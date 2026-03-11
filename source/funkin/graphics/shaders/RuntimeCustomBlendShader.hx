package funkin.graphics.shaders;

import openfl.Assets;
import openfl.display.BitmapData;

/**
 * Shader de blend mode personalizado.
 * Usa el archivo GLSL assets/shaders/customBlend.frag.
 *
 * Portado de v-slice (FunkinCrew/Funkin).
 */
class RuntimeCustomBlendShader extends RuntimePostEffectShader
{
	/** La textura fuente (el sprite que se está dibujando). */
	public var sourceSwag(default, set):BitmapData;

	function set_sourceSwag(value:BitmapData):BitmapData
	{
		// Intentar primero via ShaderInput (API directa) luego fallback a Reflect
		try
		{
			var input:openfl.display.ShaderInput<BitmapData> = cast @:privateAccess this.data.sourceSwag;
			if (input != null) { input.input = value; return sourceSwag = value; }
		}
		catch (_:Dynamic) {}
		// Fallback Reflect para versiones sin acceso directo
		try
		{
			var input:openfl.display.ShaderInput<BitmapData> = cast Reflect.field(this.data, "sourceSwag");
			if (input != null) input.input = value;
		}
		catch (_:Dynamic) {}
		return sourceSwag = value;
	}

	/** La textura de fondo (lo que había antes en pantalla). */
	public var backgroundSwag(default, set):BitmapData;

	function set_backgroundSwag(value:BitmapData):BitmapData
	{
		try
		{
			var input:openfl.display.ShaderInput<BitmapData> = cast @:privateAccess this.data.backgroundSwag;
			if (input != null) { input.input = value; return backgroundSwag = value; }
		}
		catch (_:Dynamic) {}
		try
		{
			var input:openfl.display.ShaderInput<BitmapData> = cast Reflect.field(this.data, "backgroundSwag");
			if (input != null) input.input = value;
		}
		catch (_:Dynamic) {}
		return backgroundSwag = value;
	}

	/**
	 * El blend mode a aplicar como entero GLSL.
	 * Usa FunkinCamera.blendModeToInt() para convertir un BlendMode nativo a este valor.
	 * Valores: LIGHTEN=4, DARKEN=5, DIFFERENCE=6, INVERT=9, OVERLAY=12, HARDLIGHT=13,
	 *          COLORDODGE=15, COLORBURN=16, SOFTLIGHT=17, EXCLUSION=18,
	 *          HUE=19, SATURATION=20, COLOR=21, LUMINOSITY=22
	 */
	public var blendSwag(default, set):Int = 0;

	function set_blendSwag(value:Int):Int
	{
		// safeSetInt prueba setInt() y hace fallback a setFloat() si falla
		this.safeSetInt("blendMode", value);
		return blendSwag = value;
	}

	public function new()
	{
		// Lee el shader GLSL desde assets
		super(Assets.getText("assets/shaders/customBlend.frag"));
	}
}
