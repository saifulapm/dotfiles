#version 440
// The field: one continuous diagonal grade from the scheme's one hue to the other over the paper, the whole output long, with Artboard's dot grid faint on it; windows show it through their veil, so the desk and every window are one canvas.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 outputSize;
    vec4 base;
    vec4 dotColor;
    float spacing;
    vec4 gradeFrom;
    vec4 gradeTo;
};

void main() {
    vec2 p = qt_TexCoord0 * outputSize;
    // A slow diagonal with a soft bow in it, so the field reads as composed, not as a ramp.
    float d = clamp(0.62 * qt_TexCoord0.x + 0.38 * qt_TexCoord0.y + 0.06 * sin(qt_TexCoord0.y * 3.14159), 0.0, 1.0);
    vec4 grade = mix(gradeFrom, gradeTo, smoothstep(0.0, 1.0, d));
    vec3 ground = mix(base.rgb, grade.rgb, grade.a);
    vec2 cell = mod(p + spacing * 0.5, spacing) - spacing * 0.5;
    float a = (1.0 - smoothstep(1.0, 1.3, length(cell))) * 0.6;
    fragColor = vec4(mix(ground, dotColor.rgb, a), 1.0) * qt_Opacity;
}
