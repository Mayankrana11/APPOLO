// ============================================================================
// Appolo v0.1 — Sky Pass Vertex Shader (Disabled Vanilla Sky Geometry)
// ============================================================================
#include "/lib/common.glsl"

out vec4 vColor;

void main() {
    vColor = gl_Color;
    gl_Position = gl_ProjectionMatrix * (gl_ModelViewMatrix * gl_Vertex);
}
