// ============================================================================
// Appolo v0.1 — Opaque & Cutout G-Buffer Fragment Shader
// Outputs to colortex0 (Albedo), colortex1 (Normal+Rough), colortex2 (PBR+LM), colortex7 (GeoNormal+MatID)
// Full UMSOEA (OldPBR) + LabPBR 1.3 + Vanilla Compatibility
// ============================================================================
#include "/lib/common.glsl"
#include "/lib/pbr.glsl"

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform vec3 cameraPosition;
uniform vec4 entityColor;
uniform float frameTimeCounter;
uniform float alphaTestRef;

in vec2 vTexCoord;
in vec2 vLmCoord;
in vec4 vColor;
in vec3 vWorldPos;
in vec3 vViewPos;
in vec3 vGeoNormal;
in vec3 vTangent;
in vec3 vBitangent;
flat in int vMatId;

/* RENDERTARGETS: 0,1,2,7 */
/* DRAWBUFFERS:0127 */
layout(location = 0) out vec4 outColor0;
layout(location = 1) out vec4 outColor1;
layout(location = 2) out vec4 outColor2;
layout(location = 3) out vec4 outColor7;

void main() {
#ifdef GBUFFER_IS_BASIC
    vec4 texRaw = vColor;
    vec4 baseSample = vColor;
#else
    vec4 texRaw = texture(gtexture, vTexCoord);
    vec4 baseSample = vec4(texRaw.rgb * vColor.rgb, texRaw.a * vColor.a);
#endif

#ifdef GBUFFER_IS_ENTITY
    // Only blend entity hurt/flash overlay when actively flashing (prevents whitewashing player skin in F5)
    if (entityColor.a > 0.01 && entityColor.a < 0.99) {
        baseSample.rgb = mix(baseSample.rgb, entityColor.rgb, entityColor.a * 0.65);
    }
#endif

#ifdef GBUFFER_IS_GLINT
    if (baseSample.a < 0.05) discard;
    outColor0 = vec4(baseSample.rgb * 1.3, baseSample.a);
    outColor1 = vec4(encodeNormal(vGeoNormal), 0.12);
    outColor2 = vec4(0.85, 0.65, 1.0, 1.0);
    outColor7 = vec4(encodeNormal(vGeoNormal), encodeMatId(MAT_METAL));
    return;
#endif

#ifdef GBUFFER_IS_WEATHER
    if (baseSample.a < 0.08) discard;
    outColor0 = vec4(baseSample.rgb * 0.75, baseSample.a * 0.42);
    outColor1 = vec4(encodeNormal(vGeoNormal), 0.15);
    outColor2 = vec4(0.02, 0.0, saturate(vLmCoord.x), saturate(vLmCoord.y));
    outColor7 = vec4(encodeNormal(vGeoNormal), encodeMatId(MAT_DEFAULT));
    return;
#endif

    // Universal Cutout & Skin Overlay Alpha Test:
    // Discards transparent pixels on Player Model 3D outer skin layers (F5), Tree Leaves,
    // Foliage, Doors, Trapdoors, Entities, and Resource Pack Cutout Models.
#ifndef GBUFFER_IS_BASIC
    if (texRaw.a < max(alphaTestRef, 0.10)) {
        discard;
    }
#else
    if (baseSample.a < 0.10) {
        discard;
    }
#endif

    vec3 geoN = normalize(vGeoNormal);
    vec3 tanN = (dot(vTangent, vTangent) > 1e-4) ? normalize(vTangent) : vec3(1.0, 0.0, 0.0);
    vec3 bitN = (dot(vBitangent, vBitangent) > 1e-4) ? normalize(vBitangent) : vec3(0.0, 0.0, 1.0);
    mat3 tbn = mat3(tanN, bitN, geoN);

#if defined(GBUFFER_IS_TERRAIN)
    vec4 normalSample = texture(normals, vTexCoord);
    vec4 specSample   = texture(specular, vTexCoord);
#else
    vec4 normalSample = vec4(0.5, 0.5, 1.0, 1.0);
    vec4 specSample   = vec4(0.0);
#endif

    vec3 absWorldPos = vWorldPos + cameraPosition;
    MaterialPBR mat = decodeMaterialPBR(
        baseSample,
        normalSample,
        specSample,
        geoN,
        tbn,
        absWorldPos,
        vMatId,
        frameTimeCounter
    );

#if defined(GBUFFER_IS_ENTITY) || defined(GBUFFER_IS_HAND)
    // Keep player skin, mobs, and held items clean and natural (no metallic/glossy washout)
    mat.roughness = max(mat.roughness, 0.76);
    mat.metalness = 0.0;
    mat.f0 = vec3(0.024);
#endif

    // Bake subtle PBR texture AO into albedo and keep outColor0.a = 1.0 so GL_BLEND never makes solid blocks transparent!
    vec3 finalAlbedo = clamp(mat.albedo * mix(1.0, clamp(mat.ao, 0.45, 1.0), 0.55), vec3(0.0), vec3(1.0));
#ifdef GBUFFER_IS_PARTICLE
    float outAlpha = clamp(baseSample.a, 0.0, 1.0);
#else
    float outAlpha = 1.0;
#endif
    outColor0 = vec4(linearToSrgb(finalAlbedo), outAlpha);

    // colortex1: Encoded World Normal (.rgb) + Perceptual Roughness (.a)
    outColor1 = vec4(encodeNormal(mat.normal), clamp(mat.roughness, 0.02, 0.99));

    // colortex2: Metalness/F0 (.r), Pure Emission (.g), Block Light (.b), Sky Light (.a)
    float packedSpec = (mat.metalness > 0.5) ? clamp(0.5 + 0.5 * luma(mat.f0), 0.51, 1.0) : clamp(luma(mat.f0), 0.01, 0.49);
    outColor2 = vec4(
        packedSpec,
        clamp(mat.emission, 0.0, 1.0),
        saturate(vLmCoord.x),
        saturate(vLmCoord.y)
    );

    // colortex7: Flat Geometric Normal (.rgb) + Exact Material ID (.a)
    outColor7 = vec4(encodeNormal(geoN), encodeMatId(vMatId));
}
