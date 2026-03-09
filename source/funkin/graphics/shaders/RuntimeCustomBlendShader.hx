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
		// setBitmapData no existe en esta versión de FlxRuntimeShader.
		// Accedemos al ShaderInput dinámicamente via Reflect sobre this.data.
		var input:openfl.display.ShaderInput<BitmapData> = cast Reflect.field(this.data, "sourceSwag");
		if (input != null) input.input = value;
		return sourceSwag = value;
	}

	/** La textura de fondo (lo que había antes en pantalla). */
	public var backgroundSwag(default, set):BitmapData;

	function set_backgroundSwag(value:BitmapData):BitmapData
	{
		var input:openfl.display.ShaderInput<BitmapData> = cast Reflect.field(this.data, "backgroundSwag");
		if (input != null) input.input = value;
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
		this.setInt("blendMode", value);
		return blendSwag = value;
	}

	public function new()
	{
		// Lee el shader GLSL desde assets
		super(Assets.getText("assets/shaders/customBlend.frag"));
	}
}
