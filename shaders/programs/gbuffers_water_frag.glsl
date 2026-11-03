// ============================================================================
// Appolo v0.1 — Translucent Pass Fragment Shader (Water, Architectural Glass, Ice)
// Writes to colortex1 (Normal+Roughness), colortex2 (PBR+LM),
// colortex3 (Translucent Tint + Opacity), colortex7 (GeoNormal + MatID)
// ============================================================================
#include "/lib/common.glsl"
#include "/lib/pbr.glsl"

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float rainStrength;

in vec2 vTexCoord;
in vec2 vLmCoord;
in vec4 vColor;
in vec3 vWorldPos;
in vec3 vViewPos;
in vec3 vGeoNormal;
in vec3 vTangent;
in vec3 vBitangent;
flat in int vMatId;

/* RENDERTARGETS: 1,2,3,7 */
/* DRAWBUFFERS:1237 */
layout(location = 0) out vec4 outColor1;
layout(location = 1) out vec4 outColor2;
layout(location = 2) out vec4 outColor3;
layout(location = 3) out vec4 outColor7;

void main() {
    vec4 baseSample = texture(gtexture, vTexCoord) * vColor;
    vec3 geoN = normalize(vGeoNormal);
    vec3 tanN = (dot(vTangent, vTangent) > 1e-4) ? normalize(vTangent) : vec3(1.0, 0.0, 0.0);
    vec3 bitN = (dot(vBitangent, vBitangent) > 1e-4) ? normalize(vBitangent) : vec3(0.0, 0.0, 1.0);
    mat3 tbn = mat3(tanN, bitN, geoN);
    vec3 absWorldPos = vWorldPos + cameraPosition;

    if (vMatId == MAT_WATER) {
        // Dynamic Gerstner + FFT + Capillary Wave Normal in TBN / World space
        vec3 waveLocalN = getWaterWaveNormal(absWorldPos, frameTimeCounter, rainStrength);
        vec3 worldNormal = (abs(geoN.y) > 0.75)
            ? normalize(vec3(waveLocalN.x, waveLocalN.y * sign(geoN.y), waveLocalN.z))
            : normalize(tbn * waveLocalN.xzy);

        outColor1 = vec4(encodeNormal(worldNormal), 0.015);
        outColor2 = vec4(0.035, 0.0, saturate(vLmCoord.x), saturate(vLmCoord.y));
        outColor3 = vec4(vColor.rgb, 0.95);
        outColor7 = vec4(encodeNormal(geoN), encodeMatId(MAT_WATER));
        return;
    }

    // For non-glass translucent models (e.g., UMSOEA custom translucent overlays), discard transparent pixels!
    if (vMatId != MAT_GLASS && baseSample.a < 0.08) {
        discard;
    }

    int effectiveMatId = (vMatId == MAT_DEFAULT) ? MAT_GLASS : vMatId;

    vec4 normalSample = texture(normals, vTexCoord);
    vec4 specSample   = texture(specular, vTexCoord);

    MaterialPBR mat = decodeMaterialPBR(
        baseSample,
        normalSample,
        specSample,
        geoN,
        tbn,
        absWorldPos,
        effectiveMatId,
        frameTimeCounter
    );

    if (effectiveMatId == MAT_PORTAL) {
        mat.emission = 0.95;
        mat.roughness = 0.05;
    }

    outColor1 = vec4(encodeNormal(mat.normal), clamp(mat.roughness, 0.015, 0.99));
    outColor2 = vec4(
        clamp(luma(mat.f0), 0.01, 0.49),
        clamp(mat.emission, 0.0, 1.0),
        saturate(vLmCoord.x),
        saturate(vLmCoord.y)
    );
    outColor3 = vec4(linearToSrgb(clamp(mat.albedo, vec3(0.0), vec3(1.0))), clamp(mat.opacity, 0.04, 0.98));
    outColor7 = vec4(encodeNormal(geoN), encodeMatId(effectiveMatId));
}
