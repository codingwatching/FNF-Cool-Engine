package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;
import flixel.util.FlxColor;

/**
 * NoteRGBShader — colorea automáticamente notas reutilizando el shader
 * noteRGB.frag de Psych Engine (mapeo de canales RGB a colores por dirección).
 *
 * ─── Cómo funciona ───────────────────────────────────────────────────────────
 * El shader aplica una transformación lineal por canal:
 *   newColor = clamp(src.r * uR + src.g * uG + src.b * uB, 0, 1)
 *
 * Esto permite recolorear sprites que usen los tres canales como capas
 * independientes (sombra, base, brillo) — como el atlas NOTE_assets.png.
 *
 * ─── Uso desde skin.json ─────────────────────────────────────────────────────
 *   { "colorAuto": true }                          ← presets por dirección
 *   { "colorAuto": true, "colorMult": 0.8 }        ← intensidad custom (0-1)
 *   { "colorAuto": true, "colorDirections": [      ← paleta custom
 *       { "r":[0.76,0.11,0.67], "g":[0,0,0], "b":[0.09,0.03,0.94] },
 *       { "r":[0,1,1],          "g":[0,0,0], "b":[0,1,0]          },
 *       { "r":[0.07,0.98,0.02], "g":[0,0,0], "b":[0,0.96,0]       },
 *       { "r":[0.98,0.22,0.25], "g":[0,0,0], "b":[0.96,0.09,0.12] }
 *   ]}
 *
 * ─── Presets por defecto (colores estándar FNF) ───────────────────────────────
 *  dir 0 Left  → púrpura  0xC24B99
 *  dir 1 Down  → cian     0x00FFFF
 *  dir 2 Up    → verde    0x12FA05
 *  dir 3 Right → rojo     0xF9393F
 */
class NoteRGBShader extends FlxShader
{
	// ── GLSL inline (misma lógica que noteRGB.frag) ───────────────────────────
	@:glFragmentSource("
		#pragma header

		uniform vec3 r;
		uniform vec3 g;
		uniform vec3 b;
		uniform float mult;

		vec4 flixel_texture2DCustom(sampler2D bitmap, vec2 coord) {
			vec4 color = flixel_texture2D(bitmap, coord);
			if (!hasTransform || color.a == 0.0 || mult == 0.0) {
				return color;
			}

			vec4 newColor = color;
			newColor.rgb = min(color.r * r + color.g * g + color.b * b, vec3(1.0));
			newColor.a = color.a;

			color = mix(color, newColor, mult);

			if(color.a > 0.0) {
				return vec4(color.rgb, color.a);
			}
			return vec4(0.0, 0.0, 0.0, 0.0);
		}

		void main() {
			gl_FragColor = flixel_texture2DCustom(bitmap, openfl_TextureCoordv);
		}
	")

	// ── Presets por dirección ─────────────────────────────────────────────────

	/**
	 * Preset RGB para cada dirección (0=Left, 1=Down, 2=Up, 3=Right).
	 * Cada entrada es { r:[x,y,z], g:[x,y,z], b:[x,y,z] } — vectores de columna
	 * de la matriz de transformación de color.
	 *
	 * Inspirados en los presets de Psych Engine para NOTE_assets.png.
	 */
	public static final PRESETS:Array<{ r:Array<Float>, g:Array<Float>, b:Array<Float> }> = [
		// dir 0 — Left — púrpura (0xC24B99)
		{ r: [0.76, 0.11, 0.67], g: [0.0, 0.0, 0.0], b: [0.09, 0.03, 0.94] },
		// dir 1 — Down — cian    (0x00FFFF)
		{ r: [0.0,  1.0,  1.0 ], g: [0.0, 0.0, 0.0], b: [0.0,  1.0,  0.0 ] },
		// dir 2 — Up   — verde   (0x12FA05)
		{ r: [0.07, 0.98, 0.02], g: [0.0, 0.0, 0.0], b: [0.0,  0.96, 0.0 ] },
		// dir 3 — Right — rojo   (0xF9393F)
		{ r: [0.98, 0.22, 0.25], g: [0.0, 0.0, 0.0], b: [0.96, 0.09, 0.12] },
	];

	// ── Constructor ───────────────────────────────────────────────────────────

	/**
	 * @param direction   Dirección de la nota (0-3). Usa el preset correspondiente.
	 * @param mult        Intensidad del efecto (0.0 = sin cambio, 1.0 = total). Default: 1.0.
	 * @param customPreset  Si no es null, usa este preset en lugar del default.
	 */
	public function new(direction:Int = 0, mult:Float = 1.0,
		?customPreset:{ r:Array<Float>, g:Array<Float>, b:Array<Float> })
	{
		super();

		final preset = customPreset ?? PRESETS[direction % PRESETS.length];

		this.r.value    = preset.r.copy();
		this.g.value    = preset.g.copy();
		this.b.value    = preset.b.copy();
		this.mult.value = [mult];
	}

	// ── API ───────────────────────────────────────────────────────────────────

	/** Intensidad del efecto (0.0–1.0). */
	public var intensity(get, set):Float;
	inline function get_intensity():Float         return this.mult.value[0];
	inline function set_intensity(v:Float):Float  { this.mult.value = [v]; return v; }

	/** Cambia el preset de dirección en runtime. */
	public function setDirection(direction:Int,
		?customPreset:{ r:Array<Float>, g:Array<Float>, b:Array<Float> }):Void
	{
		final preset = customPreset ?? PRESETS[direction % PRESETS.length];
		this.r.value = preset.r.copy();
		this.g.value = preset.g.copy();
		this.b.value = preset.b.copy();
	}

	/**
	 * Devuelve el preset actual como snapshot (copia de los valores actuales).
	 * Útil para calcular tweens desde el color activo.
	 */
	public function getCurrentPreset():{ r:Array<Float>, g:Array<Float>, b:Array<Float> }
	{
		return {
			r: this.r.value.copy(),
			g: this.g.value.copy(),
			b: this.b.value.copy()
		};
	}

	/**
	 * Tween suave de color: del preset actual → targetPreset en `duration` segundos.
	 *
	 * @param targetPreset   Preset destino (usa PRESETS[dir] si es null).
	 * @param duration       Duración del tween en segundos.
	 * @param ease           Función de ease (FlxEase.*). Default: linear.
	 * @param onComplete     Callback opcional al terminar.
	 * @return               El FlxTween creado (para cancelar si hace falta).
	 */
	public function tweenToPreset(
		targetPreset:{ r:Array<Float>, g:Array<Float>, b:Array<Float> },
		duration:Float = 0.25,
		?ease:Float->Float,
		?onComplete:flixel.tweens.FlxTween->Void):flixel.tweens.FlxTween
	{
		final fromR = this.r.value.copy();
		final fromG = this.g.value.copy();
		final fromB = this.b.value.copy();
		final toR   = targetPreset.r;
		final toG   = targetPreset.g;
		final toB   = targetPreset.b;
		final shader = this;

		return flixel.tweens.FlxTween.num(0.0, 1.0, duration,
			{ ease: ease ?? flixel.tweens.FlxEase.linear, onComplete: onComplete },
			function(t:Float)
			{
				shader.r.value = [
					fromR[0] + (toR[0] - fromR[0]) * t,
					fromR[1] + (toR[1] - fromR[1]) * t,
					fromR[2] + (toR[2] - fromR[2]) * t
				];
				shader.g.value = [
					fromG[0] + (toG[0] - fromG[0]) * t,
					fromG[1] + (toG[1] - fromG[1]) * t,
					fromG[2] + (toG[2] - fromG[2]) * t
				];
				shader.b.value = [
					fromB[0] + (toB[0] - fromB[0]) * t,
					fromB[1] + (toB[1] - fromB[1]) * t,
					fromB[2] + (toB[2] - fromB[2]) * t
				];
			}
		);
	}

	/**
	 * Tween de color hacia una dirección (0–3) usando los presets estándar.
	 *
	 * Ejemplo:
	 *   shader.tweenToDirection(2, 0.5, FlxEase.quadOut)  // → verde en 0.5s
	 */
	public function tweenToDirection(direction:Int, duration:Float = 0.25,
		?ease:Float->Float, ?onComplete:flixel.tweens.FlxTween->Void):flixel.tweens.FlxTween
	{
		return tweenToPreset(PRESETS[direction % PRESETS.length], duration, ease, onComplete);
	}

	/**
	 * Tween de color hacia un FlxColor hex.
	 *
	 * Ejemplo:
	 *   shader.tweenToColor(0xFF00FF, 0.3, FlxEase.sineInOut)
	 */
	public function tweenToColor(color:flixel.util.FlxColor, duration:Float = 0.25,
		?ease:Float->Float, ?onComplete:flixel.tweens.FlxTween->Void):flixel.tweens.FlxTween
	{
		final rF = color.redFloat;
		final gF = color.greenFloat;
		final bF = color.blueFloat;
		final target = {
			r: [rF, gF, bF],
			g: [0.0, 0.0, 0.0],
			b: [rF * 0.4, gF * 0.4, bF * 0.8 + 0.2]
		};
		return tweenToPreset(target, duration, ease, onComplete);
	}

	/**
	 * Tween de la intensidad (mult) de 0–1.
	 *
	 * Ejemplo — pulso en beat:
	 *   shader.tweenIntensity(1.0, 0.0, 0.15, FlxEase.quadOut)  // flash y vuelve
	 */
	public function tweenIntensity(fromMult:Float, toMult:Float, duration:Float = 0.2,
		?ease:Float->Float, ?onComplete:flixel.tweens.FlxTween->Void):flixel.tweens.FlxTween
	{
		final shader = this;
		return flixel.tweens.FlxTween.num(fromMult, toMult, duration,
			{ ease: ease ?? flixel.tweens.FlxEase.linear, onComplete: onComplete },
			function(v:Float) { shader.mult.value = [v]; }
		);
	}

	/**
	 * Crea un NoteRGBShader desde un color FlxColor convirtiendo a preset automáticamente.
	 * Útil cuando el modder define colores en hex en lugar de vectores.
	 *
	 * La conversión genera un preset que mapea las notas (principalmente rojo + azul
	 * como en NOTE_assets) al color destino.
	 */
	public static function fromColor(color:FlxColor, mult:Float = 1.0):NoteRGBShader
	{
		final rF = color.redFloat;
		final gF = color.greenFloat;
		final bF = color.blueFloat;

		// El canal rojo del sprite → color base de la nota
		// El canal azul del sprite → tint de sombra (versión más oscura del color)
		final preset = {
			r: [rF, gF, bF],
			g: [0.0, 0.0, 0.0],
			b: [rF * 0.4, gF * 0.4, bF * 0.8 + 0.2]
		};
		return new NoteRGBShader(0, mult, preset);
	}

	/**
	 * Fábrica rápida: shader para una dirección de nota usando los presets default.
	 */
	public static function forDirection(dir:Int, mult:Float = 1.0):NoteRGBShader
		return new NoteRGBShader(dir % 4, mult);
}
