#ifndef WATER_COMMON_INCLUDED
#define WATER_COMMON_INCLUDED

#define SHADOWS_SCREEN 0

#include "WaterInput.hlsl"
#include "CommonUtilities.hlsl"
#include "GerstnerWaves.hlsl"
#include "WaterLighting.hlsl"

#if defined(_STATIC_SHADER)
    #define WATER_TIME 0.0
#else
    #define WATER_TIME _Time.y
#endif

#define DEPTH_MULTIPLIER 1 / _MaxDepth
#define WaterFX(uv) SAMPLE_TEXTURE2D(_WaterFXMap, sampler_ScreenTextures_linear_clamp, uv)

///////////////////////////////////////////////////////////////////////////////
//          	   	       Water debug functions                             //
///////////////////////////////////////////////////////////////////////////////

half3 DebugWaterFX(half3 input, half4 waterFX, half screenUV)
{
    input = lerp(input, half3(waterFX.y, 1, waterFX.z), saturate(floor(screenUV + 0.7)));
    input = lerp(input, waterFX.xxx, saturate(floor(screenUV + 0.5)));
    half3 disp = lerp(0, half3(1, 0, 0), saturate((waterFX.www - 0.5) * 4));
    disp += lerp(0, half3(0, 0, 1), saturate(((1-waterFX.www) - 0.5) * 4));
    input = lerp(input, disp, saturate(floor(screenUV + 0.3)));
    return input;
}

///////////////////////////////////////////////////////////////////////////////
//          	   	      Water shading functions                            //
///////////////////////////////////////////////////////////////////////////////

half3 Scattering(half depth)
{
	return SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(depth * DEPTH_MULTIPLIER, 0.375h)).rgb;
}

half3 Absorption(half depth)
{
	return SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(depth * DEPTH_MULTIPLIER, 0.0h)).rgb;
}

float2 AdjustedDepth(half2 uvs, half4 additionalData)
{
	float rawD = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_ScreenTextures_linear_clamp, uvs);
	float d = LinearEyeDepth(rawD, _ZBufferParams);
	return float2(d * additionalData.x - additionalData.y, (rawD * -_ProjectionParams.x) + (1-UNITY_REVERSED_Z));
}

float WaterTextureDepth(float3 positionWS)
{
    return (1 - SAMPLE_TEXTURE2D_LOD(_WaterDepthMap, sampler_WaterDepthMap_linear_clamp, positionWS.xz * 0.002 + 0.5, 1).r) * (_MaxDepth + _VeraslWater_DepthCamParams.x) - _VeraslWater_DepthCamParams.x;
}

float3 WaterDepth(float3 positionWS, half4 additionalData, half2 screenUVs)// x = seafloor depth, y = water depth
{
	float3 outDepth = 0;
	outDepth.xz = AdjustedDepth(screenUVs, additionalData);
	float wd = WaterTextureDepth(positionWS);
	outDepth.y = wd + positionWS.y;
	return outDepth;
}

half3 Refraction(half2 distortion, half depth)
{
	half3 output = SAMPLE_TEXTURE2D_LOD(_CameraOpaqueTexture, sampler_CameraOpaqueTexture_linear_clamp, distortion, depth * 0.25).rgb;
	output *= Absorption(depth);
	return output;
}

half2 DistortionUVs(half depth, float3 normalWS)
{
    half3 viewNormal = mul((float3x3)GetWorldToHClipMatrix(), -normalWS).xyz;

    return viewNormal.xz * saturate((depth) * 0.005);
}

half4 AdditionalData(float3 postionWS, WaveStruct wave)
{
    half4 data = half4(0.0, 0.0, 0.0, 0.0);
    float3 viewPos = TransformWorldToView(postionWS);
	data.x = length(viewPos / viewPos.z);// distance to surface
    data.y = length(GetCameraPositionWS().xyz - postionWS); // local position in camera space(view direction WS)
	data.z = wave.position.y / _MaxWaveHeight * 0.5 + 0.5; // encode the normalized wave height into additional data
	data.w = wave.position.x + wave.position.z;
	return data;
}

float4 DetailUVs(float3 positionWS, half noise)
{
    float4 output = positionWS.xzxz * half4(0.4, 0.4, 0.1, 0.1);
    output.xy -= WATER_TIME * 0.1h + (noise * 0.2); // small detail
    output.zw += WATER_TIME * 0.05h + (noise * 0.1); // medium detail
    return output;
}

void DetailNormals(inout float3 normalWS, float4 uvs, half4 waterFX, float depth)
{
    half2 detailBump1 = SAMPLE_TEXTURE2D(_SurfaceMap, sampler_SurfaceMap, uvs.zw).xy * 2 - 1;
	half2 detailBump2 = SAMPLE_TEXTURE2D(_SurfaceMap, sampler_SurfaceMap, uvs.xy).xy * 2 - 1;
	half2 detailBump = (detailBump1 + detailBump2 * 0.5) * saturate(depth * 0.25 + 0.25);

	half3 normal1 = half3(detailBump.x, 0, detailBump.y) * _BumpScale;
	half3 normal2 = half3(1-waterFX.y, 0.5h, 1-waterFX.z) - 0.5;
	normalWS = normalize(normalWS + normal1 + normal2);
}

Varyings WaveVertexOperations(Varyings input)
{

    input.normalWS = float3(0, 1, 0);
	input.fogFactorNoise.y = ((noise((input.positionWS.xz * 0.5) + WATER_TIME) + noise((input.positionWS.xz * 1) + WATER_TIME)) * 0.25 - 0.5) + 1;

	// Detail UVs
    input.uv = DetailUVs(input.positionWS, input.fogFactorNoise.y);

	half4 screenUV = ComputeScreenPos(TransformWorldToHClip(input.positionWS));
	screenUV.xyz /= screenUV.w;

    // shallows mask
    half waterDepth = WaterTextureDepth(input.positionWS);
    input.positionWS.y += pow(saturate((-waterDepth + 1.5) * 0.4), 2);

	//Gerstner here
	WaveStruct wave;
	SampleWaves(input.positionWS, saturate((waterDepth * 0.1 + 0.05)), wave);
	input.normalWS = wave.normal;
    input.positionWS += wave.position;

#ifdef SHADER_API_PS4
	input.positionWS.y -= 0.5;
#endif

    // Dynamic displacement
	half4 waterFX = SAMPLE_TEXTURE2D_LOD(_WaterFXMap, sampler_ScreenTextures_linear_clamp, screenUV.xy, 0);
	input.positionWS.y += waterFX.w * 2 - 1;

	// After waves
	input.positionCS = TransformWorldToHClip(input.positionWS);
	input.screenPosition = ComputeScreenPos(input.positionCS);
    input.viewDirectionWS.xyz = SafeNormalize(_WorldSpaceCameraPos - input.positionWS);

    // Fog
	input.fogFactorNoise.x = ComputeFogFactor(input.positionCS.z);
	input.preWaveSP = screenUV.xyz; // pre-displaced screenUVs

	// Additional data
	input.additionalData = AdditionalData(input.positionWS, wave);

	// distance blend
	half distanceBlend = saturate(abs(length((_WorldSpaceCameraPos.xz - input.positionWS.xz) * 0.005)) - 0.25);
	input.normalWS = lerp(input.normalWS, half3(0, 1, 0), distanceBlend);

	return input;
}

void InitializeInputData(Varyings input, out WaterInputData inputData, float2 screenUV)
{
    float3 depth = WaterDepth(input.positionWS, input.additionalData, screenUV);// TODO - hardcoded shore depth UVs
    // Sample water FX texture
    inputData.waterFX = WaterFX(input.preWaveSP.xy);

    inputData.positionWS = input.positionWS;
    
    inputData.normalWS = input.normalWS;
    // Detail waves
    DetailNormals(inputData.normalWS, input.uv, inputData.waterFX, depth);
    
    inputData.viewDirectionWS = input.viewDirectionWS.xyz;
    
    half2 distortion = DistortionUVs(depth.x, inputData.normalWS);
	distortion = screenUV.xy + distortion;// * clamp(depth.x, 0, 5);
	float d = depth.x;
	depth.xz = AdjustedDepth(distortion, input.additionalData); // only x y
	distortion = depth.x < 0 ? screenUV.xy : distortion;
    inputData.refractionUV = distortion;
    depth.x = depth.x < 0 ? d : depth.x;

    inputData.detailUV = input.uv;

    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.normalWS);

    inputData.fogCoord = input.fogFactorNoise.x;
    inputData.depth = depth.x;
    inputData.reflectionUV = 0;
    inputData.GI = 0;

}

void InitializeSurfaceData(inout WaterInputData input, out WaterSurfaceData surfaceData)
{

    surfaceData.absorption = 0;
	surfaceData.scattering = 0;
/*
    // Foam
	half3 foamMap = SAMPLE_TEXTURE2D(_FoamMap, sampler_FoamMap,  IN.uv.zw).rgb; //r=thick, g=medium, b=light
	half depthEdge = saturate(depth.x * 20);
	half waveFoam = saturate(IN.additionalData.z - 0.75 * 0.5); // wave tips
	half depthAdd = saturate(1 - depth.x * 4) * 0.5;
	half edgeFoam = saturate((1 - min(depth.x, depth.y) * 0.5 - 0.25) + depthAdd) * depthEdge;
	half foamBlendMask = max(max(waveFoam, edgeFoam), waterFX.r * 2);
	half3 foamBlend = SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(foamBlendMask, 0.66)).rgb;
*/
    surfaceData.foamMask = 0;// saturate(length(foamMap * foamBlend) * 1.5 - 0.1);
    surfaceData.foam = 0;
}

float3 WaterShading(WaterInputData input, WaterSurfaceData surfaceData, float4 additionalData, float2 screenUV)
{
    // Lighting
	Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS));
    half shadow = SoftShadows(screenUV, input.positionWS, input.viewDirectionWS, input.depth);
    half3 GI = SampleSH(input.normalWS);

    // SSS
    half3 directLighting = dot(mainLight.direction, half3(0, 1, 0)) * mainLight.color;
    directLighting += saturate(pow(dot(input.viewDirectionWS.xyz, -mainLight.direction) * additionalData.z, 3)) * 5 * mainLight.color;
    

    BRDFData brdfData;
    half alpha = 1;
    InitializeBRDFData(half3(0, 0, 0), 0, half3(1, 1, 1), 0.95, alpha, brdfData);
	half3 spec = DirectBDRF(brdfData, input.normalWS, mainLight.direction, input.viewDirectionWS) * mainLight.color * shadow;

    // Fresnel
	half fresnelTerm = CalculateFresnelTerm(input.normalWS, input.viewDirectionWS);

    half3 sss = directLighting * shadow + GI;
    sss *= Scattering(input.depth);

	// Reflections
	half3 reflection = SampleReflections(input.normalWS, input.viewDirectionWS, screenUV, 0.0);

	// Refraction
	half3 refraction = Refraction(input.refractionUV, input.depth);

	// Do compositing
	half3 output = lerp(lerp(refraction, reflection, fresnelTerm) + sss + spec, surfaceData.foam, surfaceData.foamMask);

    //return refraction;
    return MixFog(output, input.fogCoord);
}

float WaterNearFade(float3 positionWS)
{
    float3 camPos = GetCameraPositionWS();
    camPos.y = 0;
    return 1 - saturate((distance(positionWS, camPos) - 50) * 0.1);
}

///////////////////////////////////////////////////////////////////////////////
//               	   Vertex and Fragment functions                         //
///////////////////////////////////////////////////////////////////////////////

// Vertex: Used for Standard non-tessellated water
Varyings WaterVertex(Attributes v)
{
    Varyings o = (Varyings)0;
	UNITY_SETUP_INSTANCE_ID(v);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
	UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

    o.uv.xy = v.texcoord; // geo uvs
    o.positionWS = TransformObjectToWorld(v.positionOS.xyz);

	o = WaveVertexOperations(o);
    return o;
}

// Fragment for water
half4 WaterFragment(Varyings IN) : SV_Target
{
	UNITY_SETUP_INSTANCE_ID(IN);
	half4 screenUV = 0.0;
	screenUV.xy  = IN.screenPosition.xy / IN.screenPosition.w; // screen UVs
	screenUV.zw  = IN.preWaveSP.xy; // screen UVs

    WaterInputData inputData;
    InitializeInputData(IN, inputData, screenUV.xy);

    WaterSurfaceData surfaceData;
    InitializeSurfaceData(inputData, surfaceData);

    half4 current;
    current.a = WaterNearFade(IN.positionWS);
    current.rgb = WaterShading(inputData, surfaceData, IN.additionalData, screenUV.xy);

    return current;

    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////

	half4 waterFX = SAMPLE_TEXTURE2D(_WaterFXMap, sampler_ScreenTextures_linear_clamp, IN.preWaveSP.xy);

	// Depth
	float3 depth = WaterDepth(IN.positionWS, IN.additionalData, screenUV.xy);// TODO - hardcoded shore depth UVs

    // Detail waves
    DetailNormals(IN.normalWS, IN.uv, waterFX, depth.x);

    // Distortion
	half2 distortion = DistortionUVs(depth.x, IN.normalWS);
	distortion = screenUV.xy + distortion;// * clamp(depth.x, 0, 5);
	float d = depth.x;
	depth.xz = AdjustedDepth(distortion, IN.additionalData);
	distortion = depth.x < 0 ? screenUV.xy : distortion;
	depth.x = depth.x < 0 ? d : depth.x;

    // Fresnel
	half fresnelTerm = CalculateFresnelTerm(IN.normalWS, IN.viewDirectionWS.xyz);
	//return fresnelTerm.xxxx;

	// Lighting
	Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
    half shadow = SoftShadows(screenUV, IN.positionWS, IN.viewDirectionWS.xyz, depth.x);
    half3 GI = SampleSH(IN.normalWS);

    // SSS
    half3 directLighting = dot(mainLight.direction, half3(0, 1, 0)) * mainLight.color;
    directLighting += saturate(pow(dot(IN.viewDirectionWS.xyz, -mainLight.direction) * IN.additionalData.z, 3)) * 5 * mainLight.color;
    half3 sss = directLighting * shadow + GI;

    ////////////////////////////////////////////////////////////////////////////////////////

	// Foam
	half3 foamMap = SAMPLE_TEXTURE2D(_FoamMap, sampler_FoamMap,  IN.uv.zw).rgb; //r=thick, g=medium, b=light
	half depthEdge = saturate(depth.x * 20);
	half waveFoam = saturate(IN.additionalData.z - 0.75 * 0.5); // wave tips
	half depthAdd = saturate(1 - depth.x * 4) * 0.5;
	half edgeFoam = saturate((1 - min(depth.x, depth.y) * 0.5 - 0.25) + depthAdd) * depthEdge;
	half foamBlendMask = max(max(waveFoam, edgeFoam), waterFX.r * 2);
	half3 foamBlend = SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(foamBlendMask, 0.66)).rgb;
	half foamMask = saturate(length(foamMap * foamBlend) * 1.5 - 0.1);
	// Foam lighting
	half3 foam = foamMask.xxx * (mainLight.shadowAttenuation * mainLight.color + GI);

    BRDFData brdfData;
    half a = 1;
    InitializeBRDFData(half3(0, 0, 0), 0, half3(1, 1, 1), 0.95, a, brdfData);
	half3 spec = DirectBDRF(brdfData, IN.normalWS, mainLight.direction, IN.viewDirectionWS) * shadow * mainLight.color;
#ifdef _ADDITIONAL_LIGHTS
    uint pixelLightCount = GetAdditionalLightsCount();
    for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
    {
        Light light = GetAdditionalLight(lightIndex, IN.positionWS);
        spec += LightingPhysicallyBased(brdfData, light, IN.normalWS, IN.viewDirectionWS.xyz);
        sss += light.distanceAttenuation * light.color;
    }
#endif

    sss *= Scattering(depth.x);

	// Reflections
	half3 reflection = SampleReflections(IN.normalWS, IN.viewDirectionWS.xyz, screenUV.xy, 0.0);

	// Refraction
	half3 refraction = Refraction(distortion, depth.x);

	// Do compositing
	half3 comp = lerp(lerp(refraction, reflection, fresnelTerm) + sss + spec, foam, foamMask); //lerp(refraction, color + reflection + foam, 1-saturate(1-depth.x * 25));

	// Fog
    float fogFactor = IN.fogFactorNoise.x;
    comp = MixFog(comp, fogFactor);

    // alpha
    float3 camPos = GetCameraPositionWS();
    camPos.y = 0;
    float alpha = 1 - saturate((distance(IN.positionWS, camPos) - 50) * 1);

    //return half4(IN.additionalData.www, alpha);
    
    half3 old = comp;
    half fiftyfifty = round(screenUV.x);
    return half4(lerp(old, current.rgb, fiftyfifty), alpha);

#if defined(_DEBUG_FOAM)
    return half4(foamMask.xxx, 1);
#elif defined(_DEBUG_SSS)
    return half4(sss, 1);
#elif defined(_DEBUG_REFRACTION)
    return half4(refraction, 1);
#elif defined(_DEBUG_REFLECTION)
    return half4(reflection, 1);
#elif defined(_DEBUG_NORMAL)
    return half4(IN.normalWS.x * 0.5 + 0.5, 0, IN.normalWS.z * 0.5 + 0.5, 1);
#elif defined(_DEBUG_FRESNEL)
    return half4(fresnelTerm.xxx, 1);
#elif defined(_DEBUG_WATEREFFECTS)
    return half4(waterFX);
#elif defined(_DEBUG_WATERDEPTH)
    return half4(frac(depth.z).xxx, 1);
#else
    return half4(comp, alpha);
#endif
}

#endif // WATER_COMMON_INCLUDED
