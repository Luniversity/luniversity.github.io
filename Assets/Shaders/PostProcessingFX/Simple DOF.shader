Shader "Custom/TiltShift/SimpleDOF"

{
    Properties
    {
        _FocusDistance("Focus Distance", Float) = 20
        _FocusRange("Focus Range", Float) = 10
        _BlurRadius("Blur Radius", Float) = 4
        _BlurStrength("Blur Strength", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        ZWrite Off
        ZTest Always
        Cull Off

        Pass
        {
            Name "SimpleDOFPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            float _FocusDistance;
            float _FocusRange;
            float _BlurRadius;
            float _BlurStrength;

            // function to sample the blurred color
            float3 SampleBlurredColor(float2 uv)
            {
                float2 texel = _BlitTexture_TexelSize.xy;
                float3 blurred = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;

                // very simple blur
                [unroll]
                for (int ring = 1; ring <= 3; ring++)
                {
                    float2 offset = texel * _BlurRadius * ring;

                    blurred += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset * float2(-1, -1)).rgb;
                    blurred += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset * float2( 0, -1)).rgb;
                    blurred += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset * float2( 1, -1)).rgb;

                    blurred += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset * float2(-1,  0)).rgb;
                    blurred += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset * float2( 1,  0)).rgb;

                    blurred += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset * float2(-1,  1)).rgb;
                    blurred += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset * float2( 0,  1)).rgb;
                    blurred += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset * float2( 1,  1)).rgb;
                }

                return blurred / 25.0;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                // sample depth
                float2 uv = input.texcoord;                
                float rawDepth = SampleSceneDepth(uv);
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                // calculate blur amount based on CoC
                float coc = (linearDepth - _FocusDistance) / _FocusRange;
                float blurAmount = saturate(abs(coc) * _BlurStrength);

                // sample original and blurred color, then lerp between them
                float3 original = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float3 blurred = SampleBlurredColor(uv);
                float3 color = lerp(original, blurred, blurAmount);

                return float4(color, 1);
            }

            ENDHLSL
        }
    }
}
