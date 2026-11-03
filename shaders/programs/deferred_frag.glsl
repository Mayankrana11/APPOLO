// ============================================================================
// Appolo v0.1 — Deferred Opaque Lighting, GI, PCSS Shadows & Sky Evaluation
// Outputs to colortex0 (Main HDR Buffer) and colortex4 (Pre-Translucent Copy)
// ============================================================================
#include "/lib/common.glsl"
#include "/lib/pbr.glsl"
#include "/lib/shadows.glsl"
#include "/lib/gi_ao.glsl"
#if DIMENSION_ID == 1
#include "/lib/sky_end.glsl"
#elif DIMENSION_ID == -1
#include "/lib/sky_nether.glsl"
#else
#include "/lib/sky_overworld.glsl"
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex7;
uniform sampler2D depthtex0;

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

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
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
uniform int moonPhase;
uniform int isEyeInWater;

in vec2 vTexCoord;

/* RENDERTARGETS: 0,4 */
/* DRAWBUFFERS:04 */
layout(location = 0) out vec4 outColor0;
layout(location = 1) out vec4 outColor4;

void main() {
    float depth = texture(depthtex0, vTexCoord).r;
    vec3 viewPos = reconstructViewPos(vTexCoord, depth, gbufferProjectionInverse);
    vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 worldDir = normalize(worldPos);

    vec3 sunWorldDir  = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    vec3 moonWorldDir = normalize(mat3(gbufferModelViewInverse) * normalize(moonPosition));
    float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);

    // ========================================================================
    // 1. SKY PIXELS (depth >= 0.9999)
    // ========================================================================
    if (depth >= 0.9999) {
        vec3 skyRadiance = vec3(0.0);
#if DIMENSION_ID == 1
        // THE END: Complete 3D Ray-Traced Solar System (Jupiter, Saturn+Rings, Inner & Outer Planets, Sun)
        skyRadiance = evaluateEndSolarSystem(worldDir, cameraPosition, frameTimeCounter);
#elif DIMENSION_ID == -1
        // THE NETHER: Oppressive Volcanic Hellscape Sky & Magma Fissures
        skyRadiance = evaluateNetherSky(worldDir, cameraPosition, fogColor, frameTimeCounter);
#else
        // OVERWORLD: Physical Rayleigh/Mie Sky, Astrophotography Milky Way, Stars, 3D Moon & Volumetric Clouds
        skyRadiance = evaluateOverworldSky(worldDir, sunWorldDir, moonWorldDir, moonPhase, rainStrength);
        if (worldDir.y > 0.015) {
            vec4 clouds = evaluateOverworldClouds(
                worldDir,
                cameraPosition,
                sunWorldDir,
                moonWorldDir,
                frameTimeCounter,
                rainStrength,
                dither
            );
            skyRadiance = mix(skyRadiance, clouds.rgb, clouds.a);
        }
#endif
        outColor0 = vec4(skyRadiance, 1.0);
        outColor4 = vec4(skyRadiance, 1.0);
        return;
    }

    // ========================================================================
    // 2. OPAQUE GEOMETRY PIXELS (Decode G-Buffer)
    // ========================================================================
    vec4 g0 = texture(colortex0, vTexCoord);
    vec4 g1 = texture(colortex1, vTexCoord);
    vec4 g2 = texture(colortex2, vTexCoord);
    vec4 g7 = texture(colortex7, vTexCoord);

    vec3  albedo      = srgbToLinear(g0.rgb);
    float matAO       = 1.0;
    vec3  worldNormal = decodeNormal(g1.rgb);
    float roughness   = g1.a;
    vec3  geoNormal   = decodeNormal(g7.rgb);
    int   matId       = decodeMatId(g7.a);

    float packedSpec  = g2.r;
    float metalness   = (packedSpec > 0.50) ? 1.0 : 0.0;
    vec3  f0          = (metalness > 0.5) ? albedo : vec3(clamp(packedSpec, 0.02, 0.08));
    if (matId == MAT_OBSIDIAN) {
        f0 = vec3(0.056, 0.050, 0.072);
    }

    float emission    = (matId == MAT_FOLIAGE || matId == MAT_ICE) ? 0.0 : g2.g;
    float sss         = (matId == MAT_FOLIAGE) ? 0.75 : ((matId == MAT_ICE) ? 0.65 : 0.0);
    float blockLight  = g2.b;
    float skyLight    = g2.a;

    vec3 viewNormal = normalize(mat3(gbufferModelView) * worldNormal);
    vec3 V = -worldDir;
    vec3 absWorldPos = worldPos + cameraPosition;

    // Ground-Truth Ambient Occlusion (GTAO) with Multi-Bounce Albedo Color Bleeding
    vec4 gtao = computeGTAO(depthtex0, vTexCoord, viewPos, viewNormal, gbufferProjectionInverse, dither);
    float combinedAO = gtao.a * matAO;
    vec3 multiBounceAO = gtaoMultiBounce(combinedAO, albedo);

    // Screen-Space Global Illumination (SSGI) + Dynamic Emissive/Lava Bounce
    vec3 ssgi = evaluateScreenSpaceGI(
        colortex0,
        colortex1,
        colortex2,
        depthtex0,
        vTexCoord,
        viewPos,
        viewNormal,
        worldNormal,
        gbufferProjectionInverse,
        gbufferModelViewInverse,
        dither
    );

    // Dynamic Block Light (Lava, Fire, Glowstone, Sea Lanterns, Torches)
    vec3 dynamicBlockIrrad = evaluateDynamicBlockLight(
        blockLight,
        skyLight,
        absWorldPos,
        worldNormal,
        emission,
        matId,
        frameTimeCounter
    );

    vec3 totalRadiance = vec3(0.0);

#if DIMENSION_ID == 1
    // ========================================================================
    // THE END LIGHTING: High-Contrast Solar Key Light + Deep Cosmic Indigo Ambient
    // ========================================================================
    vec3 endSunDir = END_SUN_DIR;
    vec3 endViewLight = normalize(mat3(gbufferModelView) * endSunDir);
    float contactShadow = computeContactShadow(depthtex0, viewPos, endViewLight, gbufferProjection, dither);

    vec3 endSunRadiance = vec3(2.85, 2.55, 2.22) * END_SUN_INTENSITY * contactShadow;
    vec3 directEnd = evaluatePBRDirect(
        worldNormal,
        V,
        endSunDir,
        albedo,
        roughness,
        metalness,
        f0,
        sss,
        matId,
        endSunRadiance
    );

    // Cosmic hemisphere ambient: warm amber planet-shine on sunward faces vs cool indigo-violet deep space shadows
    vec3 jupiterDir = normalize(vec3(680.0, 135.0, 360.0));
    vec3 saturnDir  = normalize(vec3(-740.0, 125.0, -420.0));
    float sunHemi   = dot(worldNormal, endSunDir) * 0.5 + 0.5;
    vec3 cosmicShadowHemi = mix(vec3(0.014, 0.016, 0.036), vec3(0.036, 0.030, 0.048), sunHemi);
    vec3 planetShine = cosmicShadowHemi
                     + vec3(0.022, 0.016, 0.012) * max(dot(worldNormal, jupiterDir), 0.0)
                     + vec3(0.012, 0.016, 0.028) * max(dot(worldNormal, saturnDir), 0.0);

    vec3 indirectEnd = albedo * (planetShine * multiBounceAO + dynamicBlockIrrad + ssgi * combinedAO) * (1.0 - metalness);

    // 3D Volcanic Glass Subsurface Depth for Obsidian Pillars in The End
    if (matId == MAT_OBSIDIAN) {
        float obsRim = pow(1.0 - max(dot(worldNormal, V), 0.0), 3.0);
        vec3 volcanicSubsurface = vec3(0.028, 0.014, 0.055) * obsRim * combinedAO * (0.4 + 0.6 * sunHemi);
        indirectEnd += volcanicSubsurface;
    }

    totalRadiance = directEnd + indirectEnd;

#elif DIMENSION_ID == -1
    // ========================================================================
    // THE NETHER LIGHTING: Hellish Volcanic Radiance, Lava Bounce & Deep Shadows
    // ========================================================================
    vec3 biomeTint = srgbToLinear(clamp(fogColor, vec3(0.05), vec3(1.0)));
    float isSoulValley = saturate((biomeTint.b - biomeTint.r) * 2.5);

    // Primary upward illumination from molten lava oceans (Y ~ 31) and overhead volcanic fissures
    vec3 lavaUpDir = normalize(vec3(0.18, -0.92, 0.35));
    vec3 volcanicLightRad = mix(vec3(1.65, 0.38, 0.07), vec3(0.22, 0.78, 1.05), isSoulValley * 0.65)
                          * LAVA_EMISSION_STRENGTH;

    // Height attenuation from the lava sea
    float lavaHeightBoost = exp(-max(absWorldPos.y - 31.0, 0.0) * 0.025) * 0.85 + 0.25;
    vec3 directLavaBounce = evaluatePBRDirect(
        worldNormal,
        V,
        -lavaUpDir,
        albedo,
        roughness,
        metalness,
        f0,
        sss,
        matId,
        volcanicLightRad * lavaHeightBoost * 0.55
    );

    // Deep high-contrast volcanic ambient + strong SSGI lava color bleeding
    vec3 hellAmbient = mix(vec3(0.065, 0.014, 0.005), vec3(0.015, 0.045, 0.068), isSoulValley * 0.70)
                     * (0.35 + 0.65 * max(-worldNormal.y, 0.2));

    vec3 indirectNether = albedo * (
        hellAmbient * multiBounceAO +
        dynamicBlockIrrad * 1.35 +
        ssgi * combinedAO * 1.45
    ) * (1.0 - metalness);

    totalRadiance = directLavaBounce + indirectNether;

#else
    // ========================================================================
    // OVERWORLD LIGHTING: Physical Sun/Moon, PCSS Shadows, RSM + SSGI & Caves
    // ========================================================================
    float sunElev = sunWorldDir.y;
    bool isDay = (sunElev > -0.04);
    vec3 activeLightDir = isDay ? sunWorldDir : moonWorldDir;
    vec3 viewLightDir   = normalize(mat3(gbufferModelView) * activeLightDir);

    float dayTransition  = smoothstep(-0.06, 0.14, sunElev);
    float nightTransition = 1.0 - smoothstep(-0.12, 0.04, sunElev);

    // Solar atmospheric transmittance (natural golden hour warmth near horizon)
    float sunMass = clamp(1.0 / max(sunElev + 0.14, 0.03), 1.0, 20.0);
    vec3 sunAtmosTrans = exp(-vec3(0.058, 0.135, 0.331) * 0.42 * sunMass);
    vec3 sunRadiance = sunAtmosTrans * vec3(3.25, 3.05, 2.82) * dayTransition * SUNLIGHT_INTENSITY;

    // Lunar radiance (modulated by moon phase & elevation)
    float phaseFactor = 1.0;
#ifdef MOON_PHASE_LIGHTING
    phaseFactor = 0.25 + 0.75 * (0.5 + 0.5 * cos((float(moonPhase % 8) / 8.0) * TAU));
#endif
    vec3 moonRadiance = vec3(0.042, 0.068, 0.125) * max(moonWorldDir.y, 0.0) * nightTransition * phaseFactor * MOONLIGHT_INTENSITY;

    vec3 activeLightRadiance = (isDay ? sunRadiance : moonRadiance) * (1.0 - rainStrength * 0.78);

    // Evaluate PCSS Soft Shadows + Colored Glass Shadows + Cloud Shadows + Contact Shadows
    vec3 pcssShadow = evaluatePCSSShadow(
        shadowtex0,
        shadowtex1,
        shadowcolor0,
        worldPos,
        geoNormal,
        activeLightDir,
        shadowModelView,
        shadowProjection,
        dither
    );
    float cloudShadow   = getOverworldCloudShadow(absWorldPos, activeLightDir, frameTimeCounter, rainStrength);
    float contactShadow = computeContactShadow(depthtex0, viewPos, viewLightDir, gbufferProjection, dither);

    // Prevent sunlight leaking into sealed underground caves before shadow map cutoff
    float caveLightGate = smoothstep(0.03, 0.28, skyLight);
    vec3 totalShadow = pcssShadow * (cloudShadow * contactShadow * caveLightGate);

    // Underwater Caustics when camera is submerged
    if (isEyeInWater == 1) {
        vec3 caustics = computeWaterCaustics(absWorldPos, activeLightDir, frameTimeCounter);
        totalShadow *= (vec3(1.0) + caustics * caveLightGate);
    }

    vec3 directOverworld = evaluatePBRDirect(
        worldNormal,
        V,
        activeLightDir,
        albedo,
        roughness,
        metalness,
        f0,
        sss,
        matId,
        activeLightRadiance * totalShadow
    );

    // Reflective Shadow Map (RSM) Indirect Sunlight Bounce
    vec3 rsmBounce = evaluateRSMIndirectBounce(
        shadowtex1,
        shadowcolor0,
        shadowcolor1,
        worldPos,
        worldNormal,
        shadowModelView,
        shadowProjection,
        sunRadiance * caveLightGate,
        dither
    );

    // Sky Hemisphere Ambient + Realistic Cave Darkness Gradient
    float caveExponent = mix(1.6, 3.8, CAVE_DARKNESS_LEVEL);
    float skyOcclusion = pow(saturate(skyLight), caveExponent);
    float minCaveAmbient = mix(0.012, 0.00045, CAVE_DARKNESS_LEVEL);

    vec3 skyAmbientDay   = mix(vec3(0.14, 0.20, 0.30), vec3(0.24, 0.38, 0.62), worldNormal.y * 0.5 + 0.5) * dayTransition;
    vec3 skyAmbientNight = vec3(0.0045, 0.0078, 0.0165) * (0.45 + 0.55 * phaseFactor) * nightTransition * MOONLIGHT_INTENSITY;
    vec3 skyIrradiance   = (skyAmbientDay + skyAmbientNight) * (1.0 - rainStrength * 0.45) * skyOcclusion
                         + vec3(minCaveAmbient);

    vec3 indirectOverworld = albedo * (
        skyIrradiance * multiBounceAO +
        (rsmBounce + ssgi) * combinedAO +
        dynamicBlockIrrad
    ) * (1.0 - metalness);

    totalRadiance = directOverworld + indirectOverworld;
#endif

    // ========================================================================
    // 3. EMISSIVE MATERIALS (Lava, Glowstone, Sea Lanterns, Crying Obsidian, Soul Fire)
    // ========================================================================
    if (emission > 0.005) {
        float emissiveBoost = 4.5;
        if (matId == MAT_LAVA) emissiveBoost = 3.8 * LAVA_EMISSION_STRENGTH;
        else if (matId == MAT_OBSIDIAN) emissiveBoost = 3.6; // Crying Obsidian violet veins
        totalRadiance += albedo * emission * emissiveBoost;
    }

    // Add analytical environment specular to colortex4 only for glossy/metallic opaque objects
    // seen behind refractive glass/water (prevents washing out diffuse blocks & entities)
    vec3 quickEnv = vec3(0.0);
    vec3 envFresnel = vec3(0.0);
    if (roughness < 0.42 || metalness > 0.05 || matId == MAT_OBSIDIAN) {
        vec3 worldRefl = reflect(worldDir, worldNormal);
        float NdotV = max(dot(worldNormal, V), 1e-4);
        envFresnel = fresnelSchlickRoughness(NdotV, f0, roughness);
        float roughAtten = (1.0 - smoothstep(0.35, 0.75, roughness)) * smoothstep(0.05, 0.65, skyLight);
#if DIMENSION_ID == 1
        quickEnv = evaluateEndDeepSpaceStars(worldRefl) * 0.35;
#elif DIMENSION_ID == -1
        quickEnv = evaluateNetherSky(worldRefl, cameraPosition, fogColor, frameTimeCounter) * 0.25;
#else
        quickEnv = evaluateOverworldSky(worldRefl, sunWorldDir, moonWorldDir, moonPhase, rainStrength) * roughAtten * 0.35;
#endif
    }

    outColor0 = vec4(max(totalRadiance, vec3(0.0)), 1.0);
    outColor4 = vec4(max(totalRadiance + quickEnv * envFresnel, vec3(0.0)), 1.0);
}
