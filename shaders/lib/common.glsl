// ============================================================================
// Appolo v0.1 — Common Math, Coordinate Transforms, Noise & Utility Library
// Universal Compatibility: Iris Shaders, Sodium, Beddium/Embeddium & OptiFine
// ============================================================================
#ifndef APPOLO_COMMON_GLSL
#define APPOLO_COMMON_GLSL

#include "/lib/settings.glsl"

#ifndef DIMENSION_ID
#define DIMENSION_ID 0
#endif

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA8;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
const int colortex5Format = RGBA16F;
const int colortex6Format = RGBA16F;
const int colortex7Format = RGBA8;
const int shadowcolor0Format = RGBA8;
const int shadowcolor1Format = RGBA8;
*/

const bool colortex5Clear = false;
const bool colortex6Clear = false;
const bool colortex0MipmapEnabled = false;
const bool colortex4MipmapEnabled = false;
const bool shadowHardwareFiltering0 = false;
const bool shadowHardwareFiltering1 = false;
const float sunPathRotation = -32.0;
const int noiseTextureResolution = 512;
const float ambientOcclusionLevel = 1.0;
const float shadowDistanceRenderMul = 1.0;
const float shadowIntervalSize = 2.0;
const bool generateShadowMipmap = false;
const bool generateShadowColorMipmap = false;

const float PI          = 3.14159265358979323846;
const float TAU         = 6.28318530717958647692;
const float HALF_PI     = 1.57079632679489661923;
const float INV_PI      = 0.31830988618379067154;
const float GOLDEN_ANGLE = 2.39996322972865332;
const float EPS         = 1e-5;

// --- Safe Math Helpers ---
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2  saturate(vec2  x) { return clamp(x, vec2(0.0), vec2(1.0)); }
vec3  saturate(vec3  x) { return clamp(x, vec3(0.0), vec3(1.0)); }
vec4  saturate(vec4  x) { return clamp(x, vec4(0.0), vec4(1.0)); }

float sqr(float x) { return x * x; }
vec3  sqr(vec3  x) { return x * x; }
float pow5(float x) { float x2 = x * x; return x2 * x2 * x; }
float max3(vec3 v) { return max(v.x, max(v.y, v.z)); }
float min3(vec3 v) { return min(v.x, min(v.y, v.z)); }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// --- sRGB <-> Linear Conversions ---
vec3 srgbToLinear(vec3 srgb) {
    return pow(max(srgb, vec3(0.0)), vec3(2.2));
}

vec3 linearToSrgb(vec3 linearCol) {
    return pow(max(linearCol, vec3(0.0)), vec3(1.0 / 2.2));
}

// --- Normal Encoding / Decoding ---
vec3 encodeNormal(vec3 n) {
    return normalize(n) * 0.5 + 0.5;
}

vec3 decodeNormal(vec3 enc) {
    vec3 n = enc * 2.0 - 1.0;
    float len2 = dot(n, n);
    return (len2 > 1e-6) ? (n * inversesqrt(len2)) : vec3(0.0, 1.0, 0.0);
}

// --- Material ID Mapping from block.properties (mc_Entity.x) ---
int mapBlockIdToMat(int blockId) {
    if (blockId == 10001) return MAT_WATER;
    if (blockId == 10002) return MAT_GLASS;
    if (blockId == 10003) return MAT_OBSIDIAN;
    if (blockId == 10004) return MAT_LAVA;
    if (blockId == 10005) return MAT_EMISSIVE_WARM;
    if (blockId == 10006) return MAT_EMISSIVE_COOL;
    if (blockId == 10007) return MAT_EMISSIVE_SOUL;
    if (blockId == 10010) return MAT_METAL;
    if (blockId == 10011) return MAT_POLISHED;
    if (blockId == 10012) return MAT_FOLIAGE;
    if (blockId == 10013) return MAT_ICE;
    if (blockId == 10014) return MAT_VOLCANIC;
    if (blockId == 10015) return MAT_PORTAL;
    return MAT_DEFAULT;
}

float encodeMatId(int matId) {
    return float(clamp(matId, 0, 31)) / 31.0;
}

int decodeMatId(float encoded) {
    return int(floor(encoded * 31.0 + 0.5));
}

// --- Rotation Matrices ---
mat2 rot2D(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

mat3 rotAxisAngle(vec3 axis, float angle) {
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    return mat3(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

// --- High-Quality Procedural Hash & Noise Functions ---
float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 hash33(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Interleaved Gradient Noise (Jimenez 2014) + Temporal Frame Offset
float interleavedGradientNoise(vec2 pixelCoord, int frame) {
    pixelCoord += float(frame & 63) * vec2(47.0, 17.0) * 0.695;
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(pixelCoord, magic.xy)));
}

// Quasi-random R2 Sequence for low-discrepancy sampling
vec2 r2Sequence(int index, float seed) {
    const vec2 alpha = vec2(0.7548776662466927, 0.5698402909980532);
    return fract(seed + float(index) * alpha);
}

// Smooth 2D Value Noise
float noise2D(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = hash12(i + vec2(0.0, 0.0));
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Smooth 3D Value Noise
float noise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

// 2D Fractal Brownian Motion (FBM)
float fbm2D(vec2 p, int octaves) {
    float v = 0.0;
    float amp = 0.5;
    mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
    for (int i = 0; i < octaves; i++) {
        v += amp * noise2D(p);
        p = rot * p * 2.03 + vec2(17.1, 31.7);
        amp *= 0.5;
    }
    return v;
}

// 3D Fractal Brownian Motion (FBM)
float fbm3D(vec3 p, int octaves) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < octaves; i++) {
        v += amp * noise3D(p);
        p = p * 2.02 + vec3(13.7, 29.3, 7.1);
        amp *= 0.5;
    }
    return v;
}

// Ridged Multifractal 3D Noise (for Galactic Dust Lanes, Craters, and Molten Lava Cracks)
float ridgedFbm3D(vec3 p, int octaves) {
    float sum = 0.0;
    float amp = 0.5;
    float prev = 1.0;
    for (int i = 0; i < octaves; i++) {
        float n = 1.0 - abs(noise3D(p) * 2.0 - 1.0);
        n = n * n;
        sum += n * amp * prev;
        prev = n;
        p = p * 2.11 + vec3(19.3, 7.7, 31.1);
        amp *= 0.5;
    }
    return sum;
}

// 2D Voronoi / Worley Cellular Noise (Returns vec2: x = F1 distance, y = F2 distance)
vec2 voronoi2D(vec2 x) {
    vec2 n = floor(x);
    vec2 f = fract(x);
    float d1 = 8.0;
    float d2 = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash22(n + g);
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < d1) {
                d2 = d1;
                d1 = d;
            } else if (d < d2) {
                d2 = d;
            }
        }
    }
    return sqrt(vec2(d1, d2));
}

// Analytic Ray-Sphere Intersection (Returnsvec2(tNear, tFar), or vec2(-1.0) on miss)
vec2 intersectSphere(vec3 rayOrigin, vec3 rayDir, vec3 sphereCenter, float sphereRadius) {
    vec3 oc = rayOrigin - sphereCenter;
    float b = dot(oc, rayDir);
    float c = dot(oc, oc) - sphereRadius * sphereRadius;
    float h = b * b - c;
    if (h < 0.0) return vec2(-1.0);
    h = sqrt(h);
    return vec2(-b - h, -b + h);
}

// Blackbody Planckian Locus Approximation (Temperature in Kelvin -> Linear RGB)
vec3 blackbodyColor(float tempK) {
    float t = clamp(tempK, 1000.0, 40000.0) / 100.0;
    vec3 col;
    if (t <= 66.0) {
        col.r = 1.0;
        col.g = saturate(0.39008157 * log(max(t, 1.0)) - 0.63184144);
    } else {
        col.r = saturate(1.29293618 * pow(t - 60.0, -0.13320476));
        col.g = saturate(1.12989086 * pow(t - 60.0, -0.07551485));
    }
    if (t >= 66.0) {
        col.b = 1.0;
    } else if (t <= 19.0) {
        col.b = 0.0;
    } else {
        col.b = saturate(0.54320679 * log(max(t - 10.0, 1.0)) - 1.19625409);
    }
    return srgbToLinear(col);
}

// ============================================================================
// High-Resolution 2048x2048 4-Quadrant Scientific & Astrophotography Atlas
// Bound via texture.noise=textures/noisetex.png
// ============================================================================
uniform sampler2D noisetex;

// Quadrant 0 [0.0..0.5, 0.0..0.5]: R=BlueNoise, G=Perlin-Worley Cloud FBM, B=CurlNoise, A=Micrograin
vec4 sampleCloudAndBlueNoiseAtlas(vec2 uv) {
    vec2 qUV = vec2(0.002, 0.002) + fract(uv) * 0.496;
    return textureLod(noisetex, qUV, 0.0);
}

// Quadrant 1 [0.5..1.0, 0.0..0.5]: High-Res Astrophotography Milky Way & Deep-Sky Nebulae Panorama
vec4 sampleMilkyWayAstrophoto(vec2 lonLatUV) {
    vec2 qUV = vec2(0.502, 0.002) + clamp(vec2(fract(lonLatUV.x), lonLatUV.y), 0.0, 1.0) * 0.496;
    return textureLod(noisetex, qUV, 0.0);
}

// Quadrant 2 [0.0..0.5, 0.5..1.0]: Solar System Planetary & Lunar Atlas (band 0=Jupiter, 1=Saturn+Rings, 2=Earth, 3=Moon)
vec4 samplePlanetaryAtlas(vec2 lonLatUV, int band) {
    float bandOffset = 0.500 + float(clamp(band, 0, 3)) * 0.125;
    vec2 qUV = vec2(
        0.002 + fract(lonLatUV.x) * 0.496,
        bandOffset + 0.002 + clamp(lonLatUV.y, 0.0, 1.0) * 0.121
    );
    return textureLod(noisetex, qUV, 0.0);
}

// Quadrant 3 [0.5..1.0, 0.5..1.0]: Inverse-FFT Phillips Ocean Wave Normals (RG), Capillary (B), Photon Caustics (A)
vec4 sampleOceanFFTAndCaustics(vec2 uv) {
    vec2 qUV = vec2(0.502, 0.502) + fract(uv) * 0.496;
    return textureLod(noisetex, qUV, 0.0);
}

#endif // APPOLO_COMMON_GLSL
