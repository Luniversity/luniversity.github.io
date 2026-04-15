Shader "Custom/TiltShift/DebugTint"

{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        ZWrite Off
        Cull Off

        Pass
        {
            Name "DebugTintPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag // the fragmen shader runs for each pixel on the screen

            // Important: include Core.hlsl first
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            // fragment shader function, returns a float4 color for each pixel
            // SV_target returns the final color for the pixel
            float4 Frag(Varyings input) : SV_Target
            {
                // sample_texture2D_X samples the texture at the given UV coordinates
                // blittexture is the image being processed
                // sampler linearClamp is how the texture is sampled
                // input.texcoord is the UV coordinates for the current pixel
                float4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, input.texcoord);

                // Slight red tint so we can see the pass is active
                color.rgb = saturate(color.rgb * float3(1.4, 0.6, 0.6));



                return color;
            }
            ENDHLSL
        }
    }
}