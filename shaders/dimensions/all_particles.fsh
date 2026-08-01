#if defined IS_LPV_ENABLED || defined PHOTONICS && defined PHOTONICS && !defined PH_ENABLE_HANDHELD_LIGHT
	#extension GL_ARB_shader_image_load_store: enable
	#extension GL_ARB_shading_language_packing: enable
#endif

#if defined DAMAGE_BLOCK_EFFECT && defined POM
	#extension GL_ARB_shader_texture_lod : enable
#endif

#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0 && defined OVERWORLD_SHADER && defined COLORWHEEL
	#extension GL_NV_gpu_shader5 : enable
	#extension GL_ARB_shader_image_load_store : enable
#endif

#include "/lib/settings.glsl"

#include "/lib/SSBOs.glsl"

// #if defined END_SHADER || defined NETHER_SHADER
// 	#undef IS_LPV_ENABLED
// #endif

#include "/lib/res_params.glsl"

in DATA {
	vec4 lmtexcoord;
	vec4 color;

	#if defined DAMAGE_BLOCK_EFFECT && defined POM
		vec4 tangent;
		vec3 normalMat;

		vec4 texcoordam; // .st for add, .pq for mul
		vec2 texcoord;
	#endif

	#ifdef OVERWORLD_SHADER
		flat vec3 WsunVec;
	#endif
};

#ifdef OVERWORLD_SHADER
	const bool shadowHardwareFiltering = true;
	uniform sampler2DShadow shadowtex0HW;
	
	#ifdef TRANSLUCENT_COLORED_SHADOWS
		uniform sampler2D shadowcolor0;
		uniform sampler2DShadow shadowtex1HW;
	#endif
#endif

uniform int renderStage;
uniform int isEyeInWater;
uniform vec3 sunPosition;

uniform sampler2D gtexture;
uniform sampler2D noisetex;
uniform sampler2D colortex4;

#if defined IS_LPV_ENABLED || defined PHOTONICS && defined PHOTONICS && !defined PH_ENABLE_HANDHELD_LIGHT
	uniform usampler1D texBlockData;
	uniform sampler3D texLpv1;
	uniform sampler3D texLpv2;
#endif

// uniform mat4 gbufferProjectionInverse;
// uniform mat4 gbufferModelViewInverse;
// uniform mat4 gbufferModelView;
// uniform mat4 shadowModelView;
// uniform mat4 shadowProjection;
// uniform vec3 cameraPosition;

uniform float frameTimeCounter;
#include "/lib/Shadow_Params.glsl"

uniform vec2 texelSize;

uniform ivec2 eyeBrightnessSmooth;
uniform float rainStrength;
uniform float nightVision;
uniform float waterEnteredAltitude;


uniform mat4 gbufferPreviousModelView;
uniform vec3 previousCameraPosition;
uniform vec3 relativeEyePosition;


#include "/lib/util.glsl"
#include "/lib/projections.glsl"

#ifdef OVERWORLD_SHADER
	
	#include "/lib/scene_controller.glsl"

	#if defined CUSTOM_MOON_ROTATION && LIGHTNING_SHADOWS > 0
		uniform vec4 lightningBoltPosition;
		uniform float sunElevation;
	#endif

	#define CLOUDSHADOWSONLY
	
	#include "/lib/volumetricClouds.glsl"
#endif

uniform int frameCounter;

uniform int heldItemId;
uniform int heldItemId2;

// #if defined IS_LPV_ENABLED || RAINBOW_SELECT_BOX > 0
	#include "/lib/hsv.glsl"
// #endif

#if defined IS_LPV_ENABLED || defined PHOTONICS && defined PHOTONICS && !defined PH_ENABLE_HANDHELD_LIGHT
	#include "/lib/lpv_blocks.glsl"
	#include "/lib/lpv_common.glsl"
	#include "/lib/lpv_render.glsl"
#endif

#undef FLASHLIGHT_BOUNCED_INDIRECT

#if defined VIVECRAFT
	uniform bool vivecraftIsVR;
	uniform vec3 vivecraftRelativeMainHandPos;
	uniform vec3 vivecraftRelativeOffHandPos;
	uniform mat4 vivecraftRelativeMainHandRot;
	uniform mat4 vivecraftRelativeOffHandRot;
#endif

#include "/lib/diffuse_lighting.glsl"
#include "/lib/sky_gradient.glsl"

vec3 toLinear(vec3 sRGB){
	return sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878);
}

// #define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)

// vec3 toScreenSpace(vec3 p) {
// 	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
//     vec3 p3 = p * 2. - 1.;
//     vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
//     return fragposition.xyz / fragposition.w;
// }

uniform int framemod8;

#include "/lib/TAA_jitter.glsl"

#ifdef TAA
	float blueNoise() {
		return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
	} 
#else
	float blueNoise() {
		return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887);
	}
#endif

//Mie phase function
float phaseg(float x, float g){
    float gg = g * g;
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14;
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

// #undef BASIC_SHADOW_FILTER
#if defined OVERWORLD_SHADER
float ComputeShadowMap(inout vec3 directLightColor, vec3 playerPos, float maxDistFade){

	// if(maxDistFade <= 0.0) return 1.0;

	// setup shadow projection
	#ifdef CUSTOM_MOON_ROTATION
		vec3 projectedShadowPosition = mat3(customShadowMatrixSSBO) * playerPos  + customShadowMatrixSSBO[3].xyz;
	#else
		vec3 projectedShadowPosition = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
	#endif
	projectedShadowPosition = diagonal3(shadowProjection) * projectedShadowPosition + shadowProjection[3].xyz;
	// un-distort
	#ifdef DISTORT_SHADOWMAP
		float distortFactor = calcDistort(projectedShadowPosition.xy);
		projectedShadowPosition.xy *= distortFactor;
	#else
		float distortFactor = 1.0;
	#endif

	//vec4 shadowPos = customShadowPerspectiveSSBO * (customShadowMatrixSSBO * vec4(playerPos, 1.0));
	//projectedShadowPosition = shadowPos.xyz / shadowPos.w;

	// hamburger
	projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5);
	
	float shadowmap = 0.0;
	vec3 translucentTint = vec3(0.0);

	if (projectedShadowPosition.z > 1.0 || projectedShadowPosition.z < 0.0) return 1.0;

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

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		// tint the lightsource color with the translucent shadow color
		directLightColor *= mix(vec3(1.0), translucentTint.rgb, maxDistFade);
	#endif

	return shadowmap;
	// return mix(1.0, shadowmap, maxDistFade);
}
#endif

uniform sampler2D normals;
uniform sampler2D specular;

#if defined DAMAGE_BLOCK_EFFECT && defined POM	
	mat3 inverseMatrix(mat3 m) {
	  float a00 = m[0][0], a01 = m[0][1], a02 = m[0][2];
	  float a10 = m[1][0], a11 = m[1][1], a12 = m[1][2];
	  float a20 = m[2][0], a21 = m[2][1], a22 = m[2][2];
	
	  float b01 = a22 * a11 - a12 * a21;
	  float b11 = -a22 * a10 + a12 * a20;
	  float b21 = a21 * a10 - a11 * a20;
	
	  float det = a00 * b01 + a01 * b11 + a02 * b21;
	
	  return mat3(b01, (-a22 * a01 + a02 * a21), (a12 * a01 - a02 * a11),
	              b11, (a22 * a00 - a02 * a20), (-a12 * a00 + a02 * a10),
	              b21, (-a21 * a00 + a01 * a20), (a11 * a00 - a01 * a10)) / det;
	}
	const float MAX_OCCLUSION_DISTANCE = MAX_DIST;
	const float MIX_OCCLUSION_DISTANCE = MAX_DIST*0.9;
	const int   MAX_OCCLUSION_POINTS   = MAX_ITERATIONS;
	
	vec2 dcdx = dFdx(texcoord.st*texcoordam.pq);
	vec2 dcdy = dFdy(texcoord.st*texcoordam.pq);
	
	#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
	#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

	const float mincoord = 1.0/4096.0;
	const float maxcoord = 1.0-mincoord;

	vec4 readNormal(in vec2 coord)
	{
		return textureGrad(normals,fract(coord)*texcoordam.pq+texcoordam.st,dcdx,dcdy);
	}
	vec4 readTexture(in vec2 coord)
	{
		return textureGrad(gtexture,fract(coord)*texcoordam.pq+texcoordam.st,dcdx,dcdy);
	}
	vec4 texture_POMSwitch(sampler2D sampler, vec2 lightmapCoord, vec4 dcdxdcdy){
		return textureGrad(sampler, lightmapCoord, dcdxdcdy.xy, dcdxdcdy.zw);
	}
#endif

uniform float near;
// uniform float far;
float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}


float luma(vec3 color) {
	return dot(color,vec3(0.21, 0.72, 0.07));
}

#if defined DISTANT_HORIZONS && DH_CHUNK_FADING > 0
	float R2_dither(){
		vec2 coord = gl_FragCoord.xy ;

		#ifdef TAA
			coord += + (frameCounter%40000) * 2.0;
		#endif
		
		vec2 alpha = vec2(0.75487765, 0.56984026);
		return fract(alpha.x * coord.x + alpha.y * coord.y ) ;
	}
#endif

vec2 encodeNormal(vec3 n){
	n.xy = n.xy / dot(abs(n), vec3(1.0));
	n.xy = n.z <= 0.0 ? (1.0 - abs(n.yx)) * sign(n.xy) : n.xy;
    vec2 encn = clamp(n.xy * 0.5 + 0.5,-1.0,1.0);
	
    return encn;
}

vec3 viewToWorld(vec3 viewPosition) {
    vec4 pos;
    pos.xyz = viewPosition;
    pos.w = 0.0;
    pos = gbufferModelViewInverse * pos;
    return pos.xyz;
}
vec3 worldToView(vec3 worldPos) {
    vec4 pos = vec4(worldPos, 0.0);
    pos = gbufferModelView * pos;
    return pos.xyz;
}

vec3 applyBump(mat3 tbnMatrix, vec3 bump){
	float bumpmult = NORMAL_MAP_MULT;
	bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);
	return normalize(bump*tbnMatrix);
}

uniform float alphaTestRef;
uniform vec3 playerLookVector;

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

#ifdef DAMAGE_BLOCK_EFFECT
	/* RENDERTARGETS:11 */
#elif defined PARTICLES_SOLID
	/* RENDERTARGETS:1,8 */
	layout(location = 0) out vec4 OutAlbedo;
	layout(location = 1) out vec4 OutSpecular;
#else
	/* RENDERTARGETS:2,9,11,7 */
#endif

void main() {

#ifdef DAMAGE_BLOCK_EFFECT
	vec2 adjustedTexCoord = lmtexcoord.xy;
	#ifdef POM
		vec3 fragpos = toScreenSpace(gl_FragCoord.xyz*vec3(texelSize/RENDER_SCALE,1.0));

		// vec3 worldpos = mat3(gbufferModelViewInverse) * fragpos  + gbufferModelViewInverse[3].xyz + cameraPosition;

		vec3 normal = normalMat;
		vec3 tangent2 = normalize(cross(tangent.rgb,normal)*tangent.w);
		mat3 tbnMatrix = mat3(tangent.x, tangent2.x, normal.x,
							  tangent.y, tangent2.y, normal.y,
							  tangent.z, tangent2.z, normal.z);

		adjustedTexCoord = fract(texcoord.st)*texcoordam.pq+texcoordam.st;
		vec3 viewVector = normalize(tbnMatrix*fragpos);

		float dist = length(fragpos);

		float maxdist = MAX_OCCLUSION_DISTANCE;
		if (dist < maxdist) {

			float depthmap = readNormal(texcoord.st).a;
			float used_POM_DEPTH = 1.0;

	 		if ( viewVector.z < 0.0 && depthmap < 0.9999 && depthmap > 0.00001) {	

				#ifdef Adaptive_Step_length
					vec3 interval = (viewVector.xyz /-viewVector.z/MAX_OCCLUSION_POINTS * POM_DEPTH) * clamp(1.0-pow(depthmap,2),0.1,1.0);
					used_POM_DEPTH = 1.0;
				#else
					vec3 interval = viewVector.xyz/-viewVector.z/ MAX_OCCLUSION_POINTS*POM_DEPTH;
				#endif
				vec3 coord = vec3(texcoord.st, 1.0);

				coord += interval * used_POM_DEPTH;

				float sumVec = 0.5;
				for (int loopCount = 0; (loopCount < MAX_OCCLUSION_POINTS) && (1.0 - POM_DEPTH + POM_DEPTH * readNormal(coord.st).a  ) < coord.p && coord.p >= 0.0; ++loopCount) {
					coord = coord + interval * used_POM_DEPTH; 
					sumVec += used_POM_DEPTH; 
				}

				if (coord.t < mincoord) {
					if (readTexture(vec2(coord.s,mincoord)).a == 0.0) {
						coord.t = mincoord;
						discard;
					}
				}

				adjustedTexCoord = mix(fract(coord.st)*texcoordam.pq+texcoordam.st, adjustedTexCoord, max(dist-MIX_OCCLUSION_DISTANCE,0.0)/(MAX_OCCLUSION_DISTANCE-MIX_OCCLUSION_DISTANCE));
			}
		}

		vec4 Albedo = texture_POMSwitch(gtexture, adjustedTexCoord.xy, vec4(dcdx,dcdy));
	#else
		vec4 Albedo = texture(gtexture, adjustedTexCoord.xy);
	#endif

	#ifdef COLORWHEEL
		float ao;
		vec4 overlayColor;
		vec2 lmcoord = lmtexcoord.zw;

		clrwl_computeFragment(Albedo, Albedo, lmcoord, ao, overlayColor);
		Albedo.rgb = mix(Albedo.rgb, overlayColor.rgb, overlayColor.a);
	#endif
	
	if(Albedo.a < 0.01 ) { discard; return; }

	Albedo.rgb = toLinear(Albedo.rgb);

	// if(dot(Albedo.rgb, vec3(0.33333)) < 1.0/255.0 || Albedo.a < 0.01 ) { discard; return; }
	

	gl_FragData[0] = vec4(encodeVec2(vec2(0.5)), encodeVec2(Albedo.rg), encodeVec2(vec2(Albedo.b,0.02)), 1.0);
#endif

#if !defined DAMAGE_BLOCK_EFFECT && !defined PARTICLES_SOLID
	gl_FragData[2] = vec4(0.0);
	
	#ifdef LINES
		#if MC_VERSION == 12101
			bool selectionBox = dot(color.rgb,vec3(0.33333)) < 0.00001;
		#else
			bool selectionBox = renderStage == MC_RENDER_STAGE_OUTLINE;
		#endif
		#ifndef SELECT_BOX
			if(selectionBox) discard;
		#endif
	#endif

	vec2 tempOffset = offsets[framemod8];
	vec3 viewPos = toScreenSpace(gl_FragCoord.xyz*vec3(texelSize/RENDER_SCALE,1.0)-vec3(vec2(tempOffset)*texelSize*0.5,0.0));
	vec3 feetPlayerPos = mat3(gbufferModelViewInverse) * viewPos;
	// vec3 feetPlayerPos_normalized = normalize(feetPlayerPos);

	vec4 TEXTURE = texture(gtexture, lmtexcoord.xy)*color;
	
	#ifdef WhiteWorld
		TEXTURE.rgb = vec3(0.5);
	#endif

	vec3 Albedo = toLinear(TEXTURE.rgb);

	///////////////////////// BLOCKLIGHT LIGHTING OR LPV LIGHTING OR FLOODFILL COLORED LIGHTING
	vec2 lightmap = clamp(lmtexcoord.zw,0.0,1.0);

	#ifndef OVERWORLD_SHADER
		lightmap.y = 1.0;
	#endif

	#if defined Hand_Held_lights && !defined LPV_ENABLED
		#ifdef IS_IRIS
			vec3 playerCamPos = relativeEyePosition;
		#else
			vec3 playerCamPos = vec3(0.0);
		#endif
		// lightmap.x = max(lightmap.x, HELD_ITEM_BRIGHTNESS * clamp( pow(max(1.0-length((feetPlayerPos+cameraPosition) - playerCamPos)/HANDHELD_LIGHT_RANGE,0.0),1.5),0.0,1.0));
		if(heldItemId > 999 || heldItemId2 > 999){ 
			float pointLight = clamp(1.0-(length(feetPlayerPos-playerCamPos)-1.0)/HANDHELD_LIGHT_RANGE,0.0,1.0);
			lightmap.x = mix(lightmap.x, 0.9, pointLight*pointLight);
		}
	
	#endif

	#ifdef WEATHER
		// remove very close rain
		TEXTURE.a *= smoothstep(0.15, 1.5, length(feetPlayerPos));

		#if RAIN_MODE == 1
			if(TEXTURE.a > 0.01) {
				#ifdef IS_LPV_ENABLED
					vec3 lpvPos = GetLpvPosition(feetPlayerPos);
				#else
					const vec3 lpvPos = vec3(0.0);
				#endif

				vec3 Indirect_lighting = doBlockLightLighting(vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, feetPlayerPos, lpvPos);

				#ifdef FLASHLIGHT
					vec4 flashLightSpecularData = vec4(0.0);
					Indirect_lighting += 0.3*calculateFlashlight(gl_FragCoord.xy*texelSize/RENDER_SCALE, viewPos, vec3(0.0), -normalize(feetPlayerPos), flashLightSpecularData, false);
				#endif

				TEXTURE.rgb *= Indirect_lighting + averageSkyCol_CloudsSSBO / 360.0;
			}
		#endif

		// not linearizing since it kinda looks better like that
		gl_FragData[1] = vec4(TEXTURE); // for bloomy rain and stuff
	#endif

	#ifndef WEATHER
		float viewDist = length(feetPlayerPos + gbufferModelViewInverse[3].xyz);
		vec3 worldPos = feetPlayerPos + cameraPosition;

		#ifndef LINES
			gl_FragData[0].a = TEXTURE.a;
		#else
			gl_FragData[0].a = color.a;
		#endif
		#ifndef BLOOMY_PARTICLES
			gl_FragData[1] = vec4(0.0); // for bloomy rain and stuff
		#endif

		gl_FragData[3] = vec4(0.0,0.0,0.0,0.4);

		vec3 Direct_lighting = vec3(0.0);
		vec3 directLightColor = vec3(0.0);

		vec3 Indirect_lighting = vec3(0.0);
		vec3 AmbientLightColor = vec3(0.0);
		vec3 Torch_Color = vec3(TORCH_R,TORCH_G,TORCH_B);
		vec3 MinimumLightColor = vec3(1.0);

		if(lightmap.x >= 0.9) Torch_Color *= LIT_PARTICLE_BRIGHTNESS;

		#ifdef OVERWORLD_SHADER
			directLightColor =  lightSourceColorSSBO/2400.0;
			AmbientLightColor = averageSkyCol_CloudsSSBO / 900.0;
		
			#ifdef USE_CUSTOM_DIFFUSE_LIGHTING_COLORS
				directLightColor = luma(directLightColor) * vec3(DIRECTLIGHT_DIFFUSE_R,DIRECTLIGHT_DIFFUSE_G,DIRECTLIGHT_DIFFUSE_B);
				AmbientLightColor = luma(AmbientLightColor) * vec3(INDIRECTLIGHT_DIFFUSE_R,INDIRECTLIGHT_DIFFUSE_G,INDIRECTLIGHT_DIFFUSE_B);
			#endif
			
			
			float Shadows = 1.0;

			vec3 shadowPlayerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;

			float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(shadowPlayerPos) / (shadowDistance+16),0.0)*5.0,1.0));
			float shadowMapFalloff2 = smoothstep(0.0, 1.0, min(max(1.0 - length(shadowPlayerPos) / (shadowDistance+11),0.0)*5.0,1.0));

			float LM_shadowMapFallback = min(max(lightmap.y-0.8, 0.0) * 25,1.0);

			Shadows = ComputeShadowMap(directLightColor, shadowPlayerPos, shadowMapFalloff);

			Shadows *= mix(LM_shadowMapFallback, 1.0, shadowMapFalloff2);

			Shadows *= GetCloudShadow(worldPos, WsunVec);

			if(isEyeInWater == 1){
	  			float distanceFromWaterSurface = max(-(worldPos.y - waterEnteredAltitude),0.0) ;
				directLightColor *= exp(-vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B) * distanceFromWaterSurface);
			}
			Direct_lighting = directLightColor * Shadows;

			// #ifndef LINES
			// 	Direct_lighting *= phaseg(clamp(dot(feetPlayerPos_normalized, WsunVec),0.0,1.0), 0.65)*2 + 0.5;
			// #endif


			#ifdef IS_IRIS
				AmbientLightColor *= 2.5;
			#else
				AmbientLightColor *= 0.5;
			#endif
			
			Indirect_lighting = doIndirectLighting(AmbientLightColor, MinimumLightColor, lightmap.y);
		#endif
		
		#ifdef NETHER_SHADER
			Indirect_lighting = volumetricsFromTex(vec3(0.0,1.0,0.0), colortex4, 6).rgb / 1200.0;
		#endif

		#ifdef END_SHADER
			Indirect_lighting = vec3(AmbientLightEnd_R,AmbientLightEnd_G,AmbientLightEnd_B) * 0.1;
		#endif

		///////////////////////// BLOCKLIGHT LIGHTING OR LPV LIGHTING OR FLOODFILL COLORED LIGHTING
		#ifdef IS_LPV_ENABLED
			vec3 lpvPos = GetLpvPosition(feetPlayerPos);
		#else
			const vec3 lpvPos = vec3(0.0);
		#endif

		Indirect_lighting += doBlockLightLighting( vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, feetPlayerPos, lpvPos);

		#ifdef LINES
			gl_FragData[0].rgb = (Indirect_lighting + Direct_lighting) * toLinear(color.rgb);

			#if RAINBOW_SELECT_BOX > 0
				#if RAINBOW_SELECT_BOX == 1
					float selectBoxHue = length(sin(mod(1.4*worldPos, 3.14159)));
				#else
					float selectBoxHue = length(sin(mod(1.4*worldPos+0.7*frameTimeCounter, 3.14159)));
				#endif

				vec3 selectBoxColor = HsvToRgb(vec3(selectBoxHue, 1.0, 1.0));
				if(selectionBox) gl_FragData[0] = vec4(toLinear(selectBoxColor), 1.0);
			#else
				if(selectionBox) gl_FragData[0] = vec4(toLinear(vec3(SELECT_BOX_COL_R, SELECT_BOX_COL_G, SELECT_BOX_COL_B)), 1.0);
			#endif
			
			// float LITEMATICA_SCHEMATIC_THING_MASK = 0.0;
			// if (renderStage == MC_RENDER_STAGE_NONE){
			// 	LITEMATICA_SCHEMATIC_THING_MASK = 0.1;
			// 	gl_FragData[0] = vec4(toLinear(color.rgb), color.a);
			// }

			// gl_FragData[2] = vec4(encodeVec2(vec2(0.0)), encodeVec2(vec2(0.0)), encodeVec2(vec2(0.0)), encodeVec2(0.0, LITEMATICA_SCHEMATIC_THING_MASK));

			// if (length(viewPos-normalize(sunPosition)*viewDist) < 0.03*viewDist && selectionBox) discard; // dirty fix for sun shining through selection box
		#else
			gl_FragData[0].rgb = (Indirect_lighting + Direct_lighting) * Albedo;
		#endif

		#if defined PARTICLES && !defined LIT
			if(TEXTURE.a > 0.0 && renderStage == MC_RENDER_STAGE_WORLD_BORDER) {
				float BN = blueNoise();

				// distance fade targeting the world border...
				float distanceFade = clamp(2.5 - length(feetPlayerPos) / (0.1*min(far, 225.0)),0.0,1.0);

				if(distanceFade < BN) discard;
			}
		#endif

		gl_FragData[0].rgb *= 0.1;	

		#if defined DISTANT_HORIZONS && DH_CHUNK_FADING > 0
				float ditherFade = smoothstep(0.98*far, 1.0*far, viewDist);

				if (step(ditherFade, R2_dither()) == 0.0) discard;
		#endif
	#endif
#endif

#ifdef PARTICLES_SOLID

	vec4 Albedo = texture(gtexture, lmtexcoord.xy) * color;
	if(Albedo.a < alphaTestRef){discard; return;}

	vec3 tangent  = normalize(mat3(gbufferModelViewInverse) * vec3(1.0, 0.0,  0.0));
	vec3 binormal = normalize(mat3(gbufferModelViewInverse) * vec3(0.0, 1.0,  0.0));
	vec3 normal   = normalize(mat3(gbufferModelViewInverse) * vec3(0.0, 0.0,  1.0));

	mat3 tbnMatrix = mat3(tangent.x,  binormal.x,  normal.x,
                      tangent.y,  binormal.y,  normal.y,
                      tangent.z,  binormal.z,  normal.z);

	vec4 NormalTex = texture(normals, lmtexcoord.xy);
			
	#if defined MATERIAL_AO && defined MC_TEXTURE_FORMAT_LAB_PBR
		Albedo.rgb *= NormalTex.b*0.5+0.5;
	#endif

	NormalTex.xy = NormalTex.xy * 2.0-1.0;
	NormalTex.z = sqrt(max(1.0 - dot(NormalTex.xy, NormalTex.xy), 0.0));

	normal = applyBump(tbnMatrix, NormalTex.xyz);
	
	vec2 lightmap = clamp(lmtexcoord.zw,0.0,1.0);
	
	vec4 data1 = vec4(encodeNormal(normal), lightmap);

	Albedo = clamp(vec4(Albedo.rgb,0.85),0.0,1.0);
	data1 = clamp(data1,0.0,1.0);

	OutAlbedo = vec4(
		encodeVec2(Albedo.x,data1.x),
	 	encodeVec2(Albedo.y,data1.y),
	  	encodeVec2(Albedo.z,data1.z),
	   	encodeVec2(data1.w,Albedo.w)
	);
	
	#if EMISSIVE_TYPE >= 2 || SSS_TYPE >= 2
		vec4 specularData = texture(specular, lmtexcoord.xy);
	#else
		vec4 specularData = vec4(0.0);
	#endif

	vec4 otherData = clamp(vec4(normal*0.5+0.5, 0.0),0.0,1.0);
	
	OutSpecular = vec4(
		encodeVec2(specularData.x, otherData.x),
		encodeVec2(specularData.y, otherData.y),
		encodeVec2(specularData.z, otherData.z),
		encodeVec2(specularData.w, otherData.w)
	);

#endif
}