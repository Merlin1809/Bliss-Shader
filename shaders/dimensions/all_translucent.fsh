#ifdef IS_LPV_ENABLED
	#extension GL_ARB_shader_image_load_store: enable
	#extension GL_ARB_shading_language_packing: enable
#endif

#include "/lib/settings.glsl"

#include "/lib/SSBOs.glsl"

#undef FLASHLIGHT_BOUNCED_INDIRECT

#if MC_VERSION >= 12110
#define MAIN_SHADOW_PASS
#endif

// #if defined END_SHADER || defined NETHER_SHADER
// 	#undef IS_LPV_ENABLED
// #endif

#include "/lib/res_params.glsl"

in DATA {
	vec4 lmtexcoord;
	#if defined LIGHTNING || defined ENTITIES
		vec4 color;
	#else
		vec3 color;
	#endif

	vec3 viewVector;

	vec4 normalMat;
	vec4 tangent;

	#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 0 && !defined HAND
		float chunkFade;
	#endif

	#ifdef OVERWORLD_SHADER
		flat vec3 WsunVec;
	#endif

	#if defined ENTITIES && defined IS_IRIS
		flat int NAMETAG;
	#endif

	#ifdef LARGE_WAVE_DISPLACEMENT
		vec3 largeWaveDisplacementNormal;
	#endif

	#ifdef LIGHTNING
		float LIGHTNING_BOLT;
	#endif
};

uniform vec4 entityColor;

#if defined OVERWORLD_SHADER || (defined END_ISLAND_LIGHT && defined END_SHADER)
	const bool shadowHardwareFiltering = true;
	uniform sampler2DShadow shadowtex0HW;
	
	#ifdef TRANSLUCENT_COLORED_SHADOWS
		uniform sampler2D shadowcolor0;
		uniform sampler2DShadow shadowtex1HW;
	#endif

	uniform float lightSign;
#endif

uniform sampler2D noisetex;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

#ifdef DISTANT_HORIZONS
	uniform sampler2D dhDepthTex1;
	#define dhVoxyDepthTex1 dhDepthTex1
#endif

#ifdef VOXY
	uniform sampler2D vxDepthTexOpaque;
	#define dhVoxyDepthTex1 vxDepthTexOpaque
#endif

uniform sampler2D colortex7;
uniform sampler2D colortex9;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex5;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex6;

uniform sampler2D gtexture;
uniform sampler2D specular;
uniform sampler2D normals;

#ifdef IS_LPV_ENABLED
	uniform usampler1D texBlockData;
	uniform sampler3D texLpv1;
	uniform sampler3D texLpv2;
#endif

uniform vec3 sunVec;
uniform float near;
// uniform float far;
uniform float sunElevation;

uniform int isEyeInWater;
uniform float rainStrength;
uniform float skyIntensityNight;
uniform float skyIntensity;
uniform ivec2 eyeBrightnessSmooth;
uniform float nightVision;

uniform int frameCounter;
uniform float frameTimeCounter;
uniform vec2 texelSize;
uniform int framemod8;
uniform float viewWidth;
uniform float viewHeight;

uniform mat4 gbufferPreviousModelView;
uniform vec3 previousCameraPosition;

uniform float moonIntensity;
uniform float sunIntensity;
uniform vec3 sunColor;
uniform vec3 nsunColor;

uniform int heldItemId;
uniform int heldItemId2;
uniform bool firstPersonCamera;

uniform float waterEnteredAltitude;

#if WATER_INTERACTION == 1
	uniform vec3 waterEnteredPosition;
	uniform float waterEnteredTime;
	uniform vec3 waterEnteredVelocity;

	uniform vec3 waterExitedPosition;
	uniform float waterExitedTime;
	uniform vec3 waterExitedVelocity;
#endif

#if WATER_INTERACTION == 2
	#ifdef PIXELATED_WAVES
		layout (rgba16f) uniform readonly image2D waveSim2;
	#else
		uniform sampler2D waveSim2Sampler;
	#endif
#endif

uniform float dhVoxyNearPlane;
uniform float dhVoxyFarPlane;

#include "/lib/util.glsl"
#include "/lib/Shadow_Params.glsl"
#include "/lib/color_transforms.glsl"
#include "/lib/projections.glsl"
#include "/lib/DistantHorizons_projections.glsl"
#include "/lib/sky_gradient.glsl"
#include "/lib/waterBump.glsl"

#ifdef IRIS_FEATURE_TEXTURE_FILTERING
#include "/lib/texture_filtering.glsl"
#endif

#ifdef OVERWORLD_SHADER
	#include "/lib/lightning_stuff.glsl"
	
	#include "/lib/scene_controller.glsl"
	
	#define CLOUDSHADOWSONLY
	#include "/lib/volumetricClouds.glsl"

#endif

#ifdef END_SHADER
	#include "/lib/end_fog.glsl"
#endif

#ifdef IS_LPV_ENABLED
	#include "/lib/hsv.glsl"
	#include "/lib/lpv_common.glsl"
	#include "/lib/lpv_render.glsl"
	// #include "/lib/voxel_common.glsl"
#endif

#define FORWARD_SPECULAR
#define FORWARD_SSR_QUALITY 30 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 200 300 400 500]
#define FORWARD_BACKGROUND_REFLECTION
// #define FORWARD_ROUGH_REFLECTION


#ifdef FORWARD_SPECULAR
#endif
#if FORWARD_SSR_QUALITY > -1
#endif
#ifdef FORWARD_BACKGROUND_REFLECTION
#endif
#ifdef FORWARD_ROUGH_REFLECTION
#endif

uniform vec3 relativeEyePosition;

vec2 decodeVec2(float a){
    const vec2 constant1 = 65535. / vec2( 256., 65536.);
    const float constant2 = 256. / 255.;
    return fract( a * constant1 ) * constant2 ;
}

#include "/lib/blocks.glsl"
#include "/lib/lpv_blocks.glsl"
#include "/lib/lpv_buffer.glsl"

#if defined VIVECRAFT
	uniform bool vivecraftIsVR;
	uniform vec3 vivecraftRelativeMainHandPos;
	uniform vec3 vivecraftRelativeOffHandPos;
	uniform mat4 vivecraftRelativeMainHandRot;
	uniform mat4 vivecraftRelativeOffHandRot;
#endif

#define VOXEL_REFLECTIONS_TRANSLUCENT

#ifdef VOXEL_REFLECTIONS_TRANSLUCENT
	#define VOXEL_REFLECTIONS
#endif

#ifdef PHOTONICS
	#ifdef VOXEL_REFLECTIONS
		#define PHOTONICS_INCLUDED

		#include "/photonics/photonics.glsl"
	#endif
#endif

#include "/lib/diffuse_lighting.glsl"

#if defined PHYSICSMOD_OCEAN_SHADER
	#include "/lib/oceans.glsl"
#endif


float interleaved_gradientNoise_temporal(){
	#ifdef TAA
		return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887);
	#endif
}

float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}

float R2_dither(){
	vec2 coord = gl_FragCoord.xy ;

	#ifdef TAA
		coord += + (frameCounter%40000) * 2.0;
	#endif
	
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * coord.x + alpha.y * coord.y ) ;
}

float blueNoise(){
	#ifdef TAA
  		return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887);
	#endif
}

#include "/lib/TAA_jitter.glsl"

vec3 getParallaxDisplacement(vec3 waterPos, vec3 playerPos) {

	float largeWaves = texture(noisetex, waterPos.xy / 600.0 ).b;
	float largeWavesCurved = pow(1.0-pow(1.0-largeWaves,2.5),4.5);
	largeWavesCurved = mix(1.0-largeWavesCurved, largeWavesCurved, PATCHY_WAVE_BLEND);

	float waterHeight = getWaterHeightmap(waterPos.xy, largeWaves, largeWavesCurved);
	// waterHeight = exp(-20.0*sqrt(waterHeight));
	waterHeight = exp(-7.0*exp(-7.0*waterHeight)) * 0.25;
	
	vec3 parallaxPos = waterPos;

	parallaxPos.xy += (viewVector.xy / -viewVector.z) * waterHeight;

	return parallaxPos;
}

vec3 applyBump(mat3 tbnMatrix, vec3 bump, float mult, vec3 rippleBump){
	float bumpmult = mult;
	bump = bump * bumpmult + vec3(0.0f, 0.0f, 1.0f - bumpmult);

	#if defined PHYSICSMOD_OCEAN_SHADER && defined PHYSICS_OCEAN
		bump += 4.0 * rippleBump;
	#endif
	
	return normalize(bump*tbnMatrix);
}

vec2 CleanSample(
	int samples, float totalSamples, float noise
){

	// this will be used to make 1 full rotation of the spiral. the mulitplication is so it does nearly a single rotation, instead of going past where it started
	float variance = noise * 0.897;

	// for every sample input, it will have variance applied to it.
	float variedSamples = float(samples) + variance;
	
	// for every sample, the sample position must change its distance from the origin.
	// otherwise, you will just have a circle.
    float spiralShape = sqrt(variedSamples / (totalSamples + variance));

	float shape = 2.26; // this is very important. 2.26 is very specific
    float theta = variedSamples * (PI * shape);

	float x =  cos(theta) * spiralShape;
	float y =  sin(theta) * spiralShape;

    return vec2(x, y);
}

vec3 viewToWorld(vec3 viewPos) {
    vec4 pos;
    pos.xyz = viewPos;
    pos.w = 0.0;
    pos = gbufferModelViewInverse * pos ;
    return pos.xyz;
}

vec3 worldToView(vec3 worldPos) {
    vec4 pos = vec4(worldPos, 0.0);
    pos = gbufferModelView * pos;
    return pos.xyz;
}

vec4 encode (vec3 n, vec2 lightmaps){
	n.xy = n.xy / dot(abs(n), vec3(1.0));
	n.xy = n.z <= 0.0 ? (1.0 - abs(n.yx)) * sign(n.xy) : n.xy;
    vec2 encn = clamp(n.xy * 0.5 + 0.5,-1.0,1.0);
	
    return vec4(encn,vec2(lightmaps.x,lightmaps.y));
}

//encoding by jodie
float encodeVec2(vec2 a){
    const vec2 constant1 = vec2( 1., 256.) / 65535.;
    vec2 temp = floor( a * 255. );
	return temp.x*constant1.x+temp.y*constant1.y;
}

float encodeVec2(float x,float y){
    return encodeVec2(vec2(x,y));
}

float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}



#ifdef RIPPLE_WATER
	#include "/lib/ripples.glsl"
	uniform float rippleAmount;
#endif

// #undef BASIC_SHADOW_FILTER

#if defined OVERWORLD_SHADER || (defined END_SHADER && defined END_ISLAND_LIGHT)

#include "/lib/Shadows.glsl"

float ComputeShadowMap(inout vec3 directLightColor, vec3 playerPos, float maxDistFade, float noise, in vec3 geoNormals){

	// if(maxDistFade <= 0.0) return 1.0;

	// setup shadow projection
	#ifdef OVERWORLD_SHADER
		#ifdef CUSTOM_MOON_ROTATION
			vec3 projectedShadowPosition = mat3(customShadowMatrixSSBO) * playerPos  + customShadowMatrixSSBO[3].xyz;
		#else
			vec3 projectedShadowPosition = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
		#endif

		applyShadowBias(projectedShadowPosition, playerPos, geoNormals);

		projectedShadowPosition = diagonal3(shadowProjection) * projectedShadowPosition + shadowProjection[3].xyz;

		// un-distort
		#ifdef DISTORT_SHADOWMAP
			float distortFactor = calcDistort(projectedShadowPosition.xy);
			projectedShadowPosition.xy *= distortFactor;
		#else
			float distortFactor = 1.0;
		#endif

		projectedShadowPosition.z += shadowProjection[3].z * 0.0012;
	#else
		float distortFactor = 1.0;
	#endif

	#if defined END_ISLAND_LIGHT && defined END_SHADER
		vec4 shadowPos = customShadowMatrixSSBO * vec4(playerPos, 1.0);
		applyShadowBias(shadowPos.xyz, playerPos, geoNormals);
		shadowPos =  customShadowPerspectiveSSBO * shadowPos;
		vec3 projectedShadowPosition = shadowPos.xyz / shadowPos.w;
	#endif



	// hamburger
	projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5);
	
	float shadowmap = 0.0;
	vec3 translucentTint = vec3(0.0);

	#ifdef BASIC_SHADOW_FILTER
		int samples = int(SHADOW_FILTER_SAMPLE_COUNT * 0.5);
		#ifdef END_SHADER
			float rdMul = 52.0*distortFactor*d0k;
		#else
			float rdMul = 2.4*distortFactor*d0k;
		#endif

		for(int i = 0; i < samples; i++){
			vec2 offsetS = CleanSample(i, samples - 1, noise) * rdMul;
			projectedShadowPosition.xy += offsetS;
	#else
		int samples = 1;
	#endif
	

		#ifdef TRANSLUCENT_COLORED_SHADOWS

			// determine when opaque shadows are overlapping translucent shadows by getting the difference of opaque depth and translucent depth
			float shadowDepthDiff = pow(clamp((texture(shadowtex1HW, projectedShadowPosition).x - projectedShadowPosition.z) * 2.0,0.0,1.0),2.0);

			// get opaque shadow data to get opaque data from translucent shadows.
			float opaqueShadow = texture(shadowtex0HW, projectedShadowPosition).x;
			shadowmap += max(opaqueShadow, shadowDepthDiff);

			// get translucent shadow data
			vec4 translucentShadow = texture(shadowcolor0, projectedShadowPosition.xy);

			// this curve simply looked the nicest. it has no other meaning.
			float shadowAlpha = pow(1.0 - pow(translucentShadow.a,5.0),0.2);

			// normalize the color to remove luminance, and keep the hue. remove all opaque color.
			// mulitply shadow alpha to shadow color, but only on surfaces facing the lightsource. this is a tradeoff to protect subsurface scattering's colored shadow tint from shadow bias on the back of the caster.
			translucentShadow.rgb = max(normalize(translucentShadow.rgb + 0.0001), max(opaqueShadow, 1.0-shadowAlpha)) * shadowAlpha;

			// make it such that full alpha areas that arent in a shadow have a value of 1.0 instead of 0.0
			translucentTint += mix(translucentShadow.rgb, vec3(1.0),  opaqueShadow*shadowDepthDiff);

		#else
			shadowmap += texture(shadowtex0HW, projectedShadowPosition).x;
		#endif

	#ifdef BASIC_SHADOW_FILTER
		}
	#endif

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		// tint the lightsource color with the translucent shadow color
		directLightColor *= mix(vec3(1.0), translucentTint.rgb / samples, maxDistFade);
	#endif

	float shadowResult = shadowmap / samples;

	#ifdef END_SHADER
	float r = length(projectedShadowPosition.xy - vec2(0.5));
	if (r < 0.5 && abs(projectedShadowPosition.z) < 1.0) {
		shadowResult *= smoothstep(0.5, 0.25, r);
	} else {
		shadowResult = 0.0;
	}
	#endif

	return shadowResult;
	// return mix(1.0, shadowmap / samples, maxDistFade);
}
#endif

#include "/lib/specular.glsl"

void convertHandDepth(inout float depth) {
    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;
    depth = ndcDepth * 0.5 + 0.5;
}

void Emission(
	inout vec3 Lighting,
	vec3 Albedo,
	float Emission
){
	if( Emission < 254.5/255.0) Lighting = mix(Lighting, Albedo * 5.0 * Emissive_Brightness, pow(Emission, Emissive_Curve));
}

float bias(){
	// bias mipmapping as window resolution and / or render scale changes.
	#ifdef TAA_UPSCALING
		return (1.0 - texelSize.x * 2560.0) + (0.0 - (1.0-RENDER_SCALE.x) * 2.0);
	#else
		return 1.0 - texelSize.x * 2560.0;
	#endif
}

#if defined FLASHLIGHT_SHADOWS && defined FLASHLIGHT && defined MAIN_SHADOW_PASS
float SSRT_FlashLight_Shadows(vec3 viewPos, bool depthCheck, vec3 lightDir, float noise, vec3 normals, bool hand){
	
	if(hand || !firstPersonCamera) return 1.0;

	vec3 WlightDir = normalize((gbufferModelViewInverse*vec4(lightDir, 1.0)).xyz);

	float NdotL = dot(normals, WlightDir);
	NdotL = smoothstep(0.0, 0.2, abs(NdotL));

	float shadows = 1.0;
	float samples = 16.0;

	float _near = near; float _far = far*4.0;

	if (depthCheck) {
		_near = dhVoxyNearPlane;
		_far = dhVoxyFarPlane;
	}

	vec3 position = toClipSpace3_DH(viewPos, depthCheck) ;
	
	//prevents the ray from going behind the camera
	float rayLength = ((viewPos.z + lightDir.z * _far * sqrt(3.)) > -_near) ? (-_near - viewPos.z) / lightDir.z : _far * sqrt(3.);

	vec3 direction = toClipSpace3_DH(viewPos + lightDir*rayLength, depthCheck) - position;
	direction.xyz = direction.xyz / max(max(abs(direction.x)/0.0005, abs(direction.y)/0.0005),400.0);	//fixed step size
	direction *= 6.0;

	position.xy *= RENDER_SCALE;
	direction.xy *= RENDER_SCALE;
	
	vec3 newPos = position + direction*noise;
	// literally shadow bias to fight shadow acne due to precision problems when comparing sampled depth and marched position
	//newPos += direction*0.3;


	for (int i = 0; i < int(samples); i++) {
		float samplePos;
		
		#if defined DISTANT_HORIZONS || defined VOXY
			if(depthCheck) {
				samplePos = texelFetch(dhVoxyDepthTex1, ivec2(newPos.xy/texelSize),0).x;
			} else
		#endif
			{
				samplePos = texelFetch(depthtex2, ivec2(newPos.xy/texelSize),0).x,hand;
			}

		if(samplePos < newPos.z && samplePos > 0.0){// && (samplePos <= max(minZ,maxZ) && samplePos >= min(minZ,maxZ))){
			shadows = 0.0;
			break;
		} 
	
		newPos += direction;
	}

	return clamp(shadows*NdotL, 1.0-FLASHLIGHT_SHADOWS_STRENGTH, 1.0);
}
#endif

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

/* RENDERTARGETS:2,7,11,14 */


void main() {
if (gl_FragCoord.x * texelSize.x < 1.0  && gl_FragCoord.y * texelSize.y < 1.0 )	{
	
	vec3 FragCoord = gl_FragCoord.xyz;
	float mipmapBias = bias();

	float BN = blueNoise();

	#ifdef TAA
		vec2 tempOffset = offsets[framemod8];
		vec3 viewPos = toScreenSpace(FragCoord*vec3(texelSize/RENDER_SCALE,1.0)-vec3(vec2(tempOffset)*texelSize*0.5, 0.0));
	#else
		vec3 viewPos = toScreenSpace(FragCoord*vec3(texelSize/RENDER_SCALE,1.0));
	#endif

	vec3 feetPlayerPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldPos = feetPlayerPos + cameraPosition;
////////////////////////////////////////////////////////////////////////////////
//////////////////////////////// MATERIAL MASKS ////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
	
	float MATERIALS = normalMat.w;

	// 1.0 = water mask
	// 0.9 = entity mask
	// 0.8 = reflective entities
	// 0.7 = reflective blocks
	// 0.6 = nether portal
	// 0.4 = translucent particles
	// 0.3 = hand mask

	#ifdef HAND
		MATERIALS = 0.3;
	#endif

	// bool isHand = abs(MATERIALS - 0.1) < 0.01;
	bool isWater = MATERIALS > 0.99;
	bool isReflectiveEntity = abs(MATERIALS - 0.2) < 0.01;
	bool isReflective = abs(MATERIALS - 0.1) < 0.01 || isWater || isReflectiveEntity;
	bool isEntity = abs(MATERIALS - 0.4) < 0.01 || isReflectiveEntity;
	// bool isNetherPortal =  abs(MATERIALS - 0.6) < 0.01;

////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////// ALBEDO /////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

	vec2 lightmap = lmtexcoord.zw;
	
	#ifndef COLORWHEEL
		#ifdef IRIS_FEATURE_TEXTURE_FILTERING
		gl_FragData[0] = textureFilteringMode == 1 ? sampleRGSS(gtexture, lmtexcoord.xy, 1.0 / vec2(textureSize(gtexture, 0))) : sampleNearest(gtexture, lmtexcoord.xy, 1.0 / vec2(textureSize(gtexture, 0)));
		#else
		gl_FragData[0] = texture(gtexture, lmtexcoord.xy, mipmapBias);
		#endif

		gl_FragData[0].rgb *= color.rgb;

		#if defined LIGHTNING || defined ENTITIES
			gl_FragData[0].a *= color.a;
		#endif
	#else
		vec4 _color = texture(gtexture, lmtexcoord.xy, mipmapBias);
		float ao;
		vec4 overlayColor;

		clrwl_computeFragment(_color, _color, lightmap, ao, overlayColor);
		lightmap = clamp((lightmap - 1.0 / 32.0) * 32.0 / 30.0, 0.0, 1.0);

		gl_FragData[0] = _color;
	#endif

	#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 0 && !defined HAND
		gl_FragData[0].a *= sqrt(chunkFade);

		#ifdef TAA
			if(sqrt(chunkFade) < BN && isWater) discard;
		#else
			if(sqrt(chunkFade) < R2_dither() && isWater) discard;
		#endif
	#endif

	float UnchangedAlpha = gl_FragData[0].a;

	#ifdef WhiteWorld
		gl_FragData[0].rgb = vec3(1.0);
		gl_FragData[0].a = 1.0/255.0;
	#endif

	vec3 Albedo = toLinear(gl_FragData[0].rgb);

	vec3 shadowPlayerPos = feetPlayerPos + gbufferModelViewInverse[3].xyz;
	#if (defined DISTANT_HORIZONS && DH_CHUNK_FADING > 0) || defined RIPPLE_WATER
		float viewDist = length(shadowPlayerPos); 
	#endif

	#ifndef WhiteWorld
		#ifdef VANILLA_LIKE_WATER
			if (isWater) Albedo *= sqrt(luma(Albedo));
		#else
			if (isWater){
				Albedo = vec3(0.0);
				gl_FragData[0].a = 1.0/255.0;
			}
		#endif
	#endif

	#if defined DISTANT_HORIZONS && DH_CHUNK_FADING > 0 && !defined LIGHTNING
		float ditherFade = smoothstep(0.98 * far, 1.03 * far, viewDist);

		if (step(ditherFade, R2_dither()) == 0.0) discard;
	#endif

	#ifdef LIGHTNING
		if (LIGHTNING_BOLT > 0.0){
			Albedo = 2.5 * vec3(1.0,2.2,6.5);
		} else {
			Albedo *= color.a;
			gl_FragData[0].a = color.a;
		}
	#endif

	#if defined ENTITIES && !defined COLORWHEEL
		Albedo.rgb = mix(Albedo.rgb, entityColor.rgb, pow(entityColor.a, 0.8));
	#endif

	#ifdef COLORWHEEL
		Albedo.rgb = mix(Albedo.rgb, overlayColor.rgb, overlayColor.a);
	#endif

	vec4 GLASS_TINT_COLORS = vec4(Albedo, UnchangedAlpha);
	
	#ifdef BIOME_TINT_WATER
		if (isWater) GLASS_TINT_COLORS.rgb = toLinear(color.rgb);
	#endif

////////////////////////////////////////////////////////////////////////////////
//////////////////////////////// NORMALS ///////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

	vec3 normal = normalMat.xyz; // in viewSpace
	vec3 geoNormals = viewToWorld(normal).xyz; // for refractions

	#if defined PHYSICSMOD_OCEAN_SHADER && defined PHYSICS_OCEAN
		WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);
		
		#if defined DISTANT_HORIZONS
			float PHYSICS_OCEAN_TRANSITION = 1.0-pow(1.0-pow(1.0-clamp(1.0-length(feetPlayerPos.xz)/max(far,0.0),0,1),5),5);
		#else
			float PHYSICS_OCEAN_TRANSITION = 0.0;
		#endif

		if (isWater){
			if (!gl_FrontFacing) {
   			    wave.normal = -wave.normal;
   			}

			normal = mix(normalize(gl_NormalMatrix * wave.normal), normal, PHYSICS_OCEAN_TRANSITION);
			Albedo = mix(Albedo, vec3(1.0), wave.foam);
			gl_FragData[0].a = mix(1.0/255.0, 1.0, wave.foam);
		}
	#endif

	vec3 worldSpaceNormal = viewToWorld(normal).xyz;
	
	#if defined LARGE_WAVE_DISPLACEMENT && !defined PHYSICS_OCEAN
		if (isWater){
			normal = largeWaveDisplacementNormal;
		}
	#endif

	vec3 tangent2 = normalize(cross(tangent.rgb, normal)*tangent.w);
	mat3 tbnMatrix = mat3(tangent.x, tangent2.x, normal.x,
						  tangent.y, tangent2.y, normal.y,
						  tangent.z, tangent2.z, normal.z);


	vec3 NormalTex = vec3(texture(normals, lmtexcoord.xy, mipmapBias).xy,0.0);
	NormalTex.xy = NormalTex.xy*2.0-1.0;
	NormalTex.z = clamp(sqrt(1.0 - dot(NormalTex.xy, NormalTex.xy)),0.0,1.0);

	vec3 rippleBump = vec3(0.0);

	#if !defined HAND && !defined VANILLA_LIKE_WATER
		if (isWater){
			vec3 playerPos = shadowPlayerPos;
			vec3 waterPos = playerPos;

			vec3 flowDir = normalize(worldSpaceNormal*10.0) * frameTimeCounter * 2.0 * WATER_WAVE_SPEED;
			
			vec2 newPos = worldPos.xy + abs(flowDir.xz);
			newPos = mix(newPos, worldPos.zy + abs(flowDir.zx), clamp(abs(worldSpaceNormal.x),0.0,1.0));
			newPos = mix(newPos, worldPos.xz, clamp(abs(worldSpaceNormal.y),0.0,1.0));
			waterPos.xy = newPos;
		
			waterPos.xyz = getParallaxDisplacement(waterPos, playerPos);

			vec3 bump = getWaveNormal(waterPos, playerPos);

			#ifdef RIPPLE_WATER
				if(viewDist < 35 && rainStrength > 0.0 && rippleAmount > 0.01 && abs(worldSpaceNormal.z) < 0.95 && abs(worldSpaceNormal.x) < 0.95) {
					float effectStrength = smoothstep(0.85, 1.0, lightmap.y) * smoothstep(0.0, 1.0, rippleAmount);
					rippleBump = ripples(worldPos.xz);
					bump += 0.6 * RIPPLE_STRENGTH * rippleBump * rainStrength * effectStrength * smoothstep(35.0, 10.0, viewDist);
				}
			#endif

			bump = normalize(bump);

			float bumpmult = WATER_WAVE_STRENGTH;
			bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);

			#if WATER_INTERACTION == 1
				// nice little wave effect when leaving water
				vec3 waterPlayerPostion = waterExitedPosition;
				float waterTime = waterExitedTime;
				vec3 playerVelocity = waterExitedVelocity;
				if (isEyeInWater == 1) {
					waterPlayerPostion = waterEnteredPosition;
				 	waterTime = waterEnteredTime;
					playerVelocity = waterEnteredVelocity;
				}

				float distFromWaterPos = length(worldPos - waterPlayerPostion);
				float maxWaveDist = 3.5;
				if (distFromWaterPos < maxWaveDist) {
					float newTime = frameTimeCounter - waterTime;
					newTime *= 2.15;

					float smoothDistFromWaterPos = smoothstep(maxWaveDist, 0.0, distFromWaterPos);
					float waveWidth = 0.2;
					float waveHeight = 0.3 * smoothstep(2.0, 20.0, length(playerVelocity)) + 0.5;

					float enterWave = waveHeight * smoothstep(newTime - waveWidth, newTime, distFromWaterPos-0.1) * smoothstep(newTime + waveWidth, newTime, distFromWaterPos-0.1) * smoothDistFromWaterPos;
			
					bump.y = enterWave + (1.0 - enterWave) * bump.y;
				}
			
			#elif WATER_INTERACTION == 2

				#ifdef PIXELATED_WAVES
					#if WATER_SIM_SCALE == 0
						const float NORMAL_SCALE = 20.0;
					#elif WATER_SIM_SCALE == 1
						const float NORMAL_SCALE = 40.0;
					#else
						const float NORMAL_SCALE = 80.0;
					#endif

					ivec2 normalSize = imageSize(waveSim2);
					vec2 centeredUV = (worldPos.xz - previousCameraPositionWave2.xz) * NORMAL_SCALE;
					centeredUV += normalSize * 0.5;

					if(centeredUV.x < normalSize.x && centeredUV.x > 0.0 && centeredUV.y < normalSize.y && centeredUV.y > 0.0 && abs(worldSpaceNormal.y) > 0.5 && !noSimOngoing) {
						vec4 waves = imageLoad(waveSim2, ivec2(centeredUV));
				#else
					#if WATER_SIM_DISTANCE == 1
						const float NORMAL_SCALE = 0.04;
					#elif WATER_SIM_DISTANCE == 2
						const float NORMAL_SCALE = 0.02;
					#elif WATER_SIM_DISTANCE == 3
						const float NORMAL_SCALE = 0.015;
					#else
						const float NORMAL_SCALE = 0.01;
					#endif

					vec2 waveUV = (worldPos.xz - previousCameraPositionWave2.xz) * NORMAL_SCALE;
					if(length(waveUV) < 0.5 && abs(worldSpaceNormal.y) > 0.5 && !noSimOngoing) {
						vec4 waves = texture(waveSim2Sampler, waveUV+0.5);
				#endif
						vec3 waveNormals = normalize(vec3(waves.z, waves.w, 1.0));
						bump = mix(bump, waveNormals, clamp(WATER_SIM_STRENGTH*sqrt(sqrt(abs(waves.x))), 0.0, 1.0));
						bump = normalize(bump);
					}
			#endif

			NormalTex.xyz = bump;
		}
	#endif

	// tangent space normals for refraction
	vec2 TangentNormal = NormalTex.xy;
	
	#if defined PHYSICSMOD_OCEAN_SHADER && defined PHYSICS_OCEAN
		rippleBump *= physics_localWaviness;
		float bumpmult = mix(isWater ? 1.0 : NORMAL_MAP_MULT, isWater ? PHYSICS_OCEAN_TRANSITION : NORMAL_MAP_MULT, smoothstep(0.0, 0.1, physics_localWaviness));

		normal = applyBump(tbnMatrix, NormalTex.xyz, bumpmult, rippleBump);
	#else
		normal = applyBump(tbnMatrix, NormalTex.xyz, isWater ? 1.0 : NORMAL_MAP_MULT, rippleBump);
	#endif

	worldSpaceNormal = viewToWorld(normal);
	
	#if defined PHYSICSMOD_OCEAN_SHADER && defined PHYSICS_OCEAN
		if (isWater) TangentNormal = mix(NormalTex.xy, normalize(wave.normal).xz, smoothstep(0.0, 0.1, physics_localWaviness));
	#endif

	gl_FragData[2].r = encodeVec2(TangentNormal*0.5+0.5);

	vec4 blockBreak = texelFetch(colortex11, ivec2(gl_FragCoord.xy), 0);

	if(blockBreak.a > 0.99) {
		gl_FragData[2].gba = blockBreak.gba;
	} else {
		#if defined ENTITIES && defined IS_IRIS
			float nameTagMask = 0.0;
			if(NAMETAG > 0) nameTagMask = 1.0;
		#else
			const float nameTagMask = 0.0;
		#endif

		gl_FragData[2].gba = vec3(encodeVec2(GLASS_TINT_COLORS.rg), encodeVec2(GLASS_TINT_COLORS.ba), nameTagMask);
	}

////////////////////////////////////////////////////////////////////////////////
//////////////////////////////// SPECULARS /////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

	vec3 SpecularTex = texture(specular, lmtexcoord.xy, mipmapBias).rga;
	
////////////////////////////////////////////////////////////////////////////////
//////////////////////////////// DIFFUSE LIGHTING //////////////////////////////
////////////////////////////////////////////////////////////////////////////////

	// lightmap.y = 1.0;
	
	#ifndef OVERWORLD_SHADER
		lightmap.y = 1.0;
	#endif
	
	#if defined Hand_Held_lights && !defined LPV_ENABLED
		#ifdef IS_IRIS
			vec3 playerCamPos = cameraPosition - relativeEyePosition;
		#else
			vec3 playerCamPos = cameraPosition;
		#endif
		
		if(heldItemId > 999 || heldItemId2 > 999){ 
			float pointLight = clamp(1.0-length((worldPos)-playerCamPos)/HANDHELD_LIGHT_RANGE,0.0,1.0);
			lightmap.x  = mix(lightmap.x , 0.9, pointLight*pointLight);
		}

	#endif

	vec3 Indirect_lighting = vec3(0.0);
	vec3 MinimumLightColor = vec3(1.0);

	vec3 Direct_lighting = vec3(0.0);

	#ifdef OVERWORLD_SHADER
		vec3 DirectLightColor = lightSourceColorSSBO/2400.0;
		vec3 AmbientLightColor = averageSkyCol_CloudsSSBO/900.0;

		#ifdef USE_CUSTOM_DIFFUSE_LIGHTING_COLORS
			DirectLightColor = luma(DirectLightColor) * vec3(DIRECTLIGHT_DIFFUSE_R,DIRECTLIGHT_DIFFUSE_G,DIRECTLIGHT_DIFFUSE_B);
			AmbientLightColor = luma(AmbientLightColor) * vec3(INDIRECTLIGHT_DIFFUSE_R,INDIRECTLIGHT_DIFFUSE_G,INDIRECTLIGHT_DIFFUSE_B);
		#endif
		
		if(!isWater && isEyeInWater == 1){
			float distanceFromWaterSurface = cameraPosition.y - waterEnteredAltitude;
			float waterdepth = max(-(feetPlayerPos.y + distanceFromWaterSurface),0.0);

			DirectLightColor *= exp(-vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B) * (waterdepth/abs(WsunVec.y)));
			DirectLightColor *= pow(waterCaustics(worldPos, WsunVec, -(feetPlayerPos.y + distanceFromWaterSurface))*WATER_CAUSTICS_BRIGHTNESS, WATER_CAUSTICS_POWER);
		}

		float NdotL = clamp((-15 + dot(normal, normalize(WsunVec*mat3(gbufferModelViewInverse)))*255.0) / 240.0  ,0.0,1.0);
		float Shadows = 1.0;

		float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(feetPlayerPos) / (shadowDistance+16),0.0)*5.0,1.0));
		float shadowMapFalloff2 = smoothstep(0.0, 1.0, min(max(1.0 - length(feetPlayerPos) / shadowDistance,0.0)*5.0,1.0));

		float LM_shadowMapFallback = min(max(lightmap.y-0.8, 0.0) * 25,1.0);

		Shadows = ComputeShadowMap(DirectLightColor, shadowPlayerPos, shadowMapFalloff, BN, geoNormals);

		// Shadows = mix(LM_shadowMapFallback, Shadows, shadowMapFalloff2);
		Shadows *= mix(LM_shadowMapFallback,1.0,shadowMapFalloff2);

		Shadows *= GetCloudShadow(worldPos, WsunVec);


		Direct_lighting = DirectLightColor * NdotL * Shadows;

		vec3 indirectNormal = worldSpaceNormal / dot(abs(worldSpaceNormal),vec3(1.0));
		float SkylightDir = clamp(indirectNormal.y*0.7+0.3,0.0,1.0);

		float skylight = mix(0.2 + 2.3*(1.0-lightmap.y), 2.5, SkylightDir)/2.5;
		AmbientLightColor *= skylight;

		Indirect_lighting = doIndirectLighting(AmbientLightColor, MinimumLightColor, clamp(lightmap.y, 0.0, 1.0));
	#endif

	#ifdef NETHER_SHADER
		Indirect_lighting = volumetricsFromTex(worldSpaceNormal, colortex4, 0).rgb / 1200.0 / 1.5;
	#endif

	#ifdef END_SHADER

		#ifdef END_LIGHTNING
			float vortexBounds = clamp(vortexBoundRange - length(feetPlayerPos+cameraPosition), 0.0,1.0);
		#else
			float vortexBounds = 1.0;
		#endif

        vec3 lightPos = LightSourcePosition(worldPos, cameraPosition,vortexBounds);

		float lightningflash = texelFetch(colortex4,ivec2(1,1),0).x/150.0;
		vec3 lightColors = LightSourceColors(vortexBounds, lightningflash);
		
		float end_NdotL = clamp(dot(worldSpaceNormal, normalize(-lightPos))*0.5+0.5,0.0,1.0);
		end_NdotL *= end_NdotL;

		float fogShadow = GetEndFogShadow(worldPos, lightPos);
		float endPhase = endFogPhase(lightPos);

		Direct_lighting = lightColors * endPhase * end_NdotL * fogShadow;

		#ifdef END_ISLAND_LIGHT
			vec3 WsunVec = normalize(vec3(END_LIGHT_POS)-(feetPlayerPos+cameraPosition));
			vec3 DirectLightColor = vec3(VORTEX_LIGHT_COL_R,VORTEX_LIGHT_COL_G,VORTEX_LIGHT_COL_B);

			float NdotL = clamp((-15 + dot(normal, normalize(WsunVec*mat3(gbufferModelViewInverse)))*255.0) / 240.0  ,0.0,1.0);
			float Shadows = 1.0;

			float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(feetPlayerPos) / (shadowDistance+16),0.0)*5.0,1.0));
			float shadowMapFalloff2 = smoothstep(0.0, 1.0, min(max(1.0 - length(feetPlayerPos) / shadowDistance,0.0)*5.0,1.0));

			float LM_shadowMapFallback = min(max(lightmap.y-0.8, 0.0) * 25,1.0);

			Shadows = ComputeShadowMap(DirectLightColor, shadowPlayerPos, shadowMapFalloff, BN, geoNormals);

			// Shadows = mix(LM_shadowMapFallback, Shadows, shadowMapFalloff2);
			Shadows *= mix(LM_shadowMapFallback,1.0,shadowMapFalloff2);

			Direct_lighting = DirectLightColor * NdotL * Shadows;
		#endif

		vec3 AmbientLightColor = vec3(AmbientLightEnd_R,AmbientLightEnd_G,AmbientLightEnd_B) ;
			
		Indirect_lighting = AmbientLightColor + 0.7 * AmbientLightColor * clamp(dot(worldSpaceNormal, normalize(feetPlayerPos)), -1.0, 1.0);
		Indirect_lighting *= 0.1;
	#endif

	///////////////////////// BLOCKLIGHT LIGHTING OR LPV LIGHTING OR FLOODFILL COLORED LIGHTING
	vec3 flatWorldNormal = viewToWorld(normalMat.xyz).xyz;
	#ifdef IS_LPV_ENABLED
		vec3 normalOffset = vec3(0.0);

		if (any(greaterThan(abs(flatWorldNormal), vec3(1.0e-6))))
			normalOffset = 0.5*worldSpaceNormal;

		#if LPV_NORMAL_STRENGTH > 0
			if (any(greaterThan(abs(normal), vec3(1.0e-6)))) {
				vec3 texNormalOffset = -normalOffset + worldSpaceNormal;
				normalOffset = mix(normalOffset, texNormalOffset, (LPV_NORMAL_STRENGTH*0.01));
			}
		#endif

		vec3 lpvPos = GetLpvPosition(feetPlayerPos) + normalOffset;
	#else
		const vec3 lpvPos = vec3(0.0);
	#endif

	#ifdef LIGHTNING
		vec3 lightColor = vec3(1.0);
		gl_FragData[0].a = max(gl_FragData[0].a, 1.0/255.0);
	#else
		vec3 lightColor = vec3(TORCH_R,TORCH_G,TORCH_B);
	#endif

	#ifdef MAIN_SHADOW_PASS
		Indirect_lighting += doBlockLightLighting(lightColor, lightmap.x, feetPlayerPos, lpvPos, viewPos, false, BN, worldSpaceNormal, false);
	#else
		Indirect_lighting += doBlockLightLighting(lightColor, lightmap.x, feetPlayerPos, lpvPos);
	#endif
	
	vec4 flashLightSpecularData = vec4(0.0);
	#ifdef FLASHLIGHT
		#if defined FLASHLIGHT_SHADOWS && defined MAIN_SHADOW_PASS && !defined HAND && defined MAIN_SHADOW_PASS
			vec3 newViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
			float flashlightshadows = SSRT_FlashLight_Shadows(viewPos, false, -newViewPos, BN, worldSpaceNormal, false);
		#else
			const float flashlightshadows = 1.0;
		#endif
		Indirect_lighting += flashlightshadows * calculateFlashlight(FragCoord.xy*texelSize/RENDER_SCALE, viewPos, vec3(0.0), worldSpaceNormal, flashLightSpecularData, false);
	#endif

	vec3 FinalColor = (Indirect_lighting + Direct_lighting) * Albedo;

	#if EMISSIVE_TYPE == 2 || EMISSIVE_TYPE == 3
		Emission(FinalColor, Albedo, SpecularTex.b);
	#endif

////////////////////////////////////////////////////////////////////////////////
//////////////////////////////// SPECULAR LIGHTING /////////////////////////////
////////////////////////////////////////////////////////////////////////////////

	#ifdef LIGHTNING
		#undef FORWARD_SPECULAR
	#endif

	#if defined FORWARD_SPECULAR

		float harcodedF0 = 0.02;
		
		// if nothing is chosen, no smoothness and no reflectance
		vec2 specularValues = vec2(1.0, 0.0); 

		
		// hardcode specular values for select blocks like glass, water, and slime
		if(isReflective) specularValues = vec2(1.0, harcodedF0);

		// detect if the specular texture is used, if it is, overwrite hardcoded values
		if(SpecularTex.r > 0.0 && SpecularTex.g <= 1.0) specularValues = SpecularTex.rg;
		
		float f0 = isReflective ? max(specularValues.g, harcodedF0) : specularValues.g;
		bool isHand = false;

		#ifdef HAND
			isHand = true;
			f0 = max(specularValues.g, harcodedF0);
		#endif
		
		float roughness = specularValues.r; 

		if(UnchangedAlpha <= 0.0 && !isReflective) f0 = 0.0;

		if (f0 > 0.0){
			if(isReflective) f0 = max(f0, harcodedF0);
			
			float reflectance = 0.0;

			#if !defined OVERWORLD_SHADER
				vec3 sunVec = vec3(0.0);
				vec3 DirectLightColor = sunVec;
				float Shadows = 0.0;
			#else
				vec3 sunVec = WsunVec;
			#endif
			
			vec3 specularReflections = specularReflections(viewPos, shadowPlayerPos, normalize(feetPlayerPos), sunVec, vec2(BN, interleaved_gradientNoise_temporal()), flatWorldNormal, worldSpaceNormal, roughness, f0, Albedo, FinalColor*gl_FragData[0].a, DirectLightColor * Shadows * Shadows, lightmap.y, isHand, isWater, reflectance, flashLightSpecularData);
			
			gl_FragData[0].a = gl_FragData[0].a + (1.0-gl_FragData[0].a) * reflectance;
		
			// invert the alpha blending darkening on the color so you can interpolate between diffuse and specular and keep buffer blending
			gl_FragData[0].rgb = clamp(specularReflections / gl_FragData[0].a * 0.1,0.0,65000.0);
			
		}else{
			gl_FragData[0].rgb = clamp(FinalColor * 0.1,0.0,65000.0);
		}
	#else
		gl_FragData[0].rgb = FinalColor*0.1;
	#endif

	#if defined ENTITIES && !defined COLORWHEEL
		// do not allow specular to be very visible in these regions on entities
		// this helps with specular on slimes, and entities with skin overlays like piglins/players
    	if (!gl_FrontFacing) {
			gl_FragData[0] = vec4(FinalColor*0.1, UnchangedAlpha);
		}
	#endif
	
	#if defined DISTANT_HORIZONS && defined DH_OVERDRAW_PREVENTION && !defined HAND && !defined NETHER_SHADER
		#if OVERDRAW_MAX_DISTANCE == 0
			float maxOverdrawDistance = far;
		#else
			float maxOverdrawDistance = OVERDRAW_MAX_DISTANCE;
		#endif
	 
		bool WATER = texelFetch(colortex7, ivec2(gl_FragCoord.xy), 0).a > 0.0 && length(feetPlayerPos) > clamp(far-16.0*4.0, 16.0, maxOverdrawDistance) && texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).x >= 1.0;

		if(WATER && isWater) {
			gl_FragData[0].a = 0.0;
			MATERIALS = 0.0;
		}
	#endif

	if(gl_FragData[0].a == 0.0) discard;

	gl_FragData[1] = vec4(Albedo, MATERIALS);

	#if DEBUG_VIEW == debug_DH_WATER_BLENDING
		if(gl_FragCoord.x*texelSize.x < 0.47) gl_FragData[0] = vec4(0.0);
	#endif
	#if DEBUG_VIEW == debug_NORMALS
		gl_FragData[0].rgb = worldSpaceNormal.xyz * 0.1;
		gl_FragData[0].a = 1.0;
	#endif
	#if DEBUG_VIEW == debug_INDIRECT
		gl_FragData[0].rgb = Indirect_lighting * 0.1;
	#endif
	#if DEBUG_VIEW == debug_DIRECT
		gl_FragData[0].rgb = Direct_lighting * 0.1;
	#endif

	gl_FragData[3] = vec4(1, 1, encodeVec2(lightmap.x, lightmap.y), 1);

	#if defined ENTITIES && defined IS_IRIS && !defined COLORWHEEL
		if(NAMETAG > 0) {
			//  WHY DO THEY HAVE TO AHVE LIGHTING AAAAAAUGHAUHGUAHG
			#ifndef OVERWORLD_SHADER
				lightmap.y = 0.0;
			#endif
			
			vec3 nameTagLighting = Albedo.rgb * max(max(lightmap.y*lightmap.y*lightmap.y , lightmap.x*lightmap.x*lightmap.x), 0.025);
			
			// in vanilla they have a special blending mode/no blending, or something. i cannot change the buffer blend mode without changing the rest of the entities :/
			gl_FragData[0] = vec4(nameTagLighting.rgb * 0.1, UnchangedAlpha  * 0.75);
		}
	#endif
}
}