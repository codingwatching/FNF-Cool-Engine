#pragma header

// rain.frag — shader de lluvia para phillyStreets
// Solo uniforms float (FlxRuntimeShader no soporta bool/int de forma fiable).
//
// NOTA IMPORTANTE:
//   En shaders cargados en RUNTIME (FlxRuntimeShader desde archivo .frag),
//   usar texture2D() en vez de flixel_texture2D().
//   flixel_texture2D() solo está garantizada en shaders @:glFragmentSource
//   (compile-time). En runtime, algunos builds de flixel-addons NO la definen
//   → error de compilación GLSL silencioso → todos los uniforms quedan a 0
//   → uIntensity = 0 → early return → lluvia invisible.

uniform float uTime;
uniform float uScale;
uniform float uIntensity;
uniform float uPuddleY;
uniform float uPuddleScaleY;
uniform vec3  uRainColor;
uniform vec2  uScreenResolution;

// ── Hash / ruido ──────────────────────────────────────────────────────────

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// ── Gota individual ───────────────────────────────────────────────────────

float raindrop(vec2 uv, float t) {
    float speed   = 0.6 + hash(uv.x * 43.7) * 0.8;
    float offset  = hash(uv.x * 17.3);
    float y       = fract(uv.y - t * speed + offset);

    float tailLen = 0.15 + hash(uv.x * 31.1) * 0.1;
    float head    = smoothstep(0.08, 0.0, abs(y));
    float tail    = smoothstep(tailLen, 0.0, 1.0 - y);

    return clamp(head + tail * 0.5, 0.0, 1.0);
}

// ── Capa de lluvia ────────────────────────────────────────────────────────

float rainLayer(vec2 uv, float t, vec2 cellSize, float density) {
    vec2  cell   = floor(uv / cellSize);
    vec2  cellUV = fract(uv  / cellSize);

    if (hash2(cell) >= density) return 0.0;

    float xNorm   = cellUV.x * 2.0 - 1.0;
    float xFactor = smoothstep(0.35, 0.0, abs(xNorm));
    return raindrop(cellUV, t) * xFactor;
}

// ── Reflejo de charco ─────────────────────────────────────────────────────

float puddleReflection(vec2 screenPx, float t) {
    if (uPuddleScaleY <= 0.0) return 0.0;
    float dy = screenPx.y - uPuddleY;
    if (dy < 0.0) return 0.0;
    float depth = dy * uPuddleScaleY;
    float wave  = sin(depth * 25.0 - t * 3.0) * 0.5 + 0.5;
    return wave * exp(-depth * 1.5) * 0.25;
}

// ── Main ──────────────────────────────────────────────────────────────────

void main() {
    // FIX: texture2D en vez de flixel_texture2D.
    // flixel_texture2D no esta definida en shaders runtime de algunos builds
    // de flixel-addons. Si el shader falla la compilacion GLSL (silenciosa),
    // todos los uniforms quedan a 0: uIntensity=0 -> early return -> lluvia invisible.
    vec4 tex = texture2D(bitmap, openfl_TextureCoordv);

    if (uIntensity <= 0.0) {
        gl_FragColor = tex;
        return;
    }

    vec2 sc = openfl_TextureCoordv;

    // FIX: fallback para cuando uScale falla y se queda en 0 (default GLSL).
    // Con uScale=0: uv=vec2(0) -> xNorm=-1 -> xFactor=0 -> rain=0 -> invisible.
    float scale = (uScale > 0.01) ? uScale : 3.5;
    vec2 uv = sc * scale;
    float t = uTime;

    float rain = 0.0;
    rain += rainLayer(uv,        t,        vec2(0.04, 0.10), 0.55) * 1.0;
    rain += rainLayer(uv * 0.7,  t * 0.8,  vec2(0.06, 0.14), 0.45) * 0.7;
    rain += rainLayer(uv * 1.4,  t * 1.2,  vec2(0.03, 0.08), 0.65) * 0.5;
    rain  = clamp(rain, 0.0, 1.0);

    float puddle = puddleReflection(vec2(sc.x * uScreenResolution.x, sc.y * uScreenResolution.y), t) * uIntensity;

    vec3 base = mix(tex.rgb, uRainColor, puddle);

    // FIX: color de gota blanco-azulado brillante. uRainColor queda para el charco.
    vec3 dropColor = mix(vec3(0.88, 0.94, 1.0), uRainColor, 0.25);

    // FIX: amplificar uIntensity x4 para que valores bajos sean perceptibles.
    //   intensity=0.05 -> factor=0.20  (lluvia muy ligera, visible)
    //   intensity=0.10 -> factor=0.40  (lluvia ligera)
    //   intensity=0.20 -> factor=0.80  (lluvia moderada)
    //   intensity=0.40 -> factor=1.00  (lluvia intensa, clampeado)
    float dropFactor = min(rain * uIntensity * 4.0, 1.0);
    vec3 result = mix(base, dropColor, dropFactor);

    gl_FragColor = vec4(result, tex.a);
}
