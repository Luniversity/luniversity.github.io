Shader "Custom/TiltShift/SimpleDOFv2"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        ZWrite Off
        ZTest Always
        Cull Off

        HLSLINCLUDE
        
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        float _FocalLengthMM;
        float2 _SensorSizeMM;
        float _Aperture;
        float _FocusDistance;
        float _CoCRenderScale;
        float _BokehRadius;
        float _BlurStrength;

        // gives access to the coc texture and blurred texture from the previous passes
        TEXTURE2D_X(_CoCTexture);
        TEXTURE2D_X(_BlurredTexture);

        #include "Assets/Shaders/PostProcessingFX/DiskKernels.hlsl"

        ENDHLSL

        Pass { Name "CoC" 
            // this pass calculates the circle of confusion and stores it in the red channel of the output


            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragCoC

            float4 FragCoC(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                float rawDepth = SampleSceneDepth(uv);
                float z = max(LinearEyeDepth(rawDepth, _ZBufferParams), 0.0001);
                float f = _FocalLengthMM * 0.001;
                float N = max(_Aperture, 0.1);
                float zf = max(_FocusDistance, f + 0.0001);
                float sensorHeight = max(_SensorSizeMM.y * 0.001, 0.0001);
                float pixelsPerSensorMeter = _ScreenParams.y / sensorHeight;

                float cocSensor = (f * f) / (N * (zf - f)) * ((z - zf) / z);
                float cocPixels = cocSensor * pixelsPerSensorMeter * 0.5 * _CoCRenderScale;
                float coc = clamp(cocPixels, -_BokehRadius, _BokehRadius);

                return float4(coc, 0, 0, 1);
            }

            ENDHLSL}
        Pass { Name "CoCDebug"
            // basically same thing as CoC visualizer shader
            // but we get the input from the coc pass above
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragCoCDebug

            float4 FragCoCDebug(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                float coc = SAMPLE_TEXTURE2D_X(_CoCTexture, sampler_LinearClamp, uv).r;

                float amount = saturate(abs(coc) / _BokehRadius);

                if (coc < 0.0)
                {

                    return float4(amount, 0.0, 0.0, 1.0);
                }
                return float4(amount, amount, amount, 1.0);
            }

            ENDHLSL
         }
        Pass { Name "Prefilter" 
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragPrefilter

            float WeighColor(float3 color)
            {
                return 1.0 / (1.0 + max(max(color.r, color.g), color.b));
            }

            float4 FragPrefilter(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // downsample the color to half resolution and store in halfColorTexture
                float4 offset = _BlitTexture_TexelSize.xyxy * float4(-0.5, 0.5, 0.5, -0.5);

                float3 color0 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.xy).rgb;
                float3 color1 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.zy).rgb;
                float3 color2 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.xw).rgb;
                float3 color3 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.zw).rgb;

                float weight0 = WeighColor(color0);
                float weight1 = WeighColor(color1);
                float weight2 = WeighColor(color2);
                float weight3 = WeighColor(color3);

                float3 color = color0 * weight0 + color1 * weight1 + color2 * weight2 + color3 * weight3;
                color /= max(weight0 + weight1 + weight2 + weight3, 0.00001);

                float coc0 = SAMPLE_TEXTURE2D_X(_CoCTexture, sampler_LinearClamp, uv + offset.xy).r;
                float coc1 = SAMPLE_TEXTURE2D_X(_CoCTexture, sampler_LinearClamp, uv + offset.zy).r;
                float coc2 = SAMPLE_TEXTURE2D_X(_CoCTexture, sampler_LinearClamp, uv + offset.xw).r;
                float coc3 = SAMPLE_TEXTURE2D_X(_CoCTexture, sampler_LinearClamp, uv + offset.zw).r;

                // we only care about the most blurred sample
                float cocMin = min(min(min(coc0, coc1), coc2), coc3);
                float cocMax = max(max(max(coc0, coc1), coc2), coc3);
                float coc = cocMax >= -cocMin ? cocMax : cocMin;

                return float4(color, coc);
            }

            ENDHLSL
            }
        Pass { Name "Blur"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragBlur
            #pragma multi_compile_local _ KERNEL_SMALL KERNEL_MEDIUM KERNEL_LARGE KERNEL_VERYLARGE

            float Weigh(float coc, float radius)
            {
                float softness = 2.0;
                return saturate((coc - radius + softness) / softness);
            }

            float4 FragBlur(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float coc = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).a;

                float3 bgColor = 0.0;
                float3 fgColor = 0.0;
                float bgWeight = 0.0;
                float fgWeight = 0.0;

                for (int k = 0; k < kSampleCount; k++)
                {
                    float2 offset = kDiskKernel[k] * _BokehRadius;
                    float radius = length(offset);

                    offset *= _BlitTexture_TexelSize.xy;

                    float4 sample = SAMPLE_TEXTURE2D_X(
                        _BlitTexture,
                        sampler_LinearClamp,
                        uv + offset
                    );

                    float bgw = Weigh(max(0.0, min(sample.a, coc)), radius);
                    bgColor += sample.rgb * bgw;
                    bgWeight += bgw;

                    float fgw = Weigh(-sample.a, radius);
                    fgColor += sample.rgb * fgw;
                    fgWeight += fgw;
                }

                bgColor *= 1.0 / max(bgWeight, 0.0001);
                fgColor *= 1.0 / max(fgWeight, 0.0001);

                float bgfg = min(1.0, fgWeight * 3.14159265359 / kSampleCount);
                float3 color = lerp(bgColor, fgColor, bgfg);

                return float4(color, bgfg);
            }

            ENDHLSL}
        Pass { Name "PostFilter"
            // simple box blur to smooth out the downsampled disk kernel
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragPostFilter

            float4 FragPostFilter(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                float4 offset = _BlitTexture_TexelSize.xyxy * float4(-0.5, 0.5, 0.5, -0.5);

                float4 color =
                    SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.xy) +
                    SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.zy) +
                    SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.xw) +
                    SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.zw);

                return color * 0.25;
            }

            ENDHLSL}
        Pass { Name "Composite" 
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment FragComposite

            float4 FragComposite(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // sample the coc radius
                float coc = SAMPLE_TEXTURE2D_X(_CoCTexture, sampler_LinearClamp, uv).r;
                // Keep focused fragments sharp, then blend into the half-resolution DoF texture.
                float blurAmount = smoothstep(0.1, 1.0, abs(coc));

                // sample original and blurred color, then lerp between them
                float3 original = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float4 blurred = SAMPLE_TEXTURE2D_X(_BlurredTexture, sampler_LinearClamp, uv);
                float foregroundBlend = blurAmount + blurred.a - blurAmount * blurred.a;
                float3 color = lerp(original, blurred.rgb, foregroundBlend * _BlurStrength);
                
                return float4(color, 1);
            }

            ENDHLSL}
    }
}
