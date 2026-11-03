// ============================================================================
// Appolo v0.1 — Full-Screen Post-Processing & Deferred Vertex Shader
// ============================================================================
#include "/lib/common.glsl"

out vec2 vTexCoord;

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    gl_Position = gl_ProjectionMatrix * (gl_ModelViewMatrix * gl_Vertex);
}
