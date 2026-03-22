package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;

/**
 * ChromaticAberrationShader — separa ligeramente los canales RGB.
 * uOffset eliminado (era uniform sin usar, el parser lo quitaba y rompía la compilación).
 */
class ChromaticAberrationShader extends FlxShader
{
	@:glFragmentSource("
		#pragma header

		uniform float uIntensity;

		void main()
		{
			vec2 uv = openfl_TextureCoordv;

			float r = flixel_texture2D(bitmap, vec2(uv.x - uIntensity, uv.y)).r;
			float g = flixel_texture2D(bitmap, uv).g;
			float b = flixel_texture2D(bitmap, vec2(uv.x + uIntensity, uv.y)).b;
			float a = flixel_texture2D(bitmap, uv).a;

			gl_FragColor = vec4(r, g, b, a);
		}
	")
	public function new(intensity:Float = 0.003)
	{
		super();
		uIntensity.value = [intensity];
	}

	public var intensity(get, set):Float;
	inline function get_intensity():Float return uIntensity.value[0];
	inline function set_intensity(v:Float):Float { uIntensity.value = [v]; return v; }
}
