package funkin.graphics.framebuffer;

import openfl.display.BitmapData;
import openfl.display3D.Context3D;
import openfl.display3D.textures.TextureBase;
import openfl.filters.BitmapFilter;
import animate.internal.FilterRenderer;
import flixel.math.FlxMatrix;
import openfl.display.OpenGLRenderer;
import flixel.FlxCamera;
import flixel.FlxG;
import openfl.Lib;
import openfl.geom.Matrix;
import openfl.geom.ColorTransform;

/**
 * Utilidades para BitmapData relacionadas con cámaras y filtros.
 * Portado de v-slice (FunkinCrew/Funkin).
 */
@:nullSafety
@:access(openfl.display.BitmapData)
@:access(openfl.display3D.textures.TextureBase)
@:access(openfl.display3D.Context3D)
@:access(openfl.display.OpenGLRenderer)
@:access(flixel.FlxCamera)
@:access(openfl.display.Sprite)
@:access(openfl.geom.ColorTransform)
class BitmapDataUtil
{
	static var renderer(get, never):Null<OpenGLRenderer>;
	static var _renderer:Null<OpenGLRenderer>;

	// @:nullSafety(Off) — deliberate: returns null when the GL surface isn't ready yet
	// (e.g. Android first frame). Callers MUST null-check before use.
	@:nullSafety(Off)
	static function get_renderer():Null<OpenGLRenderer>
	{
		if (_renderer == null)
		{
			// context3D is null on Android until the first rendered frame.
			// Returning null here is intentional; callers handle it gracefully.
			final ctx = FlxG.stage?.context3D;
			if (ctx == null) return null;
			_renderer = new OpenGLRenderer(ctx);
			_renderer.__worldTransform = new Matrix();
			_renderer.__worldColorTransform = new ColorTransform();
		}
		return _renderer;
	}

	/**
	 * Dibuja el contenido de varias cámaras en un BitmapData.
	 */
	public static function drawCameraScreens(bitmap:BitmapData, cameras:Array<FlxCamera>):BitmapData
	{
		bitmap.__fillRect(bitmap.rect, 0, true);

		for (camera in cameras)
		{
			if (camera.filters != null && camera.filters.length > 0)
				drawCameraScreen(bitmap, camera, false, true);
			else
				drawCameraScreen(bitmap, camera, false);
		}

		return bitmap;
	}

	/**
	 * Dibuja el contenido de una cámara en un BitmapData.
	 *
	 * Basado en el RenderTexture de flixel-animate.
	 * Créditos: ACrazyTown y MaybeMaru.
	 */
	public static function drawCameraScreen(bitmap:BitmapData, camera:FlxCamera, clearBitmap:Bool = true, drawFlashSprite:Bool = false):BitmapData
	{
		// Guard: GL surface not ready yet (Android early frames).
		final r = renderer;
		if (r == null) return bitmap;

		var matrix:FlxMatrix = new FlxMatrix();
		var pivotX:Float = FlxG.scaleMode.scale.x;
		var pivotY:Float = FlxG.scaleMode.scale.y;

		matrix.setTo(1 / pivotX, 0, 0, 1 / pivotY, camera.flashSprite.x / pivotX, camera.flashSprite.y / pivotY);

		if (clearBitmap) bitmap.__fillRect(bitmap.rect, 0, true);

		camera.render();
		camera.flashSprite.__update(false, true);

		r.__cleanup();
		r.setShader(r.__defaultShader);
		r.__allowSmoothing = false;
		r.__pixelRatio = Lib.current.stage.window.scale;
		r.__worldAlpha = 1 / camera.flashSprite.__worldAlpha;
		r.__worldTransform.copyFrom(camera.flashSprite.__renderTransform);
		r.__worldTransform.invert();
		r.__worldTransform.concat(matrix);
		r.__worldColorTransform.__copyFrom(camera.flashSprite.__worldColorTransform);
		r.__worldColorTransform.__invert();
		r.__setRenderTarget(bitmap);

		if (drawFlashSprite)
			bitmap.__drawGL(camera.flashSprite, r);
		else
			bitmap.__drawGL(camera.canvas, r);

		return bitmap;
	}

	/**
	 * Aplica un BitmapFilter a un bitmap.
	 */
	public static function applyFilter(bitmap:BitmapData, filter:BitmapFilter):BitmapData
	{
		return FilterRenderer.applyFilter(null, bitmap, [filter]);
	}

	/**
	 * Redimensiona un BitmapData.
	 */
	public static function resize(bitmap:BitmapData, width:Int, height:Int):Void
	{
		if (bitmap.width == width && bitmap.height == height) return;

		bitmap.width  = width;
		bitmap.height = height;

		if (!bitmap.readable)
			resizeTexture(bitmap.__texture, width, height);
	}

	/**
	 * Redimensiona una textura de hardware.
	 */
	public static function resizeTexture(texture:TextureBase, width:Int, height:Int):Void
	{
		if (texture.__width == width && texture.__height == height) return;

		var context:Context3D = texture.__context;
		texture.__width  = width;
		texture.__height = height;

		context.__bindGLTexture2D(texture.__textureID);
		context.gl.texImage2D(context.gl.TEXTURE_2D, 0, texture.__internalFormat, width, height, 0, texture.__format, context.gl.UNSIGNED_BYTE, null);

		@:nullSafety(Off)
		context.__bindGLTexture2D(null);
	}

	/**
	 * Copia source en destination, redimensionando si es necesario.
	 */
	public static function copy(source:BitmapData, destination:BitmapData):Void
	{
		resize(destination, source.width, source.height);
		destination.fillRect(destination.rect, 0);
		destination.draw(source);
	}
}
