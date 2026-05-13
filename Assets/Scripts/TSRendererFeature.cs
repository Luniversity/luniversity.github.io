using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class TiltShiftRendererFeature : ScriptableRendererFeature
{
    private enum OutputMode
    {
        Final,
        CoC,
        FocusBand,
        LocalFocusDepth,
        SourceHDR
    }

    private enum BokehKernel
    {
        Small,
        Medium,
        Large,
        VeryLarge
    }

    private enum PrefilterHighlightHandling
    {
        PreserveHDR,
        KarisWeighted
    }

    private static readonly string[] KernelKeywords =
    {
        "KERNEL_SMALL",
        "KERNEL_MEDIUM",
        "KERNEL_LARGE",
        "KERNEL_VERYLARGE"
    };

    [Header("Misc Settings")]
    [SerializeField] private Shader shader;
    [SerializeField] private OutputMode outputMode = OutputMode.Final;

    [Header("Focus Controls")]
    [SerializeField, Min(0.1f)] private float aperture = 16f;
    [SerializeField] private float focusDistance = 20f;
    [SerializeField, Range(-70f, 70f)] private float tiltAngleX = 0f;
    [SerializeField, Range(-70f, 70f)] private float tiltAngleY = 0f;

    [Header("Blur Fine Tuning")]
    [SerializeField] private BokehKernel bokehKernel = BokehKernel.Medium;
    [SerializeField] private string targetCameraName = "Tilt Shift Camera";
    [SerializeField, Range(0f, 1f)] private float blurStrength = 1f;
    [SerializeField, Min(0f)] private float coCRenderScale = 1f;
    [SerializeField, Range(1f, 10f)] private float maxCoCRadius = 4f;
    [SerializeField, Range(1f, 10f)] private float kernelRadius = 4f;
    [SerializeField] private PrefilterHighlightHandling prefilterHighlightHandling = PrefilterHighlightHandling.PreserveHDR;

    private Material material;
    private TiltShiftRenderPass renderPass;
    private bool warnedHdrDisabled;

    public override void Create()
    {
        CoreUtils.Destroy(material);

        if (shader == null)
        {
            material = null;
            renderPass = null;
            return;
        }

        material = CoreUtils.CreateEngineMaterial(shader);
        renderPass = new TiltShiftRenderPass(material);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderPass == null)
            return;

        Camera camera = renderingData.cameraData.camera;

        // Only apply effect to specified camera
        if (camera == null || camera.cameraType != CameraType.Game)
            return;

        if (!string.Equals(camera.name, targetCameraName, System.StringComparison.Ordinal))
            return;

        if (!renderingData.cameraData.isHdrEnabled)
        {
            if (!warnedHdrDisabled)
            {
                Debug.LogWarning("Tilt Shift HDR bokeh requires camera HDR rendering to be enabled.");
                warnedHdrDisabled = true;
            }
        }
        else
        {
            warnedHdrDisabled = false;
        }

        // send the inverse projection matrix of the target camera to the shader
        Matrix4x4 inverseProjection = camera.projectionMatrix.inverse;
        material.SetMatrix("_InverseProjection", inverseProjection);

        // the other parameters for the tilt-shift effect
        material.SetFloat("_FocalLengthMM", camera.focalLength);
        material.SetVector("_SensorSizeMM", camera.sensorSize);
        material.SetFloat("_Aperture", Mathf.Max(0.1f, aperture));
        material.SetFloat("_FocusDistance", focusDistance);
        material.SetFloat("_TiltAngleX", tiltAngleX);
        material.SetFloat("_TiltAngleY", tiltAngleY);
        material.SetFloat("_DebugMode", (float)outputMode);
        material.SetFloat("_CoCRenderScale", Mathf.Max(0f, coCRenderScale));
        material.SetFloat("_MaxCoCRadius", Mathf.Clamp(maxCoCRadius, 1f, 10f));
        material.SetFloat("_KernelRadius", Mathf.Clamp(kernelRadius, 1f, 10f));
        material.SetFloat("_BlurStrength", Mathf.Clamp01(blurStrength));
        material.SetFloat("_PrefilterHighlightHandling", (float)prefilterHighlightHandling);
        SetKernelKeyword(material, bokehKernel);

        // Tell URP this pass needs the current camera color and depth textures.
        renderPass.SetOutputMode((int)outputMode);
        renderPass.ConfigureInput(ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Depth);
        renderer.EnqueuePass(renderPass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(material);
        material = null;
        renderPass = null;
    }

    private static void SetKernelKeyword(Material material, BokehKernel kernel)
    {
        for (int i = 0; i < KernelKeywords.Length; i++)
            material.DisableKeyword(KernelKeywords[i]);

        material.EnableKeyword(KernelKeywords[(int)kernel]);
    }
}
