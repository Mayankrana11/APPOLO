// ============================================================================
// Appolo v0.1 — Composite Pass 0: Water, Architectural Glass, Obsidian &
//               Ray-Marched Screen-Space + Environment Reflections
// Reads from colortex4 (Pre-Translucent HDR Scene) and Writes to colortex0
// ============================================================================
#include "/lib/common.glsl"
#include "/lib/pbr.glsl"
#include "/lib/shadows.glsl"
#include "/lib/gi_ao.glsl"
#include "/lib/reflections.glsl"

#ifndef DIMENSION_ID
#define DIMENSION_ID 0
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex7;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 fogColor;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform int frameCounter;
uniform int moonPhase;
uniform int isEyeInWater;

in vec2 vTexCoord;

/* RENDERTARGETS: 0,3 */
/* DRAWBUFFERS:03 */
layout(location = 0) out vec4 outColor0;
layout(location = 1) out vec4 outColor3;

void writeCompositeOutput(vec4 c) {
    outColor0 = c;
    outColor3 = c;
}

void main() {
    float depth0 = texture(depthtex0, vTexCoord).r; // Includes translucent geometry (Water, Glass, Ice)
    float depth1 = texture(depthtex1, vTexCoord).r; // Opaque geometry only

    if (depth0 >= 0.9999) {
        writeCompositeOutput(texture(colortex0, vTexCoord));
        return;
    }

    vec4 g1 = texture(colortex1, vTexCoord);
    vec4 g2 = texture(colortex2, vTexCoord);
    vec4 g3 = texture(colortex3, vTexCoord);
    vec4 g7 = texture(colortex7, vTexCoord);

    vec3  worldNormal = decodeNormal(g1.rgb);
    float roughness   = g1.a;
    vec3  geoNormal   = decodeNormal(g7.rgb);
    int   matId       = decodeMatId(g7.a);

    float packedSpec  = g2.r;
    float metalness   = (packedSpec > 0.50) ? 1.0 : 0.0;
    float emission    = g2.g;
    float blockLight  = g2.b;
    float skyLight    = g2.a;

    vec3 viewPos = reconstructViewPos(vTexCoord, depth0, gbufferProjectionInverse);
    vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 absWorldPos = worldPos + cameraPosition;
    vec3 viewNormal = normalize(mat3(gbufferModelView) * worldNormal);
    vec3 worldDir = normalize(worldPos);
    vec3 V = -worldDir;

    vec3 sunWorldDir  = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    vec3 moonWorldDir = normalize(mat3(gbufferModelViewInverse) * normalize(moonPosition));
    float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);

    // Active directional light for specular highlights on Water, Glass & Obsidian
    vec3 activeLightDir = sunWorldDir;
    vec3 activeLightRad = vec3(3.15, 2.95, 2.75) * SUNLIGHT_INTENSITY;
#if DIMENSION_ID == 1
    activeLightDir = END_SUN_DIR;
    activeLightRad = vec3(2.65, 2.48, 2.28) * END_SUN_INTENSITY;
#elif DIMENSION_ID == -1
    activeLightDir = normalize(vec3(0.18, 0.92, -0.35));
    activeLightRad = vec3(1.45, 0.35, 0.06) * LAVA_EMISSION_STRENGTH;
#else
    if (sunWorldDir.y <= -0.04) {
        activeLightDir = moonWorldDir;
        activeLightRad = vec3(0.045, 0.072, 0.135) * max(moonWorldDir.y, 0.0) * MOONLIGHT_INTENSITY;
    } else {
        float sunMass = clamp(1.0 / max(sunWorldDir.y + 0.14, 0.03), 1.0, 20.0);
        activeLightRad *= exp(-vec3(0.058, 0.135, 0.331) * 0.42 * sunMass) * smoothstep(-0.06, 0.14, sunWorldDir.y);
    }
    activeLightRad *= (1.0 - rainStrength * 0.78);
#endif

    bool isTranslucentLayer = (depth0 < depth1 - 1e-6) || (matId == MAT_WATER) || (matId == MAT_GLASS) || (matId == MAT_ICE) || (matId == MAT_PORTAL);

    // ========================================================================
    // CASE A: PHOTON-STYLE ULTRA-REALISTIC WATER (Smooth Analytical Waves,
    //         Beer-Lambert Azure Absorption, Caustics & Crisp Reflections)
    // ========================================================================
    if (isTranslucentLayer && matId == MAT_WATER) {
        // Smooth Screen-Space Wave Refraction
        vec2 waveOffset = (worldNormal.xz - geoNormal.xz) * clamp(0.055 / max(length(viewPos) * 0.16, 1.0), 0.002, 0.042);
        vec2 refractUV = clamp(vTexCoord + waveOffset, vec2(0.002), vec2(0.998));
        float refractedOpaqueDepth = texture(depthtex1, refractUV).r;
        if (refractedOpaqueDepth < depth0) {
            refractUV = vTexCoord;
            refractedOpaqueDepth = depth1;
        }

        vec3 seabedRadiance = texture(colortex4, refractUV).rgb;
        vec3 refractedOpaqueView = reconstructViewPos(refractUV, refractedOpaqueDepth, gbufferProjectionInverse);
        vec3 refractedWorldPos = (gbufferModelViewInverse * vec4(refractedOpaqueView, 1.0)).xyz + cameraPosition;
        float trueWaterDepth = max(length(refractedOpaqueView - viewPos), 0.05);

        // Projected Underwater Voronoi Caustics on Sunlit Seabed
        if (refractedOpaqueDepth < 0.9999 && DIMENSION_ID == 0) {
            vec3 caustics = computeWaterCaustics(refractedWorldPos, activeLightDir, frameTimeCounter);
            float causticAtten = exp(-trueWaterDepth * 0.14) * smoothstep(0.1, 0.75, skyLight) * smoothstep(-0.02, 0.20, activeLightDir.y);
            seabedRadiance *= (vec3(1.0) + caustics * causticAtten * 0.85);
        }

        // Photon-Style Beer-Lambert Spectral Water Absorption & Subsurface Scattering
        // Rapidly absorbs red/orange, leaving a clean crystal-aquamarine shallow tint -> deep sapphire ocean volume
        float opticalDepth = (trueWaterDepth + 0.45) * WATER_ABSORPTION_SCALE;
        vec3 absorptionCoeff = vec3(0.74, 0.18, 0.038);
        vec3 waterTransmittance = exp(-absorptionCoeff * opticalDepth);

        float skyLightFactor = max(smoothstep(0.02, 0.75, skyLight), 0.12);
        float waterLightEnergy = max(luma(activeLightRad) * 0.34, 0.08) * skyLightFactor + blockLight * 0.22;

        vec3 shallowTealAzure = vec3(0.028, 0.220, 0.440);
        vec3 deepOceanBlue    = vec3(0.008, 0.078, 0.245);
        float depthFactor     = 1.0 - exp(-trueWaterDepth * 0.24);
        vec3 waterScatterCol  = mix(shallowTealAzure, deepOceanBlue, depthFactor) * waterLightEnergy;

        // Combine refracted seabed with volumetric water scattering (no blotchy noise foam!)
        vec3 underwaterColor = seabedRadiance * waterTransmittance + waterScatterCol * (vec3(1.0) - waterTransmittance * 0.68);

        // Evaluate Full Reflections (Ray-Marched SSR + Sky / Clouds / Milky Way / Stars / Terrain)
        vec3 waterFresnel;
        vec3 reflectionRadiance = evaluateMaterialReflection(
            DIMENSION_ID,
            colortex4,
            depthtex1,
            viewPos,
            worldPos,
            cameraPosition,
            worldNormal,
            viewNormal,
            vec3(0.02, 0.18, 0.38),
            0.015,
            0.0,
            vec3(0.032),
            MAT_WATER,
            skyLight,
            rainStrength,
            sunWorldDir,
            moonWorldDir,
            moonPhase,
            fogColor,
            gbufferProjection,
            gbufferProjectionInverse,
            gbufferModelViewInverse,
            frameTimeCounter,
            dither,
            waterFresnel
        );

        // Photon-Style Dual-Lobe Solar / Lunar Specular Glint on Wave Facets
        vec3 pcssShadow = vec3(1.0);
#if DIMENSION_ID == 0
        pcssShadow = evaluatePCSSShadow(
            shadowtex0, shadowtex1, shadowcolor0,
            worldPos, geoNormal, activeLightDir,
            shadowModelView, shadowProjection, dither
        );
#endif
        vec3 H = normalize(V + activeLightDir);
        float NdotH = max(dot(worldNormal, H), 0.0);
        float NdotL = max(dot(worldNormal, activeLightDir), 0.0);
        float NdotV = max(dot(worldNormal, V), 1e-4);
        float D1 = min(D_GGX(NdotH, 0.020), 22.0);
        float D2 = min(D_GGX(NdotH, 0.075), 4.0) * 0.35;
        float Vis = V_SmithGGXCorrelated(NdotV, max(NdotL, 1e-4), 0.025);
        vec3 sunGlint = (D1 + D2) * Vis * waterFresnel * NdotL * activeLightRad * pcssShadow;

        vec3 finalWater = mix(underwaterColor, reflectionRadiance, waterFresnel) + sunGlint;
        writeCompositeOutput(vec4(max(finalWater, vec3(0.0)), 1.0));
        return;
    }

    // ========================================================================
    // CASE B: ARCHITECTURAL GLASS, STAINED GLASS, ICE & PORTALS
    // ========================================================================
    if (isTranslucentLayer && (matId == MAT_GLASS || matId == MAT_ICE || matId == MAT_PORTAL)) {
        vec3 glassAlbedo = srgbToLinear(g3.rgb);
        float glassOpacity = g3.a;

        // Dual-interface architectural glass refraction offset
        vec2 refractUV = vTexCoord;
#ifdef GLASS_REFRACTION
        vec2 glassOffset = (viewNormal.xy) * 0.012 * (1.0 - abs(dot(worldNormal, V)));
        if (matId == MAT_ICE) glassOffset *= 2.2;
        vec2 candidateUV = clamp(vTexCoord + glassOffset, vec2(0.002), vec2(0.998));
        if (texture(depthtex1, candidateUV).r > depth0) {
            refractUV = candidateUV;
        }
#endif
        vec3 behindGlassRadiance = texture(colortex4, refractUV).rgb;

        // Evaluate Dielectric Glass Fresnel (IOR = 1.52) & SSR + Sky/Building Reflections
        vec3 glassFresnel;
        vec3 glassReflection = evaluateMaterialReflection(
            DIMENSION_ID,
            colortex4,
            depthtex1,
            viewPos,
            worldPos,
            cameraPosition,
            worldNormal,
            viewNormal,
            glassAlbedo,
            roughness,
            0.0,
            vec3(0.042 * GLASS_REFLECTION_BOOST),
            MAT_GLASS,
            skyLight,
            rainStrength,
            sunWorldDir,
            moonWorldDir,
            moonPhase,
            fogColor,
            gbufferProjection,
            gbufferProjectionInverse,
            gbufferModelViewInverse,
            frameTimeCounter,
            dither,
            glassFresnel
        );

        // Spectral Transmission for Clear vs Stained Glass
        // Clear glass has high luminance and low saturation -> ~96% transparent at normal incidence!
        float saturation = max3(glassAlbedo) - min3(glassAlbedo);
        bool isStainedGlass = (saturation > 0.08) || (luma(glassAlbedo) < 0.72);
        vec3 transmissionFilter = isStainedGlass
            ? mix(vec3(1.0), clamp(glassAlbedo * 1.25, vec3(0.05), vec3(1.0)), clamp(glassOpacity * 1.35, 0.25, 0.88))
            : vec3(0.96, 0.98, 0.99);

        // Subtle glass edge / grazing thickness absorption (slight green-cyan architectural glass edge tint)
        float NdotV = max(dot(worldNormal, V), 1e-4);
        float pathLength = 1.0 / max(sqrt(1.0 - (1.0 - NdotV * NdotV) / (1.52 * 1.52)), 0.35);
        vec3 architecturalEdgeTint = exp(-vec3(0.025, 0.008, 0.012) * pathLength);
        vec3 transmittedRadiance = behindGlassRadiance * transmissionFilter * architecturalEdgeTint * (vec3(1.0) - glassFresnel);

        // Direct Specular Highlight + Frame Border Illumination from Sunlight / Artificial Light
        vec3 H = normalize(V + activeLightDir);
        float NdotH = max(dot(worldNormal, H), 0.0);
        float NdotL = max(dot(worldNormal, activeLightDir), 0.0);
        float alpha = max(roughness * roughness, 0.002);
        float D = D_GGX(NdotH, alpha);
        float Vis = V_SmithGGXCorrelated(NdotV, max(NdotL, 1e-4), alpha);
        vec3 directSpec = D * Vis * glassFresnel * NdotL * activeLightRad;

        // Artificial block light reflection on glass panes at night / indoors
        vec3 artificialSpec = glassAlbedo * pow(blockLight, 3.0) * vec3(1.0, 0.65, 0.32) * 0.35;
        if (matId == MAT_PORTAL) {
            artificialSpec += glassAlbedo * 3.5;
        }

        vec3 finalGlass = transmittedRadiance + glassReflection + directSpec + artificialSpec;
        writeCompositeOutput(vec4(max(finalGlass, vec3(0.0)), 1.0));
        return;
    }

    // ========================================================================
    // CASE C: OPAQUE MATERIALS (Obsidian, Metals, Polished Stone & Wet Puddles)
    // ========================================================================
    vec3 baseLitRadiance = texture(colortex0, vTexCoord).rgb;

    // Skip environment mirror reflections on rough diffuse surfaces (player skin in F5, entities, leaves, rough terrain)
    // so they never get washed out by a sky reflection coating!
    bool isReflectiveOpaque = (matId == MAT_OBSIDIAN)
                           || (matId == MAT_METAL)
                           || (matId == MAT_POLISHED)
                           || (roughness < 0.42)
                           || (metalness > 0.05)
                           || (DIMENSION_ID == 0 && rainStrength > 0.02 && worldNormal.y > 0.5 && skyLight > 0.65);

    if (!isReflectiveOpaque) {
        writeCompositeOutput(vec4(max(baseLitRadiance, vec3(0.0)), 1.0));
        return;
    }

    vec3 f0 = (metalness > 0.5) ? baseLitRadiance : vec3(clamp(packedSpec, 0.02, 0.08));
    if (matId == MAT_OBSIDIAN) {
        f0 = vec3(0.056, 0.050, 0.072);
    }

    vec3 matFresnel;
    vec3 reflection = evaluateMaterialReflection(
        DIMENSION_ID,
        colortex4,
        depthtex1,
        viewPos,
        worldPos,
        cameraPosition,
        worldNormal,
        viewNormal,
        baseLitRadiance,
        roughness,
        metalness,
        f0,
        matId,
        skyLight,
        rainStrength,
        sunWorldDir,
        moonWorldDir,
        moonPhase,
        fogColor,
        gbufferProjection,
        gbufferProjectionInverse,
        gbufferModelViewInverse,
        frameTimeCounter,
        dither,
        matFresnel
    );

    // Combine reflections physically without washing out dark volcanic glass obsidian
    vec3 combinedOpaque = baseLitRadiance * (vec3(1.0) - matFresnel * (0.45 + 0.55 * metalness)) + reflection;
    writeCompositeOutput(vec4(max(combinedOpaque, vec3(0.0)), 1.0));
}
