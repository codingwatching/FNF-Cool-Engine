package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;

/**
 * VignetteShader — darkens the edges of the screen.
 * Extends FlxShader to be compatible with FlxCamera.filters and FlxSprite.shader.
 */
class VignetteShader extends FlxShader
{
	@:glFragmentSource("
		#pragma header

		uniform float uStrength;
		uniform float uSmoothness;

		void main()
		{
			vec4 color = flixel_texture2D(bitmap, openfl_TextureCoordv);

			vec2 uv   = openfl_TextureCoordv - vec2(0.5, 0.5);
			float dist = length(uv * vec2(1.0, 1.6));
			float vignette = smoothstep(0.5, 0.5 - uSmoothness, dist * uStrength);

			gl_FragColor = vec4(color.rgb * vignette, color.a);
		}
	")
	public function new(strength:Float = 0.45, smoothness:Float = 0.35)
	{
		super();
		uStrength.value   = [strength];
		uSmoothness.value = [smoothness];
	}

	public var strength(get, set):Float;
	inline function get_strength():Float return uStrength.value[0];
	inline function set_strength(v:Float):Float { uStrength.value = [v]; return v; }

	public var smoothness(get, set):Float;
	inline function get_smoothness():Float return uSmoothness.value[0];
	inline function set_smoothness(v:Float):Float { uSmoothness.value = [v]; return v; }
}
