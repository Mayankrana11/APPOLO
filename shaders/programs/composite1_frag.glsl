// ============================================================================
// Appolo v0.1 — Composite Pass 1: Ray-Marched Volumetrics, God Rays,
//               Nether Rising Lava Steam, Embers, Ash & Refractive Heat Haze
// Reads from colortex3 and Writes to colortex0 & colortex4
// ============================================================================
#include "/lib/common.glsl"
#include "/lib/gi_ao.glsl"
#include "/lib/volumetrics.glsl"
#if DIMENSION_ID == -1
#include "/lib/sky_nether.glsl"
#elif DIMENSION_ID == 1
#include "/lib/sky_end.glsl"
#endif

uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

uniform mat4 gbufferProjectionInverse;
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
    vec3 absWorldPos = worldPos + cameraPosition;
    float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);

    vec4 g2 = texture(colortex2, vTexCoord);
    float emission   = g2.g;
    float blockLight = g2.b;

    vec2 sampleUV = vTexCoord;

#if DIMENSION_ID == -1
    // THE NETHER: Refractive Heat Haze Distortion near Lava, Fire & Superheated Air
    sampleUV = computeNetherHeatDistortion(
        vTexCoord,
        viewPos,
        absWorldPos,
        blockLight,
        emission,
        frameTimeCounter
    );
#endif

    vec3 sceneRadiance = texture(colortex3, sampleUV).rgb;

#if DIMENSION_ID == -1
    // THE NETHER: 3D Ray-Marched Rising Lava Steam, Vapor Plumes, Volcanic Smoke, Ash & Embers
    float maxDist = (depth >= 0.9999) ? 96.0 : length(worldPos);
    vec3 rayDir   = normalize(worldPos);
    vec4 netherVol = evaluateNetherVolumetricsAndSteam(
        cameraPosition,
        absWorldPos,
        rayDir,
        maxDist,
        fogColor,
        frameTimeCounter,
        dither
    );
    sceneRadiance = sceneRadiance * netherVol.a + netherVol.rgb;

#elif DIMENSION_ID == 1
    // THE END: 3D Cosmic Depth Perspective & Solar Forward Scattering around End Islands & Obsidian Pillars
    if (depth < 0.9999) {
        float dist = length(worldPos);
        vec3 rayDir = normalize(worldPos);
        float sunPhase = pow(max(dot(rayDir, END_SUN_DIR), 0.0), 4.0);
        float cosmicFog = 1.0 - exp(-dist * 0.0022);
        vec3 cosmicTint = mix(vec3(0.009, 0.011, 0.028), vec3(0.048, 0.038, 0.065), sunPhase);
        sceneRadiance = mix(sceneRadiance, cosmicTint, saturate(cosmicFog * 0.55));
    }

#else
    // OVERWORLD: Ray-Marched Volumetric Light Shafts (God Rays), Stained-Glass Shafts & Valley Mist
    vec3 sunWorldDir  = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    vec3 moonWorldDir = normalize(mat3(gbufferModelViewInverse) * normalize(moonPosition));

    vec3 targetOffset = (depth >= 0.9999) ? (normalize(worldPos) * 96.0) : worldPos;
    vec4 overworldVol = evaluateOverworldVolumetrics(
        shadowtex0,
        shadowtex1,
        shadowcolor0,
        targetOffset,
        cameraPosition,
        sunWorldDir,
        moonWorldDir,
        shadowModelView,
        shadowProjection,
        rainStrength,
        float(isEyeInWater),
        frameTimeCounter,
        dither
    );
    if (depth >= 0.9999 && isEyeInWater == 0) {
        // Preserve 100% of the crisp blue sky & cloud clarity; only add subtle crepuscular shaft glow
        sceneRadiance += overworldVol.rgb * 0.45;
    } else {
        sceneRadiance = sceneRadiance * overworldVol.a + overworldVol.rgb;
    }
#endif

    vec4 finalOut = vec4(max(sceneRadiance, vec3(0.0)), 1.0);
    outColor0 = finalOut;
    outColor4 = finalOut;
}
