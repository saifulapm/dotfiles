#version 440
// Frost's paper: ice grain and fern veins of ink that thicken toward the edges, at most frostAlpha at the corners.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 outputSize;
    vec4 base;
    vec4 ink;
    float frostAlpha;
    float period;
};

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void main() {
    // Hashed per pixel and by smooth noise, never tiled, so no column repeats at a fractional output scale.
    vec2 p = qt_TexCoord0 * outputSize / period;
    // Each axis frosts over its outer tenth; the two add, so the corners carry the most and the middle none.
    vec2 e = smoothstep(0.8, 1.0, abs(2.0 * qt_TexCoord0 - 1.0));
    float edge = (e.x + e.y) * 0.5;
    float grain = 0.3 + 0.7 * hash(floor(p));
    // A warped ridge of noise draws thin branching lines, and they widen as they near the edge.
    vec2 q = p / 90.0;
    q += vec2(noise(q * 2.0 + 7.0), noise(q * 2.0 + 19.0)) * 1.5;
    float ridge = 1.0 - abs(2.0 * noise(q) - 1.0);
    // The lower bound stays under 1.0, since smoothstep is undefined when its two bounds meet.
    float vein = smoothstep(0.999 - 0.08 * edge, 1.0, ridge);
    float a = frostAlpha * edge * clamp(mix(grain * 0.8, 1.0, vein), 0.0, 1.0);
    fragColor = vec4(mix(base.rgb, ink.rgb, a), 1.0) * qt_Opacity;
}
