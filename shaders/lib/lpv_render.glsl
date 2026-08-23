// LPV block brightness scale. just 1.0/15.0
const float LpvBlockBrightness = 0.066666;


float lpvCurve(float values) {
    #ifdef VANILLA_LIGHTMAP_MASK
        return sqrt(values);
    #else
        return values*values;
    #endif
}

vec4 SampleLpvLinear(const in vec3 lpvPos) {
    vec3 texcoord = lpvPos / LpvSize3;

    vec4 lpvSample = (frameCounter % 2) == 0
        ? textureLod(texLpv2, texcoord, 0)
        : textureLod(texLpv1, texcoord, 0);

    vec3 hsv = RgbToHsv(lpvSample.rgb);
    hsv.z = lpvCurve(hsv.b) * LpvBlockSkyRange.x;
    lpvSample.rgb = HsvToRgb(hsv);
    
    lpvSample.rgb = clamp(lpvSample.rgb/15.0,0.0,1.0);

    return lpvSample;
}

vec3 GetLpvBlockLight(const in vec4 lpvSample) {
    return LpvBlockBrightness * lpvSample.rgb;
}

float GetLpvSkyLight(const in vec4 lpvSample) {
    float skyLight = saturate(lpvSample.a);
    return skyLight*skyLight;
}
