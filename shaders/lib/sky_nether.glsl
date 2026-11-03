// ============================================================================
// Appolo v0.1 — The Nether: Photon-Style Volcanic Atmosphere & Volumetric Fog
//               Smooth Multi-Scattered Magma Glow & Biome-Aware Hellscape
// ============================================================================
#ifndef APPOLO_SKY_NETHER_GLSL
#define APPOLO_SKY_NETHER_GLSL

#include "/lib/common.glsl"

// --- Photon-Style Atmospheric Nether Sky & Distant Magma Horizon Glow ---
vec3 evaluateNetherSky(vec3 worldDir, vec3 cameraWorldPos, vec3 vanillaFogColor, float time) {
    vec3 biomeTint = srgbToLinear(clamp(vanillaFogColor, vec3(0.05), vec3(1.0)));
    float isSoulValley  = saturate((biomeTint.b - biomeTint.r) * 2.5);
    float isBasaltDelta = saturate(1.0 - max3(biomeTint) * 2.2);

    vec3 horizonMagmaGlow = mix(vec3(0.95, 0.24, 0.04), vec3(0.16, 0.62, 0.85), isSoulValley * 0.72);
    vec3 midVolcanicHaze  = mix(vec3(0.22, 0.038, 0.010), vec3(0.035, 0.095, 0.145), isSoulValley * 0.72);
    vec3 zenithDarkSmoke  = mix(vec3(0.035, 0.008, 0.004), vec3(0.024, 0.022, 0.028), isBasaltDelta);

    // Smooth vertical atmospheric gradient (brightest near horizon & lower lava sea hemisphere)
    float horizonBand = exp(-abs(worldDir.y + 0.05) * 3.2);
    float lowerHemi   = smoothstep(0.25, -0.65, worldDir.y);

    vec3 sky = mix(zenithDarkSmoke, midVolcanicHaze, smoothstep(0.85, 0.0, abs(worldDir.y)));
    sky += horizonMagmaGlow * (horizonBand * 0.42 + lowerHemi * 0.35);

    return sky * NETHER_ATMOSPHERE_DENSITY;
}

// --- Subtle Refractive Heat Shimmer (No upward-scrolling screen wobble) ---
vec2 computeNetherHeatDistortion(
    vec2 uv,
    vec3 viewPos,
    vec3 worldPos,
    float blockLight,
    float emission,
    float time
) {
#ifndef HEAT_DISTORTION
    return uv;
#else
    // Only apply a subtle micro-shimmer on distant superheated surfaces or directly on glowing magma
    float distFactor = smoothstep(18.0, 75.0, length(viewPos)) * 0.35;
    float hotSurface = smoothstep(0.75, 1.0, emission) * 0.45;
    float strength   = (distFactor + hotSurface) * 0.00055 * HEAT_HAZE_STRENGTH;

    vec2 borderMask = smoothstep(vec2(0.0), vec2(0.06), uv) * smoothstep(vec2(1.0), vec2(0.94), uv);
    float mask = borderMask.x * borderMask.y;

    vec2 p = uv * 24.0 + vec2(sin(time * 1.4), cos(time * 1.1));
    vec2 offset = vec2(noise2D(p) - 0.5, noise2D(p + vec2(5.7, 3.1)) - 0.5) * strength * mask;
    return clamp(uv + offset, vec2(0.001), vec2(0.999));
#endif
}

// --- Photon-Style Smooth Volumetric Nether Fog & Magma Sea Scattering (No upward lava drops!) ---
vec4 evaluateNetherVolumetricsAndSteam(
    vec3 rayOriginWorld,
    vec3 targetWorldPos,
    vec3 rayDir,
    float maxDist,
    vec3 vanillaFogColor,
    float time,
    float dither
) {
    float marchDist = min(maxDist, 112.0);
    if (marchDist <= 0.1) return vec4(0.0, 0.0, 0.0, 1.0);

    const int STEPS = 14;
    float stepSize = marchDist / float(STEPS);
    float t = stepSize * dither;

    vec3 biomeTint = srgbToLinear(clamp(vanillaFogColor, vec3(0.05), vec3(1.0)));
    float isSoulValley  = saturate((biomeTint.b - biomeTint.r) * 2.5);
    float isBasaltDelta = saturate(1.0 - max3(biomeTint) * 2.2);

    // Biome-aware multi-scattered volcanic fog colors (Photon-style warm amber-crimson in Wastes, cyan in Soul Valley)
    vec3 lowerLavaGlow = mix(vec3(1.15, 0.28, 0.045), vec3(0.18, 0.68, 0.92), isSoulValley * 0.72) * (0.75 + 0.25 * LAVA_EMISSION_STRENGTH);
    vec3 ambientSmoke  = mix(vec3(0.24, 0.045, 0.012), vec3(0.045, 0.11, 0.16), isSoulValley * 0.72);
    ambientSmoke       = mix(ambientSmoke, vec3(0.12, 0.10, 0.11), isBasaltDelta * 0.65);

    float transmittance = 1.0;
    vec3 accumLight = vec3(0.0);

    for (int i = 0; i < STEPS; i++) {
        if (transmittance < 0.03) break;
        vec3 p = rayOriginWorld + rayDir * t;

        // Smooth altitude-based magma glow near the Y = 31 lava sea + gentle horizontal drift
        float distAboveLava = p.y - 31.0;
        float lavaProximity = exp(-max(distAboveLava, 0.0) * 0.055);

        // Gentle, large-scale 3D atmospheric density variation (no small blobs or upward drops!)
        vec3 mistCoord = p * 0.022 + vec3(time * 0.025, 0.0, time * 0.018);
        float mistVar  = 0.75 + 0.25 * fbm3D(mistCoord, 2);

        float baseDensity = (0.0085 + 0.0095 * lavaProximity) * mistVar * NETHER_ATMOSPHERE_DENSITY;
        vec3 localScatterColor = mix(ambientSmoke, lowerLavaGlow, lavaProximity * 0.78);

        float stepExt = baseDensity * stepSize;
        float stepTrans = exp(-stepExt);

        accumLight += transmittance * (1.0 - stepTrans) * localScatterColor;
        transmittance *= stepTrans;

        t += stepSize;
    }

    return vec4(accumLight, transmittance);
}

#endif // APPOLO_SKY_NETHER_GLSL
