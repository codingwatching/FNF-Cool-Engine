package extensions;

import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxRect;
import flixel.math.FlxPoint;

class FlxAtlasFramesExt
{
	/**
	 * Recreation of the old FlxAtlasFrames.fromGraphic
	 * BUGFIX: guarda contra graphic==null para evitar NPE en NoteSkinSystem.loadAtlas
	 */
	public static function fromGraphic(graphic:FlxGraphic, frameWidth:Int, frameHeight:Int, ?name:String):FlxAtlasFrames
	{
		if (graphic == null)
		{
			trace('[FlxAtlasFramesExt] fromGraphic: graphic es null — se devuelve null');
			return null;
		}

		if (name == null)
			name = graphic.key;

		var frames = new FlxAtlasFrames(graphic);

		var cols = Std.int(graphic.width / frameWidth);
		var rows = Std.int(graphic.height / frameHeight);

		// Protection against invalid dimensions (frame larger than the bitmap)
		if (cols <= 0) cols = 1;
		if (rows <= 0) rows = 1;

		var index = 0;

		for (y in 0...rows)
		{
			for (x in 0...cols)
			{
				var rect = FlxRect.get(x * frameWidth, y * frameHeight, frameWidth, frameHeight);

				var frame = frames.addAtlasFrame(rect, FlxPoint.get(frameWidth, frameHeight), FlxPoint.get(0, 0), name + "_" + index);
				index++;
			}
		}

		return frames;
	}

	/**
	 * Merges multiple FlxAtlasFrames in uno only.
	 *
	 * Cada atlas puede referenciar su propio FlxGraphic (PNG independiente), ya que
	 * each FlxFrame saves its own `parent` (the source texture). Flixel will use
	 * el parent correcto al dibujar cada frame, independientemente del parent nominal
	 * del atlas resultante.
	 *
	 * Typical usage: characters with various sprite sheets (avoid limit 4096×4096).
	 *
	 *   var merged = FlxAtlasFramesExt.mergeAtlases([sheet0, sheet1, sheet2]);
	 *   sprite.frames = merged;
	 */
	public static function mergeAtlases(atlases:Array<FlxAtlasFrames>):Null<FlxAtlasFrames>
	{
		if (atlases == null || atlases.length == 0) return null;
		if (atlases.length == 1) return atlases[0];

		// Usar the primer atlas valid as base (parent nominal of the resultado)
		var baseAtlas:FlxAtlasFrames = null;
		for (a in atlases)
			if (a != null) { baseAtlas = a; break; }
		if (baseAtlas == null) return null;

		// Crear nuevo atlas con el parent de la primera hoja
		var merged = new FlxAtlasFrames(baseAtlas.parent);

		// Agregar frames de todas las hojas
		for (atlas in atlases)
		{
			if (atlas == null) continue;
			for (frame in atlas.frames)
			{
				if (frame == null) continue;
				// Evitar duplicados de nombre
				if (frame.name != null && merged.framesHash.exists(frame.name))
					continue;
				merged.frames.push(frame);
				if (frame.name != null)
					merged.framesHash.set(frame.name, frame);
			}
		}

		return merged;
	}
}
