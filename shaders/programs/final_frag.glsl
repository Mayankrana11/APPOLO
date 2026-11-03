// ============================================================================
// Appolo v0.1 — Final Presentation Pass: Bloom Integration, Eye Adaptation,
//               AgX / ACES Tone Mapping & Contrast-Adaptive Sharpening (CAS)
// ============================================================================
#include "/lib/common.glsl"
#include "/lib/post.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex6;
uniform float viewWidth;
uniform float viewHeight;

in vec2 vTexCoord;

/* RENDERTARGETS: 0 */
/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 outColor0;

void main() {
    vec2 texelSize = 1.0 / max(vec2(viewWidth, viewHeight), vec2(1.0));

    // Contrast-Adaptive Sharpening (CAS) in HDR linear space
    vec3 cCenter = texture(colortex0, vTexCoord).rgb;
    vec3 cNorth  = texture(colortex0, clamp(vTexCoord + vec2(0.0,  texelSize.y), 0.001, 0.999)).rgb;
    vec3 cSouth  = texture(colortex0, clamp(vTexCoord + vec2(0.0, -texelSize.y), 0.001, 0.999)).rgb;
    vec3 cEast   = texture(colortex0, clamp(vTexCoord + vec2( texelSize.x, 0.0), 0.001, 0.999)).rgb;
    vec3 cWest   = texture(colortex0, clamp(vTexCoord + vec2(-texelSize.x, 0.0), 0.001, 0.999)).rgb;

    vec3 minNeighbor = min(cCenter, min(min(cNorth, cSouth), min(cEast, cWest)));
    vec3 maxNeighbor = max(cCenter, max(max(cNorth, cSouth), max(cEast, cWest)));
    vec3 contrast = (maxNeighbor - minNeighbor) / max(maxNeighbor + vec3(1e-4), vec3(1e-4));
    vec3 sharpenWeight = -0.12 * TAA_SHARPENING * (vec3(1.0) - saturate(contrast));

    vec3 sharpenedHDR = max(
        (cCenter + (cNorth + cSouth + cEast + cWest) * sharpenWeight) / (vec3(1.0) + 4.0 * sharpenWeight),
        vec3(0.0)
    );

    // Combine with Physical HDR Bloom & Read Temporally Adapted Luminance
    vec4 bloomAndExp = texture(colortex6, vTexCoord);
    float adaptedLuma = texture(colortex6, vec2(0.5, 0.5)).a;
    vec3 bloom = bloomAndExp.rgb * (BLOOM_INTENSITY * 0.28);

    vec3 combinedHDR = mix(sharpenedHDR, sharpenedHDR + bloom, saturate(BLOOM_INTENSITY));

    // Apply Auto-Exposure, AgX / ACES Tone Mapping, Contrast & Natural Saturation
    vec3 finalSrgb = evaluateCinematicColorPipeline(combinedHDR, adaptedLuma);

    // Subtle Dither to Eliminate 8-Bit Banding in Dark Night Skies & Deep Space
    float dither = (hash12(gl_FragCoord.xy) - 0.5) / 255.0;
    outColor0 = vec4(saturate(finalSrgb + dither), 1.0);
}
