// ============================================================================
// Appolo v0.1 — Composite Pass 3: Physical HDR Bloom & Temporal Auto-Exposure
// Reads TAA-Resolved HDR Scene from colortex0, Updates TAA History (colortex5)
// and Writes Bloom + Adapted Luminance (colortex6)
// ============================================================================
#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex6;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTime;

in vec2 vTexCoord;

/* RENDERTARGETS: 5,6 */
/* DRAWBUFFERS:56 */
layout(location = 0) out vec4 outHistory5;
layout(location = 1) out vec4 outBloomAndExposure6;

// Soft Knee Highlight Extraction for Physical HDR Bloom
vec3 extractBloomHighlights(vec3 hdr) {
    float brightness = max3(hdr);
    float knee = 0.65;
    float threshold = 0.85;
    float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = (soft * soft) / (4.0 * knee + 1e-4);
    float contribution = max(soft, brightness - threshold) / max(brightness, 1e-4);
    return hdr * clamp(contribution, 0.0, 1.0);
}

void main() {
    vec3 centerHDR = texture(colortex0, vTexCoord).rgb;
    outHistory5 = vec4(centerHDR, 1.0);

    vec2 texelSize = 1.0 / max(vec2(viewWidth, viewHeight), vec2(1.0));

    // Multi-Scale Dual-Ring Gaussian/Kawase HDR Bloom Filter
    vec3 bloomSum = vec3(0.0);
    float weightSum = 0.0;

    for (int ring = 1; ring <= 3; ring++) {
        float rad = float(ring * ring) * 2.25;
        float w = exp(-float(ring) * 0.55);
        for (int i = 0; i < 8; i++) {
            float angle = float(i) * (TAU / 8.0) + float(ring) * 0.3927;
            vec2 offset = vec2(cos(angle), sin(angle)) * rad * texelSize;
            vec2 sUV = clamp(vTexCoord + offset, vec2(0.002), vec2(0.998));
            vec3 sCol = texture(colortex0, sUV).rgb;
            bloomSum += extractBloomHighlights(sCol) * w;
            weightSum += w;
        }
    }
    vec3 bloom = bloomSum / max(weightSum, 1e-4);

    // Center-weighted scene luminance estimation for smooth Eye Adaptation
    float sampleLuma = 0.0;
    const vec2 lumaPoints[5] = vec2[5](
        vec2(0.50, 0.50),
        vec2(0.35, 0.35),
        vec2(0.65, 0.35),
        vec2(0.35, 0.65),
        vec2(0.65, 0.65)
    );
    for (int k = 0; k < 5; k++) {
        vec3 c = texture(colortex0, lumaPoints[k]).rgb;
        sampleLuma += clamp(luma(c), 0.02, 8.0) * 0.2;
    }

    float prevAdaptedLuma = texture(colortex6, vec2(0.5, 0.5)).a;
    if (prevAdaptedLuma <= 0.001 || prevAdaptedLuma > 20.0) {
        prevAdaptedLuma = 0.18;
    }
    float adaptRate = saturate(frameTime * EXPOSURE_SPEED);
    float adaptedLuma = mix(prevAdaptedLuma, sampleLuma, adaptRate);

    outBloomAndExposure6 = vec4(bloom, adaptedLuma);
}
