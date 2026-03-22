package funkin.data;

import flixel.FlxG;

/**
 * EngineSettings — Centralized engine configuration.
 *
 * ─── Bugs que resuelve ───────────────────────────────────────────────────────
 *
 *  FPS NO CAMBIA
 *    El campo de guardado era 'FPSCap' (obsoleto). El engine ya usa 'fpsTarget',
 *    but the options screen kept writing to the old field, por lo que
 *    el cambio nunca se aplicaba al reinicar. Esta clase migra el campo
 *    automatically and guarantees that the cambio is applies to AMBOS framerates
 *    de Flixel (drawFramerate + updateFramerate).
 *
 *  WINDOW SHRINKS ON STARTUP
 *    En Windows con DPI > 100 %, Lime a veces reduce la ventana porque
 *    interpreta the size lógico according to the DPI of the system. The callda to
 *    SetProcessDPIAware() en InitAPI debe suceder ANTES de que se cree la
 *    window (it manages Main). This class forces the size correct after
 *    de que la ventana existe, actuando como second line of defense.
 *
 *  DEFAULT RESOLUTION
 *    The default resolution becomes 1920×1080. The option of resolution
 *    personalizada queda eliminada of the menu of options; the game always
 *    ocupa 1080p (or ajusta to the monitor if is more small).
 *
 * @author  Cool Engine Team
 * @since   0.6.0
 */
class EngineSettings
{
	// ── FPS ──────────────────────────────────────────────────────────────────

	/** FPS por defecto en desktop. */
	public static inline var DEFAULT_FPS:Int = 60;

	/** Minimum accepted FPS. */
	public static inline var MIN_FPS:Int = 30;

	/** Maximum accepted FPS. 0 = no limit. */
	public static inline var MAX_FPS:Int = 2000;

	// ── Resolution ───────────────────────────────────────────────────────────

	/** Ancho por defecto (1080p). */
	public static inline var DEFAULT_WIDTH:Int = 1920;

	/** Alto por defecto (1080p). */
	public static inline var DEFAULT_HEIGHT:Int = 1080;

	// ─────────────────────────────────────────────────────────────────────────
	// FPS
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Aplica el FPS guardado al engine.
	 *
	 * Migration logic:
	 *   • Si 'FPSCap' existe y 'fpsTarget' es null → migrar y guardar.
	 *   • Si 'fpsTarget' existe → usar ese valor directamente.
	 *   • Si ninguno existe → usar DEFAULT_FPS.
	 *
	 * Llama esto en CacheState.goToTitle() y en el inicio de Main.
	 */
	public static function applyFPS():Void
	{
		var fps:Int = DEFAULT_FPS;

		// ── Automatic migration of obsolete field ──────────────────────────
		if (FlxG.save.data.FPSCap != null && FlxG.save.data.fpsTarget == null)
		{
			trace('[EngineSettings] Migrando FPSCap → fpsTarget (valor: ${FlxG.save.data.FPSCap})');
			FlxG.save.data.fpsTarget = FlxG.save.data.FPSCap;
			FlxG.save.data.FPSCap = null;
			FlxG.save.flush();
		}

		if (FlxG.save.data.fpsTarget != null)
			fps = Std.int(FlxG.save.data.fpsTarget);

		// Force rango valid
		fps = clampFPS(fps);

		_applyFPSRaw(fps);
	}

	/**
	 * Cambia el FPS del engine, lo persiste y lo aplica de forma inmediata.
	 *
	 * Usar desde la pantalla de opciones en lugar de escribir directamente en
	 * FlxG.save.data.
	 *
	 * @param fps  Value deseado. Is clampea automatically to [MIN_FPS, MAX_FPS].
	 */
	public static function setFPS(fps:Int):Void
	{
		fps = clampFPS(fps);

		FlxG.save.data.fpsTarget = fps;
		// Limpiar el campo obsoleto para no confundir futuras migraciones
		FlxG.save.data.FPSCap = null;
		FlxG.save.flush();

		_applyFPSRaw(fps);
	}

	/**
	 * Devuelve el FPS guardado actualmente (sin aplicarlo).
	 * Si no hay valor guardado, devuelve DEFAULT_FPS.
	 */
	public static function getFPS():Int
	{
		if (FlxG.save.data.fpsTarget != null)
			return clampFPS(Std.int(FlxG.save.data.fpsTarget));
		if (FlxG.save.data.FPSCap != null)
			return clampFPS(Std.int(FlxG.save.data.FPSCap));
		return DEFAULT_FPS;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Ventana
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Guarantees that the window tenga the size correct (1080p).
	 *
	 * Se call desde CacheState.goToTitle() como second line of defense
	 * contra el encogimiento de ventana por DPI scaling en Windows.
	 *
	 * If the monitor is more small that 1920×1080 is respeta the size of the monitor.
	 */
	/**
	 * Centra la ventana en la pantalla sin redimensionarla.
	 *
	 * IMPORTANTE — no do resize here:
	 *   Redimensionar to resolution of screen complete (1920×1080) in Windows
	 *   active the modo pseudo-fullscreen automatically, incluso with -2px of margen.
	 *   The size of window it fija Project.xml (<window width="1280" height="720"/>).
	 *   The game always renders in 1080p internamente via the camera of Flixel,
	 *   independientemente of the size of the window of the SO.
	 */
	public static function ensureWindowSize():Void
	{
		#if (!html5 && lime)
		final win = lime.app.Application.current?.window;
		if (win == null)
			return;

		// Solo centrar, nunca redimensionar
		final disp = win.display;
		if (disp != null)
		{
			final sw = Std.int(disp.bounds.width);
			final sh = Std.int(disp.bounds.height);
			if (sw > 0 && sh > 0)
				win.move(Std.int((sw - win.width) / 2), Std.int((sh - win.height) / 2));
		}
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Internals
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Aplica el valor de FPS a los dos framerates de Flixel SIN persistir nada.
	 * updateFramerate siempre >= drawFramerate para evitar freeze visual.
	 */
	static function _applyFPSRaw(fps:Int):Void
	{
		if (fps <= 0)
		{
			openfl.Lib.current.stage.frameRate = 1000;
			FlxG.updateFramerate = 1000;
			FlxG.drawFramerate = 1000;
			trace('[EngineSettings] FPS aplicado: Unlimited (cap=1000)');
		}
		else
		{
			openfl.Lib.current.stage.frameRate = fps;
			FlxG.updateFramerate = fps;
			FlxG.drawFramerate = fps;
			trace('[EngineSettings] FPS aplicado: $fps');
		}
	}

	/** Clampea a value of FPS to the rango valid. 0 = no limit, is allows pasar. */
	static inline function clampFPS(fps:Int):Int
	{
		if (fps == 0)
			return 0; // 0 = Unlimited, permitido
		if (fps < MIN_FPS)
			return MIN_FPS;
		if (fps > MAX_FPS)
			return MAX_FPS;
		return fps;
	}
}
