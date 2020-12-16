Shader "BoatAttack/InfiniteWater"
{
	Properties
	{
		_Size ("size", float) = 3.0
		_DitherPattern ("Dithering Pattern", 2D) = "bump" {}
		[Toggle(_STATIC_SHADER)] _Static ("Static", Float) = 0
		_BumpScale("Detail Wave Amount", Range(0, 2)) = 0.2//fine detail multiplier
		[KeywordEnum(Off, SSS, Refraction, Reflection, Normal, Fresnel, WaterEffects, Foam, WaterDepth)] _Debug ("Debug mode", Float) = 0
	}
	SubShader
	{
		Tags { "RenderType"="Transparent" "Queue"="Transparent-101" "RenderPipeline" = "UniversalPipeline" }
		ZWrite off

		Pass
		{
			Name "InfiniteWaterShading"
			Tags{"LightMode" = "UniversalForward"}

			HLSLPROGRAM
			#pragma prefer_hlslcc gles
			/////////////////SHADER FEATURES//////////////////
			#pragma shader_feature _REFLECTION_CUBEMAP _REFLECTION_PROBES _REFLECTION_PLANARREFLECTION
			#pragma shader_feature _ _STATIC_SHADER
			#pragma shader_feature _DEBUG_OFF _DEBUG_SSS _DEBUG_REFRACTION _DEBUG_REFLECTION _DEBUG_NORMAL _DEBUG_FRESNEL _DEBUG_WATEREFFECTS _DEBUG_FOAM _DEBUG_WATERDEPTH

            // -------------------------------------
            // Lightweight Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT

			// make fog work
			#pragma multi_compile_fog

            ////////////////////INCLUDES//////////////////////
			#include "WaterCommon.hlsl"
			#include "InfiniteWater.hlsl"

			#pragma vertex InfiniteWaterVertex
			#pragma fragment InfiniteWaterFragment

			Varyings InfiniteWaterVertex(Attributes input)
			{
				Varyings output = (Varyings)0;

                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

				output.uv.xy = input.texcoord;

				float3 cameraOffset = GetCameraPositionWS();
				//input.positionOS.y *= abs(cameraOffset.y) + 1;
				cameraOffset.y -= 25.0;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz + cameraOffset);
				output.positionCS = vertexInput.positionCS;
				output.screenPosition = ComputeScreenPos(vertexInput.positionCS);

				float3 viewPos = vertexInput.positionVS;
				output.viewDirectionWS.xyz = UNITY_MATRIX_IT_MV[2].xyz;
				output.viewDirectionWS.w = length(viewPos / viewPos.z);

				return output;
			}

			void InfiniteWaterFragment(Varyings i, out half4 outColor:SV_Target, out float outDepth : SV_Depth) //: SV_Target
			{
			    half4 screenUV = 0.0;
	            screenUV.xy  = i.screenPosition.xy / i.screenPosition.w; // screen UVs
	            screenUV.zw  = screenUV.xy; // screen UVs
                //half2 screenUV = i.screenPosition.xy / i.screenPosition.w; // screen UVs

                half4 waterFX = SAMPLE_TEXTURE2D(_WaterFXMap, sampler_ScreenTextures_linear_clamp, screenUV.xy);

				InfinitePlane plane = WorldPlane(i.screenPosition, i.viewDirectionWS);
				float3 normal = half3(0.0, 1.0, 0.0);
                half3 viewDirectionWS = normalize(GetCameraPositionWS() - plane.positionWS);
				float4 additionalData = float4(1, length(viewDirectionWS), waterFX.w, 1);

                i.positionWS = plane.positionWS;
                i.normalWS = half3(0.0, 1.0, 0.0);
                i.viewDirectionWS = normalize(GetCameraPositionWS() - plane.positionWS).xyzz;
                i.additionalData = additionalData;
                i.uv = DetailUVs(plane.positionWS * (1 / _Size), 1);

                WaterInputData inputData;
                InitializeInputData(i, inputData, screenUV.xy);

                WaterSurfaceData surfaceData;
                InitializeSurfaceData(inputData, surfaceData);

                half4 color;
                color.a = 1;
                color.rgb = WaterShading(inputData, surfaceData, additionalData, screenUV.xy);

                outColor = color;
				outDepth = 1-plane.depth;
			}
			ENDHLSL
		}
	}
	FallBack "Hidden/InternalErrorShader"
}