float invLinZ (float lindepth){
	return -((2.0*near/lindepth)-far-near)/(far-near);
}

float DH_invLinZ (float lindepth){
	return -((2.0*dhVoxyNearPlane/lindepth)-dhVoxyFarPlane-dhVoxyNearPlane)/(dhVoxyFarPlane-dhVoxyNearPlane);
}

float linZ(float depth) {
	return (2.0 * near) / (far + near - depth * (far - near));
}

float linZ2(float depth, float near, float far) {
	return (2.0 * near) / (far + near - depth * (far - near));
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

vec2 R2_Sample(int n){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha * n);
}

float fma2(float a,float b,float c){
 return a * b + c;
}

vec3 SampleVNDFGGX(
    vec3 viewerDirection, // Direction pointing towards the viewer, oriented such that +Z corresponds to the surface normal
    float alpha, // Roughness parameter along X and Y of the distribution
    vec2 xy // Pair of uniformly distributed numbers in [0, 1)
) {

    // Transform viewer direction to the hemisphere configuration
    viewerDirection = normalize(vec3( alpha * 0.5 * viewerDirection.xy, viewerDirection.z));

    // Sample a reflection direction off the hemisphere
    const float tau = 6.2831853; // 2 * pi
    float phi = tau * xy.x;

    float cosTheta = fma2(1.0 - xy.y, 1.0 + viewerDirection.z, -viewerDirection.z);
    float sinTheta = sqrt(clamp(1.0 - cosTheta * cosTheta, 0.0, 1.0));

	sinTheta = clamp(sinTheta,0.0,1.0);
	cosTheta = clamp(cosTheta,sinTheta*0.5,1.0);

	
	vec3 reflected = vec3(vec2(cos(phi), sin(phi)) * sinTheta, cosTheta);

    // Evaluate halfway direction
    // This gives the normal on the hemisphere
    vec3 halfway = reflected + viewerDirection;

    // Transform the halfway direction back to hemiellispoid configuation
    // This gives the final sampled normal
    return normalize(vec3(alpha * halfway.xy, halfway.z));
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

float shlickFresnelRoughness(float XdotN, float roughness){

	float shlickFresnel = clamp(1.0 + XdotN,0.0,1.0);

	float curves = exp(-4.0*pow(1.0-(roughness),2.5));
	float brightness = exp(-3.0*pow(1.0-sqrt(roughness),3.50));

	shlickFresnel = pow(1.0-pow(1.0-shlickFresnel, mix(1.0, 1.9, curves)),mix(5.0, 2.6, curves));
	shlickFresnel = mix(0.0, mix(1.0,0.065,  brightness) , clamp(shlickFresnel,0.0,1.0));
	
	return shlickFresnel;
}

float invertLinearizeDepthFast(const in float z) {
	return (far * (z - near)) / (z * (far - near));
}


vec3 rayTraceSpeculars(vec3 dir, vec3 position, float dither, float quality, const bool hand, inout float reflectionLength, inout bool depthCheck){

	const float biasAmount = 0.0001;

	float _near = near; float _far = far;

	vec3 clipPosition = toClipSpace3_DH(position, false);
	float rayLength = ((position.z + dir.z * _far*sqrt(3.)) > -_near) ? (-_near -position.z) / dir.z : _far*sqrt(3.);

	vec3 direction = toClipSpace3_DH(position + dir*rayLength, false) - clipPosition;  //convert to clip space
	vec3 reflectedTC = vec3((direction.xy + clipPosition.xy) * RENDER_SCALE, 0.999999);

	#if FORWARD_SSR_QUALITY == 1
		return reflectedTC;
	#endif

	//get at which length the ray intersects with the edge of the screen
	vec3 maxLengths = (step(0.0, direction) - clipPosition) / direction;
	float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z);
	vec3 stepv = direction * mult / quality;

	clipPosition.xy *= RENDER_SCALE;
	stepv.xy *= RENDER_SCALE;

	vec3 spos = clipPosition + stepv*(dither*0.5+0.5);
	spos += vec3(0.5*texelSize,0.0); // small offsets to reduce artifacts from precision differences.
	
	#if defined DEFERRED_SPECULAR && defined TAA
		spos.xy += TAA_Offset*texelSize*0.5/RENDER_SCALE;
	#endif

	float minZ = spos.z - 0.00025 / linZ2(spos.z, _near, _far);
	float maxZ = spos.z;

	#if (defined VOXY && defined VOXY_REFLECTIONS) || (defined DISTANT_HORIZONS && defined DH_SCREENSPACE_REFLECTIONS)

		const float biasAmount2 = 0.00005;


		_near = dhVoxyNearPlane;
		_far = dhVoxyFarPlane;


		vec3 clipPosition2 = toClipSpace3_DH(position, true);
		float rayLength2 = ((position.z + dir.z * _far*sqrt(3.)) > -_near) ? (-_near -position.z) / dir.z : _far*sqrt(3.);

		vec3 direction2 = toClipSpace3_DH(position + dir*rayLength2, true) - clipPosition2;  //convert to clip space

		//get at which length the ray intersects with the edge of the screen
		vec3 maxLengths2 = (step(0.0, direction2) - clipPosition2) / direction2;
		float mult2 = min(min(maxLengths2.x, maxLengths2.y), maxLengths2.z);
		vec3 stepv2 = direction2 * mult2 / quality;

		clipPosition2.xy *= RENDER_SCALE;
		stepv2.xy *= RENDER_SCALE;

		vec3 spos2 = clipPosition2 + stepv2*(dither*0.5+0.5);
		spos2 += vec3(0.5*texelSize,0.0); // small offsets to reduce artifacts from precision differences.
		
		#if defined DEFERRED_SPECULAR && defined TAA
			spos2.xy += TAA_Offset*texelSize*0.5/RENDER_SCALE;
		#endif

		float minZ2 = spos2.z - 0.00025 / linZ2(spos2.z, _near, _far);
		float maxZ2 = spos2.z;
	#endif

	vec3 hitPos = vec3(1.1);
	
  	for (int i = 0; i <= int(quality); i++) {
		#if DEFERRED_SSR_QUALITY != 1
			#if (defined VOXY && defined VOXY_REFLECTIONS) || (defined DISTANT_HORIZONS && defined DH_SCREENSPACE_REFLECTIONS)
			if(!hand && (spos.x < 0 || spos.x > 1 || spos.y < 0 || spos.y > 1) && (spos2.x < 0 || spos2.x > 1 || spos2.y < 0 || spos2.y > 1)) return vec3(1.1);
			#else
			if(!hand && (spos.x < 0 || spos.x > 1 || spos.y < 0 || spos.y > 1)) return vec3(1.1);
			#endif
		#endif

		#ifdef QUARTER_RES_SSR
			float sampleDepth = texelFetch(colortex4, ivec2(spos.xy/texelSize/4.0),0).a/65000.0;
			float sp = invLinZ(sqrt(sampleDepth));
		#else
			#ifdef FULLRESDEPTH
				float sp = texelFetch(depthtex0, ivec2(spos.xy/texelSize),0).r;
			#else
				float sp = texelFetch(depthtex1, ivec2(spos.xy/texelSize),0).r;
			#endif
		#endif
		
		#if (defined VOXY && defined VOXY_REFLECTIONS) || (defined DISTANT_HORIZONS && defined DH_SCREENSPACE_REFLECTIONS)
		if (sp > 0.9999999){

			#ifdef FULLRESDEPTH
				sp = texelFetch(dhVoxyDepthTex, ivec2(spos2.xy/texelSize),0).r;
			#else
				sp = texelFetch(dhVoxyDepthTex1, ivec2(spos2.xy/texelSize),0).r;
			#endif

			if(sp < max(minZ2, maxZ2) && sp > min(minZ2, maxZ2)) {
				hitPos = vec3(spos2.xy/RENDER_SCALE, sp);
				depthCheck = true;
				break;
			}
		} else
		#endif
		{
			if(sp < max(minZ, maxZ) && sp > min(minZ, maxZ)) {
				hitPos = vec3(spos.xy/RENDER_SCALE, sp);
				break;
			}
		}

		minZ = maxZ - biasAmount / linZ2(spos.z, near, far);
		maxZ += stepv.z;

		spos += stepv;

		#if (defined VOXY && defined VOXY_REFLECTIONS) || (defined DISTANT_HORIZONS && defined DH_SCREENSPACE_REFLECTIONS)
		minZ2 = maxZ2 - biasAmount2 / linZ2(spos2.z, dhVoxyNearPlane, dhVoxyFarPlane);
		maxZ2 += stepv2.z;

		spos2 += stepv2;
		#endif

		reflectionLength += 1.0 / quality;
  	}

	#if DEFERRED_SSR_QUALITY == 1
		return reflectedTC;
	#endif

	if(hand) return reflectedTC;
	return hitPos;
}

vec3 toScreenSpace2(vec3 p, bool depthCheck) {
	#if (defined VOXY && defined VOXY_REFLECTIONS) || (defined DISTANT_HORIZONS && defined DH_SCREENSPACE_REFLECTIONS)
		mat4 matrix = gbufferProjectionInverse;
		if(depthCheck) matrix = dhVoxyProjectionInverse;
	#else
		mat4 matrix = gbufferProjectionInverse;
	#endif
	vec4 iProjDiag = vec4(matrix[0].x, matrix[1].y, matrix[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + matrix[3];
    return fragposition.xyz / fragposition.w;
}

#if defined VOXEL_REFLECTIONS && defined IS_LPV_ENABLED && defined adjnjawudiuwad
uint GetVoxelBlock(const in ivec3 voxelPos) { 
    return imageLoad(imgVoxelMask, voxelPos).r % 2000u;
}

int voxelIndex(ivec3 voxelPos) {
    return voxelPos.x + voxelPos.y * int(VoxelSize) + voxelPos.z * int(VoxelSize*VoxelSize);
}

int voxelNormalIndex(vec3 voxelNormal) {
	return clamp(int(abs(voxelNormal.x)*(voxelNormal.x*0.5+0.5) + abs(voxelNormal.y)*(voxelNormal.y*0.5+2.5) + abs(voxelNormal.z)*(voxelNormal.z*0.5+4.5) + 0.5), 0, 5);
}

vec2 decodeVec2_16(float a){
    const vec2 constant1 = 4294967294. / vec2( 65536., 4294967295.);
    const float constant2 = 65536. / 65535.;
    return fract( a * constant1 ) * constant2 ;
}

void GetVoxelData(const in ivec3 voxelPos, inout vec2 texcoord, inout vec3 tintColor, in vec3 voxelNormal, inout vec2 lightmap) {
	vec4 blockTexture = voxelData[voxelIndex(voxelPos)][voxelNormalIndex(voxelNormal)];
	texcoord = decodeVec2_16(blockTexture.x);
	lightmap = decodeVec2(blockTexture.y);
	lightmap = min(max(lightmap - 0.05,0.0)*1.06,1.0);

	vec2 RGtint = decodeVec2(blockTexture.b);
	tintColor = vec3(RGtint.r, blockTexture.a, RGtint.g);
}

void GetTexCoord(const in ivec3 voxelPos, inout vec2 texcoord, in vec3 voxelNormal) {
	texcoord = decodeVec2_16(voxelData[voxelIndex(voxelPos)][voxelNormalIndex(voxelNormal)].x);
}

float getVoxelEmission(vec3 Albedo) {
	vec3 hsv = RgbToHsv(Albedo);
    float emissive = smoothstep(0.05, 0.15, hsv.y) * pow(hsv.z, 3.5);
    return emissive * 0.5;
}

void voxelEmission(
	inout vec3 Lighting,
	vec3 Albedo,
	float Emission
){
	if( Emission < 254.5/255.0) Lighting = mix(Lighting, Albedo * 5.0 * Emissive_Brightness, pow(Emission, Emissive_Curve));
}

vec2 CleanVoxelSample(
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

float ComputeVoxelShadowMap(inout vec3 directLightColor, vec3 playerPos, float maxDistFade, float noise, in vec3 geoNormals){

	// if(maxDistFade <= 0.0) return 1.0;

	// setup shadow projection
	#ifdef OVERWORLD_SHADER
		#ifdef CUSTOM_MOON_ROTATION
			vec3 projectedShadowPosition = mat3(customShadowMatrixSSBO) * playerPos  + customShadowMatrixSSBO[3].xyz;
		#else
			vec3 projectedShadowPosition = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
		#endif

		applyShadowBias(projectedShadowPosition, playerPos, geoNormals);

		projectedShadowPosition = diagonal3(shadowProjection) * projectedShadowPosition + shadowProjection[3].xyz;

		// un-distort
		#ifdef DISTORT_SHADOWMAP
			float distortFactor = calcDistort(projectedShadowPosition.xy);
			projectedShadowPosition.xy *= distortFactor;
		#else
			float distortFactor = 1.0;
		#endif

		projectedShadowPosition.z += shadowProjection[3].z * 0.0012;
	#else
		float distortFactor = 1.0;
	#endif

	#if defined END_ISLAND_LIGHT && defined END_SHADER
		vec4 shadowPos = customShadowMatrixSSBO * vec4(playerPos, 1.0);
		applyShadowBias(shadowPos.xyz, playerPos, geoNormals);
		shadowPos =  customShadowPerspectiveSSBO * shadowPos;
		vec3 projectedShadowPosition = shadowPos.xyz / shadowPos.w;
	#endif



	// hamburger
	projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5);
	
	float shadowmap = 0.0;
	vec3 translucentTint = vec3(0.0);

	if (projectedShadowPosition.z > 1.0 || projectedShadowPosition.z < 0.0) return 1.0;

	#ifdef BASIC_SHADOW_FILTER
		int samples = int(SHADOW_FILTER_SAMPLE_COUNT * 0.5);
		#ifdef END_SHADER
			float rdMul = 52.0*d0k;
		#else
			float rdMul = 2.4*distortFactor*d0k;
		#endif

		for(int i = 0; i < samples; i++){
			vec2 offsetS = CleanVoxelSample(i, samples - 1, noise) * rdMul;
			projectedShadowPosition.xy += offsetS;
	#else
		int samples = 1;
	#endif
	

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
			shadowmap += texture(shadowtex0HW, projectedShadowPosition.xy).x;
		#endif

	#ifdef BASIC_SHADOW_FILTER
		}
	#endif

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		// tint the lightsource color with the translucent shadow color
		directLightColor *= mix(vec3(1.0), translucentTint.rgb / samples, maxDistFade);
	#endif

	float shadowResult = shadowmap / samples;

	#ifdef END_SHADER
	float r = length(projectedShadowPosition.xy - vec2(0.5));
	if (r < 0.5 && abs(projectedShadowPosition.z) < 1.0) {
		shadowResult *= smoothstep(0.5, 0.25, r);
	} else {
		shadowResult = 0.0;
	}
	#endif

	return shadowResult;
	// return mix(1.0, shadowmap / samples, maxDistFade);
}

bool planeIntersect(inout vec3 currPos, in float worldOffset, inout vec3 voxelPos, in vec3 reflectedVector, inout vec3 stepAxis, in vec3 normal)
{		
	float denom = dot(reflectedVector, normal);
	if (abs(denom) < 1e-6) return false;
	float t = -(dot(currPos, normal) - worldOffset) / denom;
	
	if (t > 0.0 && t < 2.0) {
		vec3 hitPos = currPos + t * reflectedVector;			
		
		if (all(equal(ivec3(voxelPos), ivec3(GetLpvPosition(hitPos))))) {
			currPos = hitPos;
			stepAxis = normal;
			return true;
		}
	}
	return false;
}

bool AABBintersection(inout vec3 currPos, const vec3 reflectedVector, const vec3 stepSizes, const vec3 boxMin, const vec3 boxMax, inout vec3 stepAxis) {
    vec3 t1 = (boxMin - currPos) * stepSizes;
    vec3 t2 = (boxMax - currPos) * stepSizes;
    
    vec3 tmin = min(t1, t2);
    vec3 tmax = max(t1, t2);
    
    float tmin0 = max(max(tmin.x, tmin.y), tmin.z);
    float tmax0 = min(min(tmax.x, tmax.y), tmax.z);
    
    bool hit = tmin0 < tmax0 && tmin0 > 0.0;
    float fHit = float(hit);
    
    vec3 entryDist = abs(tmin - vec3(tmin0));
    vec3 normal = step(entryDist, vec3(0.0));
        
    stepAxis = mix(stepAxis, normal, fHit);
    currPos = mix(currPos, currPos + tmin0 * reflectedVector, fHit);
    
    return hit;
}

struct RayHit {
    bool hit;
    float t;
    vec3 currPos;
    vec3 stepAxis;
};

RayHit AABBintersection2(const vec3 currPos, const vec3 reflectedVector, const vec3 stepSizes, const vec3 boxMin, const vec3 boxMax, const in vec3 stepAxis) {
    vec3 t1 = (boxMin - currPos) * stepSizes;
    vec3 t2 = (boxMax - currPos) * stepSizes;
    
    vec3 tmin = min(t1, t2);
    vec3 tmax = max(t1, t2);
    
    float tmin0 = max(max(tmin.x, tmin.y), tmin.z);
    float tmax0 = min(min(tmax.x, tmax.y), tmax.z);
    
    bool hit = tmin0 < tmax0 && tmin0 > 0.0;
    float fHit = float(hit);
	
    RayHit result;
    result.hit = hit;
    result.t = tmin0;
    
    vec3 entryDist = abs(tmin - vec3(tmin0));
    vec3 normal = step(entryDist, vec3(0.0));
        
    result.stepAxis = mix(stepAxis, normal, fHit);
    result.currPos = mix(currPos, currPos + tmin0 * reflectedVector, fHit);
    
    return result;
}

void sortIntersectionCutout(const in RayHit RayHit1, const in RayHit RayHit2, const in vec3 stepDir, const in vec2 gtexSize, const in vec2 texCoordOffset, const in vec3 voxelPos, inout bool hit, inout vec3 shiftedCurrPos, inout vec3 stepAxis) {
	bool useFirst = (RayHit1.hit && (!RayHit2.hit || RayHit1.t < RayHit2.t));
	RayHit firstHit = useFirst ? RayHit1 : RayHit2;
	RayHit secondHit = useFirst ? RayHit2 : RayHit1;

	vec2 _texcoord;
	vec3 voxelNormal = -firstHit.stepAxis * stepDir;
	GetTexCoord(ivec3(voxelPos), _texcoord, voxelNormal);
	vec3 wPos = firstHit.currPos + cameraPosition;
	vec2 sampleDir = firstHit.stepAxis.x * fract(wPos.zy) + firstHit.stepAxis.y * fract(wPos.xz) + firstHit.stepAxis.z * fract(wPos.xy);
	_texcoord = mix(_texcoord + vec2(0, texCoordOffset.y), _texcoord - vec2(0, texCoordOffset.y), sampleDir);
	_texcoord = mix(_texcoord + vec2(texCoordOffset.x, 0), _texcoord - vec2(texCoordOffset.x, 0), sampleDir);
	#ifdef IRIS_FEATURE_TEXTURE_FILTERING
	float sampleAlpha = sampleNearest(gtexture, _texcoord, gtexSize).a;
	#else
	float sampleAlpha = texture(gtexture, _texcoord).a;
	#endif
	
	firstHit = sampleAlpha > 0.1 ? firstHit : secondHit;

	hit = firstHit.hit;
	float fHit = float(hit);
	shiftedCurrPos = mix(shiftedCurrPos, firstHit.currPos, fHit);
	stepAxis = mix(stepAxis, firstHit.stepAxis, fHit);
}

void sortIntersectionOpaque(inout RayHit RayHit1, const in RayHit RayHit2, inout bool hit, inout vec3 shiftedCurrPos, inout vec3 stepAxis) {
	bool useFirst = (RayHit1.hit && (!RayHit2.hit || RayHit1.t < RayHit2.t));
	RayHit firstHit = useFirst ? RayHit1 : RayHit2;
	RayHit secondHit = useFirst ? RayHit2 : RayHit1;

	RayHit1 = firstHit;
	hit = firstHit.hit;
	float fHit = float(hit);
	shiftedCurrPos = mix(shiftedCurrPos, firstHit.currPos, fHit);
	stepAxis = mix(stepAxis, firstHit.stepAxis, fHit);
}

void fenceIntersection(inout vec3 shiftedCurrPos, const in vec3 reflectedVector, const in vec3 invReflectedVector, inout bool hit, const in vec3 floorOffsetWorldPos, const in vec3 floorOffsetWorldPos1, const in vec3 floorOffsetWorldPos2, inout vec3 stepAxis) {
	RayHit hit1 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.375,0.001,0.375), floorOffsetWorldPos + vec3(0.625,0.999,0.625), stepAxis);
	RayHit hit2 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis);
	RayHit hit3 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos1 - vec3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - vec3(0.0, 0.375, 0.0), stepAxis);

	sortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
	sortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
}

void fenceIntersection2(inout vec3 shiftedCurrPos, const in vec3 reflectedVector, const in vec3 invReflectedVector, inout bool hit, const in vec3 floorOffsetWorldPos, const in vec3 floorOffsetWorldPos1, const in vec3 floorOffsetWorldPos2, const in vec3 floorOffsetWorldPos3, const in vec3 floorOffsetWorldPos4, inout vec3 stepAxis) {
	RayHit hit1 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.375,0.001,0.375), floorOffsetWorldPos + vec3(0.625,0.999,0.625), stepAxis);
	RayHit hit2 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis);
	RayHit hit3 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos1 - vec3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - vec3(0.0, 0.375, 0.0), stepAxis);
	RayHit hit4 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos3, floorOffsetWorldPos4, stepAxis);
	RayHit hit5 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos3 - vec3(0.0, 0.375, 0.0), floorOffsetWorldPos4 - vec3(0.0, 0.375, 0.0), stepAxis);

	sortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
	sortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
	sortIntersectionOpaque(hit1, hit4, hit, shiftedCurrPos, stepAxis);
	sortIntersectionOpaque(hit1, hit5, hit, shiftedCurrPos, stepAxis);
}

#ifdef END_SHADER
const vec3 WsunVec = vec3(0.0, 1.0, 0.0);
#endif

bool traceQuarterVoxel(in vec3 reflectedVector, in vec3 invReflectedVector, in vec3 stepSizes, in vec3 voxelPos, in vec3 stepDir, in vec3 nextDist, in vec3 currPos) {
	vec3 quarterVoxelPos = voxelPos / 4.0;
	vec3 originalQuarterVoxelPos = quarterVoxelPos;
	vec3 quarterNextDist = 4.0*((stepDir * 0.5 + 0.5) - fract(quarterVoxelPos)) * invReflectedVector;
	// vec3 oldVoxelPos = quarterVoxelPos;
	vec3 quarterCurrPos = currPos;
	// vec3 oldCurrPos = currPos;

	for (int i = 0; i < LpvSize/4; i++) {
		float closestDist = min(min(quarterNextDist.x, quarterNextDist.y), quarterNextDist.z);
		quarterCurrPos += reflectedVector * closestDist;

		vec3 stepAxis = step(quarterNextDist, vec3(closestDist));
		stepAxis.yz *= (1.0 - stepAxis.x);
		stepAxis.z *= (1.0 - stepAxis.y);

		quarterVoxelPos += stepAxis * stepDir;
		if (clamp(quarterVoxelPos, ivec3(0), ivec3(VoxelSize3/4u)) != quarterVoxelPos) break;

		uint blockID = imageLoad(imgQuarterVoxelMask, ivec3(quarterVoxelPos)).r;
		if(blockID > 0u && quarterVoxelPos != originalQuarterVoxelPos) {
			// voxelPos = oldVoxelPos * 4.0;
			// currPos = oldCurrPos;
			return true;
		}

		quarterNextDist += 4.0 * stepSizes * stepAxis - closestDist;

		// oldVoxelPos = quarterVoxelPos;
		// oldCurrPos = quarterCurrPos;
	}

	return false;
}
#endif

#if defined VOXEL_REFLECTIONS

vec4 voxelReflection(
	vec3 reflectedVector,
	vec3 flatNormal,
	vec3 normal,
	vec3 origin,
	float noise,
	inout float backgroundReflectMask
) {
	// vec3 invReflectedVector = 1.0 / reflectedVector;
	// vec3 stepSizes = abs(invReflectedVector);
	// vec3 voxelPos = GetLpvPosition(origin - 0.000055*normal);
	// vec3 originalVoxelPos = voxelPos;
	// vec3 stepDir = sign(reflectedVector);
	// vec3 nextDist = (stepDir * 0.5 + 0.5 - fract(voxelPos)) * invReflectedVector;
	// vec3 currPos = origin;

	//#ifdef OVERWORLD_SHADER
		vec3 DirectLightColor = lightSourceColorSSBO / 1400.0;
		vec3 AmbientLightColor = averageSkyCol_CloudsSSBO / 900.0;
		
		#ifdef USE_CUSTOM_DIFFUSE_LIGHTING_COLORS
			DirectLightColor = luma(DirectLightColor) * vec3(DIRECTLIGHT_DIFFUSE_R,DIRECTLIGHT_DIFFUSE_G,DIRECTLIGHT_DIFFUSE_B);
			AmbientLightColor = luma(AmbientLightColor) * vec3(INDIRECTLIGHT_DIFFUSE_R,INDIRECTLIGHT_DIFFUSE_G,INDIRECTLIGHT_DIFFUSE_B);
		#endif

		AmbientLightColor *= ambient_brightness;
	//#endif

	// vec2 gtexSize = vec2(1.0) / textureSize(gtexture, 0);
	// vec2 texCoordOffset = vec2(TEXTURE_RESOLUTION * 0.5) * gtexSize;
	vec4 color = vec4(0.0);

	//bool quarterHit = traceQuarterVoxel(reflectedVector, invReflectedVector, stepSizes, voxelPos, stepDir, nextDist, currPos);

	// uint traceDist = LpvSize;
	// if(!quarterHit) {
	// 	traceDist = 6u;
	// }

	// for (uint i = 0; i < traceDist; i++) {
	// 	float closestDist = min(min(nextDist.x, nextDist.y), nextDist.z);
	// 	currPos += reflectedVector * closestDist;
// 
	// 	vec3 stepAxis = step(nextDist, vec3(closestDist));
	// 	stepAxis.yz *= (1.0 - stepAxis.x);
	// 	stepAxis.z *= (1.0 - stepAxis.y);
// 
	// 	voxelPos += stepAxis * stepDir;
	// 	if (clamp(voxelPos, ivec3(0), ivec3(VoxelSize3-1u)) != voxelPos) break;
	// 
	// 	uint blockID = GetVoxelBlock(ivec3(voxelPos));
// 
	// 	vec3 shiftedCurrPos = currPos;
	// 	vec3 originalStepAxis = stepAxis;
// 
	// 	#ifdef DEFERRED_SPECULAR
	// 	bool hit = blockID != BLOCK_EMPTY && blockID != 80 && voxelPos != originalVoxelPos && blockID != BLOCK_LPV_IGNORE;
	// 	#else
	// 	bool hit = blockID != BLOCK_EMPTY && blockID != BLOCK_WATER && blockID != 80 && voxelPos != originalVoxelPos && blockID != BLOCK_LPV_IGNORE;
	// 	#endif
// 
	// 	#ifdef MIRROR_IRON
	// 		if (blockID == 504) {
	// 			traceDist = LpvSize;
	// 			hit = false;
	// 			vec3 voxelNormal = -originalStepAxis * stepDir;
	// 			reflectedVector = reflect(reflectedVector, voxelNormal);
	// 			invReflectedVector = 1.0 / reflectedVector;
	// 			stepSizes = abs(invReflectedVector);
	// 			voxelPos = GetLpvPosition(currPos - 0.000055*voxelNormal);
	// 			originalVoxelPos = voxelPos;
	// 			stepDir = sign(reflectedVector);
	// 			nextDist = (stepDir * 0.5 + 0.5 - fract(voxelPos)) * invReflectedVector;
	// 		} else
	// 	#endif
	// 	{
	// 		nextDist += stepSizes * originalStepAxis - closestDist;
	// 	}
// 
	// 	if(!hit) continue;
// 
	// 	vec3 offsetWorldPos = shiftedCurrPos + cameraPosition + stepAxis*stepDir*0.00015;
	// 	vec3 fractOffsetWorldPos = fract(offsetWorldPos);
	// 	vec3 floorOffsetWorldPos = floor(offsetWorldPos) - cameraPosition;
	// 	vec3 worldPosSampleOffset = vec3(0.0);
	// 	
	// 	// I hope nobody ever looks at this shit
	// 	if(blockID >= 12 && blockID < 424) {
	// 		if(blockID >= 22 &&  blockID < 38) {
	// 			if(blockID == 22) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.375,0.001,0.375), floorOffsetWorldPos + vec3(0.625,0.999,0.625), stepAxis);
	// 			else if(blockID == 23) fenceIntersection(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.375), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.001), stepAxis);
	// 			else if(blockID == 24) fenceIntersection(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.625, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.999, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 25) fenceIntersection(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.625), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.999), stepAxis);
	// 			else if(blockID == 26) fenceIntersection(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.001, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.375, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 27) fenceIntersection(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.999), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.001), stepAxis);
	// 			else if(blockID == 28) fenceIntersection(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.001, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.999, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 29) fenceIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.375), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.001), floorOffsetWorldPos + vec3(0.625, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.999, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 30) fenceIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.375), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.001), floorOffsetWorldPos + vec3(0.001, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.375, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 31) fenceIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.625), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.999), floorOffsetWorldPos + vec3(0.625, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.999, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 32) fenceIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.625), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.999), floorOffsetWorldPos + vec3(0.001, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.375, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 33) fenceIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.375), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.001), floorOffsetWorldPos + vec3(0.001, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.999, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 34) fenceIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.999), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.001), floorOffsetWorldPos + vec3(0.625, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.999, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 35) fenceIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.625), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.999), floorOffsetWorldPos + vec3(0.001, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.999, 0.9375, 0.5625), stepAxis);
	// 			else if(blockID == 36) fenceIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.001, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.375, 0.9375, 0.5625), floorOffsetWorldPos + vec3(0.4375, 0.75, 0.999), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.001), stepAxis);
	// 			else if(blockID == 37) fenceIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector, hit, floorOffsetWorldPos, floorOffsetWorldPos + vec3(0.4375, 0.75, 0.999), floorOffsetWorldPos + vec3(0.5625, 0.9375, 0.001), floorOffsetWorldPos + vec3(0.001, 0.75, 0.4375), floorOffsetWorldPos + vec3(0.999, 0.9375, 0.5625), stepAxis);
	// 		}
	// 		else if(blockID == BLOCK_TORCH || blockID == BLOCK_REDSTONE_TORCH_LIT || blockID == BLOCK_COPPER_TORCH || blockID == BLOCK_SOUL_TORCH || blockID == BLOCK_UNLIT_REDSTONE_TORCH) {
	// 			hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5625,0.0,0.5625), floorOffsetWorldPos + vec3(0.4375,0.625,0.4375), stepAxis);
	// 			worldPosSampleOffset.y = 0.1875;
	// 		}
	// 		else if(blockID == BLOCK_LANTERN || blockID == BLOCK_SOUL_LANTERN || blockID == BLOCK_COPPER_LANTERN) {
	// 			RayHit hit1 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.3125,0.001,0.3125), floorOffsetWorldPos + vec3(0.6875,0.4375,0.6875), stepAxis);
	// 			RayHit hit2 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.375,0.4375,0.375), floorOffsetWorldPos + vec3(0.625,0.5625,0.625), stepAxis);
// 
	// 			sortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
// 
	// 			// thank you mojank for making the texture layout different on all three lantern types
	// 			worldPosSampleOffset.y = 0.28125;
	// 			#if MC_VERSION >= 12111
	// 				if(blockID == BLOCK_LANTERN){
	// 					worldPosSampleOffset.xz = vec2(-0.0625);
	// 				} else if(blockID == BLOCK_SOUL_LANTERN){
	// 					worldPosSampleOffset.xz = vec2(-0.1875);
	// 				} else if(blockID == BLOCK_COPPER_LANTERN){
	// 					worldPosSampleOffset.xz = vec2(0.0625);
	// 				}
	// 				worldPosSampleOffset.z = mix(worldPosSampleOffset.z, 0.0, abs(stepAxis.y));
	// 			#else
	// 				if(blockID == BLOCK_LANTERN || blockID == BLOCK_SOUL_LANTERN){
	// 					worldPosSampleOffset.xz = vec2(0.0625);
	// 					worldPosSampleOffset.z = mix(worldPosSampleOffset.z, 0.0, abs(stepAxis.y));
	// 				}
	// 			#endif
	// 		}
	// 		else if(blockID >= 12 && blockID <= 178) {
	// 			if (blockID == 178 || blockID >= 12 && blockID <= 21 || blockID == BLOCK_GROUND_WAVING || blockID >= BLOCK_SSS_STRONG3 && blockID <= 88) { 
	// 				RayHit hit1 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0, 0.0, 0.4999), floorOffsetWorldPos + vec3(1.0, 1.0, 0.5001), stepAxis);
	// 				RayHit hit2 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.4999, 0.0, 0.0), floorOffsetWorldPos + vec3(0.5001, 1.0, 1.0), stepAxis);
// 
	// 				sortIntersectionCutout(hit1, hit2, stepDir, gtexSize, texCoordOffset, voxelPos, hit, shiftedCurrPos, stepAxis);
	// 			}
	// 			else if(blockID == BLOCK_CACTUS) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0625,0.0,0.0625), floorOffsetWorldPos + vec3(0.9375,0.9999,0.9375), stepAxis);
	// 			else if(blockID == BLOCK_BUTTON_FLOOR_NORTH_SOUTH) {
	// 				hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.3125,0.0,0.375), floorOffsetWorldPos + vec3(0.6875,0.125,0.625), stepAxis);
	// 				worldPosSampleOffset.y = 0.5;
	// 			}
	// 			else if(blockID == BLOCK_BUTTON_FLOOR_EAST_WEST) {
	// 				hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.375,0.0,0.3125), floorOffsetWorldPos + vec3(0.625,0.125,0.6875), stepAxis);
	// 				worldPosSampleOffset.y = 0.5;
	// 			}
	// 			else if(blockID == BLOCK_BUTTON_WALL_NORTH) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.6875,0.625,0.875), floorOffsetWorldPos + vec3(0.3125,0.375,1.0), stepAxis);
	// 			else if(blockID == BLOCK_BUTTON_WALL_EAST) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.125,0.625,0.6875), floorOffsetWorldPos + vec3(0.0,0.375,0.3125), stepAxis);
	// 			else if(blockID == BLOCK_BUTTON_WALL_SOUTH) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.6875,0.625,0.125), floorOffsetWorldPos + vec3(0.3125,0.375,0.0), stepAxis);
	// 			else if(blockID == BLOCK_BUTTON_WALL_WEST) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.875,0.375,0.3125), floorOffsetWorldPos + vec3(1.0,0.625,0.6875), stepAxis);
	// 			else if(blockID == BLOCK_BUTTON_CEILING_NORTH_SOUTH) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.3125,1.0,0.375), floorOffsetWorldPos + vec3(0.6875,0.875 ,0.625), stepAxis);
	// 			else if(blockID == BLOCK_BUTTON_CEILING_EAST_WEST) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.375,1.0,0.3125), floorOffsetWorldPos + vec3(0.625,0.875,0.6875), stepAxis);
	// 			else if(blockID == BLOCK_LEVER) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.375,1.0,0.3125), floorOffsetWorldPos + vec3(0.625,0.875,0.6875), stepAxis);
	// 		} else if(blockID >= 401 && blockID < 424) {
	// 			if(blockID >= 401 && blockID < 416) {
	// 				if(blockID == BLOCK_CARPET && fractOffsetWorldPos.y > 0.0625) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.0,0.0), floorOffsetWorldPos + vec3(1.0,0.0625,1.0), stepAxis);
	// 				else if(blockID == BLOCK_PRESSURE_PLATE) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0625,0.0,0.0625), floorOffsetWorldPos + vec3(0.9375,0.0625,0.9375), stepAxis);
	// 				else if (blockID == 407) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0001,0.9999,0.0001), floorOffsetWorldPos + vec3(0.9999,0.5,0.9999), stepAxis);
	// 					worldPosSampleOffset.y = -0.25;
	// 				}
	// 				else if (blockID == 408) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0001,0.0001,0.0001), floorOffsetWorldPos + vec3(0.9999,0.5,0.9999), stepAxis);
	// 					worldPosSampleOffset.y = 0.25;
	// 				}
	// 				else if (blockID == BLOCK_SNOW_LAYERS && fractOffsetWorldPos.y > 0.125) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos, floorOffsetWorldPos + vec3(1.0,0.125,1.0), stepAxis);
	// 				else if (blockID == BLOCK_TRAPDOOR_BOTTOM) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0001,0.0001,0.0001), floorOffsetWorldPos + vec3(0.9999,0.1875,0.9999), stepAxis);
	// 					worldPosSampleOffset.y = 0.40625;
	// 				}
	// 				else if (blockID == BLOCK_TRAPDOOR_TOP && fractOffsetWorldPos.y < 0.8125) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,1.0,0.0), floorOffsetWorldPos + vec3(1.0,0.8125,1.0), stepAxis);
	// 				else if (blockID == BLOCK_TRAPDOOR_N || blockID == BLOCK_DOOR_N)  {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.9999,0.9999,0.8125), floorOffsetWorldPos + vec3(0.0001,0.0001,0.9999), stepAxis);
// 
	// 					if(blockID == BLOCK_DOOR_N) {
	// 					worldPosSampleOffset.z = mix(-0.5, -0.40625, abs(stepAxis.y));
	// 					} else {
	// 					worldPosSampleOffset.z = mix(0.5, -0.40625, abs(stepAxis.y));
	// 					}
	// 				}
	// 				else if ((blockID == BLOCK_TRAPDOOR_E || blockID == BLOCK_DOOR_E)) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.1875,0.9999,0.9999), floorOffsetWorldPos + vec3(0.0001,0.0001,0.0001), stepAxis);
// 
	// 					if(blockID == BLOCK_DOOR_E) {
	// 					worldPosSampleOffset.x = mix(-0.5, 0.0, abs(stepAxis.y));
	// 					worldPosSampleOffset.z = mix(0.0, -0.40625, abs(stepAxis.y));
	// 					} else {
	// 					worldPosSampleOffset.x = mix(0.5, 0.0, abs(stepAxis.y));
	// 					worldPosSampleOffset.z = mix(0.0, 0.40625, abs(stepAxis.y));
	// 					}
	// 				}
	// 				else if (blockID == BLOCK_TRAPDOOR_S || blockID == BLOCK_DOOR_S) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.9999,0.9999,0.1875), floorOffsetWorldPos + vec3(0.0001,0.0001,0.0001), stepAxis);
// 
	// 					if(blockID == BLOCK_DOOR_S) {
	// 					worldPosSampleOffset.z = mix(-0.5, 0.34375, abs(stepAxis.y));
	// 					} else {
	// 					worldPosSampleOffset.z = mix(0.5, 0.40625, abs(stepAxis.y));
	// 					}
	// 				}
	// 				else if (blockID == BLOCK_TRAPDOOR_W || blockID == BLOCK_DOOR_W) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.8125,0.9999,0.9999), floorOffsetWorldPos + vec3(0.9999,0.0001,0.0001), stepAxis);
// 
	// 					if(blockID == BLOCK_DOOR_W) {
	// 					worldPosSampleOffset.x = mix(-0.5, 0.0, abs(stepAxis.y));
	// 					worldPosSampleOffset.z = mix(0.0, -0.40625, abs(stepAxis.y));
	// 					} else {
	// 					worldPosSampleOffset.x = mix(0.5, 0.0, abs(stepAxis.y));
	// 					worldPosSampleOffset.z = mix(0.0, 0.40625, abs(stepAxis.y));
	// 					}
	// 				}
	// 			}
	// 			else if (blockID >= 416 && blockID < 424) {
	// 				if(blockID == 416 && fractOffsetWorldPos.y > 0.5 && fractOffsetWorldPos.z > 0.5) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.0,1.0), floorOffsetWorldPos + vec3(1.0,0.5,0.5), stepAxis);
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.5,0.5), floorOffsetWorldPos + vec3(1.0,1.0,0.0), stepAxis) || hit;
	// 				} else if(blockID == 417 && fractOffsetWorldPos.y > 0.5 && fractOffsetWorldPos.x < 0.5) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,0.0,0.0), floorOffsetWorldPos + vec3(0.0,0.5,1.0), stepAxis);
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,0.5,0.0), floorOffsetWorldPos + vec3(1.0,1.0,1.0), stepAxis) || hit;
	// 				} else if(blockID == 418 && fractOffsetWorldPos.y > 0.5 && fractOffsetWorldPos.z < 0.5) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.0,0.0), floorOffsetWorldPos + vec3(1.0,0.5,0.5), stepAxis);
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.5,0.5), floorOffsetWorldPos + vec3(1.0,1.0,1.0), stepAxis) || hit;
	// 				} else if(blockID == 419) {
	// 					if(fractOffsetWorldPos.y > 0.5 && fractOffsetWorldPos.x > 0.5) {
	// 						hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,0.0,0.0), floorOffsetWorldPos + vec3(1.0,0.5,1.0), stepAxis);
	// 						hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,0.5,0.0), floorOffsetWorldPos + vec3(0.0,1.0,1.0), stepAxis) || hit;
	// 					}
// 
	// 					worldPosSampleOffset.y = -0.25;
	// 					worldPosSampleOffset.z = mix(0.0, -0.25, abs(stepAxis.y));
	// 					
	// 				} else if(blockID == 420 && fractOffsetWorldPos.y > 0.5 && fractOffsetWorldPos.x < 0.5 && fractOffsetWorldPos.z < 0.5) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.0,0.0), floorOffsetWorldPos + vec3(0.5,0.5,0.5), stepAxis);
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.5,0.5), floorOffsetWorldPos + vec3(0.5,1.0,1.0), stepAxis) || hit;
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,0.5,0.0), floorOffsetWorldPos + vec3(1.0,1.0,0.5), stepAxis) || hit;
	// 				} else if(blockID == 421 && fractOffsetWorldPos.y > 0.5 && fractOffsetWorldPos.x > 0.5 && fractOffsetWorldPos.z < 0.5) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,0.0,0.0), floorOffsetWorldPos + vec3(1.0,0.5,0.5), stepAxis);
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(1.0,0.5,0.5), floorOffsetWorldPos + vec3(0.5,1.0,1.0), stepAxis) || hit;
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,1.0,0.5), floorOffsetWorldPos + vec3(0.0,0.5,0.0), stepAxis) || hit;
	// 				} else if(blockID == 422) {
	// 					if(fractOffsetWorldPos.y > 0.5 && fractOffsetWorldPos.x > 0.5 && fractOffsetWorldPos.z > 0.5) {
	// 						hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,0.0,0.5), floorOffsetWorldPos + vec3(1.0,0.5,1.0), stepAxis);
	// 						hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,0.5,0.5), floorOffsetWorldPos + vec3(0.0,1.0,1.0), stepAxis) || hit;
	// 						hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,1.0,0.5), floorOffsetWorldPos + vec3(1.0,0.5,0.0), stepAxis) || hit;
	// 					}
// 
	// 					worldPosSampleOffset.y = -0.25;
	// 					worldPosSampleOffset.z = mix(0.0, -0.25, abs(stepAxis.y));
	// 				} else if(blockID == 423 && fractOffsetWorldPos.y > 0.5 && fractOffsetWorldPos.x < 0.5 && fractOffsetWorldPos.z > 0.5) {
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.0,0.5), floorOffsetWorldPos + vec3(0.5,0.5,1.0), stepAxis);
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,1.0,0.5), floorOffsetWorldPos + vec3(0.5,0.5,0.0), stepAxis) || hit;
	// 					hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.5,1.0,0.5), floorOffsetWorldPos + vec3(1.0,0.5,1.0), stepAxis) || hit;
	// 				}
	// 			}
	// 		} else if (blockID >= 267 && blockID <= 291) {
	// 			if(blockID == BLOCK_HOPPER) {
	// 				RayHit hit1 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.25, 0.25, 0.25), floorOffsetWorldPos + vec3(0.75, 0.625, 0.75), stepAxis);
	// 				RayHit hit2 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0001, 0.625, 0.0001), floorOffsetWorldPos + vec3(0.9999, 0.9999, 0.125), stepAxis);
	// 				RayHit hit3 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0001, 0.625, 0.0001), floorOffsetWorldPos + vec3(0.125, 0.9999, 0.9999), stepAxis);
	// 				RayHit hit4 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.875, 0.625, 0.0001), floorOffsetWorldPos + vec3(0.9999, 0.9999, 0.9999), stepAxis);
	// 				RayHit hit5 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0001, 0.625, 0.875), floorOffsetWorldPos + vec3(0.9999, 0.9999, 0.9999), stepAxis);
	// 				RayHit hit6 = AABBintersection2(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0001, 0.625, 0.0001), floorOffsetWorldPos + vec3(0.9999, 0.6875, 0.9999), stepAxis);
// 
	// 				sortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
	// 				sortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
	// 				sortIntersectionOpaque(hit1, hit4, hit, shiftedCurrPos, stepAxis);
	// 				sortIntersectionOpaque(hit1, hit5, hit, shiftedCurrPos, stepAxis);
	// 				sortIntersectionOpaque(hit1, hit6, hit, shiftedCurrPos, stepAxis);
	// 				worldPosSampleOffset.y = -0.34375;
// 
	// 				worldPosSampleOffset.z = mix(0.0, -0.34375, abs(stepAxis.y));
	// 			}
	// 			if(blockID == BLOCK_ENCHANTING_TABLE) {
	// 				worldPosSampleOffset.y = 0.125;
	// 				hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0001,0.0001,0.0001), floorOffsetWorldPos + vec3(0.9999,0.75,0.9999), stepAxis);
	// 			}
	// 			else if(blockID == BLOCK_END_PORTAL_FRAME) {
	// 				worldPosSampleOffset.y = 0.09375;
	// 				hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0001,0.0001,0.0001), floorOffsetWorldPos + vec3(0.9999,0.8125,0.9999), stepAxis);
	// 			}
	// 			else if(blockID == BLOCK_GLOW_LICHEN_NORTH || blockID == BLOCK_SCULK_VEIN_NORTH || blockID == BLOCK_VINE_NORTH) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.0,0.0001), floorOffsetWorldPos + vec3(1.0,1.0,0.001), stepAxis);
	// 			else if(blockID == BLOCK_GLOW_LICHEN_EAST || blockID == BLOCK_SCULK_VEIN_EAST || blockID == BLOCK_VINE_EAST) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.999,0.0,0.0), floorOffsetWorldPos + vec3(0.9999,1.0,1.0), stepAxis);
	// 			else if(blockID == BLOCK_GLOW_LICHEN_SOUTH || blockID == BLOCK_SCULK_VEIN_SOUTH || blockID == BLOCK_VINE_SOUTH) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.0,0.999), floorOffsetWorldPos + vec3(1.0,1.0,0.9999), stepAxis);
	// 			else if(blockID == BLOCK_GLOW_LICHEN_WEST || blockID == BLOCK_SCULK_VEIN_WEST || blockID == BLOCK_VINE_WEST) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.001,1.0,1.0), floorOffsetWorldPos + vec3(0.0001,0.0,0.0), stepAxis);
	// 			else if(blockID == BLOCK_GLOW_LICHEN_UP || blockID == BLOCK_SCULK_VEIN_UP || blockID == BLOCK_VINE_UP) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.999,0.0), floorOffsetWorldPos + vec3(1.0,0.9999,1.0), stepAxis);
	// 			else if(blockID == BLOCK_GLOW_LICHEN_DOWN || blockID == BLOCK_SCULK_VEIN_DOWN) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.0001,0.0), floorOffsetWorldPos + vec3(1.0,0.001,1.0), stepAxis);
	// 			else if (blockID == BLOCK_DAYLIGHT_DETECTOR && fractOffsetWorldPos.y > 0.375) hit = AABBintersection(shiftedCurrPos, reflectedVector, invReflectedVector, floorOffsetWorldPos + vec3(0.0,0.0,0.0), floorOffsetWorldPos + vec3(1.0,0.375,1.0), stepAxis);
	// 		} else if (blockID >= 319 && blockID < 335) {
// 
	// 			
	// 		}
	// 	}
// 
	// 	// if(length(currPos) > 50) return vec4(10.0);
	// 	// if(hit) return vec4(0.0,0.0,0.0,1.0);
// 
	// 	if(hit){
	// 		vec2 texcoord;
	// 		vec3 tint;
	// 		vec3 voxelNormal = -stepAxis * stepDir;
// 
	// 		vec2 lightmap;
	// 		GetVoxelData(ivec3(voxelPos), texcoord, tint, voxelNormal, lightmap);
// 
	// 		vec3 wPos = shiftedCurrPos + cameraPosition;
	// 		vec3 fractWpos = fract(wPos);
	// 		fractWpos += worldPosSampleOffset;
	// 		vec2 sampleDir = stepAxis.x * fractWpos.zy + stepAxis.y * fractWpos.xz + stepAxis.z * fractWpos.xy;
	// 		texcoord = mix(texcoord + vec2(0, texCoordOffset.y), texcoord - vec2(0, texCoordOffset.y), sampleDir);
	// 		texcoord = mix(texcoord + vec2(texCoordOffset.x, 0), texcoord - vec2(texCoordOffset.x, 0), sampleDir);
// 
	// 		#ifdef IRIS_FEATURE_TEXTURE_FILTERING
	// 		vec4 sampleColor = sampleNearest(gtexture, texcoord, gtexSize);
	// 		#else
	// 		vec4 sampleColor = texture(gtexture, texcoord);
	// 		#endif
	// 		
	// 		if(sampleColor.a > 0.1){
	// 			vec3 albedo = sampleColor.rgb;
	// 			albedo *= tint;
// 
	// 			albedo = toLinear(albedo);
// 
	// 			//#if defined OVERWORLD_SHADER
// 
	// 			float SkylightDir = voxelNormal.y;
	// 			
	// 			SkylightDir = SkylightDir*0.5+0.5;
// 
	// 			float skylight = mix(0.08 + 0.92*(1.0-lightmap.y), 1.0, SkylightDir);
// 
	// 			vec3 Indirect_lighting = 0.525*doIndirectLighting(AmbientLightColor * skylight, vec3(1.0), lightmap.y);
	// 			//#endif
// 
	// 			vec3 lpvPos = GetLpvPosition(shiftedCurrPos);
// 
	// 			#ifdef MAIN_SHADOW_PASS
	// 			float smoothSkylight;
	// 			Indirect_lighting += doBlockLightLighting(vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, shiftedCurrPos, lpvPos, vec3(0.0), false, noise, voxelNormal, false);
	// 			#else
	// 			Indirect_lighting += doBlockLightLighting(vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, shiftedCurrPos, lpvPos);
	// 			#endif
// 
	// 			// vec3 AO = vec3(pow(1.0 - vanillaAO*vanillaAO,5.0));
	// 			// Indirect_lighting *= AO;
// 
	// 			float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(shiftedCurrPos) / (shadowDistance+16),0.0)*5.0,1.0));
	// 			float sh = ComputeVoxelShadowMap(DirectLightColor, shiftedCurrPos, shadowMapFalloff, noise, voxelNormal);
// 
	// 			float lightLeakFix = clamp(pow(eyeBrightnessSmooth.y/240. + lightmap.y,2.0) ,0.0,1.0);
	// 			sh *= lightLeakFix;
// 
	// 			#ifdef OVERWORLD_SHADER
	// 				sh *=  GetCloudShadow(wPos, WsunVec);
	// 			#endif
// 
	// 			float NdotL; 
// 
	// 			if(blockID == BLOCK_SSS_STRONG || blockID == BLOCK_SSS_STRONG3 || blockID == BLOCK_AIR_WAVING || blockID == BLOCK_SSS_STRONG_2 ||
	// 			   blockID == BLOCK_GROUND_WAVING || blockID == BLOCK_GROUND_WAVING_VERTICAL ||
	// 			   blockID == BLOCK_GRASS_SHORT || blockID == BLOCK_GRASS_TALL_UPPER || blockID == BLOCK_GRASS_TALL_LOWER ||
	// 			   blockID == BLOCK_SSS_WEAK || blockID == BLOCK_CACTUS || blockID == BLOCK_SSS_WEAK_2 ||
	// 			   blockID == BLOCK_CELESTIUM || (blockID >= 269 && blockID <= 274) || blockID == BLOCK_SNOW_LAYERS || blockID == BLOCK_CARPET ||
	// 			   blockID == BLOCK_AMETHYST_BUD_MEDIUM || blockID == BLOCK_AMETHYST_BUD_LARGE || blockID == BLOCK_AMETHYST_CLUSTER ||
	// 			   blockID == BLOCK_BAMBOO || blockID == BLOCK_SAPLING || (blockID >= BLOCK_VINE_NORTH && blockID <= BLOCK_VINE_UP) || blockID == BLOCK_VINE_OTHER)
	// 			{
	// 				NdotL = 1.0;
	// 			} else {
	// 				NdotL = clamp((-15.0 + dot(voxelNormal, WsunVec)*255.0) / 240.0, 0.0, 1.0);
	// 			}
// 
	// 			vec3 finalColor = albedo * (Indirect_lighting + DirectLightColor * sh * NdotL);
// 
	// 			float EMISSIVE = 0.0;
// 
	// 			// normal block lightsources
	// 			if(blockID >= 100 && blockID < 282) {
	// 				EMISSIVE = 0.5;
// 
	// 				if(blockID == 266 || (blockID >= 276 && blockID <= 281)) EMISSIVE = 0.2; // sculk stuff
// 
	// 				else if(blockID == 195) EMISSIVE = 2.3; // glow lichen
// 
	// 				else if(blockID == 185) EMISSIVE = 1.5; // crying obsidian
// 
	// 				else if(blockID == 105) EMISSIVE = 2.0; // brewing stand
	// 				
	// 				else if(blockID == 236) EMISSIVE = 1.0; // respawn anchor
// 
	// 				else if(blockID == 101) EMISSIVE = 0.7; // large amethyst bud
// 
	// 				else if(blockID == 103) EMISSIVE = 1.0; // amethyst cluster
// 
	// 				else if(blockID == 244) EMISSIVE = 1.5; // soul fire
// 
	// 				EMISSIVE *= getVoxelEmission(albedo);
// 
	// 				voxelEmission(finalColor, albedo, EMISSIVE);
	// 			}
// 
	// 			#if EMISSIVE_ORES > 0
	// 				if(blockID == 502) {
	// 					EMISSIVE = EMISSIVE_ORES_STRENGTH;
// 
	// 					EMISSIVE *= getVoxelEmission(albedo);
// 
	// 					voxelEmission(finalColor, albedo, EMISSIVE);
	// 				}
	// 			#endif
// 
	// 			sampleColor.a *= (1.0 - color.a);
// 
	// 			color.rgb += finalColor * sampleColor.a;
// 
	// 			color.a += sampleColor.a;
// 
	// 			// if(dot(reflectedVector, normal) < 0.0) return vec4(color.rgb, 1.0);
	// 			#if defined DEFERRED_SPECULAR
	// 			if(blockID == BLOCK_WATER) {
	// 				if(abs(voxelNormal.y) > 0.1){
	// 					vec3 waterPos = (wPos).xzy;
// 
	// 					vec3 bump = normalize(getWaveNormal(waterPos, shiftedCurrPos));
// 
	// 					float bumpmult = WATER_WAVE_STRENGTH;
// 
	// 					bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);
// 
	// 					voxelNormal.xz = bump.xy;
	// 				}
	// 				vec3 backgroundReflection = skyCloudsFromTex(reflect(reflectedVector, voxelNormal), colortex4).rgb / 1200.0;
// 
	// 				const float f0 = 0.02;
	// 				float normalDotEye = dot(voxelNormal, reflectedVector);
	// 				float fresnel =  pow(clamp(1.0 + normalDotEye, 0.0, 1.0),5.0);
// 
	// 				fresnel = mix(f0, 1.0, fresnel);
// 
	// 				color.rgb = mix(color.rgb, backgroundReflection * min(max(lightmap.y-0.5,0.0)/0.4,1.0), fresnel);
	// 				// color.rgb += SunReflection*SSR_HIT_SKY_MASK;
// 
	// 				// color.a = color.a + (1.0-color.a) * fresnel;
	// 				return vec4(color.rgb, 1.0);
	// 			}
	// 			#endif
	// 	
	// 			if(color.a > 0.99) return vec4(color.rgb, 1.0);
	// 		}
	// 	}
	// 	
	// 	// if(hit) return color; // vec4(0.2, 0.87, 0.2, 1.0);
	// }

	backgroundReflectMask = 1.0;
	return color;
}
#endif

#if defined OVERWORLD_SHADER || defined END_ISLAND_LIGHT && defined END_SHADER
vec2 CleanPhotonicsSample(
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

float ComputePhotonicsShadowMap(inout vec3 directLightColor, vec3 playerPos, float maxDistFade, float noise, in vec3 geoNormals){

	// if(maxDistFade <= 0.0) return 1.0;

	// setup shadow projection
	#ifdef OVERWORLD_SHADER
		#ifdef CUSTOM_MOON_ROTATION
			vec3 projectedShadowPosition = mat3(customShadowMatrixSSBO) * playerPos  + customShadowMatrixSSBO[3].xyz;
		#else
			vec3 projectedShadowPosition = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
		#endif

		applyShadowBias(projectedShadowPosition, playerPos, geoNormals);

		projectedShadowPosition = diagonal3(shadowProjection) * projectedShadowPosition + shadowProjection[3].xyz;

		// un-distort
		#ifdef DISTORT_SHADOWMAP
			float distortFactor = calcDistort(projectedShadowPosition.xy);
			projectedShadowPosition.xy *= distortFactor;
		#else
			float distortFactor = 1.0;
		#endif

		projectedShadowPosition.z += shadowProjection[3].z * 0.0012;
	#else
		float distortFactor = 1.0;
	#endif

	#if defined END_ISLAND_LIGHT && defined END_SHADER
		vec4 shadowPos = customShadowMatrixSSBO * vec4(playerPos, 1.0);
		applyShadowBias(shadowPos.xyz, playerPos, geoNormals);
		shadowPos =  customShadowPerspectiveSSBO * shadowPos;
		vec3 projectedShadowPosition = shadowPos.xyz / shadowPos.w;
	#endif



	// hamburger
	projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5);
	
	float shadowmap = 0.0;
	vec3 translucentTint = vec3(0.0);

	if (projectedShadowPosition.z > 1.0 || projectedShadowPosition.z < 0.0) return 1.0;

	#ifdef BASIC_SHADOW_FILTER
		int samples = int(SHADOW_FILTER_SAMPLE_COUNT * 0.5);
		#ifdef END_SHADER
			float rdMul = 52.0*d0k;
		#else
			float rdMul = 2.4*distortFactor*d0k;
		#endif

		for(int i = 0; i < samples; i++){
			vec2 offsetS = CleanPhotonicsSample(i, samples - 1, noise) * rdMul;
			projectedShadowPosition.xy += offsetS;
	#else
		int samples = 1;
	#endif
	

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

	#ifdef BASIC_SHADOW_FILTER
		}
	#endif

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		// tint the lightsource color with the translucent shadow color
		directLightColor *= mix(vec3(1.0), translucentTint.rgb / samples, maxDistFade);
	#endif

	float shadowResult = shadowmap / samples;

	#ifdef END_SHADER
	float r = length(projectedShadowPosition.xy - vec2(0.5));
	if (r < 0.5 && abs(projectedShadowPosition.z) < 1.0) {
		shadowResult *= smoothstep(0.5, 0.25, r);
	} else {
		shadowResult = 0.0;
	}
	#endif

	return shadowResult;
	// return mix(1.0, shadowmap / samples, maxDistFade);
}
#endif
#if defined PHOTONICS_INCLUDED && defined PHOTONICS && defined VOXEL_REFLECTIONS

struct translucentHit {
	vec3 hitNormal;
	vec3 hitPos;
	vec4 hitColor;
	int hitID;
	float skylight;
};

void trace_wsr(inout RayJob job, bool transparency, inout translucentHit[10] translucentHitRays, inout uint translucentHits, out int block_id, out float skylightmap) {
	job.direction = normalize(job.direction);

    vec3 direction_inv = 1.0f / job.direction;
    float t0 = ph_intersects_world(direction_inv, 16.0f * job.origin);
    if (t0 == -1.0f) {
        job.result_position = vec3(47823934.0f) - world_offset;
        return;
    }

    vec3 position = job.origin * 16.0f + (t0 + 0.03f) * job.direction;
    //    vec3 position = 16.0f * job.origin;

    vec3 ray_direction_sign = sign(job.direction);

    ivec3 intersection_index = ivec3(7.5f * ray_direction_sign + vec3(7.5f, 12.5f, 17.5f));
    vec3 skipDelta = ray_direction_sign * 0.00001f;
    ivec3 intersection_offset = max(ivec3(ray_direction_sign), 0);

    int t_min = -1;

    int block_index = -1;

    block_id = -1;
    int voxel_index = 0;


    ivec3 new_index = ivec3(0);
    ivec3 old_index = ivec3(0);

    ivec3 entries = ivec3(0);

    result_tint_color = vec3(1f);
	int previous_block_id = -1;

    for (int i = RAY_ITERATION_COUNT; !(ray_iteration_bound_reached = i < 0); i--) {
        //        debug += vec3(0.1f);

        ivec3 w = ivec3(position); // TODO: maybe use uvec3, no negative check neccessary
        // ivec3 block_position = w >> 4;

        if (!ph_is_inside(position)) // outside of world?
            return;

        // if ((job.result_hit = block_position == ray_target)) { // ray target reached?
        //     break;
        // }

        // if (ray_constraint != ivec3(-9999) && block_position != ray_constraint)
        //     return;

        int scale = 0;
        int entry = 0;

        new_index.x = ph_get_world_index((w >> 8) & 31);
        if (new_index.x != old_index.x) { // TODO: CRITICAL! UBOs are too tiny for 32x32x32
            entries.x = root_array[new_index.x];
        }

        if (entries.x < 0) { // found chunk?
            ivec3 block_pos = (w >> 4) & 15;
            new_index.y = -entries.x + ph_get_index(block_pos);

            if (new_index.y != old_index.y) {
                entries.y = cb_array[new_index.y];
                if (entries.y < 0) { // found block
                    int block_data = -entries.y;

					block_index = block_data & 0xfff;
                    block_index = block_index * (ph_byte_size / 4);

					ph_result_sky_brightness = block_data >> 13;
                    block_id = cb_array[block_index];
                    voxel_index = block_index + 2;
                } else {
                    block_index = -1;
                }
            }

            if (block_index != -1) { // found block
                ivec3 voxel_pos = w & 15;
                new_index.z = voxel_index + ph_get_index(voxel_pos);
                if (new_index.z != old_index.z) {
                    entries.z = cb_array[new_index.z];

                    //if (breakOnEmpty && entries.z == 519536640) {
                    //    job.result_hit = true;
                    //    entries.z = -0;
					//
                    //    break;
                    //}
                }

                if (entries.z < 0) { // found bloxel
					#ifdef MIRROR_IRON
					if(block_id == 504) {
						vec3 normal = vec3(0.0);
						normal[t_min] = sign(-ray_direction_sign[t_min]);
						job.direction = reflect(job.direction, normal);

						direction_inv = 1.0f / job.direction;

						ray_direction_sign = sign(job.direction);

						intersection_index = ivec3(7.5f * ray_direction_sign + vec3(7.5f, 12.5f, 17.5f));
						skipDelta = ray_direction_sign * 0.00001f;
						intersection_offset = max(ivec3(ray_direction_sign), 0);
					} else
					#endif
					{	
						#ifdef TRANSLUCENT_IN_REFLECTIONS
						if ((-entries.z & 0x7f000000) == 0)
						#endif
						{
							job.result_hit = true;
							break;
						}

						#ifdef TRANSLUCENT_IN_REFLECTIONS
						vec4 color = ph_unpack_color(-entries.z);
						if (previous_block_id != block_id) {
							if (color.a > 0.01 && translucentHits < 10u) {

								vec3 hitnormal = vec3(0.0);
								if (t_min != -1) hitnormal[t_min] = sign(-ray_direction_sign[t_min]);

								translucentHitRays[translucentHits].hitNormal = hitnormal;
								translucentHitRays[translucentHits].hitPos = vec3(position / 16.0f);
								translucentHitRays[translucentHits].hitColor = color;
								translucentHitRays[translucentHits].hitID = block_id;
								translucentHitRays[translucentHits].skylight = get_result_sky_light(hitnormal) / 15.0;

								translucentHits += 1u;
							}

							previous_block_id = block_id;
						}
						#endif
					}

					scale = 4;
					entry = ph_to_fake_air_entry(block_pos);					

                } else { scale = 0; entry = entries.z; }
            } else { scale = 4; entry = entries.y; previous_block_id = -1;}
        } else { scale = 8; entry = entries.x; }

        old_index = new_index;

        ivec3 intersection = (((ivec3(entry) >> intersection_index) & 31) + intersection_offset) << scale;

        scale += 4;
        scale += int(scale == 8 + 4);
        intersection += w & (-1 << scale);

        vec3 t = (intersection - position) * direction_inv;
        t_min = int(t.x >= t.y);
        t_min = t.z < t[t_min] ? 2 : t_min;

        position += t[t_min] * job.direction;

        // "push precision" into lower decimal values to fight rounding errors
        position[t_min] = (intersection[t_min] * 0.01f + skipDelta[t_min]) * 100.0f;
    }

    // lightEmittance = unpackUnorm4x8(cb_array[-entries.y / 4097]).xyz;

    job.result_color = vec3((-entries.z >> 0) & 0xff, (-entries.z >> 8) & 0xff, (-entries.z >> 16) & 0xff) / 0xff;
    job.result_position = vec3(position / 16.0f);

    if (t_min != -1)
        job.result_normal[t_min] = sign(-ray_direction_sign[t_min]);

    //    job.result_color = debug;

    ray_target = ivec3(-1);
	skylightmap = get_result_sky_light(job.result_normal) / 15.0;
}
#endif

uniform float skyLightLevelSmooth;

vec3 doBlockLightLightingVoxel(
    vec3 lightColor, float lightmap,
    vec3 playerPos, vec3 lpvPos
){
    lightmap = clamp(lightmap,0.0,1.0);

    float lightmapBrightspot = min(max(lightmap-0.7,0.0)*3.3333,1.0);
    lightmapBrightspot *= lightmapBrightspot*lightmapBrightspot;

    float lightmapLight = 1.0-sqrt(1.0-lightmap);
    lightmapLight *= lightmapLight;

    float lightmapCurve = mix(lightmapLight, 2.5, lightmapBrightspot);
    vec3 blockLight = lightmapCurve * lightColor;
    
    #if defined IS_LPV_ENABLED && defined MC_GL_ARB_shader_image_load_store
        vec4 lpvSample = SampleLpvLinear(lpvPos);

        #ifdef VANILLA_LIGHTMAP_MASK
            lpvSample.rgb *= lightmapCurve;
        #endif

        // create a smooth falloff at the edges of the voxel volume.
        const float fadeLength = 10.0; // in meters
        vec3 cubicRadius = clamp(min(((LpvSize3-1.0) - lpvPos)/fadeLength, lpvPos/fadeLength), 0.0, 1.0);
        float voxelRangeFalloff = cubicRadius.x*cubicRadius.y*cubicRadius.z;
        voxelRangeFalloff = 1.0 - pow(1.0-pow(voxelRangeFalloff,1.5),3.0);
        
        // outside the voxel volume, lerp to vanilla lighting as a fallback
        blockLight = mix(blockLight, lpvSample.rgb + lightColor * 2.5 * min(max(lightmap-0.999,0.0)/(1.0-0.999),1.0), voxelRangeFalloff);

        #ifdef Hand_Held_lights
            // create handheld lightsources
            if (heldItemId > 0){
                    float lightRange = 0.0;
                    vec3 handLightCol = GetHandLight(heldItemId, playerPos, lightRange);

                    blockLight += handLightCol;
            }
            

            if (heldItemId2 > 0){
                    float lightRange2 = 0.0;
                    vec3 handLightCol2 = GetHandLight(heldItemId2, playerPos, lightRange2);

                    blockLight += handLightCol2;
            }
        #endif
    #endif

    return blockLight * TORCH_AMOUNT;
}
#if defined PHOTONICS_INCLUDED && defined PHOTONICS && defined VOXEL_REFLECTIONS
	#if defined OVERWORLD_SHADER
	uniform float caveDetection;
	#define TIMEOFDAYFOG

	#include "/lib/climate_settings.glsl"
	#include "/lib/overworld_fog.glsl"

	vec4 raymarchWSR_LPV(
		in vec3 origin,
		in vec3 endPos,
		in float dither
	){
		#if (!defined LPV_VL_FOG_ILLUMINATION || !defined IS_LPV_ENABLED) && (!defined FLASHLIGHT_FOG_ILLUMINATION || !defined FLASHLIGHT)
			return vec4(0.0,0.0,0.0,1.0);
		#endif

		if(length(origin-endPos) < 0.001) return vec4(0.0,0.0,0.0,1.0);

		const int SAMPLECOUNT = 3;
		float mult = float(VL_SAMPLES) / float(SAMPLECOUNT) * 1.15;
		float minimumDensity = 0.000025;
		// if(eyeInWater) minimumDensity = 0.00006;
		const float fadeLength = 10.0; // in blocks

		vec3 LPVrayStartPos = endPos-origin - gbufferModelViewInverse[3].xyz;
		
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

			rayProgress = gbufferModelViewInverse[3].xyz + d*LPVrayStartPos + origin;

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
			
			density = max(density/1000.0, _minimumDensity)*mult;

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

				// if(eyeInWater) lighting *= 2.5;

				#ifdef LPV_VL_FOG_ILLUMINATION_HANDHELD
					float lightRange = 0.0;
					vec3 handLightCol = GetHandLight(heldItemId, rayProgress, lightRange);
					
					vec3 handLightCol2 = GetHandLight(heldItemId2, rayProgress, lightRange);

					lighting += (handLightCol + handLightCol2) * TORCH_AMOUNT * LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 0.04;
				#endif

				color.rgb += (lighting - lighting * volumeCoeff) * color.a;
			#endif

			#if defined FLASHLIGHT && defined FLASHLIGHT_FOG_ILLUMINATION
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

	vec4 raymarchWSRfog(
		const in vec3 origin,
		const in vec3 endPos,
		const in vec2 dither,
		const in vec3 LightColor,
		const in vec3 AmbientColor,
		const in vec3 AveragedAmbientColor,
		const in int SAMPLECOUNT
	){
		#ifndef TOGGLE_VL_FOG
			return vec4(0.0,0.0,0.0,1.0);
		#endif
		if(length(origin-endPos) < 0.001) return vec4(0.0,0.0,0.0,1.0);

		float mult = float(VL_SAMPLES) / float(SAMPLECOUNT) * 1.15;

		//project pixel position into projected shadowmap space
		vec3 dVWorld = endPos-origin - gbufferModelViewInverse[3].xyz;

		float rayLength = length(dVWorld);

		vec3 rayDir = normalize(endPos-origin);

		float maxLength =  min(rayLength, far)/rayLength;
		
		dVWorld *= maxLength;

		float dL = length(dVWorld)/8.0;

		const float expFactor = 11.0;

		/// -------------  COLOR/LIGHTING STUFF ------------- \\\
		
		vec3 color = vec3(0.0);
		vec3 finalAbsorbance = vec3(1.0);

		float totalAbsorbance = 1.0;

		// float fogAbsorbance = 1.0;
		// float atmosphereAbsorbance = 1.0;
		vec3 atmosphereAbsorbance = vec3(1.0);

		float SdotV = dot(WsunVec, rayDir);

		///// ----- fog lighting
		//Mie phase + somewhat simulates multiple scattering (Horizon zero down cloud approx)
		float sunPhase = fogPhase(SdotV)*5.0;
		float skyPhase = 0.5 + pow(1.0-pow(1.0-clamp(rayDir.y*0.5+0.5,0.0,1.0),2.0),5.0)*2.0;
		float rayL = phaseRayleigh(SdotV);

		vec3 rC = vec3(sky_coefficientRayleighR*1e-6, sky_coefficientRayleighG*1e-5, sky_coefficientRayleighB*1e-5) ;
		vec3 mC = vec3(fog_coefficientMieR*1e-6, fog_coefficientMieG*1e-6, fog_coefficientMieB*1e-6);
		
		#if defined EXCLUDE_WRITE_TO_LUT && defined USE_CUSTOM_FOG_LIGHTING_COLORS
			LightColor = dot(LightColor,vec3(0.21, 0.72, 0.07)) * vec3(DIRECTLIGHT_FOG_R,DIRECTLIGHT_FOG_G,DIRECTLIGHT_FOG_B);
			AmbientColor = dot(AmbientColor,vec3(0.21, 0.72, 0.07)) * vec3(INDIRECTLIGHT_FOG_R,INDIRECTLIGHT_FOG_G,INDIRECTLIGHT_FOG_B);
		#endif

		vec3 skyLightPhased = AmbientColor;
		vec3 LightSourcePhased = LightColor;

		skyLightPhased *= skyPhase;
		LightSourcePhased *= sunPhase;

		#ifdef AMBIENT_LIGHT_ONLY
			LightSourcePhased = vec3(0.0);
		#endif

		#ifdef PER_BIOME_ENVIRONMENT
			vec3 biomeDirect = LightSourcePhased; 
			vec3 biomeIndirect = skyLightPhased;
			float inBiome = BiomeVLFogColors(biomeDirect, biomeIndirect);
		#endif

		float inACave = 1.0 - caveDetection;
		float lightLevelZero = pow(clamp(eyeBrightnessSmooth.y/240.0 ,0.0,1.0),3.0);

		// SkyLightColor *= lightLevelZero*0.9 + 0.1;
		// vec3 finalsceneColor = vec3(0.0);


		for (int i = 0; i < SAMPLECOUNT; i++) {
			float d = (pow(expFactor, float(i+dither.y)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
			float dd = pow(expFactor, float(i+dither.x)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);

			// #ifdef VOLUMETRIC_CLOUDS
			// 	// check if the fog intersects clouds
			// 	if(length(d*dVWorld) > cloudPlaneDistance) break;
			// #endif

			vec3 progressP = gbufferModelViewInverse[3].xyz + d*dVWorld + origin;
			vec3 progressW = progressP + cameraPosition;

			//------------------------------------
			//------ SAMPLE SHADOWS FOR FOG EFFECTS
			//------------------------------------
				#ifdef CUSTOM_MOON_ROTATION
					vec3 fragposition = mat3(customShadowMatrixSSBO) * progressP + customShadowMatrixSSBO[3].xyz;
				#else
					vec3 fragposition = mat3(shadowModelView) * progressP + shadowModelView[3].xyz;
				#endif
				fragposition = diagonal3(shadowProjection) * fragposition + shadowProjection[3].xyz;

				#if defined DISTORT_SHADOWMAP && defined OVERWORLD_SHADER
					float distortFactor = calcDistort(fragposition.xy);
				#else
					float distortFactor = 1.0;
				#endif

				vec3 shadowPos = vec3(fragposition.xy * distortFactor, fragposition.z);

				vec3 sh = vec3(1.0);
				if (abs(shadowPos.x) < 1.0-0.5/2048. && abs(shadowPos.y) < 1.0-0.5/2048.){
					shadowPos = shadowPos*vec3(0.5,0.5,0.5/6.0)+0.5;

					#ifdef TRANSLUCENT_COLORED_SHADOWS
						sh = vec3(texture(shadowtex0HW, shadowPos).x);

						if(texture(shadowtex1HW, shadowPos).x > shadowPos.z && sh.x < 1.0){
							vec4 translucentShadow = texture(shadowcolor0, shadowPos.xy);
							if(translucentShadow.a < 0.9) sh = normalize(translucentShadow.rgb+0.0001);
						}
					#else
						sh = vec3(texture(shadowtex0HW, shadowPos).x);
					#endif
				}

				sh *= GetCloudShadow(progressW, WsunVec);


			#ifdef PER_BIOME_ENVIRONMENT
				float maxDistance = inBiome * min(max(1.0 -  length(d*dVWorld.xz)/(32*8),0.0)*2.0,1.0);
				float fogDensity = cloudVol(progressW, maxDistance) * inACave * mult;
			#else
				float fogDensity = cloudVol(progressW, 0.0) * inACave * mult;
			#endif

			//------------------------------------
			//------ MAIN FOG EFFECT
			//------------------------------------
			float fogVolumeCoeff = exp(-fogDensity*dd*dL); // this is like beer-lambert law or something

			#ifdef PER_BIOME_ENVIRONMENT
				vec3 indirectLight = mix(skyLightPhased, biomeIndirect, maxDistance);
				vec3 DirectLight = mix(LightSourcePhased, biomeDirect, maxDistance) * sh;
			#else
				vec3 indirectLight = skyLightPhased;
				vec3 DirectLight = LightSourcePhased * sh;
			#endif

			vec3 Lightning = Iris_Lightningflash_VLfog(progressP);
			vec3 lighting = DirectLight + indirectLight + 0.0025 * Lightning;
			
			color += (lighting - lighting * fogVolumeCoeff) * totalAbsorbance;

			// kill fog absorbance when in caves.
			totalAbsorbance *= mix(1.0, fogVolumeCoeff, lightLevelZero);
			
			if(totalAbsorbance < 0.01) break;

			//------------------------------------
			//------ ATMOSPHERE HAZE EFFECT
			//------------------------------------

			// maximum range for atmosphere haze, basically.
			float planetVolume = smoothstep(1.0 - exp(clamp(1.0 - length(progressP) / (16.0*150.0), 0.0,1.0) * -10.0), 0.0, progressP.y-500.0);

			// just air
			vec2 airCoef = exp2(-max(progressW.y-SEA_LEVEL,0.0)/vec2(8.0e3, 1.2e3)*vec2(6.0,7.0)) * 192.0 * Haze_amount * planetVolume;

			// Pbr for air, yolo mix between mie and rayleigh for water droplets
			vec3 rL = rC*airCoef.x;
			vec3 m =  mC*(airCoef.y+min(Haze_amount*1.25,1.0));
			vec3 airDensity = rL + m;

			// calculate the atmosphere haze seperately and purely additive to color, do not contribute to absorbtion.
			vec3 atmosphereVolumeCoeff = exp(-airDensity*dd*dL);
			// vec3 Atmosphere = LightSourcePhased * sh * (rayL*rL + sunPhase*m) + AveragedAmbientColor * (rL+m);
			vec3 Atmosphere = (LightSourcePhased * sh * (rayL*rL + sunPhase*m) + AveragedAmbientColor * airDensity * (lightLevelZero*0.99 + 0.01)) * inACave;
			color += (Atmosphere - Atmosphere * atmosphereVolumeCoeff) / (airDensity+1e-6) * atmosphereAbsorbance;

	
			atmosphereAbsorbance *= atmosphereVolumeCoeff;

			// totalAbsorbance *= dot(atmosphereVolumeCoeff,vec3(0.33333));
		}

		// sceneColor = finalsceneColor;

		// atmosphereAlpha = atmosphereAbsorbance;
		
		return vec4(color, totalAbsorbance);
	}

	vec4 WSRwaterVolumetrics(vec3 origin, vec3 endPos, vec2 dither, vec3 ambient, vec3 lightSource, vec3 LPV){
		if(length(origin-endPos) < 0.001) return vec4(0.0,0.0,0.0,1.0);
		const int SAMPLECOUNT = 3;
		float lightSourceCheck = float(sunElevation > 1e-5)*2.0 - 1.0;

		vec3 waterCoefs = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
		vec3 scatterCoef = Dirt_Amount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / 3.14;

		//project pixel position into projected shadowmap space
		vec3 dVWorld = endPos-origin - gbufferModelViewInverse[3].xyz;

		float rayLength = length(dVWorld);

		float maxLength =  min(rayLength, far)/rayLength;
		
		dVWorld *= maxLength;

		vec3 absorbance = vec3(1.0);
		vec3 vL = vec3(0.0);
		
		#ifdef OVERWORLD_SHADER
			vec3 rayDir = normalize(endPos-origin);
			float VdotL = dot(WsunVec, rayDir);
			float phase = fogPhase(VdotL) * 5.0;
		#else
			const float phase = 0.0;
		#endif

		float thing = -normalize(dVWorld).y;
		thing = clamp(thing + 0.333,0.0,1.0);
		thing = pow(1.0-pow(1.0-thing,2.0),2.0);
		thing *= 15.0;

		const float expFactor = 11.0;
		for (int i=0;i<SAMPLECOUNT;i++) {
			float d = (pow(expFactor, float(i+dither.x)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);		// exponential step position (0-1)
			float dd = pow(expFactor, float(i+dither.y)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);	//step length (derivative)
			
			vec3 progressP = gbufferModelViewInverse[3].xyz + d*dVWorld;
			vec3 progressW = progressP + cameraPosition;
			
			float distanceFromWaterSurface = max(-(progressW.y - waterEnteredAltitude),0.0);

			vec3 sh = vec3(1.0);
			#ifdef OVERWORLD_SHADER
				#ifdef CUSTOM_MOON_ROTATION
					vec3 fragposition = mat3(customShadowMatrixSSBO) * progressP + customShadowMatrixSSBO[3].xyz;
				#else
					vec3 fragposition = mat3(shadowModelView) * progressP + shadowModelView[3].xyz;
				#endif
				fragposition = diagonal3(shadowProjection) * fragposition + shadowProjection[3].xyz;
				#if defined DISTORT_SHADOWMAP && defined OVERWORLD_SHADER
					float distortFactor = calcDistort(fragposition.xy);
				#else
					float distortFactor = 1.0;
				#endif
				vec3 spPos = vec3(fragposition.xy * distortFactor, fragposition.z);

				vec3 pos = vec3(spPos.xy*distortFactor, spPos.z);
				if (abs(pos.x) < 1.0-0.5/2048. && abs(pos.y) < 1.0-0.5/2048){
					pos = pos*vec3(0.5,0.5,0.5/6.0)+0.5;
					// sh = texture( shadowtex0HW, pos).x;

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

			#if defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED && defined LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER
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
	#endif
	float getPhotonicsEmission(vec3 Albedo) {
		vec3 hsv = RgbToHsv(Albedo);
		float emissive = smoothstep(0.05, 0.15, hsv.y) * pow(hsv.z, 3.5);
		return emissive * 0.5;
	}

	void photonicsEmission(
		inout vec3 Lighting,
		vec3 Albedo,
		float Emission
	){
		if( Emission < 254.5/255.0) Lighting = mix(Lighting, Albedo * 5.0 * Emissive_Brightness, pow(Emission, Emissive_Curve));
	}

	void photonicsReflectionShading(inout vec4 color, const in vec3 normal, const in vec3 worldPos, const in float noise, in vec3 DirectLightColor, const in vec3 AmbientLightColor, const in int blockID, const in float skylightmap) {

		float SkylightDir = normal.y;
		SkylightDir = SkylightDir*0.5+0.5;

		vec2 lightmap = vec2(0.0, skylightmap);
		if(abs(blockID-197)  <= 1 || blockID == 242) lightmap.x = 1.0;
		
		float skylight = mix(0.08 + 0.92*(1.0-lightmap.y), 1.0, SkylightDir);
		vec3 Indirect_lighting = doIndirectLighting(AmbientLightColor * skylight, vec3(1.0), lightmap.y);
		vec3 playerPosition = worldPos-cameraPosition;
		Indirect_lighting += doBlockLightLightingVoxel(vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, playerPosition, GetLpvPosition(playerPosition));

		float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(playerPosition) / (shadowDistance+16),0.0)*5.0,1.0));

		float sh = 1.0;
		#if defined OVERWORLD_SHADER || defined END_ISLAND_LIGHT && defined END_SHADER
		sh = ComputePhotonicsShadowMap(DirectLightColor, playerPosition, shadowMapFalloff, noise, normal);

		float lightLeakFix = clamp(pow(eyeBrightnessSmooth.y/240. + lightmap.y, 2.0), 0.0, 1.0);
		sh *= lightLeakFix;
		#endif

		#ifdef OVERWORLD_SHADER
			sh *=  GetCloudShadow(worldPos, WsunVec);
		

		float NdotL = clamp((-15.0 + dot(normal, WsunVec)*255.0) / 240.0, 0.0, 1.0); 
		if(blockID == BLOCK_SSS_STRONG || blockID == BLOCK_SSS_STRONG3 || blockID == BLOCK_AIR_WAVING || blockID == BLOCK_SSS_STRONG_2 ||
		blockID == BLOCK_GROUND_WAVING || blockID == BLOCK_GROUND_WAVING_VERTICAL ||
		blockID == BLOCK_GRASS_SHORT || blockID == BLOCK_GRASS_TALL_UPPER || blockID == BLOCK_GRASS_TALL_LOWER ||
		blockID == BLOCK_SSS_WEAK || blockID == BLOCK_CACTUS || blockID == BLOCK_SSS_WEAK_2 ||
		blockID == BLOCK_CELESTIUM || (blockID >= 269 && blockID <= 274) || blockID == BLOCK_SNOW_LAYERS || blockID == BLOCK_CARPET ||
		blockID == BLOCK_AMETHYST_BUD_MEDIUM || blockID == BLOCK_AMETHYST_BUD_LARGE || blockID == BLOCK_AMETHYST_CLUSTER ||
		blockID == BLOCK_BAMBOO || blockID == BLOCK_SAPLING || blockID == BLOCK_VINE || blockID == BLOCK_VINE_OTHER)
		{
			NdotL = mix(NdotL, 1.0, 0.25);
		}
		#else
		float NdotL = 1.0;
		#endif
		vec3 albedo = color.rgb;
		color.rgb *= Indirect_lighting + DirectLightColor * sh * NdotL;

		float EMISSIVE = 0.0;
		// normal block lightsources
		if(blockID >= 100 && blockID < 282) {
			EMISSIVE = 0.5;
			if(blockID == 266 || (blockID >= 276 && blockID <= 281)) EMISSIVE = 0.2; // sculk stuff
			else if(blockID == 195) EMISSIVE = 2.3; // glow lichen
			else if(blockID == 185) EMISSIVE = 1.5; // crying obsidian
			else if(blockID == 105) EMISSIVE = 2.0; // brewing stand
			
			else if(blockID == 236) EMISSIVE = 1.0; // respawn anchor
			else if(blockID == 101) EMISSIVE = 0.7; // large amethyst bud
			else if(blockID == 103) EMISSIVE = 1.0; // amethyst cluster
			else if(blockID == 244) EMISSIVE = 1.5; // soul fire
			EMISSIVE *= getPhotonicsEmission(albedo);
			EMISSIVE = clamp(EMISSIVE, 0.0, 1.0);
			photonicsEmission(color.rgb, albedo, EMISSIVE);
		}

		#if EMISSIVE_ORES > 0
			if(blockID == 502) {
				EMISSIVE = EMISSIVE_ORES_STRENGTH;
				EMISSIVE *= getPhotonicsEmission(albedo);
				EMISSIVE = clamp(EMISSIVE, 0.0, 1.0);
				photonicsEmission(color.rgb, albedo, EMISSIVE);
			}
		#endif

	}
#endif

vec4 photonicsReflection(
	vec3 reflectedVector,
	vec3 origin,
	vec2 noise,
	vec3 flatNormal,
	inout float backgroundReflectMask,
	inout vec3 backgroundTint
) {
	vec4 color = vec4(0.0);

	#if defined PHOTONICS_INCLUDED && defined PHOTONICS && defined VOXEL_REFLECTIONS
		RayJob ray = RayJob(
			rt_camera_position + origin + 0.005f * flatNormal,
			reflectedVector,
			vec3(0), vec3(0), vec3(0), false
		);

		translucentHit[10] translucentHitRays;
		uint translucentHits = 0u;
		int blockID = 0;

		translucentHitRays[0].hitColor = vec4(0.0);

		float skylightmap = 0.0;

		trace_wsr(ray, true, translucentHitRays, translucentHits, blockID, skylightmap);

		bool hitTranslucent = translucentHits > 0u;
		if(!hitTranslucent && !ray.result_hit) return color;

		vec3 DirectLightColor = lightSourceColorSSBO / 1400.0;
		vec3 AmbientLightColor = averageSkyCol_CloudsSSBO;
		vec3 indirectLightColor = skyGroundColSSBO / 1200.0;

		vec3 indirectLight = AmbientLightColor * skyLightLevelSmooth * ambient_brightness / 1200.0; 
		float minimumLightAmount = 0.02*nightVision + 0.001 * mix(MIN_LIGHT_AMOUNT_INSIDE, MIN_LIGHT_AMOUNT, clamp(skyLightLevelSmooth, 0.0, 1.0));
		indirectLight += vec3(1.0) * minimumLightAmount;
		
		vec3 indirectLight_fog = indirectLightColor * ambient_brightness; 
		indirectLight_fog += vec3(1.0) * (0.02*nightVision + 0.001 * mix(MIN_LIGHT_AMOUNT_INSIDE, MIN_LIGHT_AMOUNT, skyLightLevelSmooth));
		
		#ifdef USE_CUSTOM_DIFFUSE_LIGHTING_COLORS
			DirectLightColor = luma(DirectLightColor) * vec3(DIRECTLIGHT_DIFFUSE_R,DIRECTLIGHT_DIFFUSE_G,DIRECTLIGHT_DIFFUSE_B);
			AmbientLightColor = luma(AmbientLightColor) * vec3(INDIRECTLIGHT_DIFFUSE_R,INDIRECTLIGHT_DIFFUSE_G,INDIRECTLIGHT_DIFFUSE_B);
		#endif

		AmbientLightColor *= ambient_brightness / 900.0;
		
		vec3 endPos = ray.result_position - rt_camera_position;
		vec3 endPosW = endPos + cameraPosition;

		#ifdef TRANSLUCENT_IN_REFLECTIONS
		for (uint i = 0; i < translucentHits; i++) {
			vec4 sampleColor = translucentHitRays[i].hitColor;
			// return vec4(sampleColor.rgb, 1.0);
			
			sampleColor.rgb = toLinear(sampleColor.rgb);

			photonicsReflectionShading(sampleColor, translucentHitRays[i].hitNormal, translucentHitRays[i].hitPos + world_offset, noise.y, DirectLightColor, AmbientLightColor, translucentHitRays[i].hitID, translucentHitRays[i].skylight);
			
			sampleColor.a *= (1.0 - color.a);
			color.rgb += sampleColor.rgb * sampleColor.a;
			color.a += sampleColor.a;

			if(color.a > 0.995) return color;
		}

		if(hitTranslucent) backgroundTint = mix(normalize(translucentHitRays[0].hitColor.rgb+1e-7), vec3(1.0), min(max(0.1-translucentHitRays[0].hitColor.a,0.0) * 10.0,1.0));
		#endif

		if (ray.result_hit) {
			vec4 sampleColor = vec4(toLinear(ray.result_color), 1.0);

			photonicsReflectionShading(sampleColor, ray.result_normal, endPosW, noise.y, DirectLightColor, AmbientLightColor, blockID, skylightmap);

			#if defined VOXEL_REFLECTIONS_FOG && defined OVERWORLD_SHADER && defined TRANSLUCENT_IN_REFLECTIONS
				if(hitTranslucent && isEyeInWater != 1) {
					vec4 fog = raymarchWSRfog(translucentHitRays[0].hitPos + world_offset - cameraPosition, endPos, noise, DirectLightColor, indirectLight_fog, indirectLight, 3);

					sampleColor.rgb = sampleColor.rgb * fog.a;
					sampleColor.rgb += fog.rgb;
				}
			#endif

			sampleColor.rgb *= backgroundTint;

			sampleColor.a *= (1.0 - color.a);
			color.rgb += sampleColor.rgb * sampleColor.a;
			color.a += sampleColor.a;
		}

		#if defined VOXEL_REFLECTIONS_FOG && defined OVERWORLD_SHADER
			#ifdef TRANSLUCENT_IN_REFLECTIONS
			if(hitTranslucent && isEyeInWater != 1) endPos = translucentHitRays[0].hitPos + world_offset - cameraPosition;
			#endif

			vec4 LPVfog = vec4(0.0);
			
			#ifdef VOXEL_REFLECTIONS_LPV_FOG
				LPVfog = raymarchWSR_LPV(origin, endPos, noise.x);				
			#endif

			vec4 fog;
			if(isEyeInWater == 1) {
				fog = WSRwaterVolumetrics(origin, endPos, noise, DirectLightColor, indirectLight, LPVfog.rgb);
			} else {
				fog = raymarchWSRfog(origin, endPos, noise, DirectLightColor, indirectLight_fog, indirectLight, 4);
			}
			
			#ifdef VOXEL_REFLECTIONS_LPV_FOG
				fog.a *= LPVfog.a;
				fog.rgb = fog.rgb * LPVfog.a + LPVfog.rgb;
			#endif

			color.rgb = color.rgb * fog.a;
			color.rgb += fog.rgb;
		#endif
	#endif

	return color;
}

vec4 getEnvironmentReflections(
	vec3 reflectedVector,
	vec3 flatNormal,
	vec3 normal,
	vec3 origin,
	vec3 viewPos,
	vec2 noise,

	bool isHand,
	float roughness,
	inout float backgroundReflectMask,
	inout vec3 backgroundTint
	#ifdef FORWARD_SPECULAR
	,bool isWater
	#endif

){
	vec4 reflection = vec4(0.0);
	float reflectionLength = 0.0;

	float quality = 1.0f;

	#ifdef FORWARD_SPECULAR
		quality = float(FORWARD_SSR_QUALITY);
	#endif

	#ifdef DEFERRED_SPECULAR
		quality = float(DEFERRED_SSR_QUALITY);
	#endif
	vec3 raytracePos = vec3(0.0);
	bool depthCheck = false;
	
	// if (raytracePos.z > 1.001 || distance(gl_FragCoord.xy*texelSize, raytracePos.xy) < 0.002) return reflection;

	#if defined VOXEL_REFLECTIONS && defined PHOTONICS && defined PHOTONICS_INCLUDED
		// raytracePos = rayTraceSpeculars(mat3(gbufferModelView) * reflectedVector, viewPos, noise, quality, isHand, reflectionLength, depthCheck);
		//if(raytracePos.z > 1.0)
		{
			if(dot(reflectedVector, flatNormal) < 0.0) return reflection;
			return photonicsReflection(reflectedVector, origin, noise, flatNormal, backgroundReflectMask, backgroundTint);
		}
	#else
		raytracePos = rayTraceSpeculars(mat3(gbufferModelView) * reflectedVector, viewPos, noise.y, quality, isHand, reflectionLength, depthCheck);
		if (raytracePos.z > 1.00001) return reflection;
	#endif
	
	// use higher LOD as the reflection goes on, to blur it. this helps denoise a little.

	reflectionLength = min(max(reflectionLength - 0.1, 0.0)/0.9, 1.0);

	float LOD = mix(0.0, 6.0*(1.0-exp(-15.0*sqrt(roughness))), 1.0-pow(1.0-reflectionLength,5.0));

	#if (defined VOXY && defined VOXY_REFLECTIONS) || (defined DISTANT_HORIZONS && defined DH_SCREENSPACE_REFLECTIONS)
		mat4 projMatrix = gbufferPreviousProjection;
		if(depthCheck) projMatrix = dhVoxyProjectionPrev;
	#else
		mat4 projMatrix = gbufferPreviousProjection;
	#endif

	vec3 previousPosition = mat3(gbufferModelViewInverse) * toScreenSpace2(raytracePos, depthCheck) + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition);
	previousPosition = mat3(gbufferPreviousModelView) * previousPosition + gbufferPreviousModelView[3].xyz;
	previousPosition.xy = projMAD(projMatrix, previousPosition).xy / -previousPosition.z * 0.5 + 0.5;
	
	if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.y < 1.0) {
		if(raytracePos.z > 0.9999999) backgroundReflectMask = 1.0;

		#if defined OVERWORLD_SHADER
			reflection.a = raytracePos.z > 0.9999999 ? (isHand || isEyeInWater == 1 ? 1.0 : 0.0) : 1.0;
		#else
			reflection.a = 1.0;
		#endif
		
		#ifdef FORWARD_SPECULAR
			// vec2 clampedRes = max(vec2(viewWidth,viewHeight),vec2(1920.0,1080.));
			// vec2 resScale = vec2(1920.,1080.)/clampedRes;
			// vec2 bloomTileUV = (((previousPosition.xy/texelSize)*2.0 + 0.5)*texelSize/2.0) / clampedRes*vec2(1920.,1080.);
			// reflection.rgb = texture(colortex6, bloomTileUV / 4.0).rgb;
			reflection.rgb = texture(colortex5, previousPosition.xy).rgb;
		#else
			reflection.rgb = textureLod(colortex5, previousPosition.xy, LOD).rgb;
		#endif
	}

	// reflection.rgb = vec3(LOD/6);

// vec2 clampedRes = max(vec2(viewWidth,viewHeight),vec2(1920.0,1080.));
// vec2 resScale = vec2(1920.,1080.)/clampedRes;
// vec2 bloomTileUV = (((previousPosition.xy/texelSize)*2.0 + 0.5)*texelSize/2.0) / clampedRes*vec2(1920.,1080.);

// vec2 bloomTileoffsetUV[6] = vec2[](
//  	bloomTileUV / 4.,
//  	bloomTileUV / 8.   + vec2(0.25*resScale.x+2.5*texelSize.x, 		.0),
//  	bloomTileUV / 16.  + vec2(0.375*resScale.x+4.5*texelSize.x, 	.0),
//  	bloomTileUV / 32.  + vec2(0.4375*resScale.x+6.5*texelSize.x, 	.0),
//  	bloomTileUV / 64.  + vec2(0.46875*resScale.x+8.5*texelSize.x,  	.0),
//  	bloomTileUV / 128. + vec2(0.484375*resScale.x+10.5*texelSize.x,	.0)
// );
// // reflectLength = pow(1-pow(1-reflectLength,2),5) * 6;
// reflectLength = (exp(-4*(1-reflectLength))) * 6;
// Reflections.rgb = texture(colortex6, bloomTileoffsetUV[0]).rgb;

	return reflection;
}

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

vec3 specularReflections(

	in vec3 viewPos, // toScreenspace(vec3(screenUV, depth)
	in vec3 playerPos,
	in vec3 NplayerPos, // normalized
    in vec3 lightVec, // light direction in world space
    in vec2 noise, // x = bluenoise y = interleaved gradient noise

	in vec3 flatNormal,
	in vec3 normal, // normals in world space
	in float roughness, // red channel of specular texture _S
	in float f0, // green channel of specular texture _S
	in vec3 albedo, 
	in vec3 diffuseLighting, 
	in vec3 lightColor, // should contain the light's color and shadows.

    in float lightmap, // in anything other than world0, this should be 1.0;
    in bool isHand // mask for the hand

	#ifdef FORWARD_SPECULAR
	, bool isWater
	, inout float reflectanceForAlpha
	#endif
	#ifdef DEFERRED_SPECULAR
	, inout vec4 specularOut
	, inout float SunReflectionAlpha
	, in bool isShaderGrass
	#endif
	
	,in vec4 flashLight_stuff

){
	lightmap = min(max(lightmap-0.9,0.0)/0.1,1.0); 
	lightmap *= lightmap;	lightmap = 1.0-lightmap;
	lightmap *= lightmap;	lightmap = 1.0-lightmap;

	roughness = 1.0 - roughness; 
	roughness *= roughness;

	f0 = f0 == 0.0 ? 0.02 : f0;

// 	if(isHand){
	// f0 = 1.0;
	// roughness = 0.0;
// }
	bool isMetal = f0 > 229.5/255.0;

	// get reflected vector
	mat3 basis = CoordBase(normal);
	vec3 viewDir = -NplayerPos*basis;

	#if defined FORWARD_ROUGH_REFLECTION || defined DEFERRED_ROUGH_REFLECTION
		vec3 samplePoints = SampleVNDFGGX(viewDir, roughness, noise.xy);
		vec3 reflectedVector_L = basis * reflect(-normalize(viewDir), samplePoints);

		reflectedVector_L = isHand ? reflect(NplayerPos, normal) : reflectedVector_L;
	#else
		vec3 reflectedVector_L = reflect(NplayerPos, normal);
	#endif

	#if defined FORWARD_SPECULAR || defined DEFERRED_SPECULAR && !defined DENOISED_REFLECTIONS
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

		#if defined FORWARD_SPECULAR
			reflectanceForAlpha = clamp(dot(F0, vec3(0.3333333)), 0.0,1.0);
					
			#if defined SNELLS_WINDOW
				if(isEyeInWater == 1 && isWater){
					// emulate how mojang did snells window in vibrant visuals because it works nicely tbh
					float snellsWindow = min(max(0.54 - clamp(1.0 + VdotN,0,1),0.)/0.1,1.);
					snellsWindow = 1.0-snellsWindow*snellsWindow;
					snellsWindow *= snellsWindow*snellsWindow;
					reflectanceForAlpha = f0 + (1.0-f0) * snellsWindow;
				}
			#endif
		#endif
	#endif

	vec3 specularReflections = diffuseLighting;

	float reflectionVisibilty = getReflectionVisibility(f0, roughness);
	
	vec4 enviornmentReflection = vec4(0.0);
	float backgroundReflectMask = lightmap;

	#if defined DEFERRED_SPECULAR && defined DENOISED_REFLECTIONS
		SunReflectionAlpha = backgroundReflectMask;
	#endif

	#if (defined DEFERRED_BACKGROUND_REFLECTION || defined FORWARD_BACKGROUND_REFLECTION) || (DEFERRED_SSR_QUALITY > 0 || FORWARD_SSR_QUALITY > 0)
		if(reflectionVisibilty < 1.0){
			#if defined DEFERRED_BACKGROUND_REFLECTION || defined FORWARD_BACKGROUND_REFLECTION
				#if !defined OVERWORLD_SHADER
					vec3 backgroundReflection = volumetricsFromTex(reflectedVector_L, colortex4, roughness).rgb / 1200.0;
				#else
					//vec2 p = sphereToCarte(reflectedVector_L);
					vec3 backgroundReflection = skyCloudsFromTex(reflectedVector_L, colortex4).rgb / 1200.0;
					//vec3 backgroundReflection = imageLoad(reflectionSphere, ivec2(p)).rgb;
									
					#if defined SNELLS_WINDOW
						if(isEyeInWater == 1) backgroundReflection *= exp(-vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B) * 15.0)*2.0;
					#endif
				#endif
			#endif

			#if DEFERRED_SSR_QUALITY > 0 || FORWARD_SSR_QUALITY > 0
				vec3 backgroundTint = vec3(1.0);
				enviornmentReflection = getEnvironmentReflections(reflectedVector_L, flatNormal, normal, playerPos, viewPos, noise, isHand, roughness, backgroundReflectMask, backgroundTint
				#ifdef FORWARD_SPECULAR
				 ,isWater
				#endif
				 );
				#if defined VOXEL_REFLECTIONS && (defined DEFERRED_BACKGROUND_REFLECTION || defined FORWARD_BACKGROUND_REFLECTION)
					backgroundReflection *= backgroundTint;
				#endif
				// darkening for metals.
				vec3 DarkenedDiffuseLighting = isMetal ? diffuseLighting * (1.0-enviornmentReflection.a) * (1.0-lightmap) : diffuseLighting;

				#if defined DEFERRED_SPECULAR && defined DENOISED_REFLECTIONS
					vec3 DarkenedDiffuseLighting2 = isMetal ? vec3(0.0) : diffuseLighting;
				#endif
			#else
				// darkening for metals.
				vec3 DarkenedDiffuseLighting = isMetal ? diffuseLighting * (1.0-lightmap) : diffuseLighting;
			#endif

			// composite all the different reflections together
			#if defined DEFERRED_BACKGROUND_REFLECTION || defined FORWARD_BACKGROUND_REFLECTION
				specularReflections = mix(DarkenedDiffuseLighting, backgroundReflection, backgroundReflectMask);
			#endif

			#if DEFERRED_SSR_QUALITY > 0 || FORWARD_SSR_QUALITY > 0
				specularReflections = mix(specularReflections, enviornmentReflection.rgb, enviornmentReflection.a);
			#endif

			#if defined DEFERRED_SPECULAR && defined DENOISED_REFLECTIONS
				specularOut.rgb = specularReflections;
				SunReflectionAlpha *= 1.0 - enviornmentReflection.a;
				// specularOut.a = 1.0 - enviornmentReflection.a;
				return DarkenedDiffuseLighting2;
			#endif
			#if defined FORWARD_SPECULAR || defined DEFERRED_SPECULAR && !defined DENOISED_REFLECTIONS
				specularReflections = mix(DarkenedDiffuseLighting, specularReflections, F0);

				// lerp back to diffuse lighting if the reflection has not been deemed visible enough
				specularReflections = mix(specularReflections, DarkenedDiffuseLighting, reflectionVisibilty);
			#endif
		}
	#endif
	
	#if defined FORWARD_SPECULAR || defined DEFERRED_SPECULAR && !defined DENOISED_REFLECTIONS
		#if defined OVERWORLD_SHADER && SUN_SPECULAR_MULT > 0
			vec3 lightSourceReflection = backgroundReflectMask*SUN_SPECULAR_MULT * lightColor * GGX(normal, -NplayerPos, lightVec, roughness, reflectance, metalAlbedoTint);
			#if DEFERRED_SSR_QUALITY > 0 || FORWARD_SSR_QUALITY > 0
				specularReflections += lightSourceReflection * (1.0 - enviornmentReflection.a);
			#else
				specularReflections += lightSourceReflection;
			#endif
		#endif

		#if defined FLASHLIGHT_SPECULAR && (defined DEFERRED_SPECULAR || defined FORWARD_SPECULAR)
			vec3 flashLightReflection = vec3(FLASHLIGHT_R,FLASHLIGHT_G,FLASHLIGHT_B) * flashLight_stuff.a * GGX(normal, -flashLight_stuff.xyz, -flashLight_stuff.xyz, roughness, reflectance, metalAlbedoTint);
			specularReflections += flashLightReflection;
		#endif

		#if defined Hand_Held_lights && defined IS_LPV_ENABLED && HANDHELD_LIGHT_REFLECTIONS > 0
			if(!isHand && firstPersonCamera
				#ifdef DEFERRED_SPECULAR
				&& !isShaderGrass
				#endif
			 ) {
			if (heldItemId > 0){
				vec3 shiftedViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
				vec3 shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition);

				float lightRange = 0.0;
				vec3 handLightCol = GetHandLight(heldItemId, shiftedPlayerPos, lightRange);

				if(lightRange > 0.0) {
				vec3 handheldReflection = handLightCol * GGX(normal, -shiftedPlayerPos, -shiftedPlayerPos, roughness, reflectance, metalAlbedoTint);
				specularReflections += handheldReflection*HANDHELD_LIGHT_REFLECTIONS*0.005;
				}
			}

			if (heldItemId2 > 0){
				vec3 shiftedViewPos = viewPos + vec3(0.25, 0.2, 0.0);
				vec3 shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition);

				float lightRange = 0.0;
				vec3 handLightCol = GetHandLight(heldItemId2, shiftedPlayerPos, lightRange);

				if(lightRange > 0.0) {
				vec3 handheldReflection = handLightCol * GGX(normal, -shiftedPlayerPos, -shiftedPlayerPos, roughness, reflectance, metalAlbedoTint);
				specularReflections += handheldReflection*HANDHELD_LIGHT_REFLECTIONS*0.005;
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
					specularReflections += handheldReflection*HANDHELD_LIGHT_REFLECTIONS*0.005;
				}
				}
			#endif
			}
		#endif
	#endif

	return specularReflections;
}