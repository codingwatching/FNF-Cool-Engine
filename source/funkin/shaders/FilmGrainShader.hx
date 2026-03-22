package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;

/**
 * FilmGrainShader — grano of película sutil and animado.
 */
class FilmGrainShader extends FlxShader
{
	@:glFragmentSource("
		#pragma header

		uniform float uAmount;
		uniform float uTime;

		float rand(vec2 co, float seed)
		{
			return fract(sin(dot(co + vec2(seed, seed), vec2(12.9898, 78.233))) * 43758.5453);
		}

		void main()
		{
			vec4 color = flixel_texture2D(bitmap, openfl_TextureCoordv);

			float noise  = rand(openfl_TextureCoordv, uTime) * 2.0 - 1.0;
			float lum    = dot(color.rgb, vec3(0.299, 0.587, 0.114));
			float weight = lum > 0.5 ? 1.0 : lum * 2.0;

			vec3 result = color.rgb + noise * uAmount * weight;
			float r = result.r > 1.0 ? 1.0 : (result.r < 0.0 ? 0.0 : result.r);
			float g = result.g > 1.0 ? 1.0 : (result.g < 0.0 ? 0.0 : result.g);
			float b = result.b > 1.0 ? 1.0 : (result.b < 0.0 ? 0.0 : result.b);

			gl_FragColor = vec4(r, g, b, color.a);
		}
	")
	public function new(amount:Float = 0.045)
	{
		super();
		uAmount.value = [amount];
		uTime.value   = [0.0];
	}

	public var amount(get, set):Float;
	inline function get_amount():Float return uAmount.value[0];
	inline function set_amount(v:Float):Float { uAmount.value = [v]; return v; }

	public var time(get, set):Float;
	inline function get_time():Float return uTime.value[0];
	inline function set_time(v:Float):Float { uTime.value = [v]; return v; }
}
