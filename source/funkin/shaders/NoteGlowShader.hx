package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;
import flixel.util.FlxColor;

/**
 * NoteGlowShader — tinte de color sutil aplicado a cada flecha.
 *
 * ─── Why the previous shader broke the arrows ───────────────────────────
 * OpenFL usa texturas con alfa PREMULTIPLICADO: base.rgb ya es color×alpha.
 * The shader previous hacía `inner * base.to` → color×alpha² → the pixels
 * semi-transparentes de los bordes quedaban casi invisibles.
 * Furthermore, the 4-tap of vecinos (+/-uGlowSize) in a atlas spritesheet
 * sampleaba frames adyacentes → alpha corrupto → flechas invisibles.
 *
 * ─── Solution ────────────────────────────────────────────────────────────────
 * 1. Desempaquetar premult: actual_rgb = base.rgb / base.a
 * 2. Aplicar tinte sobre el color real
 * 3. Reempaquetar: output = vec4(tinted * base.a, base.a)
 * Sin sampling de vecinos → seguro con atlas.
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

		void main()
		{
			vec4 base = flixel_texture2D(bitmap, openfl_TextureCoordv);

			// Descartar pixeles totalmente transparentes (optimizacion + evita div/0)
			if (base.a <= 0.001)
			{
				gl_FragColor = vec4(0.0);
				return;
			}

			vec3 glowColor = vec3(uGlowR, uGlowG, uGlowB);
			float pulse    = 0.85 + uPulse * 0.15;

			// Desempaquetar premult -> color real -> tinte -> reempaquetar
			vec3 color  = base.rgb / base.a;
			vec3 tinted = mix(color, glowColor, 0.18 * uIntensity * pulse);

			// Realce de brillo sutil para que se note el glow
			tinted = clamp(tinted * (1.0 + 0.08 * uIntensity * pulse), 0.0, 1.0);

			gl_FragColor = vec4(tinted * base.a, base.a);
		}
	")

	// ── Colores by direction FNF standard ────────────────────────────────────
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

	/** Creates a NoteGlowShader with the color of direction FNF standard. */
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
