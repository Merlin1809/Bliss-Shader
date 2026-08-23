#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

out DATA {
    vec4 color;
    vec2 texcoord;
};

uniform vec2 texelSize;
uniform int framemod8;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
#include "/lib/TAA_jitter.glsl"


#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec4 toClipSpace3(vec3 viewSpacePosition) {
    return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition),-viewSpacePosition.z);
}
					
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

// uniform sampler2D colortex4;

void main() {
	color = gl_Color;

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;

	vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;

	vec3 playerPos = mat3(gbufferModelViewInverse) * position + gbufferModelViewInverse[3].xyz;

	#if defined PLANET_CURVATURE
		float curvature = length(playerPos.xz) / (16.0*8.0);
		playerPos.y -= curvature*curvature * CURVATURE_AMOUNT;
	#endif

	#ifdef BEACON_BEAM
		gl_Position = vec4(playerPos, 1.0);
	#else
		position = mat3(gbufferModelView) * playerPos + gbufferModelView[3].xyz;

		gl_Position = toClipSpace3(position);

		#ifdef TAA_UPSCALING
			gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
		#endif
		#ifdef TAA
			gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
		#endif
	#endif
}
