#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/bokeh.glsl"
#include "/lib/blocks.glsl"
#include "/lib/entities.glsl"
#include "/lib/items.glsl"

#include "/lib/SSBOs.glsl"

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/


#ifdef HAND
#undef POM
#endif

#ifndef USE_LUMINANCE_AS_HEIGHTMAP
#ifndef MC_NORMAL_MAP
#undef POM
#endif
#endif

#ifdef POM
#define MC_NORMAL_MAP
#endif



out DATA {
	#if !defined ENTITIES && !defined HAND && defined SHADER_GRASS && !defined BLOCKENTITIES && !defined CUTOUT
		vec4 grassSideCheck;
		vec3 centerPosition;
	#endif

	vec4 color;

	#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 0 && !defined HAND
		float chunkFade;
	#endif

	vec4 lmtexcoord;
	vec3 normalMat;

	#if defined POM && (defined WORLD && !defined ENTITIES && !defined HAND || defined COLORWHEEL)
		vec4 texcoordam; // .st for add, .pq for mul
		vec2 texcoord;
	#endif

	#ifdef MC_NORMAL_MAP
		vec4 tangent;
	#endif

	flat int blockID;
} data_out;

#ifdef MC_NORMAL_MAP
	in vec4 at_tangent;
#endif

uniform float frameTimeCounter;
const float PI48 = 150.796447372*WAVY_SPEED;
float pi2wt = PI48*frameTimeCounter;

in vec4 mc_Entity;
in vec4 mc_midTexCoord;

uniform int blockEntityId;
uniform int entityId;


uniform int heldItemId;
uniform int heldItemId2;

#ifdef IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
	in vec4 at_midBlock;
#else
	in vec3 at_midBlock;
#endif

uniform int frameCounter;
uniform float far;
uniform float aspectRatio;
uniform float viewHeight;
uniform float viewWidth;
uniform int hideGUI;
uniform float screenBrightness;
uniform int isEyeInWater;

// in vec3 at_velocity;
// out vec3 velocity;

uniform float nightVision;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec2 texelSize;

#if defined HAND
	uniform mat4 gbufferPreviousModelView;
	uniform vec3 previousCameraPosition;

	float detectCameraMovement(){
		// simply get the difference of modelview matrices and cameraPosition across a frame.
		vec3 fakePos = vec3(0.5,0.5,0.0);
		vec3 hand_playerPos = mat3(gbufferModelViewInverse) * fakePos + (cameraPosition - previousCameraPosition);
		vec3 previousPosition = mat3(gbufferPreviousModelView) * hand_playerPos;
		float detectMovement = 1.0 - clamp(distance(previousPosition, fakePos)/texelSize.x,0.0,1.0);

		return detectMovement;
	}
#endif

//#ifndef IS_LPV_ENABLED
	uniform vec3 relativeEyePosition;
//#endif

#if !defined ENTITIES && !defined HAND && defined SHADER_GRASS && (defined GRASS_DETECT_FALLOFF || defined GRASS_DETECT_INV_FALLOFF || REPLACE_SHORT_GRASS > 0)
	uniform usampler1D texBlockData;
	#include "/lib/lpv_common.glsl"
	#include "/lib/lpv_blocks.glsl"
	#include "/lib/lpv_buffer.glsl"
	#include "/lib/voxel_common.glsl"

	uint GetVoxelBlock(const in ivec3 voxelPos) {
		if (clamp(voxelPos, ivec3(0), ivec3(VoxelSize3-1u)) != voxelPos)
			return BLOCK_EMPTY;
		
		return imageLoad(imgVoxelMask, voxelPos).r;
	}
#endif

							
#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec4 toClipSpace3(vec3 viewSpacePosition) {
    return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition),-viewSpacePosition.z);
}

vec2 calcWave(in vec3 pos) {

    float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec2 ret = (sin(pi2wt*vec2(0.0063,0.0015)*4. - pos.xz + pos.y*0.05)+0.1)*magnitude;

    return ret;
}

vec3 calcMovePlants(in vec3 pos) {
    vec2 move1 = calcWave(pos );
	float move1y = -length(move1);
   return vec3(move1.x,move1y,move1.y)*5.*WAVY_STRENGTH;
}

vec3 calcWaveLeaves(in vec3 pos) {

    float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec3 ret = (sin(pi2wt*vec3(0.0063,0.0224,0.0015)*1.5 - pos))*magnitude;

    return ret;
}

vec3 calcMoveLeaves(in vec3 pos, in vec3 amp1) {
    vec3 move1 = calcWaveLeaves(pos) * amp1;
    return move1*5.*WAVY_STRENGTH;
}

vec3 srgbToLinear2(vec3 srgb){
    return mix(
        srgb / 12.92,
        pow(.947867 * srgb + .0521327, vec3(2.4) ),
        step( .04045, srgb )
    );
}
vec3 blackbody2(float Temp)
{
    float t = pow(Temp, -1.5);
    float lt = log(Temp);

    vec3 col = vec3(0.0);
         col.x = 220000.0 * t + 0.58039215686;
         col.y = 0.39231372549 * lt - 2.44549019608;
         col.y = Temp > 6500. ? 138039.215686 * t + 0.72156862745 : col.y;
         col.z = 0.76078431372 * lt - 5.68078431373;
         col = clamp(col,0.0,1.0);
         col = Temp < 1000. ? col * Temp * 0.001 : col;

    return srgbToLinear2(col);
}
// float luma(vec3 color) {
// 	return dot(color,vec3(0.21, 0.72, 0.07));
// }

#define SEASONS_VSH
#include "/lib/climate_settings.glsl"

uniform int framemod8;


#include "/lib/TAA_jitter.glsl"


uniform sampler2D noisetex;//depth
float densityAtPos(in vec3 pos){
	pos /= 18.;
	pos.xz *= 0.5;
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,193.0);
	vec2 coord =  uv / 512.0;
	
	//The y channel has an offset to avoid using two textures fetches
	vec2 xy = texture(noisetex, coord).yx;

	return mix(xy.r,xy.g, f.y);
}
float luma(vec3 color) {
	return dot(color,vec3(0.21, 0.72, 0.07));
}
vec3 viewToWorld(vec3 viewPos) {
    vec4 pos;
    pos.xyz = viewPos;
    pos.w = 0.0;
    pos = gbufferModelViewInverse * pos;
    return pos.xyz;
}
#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 1 && !defined HAND
	uniform float caveDetection;
#endif

#if defined BLOCKENTITIES && !defined COLORWHEEL && (MC_VERSION >= 260100 || !defined SHADER_END_PORTAL)
	vec4 projection_from_position(vec4 position) {
		vec4 projection = position * 0.5;
		projection.xy = vec2(projection.x + projection.w, projection.y + projection.w);
		projection.zw = position.zw;
		return projection;
	}
#endif

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {

	gl_Position = ftransform();

	#if defined ENTITIES && defined IS_IRIS
		// force out of frustum
		if (entityId == 1599) gl_Position.z -= 10000.0;
	#endif

	vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;

    /////// ----- COLOR STUFF ----- ///////
	data_out.color = gl_Color;

	#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 0 && !defined HAND
		data_out.chunkFade = abs(mc_chunkFade);
	#endif


    /////// ----- RANDOM STUFF ----- ///////
	// gl_TextureMatrix[0] for animated things like charged creepers
	data_out.lmtexcoord.xy = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	#if defined POM && (defined WORLD && !defined ENTITIES && !defined HAND || defined COLORWHEEL)
		vec2 midcoord = (gl_TextureMatrix[0] *  mc_midTexCoord).st;
		vec2 texcoordminusmid = data_out.lmtexcoord.xy-midcoord;
		data_out.texcoordam.pq  = abs(texcoordminusmid)*2.;
		data_out.texcoordam.st  = min(data_out.lmtexcoord.xy,midcoord-texcoordminusmid);
		data_out.texcoord.xy    = sign(texcoordminusmid)*0.5+0.5;
	#endif

	data_out.lmtexcoord.zw = gl_MultiTexCoord1.xy / 240.0; 

	#ifdef MC_NORMAL_MAP
		data_out.tangent = vec4(normalize(gl_NormalMatrix * at_tangent.rgb), at_tangent.w);
	#endif

	data_out.normalMat = normalize(gl_NormalMatrix * gl_Normal);
	
	#ifdef ENTITIES
		data_out.blockID = int(entityId);
	#elif defined BLOCKENTITIES
		data_out.blockID = int(blockEntityId);
	#else
		data_out.blockID = int(mc_Entity.x);
	#endif

	vec3 worldNormals = viewToWorld(data_out.normalMat);

	#if defined CUTOUT
		if (data_out.blockID == BLOCK_GRASS) {
			if(all(lessThan(abs(worldNormals), vec3(0.95, 0.05, 0.95)))) data_out.blockID = -BLOCK_GRASS;
		}
	#endif

	#if defined WORLD && !defined HAND
		#ifdef BLOCKENTITIES
			if(blockEntityId == BLOCK_END_PORTAL || blockEntityId == BLOCK_END_GATEWAY) {
				data_out.lmtexcoord.w = 0.0;
			}
		#endif

		#if (PUDDLE_MODE > 0 || ShaderSnow > 0) && !defined CUTOUT
			if(data_out.blockID == 215) data_out.lmtexcoord.w = 0.0;
		#endif
	#endif

	#if PUDDLE_MODE > 0 || ShaderSnow > 0
		if (data_out.blockID == 244 || data_out.blockID == 189) data_out.lmtexcoord.w = 0.0;
	#endif

#ifdef WORLD

   	vec3 worldpos = mat3(gbufferModelViewInverse) * position + gbufferModelViewInverse[3].xyz;

	#if !defined ENTITIES && !defined HAND && defined SHADER_GRASS && (defined GRASS_DETECT_FALLOFF || defined GRASS_DETECT_INV_FALLOFF || REPLACE_SHORT_GRASS > 0) && !defined BLOCKENTITIES

		#ifndef CUTOUT
			data_out.grassSideCheck = vec4(0.0);
		
			if(length(worldpos) < min(GRASS_RANGE, 0.5*float(LpvSize)) && data_out.blockID == 85 && worldNormals.y > 0.9) {

				float fractYPos = fract(worldpos.y+cameraPosition.y);
				if(fractYPos > 0.9999 || fractYPos < 0.0001 || abs(fractYPos - 0.5) < 0.0001) {

					data_out.centerPosition = worldpos + at_midBlock.xyz / 64.0;

					vec3 LPVpos = GetLpvPosition2(data_out.centerPosition);

					#if REPLACE_SHORT_GRASS > 0
						uint blockTop = GetVoxelBlock(ivec3(LPVpos.x, LPVpos.y + 0.6, LPVpos.z));
					#else
						uint blockTop = 0;
					#endif

					if(blockTop == 12 || blockTop > 4000) {
						data_out.grassSideCheck = vec4(2.0);
					}
					#if REPLACE_SHORT_GRASS < 2
					else {
						uint blockEast = GetVoxelBlock(ivec3(LPVpos.x + 1.0, LPVpos.y + 0.6, LPVpos.z));
						uint blockWest = GetVoxelBlock(ivec3(LPVpos.x - 1.0, LPVpos.y + 0.6, LPVpos.z));
						uint blockSouth = GetVoxelBlock(ivec3(LPVpos.x, LPVpos.y + 0.6, LPVpos.z + 1.0));
						uint blockNorth = GetVoxelBlock(ivec3(LPVpos.x, LPVpos.y + 0.6, LPVpos.z - 1.0));

						if(blockEast > 4000 || blockEast == 12 || (blockEast > 80 && blockEast < 86) || blockEast == 503 || (blockEast > 406 && blockEast < 440)) {data_out.grassSideCheck.x = 1.0;} else {
							#ifdef GRASS_DETECT_FALLOFF
								blockEast = GetVoxelBlock(ivec3(LPVpos.x + 1.0, LPVpos.y, LPVpos.z));
								if(blockEast != 85) {data_out.grassSideCheck.x = -1.0;}
							#endif
						}
						if(blockWest > 4000 || blockWest == 12 || (blockWest > 80 && blockWest < 86) || blockWest == 503 || (blockWest > 406 && blockWest < 440)) {data_out.grassSideCheck.y = 1.0;} else {
							#ifdef GRASS_DETECT_FALLOFF
								blockWest = GetVoxelBlock(ivec3(LPVpos.x - 1.0, LPVpos.y, LPVpos.z));
								if(blockWest != 85) {data_out.grassSideCheck.y = -1.0;}
							#endif
						}
						if(blockSouth > 4000 || blockSouth == 12 || (blockSouth > 80 && blockSouth < 86) || blockSouth == 503 || (blockSouth > 406 && blockSouth < 440)) {data_out.grassSideCheck.z = 1.0;} else {
							#ifdef GRASS_DETECT_FALLOFF
								blockSouth = GetVoxelBlock(ivec3(LPVpos.x, LPVpos.y, LPVpos.z+ 1.0));
								if(blockSouth != 85) {data_out.grassSideCheck.z = -1.0;}
							#endif
						}
						if(blockNorth > 4000 || blockNorth == 12 || (blockNorth > 80 && blockNorth < 86) || blockNorth == 503 || (blockNorth > 406 && blockNorth < 440)) {data_out.grassSideCheck.w = 1.0;} else {
							#ifdef GRASS_DETECT_FALLOFF
								blockNorth = GetVoxelBlock(ivec3(LPVpos.x, LPVpos.y, LPVpos.z - 1.0));
								if(blockNorth != 85) {data_out.grassSideCheck.w = -1.0;}
							#endif
						}
						#ifndef GRASS_DETECT_INV_FALLOFF
							data_out.grassSideCheck = clamp(data_out.grassSideCheck, -1.0, 0.0);
						#endif
					}
					#endif
				}
			}
		#endif
	#endif

	#if defined WAVY_PLANTS && !defined ENTITIES && !defined HAND
		// also use normal, so up/down facing geometry does not get detatched from its model parts.
		bool InterpolateFromBase = gl_MultiTexCoord0.t < max(mc_midTexCoord.t, abs(worldNormals.y));

		if(	
			(
				// these wave off of the ground. the area connected to the ground does not wave.
				(InterpolateFromBase && (mc_Entity.x == BLOCK_GRASS_TALL_LOWER || mc_Entity.x == BLOCK_GROUND_WAVING || mc_Entity.x == BLOCK_GRASS_SHORT || mc_Entity.x == BLOCK_SAPLING || mc_Entity.x == BLOCK_GROUND_WAVING_VERTICAL
				#if defined CUTOUT && defined WAVING_MULTIPART_GRASS
				|| data_out.blockID == -BLOCK_GRASS
				#endif
				)) 

				// these wave off of the ceiling. the area connected to the ceiling does not wave.
				|| (!InterpolateFromBase && (mc_Entity.x == BLOCK_VINE_OTHER))

				// these wave off of the air. they wave uniformly
				|| (mc_Entity.x == BLOCK_GRASS_TALL_UPPER || mc_Entity.x == BLOCK_AIR_WAVING)

			) && abs(position.z) < 64.0
		){
			// vec3 offsetPos = UnalteredWorldpos+vec3(0.0, 1.0, 0.0)+relativeEyePosition;
            // float playerDist = smoothstep(0.5, 0.05, length(offsetPos.xz)) * smoothstep(1.0, 0.2, abs(offsetPos.y));
            // vec2 dir2 = normalize(UnalteredWorldpos.xz+relativeEyePosition.xz);

			// apply displacement for waving leaf blocks specifically, overwriting the other waving mode. these wave off of the air. they wave uniformly
			if(mc_Entity.x == BLOCK_AIR_WAVING) {
				worldpos += calcMoveLeaves(worldpos + cameraPosition, vec3(1.0,0.2,1.0))*data_out.lmtexcoord.w;
			} else {
				// apply displacement for waving plant blocks
				worldpos += calcMovePlants(worldpos + cameraPosition) * max(data_out.lmtexcoord.w,0.5);
				// worldpos.xz += playerDist*dir2;
			}
		
		}
	#endif

	#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 1 && !defined HAND
	worldpos.y += -45.0*(1.0-data_out.chunkFade)*(1.0-caveDetection)*smoothstep(25.0, far, length(worldpos));
	#endif

	// position = mat3(gbufferModelView) * worldpos + gbufferModelView[3].xyz;

	#ifdef SHADER_GRASS
		#if !defined ENTITIES && !defined HAND && !defined BLOCKENTITIES && !defined CUTOUT
			gl_Position = vec4(worldpos, 0.0);
		#endif

		#if defined PLANET_CURVATURE && (defined BLOCKENTITIES || defined CUTOUT || defined HAND || defined ENTITIES)
			float curvature = length(worldpos.xz) / (16.0*8.0);
			worldpos.y -= curvature*curvature * CURVATURE_AMOUNT;
		#endif

		#if defined BLOCKENTITIES || defined CUTOUT || defined HAND || defined ENTITIES
			gl_Position = toClipSpace3(mat3(gbufferModelView) * vec3(worldpos) + gbufferModelView[3].xyz);
		#endif
	#else
		#if defined PLANET_CURVATURE
			float curvature = length(worldpos.xz) / (16.0*8.0);
			worldpos.y -= curvature*curvature * CURVATURE_AMOUNT;
		#endif

		gl_Position = toClipSpace3(mat3(gbufferModelView) * vec3(worldpos) + gbufferModelView[3].xyz);
	#endif
#endif

	#if !defined SHADER_GRASS || defined ENTITIES || defined HAND || defined BLOCKENTITIES || defined CUTOUT
		#ifdef TAA_UPSCALING
			gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
		#endif
		#ifdef TAA
			vec2 TAA_offsets = offsets[framemod8];
			// #ifdef HAND
				// turn off jitter when camera moves.
				// this is to hide the jitter when the same happens for TAA blend factor and the jitter becomes visible during camera movement
				// gl_Position.xy += (offsets[framemod8] * gl_Position.w*texelSize) * detectCameraMovement();
			// #else	
				gl_Position.xy += TAA_offsets * gl_Position.w*texelSize;
			// #endif
		#endif
	#endif

	#if defined Seasons && defined WORLD && !defined ENTITIES && !defined BLOCKENTITIES && !defined HAND
		YearCycleColor(data_out.color.rgb, gl_Color.rgb, mc_Entity.x == BLOCK_AIR_WAVING, true);
	#endif

	#if DOF_QUALITY == 5 && ((defined SHADER_GRASS && (defined ENTITIES || defined HAND || defined CUTOUT || defined BLOCKENTITIES)) || !defined SHADER_GRASS)
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

	
	#if defined SHADER_GRASS && REPLACE_SHORT_GRASS > 0 && defined CUTOUT
		#if GRASS_DENSITY == 3
			const float maxShortGrassRange = 28.0;
		#elif GRASS_DENSITY == 2
			const float maxShortGrassRange = 24.0;
		#elif GRASS_DENSITY == 1
			const float maxShortGrassRange = 20.0;
		#else
			const float maxShortGrassRange = 16.0;
		#endif

		if(length(worldpos) < maxShortGrassRange && data_out.blockID == 12) {
			vec3 centerPosition = worldpos + at_midBlock.xyz / 64.0;
			vec3 LPVpos = GetLpvPosition2(centerPosition);
			uint blockBelow = GetVoxelBlock(ivec3(LPVpos.x, LPVpos.y - 0.6, LPVpos.z));
			if(blockBelow == 85) gl_Position.z -= 10000.0;
		}
	#endif
	
	#if defined BLOCKENTITIES && !defined COLORWHEEL && (MC_VERSION >= 260100 || !defined SHADER_END_PORTAL)
		if(data_out.blockID == BLOCK_END_PORTAL || data_out.blockID == BLOCK_END_GATEWAY)data_out.lmtexcoord = projection_from_position(gl_Position);
	#endif
}
