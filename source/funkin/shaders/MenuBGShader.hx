package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;

/**
 * MenuBGShader — Coloriza un sketch desaturado (fondo claro, trazos oscuros).
 *
 * Resultado:
 *   • Fondo → negro puro
 *   • Trazos → color definido por los componentes RGB (con transición suave entre A y B)
 *
 * Uniforms (todos float, como requiere FlxShader en este proyecto):
 *   uColorAR/G/B   Color actual de los trazos   (default: rosa  #FF69B4)
 *   uColorBR/G/B   Color destino (transición)    (default: morado #9B30FF)
 *   uBlend         0 = 100% colorA · 1 = 100% colorB
 *   uContrast      Sharpness de los trazos (recomendado: 1.5–3.0)
 *   uBrightness    Multiplicador general de brillo (default 1.0)
 */
class MenuBGShader extends FlxShader
{
	@:glFragmentSource("
		#pragma header

		uniform float uColorAR;
		uniform float uColorAG;
		uniform float uColorAB;

		uniform float uColorBR;
		uniform float uColorBG;
		uniform float uColorBB;

		uniform float uBlend;
		uniform float uContrast;
		uniform float uBrightness;

		void main()
		{
			vec4 tex = flixel_texture2D(bitmap, openfl_TextureCoordv);

			// Luminancia del pixel original (fondo claro ~ 0.85, trazos ~ 0.35-0.55)
			float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));

			// Invertir: trazos oscuros -> valor alto, fondo claro -> valor bajo
			float raw = 1.0 - lum;

			// Curva de contraste para enfatizar los trazos
			float strokeStrength = clamp(pow(raw * 1.15, uContrast), 0.0, 1.0);

			// Reconstruir colores desde floats
			vec3 colorA = vec3(uColorAR, uColorAG, uColorAB);
			vec3 colorB = vec3(uColorBR, uColorBG, uColorBB);

			// Interpolar entre los dos colores de paleta
			vec3 color = mix(colorA, colorB, clamp(uBlend, 0.0, 1.0));

			// Fondo = negro, trazos = color elegido
			vec3 finalColor = color * strokeStrength * uBrightness;

			gl_FragColor = vec4(finalColor, tex.a);
		}
	")

	public function new()
	{
		super();
		// Rosa neon por defecto (#FF69B4)
		uColorAR.value = [1.00];
		uColorAG.value = [0.41];
		uColorAB.value = [0.71];
		// Morado por defecto (#9B30FF)
		uColorBR.value = [0.61];
		uColorBG.value = [0.19];
		uColorBB.value = [1.00];

		uBlend.value      = [0.0];
		uContrast.value   = [2.2];
		uBrightness.value = [1.0];
	}

	// ── Helpers para asignar colores ─────────────────────────────────────────

	/** Asigna el color A (canal actual) en floats 0-1. */
	public function setColorA(r:Float, g:Float, b:Float):Void
	{
		uColorAR.value = [r];
		uColorAG.value = [g];
		uColorAB.value = [b];
	}

	/** Asigna el color B (canal destino) en floats 0-1. */
	public function setColorB(r:Float, g:Float, b:Float):Void
	{
		uColorBR.value = [r];
		uColorBG.value = [g];
		uColorBB.value = [b];
	}

	/** Asigna el blend (0 = A puro, 1 = B puro). */
	public function setBlend(v:Float):Void
		uBlend.value = [v];

	/** Convierte 0xRRGGBB a Array<Float> [r, g, b] en rango 0-1. */
	public static function hexToRGB(hex:Int):Array<Float>
	{
		return [
			((hex >> 16) & 0xFF) / 255.0,
			((hex >>  8) & 0xFF) / 255.0,
			( hex        & 0xFF) / 255.0
		];
	}
}
