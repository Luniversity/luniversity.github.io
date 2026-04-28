using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class DOFV3RendererFeature : ScriptableRendererFeature
{
    private enum OutputMode
    {
        Final,
        CoCDebug
    }

    private enum BokehKernel
    {
        Small,
        Medium,
        Large,
        VeryLarge
    }

    private static readonly string[] KernelKeywords =
    {
        "KERNEL_SMALL",
        "KERNEL_MEDIUM",
        "KERNEL_LARGE",
        "KERNEL_VERYLARGE"
    };

    [SerializeField] private Shader shader;
    [SerializeField] private RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    [SerializeField] private OutputMode outputMode = OutputMode.Final;
    [SerializeField] private BokehKernel bokehKernel = BokehKernel.Medium;
    [SerializeField] private string targetCameraName = "Tilt Shift Camera";
    [SerializeField, Min(0.1f)] private float aperture = 16f;
    [SerializeField] private float focusDistance = 20f;
    [SerializeField, Min(0f)] private float coCRenderScale = 1f;
    [SerializeField, Range(1f, 10f)] private float bokehRadius = 4f;
    [SerializeField, Range(0f, 1f)] private float blurStrength = 1f;

    private Material material;
    private TiltShiftRenderPass renderPass;

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
        renderPass = new TiltShiftRenderPass(material)
        {
            renderPassEvent = renderPassEvent
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderPass == null)
            return;

        Camera camera = renderingData.cameraData.camera;
        if (camera == null || camera.cameraType != CameraType.Game)
            return;

        if (!string.Equals(camera.name, targetCameraName, System.StringComparison.Ordinal))
            return;

        material.SetFloat("_FocalLengthMM", camera.focalLength);
        material.SetVector("_SensorSizeMM", camera.sensorSize);
        material.SetFloat("_Aperture", Mathf.Max(0.1f, aperture));
        material.SetFloat("_FocusDistance", focusDistance);
        material.SetFloat("_CoCRenderScale", Mathf.Max(0f, coCRenderScale));
        material.SetFloat("_BokehRadius", Mathf.Clamp(bokehRadius, 1f, 10f));
        material.SetFloat("_BlurStrength", Mathf.Clamp01(blurStrength));
        SetKernelKeyword(material, bokehKernel);

        renderPass.SetOutputMode(outputMode == OutputMode.CoCDebug ? 1 : 0);
        renderPass.renderPassEvent = renderPassEvent;
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
