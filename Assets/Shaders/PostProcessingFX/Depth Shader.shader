Shader "Custom/TiltShift/LinearDepth"

{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        ZWrite Off
        Cull Off

        Pass
        {
            Name "DebugDepthPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag // the fragmen shader runs for each pixel on the screen

            // Important: include Core.hlsl first
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            // fragment shader function, returns a float4 color for each pixel
            // SV_target returns the final color for the pixel
            float4 Frag(Varyings input) : SV_Target
            {
                float rawDepth = SampleSceneDepth(input.texcoord);
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                // Divide by a visible range so it fits into 0-1 grayscale.
                // Adjust 150.0 depending on your scene scale.
                float depth01 = saturate(linearDepth / 150.0);

                return float4(depth01, depth01, depth01, 1);
            }

            ENDHLSL
        }
    }
}
