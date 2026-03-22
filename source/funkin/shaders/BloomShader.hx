package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;

/**
 * BloomShader — efecto de brillo/resplandor.
 *
 * GLSL reescrito without loops for (problemáticos in the parser GLSL is of OpenFL).
 * Usa 9 muestras manuales para el blur del bright-pass.
 * uTexelSize eliminado of the constructor; the size of texel is pasa inline
 * via uBlurX / uBlurY in pixels normalizados (ej: 2.0/1920.0).
 */
class BloomShader extends FlxShader
{
	@:glFragmentSource("
		#pragma header

		uniform float uThreshold;
		uniform float uIntensity;
		uniform float uBlurX;
		uniform float uBlurY;

		vec3 brightPass(vec2 uv)
		{
			vec3 col = flixel_texture2D(bitmap, uv).rgb;
			float lum = dot(col, vec3(0.299, 0.587, 0.114));
			float diff = lum - uThreshold;
			float factor = diff > 0.0 ? diff : 0.0;
			return col * factor;
		}

		void main()
		{
			vec2 uv  = openfl_TextureCoordv;
			vec4 base = flixel_texture2D(bitmap, uv);

			vec2 o1 = vec2(uBlurX,  0.0);
			vec2 o2 = vec2(0.0,     uBlurY);
			vec2 o3 = vec2(uBlurX,  uBlurY);
			vec2 o4 = vec2(-uBlurX, uBlurY);

			vec3 blur =
				brightPass(uv)          * 0.2 +
				brightPass(uv + o1)     * 0.125 +
				brightPass(uv - o1)     * 0.125 +
				brightPass(uv + o2)     * 0.125 +
				brightPass(uv - o2)     * 0.125 +
				brightPass(uv + o3)     * 0.075 +
				brightPass(uv - o3)     * 0.075 +
				brightPass(uv + o4)     * 0.075 +
				brightPass(uv - o4)     * 0.075;

			vec3 result = base.rgb + blur * uIntensity;

			gl_FragColor = vec4(result, base.a);
		}
	")

	static inline var INV_W:Float = 1.0 / 1920.0;
	static inline var INV_H:Float = 1.0 / 1080.0;

	public function new(threshold:Float = 0.55, intensity:Float = 0.7, blurSize:Float = 2.0)
	{
		super();
		uThreshold.value = [threshold];
		uIntensity.value  = [intensity];
		uBlurX.value      = [blurSize * INV_W];
		uBlurY.value      = [blurSize * INV_H];
	}

	public var threshold(get, set):Float;
	inline function get_threshold():Float return uThreshold.value[0];
	inline function set_threshold(v:Float):Float { uThreshold.value = [v]; return v; }

	public var intensity(get, set):Float;
	inline function get_intensity():Float return uIntensity.value[0];
	inline function set_intensity(v:Float):Float { uIntensity.value = [v]; return v; }

	/** Updates the size of blur when changes the resolution. */
	public function setResolution(w:Float, h:Float, blurSize:Float = 2.0):Void
	{
		uBlurX.value = [blurSize / w];
		uBlurY.value = [blurSize / h];
	}
}
