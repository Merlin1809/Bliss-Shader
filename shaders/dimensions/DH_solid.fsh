#include "/lib/settings.glsl"

in DATA {
    vec4 localPos;
    vec4 vPos;
    vec4 gcolor;
    vec2 lightmapCoords;
    vec4 normalMat;
    flat float SSSAMOUNT;
    flat float EMISSIVE;
    flat int dh_material_id;
};

#ifdef VISUALIZE_LIGHTMAP
    uniform float viewWidth;
    uniform float viewHeight;
    #include "/lib/text_rendering.glsl"
#endif

uniform float far;
uniform float nightVision;
// uniform int hideGUI;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

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

// uniform sampler2D depthtex0;
// uniform vec2 texelSize;


#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;

vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 feetPlayerPos = p * 2. - 1.;
    vec4 viewPos = iProjDiag * feetPlayerPos.xyzz + gbufferProjectionInverse[3];
    return viewPos.xyz / viewPos.w;
}

uniform sampler2D noisetex;
uniform int frameCounter;
uniform float frameTimeCounter;
float blueNoise(){
  return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
}
float interleaved_gradientNoise_temporal(){
	return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y)+frameTimeCounter*51.9521);
}
float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}
float R2_dither(){
	vec2 coord = gl_FragCoord.xy + (frameCounter%40000) * 2.0;
    
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * coord.x + alpha.y * coord.y ) ;
}

//3D noise from 2d texture
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

// https://gitlab.com/jeseibel/distant-horizons-core/-/blob/main/core/src/main/resources/shaders/flat_shaded.frag?ref_type=heads
// Property of Distant Horizons [mod]

// --- NOISE SETTINGS ---
// const int noiseSteps = NOISE_RESOLUTION;
const float noiseIntensity = NOISE_INTENSITY;
// ----------------------

float rand(float co) { return fract(sin(co*(91.3458)) * 47453.5453); }
float rand(vec2 co) { return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453); }
float rand(vec3 co) { return rand(co.xy + rand(co.z)); }

vec3 quantize(const in vec3 val, const in int stepSize) {
    return floor(val * stepSize) / stepSize;
}

vec4 applyNoise(in vec4 fragColor, const in float viewDist) {
    vec3 vertexNormal = normalize(cross(dFdy(vPos.xyz), dFdx(vPos.xyz)));
    // // This bit of code is required to fix the vertex position problem cus of floats in the verted world position varuable
    vec3 fixedVPos = vPos.xyz + vertexNormal * 0.001;

    float noiseAmplification = noiseIntensity * 0.01;
    float lum = (fragColor.r + fragColor.g + fragColor.b) / 3.0;
    noiseAmplification = (1.0 - pow(lum * 2.0 - 1.0, 2.0)) * noiseAmplification; // Lessen the effect on depending on how dark the object is, equasion for this is -(2x-1)^{2}+1
    noiseAmplification *= fragColor.a; // The effect would lessen on transparent objects
    
    // Mikis idea. make it such that you can control the step amount as distance increases out from where vanilla chunks end.
    // ideally, close = higher steps and far = lower steps
    float highestSteps = NOISE_RESOLUTION + blueNoise();
    float lowestSteps = 2.0;
    float transitionLength = 16.0 * 16.0; // distance it takes to reach the lowest steps from the highest. measured in meters/blocks.
    
    float transitionGradient = clamp((viewDist - (far+32.0)) / transitionLength,0.0,1.0);
    transitionGradient = sqrt(transitionGradient);// make the gradient appear smoother and less sudden when approaching low steps.

    int dynamicNoiseSteps = int(mix(highestSteps, lowestSteps, transitionGradient));

    // Random value for each position
    float randomValue = rand(quantize(fixedVPos+cameraPosition, dynamicNoiseSteps))
    * 2.0 * noiseAmplification - noiseAmplification;

    // Modifies the color
    // A value of 0 on the randomValue will result in the original color, while a value of 1 will result in a fully bright color
    vec3 newCol = fragColor.rgb + (1.0 - fragColor.rgb) * randomValue;
    newCol = clamp(newCol, 0.0, 1.0);

    #if NOISE_DROPOFF != 0
        float distF = min(viewDist / NOISE_DROPOFF, 1.0);
        newCol = mix(newCol, fragColor.rgb, distF); // The further away it gets, the less noise gets applied
    #endif

    return vec4(newCol,1.0);
}

/* RENDERTARGETS:1,7,8 */
void main() {

    #if defined DH_OVERDRAW_PREVENTION || defined DH_NOISE_TEXTURE || DH_CHUNK_FADING > 0
        float viewDist = length(localPos.xyz); 
    #endif

    #if DH_CHUNK_FADING > 0
        float ditherFade = smoothstep(0.86 * far, 0.9 * far, viewDist);

        if (step(R2_dither()/ditherFade, ditherFade) == 0.0) discard;
    #endif
    
    #ifdef DH_OVERDRAW_PREVENTION
    	#if OVERDRAW_MAX_DISTANCE == 0
			float maxOverdrawDistance = far;
		#else
			float maxOverdrawDistance = OVERDRAW_MAX_DISTANCE;
		#endif

        if(clamp(1.0-viewDist/clamp(far - 32.0,32.0,maxOverdrawDistance),0.0,1.0) > 0.0 ){
            discard;
            return;
        }
    #endif

    vec3 normals = (normalMat.xyz);
    float materials = normalMat.a;
	vec2 PackLightmaps = lightmapCoords;

    // PackLightmaps.y *= 1.05;
    PackLightmaps = min(max(PackLightmaps,0.0)*1.05,1.0);

    normals = viewToWorld(normals);
    
    vec4 data1 = clamp( encode(normals, PackLightmaps), 0.0, 1.0);
    
    // alpha is material masks, set it to 0.65 to make a DH LODs mask. 
	#if defined DH_NOISE_TEXTURE && !defined DISTANT_HORIZONS_TEXTURES
		vec4 Albedo = applyNoise(gcolor, viewDist);
	#else
		vec4 Albedo = vec4(gcolor.rgb, 1.0);
	#endif

    #ifdef DISTANT_HORIZONS_TEXTURES
    if (dh_hasTexture()) {
        vec4 that = dh_sampleTexture();
        vec3 clampedColor = clamp(Albedo.rgb * (that.rgb * 2.0), 0.0, 1.0);
        Albedo.rgb = mix(Albedo.rgb, clampedColor, that.a);
    }
   #endif
    // vec3 worldPos = mat3(gbufferModelViewInverse)*pos.xyz + cameraPosition;
    // worldPos = (worldPos*vec3(1.0,1./48.,1.0)/4) ;
    // worldPos = floor(worldPos * 4.0 + 0.001) / 32.0;
    // float noiseTexture = densityAtPos(worldPos* 5000 ) +0.5;

    // float noiseFactor = max(1.0 - 0.3 * dot(Albedo.rgb, Albedo.rgb),0.0);
    // Albedo.rgb *= pow(noiseTexture, 0.6 * noiseFactor);
    // Albedo.rgb *= (noiseTexture*noiseTexture)*0.5 + 0.5;

	#ifdef AEROCHROME_MODE
		if(dh_material_id == DH_BLOCK_LEAVES || dh_material_id == DH_BLOCK_WATER) { // leaves and waterlogged blocks
			float grey = dot(Albedo.rgb, vec3(0.2, 01.0, 0.07));
			Albedo.rgb = mix(vec3(grey), aerochrome_color, 0.7);
			
		} else if(dh_material_id == DH_BLOCK_GRASS) { // grass
			Albedo.rgb = mix(Albedo.rgb, aerochrome_color, 1.0 - Albedo.g);
		}
	#endif

    #ifdef WhiteWorld
        Albedo.rgb = vec3(0.5);
    #endif

    #ifdef VISUALIZE_LIGHTMAP
        beginText(ivec2(gl_FragCoord.xy/vec2(8.0, 8.0)), ivec2(0.45*viewWidth/8.0, 0.7*viewHeight/8.0));
        text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
        printVec2(lightmapCoords);
        endText(Albedo.rgb);
    #endif

    Albedo = clamp(Albedo, 0.0, 1.0);
    
    gl_FragData[0] = vec4(encodeVec2(Albedo.x,data1.x),	encodeVec2(Albedo.y,data1.y),	encodeVec2(Albedo.z,data1.z),	encodeVec2(data1.w, materials));
    
	gl_FragData[1].a = 0.0;

    gl_FragData[2] = vec4(0.0,0.0,0.0,0.0);
    
	#if EMISSIVE_TYPE == 0
		gl_FragData[2].a = 0.0;
	#else
		gl_FragData[2].a = EMISSIVE;
	#endif

	#if SSS_TYPE == 0
		gl_FragData[2].b = 0.0;
	#else
		gl_FragData[2].b = SSSAMOUNT;
	#endif

    vec4 otherData = clamp(vec4(normals * 0.5 + 0.5, 0.0), 0.0, 1.0);
    gl_FragData[2] = clamp(gl_FragData[2], 0.0, 1.0);

    gl_FragData[2] = vec4(
        encodeVec2(gl_FragData[2].x, otherData.x),
        encodeVec2(gl_FragData[2].y, otherData.y),
        encodeVec2(gl_FragData[2].z, otherData.z),
        encodeVec2(gl_FragData[2].w, otherData.w)
    );
}