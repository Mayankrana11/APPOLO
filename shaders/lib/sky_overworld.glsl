// ============================================================================
// Appolo v0.1 — Overworld Atmospheric Scattering, Volumetric Clouds &
//               Astrophotography-Grade Milky Way Night Sky (Reference-Matched)
// ============================================================================
#ifndef APPOLO_SKY_OVERWORLD_GLSL
#define APPOLO_SKY_OVERWORLD_GLSL

#include "/lib/common.glsl"

// --- Phase Functions ---
float rayleighPhase(float cosTheta) {
    return (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta);
}

float cornetteShanksMiePhase(float cosTheta, float g) {
    float g2 = g * g;
    float num = 3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta);
    float den = (8.0 * PI) * (2.0 + g2) * pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5);
    return num / max(den, 1e-5);
}

// --- Celestial Rotation Matrix (Aligns with Sun/Moon Orbit, Steeply Arched Band) ---
mat3 getCelestialRotation(vec3 sunWorldDir) {
    vec3 east = normalize(vec3(sunWorldDir.y, -sunWorldDir.x, 0.0001));
    vec3 north = normalize(cross(sunWorldDir, east));
    vec3 up = cross(east, north);
    // Orient galactic plane so the Sagittarius core & Great Rift arch dramatically across the night sky
    mat3 galacticTilt = rotAxisAngle(normalize(vec3(0.36, 0.22, 0.91)), 1.18);
    return galacticTilt * mat3(east, up, north);
}

// --- Cube-Sphere 2D Projection for Distortion-Free Pinpoint Star Grids ---
vec2 dirToCubeUV(vec3 d, out float faceId) {
    vec3 ad = abs(d);
    vec2 uv;
    if (ad.x >= ad.y && ad.x >= ad.z) {
        faceId = (d.x > 0.0) ? 0.0 : 1.0;
        uv = d.yz / ad.x;
    } else if (ad.y >= ad.x && ad.y >= ad.z) {
        faceId = (d.y > 0.0) ? 2.0 : 3.0;
        uv = d.xz / ad.y;
    } else {
        faceId = (d.z > 0.0) ? 4.0 : 5.0;
        uv = d.xy / ad.z;
    }
    return atan(uv) * (2.0 / PI);
}

// --- Razor-Sharp Pinpoint Star Layer (No bloated blobs, true DSLR pinpoint stars) ---
vec3 evaluateStarLayer(vec3 celestialDir, float gridRes, float spawnProb, float sizeScale, float horizonElev) {
    float faceId;
    vec2 cubeUV = dirToCubeUV(celestialDir, faceId);
    vec2 p = cubeUV * gridRes + vec2(faceId * 37.0, faceId * 73.0);
    vec2 cell = floor(p);
    vec2 fracP = fract(p) - 0.5;

    vec3 seed = vec3(cell, faceId * 13.0 + gridRes * 0.1);
    vec3 rnd = hash33(seed);
    if (rnd.x > spawnProb) return vec3(0.0);

    vec2 starCenter = (rnd.yz - 0.5) * 0.44;
    vec2 delta = fracP - starCenter;
    float d2 = dot(delta, delta);
    float cellWindow = smoothstep(0.26, 0.04, sqrt(d2));
    if (cellWindow <= 0.001) return vec3(0.0);

    // Power-law stellar magnitude distribution matching real astrophotography
    float magRand = hash13(seed + vec3(19.7, 43.1, 7.3));
    float isBrightStar = step(0.955, magRand);
    float brightness = mix(pow(magRand, 2.6) * 1.55 + 0.12, 3.6 + pow(magRand, 6.0) * 8.0, isBrightStar);

    // Tight, crisp pinpoint Gaussian core + subtle soft halo on brightest stars
    float radius = mix(0.020, 0.046, magRand) * sizeScale;
    float core = exp(-d2 / max(radius * radius * 0.11, 1e-6));
    float airyHalo = exp(-d2 / max(radius * radius * 1.15, 1e-5)) * (0.08 + 0.24 * isBrightStar) * cellWindow;

    // Authentic Blackbody Stellar Classification (Warm K/M orange-gold, G yellow-white, A/B blue-white)
    float tempRand = hash13(seed + vec3(71.3, 11.9, 53.7));
    float tempK = mix(3200.0, 19500.0, pow(tempRand, 1.35));
    vec3 starColor = mix(blackbodyColor(tempK), vec3(1.0, 0.97, 0.94), 0.25);

    float horizonFactor = saturate(1.0 - horizonElev * 3.0);
    float scint = 1.0 - horizonFactor * 0.15 * (0.5 + 0.5 * sin(dot(cell, vec2(1.7, 2.3))));

    return starColor * (core + airyHalo) * brightness * scint;
}

// --- Distant Galaxies & Deep-Space Nebulae ---
vec3 evaluateDeepSpaceObjects(vec3 galDir) {
#ifndef DEEP_SPACE_GALAXIES
    return vec3(0.0);
#else
    vec3 deepSpace = vec3(0.0);

    // Andromeda-style Inclined Spiral Galaxy (M31)
    vec3 m31Center = normalize(vec3(0.54, -0.28, 0.79));
    float m31Dot = dot(galDir, m31Center);
    if (m31Dot > 0.993) {
        vec3 t1 = normalize(cross(m31Center, vec3(0.0, 1.0, 0.0)));
        vec3 t2 = cross(m31Center, t1);
        vec2 localUV = vec2(dot(galDir - m31Center, t1), dot(galDir - m31Center, t2)) * 28.0;
        localUV = rot2D(0.62) * localUV;
        localUV.y *= 2.85;
        float r = length(localUV);
        float angle = atan(localUV.y, localUV.x);
        float spiral = 0.5 + 0.5 * cos(2.0 * angle - r * 5.8 + fbm2D(localUV * 2.8, 3) * 1.6);
        float dustRing = smoothstep(0.22, 0.68, fbm2D(localUV * 5.2, 3));
        float core = exp(-r * r * 4.8);
        float disc = exp(-r * 1.85) * mix(0.35, 1.0, spiral) * dustRing;
        vec3 m31Col = core * vec3(1.0, 0.88, 0.72) * 1.15 + disc * vec3(0.72, 0.76, 0.88) * 0.42;
        deepSpace += m31Col * smoothstep(2.3, 0.15, r);
    }

    return deepSpace;
#endif
}

// --- Complete Astrophotography Milky Way & Star Field (Matched to Reference Photo) ---
// Uses 100% Isotropic 3D Unit-Sphere Domain Warping (ZERO stretching at any angle!)
vec3 evaluateMilkyWayAndStars(vec3 worldDir, vec3 sunWorldDir, float moonBrightness, float rainStrength) {
    if (worldDir.y < -0.05) return vec3(0.0);
    float horizonFade = smoothstep(-0.04, 0.08, worldDir.y);
    float weatherVis = 1.0 - saturate(rainStrength * 0.96);
    if (horizonFade * weatherVis <= 0.001) return vec3(0.0);

    mat3 galRot = getCelestialRotation(sunWorldDir);
    vec3 galDir = normalize(galRot * worldDir);

    // Galactic latitude (galDir.y = 0 along galactic equator) and longitude
    float galLat = galDir.y;
    float galLon = atan(galDir.z, galDir.x);

    // 1. Isotropic 3D Domain-Warped Coordinates on the Unit Sphere (No anisotropic squashing/stretching!)
    vec3 pIso = galDir * 3.2;
    vec3 warp1 = vec3(
        fbm3D(pIso + vec3(1.7, 9.2, 3.4), 4),
        fbm3D(pIso + vec3(8.3, 2.8, 5.1), 4),
        fbm3D(pIso + vec3(4.5, 6.1, 1.9), 4)
    ) - 0.5;
    vec3 warp2 = vec3(
        fbm3D(pIso * 2.7 + warp1 * 1.1 + vec3(13.1), 4),
        fbm3D(pIso * 2.7 + warp1 * 1.1 + vec3(27.4), 4),
        fbm3D(pIso * 2.7 + warp1 * 1.1 + vec3(41.9), 4)
    ) - 0.5;
    vec3 wDir = galDir + warp1 * 0.22 + warp2 * 0.095;

    // 2. Asymmetric Galactic Bulge & Star-Cloud Envelopes (matching the photo's bright left / dark-rift right structure)
    float lonDist = atan(sin(galLon - 0.25), cos(galLon - 0.25));
    float warpedLat = galLat + warp1.y * 0.085 + warp2.y * 0.035;

    // Bright Sagittarius-Scorpius star cloud ridge (offset slightly to one side of the Great Rift, just like the photo)
    float brightRidgeLat = galLat - 0.038 + warp1.x * 0.045;
    float sagCoreEnv = exp(-lonDist * lonDist * 1.85) * exp(-brightRidgeLat * brightRidgeLat * 68.0);
    float mainBandEnv = exp(-warpedLat * warpedLat * 22.0) * (0.35 + 0.65 * exp(-lonDist * lonDist * 0.75));
    float wideHaloEnv = exp(-warpedLat * warpedLat * 6.5)  * (0.28 + 0.72 * exp(-lonDist * lonDist * 0.55));

    // 3. Billowing, Clumpy 3D Star Clouds + Granular Million-Star Stipple
    float cloudCoarse = fbm3D(wDir * 3.8, 5);
    float cloudMedium = fbm3D(wDir * 9.2 + warp2 * 0.8, 4);
    float cloudFine   = fbm3D(wDir * 21.0, 3);

    // Multi-octave high-frequency 3D stellar stipple so the Milky Way looks made of millions of tiny stars
    float stipple1 = noise3D(galDir * 220.0);
    float stipple2 = noise3D(galDir * 480.0);
    float stipple3 = noise3D(galDir * 920.0);
    float starGranularity = 0.52 + 0.95 * pow(stipple1 * stipple2, 1.35) + 0.65 * pow(stipple2 * stipple3, 2.2);

    float cloudStructure = pow(saturate(cloudCoarse * 0.55 + cloudMedium * 0.32 + cloudFine * 0.18), 1.45);

    // 4. Clumpy, Jagged Great Rift Dark Interstellar Dust Clouds (Isotropic 3D — zero stretched lines!)
    // Offset the primary dark rift slightly toward -galLat so it carves alongside & across the bright core
    float riftLat = galLat + 0.018 + warp1.z * 0.055;
    float riftEnvelope = exp(-riftLat * riftLat * 42.0) * (0.45 + 0.55 * exp(-lonDist * lonDist * 0.95));

    float dustClumps = fbm3D(wDir * 4.5 + vec3(5.2, 8.1, 2.7), 5);
    float dustWeb    = ridgedFbm3D(wDir * 7.8 + warp2 * 1.2, 4);
    float dustKnots  = fbm3D(galDir * 18.5 + warp2 * 2.0, 4);

    float rawDust = saturate((dustClumps * 0.52 + dustWeb * 0.48 - 0.30) * 2.35)
                  * (0.55 + 0.65 * dustKnots)
                  * riftEnvelope;
    float dustOpticalDepth = rawDust * 2.85;

    // Realistic warm-umber / dark-espresso dust extinction
    vec3 dustTransmittance = exp(-dustOpticalDepth * vec3(1.85, 2.15, 2.55));

    // 5. Authentic DSLR Astrophotography Color Palette (Matched to Reference Image):
    //    - Creamy warm-ivory / pale-gold Sagittarius core
    //    - Dusty warm-taupe & muted mauve-lavender outer star clouds
    //    - Crisp violet-pink H-II star-forming knots (M8 Lagoon / M20 Trifid) along the core spine
    vec3 coreIvoryGold  = vec3(1.00, 0.90, 0.78); // Blazing creamy-warm Sagittarius star cloud
    vec3 midWarmTaupe   = vec3(0.76, 0.64, 0.62); // Natural warm dusty star clouds
    vec3 outerMauveGray = vec3(0.54, 0.48, 0.64); // Subtle lavender-taupe outer galactic band
    vec3 darkDustGlow   = vec3(0.24, 0.18, 0.16); // Faint warm-brown scattered light on dark dust edges

    float colorVar = smoothstep(0.25, 0.75, fbm3D(wDir * 3.0 + vec3(19.0), 3));
    vec3 bandColor = mix(midWarmTaupe, outerMauveGray, colorVar);

    // Localized Violet-Lavender & Rose H-II Nebulae Knots (Lagoon M8 & Trifid M20 in the upper core)
    float knotField = fbm3D(wDir * 11.5 + vec3(3.7, 11.2, 6.8), 4);
    float violetKnotMask = pow(saturate((knotField - 0.54) * 2.6), 3.0) * (sagCoreEnv * 0.8 + mainBandEnv * 0.5);
    vec3 nebulaKnots = mix(vec3(0.72, 0.54, 0.96), vec3(0.92, 0.46, 0.68), stipple1) * violetKnotMask * 1.35;

    vec3 milkyWay = (
        coreIvoryGold  * sagCoreEnv  * (0.55 + cloudStructure * 1.45) * starGranularity +
        bandColor      * mainBandEnv * (0.35 + cloudStructure * 1.15) * starGranularity +
        outerMauveGray * wideHaloEnv * (0.18 + cloudCoarse * 0.55) * (0.7 + 0.3 * starGranularity) +
        nebulaKnots
    ) * dustTransmittance;

    // Subtle warm-umber rim scattering along the edges of the Great Rift dark dust clouds
    float dustRim = dustOpticalDepth * exp(-dustOpticalDepth * 0.95);
    milkyWay += darkDustGlow * dustRim * (0.25 + 0.45 * sagCoreEnv) * 0.32;
    milkyWay *= MILKY_WAY_INTENSITY * 0.24;

    // 6. Ultra-Dense Multi-Tier Pinpoint Star Field (Matching the dense star-filled reference photo)
    vec3 stars = vec3(0.0);
    float galDensityBoost = clamp(1.0 + mainBandEnv * 2.2 + sagCoreEnv * 2.4 + wideHaloEnv * 0.8, 1.0, 4.8);

#if STAR_DENSITY >= 1
    // Tier 1: Bright Primary Constellation Stars
    stars += evaluateStarLayer(galDir, 62.0, 0.22, 0.92, worldDir.y) * 1.45;
#endif
#if STAR_DENSITY >= 2
    // Tier 2: Crisp Medium Field Stars across the entire sky
    stars += evaluateStarLayer(rotAxisAngle(vec3(0.0, 1.0, 0.0), 0.73) * galDir, 128.0, 0.34 * min(galDensityBoost, 2.2), 0.80, worldDir.y) * 1.15;
#endif
#if STAR_DENSITY >= 3
    // Tier 3: Dense Astrophotography Background Stars
    stars += evaluateStarLayer(rotAxisAngle(vec3(1.0, 0.0, 0.0), 1.19) * galDir, 230.0, 0.44 * min(galDensityBoost, 3.0), 0.70, worldDir.y) * 0.88;
#endif
#if STAR_DENSITY >= 4
    // Tier 4 & 5: Thousands of Fine Pinpoint Stars & Milky Way Star Clusters
    vec3 clusterStars = evaluateStarLayer(rotAxisAngle(vec3(0.0, 0.0, 1.0), 1.87) * galDir, 370.0, 0.52 * galDensityBoost, 0.62, worldDir.y) * 0.68;
    clusterStars += evaluateStarLayer(rotAxisAngle(vec3(0.6, 0.8, 0.0), 2.41) * galDir, 560.0, 0.58 * galDensityBoost, 0.54, worldDir.y) * 0.52;
    stars += clusterStars * mix(vec3(1.0), dustTransmittance, 0.78);
#endif

    // 7. Distant Galaxies
    vec3 galaxies = evaluateDeepSpaceObjects(galDir);

    float moonVeil = mix(1.0, 0.76, saturate(moonBrightness * 0.45));
    return (milkyWay * moonVeil + stars + galaxies * moonVeil) * horizonFade * weatherVis;
}

// --- Ray-Traced 3D Realistic Moon with Mare, Craters, Phases & Earthshine ---
vec3 evaluateRealisticMoon(vec3 worldDir, vec3 moonWorldDir, vec3 sunWorldDir, int moonPhase) {
    float cosAngle = dot(worldDir, moonWorldDir);
    const float moonAngularRadius = 0.038;
    float cosRadius = cos(moonAngularRadius);

    float halo = exp(-max(0.0, 1.0 - cosAngle) * 850.0) * 0.09 + exp(-max(0.0, 1.0 - cosAngle) * 85.0) * 0.012;
    vec3 haloColor = vec3(0.62, 0.70, 0.86) * halo;

    if (cosAngle < cosRadius) {
        return haloColor;
    }

    vec3 moonCenter = moonWorldDir * 100.0;
    float moonRadius = sin(moonAngularRadius) * 100.0;
    vec2 hit = intersectSphere(vec3(0.0), worldDir, moonCenter, moonRadius);
    if (hit.x < 0.0) return haloColor;

    vec3 hitPos = worldDir * hit.x;
    vec3 moonNormal = normalize(hitPos - moonCenter);

    vec3 mUp = normalize(vec3(0.15, 0.98, 0.12));
    vec3 mRight = normalize(cross(moonWorldDir, mUp));
    vec3 mTrueUp = cross(mRight, moonWorldDir);
    vec3 localN = vec3(dot(moonNormal, mRight), dot(moonNormal, mTrueUp), dot(moonNormal, -moonWorldDir));

    float mareNoise = fbm3D(localN * 2.4 + vec3(1.3, 4.2, 2.8), 4);
    float mareMask = smoothstep(0.46, 0.62, mareNoise) * smoothstep(-0.3, 0.5, localN.y + 0.15);

    vec2 c1 = voronoi2D(localN.xy * 6.5 + vec2(2.1, 3.7));
    vec2 c2 = voronoi2D(localN.xy * 18.0 + vec2(8.4, 1.9));
    float craterRim = smoothstep(0.28, 0.18, c1.x) - smoothstep(0.18, 0.04, c1.x) * 1.35;
    craterRim += (smoothstep(0.25, 0.15, c2.x) - smoothstep(0.15, 0.03, c2.x)) * 0.45;

    vec3 perturbedN = normalize(moonNormal + (mRight * (c1.x - 0.5) + mTrueUp * (c2.x - 0.5)) * 0.14);

    vec3 highlandAlbedo = vec3(0.76, 0.73, 0.68);
    vec3 mareAlbedo     = vec3(0.32, 0.31, 0.33);
    vec3 surfaceAlbedo  = mix(highlandAlbedo, mareAlbedo, mareMask) * (1.0 + craterRim * 0.18);

    vec3 lightDir = sunWorldDir;
#ifdef MOON_PHASE_LIGHTING
    float phaseAngle = (float(moonPhase % 8) / 8.0) * TAU;
    vec3 phaseDir = normalize(moonWorldDir * cos(phaseAngle) + mRight * sin(phaseAngle) + mTrueUp * 0.12);
    lightDir = normalize(mix(sunWorldDir, phaseDir, 0.65));
#endif

    float NdotL = max(dot(perturbedN, lightDir), 0.0);
    float NdotV = max(dot(moonNormal, -worldDir), 0.0);
    float orenNayar = pow(NdotL, 0.78) * mix(1.0, pow(NdotV, 0.35), 0.5);

    vec3 earthshine = surfaceAlbedo * vec3(0.010, 0.015, 0.026) * (1.0 - NdotL);
    vec3 moonSurface = surfaceAlbedo * vec3(2.4, 2.30, 2.15) * orenNayar * MOONLIGHT_INTENSITY + earthshine;

    float edgeAA = smoothstep(cosRadius, cosRadius + 0.00025, cosAngle);
    return mix(haloColor, moonSurface + haloColor * 0.35, edgeAA);
}

// --- Photon-Style Overworld Atmospheric Sky Scattering ---
// Seamless 24-Hour Transition: Early Day -> Day -> Noon -> Afternoon -> Evening/Sunset -> Dusk -> Night -> Midnight -> Dawn
vec3 evaluateOverworldSky(
    vec3 worldDir,
    vec3 sunWorldDir,
    vec3 moonWorldDir,
    int moonPhase,
    float rainStrength
) {
    float sunElev = sunWorldDir.y;
    float viewElev = max(worldDir.y, 0.001);
    float cosSun = dot(worldDir, sunWorldDir);

    // Smooth continuous diurnal phase weights across the full 24-hour solar elevation cycle [-1..+1]
    float noonFactor      = smoothstep(0.28, 0.78, sunElev);
    float dayFactor       = smoothstep(-0.04, 0.22, sunElev);
    float goldenHour      = smoothstep(-0.12, 0.04, sunElev) * (1.0 - smoothstep(0.06, 0.34, sunElev));
    float twilightFactor  = smoothstep(-0.26, -0.06, sunElev) * (1.0 - smoothstep(-0.02, 0.14, sunElev));
    float nightFactor     = smoothstep(0.02, -0.16, sunElev);
    float midnightFactor  = smoothstep(-0.35, -0.85, sunElev);

    // Optical air-mass & Rayleigh/Mie phase functions (normalized so zenith stays vibrant and bright!)
    float rPhaseNorm = 0.78 + 0.36 * cosSun * cosSun;
    float mPhase = cornetteShanksMiePhase(cosSun, 0.76);

    // 1. Clear Bright Photon-Style Daytime & Afternoon Sky
    // Noon: Deep royal azure zenith + crisp luminous cyan-blue horizon
    // Morning / Afternoon: Smoothly warms the lower horizon while keeping the upper sky crystal blue
    vec3 zenithNoon      = vec3(0.085, 0.320, 0.880);
    vec3 zenithAfternoon = vec3(0.110, 0.365, 0.860);
    vec3 zenithDay       = mix(zenithAfternoon, zenithNoon, noonFactor);

    vec3 horizonNoon      = vec3(0.380, 0.690, 0.980);
    vec3 horizonAfternoon = vec3(0.520, 0.740, 0.960);
    vec3 horizonDay       = mix(horizonAfternoon, horizonNoon, noonFactor);

    // Subtle warm solar azimuth tint during morning/afternoon
    float sunAzimuthGlow = pow(saturate(cosSun * 0.5 + 0.5), 3.0) * (1.0 - noonFactor * 0.75);
    horizonDay = mix(horizonDay, vec3(0.92, 0.78, 0.62), sunAzimuthGlow * 0.28);

    float horizonCurve = pow(1.0 - saturate(viewElev), 2.8);
    vec3 clearDaySky = mix(zenithDay, horizonDay, horizonCurve) * rPhaseNorm * SUNLIGHT_INTENSITY;

    // Clean circumsolar forward scattering bloom (crisp white-gold around the sun, never grey smog)
    vec3 solarBloomTint = mix(vec3(1.00, 0.76, 0.48), vec3(1.00, 0.95, 0.88), smoothstep(0.05, 0.45, sunElev));
    clearDaySky += solarBloomTint * mPhase * 0.22 * SUNLIGHT_INTENSITY;

    // 2. Golden Hour / Sunrise / Evening Sunset Sky (Smooth transition between Day and Twilight)
    float solarSide = pow(saturate(cosSun * 0.5 + 0.5), 2.4);
    float antiSolar = saturate(-cosSun * 0.5 + 0.5);
    vec3 goldenZenith  = vec3(0.065, 0.195, 0.540);
    vec3 goldenMid     = mix(vec3(0.46, 0.36, 0.58), vec3(0.95, 0.52, 0.28), solarSide);
    vec3 goldenHorizon = mix(vec3(0.52, 0.34, 0.50), vec3(1.38, 0.50, 0.16), solarSide);

    vec3 goldenSky = mix(goldenZenith, goldenMid, smoothstep(0.65, 0.15, viewElev));
    goldenSky = mix(goldenSky, goldenHorizon, pow(1.0 - saturate(viewElev), 3.6));
    goldenSky += vec3(1.45, 0.56, 0.18) * mPhase * 0.38;

    // 3. Dusk / Dawn Blue-Hour Twilight (Belt of Venus + Deep Cobalt Zenith)
    float venusBand = smoothstep(0.0, 0.12, viewElev) * (1.0 - smoothstep(0.12, 0.34, viewElev));
    vec3 twilightSky = mix(
        vec3(0.018, 0.042, 0.125),
        vec3(0.28, 0.18, 0.34),
        venusBand * antiSolar
    ) + vec3(0.88, 0.38, 0.15) * pow(solarSide, 2.8) * pow(1.0 - saturate(viewElev), 4.0) * 0.65;

    // 4. Night & Midnight Sky (Dark Charcoal-Neutral Astrophotography Base)
    float phaseIllum = 1.0;
#ifdef MOON_PHASE_LIGHTING
    phaseIllum = 0.25 + 0.75 * (0.5 + 0.5 * cos((float(moonPhase % 8) / 8.0) * TAU));
#endif
    float moonElev = max(moonWorldDir.y, 0.0);
    float moonAtmosBrightness = moonElev * phaseIllum * MOONLIGHT_INTENSITY;

    vec3 nightZenith  = mix(vec3(0.0016, 0.0018, 0.0026), vec3(0.0011, 0.0012, 0.0017), midnightFactor)
                      + vec3(0.0016, 0.0026, 0.0052) * moonAtmosBrightness;
    vec3 nightHorizon = mix(vec3(0.0042, 0.0040, 0.0052), vec3(0.0030, 0.0029, 0.0038), midnightFactor)
                      + vec3(0.0040, 0.0060, 0.0110) * moonAtmosBrightness;
    vec3 nightBaseSky = mix(nightZenith, nightHorizon, pow(1.0 - saturate(viewElev), 3.2));

    // Seamlessly blend all diurnal phases
    vec3 skyColor = clearDaySky * dayFactor + nightBaseSky * nightFactor;
    skyColor = mix(skyColor, goldenSky, goldenHour * 0.85);
    skyColor = mix(skyColor, twilightSky, twilightFactor * 0.78);

    // Rain / Overcast weather transition (only when actually raining!)
    if (rainStrength > 0.001) {
        float skyLuma = luma(skyColor);
        vec3 stormCol = vec3(0.46, 0.52, 0.60) * max(skyLuma * 0.75, 0.02 * dayFactor + 0.002);
        skyColor = mix(skyColor, stormCol, rainStrength * 0.85);
    }

    // Physical Solar Disc with Crisp Limb Darkening
    if (worldDir.y > -0.04 && cosSun > 0.9985) {
        float sunLimb = saturate((cosSun - 0.9991) / (1.0 - 0.9991));
        vec3 sunDiscTint = mix(vec3(16.0, 7.5, 2.8), vec3(20.0, 18.5, 16.0), smoothstep(-0.02, 0.28, sunElev));
        vec3 solarDisc = sunDiscTint * pow(sunLimb, 0.42) * (1.0 - rainStrength * 0.94);
        skyColor += solarDisc * SUNLIGHT_INTENSITY;
    }

    // Night Stars & 3D Milky Way (Smoothly fade in during dusk and fade out at dawn)
    float starVis = smoothstep(0.04, -0.15, sunElev);
    if (starVis > 0.001) {
        vec3 cosmos = evaluateMilkyWayAndStars(worldDir, sunWorldDir, moonAtmosBrightness, rainStrength);
        skyColor += cosmos * starVis;
    }

    if (moonWorldDir.y > -0.05 && starVis > 0.01) {
        vec3 moonCol = evaluateRealisticMoon(worldDir, moonWorldDir, sunWorldDir, moonPhase);
        skyColor += moonCol * starVis * (1.0 - rainStrength * 0.95);
    }

    if (worldDir.y < 0.0) {
        vec3 groundBounce = skyColor * vec3(0.24, 0.28, 0.34) * exp(worldDir.y * 5.0);
        skyColor = mix(groundBounce, skyColor, smoothstep(-0.12, 0.0, worldDir.y));
    }

    return max(skyColor, vec3(0.0));
}

// --- Dynamic Terrain Cloud Shadow Evaluation ---
float getOverworldCloudShadow(vec3 worldPos, vec3 lightDir, float time, float rainStrength) {
#ifndef CLOUD_SHADOWS
    return 1.0;
#else
    if (lightDir.y <= 0.03 || CLOUD_COVERAGE <= 0.01) return 1.0;
    float cloudAlt = 260.0;
    vec2 cloudPos = worldPos.xz + lightDir.xz * ((cloudAlt - worldPos.y) / max(lightDir.y, 0.08));
    vec2 wind = vec2(time * 1.8, time * 0.70);
    vec2 uv = (cloudPos + wind) * 0.0012;

    float n = fbm2D(uv, 4);
    float coverage = mix(CLOUD_COVERAGE * 0.80, 0.86, rainStrength);
    float cloudDensity = smoothstep(1.0 - coverage, 1.0 - coverage + 0.30, n);
    return 1.0 - cloudDensity * 0.45;
#endif
}

// --- Photon-Style Bright Fluffy 3D Volumetric Cumulus Clouds ---
vec4 evaluateOverworldClouds(
    vec3 worldDir,
    vec3 cameraWorldPos,
    vec3 sunWorldDir,
    vec3 moonWorldDir,
    float time,
    float rainStrength,
    float dither
) {
    if (worldDir.y <= 0.018 || CLOUD_COVERAGE <= 0.01) return vec4(0.0);

    float sunElev = sunWorldDir.y;
    vec3 mainLightDir = (sunElev > -0.06) ? sunWorldDir : moonWorldDir;
    float dayFactor = smoothstep(-0.04, 0.20, sunElev);
    float goldenFactor = smoothstep(-0.12, 0.04, sunElev) * (1.0 - smoothstep(0.06, 0.30, sunElev));

    float bottomAlt = 240.0 - cameraWorldPos.y;
    float topAlt    = 350.0 - cameraWorldPos.y;
    if (bottomAlt <= 0.0) bottomAlt = 45.0;
    if (topAlt <= bottomAlt) topAlt = bottomAlt + 110.0;

    float tStart = bottomAlt / max(worldDir.y, 0.028);
    float tEnd   = topAlt / max(worldDir.y, 0.028);
    if (tStart > 3000.0) return vec4(0.0);

    const int STEPS = 12;
    float stepSize = (tEnd - tStart) / float(STEPS);
    float t = tStart + stepSize * dither;

    vec2 wind = vec2(time * 1.8, time * 0.70);
    // Keep clear-day cloud coverage airy so plenty of crisp blue sky shows through!
    float coverage = mix(CLOUD_COVERAGE * 0.78, 0.85, rainStrength);

    float transmittance = 1.0;
    vec3 scatteredLight = vec3(0.0);

    // Bright, clean sunlit white cumulus tops during day; warm coral-gold at sunrise/sunset
    vec3 daySunCloud    = vec3(1.52, 1.48, 1.44) * SUNLIGHT_INTENSITY;
    vec3 goldenSunCloud = vec3(1.38, 0.68, 0.34) * SUNLIGHT_INTENSITY;
    vec3 nightMoonCloud = vec3(0.014, 0.020, 0.036) * MOONLIGHT_INTENSITY;

    vec3 directCloudLight = mix(nightMoonCloud, daySunCloud, dayFactor);
    directCloudLight = mix(directCloudLight, goldenSunCloud, goldenFactor * 0.85);

    // Clean sky-blue ambient shading on cloud bases (never grey/muddy during clear days!)
    vec3 ambientCloudLight = mix(
        vec3(0.003, 0.004, 0.008),
        mix(vec3(0.38, 0.56, 0.85), vec3(0.45, 0.36, 0.52), goldenFactor * 0.7),
        dayFactor
    );
    if (rainStrength > 0.01) {
        directCloudLight  *= (1.0 - rainStrength * 0.55);
        ambientCloudLight  = mix(ambientCloudLight, vec3(0.32, 0.36, 0.42) * dayFactor, rainStrength * 0.8);
    }

    float cosLight = dot(worldDir, mainLightDir);
    float hgPhase = mix(cornetteShanksMiePhase(cosLight, 0.58), cornetteShanksMiePhase(cosLight, -0.25), 0.32);

    for (int i = 0; i < STEPS; i++) {
        if (transmittance < 0.03) break;
        vec3 p = worldDir * t;
        float hFrac = saturate((p.y - bottomAlt) / (topAlt - bottomAlt));
        float heightProfile = smoothstep(0.0, 0.22, hFrac) * smoothstep(1.0, 0.52, hFrac);

        vec3 sampleCoord = vec3((p.xz + cameraWorldPos.xz + wind) * 0.0012, p.y * 0.0032);
        float baseNoise = fbm3D(sampleCoord, 4);
        float detailNoise = noise3D(sampleCoord * 3.5) * 0.22;
        float density = smoothstep(1.0 - coverage, 1.0 - coverage + 0.28, baseNoise - detailNoise * (1.0 - hFrac)) * heightProfile;

        if (density > 0.005) {
            vec3 lightSampleCoord = sampleCoord + mainLightDir * vec3(0.07, 0.14, 0.07);
            float lightDensity = max(0.0, fbm3D(lightSampleCoord, 3) - (1.0 - coverage));
            // Multi-scattering approximation so cumulus interiors stay bright white instead of turning dark grey
            float primaryTrans   = exp(-lightDensity * 3.2);
            float secondaryTrans = exp(-lightDensity * 0.85) * 0.65;
            float lightTrans     = max(primaryTrans, secondaryTrans);
            float powder         = 0.55 + 0.45 * (1.0 - exp(-density * 5.0));

            vec3 stepScattering = (
                directCloudLight * lightTrans * powder * (0.55 + hgPhase * 1.15) +
                ambientCloudLight * (0.55 + 0.45 * hFrac)
            );

            float stepExt = density * 0.28;
            float stepTrans = exp(-stepExt);
            scatteredLight += transmittance * (1.0 - stepTrans) * stepScattering;
            transmittance *= stepTrans;
        }
        t += stepSize;
    }

    float distFade = exp(-tStart * 0.00040) * smoothstep(0.018, 0.12, worldDir.y);
    float cloudAlpha = (1.0 - transmittance) * distFade;
    return vec4(scatteredLight * distFade, cloudAlpha);
}

#endif // APPOLO_SKY_OVERWORLD_GLSL
