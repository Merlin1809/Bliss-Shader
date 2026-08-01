#include "/lib/settings.glsl"

#include "/lib/SSBOs.glsl"

#define EXCLUDE_WRITE_TO_LUT

uniform float skyLightLevelSmooth;


uniform sampler2D noisetex;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

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

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
// uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex14;

#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
layout (rgba16f) uniform image2D cloudDepthTex;
#endif

in DATA {
	flat vec3 WsunVec;
	flat vec3 WrealSunVec;
	flat vec3 WmoonVec;
};

uniform vec3 sunVec;
uniform float sunElevation;

// uniform float far;
uniform float near;
uniform float dhVoxyFarPlane;
uniform float dhVoxyNearPlane;

uniform mat4 gbufferPreviousModelView;
uniform vec3 previousCameraPosition;
uniform vec3 relativeEyePosition;

#if defined VIVECRAFT
	uniform bool vivecraftIsVR;
	uniform vec3 vivecraftRelativeMainHandPos;
	uniform vec3 vivecraftRelativeOffHandPos;
	uniform mat4 vivecraftRelativeMainHandRot;
	uniform mat4 vivecraftRelativeOffHandRot;
#endif

uniform int frameCounter;
uniform float frameTimeCounter;

uniform vec2 texelSize;

uniform int isEyeInWater;
uniform float rainStrength;
uniform ivec2 eyeBrightnessSmooth;
uniform float eyeAltitude;
uniform float caveDetection;

// uniform int dhVoxyRenderDistance;
#define DHVLFOG
#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

#include "/lib/color_transforms.glsl"
#include "/lib/color_dither.glsl"
#include "/lib/projections.glsl"
#include "/lib/res_params.glsl"
#include "/lib/sky_gradient.glsl"
#include "/lib/Shadow_Params.glsl"
#include "/lib/waterBump.glsl"

#include "/lib/DistantHorizons_projections.glsl"

float DH_ld(float dist) {
    return (2.0 * dhVoxyNearPlane) / (dhVoxyFarPlane + dhVoxyNearPlane - dist * (dhVoxyFarPlane - dhVoxyNearPlane));
}
float DH_inv_ld (float lindepth){
	return -((2.0*dhVoxyNearPlane/lindepth)-dhVoxyFarPlane-dhVoxyNearPlane)/(dhVoxyFarPlane-dhVoxyNearPlane);
}

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
    return (near * far) / (depth * (near - far) + far);
}

uniform float nightVision;

#ifdef OVERWORLD_SHADER
	uniform float auroraAmount;
	const bool shadowHardwareFiltering = true;
	uniform sampler2DShadow shadowtex0HW;

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		uniform sampler2D shadowcolor0;
		uniform sampler2DShadow shadowtex1HW;
	#endif
	
	
	#include "/lib/scene_controller.glsl"

	#define TIMEOFDAYFOG
	#include "/lib/lightning_stuff.glsl"

	#include "/lib/volumetricClouds.glsl"

	#include "/lib/climate_settings.glsl"
	#include "/lib/overworld_fog.glsl"
#endif
#ifdef NETHER_SHADER
uniform sampler2D colortex4;
	#include "/lib/nether_fog.glsl"
#endif
#ifdef END_SHADER
uniform sampler2D colortex4;
	#include "/lib/end_fog.glsl"
#endif

#include "/lib/util.glsl"

#define IS_LPV_ENABLED

#if defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED
	#extension GL_ARB_shader_image_load_store: enable
	#extension GL_ARB_shading_language_packing: enable

	uniform usampler1D texBlockData;
	uniform sampler3D texLpv1;
	uniform sampler3D texLpv2;

	#include "/lib/hsv.glsl"
	#include "/lib/lpv_blocks.glsl"
	#include "/lib/lpv_common.glsl"
	#include "/lib/lpv_render.glsl"

	#if defined LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER || defined LPV_VL_FOG_ILLUMINATION_HANDHELD
		uniform int heldItemId;
		uniform int heldItemId2;

		#include "/lib/diffuse_lighting.glsl"
	#else
		uniform bool IEXT_KEY_0;
	#endif
	#ifdef LPV_VL_FOG_ILLUMINATION_HANDHELD
	#endif
#else
	uniform bool IEXT_KEY_0;
#endif

bool eyeInWater = isEyeInWater == 1;

vec4 raymarchLPV(
	in vec3 viewPos,
	in float dither
){
	#if (!defined LPV_VL_FOG_ILLUMINATION || !defined IS_LPV_ENABLED) && (!defined FLASHLIGHT_FOG_ILLUMINATION || !defined FLASHLIGHT)
		return vec4(0.0);
	#endif

	const int SAMPLECOUNT = 8;
	float minimumDensity = 0.000025;
	if(eyeInWater) minimumDensity = 0.00006;
	const float fadeLength = 10.0; // in blocks

	vec3 LPVrayStartPos = mat3(gbufferModelViewInverse) * viewPos;
	
	// ensure the max marching distance is the voxel distance, or the render distance if the voxels go farther than it
	float LPVRayLength = length(LPVrayStartPos);
	#if LPV_SIZE == 8
		LPVrayStartPos *= min(LPVRayLength, min(256.0,far))/LPVRayLength;
	#elif LPV_SIZE == 7
		LPVrayStartPos *= min(LPVRayLength, min(128.0,far))/LPVRayLength;
	#elif LPV_SIZE == 6
		LPVrayStartPos *= min(LPVRayLength, min(64.0,far))/LPVRayLength;
	#endif
	LPVRayLength = length(LPVrayStartPos);

	vec3 rayProgress = vec3(0.0);
	vec4 color = vec4(0.0,0.0,0.0,1.0);
	const float expFactor = 11.0;

	for (int i = 0; i < SAMPLECOUNT; i++) {
		float d = (pow(expFactor, float(i+dither)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1.0-1.0/expFactor);
		float dd = pow(expFactor, float(i+dither)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);

		rayProgress = gbufferModelViewInverse[3].xyz + d*LPVrayStartPos;

		float density;
		float _minimumDensity = minimumDensity;

		#ifdef OVERWORLD_SHADER
			if(caveDetection < 0.9999) density = cloudVol(rayProgress + cameraPosition, 0.0) * (1.0 - caveDetection);

			_minimumDensity += caveDetection * minimumDensity;
		#elif defined NETHER_SHADER
			vec3 progressW = rayProgress + cameraPosition;
			density = cloudVol(progressW);

			float dist = length(rayProgress);
			float clearArea = 1.0 - min(max(1.0 - dist / 24.0,0.0),1.0);

			float plumeDensity = min(density * pow(min(max(100.0-progressW.y,0.0)/30.0,1.0),4.0), pow(clamp(1.0 - dist/far,0.0,1.0),5.0));
			plumeDensity *= NETHER_PLUME_DENSITY;

			float ceilingSmokeDensity = 0.001 * pow(min(max(progressW.y-40.0,0.0)/50.0,1.0),3.0);
			ceilingSmokeDensity *= NETHER_CEILING_SMOKE_DENSITY;

			density = plumeDensity + ceilingSmokeDensity;
		#elif defined END_SHADER
			float volumeDensity = fogShape(rayProgress + cameraPosition);
			float clearArea =  1.0-min(max(1.0 - length(rayProgress) / 100,0.0),1.0);
			density = min(volumeDensity, clearArea*clearArea * END_STORM_DENSTIY);
		#endif
		
		density = max(density/1000.0, _minimumDensity);

		// density = 0.0001;

		float volumeCoeff = exp(-dd*density*LPVRayLength);

		#if defined IS_LPV_ENABLED && defined LPV_VL_FOG_ILLUMINATION
			vec3 lpvPos = GetLpvPosition(rayProgress);

			vec3 cubicRadius = clamp(min(((LpvSize3-1.0) - lpvPos)/fadeLength, lpvPos/fadeLength), 0.0, 1.0);
			float LpvFadeF = cubicRadius.x*cubicRadius.y*cubicRadius.z;

			if(LpvFadeF < 0.01) break;

			vec3 sampleColor = SampleLpvLinear(lpvPos).rgb;
			#ifdef VANILLA_LIGHTMAP_MASK
				vec3 lighting = sampleColor * LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 25. * exp(-10 * (1.0-luma(sampleColor)));
			#else
				vec3 lighting = sampleColor * LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 25. * exp(-5 * (1.0-luma(sampleColor)));
			#endif

			if(eyeInWater) lighting *= 2.5;

			#ifdef LPV_VL_FOG_ILLUMINATION_HANDHELD
				float lightRange = 0.0;
				vec3 handLightCol = GetHandLight(heldItemId, rayProgress, lightRange);
				
				vec3 handLightCol2 = GetHandLight(heldItemId2, rayProgress, lightRange);

				lighting += (handLightCol + handLightCol2) * TORCH_AMOUNT * LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 0.04;
			#endif

			color.rgb += (lighting - lighting * volumeCoeff) * color.a;
		#endif

		#if defined FLASHLIGHT && defined FLASHLIGHT_FOG_ILLUMINATION

			#ifdef IEXT_ENABLED
				if (IEXT_KEY_0) continue;
			#endif

			// vec3 shiftedViewPos = mat3(gbufferModelView)*(progressW-cameraPosition) + vec3(-0.25, 0.2, 0.0);
			// vec3 shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos;
				vec3 shiftedViewPos;
				vec3 shiftedPlayerPos;
				float forwardOffset;

				#ifdef VIVECRAFT
					if (vivecraftIsVR) {
						forwardOffset = 0.0;
						shiftedPlayerPos = (rayProgress) + ( vivecraftRelativeMainHandPos);
						shiftedViewPos = shiftedPlayerPos * mat3(vivecraftRelativeMainHandRot);
					} else
				#endif
				{
					forwardOffset = 0.5;
					shiftedViewPos = mat3(gbufferModelView)*(rayProgress) + vec3(-0.25, 0.2, 0.0);
					shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos;
				}

			vec2 scaledViewPos = shiftedViewPos.xy / max(-shiftedViewPos.z - forwardOffset, 1e-7);
			float linearDistance = length(shiftedPlayerPos);
			float shiftedLinearDistance = length(scaledViewPos);

			float lightFalloff = 1.0 - clamp(1.0-linearDistance/FLASHLIGHT_RANGE, -0.999,1.0);
			lightFalloff = max(exp(-10.0 * FLASHLIGHT_BRIGHTNESS_FALLOFF_MULT * lightFalloff),0.0);
			float projectedCircle = clamp(1.0 - shiftedLinearDistance*FLASHLIGHT_SIZE,0.0,1.0);

			vec3 flashlightGlow = 25.0 * vec3(FLASHLIGHT_R,FLASHLIGHT_G,FLASHLIGHT_B) * lightFalloff * projectedCircle * FLASHLIGHT_BRIGHTNESS_MULT;

			color.rgb += (flashlightGlow - flashlightGlow * volumeCoeff) * color.a;
		#endif

		color.a *= volumeCoeff;
	}
	return color;
}

float invLinZ (float lindepth){
	return -((2.0*near/lindepth)-far-near)/(far-near);
}

/*
from https://blog.demofox.org/2022/01/01/interleaved-gradient-noise-a-different-kind-of-low-discrepancy-sequence/
Copyright 2019 Alan Wolfe

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
float interleaved_gradientNoise_temporal(){
	vec2 coord = gl_FragCoord.xy + 5.588238 * float(frameCounter%64);
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y)) ;
	return noise;
}
float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}

float blueNoise(){
  return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter );
}

float R2_dither(){
  	// #ifdef TAA
		vec2 coord = gl_FragCoord.xy + (frameCounter%40000) * 2.0;
	// #else
	// 	vec2 coord = gl_FragCoord.xy;
	// #endif
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * coord.x + alpha.y * coord.y ) ;
}

uniform float waterEnteredAltitude;
float lightSourceCheck = float(sunElevation > 1e-5)*2.0 - 1.0;

uniform vec3 fogColor;


float waterPhase(float VdotL) {
	// from https://www.desmos.com/calculator/tbl4g5bvlc

	const float ge = 100.0;
	const float gHG = -0.27;
	const float gHG2 = gHG*gHG;
	const float wk = 0.797;

	float fKN = ge / (2.0 * PI * (ge * (1.0 - VdotL) + 1.0) * log(2.0 * ge + 1.0));
	float fCS = (3.0 * (1.0 - gHG2)) / (8.0 * PI * (2.0 + gHG2)) * ((1.0 + VdotL * VdotL) / pow(1.0 + gHG2 - 2.0 * gHG * VdotL, 1.5));


	return fKN * wk + fCS * (1.0 - wk);
}

float waterPhase2(in float x)
	{
		const float g = 0.7;
		const float a = 0.9;
		float gg = g * g;
		return ((1 - gg)*(1 + a*x*x))/(4.*(1 + (a*(1 + 2*gg))/3.) * 3.1415926 * pow(1 + gg - 2*g*x,1.5));
	}

vec4 waterVolumetrics(vec3 rayStart, vec3 rayEnd, float rayLength, vec2 dither, vec3 waterCoefs, vec3 scatterCoef, vec3 ambient, vec3 lightSource, float VdotL, vec3 LPV){
	const int spCount = 8;

	vec3 start = toShadowSpaceProjected(rayStart);
	vec3 end = toShadowSpaceProjected(rayEnd);
	vec3 dV = (end-start);

	//limit ray length at 32 blocks for performance and reducing integration error
	//you can't see above this anyway
	float maxZ = min(rayLength,32.0)/(1e-8+rayLength);
	
	dV *= maxZ;
	rayLength *= maxZ;

	vec3 dVWorld = mat3(gbufferModelViewInverse) * (rayEnd - rayStart) * maxZ;

	vec3 absorbance = vec3(1.0);
	vec3 vL = vec3(0.0);
	
	#ifdef OVERWORLD_SHADER
		float phase = fogPhase(VdotL) * 5.0;
	#else
		const float phase = 0.0;
	#endif

	float thing = -normalize(dVWorld).y;
	thing = clamp(thing + 0.333,0.0,1.0);
	thing = pow(1.0-pow(1.0-thing,2.0),2.0);
	thing *= 15.0;

	const float expFactor = 11.0;
	for (int i=0;i<spCount;i++) {
		float d = (pow(expFactor, float(i+dither.x)/float(spCount))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);		// exponential step position (0-1)
		float dd = pow(expFactor, float(i+dither.y)/float(spCount)) * log(expFactor) / float(spCount)/(expFactor-1.0);	//step length (derivative)
		
		vec3 progressP = gbufferModelViewInverse[3].xyz + d*dVWorld;
		vec3 progressW = progressP + cameraPosition;
		
		float distanceFromWaterSurface = max(-(progressW.y - waterEnteredAltitude),0.0);

		vec3 sh = vec3(1.0);
		#ifdef OVERWORLD_SHADER
			vec3 spPos = start.xyz + dV*d;

			//project into biased shadowmap space
			#if defined DISTORT_SHADOWMAP && defined OVERWORLD_SHADER
				float distortFactor = calcDistort(spPos.xy);
			#else
				float distortFactor = 1.0;
			#endif

			vec3 pos = vec3(spPos.xy*distortFactor, spPos.z);
			if (abs(pos.x) < 1.0-0.5/2048. && abs(pos.y) < 1.0-0.5/2048){
				pos = pos*vec3(0.5,0.5,0.5/6.0)+0.5;
				// sh = texture( shadowtex0HW, pos).x;

				if (pos.z < 1.0 && pos.z > 0.0) {
					#ifdef TRANSLUCENT_COLORED_SHADOWS
						sh = vec3(texture(shadowtex0HW, pos).x);

						if(texture(shadowtex1HW, pos).x > pos.z && sh.x < 1.0){
							vec4 translucentShadow = texture(shadowcolor0, pos.xy);
							if(translucentShadow.a < 0.9) sh = normalize(translucentShadow.rgb+0.0001);
						}
					#else
						sh = vec3(texture(shadowtex0HW, pos).x);
					#endif
				}
			}

			sh *= GetCloudShadow(progressW, WsunVec * lightSourceCheck);

		#endif

		float bubble = exp2(-10.0 * clamp(1.0 - length(d*dVWorld) / 16.0, 0.0,1.0));
		float caustics = max(max(waterCaustics(progressW, WsunVec, -(progressW.y - waterEnteredAltitude)), phase*0.5) * mix(0.5, 1.5, bubble), phase);

		vec3 sunAbsorbance = exp(-waterCoefs * (distanceFromWaterSurface/abs(WsunVec.y)));
		vec3 WaterAbsorbance = exp(-waterCoefs * (distanceFromWaterSurface + thing));

		vec3 Directlight = lightSource * sh * phase * caustics * sunAbsorbance;

		vec3 _ambient = ambient;

		// #ifdef BIOME_TINT_WATER
		// 	_ambient *= sqrt(fogColor);
		// 	Directlight *= pow(fogColor, vec3(0.01,0.01,3.75));
		// #endif

		#ifdef OVERWORLD_SHADER
			float horizontalDist = length((progressP.xz) - lightningBoltPosition.xz);
			if (horizontalDist < 250.0 && lightningBoltPosition.w > 0.0) {
				float lightningIntensity = exp(-horizontalDist * 0.02) * lightningFlash;
				_ambient = mix(_ambient, vec3(1.3,1.5,3.0) * sh, lightningIntensity);
			}
		#endif

		vec3 Indirectlight = _ambient * WaterAbsorbance;

		#if defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED && defined LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER && !defined FLASHLIGHT
			float lightRange = 0.0;
			vec3 handLightCol = GetHandLight(heldItemId, progressP, lightRange);
			
			vec3 handLightCol2 = GetHandLight(heldItemId2, progressP, lightRange);

			Indirectlight += (handLightCol + handLightCol2) * TORCH_AMOUNT * (LPV_VL_FOG_ILLUMINATION_BRIGHTNESS / 100.0) * 0.2 * exp(-waterCoefs * (length(progressP) + 0.05 * thing));
		#endif


		vec3 light = (Indirectlight + Directlight + LPV) * scatterCoef;
		
		vec3 volumeCoeff = exp(-waterCoefs * length(dd*dVWorld));
		vL += (light - light * volumeCoeff) / waterCoefs * absorbance;
		absorbance *= volumeCoeff;

	}

	return vec4(vL, dot(absorbance,vec3(0.333333)));
}

vec4 blueNoise(vec2 coord){
  return texelFetch(colortex6, ivec2(coord)%512 , 0) ;
}
vec2 R2_samples(int n){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha * n);
}

float fogPhase2(float lightPoint){
	float linear = 1.0 - clamp(lightPoint*0.5+0.5,0.0,1.0);
	float linear2 = 1.0 - clamp(lightPoint,0.0,1.0);

	float exponential = exp2(pow(linear,0.3) * -15.0 ) * 1.5;
	exponential += sqrt(exp2(sqrt(linear) * -12.5));

	return exponential;
}
//encoding by jodie
float encodeVec2(vec2 a){
    const vec2 constant1 = vec2( 1., 256.) / 65535.;
    vec2 temp = floor( a * 255. );
	return temp.x*constant1.x+temp.y*constant1.y;
}



uniform int framemod8;
#include "/lib/TAA_jitter.glsl"

float convertHandDepth(float depth) {
    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;
    return ndcDepth * 0.5 + 0.5;
}

float swapperlinZ(float depth, float _near, float _far) {
    return (2.0 * _near) / (_far + _near - depth * (_far - _near));
	// l = (2*n)/(f+n-d(f-n))
	// f+n-d(f-n) = 2n/l
	// -d(f-n) = ((2n/l)-f-n)
	// d = -((2n/l)-f-n)/(f-n)

}


vec3 alterCoords(in vec3 coords, bool lighting){

	float theDistance = length(coords + (lighting ? vec3(0.0) : cameraPosition));

	coords.x = coords.x*3;

	coords.y = coords.y;

	coords.z = coords.z*3;
	
	return coords;
}

uniform float viewHeight;
uniform float viewWidth;
float godrayTest( in vec3 viewPos, in vec3 lightDir, float noise, float vanilladepth){

	// return 1.0;1

	float godrays = 0.0;
	float samples = 8.0;

	float _near = near; float _far = far*4.0;

	// #ifdef DISTANT_HORIZONS
	// 	bool depthCheck = true;
	// #else
	// 	bool depthCheck = false;
	// #endif

	bool depthCheck = true;

	if (depthCheck) {
		_near = dhVoxyNearPlane;
		_far = dhVoxyFarPlane;
	}
    
    float lightRange = pow(clamp(-dot(normalize(viewPos), lightDir)+0.65,0.0,1.0),2.0);
    vec3 position = toClipSpace3_DH(viewPos, depthCheck) ;
	
	//prevents the ray from going behind the camera
	float rayLength = ((viewPos.z + lightDir.z * _far * sqrt(3.)) > -_near) ? (-_near - viewPos.z) / lightDir.z : _far * sqrt(3.);

    vec3 direction = toClipSpace3_DH(viewPos + lightDir*rayLength, depthCheck) - position;

	direction.xyz = direction.xyz / max(max(abs(direction.x)/0.0005, abs(direction.y)/0.0005),500.0);	//fixed step size
	direction *= 60.0;
	
	position.xy *= RENDER_SCALE;
	direction.xy *= RENDER_SCALE;
	
	vec3 newPos = position + direction*noise;

  	vec2 screenEdges = 2.0/vec2(viewWidth, viewHeight);

	for (int i = 0; i < int(samples); i++) { 
		newPos.xy = clamp(newPos.xy, screenEdges, 1.0-screenEdges);

		float sampleDepth = invLinZ(sqrt(texelFetch(colortex4, ivec2(newPos.xy/texelSize/4.0),0).a/65000.0));
		
		#ifdef DISTANT_HORIZONS
			if(depthCheck) sampleDepth = texelFetch(dhDepthTex1, ivec2(newPos.xy/texelSize),0).x;
		#endif
		
		godrays += (swapperlinZ(sampleDepth, _near, _far) > 1.0 ? 1.0 : lightRange);
		newPos += direction;
	}

	return godrays/samples;
}

vec4 waterVolumetrics_alt( vec3 rayStart, vec3 rayEnd, float estEndDepth, float estSunDepth, float rayLength, float dither, vec3 waterCoefs, vec3 scatterCoef, vec3 ambient, vec3 lightSource, float VdotL){
	int spCount = rayMarchSampleCount;

	vec3 start = toShadowSpaceProjected(rayStart);
	vec3 end = toShadowSpaceProjected(rayEnd);
	vec3 dV = (end-start);

	//limit ray length at 32 blocks for performance and reducing integration error
	//you can't see above this anyway
	float maxZ = min(rayLength,12.0)/(1e-8+rayLength);
	dV *= maxZ;
	rayLength *= maxZ;
	estEndDepth *= maxZ;
	estSunDepth *= maxZ;
	
	vec3 dVWorld = mat3(gbufferModelViewInverse) * rayStart;
	vec3 wpos = dVWorld + gbufferModelViewInverse[3].xyz;
	
    #ifdef OVERWORLD_SHADER
		float phase = fogPhase(VdotL) * 5.0;
	#else
		const float phase = 1.0;
	#endif

	vec3 absorbance = vec3(1.0);
	vec3 vL = vec3(0.0);
	
	float expFactor = 11.0;
	vec3 sh = vec3(1.0);

	// do this outside raymarch loop, masking the water surface is good enough
	#if defined OVERWORLD_SHADER
		sh *= GetCloudShadow(wpos+cameraPosition, WsunVec);
	#endif
	
	float thing = -normalize(dVWorld).y;
	thing = clamp(thing - 0.333,0.0,1.0);
	thing = pow(1.0-pow(1.0-thing,2.0),2.0);
	thing *= 15.0;

	for (int i=0;i<spCount;i++) {
		float d = (pow(expFactor, float(i+dither)/float(spCount))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
		float dd = pow(expFactor, float(i+dither)/float(spCount)) * log(expFactor) / float(spCount)/(expFactor-1.0);

		#if defined OVERWORLD_SHADER || (defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED && defined LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER)
			vec3 progressP = gbufferModelViewInverse[3].xyz + d*dVWorld + dVWorld;
		#endif

		vec3 sh2 = sh;

		#ifdef OVERWORLD_SHADER
			vec3 spPos = start.xyz + dV*d;

			//project into biased shadowmap space
			#ifdef DISTORT_SHADOWMAP
				float distortFactor = calcDistort(spPos.xy);
			#else
				float distortFactor = 1.0;
			#endif

			vec3 pos = vec3(spPos.xy*distortFactor, spPos.z);
			if (abs(pos.x) < 1.0-0.5/2048. && abs(pos.y) < 1.0-0.5/2048.){
				pos = pos*vec3(0.5,0.5,0.5/6.0)+0.5;
				// sh = texture( shadowtex0HW, pos).x;

				if (pos.z < 1.0 && pos.z > 0.0) {
					#ifdef TRANSLUCENT_COLORED_SHADOWS
						sh2 *= vec3(texture(shadowtex0HW, pos).x);

						if(texture(shadowtex1HW, pos).x > pos.z && sh2.x < 1.0){
							vec4 translucentShadow = texture(shadowcolor0, pos.xy);
							if(translucentShadow.a < 0.9) sh2 = normalize(translucentShadow.rgb+0.0001);
						}
					#else
						sh2 *= vec3(texture(shadowtex0HW, pos).x);
					#endif
				}
			}
		#endif

		vec3 sunAbsorbance = exp(-waterCoefs * estSunDepth * d);
		vec3 ambientAbsorbance = exp(-waterCoefs * (estEndDepth * d + thing));

		vec3 Directlight = lightSource * sh2 * phase * sunAbsorbance;

		vec3 _ambient = ambient;

		#ifdef OVERWORLD_SHADER
			float horizontalDist = length(progressP.xz - lightningBoltPosition.xz);
			if (horizontalDist < 250.0 && lightningBoltPosition.w > 0.0) {
				float lightningIntensity = exp(-horizontalDist * 0.02) * lightningFlash;
				_ambient = mix(_ambient, vec3(1.3,1.5,3.0) * sh2, lightningIntensity);
			}
		#endif

		#if defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED && defined LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER && !defined FLASHLIGHT
			float lightRange = 0.0;
			vec3 handLightCol = GetHandLight(heldItemId, progressP, lightRange);
			
			vec3 handLightCol2 = GetHandLight(heldItemId2, progressP, lightRange);

			_ambient += (handLightCol + handLightCol2) * TORCH_AMOUNT * 0.225 * (LPV_VL_FOG_ILLUMINATION_BRIGHTNESS / 100.0);
		#endif

		vec3 Indirectlight = _ambient * ambientAbsorbance;

		vec3 light = (Indirectlight + Directlight) * scatterCoef;
		
		vec3 volumeCoeff = exp(-waterCoefs * dd * rayLength);
		vL += (light - light * volumeCoeff) / waterCoefs * absorbance;
		absorbance *= volumeCoeff;
	}
	
    return vec4(vL, dot(absorbance,vec3(0.333333)));
}

vec2 decodeVec2(float a){
    const vec2 constant1 = 65535. / vec2( 256., 65536.);
    const float constant2 = 256. / 255.;
    return fract( a * constant1 ) * constant2 ;
}


//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////


void main() {

	/* RENDERTARGETS:0,13 */

	gl_FragData[1] = vec4(0.0,0.0,0.0, 1.0);

	float noise_1 = interleaved_gradientNoise_temporal();
	// float noise_2 = blueNoise();
	// float noise_2 = interleaved_gradientNoise_temporal();
	vec2 bnoise = blueNoise(gl_FragCoord.xy ).rg;

	int seed = frameCounter%40000;
	vec2 r2_sequence = R2_samples(seed).xy*5.0;
	vec2 BN = fract(r2_sequence + bnoise);

	vec2 tc = floor(gl_FragCoord.xy)/VL_RENDER_SCALE*texelSize + texelSize*0.5;
	// vec2 tc = (gl_FragCoord.xy - 0.5)/VL_RENDER_SCALE*texelSize;

	// bool iswater = texture(colortex7,tc).a > 0.99;

	ivec2 texcoord = ivec2(tc/texelSize);

	float alpha = texelFetch(colortex7,texcoord,0).a ;
	float blendedAlpha = texelFetch(colortex2, texcoord,0).a;

	bool iswater = alpha > 0.99;

	float z0 = texelFetch(depthtex0, texcoord,0).x;
	
	// z0 = depth < 0.56 ? convertHandDepth(depth) : depth;

	#if defined DISTANT_HORIZONS || defined VOXY
		float DH_z0 = 0.0;
		
		if (z0 >= 1.0) DH_z0 = texelFetch(dhVoxyDepthTex, texcoord,0).x;
	#else
		float DH_z0 = 0.0;
	#endif
	
	vec3 viewPos0 = toScreenSpace_DH(tc/RENDER_SCALE, z0, DH_z0);
	vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos0 + gbufferModelViewInverse[3].xyz;
	vec3 playerPos_normalized = normalize(playerPos);

	// vec3 waterEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
	// vec3 dirtEpsilon = vec3(Dirt_Absorb_R, Dirt_Absorb_G, Dirt_Absorb_B);
	vec3 totEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
	vec3 scatterCoef = Dirt_Amount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / 3.14;

	vec3 directLightColor = lightSourceColorSSBO / 2400.0;

	vec3 directSunlightColor = sunColorSSBO / 2400.0;
	#ifdef CUSTOM_MOON_ROTATION
		directSunlightColor *= smoothstep(0.005, 0.09, length(WmoonVec - WrealSunVec));
	#endif

	vec3 directMoonlightColor = moonColorSSBO / 2400.0;
	#ifdef CUSTOM_MOON_ROTATION
		directMoonlightColor *= mix(0.0, 1.0, clamp(WmoonVec.y + 0.05, 0.0, 0.1)/0.1);
	#endif

	vec3 indirectLightColor = skyGroundColSSBO / 1200.0;
	vec3 indirectLightColor_dynamic = averageSkyCol_CloudsSSBO / 1200.0;

	// #if defined DISTANT_HORIZONS || defined VOXY
	//  	float godrays = godrayTest(viewPos0, normalize(WsunVec*mat3(gbufferModelViewInverse)),BN.x, z0);
	// #else
	// 	float godrays = 1.0;
	// #endif

	#if (defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED) || (defined FLASHLIGHT && defined FLASHLIGHT_FOG_ILLUMINATION)
		vec4 LPV_ILLUMINATION = raymarchLPV(viewPos0, BN.y);
	#else
		vec4 LPV_ILLUMINATION = vec4(0.0,0.0,0.0,1.0);
	#endif

	vec3 indirectLight = indirectLightColor_dynamic * skyLightLevelSmooth * ambient_brightness; 
    float minimumLightAmount = 0.02*nightVision + 0.001 * mix(MIN_LIGHT_AMOUNT_INSIDE, MIN_LIGHT_AMOUNT, clamp(skyLightLevelSmooth, 0.0, 1.0));
    indirectLight += vec3(1.0) * minimumLightAmount;
	
    vec3 indirectLight_fog = indirectLightColor * ambient_brightness; 
    indirectLight_fog += vec3(1.0) * (0.02*nightVision + 0.001 * mix(MIN_LIGHT_AMOUNT_INSIDE, MIN_LIGHT_AMOUNT, skyLightLevelSmooth));


	float cloudPlaneDistance = 0.0;
	vec2 cloudDistance = vec2(0.0); // r = cumulus, g = cumulonimbus

	vec4 VolumetricFog;
	#ifdef OVERWORLD_SHADER
		vec4 VolumetricClouds;
	#endif
	
	if (eyeInWater){
		vec4 underWaterFog =  waterVolumetrics(vec3(0.0), viewPos0, length(viewPos0), vec2(noise_1, BN.y), totEpsilon, scatterCoef, indirectLightColor_dynamic, directLightColor, dot(normalize(viewPos0), normalize(sunVec * lightSourceCheck)), LPV_ILLUMINATION.rgb);
		VolumetricFog = vec4(underWaterFog.rgb, 1.0);
	} else {
		#ifdef OVERWORLD_SHADER
			VolumetricClouds = GetVolumetricClouds(viewPos0, BN, WrealSunVec, WmoonVec, directSunlightColor, directMoonlightColor, indirectLightColor, cloudPlaneDistance, cloudDistance);
			
			#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
				imageStore(cloudDepthTex, ivec2(gl_FragCoord.xy), vec4(cloudDistance.r, cloudDistance.g, 0, 1));
			#endif

			#ifdef CAVE_FOG
				#if CAVE_DETECTION < 2
					#if CAVE_DETECTION == 1
						float caveFactor = 1.0 - smoothstep(60.0, 63.0, cameraPosition.y);
					#else
						const float caveFactor = 1.0;
					#endif
				#else
					const float caveFactor = 0.0;
				#endif

				float skyhole = pow(clamp(1.0-pow(max(playerPos_normalized.y - 0.6,0.0)*5.0,2.0),0.0,1.0),2)* caveDetection * caveFactor;
				VolumetricClouds.rgb *= 1.0-skyhole;
				VolumetricClouds.a = mix(VolumetricClouds.a, 1.0, skyhole);
			#endif

			VolumetricFog = GetVolumetricFog(viewPos0, WsunVec, BN, directLightColor, indirectLight_fog, indirectLightColor_dynamic, cloudPlaneDistance);

			#if (defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED) || (defined FLASHLIGHT && defined FLASHLIGHT_FOG_ILLUMINATION)
				VolumetricFog.a *= LPV_ILLUMINATION.a;
				VolumetricFog.rgb = VolumetricFog.rgb * LPV_ILLUMINATION.a + LPV_ILLUMINATION.rgb;
			#endif

			// for bloomy fog mask
			gl_FragData[1].a = VolumetricFog.a;

			VolumetricFog = vec4(VolumetricClouds.rgb * VolumetricFog.a  + VolumetricFog.rgb, VolumetricFog.a*VolumetricClouds.a);
		#endif
		
		#if defined NETHER_SHADER || defined END_SHADER
			VolumetricFog = GetVolumetricFog(viewPos0, noise_1, noise_1);

			#if (defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED) || (defined FLASHLIGHT && defined FLASHLIGHT_FOG_ILLUMINATION)
				VolumetricFog.a *= LPV_ILLUMINATION.a;
				VolumetricFog.rgb = VolumetricFog.rgb * LPV_ILLUMINATION.a + LPV_ILLUMINATION.rgb;
			#endif

			// for bloomy fog mask
			gl_FragData[1].a = VolumetricFog.a;
		#endif
	}

	// VolumetricFog = vec4(godrays,godrays,godrays,0.0);
	// VolumetricFog = raymarchTest(viewPos0, BN);
	// VolumetricFog = vec4(0.0,0.0,0.0,1.0);
	// VolumetricFog.rgb = vec3(0);

	gl_FragData[0] = clamp(VolumetricFog, 0.0, 65000.0);



	/// FOG BEHIND TRANSLUCENTS

	if(blendedAlpha > 0.0 || iswater){
		vec2 lightmap = decodeVec2(texelFetch(colortex14,texcoord,0).z);
		lightmap = min(max(lightmap - 0.05,0.0)*1.06,1.0);

		#ifndef OVERWORLD_SHADER
			lightmap.y = 1.0;
		#endif

		vec2 curvedLightmaps = lightmap;
		float lightmapBrightspot = min(max(lightmap.x-0.7,0.0)*3.3333,1.0);
		lightmapBrightspot *= lightmapBrightspot*lightmapBrightspot;
		float lightmapLight = 1.0-sqrt(1.0-lightmap.x);
		lightmapLight *= lightmapLight;
		curvedLightmaps.x = mix(lightmapLight, 2.5, lightmapBrightspot);
		curvedLightmaps.y = (pow(lightmap.y,15.0)*2.0 + lightmap.y*lightmap.y)/3.0;

		float z1 = texelFetch(depthtex1, texcoord,0).x;

		#if defined DISTANT_HORIZONS || defined VOXY
			float DH_z1 = 0.0;
			if (z1 >= 1.0) DH_z1 = texelFetch(dhVoxyDepthTex1, texcoord,0).x;
		#else
			float DH_z1 = 0.0;
		#endif

		vec3 viewPos1 = toScreenSpace_DH(tc/RENDER_SCALE, z1, DH_z1);

		indirectLight = indirectLightColor_dynamic * skyLightLevelSmooth * ambient_brightness;


		if(iswater && !eyeInWater){
			float Vdiff = distance(viewPos1, viewPos0);
			float estimatedDepth = Vdiff * abs(playerPos_normalized.y);
			float estimatedSunDepth = Vdiff / abs(WsunVec.y); //assuming water plane

			float lightleakfix = clamp(lightmap.y + (1.0-caveDetection),0.0,1.0);

			directLightColor *= lightleakfix;

			// #ifdef BIOME_TINT_WATER
			// 	vec4 data = texelFetch(colortex11,texcoord,0).rgba;			
			// 	bool isBlockBreaking = data.a > 0.99;
// 
// 
			// 	if(!isBlockBreaking) {
			// 		vec4 albedo = vec4(decodeVec2(data.g),decodeVec2(data.b));
			// 		scatterCoef *= 0.85 + vec3(0.35,0.35,1.0)*log(albedo.rgb + 1e-6);
			// 	}
			// #endif

			indirectLight *= curvedLightmaps.y;

			indirectLight += mix(MIN_LIGHT_AMOUNT * 0.004 + nightVision*0.02, MIN_LIGHT_AMOUNT_INSIDE * 0.004 + nightVision*0.02, 1.0 - lightmap.y);

			indirectLight += vec3(TORCH_R,TORCH_G,TORCH_B)	* curvedLightmaps.x  * TORCH_AMOUNT * blendedAlpha;

			VolumetricFog = waterVolumetrics_alt(viewPos0, viewPos1, estimatedDepth, estimatedSunDepth, Vdiff, noise_1, totEpsilon, scatterCoef, indirectLight, directLightColor, dot(normalize(viewPos0), normalize(sunVec*lightSourceCheck)));
		} else {
			#if defined OVERWORLD_SHADER
				VolumetricClouds = GetVolumetricClouds(viewPos1, vec2(noise_1), WrealSunVec, WmoonVec, directSunlightColor, directMoonlightColor, indirectLightColor, cloudPlaneDistance, cloudDistance);

				#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
					imageStore(cloudDepthTex, ivec2(gl_FragCoord.xy), vec4(cloudDistance.r, cloudDistance.g, 0, 1));
				#endif
		
				VolumetricFog = GetVolumetricFog(viewPos1, WsunVec, vec2(noise_1), directLightColor, indirectLight_fog, indirectLight, cloudPlaneDistance);

				VolumetricFog = vec4(VolumetricClouds.rgb*VolumetricFog.a + VolumetricFog.rgb, VolumetricFog.a*VolumetricClouds.a);
			#endif
			
			#if defined NETHER_SHADER || defined END_SHADER
				VolumetricFog = GetVolumetricFog(viewPos1, noise_1, noise_1);
			#endif
		}
		
		gl_FragData[1] = clamp(VolumetricFog, 0.0, 65000.0);
	}
}