Shader "Custom/TiltShift/TiltShiftShader"
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

        // Receive variables from the RendererFeature
        float _FocalLengthMM;
        float2 _SensorSizeMM;
        float _Aperture;
        float _FocusDistance;
        float _CoCRenderScale;
        float _MaxCoCRadius;
        float _KernelRadius;
        float _BlurStrength;
        float _TiltAngleX;
        float _TiltAngleY;
        float _DebugMode;
        float4x4 _InverseProjection;

        // gives access to the coc texture and blurred texture from the previous passes
        TEXTURE2D_X(_CoCTexture);
        TEXTURE2D_X(_BlurredTexture);

        // Disk sample patterns used by the bokeh blur pass
        #include "Assets/Shaders/PostProcessingFX/DiskKernels.hlsl"

        ENDHLSL

        Pass { Name "CoC" 
            // CoC pass calculates the circle of confusion

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragCoC

            float4 FragCoC(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                int debugMode = (int)round(_DebugMode);

                // Read the camera depth buffer and convert to linear eye depth
                float rawDepth = SampleSceneDepth(uv);
                float z = max(LinearEyeDepth(rawDepth, _ZBufferParams), 0.0001);

                // Convert physical camera values from mm to m
                float f = _FocalLengthMM * 0.001;
                float N = max(_Aperture, 0.1);
                float sensorHeight = max(_SensorSizeMM.y * 0.001, 0.0001);
                float pixelsPerSensorMeter = _ScreenParams.y / sensorHeight;

                // Reconstruct the pixel position in view space
                float2 ndcXY = uv * 2.0 - 1.0; // convert from [0,1] to [-1,1]
                float4 projected = float4(ndcXY, rawDepth, 1.0);
                float4 view = mul(_InverseProjection, projected);
                float3 p = view.xyz / view.w; // perspective divide to get view space position
                
                // Define the focal plane before tilting
                float3 p0 = float3(0.0, 0.0, -_FocusDistance); // Origin of the focal plane

                // Compute the tilted focal plane normal
                float tiltX = radians(_TiltAngleX); // compute in radians
                float tiltY = radians(_TiltAngleY);

                float3x3 rx = float3x3( // build rx and ry rotation matrices
                    1, 0, 0,
                    0, cos(tiltX), sin(tiltX),
                    0, -sin(tiltX), cos(tiltX)
                );
                float3x3 ry = float3x3(
                    cos(tiltY), 0, sin(tiltY),
                    0, 1, 0,
                    -sin(tiltY), 0, cos(tiltY)
                );
                float3 n0 = float3(0, 0, 1); // normal of the focal plane before tilt
                float3 n = normalize(mul(ry, mul(rx, n0))); // normal of the focal plane after applying tilt rotations
                
                // Plane eq: dot(n, x) + d = 0
                float d = -dot(n, p0); 
                
                // Find the intersection of the view ray with the focal plane to get the local focal distance
                float denom = dot(n, p);
                float zfLocal;

                if (abs(denom) < 1e-5) {
                    // Avoid division by 0
                    zfLocal = _FocusDistance;
                }
                else
                {
                    float lambda = -d / denom;
                    float3 pf = lambda * p;
                    zfLocal = max(-pf.z, f + 0.0001);
                }

                // Compute thin lens approximation for blur
                // then convert from from metric units to pixel units
                float cocSensor = (f * f) / (N * (zfLocal - f)) * ((z - zfLocal) / z);
                float cocPixels = cocSensor * pixelsPerSensorMeter * 0.5 * _CoCRenderScale;
                float coc = clamp(cocPixels, -_MaxCoCRadius, _MaxCoCRadius);

                // Debug visualization modes
                if (debugMode == 1){
                    float amount = saturate(abs(coc) / _MaxCoCRadius);
                    if (coc < 0.0)
                    {
                        return float4(amount, 0.0, 0.0, 1.0);
                    }
                    return float4(amount, amount, amount, 1.0);
                }

                if (debugMode == 2){
                    float diff = z - zfLocal;
                    float amount = saturate(1.0 - abs(diff) / 2.0);
                    float3 nearColor = float3(0.2, 0.5, 1.0);
                    float3 farColor = float3(1.0, 0.6, 0.2);
                    float3 focusColor = float3(1.0, 1.0, 1.0);
                    float3 sideColor = diff < 0.0 ? nearColor : farColor;
                    float3 color = lerp(sideColor, focusColor, amount);
                    return float4(color, 1.0);
                }

                if (debugMode == 3){
                    float delta = zfLocal - _FocusDistance;
                    float amount = saturate(abs(delta) / max(_FocusDistance * 0.5, 0.0001));
                    float3 nearColor = float3(0.2, 0.5, 1.0);
                    float3 farColor = float3(1.0, 0.45, 0.8);
                    float3 neutralColor = float3(1.0, 1.0, 1.0);
                    float3 sideColor = delta < 0.0 ? nearColor : farColor;
                    float3 color = lerp(neutralColor, sideColor, amount);
                    return float4(color, 1.0);
                }

                return float4(coc, 0, 0, 1);
            }

            ENDHLSL}
        Pass { Name "Prefilter" 
            // Prefilter pass downsamples the image to half resolution

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragPrefilter

            float WeighColor(float3 color)
            {
                // reduce the influence of very bright pixels
                return 1.0 / (1.0 + max(max(color.r, color.g), color.b));
            }

            float4 FragPrefilter(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // Downsample the color to half resolution and store in halfColorTexture
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
            // Blur pass applies the disk kernel bokeh at half resolution

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragBlur
            #pragma multi_compile_local _ KERNEL_SMALL KERNEL_MEDIUM KERNEL_LARGE KERNEL_VERYLARGE

            // Converts a CoC value into a sample weight.
            float Weigh(float coc, float radius)
            {
                float softness = 2.0;
                return saturate((coc - radius + softness) / softness);
            }

            float4 FragBlur(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float coc = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).a;

                // Seperate foreground and background objects 
                float3 bgColor = 0.0;
                float3 fgColor = 0.0;
                float bgWeight = 0.0;
                float fgWeight = 0.0;

                // sample nearby pixels in a disk pattern
                for (int k = 0; k < kSampleCount; k++)
                {
                    // compute the sample offset and radius in pixels
                    float2 offset = kDiskKernel[k] * _KernelRadius;
                    float radius = length(offset);

                    offset *= _BlitTexture_TexelSize.xy;

                    float4 sample = SAMPLE_TEXTURE2D_X(
                        _BlitTexture,
                        sampler_LinearClamp,
                        uv + offset
                    );
                    
                    // Positive CoC = background blur
                    float bgw = Weigh(max(0.0, min(sample.a, coc)), radius);
                    bgColor += sample.rgb * bgw;
                    bgWeight += bgw;
                    
                    // Negative CoC = foreground blur
                    float fgw = Weigh(-sample.a, radius);
                    fgColor += sample.rgb * fgw;
                    fgWeight += fgw;
                }

                // Normalize accumulated colors so the result is an average of all
                // contributing samples rather than becoming brighter with more samples.
                bgColor *= 1.0 / max(bgWeight, 0.0001);
                fgColor *= 1.0 / max(fgWeight, 0.0001);

                float bgfg = min(1.0, fgWeight * 3.14159265359 / kSampleCount);
                float3 color = lerp(bgColor, fgColor, bgfg);

                return float4(color, bgfg);
            }

            ENDHLSL}
        Pass { Name "PostFilter"
            // PostFilter pass applies a simple blur to the blurred image to reduce blockiness from the disk sampling pattern
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragPostFilter

            float4 FragPostFilter(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                // simple 4-tap blur to reduce blockiness from the disk sampling pattern
                float4 offset = _BlitTexture_TexelSize.xyxy * float4(-0.5, 0.5, 0.5, -0.5);
                // average the 4 samples
                // rgb = color, a = foreground blend factor
                float4 color =
                    SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.xy) +
                    SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.zy) +
                    SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.xw) +
                    SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + offset.zw);

                return color * 0.25;
            }

            ENDHLSL}
        Pass { Name "Composite" 
            // Composite pass combines the sharp original image with the blurred bokeh image

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment FragComposite

            float4 FragComposite(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // sample the coc radius
                float coc = SAMPLE_TEXTURE2D_X(_CoCTexture, sampler_LinearClamp, uv).r;

                // Convert CoC into a smooth 0-1 blur amount
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
