// ============================================================================
// Appolo v0.1 — Physical Soft Shadows (PCSS), Colored Shadows & Contact Shadows
// ============================================================================
#ifndef APPOLO_SHADOWS_GLSL
#define APPOLO_SHADOWS_GLSL

#include "/lib/common.glsl"

// --- Shadow Map Distortion (Concentrates Texel Density Near Camera) ---
vec3 distortShadowClipPos(vec3 shadowClipPos, out float distortFactor) {
    float dist = length(shadowClipPos.xy);
    distortFactor = mix(1.0, dist, 0.86);
    shadowClipPos.xy /= max(distortFactor, 1e-4);
    shadowClipPos.z *= 0.25; // Expand Z depth range to prevent clipping tall mountains
    return shadowClipPos;
}

vec3 distortShadowClipPos(vec3 shadowClipPos) {
    float dummy;
    return distortShadowClipPos(shadowClipPos, dummy);
}

// --- Vogel Disk Sample Pattern ---
vec2 vogelDiskSample(int sampleIndex, int samplesCount, float phi) {
    float r = sqrt((float(sampleIndex) + 0.5) / float(samplesCount));
    float theta = float(sampleIndex) * GOLDEN_ANGLE + phi;
    return vec2(cos(theta), sin(theta)) * r;
}

// --- Percentage-Closer Soft Shadows (PCSS) + Colored Translucent Shadows ---
vec3 evaluatePCSSShadow(
    sampler2D shadowtex0,
    sampler2D shadowtex1,
    sampler2D shadowcolor0,
    vec3 worldPos,
    vec3 geoNormal,
    vec3 lightDir,
    mat4 shadowModelView,
    mat4 shadowProjection,
    float dither
) {
    float NdotL = dot(geoNormal, lightDir);
    // Normal offset bias to eliminate shadow acne on steep slopes
    vec3 offsetWorldPos = worldPos + geoNormal * clamp(0.035 + (1.0 - max(NdotL, 0.0)) * 0.065, 0.02, 0.12);

    vec4 shadowView = shadowModelView * vec4(offsetWorldPos, 1.0);
    vec4 shadowClip = shadowProjection * shadowView;

    float distortFactor;
    shadowClip.xyz = distortShadowClipPos(shadowClip.xyz, distortFactor);
    vec3 shadowNDC = shadowClip.xyz * 0.5 + 0.5;

    // Fade out cleanly at the edge of the shadow map
    vec2 edgeFade2 = smoothstep(vec2(0.985), vec2(0.92), abs(shadowClip.xy));
    float edgeFade = edgeFade2.x * edgeFade2.y;
    if (edgeFade <= 0.001 || shadowNDC.z <= 0.0 || shadowNDC.z >= 1.0) {
        return vec3(1.0);
    }

    float bias = (0.00035 * distortFactor * distortFactor) / max(abs(NdotL), 0.15);
    float receiverDepth = shadowNDC.z - bias;
    float phi = dither * TAU;

    // 1. PCSS Blocker Search
    float avgBlockerDepth = 0.0;
    float blockerCount = 0.0;
    float searchRadius = 0.0032 / max(distortFactor, 0.15);

#if SHADOW_QUALITY >= 3
    const int BLOCKER_SAMPLES = 8;
    for (int i = 0; i < BLOCKER_SAMPLES; i++) {
        vec2 offset = vogelDiskSample(i, BLOCKER_SAMPLES, phi) * searchRadius;
        float d = texture(shadowtex1, shadowNDC.xy + offset).r;
        if (d < receiverDepth) {
            avgBlockerDepth += d;
            blockerCount += 1.0;
        }
    }
#endif

    // Compute physical penumbra filter radius based on blocker distance
    float penumbraRadius = 0.0011 / max(distortFactor, 0.15);
    if (blockerCount > 0.5) {
        avgBlockerDepth /= blockerCount;
        float penumbraRatio = clamp((receiverDepth - avgBlockerDepth) / max(avgBlockerDepth, 0.05), 0.0, 1.0);
        penumbraRadius = mix(0.00065, 0.0048, sqrt(penumbraRatio)) / max(distortFactor, 0.18);
    }

    // 2. Variable-Radius Vogel Disk PCF + Colored Translucent Shadow Filtering
#if SHADOW_QUALITY == 1
    const int PCF_SAMPLES = 4;
#elif SHADOW_QUALITY == 2
    const int PCF_SAMPLES = 12;
#elif SHADOW_QUALITY == 3
    const int PCF_SAMPLES = 20;
#else
    const int PCF_SAMPLES = 28;
#endif

    vec3 shadowAccum = vec3(0.0);
    for (int i = 0; i < PCF_SAMPLES; i++) {
        vec2 offset = vogelDiskSample(i, PCF_SAMPLES, phi) * penumbraRadius;
        vec2 sampleUV = shadowNDC.xy + offset;

        float depthOpaque = texture(shadowtex1, sampleUV).r;
        if (receiverDepth > depthOpaque) {
            // Fully occluded by opaque geometry
            continue;
        }

        float depthAll = texture(shadowtex0, sampleUV).r;
        if (receiverDepth > depthAll) {
            // Occluded only by translucent geometry (Stained Glass, Water, Ice)
            vec4 transCol = texture(shadowcolor0, sampleUV);
            vec3 stainedTint = srgbToLinear(transCol.rgb);
            float transAlpha = clamp(transCol.a, 0.05, 0.95);
            shadowAccum += mix(vec3(1.0), stainedTint * 1.15, transAlpha) * (1.0 - transAlpha * 0.65);
        } else {
            shadowAccum += vec3(1.0);
        }
    }

    vec3 finalShadow = shadowAccum / float(PCF_SAMPLES);
    return mix(vec3(1.0), finalShadow, edgeFade);
}

// --- Screen-Space Contact Shadows (Micro-Details Around Foliage & Blocks) ---
float computeContactShadow(
    sampler2D depthtex,
    vec3 viewPos,
    vec3 viewLightDir,
    mat4 projMatrix,
    float dither
) {
#ifndef CONTACT_SHADOWS
    return 1.0;
#else
    float viewDist = length(viewPos);
    if (viewDist > 48.0) return 1.0;

    const int STEPS = 12;
    float rayLength = clamp(0.18 + viewDist * 0.03, 0.15, 1.25);
    vec3 stepVec = (viewLightDir * rayLength) / float(STEPS);
    vec3 marchPos = viewPos + stepVec * (0.25 + dither);
    float thickness = 0.045 * (1.0 + viewDist * 0.05);

    for (int i = 0; i < STEPS; i++) {
        vec4 clip = projMatrix * vec4(marchPos, 1.0);
        vec3 ndc = clip.xyz / max(clip.w, 1e-5);
        vec2 uv = ndc.xy * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

        float sampleDepth = texture(depthtex, uv).r;
        float rayDepth = ndc.z * 0.5 + 0.5;

        // Convert depth diff in view space
        float depthDiff = rayDepth - sampleDepth;
        if (depthDiff > 0.00004 && depthDiff < 0.0025 * (1.0 / max(viewDist, 1.0))) {
            float fade = 1.0 - float(i) / float(STEPS);
            return 1.0 - fade * 0.85;
        }
        marchPos += stepVec;
    }
    return 1.0;
#endif
}

#endif // APPOLO_SHADOWS_GLSL
