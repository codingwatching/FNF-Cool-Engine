#pragma header

// rain.frag — shader de lluvia para phillyStreets (OVERLAY de sprite)
// Se aplica a un FlxSprite blanco de pantalla completa con scrollFactor(0,0).
// ShaderManager.applyShaderToCamera() gestiona el sprite internamente.
//
// ── FIXES ─────────────────────────────────────────────────────────────────────
// 1. SIN precision highp override: #pragma header ya inyecta mediump en GL ES.
//    Declarar una segunda directiva de precisión puede provocar error de
//    compilación silencioso en compiladores GLSL ES estrictos (algunos GPUs
//    Android/iOS), dejando el shader negro o transparente.
//
// 2. OUTPUT DE ALPHA PREMULTIPLICADO: OpenFL usa blending ONE / ONE_MINUS_SRC_A
//    (premultiplicado). Si se emite vec4(color, alpha) straight, el color se
//    suma de forma aditiva en lugar de mezclarse. La salida correcta es:
//    gl_FragColor = vec4(color * alpha, alpha)
//    Así el blending produce: dst = color*alpha + (1-alpha)*dst  ✓
//
// ── MODO OVERLAY ─────────────────────────────────────────────────────────────
// El shader NO muestrea bitmap (textura del sprite blanco).
// Emite un overlay semi-transparente que OpenFL composta sobre la escena.
// El efecto de oscurecimiento se obtiene sin leer la textura de la cámara.

uniform float uTime;
uniform float uScale;
uniform float uIntensity;
uniform float uPuddleY;
uniform float uPuddleScaleY;
uniform float uScreenW;
uniform float uScreenH;

// ── Hash / ruido ──────────────────────────────────────────────────────────────

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// ── Rayo de lluvia diagonal ───────────────────────────────────────────────────

float raindrop(vec2 uv, float t) {
    float speed  = 0.7 + hash(floor(uv.x * 38.0)) * 0.6;
    float offset = hash(floor(uv.x * 38.0) * 17.3);
    float xDrift = t * speed * 0.12;
    vec2  dUV    = vec2(uv.x + xDrift, uv.y);

    float y    = fract(dUV.y - t * speed + offset);
    float head = smoothstep(0.06, 0.0, abs(y - 0.05));
    float tail = smoothstep(0.22, 0.0, y) * (1.0 - smoothstep(0.0, 0.05, y));

    return clamp(head * 1.2 + tail * 0.6, 0.0, 1.0);
}

// ── Capa de lluvia ────────────────────────────────────────────────────────────

float rainLayer(vec2 uv, float t, float cellW, float cellH, float density, float speed) {
    vec2 cellSize = vec2(cellW, cellH);
    vec2 cell     = floor(uv / cellSize);
    vec2 cellUV   = fract(uv  / cellSize);

    if (hash2(cell) >= density) return 0.0;

    float xNorm   = cellUV.x * 2.0 - 1.0;
    float xFactor = smoothstep(0.45, 0.0, abs(xNorm));

    return raindrop(cellUV, t * speed) * xFactor;
}

// ── Reflejo de charco ─────────────────────────────────────────────────────────

float puddleReflection(vec2 screenPx, float t) {
    if (uPuddleScaleY <= 0.0) return 0.0;
    float dy    = screenPx.y - uPuddleY;
    if (dy < 0.0) return 0.0;
    float depth = dy * uPuddleScaleY;
    float wave  = sin(depth * 20.0 - t * 4.0) * 0.5 + 0.5;
    return wave * exp(-depth * 1.2) * 0.35;
}

// ── Main ──────────────────────────────────────────────────────────────────────

void main() {
    // Normalizar UV — guard contra builds donde llega en pixel space
    float _sw = (uScreenW > 1.0) ? uScreenW : 1280.0;
    float _sh = (uScreenH > 1.0) ? uScreenH : 720.0;
    vec2 sc;
    if (openfl_TextureCoordv.x > 2.0 || openfl_TextureCoordv.y > 2.0)
        sc = vec2(openfl_TextureCoordv.x / _sw, openfl_TextureCoordv.y / _sh);
    else
        sc = openfl_TextureCoordv;

    // Overlay completamente transparente cuando no hay efecto.
    if (uIntensity <= 0.0) {
        gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
        return;
    }

    float scale = (uScale > 0.01) ? uScale : 3.5;
    vec2  uv    = sc * scale;
    float t     = uTime;

    // ── 1. OSCURECIMIENTO ATMOSFÉRICO ─────────────────────────────────────────
    // darkAlpha mínimo 0.15 → visible incluso a la intensidad más baja (darnell).
    vec3  coldTint  = vec3(0.08, 0.11, 0.22);
    float darkAlpha = clamp(0.15 + uIntensity * 0.65, 0.15, 0.65);

    // ── 2. RAYOS DE LLUVIA ────────────────────────────────────────────────────
    float rain = 0.0;
    rain += rainLayer(uv,        t, 0.025, 0.09, 0.60, 1.0)  * 1.0;
    rain += rainLayer(uv * 0.65, t, 0.035, 0.12, 0.50, 0.75) * 0.65;
    rain += rainLayer(uv * 1.5,  t, 0.018, 0.07, 0.70, 1.3)  * 0.40;
    rain  = clamp(rain, 0.0, 1.0);

    vec3  dropColor  = vec3(0.75, 0.87, 1.0);
    float dropFactor = rain * clamp(uIntensity * 5.0, 0.5, 1.0);
    dropFactor = clamp(dropFactor * 0.55, 0.0, 0.55);

    // ── 3. REFLEJO DE CHARCO ──────────────────────────────────────────────────
    float puddle      = puddleReflection(vec2(sc.x * _sw, sc.y * _sh), t) * uIntensity;
    vec3  puddleColor = vec3(0.35, 0.45, 0.75);

    // ── COMPOSITAR ────────────────────────────────────────────────────────────
    vec3 color = coldTint;
    color = mix(color, dropColor,   dropFactor);
    color = mix(color, puddleColor, clamp(puddle * 0.8, 0.0, 1.0));

    float alpha = darkAlpha + dropFactor * 0.50 + puddle * 0.25;
    alpha = clamp(alpha, 0.0, 0.88);

    // ── PREMULTIPLIED ALPHA ───────────────────────────────────────────────────
    // OpenFL usa blending ONE / ONE_MINUS_SRC_ALPHA (premultiplicado).
    // Sin premultiplicar: dst = color + (1-alpha)*dst  → aditivo incorrecto.
    // Con premultiplicar: dst = color*alpha + (1-alpha)*dst  ✓
    gl_FragColor = vec4(color * alpha, alpha);
}
