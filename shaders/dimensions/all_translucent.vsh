#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/bokeh.glsl"
#include "/lib/items.glsl"

#include "/lib/SSBOs.glsl"

#include "/lib/blocks.glsl"
#include "/lib/entities.glsl"

uniform float frameTimeCounter;
#include "/lib/Shadow_Params.glsl"

#if defined PHYSICSMOD_OCEAN_SHADER
	#include "/lib/oceans.glsl"
#endif

#if defined PHYSICSMOD_OCEAN_SHADER_V2
	#include "/lib/oceans_v2.glsl"
#endif

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

out DATA {
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

uniform sampler2D colortex4;
uniform sampler2D noisetex;

#ifdef OVERWORLD_SHADER
	#include "/lib/scene_controller.glsl"
#endif

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;

in vec4 at_tangent;
in vec4 mc_Entity;
#if defined ENTITIES || defined BLOCKENTITIES
	uniform int entityId;
#endif

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform float sunElevation;

uniform int frameCounter;
// uniform float far;
uniform float aspectRatio;
uniform float viewHeight;
uniform float viewWidth;
uniform int hideGUI;
uniform float screenBrightness;

uniform vec2 texelSize;
uniform int framemod8;

#include "/lib/TAA_jitter.glsl"


#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

vec4 toClipSpace3(vec3 viewSpacePosition) {
    return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition),-viewSpacePosition.z);
}


float getWave (vec3 pos, float range){
	// return pow(1.0-texture(noisetex, (pos.xz + frameTimeCounter * WATER_WAVE_SPEED)/150.0).b,2.0) * WATER_WAVE_STRENGTH * range;
	return pow(1.0-texture(noisetex, (pos.xz + frameTimeCounter * WATER_WAVE_SPEED)/125.0).r,5.0) * min(WATER_WAVE_STRENGTH, 1.0) * range;
}

vec3 getWaveNormal(vec3 posxz, float range){

	float deltaPos = 0.5;

	vec3 coord = posxz;

	float h0 = getWave(coord,range);
	float h1 = getWave(coord - vec3(deltaPos,0.0,0.0),range);
	float h3 = getWave(coord - vec3(0.0,0.0,deltaPos),range);


	float xDelta = (h1-h0)/deltaPos * 1.5;
	float yDelta = (h3-h0)/deltaPos * 1.5;

	vec3 wave = normalize(vec3(xDelta, yDelta,1.0-pow(abs(xDelta+yDelta),2.0)));

	return wave;

}

#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 1 && !defined HAND
	uniform float caveDetection;
#endif

uniform int currentRenderedItemId;

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {

	gl_Position = ftransform();

	color.rgb = gl_Color.rgb;
	#if defined LIGHTNING || defined ENTITIES
		color.a = gl_Color.a;
	#endif

	bool isWater = mc_Entity.x == 8.0;

	#if defined PHYSICSMOD_OCEAN_SHADER && defined PHYSICS_OCEAN
    	// basic texture to determine how shallow/far away from the shore the water is
    	physics_localWaviness = texelFetch(physics_waviness, ivec2(gl_Vertex.xz) - physics_textureOffset, 0).r;
    	// transform gl_Vertex (since it is the raw mesh, i.e. not transformed yet)
    	vec4 finalPosition = vec4(gl_Vertex.x, gl_Vertex.y + physics_waveHeight(gl_Vertex.xz, PHYSICS_ITERATIONS_OFFSET, physics_localWaviness, physics_gameTime), gl_Vertex.z, gl_Vertex.w);
    	// pass this to the fragment shader to fetch the texture there for per fragment normals
    	physics_localPosition = finalPosition.xyz;

		vec3 position = mat3(gl_ModelViewMatrix) * vec3(finalPosition) + gl_ModelViewMatrix[3].xyz;
	#elif defined PHYSICSMOD_OCEAN_SHADER_V2
		// basic value to determine how shallow/far away from the shore the water is
		physics_localWaviness = physics_waviness;
		// transform gl_Vertex (since it is the raw mesh, i.e. not transformed yet)
		float baseWaveHeight = physics_waveHeight(gl_Vertex.xz, PHYSICS_ITERATIONS_OFFSET, physics_localWaviness, physics_gameTime);
		float rippleHeight = physics_rippleVertexHeight(gl_Vertex.xz);
		vec4 finalPosition = vec4(gl_Vertex.x, gl_Vertex.y + baseWaveHeight + rippleHeight, gl_Vertex.z, gl_Vertex.w);
		// pass this to the fragment shader to fetch the texture there for per fragment normals
		physics_localPosition = finalPosition.xyz;
		
		// now use finalPosition instead of gl_Vertex
		vec3 position = mat3(gl_ModelViewMatrix) * vec3(finalPosition) + gl_ModelViewMatrix[3].xyz;
	#else
		vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;
	#endif

	// lmtexcoord.xy = (gl_MultiTexCoord0).xy;
	lmtexcoord.xy = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmtexcoord.zw = gl_MultiTexCoord1.xy / 240.0;

	#if defined LARGE_WAVE_DISPLACEMENT && !defined PHYSICS_OCEAN
		if(isWater) {
				
			vec3 playerPos = mat3(gbufferModelViewInverse) * position.xyz;

			#ifdef DISTANT_HORIZONS
				float range = pow(1-pow(1-clamp(1.0 - length(playerPos) / far, 0.0,1.0),3.0),3.0);
			#else
				float range = min(1.0 + pow(length(playerPos) / 256,2.0), 256.0);
			#endif

			vec4 displacedVertex = vec4(gl_Vertex.x, gl_Vertex.y + (getWave(gl_Vertex.xyz + cameraPosition, range)*0.6-0.5), gl_Vertex.z, gl_Vertex.w);
			position = mat3(gl_ModelViewMatrix) * vec3(displacedVertex) + gl_ModelViewMatrix[3].xyz;
			
			playerPos = mat3(gbufferModelViewInverse) * position.xyz;
			largeWaveDisplacementNormal = getWaveNormal(playerPos + cameraPosition, range);

		}
	#endif

	#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 0 && !defined HAND
		chunkFade = abs(mc_chunkFade);
	#endif
	
	// keep this OUT of the #if block... otherwise there will be z-fighting when using some overlay textures for some random ass reason.....
	vec3 worldpos = mat3(gbufferModelViewInverse) * position + gbufferModelViewInverse[3].xyz;

	#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 1 && !defined HAND
		worldpos.y += -45.0*(1.0-chunkFade)*(1.0-caveDetection)*smoothstep(25.0, far, length(worldpos));
	#endif

	#ifdef PLANET_CURVATURE
		float curvature = length(worldpos.xz) / (16.0*8.0);
		worldpos.y -= curvature*curvature * CURVATURE_AMOUNT;
	#endif

	position = mat3(gbufferModelView) * worldpos + gbufferModelView[3].xyz;
	
 	gl_Position = toClipSpace3(position);

	#if defined ENTITIES && defined IS_IRIS
		// force out of frustum
		if (entityId == 1599) gl_Position.z -= 10000.0;
	#endif
	
	// 1.0 = water mask
	// 0.9 = entity mask
	// 0.8 = reflective entities
	// 0.7 = reflective blocks
	// 0.6 = nether portal
	float mat = 0.0;

	// water mask
	if(isWater
	#if MC_VERSION > 12111
	 || mc_Entity.x == 505
	#endif
	 
	 ) {
    	mat = 1.0;
  	}

	// translucent entities
	#if defined ENTITIES || defined BLOCKENTITIES
		mat = 0.4;
		if (entityId == 1804) mat = 0.2;
	#endif

	// translucent blocks
	if (mc_Entity.x >= 301 && mc_Entity.x <= 338 || currentRenderedItemId >= 301 && currentRenderedItemId <= 338) mat = 0.1;

	// if (mc_Entity.x == BLOCK_NETHER_PORTAL) mat = 0.6;

	if (mc_Entity.x == WISPJELLY || currentRenderedItemId== WISPJELLY) lmtexcoord.z = 0.0;

	#if defined ENTITIES && defined IS_IRIS
		NAMETAG = 0;
		if (entityId == 1600) NAMETAG = 1;
		else if (entityId == 1615) NAMETAG = 2;
	#endif
	


	tangent = vec4(normalize(gl_NormalMatrix * at_tangent.rgb),at_tangent.w);
	normalMat = vec4(normalize(gl_NormalMatrix * gl_Normal), mat);
	vec3 binormal = normalize(cross(tangent.rgb,normalMat.xyz)*at_tangent.w);
	mat3 tbnMatrix = mat3(tangent.x, binormal.x, normalMat.x,
						  tangent.y, binormal.y, normalMat.y,
						  tangent.z, binormal.z, normalMat.z);

	#ifdef LARGE_WAVE_DISPLACEMENT
		if(isWater) {
			largeWaveDisplacementNormal = normalize(largeWaveDisplacementNormal * tbnMatrix);
		}else{
			largeWaveDisplacementNormal = normalMat.xyz;
		}
	#endif

	viewVector = position.xyz;
	if(isWater) viewVector = normalize(tbnMatrix * viewVector);

	#ifdef OVERWORLD_SHADER		
		// WsunVec = lightCol.a * normalize(mat3(gbufferModelViewInverse) * sunPosition);
		
		#ifdef SMOOTH_SUN_ROTATION
			WsunVec = WsunVecSmooth;
		#else
			WsunVec = normalize(mat3(gbufferModelViewInverse) * sunPosition);
		#endif
		#ifdef CUSTOM_MOON_ROTATION
			vec3 moonVec = customMoonVecSSBO;
		#else
			#ifdef SMOOTH_MOON_ROTATION
				vec3 moonVec = WmoonVecSmooth;
			#else
				vec3 moonVec = normalize(mat3(gbufferModelViewInverse) * moonPosition);
			#endif
			if(dot(-moonVec, WsunVec) < 0.9999) moonVec = -moonVec;
		#endif
		
		vec3 WmoonVec = moonVec;

		WsunVec = mix(WmoonVec, WsunVec, clamp(float(sunElevation > 1e-5)*2.0 - 1.0,0,1));
	#endif

	#ifdef LIGHTNING
		LIGHTNING_BOLT = 0.0;
		normalMat.a = 0.5;
		if(entityId == ENTITY_LIGHTNING){
			LIGHTNING_BOLT = 1.0;
		}
	#endif

	#ifdef TAA_UPSCALING
		gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
	#endif
	#ifdef TAA
		#if defined ENTITIES && defined IS_IRIS
		// remove jitter for nametags lol
			if (entityId != 1600) gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
		#else
			gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
		#endif
	#endif

	#if DOF_QUALITY == 5
		vec2 jitter = clamp(jitter_offsets[frameCounter % 64], -1.0, 1.0);
		jitter = rotate(radians(float(frameCounter))) * jitter;
		jitter.y *= aspectRatio;
		jitter.x *= DOF_ANAMORPHIC_RATIO;

		#if MANUAL_FOCUS == -2
		float focusMul = 0;
		#elif MANUAL_FOCUS == -1
		float focusMul = gl_Position.z - mix(pow(512.0, screenBrightness), 512.0 * screenBrightness, 0.25);
		#else
		float focusMul = gl_Position.z - MANUAL_FOCUS;
		#endif

		vec2 totalOffset = (jitter * JITTER_STRENGTH) * focusMul * 1e-2;
		gl_Position.xy += hideGUI >= 1 ? totalOffset : vec2(0);
	#endif
}
