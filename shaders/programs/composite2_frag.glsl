// ============================================================================
// Appolo v0.1 — Composite Pass 2: Temporal Anti-Aliasing (TAA) & Denoising
// Reads Current Frame from colortex4 & History from colortex5, Writes to colortex0
// ============================================================================
#include "/lib/common.glsl"
#include "/lib/post.glsl"

uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float viewWidth;
uniform float viewHeight;

in vec2 vTexCoord;

/* RENDERTARGETS: 0 */
/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 outColor0;

void main() {
    float depth = texture(depthtex0, vTexCoord).r;
    vec2 texelSize = 1.0 / max(vec2(viewWidth, viewHeight), vec2(1.0));

    vec2 prevUV = computePreviousScreenUV(
        vTexCoord,
        depth,
        gbufferProjectionInverse,
        gbufferModelViewInverse,
        cameraPosition,
        previousCameraPosition,
        gbufferPreviousModelView,
        gbufferPreviousProjection
    );

    vec3 resolvedHDR = resolveTAA(
        colortex4,
        colortex5,
        vTexCoord,
        prevUV,
        texelSize
    );

    outColor0 = vec4(max(resolvedHDR, vec3(0.0)), 1.0);
}
