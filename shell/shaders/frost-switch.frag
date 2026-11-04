#version 440
// Frost's theme switch: frost of the ink colour, grown in from every edge as far as reach, over whatever paper is under it.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 outputSize;
    vec4 ink;
    // 0 no frost, 1 the whole screen.
    float reach;
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
    vec2 px = qt_TexCoord0 * outputSize;
    // Distance to the nearest edge, 0 at the edge and 1 at the middle of the shorter side.
    vec2 toEdge = min(px, outputSize - px);
    float d = min(toEdge.x, toEdge.y) / (0.5 * min(outputSize.x, outputSize.y));
    // The front is ragged like ice, and overshoots the middle so a full reach covers every pixel.
    d += (noise(px / 40.0) - 0.5) * 0.16;
    float front = reach * 1.4 - 0.15;
    float cover = 1.0 - smoothstep(front - 0.06, front + 0.06, d);
    float grain = 0.75 + 0.25 * hash(floor(px));
    float a = 0.85 * cover * grain;
    fragColor = vec4(ink.rgb * a, a) * qt_Opacity;
}
