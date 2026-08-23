layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;

#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"

#include "/lib/SSBOs.glsl"

uniform vec2 texelSize;
uniform int framemod8;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
#include "/lib/TAA_jitter.glsl"


in DATA {
    vec4 color;
    vec2 texcoord;
} data_in[];


out DATA {
    vec4 color;
    vec2 texcoord;
} data_out;

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec4 toClipSpace3(vec3 viewSpacePosition) {
    return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition),-viewSpacePosition.z);
}

uniform vec3 cameraPosition;
uniform vec3 relativeEyePosition;

#define RENDER_SHADOW

#include "/lib/voxel_common.glsl"

ivec3 GetVoxelIndex(const in vec3 playerPos) {
	#if !defined IS_LPV_ENABLED && !defined SHADER_GRASS
		vec3 cameraOffset = fract(cameraPosition-relativeEyePosition);
	#else
		vec3 cameraOffset = fract(cameraPosition);
	#endif
	return ivec3(floor(playerPos + cameraOffset) + VoxelSize3/2u);
}

void SetVoxelBlock(const in ivec3 voxelPos, const in uint blockId) {
	if (clamp(voxelPos.y, int(0), int(VoxelSize-1u)) != voxelPos.y) return;
	
	// imageStore(imgQuarterVoxelMask, voxelPos / 4, uvec4(1u));

	imageStore(imgVoxelMask, voxelPos, uvec4(blockId));
}

int packColor(vec3 color) {
    int ri = int(round(clamp(color.r, 0.0, 1.0) * 100.0));
    int gi = int(round(clamp(color.g, 0.0, 1.0) * 100.0));
    int bi = int(round(clamp(color.b, 0.0, 1.0) * 100.0));

    int index = (ri * 101 + gi) * 101 + bi;
    return 50000 + index;
}

vec3 UnpackColor(int packedC) {
    int idx = packedC - 50000;
    if (idx < 0) return vec3(-1.0);

    int b = idx % 101;
    idx /= 101;
    int g = idx % 101;
    idx /= 101;
    int r = idx % 101;

    return vec3(r / 100.0, g / 100.0, b / 100.0);
}


void main() {

    #if defined BEACON_FLOODFILL && defined IS_LPV_ENABLED
        float h0 = gl_in[0].gl_Position.y;
        float h1 = gl_in[1].gl_Position.y;
        float h2 = gl_in[2].gl_Position.y;

        float yStart = min(h0, min(h1, h2));

        bool isBottom0 = abs(h0 - yStart) < 1e-5;
        bool isBottom1 = abs(h1 - yStart) < 1e-5;
        bool isBottom2 = abs(h2 - yStart) < 1e-5;


        if(int(isBottom0) + int(isBottom1) + int(isBottom2) == 1) {
            int bottomIndex = isBottom0 ? 0 : (isBottom1 ? 1 : 2);
            if(data_in[bottomIndex].color.a < 1.0) {
                vec3 playerPos = gl_in[bottomIndex].gl_Position.xyz;
                
                vec3 edge1 = gl_in[1].gl_Position.xyz - gl_in[0].gl_Position.xyz;
                vec3 edge2 = gl_in[2].gl_Position.xyz - gl_in[0].gl_Position.xyz;
                vec3 flatNormals = normalize(cross(edge1, edge2));

                if(flatNormals.x > 0.5) {
                    playerPos.y += 0.5;

                    ivec3 voxelPos = GetVoxelIndex(playerPos);

                    if (clamp(voxelPos.xz, ivec2(0), ivec2(VoxelSize-1u)) == voxelPos.xz) {
                        float yEnd = max(h0, max(h1, h2));
                        int blocks = int(yEnd - yStart - 0.5);
                        vec4 vcolor = data_in[bottomIndex].color;
                        vec3 color = vcolor.rgb * vcolor.rgb;

                        int j;
                        for (j = 0; j < blocks; j++) {
                            SetVoxelBlock(voxelPos, packColor(color));
                            voxelPos.y += 1;
                            if(voxelPos.y > int(VoxelSize) - 1) break;
                        }
                    }
                }
            }
        }
    #endif

    int i;
    for (i = 0; i < 3; i++) {
		vec4 vertex = gl_in[i].gl_Position;

        data_out.color = data_in[i].color;

        data_out.texcoord = data_in[i].texcoord;

        gl_Position = vertex;

        vertex.rgb = mat3(gbufferModelView) * vertex.rgb + gbufferModelView[3].xyz;

		gl_Position = toClipSpace3(vertex.rgb);


        if(data_in[i].color.a < 1.0) gl_Position = vec4(10,10,10,0);

        #ifdef TAA_UPSCALING
            gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
        #endif
        #ifdef TAA
            gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
        #endif


		EmitVertex();
	}
	EndPrimitive();

}