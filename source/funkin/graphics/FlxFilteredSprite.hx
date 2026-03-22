package funkin.graphics;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFrame;
import flixel.math.FlxMatrix;
import flixel.math.FlxRect;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.filters.BitmapFilter;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
#if (js && html5)
import openfl.display.CanvasRenderer;
import openfl.display._internal.CanvasGraphics as GfxRenderer;
#else
import openfl.display.CairoRenderer;
import openfl.display._internal.CairoGraphics as GfxRenderer;
#end

/**
 * FlxSprite con soporte para filtros OpenFL (BitmapFilter / ShaderFilter).
 *
 * Uso:
 *   var sprite = new FlxFilteredSprite();
 *   sprite.filters = [new ShaderFilter(miShader)];
 *
 * Portado de v-slice (FunkinCrew/Funkin).
 */
@:nullSafety
@:access(openfl.geom.Rectangle)
@:access(openfl.filters.BitmapFilter)
@:access(flixel.graphics.frames.FlxFrame)
class FlxFilteredSprite extends FlxSprite
{
	@:noCompletion var _renderer:Dynamic = null; // FlxAnimateFilterRenderer en v-slice

	@:noCompletion var _filterMatrix:FlxMatrix = new FlxMatrix();

	/**
	 * Lista de filtros a aplicar al sprite.
	 * Puedes usar ShaderFilter, GlowFilter, BlurFilter, etc.
	 */
	public var filters(default, set):Null<Array<BitmapFilter>>;

	/**
	 * Fuerza re-render con filtros en cada frame.
	 * Enable it if your shader uses time or other uniforms that change.
	 */
	public var filterDirty:Bool = false;

	@:noCompletion var filtered:Bool = false;

	@:nullSafety(Off)
	@:noCompletion var _blankFrame:FlxFrame;

	@:nullSafety(Off)
	var _filterBmp1:BitmapData;
	@:nullSafety(Off)
	var _filterBmp2:BitmapData;

	override public function update(elapsed:Float)
	{
		super.update(elapsed);
		if (!filterDirty && filters != null)
		{
			for (filter in filters)
			{
				if (filter.__renderDirty)
				{
					filterDirty = true;
					break;
				}
			}
		}
	}

	override function draw():Void
	{
		if (filters == null || filters.length == 0)
		{
			filtered = false;
			super.draw();
			return;
		}

		if (!filtered || filterDirty)
		{
			applyFilters();
			filterDirty = false;
			filtered = true;
		}

		// Dibuja el resultado filtrado
		if (_blankFrame != null)
		{
			for (camera in cameras)
			{
				if (!camera.visible || !camera.exists) continue;
				drawFrameForCamera(camera, _blankFrame);
			}
		}
	}

	function applyFilters():Void
	{
		if (frames == null) return;

		var frame:FlxFrame = frames.frames[animation.frameIndex];
		if (frame == null) return;

		var w:Int = Std.int(frame.sourceSize.x);
		var h:Int = Std.int(frame.sourceSize.y);

		if (w <= 0 || h <= 0) return;

		if (_filterBmp1 == null || _filterBmp1.width != w || _filterBmp1.height != h)
		{
			if (_filterBmp1 != null) _filterBmp1.dispose();
			if (_filterBmp2 != null) _filterBmp2.dispose();
			_filterBmp1 = new BitmapData(w, h, true, 0);
			_filterBmp2 = new BitmapData(w, h, true, 0);
		}
		else
		{
			_filterBmp1.fillRect(_filterBmp1.rect, 0);
		}

		// Dibuja el frame en el bitmap
		var mat:Matrix = new Matrix();
		mat.translate(frame.offset.x, frame.offset.y);
		_filterBmp1.draw(frame.parent.bitmap, mat, null, null, new Rectangle(0, 0, w, h));

		// Aplica los filtros
		var src:BitmapData = _filterBmp1;
		var dst:BitmapData = _filterBmp2;

		for (filter in filters)
		{
			dst.fillRect(dst.rect, 0);
			dst.applyFilter(src, src.rect, new openfl.geom.Point(), filter);
			var tmp = src;
			src = dst;
			dst = tmp;
		}

		// Guarda como frame especial
		if (_blankFrame == null)
		{
			var graphic = FlxGraphic.fromBitmapData(src, false, null, false);
			_blankFrame = graphic.imageFrame.frame;
		}
		else
		{
			_blankFrame.parent.bitmap = src;
		}
	}

	function drawFrameForCamera(camera:FlxCamera, frame:FlxFrame):Void
	{
		var mat:FlxMatrix = new FlxMatrix();
		mat.translate(-origin.x, -origin.y);
		mat.scale(scale.x, scale.y);
		if (angle != 0) mat.rotateWithTrig(_cosAngle, _sinAngle);
		mat.translate(x + origin.x - camera.scroll.x * scrollFactor.x,
		              y + origin.y - camera.scroll.y * scrollFactor.y);

		camera.drawPixels(frame, null, mat, colorTransform, blend);
	}

	function set_filters(value:Null<Array<BitmapFilter>>):Null<Array<BitmapFilter>>
	{
		filterDirty = true;
		filtered    = false;
		return filters = value;
	}

	override function destroy():Void
	{
		super.destroy();
		if (_filterBmp1 != null) { _filterBmp1.dispose(); _filterBmp1 = null; }
		if (_filterBmp2 != null) { _filterBmp2.dispose(); _filterBmp2 = null; }
	}
}
