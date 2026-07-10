#include "/lib/settings.glsl"

#include "/lib/SSBOs.glsl"

uniform sampler2D colortex7;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex14;
uniform sampler2D colortex15;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;
uniform sampler2D noisetex;
uniform sampler2D shadowcolor1;

// #if !defined IS_IRIS || (defined SHADER_GRASS_SETTING && MC_VERSION < 12101 && !defined SHADER_GRASS_UNSUPPORTED_FIX) || defined EXPLODE_THE_SHADER
  #include "/lib/text_rendering.glsl"
// #endif

#if DEBUG_VIEW == debug_CLOUDDEPTHTEX && defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
  #extension GL_NV_gpu_shader5 : enable
  #extension GL_ARB_shader_image_load_store : enable

  layout (rgba16f) uniform image2D cloudDepthTex;
#endif

in vec2 texcoord;
uniform vec2 texelSize;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float frameTime;
uniform float viewHeight;
uniform float viewWidth;
uniform float aspectRatio;
uniform vec3 relativeEyePosition;

#ifdef PIXELATED
  uniform vec2 view_res;
#endif

uniform int hideGUI;

uniform vec3 previousCameraPosition;
// uniform vec3 cameraPosition;
uniform mat4 gbufferPreviousModelView;
// uniform mat4 gbufferModelViewInverse;
// uniform mat4 gbufferModelView;

#ifdef DROWNING_EFFECT
  uniform float drowningSmooth;
  uniform float currentPlayerAir;
#endif

#include "/lib/color_transforms.glsl"
#include "/lib/color_dither.glsl"
#include "/lib/res_params.glsl"

uniform float near;
uniform float far;
float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}
float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}
float blueNoise(){
  return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
}

float convertHandDepth_2(in float depth, bool hand) {
	  if(!hand) return depth;

    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;
    return ndcDepth * 0.5 + 0.5;
}

#include "/lib/util.glsl"
#include "/lib/projections.glsl"

#include "/lib/gameplay_effects.glsl"

void doCameraGridLines(inout vec3 color, vec2 UV){

  float lineThicknessY = 0.001;
  float lineThicknessX = lineThicknessY/aspectRatio;
  
  float horizontalLines = abs(UV.x-0.33);
  horizontalLines = min(abs(UV.x-0.66), horizontalLines);

  float verticalLines = abs(UV.y-0.33);
  verticalLines = min(abs(UV.y-0.66), verticalLines);

  float gridLines = horizontalLines < lineThicknessX || verticalLines < lineThicknessY ? 1.0 : 0.0;

  if(hideGUI > 0.0) gridLines = 0.0;
  color = mix(color, vec3(1.0),  gridLines);
}

vec3 doMotionBlur(vec2 texcoord, float depth, float noise, bool hand){
  
  const float samples = 4.0;
  vec3 color = vec3(0.0);

  float blurMult = 1.0;
  if(hand) blurMult = 0.0;

	vec3 viewPos = toScreenSpace(vec3(texcoord, depth));
	viewPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition);

	vec3 previousPosition = mat3(gbufferPreviousModelView) * viewPos + gbufferPreviousModelView[3].xyz;
  previousPosition = toClipSpace3(previousPosition);

	vec2 velocity = texcoord - previousPosition.xy;
  
  // thank you Capt Tatsu for letting me use these
  velocity /= (1.0 + length(velocity)); // ensure the blurring stays sane where UV is beyond 1.0 or -1.0
  velocity /= (1.0 + frameTime*1000.0 * samples * 0.25); // ensure the blur radius stays roughly the same no matter the framerate or sample count
  velocity *= blurMult * MOTION_BLUR_STRENGTH; // remove hand blur and add user control

  texcoord = texcoord - velocity*(samples*0.5 + noise);

  vec2 screenEdges = 2.0/vec2(viewWidth, viewHeight);

	for (int i = 0; i < int(samples); i++) {

    texcoord += velocity;
    color += texture(colortex7, clamp(texcoord, screenEdges, 1.0-screenEdges)).rgb;

  }

  return color / samples;
}

float doVignette( in vec2 texcoord, in float noise){

  float vignette = 1.0-clamp(1.0-length(texcoord-0.5),0.0,1.0);
  
  // vignette = pow(1.0-pow(1.0-vignette,3),5);
  vignette *= vignette*vignette;
  vignette = 1.0-vignette;
  vignette *= vignette*vignette*vignette*vignette;
  
  // stop banding
  vignette = vignette + vignette*(noise-0.5)*0.01;
  
  return mix(1.0, vignette, VIGNETTE_STRENGTH);
}

#if DEBUG_VIEW == debug_WATERSIM && WATER_INTERACTION == 2
  layout (rgba16f) uniform readonly image2D waveSim2;
#endif

uniform sampler2D radiosity_direct;
uniform sampler2D radiosity_direct_soft;
uniform sampler2D radiosity_handheld;


void main() {
  
  float noise = blueNoise();

  #if defined MOTION_BLUR
    float depth = texture(depthtex0, texcoord*RENDER_SCALE).r;
    bool hand = depth < 0.56;
    float depth2 = convertHandDepth_2(depth, hand);

    vec3 COLOR = doMotionBlur(texcoord, depth2, noise, hand);
  #elif defined PIXELATED
    vec3 COLOR = texelFetch(colortex7, ivec2(gl_FragCoord.xy)-ivec2(mod(gl_FragCoord.xy, PIXELIZATION_STRENGTH)),0).rgb;
  #else
    #ifdef FISHEYE_EFFECT
      vec2 _texcoord = texcoord - vec2(0.5);
      
      float dist = length(_texcoord);
      float dist2 = dist * (1.0 - FISHEYE_STRENGTH * dist * dist);
      
      _texcoord = _texcoord * dist2 / dist;
      
      _texcoord += vec2(0.5);

      vec3 COLOR = texture(colortex7, _texcoord).rgb;
    #else
      vec3 COLOR = texture(colortex7, texcoord).rgb;
    #endif
  #endif
  
  #if defined LOW_HEALTH_EFFECT || defined DAMAGE_TAKEN_EFFECT || defined WATER_ON_CAMERA_EFFECT  
    // for making the fun, more fun
    applyGameplayEffects(COLOR, texcoord, noise);
  #endif

  #if MAX_COLORS_PER_CHANNEL > 1
    COLOR = floor(COLOR*(MAX_COLORS_PER_CHANNEL-1))/(MAX_COLORS_PER_CHANNEL-1);
  #endif 

  #ifdef FILM_GRAIN
    // basic film grain implementation from https://www.shadertoy.com/view/4sXSWs slightly edited
    float x = (texcoord.x + 4.0 ) * (texcoord.y + 4.0 ) * (frameTimeCounter * 10.0);
    vec3 grain = vec3(mod((mod(x, 13.0) + 1.0) * (mod(x, 123.0) + 1.0), 0.01)-0.005) * FILM_GRAIN_STRENGTH;

    COLOR += grain;
  #endif

  #ifdef DROWNING_EFFECT
    if (currentPlayerAir != -1.0) COLOR *= 0.2 + 0.8*drowningSmooth;
  #endif
  
  #ifdef VIGNETTE
    COLOR *= doVignette(texcoord, noise);
  #endif

  #ifdef CAMERA_GRIDLINES
    doCameraGridLines(COLOR, texcoord);
  #endif

  #if DEBUG_VIEW == debug_SHADOWMAP
    vec2 shadowUV = texcoord * vec2(2.0, 1.0) ;

    // shadowUV -= vec2(0.5,0.0);
    // float zoom = 0.1;
    // shadowUV = ((shadowUV-0.5) - (shadowUV-0.5)*zoom) + 0.5;

    if(shadowUV.x < 1.0 && shadowUV.y < 1.0 && hideGUI == 1) COLOR = texture(shadowcolor1,shadowUV).rgb;
  #endif
  #if DEBUG_VIEW == debug_DEPTHTEX0
    COLOR = vec3(ld(texture(depthtex0, texcoord*RENDER_SCALE).r));
  #endif
  #if DEBUG_VIEW == debug_DEPTHTEX1
    COLOR = vec3(ld(texture(depthtex1, texcoord*RENDER_SCALE).r));
  #endif
  #if DEBUG_VIEW == debug_CLOUDDEPTHTEX && defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
    COLOR = imageLoad(cloudDepthTex, ivec2(gl_FragCoord.xy*VL_RENDER_SCALE*RENDER_SCALE)).rgb;
  #endif

  gl_FragColor.rgb = COLOR;

  #if DEBUG_VIEW == debug_WATERSIM && WATER_INTERACTION == 2
    if (hideGUI == 1) {
    gl_FragColor.rgb += vec3(imageLoad(waveSim2, ivec2(gl_FragCoord.xy)*5).x);

    vec2 offsetCoords = vec2(gl_FragCoord.x-840.0, gl_FragCoord.y);
    vec2 waveGradients = vec2(imageLoad(waveSim2, ivec2(offsetCoords)*5).zw);
    vec3 waveNormals = normalize(vec3(waveGradients.x, waveGradients.y, 0.2));
    if (length(waveNormals.xy) > 0.0) gl_FragColor.rgb += waveNormals;
    }
  #endif

  #if defined SHADER_GRASS_SETTING && MC_VERSION < 12101 && !defined SHADER_GRASS_UNSUPPORTED_FIX
    const float textSize2 = 4.0;
    beginText(ivec2(gl_FragCoord.xy/textSize2), ivec2(0.05*viewWidth/textSize2, 0.75*viewHeight/textSize2));
    text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
    printString((_S, _h, _a, _d, _e, _r, _space, _G, _r, _a, _s, _s, _space, _n, _e, _e, _d, _s, _space, _1, _dot, _2, _1, _dot, _1, _space, _o, _r, _space, _h, _i, _g, _h, _e, _r, _exclm));
    printLine();
    printString((_D, _i, _s, _a, _b, _l, _e, _space, _i, _t, _exclm));
    #if MC_VERSION == 12001
      printLine();
      printLine();
      printString((_T, _o, _space, _u, _s, _e, _space, _i, _t, _space, _o, _n, _space, _1, _dot, _2, _0, _dot, _1, _space, _u, _s, _e, _space, _t, _h, _e));
      printLine();
      text.fgCol = vec4(0.0, 1.0, 0.0, 1.0);
      printString((_quote, _E, _c, _l, _i, _p, _s, _e, _space, _S, _h, _a, _d, _e, _r, _space, _G, _r, _a, _s, _s, _space, _C, _o, _m, _p, _a, _t, _quote));
      printLine();
      text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
      printString((_R, _e, _s, _o, _u, _r, _c, _e, _space, _P, _a, _c, _k, _space, _f, _r, _o, _m, _space, _M, _o, _d, _r, _i, _n, _t, _h, _exclm));
      printLine();
      printLine();
      printString((_A, _d, _d, _i, _t, _i, _o, _n, _a, _l, _l, _y, _space, _e, _n, _a, _b, _l, _e, _space, _t, _h, _e));
      printLine();
      text.fgCol = vec4(1.0, 1.0, 0.0, 1.0);
      printString((_quote, _S, _h, _a, _d, _e, _r, _space, _G, _r, _a, _s, _s, _space, _U, _n, _s, _u, _p, _p, _o, _r, _t, _e, _d, _space, _F, _i, _x, _quote));
      printLine();
      text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
      printString((_i, _n, _space, _e, _x, _p, _e, _r, _i, _m, _e, _n, _t, _a, _l, _space, _s, _e, _t, _t, _i, _n, _g, _s, _exclm));
    #endif
    endText(gl_FragColor.rgb);
  #endif

  #ifndef IS_IRIS
    gl_FragColor.rgb = vec3(0.0);
    const float textSize = 4.0;
    beginText(ivec2(gl_FragCoord.xy/textSize), ivec2(0.05*viewWidth/textSize, 0.75*viewHeight/textSize));
    text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
    printString((_O, _p, _t, _i, _F, _i, _n, _e, _space, _d, _o, _e, _s, _space, _n, _o, _t, _space, _s, _u, _p, _p, _o, _r, _t, _space, _E, _c, _l, _i, _p, _s, _e, _exclm));
    printLine();
    printLine();
    printString((_U, _s, _e, _space, _I, _r, _i, _s, _space, _i, _n, _s, _t, _e, _a, _d, _exclm));
    endText(gl_FragColor.rgb);
  #endif

  #ifdef PHOTONICS
    #if DEBUG_VIEW == debug_radiosity_direct
      gl_FragColor.rgb = vec3(texture(radiosity_direct, texcoord).rgb);
    #elif DEBUG_VIEW == debug_radiosity_direct_soft
      gl_FragColor.rgb = vec3(texture(radiosity_direct_soft, texcoord).rgb);
    #elif DEBUG_VIEW == debug_radiosity_handheld
      gl_FragColor.rgb = vec3(texture(radiosity_handheld, texcoord).rgb);
    #elif DEBUG_VIEW == debug_radiosity_GI
      gl_FragColor.rgb = vec3(texture(colortex15, texcoord).rgb);
    #endif
  #endif

  #ifdef EXPLODE_THE_SHADER
    gl_FragColor.rgb = vec3(0.0);
    beginText(ivec2(gl_FragCoord.xy/vec2(6.0, 8.0)), ivec2(0.05*viewWidth/6.0, 0.75*viewHeight/8.0));
    text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
    printString((_D, _o, _space, _N, _O, _T, _space, _u, _s, _e, _space, _b, _o, _t, _h, _space, _D, _i, _s, _t, _a, _n, _t, _space, _H, _o, _r, _i, _z, _o, _n, _s, _space));
    printLine();
    printString((_a, _n, _d, _space, _V, _o, _x, _y, _space, _t, _o, _g, _e, _t, _h, _e, _r, _exclm));
    printLine();
    printLine();
    printString((_D, _i, _s, _a, _b, _l, _e, _space, _o, _n, _e, _space, _o, _f, _space, _t, _h, _e, _m, _exclm));
    endText(gl_FragColor.rgb);
  #endif

  #if defined SHADER_GRASS_SETTING && MC_VERSION >= 260200 && defined IEXT_ENABLED
  const float textSize2 = 4.0;
  beginText(ivec2(gl_FragCoord.xy/textSize2), ivec2(0.05*viewWidth/textSize2, 0.75*viewHeight/textSize2));
  text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
  printString((_S, _h, _a, _d, _e, _r, _space, _G, _r, _a, _s, _s, _space, _i, _s, _space, _b, _r, _o, _k, _e, _n, _space, _o, _n, _space, _2, _6, _dot, _2, _space, _o, _r, _space, _h, _i, _g, _h, _e, _r, _exclm));
  printLine();
  printString((_D, _i, _s, _a, _b, _l, _e, _space, _i, _t, _exclm));
  endText(gl_FragColor.rgb);
  #endif

  #if MC_VERSION >= 260200 && !defined IEXT_ENABLED
  const float textSize2 = 4.0;
  beginText(ivec2(gl_FragCoord.xy/textSize2), ivec2(0.05*viewWidth/textSize2, 0.75*viewHeight/textSize2));
  text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
  printString((_T, _h, _e, _space, _i, _n, _v, _i, _s, _i, _b, _l, _e, _space, _t, _e, _r, _r, _a, _i, _n, _space, _i, _s, _space, _a, _n, _space, _I, _r, _i, _s, _space, _b, _u, _g, _exclm));
  printLine();
  printLine();
  printString((_I, _n, _s, _t, _a, _l, _l, _space, _m, _y, _space));
  text.fgCol = vec4(0.0, 1.0, 0.0, 1.0);
  printString((_I, _r, _i, _s, _space, _E, _x, _t, _e, _n, _s, _i, _o, _n));
  text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
  printString((_space, _m, _o, _d, _space, _t, _o, _space, _f, _i, _x, _space, _i, _t, _exclm));
  endText(gl_FragColor.rgb);
  #endif

#if defined SHADER_GRASS_SETTING && defined CREATE_AERONAUTICS
  const float textSize3 = 4.0;
  beginText(ivec2(gl_FragCoord.xy/textSize3), ivec2(0.05*viewWidth/textSize3, 0.75*viewHeight/textSize3));
  text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
  printString((_S, _h, _a, _d, _e, _r, _space, _G, _r, _a, _s, _s, _space, _i, _s, _space, _b, _r, _o, _k, _e, _n, _space, _b, _y, _space, _C, _r, _e, _a, _t, _e, _space, _A, _e, _r, _o, _n, _a, _u, _t, _i, _c, _s, _exclm));
  printLine();
  printString((_D, _i, _s, _a, _b, _l, _e, _space, _i, _t, _exclm));
  endText(gl_FragColor.rgb);
#endif
}
