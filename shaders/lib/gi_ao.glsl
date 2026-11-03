// ============================================================================
// Appolo v0.1 — Ground-Truth Ambient Occlusion (GTAO) & Hybrid Global Illumination
// Includes RSM Sunlight Bounce, Screen-Space Path GI & Dynamic Lava/Emissive GI
// ============================================================================
#ifndef APPOLO_GI_AO_GLSL
#define APPOLO_GI_AO_GLSL

#include "/lib/common.glsl"

// --- Reconstruct View-Space Position from Screen UV & Depth ---
vec3 reconstructViewPos(vec2 uv, float depth, mat4 projInv) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = projInv * clip;
    return view.xyz / max(view.w, 1e-6);
}

// --- Multi-Bounce Albedo AO Approximation (Jimenez et al. 2016) ---
vec3 gtaoMultiBounce(float visibility, vec3 albedo) {
    vec3 a =  2.0404 * albedo - 0.3324;
    vec3 b = -4.7951 * albedo + 0.6417;
    vec3 c =  2.7552 * albedo + 0.6903;
    float x = saturate(visibility);
    return max(vec3(x), ((x * a + b) * x + c) * x);
}

// --- Ground-Truth Ambient Occlusion (GTAO) + Bent Normal ---
vec4 computeGTAO(
    sampler2D depthtex,
    vec2 uv,
    vec3 viewPos,
    vec3 viewNormal,
    mat4 projInv,
    float dither
) {
    if (AO_INTENSITY <= 0.01) return vec4(viewNormal, 1.0);

    float viewDist = max(-viewPos.z, 0.5);
    float radiusUV = clamp(0.11 / viewDist, 0.004, 0.055);
    const int DIRECTIONS = 4;
    const int STEPS = 4;

    float aoAccum = 0.0;
    vec3 bentNormal = viewNormal * 0.5;

    for (int d = 0; d < DIRECTIONS; d++) {
        float angle = (float(d) + dither) * (PI / float(DIRECTIONS));
        vec2 dir = vec2(cos(angle), sin(angle));

        for (int s = 1; s <= STEPS; s++) {
            float stepFrac = (float(s) - 0.35 + dither * 0.3) / float(STEPS);
            vec2 sampleUV = uv + dir * radiusUV * stepFrac;
            if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) continue;

            float sDepth = texture(depthtex, sampleUV).r;
            if (sDepth >= 0.9999) continue;

            vec3 sViewPos = reconstructViewPos(sampleUV, sDepth, projInv);
            vec3 diff = sViewPos - viewPos;
            float dist2 = dot(diff, diff);
            float dist = sqrt(max(dist2, 1e-5));
            vec3 horizonDir = diff / dist;

            // Smooth range attenuation so distant geometry doesn't create dark halos
            float falloff = saturate(1.0 - dist / 2.6);
            float cosAng = saturate(dot(viewNormal, horizonDir) - 0.06);
            float occ = cosAng * falloff * falloff;
            aoAccum += occ;
            bentNormal -= horizonDir * occ * 0.25;
        }
    }

    float normAO = 1.0 - saturate((aoAccum / float(DIRECTIONS * STEPS)) * 2.35 * AO_INTENSITY);
    return vec4(normalize(bentNormal), clamp(normAO, 0.04, 1.0));
}

// --- Reflective Shadow Map (RSM) Indirect Sunlight Bounce ---
vec3 evaluateRSMIndirectBounce(
    sampler2D shadowtex1,
    sampler2D shadowcolor0,
    sampler2D shadowcolor1,
    vec3 worldPos,
    vec3 worldNormal,
    mat4 shadowModelView,
    mat4 shadowProjection,
    vec3 sunIrradiance,
    float dither
) {
#if GI_QUALITY < 3
    return vec3(0.0);
#else
    vec4 shadowView = shadowModelView * vec4(worldPos, 1.0);
    vec4 shadowClip = shadowProjection * shadowView;
    float distortFactor = mix(1.0, length(shadowClip.xy), 0.86);
    shadowClip.xy /= max(distortFactor, 1e-4);
    shadowClip.z *= 0.25;
    vec3 shadowNDC = shadowClip.xyz * 0.5 + 0.5;

    if (any(lessThan(shadowNDC.xy, vec2(0.03))) || any(greaterThan(shadowNDC.xy, vec2(0.97)))) {
        return vec3(0.0);
    }

    const int RSM_SAMPLES = 8;
    float rsmRadius = 0.016 / max(distortFactor, 0.2);
    float phi = dither * TAU;
    vec3 bounceAccum = vec3(0.0);

    for (int i = 0; i < RSM_SAMPLES; i++) {
        float r = sqrt((float(i) + 0.5) / float(RSM_SAMPLES)) * rsmRadius;
        float theta = float(i) * GOLDEN_ANGLE + phi;
        vec2 sampleUV = shadowNDC.xy + vec2(cos(theta), sin(theta)) * r;

        float sDepth = texture(shadowtex1, sampleUV).r;
        if (sDepth >= 0.999) continue;

        vec3 fluxAlbedo = srgbToLinear(texture(shadowcolor0, sampleUV).rgb);
        vec3 sNormal = decodeNormal(texture(shadowcolor1, sampleUV).rgb);

        // Estimate directional transfer between virtual point light (VPL) and receiver
        float depthDelta = (shadowNDC.z - sDepth) * 64.0;
        vec3 vplToReceiver = normalize(vec3(( shadowNDC.xy - sampleUV ) * 24.0, depthDelta));
        float emitWeight = max(0.0, dot(sNormal, vplToReceiver));
        float recvWeight = max(0.0, dot(worldNormal, -vplToReceiver) * 0.65 + 0.35);
        float distAtten  = 1.0 / (1.0 + depthDelta * depthDelta * 0.35);

        bounceAccum += fluxAlbedo * emitWeight * recvWeight * distAtten;
    }

    return (bounceAccum / float(RSM_SAMPLES)) * sunIrradiance * 0.85 * GI_BOUNCE_INTENSITY;
#endif
}

// --- Screen-Space Ray-Marched Global Illumination (SSGI) + Dynamic Emissive / Lava Bounce ---
vec3 evaluateScreenSpaceGI(
    sampler2D colortex0,
    sampler2D colortex1,
    sampler2D colortex2,
    sampler2D depthtex,
    vec2 uv,
    vec3 viewPos,
    vec3 viewNormal,
    vec3 worldNormal,
    mat4 projInv,
    mat4 gbufferModelViewInverse,
    float dither
) {
#if GI_QUALITY == 0
    return vec3(0.0);
#else
    #if GI_QUALITY == 1
        const int GI_RAYS = 4;
    #elif GI_QUALITY == 2
        const int GI_RAYS = 8;
    #else
        const int GI_RAYS = 12;
    #endif

    float viewDist = max(-viewPos.z, 0.5);
    float maxSearchUV = clamp(0.32 / sqrt(viewDist), 0.025, 0.22);
    float phi = dither * TAU;

    vec3 giAccum = vec3(0.0);
    float weightSum = 0.001;

    for (int i = 0; i < GI_RAYS; i++) {
        float frac = (float(i) + 0.5) / float(GI_RAYS);
        float radius = frac * frac * maxSearchUV;
        float theta = float(i) * GOLDEN_ANGLE + phi;
        vec2 sampleUV = uv + vec2(cos(theta), sin(theta)) * radius;

        if (sampleUV.x < 0.01 || sampleUV.x > 0.99 || sampleUV.y < 0.01 || sampleUV.y > 0.99) continue;

        float sDepth = texture(depthtex, sampleUV).r;
        if (sDepth >= 0.9999) continue;

        vec3 sViewPos = reconstructViewPos(sampleUV, sDepth, projInv);
        vec3 diff = sViewPos - viewPos;
        float dist2 = dot(diff, diff);
        if (dist2 > 64.0 || dist2 < 1e-4) continue;

        float invDist = inversesqrt(dist2);
        vec3 dir = diff * invDist;

        // Cosine hemisphere weight on the receiving surface
        float recvCos = max(dot(viewNormal, dir), 0.0);
        if (recvCos <= 0.01) continue;

        vec4 sCol0 = texture(colortex0, sampleUV);
        vec4 sCol1 = texture(colortex1, sampleUV);
        vec4 sCol2 = texture(colortex2, sampleUV);

        vec3 sAlbedo = srgbToLinear(sCol0.rgb);
        vec3 sWorldNormal = decodeNormal(sCol1.rgb);
        vec3 sViewNormal = mat3( transpose(gbufferModelViewInverse) ) * sWorldNormal;

        // Emitter surface facing check (facing toward receiver or omnidirectional if strongly emissive)
        float sEmission = sCol2.g;
        float sBlockLight = sCol2.b;
        float emitCos = mix(max(dot(sViewNormal, -dir), 0.15), 1.0, saturate(sEmission * 2.0));

        // Distance attenuation (inverse-square with smooth near clamp)
        float atten = 1.0 / (1.0 + dist2 * 0.22);

        // Estimate radiance leaving the sampled texel (sky light + block light + emission)
        float sSkyLight = sCol2.a;
        vec3 sampleRadiance = sAlbedo * (sSkyLight * sSkyLight * 1.2 + sBlockLight * sBlockLight * vec3(1.5, 0.85, 0.42));

        // Boost warm orange-red illumination from Lava & Luminous blocks
        if (sEmission > 0.05) {
            sampleRadiance += sAlbedo * (sEmission * 6.5 * DYNAMIC_LAVA_LIGHT);
        }

        giAccum += sampleRadiance * recvCos * emitCos * atten;
        weightSum += 1.0;
    }

    return (giAccum / weightSum) * 1.45 * GI_BOUNCE_INTENSITY;
#endif
}

// --- Physically Plausible Block / Torch / Lava Light Attenuation ---
vec3 evaluateDynamicBlockLight(
    float blockLightCoord,
    float skyLightCoord,
    vec3 worldPos,
    vec3 worldNormal,
    float emission,
    int matId,
    float time
) {
    // Convert vanilla linear [0..1] lightmap into physical inverse-square falloff
    float bl = saturate(blockLightCoord);
    float physicalFalloff = pow(bl, 3.35) + bl * bl * 0.18;

    // Subtle organic flicker for fire/lava/torches
    float flicker = 1.0 + (noise3D(worldPos * 0.65 + vec3(0.0, time * 2.8, 0.0)) - 0.5) * 0.06 * smoothstep(0.4, 0.95, bl);

    // Warm blackbody spectrum (2300K at distance -> 3100K near source)
    vec3 warmLightColor = mix(vec3(1.0, 0.34, 0.08), vec3(1.0, 0.68, 0.32), bl);
    if (matId == MAT_EMISSIVE_SOUL) {
        warmLightColor = vec3(0.18, 0.78, 1.0); // Soul fire turquoise
    } else if (matId == MAT_EMISSIVE_COOL) {
        warmLightColor = vec3(0.58, 0.92, 1.0); // Sea lantern / Beacon cyan-white
    }

    // Directional bump responsiveness so normal-mapped stone catches warm light relief
    vec3 synthLightDir = normalize(vec3(
        sin(worldPos.x * 0.5) * 0.4,
        0.75,
        cos(worldPos.z * 0.5) * 0.4
    ));
    float normalRelief = clamp(dot(worldNormal, synthLightDir) * 0.45 + 0.65, 0.30, 1.15);

    return warmLightColor * physicalFalloff * flicker * normalRelief * 2.15 * DYNAMIC_LAVA_LIGHT;
}

#endif // APPOLO_GI_AO_GLSL
