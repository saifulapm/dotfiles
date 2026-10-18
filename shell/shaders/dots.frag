#version 440
// Artboard's dot grid: a 1 px radius dot at every multiple of spacing, as the canvas's radial-gradient draws it.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 outputSize;
    vec4 base;
    vec4 dotColor;
    float spacing;
};

void main() {
    vec2 p = qt_TexCoord0 * outputSize;
    vec2 cell = mod(p + spacing * 0.5, spacing) - spacing * 0.5;
    float a = 1.0 - smoothstep(1.0, 1.3, length(cell));
    fragColor = vec4(mix(base.rgb, dotColor.rgb, a), 1.0) * qt_Opacity;
}
