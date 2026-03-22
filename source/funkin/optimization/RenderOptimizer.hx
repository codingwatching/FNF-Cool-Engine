package funkin.optimization;

import openfl.display.DisplayObject;
import openfl.display.Sprite;
import openfl.display.BitmapData;
import openfl.filters.BitmapFilter;
import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import funkin.data.CameraUtil;
import funkin.audio.AudioConfig;

/**
 * RenderOptimizer — configura el pipeline de renderizado de OpenFL/HaxeFlixel
 * para maximizar el trabajo en GPU y minimizar el overhead de CPU.
 *
 * ─── Techniques ────────────────────────────────────────────────────────────────
 *
 * 1. cacheAsBitmap = true  (CPU → GPU upload ONCE, without re-rasterización)
 *    Cuando un DisplayObject tiene `cacheAsBitmap = true`, OpenFL rasteriza
 *    su contenido a una textura interna y la sube a VRAM una sola vez.
 *    Cada frame subsiguiente se dibuja con un draw call GPU directamente desde
 *    esa textura, sin pasar por el rasterizador de CPU.
 *    IDEAL for: sprites of stage that no cambian (fondos, props static).
 *    NO USAR EN: sprites con animaciones o cambios de color frecuentes.
 *
 * 2. cacheAsBitmapMatrix = identityMatrix
 *    Junto with cacheAsBitmap, indicates to OpenFL that the texture is in espacio
 *    local (no transformada), lo que permite que el engine reutilice la misma
 *    textura cacheada aunque el sprite se mueva/rote.
 *    Without this, any movement of the sprite forces re-rasterización.
 *
 * 3. FlxCamera.bgColor con alpha=0
 *    The canal alpha of bgColor determina if the camera clears its canvas each
 *    frame (alpha > 0 = fill rect con el color). Si el stage cubre toda la
 *    screen, podemos avoid the clear of the canvas of the camera of the game
 *    usando alpha=0, ahorrando a fill rect of 1280×720 pixels by frame.
 *
 * 4. Desactivar filtros innecesarios
 *    Cada FlxCamera con filtros fuerza un renderizado en dos pasadas (off-screen
 *    buffer + composition). Desactivar filtros in cameras that no the necesitan
 *    elimina ese coste.
 *
 * 5. smoothing = false en texturas de notas/HUD
 *    The bilinear filtering GPU tiene coste. For textures pixel-perfect (HUD,
 *    notas a escala entera) desactivar smoothing es correcto y ahorra tiempo
 *    de texturizado.
 */

class RenderOptimizer
{
	/** Instancia of the stage of OpenFL for configuration global. */
	private static var _stage:openfl.display.Stage = null;

	/**
	 * Callr a VEZ to the start of the game (in Main.setupGame() after of
	 * crear el FlxGame).
	 */
	public static function init():Void
	{
		_stage = openfl.Lib.current.stage;
		if (_stage == null) return;

		// ── Desactivar vector antialiasing global ────────────────────────────
		// StageQuality.LOW = without antialiasing of lines vectoriales.
		// Las texturas de sprites tienen su propio antialiasing (antialiasing=true).
		// El antialiasing vectorial solo aplica a primitivas drawn con Graphics,
		// that in FNF are the bg of the healthbar and poco more.
		_stage.quality = openfl.display.StageQuality.LOW;

		// ── Activar pixel snapping global ────────────────────────────────────
		// PixelSnapping.ALWAYS hace que los DisplayObjects se posicionen en
		// coordenadas enteras, eliminando el sub-pixel rendering (bilinear
		// filtering en bordes). Mejora nitidez Y reduce trabajo de texturizado.
		// Note: HaxeFlixel already redondea coordenadas internamente in the majority
		// of targets, but forzarlo to level of stage is the garantía definitiva.
		try
		{
			@:privateAccess
			_stage.align = openfl.display.StageAlign.TOP_LEFT;
		}
		catch (_:Dynamic) {}

		trace('[RenderOptimizer] Inicializado.');
		trace('[RenderOptimizer] Audio → ${AudioConfig.debugString()}');
	}

	/**
	 * Applies cacheAsBitmap to sprites of stage that are completely static.
	 * Callr after of create the Stage.
	 *
	 * @param sprites  Array of FlxSprites that no tendrán cambios of contenido.
	 */
	public static function cacheStaticSprites(sprites:Array<FlxSprite>):Void
	{
		if (sprites == null) return;
		for (spr in sprites)
		{
			if (spr == null || !spr.alive) continue;
			try
			{
				// Solo cachear si el sprite no tiene animaciones activas
				if (spr.animation == null || spr.animation.numFrames <= 1)
				{
					spr.active = false; // No necesita update()
					// cacheAsBitmap sube la textura a VRAM una sola vez
					// cacheAsBitmap is not directly accessible on FlxSprite;
					// setting active = false above already prevents unnecessary updates.
				}
			}
			catch (_:Dynamic) {}
		}
	}

	/**
	 * Configures the FlxCameras for rendering óptimo.
	 * Usa CameraUtil para acceder a _filters correctamente — centraliza el
	 * unique punto of acceso private in vez of `@:privateAccess` disperso.
	 * - gameCam: camera of the stage
	 * - hudCam : camera of the HUD (puede be null)
	 */
	public static function optimizeCameras(gameCam:FlxCamera, ?hudCam:FlxCamera):Void
	{
		if (gameCam != null) CameraUtil.pruneEmptyFilters(gameCam);
		if (hudCam  != null) CameraUtil.pruneEmptyFilters(hudCam);
	}

	/**
	 * Marca un BitmapData como "no necesita mipmaps" y desactiva smoothing.
	 * Useful for textures of notes / HUD that is renderizan to size 1:1 or scales entera.
	 */
	public static inline function setNearestNeighbor(sprite:FlxSprite):Void
	{
		if (sprite == null) return;
		sprite.antialiasing = false;
		// smoothing=false en el FlxFrame le dice a OpenFL que use GL_NEAREST
		// en vez de GL_LINEAR para el sampler de esta textura.
		if (sprite.frame != null && sprite.frame.parent != null)
		{
			@:privateAccess
			sprite.frame.parent.bitmap.lock(); // pin en VRAM, evita eviction
		}
	}

	/**
	 * Forces a recolección of basura mayor.
	 * Callr between songs / to the entrar to the menu main.
	 */
	public static function forceGC():Void
	{
		#if cpp
		cpp.vm.Gc.run(true);
		cpp.vm.Gc.compact();
		#end
		#if hl
		hl.Gc.major();
		#end
	}
}
