package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;
import flixel.util.FlxColor;

/**
 * NoteGlowShader — tinte de color sutil aplicado a cada flecha.
 *
 * ─── Por qué el shader anterior rompía algunas skins ───────────────────────
 * El enfoque "unpack premult → procesar en espacio lineal → reempaquetar"
 * (base.rgb / base.a ... tinted * base.a) falla en dos escenarios:
 *
 *   1. Píxeles con alpha bajo (bordes AA, gradientes de skin):
 *      base.rgb / 0.05 → valores ×20, el clamp los aplana, el repack
 *      produce un color totalmente distinto → bordes y sombras arruinados.
 *
 *   2. Skins cuya textura NO está en espacio premultiplicado:
 *      la división + posterior *base.a doble-multiplica el alpha
 *      → la nota queda casi o totalmente invisible.
 *
 * ─── Solución ────────────────────────────────────────────────────────────────
 * Operar DIRECTAMENTE en espacio premultiplicado, sin unpack/repack:
 *   • blanco en premult    = vec3(base.a)
 *   • glowColor en premult = glowColor * base.a
 *   • clamp válido         = clamp(rgb, 0.0, base.a)
 * Sin sampling de vecinos → seguro con atlas.
 * Sin división por alpha  → sin NaN, sin overflow, correcto para cualquier skin.
 *
 * Uso:
 *   ShaderManager.applyToNote(arrowSprite, noteData % 4);
 */
class NoteGlowShader extends FlxShader
{
	@:glFragmentSource("
		#pragma header

		uniform float uGlowR;
		uniform float uGlowG;
		uniform float uGlowB;
		uniform float uIntensity;
		uniform float uPulse;

		// 0.0 = lejos del strum   1.0 = justo en el strum
		uniform float uProximity;

		void main()
		{
			vec4 base = flixel_texture2D(bitmap, openfl_TextureCoordv);

			// Descartar pixeles totalmente transparentes
			if (base.a <= 0.001)
			{
				gl_FragColor = vec4(0.0);
				return;
			}

			vec3 glowColor = vec3(uGlowR, uGlowG, uGlowB);
			float pulse    = 0.85 + uPulse * 0.15;

			// ── Operar directamente en espacio premultiplicado ─────────────
			// NO se hace base.rgb / base.a.
			// Esa division falla en dos escenarios comunes:
			//   - Alpha bajo (bordes AA, gradientes): divide por casi 0, dispara
			//     los valores de color, el clamp posterior los aplana y el repack
			//     produce un color completamente distinto al original.
			//   - Textura no-premult (algunas skins): la division y el posterior
			//     * base.a doble-multiplican el alpha -> la skin queda invisible.
			//
			// En premult:  blanco    = vec3(base.a)
			//              glowColor = glowColor * base.a
			//              rgb nunca puede superar alpha  -> clamp(x, 0.0, base.a)

			// ── Tinte de color base ────────────────────────────────────────
			// mix(base.rgb, glowColor*base.a, t): ambos en espacio premult
			float tintFactor = 0.18 * uIntensity * pulse;
			vec3 tinted = mix(base.rgb, glowColor * base.a, tintFactor);

			// Realce de brillo sutil (multiplicativo, correcto en premult)
			tinted = tinted * (1.0 + 0.08 * uIntensity * pulse);

			// ── Efecto de proximidad: la nota se ilumina hacia el blanco ───
			// p2: curva cuadratica — suave al principio, explosivo al final
			float p  = uProximity;
			float p2 = p * p;

			// 1) Blanqueado: mezclar hacia vec3(base.a) = blanco en premult
			float whitenAmount = p2 * 0.82;
			tinted = mix(tinted, vec3(base.a), whitenAmount);

			// 2) Bloom aditivo: escalar el boost por base.a (no salir del rango)
			float bloomBoost = p2 * 0.55;
			tinted = tinted + vec3(bloomBoost * base.a);

			// 3) Destello en el pico final, escalado por base.a
			float flash = smoothstep(0.92, 1.0, p);
			tinted = tinted + vec3(flash * 0.45 * base.a);

			// Clamp en premult: rgb no puede superar alpha
			tinted = clamp(tinted, 0.0, base.a);

			// Sin reempaquetar — ya estamos en premult, pasar alpha original
			gl_FragColor = vec4(tinted, base.a);
		}
	")

	// ── Colores por dirección FNF estándar ────────────────────────────────────
	public static final COLOR_LEFT  :FlxColor = 0xFFC24B99;
	public static final COLOR_DOWN  :FlxColor = 0xFF00FFFF;
	public static final COLOR_UP    :FlxColor = 0xFF12FA05;
	public static final COLOR_RIGHT :FlxColor = 0xFFF9393F;

	public function new(color:FlxColor = FlxColor.WHITE, intensity:Float = 0.55)
	{
		super();
		setColor(color);
		uIntensity.value = [intensity];
		uPulse.value     = [0.0];
		uProximity.value = [0.0];
	}

	/** Cambia el color del glow en runtime. */
	public function setColor(color:FlxColor):Void
	{
		uGlowR.value = [color.redFloat];
		uGlowG.value = [color.greenFloat];
		uGlowB.value = [color.blueFloat];
	}

	public var intensity(get, set):Float;
	inline function get_intensity():Float  return uIntensity.value[0];
	inline function set_intensity(v:Float):Float { uIntensity.value = [v]; return v; }

	public var pulse(get, set):Float;
	inline function get_pulse():Float  return uPulse.value[0];
	inline function set_pulse(v:Float):Float { uPulse.value = [v]; return v; }

	/** 0.0 = nota lejos del strum · 1.0 = nota justo en el strum.
	 *  Controla el efecto de iluminacion blanca / destello de proximidad. */
	public var proximity(get, set):Float;
	inline function get_proximity():Float  return uProximity.value[0];
	inline function set_proximity(v:Float):Float { uProximity.value = [v]; return v; }

	/** Crea un NoteGlowShader con el color de dirección FNF estándar. */
	public static function forDirection(direction:Int, intensity:Float = 0.55):NoteGlowShader
	{
		final color:FlxColor = switch (direction % 4)
		{
			case 0: COLOR_LEFT;
			case 1: COLOR_DOWN;
			case 2: COLOR_UP;
			default: COLOR_RIGHT;
		};
		return new NoteGlowShader(color, intensity);
	}
}
