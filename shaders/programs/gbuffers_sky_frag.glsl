// ============================================================================
// Appolo v0.1 — Sky Pass Fragment Shader
// Discards vanilla flat sky/clouds/sun/moon quads so our analytical & ray-traced
// 3D celestial renderer in deferred.fsh renders the sky cleanly at depth == 1.0.
// ============================================================================
#include "/lib/common.glsl"

in vec4 vColor;

/* RENDERTARGETS: 0 */
/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 outColor0;

void main() {
    if (vColor.a >= -1.0) discard;
    outColor0 = vec4(0.0);
}
