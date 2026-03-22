package funkin.graphics.framebuffer;

import openfl.display.BitmapData;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.display.IBitmapDrawable;
import openfl.display.OpenGLRenderer;
import openfl.display3D.textures.TextureBase;
import openfl.Lib;

/**
 * BitmapData corregida para funcionar bien con el renderer OpenGL.
 * Portado de v-slice (FunkinCrew/Funkin).
 */
@:nullSafety
@:access(openfl.display3D.textures.TextureBase)
@:access(openfl.display.OpenGLRenderer)
class FixedBitmapData extends BitmapData
{
	override function __drawGL(source:IBitmapDrawable, renderer:OpenGLRenderer):Void
	{
		if (Std.isOfType(source, DisplayObject))
		{
			final object:DisplayObjectContainer = cast source;
			renderer.__stage = object.stage;
		}
		super.__drawGL(source, renderer);
	}

	/**
	 * Crea una FixedBitmapData con las dimensiones dadas.
	 * @param width  Width in pixels
	 * @param height Height in pixels
	 * @param useGPU Si es true usa una textura de hardware (recomendado)
	 */
	public static function create(width:Int, height:Int, useGPU:Bool = true):FixedBitmapData
	{
		if (useGPU)
		{
			// FIX: context3D puede ser null en Android durante el arranque.
			// If no is available, caemos to bitmap software (without GPU).
			var texture:Null<TextureBase> = _createTexture(width, height);
			if (texture != null) return fromTexture(texture);
		}
		return new FixedBitmapData(width, height, true, 0);
	}

	/**
	 * Crea una FixedBitmapData desde una textura de hardware.
	 */
	public static function fromTexture(texture:TextureBase):FixedBitmapData
	{
		var bitmapData:FixedBitmapData = new FixedBitmapData(texture.__width, texture.__height, true, 0);
		bitmapData.readable = false;
		bitmapData.__texture = texture;
		bitmapData.__textureContext = texture.__textureContext;

		@:nullSafety(Off)
		bitmapData.image = null;

		return bitmapData;
	}

	static function _createTexture(width:Int, height:Int):Null<TextureBase>
	{
		// The textures of size cero dan problemas
		width  = width  < 1 ? 1 : width;
		height = height < 1 ? 1 : height;
		// FIX: context3D es null en Android hasta el primer frame renderizado.
		// Return null here is safe; create() caerá to bitmap software.
		var ctx = Lib.current.stage.context3D;
		if (ctx == null) return null;
		return ctx.createTexture(width, height, BGRA, true);
	}
}
