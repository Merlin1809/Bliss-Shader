#extension GL_ARB_shader_texture_lod : enable

#include "/lib/settings.glsl"
#include "/lib/blocks.glsl"
#include "/lib/entities.glsl"
#include "/lib/items.glsl"
#include "/lib/hsv.glsl"

#ifdef IRIS_FEATURE_TEXTURE_FILTERING
#include "/lib/texture_filtering.glsl"
#endif

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


in DATA {
	vec4 color;

	#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 0 && !defined HAND
		float chunkFade;
	#endif

	vec4 lmtexcoord;
	vec3 normalMat;

	#if (defined POM && (defined WORLD && !defined ENTITIES && !defined HAND || defined COLORWHEEL)) || (!defined BLOCKENTITIES && !defined ENTITIES && !defined HAND && defined SHADER_GRASS && !defined COLORWHEEL && defined WORLD && !defined CUTOUT)
		vec4 texcoordam; // .st for add, .pq for mul
	#endif

	#if defined POM && (defined WORLD && !defined ENTITIES && !defined HAND || defined COLORWHEEL)
		vec2 texcoord;
	#endif

	#ifdef MC_NORMAL_MAP
		vec4 tangent;
	#endif

	flat int blockID;
} data_in;

const float mincoord = 1.0/4096.0;
const float maxcoord = 1.0-mincoord;

const float MAX_OCCLUSION_DISTANCE = MAX_DIST;
const float MIX_OCCLUSION_DISTANCE = MAX_DIST*0.9;
const int   MAX_OCCLUSION_POINTS   = MAX_ITERATIONS;
const float   MAX_OCCLUSION_POINTS_DIV = 1.0 / MAX_OCCLUSION_POINTS;

uniform vec2 texelSize;
uniform int framemod8;

#if defined POM && (defined WORLD && !defined ENTITIES && !defined HAND || defined COLORWHEEL)
	vec2 dcdx = dFdx(data_in.texcoord.st*data_in.texcoordam.pq);
	vec2 dcdy = dFdy(data_in.texcoord.st*data_in.texcoordam.pq);
#else
	const vec2 dcdx = vec2(0.0);
	const vec2 dcdy = vec2(0.0);
#endif

#include "/lib/res_params.glsl"

#ifdef VISUALIZE_LIGHTMAP
	uniform float viewWidth;
	uniform float viewHeight;
	#include "/lib/text_rendering.glsl"
#endif


uniform float far;


#ifdef MC_NORMAL_MAP
	uniform sampler2D normals;
#endif


uniform sampler2D specular;
uniform sampler2D gtexture;
uniform sampler2D colortex1;//albedo(rgb),material(alpha) RGBA16
uniform float frameTimeCounter;
uniform int frameCounter;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float rainStrength;
uniform sampler2D noisetex;//depth
uniform sampler2D depthtex0;

#if defined VIVECRAFT
	uniform bool vivecraftIsVR;
	uniform vec3 vivecraftRelativeMainHandPos;
	uniform vec3 vivecraftRelativeOffHandPos;
	uniform mat4 vivecraftRelativeMainHandRot;
	uniform mat4 vivecraftRelativeOffHandRot;
#endif

uniform vec4 entityColor;

// in vec3 velocity;

uniform int heldItemId;
uniform int heldItemId2;


uniform float noPuddleAreas;
uniform float nightVision;
uniform vec3 relativeEyePosition;

// float interleaved_gradientNoise(){
// 	return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y)+frameTimeCounter*51.9521);
// }

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

#ifdef TAA
	float blueNoise() {
		return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
	} 
#else
	float blueNoise() {
		return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887);
	}
#endif

uniform int currentRenderedItemId;


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

vec2 encodeNormal(vec3 n){
	n.xy = n.xy / dot(abs(n), vec3(1.0));
	n.xy = n.z <= 0.0 ? (1.0 - abs(n.yx)) * sign(n.xy) : n.xy;
    vec2 encn = clamp(n.xy * 0.5 + 0.5,-1.0,1.0);
	
    return encn;
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

#ifdef MC_NORMAL_MAP
	vec3 applyBump(mat3 tbnMatrix, vec3 bump){
		float bumpmult = NORMAL_MAP_MULT;
		bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);
		return normalize(bump*tbnMatrix);
	}
#endif


#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}
vec3 toClipSpace3(vec3 viewSpacePosition) {
    return projMAD(gbufferProjection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
}

#if defined POM && (defined WORLD && !defined ENTITIES && !defined HAND || defined COLORWHEEL)
	vec4 readNormal(in vec2 coord)
	{
		return textureGrad(normals,fract(coord)*data_in.texcoordam.pq+data_in.texcoordam.st,dcdx,dcdy);
	}
	vec4 readTexture(in vec2 coord)
	{
		return textureGrad(gtexture,fract(coord)*data_in.texcoordam.pq+data_in.texcoordam.st,dcdx,dcdy);
	}
#endif


float luma(vec3 color) {
	return dot(color,vec3(0.21, 0.72, 0.07));
}


vec3 toLinear(vec3 sRGB){
	return sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878);
}


const vec2[8] offsets = vec2[8](vec2(1./8.,-3./8.),
									vec2(-1.,3.)/8.,
									vec2(5.0,1.)/8.,
									vec2(-3,-5.)/8.,
									vec2(-5.,5.)/8.,
									vec2(-7.,-1.)/8.,
									vec2(3,7.)/8.,
									vec2(7.,-7.)/8.);


uniform float near;


float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}


// vec4 readNoise(in vec2 coord){
// 	// return texture(noisetex,coord*texcoordam.pq+texcoord);
// 		return textureGradARB(noisetex,coord*texcoordam.pq + texcoordam.st,dcdx,dcdy);
// }
// float EndPortalEffect(
// 	inout vec4 ALBEDO,
// 	vec3 FragPos,
// 	vec3 WorldPos,
// 	mat3 tbnMatrix
// ){	
// 
// 	int maxdist = 25;
// 	int quality = 35;
// 
// 	vec3 viewVec = normalize(tbnMatrix*FragPos);
// 	if ( viewVec.z < 0.0 && length(FragPos) < maxdist) {
// 		float endportalGLow = 0.0;
// 		float Depth = 0.3;
// 		vec3 interval = (viewVec.xyz /-viewVec.z/quality*Depth) * (0.7 + (blueNoise-0.5)*0.1);
// 
// 		vec3 coord = vec3(WorldPos.xz , 1.0);
// 		coord += interval;
// 
// 		for (int loopCount = 0; (loopCount < quality) && (1.0 - Depth + Depth * ( 1.0-readNoise(coord.st).r - readNoise(-coord.st*3).b*0.2 ) ) < coord.p  && coord.p >= 0.0; ++loopCount) {
// 			coord = coord+interval ; 
// 			endportalGLow += (0.3/quality);
// 		}
// 
//   		ALBEDO.rgb = vec3(0.5,0.75,1.0) * sqrt(endportalGLow);
// 
// 		return clamp(pow(endportalGLow*3.5,3),0,1);
// 	}
// }

float bias(){
	// bias mipmapping as window resolution and / or render scale changes.
	#ifdef TAA_UPSCALING
		return (1.0 - texelSize.x * 2560.0) + (0.0 - (1.0-RENDER_SCALE.x) * 2.0);
	#else
		return 1.0 - texelSize.x * 2560.0;
	#endif
}
vec4 texture_POMSwitch(
	sampler2D sampler, 
	vec2 lightmapCoord,
	vec4 dcdxdcdy, 
	bool ifPOM,
	float LOD
){
	#if defined POM && (defined WORLD && !defined ENTITIES && !defined HAND || defined COLORWHEEL)
	if(ifPOM){
		return textureGrad(sampler, lightmapCoord, dcdxdcdy.xy, dcdxdcdy.zw);
	}else
	#endif
	{
		return texture(sampler, lightmapCoord, LOD);
	}
}

void convertHandDepth(inout float depth) {
    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;
    depth = ndcDepth * 0.5 + 0.5;
}

float getEmission(vec3 Albedo) {
	vec3 hsv = RgbToHsv(Albedo);
    float emissive = smoothstep(0.05, 0.15, hsv.y) * pow(hsv.z, 3.5);
    return emissive * 0.5;
}

float getTrimEmission(vec3 Albedo) {
	vec3 hsv = RgbToHsv(Albedo);
    return sqrt(hsv.z);
}

#if defined BLOCKENTITIES && !defined COLORWHEEL && (MC_VERSION >= 260100 || !defined SHADER_END_PORTAL)
	mat2 mat2_rotate_z(float radians) {
		return mat2(
			cos(radians), -sin(radians),
			sin(radians), cos(radians)
		);
	}

	const vec3[] COLORS = vec3[](
		vec3(0.022087, 0.098399, 0.110818),
		vec3(0.011892, 0.095924, 0.089485),
		vec3(0.027636, 0.101689, 0.100326),
		vec3(0.046564, 0.109883, 0.114838),
		vec3(0.064901, 0.117696, 0.097189),
		vec3(0.063761, 0.086895, 0.123646),
		vec3(0.084817, 0.111994, 0.166380),
		vec3(0.097489, 0.154120, 0.091064),
		vec3(0.106152, 0.131144, 0.195191),
		vec3(0.097721, 0.110188, 0.187229),
		vec3(0.133516, 0.138278, 0.148582),
		vec3(0.070006, 0.243332, 0.235792),
		vec3(0.196766, 0.142899, 0.214696),
		vec3(0.047281, 0.315338, 0.321970),
		vec3(0.204675, 0.390010, 0.302066),
		vec3(0.080955, 0.314821, 0.661491)
	);

	const mat4 SCALE_TRANSLATE = mat4(
		0.5, 0.0, 0.0, 0.25,
		0.0, 0.5, 0.0, 0.25,
		0.0, 0.0, 1.0, 0.0,
		0.0, 0.0, 0.0, 1.0
	);

	mat4 end_portal_layer(float layer) {
		mat4 translate = mat4(
			1.0, 0.0, 0.0, 17.0 / layer,
			0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (frameTimeCounter * 0.0011),
			0.0, 0.0, 1.0, 0.0,
			0.0, 0.0, 0.0, 1.0
		);

		mat2 rotate = mat2_rotate_z(radians((layer * layer * 4321.0 + layer * 9.0) * 2.0));

		mat2 scale = mat2((4.5 - layer / 4.0) * 2.0);

		return mat4(scale * rotate) * translate * SCALE_TRANSLATE;
	}
#endif

uniform float alphaTestRef;

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

layout(location = 0) out vec4 OutAlbedo;
layout(location = 1) out vec4 OutSpecular;

#if defined HAND || defined ENTITIES || defined BLOCKENTITIES
	layout(location = 2) out vec4 OutTranslucents;
	#ifdef VOXY
		layout(location = 3) out vec4 OutTranslucents2;
		/* RENDERTARGETS:1,8,2,7 */
	#else
		/* RENDERTARGETS:1,8,2 */
	#endif
#else
	/* RENDERTARGETS:1,8 */
#endif

void main() {
	vec3 FragCoord = gl_FragCoord.xyz;

	#ifdef HAND
		convertHandDepth(FragCoord.z);
	#endif
	
	#ifdef POM
		bool ifPOM = true;
	#else
		bool ifPOM = false;
	#endif

	#if !defined BLOCKENTITIES && !defined ENTITIES && !defined HAND && defined SHADER_GRASS && !defined COLORWHEEL && defined WORLD && !defined CUTOUT
		bool ShaderGrass = data_in.blockID == -15;
		if(ShaderGrass) ifPOM = false;
	#else
		bool ShaderGrass = false;
	#endif

	bool SIGN = data_in.blockID == BLOCK_SIGN;

	#ifdef ENTITIES
		// disallow POM to work on item frames.
		SIGN = data_in.blockID == ENTITY_ITEM_FRAME || data_in.blockID == ENTITY_GLOW_ITEM_FRAME;
	#else
		SIGN = data_in.blockID == BLOCK_SIGN;
	#endif

	if(SIGN) ifPOM = false;

	vec3 normal = data_in.normalMat;

	#ifdef MC_NORMAL_MAP
		vec3 binormal = normalize(cross(data_in.tangent.rgb,normal)*data_in.tangent.w);
		mat3 tbnMatrix = mat3(data_in.tangent.x, binormal.x, normal.x,
							  data_in.tangent.y, binormal.y, normal.y,
							  data_in.tangent.z, binormal.z, normal.z);
	#endif

	float BN = blueNoise();
	float R2 = R2_dither();

	vec2 tempOffset = offsets[framemod8];

	vec3 fragpos = toScreenSpace(FragCoord*vec3(texelSize/RENDER_SCALE,1.0)-vec3(vec2(tempOffset)*texelSize*0.5, 0.0));
	vec3 playerpos = mat3(gbufferModelViewInverse) * fragpos  + gbufferModelViewInverse[3].xyz;
	vec3 worldpos = playerpos + cameraPosition;

	vec2 adjustedTexCoord = data_in.lmtexcoord.xy;

	float saveDepth = 0.0;
#if defined POM && (defined WORLD && !defined ENTITIES && !defined HAND || defined COLORWHEEL)
	// vec2 tempOffset=offsets[framemod8];
	
	// this fixes create multiblock entity thingies like train wheels (but probably breaks something else, didn't notice anything tho)
	#ifndef COLORWHEEL
		// adjustedTexCoord = fract(data_in.texcoord.st)*data_in.texcoordam.pq+data_in.texcoordam.st;
	#endif

	// vec3 fragpos = toScreenSpace(gl_FragCoord.xyz*vec3(texelSize/RENDER_SCALE,1.0)-vec3(vec2(tempOffset)*texelSize*0.5,0.0));
	vec3 viewVector = normalize(tbnMatrix*fragpos);
	float dist = length(playerpos);

	float falloff = min(max(1.0-dist/MAX_OCCLUSION_DISTANCE,0.0) * 2.0,1.0);

	falloff = pow(1.0-pow(1.0-falloff,1.0),2.0);

	// falloff =  1;

	float maxdist = MAX_OCCLUSION_DISTANCE;
	if(!ifPOM) maxdist = 0.0;

	#if defined DEPTH_WRITE_POM
		gl_FragDepth = gl_FragCoord.z;
	#endif

	#if !defined BLOCKENTITIES && !defined ENTITIES && !defined HAND && defined SHADER_GRASS && !defined COLORWHEEL && defined WORLD && !defined CUTOUT
	 if (falloff > 0.0 && !ShaderGrass)
	#else
	 if (falloff > 0.0)
	#endif
	{
		float depthmap = readNormal(data_in.texcoord.st).a;
		float pomdepth = POM_DEPTH * falloff;

 		if ( viewVector.z < 0.0 && depthmap < 0.9999 && depthmap > 0.00001) {	
			float noise = BN;
			#ifdef Adaptive_Step_length
				depthmap = clamp(1.0 - depthmap * depthmap, 0.1, 1.0);
				vec3 interval = (viewVector.xyz / -viewVector.z * MAX_OCCLUSION_POINTS_DIV * pomdepth) * depthmap;
			#else
				vec3 interval = viewVector.xyz /-viewVector.z * MAX_OCCLUSION_POINTS_DIV * pomdepth;
			#endif
			vec3 coord = vec3(data_in.texcoord.st , 1.0);

			coord += interval * noise;

			float sumVec = noise;
			for (int loopCount = 0; (loopCount < MAX_OCCLUSION_POINTS) && (1.0 - pomdepth + pomdepth * readNormal(coord.st).a) < coord.p && coord.p >= 0.0; ++loopCount) {
				coord = coord + interval; 
				sumVec += 1.0; 
			}

			#if defined POM_OFFSET_SHADOW_BIAS
				#ifdef Adaptive_Step_length
					saveDepth += clamp(MAX_OCCLUSION_POINTS_DIV * depthmap-0.0001, 0.0, 1.0);
				#else
					saveDepth += clamp(MAX_OCCLUSION_POINTS_DIV-0.0001, 0.0, 1.0);
				#endif
			#endif
	
			if (coord.t < mincoord) {
				if (readTexture(vec2(coord.s,mincoord)).a == 0.0) {
					coord.t = mincoord;
					discard;
				}
			}
			
			adjustedTexCoord = mix(fract(coord.st)*data_in.texcoordam.pq+data_in.texcoordam.st, adjustedTexCoord, max(dist-MIX_OCCLUSION_DISTANCE,0.0)/(MAX_OCCLUSION_DISTANCE-MIX_OCCLUSION_DISTANCE));

			#if defined DEPTH_WRITE_POM
				vec3 truePos = fragpos + sumVec*inverseMatrix(tbnMatrix)*interval;
				gl_FragDepth = toClipSpace3(truePos).z;
			#endif
		}
	}
#endif
	if(!ifPOM) adjustedTexCoord = data_in.lmtexcoord.xy;

	float opaqueMasks = 1.0;

	vec2 lmcoord = data_in.lmtexcoord.zw;

	#ifdef HAND
		opaqueMasks = 0.75;
	#else
		#if defined WORLD && !defined ENTITIES
			if(data_in.blockID == BLOCK_GROUND_WAVING_VERTICAL || data_in.blockID == BLOCK_GRASS_SHORT || data_in.blockID == BLOCK_GRASS_TALL_LOWER || data_in.blockID == BLOCK_GRASS_TALL_UPPER ) opaqueMasks = 0.60;
			else if(data_in.blockID == BLOCK_AIR_WAVING) opaqueMasks = 0.55;
		#endif

		#if defined ENTITIES
		if (data_in.blockID == ENTITY_GLOW_ITEM_FRAME) {opaqueMasks = 0.9; lmcoord.x = min(lmcoord.x, 0.925);}
		else opaqueMasks = 0.45;
		#endif

		#if !defined BLOCKENTITIES && !defined ENTITIES && defined SHADER_GRASS && !defined COLORWHEEL && !defined HAND && !defined CUTOUT
			if(ShaderGrass) opaqueMasks = 0.8;
		#endif
	#endif
	

	//////////////////////////////// 				////////////////////////////////
	////////////////////////////////	ALBEDO		////////////////////////////////
	//////////////////////////////// 				//////////////////////////////// 

	float textureLOD = bias();

	vec4 Color = data_in.color;

	#ifndef COLORWHEEL
		float vanillaAO = 1.0 - clamp(Color.a,0,1);

		// don't fix vanilla ao on some custom block models.
		// if (Color.a < 0.3) Color.a = 1.0; // fix vanilla ao on some custom block models.

		vec4 Albedo = vec4(Color.rgb, 1.0);
		
		#if !defined BLOCKENTITIES && !defined ENTITIES && !defined HAND && defined SHADER_GRASS && defined WORLD && !defined CUTOUT
		if (!ShaderGrass)
		#endif
		{
		#ifdef IRIS_FEATURE_TEXTURE_FILTERING
		vec2 texSize = 1.0 / vec2(textureSize(gtexture, 0));
		 Albedo *= textureFilteringMode == 1 ? sampleRGSS(gtexture, adjustedTexCoord.xy, texSize) : sampleNearest(gtexture, adjustedTexCoord.xy, texSize);
		#else
		 Albedo *= texture_POMSwitch(gtexture, adjustedTexCoord.xy, vec4(dcdx,dcdy), ifPOM, textureLOD);
		#endif
		}
	#else
		vec4 Albedo = texture_POMSwitch(gtexture, adjustedTexCoord.xy, vec4(dcdx,dcdy), ifPOM, textureLOD);
		vec4 overlayColor;
		float vanillaAO;

		clrwl_computeFragment(Albedo, Albedo, lmcoord, vanillaAO, overlayColor);
		lmcoord = clamp((lmcoord - 1.0 / 32.0) * 32.0 / 30.0, 0.0, 1.0);
		vanillaAO = 1.0 - clamp(vanillaAO, 0,1);
	#endif

	#ifdef WORLD
		vec3 flatNormals = viewToWorld(normal);
	#endif

	#if REPLACE_SHORT_GRASS < 2 && !defined BLOCKENTITIES && !defined ENTITIES && !defined HAND && defined SHADER_GRASS && !defined COLORWHEEL && defined WORLD && !defined CUTOUT
		// darken the top of grass blocks a bit
		if(data_in.blockID == 85 && flatNormals.y > 0.9 && !ShaderGrass) Albedo.rgb *= smoothstep(-30.0, 25.0, length(playerpos));
	#endif

	#if defined DISTANT_HORIZONS && DH_CHUNK_FADING > 0
			float viewDist = length(playerpos); 
			float ditherFade = smoothstep(0.98 * far, 1.03 * far, viewDist);

			if(step(ditherFade, R2) == 0.0) discard;
	#endif
	
	if(Albedo.a < alphaTestRef) discard;
	
	#if defined IRIS_FEATURE_FADE_VARIABLE && VANILLA_CHUNK_FADING > 0 && !defined HAND
		#ifdef TAA
			if(sqrt(data_in.chunkFade) < BN) discard;
		#else
			if(sqrt(data_in.chunkFade) < R2) discard;
		#endif
	#endif

	#if (defined BLOCKENTITIES || defined ENTITIES || defined HAND) && !defined TRANSLUCENT_ENTITIES && defined TRANSLUCENT_ENTITIES_DITHER_FALLBACK
		if(data_in.blockID != 1612) {
			float entityAlbedo = clamp((Albedo.a*Color.a - 0.1) * 10.0 / 9.0, 0.0, 1.0);

			#ifdef TAA
				if(entityAlbedo < BN) discard;
			#else
				if(entityAlbedo < R2) discard;
			#endif
		}
	#endif

	float torchlightmap = lmcoord.x;

	#if defined Hand_Held_lights && !defined LPV_ENABLED
		#ifdef IS_IRIS
			vec3 playerCamPos = cameraPosition - relativeEyePosition;
		#else
			vec3 playerCamPos = cameraPosition;
		#endif

		#ifdef VIVECRAFT
        	if (vivecraftIsVR) { 
				playerCamPos = cameraPosition - vivecraftRelativeMainHandPos;
			}
		#endif

		// if(HELD_ITEM_BRIGHTNESS > 0.0) torchlightmap = max(torchlightmap, HELD_ITEM_BRIGHTNESS * clamp( pow(max(1.0-length(worldpos-playerCamPos)/HANDHELD_LIGHT_RANGE,0.0),1.5),0.0,1.0));
		if(heldItemId > 999 || heldItemId2 > 999){ 
			float pointLight = clamp(1.0-(length(worldpos-playerCamPos)-1.)/HANDHELD_LIGHT_RANGE,0.0,1.0);

			if (torchlightmap < 0.99) { 
				torchlightmap = mix(torchlightmap, 0.9, pointLight);
			}
		}

		#ifdef HAND
			torchlightmap *= 0.9;
		#endif
	#endif
	
	#if defined WORLD && !defined ENTITIES && !defined HAND && defined BLOCKENTITIES && !defined COLORWHEEL && !defined CUTOUT
		bool PORTAL = data_in.blockID == BLOCK_END_PORTAL || data_in.blockID == BLOCK_END_GATEWAY;

		float endPortalEmission = 0.0;
		if(PORTAL) {
			#if MC_VERSION < 260100 && defined SHADER_END_PORTAL
				const float steps = 20.0;

				vec3 color = vec3(0.0);
				float absorbance = 1.0;

				vec3 worldSpaceNormal = flatNormals;

				vec3 viewVec = normalize(tbnMatrix*fragpos);
				vec3 correctedViewVec = viewVec;
				
				correctedViewVec.xy = mix(correctedViewVec.xy, vec2( viewVec.y,-viewVec.x), clamp( worldSpaceNormal.y,0,1));
				correctedViewVec.xy = mix(correctedViewVec.xy, vec2(-viewVec.y, viewVec.x), clamp(-worldSpaceNormal.x,0,1)); 
				correctedViewVec.xy = mix(correctedViewVec.xy, vec2(-viewVec.y, viewVec.x), clamp(-worldSpaceNormal.z,0,1));
				
				correctedViewVec.z = mix(correctedViewVec.z, -correctedViewVec.z, clamp(length(vec3(worldSpaceNormal.xz, clamp(-worldSpaceNormal.y,0,1))),0,1)); 
				
				vec2 correctedWorldPos = playerpos.xz + cameraPosition.xz;
				correctedWorldPos = mix(correctedWorldPos,	vec2(-playerpos.x,playerpos.z)	+	vec2(-cameraPosition.x,cameraPosition.z),	clamp(-worldSpaceNormal.y,0,1));
				correctedWorldPos = mix(correctedWorldPos,	vec2( playerpos.z,playerpos.y)	+	vec2( cameraPosition.z,cameraPosition.y),	clamp( worldSpaceNormal.x,0,1));
				correctedWorldPos = mix(correctedWorldPos,	vec2(-playerpos.z,playerpos.y)	+	vec2(-cameraPosition.z,cameraPosition.y),	clamp(-worldSpaceNormal.x,0,1));
				correctedWorldPos = mix(correctedWorldPos,	vec2( playerpos.x,playerpos.y)	+	vec2( cameraPosition.x,cameraPosition.y),	clamp(-worldSpaceNormal.z,0,1));
				correctedWorldPos = mix(correctedWorldPos,	vec2(-playerpos.x,playerpos.y)	+	vec2(-cameraPosition.x,cameraPosition.y),	clamp( worldSpaceNormal.z,0,1));


				vec2 rayDir = ((correctedViewVec.xy) / -correctedViewVec.z) / steps * 5.0 ;
			
				vec2 uv = correctedWorldPos + rayDir * BN;
				uv += rayDir * 10.0;

				vec2 animation = vec2(frameTimeCounter, -frameTimeCounter)*0.01;
				
				for (int i = 0; i < int(steps); i++) {
					
					float verticalGradient = (i + BN)/steps ;
					float verticalGradient2 = exp(-7*(1-verticalGradient*verticalGradient));
				
					float density = max(max(verticalGradient - texture(noisetex, uv/256.0 + animation.xy).b*0.5,0.0) - (1.0-texture(noisetex, uv/32.0 + animation.xx).r) * (0.4 + 0.1 * (texture(noisetex, uv/10.0 - animation.yy).b)),0.0);
				
					float volumeCoeff = exp(-density*(i+1));
					
					vec3 lighting =  vec3(0.5,0.75,1.0) * 0.1 * exp(-10*density) + vec3(0.8,0.3,1.0) * verticalGradient2 * 1.7;
					color += (lighting - lighting * volumeCoeff) * absorbance;;

					absorbance *= volumeCoeff;
					endPortalEmission += verticalGradient*verticalGradient ;
					uv += rayDir;
				}

				Albedo.rgb = clamp(color,0,1);
				endPortalEmission = clamp(endPortalEmission/steps * 1.0,0.0,254.0/255.0);

			#else
				int PORTAL_STEPS = 16;
				if(data_in.blockID == BLOCK_END_PORTAL) PORTAL_STEPS = 15;

				Albedo.rgb = textureProj(gtexture, data_in.lmtexcoord).rgb * COLORS[0];
				for (int i = 0; i < PORTAL_STEPS; i++) {
					Albedo.rgb += textureProj(gtexture, data_in.lmtexcoord * end_portal_layer(float(i + 1))).rgb * COLORS[i];
				}
				Albedo.rgb *= 0.3;
				torchlightmap = 0.0;
				lmcoord.y = 0.0;
				endPortalEmission = 0.9;
			#endif
		}
	#endif
	
	#ifdef WhiteWorld
		Albedo.rgb = vec3(0.5);
	#endif

		
	#ifdef AEROCHROME_MODE
		float gray = dot(Albedo.rgb, vec3(0.2, 1.0, 0.07));
		if (
			data_in.blockID == BLOCK_AMETHYST_BUD_MEDIUM || data_in.blockID == BLOCK_AMETHYST_BUD_LARGE || data_in.blockID == BLOCK_AMETHYST_CLUSTER 
			|| data_in.blockID == BLOCK_SSS_STRONG || data_in.blockID == BLOCK_SSS_STRONG3 || data_in.blockID == BLOCK_SSS_WEAK || data_in.blockID == BLOCK_CACTUS
			|| data_in.blockID == BLOCK_CELESTIUM || data_in.blockID == BLOCK_SNOW_LAYERS
			|| data_in.blockID >= 10 && data_in.blockID < 80
		) {
			// IR Reflective (Pink-red)
			Albedo.rgb = mix(vec3(gray), aerochrome_color, 0.7);
		}
		else if(data_in.blockID == BLOCK_GRASS) {
		// Special handling for grass block
			float strength = 1.0 - Color.b;
			Albedo.rgb = mix(Albedo.rgb, aerochrome_color, strength);
		}
		#ifdef AEROCHROME_WOOL_ENABLED
			else if (data_in.blockID == BLOCK_SSS_WEAK_2 || data_in.blockID == BLOCK_CARPET) {
			// Wool
				Albedo.rgb = mix(Albedo.rgb, aerochrome_color, 0.3);
			}
		#endif
		else if(data_in.blockID == BLOCK_WATER || (data_in.blockID >= 300 && data_in.blockID < 400))
		{
		// IR Absorbsive? Dark.
			Albedo.rgb = mix(Albedo.rgb, vec3(0.01, 0.08, 0.15), 0.5);
		}
	#endif

	#ifdef WORLD
		Albedo.a = opaqueMasks;

		#if defined POM_OFFSET_SHADOW_BIAS && defined POM && (!defined ENTITIES && !defined HAND || defined COLORWHEEL)
			if(saveDepth > 0) Albedo.a = clamp(sqrt(saveDepth)*0.44, 0.0, 0.44);
		#endif
	#endif

	#if defined ENTITIES || defined BLOCKENTITIES || defined HAND
		OutTranslucents = vec4(0.0);

		#ifdef VOXY
			OutTranslucents2 = vec4(0.0);
		#endif
	#endif

	// #ifdef COLORWHEEL
	// 	Albedo.a = 0.4;
	// #endif

	
	//////////////////////////////// 				////////////////////////////////
	////////////////////////////////	NORMAL		////////////////////////////////
	//////////////////////////////// 				//////////////////////////////// 

	#if defined WORLD && defined MC_NORMAL_MAP
		#if !defined BLOCKENTITIES && !defined ENTITIES && !defined HAND && defined SHADER_GRASS && !defined COLORWHEEL && defined WORLD && !defined CUTOUT
		if(!ShaderGrass)
		#endif
		{
			vec4 NormalTex = texture_POMSwitch(normals, adjustedTexCoord.xy, vec4(dcdx,dcdy), ifPOM,textureLOD).xyzw;
			
			#if defined MATERIAL_AO && defined MC_TEXTURE_FORMAT_LAB_PBR
				Albedo.rgb *= NormalTex.b*0.5+0.5;
			#endif

			// float Heightmap = 1.0 - NormalTex.w;

			NormalTex.xy = NormalTex.xy * 2.0-1.0;
			NormalTex.z = sqrt(max(1.0 - dot(NormalTex.xy, NormalTex.xy), 0.0));

			normal = applyBump(tbnMatrix, NormalTex.xyz);
		}
	#endif
	
	//////////////////////////////// 				////////////////////////////////
	////////////////////////////////	SPECULAR	////////////////////////////////
	//////////////////////////////// 				//////////////////////////////// 
	
	#ifdef WORLD
		normal = viewToWorld(normal);

		float SSSAMOUNT = 0.0;
		#if (SSS_TYPE == 1 || SSS_TYPE == 2) && !defined HAND
			#ifdef ENTITIES
				#ifdef MOB_SSS
					/////// ----- SSS ON MOBS----- ///////
					// strong
					if(data_in.blockID == ENTITY_SSS_MEDIUM) SSSAMOUNT = 0.75;
			
					// medium
			
					// low
					else if(data_in.blockID == ENTITY_SSS_WEAK || data_in.blockID == ENTITY_PLAYER || data_in.blockID == ENTITY_CURRENT_PLAYER) SSSAMOUNT = 0.4;
				#endif
			#else
				#if defined SHADER_GRASS && !defined CUTOUT
					if (ShaderGrass) SSSAMOUNT = 0.65;
					else
				#endif

				/////// ----- SSS ON BLOCKS ----- ///////
				// strong
				if (
					data_in.blockID == BLOCK_SSS_STRONG || data_in.blockID == BLOCK_SSS_STRONG3 || data_in.blockID == BLOCK_AIR_WAVING || data_in.blockID == BLOCK_SSS_STRONG_2
				) {
					SSSAMOUNT = 1.0;
				}
				// medium
				else if (
					data_in.blockID == BLOCK_GROUND_WAVING || data_in.blockID == BLOCK_GROUND_WAVING_VERTICAL ||
					data_in.blockID == BLOCK_GRASS_SHORT || data_in.blockID == BLOCK_GRASS_TALL_UPPER || data_in.blockID == BLOCK_GRASS_TALL_LOWER ||
					data_in.blockID == BLOCK_SSS_WEAK || data_in.blockID == BLOCK_CACTUS || data_in.blockID == BLOCK_SSS_WEAK_2 ||
					data_in.blockID == BLOCK_CELESTIUM || (data_in.blockID >= 269 && data_in.blockID <= 274) || data_in.blockID == BLOCK_SNOW_LAYERS || data_in.blockID == BLOCK_CARPET ||
					data_in.blockID == BLOCK_AMETHYST_BUD_MEDIUM || data_in.blockID == BLOCK_AMETHYST_BUD_LARGE || data_in.blockID == BLOCK_AMETHYST_CLUSTER ||
					data_in.blockID == BLOCK_BAMBOO || data_in.blockID == BLOCK_SAPLING || data_in.blockID == BLOCK_VINE || data_in.blockID == BLOCK_VINE_OTHER
					#ifdef MISC_BLOCK_SSS
					|| data_in.blockID == BLOCK_SSS_WEIRD || data_in.blockID == BLOCK_GRASS
					#endif
				) {
					SSSAMOUNT = 0.5;
				} else if(data_in.blockID == GRASS_BLOCK_SNOWY) {
					SSSAMOUNT = 0.5 * smoothstep(0.0, 1.0, fract(worldpos.y));
				}
				#if defined CUTOUT
					else if (data_in.blockID == -BLOCK_GRASS) {
						SSSAMOUNT = 0.3;
					}
				#endif
			#endif

			#ifdef BLOCKENTITIES
				/////// ----- SSS ON BLOCK ENTITIES----- ///////
				// strong

				// medium
				if(data_in.blockID == BLOCK_SSS_WEAK_3) SSSAMOUNT = 0.4;

				// low

			#endif
		#endif

		#if EMISSIVE_TRIMS > 0
			bool isBrightTrim = currentRenderedItemId == 1026;
			bool isTrim = isBrightTrim || currentRenderedItemId == 1027;
		#endif

		#if EMISSIVE_TYPE == 1 || EMISSIVE_TYPE == 2
			/////// ----- EMISSIVE STUFF ----- ///////
			float EMISSIVE = 0.0;

			// if(vNameTags > 0) EMISSIVE = 0.9;

			// normal block lightsources
			if(data_in.blockID >= 100 && data_in.blockID < 282) {
				EMISSIVE = 0.5;

				if(data_in.blockID == 266 || (data_in.blockID >= 276 && data_in.blockID <= 281)) EMISSIVE = 0.2; // sculk stuff

				else if(data_in.blockID == 195) EMISSIVE = 2.3; // glow lichen

				else if(data_in.blockID == 185) EMISSIVE = 1.5; // crying obsidian

				else if(data_in.blockID == 105) EMISSIVE = 2.0; // brewing stand
				
				else if(data_in.blockID == 236) EMISSIVE = 1.0; // respawn anchor

				else if(data_in.blockID == 101) EMISSIVE = 0.7; // large amethyst bud

				else if(data_in.blockID == 103) EMISSIVE = 1.0; // amethyst cluster

				else if(data_in.blockID == 244) EMISSIVE = 1.5; // soul fire
			}

			#if EMISSIVE_ORES > 0
				if(data_in.blockID == 502) {
					EMISSIVE = EMISSIVE_ORES_STRENGTH;

					#ifndef HARDCODED_EMISSIVES_APPROX
						EMISSIVE *= getEmission(Albedo.rgb);
					#endif
				}
			#endif

			#if EMISSIVE_TRIMS > 0
				if(isTrim) EMISSIVE = EMISSIVE_TRIMS_STRENGTH*getTrimEmission(Albedo.rgb);

				if(isBrightTrim) EMISSIVE *= 0.4;
			#endif
		#endif


		vec4 SpecularTex = vec4(0.0);
		#if !defined BLOCKENTITIES && !defined ENTITIES && !defined HAND && defined SHADER_GRASS && !defined COLORWHEEL && defined WORLD && !defined CUTOUT
		if (ShaderGrass) {
			SpecularTex = vec4(0.15, 0.025, 1.0, 0.0);
		} else
		#endif
		{
			SpecularTex = texture_POMSwitch(specular, adjustedTexCoord.xy, vec4(dcdx,dcdy), ifPOM,textureLOD);
		}

		// SpecularTex.r = max(SpecularTex.r, rainfall);
		// SpecularTex.g = max(SpecularTex.g, max(Puddle_shape*0.02,0.02));

		OutSpecular = vec4(0.0,0.0,0.0,0.0);
		OutSpecular.rg = SpecularTex.rg;

		#if EMISSIVE_ORES > 1 && EMISSIVE_TYPE > 1
			if(data_in.blockID == 502) {
				SpecularTex.a = EMISSIVE_ORES_STRENGTH;
				
				SpecularTex.a *= getEmission(Albedo.rgb);
			}
		#endif

		#if EMISSIVE_TRIMS > 1 && EMISSIVE_TYPE > 1
			if(isTrim) SpecularTex.a = EMISSIVE_TRIMS_STRENGTH*getTrimEmission(Albedo.rgb);

			if(isBrightTrim) SpecularTex.a *= 0.4;
		#endif

		#if EMISSIVE_TYPE == 2
		bool emissionCheck = SpecularTex.a <= 0.0;
		#endif

		#ifdef MIRROR_IRON
		if(data_in.blockID == 504 || currentRenderedItemId == 504) {
			OutSpecular.rg = vec2(1.0, 1.0);
			Albedo.rgb = vec3(1.0);
			// normal = flatNormals;
		}
		#endif

		#if defined HARDCODED_EMISSIVES_APPROX && (EMISSIVE_TYPE == 1 || EMISSIVE_TYPE == 2)
			#if EMISSIVE_TYPE == 2 && EMISSIVE_TRIMS > 0
			if(emissionCheck && !isTrim)
			#elif EMISSIVE_TRIMS > 0
			if(!isTrim)
			#elif EMISSIVE_TYPE == 2
			if(emissionCheck)
			#endif
			{
			EMISSIVE *= getEmission(Albedo.rgb);
			}
		#endif

		#if EMISSIVE_TYPE == 0
			OutSpecular.a = 0.0;
		#endif

		#if EMISSIVE_TYPE == 1
			EMISSIVE = clamp(EMISSIVE, 0.0, 0.99);
			OutSpecular.a = EMISSIVE;
		#endif

		#if EMISSIVE_TYPE == 2
			OutSpecular.a = SpecularTex.a;
			EMISSIVE = clamp(EMISSIVE, 0.0, 0.99);
			if(emissionCheck) OutSpecular.a = EMISSIVE;
		#endif

		#if EMISSIVE_TYPE == 3		
			OutSpecular.a = SpecularTex.a;
		#endif
		
		#if defined WORLD && !defined ENTITIES && !defined HAND && defined BLOCKENTITIES && !defined COLORWHEEL
			if(PORTAL) OutSpecular.a = endPortalEmission;
		#endif

		#if SSS_TYPE == 0
			OutSpecular.b = 0.0;
		#endif

		#if SSS_TYPE == 1
			OutSpecular.b = SSSAMOUNT;
		#endif

		#if SSS_TYPE == 2
			OutSpecular.b = SpecularTex.b;
			if(SpecularTex.b < 65.0/255.0) OutSpecular.b = SSSAMOUNT;
		#endif

		#if SSS_TYPE == 3		
			OutSpecular.b = SpecularTex.b;
		#endif

		#if SSS_TYPE != 0
			if(data_in.blockID == 829925) OutSpecular.b = 1.0;
		#endif
	#endif

	// hit glow effect...
	#if defined ENTITIES && !defined COLORWHEEL
		Albedo.rgb = mix(Albedo.rgb, entityColor.rgb, pow(entityColor.a, 0.8));
	#endif

	#ifdef COLORWHEEL
		Albedo.rgb = mix(Albedo.rgb, overlayColor.rgb, overlayColor.a);
	#endif

	//////////////////////////////// 				////////////////////////////////
	////////////////////////////////	FINALIZE	////////////////////////////////
	//////////////////////////////// 				////////////////////////////////

	#ifdef WORLD
		// apply noise to lightmaps to reduce banding.
		vec2 PackLightmaps = vec2(torchlightmap, lmcoord.y);

		// special curve to give more precision on high/low values of the gradient. this curve will be inverted after sampling and decoding.
		// PackLightmaps = pow(1.0-pow(1.0-PackLightmaps,vec2(0.5)),vec2(0.5));
		
		#if defined WORLD && !defined HAND && !defined ENTITIES
			// some dither to lightmaps to reduce banding.
			PackLightmaps = clamp( PackLightmaps + PackLightmaps * (BN-0.5)*0.005,0,1);
		#endif

		#if !defined BLOCKENTITIES && !defined ENTITIES && !defined HAND && defined SHADER_GRASS && !defined COLORWHEEL && defined WORLD && !defined CUTOUT
			if (ShaderGrass) {flatNormals = data_in.normalMat; normal = data_in.texcoordam.xyz;}
		#endif

		vec4 data1 = clamp(vec4(encodeNormal(normal), PackLightmaps), 0.0, 1.0);

		#ifdef VISUALIZE_LIGHTMAP
			beginText(ivec2(gl_FragCoord.xy/vec2(8.0, 8.0)), ivec2(0.45*viewWidth/8.0, 0.5*viewHeight/8.0));
			text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
			printVec2(data_in.lmtexcoord.zw);
			endText(Albedo.rgb);
		#endif

		Albedo = clamp(Albedo, 0.0, 1.0);

		OutAlbedo = vec4(encodeVec2(Albedo.x,data1.x),	encodeVec2(Albedo.y,data1.y),	encodeVec2(Albedo.z,data1.z),	encodeVec2(data1.w,Albedo.w));

		vec4 otherData = clamp(vec4(flatNormals * 0.5 + 0.5, vanillaAO), 0.0, 1.0);
		OutSpecular = clamp(OutSpecular, 0.0, 1.0);

		OutSpecular = vec4(
			encodeVec2(OutSpecular.x, otherData.x),
			encodeVec2(OutSpecular.y, otherData.y),
			encodeVec2(OutSpecular.z, otherData.z),
			encodeVec2(OutSpecular.w, otherData.w)
		);

	#endif
	
}