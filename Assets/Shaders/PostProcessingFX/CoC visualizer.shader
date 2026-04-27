Shader "Custom/TiltShift/DebugDepth"

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

            float _FocusDistance;
            float _FocusRange;

            // fragment shader function, returns a float4 color for each pixel
            // SV_target returns the final color for the pixel
            float4 Frag(Varyings input) : SV_Target
            {
                float rawDepth = SampleSceneDepth(input.texcoord);
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                // calculate cirle of confusion
                float CoC = (linearDepth - _FocusDistance) / _FocusRange;
                float blurAmount = saturate(abs(CoC));

                // color foreground blue and backgorund orange
                // the focus plane is bcomes black
                float3 nearColor = float3(0.0, 0.25, 1.0) * blurAmount;
                float3 farColor = float3(1.0, 0.15, 0.0) * blurAmount;
                float3 cocColor = CoC < 0.0 ? nearColor : farColor;

                return float4(cocColor, 1);
            }

            ENDHLSL
        }
    }
}
