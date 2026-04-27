using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class TiltShiftRenderPass : ScriptableRenderPass
{
    // declare the shader pass indixes (they are in order)
    private const string PassName = "TiltShift Pass";
    private const int CoCPassIndex = 0;
    private const int CoCDebugPassIndex = 1;
    private const int PreFilterPassIndex = 2;
    private const int BlurPassIndex = 3;
    private const int PostFilterPassIndex = 4;
    private const int CompositePassIndex = 5;

    // these are the shader property IDs used in the shader, we cache them here for efficiency
    private static readonly int BlitTextureId = Shader.PropertyToID("_BlitTexture"); // this is the source texture for a pass
    private static readonly int BlitScaleBiasId = Shader.PropertyToID("_BlitScaleBias");
    private static readonly int CoCTextureId = Shader.PropertyToID("_CoCTexture"); // our coc texture as a shader property
    private static readonly int BlurredTextureId = Shader.PropertyToID("_BlurredTexture"); // the blurred texture as a shader property
    private static readonly MaterialPropertyBlock SharedPropertyBlock = new MaterialPropertyBlock();

    private readonly Material material;
    private bool outputCoCDebug;


    // the constructor takes a material which contains the shader we use
    // it stores the material and configures when the pass runs
    public TiltShiftRenderPass(Material material)
    {
        this.material = material;
        // run this before post-processing
        renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        profilingSampler = new ProfilingSampler(PassName);
        requiresIntermediateTexture = true;
    }

    // togggle for debug view
    public void SetCoCDebugOutput(bool enabled)
    {
        outputCoCDebug = enabled;
    }
    // Main function
    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        if (material == null)
            return;

        // we only run for the game camera
        UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
        if (cameraData.cameraType != CameraType.Game)
            return;

        UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
        if (resourceData.isActiveTargetBackBuffer)
        {
            Debug.LogWarning("Skipping TiltShift render pass because the active target is the back buffer.");
            return;
        }
        // get the source camera color texture
        TextureHandle source = resourceData.activeColorTexture;
        if (!source.IsValid())
            return;

        // Step 1
        // create a coc texture
        TextureDesc cocDesc = renderGraph.GetTextureDesc(source);
        cocDesc.name = "_TiltShiftCoC";
        cocDesc.format = GraphicsFormat.R16_SFloat;
        cocDesc.clearBuffer = false;
        TextureHandle cocTexture = renderGraph.CreateTexture(cocDesc);

        // run the CoC pass to fill the coc texture
        AddFullscreenPass(
            renderGraph,
            "TiltShift CoC",
            CoCPassIndex,
            TextureHandle.nullHandle,
            TextureHandle.nullHandle,
            TextureHandle.nullHandle,
            cocTexture,
            resourceData.cameraDepthTexture);

        TextureDesc colorDesc = renderGraph.GetTextureDesc(source);
        colorDesc.clearBuffer = false;

        TextureHandle destination;


        if (outputCoCDebug) // Debug view,
        {
            colorDesc.name = "_TiltShiftCoCDebug";
            destination = renderGraph.CreateTexture(colorDesc);
            // run shader pass 1
            AddFullscreenPass(
                renderGraph,
                "TiltShift CoC Debug",
                CoCDebugPassIndex,
                TextureHandle.nullHandle,
                cocTexture,
                TextureHandle.nullHandle,
                destination,
                TextureHandle.nullHandle);
        }
        else
        {
            // Step 2
            // create a half-resolution color texture
            TextureDesc halfColorDesc = colorDesc;
            halfColorDesc.width = Mathf.Max(1, halfColorDesc.width / 2);
            halfColorDesc.height = Mathf.Max(1, halfColorDesc.height / 2);
            halfColorDesc.format = GraphicsFormat.R16G16B16A16_SFloat;

            // downsample the color and CoC to half resolution and store in halfColorTexture
            halfColorDesc.name = "_TiltShiftHalfColor";
            TextureHandle halfColorTexture = renderGraph.CreateTexture(halfColorDesc);

            // run shader pass 2 to prefilter the color and CoC
            AddFullscreenPass(
                renderGraph,
                "TiltShift PreFilter",
                PreFilterPassIndex,
                source,
                cocTexture,
                TextureHandle.nullHandle,
                halfColorTexture,
                TextureHandle.nullHandle);

            halfColorDesc.name = "_TiltShiftHalfBokeh";
            TextureHandle halfBokehTexture = renderGraph.CreateTexture(halfColorDesc);

            AddFullscreenPass(
                renderGraph,
                "TiltShift Bokeh",
                BlurPassIndex,
                halfColorTexture,
                TextureHandle.nullHandle,
                TextureHandle.nullHandle,
                halfBokehTexture,
                TextureHandle.nullHandle);

            halfColorDesc.name = "_TiltShiftHalfBokehPostFilter";
            TextureHandle halfFilteredBokehTexture = renderGraph.CreateTexture(halfColorDesc);

            AddFullscreenPass(
                renderGraph,
                "TiltShift Bokeh Post Filter",
                PostFilterPassIndex,
                halfBokehTexture,
                TextureHandle.nullHandle,
                TextureHandle.nullHandle,
                halfFilteredBokehTexture,
                TextureHandle.nullHandle);

            colorDesc.name = "_TiltShiftComposite";
            destination = renderGraph.CreateTexture(colorDesc);

            AddFullscreenPass(
                renderGraph,
                "TiltShift Composite",
                CompositePassIndex,
                source,
                cocTexture,
                halfFilteredBokehTexture,
                destination,
                TextureHandle.nullHandle);
        }

        resourceData.cameraColor = destination;
    }

    private void AddFullscreenPass(
        RenderGraph renderGraph,
        string passName,
        int shaderPassIndex,
        TextureHandle source,
        TextureHandle cocTexture,
        TextureHandle blurredTexture,
        TextureHandle destination,
        TextureHandle depthTexture)
    {
        using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass<PassData>(passName, out PassData passData, profilingSampler))
        {
            passData.material = material;
            passData.source = source;
            passData.cocTexture = cocTexture;
            passData.blurredTexture = blurredTexture;
            passData.shaderPassIndex = shaderPassIndex;

            if (passData.source.IsValid())
                builder.UseTexture(passData.source, AccessFlags.Read);

            if (passData.cocTexture.IsValid())
                builder.UseTexture(passData.cocTexture, AccessFlags.Read);

            if (passData.blurredTexture.IsValid())
                builder.UseTexture(passData.blurredTexture, AccessFlags.Read);

            if (depthTexture.IsValid())
                builder.UseTexture(depthTexture, AccessFlags.Read);

            builder.SetRenderAttachment(destination, 0, AccessFlags.Write);
            builder.SetRenderFunc(static (PassData data, RasterGraphContext context) =>
            {
                ExecuteFullscreenPass(context.cmd, data.source, data.cocTexture, data.blurredTexture, data.material, data.shaderPassIndex);
            });
        }
    }

    private static void ExecuteFullscreenPass(
        RasterCommandBuffer cmd,
        RTHandle source,
        RTHandle cocTexture,
        RTHandle blurredTexture,
        Material material,
        int shaderPassIndex)
    {
        SharedPropertyBlock.Clear();
        SharedPropertyBlock.SetVector(BlitScaleBiasId, new Vector4(1f, 1f, 0f, 0f));

        if (source != null)
            SharedPropertyBlock.SetTexture(BlitTextureId, source);

        if (cocTexture != null)
            SharedPropertyBlock.SetTexture(CoCTextureId, cocTexture);

        if (blurredTexture != null)
            SharedPropertyBlock.SetTexture(BlurredTextureId, blurredTexture);

        cmd.DrawProcedural(Matrix4x4.identity, material, shaderPassIndex, MeshTopology.Triangles, 3, 1, SharedPropertyBlock);
    }

    private class PassData
    {
        internal Material material;
        internal TextureHandle source;
        internal TextureHandle cocTexture;
        internal TextureHandle blurredTexture;
        internal int shaderPassIndex;
    }
}
