package extensions;

import extensions.InitAPI;
import openfl.Lib;
import flixel.FlxG;
import flixel.system.scaleModes.StageSizeScaleMode;
import flixel.system.scaleModes.BaseScaleMode;

/**
 * CppAPI — fachada de alto nivel sobre InitAPI y otras funciones nativas.
 *
 * Agrupa the calldas nativas with a API more clears and platform-safe.
 * Adds: dark mode, DPI awareness, and helpers of window.
 */
class CppAPI
{
	// ── Colores de ventana ────────────────────────────────────────────────────

	/**
	 * Cambia el color del borde de la ventana (DWM).
	 * No-op en macOS/Linux.
	 */
	public static inline function changeColor(r:Int, g:Int, b:Int):Void
		InitAPI.setWindowBorderColor(r, g, b);

	/**
	 * Changes the color of the title of the window.
	 * No-op en macOS/Linux.
	 */
	public static inline function changeCaptionColor(r:Int, g:Int, b:Int):Void
		InitAPI.setWindowCaptionColor(r, g, b);

	// ── Modo oscuro ───────────────────────────────────────────────────────────

	/**
	 * Activa el frame oscuro inmersivo del sistema.
	 * Disponible en Windows 10 1809+ y Windows 11.
	 */
	public static inline function enableDarkMode():Void
		InitAPI.setDarkMode(true);

	/** Desactiva el frame oscuro (vuelve al tema claro). */
	public static inline function disableDarkMode():Void
		InitAPI.setDarkMode(false);

	// ── DPI ───────────────────────────────────────────────────────────────────

	/**
	 * Registra el proceso como DPI-aware.
	 * Llamar ANTES de que se cree la ventana, idealmente en el static __init__.
	 * Ver InitAPI.setDPIAware() para detalles.
	 */
	public static inline function registerDPIAware():Void
		InitAPI.setDPIAware();

	// ── Helpers de ventana ────────────────────────────────────────────────────

	/** Returns the title current of the window of lima. */
	public static var windowTitle(get, never):String;
	static inline function get_windowTitle():String
	{
		#if !html5
		return lime.app.Application.current?.window?.title ?? "";
		#else
		return "";
		#end
	}

	/** Changes the title of the window in runtime. */
	public static function setWindowTitle(title:String):Void
	{
		#if !html5
		if (lime.app.Application.current?.window != null)
			lime.app.Application.current.window.title = title;
		#end
	}

	// ── Opacidad de ventana ────────────────────────────────────────────────────

	/**
	 * Cambia la opacidad de la ventana del OS.
	 *
	 * En Windows usa SetLayeredWindowAttributes (User32.dll).
	 * The window debe have the estilo WS_EX_LAYERED; lime it adds automatically
	 * if is call before of create the window, or is puede add in runtime with
	 * SetWindowLongPtr — InitAPI debe implementar setLayeredWindowAttributes.
	 *
	 * En otras plataformas, se usa el alpha del contenedor de OpenFL como fallback.
	 *
	 * @param alpha  0.0 = completamente transparente, 1.0 = opaco.
	 */
	public static function setWindowOpacity(alpha:Float):Void
	{
		alpha = Math.max(0.0, Math.min(1.0, alpha));
		#if !html5
		if (flixel.FlxG.game != null)
			flixel.FlxG.game.alpha = alpha;
		#end
	}
}
