package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;

/**
 * Port del ColorSwapShader de NightmareVision.
 * Desplaza hue/saturación/brillo en espacio HSV.
 *
 * Uso en skin.json con colorAuto:
 *   { "colorAuto": true }                          ← sin cambio de color (shifts 0,0,0)
 *   { "colorAuto": true, "colorHSV": [
 *       { "h": 0.0,  "s": 0.0, "b": 0.0 },        ← Left
 *       { "h": 0.5,  "s": 0.0, "b": 0.0 },        ← Down (giro 180° de tono)
 *       { "h": 0.33, "s": 0.2, "b": 0.0 },        ← Up
 *       { "h": 0.0,  "s": 0.0, "b": -0.1 }        ← Right
 *   ]}
 *
 * h: rotación de tono (0.0–1.0, wraps)
 * s: desplazamiento de saturación (se suma y clampea -1–1)
 * b: factor de brillo (value * (1 + b))
 */
class NoteColorSwapShader extends FlxShader
{
	/** Presets HSV neutros por dirección (Left/Down/Up/Right). Los skins los sobreescriben vía colorHSV. */
	public static final DIRECTION_PRESETS:Array<{ h:Float, s:Float, b:Float }> = [
		{ h: 0.0, s: 0.0, b: 0.0 }, // Left
		{ h: 0.0, s: 0.0, b: 0.0 }, // Down
		{ h: 0.0, s: 0.0, b: 0.0 }, // Up
		{ h: 0.0, s: 0.0, b: 0.0 }  // Right
	];

	@:glFragmentSource('
		#pragma header

		uniform float u_saturation;
		uniform float u_hue;
		uniform float u_brightness;
		uniform float u_shaderAlpha;
		uniform float u_flash;
		uniform float u_intensity;

		vec3 rgb2hsv(vec3 c)
		{
			vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
			vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
			vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
			float d = q.x - min(q.w, q.y);
			float e = 1.0e-10;
			return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
		}

		vec3 hsv2rgb(vec3 c)
		{
			vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
			vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
			return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
		}

		void main()
		{
			vec4 color = flixel_texture2D(bitmap, openfl_TextureCoordv);
			vec4 original = color;

			vec4 swagColor = vec4(rgb2hsv(vec3(color.rgb)), color.a);

			swagColor.r = swagColor.r + u_hue;
			swagColor.g = swagColor.g + clamp(u_saturation, -1.0, 1.0);
			swagColor.b = swagColor.b * (1.0 + u_brightness);

			vec4 shifted = vec4(hsv2rgb(vec3(swagColor.rgb)), swagColor.a);

			color = mix(original, shifted, u_intensity);

			if (u_flash != 0.0)
				color = mix(color, vec4(1.0, 1.0, 1.0, 1.0), u_flash) * color.a;

			color *= u_shaderAlpha;
			gl_FragColor = color;
		}
	')

	// ── Stored raw HSV values (before intensity scaling) ─────────────────
	private var _rawHue:Float        = 0.0;
	private var _rawSaturation:Float = 0.0;
	private var _rawBrightness:Float = 0.0;
	private var _intensity:Float     = 1.0;

	/**
	 * @param direction  Dirección inicial (0-3). -1 = sin preset de dirección.
	 * @param mult       Intensidad del efecto (0.0–1.0). Default: 1.0.
	 * @param preset     Preset HSV custom { h, s, b } o preset legacy RGB { r, g, b } (ignorado).
	 *                   También acepta el retorno de getCurrentPreset().
	 */
	public function new(?direction:Int = -1, ?mult:Float = 1.0, ?preset:Dynamic = null)
	{
		super();
		u_hue.value         = [0.0];
		u_saturation.value  = [0.0];
		u_brightness.value  = [0.0];
		u_shaderAlpha.value = [1.0];
		u_flash.value       = [0.0];
		u_intensity.value   = [1.0];

		_intensity = mult;
		u_intensity.value[0] = mult;

		if (direction >= 0)
			setDirection(direction);

		// Accept an HSV preset passed directly (e.g. from getCurrentPreset() / fromColor())
		if (preset != null && Reflect.hasField(preset, 'h'))
			applyEntry(cast preset);
	}

	// ── HSV properties (unscaled) ─────────────────────────────────────────

	public var hue(get, set):Float;
	inline function get_hue():Float        return _rawHue;
	inline function set_hue(v:Float):Float { _rawHue = v; u_hue.value[0] = v; return v; }

	public var saturation(get, set):Float;
	inline function get_saturation():Float        return _rawSaturation;
	inline function set_saturation(v:Float):Float { _rawSaturation = v; u_saturation.value[0] = v; return v; }

	public var brightness(get, set):Float;
	inline function get_brightness():Float        return _rawBrightness;
	inline function set_brightness(v:Float):Float { _rawBrightness = v; u_brightness.value[0] = v; return v; }

	/** Alpha propio del shader (multiplicador final sobre el color). Distinto del alpha de render de Flixel. */
	public var shaderAlpha(get, set):Float;
	inline function get_shaderAlpha():Float        return u_shaderAlpha.value[0];
	inline function set_shaderAlpha(v:Float):Float { u_shaderAlpha.value[0] = v; return v; }

	public var flash(get, set):Float;
	inline function get_flash():Float        return u_flash.value[0];
	inline function set_flash(v:Float):Float { u_flash.value[0] = v; return v; }

	/**
	 * Intensidad del efecto (0.0 = sin cambio de color, 1.0 = efecto completo).
	 * Actúa como factor de mezcla en GLSL: mix(original, shifted, intensity).
	 */
	public var intensity(get, set):Float;
	inline function get_intensity():Float        return _intensity;
	inline function set_intensity(v:Float):Float
	{
		_intensity = v;
		u_intensity.value[0] = v;
		return v;
	}

	// ── Direction / preset helpers ────────────────────────────────────────

	/**
	 * Aplica valores HSV de una entrada de colorHSV del skin.json.
	 * @param entry { h, s, b } — desplazamiento HSV para esta dirección.
	 */
	public function applyEntry(entry:{ h:Float, s:Float, b:Float }):Void
	{
		_rawHue        = entry.h;
		_rawSaturation = entry.s;
		_rawBrightness = entry.b;
		u_hue.value[0]        = entry.h;
		u_saturation.value[0] = entry.s;
		u_brightness.value[0] = entry.b;
	}

	/**
	 * Aplica el preset HSV para la dirección indicada.
	 * Si `customPreset` es un objeto { h, s, b } lo usa directamente.
	 * Si `customPreset` es un objeto RGB legacy { r, g, b } es ignorado (formato no soportado).
	 * @param dir          Dirección (0=Left, 1=Down, 2=Up, 3=Right).
	 * @param customPreset Preset HSV custom opcional.
	 */
	public function setDirection(dir:Int, ?customPreset:Dynamic = null):Void
	{
		if (customPreset != null && Reflect.hasField(customPreset, 'h'))
			applyEntry(cast customPreset);
		else
			applyEntry(DIRECTION_PRESETS[dir % 4]);
	}

	/**
	 * Devuelve el preset HSV actual (valores sin escalar por intensity).
	 * Puede pasarse al constructor de otro NoteColorSwapShader como tercer argumento.
	 */
	public function getCurrentPreset():{ h:Float, s:Float, b:Float }
	{
		return { h: _rawHue, s: _rawSaturation, b: _rawBrightness };
	}

	// ── Static factories ──────────────────────────────────────────────────

	/**
	 * Crea un shader con desplazamiento HSV derivado de un color hex.
	 * Convierte el color a HSV y usa su tono/saturación/brillo como desplazamiento.
	 */
	public static function fromColor(color:FlxColor, mult:Float = 1.0):NoteColorSwapShader
	{
		final s       = new NoteColorSwapShader(-1, mult);
		// FlxColor exposes hue (0–360), saturation (0–1) and brightness (0–1) as
		// direct properties — there is no getHSB() helper in HaxeFlixel.
		final targetH = color.hue / 360.0;
		final targetS = color.saturation;
		final targetB = color.brightness - 1.0; // desplazamiento relativo a brillo 1.0
		s.applyEntry({ h: targetH, s: targetS, b: targetB });
		return s;
	}

	// ── Tween helpers ─────────────────────────────────────────────────────

	/**
	 * Interpola el preset HSV del shader hacia el preset estándar de una dirección.
	 * @return FlxTween activo.
	 */
	public function tweenToDirection(dir:Int, duration:Float = 0.25,
		?ease:Float->Float):FlxTween
	{
		final easeFn = ease != null ? ease : FlxEase.linear;
		final target = DIRECTION_PRESETS[dir % 4];
		final fromH  = _rawHue;
		final fromS  = _rawSaturation;
		final fromB  = _rawBrightness;
		return FlxTween.num(0, 1, duration, { ease: easeFn }, t -> {
			applyEntry({
				h: fromH + (target.h - fromH) * t,
				s: fromS + (target.s - fromS) * t,
				b: fromB + (target.b - fromB) * t
			});
		});
	}

	/**
	 * Interpola el preset HSV del shader hacia el preset derivado de un color hex.
	 * @return FlxTween activo.
	 */
	public function tweenToColor(color:FlxColor, duration:Float = 0.25,
		?ease:Float->Float):FlxTween
	{
		final easeFn = ease != null ? ease : FlxEase.linear;
		final tmp    = fromColor(color, 1.0);
		final target = tmp.getCurrentPreset();
		final fromH  = _rawHue;
		final fromS  = _rawSaturation;
		final fromB  = _rawBrightness;
		return FlxTween.num(0, 1, duration, { ease: easeFn }, t -> {
			applyEntry({
				h: fromH + (target.h - fromH) * t,
				s: fromS + (target.s - fromS) * t,
				b: fromB + (target.b - fromB) * t
			});
		});
	}

	/**
	 * Interpola la intensidad del efecto entre dos valores.
	 * Útil para flashes de color sincronizados con el beat.
	 * @return FlxTween activo.
	 */
	public function tweenIntensity(fromMult:Float, toMult:Float, duration:Float = 0.2,
		?ease:Float->Float):FlxTween
	{
		final easeFn = ease != null ? ease : FlxEase.linear;
		intensity = fromMult;
		return FlxTween.num(fromMult, toMult, duration, { ease: easeFn }, v -> {
			intensity = v;
		});
	}
}
