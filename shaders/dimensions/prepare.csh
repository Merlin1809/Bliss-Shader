#include "/lib/settings.glsl"
layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

const ivec3 workGroups = ivec3(1, 1, 1);

uniform vec3 previousCameraPosition;

#include "/lib/util.glsl"
uniform vec3 cameraPosition;
uniform vec3 relativeEyePosition;

#include "/lib/blocks.glsl"
#include "/lib/entities.glsl"
#include "/lib/lpv_common.glsl"
#include "/lib/lpv_blocks.glsl"
#include "/lib/lpv_buffer.glsl"
#include "/lib/voxel_common.glsl"

uint GetVoxelBlock(const in ivec3 voxelPos) {
    if (clamp(voxelPos, ivec3(0), ivec3(VoxelSize3-1u)) != voxelPos)
        return BLOCK_EMPTY;
    
    return imageLoad(imgVoxelMask, voxelPos).r % 2000u;
}

#include "/lib/SSBOs.glsl"

uniform bool is_sneaking;
uniform float frameTimeCounter;
uniform float frameTime;

#if IRIS_VERSION >= 11004
    uniform bool onWaterSurface;
    uniform int vehicleId;
    uniform bool vehicleInWater;
    uniform bool feetInWater;
    uniform vec3 relativeVehiclePosition;
    uniform bool isRiding;
#endif

vec2 getPlayerMovementOffset() {
    vec2 currentPos = cameraPosition.xz;

    #if IRIS_VERSION >= 11004
    if(isRiding) {
        currentPos -= relativeVehiclePosition.xz;
    } else
    #endif
    {
        currentPos -= relativeEyePosition.xz;
    }

    vec2 previousPos = previousCameraPositionWave2.xz;
    vec2 movement = currentPos - previousPos;
    #if WATER_SIM_SCALE == 0
        return -20.0 * movement;
    #else
        return -40.0 * movement * WATER_SIM_SCALE;
    #endif
}

void main() {
    #if WATER_INTERACTION == 2
    if (abs(frameTimeCounter - lastFrameTimeCount) > WATER_SIM_FRAMETIME) {
        noSimOngoing = noSimOngoingCheck;
        noSimOngoingCheck = true;

        #if IRIS_VERSION >= 11004
            bool inBoat = vehicleId == ENTITY_BOAT;

            bool inShip = false;
        #else
            float playerTallness = 1.5;
            if(is_sneaking) playerTallness = 1.2;
            #if !defined IS_LPV_ENABLED && !defined SHADER_GRASS
                vec3 rayStart = vec3(0.0);
            #else
                vec3 rayStart = vec3(-relativeEyePosition);
            #endif
            vec3 LPVpos = GetLpvPosition2(rayStart);
            uint BlockID1 = GetVoxelBlock(ivec3(LPVpos));
            uint BlockID2 = GetVoxelBlock(ivec3(LPVpos.x, LPVpos.y - 0.5*playerTallness, LPVpos.z));
            uint BlockID3 = GetVoxelBlock(ivec3(LPVpos.x, LPVpos.y - playerTallness, LPVpos.z));

            // Big shenanigans lol, don't ask, it just works
            bool inShip = false;
            onWaterSurface = false;
            bool inBoat = false;
            bool inBoat2Frames = inBoatLastFrame;
            inBoatLastFrame = inBoatCurrentFrame;
            inBoatCurrentFrame = false;

            bool inShip2Frames = inShipLastFrame;
            inShipLastFrame = inShipCurrentFrame;
            inShipCurrentFrame = false;

            if(BlockID1 == BLOCK_WATER || BlockID2 == BLOCK_WATER || BlockID3 == BLOCK_WATER) onWaterSurface = true;

            if(BlockID1 == ENTITY_BOAT || BlockID2 == ENTITY_BOAT || BlockID3 == ENTITY_BOAT) inBoatCurrentFrame = true;

            if(BlockID1 == ENTITY_SMALLSHIPS || BlockID2 == ENTITY_SMALLSHIPS || BlockID3 == ENTITY_SMALLSHIPS) inShipCurrentFrame = true;

            if(inBoatCurrentFrame || inBoatLastFrame || inBoat2Frames) inBoat = true;

            if(inShipCurrentFrame || inShipLastFrame || inShip2Frames) inShip = true;
        #endif

        vec2 playerMovement = getPlayerMovementOffset();
        water_move_compensation_counter_SSBO += playerMovement;

        water_move_compensationSSBO = ivec2(0);
        ivec2 offset = ivec2(trunc(water_move_compensation_counter_SSBO));
        if (any(notEqual(offset, ivec2(0)))) {
            water_move_compensationSSBO = offset;
            water_move_compensation_counter_SSBO -= vec2(offset);
        }

        if (onWaterSurface) {
            vec3 position = cameraPosition-previousCameraPositionWave;
            #if IRIS_VERSION >= 11004
            if(isRiding) {
                position -= relativeVehiclePosition;
            } else
            #endif
            {
                position -= relativeEyePosition;
            }
            
            vec3 velocity = position/frameTime;
            velocity.y *= 1.2;
            float speed = length(velocity);

            float size = 10.0;
            #if IRIS_VERSION >= 11004
                if(inBoat) {
                    size += 23.0;
                } else if (inShip) {
                    size += 61.0 * smoothstep(0.0, 10.0, speed);
                } else {
                    size += 10.0 * smoothstep(0.1, 13.0, speed);
                }
            #else
                if(inBoat) {
                    size += 26.0 * smoothstep(0.0, 10.0, speed);
                } else if (inShip) {
                    size += 61.0 * smoothstep(0.0, 10.0, speed);
                } else {
                    size += 10.0 * smoothstep(0.1, 13.0, speed);
                }
            #endif

            #if WATER_SIM_SCALE == 0
                size *= 0.5;
            #else
                size *= WATER_SIM_SCALE;
            #endif

            #if IRIS_VERSION >= 11004
            if(speed < 0.15 && isRiding) size = 0.01;
            #endif

            waterRoundSize = size;
        }
    }
    #endif
}