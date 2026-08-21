ivec3 GetVoxelIndex(const in vec3 playerPos) {
	#if !defined IS_LPV_ENABLED && !defined SHADER_GRASS
		vec3 cameraOffset = fract(cameraPosition-relativeEyePosition);
	#else
		vec3 cameraOffset = fract(cameraPosition);
	#endif
	return ivec3(floor(playerPos + cameraOffset) + VoxelSize3/2u);
}

// ivec3 GetVoxelIndex2(const in vec3 playerPos) {
// 	#if !defined IS_LPV_ENABLED && !defined SHADER_GRASS
// 		vec3 cameraOffset = fract(cameraPositionFract-relativeEyePosition);
// 	#else
// 		vec3 cameraOffset = fract(cameraPositionFract);
// 	#endif
// 	return ivec3(floor(playerPos + cameraOffset) + VoxelSize3/8u);
// }

void SetVoxelBlock(const in ivec3 voxelPos, const in uint blockId) {
	if (clamp(voxelPos, ivec3(0), ivec3(VoxelSize-1u)) != voxelPos) return;
	
	// imageStore(imgQuarterVoxelMask, voxelPos / 4, uvec4(1u));

	imageStore(imgVoxelMask, voxelPos, uvec4(blockId));
}

// #ifdef SAVE_VOXEL_STUFF
// int voxelIndex(ivec3 voxelPos) {
//     return voxelPos.x + voxelPos.y * int(VoxelSize) + voxelPos.z * int(VoxelSize*VoxelSize);
// }
// 
// int voxelNormalIndex(vec3 voxelNormal) {
// 	return clamp(int(abs(voxelNormal.x)*(voxelNormal.x*0.5+0.5) + abs(voxelNormal.y)*(voxelNormal.y*0.5+2.5) + abs(voxelNormal.z)*(voxelNormal.z*0.5+4.5) + 0.5), 0, 5);
// }
// 
// float encodeVec2_16(vec2 a){
//     const vec2 constant1 = vec2( 1., 65536.) / 4294967295.;
//     vec2 temp = floor( a * 65535. );
// 	return temp.x*constant1.x+temp.y*constant1.y;
// }
// 
// float encodeVec2_16(float a, float b){
//     return encodeVec2_16(vec2(a,b));
// }
// 
// vec2 decodeVec2_16(float a){
//     const vec2 constant1 = 4294967294. / vec2( 65536., 4294967295.);
//     const float constant2 = 65536. / 65535.;
//     return fract( a * constant1 ) * constant2 ;
// }
// 
// void SaveVoxelData(const in ivec3 voxelPos, in vec2 midTex, in vec2 lightcoord, const in uint voxelId, in vec3 originPos) {
// 	if (clamp(voxelPos, ivec3(0), ivec3(VoxelSize-1u)) != voxelPos) return;
// 
// 	if(voxelId > 0u) {
// 		vec3 worldNormal = viewToWorld(normalize(gl_NormalMatrix * gl_Normal));
// 		float fractYpos = fract(originPos.y+cameraPosition.y);
// 		float xzLength = length(fract(originPos.xz+cameraPosition.xz) - vec2(0.5));
// 		
// 		if(voxelId == BLOCK_HOPPER && (dot(at_midBlock.xz, worldNormal.xz) < 0.0 || abs(worldNormal.y) > 0.001)
// 		 || voxelId == BLOCK_END_PORTAL_FRAME && xzLength < 0.4
// 		 || voxelId == BLOCK_GRASS && alphaTestRef >= 0.1
// 		 || voxelId >= 22 && voxelId < 38 && fractYpos < 0.99 && fractYpos > 0.01
// 		 || (voxelId == BLOCK_LANTERN || voxelId == BLOCK_SOUL_LANTERN || voxelId == BLOCK_COPPER_LANTERN) && xzLength < 0.185
// 		 || voxelId == 419 && (xzLength > 0.501 || abs(worldNormal.x) < 0.99)
// 		) return;
// 
// 		float encodedRB = encodeVec2(gl_Color.rb);
// 		vec2 _color = vec2(encodedRB, gl_Color.g);
// 
// 		midTex.r = encodeVec2_16(midTex);
// 		midTex.g = encodeVec2(lightcoord);
// 
// 		if(voxelId == 419 || voxelId == BLOCK_HOPPER || voxelId == 178 || voxelId >= 11 && voxelId <= 21 || voxelId == BLOCK_LPV_MIN || voxelId == BLOCK_GROUND_WAVING || voxelId > 300 && voxelId < 335 || voxelId >= BLOCK_SSS_STRONG3 && voxelId <= 87 || (voxelId >= 22 && voxelId < 38 && abs(worldNormal.y) < 0.01)) {
// 			voxelData[voxelIndex(voxelPos)][0] = vec4(midTex, _color);
// 			voxelData[voxelIndex(voxelPos)][1] = vec4(midTex, _color);
// 			voxelData[voxelIndex(voxelPos)][2] = vec4(midTex, _color);
// 			voxelData[voxelIndex(voxelPos)][3] = vec4(midTex, _color);
// 			voxelData[voxelIndex(voxelPos)][4] = vec4(midTex, _color);
// 			voxelData[voxelIndex(voxelPos)][5] = vec4(midTex, _color);
// 		}
// 		else
// 			voxelData[voxelIndex(voxelPos)][voxelNormalIndex(worldNormal)] = vec4(midTex, _color);
// 
// 	}
// }
// #endif

void PopulateShadowVoxel(const in vec3 playerPos) {
	uint voxelId = 0u;
	vec3 originPos = playerPos;

	if (
		#ifdef COLORWHEEL
			renderStage == CLRWL_RENDER_STAGE_SOLID || renderStage == CLRWL_RENDER_STAGE_TRANSLUCENT 
		#else
			renderStage == MC_RENDER_STAGE_TERRAIN_SOLID || renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT ||
			renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED
		#endif
	)
	{
		float blockID = mc_Entity.x;

		#ifdef COLORWHEEL
			if(mc_Entity.x < 0.0) blockID = blockEntityId;
		#endif

		voxelId = uint(blockID + 0.5);

		#ifdef IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
			if (voxelId == 0u && at_midBlock.w > 0) voxelId = uint(BLOCK_LIGHT_1 + at_midBlock.w - 1);
		#endif

		if (voxelId == 0u) voxelId = 1u;

		originPos += at_midBlock.xyz/64.0;

		// #ifdef SAVE_VOXEL_STUFF
		// 	SaveVoxelData(GetVoxelIndex(originPos), mc_midTexCoord.xy, gl_MultiTexCoord1.xy / 240.0, voxelId, playerPos);
		// #endif
	}

	#if !defined IS_LPV_ENABLED && !defined SHADER_GRASS
		ivec3 voxelPos = GetVoxelIndex(originPos+relativeEyePosition);
	#else
		ivec3 voxelPos = GetVoxelIndex(originPos);
	#endif
	
	#if defined LPV_ENTITY_LIGHTS && !defined COLORWHEEL
		if (
			((renderStage == MC_RENDER_STAGE_ENTITIES && (currentRenderedItemId > 0 || entityId > 0)) || renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES)
		) {
			if (renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES) {
				if (blockEntityId > 0 && blockEntityId < 500 && blockEntityId != BLOCK_ENCHANTING_TABLE)
					voxelId = uint(blockEntityId);
			}
			else if (currentRenderedItemId > 100 && currentRenderedItemId < 276) {
				#if MC_VERSION > 12100 && ((MC_VERSION != 12109 && MC_VERSION != 12110) || IRIS_VERSION >= 10907)
				if (entityId != ENTITY_ITEM_FRAME && entityId != ENTITY_CURRENT_PLAYER && entityId != ENTITY_GLOW_ITEM_FRAME)
				#else
				if (entityId != ENTITY_ITEM_FRAME && entityId != ENTITY_PLAYER && entityId != ENTITY_GLOW_ITEM_FRAME)
				#endif
				{
					voxelId = uint(currentRenderedItemId);

					// offset by a random number that came into my head to make entities and items not interact with shader grass
					voxelId += 2000u;

					#if defined SHADER_GRASS && REPLACE_SHORT_GRASS < 2
						uint oldID = imageLoad(imgVoxelMask, voxelPos).r;
						if(oldID == 12u) voxelId += 2000u;
					#endif
				}
			}
			else {
				switch (entityId) {
					case ENTITY_BLAZE:
					case ENTITY_END_CRYSTAL:
					// case ENTITY_FIREBALL_SMALL:
					case ENTITY_GLOW_SQUID:
					case ENTITY_MAGMA_CUBE:
					case ENTITY_SPECTRAL_ARROW:
					case ENTITY_TNT:
						voxelId = uint(entityId)+2000u;
						break;
				}
			}
		}
	#endif

	#if WATER_INTERACTION == 2 && !defined COLORWHEEL && IRIS_VERSION < 11004
		if (
			((renderStage == MC_RENDER_STAGE_ENTITIES && (currentRenderedItemId > 0 || entityId > 0)) || renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES)
		) {
			switch (entityId) {
				case ENTITY_BOAT:
				case ENTITY_SMALLSHIPS:
					voxelId = uint(entityId)+2000u;
					break;
			}
		}
	#endif

	if (voxelId > 0u){
		SetVoxelBlock(voxelPos, voxelId);
	}
		
}