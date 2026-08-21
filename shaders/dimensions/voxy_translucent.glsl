#define VOXY_PROGRAM

layout (location = 0) out vec4 gbuffer_data_0;
layout (location = 1) out vec4 gbuffer_data_1;
layout (location = 2) out vec4 gbuffer_data_2;
layout (location = 3) out vec4 gbuffer_data_3;

#include "/lib/settings.glsl"
#include "/lib/blocks.glsl"
#include "/lib/waterBump.glsl"
#include "/lib/res_params.glsl"
#include "/lib/TAA_jitter.glsl"

#undef Hand_Held_lights
#undef PHOTONICS
#undef IS_LPV_ENABLED
#include "/lib/diffuse_lighting.glsl"

#ifdef OVERWORLD_SHADER
	#include "/lib/scene_controller.glsl"
	#define CLOUDSHADOWSONLY
	#include "/lib/volumetricClouds.glsl"
#endif

#ifdef OVERWORLD_SHADER
	#define WATER_SUN_SPECULAR
#endif

#ifndef OVERWORLD_SHADER
#undef WATER_SUN_SPECULAR
#endif

#ifdef END_SHADER
	#include "/lib/end_fog.glsl"
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

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

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

vec3 toLinear(vec3 sRGB){
	return sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878);
}

float luma(vec3 color) {
	return dot(color,vec3(0.21, 0.72, 0.07));
}

vec3 worldToView(vec3 worldPos) {
    vec4 pos = vec4(worldPos, 0.0);
    pos = vxModelView * pos;
    return pos.xyz;
}

vec3 DH_toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(vxProjInv[0].x, vxProjInv[1].y, vxProjInv[2].zw);
    vec3 feetPlayerPos = p * 2. - 1.;
    vec4 viewPos = iProjDiag * feetPlayerPos.xyzz + vxProjInv[3];
    return viewPos.xyz / viewPos.w;
}

float interleaved_gradientNoise_temporal(){
	#ifdef TAA
		return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887);
	#endif
}

#include "/lib/sky_gradient.glsl"
#include "/lib/Shadow_Params.glsl"

#define FORWARD_SSR_QUALITY 30 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 200 300 400 500]

#define FORWARD_SPECULAR
#define FORWARD_BACKGROUND_REFLECTION
// #define FORWARD_ROUGH_REFLECTION

#ifdef FORWARD_ROUGH_REFLECTION
#endif

vec3 DH_toClipSpace3(vec3 viewSpacePosition) {
    return projMAD(vxProj, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
}

float invLdFast(float linearDepth) {
    return (dhVoxyFarPlane * (dhVoxyNearPlane - linearDepth)) / ((dhVoxyNearPlane - dhVoxyFarPlane) * linearDepth);
}

float DH_ld(float dist) {
    return (2.0 * dhVoxyNearPlane) / (dhVoxyFarPlane + dhVoxyNearPlane - dist * (dhVoxyFarPlane - dhVoxyNearPlane));
}

vec3 rayTrace(vec3 dir, vec3 position, float dither, float fresnel) {

	const float biasAmount = 0.00015;

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

		float vanillaDepth = texelFetch(depthtex0, ivec2(spos.xy / texelSize), 0).r;
		
		if(vanillaDepth >= 1.0) {
			float sp = texelFetch(vxDepthTexOpaque, ivec2(spos.xy / texelSize), 0).r;
			
			if (sp < max(minZ, maxZ) && sp > min(minZ, maxZ)) {
				return vec3(spos.xy / RENDER_SCALE, sp);
			}
		}
        
		minZ = maxZ - biasAmount / DH_ld(spos.z);
        maxZ += stepv.z;
        
        spos += stepv;
    }
    return vec3(1.1);
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
if (gl_FragCoord.x * texelSize.x < 1.0  && gl_FragCoord.y * texelSize.y < 1.0 )	{
    vec3 viewPos = DH_toScreenSpace(gl_FragCoord.xyz*vec3(texelSize/RENDER_SCALE,1.0));

	vec3 feetPlayerPos = mat3(vxModelViewInv) * viewPos + vxModelViewInv[3].xyz;;
    
    gbuffer_data_0 = parameters.sampledColour * parameters.tinting;

    vec3 Albedo = toLinear(gbuffer_data_0.rgb);
	float UnchangedAlpha = gbuffer_data_0.a;
    
    int blockID = int(parameters.customId);
    bool isWater = blockID == 8;

    #ifndef WhiteWorld
		#ifdef VANILLA_LIKE_WATER
			if (isWater) Albedo *= luma(Albedo);
		#else
			if (isWater){
				Albedo = vec3(0.0);
				gbuffer_data_0.a = 1.0/255.0;
			}
		#endif
	#endif

    vec3 normal = vec3(uint((parameters.face>>1)==2), uint((parameters.face>>1)==0), uint((parameters.face>>1)==1)) * (float(int(parameters.face)&1)*2-1);

	if (normal.z<=-0.9) normal.xy = vec2(-0.0000000000001);

    vec3 WsunVec;
    vec3 WsunVec2;

	#ifdef CUSTOM_MOON_ROTATION
		vec3 WmoonVec = customMoonVecSSBO;

		#ifdef SMOOTH_SUN_ROTATION
			WsunVec = WsunVecSmooth;
		#else
			WsunVec = normalize(mat3(vxModelViewInv) * sunPosition);
		#endif
		WsunVec2 = normalize(sunPosition);

		WsunVec = mix(WmoonVec, WsunVec, float(sunElevation > 1e-5));
		WsunVec2 = mix(normalize(mat3(vxModelView)*WmoonVec), WsunVec2, float(sunElevation > 1e-5));
	#else
		float lightSourceCheck = float(sunElevation > 1e-5)*2.0 - 1.0;
		#ifdef SMOOTH_SUN_ROTATION
			WsunVec = lightSourceCheck * WsunVecSmooth;
		#else
			WsunVec = lightSourceCheck * normalize(mat3(vxModelViewInv) * sunPosition);
		#endif
		WsunVec2 = lightSourceCheck * normalize(sunPosition);
	#endif

    // diffuse
	vec3 Indirect_lighting = vec3(0.0);
	// vec3 MinimumLightColor = vec3(1.0);
	vec3 Direct_lighting = vec3(0.0);

    #ifdef OVERWORLD_SHADER
		vec3 DirectLightColor = lightSourceColorSSBO/2400.0;

    	float NdotL = clamp(dot(normal, WsunVec),0.0,1.0); 
        NdotL = clamp((-15.0 + NdotL*255.0) / 240.0  ,0.0,1.0);

        float Shadows = 1.0;

		Shadows *= GetCloudShadow(feetPlayerPos + cameraPosition, WsunVec);

    	Direct_lighting = DirectLightColor * NdotL * Shadows;

    	vec3 AmbientLightColor = averageSkyCol_CloudsSSBO/900.0 ;

    	vec3 indirectNormal = normal.xyz / dot(abs(normal.xyz), vec3(1.0));
    	float SkylightDir = clamp(indirectNormal.y*0.7+0.3,0.0,1.0);
    
    	float skylight = mix(0.08, 1.0, SkylightDir);
    	AmbientLightColor *= skylight;

		vec3 MinimumLightColor = vec3(1.0);
		Indirect_lighting = doIndirectLighting(AmbientLightColor, MinimumLightColor, parameters.lightMap.y);
    #endif

	#ifdef NETHER_SHADER
		Indirect_lighting = volumetricsFromTex(normal, colortex4, 0).rgb / 1200.0 / 1.5;
	#endif

	#ifdef END_SHADER
		#ifdef END_LIGHTNING
			float vortexBounds = clamp(vortexBoundRange - length(feetPlayerPos+cameraPosition), 0.0,1.0);
		#else
			float vortexBounds = 1.0;
		#endif

        vec3 lightPos = LightSourcePosition(feetPlayerPos+cameraPosition, cameraPosition,vortexBounds);

		float lightningflash = texelFetch(colortex4,ivec2(1,1),0).x/150.0;
		vec3 lightColors = LightSourceColors(vortexBounds, lightningflash);
		
		float end_NdotL = clamp(dot(normal, normalize(-lightPos))*0.5+0.5,0.0,1.0);
		end_NdotL *= end_NdotL;

		float fogShadow = GetEndFogShadow(feetPlayerPos+cameraPosition, lightPos);
		float endPhase = endFogPhase(lightPos);

		Direct_lighting = lightColors * endPhase * end_NdotL * fogShadow;

		vec3 AmbientLightColor = vec3(AmbientLightEnd_R,AmbientLightEnd_G,AmbientLightEnd_B) ;
			
		Indirect_lighting = AmbientLightColor + 0.7 * AmbientLightColor * dot(normal, normalize(feetPlayerPos));
		Indirect_lighting *= 0.1;
	#endif


	float indoors = min(max(parameters.lightMap.y-0.5,0.0)/0.4,1.0);

	vec3 lightColor = vec3(TORCH_R,TORCH_G,TORCH_B);
	const vec3 lpvPos = vec3(0.0);
	Indirect_lighting += doBlockLightLighting(lightColor, parameters.lightMap.x * 0.8, feetPlayerPos, lpvPos, false, false);

	vec3 FinalColor = (Indirect_lighting + Direct_lighting*indoors) * Albedo;
	
    #ifndef VANILLA_LIKE_WATER
		if(isWater && abs(normal.y) > 0.1){
			vec3 waterPos = (feetPlayerPos+cameraPosition).xzy;

			vec3 bump = normalize(getWaveNormal(waterPos, feetPlayerPos));

			float bumpmult = WATER_WAVE_STRENGTH;

			bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);

			normal.xz = bump.xy;
		}
	#endif

    vec3 normals = normalize(worldToView(normal));

	#if defined FORWARD_SPECULAR
		vec3 Reflections_Final = vec3(0.0);
		vec4 Reflections = vec4(0.0);
		vec3 BackgroundReflection = FinalColor; 
		vec3 SunReflection = vec3(0.0);
		float SSR_HIT_SKY_MASK = indoors;
		
		float roughness = 0.0;
		float f0 = 0.02;

        vec3 reflectedVector = reflect(normalize(viewPos), normals);
	    float normalDotEye = dot(normals, normalize(viewPos));

		float fresnel =  pow(clamp(1.0 + normalDotEye, 0.0, 1.0), 5.0);

		fresnel = mix(f0, 1.0, fresnel);

        #ifdef SNELLS_WINDOW
	    	if(isEyeInWater == 1) fresnel = pow(clamp(1.5 + normalDotEye,0.0,1.0), 25.0);
	    #endif
        #if FORWARD_SSR_QUALITY > 0 && defined VOXY_REFLECTIONS
            vec3 rtPos = rayTrace(reflectedVector, viewPos, interleaved_gradientNoise_temporal(), fresnel);
            if (rtPos.z < 0.99999){
            	vec3 previousPosition = mat3(gbufferModelViewInverse) * DH_toScreenSpace(rtPos) + gbufferModelViewInverse[3].xyz + cameraPosition-previousCameraPosition;
            	previousPosition = mat3(gbufferPreviousModelView) * previousPosition + gbufferPreviousModelView[3].xyz;
            	previousPosition.xy = projMAD(vxProjPrev, previousPosition).xy / -previousPosition.z * 0.5 + 0.5;
            	if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.y < 1.0) {
					Reflections.a = 1.0;
					Reflections.rgb = texture(colortex5, previousPosition.xy).rgb;
            	}
            }else{
				if (rtPos.x > 0.0 && rtPos.y > 0.0 && rtPos.x < 1.0 && rtPos.y < 1.0) SSR_HIT_SKY_MASK = 1.0;
			}
        #endif
		#if defined FORWARD_BACKGROUND_REFLECTION
            BackgroundReflection = skyCloudsFromTex(mat3(gbufferModelViewInverse) * reflectedVector, colortex4).rgb / 1200.0;
        #endif
        #if defined OVERWORLD_SHADER && SUN_SPECULAR_MULT > 0
            SunReflection = SUN_SPECULAR_MULT * DirectLightColor * Shadows * GGX(normalize(normals), -normalize(viewPos), normalize(WsunVec2), roughness, f0) * (1.0-Reflections.a);
        #endif

		Reflections_Final = mix(FinalColor, mix(BackgroundReflection*SSR_HIT_SKY_MASK, Reflections.rgb, Reflections.a), fresnel);
		Reflections_Final += SunReflection*SSR_HIT_SKY_MASK;

		gbuffer_data_0.a = gbuffer_data_0.a + (1.0-gbuffer_data_0.a) * fresnel;
	
		gbuffer_data_0.rgb = clamp((Reflections_Final/gbuffer_data_0.a) * 0.1,0.0,65000.0);

		if (gbuffer_data_0.r > 65000.) gbuffer_data_0.rgba = vec4(0.0);
	#else
		gbuffer_data_0.rgb = FinalColor*0.1;
	#endif

    float material = 0.7;
    if(isWater) material = 1.0;

    //gbuffer_data_0.rgb = Albedo;

    gbuffer_data_1 = vec4(Albedo, material);

	vec4 GLASS_TINT_COLORS = vec4(Albedo, UnchangedAlpha);
	
	#ifdef BIOME_TINT_WATER
		if (isWater) GLASS_TINT_COLORS.rgb = toLinear(parameters.tinting.rgb);
	#endif

	gbuffer_data_2 = vec4(0.0, encodeVec2(GLASS_TINT_COLORS.rg), encodeVec2(GLASS_TINT_COLORS.ba), 0.5);

    gbuffer_data_3 = vec4(1, 1, encodeVec2(parameters.lightMap), 1);

}
}