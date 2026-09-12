#include "/lib/settings.glsl"

#include "/lib/SSBOs.glsl"

#include "/lib/util.glsl"
#include "/lib/res_params.glsl"
#include "/lib/color_transforms.glsl"
#include "/lib/projections.glsl"

#ifdef OVERWORLD_SHADER
	#define WATER_SUN_SPECULAR
#endif

uniform vec2 texelSize;
// uniform int moonPhase;
uniform float frameTimeCounter;
uniform sampler2D noisetex;

const bool shadowHardwareFiltering = true;
uniform sampler2DShadow shadowtex0HW;

uniform sampler2D dhDepthTex;
uniform sampler2D dhDepthTex1;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform sampler2D colortex11;
uniform sampler2D colortex12;
// uniform sampler2D colortex7;
uniform sampler2D colortex4;
uniform sampler2D colortex5;


#include "/lib/sky_gradient.glsl"
#include "/lib/waterBump.glsl"
#include "/lib/Shadow_Params.glsl"

in DATA {
	vec4 pos;
	vec4 gcolor;
		
	vec4 normalMat;
	vec2 lightmapCoords;
	flat int isWater;

	mat4 normalmatrix;

	flat vec3 WsunVec;
	flat vec3 WsunVec2;
};


// uniform float far;
uniform float dhVoxyFarPlane;
uniform float dhVoxyNearPlane;

uniform vec3 previousCameraPosition;
// uniform vec3 cameraPosition;

// uniform mat4 gbufferModelView;
uniform mat4 gbufferPreviousModelView;

// uniform mat4 shadowModelView;
// uniform mat4 shadowModelViewInverse;
// uniform mat4 shadowProjection;
// uniform mat4 shadowProjectionInverse;



uniform int frameCounter;


// uniform sampler2D colortex4;



// uniform mat4 dhPreviousProjection;
// uniform mat4 dhProjectionInverse;
// uniform mat4 dhProjection;



#include "/lib/DistantHorizons_projections.glsl"

vec3 DH_toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(dhProjectionInverse[0].x, dhProjectionInverse[1].y, dhProjectionInverse[2].zw);
    vec3 feetPlayerPos = p * 2. - 1.;
    vec4 viewPos = iProjDiag * feetPlayerPos.xyzz + dhProjectionInverse[3];
    return viewPos.xyz / viewPos.w;
}

vec3 DH_toClipSpace3(vec3 viewSpacePosition) {
    return projMAD(dhProjection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
}
uniform float near;
float invLinZ (float lindepth){
	return -((2.0*near/lindepth)-far-near)/(far-near);
}
float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}

// float DH_ld(float dist) {
//     return (2.0 * dhVoxyNearPlane) / (dhVoxyFarPlane + dhVoxyNearPlane - dist * (dhVoxyFarPlane - dhVoxyNearPlane));
// }
// float DH_invLinZ (float lindepth){
// 	return -((2.0*dhVoxyNearPlane/lindepth)-dhVoxyFarPlane-dhVoxyNearPlane)/(dhVoxyFarPlane-dhVoxyNearPlane);
// }

float DH_ld(float dist) {
    return (2.0 * dhVoxyNearPlane) / (dhVoxyFarPlane + dhVoxyNearPlane - dist * (dhVoxyFarPlane - dhVoxyNearPlane));
}
float DH_inv_ld (float lindepth){
	return -((2.0*dhVoxyNearPlane/lindepth)-dhVoxyFarPlane-dhVoxyNearPlane)/(dhVoxyFarPlane-dhVoxyNearPlane);
}

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
    return (near * far) / (depth * (near - far) + far);
}




uniform int isEyeInWater;
uniform float rainStrength;

#ifdef OVERWORLD_SHADER
	#if defined CUSTOM_MOON_ROTATION && LIGHTNING_SHADOWS > 0
		uniform vec4 lightningBoltPosition;
		uniform float sunElevation;
	#endif

	#include "/lib/scene_controller.glsl"
	#define CLOUDSHADOWSONLY
	#include "/lib/volumetricClouds.glsl"
#endif

#ifndef OVERWORLD_SHADER
#undef WATER_SUN_SPECULAR
#endif
float GGX(vec3 n, vec3 v, vec3 l, float r, float f0) {
  r = max(pow(r,2.5), 0.0001);

  vec3 h = l + v;
  float hn = inversesqrt(dot(h, h));

  float dotLH = clamp(dot(h,l)*hn,0.,1.);
  float dotNH = clamp(dot(h,n)*hn,0.,1.) ;
  float dotNL = clamp(dot(n,l),0.,1.);
  float dotNHsq = dotNH*dotNH;

  float denom = dotNHsq * r - dotNHsq + 1.;
  float D = r / (3.141592653589793 * denom * denom);

  float F = f0 + (1. - f0) * exp2((-5.55473*dotLH-6.98316)*dotLH);
  float k2 = .25 * r;

  return dotNL * D * F / (dotLH*dotLH*(1.0-k2)+k2);
}

uniform int framemod8;

#include "/lib/TAA_jitter.glsl"

float invLdFast(float linearDepth) {
    return (dhVoxyFarPlane * (dhVoxyNearPlane - linearDepth)) / ((dhVoxyNearPlane - dhVoxyFarPlane) * linearDepth);
}

#define FORWARD_SSR_QUALITY 30 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 200 300 400 500]

vec3 rayTrace(vec3 dir, vec3 position, float dither, float fresnel) {

	const float biasAmount = 0.0000015;

    float quality = float(FORWARD_SSR_QUALITY);
    vec3 clipPosition = DH_toClipSpace3(position);

    float rayLength = ((position.z + dir.z * dhVoxyFarPlane*sqrt(3.)) > -dhVoxyNearPlane) ?
       (-dhVoxyNearPlane - position.z) / dir.z : dhVoxyFarPlane*sqrt(3.);
    
    vec3 direction = DH_toClipSpace3(position + dir * rayLength) - clipPosition;  //convert to clip space
	
	//get at which length the ray intersects with the edge of the screen
    vec3 maxLengths = (step(0.0, direction) - clipPosition) / direction;
    float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z);
    vec3 stepv = direction * mult / quality;
    
    clipPosition.xy *= RENDER_SCALE;
    stepv.xy *= RENDER_SCALE;
    
    vec3 spos = clipPosition + stepv * dither;
    spos.xy += offsets[framemod8] * texelSize * 0.5 / RENDER_SCALE;
    
    float minZ = spos.z - 0.00025 / DH_ld(spos.z);
    float maxZ = spos.z;
    
    for (int i = 0; i <= int(quality); i++) {
		#if FORWARD_SSR_QUALITY != 1
			if(spos.x < 0 || spos.x > 1 || spos.y < 0 || spos.y > 1) return vec3(1.1);
		#endif

		float sp = texelFetch(dhDepthTex, ivec2(spos.xy /texelSize), 0).r;
        
        if (sp < max(minZ, maxZ) && sp > min(minZ, maxZ)) {
            return vec3(spos.xy / RENDER_SCALE, sp);
        }
        
		minZ = maxZ - biasAmount / DH_ld(spos.z);
        maxZ += stepv.z;
        
        spos += stepv;
    }
    return vec3(1.1);
}

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
vec3 applyBump(mat3 tbnMatrix, vec3 bump, float puddle_values){
	float bumpmult = puddle_values;
	bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);
	// 
	return normalize(bump*tbnMatrix);
}

#define FORWARD_SPECULAR
#define FORWARD_BACKGROUND_REFLECTION
// #define FORWARD_ROUGH_REFLECTION

#ifdef FORWARD_ROUGH_REFLECTION
#endif

/* RENDERTARGETS:2,7,11,14 */
void main() {
if (gl_FragCoord.x * texelSize.x < 1.0  && gl_FragCoord.y * texelSize.y < 1.0 )	{
   
    bool iswater = isWater > 0;

	vec3 viewPos = pos.xyz;
    vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
	float viewDist = length(playerPos);
    // float transition = exp(-25* pow(clamp(1.0 - viewDist/(far-8),0.0,1.0),2));

	#if DH_CHUNK_FADING > 0
		if (!iswater){
			float ditherFade = smoothstep(0.86 * far, 0.9 * far, viewDist);
			if (step(R2_dither()/ditherFade, ditherFade) == 0.0) discard;
		}
	#endif
   
    float material = 0.7;
    if(iswater) material = 1.0;

    vec3 normals = normalize(normalMat.xyz);
    if (!gl_FrontFacing) normals = -normals;

   vec3 worldSpaceNormals =  mat3(gbufferModelViewInverse) * normals;


    #ifdef DH_OVERDRAW_PREVENTION
		#if OVERDRAW_MAX_DISTANCE == 0
			float maxOverdrawDistance = far;
		#else
			float maxOverdrawDistance = OVERDRAW_MAX_DISTANCE;
		#endif

        if(viewDist < clamp(far-16*4, 16, maxOverdrawDistance) ){ discard; return;}
    #endif

	vec3 waterNormals = worldSpaceNormals;

	#ifndef VANILLA_LIKE_WATER
		if(iswater && abs(worldSpaceNormals.y) > 0.1){
			vec3 waterPos = (playerPos+cameraPosition).xzy;

			vec3 bump = normalize(getWaveNormal(waterPos, playerPos));

			float bumpmult = WATER_WAVE_STRENGTH;

			bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);

			waterNormals.xz = bump.xy;
		}
	#endif

	normals = worldToView(waterNormals);
    

    gl_FragData[0] = gcolor;

	#ifdef DISTANT_HORIZONS_TEXTURES
    if (dh_hasTexture()) {
        vec4 that = dh_sampleTexture();
        vec3 clampedColor = clamp(gl_FragData[0].rgb * (that.rgb * 2.0), 0.0, 1.0);
        gl_FragData[0].rgb = mix(gl_FragData[0].rgb, clampedColor, that.a);
    }
   #endif

    float UnchangedAlpha = gl_FragData[0].a;

	#ifdef WhiteWorld
		gl_FragData[0].rgb = vec3(0.5);
		gl_FragData[0].a = 1.0;
	#endif
    
	vec3 Albedo = toLinear(gl_FragData[0].rgb);

	#ifndef WhiteWorld
	    #ifdef VANILLA_LIKE_WATER
			if (iswater) Albedo *= sqrt(luma(Albedo));
		#else
	    	if (iswater){
	    		Albedo = vec3(0.0);
	    		gl_FragData[0].a = 1.0/255.0;
	    	}
        #endif
    #endif

    // diffuse
	vec3 Indirect_lighting = vec3(0.0);
	// vec3 MinimumLightColor = vec3(1.0);
	vec3 Direct_lighting = vec3(0.0);

    #ifdef OVERWORLD_SHADER
		vec3 DirectLightColor = lightSourceColorSSBO/2400.0;

    	float NdotL = clamp(dot(worldSpaceNormals, WsunVec),0.0,1.0); 
        NdotL = clamp((-15 + NdotL*255.0) / 240.0  ,0.0,1.0);

        float Shadows = 1.0;

        #ifdef DISTANT_HORIZONS_SHADOWMAP
    	    vec3 feetPlayerPos_shadow = mat3(gbufferModelViewInverse) * pos.xyz + gbufferModelViewInverse[3].xyz;

    	    vec3 projectedShadowPosition = mat3(shadowModelView) * feetPlayerPos_shadow  + shadowModelView[3].xyz;
    	    projectedShadowPosition = diagonal3(shadowProjection) * projectedShadowPosition + shadowProjection[3].xyz;

    	    //apply distortion
    	    #ifdef DISTORT_SHADOWMAP
    	        float distortFactor = calcDistort(projectedShadowPosition.xy);
    	    	projectedShadowPosition.xy *= distortFactor;
    	    #else
    	    	float distortFactor = 1.0;
    	    #endif

    	    float smallbias = -0.0035;

    	    bool ShadowBounds = abs(projectedShadowPosition.x) < 1.0-1.5/shadowMapResolution && abs(projectedShadowPosition.y) < 1.0-1.5/shadowMapResolution && abs(projectedShadowPosition.z) < 6.0;

    	    if(ShadowBounds){
    	    	Shadows = 0.0;
    	    	projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5);

    	    	Shadows = texture(shadowtex0HW, projectedShadowPosition + vec3(0.0,0.0, smallbias)).x;
    	    }
        #endif

		Shadows *= GetCloudShadow(playerPos + cameraPosition, WsunVec);


    	Direct_lighting = DirectLightColor * NdotL * Shadows;

    	vec3 AmbientLightColor = averageSkyCol_CloudsSSBO/900.0 ;

    	vec3 indirectNormal = worldSpaceNormals.xyz / dot(abs(worldSpaceNormals.xyz), vec3(1.0));
    	float SkylightDir = clamp(indirectNormal.y*0.7+0.3,0.0,1.0);
    
    	float skylight = mix(0.08, 1.0, SkylightDir);
    	AmbientLightColor *= skylight;
    #endif
	
    #ifndef OVERWORLD_SHADER
		vec3 AmbientLightColor = vec3(0.5);
	#endif

    Indirect_lighting = AmbientLightColor;
	float indoors = min(max(lightmapCoords.y-0.5,0.0)/0.4,1.0);
	vec3 FinalColor = (Indirect_lighting + Direct_lighting*indoors) * Albedo;

    // specular
    #ifdef FORWARD_SPECULAR
		vec3 Reflections_Final = vec3(0.0);
		vec4 Reflections = vec4(0.0);
		vec3 BackgroundReflection = FinalColor; 
		vec3 SunReflection = vec3(0.0);
		float SSR_HIT_SKY_MASK = indoors;
		
        float roughness = 0.0;
		float f0 = 0.02;
		// f0 = 0.9;

        vec3 reflectedVector = reflect(normalize(viewPos), normals);
	    float normalDotEye = dot(normals, normalize(viewPos));

	    float fresnel =  pow(clamp(1.0 + normalDotEye, 0.0, 1.0),5.0);

	    fresnel = mix(f0, 1.0, fresnel);

        #ifdef SNELLS_WINDOW
	    	if(isEyeInWater == 1) fresnel = pow(clamp(1.5 + normalDotEye,0.0,1.0), 25.0);
	    #endif
        #if FORWARD_SSR_QUALITY > 0 && defined DH_SCREENSPACE_REFLECTIONS
            vec3 rtPos = rayTrace(reflectedVector, viewPos, interleaved_gradientNoise_temporal(), fresnel);
            if (rtPos.z < 0.99999){
            	vec3 previousPosition = mat3(gbufferModelViewInverse) * DH_toScreenSpace(rtPos) + gbufferModelViewInverse[3].xyz + cameraPosition-previousCameraPosition;
            	previousPosition = mat3(gbufferPreviousModelView) * previousPosition + gbufferPreviousModelView[3].xyz;
            	previousPosition.xy = projMAD(dhPreviousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5;
            	if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.y < 1.0) {
					Reflections.a = 1.0;
					Reflections.rgb = texture(colortex5, previousPosition.xy).rgb;
            	}
            }else{
				if (rtPos.x > 0.0 && rtPos.y > 0.0 && rtPos.x < 1.0 && rtPos.y < 1.0) SSR_HIT_SKY_MASK = 1.0;
			}
        #endif
		#ifdef FORWARD_BACKGROUND_REFLECTION
            BackgroundReflection = skyCloudsFromTex(mat3(gbufferModelViewInverse) * reflectedVector, colortex4).rgb / 1200.0;
        #endif
        #if defined OVERWORLD_SHADER && SUN_SPECULAR_MULT > 0
            SunReflection = SUN_SPECULAR_MULT * DirectLightColor * Shadows * GGX(normalize(normals), -normalize(viewPos), normalize(WsunVec2), roughness, f0) * (1.0-Reflections.a);
        #endif

		Reflections_Final = mix(FinalColor, mix(BackgroundReflection*SSR_HIT_SKY_MASK, Reflections.rgb, Reflections.a), fresnel);
		Reflections_Final += SunReflection*SSR_HIT_SKY_MASK;

		gl_FragData[0].a = gl_FragData[0].a + (1.0-gl_FragData[0].a) * fresnel;
	
		gl_FragData[0].rgb = clamp(Reflections_Final / gl_FragData[0].a * 0.1,0.0,65000.0);

		if (gl_FragData[0].r > 65000.) gl_FragData[0].rgba = vec4(0.0);
	#else
		gl_FragData[0].rgb = FinalColor*0.1;
	#endif
	
		// gl_FragData[0].rgb = normals*0.1;
    
    #ifdef DH_OVERDRAW_PREVENTION
        float distancefade = min(max(1.0 - viewDist/clamp(far-16*4, 16, maxOverdrawDistance),0.0)*5,1.0);

        if(texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x < 1.0 ||  distancefade > 0.0){
            discard;
        }
    #endif
	
    #if DEBUG_VIEW == debug_DH_WATER_BLENDING
        if(gl_FragCoord.x*texelSize.x > 0.53) gl_FragData[0] = vec4(0.0);
    #endif
   
    gl_FragData[1] = vec4(Albedo, material);

	vec4 GLASS_TINT_COLORS = vec4(Albedo, UnchangedAlpha);
	
	#ifdef BIOME_TINT_WATER
		if (iswater) GLASS_TINT_COLORS.rgb = toLinear(gcolor.rgb);
	#endif
	
	vec4 blockBreak = texelFetch(colortex11, ivec2(gl_FragCoord.xy), 0);

	if(blockBreak.a > 0.99) {
		gl_FragData[2] = blockBreak;
	} else {
		gl_FragData[2] = vec4(0.0, encodeVec2(GLASS_TINT_COLORS.rg), encodeVec2(GLASS_TINT_COLORS.ba), 0.5);
	}

	gl_FragData[3] = vec4(1, 1, encodeVec2(lightmapCoords.x, lightmapCoords.y), 1);

}


}