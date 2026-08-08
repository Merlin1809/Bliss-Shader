#include "/lib/settings.glsl"

#include "/lib/SSBOs.glsl"

#ifdef OVERWORLD_SHADER
  in DATA {
    flat vec3 WsunVec;
  };
#endif

#define DEFERRED_SPECULAR
#define DEFERRED_SSR_QUALITY 30 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 200 300 400 500]

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
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex15;
uniform vec2 texelSize;

uniform float viewHeight;
uniform float viewWidth;
uniform float nightVision;
uniform float fogEnd;
uniform vec3 fogColor;
uniform vec3 sunVec;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float far;
uniform float near;
uniform float farPlane;
uniform float dhVoxyNearPlane;
uniform float dhVoxyFarPlane;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferPreviousProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform int hideGUI;
uniform int dhVoxyRenderDistance;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform ivec2 eyeBrightness;
uniform float rainStrength;
uniform float blindness;
uniform float darknessFactor;
uniform float darknessLightFactor;
uniform float caveDetection;
uniform float sunElevation;

#include "/lib/res_params.glsl"

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}

float linearize(float dist) {
  return (2.0 * near) / (far + near - dist * (far - near));
}

vec3 toClipSpace3Prev(vec3 viewSpacePosition) {
    return projMAD(gbufferPreviousProjection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
}

vec3 bilateralUpsample2(vec2 fragcoord, sampler2D colortex, out float outerEdgeResults, float referenceDepth, sampler2D depth, bool hand){

  vec3 colorSum = vec3(0.0);
  float edgeSum = 0.0;

  const float threshold = 0.005;


  const int samples = 5;
  
  vec2 coord = fragcoord - 1.5;

  vec2 UV = coord;
  const ivec2 SCALE = ivec2(1.0);
  ivec2 UV_COLOR = ivec2(UV);
  ivec2 UV_NOISE = ivec2(gl_FragCoord.xy*texelSize + 1);

	const ivec2 OFFSET[5] = ivec2[5](
    ivec2(-1,-1),
	 	ivec2( 1, 1),
		ivec2(-1, 1),
		ivec2( 1,-1),
		ivec2( 0, 0)
    // ,ivec2( 0, 1),
    // ivec2( 0,-1),
    // ivec2( 1, 0),
    // ivec2(-1, 0)
  );

  for(int i = 0; i < samples; i++) {
    float offsetDepth = linearize(texelFetch(depth, UV_COLOR + (OFFSET[i] + UV_NOISE), 0).r);

    float edgeDiff = abs(offsetDepth - referenceDepth) < threshold ? 1.0 : 1e-7;
    outerEdgeResults = max(outerEdgeResults, abs(referenceDepth - offsetDepth));

    vec3 offsetColor = texelFetch(colortex, UV_COLOR + OFFSET[i] + UV_NOISE, 0).rgb;
    colorSum += offsetColor*edgeDiff;
    edgeSum += edgeDiff;

  }

  outerEdgeResults = outerEdgeResults > (hand ? 0.005 : referenceDepth*0.05 + 0.1) ? 1.0 : 0.0;
  
  return colorSum / edgeSum;
}

vec3 VLTemporalFiltering2(vec2 texcoord, vec3 playerPosIn, in float referenceDepth, sampler2D depth, bool hand, vec3 currentFrame, float roughness){  
	// get previous frames position stuff for UV
	vec3 playerPos = playerPosIn + (cameraPosition - previousCameraPosition);
	vec3 previousPosition = mat3(gbufferPreviousModelView) * playerPos + gbufferPreviousModelView[3].xyz;
	previousPosition = toClipSpace3Prev(previousPosition);

	vec2 velocity = previousPosition.xy - texcoord;
	previousPosition.xy = texcoord + velocity;

  // return vec4(outerEdgeResults,0,0,1);
  // return upsampledCurrentFrame;

  if (previousPosition.x < 0.0 || previousPosition.y < 0.0 || previousPosition.x > 1.0 || previousPosition.y > 1.0 || hand) return currentFrame.rgb;

  // to fill pixel gaps in geometry edges, do a bilateral upsample.
  // pass a mask to only show upsampled color around the edges of blocks. this is so it doesnt blur reprojected results.
  float outerEdgeResults = 0.0;
  vec3 upsampledCurrentFrame = bilateralUpsample2(gl_FragCoord.xy , colortex0, outerEdgeResults, referenceDepth, depth, hand);
  //return currentFrame;
  // vec4 upsampledCurrentFrame = BilateralUpscale(colortex0, depth, gl_FragCoord.xy - 1.5, referenceDepth);
  // /*

  vec4 frameHistoryTex = texture(colortex12, previousPosition.xy*RENDER_SCALE);
  float prevDepth = frameHistoryTex.a;
  float linPrevDepth = linearize(previousPosition.z);

  vec3 frameHistory = frameHistoryTex.rgb;

  vec3 reprojectFrame = currentFrame.rgb;

  if(!(frameHistory.r == 0.0 && frameHistory.g == 0.0 && frameHistory.b == 0.0) && (abs(prevDepth-linPrevDepth) < max(linPrevDepth * 0.02, 0.001))) {
    vec3 col1 = texture(colortex0, texcoord + vec2( texelSize.x,  texelSize.y)).rgb;
    vec3 col2 = texture(colortex0, texcoord + vec2( texelSize.x, -texelSize.y)).rgb;
    vec3 col3 = texture(colortex0, texcoord + vec2(-texelSize.x, -texelSize.y)).rgb;
    vec3 col4 = texture(colortex0, texcoord + vec2(-texelSize.x,  texelSize.y)).rgb;
    vec3 col5 = texture(colortex0, texcoord + vec2( 0.0,			    texelSize.y)).rgb;
    vec3 col6 = texture(colortex0, texcoord + vec2( 0.0,			   -texelSize.y)).rgb;
    vec3 col7 = texture(colortex0, texcoord + vec2(-texelSize.x,  		    0.0)).rgb;
    vec3 col8 = texture(colortex0, texcoord + vec2( texelSize.x,  		    0.0)).rgb;

    vec3 colMax = max(currentFrame.rgb,max(col1,max(col2,max(col3, max(col4, max(col5, max(col6, max(col7, col8))))))));
    vec3 colMin = min(currentFrame.rgb,min(col1,min(col2,min(col3, min(col4, min(col5, min(col6, min(col7, col8))))))));
    
    vec3 clampedFrameHistory = clamp(frameHistory, colMin, colMax);

    float blendingFactor = mix(0.025, 1.0, smoothstep(0.05, 0.25, length(cameraPosition-previousCameraPosition)));
    blendingFactor = mix(1.0, blendingFactor, smoothstep(0.0, 0.1, roughness));
    reprojectFrame = mix(clampedFrameHistory, currentFrame.rgb, blendingFactor);
  }

  // return clamp(reprojectFrame,0.0,65000.0);
  return clamp(mix(reprojectFrame, upsampledCurrentFrame, outerEdgeResults),0.0,65000.0);
  // */

}

float blueNoise(){
	#ifdef TAA
  		return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887);
	#endif
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

vec2 decodeVec2(float a){
    const vec2 constant1 = 65535. / vec2( 256., 65536.);
    const float constant2 = 256. / 255.;
    return fract( a * constant1 ) * constant2 ;
}

vec3 decode (vec2 encn){
    vec3 n = vec3(0.0);
    encn = encn * 2.0 - 1.0;
    n.xy = abs(encn);
    n.z = 1.0 - n.x - n.y;
    n.xy = n.z <= 0.0 ? (1.0 - n.yx) * sign(encn) : encn;
    return clamp(normalize(n.xyz),-1.0,1.0);
}

vec3 toLinear(vec3 sRGB){
return sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878);
}

float shlickFresnelRoughness(float XdotN, float roughness){

	float shlickFresnel = clamp(1.0 + XdotN,0.0,1.0);

	float curves = exp(-4.0*pow(1.0-(roughness),2.5));
	float brightness = exp(-3.0*pow(1.0-sqrt(roughness),3.50));

	shlickFresnel = pow(1.0-pow(1.0-shlickFresnel, mix(1.0, 1.9, curves)),mix(5.0, 2.6, curves));
	shlickFresnel = mix(0.0, mix(1.0,0.065,  brightness) , clamp(shlickFresnel,0.0,1.0));
	
	return shlickFresnel;
}

void frisvad(in vec3 n, out vec3 f, out vec3 r){
    if(n.z < -0.9) {
        f = vec3(0.,-1,0);
        r = vec3(-1, 0, 0);
    } else {
    	float a = 1./(1.+n.z);
    	float b = -n.x*n.y*a;
    	f = vec3(1. - n.x*n.x*a, b, -n.x) ;
    	r = vec3(b, 1. - n.y*n.y*a , -n.y);
    }
}

mat3 CoordBase(vec3 n){
	vec3 x,y;
    frisvad(n,x,y);
    return mat3(x,y,n);
}

vec3 GGX(vec3 n, vec3 v, vec3 l, float r, vec3 f0, vec3 metalAlbedoTint) {
  r = max(pow(r,2.5), 0.0001);

  vec3 h = normalize(l + v);
  float hn = inversesqrt(dot(h, h));

  float dotLH = clamp(dot(h,l)*hn,0.,1.);
  float dotNH = clamp(dot(h,n)*hn,0.,1.) ;
  float dotNL = clamp(dot(n,l),0.,1.);
  float dotNHsq = dotNH*dotNH;

  float denom = dotNHsq * r - dotNHsq + 1.;
  float D = r / (3.141592653589793 * denom * denom);

  vec3 F = (f0 + (1. - f0) * exp2((-5.55473*dotLH-6.98316)*dotLH)) * metalAlbedoTint;
  float k2 = .25 * r;

  return dotNL * D * F / (dotLH*dotLH*(1.0-k2)+k2);
}

#ifdef IEXT_ENABLED
uniform bool IEXT_KEY_0;
#endif

vec4 calculateFlashlightData(in vec3 viewPos, bool hand){
    #ifdef IEXT_ENABLED
    if(IEXT_KEY_0) return vec4(0.0);
    #endif

  vec4 flashLightSpecularData = vec4(0.0);
  if(hand){
		return flashLightSpecularData;
	}

	// vec3 shiftedViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
	// vec3 shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition) * 3.0;
	// shiftedViewPos = mat3(gbufferPreviousModelView) * shiftedPlayerPos + gbufferPreviousModelView[3].xyz;
	vec3 shiftedViewPos;
    vec3 shiftedPlayerPos;
	float forwardOffset;

    #ifdef VIVECRAFT
        if (vivecraftIsVR) {
	        forwardOffset = 0.0;
            shiftedPlayerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + vivecraftRelativeMainHandPos;
            shiftedViewPos = shiftedPlayerPos * mat3(vivecraftRelativeMainHandRot);
        } else
    #endif
    {
	    forwardOffset = 0.5;
        shiftedViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
        shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition) * 3.0;
        shiftedViewPos = mat3(gbufferPreviousModelView) * shiftedPlayerPos + gbufferPreviousModelView[3].xyz;
    }

    
    
  vec2 scaledViewPos = shiftedViewPos.xy / max(-shiftedViewPos.z - forwardOffset, 1e-7);
	float linearDistance = length(shiftedPlayerPos);
	float shiftedLinearDistance = length(scaledViewPos);

	float lightFalloff = 1.0 - clamp(1.0-linearDistance/FLASHLIGHT_RANGE, -0.999,1.0);
	lightFalloff = max(exp(-10.0 * FLASHLIGHT_BRIGHTNESS_FALLOFF_MULT * lightFalloff),0.0);

	float flashLightSpecular = lightFalloff * exp2(-7.0*shiftedLinearDistance*shiftedLinearDistance) * FLASHLIGHT_BRIGHTNESS_MULT;
	flashLightSpecularData = vec4(normalize(shiftedPlayerPos), flashLightSpecular);	

  return flashLightSpecularData;
}

#if defined IS_LPV_ENABLED || defined PHOTONICS && defined PHOTONICS && !defined PH_ENABLE_HANDHELD_LIGHT
  uniform bool firstPersonCamera;
	uniform vec3 relativeEyePosition;
  uniform int heldItemId;
  uniform int heldItemId2;

	uniform sampler3D texLpv1;
	uniform sampler3D texLpv2;

  #include "/lib/util.glsl"
	#include "/lib/hsv.glsl"
	#include "/lib/lpv_common.glsl"
	#include "/lib/lpv_render.glsl"
	#include "/lib/blocks.glsl"
	#include "/lib/lpv_blocks.glsl"

  vec3 GetHandLight(const in int itemId, const in vec3 playerPos, inout float lightRange) {
      vec3 lightFinal = vec3(0.0);

      uint blockData = imageLoad(imgBlockData, itemId).r;
      vec4 lightColorRange = unpackUnorm4x8(blockData);
      lightRange = lightColorRange.a * 255.0;

      if (lightRange > 0.0) {
          vec3 lightColor = srgbToLinear(lightColorRange.rgb);
          float lightDist = length(playerPos+relativeEyePosition)*0.7;
          float falloff = pow(1.0 - lightDist / lightRange, 3.0);
          lightFinal = lightColor * max(falloff, 0.0);
      }

      return lightFinal;
  }

  #ifdef BELTBORNE_LANTERNS
  uniform int IEXT_beltborne_lanterns_Id;
  #endif
#endif

float getReflectionVisibility(float f0, float roughness){

	// the goal is to determine if the reflection is even visible. 
	// if it reaches a point in smoothness or reflectance where it is not visible, allow it to interpolate to diffuse lighting.
	#if ROUGHNESS_THRESHOLD < 1
		return 0.0;
	#else
		float thresholdValue = ROUGHNESS_THRESHOLD/100.0;

		// the visibility gradient should only happen for dialectric materials. because metal is always shiny i guess or something
		float dialectrics = max(f0*255.0 - 26.0,0.0)/229.0;
		float value = 0.35; // so to a value you think is good enough.
		float thresholdA = min(max( (1.0-dialectrics) - value, 0.0)/value, 1.0);

		// use perceptual smoothness instead of linear roughness. it just works better i guess
		float smoothness = 1.0-sqrt(roughness);
		value = thresholdValue; // this one is typically want you want to scale.
		float thresholdB = min(max(smoothness - value, 0.0)/value, 1.0);
		
		// preserve super smooth reflections. if thresholdB's value is really high, then fully smooth, low f0 materials would be removed (like water).
		value = 0.1; // super low so only the smoothest of materials are includes.
		float thresholdC = 1.0-min(max(value - (1.0-smoothness), 0.0)/value, 1.0);
		
		float visibilityGradient = max(thresholdA*thresholdC - thresholdB,0.0);

		// a curve to make the gradient look smooth/nonlinear. just preference
		visibilityGradient = 1.0-visibilityGradient;
		visibilityGradient *=visibilityGradient;
		visibilityGradient = 1.0-visibilityGradient;
		visibilityGradient *=visibilityGradient;

		return visibilityGradient;
	#endif
}

/* RENDERTARGETS:12,3 */

void main() {

    vec2 texcoord = gl_FragCoord.xy*texelSize;
    float depth = texelFetch(depthtex1, ivec2(gl_FragCoord.xy),0).x;
    // bool hand = depth < 0.56;
    float z = depth;

    #if defined DISTANT_HORIZONS || defined VOXY
      float DH_depth1 = 1.0;
      float swappedDepth;
      if(z >= 1.0) {
        DH_depth1 = texelFetch(dhVoxyDepthTex1,ivec2(gl_FragCoord.xy),0).x;
        swappedDepth = DH_depth1;
      } else {
        swappedDepth = z;
      }
    #else
      float DH_depth1 = 1.0;
      float swappedDepth = z;
    #endif

    bool isSky = swappedDepth >= 1.0;
  
    gl_FragData[0] = vec4(0.0);
    vec3 FINAL_COLOR = texture(colortex3, texcoord).rgb;
    if(!isSky) {

      float frDepth = linearize(z);
      gl_FragData[0].a = frDepth;

      vec4 data = texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0);

      vec4 dataUnpacked0 = vec4(decodeVec2(data.x),decodeVec2(data.y)); // albedo, masks
      vec4 dataUnpacked1 = vec4(decodeVec2(data.z),decodeVec2(data.w)); // normals, lightmaps

      float opaqueMasks = dataUnpacked1.w;
      bool hand = abs(opaqueMasks-0.75) < 0.01;
      bool entities = abs(opaqueMasks-0.45) < 0.01;
      bool opaqueParticles = abs(opaqueMasks-0.85) <0.01;
      #ifdef SHADER_GRASS
        bool isShaderGrass = abs(opaqueMasks-0.80) < 0.01;
      #else
        const bool isShaderGrass = false;
      #endif

      vec3 viewPos = toScreenSpace(vec3(texcoord/RENDER_SCALE, z));

      vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos;
      vec3 NplayerPos = normalize(playerPos);
      playerPos += gbufferModelViewInverse[3].xyz;


      // derived from N and K from labPBR wiki https://shaderlabs.org/wiki/LabPBR_Material_Standard
      // using ((1.0 - N)^2 + K^2) / ((1.0 + N)^2 + K^2)
      const vec3 HCM_F0 [8] = vec3[8](
        vec3(0.531228825312, 0.51235724246, 0.495828545714),// iron	
        vec3(0.944229966045, 0.77610211732, 0.373402004593),// gold		
        vec3(0.912298031535, 0.91385063144, 0.919680580954),// Aluminum
        vec3(0.55559681715,  0.55453707574, 0.554779427513),// Chrome
        vec3(0.925952196272, 0.72090163805, 0.504154241735),// Copper
        vec3(0.632483812932, 0.62593707362, 0.641478899539),// Lead
        vec3(0.678849234658, 0.64240055565, 0.588409633571),// Platinum
        vec3(0.961999998804, 0.94946811207, 0.922115710997)	// Silver
      );

      vec3 albedo = toLinear(vec3(dataUnpacked0.xz,dataUnpacked1.x));
      vec2 lightmap = dataUnpacked1.yz;

      vec4 stuff = texelFetch(colortex8, ivec2(gl_FragCoord.xy), 0);
      vec3 normal = normalize(decode(stuff.xy));
      vec2 speculars = stuff.zw;

      float roughness = speculars.r;
      float f0 = speculars.g;
      roughness = 1.0 - roughness; 
      roughness *= roughness;

      f0 = f0 == 0.0 ? 0.02 : f0;

      bool isMetal = f0 > 229.5/255.0;

      // get reflected vector
      mat3 basis = CoordBase(normal);
      vec3 viewDir = -NplayerPos*basis;
      viewDir.z = abs(viewDir.z);

      float VdotN = dot(-normalize(viewDir), vec3(0.0,0.0,1.0));
      float shlickFresnel = shlickFresnelRoughness(VdotN, roughness);

      // F0 <  230 dialectrics
      // F0 >= 230 hardcoded metal f0
      // F0 == 255 use albedo for f0
      albedo = f0 == 1.0 ? sqrt(albedo) : albedo;
      vec3 metalAlbedoTint = isMetal ? albedo : vec3(1.0);
      // get F0 values for hardcoded metals.
      vec3 hardCodedMetalsF0 = f0 == 1.0 ? albedo : HCM_F0[int(clamp(f0*255.0 - 229.5,0.0,7.0))];
      vec3 reflectance = isMetal ? hardCodedMetalsF0 : vec3(f0);
      vec3 F0 = (reflectance + (1.0-reflectance) * shlickFresnel) * metalAlbedoTint;

      vec4 currentFrame = texture(colortex0, texcoord);
      float alpha = getReflectionVisibility(f0, roughness);

      vec3 denoisedReflections = currentFrame.rgb;

      if(roughness > 0.005 && alpha < 0.9999 && !hand && !entities && !opaqueParticles
        #if defined DISTANT_HORIZONS || defined VOXY
          && z < 1.0
        #endif
      ) {
        denoisedReflections = VLTemporalFiltering2(texcoord, playerPos, frDepth, depthtex1, hand, currentFrame.rgb, roughness);

        gl_FragData[0].rgb = denoisedReflections;
      }

      denoisedReflections.rgb = mix(FINAL_COLOR, denoisedReflections.rgb, F0);
      FINAL_COLOR = mix(denoisedReflections.rgb, FINAL_COLOR, alpha);

      #if defined OVERWORLD_SHADER && SUN_SPECULAR_MULT > 0
        vec3 lightSourceReflection = SUN_SPECULAR_MULT * texture(colortex15, texcoord).rgb * GGX(normal, -NplayerPos, WsunVec, roughness, reflectance, metalAlbedoTint);
        FINAL_COLOR += lightSourceReflection;
      #endif

      #if defined FLASHLIGHT_SPECULAR && (defined DEFERRED_SPECULAR || defined FORWARD_SPECULAR)
        vec4 flashlightData = calculateFlashlightData(viewPos, hand);
        vec3 flashLightReflection = vec3(FLASHLIGHT_R,FLASHLIGHT_G,FLASHLIGHT_B) * flashlightData.a * GGX(normal, -flashlightData.xyz, -flashlightData.xyz, roughness, reflectance, metalAlbedoTint);
        FINAL_COLOR += flashLightReflection;
      #endif

      #if defined Hand_Held_lights && defined IS_LPV_ENABLED && HANDHELD_LIGHT_REFLECTIONS > 0
        if(!hand && firstPersonCamera && !isShaderGrass) {
          if (heldItemId > 0){
            vec3 shiftedViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
            vec3 shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition);

            float lightRange = 0.0;
            vec3 handLightCol = GetHandLight(heldItemId, shiftedPlayerPos, lightRange);

            if(lightRange > 0.0) {
              vec3 handheldReflection = handLightCol * GGX(normal, -shiftedPlayerPos, -shiftedPlayerPos, roughness, reflectance, metalAlbedoTint);
              FINAL_COLOR += handheldReflection*HANDHELD_LIGHT_REFLECTIONS*0.005;
            }
          }

          if (heldItemId2 > 0){
            vec3 shiftedViewPos = viewPos + vec3(0.25, 0.2, 0.0);
            vec3 shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition);

            float lightRange = 0.0;
            vec3 handLightCol = GetHandLight(heldItemId2, shiftedPlayerPos, lightRange);

            if(lightRange > 0.0) {
              vec3 handheldReflection = handLightCol * GGX(normal, -shiftedPlayerPos, -shiftedPlayerPos, roughness, reflectance, metalAlbedoTint);
              FINAL_COLOR += handheldReflection*HANDHELD_LIGHT_REFLECTIONS*0.005;
            }
          }

          #ifdef BELTBORNE_LANTERNS
            if (IEXT_beltborne_lanterns_Id > 0){
              vec3 shiftedViewPos = viewPos + vec3(0.15, 0.2, 0.0);
              vec3 shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition);

              float lightRange = 0.0;
              vec3 handLightCol = GetHandLight(IEXT_beltborne_lanterns_Id, shiftedPlayerPos, lightRange);

              if(lightRange > 0.0) {
                vec3 handheldReflection = handLightCol * GGX(normal, -shiftedPlayerPos, -shiftedPlayerPos, roughness, reflectance, metalAlbedoTint);
                FINAL_COLOR += handheldReflection*HANDHELD_LIGHT_REFLECTIONS*0.005;
              }
            }
          #endif
        }
      #endif
      
    }

    gl_FragData[1].rgb = FINAL_COLOR;
}