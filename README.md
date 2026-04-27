# DH2323 Project - Depth of Field & Tilt-Shift

This repository contains a Unity project for experimenting with depth of field and tilt-shift rendering effects. The project is currently in development and includes custom Universal Render Pipeline render passes and shaders for Circle of Confusion generation, bokeh blur, debug visualization, and final compositing.

## Current Status

Work in progress.

Currently included:

- Unity project setup using Universal Render Pipeline.
- Custom tilt-shift renderer feature and render pass.
- Depth of field / bokeh shader experiments.
- Demo scenes and imported environment/material assets for testing the effect.

Still to document or finalize:

- Final project goals and scope.
- Screenshots or video examples.
- Controls and recommended test scenes.
- Known limitations.
- Credits for third-party assets.
- Final report or technical explanation, if required for the course.

## Requirements

- Unity `6000.4.1f1`
- Universal Render Pipeline `17.4.0`

The project may open in other Unity 6 versions, but the version above is the one recorded in `ProjectSettings/ProjectVersion.txt`.

## Opening the Project

1. Clone the repository.
2. Open Unity Hub.
3. Add the repository folder as an existing project.
4. Open it with Unity `6000.4.1f1`.
5. Open a scene from `Assets/Scenes`.

Unity will regenerate local folders such as `Library`, `Temp`, and `Logs` when the project is opened. These folders should normally not be committed.

## Project Structure

```text
Assets/
  Scenes/                 Demo and test scenes
  Scripts/Rendering/      Custom URP renderer feature and render pass
  Shaders/                Depth of field, tilt-shift, and shader experiments
  Prefabs/                Reusable scene objects
  Material/               Project materials
Packages/
  manifest.json           Unity package dependencies
ProjectSettings/
  ProjectVersion.txt      Unity editor version
```

## Main Implementation Files

- `Assets/Scripts/Rendering/TSRendererFeature.cs`
- `Assets/Scripts/Rendering/TSRenderPass.cs`
- `Assets/Shaders/PostProcessingFX/Simple DOF.shader`
- `Assets/Shaders/PostProcessingFX/Simple DOF v2.shader`
- `Assets/Shaders/DepthOfFieldShader.shader`

## Notes for Development

This README is intentionally short while the project is still being built. As the implementation stabilizes, add:

- A short screenshot or GIF of the effect.
- A clear description of how the tilt-shift / depth of field effect works.
- Instructions for enabling the renderer feature in URP.
- Parameter descriptions for aperture, focus distance, bokeh radius, blur strength, and debug output.
- A list of third-party assets and their licenses.

## License

No license has been selected yet.

Before making the repository public or allowing reuse, add a license file and check the licenses of all third-party assets included in `Assets/`.
