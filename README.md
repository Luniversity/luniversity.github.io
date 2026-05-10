# Tilt-Shift Depth of Field in Unity URP

This project implements a custom depth-of-field and tilt-shift post-processing effect in Unity's Universal Render Pipeline. The work started with simple fullscreen shader experiments and gradually developed into a multi-pass bokeh pipeline driven by a camera-inspired circle of confusion calculation and a tilted focus plane.

## Final Result

The final effect can be tuned from the renderer feature inspector. The main view below shows the same scene without the custom effect, with ordinary depth of field, and with an X-axis tilted focus plane.

| No custom DOF | DOF enabled | X-axis tilt |
|---|---|---|
| ![Main view without DOF](docs/images/main%20view%20no%20DOF.png) | ![Main view with DOF](docs/images/main%20view.png) | ![Main view with X tilt](docs/images/main%20view%20xtilt.png) |

The second view was set up to show Y-axis tilt. The drums are arranged in a line, and the focus plane can be rotated so that more of them fall within the focused region.

| No Y-axis tilt | Y-axis tilt |
|---|---|
| ![Second view without Y tilt](docs/images/second%20view.png) | ![Second view with Y tilt](docs/images/second%20view%20ytilt.png) |

## Project Progress

Below are some highlights and milestones of the project, showcasing the steps and iterations of the DOF and Tilt effect before the final implementation.

## Early Experiments: Depth and CoC

The first steps was learning how to write a fullscreen post-processing shader in URP. A simple color tint helped me verify that the render pass was running correctly. After that, the shader sampled the camera depth texture and visualized linear depth.

![Depth visualization](docs/images/01-depth-visualization.png)

Once depth was available, the first circle of confusion was based on a simple depth difference:

```text
CoC = (depth - focusDistance) / focusRange
```

This was not physically accurate, but I just wanted something simple for testing. The debug view colored pixels in front of the focus plane differently from pixels behind it, with the focus region near black.

![Early CoC visualization](docs/images/02-coc-visualization.png)

## First DOF Prototype

The first working depth-of-field version blurred the image and blended between the sharp and blurred versions using the CoC value. This made the effect recognizable as depth of field, but the blur quality was still rough and the implementation was too monolithic.

| Focus on lamppost | Focus on truck |
|---|---|
| ![First DOF focused on truck](docs/images/03-first-dof-truck.png) | ![First DOF focused on lamppost](docs/images/04-first-dof-lamppost.png) |

At this stage most of the logic lived inside one shader pass. That made the effect harder to debug because intermediate values such as the CoC only existed temporarily inside the fragment shader.

## From Single Pass to Multi-Pass

The effect was then split into a small post-processing pipeline:

From:
```text
Source color + depth
```
To:
```text
CoC pass -> Prefilter -> Blur -> Postfilter -> Composite
```

The CoC pass generates the blur control texture. The prefilter pass downsamples color and CoC to half resolution. The blur pass applies the bokeh kernel. The postfilter smooths the half-resolution blur, and the composite pass blends the blurred result with the original image.

This structure made it easier to inspect and improve each part independently (and was part of the tutorial I followed). 

## From Blur to Bokeh

The blur started as a simple fixed kernel, then moved toward a disk-shaped bokeh kernel. Early versions sampled from a square or sparse pattern, which made the blur look blocky or visibly separated when the radius increased.

![Circular kernel experiment](docs/images/05-circular-kernel-offset-10.png)

The blur was later moved to half resolution. This reduced the number of pixels processed by the expensive bokeh pass, while still being acceptable because blurred regions do not need full image detail.

Several bokeh kernels were added, ranging from small to very large. Larger kernels give smoother and more circular bokeh, but they also require more texture samples.

## Foreground vs Background Blur

One issue with early bokeh blur was that foreground and background blur were treated the same. This caused background blur to bleed over foreground objects in cases where the foreground should occlude the background.

The implementation was changed to use the sign of the CoC. Foreground and background contributions are accumulated separately and then recombined. This gives more plausible behavior around depth transitions.

| Before foreground/background split | After foreground/background split |
|---|---|
| ![Background bleed before](docs/images/08-background-bleed-before.png) | ![Background bleed after](docs/images/09-background-bleed-after.png) |

You can see the change on the edge of the truck. 

## Camera-Inspired CoC

The first CoC model used an arbitrary focus range (an abstract constant really). Later, the calculation was changed to use camera-inspired parameters: focal length, aperture, focus distance, and sensor size. This made the controls closer to real camera behavior.

The early version used a simple normalized depth difference:

```text
CoC = (z - focusDistance) / focusRange
```

The current version uses a thin-lens-inspired expression before converting the result to screen-space blur units:

```text
CoC = (f² / (N * (zfLocal - f))) * ((z - zfLocal) / z)
```

Here `z` is the current pixel depth, `zfLocal` is the local focus distance, `f` is focal length, and `N` is the aperture f-number.

The graphs below compare the simple linear CoC with a more lens-inspired version at two focus distances. Both reach zero at the focus distance, but the camera-inspired curve changes more strongly at close distances and more gradually at far distances.

| Focus distance 0.5m | Focus distance 3m |
|---|---|
| ![CoC comparison graph at 0.5m](docs/images/CoC%20comparison%20graph%200.5m.png) | ![CoC comparison graph at 3m](docs/images/CoC%20comparison%203m.png) |

The implementation is still a screen-space post-process, not a full lens simulation. A render-scale factor is still needed to map optical blur into the blur radius used by the shader. However, aperture and focal length now affect the result in a more meaningful way than a simple arbitrary blur slider.

The screenshots below show the same main view with different aperture values. A smaller f-number produces a shallower depth of field, while a larger f-number keeps more of the scene sharp.

| f/2.2 | f/5.6 | f/11 | f/22 |
|---|---|---|---|
| ![Main view f2.2](docs/images/main%20view%20f2.2.png) | ![Main view f5.6](docs/images/main%20view%20f5.6.png) | ![Main view f11](docs/images/main%20view%20f11.png) | ![Main view f22](docs/images/main%20view%20f22.png) |

Changing the camera focal length also changes the result. This keeps the effect closer to camera behavior than the first linear CoC prototype.

| 24mm | 35mm | 50mm | 75mm |
|---|---|---|---|
| ![Main view 24mm](docs/images/main%20view%2024mm.png) | ![Main view 35mm](docs/images/main%20view%2035mm.png) | ![Main view 50mm](docs/images/main%20view%2050mm.png) | ![Main view 75mm](docs/images/main%20view%2075mm.png) |

## Tilted Focus Plane

The main tilt step was replacing the single global focus distance with a tilted focus plane. Instead of asking whether a pixel is close to one fixed depth, the shader reconstructs the pixel's view-space ray and intersects it with the focus plane. The intersection depth becomes that pixel's local focus distance.

The diagrams below show the idea in 2D. With no tilt, the focus plane behaves like a normal depth-of-field plane. With tilt, different rays intersect the plane at different depths.

| Untilted focus plane | Tilted focus plane |
|---|---|
| ![Ray-plane intersection without tilt](docs/images/11-ray-plane-untilted.png) | ![Ray-plane intersection with tilt](docs/images/12-ray-plane-tilted.png) |

The final implementation defines the focus plane in camera view space. The plane is anchored at the selected focus distance and its normal is rotated around the camera-local X and Y axes.

This camera-relative approach is simple and works well for the project, but it also means the tilt is relative to the camera orientation rather than directly relative to the ground.

## Debug Views

Several debug views were added because the final image combines many different steps. These views make it easier to tell whether a problem comes from the focus plane, the CoC calculation, or the blur/composite stage.

### Focus Band

The Focus Band view compares the scene depth with the local focus distance. Bright areas show where the visible geometry is close to the tilted focus plane. In the examples below, only the X-axis tilt changes while the camera view stays the same.

| Tilt X = -65 degrees | Tilt X = 0 degrees | Tilt X = +65 degrees |
|---|---|---|
| ![Focus band with negative X tilt](docs/images/main%20view%20-xtilt%20focus%20band%20debug.png) | ![Focus band with no X tilt](docs/images/main%20view%20focus%20band%20debug.png) | ![Focus band with positive X tilt](docs/images/main%20view%20xtilt%20focus%20band%20debug.png) |


### Local Focus Depth

The Local Focus Depth view shows the focus field itself. Blue means the local focus depth is closer than the focus anchor, white is near the anchor distance, and pink means the local focus depth is farther away.

![Local focus depth debug](docs/images/15-local-focus-depth.png)

This became more useful once tilt along both axes was added, because it shows the orientation of the focus plane without depending on the visible scene geometry.

### CoC

The CoC view shows the signed blur amount that is passed to the blur stage. It is useful for checking whether aperture, focal length, focus distance, and tilt combine into the expected blur distribution.

| Main view CoC | X-tilt Focus Band |
|---|---|
| ![Main view X tilt CoC debug](docs/images/main%20view%20xtilt%20CoC%20debug.png) | ![Main view X tilt focus band debug](docs/images/main%20view%20xtilt%20focus%20band%20debug.png) |

The same debug view is useful for the second setup when testing Y-axis tilt.

| No Y-axis tilt CoC | Y-axis tilt CoC |
|---|---|
| ![Second view CoC debug](docs/images/second%20view%20CoC%20debug.png) | ![Second view Y tilt CoC debug](docs/images/second%20view%20ytilt%20CoC%20debug.png) |

## Tilt Results

The first tilt version supported rotation around the camera X-axis. In the example below, the camera is already angled downward, so positive tilt can bring the focus plane closer to parallel with the ground.

| Negative X tilt | No focus-plane tilt | Positive X tilt |
|---|---|---|
| ![Main view with negative X tilt](docs/images/main%20view%20-xtilt.png) | ![Main view with DOF](docs/images/main%20view.png) | ![Main view with positive X tilt](docs/images/main%20view%20xtilt.png) |

The debug views show how the signed CoC and focus band change when the focus plane is tilted in the opposite direction.

| Negative X tilt CoC | Negative X tilt Focus Band |
|---|---|
| ![Main view negative X tilt CoC debug](docs/images/main%20view%20-xtilt%20CoC%20debug.png) | ![Main view negative X tilt focus band debug](docs/images/main%20view%20-xtilt%20focus%20band%20debug.png) |

Later, Y-axis tilt was added by rotating the focus-plane normal around both camera-local axes. This allows the sharp region to be aligned across the image horizontally as well as vertically.

| No Y tilt | Y-axis tilt |
|---|---|
| ![Second view without Y tilt](docs/images/second%20view.png) | ![Second view with Y tilt](docs/images/second%20view%20ytilt.png) |

The opposite Y-tilt direction was also tested to check that the plane can be rotated both ways around the second axis.

| Negative Y tilt | Negative Y tilt CoC |
|---|---|
| ![Second view with negative Y tilt](docs/images/second%20view%20-ytilt%20.png) | ![Second view negative Y tilt CoC debug](docs/images/second%20view%20-ytilt%20CoC%20debug.png) |

The debug view confirms that the focus plane has rotated across the screen.

![Y tilt debug view](docs/images/20-y-tilt-debug.png)

## Current Controls

The effect is controlled from a custom renderer feature. The inspector is grouped into focus controls, blur tuning, and general settings.

Focus controls:

- Aperture
- Focus Distance
- Tilt Angle X
- Tilt Angle Y

Blur tuning:

- Bokeh Kernel
- Blur Strength
- CoC Render Scale
- Max CoC Radius
- Kernel Radius

General settings:

- Shader
- Render Pass Event
- Output Mode
- Target Camera Name

## Important Files

- [`Assets/Shaders/PostProcessingFX/Tilt Shift Shader.shader`](Assets/Shaders/PostProcessingFX/Tilt%20Shift%20Shader.shader)
- [`Assets/Shaders/PostProcessingFX/Depth of field v3.shader`](Assets/Shaders/PostProcessingFX/Depth%20of%20field%20v3.shader)
- [`Assets/Shaders/PostProcessingFX/DiskKernels.hlsl`](Assets/Shaders/PostProcessingFX/DiskKernels.hlsl)
- [`Assets/Scripts/TSRendererFeature.cs`](Assets/Scripts/TSRendererFeature.cs)
- [`Assets/Scripts/DOFV3RendererFeature.cs`](Assets/Scripts/DOFV3RendererFeature.cs)
- [`Assets/Scripts/TSRenderPass.cs`](Assets/Scripts/TSRenderPass.cs)

## Requirements

- Unity `6000.4.1f1`
- Universal Render Pipeline `17.4.0`

## Opening the Project

1. Clone the repository.
2. Open Unity Hub.
3. Add the repository folder as an existing project.
4. Open it with Unity `6000.4.1f1`.
5. Open a scene from `Assets/Scenes`.

## References

- [Catlike Coding: Depth of Field](https://catlikecoding.com/unity/tutorials/advanced-rendering/depth-of-field/)
- [Unity Post Processing: DiskKernels.hlsl](https://github.com/Unity-Technologies/PostProcessing/blob/v2/PostProcessing/Shaders/Builtins/DiskKernels.hlsl)
- [Wikipedia: Circle of confusion](https://en.wikipedia.org/wiki/Circle_of_confusion)
- [Wikipedia: Tilt-shift photography](https://en.wikipedia.org/wiki/Tilt%E2%80%93shift_photography)
- [Wikipedia: Scheimpflug principle](https://en.wikipedia.org/wiki/Scheimpflug_principle)
