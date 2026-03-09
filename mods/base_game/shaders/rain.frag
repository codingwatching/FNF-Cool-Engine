#pragma header

// rain.frag — shader de lluvia atmosférica para phillyStreets
// Replica el look de V-Slice: oscurecimiento de escena + rayos diagonales visibles.
//
// BUG FIX: openfl_TextureCoordv cuando se usa como ShaderFilter de cámara está en
// espacio de píxeles (0..1280, 0..720), NO en UV normalizado [0..1].
// flixel_texture2D() divide internamente por openfl_TextureSize para normalizar.
// texture2D() no lo hace → muestrea fuera de rango → GL_CLAMP → negro.
// sc = openfl_TextureCoordv / openfl_TextureSize normaliza para los demás cálculos.

uniform float uTime;
uniform float uScale;
uniform float uIntensity;
uniform float uPuddleY;
uniform float uPuddleScaleY;
uniform float uScreenW;
uniform float uScreenH;

// ── Hash / ruido ──────────────────────────────────────────────────────────

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// ── Rayo de lluvia diagonal ───────────────────────────────────────────────
// Las gotas caen con una leve inclinación hacia la derecha (viento ligero).

float raindrop(vec2 uv, float t) {
    float speed  = 0.7 + hash(floor(uv.x * 38.0)) * 0.6;
    float offset = hash(floor(uv.x * 38.0) * 17.3);
    // Movimiento diagonal: x se desplaza levemente con el tiempo
    float xDrift = t * speed * 0.12;
    vec2 dUV = vec2(uv.x + xDrift, uv.y);

    float y = fract(dUV.y - t * speed + offset);

    // Cabeza brillante
    float head = smoothstep(0.06, 0.0, abs(y - 0.05));
    // Cola larga semitransparente
    float tail = smoothstep(0.22, 0.0, y) * (1.0 - smoothstep(0.0, 0.05, y));

    return clamp(head * 1.2 + tail * 0.6, 0.0, 1.0);
}

// ── Capa de lluvia ────────────────────────────────────────────────────────

float rainLayer(vec2 uv, float t, float cellW, float cellH, float density, float speed) {
    vec2 cellSize = vec2(cellW, cellH);
    vec2 cell     = floor(uv / cellSize);
    vec2 cellUV   = fract(uv  / cellSize);

    if (hash2(cell) >= density) return 0.0;

    // Fade en los bordes horizontales de la celda
    float xNorm   = cellUV.x * 2.0 - 1.0;
    float xFactor = smoothstep(0.45, 0.0, abs(xNorm));

    return raindrop(cellUV, t * speed) * xFactor;
}

// ── Reflejo de charco ─────────────────────────────────────────────────────

float puddleReflection(vec2 screenPx, float t) {
    if (uPuddleScaleY <= 0.0) return 0.0;
    float dy = screenPx.y - uPuddleY;
    if (dy < 0.0) return 0.0;
    float depth = dy * uPuddleScaleY;
    float wave  = sin(depth * 20.0 - t * 4.0) * 0.5 + 0.5;
    return wave * exp(-depth * 1.2) * 0.35;
}

// ── Main ──────────────────────────────────────────────────────────────────

void main() {
    // FIX: flixel_texture2D normaliza openfl_TextureCoordv dividiéndolo por
    // openfl_TextureSize antes de pasarlo a texture2D.
    // texture2D(bitmap, openfl_TextureCoordv) con coordenadas en pixel-space
    // (ej. 640, 360) muestrea fuera de [0,1] → GL_CLAMP_TO_EDGE → mismo
    // píxel en toda la pantalla → negro.
    vec4 tex = flixel_texture2D(bitmap, openfl_TextureCoordv);

    if (uIntensity <= 0.0) {
        gl_FragColor = tex;
        return;
    }

    // Normalizar a UV [0..1] para los cálculos de posición de lluvia y charco.
    // openfl_TextureSize contiene las dimensiones reales de la textura de cámara.
    vec2 sc    = openfl_TextureCoordv / openfl_TextureSize;
    float scale = (uScale > 0.01) ? uScale : 3.5;
    vec2 uv = sc * scale;
    float t  = uTime;

    // ── 1. OSCURECIMIENTO ATMOSFÉRICO ─────────────────────────────────────
    // La escena se oscurece y toma un tinte azul-gris frío, como en la ref.
    float darkAmount = clamp(uIntensity * 0.7, 0.0, 0.55);

    // Tinte frío: mezcla hacia un azul-gris oscuro
    vec3 coldTint = vec3(0.18, 0.22, 0.32);
    vec3 base = mix(tex.rgb, coldTint, darkAmount);

    // ── 2. RAYOS DE LLUVIA ────────────────────────────────────────────────
    float rain = 0.0;
    // Capa primaria — gotas medianas, densas
    rain += rainLayer(uv,        t, 0.025, 0.09, 0.60, 1.0)  * 1.0;
    // Capa secundaria — gotas más finas (profundidad)
    rain += rainLayer(uv * 0.65, t, 0.035, 0.12, 0.50, 0.75) * 0.65;
    // Capa terciaria — fondo lejano, muy fina
    rain += rainLayer(uv * 1.5,  t, 0.018, 0.07, 0.70, 1.3)  * 0.40;
    rain  = clamp(rain, 0.0, 1.0);

    // Color de gota: blanco-azulado
    vec3 dropColor = vec3(0.75, 0.87, 1.0);
    float dropFactor = rain * clamp(uIntensity * 5.0, 0.5, 1.0);
    base = mix(base, dropColor, clamp(dropFactor * 0.55, 0.0, 0.55));

    // ── 3. REFLEJO DE CHARCO ──────────────────────────────────────────────
    // sc ya está en [0..1], multiplicar por screenW/H da coordenadas de pantalla.
    float screenW = (uScreenW > 1.0) ? uScreenW : 1280.0;
    float screenH = (uScreenH > 1.0) ? uScreenH : 720.0;
    float puddle  = puddleReflection(vec2(sc.x * screenW, sc.y * screenH), t) * uIntensity;
    vec3 puddleColor = vec3(0.35, 0.45, 0.75);
    base = mix(base, puddleColor, puddle);

    gl_FragColor = vec4(base, tex.a);
}
