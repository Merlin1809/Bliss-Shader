#include "/lib/settings.glsl"

#include "/lib/SSBOs.glsl"

#ifdef CUSTOM_MOON_ROTATION
	uniform sampler2D CoronaTex;
#endif

// #if defined END_SHADER || defined NETHER_SHADER
// 	#undef IS_LPV_ENABLED
// #endifs

#ifdef IS_LPV_ENABLED
	#extension GL_ARB_shader_image_load_store: enable
	#extension GL_ARB_shading_language_packing: enable
#endif

#include "/lib/util.glsl"
#include "/lib/res_params.glsl"

#define diagonal3_old(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define projMAD_old(m, v) (diagonal3_old(m) * (v) + (m)[3].xyz)

const bool colortex5MipmapEnabled = true;
uniform float nightVision;
uniform float frameTimeCounter;
uniform float rainStrength;
#define PHOTONICS_LIGHT_PASS

#if defined OVERWORLD_SHADER || (defined END_ISLAND_LIGHT && defined END_SHADER)
	const bool shadowHardwareFiltering = true;
	uniform sampler2DShadow shadowtex0HW;

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		uniform sampler2D shadowcolor0;
		uniform sampler2DShadow shadowtex1HW;
	#endif

	#if ShaderSnow > 0
		uniform sampler2D snowTexA;
		uniform sampler2D snowTexN;
	#endif
	#if ShaderSnow > 0 || PUDDLE_MODE > 0
		uniform sampler2D snowTexR;
	#endif

	#if defined RIPPLE_PUDDLES && PUDDLE_MODE > 0
		#include "/lib/ripples.glsl"
		uniform float rippleAmount;
	#endif

	#include "/lib/stars.glsl"

	#ifdef REALMOON
		uniform sampler2D moon;
		#ifdef MOON_NORMALS
			uniform sampler2D moonN;
		#endif
	#endif

	#if SUN_SPECULAR_MULT != 0
		#define LIGHTSOURCE_REFLECTION
	#endif
	
	#include "/lib/lightning_stuff.glsl"
#endif

#ifdef NETHER_SHADER
	const bool colortex4MipmapEnabled = true;
	uniform vec3 lightningEffect;
	#undef LIGHTSOURCE_REFLECTION
#endif

#ifdef END_SHADER
	uniform float worldTimeSmooth;
	#ifndef END_ISLAND_LIGHT
		uniform vec3 lightningEffect;	
		#include "/lib/stars.glsl"
	#endif
	
	#undef LIGHTSOURCE_REFLECTION
#endif

uniform int hideGUI;
uniform sampler2D noisetex; //noise
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

#ifdef DISTANT_HORIZONS
	uniform sampler2D dhDepthTex;
	uniform sampler2D dhDepthTex1;
	#define dhVoxyDepthTex dhDepthTex
	#define dhVoxyDepthTex1 dhDepthTex1
#endif

#ifdef VOXY
	uniform sampler2D vxDepthTexOpaque;
	uniform sampler2D vxDepthTexTrans;
	#define dhVoxyDepthTex vxDepthTexTrans
	#define dhVoxyDepthTex1 vxDepthTexOpaque
#endif

uniform sampler2D colortex0; //clouds
uniform sampler2D colortex1; //albedo(rgb),material(alpha) RGBA16
uniform sampler2D colortex2; //translucents(rgba)
uniform sampler2D colortex3; //filtered shadowmap(VPS)
uniform sampler2D colortex4; //LUT(rgb), quarter res depth(alpha)
uniform sampler2D colortex5; //TAA buffer/previous frame
uniform sampler2D colortex6; //Noise
uniform sampler2D colortex7; //water?
uniform sampler2D colortex8; //Specular
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex15;
uniform sampler2D colortex17;
uniform sampler2D colortex18;

in DATA {
	flat vec2 TAA_Offset;

	#if !defined END_ISLAND_LIGHT || !defined END_SHADER
		flat vec3 WsunVec;
	#endif
	flat vec3 unsigned_WsunVec;
	flat vec3 WmoonVec;
};


uniform float sunElevation;

#if defined IS_LPV_ENABLED || defined PHOTONICS
	uniform usampler1D texBlockData;
	uniform sampler3D texLpv1;
	uniform sampler3D texLpv2;
#endif

uniform mat4 gbufferPreviousModelView;

// uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float updateFadeTime;
// uniform float centerDepthSmooth;
uniform bool firstPersonCamera;

// uniform float far;
uniform float near;
uniform float farPlane;
uniform float dhVoxyFarPlane;
uniform float dhVoxyNearPlane;

uniform vec2 texelSize;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;

uniform float eyeAltitude;
uniform int frameCounter;

uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;

uniform vec3 sunVec;

#define VOXEL_REFLECTIONS_SOLID

#ifdef VOXEL_REFLECTIONS_SOLID
	#define VOXEL_REFLECTIONS
#endif

#ifdef PHOTONICS
	#define PHOTONICS_INCLUDED

	#include "/photonics/photonics.glsl"
#endif



#if defined IS_LPV_ENABLED || defined PHOTONICS && defined PHOTONICS && !defined PH_ENABLE_HANDHELD_LIGHT
	uniform int heldItemId;
	uniform int heldItemId2;
#endif

uniform float waterEnteredAltitude;

void convertHandDepth(inout float depth) {
    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;
    depth = ndcDepth * 0.5 + 0.5;
}

float convertHandDepth_2(in float depth, bool hand) {
	if(!hand) return depth;

    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;
    return ndcDepth * 0.5 + 0.5;
}

#include "/lib/projections.glsl"
#include "/lib/DistantHorizons_projections.glsl"
#include "/lib/color_transforms.glsl"
#include "/lib/waterBump.glsl"
#include "/lib/Shadow_Params.glsl"
#include "/lib/Shadows.glsl"
#include "/lib/sky_gradient.glsl"

#ifdef OVERWORLD_SHADER

	#include "/lib/scene_controller.glsl"
	
	#define CLOUDSHADOWSONLY
	#include "/lib/volumetricClouds.glsl"
#endif


#if defined IS_LPV_ENABLED || defined PHOTONICS && defined PHOTONICS && !defined PH_ENABLE_HANDHELD_LIGHT
	uniform vec3 relativeEyePosition;

	#include "/lib/hsv.glsl"
	#include "/lib/lpv_common.glsl"
	#include "/lib/lpv_render.glsl"
	#include "/lib/blocks.glsl"
	#include "/lib/lpv_blocks.glsl"
#endif

#define DEFERRED_SPECULAR
#define DEFERRED_SSR_QUALITY 30 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 200 300 400 500]
#define DEFERRED_BACKGROUND_REFLECTION
#define DEFERRED_ROUGH_REFLECTION

#ifdef DEFERRED_SPECULAR
#endif
#if DEFERRED_SSR_QUALITY > -1
#endif
#ifdef DEFERRED_BACKGROUND_REFLECTION
#endif
#ifdef DEFERRED_ROUGH_REFLECTION
#endif

#ifndef DEFERRED_ROUGH_REFLECTION
	#undef DENOISED_REFLECTIONS
#endif

#define MAIN_SHADOW_PASS
#define FULLRESDEPTH

vec2 decodeVec2(float a){
    const vec2 constant1 = 65535. / vec2( 256., 65536.);
    const float constant2 = 256. / 255.;
    return fract( a * constant1 ) * constant2 ;
}

#if defined VIVECRAFT
	uniform bool vivecraftIsVR;
	uniform vec3 vivecraftRelativeMainHandPos;
	uniform vec3 vivecraftRelativeOffHandPos;
	uniform mat4 vivecraftRelativeMainHandRot;
	uniform mat4 vivecraftRelativeOffHandRot;
#endif

#include "/lib/diffuse_lighting.glsl"
#include "/lib/specular.glsl"

#ifdef END_SHADER
#include "/lib/end_fog.glsl"
#endif

float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}

vec3 decode (vec2 encn){
    vec3 n = vec3(0.0);
    encn = encn * 2.0 - 1.0;
    n.xy = abs(encn);
    n.z = 1.0 - n.x - n.y;
    n.xy = n.z <= 0.0 ? (1.0 - n.yx) * sign(encn) : encn;
    return clamp(normalize(n.xyz),-1.0,1.0);
}

float DH_ld(float dist) {
    return (2.0 * dhVoxyNearPlane) / (dhVoxyFarPlane + dhVoxyNearPlane - dist * (dhVoxyFarPlane - dhVoxyNearPlane));
}

float DH_inv_ld (float lindepth){
	return -((2.0*dhVoxyNearPlane/lindepth)-dhVoxyFarPlane-dhVoxyNearPlane)/(dhVoxyFarPlane-dhVoxyNearPlane);
}

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
    return (near * far) / (depth * (near - far) + far);
	// return (2.0 * near) / (far + near - depth * (far - near));
}

float invertlinearDepthFast(const in float depth, const in float near, const in float far) {
	return ((2.0*near/depth)-far-near)/(far-near);
}


float triangularize(float dither)
{
    float center = dither*2.0-1.0;
    dither = center*inversesqrt(abs(center));
    return clamp(dither-fsign(center),0.0,1.0);
}

vec3 fp10Dither(vec3 color,float dither){
	const vec3 mantissaBits = vec3(6.,6.,5.);
	vec3 exponent = floor(log2(color));
	return color + dither*exp2(-mantissaBits)*exp2(exponent);
}

float interleaved_gradientNoise_temporal(){
	// #ifdef TAA
	// 	return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887 * frameCounter);
	// #else
	// 	return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887);
	// #endif

	vec2 coord = gl_FragCoord.xy;
	#ifdef TAA
		coord += (frameCounter%40000) * 2.0;
	#endif

	return fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y ) + 1.0/1.6180339887);
}

float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}

float R2_dither(){
	vec2 coord = gl_FragCoord.xy ;

	#ifdef TAA
		coord += (frameCounter%40000) * 2.0;
	#endif
	
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * coord.x + alpha.y * coord.y ) ;
}

float R2_dither2(){
	vec2 coord = gl_FragCoord.xy ;

	#ifdef TAA
		coord += (frameCounter*8)%40000;
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

vec4 blueNoise(vec2 coord){
  return texelFetch(colortex6, ivec2(coord)%512 , 0) ;
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
    pos = gbufferModelViewInverse * pos;
    return pos.xyz;
}

vec3 worldToView(vec3 worldPos) {
    vec4 pos = vec4(worldPos, 0.0);
    pos = gbufferModelView * pos;
    return pos.xyz;
}

float swapperlinZ(float depth, float _near, float _far) {
    return (2.0 * _near) / (_far + _near - depth * (_far - _near));
	// l = (2*n)/(f+n-d(f-n))
	// f+n-d(f-n) = 2n/l
	// -d(f-n) = ((2n/l)-f-n)
	// d = -((2n/l)-f-n)/(f-n)

}

// vec2 SSRT_Shadows(vec3 viewPos, bool depthCheck, vec3 lightDir, float noise, bool isSSS, bool hand){
	

// 	float handSwitch = hand ? 1.0 : 0.0;

//     float steps = 16.0;
// 	float Shadow = 1.0; 
// 	float SSS = 0.0;
// 	// isSSS = true;

// 	float _near = near; float _far = far*4.0;

// 	if (depthCheck) {
// 		_near = dhVoxyNearPlane;
// 		_far = dhVoxyFarPlane;
// 	}
    

// 	vec3 clipPosition = toClipSpace3_DH(viewPos, depthCheck);
// 	//prevents the ray from going behind the camera
// 	float rayLength = ((viewPos.z + lightDir.z * _far*sqrt(3.)) > -_near) ?
//       				  (-_near -viewPos.z) / lightDir.z : _far*sqrt(3.);

//     vec3 direction = toClipSpace3_DH(viewPos + lightDir*rayLength, depthCheck) - clipPosition;  //convert to clip space

//     direction.xyz = direction.xyz / max(abs(direction.x)/0.0005, abs(direction.y)/0.0005);	//fixed step size

// 	// float Stepmult = depthCheck ? (isSSS ? 1.0 : 3.0) : (isSSS ? 1.0 : 3.0);
// 	float Stepmult = isSSS ? 3.0 : 6.0;

//     vec3 rayDir = direction * Stepmult * vec3(RENDER_SCALE,1.0);
// 	vec3 screenPos = clipPosition * vec3(RENDER_SCALE,1.0) + rayDir*noise - (isSSS ? rayDir*0.9 : vec3(0.0));

// 	float minZ = screenPos.z - 1.0;
// 	float maxZ = screenPos.z;

// 	// as distance increases, add larger values to the SSS value. this scales the "density" with distance, as far things should appear denser.
// 	float dist = 1.0 + length(mat3(gbufferModelViewInverse) * viewPos) / 500.0;

// 	for (int i = 0; i < int(steps); i++) {
		
// 		float samplePos = convertHandDepth_2(texture(depthtex1, screenPos.xy).x, hand);
		
// 		#ifdef DISTANT_HORIZONS
// 			if(depthCheck) samplePos = texture(dhDepthTex1, screenPos.xy).x;
// 		#endif

// 		if(samplePos < screenPos.z && (samplePos <= max(minZ,maxZ) && samplePos >= min(minZ,maxZ))){
// 			vec2 linearZ = vec2(swapperlinZ(screenPos.z, _near, _far), swapperlinZ(samplePos, _near, _far));
// 			float calcthreshold = abs(linearZ.x - linearZ.y) / linearZ.x;

// 			if (calcthreshold < 0.035) Shadow = 0.0;
// 			SSS += dist;
// 		} 
		
// 		minZ = maxZ - (isSSS ? 1.0 : 0.0001) / swapperlinZ(samplePos, _near, _far);
// 		maxZ += rayDir.z;

// 		screenPos += rayDir;
// 	}

// 	return vec2(Shadow, SSS / steps);
// }

vec2 SSRT_Shadows(vec3 viewPos, bool depthCheck, vec3 lightDir, float noise, bool isSSS, bool hand){

	// return 1.0;

	float shadows = 1.0;
	float samples = 16.0;
	float SSS = 0.0;

	float _near = near; float _far = far*4.0;
	
	#if defined DISTANT_HORIZONS || defined VOXY
	if (depthCheck) {
		_near = dhVoxyNearPlane;
		_far = dhVoxyFarPlane;
	}
	#endif
    
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
	newPos += direction*0.3;

	float SSSdistanceScale = 1.0 / (1.0 + swapperlinZ(position.z, _near, _far)*32.0);
	float distanceScale2 = 1.0 + length(mat3(gbufferModelViewInverse) * viewPos) / 150.0;

	for (int i = 0; i < int(samples); i++) { 
		if (newPos.x < 0.0 || newPos.y < 0.0 || newPos.x > 1.0 || newPos.y > 1.0) break;
		float sampleDepth = 0.0;
		
		#if defined DISTANT_HORIZONS || defined VOXY
		if(depthCheck) {
			sampleDepth = texelFetch(dhVoxyDepthTex1, ivec2(newPos.xy/texelSize),0).x;
		} else
		#endif
		{	
			if(hand) {
				sampleDepth = texelFetch(depthtex1, ivec2(newPos.xy/texelSize),0).x;
				convertHandDepth(sampleDepth);
			} else {
				sampleDepth = texelFetch(depthtex2, ivec2(newPos.xy/texelSize),0).x;
			}
		}

		if(sampleDepth < newPos.z){
			float linearCurrentPos = swapperlinZ(newPos.z, _near, _far);
			float linearSampledDepth = swapperlinZ(sampleDepth, _near, _far);

			float dist = abs(linearSampledDepth - linearCurrentPos) / linearCurrentPos;
			
			// if (dist < 0.035){
			if (dist < 0.035/(1.0+linearCurrentPos)) shadows = 0.0;

			// if (dist < 0.3/(1.0+linearCurrentPos)) SSS += distanceScale2;
			if (dist < SSSdistanceScale) SSS += distanceScale2;
		}

		newPos += direction;
		
	}
	return vec2(shadows, SSS / samples );
}

#if defined FLASHLIGHT_SHADOWS && defined FLASHLIGHT
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

void Emission(
	inout vec3 Lighting,
	vec3 Albedo,
	float Emission
){
	if( Emission < 254.5/255.0) Lighting = mix(Lighting, Albedo * 5.0 * Emissive_Brightness, pow(Emission, Emissive_Curve));
}

#include "/lib/indirect_lighting_effects.glsl"
#include "/lib/PhotonGTAO.glsl"

void doEdgeAwareBlur(
	sampler2D tex1, sampler2D tex2, sampler2D depth,
	float referenceDepth, bool hand,
	inout vec2 ambientEffects, inout vec3 filteredShadow
){
	float threshold = clamp(referenceDepth*referenceDepth*0.5,0.0001,0.005);
	vec3 shadow_RESULT = vec3(0.0);
	vec2 ssao_RESULT = vec2(0.0);
	float edgeSum = 0.0;

	vec2 coord = gl_FragCoord.xy - 1.5;
	ivec2 UV = ivec2(coord);
	ivec2 UV_NOISE = ivec2(gl_FragCoord.xy*texelSize + 1);

	ivec2 OFFSET[4] = ivec2[](
	  ivec2(-1,-1),
	  ivec2( 1, 1),
	  ivec2(-1, 1),
	  ivec2( 1,-1)
	);

	for(int i = 0; i < 4; i++) {
		#if defined DISTANT_HORIZONS || defined VOXY
			float offsetDepth = sqrt(texelFetch(depth, UV + OFFSET[i] + UV_NOISE,0).z);
		#else
			float offsetDepth = ld(convertHandDepth_2(texelFetch(depth, UV + OFFSET[i] + UV_NOISE, 0).r,hand));
		#endif

		float edgeDiff = abs(offsetDepth - referenceDepth) < threshold ? 1.0 : 1e-7;

		#ifdef Variable_Penumbra_Shadows
			shadow_RESULT += texelFetch(tex1, UV + OFFSET[i] + UV_NOISE, 0).rgb*edgeDiff;
		#endif
		#if indirect_effect == SSAO_FILTERED
			ssao_RESULT += texelFetch(tex2, UV + OFFSET[i] + UV_NOISE, 0).rg*edgeDiff;
		#endif

		edgeSum += edgeDiff;
	}
	// sample without an offset with texture filtering to get a slightly blurred sample. make sure to average without skewing the rest of the average.
	filteredShadow = shadow_RESULT/edgeSum * 0.8 + 0.2 * texture(tex1, texelSize*gl_FragCoord.xy).rgb;

	#if indirect_effect == SSAO_FILTERED
		ambientEffects = ssao_RESULT/edgeSum * 0.8 + 0.2 * texture(tex2, texelSize*gl_FragCoord.xy).rg;
	#endif
	#if indirect_effect == SSAO_HQ
		ambientEffects = texture(tex2, texelSize*gl_FragCoord.xy).rg;
	#endif

}

vec4 BilateralUpscale_VLFOG(sampler2D tex, sampler2D depth, float referenceDepth){

	vec4 colorSum = vec4(0.0);
	float edgeSum = 0.0;

	#if defined DISTANT_HORIZONS || defined VOXY
		float threshold = referenceDepth * mix(0.5,  0.05, min(max(0.1 - referenceDepth,0)/0.1,1));
	#else
		float threshold = referenceDepth * 0.05;
	#endif

	#ifdef HQ_CLOUD_UPSAMPLE
		const int samples = 9;
	#else
		const int samples = 5;
	#endif

	vec2 coord = gl_FragCoord.xy - 1.5;
	vec2 UV = coord;
	const ivec2 SCALE = ivec2(1.0/VL_RENDER_SCALE);
	ivec2 UV_DEPTH = ivec2(UV*VL_RENDER_SCALE)*SCALE;
	ivec2 UV_COLOR = ivec2(UV*VL_RENDER_SCALE);
	ivec2 UV_NOISE = ivec2(gl_FragCoord.xy*texelSize + 1);

	ivec2 OFFSET[9] = ivec2[](
		ivec2(-1,-1),
		ivec2( 1, 1),
		ivec2(-1, 1),
		ivec2( 1,-1),
		ivec2( 0, 0),
		ivec2( 0, 1),
		ivec2( 0,-1),
		ivec2( 1, 0),
		ivec2(-1, 0)
  	);

	for(int i = 0; i < samples; i++) {
		#if defined DISTANT_HORIZONS || defined VOXY
			float offsetDepth = sqrt(texelFetch(depth, UV_DEPTH + (OFFSET[i] + UV_NOISE) * SCALE,0).a);
		#else
			float offsetDepth = ld(texelFetch(depth, UV_DEPTH + (OFFSET[i] + UV_NOISE) * SCALE, 0).r);
		#endif

		float edgeDiff = abs(offsetDepth - referenceDepth) < threshold ? 1.0 : 0.0;
		vec4 offsetColor = texelFetch(tex, UV_COLOR + OFFSET[i] + UV_NOISE, 0).rgba;
		colorSum += offsetColor*edgeDiff;
		edgeSum += edgeDiff;
	}

	if (edgeSum == 0.0) return vec4(0.0);
	return colorSum/edgeSum;
}

#if defined OVERWORLD_SHADER || (defined END_ISLAND_LIGHT && defined END_SHADER)

vec3 ComputeShadowMap_COLOR(in vec3 projectedShadowPosition, float distortFactor, float noise, float shadowBlockerDepth, float NdotL, float maxDistFade, vec3 directLightColor, inout float FUNNYSHADOW, inout vec3 tintedSunlight, bool isSSS ,inout float shadowDebug){

	// if(maxDistFade <= 0.0) return 1.0;
	float backface = NdotL <= 0.0 ? 1.0 : 0.0;

	vec3 shadowColor = vec3(0.0);
	vec3 translucentTint = vec3(0.0);

	if (projectedShadowPosition.z > 1.0 || projectedShadowPosition.z < 0.0) return vec3(1.0);

	#ifdef BASIC_SHADOW_FILTER
		int samples = SHADOW_FILTER_SAMPLE_COUNT;
		float rdMul = (shadowBlockerDepth*distortFactor*d0k) * 0.3;
		
		for(int i = 0; i < samples; i++){
			vec2 offsetS = CleanSample(i, samples - 1, noise) * rdMul;
			projectedShadowPosition.xy += offsetS;
	#else
		int samples = 1;
	#endif

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		float opaqueShadow = texture(shadowtex0HW, projectedShadowPosition).x;
		float opaqueShadowT = texture(shadowtex1HW, projectedShadowPosition).x;
		vec4 translucentShadow = texture(shadowcolor0, projectedShadowPosition.xy);

		float shadowAlpha = pow(1.0-pow(1.0-translucentShadow.a,2.0),5.0);
		translucentShadow.rgb = normalize(translucentShadow.rgb*translucentShadow.rgb + 0.0001) * (1.0-shadowAlpha);

		// translucentTint += mix(translucentShadow.rgb * mix(opaqueShadowT, 1.0, backface), vec3(1.0), max(opaqueShadow, backface * (shadowAlpha < 1.0 ? 0.0 : 1.0)));
		// shadowColor += directLightColor * mix(translucentShadow.rgb * opaqueShadowT, vec3(1.0), opaqueShadow);
		shadowColor += mix(translucentShadow.rgb * opaqueShadowT, vec3(1.0), opaqueShadow);
		
		translucentTint += mix(translucentShadow.rgb, vec3(1.0), max(opaqueShadow, backface * (shadowAlpha < 1.0 ? 0.0 : 1.0)));
		FUNNYSHADOW += ((1.0-shadowAlpha) * opaqueShadowT)/samples;
	#else
		// shadowColor += directLightColor * texture(shadowtex0HW, projectedShadowPosition).x;
		shadowColor += vec3(1.0) * texture(shadowtex0HW, projectedShadowPosition).x;
	#endif


	#ifdef BASIC_SHADOW_FILTER
		}
	#endif

	#if DEBUG_VIEW == debug_SHADOWMAP
		shadowDebug = texture(shadowtex0HW, projectedShadowPosition).x;
	#endif
	// #ifdef TRANSLUCENT_COLORED_SHADOWS
	// 	// directLightColor *= mix(vec3(1.0), translucentTint.rgb / samples, maxDistFade);
	// 	tintedSunlight *= translucentTint.rgb / samples;
	// #endif

	return shadowColor.rgb / samples;
	// return mix(directLightColor, shadowColor.rgb / samples, maxDistFade);

}

#endif

float CustomPhase(float LightPos){

	float PhaseCurve = 1.0 - LightPos;
	float Final = exp2(sqrt(PhaseCurve) * -25.0);
	Final += exp(PhaseCurve * -10.0)*0.5;

	return Final;
}

vec3 SubsurfaceScattering_sun(vec3 albedo, float Scattering, float Density, float lightPos, float SS_shadows, float distantSSS, bool hand){
	
	// Density = 1.0;
	Scattering *= sss_density_multiplier;

	float density = 1e-6 + Density * 1.5;
	float scatterDepth = max(1.0 - Scattering/density, 0.0);
	scatterDepth *= exp(-7.0 * (1.0-scatterDepth));
	SS_shadows = exp(-7.0 * SS_shadows)*0.7;

	scatterDepth = scatterDepth * mix(SS_shadows, 1.0, (1.0-SCREENSPACE_DIRECT_SSS_BLENDING) * scatterDepth * distantSSS);

	if(hand) scatterDepth = max(1.0 - Scattering*10.0, 0.0) * SS_shadows;

	vec3 absorbColor = exp(max(luma(albedo) - albedo*vec3(1.0,1.1,1.2), 0.0) * -20.0 * sss_absorbance_multiplier);
	vec3 scatter = scatterDepth * mix(absorbColor, vec3(1.0), scatterDepth);
	
	#if SSS_TYPE == 3
		scatter *= pow(Density, LabSSS_Curve);
	#else
		if(Density < 0.01) scatter = vec3(0.0);
	#endif
	
	scatter *= 1.0 + CustomPhase(lightPos)*20.0;

	return scatter;	
}

vec3 SubsurfaceScattering_sky(vec3 albedo, float Scattering, float Density){
	// Density = 1.0;

	float scatterDepth = pow(Scattering,3.5);
	scatterDepth = 1.0-pow(1.0-scatterDepth,5.0);

	vec3 absorbColor = exp(max(luma(albedo) - albedo*vec3(1.0,1.1,1.2), 0.0) * -20.0 * sss_absorbance_multiplier);
	vec3 scatter = scatterDepth * mix(absorbColor, vec3(1.0), scatterDepth) * pow(Density, LabSSS_Curve);

	// scatter *= 1.0 + exp(-7.0*(-playerPosNormalized.y*0.5+0.5));

	return scatter;
}

uniform float wetnessAmount;
uniform float snowAmount;
uniform float wetness;

#ifdef OVERWORLD_SHADER
	void applyPuddles(
		in vec3 worldPos, in vec3 flatNormals, in float lightmap, in bool eyeInWater, inout vec3 albedo, inout vec3 normals, inout float roughness, inout float f0, in bool isShaderGrass, in float porosity
	){
		/* PUDDLE_MODE
			0 = OFF, NO WETNESS
			1 = puddles + full wetness
			2 = only puddles
			3 = only full wetness
		*/

		float effectStrength = smoothstep(0.85, 1.0, lightmap);
		//float effectStrength = smoothstep(0.85, 1.0, max(lightmap.y-step(1.0,lightmap.x), 0.0));
		vec2 snowCoords = worldPos.xz*0.1;

		#if ShaderSnow > 0 || PUDDLE_MODE > 0
			float snowR = texture(snowTexR, snowCoords).g;
		#endif

		#if PUDDLE_MODE > 0
			if (wetnessAmount > 0.01) {
				float halfWet = min(wetnessAmount,1.0);
				float fullWet = clamp(wetnessAmount - 2.0,0.0,1.0);

				vec2 driprate = vec2(0.0,frameTimeCounter)*0.05;

				vec2 UV = mix(worldPos.xz, worldPos.xy*vec2(2.0, 0.5)+driprate, pow(abs(flatNormals.z),2));
				UV = mix(UV, worldPos.zy*vec2(2.0, 0.5)+driprate, pow(abs(flatNormals.x),2));

				#ifdef SHADER_GRASS
				if(isShaderGrass) UV = worldPos.xz;
				#endif
				
				float noise = texture(noisetex, UV * 0.02).b;

				#if PUDDLE_MODE == 1
					float puddles = max(halfWet - noise,0.0);
					puddles = clamp(halfWet - exp(-25.0 * puddles*puddles*puddles*puddles*puddles*Puddle_Size),0.0,1.0);

					float wetnessStages = max(puddles, fullWet) * lightmap;
					
					fullWet = fullWet + porosity * fullWet;
					float wetnessDarkening = max(puddles, fullWet*0.5) * lightmap;
				#endif

				#if PUDDLE_MODE == 2
					float puddles = max(halfWet - noise,0.0);
					puddles = clamp(halfWet - exp(-25.0 * puddles*puddles*puddles*puddles*puddles*Puddle_Size),0.0,1.0);

					float wetnessStages = puddles * lightmap;
					float wetnessDarkening = min(wetnessStages + porosity * fullWet, 1.0);
				#endif

				#if PUDDLE_MODE == 3
					float puddles = 0.0;
					float wetnessStages = fullWet * lightmap;

					fullWet = fullWet + porosity * fullWet;
					float wetnessDarkening = fullWet*0.5*lightmap;
				#endif				

				wetnessStages *= effectStrength;

				#ifdef SHADER_GRASS
				if(!isShaderGrass)
				#endif
				{
					#ifdef RIPPLE_PUDDLES
						float viewDist = length(worldPos - cameraPosition);
						vec3 rippleNormal = flatNormals;

						if(viewDist < 35 && rainStrength > 0.0 && rippleAmount > 0.01 && snowAmount < 0.01) {
							vec3 ripple = ripples(1.2 * worldPos.xz);
							
							ripple = ripple.xzy;
							rippleNormal = mix(flatNormals, ripple, smoothstep(35., 10., viewDist) * rainStrength * smoothstep(0.0, 1.0, rippleAmount));
						}

						normals = mix(normals, rippleNormal, wetnessStages * clamp(flatNormals.y,0.0,1.0));
					#else
						normals = mix(normals, flatNormals, wetnessStages * clamp(flatNormals.y,0.0,1.0));
					#endif
				}

				roughness = mix(roughness, 0.5*(1.0+snowR), wetnessStages * Puddle_Reflection_Sharpness);

				if(f0 < 229.5/255.0 ) albedo = pow(albedo * (1.0 - 0.08*wetnessDarkening), vec3(1.0 + 0.7*wetnessDarkening));
			}
		#endif

		#if ShaderSnow > 0
			if (snowAmount > 0.01) {
				float minClamp = 0.72;

				#ifdef SHADER_GRASS
				if(isShaderGrass) minClamp = 0.5;
				#endif

				float upnormal = clamp(-(normals / dot(abs(normals),vec3(1.0))).y+clamp(normals.y,minClamp,1.0),0.,1.);
				float snow = clamp(1.0 - 2.*upnormal - (1.0-effectStrength),0.0,1.0);

				if(f0 > 229.5/255.0 || eyeInWater) snow = 0.0;

				vec3 snowA = pow(texture(snowTexA, snowCoords).rgb, vec3(2.0/(ShaderSnowStrength-0.1)));
				#ifdef SHADER_GRASS
				if(!isShaderGrass)
				#endif
				{
				snowA = mix(snowA, vec3(0.8, 0.75, 0.85), 1.0-abs(flatNormals.y));
				}
				vec3 snowN = 2.*texture(snowTexN, snowCoords).rgb - 1.;

				snowN = snowN.xzy;
				
				float omSA = 1.-snowAmount;

				float textureMult = smoothstep(0.1+0.5*omSA, 0.5+0.9*omSA, length(snowA)*snow*snowAmount);

				normals = mix(normals, normalize(snowN), textureMult);
				roughness = mix(roughness, snowR, sqrt(textureMult));
				albedo = mix(albedo, 2.5*snowA, textureMult);

				// let it melt
				roughness = mix(roughness, 0.75*snowR, smoothstep(0.15, 0.7, snowAmount)*smoothstep(1.0, 0.8, snowAmount)*effectStrength); 
			}
		#endif
	}
#endif

//encoding by jodie
float encodeVec2(vec2 a){
    const vec2 constant1 = vec2( 1., 256.) / 65535.;
    vec2 temp = floor( a * 255. );
	return temp.x*constant1.x+temp.y*constant1.y;
}
float encodeVec2(float x,float y){
    return encodeVec2(vec2(x,y));
}

vec2 signNotZero(vec2 v) {
    return step(vec2(0.0), v) * 2.0 - 1.0;
}

vec2 encodeNormal(vec3 n){
	n.xy = n.xy / dot(abs(n), vec3(1.0));
	n.xy = n.z <= 0.0 ? (1.0 - abs(n.yx)) * signNotZero(n.xy) : n.xy;
    vec2 encn = clamp(n.xy * 0.5 + 0.5,0.0,1.0);
	
    return encn;
}

void main() {
		#if defined DEFERRED_SPECULAR && defined DENOISED_REFLECTIONS
		gl_FragData[1] = vec4(0.0);
		gl_FragData[2] = vec4(0.0);
		gl_FragData[3] = vec4(0.0);
		#endif
		vec3 DEBUG = vec3(1.0);

	////// --------------- SETUP STUFF --------------- //////
		vec2 texcoord = (gl_FragCoord.xy*texelSize);
	
		float noise_2 = R2_dither();
		vec2 bnoise = blueNoise(gl_FragCoord.xy).rg;
		float ig_noise = interleaved_gradientNoise_temporal();

		#ifdef TAA
			int seed = frameCounter*8%40000;
		#else
			int seed = 600;
		#endif

		vec2 r2_sequence = R2_samples(seed).xy;
		vec2 BN = fract(r2_sequence + bnoise);
		float noise = BN.y;


		// float z0 = texture(depthtex0,texcoord).x;
		// float z = texture(depthtex1,texcoord).x;
		
		float z0 = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x;
		float z =  texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).x;
		float swappedDepth = z;

		#if defined DISTANT_HORIZONS || defined VOXY
			bool isDHrange = z >= 1.0;

			float DH_mixedLinearZ = sqrt(texelFetch(colortex9,ivec2(gl_FragCoord.xy), 0).z);
			float DH_depth0 = 0.0;
			if(isDHrange) DH_depth0 = texelFetch(dhVoxyDepthTex,ivec2(gl_FragCoord.xy), 0).x;
			float DH_depth1 = texelFetch(dhVoxyDepthTex1,ivec2(gl_FragCoord.xy), 0).x;

			float depthOpaque = z;
			float depthOpaqueL = linearizeDepthFast(depthOpaque, near, farPlane);
			
			float dhDepthOpaque = DH_depth1;
			float dhDepthOpaqueL = linearizeDepthFast(dhDepthOpaque, dhVoxyNearPlane, dhVoxyFarPlane);

			if (isDHrange || (dhDepthOpaqueL < depthOpaqueL && dhDepthOpaque > 0.0)){
				depthOpaque = dhDepthOpaque;
				depthOpaqueL = dhDepthOpaqueL;
			}

			swappedDepth = depthOpaque;
		#else
			const bool isDHrange = false;
			const float DH_depth0 = 0.0;
			const float DH_depth1 = 0.0;
		#endif

		bool eyeInWater = isEyeInWater == 1;
		bool isSky = swappedDepth >= 1.0;

	////// --------------- UNPACK OPAQUE GBUFFERS --------------- //////
	
		vec4 data = texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0);

		vec3 skyboxCol = data.rgb;

		vec4 dataUnpacked0 = vec4(decodeVec2(data.x),decodeVec2(data.y)); // albedo, masks
		vec4 dataUnpacked1 = vec4(decodeVec2(data.z),decodeVec2(data.w)); // normals, lightmaps
		// vec4 dataUnpacked2 = vec4(decodeVec2(data.z),decodeVec2(data.w));

		vec3 albedo = toLinear(vec3(dataUnpacked0.xz,dataUnpacked1.x));
		vec3 normal = decode(dataUnpacked0.yw);
		vec2 lightmap = dataUnpacked1.yz;

		// special curve to give more precision on high/low values of the gradient. this curve will be inverted after sampling and decoding.
		// lightmap = 1.0-pow(1.0-pow(lightmap,vec2(2)),vec2(2));
		// small offset to hide flickering from precision error in the encoding/decoding on values close to 1.0 or 0.0
		lightmap.xy = min(max(lightmap.xy - 0.05,0.0)*1.06,1.0);
		
		#if MC_VERSION < 12109
			#if !defined OVERWORLD_SHADER
				lightmap.y = 1.0;
			#endif
		#else
			#if !defined OVERWORLD_SHADER && !defined END_SHADER
				lightmap.y = 1.0;
			#endif
		#endif

	////// --------------- UNPACK MISC --------------- //////
	
		vec4 SpecularData = texelFetch(colortex8, ivec2(gl_FragCoord.xy), 0);
		vec4 specdataUnpacked0 = vec4(decodeVec2(SpecularData.x),decodeVec2(SpecularData.y));
		vec4 specdataUnpacked1 = vec4(decodeVec2(SpecularData.z),decodeVec2(SpecularData.w));

		vec4 SpecularTex = vec4(specdataUnpacked0.xz, specdataUnpacked1.xz);
		vec3 FlatNormals = normalize(vec3(specdataUnpacked0.yw,specdataUnpacked1.y) * 2.0 - 1.0);
		float vanilla_AO = min(max(specdataUnpacked1.w-0.005,0.0)/0.995,1.0);

		float LabSSS = clamp((-65.0 + SpecularTex.z * 255.0) / 190.0 ,0.0,1.0);

		float labPorosity = SpecularTex.z * 255.0 <= 64.5 ? clamp(SpecularTex.z * 255.0, 0.0, 64.5)/64.5 : 0.0;

		vec3 slopednormal = normal;

		if(isDHrange){
			FlatNormals = normal;
		}


	////// --------------- MASKS/BOOLEANS --------------- //////
		// 1.0-0.8 ???
		// 0.75 = hand mask
		// 0.60 = grass mask
		// 0.55 = leaf mask (for ssao-sss)
		// 0.50 = lightning bolt mask
		// 0.45 = entity mask
		float opaqueMasks = dataUnpacked1.w;
		// 1.0 = water mask
		// 0.9 = entity mask
		// 0.8 = reflective entities
		// 0.7 = reflective blocks
  		float translucentMasks = texelFetch(colortex7, ivec2(gl_FragCoord.xy), 0).a;

		bool isWater = translucentMasks > 0.99;
		// bool isReflectiveEntity = abs(translucentMasks - 0.8) < 0.01;
		// bool isReflective = abs(translucentMasks - 0.7) < 0.01 || isWater || isReflectiveEntity;
		// bool isEntity = abs(translucentMasks - 0.9) < 0.01 || isReflectiveEntity;

		// bool lightningBolt = abs(opaqueMasks-0.5) <0.01;
		// bool isLeaf = abs(opaqueMasks-0.55) <0.01;
		bool entities = abs(opaqueMasks-0.45) < 0.01;	
		bool isGrass = abs(opaqueMasks-0.60) < 0.01;
		bool hand = abs(opaqueMasks-0.75) < 0.01 && z < 1.0;

		#ifdef SHADER_GRASS
			bool isShaderGrass = abs(opaqueMasks-0.80) < 0.01;
		#else
			const bool isShaderGrass = false;
		#endif

		#if defined POM_OFFSET_SHADOW_BIAS
			float POM_DEEPNESS = opaqueMasks < 0.44 ? min(max(opaqueMasks/0.44,0.0)*3.0,1.0) : 0.0;
		#else
			const float POM_DEEPNESS = 0.0;
		#endif
		// bool handwater = abs(translucentMasks-0.3) < 0.01 ;
		bool opaqueParticles = abs(opaqueMasks-0.85) < 0.01;
		bool glowframe = abs(opaqueMasks-0.9) < 0.01;

		if(hand){
			convertHandDepth(z);
			convertHandDepth(z0);
		}

		#if defined DISTANT_HORIZONS || defined VOXY
			vec3 viewPos = toScreenSpace_DH(texcoord/RENDER_SCALE - TAA_Offset*texelSize*0.5, z, DH_depth1);
		#else
			vec3 viewPos = toScreenSpace(vec3(texcoord/RENDER_SCALE - TAA_Offset*texelSize*0.5, z));
		#endif
		
		vec3 feetPlayerPos = mat3(gbufferModelViewInverse) * viewPos;
		vec3 feetPlayerPos_normalized = normalize(feetPlayerPos);

		vec3 worldPos = feetPlayerPos + cameraPosition;

		#ifdef POM
			#ifdef Horrible_slope_normals
    			vec3 ApproximatedFlatNormal = normalize(cross(dFdx(feetPlayerPos), dFdy(feetPlayerPos))); // it uses depth that has POM written to it.
				slopednormal = normalize(clamp(normal, ApproximatedFlatNormal*2.0 - 1.0, ApproximatedFlatNormal*2.0 + 1.0) );
			#endif
		#endif

		#if defined END_SHADER && defined END_ISLAND_LIGHT
			vec3 WsunVec = normalize(END_LIGHT_POS-worldPos);
		#endif

	////// --------------- COLORS --------------- //////

		vec3 waterEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
		vec3 dirtEpsilon = vec3(Dirt_Absorb_R, Dirt_Absorb_G, Dirt_Absorb_B);
		vec3 totEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
		vec3 scatterCoef = Dirt_Amount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / 3.14;

		vec3 Absorbtion = vec3(1.0);
		vec3 AmbientLightColor = vec3(0.0);
		vec3 MinimumLightColor = vec3(1.0);
		vec3 Indirect_lighting = vec3(0.0);
		vec3 Indirect_SSS = vec3(0.0);
		vec2 SSAO_SSS = vec2(1.0);
		
		vec3 DirectLightColor = vec3(0.0);
		vec3 Direct_lighting = vec3(0.0);
		vec3 Direct_SSS = vec3(0.0);
		float cloudShadow = 1.0;
		float Shadows = 1.0;

		vec3 shadowColor = vec3(1.0);
		vec3 SSSColor = vec3(0.0);
		#if defined END_ISLAND_LIGHT && defined END_SHADER
			vec3 filteredShadow = vec3(Min_Shadow_Filter_Radius_END,1.0,0.0);
		#else
			vec3 filteredShadow = vec3(Min_Shadow_Filter_Radius,1.0,0.0);
		#endif

		float NdotL = 1.0;
		float lightLeakFix = clamp(pow(eyeBrightnessSmooth.y/240. + lightmap.y,2.0) ,0.0,1.0);

		#ifdef OVERWORLD_SHADER
			DirectLightColor = lightSourceColorSSBO / 2400.0;
			AmbientLightColor = averageSkyCol_CloudsSSBO / 900.0;

			#if defined CUSTOM_MOON_ROTATION && LIGHTNING_SHADOWS > 0
				#if LIGHTNING_SHADOWS < 2
				if (lightningBoltPosition.w > 0.0 && sunElevation < 0.0)
				#else
				if (lightningBoltPosition.w > 0.0)
				#endif
				{
					vec3 lightningColor = vec3(2.0, 4.5, 6.6) * lightningFlash;
					DirectLightColor += 0.5 * lightningColor * smoothstep(300.0, 0.0, length(feetPlayerPos-lightningBoltPosition.xyz));
				}
			#endif
			
			#ifdef USE_CUSTOM_DIFFUSE_LIGHTING_COLORS
				DirectLightColor = luma(DirectLightColor) * vec3(DIRECTLIGHT_DIFFUSE_R,DIRECTLIGHT_DIFFUSE_G,DIRECTLIGHT_DIFFUSE_B);
				AmbientLightColor = luma(AmbientLightColor) * vec3(INDIRECTLIGHT_DIFFUSE_R,INDIRECTLIGHT_DIFFUSE_G,INDIRECTLIGHT_DIFFUSE_B);
			#endif
			
			shadowColor = DirectLightColor;

			//bool inShadowmapBounds = false;
		#endif

		#if defined END_SHADER && defined END_ISLAND_LIGHT
			DirectLightColor = vec3(VORTEX_LIGHT_COL_R,VORTEX_LIGHT_COL_G,VORTEX_LIGHT_COL_B);

			shadowColor = DirectLightColor;
		#endif

	////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	UNDER WATER SHADING		////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////


 	if ((isEyeInWater == 0 && isWater) || (eyeInWater && !isWater)){
		
		feetPlayerPos += gbufferModelViewInverse[3].xyz;
		worldPos = feetPlayerPos + cameraPosition;
		
		#if defined DISTANT_HORIZONS || defined VOXY
			vec3 playerPos0 = mat3(gbufferModelViewInverse) *  toScreenSpace_DH(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5, z0, DH_depth0) + gbufferModelViewInverse[3].xyz;
		#else
			vec3 playerPos0 = mat3(gbufferModelViewInverse) * toScreenSpace(vec3(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5,z0)) + gbufferModelViewInverse[3].xyz;
		#endif

		float Vdiff = distance(feetPlayerPos, playerPos0);
		float estimatedDepth = Vdiff * abs(feetPlayerPos_normalized.y);// assuming water plane

		// force the absorbance to start way closer to the water surface in low light areas, so the water is visible in caves and such.
		#if MINIMUM_WATER_ABSORBANCE > -1
			float minimumAbsorbance = MINIMUM_WATER_ABSORBANCE*0.1;
		#else
			float minimumAbsorbance	= (1.0 - lightLeakFix);
		#endif
		
		Absorbtion = exp(-totEpsilon * max(Vdiff, minimumAbsorbance));

		if(!isSky) {
			// things to note about sunlight in water
			// sunlight gets absorbed by water on the way down to the floor, and on the way back up to your eye. im gonna ingore the latter part lol
			// based on the angle of the sun, sunlight will travel through more/less water to reach the same spot. scale absorbtion depth accordingly
			vec3 sunlightAbsorbtion = exp(-totEpsilon * (estimatedDepth/abs(WsunVec.y)));

			float percievedWaterDepth = estimatedDepth;

			if (eyeInWater){
				estimatedDepth = 1.0;

				// viewerWaterDepth = max(0.9-lightmap.y,0.0)*3.0;
				float distanceFromWaterSurface = -(worldPos.y - waterEnteredAltitude);//max(-(feetPlayerPos.y + (cameraPosition.y - waterEnteredAltitude)),0.0) ;
				
				percievedWaterDepth = distanceFromWaterSurface;

				distanceFromWaterSurface = max(distanceFromWaterSurface,0.0);

				Absorbtion = exp(-totEpsilon * distanceFromWaterSurface);
				
				sunlightAbsorbtion = exp(-totEpsilon * (distanceFromWaterSurface/abs(WsunVec.y)));
			} else {
				// use hardcoded gradient position if the water surface normal does not face upwards.
				vec3 waterNormal = clamp(normalize(cross(dFdx(playerPos0), dFdy(playerPos0))),0,1); // it uses depth that has POM written to it.
				percievedWaterDepth = mix(-(feetPlayerPos.y + cameraPosition.y), percievedWaterDepth, waterNormal.y);
			}
			
			DirectLightColor *= sunlightAbsorbtion;

			if( nightVision > 0.0 ) Absorbtion += exp(-totEpsilon * 25.0) * nightVision;

			// vec2 causticPos = pos.xz;
			// causticPos = mix(causticPos, pos.xz, max(FlatNormals.y,0));
			// causticPos = mix(causticPos, pos.xy, max(-FlatNormals.y,0));
			// causticPos = mix(causticPos, pos.zy, max(FlatNormals.x,0));
			// causticPos = mix(causticPos, pos.xy, max(-FlatNormals.z,0));
			// causticPos = mix(causticPos, pos.xy, max(FlatNormals.x,0));
			// causticPos = mix(causticPos, pos.xy, max(-FlatNormals.x,0));

			// apply caustics to the lighting, and make sure they dont look weird
			DirectLightColor *= pow(mix(1.0, waterCaustics(worldPos, WsunVec, percievedWaterDepth)*WATER_CAUSTICS_BRIGHTNESS, clamp(estimatedDepth,0,1)), WATER_CAUSTICS_POWER);
		}
	}


	if (!isSky) {
		MinimumLightColor = MinimumLightColor + 0.7 * MinimumLightColor * dot(slopednormal, feetPlayerPos_normalized);

		// idk why this do
		// this seems to be compensating view bobbing, but why not do this when calculating feetPlayerPos? hmmm
		feetPlayerPos += gbufferModelViewInverse[3].xyz;
		float viewDist = length(feetPlayerPos);
		worldPos = feetPlayerPos + cameraPosition;
	////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////	    FILTER STUFF      //////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////

		#if (defined DISTANT_HORIZONS && defined DH_AMBIENT_OCCLUSION) || (defined VOXY && defined VOXY_AMBIENT_OCCLUSION)
			doEdgeAwareBlur(colortex3,	colortex14, colortex9, DH_mixedLinearZ, hand, SSAO_SSS, filteredShadow);
		#else
			doEdgeAwareBlur(colortex3,	colortex14, depthtex0, ld(z0), 	hand, SSAO_SSS, filteredShadow);
		#endif
		
		float ShadowBlockerDepth = filteredShadow.y;

	////////////////////////////////////////////////////////////////////////////////////
	/////////////////////////////	MAJOR LIGHTSOURCE STUFF 	////////////////////////
	////////////////////////////////////////////////////////////////////////////////////
	
	#if defined OVERWORLD_SHADER || (defined END_ISLAND_LIGHT && defined END_SHADER)

		// float LM_shadowMapFallback =  clamp(lightmap.y, 0.0,1.0);

		//float LightningPhase = 0.0;
		//vec3 LightningFlashLighting = Iris_Lightningflash(feetPlayerPos, lightningBoltPosition.xyz, slopednormal, LightningPhase) * pow(lightmap.y,10);

		NdotL = clamp((-15 + dot(slopednormal, WsunVec)*255.0) / 240.0  ,0.0,1.0);

		// NdotL = 1;
		float flatNormNdotL = clamp((-15 + dot((FlatNormals), WsunVec)*255.0) / 240.0  ,0.0,1.0);
		if(opaqueParticles) {
			flatNormNdotL = mix(0.5, 1.0, flatNormNdotL);
			NdotL = mix(0.5, 1.0, NdotL);
		}
		
	////////////////////////////////	SHADOWMAP		////////////////////////////////
		// setup shadow projection

		float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - viewDist / (shadowDistance+32.0),0.0)*5.0,1.0));
		#if defined DISTANT_HORIZONS || defined VOXY
			float shadowMapFalloff2 = smoothstep(0.0, 1.0, min(max(1.0 - viewDist / min(shadowDistance, max(far-32.0,32.0)),0.0)*5.0,1.0));
		#else
			float shadowMapFalloff2 = smoothstep(0.0, 1.0, min(max(1.0 - viewDist / shadowDistance,0.0)*5.0,1.0));
		#endif

		if(eyeInWater){
			shadowMapFalloff = 1.0;
			shadowMapFalloff2 = 1.0;
		}

		vec3 shadowPlayerPos = feetPlayerPos;

		#if LIGHTLEAKFIX_MODE == 1
			if(!hand) GriAndEminShadowFix(shadowPlayerPos, FlatNormals, lightLeakFix);
		#endif

		#ifdef OVERWORLD_SHADER
			#ifdef CUSTOM_MOON_ROTATION
				vec3 projectedShadowPosition = mat3(customShadowMatrixSSBO) * shadowPlayerPos + customShadowMatrixSSBO[3].xyz;
			#else
				vec3 projectedShadowPosition = mat3(shadowModelView) * shadowPlayerPos + shadowModelView[3].xyz;
			#endif

			applyShadowBias(projectedShadowPosition, shadowPlayerPos, FlatNormals);
			projectedShadowPosition = diagonal3_old(shadowProjection) * projectedShadowPosition + shadowProjection[3].xyz;

			// Calclulate distortion factor before bias application
			#ifdef DISTORT_SHADOWMAP
				float distortFactor = calcDistort(projectedShadowPosition.xy);
				projectedShadowPosition.xy *= distortFactor;
			#else
				float distortFactor = 1.0;
			#endif

			#if defined POM_OFFSET_SHADOW_BIAS && defined POM
				projectedShadowPosition.z += shadowProjection[3].z * (0.0012 + POM_DEEPNESS * mix(0.25,1.0,POM_DEPTH) * 0.025);
			#else
				projectedShadowPosition.z += shadowProjection[3].z * 0.0012;
			#endif
		#else
			float distortFactor = 1.0;
		#endif

		#if defined END_ISLAND_LIGHT && defined END_SHADER
			vec4 shadowPos = customShadowMatrixSSBO * (gbufferModelViewInverse * vec4(viewPos, 1.0));
			applyShadowBias(shadowPos.xyz, shadowPlayerPos, FlatNormals);
			shadowPos = customShadowPerspectiveSSBO * shadowPos;
			vec3 projectedShadowPosition = shadowPos.xyz / shadowPos.w;
		#endif

		projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5,0.5,0.5) ;

		float ShadowAlpha = 0.0; // this is for subsurface scattering later.
		vec3 tintedSunlight = DirectLightColor; // this is for subsurface scattering later.
		// nobody cares, it makes zero difference
		
		#if defined END_ISLAND_LIGHT && defined END_SHADER			
			// make light fade out
			float r = length(projectedShadowPosition.xy - vec2(0.5));

			if (r < 0.5 && abs(projectedShadowPosition.z) < 1.0) {
				shadowColor = ComputeShadowMap_COLOR(projectedShadowPosition, distortFactor, noise_2, filteredShadow.x, flatNormNdotL, shadowMapFalloff, DirectLightColor, ShadowAlpha, tintedSunlight, LabSSS > 0.0,Shadows);
				shadowColor *= smoothstep(0.5, 0.25, r);
			} else {
				shadowColor = vec3(0.0);
			}

		#else
			shadowColor = ComputeShadowMap_COLOR(projectedShadowPosition, distortFactor, noise_2, filteredShadow.x, flatNormNdotL, shadowMapFalloff, DirectLightColor, ShadowAlpha, tintedSunlight, LabSSS > 0.0,Shadows);
		#endif
		
		// transition to fallback lightmap shadow mask.
		// shadowColor *= mix(isWater ? lightLeakFix : LM_shadowMapFallback, 1.0, shadowMapFalloff2);

		#if LIGHTLEAKFIX_MODE == 2
			if(!eyeInWater) shadowColor *= lightLeakFix; // light leak fix
		#endif
		
	////////////////////////////////	SUN SSS		////////////////////////////////
		#if SSS_TYPE != 0
			float sunSSS_density = LabSSS;
			float SSS_shadow = ShadowAlpha;
			

			#ifndef RENDER_ENTITY_SHADOWS
				if(entities) sunSSS_density = 0.0;
			#endif
			
			#if SCREENSPACE_CONTACT_SHADOWS > 0 && !defined END_SHADER
				vec2 SS_directLight = SSRT_Shadows(toScreenSpace_DH(texcoord/RENDER_SCALE, z, DH_depth1), isDHrange, normalize(WsunVec*mat3(gbufferModelViewInverse)), ig_noise, sunSSS_density > 0.0 && shadowMapFalloff2 < 1.0, hand);

				// combine shadowmap with screenspace shadows.
				#if SCREENSPACE_CONTACT_SHADOWS == 1
					SS_directLight.r = mix(1.0, SS_directLight.r, 1.0-shadowMapFalloff);
				#endif

				if(!opaqueParticles) shadowColor *= SS_directLight.r;			
			#else
				vec2 SS_directLight = vec2(1,0);
				ShadowBlockerDepth = max(ShadowBlockerDepth, (1.0-shadowMapFalloff2) * 10.0);
			#endif
			
				
			// #ifdef TRANSLUCENT_COLORED_SHADOWS
			// 	SSSColor = tintedSunlight;
			// #else
			// 	SSSColor = DirectLightColor;
			// #endif
			
			// TODO CHECK IF *= OR =
			// *= looks better idk
			// = is nice too though ???
			SSSColor = SubsurfaceScattering_sun(albedo, ShadowBlockerDepth, sunSSS_density, clamp(dot(feetPlayerPos_normalized, WsunVec),0.0,1.0), SS_directLight.g, shadowMapFalloff2, hand);
			
			if(!eyeInWater) SSSColor *= lightLeakFix;

			#if defined END_ISLAND_LIGHT && defined END_SHADER
				float fade = 0.0;
				if (r < 0.5 && abs(projectedShadowPosition.z) < 1.0) fade = smoothstep(0.25, 0.2, r*r);

				SSSColor *= fade;

				#ifdef SHADER_GRASS
					if(isShaderGrass) SSSColor *= 0.3;
				#endif
			#endif
		#endif
		
		#ifndef END_SHADER
			float cloudShadows = GetCloudShadow(worldPos, WsunVec);
			shadowColor *= cloudShadows;
			SSSColor *= cloudShadow*cloudShadows;
		#endif

	#endif

	#ifdef END_SHADER
		#ifdef END_LIGHTNING
			float vortexBounds = clamp(vortexBoundRange - length(worldPos), 0.0,1.0);
		#else
			float vortexBounds = 1.0;
		#endif

        vec3 lightPos = LightSourcePosition(worldPos, cameraPosition,vortexBounds);

		float lightningflash = texelFetch(colortex4,ivec2(1,1),0).x/150.0;
		vec3 lightColors = pow(lightmap.y,8) * LightSourceColors(vortexBounds, lightningflash);
		
		float end_NdotL = clamp(dot(slopednormal, normalize(-lightPos))*0.5+0.5,0.0,1.0);
		end_NdotL *= end_NdotL;

		float fogShadow = GetEndFogShadow(worldPos, lightPos);
		float endPhase = endFogPhase(lightPos);

		Direct_lighting += lightColors * endPhase * end_NdotL * fogShadow;
	#endif
	

	/////////////////////////////////////////////////////////////////////////////////
	/////////////////////////////	INDIRECT LIGHTING 	/////////////////////////////
	/////////////////////////////////////////////////////////////////////////////////

		#if defined OVERWORLD_SHADER
			float skylight = 1.0;
		
			#if indirect_effect == VANILLA_AO || indirect_effect == SSAO_FILTERED || indirect_effect == SSAO_HQ || indirect_effect == GTAO

				vec3 indirectNormal = slopednormal / dot(abs(slopednormal),vec3(1.0));

				float SkylightDir = indirectNormal.y;

				if(isGrass) SkylightDir = 1.0;
				
				SkylightDir = clamp(SkylightDir*0.7+0.3, 0.0, pow(1-pow(1-SSAO_SSS.x, 0.5),4.0) * 0.7 + 0.3);

				skylight = mix(0.08 + 0.92*(1.0-lightmap.y), 1.0, SkylightDir);

				// skylight = 1.0;
			#endif

			#if indirect_effect == SSRT_AO || indirect_effect == SSRT_AO_GI
				skylight = 1.0;
			#endif
			
			Indirect_lighting += doIndirectLighting(AmbientLightColor * skylight, MinimumLightColor, lightmap.y);

			#if defined PH_ENABLE_GI && defined PHOTONICS && defined ENABLE_PHOTONICS_GI
				#if defined DISTANT_HORIZONS || defined VOXY
					float photonicsFalloff = smoothstep(min(far, 128.0), min(0.9*far, 114.0), viewDist);
				#else
					float photonicsFalloff = smoothstep(128.0, 114.0, viewDist);
				#endif

				vec3 gi_color = texture(colortex15, texcoord).xyz*2.0*PHOTONICS_INDIRECT_BRIGHTNESS* skylight;
				gi_color += mix(MinimumLightColor * (MIN_LIGHT_AMOUNT * 0.004 + nightVision*0.02), MinimumLightColor * (MIN_LIGHT_AMOUNT_INSIDE * 0.004 + nightVision*0.02), 1.0-lightmap.y);

				Indirect_lighting = mix(Indirect_lighting, gi_color, photonicsFalloff);
			#endif
		#endif

		#ifdef NETHER_SHADER
			Indirect_lighting = volumetricsFromTex(normalize(normal), colortex4, 6).rgb / 1200.0;
			vec3 up = volumetricsFromTex(vec3(0.0,1.0,0.0), colortex4, 6).rgb / 1200.0;
			
			#if indirect_effect == SSAO_FILTERED || indirect_effect == SSAO_HQ
				Indirect_lighting = mix(up, Indirect_lighting,  clamp(pow(1.0-pow(1.0-SSAO_SSS.x, 0.5),2.0),0.0,1.0));
			#endif
			
			AmbientLightColor = Indirect_lighting;
		#endif
		
		#ifdef END_SHADER
			Indirect_lighting = vec3(AmbientLightEnd_R,AmbientLightEnd_G,AmbientLightEnd_B);
			
			Indirect_lighting = Indirect_lighting + 0.7*mix(-Indirect_lighting, Indirect_lighting * dot(slopednormal, feetPlayerPos_normalized), clamp(pow(1.0-pow(1.0-SSAO_SSS.x, 0.5),2.0),0.0,1.0));
			Indirect_lighting *= 0.05 * lightmap.y*lightmap.y;

			Indirect_lighting += lightColors * (endPhase*endPhase) * (1.0-exp(vec3(0.6,2.0,2.0) * -(endPhase*0.01))) /1000.0;

			// float minimumLightAmount = 0.02*nightVision + 0.005 * mix(MINIMUM_INDOOR_LIGHT, MINIMUM_OUTDOOR_LIGHT, clamp(eyeBrightnessSmooth.y/240.0 + lightmap.y,0.0,1.0));
    		// Indirect_lighting += MinimumLightColor * minimumLightAmount;
			Indirect_lighting += MinimumLightColor * (MIN_LIGHT_AMOUNT * 0.02 * 0.2 + nightVision*0.02);
		#endif
		
		#ifdef IS_LPV_ENABLED
			vec3 normalOffset = vec3(0.0);

			if (any(greaterThan(abs(FlatNormals), vec3(1.0e-6))))
				normalOffset = 0.5*(FlatNormals);

			#if LPV_NORMAL_STRENGTH > 0
				vec3 texNormalOffset = -normalOffset + slopednormal;
				normalOffset = mix(normalOffset, texNormalOffset, (LPV_NORMAL_STRENGTH*0.01));
			#endif

			vec3 lpvPos = GetLpvPosition(feetPlayerPos) + normalOffset;
		#else
			const vec3 lpvPos = vec3(0.0);
		#endif
		
		vec3 blockLightColor = doBlockLightLighting(vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, feetPlayerPos, lpvPos, viewPos, isDHrange, blueNoise(), FlatNormals, hand, glowframe, opaqueParticles);
		Indirect_lighting += blockLightColor;

		vec4 flashLightSpecularData = vec4(0.0);
		#ifdef FLASHLIGHT
			#ifdef FLASHLIGHT_SHADOWS
				vec3 newViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
				float flashlightshadows = SSRT_FlashLight_Shadows(toScreenSpace_DH(texcoord/RENDER_SCALE, z, DH_depth1), isDHrange, -newViewPos, blueNoise(), FlatNormals, hand);
			#else
				const float flashlightshadows = 1.0;
			#endif
			
			Indirect_lighting += flashlightshadows*calculateFlashlight(texcoord, viewPos, albedoSmoothSSBO, slopednormal, flashLightSpecularData, hand);
		#endif

	/////////////////////////////////////////////////////////////////////////////////////
	/////////////////////////////	EFFECTS FOR INDIRECT	/////////////////////////////
	/////////////////////////////////////////////////////////////////////////////////////

		float SkySSS = SSAO_SSS.y;
		vec3 AO = vec3(1.0);

		#if indirect_effect == 0
			AO = vec3(pow(1.0 - vanilla_AO*vanilla_AO,5.0));
			Indirect_lighting *= AO;
		#endif

		#if indirect_effect == SSAO_FILTERED || indirect_effect == SSAO_HQ
			SkySSS = SSAO_SSS.y;

			float vanillaAO_curve = pow(1.0 - vanilla_AO*vanilla_AO,5.0);
			float SSAO_curve = pow(SSAO_SSS.x,4.0);

			// use the min of vanilla ao so they dont overdarken eachother
			// AO = vec3( min(vanillaAO_curve, SSAO_curve) );
			AO = vec3( SSAO_curve );
			Indirect_lighting *= AO;
		#endif

		// // GTAO... this is so dumb but whatevverrr
		#if indirect_effect == GTAO
			float vanillaAO_curve = pow(1.0 - vanilla_AO*vanilla_AO,5.0);

			vec2 r2 = fract(R2_samples((frameCounter%40000) + frameCounter*2) + bnoise);
			float getGTAO =  !hand ? ambient_occlusion(vec3(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5, z), viewPos, worldToView(slopednormal), r2) : 1.0;
			
			AO = vec3(min(vanillaAO_curve,getGTAO));
			
			Indirect_lighting *= AO;
		#endif

		// RTAO and/or SSGI
		#if indirect_effect == SSRT_AO || indirect_effect == SSRT_AO_GI
			if(!hand) Indirect_lighting = ApplySSRT(Indirect_lighting, blockLightColor, MinimumLightColor, viewPos, normal, vec3(bnoise, noise_2), lightmap.y, isGrass, isDHrange);
		#endif



	////////////////////////////////////////////////////////////////////////////////
	/////////////////////////	SUB SURFACE SCATTERING	////////////////////////////
	////////////////////////////////////////////////////////////////////////////////
	
	/////////////////////////////	SKY SSS		/////////////////////////////
		#if defined Ambient_SSS && defined OVERWORLD_SHADER && (indirect_effect == SSAO_FILTERED || indirect_effect == SSAO_HQ)
			vec3 ambientColor = AmbientLightColor * ambientsss_brightness * ambient_brightness;

			Indirect_SSS = SubsurfaceScattering_sky(albedo, SkySSS, LabSSS);
			Indirect_SSS *= lightmap.y;

			// float thingy = SkySSS;
			// thingy = pow(thingy,3.5);
			// thingy = 1-pow(1-thingy,5);

			Indirect_lighting += Indirect_SSS * ambientColor;
		#endif
	
	/////////////////////////////////////////////////////////////////////////
	/////////////////////////////	FINALIZE	/////////////////////////////
	/////////////////////////////////////////////////////////////////////////


		// shadowColor *= 0.0;
		// SSSColor *= 0.0;

		#ifdef SSS_view
			albedo = vec3(1);
			NdotL = 0;
		#endif
		#if defined END_SHADER
			Direct_lighting *= AO;
		#endif
		#if defined OVERWORLD_SHADER || (defined END_ISLAND_LIGHT && defined END_SHADER)
			

			#ifdef AO_in_sunlight
				// Direct_lighting = shadowColor*NdotL*(AO*0.7+0.3) + SSSColor * (1.0-NdotL);
				Direct_lighting = DirectLightColor * mix(SSSColor, vec3(1.0), NdotL*shadowColor * (AO*0.7+0.3));
			#else
				// Direct_lighting = shadowColor*NdotL + SSSColor * (1.0-NdotL);
				Direct_lighting = DirectLightColor * mix(SSSColor, vec3(1.0), NdotL*shadowColor);
			#endif
		#endif

		#if defined OVERWORLD_SHADER && defined DEFERRED_SPECULAR && (PUDDLE_MODE > 0 || ShaderSnow > 0)
			if(!hand && !entities && !isWater) applyPuddles(worldPos, FlatNormals, lightmap.y, eyeInWater, albedo, normal, SpecularTex.r, SpecularTex.g, isShaderGrass, labPorosity);
		#endif

		vec3 FINAL_COLOR = (Indirect_lighting + Direct_lighting) * albedo;

		Emission(FINAL_COLOR, albedo, SpecularTex.a);
		
		// if(lightningBolt) FINAL_COLOR = vec3(77.0, 153.0, 255.0);
		
		#if defined DEFERRED_SPECULAR	
			vec2 specularNoises = vec2(blueNoise(), ig_noise);
    		vec3 specularNormal = normal;
			if (dot(normal, (feetPlayerPos_normalized)) > 0.0) specularNormal = FlatNormals;

			vec4 reflections = vec4(0.0,0.0,0.0,1.0);
			float SunReflectionAlpha = 0.0;
			
			FINAL_COLOR = specularReflections(viewPos, feetPlayerPos, feetPlayerPos_normalized, WsunVec, specularNoises, FlatNormals, specularNormal, SpecularTex.r, SpecularTex.g, albedo, FINAL_COLOR, DirectLightColor*shadowColor*shadowColor, lightmap.y, hand, reflections, SunReflectionAlpha, isShaderGrass, flashLightSpecularData);

			#if defined DEFERRED_SPECULAR && defined DENOISED_REFLECTIONS
			gl_FragData[1] = reflections;
			gl_FragData[2].rgb = DirectLightColor*shadowColor*shadowColor*SunReflectionAlpha;
			gl_FragData[3] = vec4(encodeNormal(specularNormal), SpecularTex.r, SpecularTex.g);
			#endif
		#endif

		gl_FragData[0].rgb = FINAL_COLOR;

	}else{
		vec3 Background = vec3(0.0);


		#ifdef OVERWORLD_SHADER

			float atmosphereGround = 1.0 - exp2(-50.0 * pow(clamp(feetPlayerPos_normalized.y+0.025,0.0,1.0),2.0)  ); // darken the ground in the sky.
			
			#if RESOURCEPACK_SKY == 1 || RESOURCEPACK_SKY == 0 || RESOURCEPACK_SKY == 3
				// vec3 orbitstar = vec3(feetPlayerPos_normalized.x,abs(feetPlayerPos_normalized.y),feetPlayerPos_normalized.z); orbitstar.x -= WsunVec.x*0.2;
				vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * toScreenSpace(vec3(texcoord/RENDER_SCALE,1.0)));

				#if RESOURCEPACK_SKY == 0 || RESOURCEPACK_SKY == 3
					vec3 orbitstar = customRotation(sunPathRotation, worldTimeSmooth) * worldDir;

					vec3 starColor = vec3(1.0);
					#if defined OVERWORLD_SHADER && defined TWILIGHT_FOREST_FLAG
						float stars = stars(orbitstar, starColor) * 100.0;
						Background += stars * starColor;
					#else
						float stars = stars(orbitstar, starColor) * 10.0;
						Background += stars * starColor * mix(clamp(-unsigned_WsunVec.y*2.0,0.0,1.0), 1.0, clamp(cameraPosition.y-15000.0, 0.0, 45000.0)/45000.0);
					#endif
				#endif

				#if !defined AMBIENT_LIGHT_ONLY && (RESOURCEPACK_SKY == 1 || RESOURCEPACK_SKY == 0)
					#ifdef CUSTOM_MOON_ROTATION
						float sunMoonDist = length(unsigned_WsunVec - WmoonVec);
						if (sunMoonDist < 0.004){
							vec3 tangent2 = normalize(cross(unsigned_WsunVec, vec3(0.0, 1.0, 0.0)));
							vec3 binormal2 = cross(unsigned_WsunVec, tangent2);
							vec3 dirDiff2 = worldDir - unsigned_WsunVec;

							float u2 = dot(dirDiff2, tangent2);
							float v2 = dot(dirDiff2, binormal2);

							float sunAngularRadius = acos(0.9984)*SUN_SIZE*0.01;
							float mult = 1.0;
							#if SUN_SIZE > MOON_SIZE
								mult = smoothstep(1.3, 1.1, float(SUN_SIZE)/float(MOON_SIZE));
							#endif


							u2 = u2 / (2.0 * sunAngularRadius) + 0.5;
							v2 = -v2 / (1.96 * sunAngularRadius) + 0.505;

							vec2 coronaUV = vec2(u2, v2);
							vec3 coronaTex = texture(CoronaTex, coronaUV).rgb;
							Background += 0.5 * coronaTex * coronaTex * coronaTex * coronaTex * coronaTex * smoothstep(0.004, 0.0002, sunMoonDist)*mult;
						}
					#endif

					#ifdef SMOOTH_SUN_ROTATION
						vec3 sunVec = WsunVecSmooth;
					#else
						vec3 sunVec = unsigned_WsunVec;
					#endif

					Background += drawSun(dot(sunVec, feetPlayerPos_normalized), sunColorSSBO / 2400.0);

					#ifdef REALMOON
						vec3 tangent = normalize(cross(WmoonVec, vec3(0.0, 1.0, 0.0)));
						vec3 binormal = cross(WmoonVec, tangent);
						vec3 dirDiff = worldDir - WmoonVec;

						float u = dot(dirDiff, tangent);
						float v = dot(dirDiff, binormal);

						float moonAngularRadius = acos(0.9994) * MOON_SIZE * 0.01; 

						u = u / (2.0 * moonAngularRadius) + 0.5;
						v = -v / (2.0 * moonAngularRadius) + 0.5;
						vec2 moonUV = vec2(u, v);
						vec2 moonSphericalUV = sphereMap(moonUV);
						
						#ifdef CUSTOM_MOON_ROTATION
							vec3 moonTex = texture(moon, moonSphericalUV).rgb;
							float moonVis = smoothstep(0.08, -0.03, WmoonVec.y);

							vec2 pos = 2.0 * moonUV - 1.0;

							vec3 moonDirLocal = normalize(vec3(pos.x, pos.y, sqrt(1.0 - dot(pos, pos))));

							vec3 moonDirWorld = moonDirLocal.x * tangent - moonDirLocal.y * binormal - moonDirLocal.z * WmoonVec;

							float sunLight = dot(normalize(moonDirWorld), unsigned_WsunVec);

							#ifdef MOON_NORMALS
								float mask = smoothstep(-0.25, 0.12, sunLight);

								vec3 normalTex = texture(moonN, moonSphericalUV).xyz;
								normalTex = normalTex * 2.0 - 1.0;

								mat3 TBN = mat3(tangent, binormal, normalize(moonDirWorld));
								vec3 worldNormal = normalize(TBN * normalTex);

								float normalSunLight = dot(worldNormal, unsigned_WsunVec);
								
								// smoothstep to boost contrast
								mask *= smoothstep(-0.5, 0.5, normalSunLight);
							#else
								float mask = smoothstep(-0.2, 0.12, sunLight);
							#endif
							
							moonTex *= (1.0 - vec3(0.0, 0.5, 0.7)*clamp((1.0-0.5*v)*moonVis, 0.0, 1.0)) * mask;
						#else
							float moonVis = smoothstep(0.12, -0.03, -moonElevation);
							float moonphaseMult = 1.0;
							#ifdef MOONPHASE_BASED_MOONLIGHT
								float[8] phase = float[8](
									1.0,
									smoothstep(0.85, 0.65, u + pow(abs(0.8*(v-0.5)), 2.0)),
									smoothstep(0.6, 0.4, u),
									smoothstep(0.35, 0.15, u - pow(abs(0.8*(v-0.5)), 2.0)),
									0.0,
									smoothstep(0.65, 0.85, u + pow(abs(0.8*(v-0.5)), 2.0)),
									smoothstep(0.4, 0.6, u),
									smoothstep(0.15, 0.35, u - pow(abs(0.8*(v-0.5)), 2.0))
								);

								moonphaseMult = phase[moonPhase];
							#endif
							vec3 moonTex = (1.0 - vec3(0.0, 0.5, 0.7)*clamp((1-0.5*v)*moonVis, 0.0, 1.0)) * moonphaseMult * texture(moon, moonSphericalUV).rgb;
						#endif
						
						vec3 moonLightCol = moonColorBase2;
						Background += pow(moonTex, vec3(3.2)) * 12.0 * drawRealMoon(feetPlayerPos_normalized, WmoonVec, moonLightCol, Background);
					#else
						vec3 moonLightCol = moonColorSSBO / 2400.0;
						Background += drawMoon(feetPlayerPos_normalized, WmoonVec, moonLightCol, Background); 
					#endif
				#endif

				Background *= atmosphereGround;
			#endif
			
			#ifndef ISOLATE_RESOURCEPACK_SKY
				vec3 Sky = skyFromTex(feetPlayerPos_normalized, colortex4)/1200.0 * Sky_Brightness;
				Background += Sky;
			#endif
			
			#if RESOURCEPACK_SKY == 1 || RESOURCEPACK_SKY == 2 || RESOURCEPACK_SKY == 3
				vec3 resourcePackskyBox = skyboxCol * 50.0 * clamp(unsigned_WsunVec.y*255.0,0.1,1.0);

				#if defined SKY_GROUND && !defined ISOLATE_RESOURCEPACK_SKY
					resourcePackskyBox *= atmosphereGround;
				#endif

				Background += resourcePackskyBox;
			#endif

		#endif

		#ifdef END_SHADER
			vec3 starColor = vec3(1.0);
			Background += stars(normalize(mat3(gbufferModelViewInverse) * toScreenSpace(vec3(texcoord/RENDER_SCALE,1.0))), starColor) * 5.0;
		#endif

		gl_FragData[0].rgb = clamp(fp10Dither(Background, triangularize(noise_2)), 0.0, 65000.);
	}


	if(translucentMasks > 0.0 && !hand){
		// water absorbtion will impact ALL light coming up from terrain underwater.
		gl_FragData[0].rgb *= Absorbtion;
	}

	////// DEBUG VIEW STUFF
	#if DEBUG_VIEW == debug_SHADOWMAP	
		gl_FragData[0].rgb = vec3(1.0) * (Shadows * NdotL * 0.9 + 0.1);
		
		if(dot(feetPlayerPos_normalized, unsigned_WsunVec) > 0.999 ) gl_FragData[0].rgb = vec3(10,10,0);
		if(dot(feetPlayerPos_normalized, WmoonVec) > 0.999 ) gl_FragData[0].rgb = vec3(1,1,10);
	#endif
	#if DEBUG_VIEW == debug_NORMALS
		if(swappedDepth >= 1.0) Direct_lighting = vec3(1.0);
		gl_FragData[0].rgb = normal ;
	#endif
	#if DEBUG_VIEW == debug_SPECULAR
		if(swappedDepth >= 1.0) Direct_lighting = vec3(1.0);
		gl_FragData[0].rgb = SpecularTex.rgb;
	#endif
	#if DEBUG_VIEW == debug_INDIRECT
		if(swappedDepth >= 1.0) Direct_lighting = vec3(5.0);
		gl_FragData[0].rgb = Indirect_lighting;
	#endif
	#if DEBUG_VIEW == debug_DIRECT
		if(swappedDepth < 1.0) gl_FragData[0].rgb = Direct_lighting;
	#endif
	#if DEBUG_VIEW == debug_VIEW_POSITION
		gl_FragData[0].rgb = viewPos * 0.001;
	#endif
	#if DEBUG_VIEW == debug_FILTERED_STUFF
		// if(hideGUI == 0){
			float value = SSAO_SSS.y;
			value = pow(value,3.5);
			value = 1-pow(1-value,5);

			if(hideGUI == 1) value = pow(SSAO_SSS.x,6);
			gl_FragData[0].rgb = vec3(value);

			if(swappedDepth >= 1.0) gl_FragData[0].rgb  = vec3(1.0);
		// }
	#endif

	#if defined DEFERRED_SPECULAR && defined DENOISED_REFLECTIONS
	/* RENDERTARGETS:3,0,15,8 */
	#else
	/* RENDERTARGETS:3 */
	#endif
}