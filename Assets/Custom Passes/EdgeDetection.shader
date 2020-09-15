Shader "FullScreen/EdgeDetection"
{
    HLSLINCLUDE

    #pragma vertex Vert

    #pragma target 4.5
    #pragma only_renderers d3d11 ps4 xboxone vulkan metal switch

    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/RenderPass/CustomPass/CustomPassCommon.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/NormalBuffer.hlsl"

    TEXTURE2D_X(_EdgeDetectionBuffer);
    float _EdgeDetectColorThreshold;
    float _EdgeDetectNormalThreshold;
    float _EdgeDetectDepthThreshold;
    float4 _EdgeColor;
    float _EdgeRadius;
    float _BypassMeshDepth;

    float SampleClampedDepth(float2 uv) { return SampleCameraDepth(clamp(uv, _ScreenSize.zw, 1 - _ScreenSize.zw)).r; }

    float EdgeDetect(float2 uv, float depthThreshold, float normalThreshold, float colorThreshold)
    {
        float halfScaleFloor = floor(_EdgeRadius * 0.5);
        float halfScaleCeil = ceil(_EdgeRadius * 0.5);
    
        // Compute uv position to fetch depth informations
        float2 bottomLeftUV = uv - float2(_ScreenSize.zw.x, _ScreenSize.zw.y) * halfScaleFloor;
        float2 topRightUV = uv + float2(_ScreenSize.zw.x, _ScreenSize.zw.y) * halfScaleCeil;
        float2 bottomRightUV = uv + float2(_ScreenSize.zw.x * halfScaleCeil, -_ScreenSize.zw.y * halfScaleFloor);
        float2 topLeftUV = uv + float2(-_ScreenSize.zw.x * halfScaleFloor, _ScreenSize.zw.y * halfScaleCeil);
    
        // Depth from camera buffer
        float depth0 = SampleClampedDepth(bottomLeftUV);
        float depth1 = SampleClampedDepth(topRightUV);
        float depth2 = SampleClampedDepth(bottomRightUV);
        float depth3 = SampleClampedDepth(topLeftUV);
    
        float depthDerivative0 = depth1 - depth0;
        float depthDerivative1 = depth3 - depth2;
    
        float edgeDepth = sqrt(pow(depthDerivative0, 2) + pow(depthDerivative1, 2)) * 100;

        float newDepthThreshold = depthThreshold * depth0;
        edgeDepth = edgeDepth > newDepthThreshold ? 1 : 0;
    
        // Normals extracted from the camera normal buffer
        NormalData normalData0, normalData1, normalData2, normalData3;
        DecodeFromNormalBuffer(_ScreenSize.xy * bottomLeftUV, normalData0);
        DecodeFromNormalBuffer(_ScreenSize.xy * topRightUV, normalData1);
        DecodeFromNormalBuffer(_ScreenSize.xy * bottomRightUV, normalData2);
        DecodeFromNormalBuffer(_ScreenSize.xy * topLeftUV, normalData3);
    
        float3 normalFiniteDifference0 = normalData1.normalWS - normalData0.normalWS;
        float3 normalFiniteDifference1 = normalData3.normalWS - normalData2.normalWS;
    
        float edgeNormal = sqrt(dot(normalFiniteDifference0, normalFiniteDifference0) + dot(normalFiniteDifference1, normalFiniteDifference1));
        edgeNormal = edgeNormal > normalThreshold ? 1 : 0;

        // Color and Alpha
        float4 color0 = SAMPLE_TEXTURE2D_X_LOD(_ColorPyramidTexture, s_trilinear_clamp_sampler, bottomLeftUV, 0);
        float4 color1 = SAMPLE_TEXTURE2D_X_LOD(_ColorPyramidTexture, s_trilinear_clamp_sampler, topRightUV, 0);
        float4 color2 = SAMPLE_TEXTURE2D_X_LOD(_ColorPyramidTexture, s_trilinear_clamp_sampler, bottomRightUV, 0);
        float4 color3 = SAMPLE_TEXTURE2D_X_LOD(_ColorPyramidTexture, s_trilinear_clamp_sampler, topLeftUV, 0);

        float4 colorFiniteDifference0 = color1 - color0;
        float4 colorFiniteDifference1 = color3 - color2;

        float edgeAlpha = sqrt(dot(colorFiniteDifference0.a, colorFiniteDifference0.a) + dot(colorFiniteDifference1.a, colorFiniteDifference1.a));

        float edgeColor = sqrt(dot(colorFiniteDifference0.xyz, colorFiniteDifference0.xyz) + dot(colorFiniteDifference1.xyz, colorFiniteDifference1.xyz));
        edgeColor = edgeColor > colorThreshold ? 1 : 0;

        // Combined
        return clamp(edgeDepth + edgeNormal + edgeColor + edgeAlpha, 0, 1);

    }

    float4 Compositing(Varyings varyings) : SV_Target
    {
        float depth = LoadCameraDepth(varyings.positionCS.xy);
        PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);

        // original
        float4 color = float4(CustomPassSampleCameraColor(posInput.positionNDC.xy, 0), 1);

        // Do some normal, depth and color based edge detection on the camera buffers.
        float4 edgeDetectColor = EdgeDetect(posInput.positionNDC.xy, _EdgeDetectDepthThreshold, _EdgeDetectNormalThreshold, _EdgeDetectColorThreshold);

        // Remove the edge detect effect between the sky and objects when the object is inside the sphere
        edgeDetectColor *= depth != UNITY_RAW_FAR_CLIP_VALUE;

        // Combine edge and camera color
        return color * (1 - edgeDetectColor) + edgeDetectColor * _EdgeColor;
    }

    // We need this copy because we can't sample and write to the same render target (Camera color buffer)
    float4 Copy(Varyings varyings) : SV_Target
    {
        float depth = LoadCameraDepth(varyings.positionCS.xy);
        PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);

        return float4(LOAD_TEXTURE2D_X_LOD(_EdgeDetectionBuffer, posInput.positionSS.xy, 0).rgb, 1);
    }

    ENDHLSL

    SubShader
    {
        Pass
        {
            Name "Compositing"

            ZWrite Off
            ZTest Always
            Blend Off
            Cull Off

            HLSLPROGRAM
                #pragma fragment Compositing
            ENDHLSL
        }

        Pass
        {
            Name "Copy"

            ZWrite Off
            ZTest Always
            Blend Off
            Cull Off

            HLSLPROGRAM
                #pragma fragment Copy
            ENDHLSL
        }
    }
    Fallback Off
}
