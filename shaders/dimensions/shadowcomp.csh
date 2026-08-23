#define RENDER_SHADOWCOMP

layout (local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

#if   LPV_SIZE == 8
    const ivec3 workGroups = ivec3(32, 32, 32);
#elif LPV_SIZE == 7
    const ivec3 workGroups = ivec3(16, 16, 16);
#elif LPV_SIZE == 6
    const ivec3 workGroups = ivec3(8, 8, 8);
#endif

#ifdef IS_LPV_ENABLED
    shared vec4 lpvSharedData[10*10*10];
    shared uint voxelSharedData[10*10*10];

    const vec2 LpvBlockSkyFalloff = vec2(0.96, 0.96);
    const ivec3 lpvFlatten = ivec3(1, 10, 100);

    uniform int frameCounter;
    uniform vec3 cameraPosition;
    uniform vec3 previousCameraPosition;

    #include "/lib/hsv.glsl"
    #include "/lib/util.glsl"
    #include "/lib/blocks.glsl"
    #include "/lib/entities.glsl"
    #include "/lib/lpv_common.glsl"
    #include "/lib/lpv_blocks.glsl"
    #include "/lib/lpv_buffer.glsl"
    #include "/lib/voxel_common.glsl"

    int sumOf(ivec3 vec) {return vec.x + vec.y + vec.z;}

    int getSharedIndex(ivec3 pos) {
        return sumOf(pos * lpvFlatten);
    }

    vec4 GetLpvValue(in ivec3 texCoord) {
        if (clamp(texCoord, ivec3(0), ivec3(LpvSize) - 1) != texCoord) return vec4(0.0);

        vec4 lpvSample = (frameCounter % 2) == 0
            ? imageLoad(imgLpv2, texCoord)
            : imageLoad(imgLpv1, texCoord);

        vec4 hsv_sky = vec4(RgbToHsv(lpvSample.rgb), lpvSample.a);
        hsv_sky.zw = exp2(hsv_sky.zw * LpvBlockSkyRange) - 1.0;
        lpvSample = vec4(HsvToRgb(hsv_sky.xyz), hsv_sky.w);

        return lpvSample;
    }
    
    uint GetVoxelBlock(const in ivec3 voxelPos) {
        if (clamp(voxelPos, ivec3(0), ivec3(VoxelSize3-1u)) != voxelPos)
            return BLOCK_EMPTY;

        uint blockId = imageLoad(imgVoxelMask, voxelPos).r;

        #ifdef BEACON_FLOODFILL
            if(blockId >= 50000u) return blockId;
        #endif

        blockId = blockId % 2000u;

        #if IRIS_VERSION < 11004
            if (blockId == ENTITY_BOAT || blockId == ENTITY_SMALLSHIPS) return BLOCK_EMPTY;
        #endif
                
        return blockId;
    }

    void PopulateSharedIndex(const in ivec3 imgCoordOffset, const in ivec3 workGroupOffset, const in uint i) {
        ivec3 pos = workGroupOffset + ivec3(i / lpvFlatten) % 10;

        lpvSharedData[i] = GetLpvValue(imgCoordOffset + pos);
        voxelSharedData[i] = GetVoxelBlock(pos);
    }

    vec4 sampleShared(ivec3 pos, int mask_index) {
        int shared_index = getSharedIndex(pos + 1);

        float mixWeight = 1.0;
        uint mask = 0xFFFF;
        uint blockId = voxelSharedData[shared_index];
        
        if (blockId > 0 && blockId < 2048) {
            uvec2 blockData = imageLoad(imgBlockData, int(blockId)).rg;
            mask = (blockData.g >> 24) & 0xFFFF;
        }

        return lpvSharedData[shared_index] * ((mask >> mask_index) & 1u);
    }

    vec4 mixNeighbours(const in ivec3 fragCoord, const in uint mask) {
        uvec3 m1 = (uvec3(mask) >> uvec3(0, 2, 4)) & uvec3(1u);
        uvec3 m2 = (uvec3(mask) >> uvec3(1, 3, 5)) & uvec3(1u);

        vec4 sX1 = sampleShared(fragCoord + ivec3(-1,  0,  0), 1) * m1.x;
        vec4 sX2 = sampleShared(fragCoord + ivec3( 1,  0,  0), 0) * m2.x;
        vec4 sY1 = sampleShared(fragCoord + ivec3( 0, -1,  0), 3) * m1.y;
        vec4 sY2 = sampleShared(fragCoord + ivec3( 0,  1,  0), 2) * m2.y;
        vec4 sZ1 = sampleShared(fragCoord + ivec3( 0,  0, -1), 5) * m1.z;
        vec4 sZ2 = sampleShared(fragCoord + ivec3( 0,  0,  1), 4) * m2.z;

        const vec4 avgFalloff = (1.0/6.0) * LpvBlockSkyFalloff.xxxy;
        return (sX1 + sX2 + sY1 + sY2 + sZ1 + sZ2) * avgFalloff;
    }
#endif

vec3 UnpackColor(uint packedC) {
    int idx = int(packedC) - 50000;

    int b = idx % 101;
    idx /= 101;
    int g = idx % 101;
    idx /= 101;
    int r = idx % 101;

    return vec3(r / 100.0, g / 100.0, b / 100.0);
}

////////////////////////////// VOID MAIN //////////////////////////////

void main() {
    #ifdef IS_LPV_ENABLED
        uvec3 chunkPos = gl_WorkGroupID * gl_WorkGroupSize;
        if (any(greaterThanEqual(chunkPos, LpvSize3))) return;

        // Pre-populate shared-memory buffer for improved sampling performance
        uint i = uint(gl_LocalInvocationIndex) * 2u;
        if (i < 1000u) {
            ivec3 imgCoordOffset = ivec3(floor(cameraPosition) - floor(previousCameraPosition));
            ivec3 workGroupOffset = ivec3(gl_WorkGroupID * gl_WorkGroupSize) - 1;

            PopulateSharedIndex(imgCoordOffset, workGroupOffset, i);
            PopulateSharedIndex(imgCoordOffset, workGroupOffset, i + 1u);
        }

        barrier();

        // Exit early if outside LPV buffer size
        ivec3 imgCoord = ivec3(gl_GlobalInvocationID);
        if (any(greaterThanEqual(imgCoord, LpvSize3))) return;

        vec4 lightValue = vec4(0.0);
        vec3 lightColor = vec3(0.0);
        vec3 tintColor = vec3(1.0);
        float lightRange = 0.0;
        uint mixMask = 0xFFFF;
    
        // Decode light data for current voxel
        uint blockId = voxelSharedData[getSharedIndex(ivec3(gl_LocalInvocationID) + 1)];

        if (blockId > 0u && blockId < 2048u) {
            uvec2 blockData = imageLoad(imgBlockData, int(blockId)).rg;
            vec4 lightColorRange = unpackUnorm4x8(blockData.r);
            lightColor = srgbToLinear(lightColorRange.rgb);
            lightRange = lightColorRange.a * 255.0;
            vec4 tintColorMask = unpackUnorm4x8(blockData.g);
            tintColor = srgbToLinear(tintColorMask.rgb);
            mixMask = (blockData.g >> 24) & 0xFFFF;
        }
        #ifdef BEACON_FLOODFILL
        else if(blockId >= 50000u) {
            lightColor = BEACON_FLOODFILL_BRIGHTNESS * 17.0 * srgbToLinear(UnpackColor(blockId));

            lightRange = 0.0425 * 255.0;
            tintColor = vec3(1.0);
            mixMask = 0xFFFF;
        }
        #endif

        // Mix neighbor voxel light values
        if (any(greaterThan(tintColor, vec3(0.0)))) {
            vec4 lightMixed = mixNeighbours(ivec3(gl_LocalInvocationID), mixMask);
            lightMixed.rgb *= tintColor;
            lightValue += lightMixed;
        }

        // Add light for current voxel
        if (lightRange > 0.0) {
            vec3 hsv = RgbToHsv(lightColor);
            #ifdef BEACON_FLOODFILL
            if(blockId < 50000u)
            #endif
            {
                hsv.z = exp2(lightRange) - 1.0;
            }
            lightValue.rgb += HsvToRgb(hsv);
        }

        // Convert back to linear RGB space
        vec4 hsv_sky = vec4(RgbToHsv(lightValue.rgb), lightValue.a);
        hsv_sky.zw = log2(hsv_sky.zw + 1.0) / LpvBlockSkyRange;
        lightValue = vec4(HsvToRgb(hsv_sky.xyz), hsv_sky.w);

        // Store final value
        if (frameCounter % 2 == 0)
            imageStore(imgLpv1, imgCoord, lightValue);
        else
            imageStore(imgLpv2, imgCoord, lightValue);
    #endif
}
