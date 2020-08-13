#ifndef WATER_INPUT_INCLUDED
#define WATER_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

CBUFFER_START(UnityPerMaterial)
half _BumpScale;
half4 _DitherPattern_TexelSize;
CBUFFER_END
half _MaxDepth;
half _MaxWaveHeight;
int _DebugPass;
half4 _VeraslWater_DepthCamParams;
float4x4 _InvViewProjection;

// Screen Effects textures
SAMPLER(sampler_ScreenTextures_linear_clamp);
#if defined(_REFLECTION_PLANARREFLECTION)
TEXTURE2D(_PlanarReflectionTexture);
#elif defined(_REFLECTION_CUBEMAP)
TEXTURECUBE(_CubemapTexture);
SAMPLER(sampler_CubemapTexture);
#endif
TEXTURE2D(_WaterFXMap);
TEXTURE2D(_CameraDepthTexture);
TEXTURE2D(_CameraOpaqueTexture); SAMPLER(sampler_CameraOpaqueTexture_linear_clamp);

TEXTURE2D(_WaterDepthMap); SAMPLER(sampler_WaterDepthMap_linear_clamp);

// Surface textures
TEXTURE2D(_AbsorptionScatteringRamp); SAMPLER(sampler_AbsorptionScatteringRamp);
TEXTURE2D(_SurfaceMap); SAMPLER(sampler_SurfaceMap);
TEXTURE2D(_FoamMap); SAMPLER(sampler_FoamMap);
TEXTURE2D(_DitherPattern); SAMPLER(sampler_DitherPattern);

///////////////////////////////////////////////////////////////////////////////
//                  				Structs		                             //
///////////////////////////////////////////////////////////////////////////////

struct Attributes // vert struct
{
    float4 positionOS 			    : POSITION;		// vertex positions
	float2	texcoord 				: TEXCOORD0;	// local UVs
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings // fragment struct
{
	float4	uv 						: TEXCOORD0;	// Geometric UVs stored in xy, and world(pre-waves) in zw
	float3	positionWS				: TEXCOORD1;	// world position of the vertices
	half3 	normalWS 				: NORMAL;		// vert normals
	float4 	viewDirectionWS 		: TEXCOORD2;	// view direction
	float3	preWaveSP 				: TEXCOORD3;	// screen position of the verticies before wave distortion
	half2 	fogFactorNoise          : TEXCOORD4;	// x: fogFactor, y: noise
	float4	additionalData			: TEXCOORD5;	// x = distance to surface, y = distance to surface, z = normalized wave height, w = horizontal movement
	half4	screenPosition			: TEXCOORD6;	// screen position after the waves

	float4	positionCS				: SV_POSITION;
	UNITY_VERTEX_INPUT_INSTANCE_ID
	UNITY_VERTEX_OUTPUT_STEREO
};

struct WaterSurfaceData
{
    half3   absorption;
	half3   scattering;
    half3   normalWS;
    half    foam;
    half    foamMask;
};

struct WaterInputData
{
    float3 positionWS;
    half3 normalWS;
    half3 viewDirectionWS;
    float2 reflectionUV;
    float2 refractionUV;
    float4 detailUV;
    float4 shadowCoord;
    half4 waterFX;
    half fogCoord;
    float depth;
    half3 GI;
};

struct WaterLighting
{
    half3 driectLighting;
    half3 ambientLighting;
    half3 sss;
    half3 shadow;
};

#endif // WATER_INPUT_INCLUDED