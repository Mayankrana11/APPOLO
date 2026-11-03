// ============================================================================
// Appolo v0.1 — The End Dimension: Complete 3D Ray-Traced Solar System
// True 3D Point-Source Solar Illumination, Crescent/Gibbous Terminators,
// Proper Astronomical Spacing & Mutual Planetary/Ring Shadow Ray-Tracing
// ============================================================================
#ifndef APPOLO_SKY_END_GLSL
#define APPOLO_SKY_END_GLSL

#include "/lib/common.glsl"

// Primary Solar System Sun Direction & 3D World Position in The End
const vec3 END_SUN_DIR = normalize(vec3(-0.78, 0.34, 0.52));
const vec3 END_SUN_POS = vec3(-2730.0, 1190.0, 1820.0); // END_SUN_DIR * 3500.0

// --- Deep-Space Pinpoint Star Layer (No Atmospheric Twinkling in Vacuum) ---
vec3 evaluateVacuumStarLayer(vec3 d, float gridRes, float prob, float sizeScale) {
    float faceId;
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
    vec2 cubeUV = atan(uv) * (2.0 / PI);
    vec2 p = cubeUV * gridRes + vec2(faceId * 41.0, faceId * 89.0);
    vec2 cell = floor(p);
    vec2 fracP = fract(p) - 0.5;

    vec3 seed = vec3(cell, faceId * 17.0 + gridRes * 0.13);
    vec3 rnd = hash33(seed);
    if (rnd.x > prob) return vec3(0.0);

    vec2 center = (rnd.yz - 0.5) * 0.44;
    vec2 delta = fracP - center;
    float d2 = dot(delta, delta);
    float cellWindow = smoothstep(0.26, 0.04, sqrt(d2));
    if (cellWindow <= 0.001) return vec3(0.0);

    float mag = hash13(seed + vec3(23.1, 59.3, 11.7));
    float isBright = step(0.96, mag);
    float intensity = mix(pow(mag, 2.8) * 1.35 + 0.08, 3.5 + pow(mag, 5.0) * 7.5, isBright);

    float rad = mix(0.018, 0.042, mag) * sizeScale;
    float core = exp(-d2 / max(rad * rad * 0.11, 1e-6));
    float halo = exp(-d2 / max(rad * rad * 1.15, 1e-5)) * (0.08 + 0.22 * isBright) * cellWindow;

    float tempK = mix(3200.0, 22000.0, pow(hash13(seed + vec3(83.7, 19.1, 47.3)), 1.35));
    vec3 col = mix(blackbodyColor(tempK), vec3(1.0, 0.98, 0.95), 0.22);

    return col * (core + halo) * intensity * END_STAR_BRIGHTNESS;
}

// --- Deep-Space Cosmic Background, Faint Ecliptic Zodiacal Dust & Starfield ---
vec3 evaluateEndDeepSpaceStars(vec3 worldDir) {
    // True pitch-black deep space vacuum with subtle ecliptic zodiacal dust band
    vec3 bg = vec3(0.00035, 0.00040, 0.00058);

    // Subtle zodiacal light / ecliptic dust band oriented along the solar system plane
    vec3 eclipticNormal = normalize(vec3(0.18, 0.94, -0.28));
    float eclipticLat = dot(worldDir, eclipticNormal);
    float zodiacalBand = exp(-eclipticLat * eclipticLat * 18.0);

    vec3 pIso = worldDir * 3.4;
    vec3 warp = vec3(
        fbm3D(pIso + vec3(2.1, 5.4, 8.7), 4),
        fbm3D(pIso + vec3(7.3, 1.9, 4.2), 4),
        fbm3D(pIso + vec3(4.8, 9.1, 3.6), 4)
    ) - 0.5;
    vec3 wDir = worldDir + warp * 0.18;

    float dustCloud = fbm3D(wDir * 4.2, 4);
    float darkRift  = ridgedFbm3D(wDir * 6.8, 4);
    float stipple   = 0.6 + 0.8 * pow(noise3D(worldDir * 280.0) * noise3D(worldDir * 560.0), 1.5);

    vec3 dustCol = mix(vec3(0.0045, 0.0038, 0.0052), vec3(0.0095, 0.0078, 0.0068), dustCloud)
                 * exp(-saturate(darkRift - 0.35) * 2.5) * stipple;
    bg += dustCol * zodiacalBand;

    // Multi-tier razor-sharp vacuum stars
    vec3 stars = vec3(0.0);
    stars += evaluateVacuumStarLayer(worldDir, 68.0, 0.20, 0.90);
    stars += evaluateVacuumStarLayer(rotAxisAngle(vec3(0.0, 1.0, 0.0), 0.81) * worldDir, 145.0, 0.32, 0.78) * 0.85;
    stars += evaluateVacuumStarLayer(rotAxisAngle(vec3(1.0, 0.0, 0.0), 1.37) * worldDir, 270.0, 0.42 * (1.0 + zodiacalBand), 0.66) * 0.65;
    stars += evaluateVacuumStarLayer(rotAxisAngle(vec3(0.0, 0.0, 1.0), 2.09) * worldDir, 450.0, 0.48 * (1.0 + zodiacalBand * 1.5), 0.55) * 0.45;

    return bg + stars;
}

// --- 1. THE SUN: Blinding Stellar Core, Limb Darkening & Solar Corona ---
vec3 evaluateEndSun(vec3 worldDir, vec3 sunDir) {
    float cosTheta = dot(worldDir, sunDir);
    float angle = acos(clamp(cosTheta, -1.0, 1.0));

    // Tight, realistic solar disc (angular radius ~0.022 rad = 1.25 deg)
    const float sunRadius = 0.022;
    vec3 sunResult = vec3(0.0);

    if (angle < sunRadius) {
        float rNorm = angle / sunRadius;
        float mu = sqrt(max(0.0, 1.0 - rNorm * rNorm));
        // Physical Eddington solar limb darkening + photospheric convection granules
        float limbDarkening = 0.35 + 0.65 * pow(mu, 0.55);
        float granulation = 0.90 + 0.20 * noise3D(worldDir * 420.0);
        sunResult += vec3(38.0, 33.0, 27.0) * limbDarkening * granulation * END_SUN_INTENSITY;
    }

    // Multi-scale physical solar corona + subtle diffraction streamers
    float coronaInner = exp(-angle * 48.0) * 1.65;
    float coronaMid   = exp(-angle * 11.5) * 0.18;
    float coronaOuter = exp(-angle * 3.2)  * 0.022;

    vec3 sRight = normalize(cross(sunDir, vec3(0.0, 1.0, 0.0)));
    vec3 sUp    = cross(sRight, sunDir);
    vec2 coronaXY = vec2(dot(worldDir, sRight), dot(worldDir, sUp));
    float streamerAngle = atan(coronaXY.y, coronaXY.x);
    float streamers = 0.82 + 0.18 * cos(streamerAngle * 4.0) * sin(streamerAngle * 2.0 + 0.6);

    vec3 coronaColor = mix(vec3(1.00, 0.72, 0.42), vec3(1.00, 0.94, 0.86), exp(-angle * 28.0));
    sunResult += coronaColor * (coronaInner + coronaMid * streamers + coronaOuter) * END_SUN_INTENSITY;

    return sunResult;
}

// --- Helper: Construct Orthonormal Planetary Coordinate Frame ---
mat3 getPlanetBasis(vec3 centerDir, vec3 axisTilt, float spinAngle) {
    vec3 up = normalize(axisTilt);
    vec3 right = normalize(cross(up, centerDir));
    vec3 fwd = cross(right, up);
    mat3 base = mat3(right, up, fwd);
    return rotAxisAngle(vec3(0.0, 1.0, 0.0), spinAngle) * transpose(base);
}

// --- Helper: Physically Based Planetary Sphere Illumination & Terminator Shading ---
// Computes true 3D solar lighting with Oren-Nayar/Minnaert limb darkening, 3D bump terminator,
// Rayleigh atmospheric crescent limb scattering, and pitch-black night hemisphere!
vec3 shadePlanetarySphere(
    vec3 worldNormal,
    vec3 bumpNormal,
    vec3 viewDir,
    vec3 hitPos,
    vec3 albedo,
    vec3 atmosColor,
    float atmosStrength,
    float limbExponent
) {
    // True 3D direction from this exact point on the planet to the Sun!
    vec3 L = normalize(END_SUN_POS - hitPos);
    vec3 V = -viewDir;

    float rawNdotL  = dot(worldNormal, L);
    float bumpNdotL = dot(bumpNormal, L);
    float NdotV     = max(dot(worldNormal, V), 1e-4);

    // Crisp, realistic solar terminator: day side is brilliantly lit; night side is 0.0 (true space darkness!)
    float terminator = smoothstep(-0.04, 0.08, rawNdotL);
    // Near the terminator, 3D cloud/terrain bump relief casts dramatic long shadows
    float reliefDiff = max(bumpNdotL, 0.0) * terminator;

    // Minnaert / Oren-Nayar planetary limb darkening
    float limbDark = pow(clamp(NdotV, 0.02, 1.0), limbExponent);

    // Warm golden-amber twilight scattering right along the solar terminator band
    float twilightBand = exp(-sqr((rawNdotL - 0.02) * 14.0)) * smoothstep(-0.08, 0.02, rawNdotL);
    vec3 terminatorTint = mix(vec3(1.0), vec3(1.05, 0.72, 0.45), twilightBand * 0.55);

    // Thin, realistic Rayleigh atmospheric scattering arc along the sunlit limb only
    float fresnelLimb = pow(1.0 - NdotV, 4.2);
    float sunlitLimbMask = smoothstep(-0.08, 0.35, rawNdotL);
    vec3 atmosScattering = atmosColor * fresnelLimb * sunlitLimbMask * atmosStrength;

    vec3 sunIrradiance = vec3(2.85, 2.70, 2.52) * END_SUN_INTENSITY;

    // Very faint cosmic starlight on the dark side (0.04% so the dark crescent merges naturally with deep space)
    vec3 darkSideAmbient = albedo * vec3(0.0004, 0.0005, 0.0008);

    return albedo * sunIrradiance * terminatorTint * reliefDiff * limbDark
         + atmosScattering * END_SUN_INTENSITY
         + darkSideAmbient;
}

// --- 2. JUPITER: Gas Giant with Zonal Jet-Streams, 3D Cloud Relief & Great Red Spot ---
bool evaluateJupiter(
    vec3 rayOrigin,
    vec3 rayDir,
    float time,
    inout float closestT,
    inout vec3 outColor
) {
    // Positioned at vast orbital distance with majestic, realistic angular scale (~8.2 deg diameter)
    vec3 jupiterCenter = vec3(680.0, 145.0, 390.0);
    float jupiterRadius = 56.0 * JUPITER_SCALE;

    vec2 hit = intersectSphere(rayOrigin, rayDir, jupiterCenter, jupiterRadius);
    if (hit.x <= 0.0 || hit.x >= closestT) return false;

    closestT = hit.x;
    vec3 hitPos = rayOrigin + rayDir * hit.x;
    vec3 worldNormal = normalize(hitPos - jupiterCenter);

    float spin = time * 0.003 * PLANET_ROTATION_SPEED - 0.45;
    mat3 pBasis = getPlanetBasis(normalize(jupiterCenter), vec3(0.06, 0.99, 0.04), spin);
    vec3 pN = normalize(pBasis * worldNormal);

    float lat = asin(clamp(pN.y, -1.0, 1.0));
    float lon = atan(pN.z, pN.x);

    // Zonal jet-stream wind shear & turbulent Kelvin-Helmholtz eddies
    float jetShear = cos(lat * 18.0) * 0.45 + sin(lat * 38.0) * 0.18;
    vec3 tCoord = vec3(pN.x * 5.0 + jetShear, lat * 16.0, pN.z * 5.0 - jetShear);
    float turb1 = fbm3D(tCoord, 5);
    float turb2 = fbm3D(tCoord * 2.7 + vec3(turb1 * 1.8), 4);
    float turb3 = ridgedFbm3D(tCoord * 4.5 - vec3(turb2 * 1.3), 3);

    float shearedLat = lat + (turb1 - 0.5) * 0.085 + (turb2 - 0.5) * 0.038;

    // High-resolution Jovian Belts & Zones (Cassini/Juno true-color palette)
    float majorBands = cos(shearedLat * 20.0) * 0.5 + 0.5;
    float minorBands = sin(shearedLat * 48.0 + turb1 * 3.6) * 0.5 + 0.5;
    float polarMask  = smoothstep(0.74, 1.35, abs(lat));

    vec3 zoneIvory      = vec3(0.92, 0.86, 0.75); // High ammonia cloud decks
    vec3 beltOchre      = vec3(0.74, 0.49, 0.30); // Equatorial & Tropical Belts
    vec3 beltTerracotta = vec3(0.54, 0.26, 0.15); // Deep cyclonic brown-red barges
    vec3 festoonBlue    = vec3(0.36, 0.45, 0.58); // North Equatorial hot-spot plumes
    vec3 polarSlate     = vec3(0.32, 0.38, 0.48); // Polar cyclonic haze

    vec3 cloudAlbedo = mix(beltOchre, zoneIvory, smoothstep(0.20, 0.80, majorBands));
    cloudAlbedo = mix(cloudAlbedo, beltTerracotta, smoothstep(0.52, 0.86, minorBands) * (1.0 - majorBands * 0.68) * 0.82);
    cloudAlbedo = mix(cloudAlbedo, zoneIvory * 1.04, smoothstep(0.38, 0.78, turb3) * majorBands * 0.32);

    // Blue-gray equatorial festoons
    float festoonMask = exp(-sqr((shearedLat - 0.11) * 20.0)) * smoothstep(0.46, 0.74, turb2);
    cloudAlbedo = mix(cloudAlbedo, festoonBlue, festoonMask * 0.68);

    // Great Red Spot on the sunlit side of the Southern Tropical Zone
    float grsLat = -0.33;
    float grsLon = 0.65;
    vec2 grsDelta = vec2(atan(sin(lon - grsLon), cos(lon - grsLon)) * 0.92, (lat - grsLat) * 1.85);
    float grsDist = length(grsDelta);
    float grsHeight = 0.0;
    if (grsDist < 0.38) {
        float grsAngle = atan(grsDelta.y, grsDelta.x) + (0.38 - grsDist) * 11.0;
        vec2 spiralUV = vec2(cos(grsAngle), sin(grsAngle)) * grsDist * 9.5;
        float swirl = fbm2D(spiralUV + vec2(2.3, 5.1), 4);
        float eyeMask = smoothstep(0.26, 0.13, grsDist);
        float collarMask = smoothstep(0.36, 0.25, grsDist) * smoothstep(0.16, 0.25, grsDist);

        vec3 grsCol = mix(vec3(0.88, 0.48, 0.30), vec3(0.76, 0.22, 0.12), smoothstep(0.25, 0.06, grsDist));
        grsCol *= (0.85 + 0.28 * swirl);
        cloudAlbedo = mix(cloudAlbedo, vec3(0.93, 0.88, 0.78), collarMask * 0.85);
        cloudAlbedo = mix(cloudAlbedo, grsCol, eyeMask);
        grsHeight = eyeMask * 0.45;
    }

    cloudAlbedo = mix(cloudAlbedo, polarSlate, polarMask * 0.78);

    // 3D Cloud-deck relief normal for dramatic terminator shadows
    float cloudElev = majorBands * 0.55 + turb2 * 0.45 + grsHeight;
    vec3 tangentLat = normalize(cross(worldNormal, vec3(0.0, 1.0, 0.0)));
    vec3 bumpNormal = normalize(worldNormal + tangentLat * (cloudElev - 0.5) * 0.18);

    outColor = shadePlanetarySphere(
        worldNormal,
        bumpNormal,
        rayDir,
        hitPos,
        cloudAlbedo,
        vec3(0.65, 0.78, 0.98),
        0.55,
        0.32
    );
    return true;
}

// --- Helper: Evaluate Saturn's Concentric Ring Profile (D, C, B, Cassini, A, Encke, F) ---
void evaluateSaturnRingProperties(float normR, out vec3 ringAlbedo, out float opticalDepth) {
    ringAlbedo = vec3(0.0);
    opticalDepth = 0.0;
    if (normR < 1.18 || normR > 2.36) return;

    float fineRinglets = 0.5 + 0.5 * sin(normR * 310.0 * SATURN_RING_DETAIL + noise2D(vec2(normR * 58.0, 1.7)) * 4.2);
    float microBands   = fbm2D(vec2(normR * 105.0 * SATURN_RING_DETAIL, 3.1), 3);

    float cRing = smoothstep(1.18, 1.24, normR) * (1.0 - smoothstep(1.50, 1.53, normR));
    float bRing = smoothstep(1.52, 1.55, normR) * (1.0 - smoothstep(1.93, 1.95, normR));
    float cassiniGap = 1.0 - 0.96 * (smoothstep(1.94, 1.96, normR) * (1.0 - smoothstep(2.01, 2.03, normR)));
    float aRing = smoothstep(2.02, 2.04, normR) * (1.0 - smoothstep(2.26, 2.28, normR));
    float enckeGap = 1.0 - 0.92 * exp(-sqr((normR - 2.21) * 155.0));
    float fRing = exp(-sqr((normR - 2.33) * 105.0)) * 0.58;

    float density = (
        cRing * (0.18 + 0.16 * microBands) +
        bRing * (0.76 + 0.24 * fineRinglets * microBands) +
        aRing * (0.50 + 0.20 * fineRinglets) +
        fRing
    ) * cassiniGap * enckeGap;

    opticalDepth = clamp(density, 0.0, 0.98);

    vec3 cColor = vec3(0.46, 0.43, 0.40);
    vec3 bColor = mix(vec3(0.84, 0.77, 0.65), vec3(0.94, 0.89, 0.80), microBands);
    vec3 aColor = vec3(0.75, 0.71, 0.66);

    ringAlbedo = (cColor * cRing + bColor * bRing + aColor * (aRing + fRing))
               / max(cRing + bRing + aRing + fRing, 1e-4);
}

// --- 3. SATURN: Opposite-Hemisphere Gas Giant + 3D Concentric Rings & Mutual Shadows ---
void evaluateSaturnAndRings(
    vec3 rayOrigin,
    vec3 rayDir,
    float time,
    inout float closestT,
    inout vec3 outColor,
    out vec4 ringOverlay
) {
    ringOverlay = vec4(0.0, 0.0, 0.0, 1.0);

    // Positioned at vast distance in opposite hemisphere (~5.6 deg globe, ~13 deg ring span)
    vec3 saturnCenter = vec3(-650.0, 135.0, -520.0);
    float saturnRadius = 42.0 * SATURN_SCALE;

    vec3 ringNormal = normalize(vec3(-0.32, 0.85, -0.42));
    vec3 saturnLightDir = normalize(END_SUN_POS - saturnCenter);
    float spin = time * 0.004 * PLANET_ROTATION_SPEED;

    // 1. Ray-Sphere Intersection for Saturn's Gas Giant Body
    vec2 sphereHit = intersectSphere(rayOrigin, rayDir, saturnCenter, saturnRadius);
    bool hitPlanet = (sphereHit.x > 0.0 && sphereHit.x < closestT);
    float planetT = hitPlanet ? sphereHit.x : closestT;

    if (hitPlanet) {
        closestT = sphereHit.x;
        vec3 hitPos = rayOrigin + rayDir * sphereHit.x;
        vec3 worldNormal = normalize(hitPos - saturnCenter);

        float sinLat = clamp(dot(worldNormal, ringNormal), -1.0, 1.0);
        float lat = asin(sinLat);
        vec3 eqX = normalize(cross(ringNormal, vec3(0.0, 0.0, 1.0)));
        vec3 eqZ = cross(ringNormal, eqX);
        float lon = atan(dot(worldNormal, eqZ), dot(worldNormal, eqX)) + spin;

        float turb = fbm3D(vec3(lon * 2.2, lat * 10.0, sin(lon)), 4);
        float band = cos((lat + (turb - 0.5) * 0.05) * 22.0) * 0.5 + 0.5;
        float fineBand = sin(lat * 52.0 + turb * 2.5) * 0.5 + 0.5;

        vec3 eqGold    = vec3(0.90, 0.81, 0.62);
        vec3 beltOchre = vec3(0.75, 0.63, 0.45);
        vec3 beltAmber = vec3(0.64, 0.50, 0.34);
        vec3 polarHex  = vec3(0.42, 0.52, 0.60);

        vec3 saturnAlbedo = mix(beltOchre, eqGold, smoothstep(0.2, 0.8, band));
        saturnAlbedo = mix(saturnAlbedo, beltAmber, (1.0 - fineBand) * 0.32);
        saturnAlbedo = mix(saturnAlbedo, polarHex, smoothstep(0.82, 1.38, abs(lat)) * 0.78);

        // Ray-traced shadow cast by Saturn's Rings onto Saturn's cloud tops
        float ringShadowOnPlanet = 1.0;
        float sunDotRingN = dot(saturnLightDir, ringNormal);
        if (abs(sunDotRingN) > 1e-4) {
            float tShadowRing = dot(saturnCenter - hitPos, ringNormal) / sunDotRingN;
            if (tShadowRing > 0.0) {
                vec3 shadowRingPos = hitPos + saturnLightDir * tShadowRing;
                float rNorm = length(shadowRingPos - saturnCenter) / saturnRadius;
                vec3 dummyAlb;
                float ringTau;
                evaluateSaturnRingProperties(rNorm, dummyAlb, ringTau);
                ringShadowOnPlanet = exp(-ringTau * 2.5);
            }
        }

        vec3 bumpNormal = normalize(worldNormal + ringNormal * (band - 0.5) * 0.08);
        vec3 litSaturn = shadePlanetarySphere(
            worldNormal,
            bumpNormal,
            rayDir,
            hitPos,
            saturnAlbedo,
            vec3(0.68, 0.80, 0.98),
            0.48,
            0.34
        );
        outColor = litSaturn * (0.04 + 0.96 * ringShadowOnPlanet);
    }

    // 2. Analytic 3D Ray-Plane Intersection for Saturn's Concentric Ring System
    float denom = dot(rayDir, ringNormal);
    if (abs(denom) > 1e-5) {
        float tRing = dot(saturnCenter - rayOrigin, ringNormal) / denom;
        if (tRing > 0.0 && tRing < planetT) {
            vec3 ringHitPos = rayOrigin + rayDir * tRing;
            float rNorm = length(ringHitPos - saturnCenter) / saturnRadius;
            vec3 ringAlbedo;
            float ringTau;
            evaluateSaturnRingProperties(rNorm, ringAlbedo, ringTau);

            if (ringTau > 0.002) {
                // True ray-traced cylindrical shadow cast by Saturn's 3D Globe onto the Rings
                vec2 shadowSphere = intersectSphere(ringHitPos + saturnLightDir * 0.5, saturnLightDir, saturnCenter, saturnRadius);
                float planetShadowOnRing = 1.0;
                if (shadowSphere.x > 0.0) {
                    float distRatio = length(cross(ringHitPos - saturnCenter, saturnLightDir)) / saturnRadius;
                    planetShadowOnRing = smoothstep(0.97, 1.01, distRatio);
                }

                float cosSunView = dot(rayDir, saturnLightDir);
                float phase = mix(0.68, 1.45, pow(saturate(cosSunView * 0.5 + 0.5), 2.0));
                float sunPlaneElev = abs(dot(saturnLightDir, ringNormal));
                float ringIllum = clamp(sunPlaneElev * 1.85 + 0.25, 0.25, 1.15);

                vec3 sunRad = vec3(2.75, 2.60, 2.42) * END_SUN_INTENSITY;
                vec3 saturnShine = ringAlbedo * vec3(0.004, 0.0035, 0.0028);
                vec3 ringRadiance = ringAlbedo * sunRad * ringIllum * phase * planetShadowOnRing + saturnShine;

                float alpha = saturate(1.0 - exp(-ringTau * 2.25));
                ringOverlay = vec4(ringRadiance * alpha, 1.0 - alpha);
            }
        }
    }
}

// --- 4. INNER PLANETS (Mars, Earth, Venus, Mercury) & OUTER ICE GIANTS (Uranus, Neptune) ---
bool evaluateSolarSystemPlanet(
    int planetType, // 1=Mars, 2=Earth, 3=Venus, 4=Mercury, 5=Uranus, 6=Neptune
    vec3 planetCenter,
    float planetRadius,
    vec3 rayOrigin,
    vec3 rayDir,
    float time,
    inout float closestT,
    inout vec3 outColor
) {
    vec2 hit = intersectSphere(rayOrigin, rayDir, planetCenter, planetRadius);
    if (hit.x <= 0.0 || hit.x >= closestT) return false;

    closestT = hit.x;
    vec3 hitPos = rayOrigin + rayDir * hit.x;
    vec3 worldNormal = normalize(hitPos - planetCenter);

    float spin = time * 0.005 * PLANET_ROTATION_SPEED + float(planetType) * 1.3;
    mat3 pBasis = getPlanetBasis(normalize(planetCenter), vec3(0.15, 0.98, 0.08), spin);
    vec3 pN = normalize(pBasis * worldNormal);

    // True 3D Sun direction from this planet's position in space!
    vec3 trueSunDir = normalize(END_SUN_POS - hitPos);
    float rawNdotL = dot(worldNormal, trueSunDir);
    vec3 V = -rayDir;
    vec3 H = normalize(V + trueSunDir);

    vec3 surfaceColor = vec3(0.0);
    vec3 nightEmission = vec3(0.0);
    vec3 atmosColor = vec3(0.0);
    float atmosStrength = 0.0;
    vec3 bumpNormal = worldNormal;

    if (planetType == 1) {
        // --- MARS: Rusty Iron-Oxide Deserts, Syrtis Major Basalt & Polar Ice Caps ---
        float terrain = fbm3D(pN * 3.8 + vec3(2.1, 4.3, 1.7), 5);
        float craters = voronoi2D(pN.xy * 10.0 + pN.z * 3.0).x;
        vec3 rustDesert = vec3(0.76, 0.34, 0.18);
        vec3 darkBasalt = vec3(0.30, 0.14, 0.09);
        surfaceColor = mix(darkBasalt, rustDesert, smoothstep(0.32, 0.68, terrain));
        surfaceColor *= (0.86 + 0.26 * smoothstep(0.15, 0.45, craters));

        float polarIce = smoothstep(0.78, 0.90, abs(pN.y) + (terrain - 0.5) * 0.12);
        surfaceColor = mix(surfaceColor, vec3(0.94, 0.91, 0.88), polarIce);

        bumpNormal = normalize(worldNormal + pN * (terrain - 0.5) * 0.16);
        atmosColor = vec3(0.90, 0.54, 0.36);
        atmosStrength = 0.42;
    }
    else if (planetType == 2) {
        // --- EARTH: Blue Oceans, Continents, Polar Ice, Cyclone Clouds & Night City Lights ---
        float contNoise = fbm3D(pN * 2.85 + vec3(5.2, 1.8, 3.4), 5);
        float isLand = smoothstep(0.47, 0.52, contNoise);
        float elev = saturate((contNoise - 0.49) * 4.0);
        float absLat = abs(pN.y);

        vec3 deepOcean  = vec3(0.02, 0.10, 0.34);
        vec3 shallowSea = vec3(0.04, 0.28, 0.56);
        vec3 oceanCol = mix(deepOcean, shallowSea, smoothstep(0.36, 0.49, contNoise));

        float moisture = fbm3D(pN * 4.5 + vec3(9.1, 3.2, 7.4), 3);
        vec3 forestCol = vec3(0.09, 0.32, 0.10);
        vec3 desertCol = vec3(0.70, 0.57, 0.36);
        vec3 mountCol  = vec3(0.45, 0.42, 0.40);
        vec3 landCol = mix(desertCol, forestCol, smoothstep(0.35, 0.68, moisture - max(0.0, 0.45 - absLat) * 0.3));
        landCol = mix(landCol, mountCol, smoothstep(0.45, 0.85, elev));

        float iceCap = smoothstep(0.76, 0.86, absLat + (contNoise - 0.5) * 0.18);
        surfaceColor = mix(oceanCol, landCol, isLand);
        surfaceColor = mix(surfaceColor, vec3(0.95, 0.97, 0.99), iceCap);

        // Specular Solar Glint on Earth's Sunlit Oceans
        float spec = pow(max(dot(worldNormal, H), 0.0), 42.0) * (1.0 - isLand) * (1.0 - iceCap) * smoothstep(0.0, 0.2, rawNdotL);
        surfaceColor += vec3(1.35, 1.22, 1.00) * spec;

        // Swirling Atmospheric Clouds
        vec3 cloudCoord = rotAxisAngle(vec3(0.0, 1.0, 0.0), time * 0.002) * pN;
        float cloudWarp = fbm3D(cloudCoord * 3.5, 3);
        float clouds = smoothstep(0.49, 0.76, fbm3D(cloudCoord * 5.2 + vec3(cloudWarp * 0.9), 4));
        surfaceColor = mix(surfaceColor, vec3(0.96, 0.97, 0.99), clouds * 0.78);
        bumpNormal = normalize(worldNormal + pN * (elev * isLand * 0.12 + clouds * 0.08));

        // Night-Side City Lights on Earth's Unlit Dark Crescent
#ifdef EARTH_CITY_LIGHTS
        float nightMask = smoothstep(0.04, -0.14, rawNdotL) * isLand * (1.0 - iceCap) * (1.0 - clouds * 0.82);
        if (nightMask > 0.001) {
            vec2 cityVor = voronoi2D(pN.xy * 28.0 + pN.z * 16.0);
            float urbanHub = exp(-cityVor.x * 9.5);
            float highwayGrid = smoothstep(0.055, 0.0, abs(cityVor.y - cityVor.x)) * 0.50;
            float coastPref = smoothstep(0.76, 0.48, contNoise);
            float cityIntensity = (urbanHub + highwayGrid) * coastPref * nightMask;
            nightEmission = vec3(1.00, 0.72, 0.32) * cityIntensity * 0.55;
        }
#endif

        atmosColor = vec3(0.24, 0.58, 1.00);
        atmosStrength = 0.92;
    }
    else if (planetType == 3) {
        // --- VENUS: Dense Creamy-Gold Sulfuric Cloud Deck ---
        float chevron = fbm3D(pN * vec3(2.5, 6.0, 2.5) + vec3(cos(pN.y * 3.5) * 0.8), 4);
        vec3 venusCream  = vec3(0.94, 0.84, 0.60);
        vec3 venusYellow = vec3(0.76, 0.62, 0.38);
        surfaceColor = mix(venusYellow, venusCream, smoothstep(0.28, 0.74, chevron));
        bumpNormal = normalize(worldNormal + pN * (chevron - 0.5) * 0.08);
        atmosColor = vec3(1.00, 0.88, 0.58);
        atmosStrength = 0.82;
    }
    else if (planetType == 4) {
        // --- MERCURY: Heavily Cratered Silicate Regolith Near the Sun ---
        vec2 c1 = voronoi2D(pN.xy * 8.5 + pN.z * 4.5);
        vec2 c2 = voronoi2D(pN.xy * 22.0 - pN.z * 9.0);
        float regolith = fbm3D(pN * 6.0, 4);
        float craterBasin = smoothstep(0.15, 0.42, c1.x) * 0.7 + smoothstep(0.12, 0.35, c2.x) * 0.3;
        surfaceColor = mix(vec3(0.24, 0.22, 0.20), vec3(0.48, 0.45, 0.42), regolith * craterBasin);
        bumpNormal = normalize(worldNormal + pN * (craterBasin - 0.5) * 0.22);
        atmosStrength = 0.04;
        atmosColor = vec3(0.60, 0.56, 0.50);
    }
    else if (planetType == 5) {
        // --- URANUS: Pale Cyan-Aquamarine Ice Giant ---
        float uBand = cos(pN.x * 10.0) * 0.5 + 0.5;
        vec3 cyanLight = vec3(0.64, 0.89, 0.93);
        vec3 cyanDeep  = vec3(0.46, 0.78, 0.86);
        surfaceColor = mix(cyanDeep, cyanLight, uBand * 0.65 + 0.25 * pN.x);
        atmosColor = vec3(0.55, 0.92, 0.98);
        atmosStrength = 0.68;
    }
    else if (planetType == 6) {
        // --- NEPTUNE: Deep Cobalt-Azure Ice Giant with Methane Cirrus ---
        float nTurb = fbm3D(pN * vec3(3.5, 12.0, 3.5), 4);
        float nBand = sin(pN.y * 16.0 + nTurb * 1.5) * 0.5 + 0.5;
        vec3 nepDeep   = vec3(0.10, 0.25, 0.70);
        vec3 nepBright = vec3(0.20, 0.45, 0.88);
        surfaceColor = mix(nepDeep, nepBright, nBand);

        float cirrus = smoothstep(0.66, 0.84, fbm3D(pN * vec3(4.0, 24.0, 4.0), 3));
        surfaceColor = mix(surfaceColor, vec3(0.90, 0.95, 1.00), cirrus * 0.58);
        atmosColor = vec3(0.26, 0.58, 1.00);
        atmosStrength = 0.72;
    }

    outColor = shadePlanetarySphere(
        worldNormal,
        bumpNormal,
        rayDir,
        hitPos,
        surfaceColor,
        atmosColor,
        atmosStrength,
        0.28
    ) + nightEmission;
    return true;
}

// --- Master Evaluation of The End's Complete 3D Solar System ---
// Properly Spaced Across the Full Celestial Ecliptic with True 3D Solar Illumination
vec3 evaluateEndSolarSystem(vec3 worldDir, vec3 cameraWorldPos, float time) {
    vec3 rayOrigin = clamp(cameraWorldPos * 0.025, vec3(-25.0), vec3(25.0));
    vec3 sunDir = END_SUN_DIR;

    // 1. Background Deep-Space Starfield, Zodiacal Dust & Blazing Sun
    vec3 spaceBg = evaluateEndDeepSpaceStars(worldDir);
    spaceBg += evaluateEndSun(worldDir, sunDir);

    float closestT = 1e9;
    vec3 planetColor = vec3(0.0);
    bool hitAnyPlanet = false;

    // 2. Dominant Gas Giant #1: JUPITER (Positioned at ~800 units, angular size ~8 deg)
    if (evaluateJupiter(rayOrigin, worldDir, time, closestT, planetColor)) {
        hitAnyPlanet = true;
    }

    // 3. Dominant Gas Giant #2: SATURN + 3D Concentric Rings (Opposite Hemisphere at ~840 units)
    vec4 saturnRingOverlay;
    float prevT = closestT;
    evaluateSaturnAndRings(rayOrigin, worldDir, time, closestT, planetColor, saturnRingOverlay);
    if (closestT < prevT) {
        hitAnyPlanet = true;
    }

#if PLANET_RENDERING >= 2
    // 4. Widely Spaced Inner Planets Along the Ecliptic Arc Between Jupiter and the Sun:
    //    Jupiter (az +60 deg) -> Mars (az +24 deg) -> Earth (az -6 deg) -> Venus (az -34 deg) -> Mercury (az -52 deg) -> Sun (az -56 deg)
    // MARS (Distance ~850, radius 9.5 -> crisp ~1.2 deg red planet with polar ice cap & crescent shadow)
    if (evaluateSolarSystemPlanet(1, vec3(320.0, 185.0, 760.0), 9.5, rayOrigin, worldDir, time, closestT, planetColor)) {
        hitAnyPlanet = true;
    }
    // EARTH (Distance ~820, radius 16.5 -> ~2.3 deg blue marble with continents, clouds, ocean glint & night city lights)
    if (evaluateSolarSystemPlanet(2, vec3(-85.0, 220.0, 785.0), 16.5, rayOrigin, worldDir, time, closestT, planetColor)) {
        hitAnyPlanet = true;
    }
    // VENUS (Distance ~920, radius 13.5 -> brilliant golden-cream crescent planet)
    if (evaluateSolarSystemPlanet(3, vec3(-460.0, 260.0, 745.0), 13.5, rayOrigin, worldDir, time, closestT, planetColor)) {
        hitAnyPlanet = true;
    }
    // MERCURY (Distance ~1050, radius 7.5 -> crisp sunlit crescent near the solar corona)
    if (evaluateSolarSystemPlanet(4, vec3(-710.0, 310.0, 680.0), 7.5, rayOrigin, worldDir, time, closestT, planetColor)) {
        hitAnyPlanet = true;
    }

    // 5. Widely Spaced Outer Ice Giants on the Saturn-Facing Side:
    // URANUS (Distance ~980, radius 12.0 -> pale aquamarine ice giant)
    if (evaluateSolarSystemPlanet(5, vec3(-180.0, 85.0, -960.0), 12.0, rayOrigin, worldDir, time, closestT, planetColor)) {
        hitAnyPlanet = true;
    }
    // NEPTUNE (Distance ~1120, radius 11.0 -> deep cobalt-azure ice giant)
    if (evaluateSolarSystemPlanet(6, vec3(340.0, 52.0, -1065.0), 11.0, rayOrigin, worldDir, time, closestT, planetColor)) {
        hitAnyPlanet = true;
    }
#endif

    vec3 baseResult = hitAnyPlanet ? planetColor : spaceBg;
    return baseResult * saturnRingOverlay.a + saturnRingOverlay.rgb;
}

#endif // APPOLO_SKY_END_GLSL
