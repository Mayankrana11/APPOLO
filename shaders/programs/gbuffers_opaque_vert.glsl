// ============================================================================
// Appolo v0.1 — Opaque & Cutout G-Buffer Vertex Shader
// Universal Compatibility: UMSOEA (OldPBR), LabPBR 1.3 & Vanilla
// ============================================================================
#include "/lib/common.glsl"

#ifdef GBUFFER_IS_TERRAIN
in vec4 mc_Entity;
in vec4 at_tangent;
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float rainStrength;

out vec2 vTexCoord;
out vec2 vLmCoord;
out vec4 vColor;
out vec3 vWorldPos;
out vec3 vViewPos;
out vec3 vGeoNormal;
out vec3 vTangent;
out vec3 vBitangent;
flat out int vMatId;

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 rawLm = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vLmCoord  = clamp((rawLm - 0.03125) * 1.06667, 0.0, 1.0);
    vColor    = gl_Color;

    int blockId = 0;
#ifdef GBUFFER_IS_TERRAIN
    blockId = int(mc_Entity.x + 0.5);
#endif
    vMatId = mapBlockIdToMat(blockId);

    vec3 rawNormal = gl_NormalMatrix * gl_Normal;
    vec3 viewNormal = (dot(rawNormal, rawNormal) > 1e-6) ? normalize(rawNormal) : vec3(0.0, 1.0, 0.0);
    vGeoNormal = normalize(mat3(gbufferModelViewInverse) * viewNormal);

    vec3 upVec = (abs(vGeoNormal.y) < 0.99) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 fallbackTan = normalize(cross(upVec, vGeoNormal));

#ifdef GBUFFER_IS_TERRAIN
    if (dot(at_tangent.xyz, at_tangent.xyz) > 1e-4) {
        vec3 viewTangent = normalize(gl_NormalMatrix * at_tangent.xyz);
        vTangent = normalize(mat3(gbufferModelViewInverse) * viewTangent);
        float handedness = (at_tangent.w < 0.0) ? -1.0 : 1.0;
        vBitangent = cross(vGeoNormal, vTangent) * handedness;
    } else {
        vTangent = fallbackTan;
        vBitangent = cross(vGeoNormal, vTangent);
    }
#else
    vTangent = fallbackTan;
    vBitangent = cross(vGeoNormal, vTangent);
#endif

    vec4 viewPos4 = gl_ModelViewMatrix * gl_Vertex;
    vec3 worldOffset = (gbufferModelViewInverse * viewPos4).xyz;
    vec3 absWorldPos = worldOffset + cameraPosition;

#ifdef GBUFFER_IS_TERRAIN
    // Organic Wind Waving for Leaves, Grass, Ferns & Flora
    if (vMatId == MAT_FOLIAGE) {
        float windAmp = 0.042 * (1.0 + rainStrength * 0.85) * smoothstep(0.15, 0.75, vLmCoord.y);
        float phase = dot(absWorldPos.xz, vec2(0.65, 0.45)) + frameTimeCounter * 2.6;
        vec2 sway = vec2(sin(phase), cos(phase * 0.85)) * windAmp;
        worldOffset.xz += sway;
        viewPos4 = gbufferModelView * vec4(worldOffset, 1.0);
    }
#endif

    vViewPos  = viewPos4.xyz;
    vWorldPos = worldOffset;
    gl_Position = gl_ProjectionMatrix * viewPos4;
}
