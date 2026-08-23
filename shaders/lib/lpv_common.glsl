// How far light propagates (block, sky)
const vec2 LpvBlockSkyRange = vec2(15.0, 24.0);

#if defined IS_LPV_ENABLED || defined SHADER_GRASS
	const uint LpvSize = uint(exp2(LPV_SIZE));
	const uvec3 LpvSize3 = uvec3(LpvSize);
#else
	const uint LpvSize = uint(5);
	const uvec3 LpvSize3 = uvec3(LpvSize);
#endif

vec3 GetLpvPosition(const in vec3 playerPos) {
    vec3 cameraOffset = cameraPosition - floor(previousCameraPosition);
    return playerPos + cameraOffset + LpvSize3/2u;
}

vec3 GetLpvPosition2(const in vec3 playerPos) {
    #if !defined IS_LPV_ENABLED && !defined SHADER_GRASS
	    vec3 cameraOffset = fract(cameraPosition-relativeEyePosition);
    #else
        vec3 cameraOffset = fract(cameraPosition);
    #endif
    return playerPos + cameraOffset + LpvSize3/2u;
}
