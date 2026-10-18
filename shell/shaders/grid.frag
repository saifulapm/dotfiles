#version 440
// Blueprint's grid: the first pixel of every minor and major cell, the minor lines under the major ones.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 outputSize;
    vec4 base;
    vec4 accent;
    float minor;
    float major;
    float minorAlpha;
    float majorAlpha;
};

vec3 line(vec3 c, float x, float every, float alpha) {
    return mix(c, accent.rgb, mod(x, every) < 1.0 ? alpha : 0.0);
}

void main() {
    vec2 p = floor(qt_TexCoord0 * outputSize);
    vec3 c = line(base.rgb, p.x, minor, minorAlpha);
    c = line(c, p.y, minor, minorAlpha);
    c = line(c, p.x, major, majorAlpha);
    c = line(c, p.y, major, majorAlpha);
    fragColor = vec4(c, 1.0) * qt_Opacity;
}
