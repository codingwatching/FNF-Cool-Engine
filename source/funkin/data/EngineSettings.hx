package funkin.data;

import flixel.FlxG;

/**
 * EngineSettings — Configuración centralizada del engine.
 *
 * ─── Bugs que resuelve ───────────────────────────────────────────────────────
 *
 *  FPS NO CAMBIA
 *    El campo de guardado era 'FPSCap' (obsoleto). El engine ya usa 'fpsTarget',
 *    pero la pantalla de opciones seguía escribiendo en el campo viejo, por lo que
 *    el cambio nunca se aplicaba al reinicar. Esta clase migra el campo
 *    automáticamente y garantiza que el cambio se aplica a AMBOS framerates
 *    de Flixel (drawFramerate + updateFramerate).
 *
 *  VENTANA SE HACE PEQUEÑA AL INICIAR
 *    En Windows con DPI > 100 %, Lime a veces reduce la ventana porque
 *    interpreta el tamaño lógico según el DPI del sistema. La llamada a
 *    SetProcessDPIAware() en InitAPI debe suceder ANTES de que se cree la
 *    ventana (lo gestiona Main). Esta clase fuerza el tamaño correcto DESPUÉS
 *    de que la ventana existe, actuando como segunda línea de defensa.
 *
 *  RESOLUCIÓN POR DEFECTO
 *    La resolución por defecto pasa a ser 1920×1080. La opción de resolución
 *    personalizada queda eliminada del menú de opciones; el juego siempre
 *    ocupa 1080p (o ajusta al monitor si es más pequeño).
 *
 * @author  Cool Engine Team
 * @since   0.6.0
 */
class EngineSettings
{
	// ── FPS ──────────────────────────────────────────────────────────────────

	/** FPS por defecto en desktop. */
	public static inline var DEFAULT_FPS:Int = 60;

	/** FPS mínimo aceptado. */
	public static inline var MIN_FPS:Int = 30;

	/** FPS máximo aceptado. 0 = sin límite. */
	public static inline var MAX_FPS:Int = 2000;

	/** Opciones de FPS en el menú (la opción "resolución" se elimina). */
	public static var FPS_OPTIONS:Array<Int> = [30, 60, 75, 120, 144, 165, 240];

	// ── Resolución ───────────────────────────────────────────────────────────

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
	 * Lógica de migración:
	 *   • Si 'FPSCap' existe y 'fpsTarget' es null → migrar y guardar.
	 *   • Si 'fpsTarget' existe → usar ese valor directamente.
	 *   • Si ninguno existe → usar DEFAULT_FPS.
	 *
	 * Llama esto en CacheState.goToTitle() y en el inicio de Main.
	 */
	public static function applyFPS():Void
	{
		var fps:Int = DEFAULT_FPS;

		// ── Migración automática del campo obsoleto ──────────────────────────
		if (FlxG.save.data.FPSCap != null && FlxG.save.data.fpsTarget == null)
		{
			trace('[EngineSettings] Migrando FPSCap → fpsTarget (valor: ${FlxG.save.data.FPSCap})');
			FlxG.save.data.fpsTarget = FlxG.save.data.FPSCap;
			FlxG.save.data.FPSCap = null;
			FlxG.save.flush();
		}

		if (FlxG.save.data.fpsTarget != null)
			fps = Std.int(FlxG.save.data.fpsTarget);

		// Forzar rango válido
		fps = clampFPS(fps);

		_applyFPSRaw(fps);
	}

	/**
	 * Cambia el FPS del engine, lo persiste y lo aplica de forma inmediata.
	 *
	 * Usar desde la pantalla de opciones en lugar de escribir directamente en
	 * FlxG.save.data.
	 *
	 * @param fps  Valor deseado. Se clampea automáticamente a [MIN_FPS, MAX_FPS].
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
	 * Garantiza que la ventana tenga el tamaño correcto (1080p).
	 *
	 * Se llama desde CacheState.goToTitle() como segunda línea de defensa
	 * contra el encogimiento de ventana por DPI scaling en Windows.
	 *
	 * Si el monitor es más pequeño que 1920×1080 se respeta el tamaño del monitor.
	 */
	/**
	 * Centra la ventana en la pantalla sin redimensionarla.
	 *
	 * IMPORTANTE — NO hacer resize aquí:
	 *   Redimensionar a resolución de pantalla completa (1920×1080) en Windows
	 *   activa el modo pseudo-fullscreen automáticamente, incluso con -2px de margen.
	 *   El tamaño de ventana lo fija Project.xml (<window width="1280" height="720"/>).
	 *   El juego siempre renderiza en 1080p internamente vía la cámara de Flixel,
	 *   independientemente del tamaño de la ventana del SO.
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

	/** Clampea un valor de FPS al rango válido. 0 = sin límite, se permite pasar. */
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
