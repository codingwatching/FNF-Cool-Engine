package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;

/**
 * NoteHoldShader — desvanece los bordes superior e inferior de cada pieza
 * of long note to hide the joints when segments are rotated.
 *
 * ── Why this works ───────────────────────────────────────────────────
 * Cada pieza de sustain es un sprite rectangular. Al rotar las piezas para
 * follow a curve (NightmareVision style), the corners of the rectangles
 * se asoman en las juntas, creando seams visibles.
 *
 * Solution: desvanecer uFadeZone fracción of the altura in the top edge
 * e inferior de cada pieza. Como las piezas se solapan ligeramente (scale.y
 * compensado by 1/cos(angle)), the zona of fade of a piece always queda
 * cubierta por la zona opaca de la siguiente. El resultado es una cadena
 * visually continuous regardless of the deformation angle.
 *
 * ── Premultiplied alpha ────────────────────────────────────────────────────
 * OpenFL usa texturas con alpha premultiplicado (rgb = color × alpha).
 * Para modificar la opacidad sin shift de color hay que:
 *   1. Desempaquetar: color = base.rgb / base.a
 *   2. Reempaquetar: output = vec4(color * newAlpha, newAlpha)
 * Sin esto, las zonas de fade muestran halo negro en los bordes.
 *
 * ── Uso ───────────────────────────────────────────────────────────────────
 *   note.shader = new NoteHoldShader();
 *   // The fade by default (0.18) is suficiente for the majority of mods.
 *   // Aumentar if the angles are very extremos.
 */
class NoteHoldShader extends FlxShader
{
	@:glFragmentSource("
		#pragma header

		// Fracción of the altura UV to desvanecer in each extremo (0.0 - 0.5).
		// 0.18 = 18% del alto de la pieza → suficiente para ocultar seams a
		// angles moderados. to angles very extremos is puede subir to 0.30.
		uniform float uFadeZone;

		// 1.0 si este es un segmento TAIL (holdend) — no desvanecer el
		// extremo libre (el 'punto' final de la nota larga).
		// 0.0 para segmentos de cuerpo (hold piece) — desvanecer ambos lados.
		uniform float uIsTail;

		// 1.0 si el sprite tiene flipY activo (downscroll).
		// Necesario for saber what extremo is the 'libre' in espacio UV.
		uniform float uFlipY;

		void main()
		{
			vec4 base = flixel_texture2D(bitmap, openfl_TextureCoordv);

			// Descartar pixels totalmente transparentes — optimization and avoids div/0
			if (base.a <= 0.001)
			{
				gl_FragColor = vec4(0.0);
				return;
			}

			float y = openfl_TextureCoordv.y;
			float fade = 1.0;

			if (uFadeZone > 0.001)
			{
				// Borde A = extremo 'conectado' (une con la pieza anterior / el strum)
				// Borde B = extremo 'libre'     (apunta hacia donde viene la nota)
				//
				// In upscroll (flipY=0): edge A is at y=0 (top UV), B at y=1
				// En downscroll (flipY=1): flipY invierte UVs → borde A en y=1, B en y=0
				float borderA = (uFlipY < 0.5) ? y : (1.0 - y);
				float borderB = 1.0 - borderA;

				// Siempre desvanecer el borde conectado
				float fadeA = smoothstep(0.0, uFadeZone, borderA);

				// Desvanecer el borde libre solo en segmentos de cuerpo (no tail)
				float fadeB = (uIsTail < 0.5)
					? smoothstep(0.0, uFadeZone, borderB)
					: 1.0;

				fade = fadeA * fadeB;
			}

			// Desempaquetar premult → aplicar fade → reempaquetar
			float newA = base.a * fade;
			vec3  col  = base.rgb / base.a;
			gl_FragColor = vec4(col * newA, newA);
		}
	")

	public function new(fadeZone:Float = 0.18)
	{
		super();
		uFadeZone.value = [fadeZone];
		uIsTail.value   = [0.0];
		uFlipY.value    = [0.0];
	}

	// ── Getters / setters para actualizar en runtime ──────────────────────────

	public var fadeZone(get, set):Float;
	inline function get_fadeZone():Float         return uFadeZone.value[0];
	inline function set_fadeZone(v:Float):Float  { uFadeZone.value = [v]; return v; }

	public var isTail(get, set):Bool;
	inline function get_isTail():Bool              return uIsTail.value[0] > 0.5;
	inline function set_isTail(v:Bool):Bool        { uIsTail.value = [v ? 1.0 : 0.0]; return v; }

	public var flipY(get, set):Bool;
	inline function get_flipY():Bool               return uFlipY.value[0] > 0.5;
	inline function set_flipY(v:Bool):Bool         { uFlipY.value = [v ? 1.0 : 0.0]; return v; }
}
