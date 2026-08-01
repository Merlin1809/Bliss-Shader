// just some basic consts for the wave function based on afl_ext's shader https://www.shadertoy.com/view/Xdlczl
// the overall shape must stay consistent because it is also computed on the CPU side
// to offset entities, vertex and fragment shader stage examples at the bottom
// this upper part is basically just a library that you don't need to change
const int PHYSICS_ITERATIONS_OFFSET = 13;
const float PHYSICS_DRAG_MULT = 0.048;
const float PHYSICS_XZ_SCALE = 0.035;
const float PHYSICS_TIME_MULTIPLICATOR = 0.45;
const float PHYSICS_W_DETAIL = 0.75;
const float PHYSICS_FREQUENCY = 6.0;
const float PHYSICS_SPEED = 2.0;
const float PHYSICS_WEIGHT = 0.8;
const float PHYSICS_FREQUENCY_MULT = 1.18;
const float PHYSICS_SPEED_MULT = 1.07;
const float PHYSICS_ITER_INC = 12.0;
const float PHYSICS_NORMAL_STRENGTH = 0.6;
const float PHYSICS_RIPPLE_VERTEX_DISPLACEMENT = 0.01;
const float PHYSICS_RIPPLE_NORMAL_STRENGTH = 0.042;
const float PHYSICS_RIPPLE_NORMAL_MAX_BLEND = 0.32;
const float PHYSICS_RIPPLE_NORMAL_SAMPLE_WORLD_DISTANCE = 0.25;
const float PHYSICS_RIPPLE_EDGE_FADE = 0.035;

layout(std140) uniform PhysicsOcean {
    // time in seconds that can go faster dependent on weather conditions (affected by weather strength
    // multiplier in ocean settings
    float physics_gameTime;
    float physics_globalTime;
    // this is the surface detail from the physics options, ranges from 13 to 48 (yeah I know weird)
    int physics_iterationsNormal;
    // base value is 13 and gets multiplied by wave height in ocean settings
    float physics_oceanHeight;
    // basic scale for the horizontal size of the waves
    float physics_oceanWaveHorizontalScale;
    // used for offsetting the ripple texture
    float physics_rippleRange;
    // controlling how much foam generates on the ocean
    float physics_foamAmount;
    // controlling the opacity of the foam
    float physics_foamOpacity;
};

layout(std140) uniform PhysicsOceanChunk {
    // used to offset the model to know the ripple position
    float physics_modelOffsetX;
    float physics_modelOffsetY;
    float physics_modelOffsetZ;
    // though the mesh totally changes
    float physics_waveOffsetX;
    float physics_waveOffsetZ;
};

#if defined PHYSICSMOD_VERTEX
    in float physics_waviness;

    // for the vertex shader stage
    out vec3 physics_localPosition;
    out float physics_localWaviness;
#endif

#if defined PHYSICSMOD_FRAGMENT
    // for the fragment shader stage
    in vec3 physics_localPosition;
    in float physics_localWaviness;
#endif

// texture containing the ripples (basic bump map)
uniform sampler2D physics_ripples;
// foam noise
uniform sampler3D physics_foam;
// just the generic minecraft lightmap, you can remove this and use the one supplied by Optifine/Iris
uniform sampler2D physics_lightmap;

// some functions for the dynamic ripples
vec2 physics_rippleUv(const in vec2 position) {
    vec2 eyePosition = position + vec2(physics_modelOffsetX, physics_modelOffsetZ);
    return (eyePosition + vec2(physics_rippleRange)) / (physics_rippleRange * 2.0);
}

float physics_rippleUvMask(const in vec2 uv) {
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
        return 0.0;
    }

    float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
    return smoothstep(0.0, PHYSICS_RIPPLE_EDGE_FADE, edge);
}

float physics_rippleSampleRaw(const in vec2 position) {
    vec2 uv = physics_rippleUv(position);
    return texture(physics_ripples, uv).r * physics_rippleUvMask(uv);
}

float physics_rippleVertexHeight(const in vec2 position) {
    return physics_rippleSampleRaw(position) * PHYSICS_RIPPLE_VERTEX_DISPLACEMENT;
}

float physics_waveHeight(vec2 position, int iterations, float factor, float time) {
    float adjustedFactor = clamp(factor * 2.0, 0.1, 1.0);
    position = (position - vec2(physics_waveOffsetX, physics_waveOffsetZ)) * PHYSICS_XZ_SCALE * physics_oceanWaveHorizontalScale;
	float iter = 0.0;
    float frequency = PHYSICS_FREQUENCY;
    float speed = PHYSICS_SPEED;
    float weight = 1.0;
    float height = 0.0;
    float waveSum = 0.0;
    float modifiedTime = time * PHYSICS_TIME_MULTIPLICATOR;
    
    for (int i = 0; i < iterations; i++) {
        vec2 direction = vec2(sin(iter), cos(iter));
        float x = dot(direction, position) * frequency + modifiedTime * speed;
        float wave = exp(sin(x) - 1.0);
        float result = wave * cos(x);
        vec2 force = result * weight * direction;
        
        position -= force * PHYSICS_DRAG_MULT * adjustedFactor;
        height += wave * weight;
        iter += PHYSICS_ITER_INC;
        waveSum += weight;
        weight *= PHYSICS_WEIGHT;
        frequency *= PHYSICS_FREQUENCY_MULT;
        speed *= PHYSICS_SPEED_MULT;
    }
    
    return height / waveSum * physics_oceanHeight * factor - physics_oceanHeight * factor * 0.5;
}

vec3 physics_waveNormal(const in vec2 position, const in vec2 direction, const in float factor, const in float time) {
    float oceanHeightFactor = physics_oceanHeight / 13.0;
    float totalFactor = oceanHeightFactor * factor;
    vec3 waveNormal = normalize(vec3(direction.x * totalFactor, PHYSICS_NORMAL_STRENGTH, direction.y * totalFactor));
    
    float rippleTexelSize = 1.0 / textureSize(physics_ripples, 0).x;
    float texelWorldSize = max((physics_rippleRange * 2.0) * rippleTexelSize, 0.001);
    float normalSampleDistance = min(texelWorldSize, PHYSICS_RIPPLE_NORMAL_SAMPLE_WORLD_DISTANCE);

    float center = physics_rippleSampleRaw(position);
    float left = physics_rippleSampleRaw(position - vec2(normalSampleDistance, 0.0));
    float right = physics_rippleSampleRaw(position + vec2(normalSampleDistance, 0.0));
    float top = physics_rippleSampleRaw(position - vec2(0.0, normalSampleDistance));
    float bottom = physics_rippleSampleRaw(position + vec2(0.0, normalSampleDistance));
    float totalEffect = abs(center) + abs(left) + abs(right) + abs(top) + abs(bottom);
    
    float rippleSlopeX = ((left - right) / (normalSampleDistance * 2.0)) * PHYSICS_RIPPLE_NORMAL_STRENGTH;
    float rippleSlopeZ = ((top - bottom) / (normalSampleDistance * 2.0)) * PHYSICS_RIPPLE_NORMAL_STRENGTH;
    float rippleBlend = smoothstep(0.006, 0.10, totalEffect) * PHYSICS_RIPPLE_NORMAL_MAX_BLEND;

    vec2 baseSlope = waveNormal.xz / max(waveNormal.y, 0.001);
    vec2 combinedSlope = baseSlope + vec2(rippleSlopeX, rippleSlopeZ) * rippleBlend;
    return normalize(vec3(combinedSlope.x, 1.0, combinedSlope.y));
}

struct WavePixelData {
    vec2 direction;
    vec2 worldPos;
    vec3 normal;
    float foam;
    float height;
};

WavePixelData physics_wavePixel(
    const in vec2 position,
    const in float factor,
    const in float iterations,
    const in float time
) {
    float adjustedFactor = clamp(factor * 2.0, 0.1, 1.0);
    vec2 wavePos = (position.xy - vec2(physics_waveOffsetX, physics_waveOffsetZ)) * PHYSICS_XZ_SCALE * physics_oceanWaveHorizontalScale;
    float iter = 0.0;
    float frequency = PHYSICS_FREQUENCY;
    float speed = PHYSICS_SPEED;
    float weight = 1.0;
    float height = 0.0;
    float waveSum = 0.0;
    float modifiedTime = time * PHYSICS_TIME_MULTIPLICATOR;
    vec2 dx = vec2(0.0);
    
    for (int i = 0; i < iterations; i++) {
        vec2 direction = vec2(sin(iter), cos(iter));
        float x = dot(direction, wavePos) * frequency + modifiedTime * speed;
        float wave = exp(sin(x) - 1.0);
        float result = wave * cos(x);
        vec2 force = result * weight * direction;
        
        dx += force / pow(weight, PHYSICS_W_DETAIL); 
        wavePos -= force * PHYSICS_DRAG_MULT * adjustedFactor;
        height += wave * weight;
        iter += PHYSICS_ITER_INC;
        waveSum += weight;
        weight *= PHYSICS_WEIGHT;
        frequency *= PHYSICS_FREQUENCY_MULT;
        speed *= PHYSICS_SPEED_MULT;
    }
    
    WavePixelData data;
    data.direction = -vec2(dx / pow(waveSum, 1.0 - PHYSICS_W_DETAIL));
    data.worldPos = wavePos / physics_oceanWaveHorizontalScale / PHYSICS_XZ_SCALE;
    float baseHeight = height / waveSum * physics_oceanHeight * factor - physics_oceanHeight * factor * 0.5;
    float rippleHeight = physics_rippleVertexHeight(position);
    data.height = baseHeight + rippleHeight;
    
    data.normal = physics_waveNormal(position, data.direction, max(0.1, factor), time);

    float waveAmplitude = data.height * pow(max(data.normal.y, 0.0), 4.0);
    float rippleFoam = smoothstep(0.10, 0.38, abs(rippleHeight));
    vec2 waterUV = mix(position - vec2(physics_waveOffsetX, physics_waveOffsetZ), data.worldPos, clamp(factor * 2.0, 0.2, 1.0));
    
    vec2 s1 = textureLod(physics_foam, vec3(waterUV * 0.26, physics_globalTime / 360.0), 0).rg;
    vec2 s2 = textureLod(physics_foam, vec3(waterUV * 0.02, physics_globalTime / 360.0 + 0.5), 0).rg;
    vec2 s3 = textureLod(physics_foam, vec3(waterUV * 0.1, physics_globalTime / 360.0 + 1.0), 0).rg;
    
    float waterSurfaceNoise = s1.r * s2.r * s3.r * 2.8 * physics_foamAmount;
    waveAmplitude = clamp(waveAmplitude * 1.2, 0.0, 1.0);
    waterSurfaceNoise = (1.0 - waveAmplitude) * waterSurfaceNoise + waveAmplitude * physics_foamAmount;
    
    float worleyNoise = 0.2 + 0.8 * s1.g * (1.0 - s2.g);
    float waterFoamMinSmooth = 0.45;
    float waterFoamMaxSmooth = 2.0;
    waterSurfaceNoise = smoothstep(waterFoamMinSmooth, 1.0, waterSurfaceNoise) * worleyNoise;
    
    data.foam = clamp(waterFoamMaxSmooth * waterSurfaceNoise * physics_foamOpacity, 0.0, 1.0);
    
    return data;
}

/*

// VERTEX STAGE
in float physics_waviness;

out vec3 physics_localPosition;
out float physics_localWaviness;

void main() {
    // basic value to determine how shallow/far away from the shore the water is
    physics_localWaviness = physics_waviness;
    // transform gl_Vertex (since it is the raw mesh, i.e. not transformed yet)
    float baseWaveHeight = physics_waveHeight(gl_Vertex.xz, PHYSICS_ITERATIONS_OFFSET, physics_localWaviness, physics_gameTime);
    float rippleHeight = physics_rippleVertexHeight(gl_Vertex.xz);
    vec4 finalPosition = vec4(gl_Vertex.x, gl_Vertex.y + baseWaveHeight + rippleHeight, gl_Vertex.z, gl_Vertex.w);
    // pass this to the fragment shader to fetch the texture there for per fragment normals
    physics_localPosition = finalPosition.xyz;
    
    // now use finalPosition instead of gl_Vertex
}

// FRAGMENT STAGE
in vec3 physics_localPosition;
in float physics_localWaviness;

void main() {
    WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);
    
    // access the wave struct data however you want, wave.normal is in world space, wave.foam is the final foam amount
}

*/