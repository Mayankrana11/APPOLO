// ============================================================================
// Appolo v0.1 — Cinematic Color Pipeline, Auto-Exposure, AgX/ACES Tone Mapping,
//               Temporal Anti-Aliasing (TAA) & Contrast Adaptive Sharpening
// ============================================================================
#ifndef APPOLO_POST_GLSL
#define APPOLO_POST_GLSL

#include "/lib/common.glsl"

// --- RGB <-> YCoCg Color Space (for Artifact-Free TAA Neighborhood Clamping) ---
vec3 rgbToYCoCg(vec3 c) {
    return vec3(
         0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
         0.50 * c.r             - 0.50 * c.b,
        -0.25 * c.r + 0.5 * c.g - 0.25 * c.b
    );
}

vec3 yCoCgToRgb(vec3 ycc) {
    float tmp = ycc.x - ycc.z;
    return max(vec3(0.0), vec3(tmp + ycc.y, ycc.x + ycc.z, tmp - ycc.y));
}

// --- Temporal Reprojection UV Calculation ---
vec2 computePreviousScreenUV(
    vec2 currentUV,
    float depth,
    mat4 projInv,
    mat4 modelViewInv,
    vec3 cameraPosition,
    vec3 previousCameraPosition,
    mat4 prevModelView,
    mat4 prevProjection
) {
    vec4 clip = vec4(currentUV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = projInv * clip;
    viewPos /= max(viewPos.w, 1e-6);

    vec3 worldPos = (modelViewInv * viewPos).xyz;
    // Compensate for camera translation only on non-sky geometry
    if (depth < 0.9999) {
        worldPos += (cameraPosition - previousCameraPosition);
    }

    vec4 prevView = prevModelView * vec4(worldPos, 1.0);
    vec4 prevClip = prevProjection * prevView;
    return (prevClip.xy / max(prevClip.w, 1e-6)) * 0.5 + 0.5;
}

// --- Temporal Anti-Aliasing (TAA) with Variance Clipping ---
vec3 resolveTAA(
    sampler2D currentTex,
    sampler2D historyTex,
    vec2 uv,
    vec2 prevUV,
    vec2 texelSize
) {
    vec3 centerRGB = texture(currentTex, uv).rgb;
#ifndef TAA_ENABLED
    return centerRGB;
#else
    if (prevUV.x < 0.001 || prevUV.x > 0.999 || prevUV.y < 0.001 || prevUV.y > 0.999) {
        return centerRGB;
    }

    // Sample 3x3 neighborhood in YCoCg space to build variance bounding box
    vec3 m1 = vec3(0.0);
    vec3 m2 = vec3(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 sUV = clamp(uv + vec2(float(x), float(y)) * texelSize, 0.001, 0.999);
            vec3 sYCC = rgbToYCoCg(max(texture(currentTex, sUV).rgb, vec3(0.0)));
            m1 += sYCC;
            m2 += sYCC * sYCC;
        }
    }
    m1 /= 9.0;
    vec3 sigma = sqrt(max(m2 / 9.0 - m1 * m1, vec3(1e-6)));
    const float gamma = 1.25;
    vec3 minBox = m1 - gamma * sigma;
    vec3 maxBox = m1 + gamma * sigma;

    vec3 histRGB = max(texture(historyTex, prevUV).rgb, vec3(0.0));
    vec3 histYCC = clamp(rgbToYCoCg(histRGB), minBox, maxBox);
    vec3 clampedHistRGB = yCoCgToRgb(histYCC);

    // Karis luma weighting to suppress fireflies and specular shimmering
    float wCurr = 1.0 / (1.0 + luma(centerRGB) * 0.5);
    float wHist = 1.0 / (1.0 + luma(clampedHistRGB) * 0.5);

    float velocity = length((uv - prevUV) / max(texelSize, vec2(1e-5)));
    float blendFactor = clamp(mix(0.90, 0.68, saturate(velocity * 0.15)), 0.65, 0.92);

    return (centerRGB * wCurr * (1.0 - blendFactor) + clampedHistRGB * wHist * blendFactor)
         / max(wCurr * (1.0 - blendFactor) + wHist * blendFactor, 1e-5);
#endif
}

// --- AgX Cinematic Tone Mapping (Troy Sobotka / Blender 4.0+ Filmic Transform) ---
// Preserves highlight hue rolloff on intense lava, solar discs, and colored lights
vec3 agxDefaultContrastApprox(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;
    return + 15.5     * x4 * x2
           - 40.14    * x4 * x
           + 31.96    * x4
           - 6.868    * x2 * x
           + 0.4298   * x2
           + 0.1191   * x
           - 0.00232;
}

vec3 tonemapAgX(vec3 color) {
    const mat3 agxMat = mat3(
        0.842479062253094,  0.0423282422610123, 0.0423756549057051,
        0.0784335999999992, 0.878468636469772,  0.0784336,
        0.0792237451477643, 0.0791661274605434, 0.879142973793104
    );
    const mat3 agxMatInv = mat3(
         1.19687900512017,   -0.0528968517574562, -0.0529716355144438,
        -0.0980208811401368,  1.15190312990417,   -0.0980434501171241,
        -0.0990297440797205, -0.0989611768448433,  1.15107367264116
    );
    const float minEv = -12.47393;
    const float maxEv =  4.026069;

    color = max(color, vec3(1e-6));
    color = agxMat * color;
    color = clamp(log2(color), minEv, maxEv);
    color = (color - minEv) / (maxEv - minEv);
    color = agxDefaultContrastApprox(color);
    color = agxMatInv * color;
    return clamp(pow(max(color, vec3(0.0)), vec3(2.2)), vec3(0.0), vec3(1.0));
}

// --- ACES Fitted RRT + ODT Tone Mapping (Stephen Hill) ---
vec3 tonemapACESFitted(vec3 color) {
    const mat3 acesInput = mat3(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    const mat3 acesOutput = mat3(
         1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    color = acesInput * color;
    vec3 a = color * (color + 0.0245786) - 0.000090537;
    vec3 b = color * (0.983729 * color + 0.4329510) + 0.238081;
    color = acesOutput * (a / max(b, vec3(1e-5)));
    return saturate(color);
}

// --- Khronos PBR Neutral Tone Mapper ---
vec3 tonemapPBRNeutral(vec3 color) {
    const float startCompression = 0.8 - 0.04;
    const float desaturation = 0.15;
    float x = min(color.r, min(color.g, color.b));
    float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
    color -= offset;
    float peak = max(color.r, max(color.g, color.b));
    if (peak < startCompression) return color;
    const float d = 1.0 - startCompression;
    float newPeak = 1.0 - d * d / (peak + d - startCompression);
    color *= newPeak / max(peak, 1e-5);
    float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
    return mix(color, vec3(newPeak), g);
}

// --- Apply Selected Cinematic Tone Mapping, Contrast & Natural Saturation ---
vec3 evaluateCinematicColorPipeline(vec3 hdrColor, float adaptedLuma) {
    // Balanced cinematic auto-exposure (prevents over-brightening dark night skies & The End)
    float targetKey = 0.18;
    float autoExposure = clamp(targetKey / max(adaptedLuma, 0.11), 0.68, 1.32);
    float manualExposure = exp2(EXPOSURE_BIAS);
    vec3 exposed = hdrColor * autoExposure * manualExposure;

    // Tone Mapping Operator
    vec3 mapped;
#if TONEMAP_OPERATOR == 1
    mapped = tonemapAgX(exposed);
#elif TONEMAP_OPERATOR == 2
    mapped = tonemapACESFitted(exposed);
#else
    mapped = tonemapPBRNeutral(exposed);
#endif

    // Subtle S-curve Contrast around Mid-Grey (0.18)
    mapped = pow(max(mapped, vec3(0.0)), vec3(CONTRAST_LEVEL));

    // Natural Color Saturation (prevents cartoon oversaturation)
    float y = luma(mapped);
    mapped = mix(vec3(y), mapped, SATURATION_LEVEL);

    return linearToSrgb(saturate(mapped));
}

#endif // APPOLO_POST_GLSL
