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
				cameraOffset.y *= 0.0;
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
                half2 screenUV = i.screenPosition.xy / i.screenPosition.w; // screen UVs

                half4 waterFX = SAMPLE_TEXTURE2D(_WaterFXMap, sampler_ScreenTextures_linear_clamp, screenUV.xy);

				InfinitePlane plane = WorldPlane(i.screenPosition, i.viewDirectionWS);
				float3 normal = half3(0.0, 1.0, 0.0);
                half3 viewDirectionWS = normalize(GetCameraPositionWS() - plane.positionWS);
				float4 additionalData = float4(1, length(viewDirectionWS), waterFX.w, 1);

                // Depth
	            float3 depth = WaterDepth(plane.positionWS, additionalData, screenUV.xy);

	            // Detail waves
                DetailNormals(normal, DetailUVs(plane.positionWS * (1 / _Size), 1.0), waterFX, depth.x);

                // Lighting
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(plane.positionWS));
                half shadow = SoftShadows(screenUV, plane.positionWS);
                half3 GI = SampleSH(normal);

                // SSS
                half3 directLighting = dot(mainLight.direction, half3(0, 1, 0)) * mainLight.color;
                directLighting += saturate(pow(dot(viewDirectionWS, -mainLight.direction) * 1, 3)) * 5 * mainLight.color;
                half3 sss = directLighting * shadow + GI;

				half4 col = SAMPLE_TEXTURE2D(_SurfaceMap, sampler_SurfaceMap, plane.positionWS.xz);


                half lighting = dot(normal,  mainLight.direction);

                // Fresnel
	            half fresnelTerm = CalculateFresnelTerm(normal, viewDirectionWS);

    BRDFData brdfData;
    half alpha = 1.0f;
    InitializeBRDFData(half3(0, 0, 0), 0, half3(1, 1, 1), 0.95, alpha, brdfData);
	half3 spec = DirectBDRF(brdfData, normal, mainLight.direction, viewDirectionWS) * shadow * mainLight.color;

float tempdepth = 2;
                sss *= Scattering(depth.x);

                // Reflections
	            half3 reflection = SampleReflections(normal, viewDirectionWS, screenUV.xy, 0.0);

                // Refraction
                half3 refraction = Refraction(screenUV, depth.x);

	// Do compositing
	half3 comp = lerp(refraction, reflection, fresnelTerm) + sss + spec; //lerp(refraction, color + reflection + foam, 1-saturate(1-depth.x * 25));


				//outColor = half4(reflection * fresnelTerm + spec, 1);
				outColor = half4(comp, 1);
				outDepth = 1-plane.depth;
			}
			ENDHLSL
		}
	}
	FallBack "Hidden/InternalErrorShader"
}