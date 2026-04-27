Shader "Custom/TiltShift/BlurOnly"

{
    Properties
    {
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
            Name "BlurOnlyPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _BlurRadius;
            float _BlurStrength;

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 texel = _BlitTexture_TexelSize.xy;

                float3 original = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float3 blurred = original;

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

                blurred /= 25.0;

                float strength = saturate(_BlurStrength);
                float3 color = lerp(original, blurred, strength);

                return float4(color, 1);
            }
            ENDHLSL
        }
    }
}
