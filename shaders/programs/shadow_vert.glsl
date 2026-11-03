// ============================================================================
// Appolo v0.1 — Shadow Pass Vertex Shader (Included by shadow.vsh)
// ============================================================================
#include "/lib/common.glsl"
#include "/lib/shadows.glsl"

in vec4 mc_Entity;
in vec4 mc_midTexCoord;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float rainStrength;

out vec2 vTexCoord;
out vec4 vColor;
out vec3 vWorldNormal;
flat out int vMatId;

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    vMatId = mapBlockIdToMat(int(mc_Entity.x + 0.5));

    vec3 viewNormal = normalize(gl_NormalMatrix * gl_Normal);
    vWorldNormal = normalize(mat3(shadowModelViewInverse) * viewNormal);

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec3 worldPos = (shadowModelViewInverse * viewPos).xyz + cameraPosition;

    // Synchronized wind animation for foliage/leaves/grass in the shadow map
    if (vMatId == MAT_FOLIAGE) {
        float windStrength = 0.045 * (1.0 + rainStrength * 0.8);
        float phase = dot(worldPos.xz, vec2(0.65, 0.45)) + frameTimeCounter * 2.6;
        vec2 sway = vec2(sin(phase), cos(phase * 0.85)) * windStrength;
        viewPos.xyz += (shadowModelView * vec4(sway.x, 0.0, sway.y, 0.0)).xyz;
    }

    vec4 clipPos = gl_ProjectionMatrix * viewPos;
    clipPos.xyz = distortShadowClipPos(clipPos.xyz);
    gl_Position = clipPos;
}
