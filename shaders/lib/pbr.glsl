// ============================================================================
// Appolo v0.1 — Ultra-Realistic Physically Based Rendering (PBR) Library
// Supports LabPBR 1.3 + Procedural Material Synthesis, Glass, Obsidian & Water
// ============================================================================
#ifndef APPOLO_PBR_GLSL
#define APPOLO_PBR_GLSL

#include "/lib/common.glsl"

struct MaterialPBR {
    vec3  albedo;
    vec3  normal;
    float roughness;
    float metalness;
    vec3  f0;
    float emission;
    float sss;
    float ao;
    float opacity;
    int   matId;
};

// --- Exact Dielectric Fresnel (Unpolarized Snell + Fresnel Equations) ---
float fresnelDielectric(float cosThetaI, float etaI, float etaT) {
    cosThetaI = clamp(cosThetaI, -1.0, 1.0);
    if (cosThetaI < 0.0) {
        float tmp = etaI;
        etaI = etaT;
        etaT = tmp;
        cosThetaI = abs(cosThetaI);
    }
    float sinThetaI = sqrt(max(0.0, 1.0 - cosThetaI * cosThetaI));
    float sinThetaT = (etaI / etaT) * sinThetaI;
    if (sinThetaT >= 1.0) return 1.0; // Total Internal Reflection
    float cosThetaT = sqrt(max(0.0, 1.0 - sinThetaT * sinThetaT));
    float rParl = ((etaT * cosThetaI) - (etaI * cosThetaT)) / max((etaT * cosThetaI) + (etaI * cosThetaT), 1e-5);
    float rperp = ((etaI * cosThetaI) - (etaT * cosThetaT)) / max((etaI * cosThetaI) + (etaT * cosThetaT), 1e-5);
    return saturate(0.5 * (rParl * rParl + rperp * rperp));
}

// --- Schlick Fresnel with Roughness Attenuation ---
vec3 fresnelSchlick(float cosTheta, vec3 f0) {
    return f0 + (1.0 - f0) * pow5(saturate(1.0 - cosTheta));
}

vec3 fresnelSchlickRoughness(float cosTheta, vec3 f0, float roughness) {
    return f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow5(saturate(1.0 - cosTheta));
}

// --- Hardcoded Metal F0 Table (LabPBR 1.3 Standard IDs 230..237) ---
vec3 getMetalF0FromCode(int code, vec3 baseAlbedo) {
    if (code == 230) return vec3(0.56, 0.57, 0.58); // Iron
    if (code == 231) return vec3(1.00, 0.78, 0.34); // Gold
    if (code == 232) return vec3(0.91, 0.92, 0.92); // Aluminum
    if (code == 233) return vec3(0.55, 0.56, 0.55); // Chrome
    if (code == 234) return vec3(0.95, 0.64, 0.54); // Copper
    if (code == 235) return vec3(0.63, 0.63, 0.64); // Lead
    if (code == 236) return vec3(0.67, 0.64, 0.59); // Platinum
    if (code == 237) return vec3(0.97, 0.96, 0.91); // Silver
    return clamp(baseAlbedo, vec3(0.04), vec3(0.99));
}

// --- Trowbridge-Reitz GGX Normal Distribution Function ---
float D_GGX(float NdotH, float alpha) {
    float a2 = max(alpha * alpha, 1e-4);
    float d = (NdotH * a2 - NdotH) * NdotH + 1.0;
    return a2 / max(PI * d * d, 1e-6);
}

// --- Smith Height-Correlated Masking-Shadowing Function ---
float V_SmithGGXCorrelated(float NdotV, float NdotL, float alpha) {
    float a2 = alpha * alpha;
    float ggxV = NdotL * sqrt(max(NdotV * NdotV * (1.0 - a2) + a2, 1e-6));
    float ggxL = NdotV * sqrt(max(NdotL * NdotL * (1.0 - a2) + a2, 1e-6));
    return 0.5 / max(ggxV + ggxL, 1e-5);
}

// --- Disney / Burley Diffuse BRDF ---
float Fd_Burley(float NdotV, float NdotL, float LdotH, float roughness) {
    float f90 = 0.5 + 2.0 * roughness * LdotH * LdotH;
    float lightScatter = 1.0 + (f90 - 1.0) * pow5(1.0 - NdotL);
    float viewScatter  = 1.0 + (f90 - 1.0) * pow5(1.0 - NdotV);
    return (lightScatter * viewScatter) * INV_PI;
}

// --- Photon-Style Multi-Cascade Smooth Analytical Water Wave Normal (Zero Texture Seams!) ---
float evaluateWaterWaveHeight(vec2 pos, float time, float rain) {
    float t = time * 1.15;
    float w = 0.0;

    // 5 Golden-Angle directional Gerstner-like swell cascades
    vec2 d0 = vec2( 0.866,  0.500);
    vec2 d1 = vec2(-0.540,  0.841);
    vec2 d2 = vec2( 0.284, -0.959);
    vec2 d3 = vec2(-0.960, -0.279);
    vec2 d4 = vec2( 0.754, -0.657);

    float ph0 = dot(pos, d0) * 1.15 + t * 1.55;
    float ph1 = dot(pos, d1) * 1.85 - t * 1.90 + sin(ph0) * 0.35;
    float ph2 = dot(pos, d2) * 3.10 + t * 2.45 + cos(ph1) * 0.28;
    float ph3 = dot(pos, d3) * 5.20 - t * 3.10;
    float ph4 = dot(pos, d4) * 8.40 + t * 3.85;

    // Trochoidal wave shaping (sharper crests, wide smooth troughs like real water)
    w += (1.0 - abs(sin(ph0 * 0.5))) * 0.052;
    w += sin(ph1) * 0.028;
    w += cos(ph2) * 0.015;
    w += sin(ph3) * 0.0075;
    w += cos(ph4) * 0.0038;

    // Smooth rotated capillary ripples (analytical value noise, no atlas seams)
    mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
    vec2 p1 = pos * 1.65 + vec2(t * 0.45, -t * 0.32);
    vec2 p2 = (rot * pos) * 3.80 - vec2(t * 0.68, t * 0.54);
    vec2 p3 = (rot * (rot * pos)) * 7.60 + vec2(-t * 0.95, t * 0.82);

    w += (noise2D(p1) - 0.5) * 0.026;
    w += (noise2D(p2) - 0.5) * 0.012;
    w += (noise2D(p3) - 0.5) * 0.005;

    if (rain > 0.01) {
        vec2 ripple = voronoi2D(pos * 5.5 + fract(time * 2.2));
        w += sin(ripple.x * 16.0 - time * 12.0) * exp(-ripple.x * 4.2) * 0.014 * rain;
    }

    return w * WATER_WAVE_HEIGHT * (1.0 + rain * 0.35);
}

vec3 getWaterWaveNormal(vec3 worldPos, float time, float rain) {
    if (WATER_WAVE_HEIGHT <= 0.001) return vec3(0.0, 1.0, 0.0);
    vec2 p = worldPos.xz;
    const float eps = 0.065;
    float h0 = evaluateWaterWaveHeight(p, time, rain);
    float hx = evaluateWaterWaveHeight(p + vec2(eps, 0.0), time, rain);
    float hz = evaluateWaterWaveHeight(p + vec2(0.0, eps), time, rain);
    return normalize(vec3((h0 - hx) / eps, 1.0, (h0 - hz) / eps));
}

// --- Photon-Style Dual-Layer Voronoi Underwater Caustics (Zero Texture Seams!) ---
vec3 computeWaterCaustics(vec3 worldPos, vec3 lightDir, float time) {
#ifndef WATER_CAUSTICS
    return vec3(0.0);
#else
    vec2 uv = worldPos.xz - lightDir.xz * (worldPos.y / max(abs(lightDir.y), 0.25));
    uv *= 0.78;
    float t = time * 0.68;

    mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
    vec2 uv1 = uv * 1.35 + vec2(t * 0.38, -t * 0.29);
    vec2 uv2 = (rot * uv) * 1.85 - vec2(t * 0.32, t * 0.44) + vec2(3.7, 1.9);

    vec2 vR1 = voronoi2D(uv1);
    vec2 vR2 = voronoi2D(uv2);
    vec2 vG1 = voronoi2D(uv1 + vec2(0.014, 0.010));
    vec2 vB1 = voronoi2D(uv1 - vec2(0.014, 0.010));

    float netR = pow(saturate(1.0 - abs(vR1.y - vR1.x) * 2.45), 3.4) + pow(saturate(1.0 - vR2.x * 1.12), 4.2) * 0.55;
    float netG = pow(saturate(1.0 - abs(vG1.y - vG1.x) * 2.45), 3.4) + pow(saturate(1.0 - vR2.x * 1.12), 4.2) * 0.55;
    float netB = pow(saturate(1.0 - abs(vB1.y - vB1.x) * 2.45), 3.4) + pow(saturate(1.0 - vR2.x * 1.12), 4.2) * 0.55;

    return vec3(netR, netG, netB) * 1.25;
#endif
}

// --- Obsidian Conchoidal Volcanic Glass Micro-Normal & 3D Faceted Relief ---
vec3 getObsidianMicroNormal(vec3 worldPos, vec3 baseNormal) {
    vec3 p1 = worldPos * 3.8;
    vec3 p2 = worldPos * 11.5;
    float nX = (noise3D(p1 + vec3(0.14, 0.0, 0.0)) - noise3D(p1 - vec3(0.14, 0.0, 0.0))) * 0.095
             + (noise3D(p2 + vec3(0.08, 0.0, 0.0)) - noise3D(p2 - vec3(0.08, 0.0, 0.0))) * 0.042;
    float nY = (noise3D(p1 + vec3(0.0, 0.14, 0.0)) - noise3D(p1 - vec3(0.0, 0.14, 0.0))) * 0.095
             + (noise3D(p2 + vec3(0.0, 0.08, 0.0)) - noise3D(p2 - vec3(0.0, 0.08, 0.0))) * 0.042;
    float nZ = (noise3D(p1 + vec3(0.0, 0.0, 0.14)) - noise3D(p1 - vec3(0.0, 0.0, 0.14))) * 0.095
             + (noise3D(p2 + vec3(0.0, 0.0, 0.08)) - noise3D(p2 - vec3(0.0, 0.0, 0.08))) * 0.042;
    vec3 perturb = vec3(nX, nY, nZ);
    perturb -= baseNormal * dot(perturb, baseNormal);
    return normalize(baseNormal + perturb);
}

// --- Photon-Style Molten Lava Enhancement (Preserves Texture & Adds Rich Magma Radiance) ---
void evaluateLavaMaterial(vec3 worldPos, float time, inout vec3 albedo, inout vec3 normal, out float emission, out float roughness) {
    float texHeat = clamp(luma(albedo) * 1.45, 0.0, 1.0);
    // Subtle 3D thermal convection variation that works on both horizontal lava lakes & vertical lavafalls
    float flowRipple = fbm3D(worldPos * 1.35 + vec3(time * 0.12, -time * 0.18, time * 0.09), 3);
    float heatFactor = clamp(texHeat * 0.78 + flowRipple * 0.28, 0.15, 1.0);

    // Rich molten crimson-orange cooler cells -> blazing golden-yellow/orange magma veins (never black!)
    vec3 moltenCrimson = vec3(0.88, 0.18, 0.02);
    vec3 blazingMagma  = vec3(1.00, 0.56, 0.10);
    vec3 whiteHotCore  = vec3(1.00, 0.88, 0.42);

    vec3 magmaGrade = mix(moltenCrimson, blazingMagma, smoothstep(0.15, 0.68, heatFactor));
    magmaGrade = mix(magmaGrade, whiteHotCore, smoothstep(0.68, 0.98, heatFactor));

    // Blend 65% of the resource-pack/vanilla lava texture with 35% physical thermal grading
    albedo = mix(max(albedo, vec3(0.28, 0.05, 0.008)), magmaGrade, 0.42);
    emission = clamp(0.58 + 0.42 * pow(heatFactor, 1.15), 0.55, 1.0);
    roughness = mix(0.28, 0.08, heatFactor);

    // Smooth liquid magma surface normal perturbation
    vec3 p = worldPos * 2.4 + vec3(time * 0.15, -time * 0.20, time * 0.12);
    vec3 nPerturb = vec3(
        noise3D(p + vec3(0.1, 0.0, 0.0)) - noise3D(p - vec3(0.1, 0.0, 0.0)),
        noise3D(p + vec3(0.0, 0.1, 0.0)) - noise3D(p - vec3(0.0, 0.1, 0.0)),
        noise3D(p + vec3(0.0, 0.0, 0.1)) - noise3D(p - vec3(0.0, 0.0, 0.1))
    ) * 0.12;
    nPerturb -= normal * dot(nPerturb, normal);
    normal = normalize(normal + nPerturb);
}

// --- Decode LabPBR 1.3 + Procedural Material Properties ---
MaterialPBR decodeMaterialPBR(
    vec4 baseTex,
    vec4 normalTex,
    vec4 specTex,
    vec3 geoNormal,
    mat3 tbn,
    vec3 worldPos,
    int matId,
    float time
) {
    MaterialPBR m;
    m.albedo = srgbToLinear(baseTex.rgb);
    m.opacity = baseTex.a;
    m.matId = matId;
    m.normal = geoNormal;
    m.roughness = 0.68;
    m.metalness = 0.0;
    m.f0 = vec3(0.04);
    m.emission = 0.0;
    m.sss = 0.0;
    m.ao = 1.0;

    // 1. Universal LabPBR 1.3 + UMSOEA (OldPBR/SEUS) Normal & Specular Decoding
#if PBR_MODE != 3
    bool hasCustomNormal = (normalTex.r > 0.02 && normalTex.g > 0.02 && normalTex.a > 0.01)
                        && (abs(normalTex.r - 0.5) > 0.008 || abs(normalTex.g - 0.5) > 0.008);
    if (hasCustomNormal) {
        vec2 nXY = clamp(normalTex.rg * 2.0 - 1.0, vec2(-0.90), vec2(0.90));
        float lenSq = dot(nXY, nXY);
        if (lenSq > 0.85) {
            nXY *= inversesqrt(lenSq) * 0.92;
        }
        float nZ = sqrt(max(0.08, 1.0 - dot(nXY, nXY)));
        vec3 mappedN = tbn * vec3(nXY, nZ);
        if (dot(mappedN, mappedN) > 1e-4) {
            m.normal = normalize(mappedN);
        }
        // In UMSOEA (OldPBR), normalTex.b is ~1.0 (normal Z); in LabPBR, normalTex.b is Material AO.
        m.ao = (normalTex.b > 0.55) ? 1.0 : clamp(normalTex.b * 1.65 + 0.35, 0.55, 1.0);
    }

    bool hasCustomSpec = (specTex.r > 0.005 || specTex.g > 0.005);
    if (hasCustomSpec) {
        float smoothness = clamp(specTex.r, 0.0, 0.96);
        m.roughness = clamp(sqr(1.0 - smoothness), 0.03, 0.98);
        int f0Code = int(specTex.g * 255.0 + 0.5);
        if (f0Code >= 230) {
            // LabPBR 1.3 Metalness Code
            m.metalness = 1.0;
            m.f0 = getMetalF0FromCode(f0Code, m.albedo);
        } else if (specTex.g > 0.25 && specTex.a > 0.95) {
            // UMSOEA (OldPBR) Continuous Metalness in Green Channel
            m.metalness = saturate((specTex.g - 0.20) / 0.70);
            m.f0 = mix(vec3(0.04), clamp(m.albedo, vec3(0.08), vec3(0.98)), m.metalness);
        } else {
            m.metalness = 0.0;
            m.f0 = vec3(clamp(specTex.g, 0.02, 0.12));
        }
        // NOTE: Do NOT set m.emission from specTex.a or specTex.b on non-emissive terrain blocks!
        // In UMSOEA (OldPBR), specTex.a is 1.0 (or mip-compressed ~0.96), which would falsely make normal blocks glow white!
    }
#endif

    // 2. Procedural Material Specialization & Enhancement
#if PBR_MODE != 2
    float texLuma = luma(m.albedo);

    if (matId == MAT_GLASS) {
        // Architectural Glass: High transparency, crystal-clear center, grazing dielectric Fresnel
        m.roughness = 0.022;
        m.metalness = 0.0;
        m.f0 = vec3(0.042 * GLASS_REFLECTION_BOOST); // IOR ~ 1.52
        float isBorder = smoothstep(0.55, 0.88, baseTex.a) * (1.0 - smoothstep(0.15, 0.45, abs(texLuma - 0.5)));
        if (baseTex.a < 0.12) {
            // Clear glass interior texels in vanilla have alpha = 0; restore subtle physical glass transmission
            m.albedo = vec3(0.88, 0.95, 0.98);
            m.opacity = 0.05;
        } else {
            // Stained glass or frame border
            m.opacity = clamp(baseTex.a * 0.48, 0.08, 0.82);
            m.roughness = mix(0.025, 0.14, isBorder);
        }
    }
    else if (matId == MAT_OBSIDIAN) {
        // Volcanic Glass Obsidian: Deep black & dark amethyst-purple with 3D conchoidal facets
        float purpleGlow = saturate((m.albedo.b - m.albedo.g) * 3.5 + (m.albedo.r - m.albedo.g) * 2.0);
        float facetVar = fbm3D(worldPos * 3.2, 3);
        // Deep volcanic body coloration with subtle internal purple-indigo depth variation
        m.albedo = mix(m.albedo * vec3(0.38, 0.28, 0.62), vec3(0.008, 0.005, 0.018), 0.52);
        // Vary roughness between glossy volcanic cleavage facets (0.045) and rougher stone ridges (0.26)
        m.roughness = clamp(mix(0.045, 0.26, smoothstep(0.02, 0.16, texLuma) * 0.65 + (1.0 - facetVar) * 0.35), 0.04, 0.32);
        m.metalness = 0.0;
        m.f0 = vec3(0.054, 0.048, 0.070);
        m.normal = getObsidianMicroNormal(worldPos, m.normal);
        // Crying Obsidian glowing violet veins
        if (purpleGlow > 0.24 && texLuma > 0.09) {
            m.emission = saturate(purpleGlow * 1.6);
            m.albedo = mix(m.albedo, vec3(0.55, 0.12, 0.95), saturate(purpleGlow));
        }
    }
    else if (matId == MAT_WATER) {
        m.albedo = vec3(0.04, 0.19, 0.28);
        m.roughness = 0.018;
        m.metalness = 0.0;
        m.f0 = vec3(0.0204); // Water IOR = 1.333
        m.opacity = 0.15;
    }
    else if (matId == MAT_LAVA) {
        evaluateLavaMaterial(worldPos, time, m.albedo, m.normal, m.emission, m.roughness);
        m.f0 = vec3(0.06);
        m.opacity = 1.0;
    }
    else if (matId == MAT_EMISSIVE_WARM) {
        m.emission = max(m.emission, clamp(0.45 + texLuma * 0.85, 0.50, 1.0));
        m.roughness = 0.35;
    }
    else if (matId == MAT_EMISSIVE_COOL) {
        m.emission = max(m.emission, clamp(0.50 + texLuma * 0.80, 0.55, 1.0));
        m.roughness = 0.22;
        m.f0 = vec3(0.05);
    }
    else if (matId == MAT_EMISSIVE_SOUL) {
        m.emission = max(m.emission, 0.90);
        m.roughness = 0.30;
    }
    else if (matId == MAT_METAL) {
        m.metalness = 1.0;
        m.roughness = clamp(0.14 + (1.0 - texLuma) * 0.28, 0.08, 0.52);
        m.f0 = clamp(m.albedo * 1.05, vec3(0.45), vec3(0.99));
    }
    else if (matId == MAT_POLISHED) {
        m.metalness = 0.0;
        m.roughness = clamp(0.08 + (1.0 - texLuma) * 0.18, 0.05, 0.30);
        m.f0 = vec3(0.052);
    }
    else if (matId == MAT_ICE) {
        m.metalness = 0.0;
        m.roughness = 0.06;
        m.f0 = vec3(0.018); // Ice IOR = 1.31
        m.sss = 0.65;
    }
    else if (matId == MAT_FOLIAGE) {
        m.metalness = 0.0;
        m.roughness = clamp(0.52 - texLuma * 0.15, 0.35, 0.72);
        m.f0 = vec3(0.035);
        m.sss = 0.75;
    }
    else if (matId == MAT_VOLCANIC) {
        // Nether Basalt, Blackstone & Netherrack: Rough volcanic rock with specular mineral glints
        float mineralGlint = smoothstep(0.18, 0.45, texLuma);
        m.roughness = mix(0.82, 0.32, mineralGlint);
        m.f0 = mix(vec3(0.038), vec3(0.065), mineralGlint);
    }
    else {
        // Default Terrain Blocks: Derive subtle micro-roughness variation from texture luminance
        m.roughness = clamp(0.76 - (texLuma - 0.25) * 0.28, 0.38, 0.92);
        m.f0 = vec3(0.04);
    }
#endif

    return m;
}

// --- Full Cook-Torrance + Burley Direct Lighting Evaluation ---
vec3 evaluatePBRDirect(
    vec3 N,
    vec3 V,
    vec3 L,
    vec3 albedo,
    float roughness,
    float metalness,
    vec3 f0,
    float sss,
    int matId,
    vec3 lightRadiance
) {
    vec3 H = normalize(V + L);
    float NdotV = max(abs(dot(N, V)), 1e-4);
    float NdotL = max(dot(N, L), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float LdotH = max(dot(L, H), 0.0);

    float alpha = max(roughness * roughness, 0.002);

    // Specular BRDF (Cook-Torrance GGX, energy-clamped to prevent white fireflies on smooth UMSOEA surfaces)
    float D = D_GGX(NdotH, alpha);
    float Vis = V_SmithGGXCorrelated(NdotV, max(NdotL, 1e-4), alpha);
    vec3  F = fresnelSchlick(LdotH, mix(f0, albedo, metalness));
    vec3  specular = min(D * Vis, 6.5) * F;

    // Obsidian Dual-Lobe Volcanic Clearcoat Specular
    if (matId == MAT_OBSIDIAN) {
        float clearcoatAlpha = 0.012;
        float Dc = D_GGX(NdotH, clearcoatAlpha);
        float Vc = V_SmithGGXCorrelated(NdotV, max(NdotL, 1e-4), clearcoatAlpha);
        float Fc = fresnelDielectric(LdotH, 1.0, 1.62);
        specular += vec3(0.72, 0.58, 0.95) * (min(Dc * Vc, 5.0) * Fc * 0.48);
    }

    // Energy-conserving Diffuse BRDF (Burley)
    vec3 kD = (vec3(1.0) - F) * (1.0 - metalness);
    float fd = Fd_Burley(NdotV, NdotL, LdotH, roughness);
    vec3 diffuse = kD * albedo * fd * NdotL;

    // Subsurface Scattering Transmission (Foliage, Ice, Thin Geometry)
    vec3 transmission = vec3(0.0);
    if (sss > 0.01) {
        float backLight = saturate(dot(-N, L) * 0.65 + 0.35);
        float phase = pow(saturate(dot(V, -L)), 3.0) * 0.6 + 0.4;
        transmission = albedo * sqrt(max(albedo, vec3(0.01))) * backLight * phase * sss * INV_PI;
    }

    return (diffuse + specular * NdotL + transmission) * lightRadiance;
}

#endif // APPOLO_PBR_GLSL
