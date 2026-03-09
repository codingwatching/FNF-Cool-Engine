// customBlend.frag
// Shader GLSL para blend modes avanzados que OpenGL no soporta nativamente.
// Portado/reconstruido a partir de v-slice (FunkinCrew/Funkin).
//
// Blend mode IDs (OpenFL BlendMode cast to int):
//   NORMAL=0, LAYER=1, MULTIPLY=2, SCREEN=3,
//   LIGHTEN=4, DARKEN=5, DIFFERENCE=6, ADD=7,
//   SUBTRACT=8, INVERT=9, ALPHA=10, ERASE=11,
//   OVERLAY=12, HARDLIGHT=13, SHADER=14,
//   COLORDODGE=15, COLORBURN=16, SOFTLIGHT=17,
//   EXCLUSION=18, HUE=19, SATURATION=20,
//   COLOR=21, LUMINOSITY=22

#pragma header

// Textura fuente (el sprite que se dibuja)
uniform sampler2D sourceSwag;
// Textura de fondo (lo que había antes)
uniform sampler2D backgroundSwag;
// Qué blend mode aplicar
uniform int blendMode;

// ── Conversiones HSL/HSV ──────────────────────────────────────────────────

vec3 rgb2hsl(vec3 c) {
    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float l    = (maxC + minC) * 0.5;
    float s    = 0.0;
    float h    = 0.0;
    float d    = maxC - minC;

    if (d > 0.0) {
        s = d / (1.0 - abs(2.0 * l - 1.0));

        if (maxC == c.r)      h = mod((c.g - c.b) / d, 6.0);
        else if (maxC == c.g) h = (c.b - c.r) / d + 2.0;
        else                  h = (c.r - c.g) / d + 4.0;

        h /= 6.0;
    }
    return vec3(h, s, l);
}

float hue2rgb(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0 / 2.0) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

vec3 hsl2rgb(vec3 c) {
    float h = c.x, s = c.y, l = c.z;
    if (s == 0.0) return vec3(l);
    float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    float p = 2.0 * l - q;
    return vec3(hue2rgb(p, q, h + 1.0 / 3.0),
                hue2rgb(p, q, h),
                hue2rgb(p, q, h - 1.0 / 3.0));
}

// Luminancia perceptual (fórmula Rec.709)
float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Establece la luminancia de un color
vec3 setLuminance(vec3 c, float lum) {
    float d = lum - luminance(c);
    c = c + d;
    float l = luminance(c);
    float n = min(c.r, min(c.g, c.b));
    float x = max(c.r, max(c.g, c.b));
    if (n < 0.0) c = l + ((c - l) * l) / (l - n);
    if (x > 1.0) c = l + ((c - l) * (1.0 - l)) / (x - l);
    return c;
}

// Saturación
float saturation(vec3 c) {
    return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
}

// Establece la saturación de un color manteniendo la luminancia
vec3 setSaturation(vec3 c, float sat) {
    float cMin = min(c.r, min(c.g, c.b));
    float cMax = max(c.r, max(c.g, c.b));
    float cSat = cMax - cMin;
    if (cSat <= 0.0) return vec3(0.0);
    return (c - cMin) * sat / cSat;
}

// ── Fórmulas de blend mode ────────────────────────────────────────────────

vec3 blendOverlay(vec3 src, vec3 dst) {
    return mix(
        2.0 * dst * src,
        1.0 - 2.0 * (1.0 - dst) * (1.0 - src),
        step(0.5, dst)
    );
}

vec3 blendHardLight(vec3 src, vec3 dst) {
    return blendOverlay(dst, src);
}

vec3 blendColorDodge(vec3 src, vec3 dst) {
    return min(vec3(1.0), dst / (1.0 - src + 0.001));
}

vec3 blendColorBurn(vec3 src, vec3 dst) {
    return 1.0 - min(vec3(1.0), (1.0 - dst) / (src + 0.001));
}

vec3 blendSoftLight(vec3 src, vec3 dst) {
    vec3 d = mix(
        dst - (1.0 - 2.0 * src) * dst * (1.0 - dst),
        dst + (2.0 * src - 1.0) * (sqrt(dst) - dst),
        step(0.5, src)
    );
    return d;
}

vec3 blendExclusion(vec3 src, vec3 dst) {
    return src + dst - 2.0 * src * dst;
}

// Blend modes basados en HSL
vec3 blendHue(vec3 src, vec3 dst) {
    vec3 hsl = rgb2hsl(src);
    vec3 dstHsl = rgb2hsl(dst);
    return hsl2rgb(vec3(hsl.x, dstHsl.y, dstHsl.z));
}

vec3 blendSaturation(vec3 src, vec3 dst) {
    vec3 hsl = rgb2hsl(src);
    vec3 dstHsl = rgb2hsl(dst);
    return hsl2rgb(vec3(dstHsl.x, hsl.y, dstHsl.z));
}

vec3 blendColor(vec3 src, vec3 dst) {
    vec3 hsl = rgb2hsl(src);
    vec3 dstHsl = rgb2hsl(dst);
    return hsl2rgb(vec3(hsl.x, hsl.y, dstHsl.z));
}

vec3 blendLuminosity(vec3 src, vec3 dst) {
    return setLuminance(dst, luminance(src));
}

// ── Main ──────────────────────────────────────────────────────────────────

void main()
{
    vec2 uv = openfl_TextureCoordv;

    vec4 src = texture2D(sourceSwag,     uv);
    vec4 bg  = texture2D(backgroundSwag, uv);

    // Pre-multiply alpha
    vec3 srcRGB = src.a > 0.0 ? src.rgb / src.a : vec3(0.0);
    vec3 bgRGB  = bg.a  > 0.0 ? bg.rgb  / bg.a  : vec3(0.0);

    vec3 result;

    // DARKEN = 5
    if (blendMode == 5)
        result = min(srcRGB, bgRGB);
    // LIGHTEN = 4
    else if (blendMode == 4)
        result = max(srcRGB, bgRGB);
    // DIFFERENCE = 6
    else if (blendMode == 6)
        result = abs(srcRGB - bgRGB);
    // INVERT = 9
    else if (blendMode == 9)
        result = 1.0 - bgRGB;
    // OVERLAY = 12
    else if (blendMode == 12)
        result = blendOverlay(srcRGB, bgRGB);
    // HARDLIGHT = 13
    else if (blendMode == 13)
        result = blendHardLight(srcRGB, bgRGB);
    // COLORDODGE = 15
    else if (blendMode == 15)
        result = blendColorDodge(srcRGB, bgRGB);
    // COLORBURN = 16
    else if (blendMode == 16)
        result = blendColorBurn(srcRGB, bgRGB);
    // SOFTLIGHT = 17
    else if (blendMode == 17)
        result = blendSoftLight(srcRGB, bgRGB);
    // EXCLUSION = 18
    else if (blendMode == 18)
        result = blendExclusion(srcRGB, bgRGB);
    // HUE = 19
    else if (blendMode == 19)
        result = blendHue(srcRGB, bgRGB);
    // SATURATION = 20
    else if (blendMode == 20)
        result = blendSaturation(srcRGB, bgRGB);
    // COLOR = 21
    else if (blendMode == 21)
        result = blendColor(srcRGB, bgRGB);
    // LUMINOSITY = 22
    else if (blendMode == 22)
        result = blendLuminosity(srcRGB, bgRGB);
    // Fallback: NORMAL
    else
        result = srcRGB;

    // Re-aplica el alpha del source
    float outAlpha = src.a + bg.a * (1.0 - src.a);
    gl_FragColor = vec4(result * outAlpha, outAlpha);
}
