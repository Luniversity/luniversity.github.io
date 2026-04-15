using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class TiltShiftRenderPass : ScriptableRenderPass
{
    private const string PassName = "TiltShift Pass";
    private static readonly int BlitTextureId = Shader.PropertyToID("_BlitTexture");
    private static readonly int BlitScaleBiasId = Shader.PropertyToID("_BlitScaleBias");
    private static readonly MaterialPropertyBlock SharedPropertyBlock = new MaterialPropertyBlock();

    private readonly Material material;

    public TiltShiftRenderPass(Material material)
    {
        this.material = material;
        renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        profilingSampler = new ProfilingSampler(PassName);
        requiresIntermediateTexture = true;
    }

    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        if (material == null)
            return;

        UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
        if (cameraData.cameraType != CameraType.Game)
            return;

        UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
        if (resourceData.isActiveTargetBackBuffer)
        {
            Debug.LogWarning("Skipping TiltShift render pass because the active target is the back buffer.");
            return;
        }

        TextureHandle source = resourceData.activeColorTexture;
        if (!source.IsValid())
            return;

        TextureDesc destinationDesc = renderGraph.GetTextureDesc(source);
        destinationDesc.name = "_TiltShiftColor";
        destinationDesc.clearBuffer = false;

        TextureHandle destination = renderGraph.CreateTexture(destinationDesc);
        AddTiltShiftPass(renderGraph, resourceData, source, destination);

        resourceData.cameraColor = destination;
    }

    private void AddTiltShiftPass(RenderGraph renderGraph, UniversalResourceData resourceData, TextureHandle source, TextureHandle destination)
    {
        using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass<PassData>(PassName, out PassData passData, profilingSampler))
        {
            passData.material = material;
            passData.source = source;

            builder.UseTexture(passData.source, AccessFlags.Read);

            if ((input & ScriptableRenderPassInput.Color) != ScriptableRenderPassInput.None)
            {
                TextureHandle opaqueTexture = resourceData.cameraOpaqueTexture;
                if (opaqueTexture.IsValid())
                    builder.UseTexture(opaqueTexture, AccessFlags.Read);
            }

            if ((input & ScriptableRenderPassInput.Depth) != ScriptableRenderPassInput.None)
            {
                TextureHandle depthTexture = resourceData.cameraDepthTexture;
                if (depthTexture.IsValid())
                    builder.UseTexture(depthTexture, AccessFlags.Read);
            }

            builder.SetRenderAttachment(destination, 0, AccessFlags.Write);
            builder.SetRenderFunc(static (PassData data, RasterGraphContext context) =>
            {
                ExecutePass(context.cmd, data.source, data.material);
            });
        }
    }

    private static void ExecutePass(RasterCommandBuffer cmd, RTHandle source, Material material)
    {
        SharedPropertyBlock.Clear();
        SharedPropertyBlock.SetTexture(BlitTextureId, source);
        SharedPropertyBlock.SetVector(BlitScaleBiasId, new Vector4(1f, 1f, 0f, 0f));

        cmd.DrawProcedural(Matrix4x4.identity, material, 0, MeshTopology.Triangles, 3, 1, SharedPropertyBlock);
    }

    private class PassData
    {
        internal Material material;
        internal TextureHandle source;
    }
}
