using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class TiltShiftRendererFeature : ScriptableRendererFeature
{
    [SerializeField] private Shader shader;
    [SerializeField] private RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;

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

        if (renderingData.cameraData.camera.cameraType != CameraType.Game)
            return;

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
}
