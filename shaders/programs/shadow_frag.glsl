// ============================================================================
// Appolo v0.1 — Shadow Pass Fragment Shader (Included by shadow.fsh)
// Writes Colored Translucent Shadow Flux (shadowcolor0) & RSM Normal (shadowcolor1)
// ============================================================================
#include "/lib/common.glsl"

uniform sampler2D tex;
uniform float frameTimeCounter;

in vec2 vTexCoord;
in vec4 vColor;
in vec3 vWorldNormal;
flat in int vMatId;

/* RENDERTARGETS: 0,1 */
/* DRAWBUFFERS:01 */
layout(location = 0) out vec4 outShadowColor0;
layout(location = 1) out vec4 outShadowColor1;

void main() {
    vec4 texCol = texture(tex, vTexCoord) * vColor;

    // Handle architectural clear glass where vanilla interior alpha is 0.0
    if (vMatId == MAT_GLASS) {
        if (texCol.a < 0.05) {
            texCol.rgb = vec3(0.95, 0.98, 1.00);
            texCol.a = 0.12;
        }
    } else if (vMatId == MAT_WATER) {
        texCol.rgb = vec3(0.22, 0.72, 0.88);
        texCol.a = 0.24;
    } else {
        if (texCol.a < 0.10) discard;
    }

    outShadowColor0 = vec4(texCol.rgb, texCol.a);
    outShadowColor1 = vec4(encodeNormal(vWorldNormal), 1.0);
}
