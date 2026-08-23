#ifdef RENDER_SHADOW
	#if defined BEACON_FLOODFILL && defined IS_LPV_ENABLED
		layout(r32ui) uniform uimage3D imgVoxelMask;
	#else
		layout(r16ui) uniform uimage3D imgVoxelMask;
	#endif
	// layout(r8ui) uniform uimage3D imgQuarterVoxelMask;
// 
	// layout(std430, binding = 5) buffer voxelSSBO {
	// 	vec4[6] voxelData[];
	// };  
#else
	#if defined BEACON_FLOODFILL && defined IS_LPV_ENABLED
		layout(r32ui) uniform readonly uimage3D imgVoxelMask;
	#else
		layout(r16ui) uniform readonly uimage3D imgVoxelMask;
	#endif
	// layout(r8ui) uniform readonly uimage3D imgQuarterVoxelMask;
// 
	// layout(std430, binding = 5) readonly buffer voxelSSBO {
	// 	vec4[6] voxelData[];
	// };  
#endif

#if defined IS_LPV_ENABLED || defined SHADER_GRASS
	const uint VoxelSize = uint(exp2(LPV_SIZE));
	const uvec3 VoxelSize3 = uvec3(VoxelSize);
#else
	const uint VoxelSize = uint(5);
	const uvec3 VoxelSize3 = uvec3(VoxelSize);
#endif

#define BLOCK_EMPTY 0
