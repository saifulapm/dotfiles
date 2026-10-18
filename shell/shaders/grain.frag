#version 440
// Paper's grain: two octaves of value noise scale the paper by 1 +- grain, so the mean stays the paper colour.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 outputSize;
    vec4 base;
    float grain;
};

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
    vec2 p = floor(qt_TexCoord0 * outputSize) + 0.5;
    float n = (noise(p * 0.85) * 2.0 + noise(p * 1.7)) / 3.0;
    fragColor = vec4(base.rgb * (1.0 + grain * (n - 0.5) * 2.0), 1.0) * qt_Opacity;
}
