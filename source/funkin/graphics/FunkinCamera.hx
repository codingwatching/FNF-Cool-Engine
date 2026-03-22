package funkin.graphics;

import animate.internal.RenderTexture;
import flash.geom.ColorTransform;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFrame;
import flixel.math.FlxMatrix;
import flixel.math.FlxRect;
import flixel.system.FlxAssets.FlxShader;
import funkin.graphics.framebuffer.FixedBitmapData;
import funkin.graphics.shaders.RuntimeCustomBlendShader;
import openfl.display.OpenGLRenderer;
import openfl.Lib;
import openfl.display.BitmapData;
import openfl.display.BlendMode;

using funkin.graphics.framebuffer.BitmapDataUtil;

/**
 * FlxCamera ampliada con soporte para blend modes avanzados mediante shaders.
 *
 * Blend modes soportados without extension KHR:
 *   DARKEN, HARDLIGHT, LIGHTEN (no-desktop), OVERLAY, DIFFERENCE,
 *   INVERT, COLORDODGE, COLORBURN, SOFTLIGHT, EXCLUSION,
 *   HUE, SATURATION, COLOR, LUMINOSITY
 *
 * For activar in all the game, adds in Main.hx (setupGame):
 *   untyped FlxG.cameras = new funkin.graphics.FunkinCameraFrontEnd();
 *
 * Portado de v-slice (FunkinCrew/Funkin).
 */
@:nullSafety
@:access(openfl.display.DisplayObject)
@:access(openfl.display.BitmapData)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D.textures.TextureBase)
@:access(flixel.graphics.FlxGraphic)
@:access(flixel.graphics.frames.FlxFrame)
@:access(openfl.display.OpenGLRenderer)
@:access(openfl.geom.ColorTransform)
class FunkinCamera extends FlxCamera
{
	/**
	 * If the dispositivo soporta the extension OpenGL KHR_blend_equation_advanced.
	 * If false, a shader-based implementation will be used for certain blend modes.
	 */
	public static var hasKhronosExtension(get, never):Bool;

	static inline function get_hasKhronosExtension():Bool
	{
		// This version of OpenFL no expone __complexBlendsSupported.
		// Always usamos the camino of shader for maximum compatibility.
		return false;
	}

	/**
	 * Blend modes that requieren the extension KHR or caen to shader if no is available.
	 * LIGHTEN se excluye en desktop porque lo soporta nativamente.
	 */
	// Blend modes disponibles in this version of OpenFL that necesitan shader.
	// COLORDODGE, COLORBURN, SOFTLIGHT, EXCLUSION, HUE, SATURATION, COLOR, LUMINOSITY
	// do not exist in this version of OpenFL — will be added if it updates.
	static final KHR_BLEND_MODES:Array<BlendMode> = [
		DARKEN, HARDLIGHT,
		#if !desktop LIGHTEN, #end
		OVERLAY, DIFFERENCE
	];

	/** Blend modes que siempre necesitan shader (sin soporte nativo en ninguna plataforma). */
	static final SHADER_REQUIRED_BLEND_MODES:Array<BlendMode> = [INVERT];

	/**
	 * Convierte un BlendMode nativo al entero que espera el shader GLSL.
	 * BlendMode in this version of OpenFL is a abstract over String,
	 * so that no is puede do cast directo to Int.
	 */
	public static function blendModeToInt(blend:BlendMode):Int
	{
		if (blend == null) return 0;
		return switch (blend)
		{
			case LIGHTEN:    4;
			case DARKEN:     5;
			case DIFFERENCE: 6;
			case INVERT:     9;
			case OVERLAY:    12;
			case HARDLIGHT:  13;
			// Modos futuros (requieren OpenFL con soporte extendido):
			// COLORDODGE=15, COLORBURN=16, SOFTLIGHT=17, EXCLUSION=18
			// HUE=19, SATURATION=20, COLOR=21, LUMINOSITY=22
			default: 0;
		};
	}

	/** ID of this camera, for debug. */
	public var id:String;

	/**
	 * If true, the blend shader will attempt to blend with cameras below this one.
	 * Useful for blend modes in strumlines that is mezclan with the fondo.
	 * Impacta el rendimiento — por defecto desactivado.
	 */
	public var crossCameraBlending:Bool;

	var _blendShader:RuntimeCustomBlendShader;
	var _backgroundFrame:FlxFrame;

	var _blendRenderTexture:RenderTexture;
	var _backgroundRenderTexture:RenderTexture;

	var _cameraTexture:FixedBitmapData;
	var _cameraMatrix:FlxMatrix;

	@:nullSafety(Off)
	public function new(id:String = 'unknown', x:Int = 0, y:Int = 0, width:Int = 0, height:Int = 0, zoom:Float = 0)
	{
		super(x, y, width, height, zoom);

		this.id = id;

		_backgroundFrame = new FlxFrame(new FlxGraphic('', null));
		_backgroundFrame.frame = new FlxRect();

		_blendShader = new RuntimeCustomBlendShader();

		// FIX: Flixel asigna the dimensiones reales of the camera after of
		// super(), pero en el constructor this.width/height pueden ser 0.
		// RenderTexture(0, 0) no tiene la guarda que tiene FixedBitmapData y
		// puede crashear en el driver OpenGL de Android. Usamos al menos 1×1.
		var safeW:Int = this.width  > 0 ? this.width  : 1;
		var safeH:Int = this.height > 0 ? this.height : 1;

		_backgroundRenderTexture = new RenderTexture(safeW, safeH);
		_blendRenderTexture      = new RenderTexture(safeW, safeH);

		_cameraMatrix  = new FlxMatrix();
		_cameraTexture = FixedBitmapData.create(safeW, safeH);

		crossCameraBlending = false;
	}

	override function drawPixels(?frame:FlxFrame, ?pixels:BitmapData, matrix:FlxMatrix, ?transform:ColorTransform, ?blend:BlendMode, ?smoothing:Bool = false,
		?shader:FlxShader):Void
	{
		var shouldUseShader:Bool = blend != null
			&& ((!hasKhronosExtension && KHR_BLEND_MODES.contains(blend))
				|| SHADER_REQUIRED_BLEND_MODES.contains(blend));

		if (shouldUseShader)
		{
			// Captura el fondo actual
			if (crossCameraBlending)
			{
				var camerasUnderneath:Array<FlxCamera> = FlxG.cameras.list.copy();
				for (i in camerasUnderneath.length - 1...-1)
				{
					if (i > FlxG.cameras.list.indexOf(this))
						camerasUnderneath.remove(camerasUnderneath[i]);
				}
				_cameraTexture.drawCameraScreens(camerasUnderneath);
				for (camera in camerasUnderneath)
				{
					camera.clearDrawStack();
					camera.canvas.graphics.clear();
				}
			}
			else
			{
				_cameraTexture.drawCameraScreen(this);
			}

			_backgroundFrame.frame.set(0, 0, this.width, this.height);

			this.clearDrawStack();
			this.canvas.graphics.clear();

			// Renderiza el sprite fuente en una textura temporal
			_blendRenderTexture.init(this.width, this.height);
			_blendRenderTexture.drawToCamera((camera, frameMatrix) ->
			{
				var pivotX:Float = width / 2;
				var pivotY:Float = height / 2;
				frameMatrix.copyFrom(matrix);
				frameMatrix.translate(-pivotX, -pivotY);
				frameMatrix.scale(this.scaleX, this.scaleY);
				frameMatrix.translate(pivotX, pivotY);
				camera.drawPixels(frame, pixels, frameMatrix, transform, null, smoothing, shader);
			});
			_blendRenderTexture.render();

			// Configura el shader de blend
			_blendShader.sourceSwag     = _blendRenderTexture.graphic.bitmap;
			_blendShader.backgroundSwag = _cameraTexture;
			_blendShader.blendSwag      = blendModeToInt(blend);
			if (_blendShader != null) _blendShader.updateViewInfo(width, height, this);

			_backgroundFrame.parent.bitmap = _blendRenderTexture.graphic.bitmap;

			// Aplica el blend al fondo
			_backgroundRenderTexture.init(
				Std.int(this.width  * Lib.current.stage.window.scale),
				Std.int(this.height * Lib.current.stage.window.scale)
			);
			_backgroundRenderTexture.drawToCamera((camera, mat) ->
			{
				camera.zoom = this.zoom;
				mat.scale(Lib.current.stage.window.scale, Lib.current.stage.window.scale);
				camera.drawPixels(_backgroundFrame, null, mat, canvas.transform.colorTransform, null, false, _blendShader);
			});
			_backgroundRenderTexture.render();

			// Draws the resultado final in the camera
			_cameraMatrix.identity();
			_cameraMatrix.scale(
				1 / (this.scaleX * Lib.current.stage.window.scale),
				1 / (this.scaleY * Lib.current.stage.window.scale)
			);
			_cameraMatrix.translate(
				((width  - width  / this.scaleX) * 0.5),
				((height - height / this.scaleY) * 0.5)
			);
			super.drawPixels(_backgroundRenderTexture.graphic.imageFrame.frame, null, _cameraMatrix, null, null, smoothing, null);
		}
		else
		{
			super.drawPixels(frame, pixels, matrix, transform, blend, smoothing, shader);
		}
	}

	override function destroy():Void
	{
		super.destroy();
		_blendRenderTexture.destroy();
		_backgroundRenderTexture.destroy();
		_cameraTexture.dispose();
	}
}
