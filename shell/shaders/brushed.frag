#version 440
// Hi-Fi's brushed faceplate: each row of the paper carries its own streaks of ink, at most streakAlpha.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 outputSize;
    vec4 base;
    vec4 ink;
    float streakAlpha;
    float period;
};

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    // Rows are hashed one by one, never tiled, so no column repeats at a fractional output scale.
    vec2 p = qt_TexCoord0 * outputSize / period;
    float row = floor(p.y);
    // Each row's streaks run 24 to 280 px and start at their own offset.
    float x = p.x / mix(24.0, 280.0, hash(vec2(row, 1.0))) + hash(vec2(row, 2.0)) * 97.0;
    float i = floor(x);
    float f = fract(x);
    float s = mix(hash(vec2(i, row + 0.5)), hash(vec2(i + 1.0, row + 0.5)), f * f * (3.0 - 2.0 * f));
    // Squaring the row's weight keeps most rows dim, so the sheet's mean stays near the paper.
    float w = hash(vec2(row, 3.0));
    float a = streakAlpha * w * w * smoothstep(0.3, 0.9, s);
    fragColor = vec4(mix(base.rgb, ink.rgb, a), 1.0) * qt_Opacity;
}
