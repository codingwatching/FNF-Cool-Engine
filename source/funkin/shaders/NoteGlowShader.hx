package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;
import flixel.util.FlxColor;

/**
 * NoteGlowShader — replica el look del frame "Active" de FPS Plus,
 * compatible con CUALQUIER skin (colores custom, pixel art, etc.).
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
		uniform float uProximity;

		void main()
		{
			vec4 base = flixel_texture2D(bitmap, openfl_TextureCoordv);

			if (base.a <= 0.001)
			{
				gl_FragColor = vec4(0.0);
				return;
			}

			// ── EARLY EXIT: idle pass-through ──────────────────────────────
			// Sin este return el shader corre siempre y puede corromper
			// texturas no-premult en estado idle (clamp, division, etc.).
			if (uIntensity <= 0.001 && uProximity <= 0.001)
			{
				gl_FragColor = base;
				return;
			}

			// ── Desempaquetar premultiplied a straight alpha ───────────────
			vec3 straight = base.rgb / base.a;

			// Luminancia perceptual (Rec.601).
			// Solo guia la curva de brillo, no detecta colores especificos,
			// por lo que funciona igual con cualquier skin.
			float lum = dot(straight, vec3(0.299, 0.587, 0.114));

			// ── Fuerza del efecto ──────────────────────────────────────────
			float p            = uProximity * uProximity;     // curva cuadratica
			float pulse        = 0.85 + uPulse * 0.15;
			float glowStrength = clamp((uIntensity + p) * pulse, 0.0, 1.0);

			vec3 glowColor = vec3(uGlowR, uGlowG, uGlowB);

			// ── 1. BRIGHTENING hacia blanco ────────────────────────────────
			// El pixel se mueve hacia blanco en proporcion a su propia
			// luminancia. El centro blanco aparece DONDE YA HAY BRILLO en la
			// skin, sin importar su color → funciona con cualquier paleta.
			//
			// pow(lum, 1.5): curva que blanquea mas agresivamente los brillos
			// y deja casi intactos los oscuros (outline).
			float brightenT = pow(lum, 1.5) * glowStrength;
			vec3  brightened = mix(straight, vec3(1.0), brightenT);

			// ── 2. COLOR BOOST aditivo ─────────────────────────────────────
			// Añade glowColor de forma ADITIVA escalada por lum:
			//   - Pixels oscuros (outline) → boost minimo → outline preservado
			//   - Pixels medios/brillantes → tinte visible del color de direccion
			float boostAmt = glowStrength * lum * 0.30;
			vec3  boosted   = brightened + glowColor * boostAmt;

			// ── 3. OUTLINE DARKENING ───────────────────────────────────────
			// Pixels muy oscuros (lum < 0.25) se oscurecen ligeramente.
			// Replica el contorno mas definido del frame Active de FPS Plus.
			// smoothstep evita un corte abrupto entre outline y cuerpo.
			float outlineMask = 1.0 - smoothstep(0.0, 0.25, lum);
			float darkenAmt   = outlineMask * glowStrength * 0.25;
			vec3  result      = boosted * (1.0 - darkenAmt);

			result = clamp(result, 0.0, 1.0);

			// ── Re-empaquetar straight a premultiplied ─────────────────────
			gl_FragColor = vec4(result * base.a, base.a);
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
	 *  A 1.0 el shader replica el look del frame Active de FPS Plus. */
	public var proximity(get, set):Float;
	inline function get_proximity():Float  return uProximity.value[0];
	inline function set_proximity(v:Float):Float { uProximity.value = [v]; return v; }

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
