#pragma header

// ─── Uniforms ─────────────────────────────────────────────────────────────────
uniform float alphaShit;        // peso del blend (0.0 = solo base, 1.0 = blend completo)
uniform float xPos;             // offset X del UV secundario
uniform float yPos;             // offset Y del UV secundario
uniform sampler2D funnyShit;    // textura secundaria a mezclar (blend layer)

// ─── Blend Overlay ────────────────────────────────────────────────────────────
vec4 blendOverlay(vec4 base, vec4 blend)
{
    vec4 dark  = 2.0 * base * blend;
    vec4 light = 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
    return mix(light, dark, step(base, vec4(0.5)));
}

// ─── Main ─────────────────────────────────────────────────────────────────────
void main()
{
    vec2 uv   = openfl_TextureCoordv;
    vec4 base = flixel_texture2D(bitmap, uv);

    // FIX: si funnyShit no tiene textura asignada, el sampler devuelve (0,0,0,0).
    // Hacer overlay con negro = resultado negro.
    // Solucion: si el alpha de funnyShit es 0 (textura vacia), pasar el sprite sin cambios.
    vec2 blendUV = uv + vec2(xPos, yPos);
    vec4 overlay = texture2D(funnyShit, blendUV);

    if (overlay.a < 0.01)
    {
        gl_FragColor = base;
        return;
    }

    vec4 mixed  = blendOverlay(base, overlay);

    float weight = clamp(alphaShit, 0.0, 1.0);
    vec4 result  = mix(base, mixed, weight);

    // Preservar el alpha original del sprite base
    result.a = base.a;

    gl_FragColor = result;
}
