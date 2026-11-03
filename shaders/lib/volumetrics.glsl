// ============================================================================
// Appolo v0.1 — Ray-Marched Volumetric Light Shafts (God Rays) & Atmospheric Fog
// ============================================================================
#ifndef APPOLO_VOLUMETRICS_GLSL
#define APPOLO_VOLUMETRICS_GLSL

#include "/lib/common.glsl"
#include "/lib/shadows.glsl"

// --- Overworld Volumetric Light Scattering (Crepuscular Rays + Valley Mist) ---
vec4 evaluateOverworldVolumetrics(
    sampler2D shadowtex0,
    sampler2D shadowtex1,
    sampler2D shadowcolor0,
    vec3 targetWorldPos,
    vec3 cameraWorldPos,
    vec3 sunWorldDir,
    vec3 moonWorldDir,
    mat4 shadowModelView,
    mat4 shadowProjection,
    float rainStrength,
    float isEyeInWater,
    float time,
    float dither
) {
    float maxDist = length(targetWorldPos);
    float marchDist = min(maxDist, 144.0);
    if (marchDist <= 0.05) return vec4(0.0, 0.0, 0.0, 1.0);

    vec3 rayDir = targetWorldPos / max(maxDist, 1e-5);

#if VOLUMETRIC_QUALITY == 1
    const int STEPS = 8;
#elif VOLUMETRIC_QUALITY == 2
    const int STEPS = 14;
#elif VOLUMETRIC_QUALITY == 3
    const int STEPS = 20;
#else
    const int STEPS = VOLUMETRIC_STEPS;
#endif

    float stepSize = marchDist / float(STEPS);
    float t = stepSize * dither;

    float sunElev = sunWorldDir.y;
    vec3 activeLightDir = (sunElev > -0.05) ? sunWorldDir : moonWorldDir;
    float dayFactor = smoothstep(-0.08, 0.16, sunElev);
    float twilightFactor = smoothstep(-0.20, -0.01, sunElev) * (1.0 - smoothstep(0.02, 0.24, sunElev));

    // Mie forward-scattering phase function for dramatic God rays when looking near Sun/Moon
    float cosTheta = dot(rayDir, activeLightDir);
    float phase = (3.0 / (8.0 * PI)) * ((1.0 - 0.56) * (1.0 + cosTheta * cosTheta))
                / ((2.0 + 0.56) * pow(max(1.0 + 0.56 - 2.0 * 0.75 * cosTheta, 1e-3), 1.5));

    vec3 sunScatterColor = mix(
        mix(vec3(0.018, 0.032, 0.068) * MOONLIGHT_INTENSITY, vec3(1.10, 0.48, 0.18), twilightFactor),
        vec3(1.05, 0.96, 0.84) * SUNLIGHT_INTENSITY,
        dayFactor
    );
    vec3 ambientFogColor = mix(
        vec3(0.003, 0.005, 0.012),
        mix(vec3(0.32, 0.48, 0.72), vec3(0.65, 0.42, 0.28), twilightFactor),
        dayFactor
    );

    if (isEyeInWater > 0.5) {
        // Underwater Volumetric Caustic Light Shafts
        sunScatterColor *= vec3(0.14, 0.62, 0.78) * 1.45;
        ambientFogColor = vec3(0.02, 0.14, 0.22) * (0.25 + 0.75 * dayFactor);
    }

    vec3 accumScattering = vec3(0.0);
    float transmittance = 1.0;

    for (int i = 0; i < STEPS; i++) {
        if (transmittance < 0.02) break;
        vec3 sampleWorldOffset = rayDir * t;
        vec3 absWorldPos = sampleWorldOffset + cameraWorldPos;

        // Shadow map visibility check at sample position
        vec4 sView = shadowModelView * vec4(sampleWorldOffset, 1.0);
        vec4 sClip = shadowProjection * sView;
        sClip.xyz = distortShadowClipPos(sClip.xyz);
        vec3 sNDC = sClip.xyz * 0.5 + 0.5;

        vec3 shadowVis = vec3(1.0);
        if (all(greaterThan(sNDC, vec3(0.005))) && all(lessThan(sNDC, vec3(0.995)))) {
            float dOpaque = texture(shadowtex1, sNDC.xy).r;
            if (sNDC.z > dOpaque) {
                shadowVis = vec3(0.0);
            } else {
                float dAll = texture(shadowtex0, sNDC.xy).r;
                if (sNDC.z > dAll) {
                    // Colored volumetric light shaft passing through stained glass!
                    vec4 sc = texture(shadowcolor0, sNDC.xy);
                    shadowVis = srgbToLinear(sc.rgb) * (1.0 - sc.a * 0.55);
                }
            }
        }

        // Clean air density on clear days (prevents grey smog while keeping crisp God rays)
        float heightFalloff = exp(-max(absWorldPos.y - 62.0, 0.0) * 0.038);
        float mistNoise = 0.75 + 0.25 * noise3D(absWorldPos * 0.025 + vec3(time * 0.04, 0.0, time * 0.02));
        float density = (0.00045 + 0.0012 * heightFalloff * mistNoise) * (1.0 + rainStrength * 4.5);
        if (isEyeInWater > 0.5) {
            density = 0.038;
        }

        vec3 stepLight = sunScatterColor * shadowVis * (0.28 + phase * 1.85) + ambientFogColor * 0.22;
        float stepExt = density * stepSize;
        float stepTrans = exp(-stepExt);

        accumScattering += transmittance * (1.0 - stepTrans) * stepLight;
        transmittance *= stepTrans;

        t += stepSize;
    }

    return vec4(accumScattering, transmittance);
}

#endif // APPOLO_VOLUMETRICS_GLSL
