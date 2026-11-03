// ============================================================================
// Appolo v0.1 — Multi-Tier Ray-Marched Reflections & Dimension-Aware Environment
// Supports Water, Architectural Glass, Obsidian, Metals, Polished Stone & Rain
// ============================================================================
#ifndef APPOLO_REFLECTIONS_GLSL
#define APPOLO_REFLECTIONS_GLSL

#include "/lib/common.glsl"
#include "/lib/pbr.glsl"
#if DIMENSION_ID == 1
#include "/lib/sky_end.glsl"
#elif DIMENSION_ID == -1
#include "/lib/sky_nether.glsl"
#else
#include "/lib/sky_overworld.glsl"
#endif

// --- Evaluate Dimension-Specific Sky & Environment along World Reflection Vector ---
vec3 evaluateDimensionEnvironment(
    int dimensionId, // 0 = Overworld, -1 = Nether, 1 = The End
    vec3 worldReflDir,
    vec3 cameraWorldPos,
    vec3 sunWorldDir,
    vec3 moonWorldDir,
    int moonPhase,
    float rainStrength,
    vec3 vanillaFogColor,
    float time
) {
#if DIMENSION_ID == 1
    // The End: Reflect 3D Lit Solar System & Deep Space
    return evaluateEndSolarSystem(worldReflDir, cameraWorldPos, time);
#elif DIMENSION_ID == -1
    // The Nether: Reflect Volcanic Smoke, Lava Glow & Hellish Atmosphere
    return evaluateNetherSky(worldReflDir, cameraWorldPos, vanillaFogColor, time);
#else
    // Overworld: Reflect Daytime Sky, Clouds, Sunset, or Nighttime Milky Way, Stars & Moon
    vec3 sky = evaluateOverworldSky(worldReflDir, sunWorldDir, moonWorldDir, moonPhase, rainStrength);
    if (worldReflDir.y > 0.02) {
        vec4 clouds = evaluateOverworldClouds(worldReflDir, cameraWorldPos, sunWorldDir, moonWorldDir, time, rainStrength, 0.5);
        sky = mix(sky, clouds.rgb, clouds.a);
    }
    return sky;
#endif
}

// --- Screen-Space Ray Marching (SSRT) with Binary Refinement ---
vec4 traceScreenSpaceReflection(
    sampler2D sceneColorTex,
    sampler2D depthtex,
    vec3 viewOrigin,
    vec3 viewReflDir,
    mat4 projMatrix,
    mat4 projInv,
    float roughness,
    float dither
) {
#if REFLECTION_QUALITY == 1
    const int MAX_STEPS = 18;
#elif REFLECTION_QUALITY == 2
    const int MAX_STEPS = 28;
#elif REFLECTION_QUALITY == 3
    const int MAX_STEPS = 40;
#else
    const int MAX_STEPS = SSR_MAX_STEPS;
#endif

    // Prevent ray from marching behind the camera near plane
    float maxRayDist = 96.0;
    if (viewOrigin.z + viewReflDir.z * maxRayDist > -0.15) {
        maxRayDist = max((-0.15 - viewOrigin.z) / min(viewReflDir.z, -1e-4), 0.0);
    }
    if (maxRayDist <= 0.05) return vec4(0.0);

    vec3 startView = viewOrigin + viewReflDir * 0.045;
    vec3 marchPos  = startView;

    // Exponentially growing step size for both fine contact reflections & long-distance terrain reflections
    float stepScale = maxRayDist / float(MAX_STEPS);
    vec3 stepVec = viewReflDir * stepScale * 0.45;
    marchPos += stepVec * dither;

    vec2 hitUV = vec2(-1.0);
    bool hit = false;
    vec3 prevPos = startView;

    for (int i = 0; i < MAX_STEPS; i++) {
        vec4 clip = projMatrix * vec4(marchPos, 1.0);
        vec3 ndc  = clip.xyz / max(clip.w, 1e-5);
        vec2 uv   = ndc.xy * 0.5 + 0.5;

        if (uv.x < 0.002 || uv.x > 0.998 || uv.y < 0.002 || uv.y > 0.998 || ndc.z >= 1.0) {
            break;
        }

        float sceneDepth = texture(depthtex, uv).r;
        float rayDepth   = ndc.z * 0.5 + 0.5;

        if (rayDepth > sceneDepth && sceneDepth < 0.9999) {
            // Reconstruct linear view Z of scene sample to verify physical thickness
            vec4 sClip = vec4(uv * 2.0 - 1.0, sceneDepth * 2.0 - 1.0, 1.0);
            vec4 sView = projInv * sClip;
            float sceneViewZ = sView.z / max(sView.w, 1e-5);

            float thickness = marchPos.z - sceneViewZ;
            float allowedThickness = max(0.45, length(stepVec) * 2.4);

            if (thickness < 0.0 && abs(thickness) < allowedThickness) {
                // Binary search refinement (4 iterations) for sub-pixel reflection accuracy
                vec3 a = prevPos;
                vec3 b = marchPos;
                for (int j = 0; j < 4; j++) {
                    vec3 mid = 0.5 * (a + b);
                    vec4 mClip = projMatrix * vec4(mid, 1.0);
                    vec2 mUV = (mClip.xy / max(mClip.w, 1e-5)) * 0.5 + 0.5;
                    float mSceneDepth = texture(depthtex, mUV).r;
                    float mRayDepth = (mClip.z / max(mClip.w, 1e-5)) * 0.5 + 0.5;
                    if (mRayDepth > mSceneDepth) {
                        b = mid;
                        uv = mUV;
                    } else {
                        a = mid;
                    }
                }
                hitUV = uv;
                hit = true;
                break;
            }
        }

        prevPos = marchPos;
        stepVec *= 1.045;
        marchPos += stepVec;
    }

    if (!hit) return vec4(0.0);

    // Smooth vignette fade near screen borders so SSR transitions seamlessly into the analytical sky
    vec2 borderFade = smoothstep(vec2(0.0), vec2(0.08), hitUV) * smoothstep(vec2(1.0), vec2(0.92), hitUV);
    float confidence = borderFade.x * borderFade.y;

    vec3 hitColor = texture(sceneColorTex, hitUV).rgb;

    // Optional roughness-aware spatial blur for glossy-to-semi-rough materials
#ifdef ROUGHNESS_FILTERING
    if (roughness > 0.06) {
        float blurRadius = clamp(roughness * 0.012, 0.0, 0.008);
        vec3 c1 = texture(sceneColorTex, clamp(hitUV + vec2( blurRadius,  blurRadius), 0.001, 0.999)).rgb;
        vec3 c2 = texture(sceneColorTex, clamp(hitUV + vec2(-blurRadius,  blurRadius), 0.001, 0.999)).rgb;
        vec3 c3 = texture(sceneColorTex, clamp(hitUV + vec2( blurRadius, -blurRadius), 0.001, 0.999)).rgb;
        vec3 c4 = texture(sceneColorTex, clamp(hitUV + vec2(-blurRadius, -blurRadius), 0.001, 0.999)).rgb;
        hitColor = mix(hitColor, (c1 + c2 + c3 + c4) * 0.25, saturate(roughness * 2.5));
    }
#endif

    return vec4(hitColor, confidence);
}

// --- Complete Material-Specific Reflection & Fresnel Evaluation ---
vec3 evaluateMaterialReflection(
    int dimensionId,
    sampler2D sceneColorTex,
    sampler2D depthtex,
    vec3 viewPos,
    vec3 worldPos,
    vec3 cameraWorldPos,
    vec3 worldNormal,
    vec3 viewNormal,
    vec3 albedo,
    float roughness,
    float metalness,
    vec3 f0,
    int matId,
    float skyLight,
    float rainStrength,
    vec3 sunWorldDir,
    vec3 moonWorldDir,
    int moonPhase,
    vec3 vanillaFogColor,
    mat4 projMatrix,
    mat4 projInv,
    mat4 gbufferModelViewInverse,
    float time,
    float dither,
    out vec3 outFresnel
) {
    // Apply dynamic rain puddle wetness on upward-facing outdoor surfaces in the Overworld
    float effectiveRoughness = roughness;
    vec3  effectiveF0 = f0;
    if (dimensionId == 0 && rainStrength > 0.01 && matId != MAT_WATER && matId != MAT_LAVA) {
        float puddleNoise = smoothstep(0.42, 0.68, fbm2D(worldPos.xz * 0.35, 3));
        float wetMask = saturate(worldNormal.y) * smoothstep(0.65, 0.95, skyLight) * rainStrength * (0.45 + 0.55 * puddleNoise);
        effectiveRoughness = mix(effectiveRoughness, 0.035, wetMask);
        effectiveF0 = mix(effectiveF0, vec3(0.025), wetMask * (1.0 - metalness));
    }

    vec3 viewDir = normalize(viewPos);
    vec3 worldViewDir = normalize(mat3(gbufferModelViewInverse) * viewDir);
    float NdotV = max(dot(worldNormal, -worldViewDir), 1e-4);

    // Compute Material-Specific Physical Fresnel
    if (matId == MAT_WATER) {
        // Photon-style crisp dielectric Fresnel curve for water
        float fWater = fresnelDielectric(NdotV, 1.0, 1.333);
        float schlickWater = 0.055 + 0.925 * pow(1.0 - NdotV, 3.8);
        outFresnel = vec3(clamp(max(fWater, schlickWater), 0.055, 0.985));
    } else if (matId == MAT_GLASS) {
        float fGlass = fresnelDielectric(NdotV, 1.0, 1.52) * GLASS_REFLECTION_BOOST;
        outFresnel = vec3(clamp(fGlass, 0.04, 0.995));
    } else if (matId == MAT_OBSIDIAN) {
        // Volcanic Glass Obsidian: Deep dark-amethyst dielectric Fresnel (subtle at normal incidence, strong rim)
        float fObs = fresnelDielectric(NdotV, 1.0, 1.62);
        float rimCurve = 0.045 + 0.80 * pow(1.0 - NdotV, 3.6);
        vec3 obsTint = mix(vec3(0.76, 0.62, 0.98), vec3(0.90, 0.86, 1.00), 1.0 - NdotV);
        outFresnel = clamp(max(fObs * 0.75, rimCurve) * obsTint, vec3(0.042, 0.036, 0.058), vec3(0.82));
    } else {
        outFresnel = fresnelSchlickRoughness(NdotV, mix(effectiveF0, albedo, metalness), effectiveRoughness);
    }

    // Perturb reflection vector for rough surfaces & 3D volcanic glass parallax on Obsidian
    vec3 jitter = vec3(0.0);
    if (effectiveRoughness > 0.04) {
        vec2 xi = r2Sequence(int(dither * 64.0), dither) - 0.5;
        jitter = vec3(xi.x, xi.y * 0.5, xi.y) * (effectiveRoughness * effectiveRoughness * 0.35);
    }
    if (matId == MAT_OBSIDIAN) {
        // 3D subsurface conchoidal fracture parallax so Obsidian never projects a flat 2D skybox image
        vec3 absWorldPos = worldPos + cameraWorldPos;
        vec3 parallaxPos = absWorldPos * 3.8 + worldViewDir * 0.22;
        vec3 depthFracture = vec3(
            noise3D(parallaxPos + vec3(11.3, 4.7, 8.1)) - 0.5,
            noise3D(parallaxPos + vec3(23.9, 15.2, 3.4)) - 0.5,
            noise3D(parallaxPos + vec3(5.6, 31.8, 19.7)) - 0.5
        );
        vec3 viewFracture = mat3( transpose(mat3(gbufferModelViewInverse)) ) * depthFracture;
        jitter += viewFracture * 0.14;
    }

    vec3 perturbedViewNormal = normalize(viewNormal + jitter);
    vec3 viewReflDir = reflect(viewDir, perturbedViewNormal);
    vec3 worldReflDir = normalize(mat3(gbufferModelViewInverse) * viewReflDir);

    // 1. Evaluate Analytical Environment Reflection (Sky, Milky Way, Stars, Solar System, or Nether)
    vec3 envReflection = evaluateDimensionEnvironment(
        dimensionId,
        worldReflDir,
        cameraWorldPos,
        sunWorldDir,
        moonWorldDir,
        moonPhase,
        rainStrength,
        vanillaFogColor,
        time
    );

    // Attenuate sky reflection inside enclosed caves/interiors
    float interiorAtten = (dimensionId == 1) ? 0.68 : smoothstep(0.05, 0.65, skyLight);
    envReflection *= interiorAtten;

    // 2. Trace Screen-Space Reflection (SSRT) for local buildings, terrain, entities & light sources
    vec4 ssr = vec4(0.0);
    if (effectiveRoughness < 0.72) {
        ssr = traceScreenSpaceReflection(
            sceneColorTex,
            depthtex,
            viewPos,
            viewReflDir,
            projMatrix,
            projInv,
            effectiveRoughness,
            dither
        );
    }

    // Blend SSR hit with environment reflection
    vec3 combinedReflection = mix(envReflection, ssr.rgb, ssr.a);

    // Volcanic Glass Obsidian Depth Absorption & Color Grading
    // Prevents raw skybox images from pasting onto Obsidian; grades reflections through dark amethyst volcanic glass
    if (matId == MAT_OBSIDIAN) {
        float reflLuma = luma(combinedReflection);
        vec3 smokyAmethyst = vec3(reflLuma) * vec3(0.42, 0.30, 0.68);
        vec3 gradedHighlight = combinedReflection * vec3(0.78, 0.70, 0.95);
        vec3 volcanicGrade = mix(smokyAmethyst, gradedHighlight, smoothstep(0.06, 0.75, reflLuma));
        // Compress dim sky background while preserving crisp specular reflections of bright planets/sun/local blocks
        float depthWeight = mix(smoothstep(0.02, 0.55, reflLuma) * 0.55 + 0.18, 0.92, ssr.a);
        combinedReflection = volcanicGrade * depthWeight;
    }

    // Roughness energy preservation & specular occlusion
    float roughnessFade = 1.0 - smoothstep(0.55, 0.95, effectiveRoughness);
    if (matId == MAT_METAL) {
        combinedReflection *= mix(vec3(1.0), albedo, 0.85);
    }

    return combinedReflection * outFresnel * roughnessFade;
}

#endif // APPOLO_REFLECTIONS_GLSL
