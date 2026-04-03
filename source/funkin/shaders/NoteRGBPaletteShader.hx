package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;

/**
 * Port del RGBPaletteShader de NightmareVision.
 * Reemplaza los canales R, G y B de la textura con colores reales de gameplay.
 *
 * Cómo funciona:
 *   El spritesheet de notas usa rojo, verde y azul como "capas de máscara".
 *   El shader multiplica cada canal por un color destino:
 *     pixel_final = clamp(pixel.r * colorR + pixel.g * colorG + pixel.b * colorB, 0, 1)
 *
 * Uso en skin.json con colorAuto + colorDirections:
 * {
 *   "colorAuto": true,
 *   "colorDirections": [
 *     { "r": [1.0, 0.25, 0.25], "g": [0.6, 0.0, 0.6], "b": [0.1, 0.1, 0.1] },  <- Left
 *     { "r": [0.25, 1.0, 0.25], "g": [0.0, 0.6, 0.0], "b": [0.1, 0.1, 0.1] },  <- Down
 *     { "r": [0.25, 0.25, 1.0], "g": [0.0, 0.0, 0.6], "b": [0.1, 0.1, 0.1] },  <- Up
 *     { "r": [1.0, 1.0, 0.25], "g": [0.6, 0.6, 0.0], "b": [0.1, 0.1, 0.1] }   <- Right
 *   ]
 * }
 *
 * Cada entrada tiene:
 *   r → color de reemplazo para el canal rojo de la textura   [R, G, B] floats 0-1
 *   g → color de reemplazo para el canal verde de la textura
 *   b → color de reemplazo para el canal azul de la textura
 */
class NoteRGBPaletteShader extends FlxShader
{
	@:glFragmentHeader('
		#pragma header

		uniform vec3 r;
		uniform vec3 g;
		uniform vec3 b;
		uniform float mult;
		uniform float u_alpha;
		uniform float u_flash;
		uniform bool u_enabled;

		vec4 flixel_texture2DCustom(sampler2D bitmap, vec2 coord)
		{
			vec4 color = flixel_texture2D(bitmap, coord);

			if (!u_enabled || !hasTransform || color.a == 0.0 || mult == 0.0)
				return color;

			vec4 newColor = color;
			newColor.rgb = min(color.r * r + color.g * g + color.b * b, vec3(1.0));
			newColor.a   = color.a;

			color = mix(color, newColor, mult);

			if (color.a > 0.0)
				return vec4(color.rgb, color.a);
			return vec4(0.0, 0.0, 0.0, 0.0);
		}
	')

	@:glFragmentSource('
		#pragma header

		void main()
		{
			vec4 texOutput = flixel_texture2DCustom(bitmap, openfl_TextureCoordv);

			if (u_flash != 0.0)
				texOutput = mix(texOutput, vec4(1.0, 1.0, 1.0, 1.0), u_flash) * texOutput.a;

			texOutput *= u_alpha;
			gl_FragColor = texOutput;
		}
	')

	// ── Habilitación del efecto ───────────────────────────────────────────────

	public var enabled(get, set):Bool;

	inline function get_enabled():Bool
		return u_enabled.value != null && u_enabled.value[0];

	inline function set_enabled(v:Bool):Bool
	{
		u_enabled.value = [v];
		return v;
	}

	// ── Intensidad de mezcla (0 = sin efecto, 1 = reemplazo total) ────────────

	public var intensity(get, set):Float;

	inline function get_intensity():Float
		return mult.value != null ? mult.value[0] : 1.0;

	inline function set_intensity(v:Float):Float
	{
		mult.value = [v];
		return v;
	}

	// ── Alpha y flash ──────────────────────────────────────────────────────────

	public var shaderAlpha(get, set):Float;

	inline function get_shaderAlpha():Float
		return u_alpha.value != null ? u_alpha.value[0] : 1.0;

	inline function set_shaderAlpha(v:Float):Float
	{
		u_alpha.value = [v];
		return v;
	}

	public var flash(get, set):Float;

	inline function get_flash():Float
		return u_flash.value != null ? u_flash.value[0] : 0.0;

	inline function set_flash(v:Float):Float
	{
		u_flash.value = [v];
		return v;
	}

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new()
	{
		super();

		// Defaults: reemplazos neutros (identidad aproximada), fully enabled.
		r.value        = [1.0, 0.0, 0.0]; // rojo → rojo
		g.value        = [0.0, 1.0, 0.0]; // verde → verde
		b.value        = [0.0, 0.0, 1.0]; // azul → azul
		mult.value     = [1.0];
		u_alpha.value  = [1.0];
		u_flash.value  = [0.0];
		u_enabled.value = [true];
	}

	// ── API principal ─────────────────────────────────────────────────────────

	/**
	 * Aplica los tres canales de color desde arrays de floats [R, G, B] normalizados.
	 * Equivalente a NightmareVision: shader.r.value = [...], etc.
	 *
	 * @param rVec  Color de reemplazo para el canal rojo   → [rf, gf, bf]  (0.0–1.0)
	 * @param gVec  Color de reemplazo para el canal verde  → [rf, gf, bf]
	 * @param bVec  Color de reemplazo para el canal azul   → [rf, gf, bf]
	 */
	public function setColors(rVec:Array<Float>, gVec:Array<Float>, bVec:Array<Float>):Void
	{
		r.value = _padVec3(rVec);
		g.value = _padVec3(gVec);
		b.value = _padVec3(bVec);
	}

	/**
	 * Aplica colores desde un FlxColor para cada canal.
	 * Útil cuando los colores vienen de preferencias de usuario (como arrowRGB en Psych).
	 *
	 * @param rColor  FlxColor que reemplaza el canal rojo
	 * @param gColor  FlxColor que reemplaza el canal verde
	 * @param bColor  FlxColor que reemplaza el canal azul
	 */
	public function setFlxColors(rColor:flixel.util.FlxColor, gColor:flixel.util.FlxColor, bColor:flixel.util.FlxColor):Void
	{
		r.value = [rColor.redFloat, rColor.greenFloat, rColor.blueFloat];
		g.value = [gColor.redFloat, gColor.greenFloat, gColor.blueFloat];
		b.value = [bColor.redFloat, bColor.greenFloat, bColor.blueFloat];
	}

	// ── Utilidad privada ──────────────────────────────────────────────────────

	/** Asegura que el array tenga exactamente 3 elementos para vec3. */
	static inline function _padVec3(v:Array<Float>):Array<Float>
	{
		if (v == null) return [0.0, 0.0, 0.0];
		return [
			v.length > 0 ? v[0] : 0.0,
			v.length > 1 ? v[1] : 0.0,
			v.length > 2 ? v[2] : 0.0
		];
	}
}
