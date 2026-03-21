package;

/**
 * CrashHandler — Cool Engine (v2)
 *
 * ── Por qué el handler anterior no mostraba nada ─────────────────────────────
 *
 *  PROBLEMA 1 — GC en estado corrupto:
 *    _onCriticalError() creaba StringBuf, llamaba Date.now(), accedía a FlxG…
 *    todo requiere el heap de Haxe sano. Con un NULL OBJECT REF en C++ el heap
 *    puede estar corrupto → el handler crasheaba de nuevo, sin mostrar nada.
 *
 *  PROBLEMA 2 — Deadlock en el render thread:
 *    FlxDrawQuadsItem::render corre en el render thread. window.alert() postea
 *    al event loop principal, que espera al render thread → deadlock.
 *    La ventana se congelaba y desaparecía sin mostrar nada.
 *
 *  PROBLEMA 3 — Sin fallback nativo:
 *    Si Lime fallaba, el catch solo hacía Sys.println() — invisible en release.
 *
 * ── Solución ─────────────────────────────────────────────────────────────────
 *
 *  Hook 1 → UncaughtErrorEvent  : errores Haxe/OpenFL normales
 *  Hook 2 → hxcpp critical hook : null ptr, stack overflow (CPP only)
 *
 *  Para Hook 2:
 *   - Timestamp via Sys.time() (Float, tipo valor, sin GC)
 *   - Log via sys.io.File (try/catch independiente)
 *   - Diálogo via proceso separado (PowerShell/osascript/zenity) → sin deadlock
 *   - Info del sistema pre-construida en init() cuando el runtime estaba sano
 *
 * ── Uso ──────────────────────────────────────────────────────────────────────
 *
 *  CrashHandler.init();   // UNA sola vez en Main, ANTES de createGame()
 */

import openfl.Lib;
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.CallStack.StackItem;
import haxe.io.Path;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if (desktop && DISCORD_ALLOWED)
import data.Discord.DiscordClient;
#end

using StringTools;

class CrashHandler
{
	// ── Configuración ──────────────────────────────────────────────────────────

	private static var   CRASH_DIR         : String = _resolveCrashDir();
	private static inline final LOG_PREFIX  : String = "CoolEngine_";
	private static inline final REPORT_URL  : String = "https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/issues";
	private static inline final ENGINE_VERSION : String = "0.6.0B";

	// ── Estado interno ────────────────────────────────────────────────────────

	private static var _handling    : Bool = false;
	private static var _initialized : Bool = false;

	/**
	 * Info del sistema pre-construida en init() cuando el runtime está sano.
	 * Se usa en _onCriticalError sin necesidad de crear ningún objeto Haxe.
	 */
	private static var _staticInfo : String = "";

	// =========================================================================
	//  API PÚBLICA
	// =========================================================================

	public static function init() : Void
	{
		if (_initialized) return;
		_initialized = true;

		_staticInfo = _buildStaticInfo();

		// Hook 1: errores Haxe/OpenFL (throw, etc.)
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(
			UncaughtErrorEvent.UNCAUGHT_ERROR,
			_onUncaughtError
		);

		// Hook 2: C++ null ptr, stack overflow, assert
		#if cpp
		untyped __global__.__hxcpp_set_critical_error_handler(_onCriticalError);
		#end

		trace('[CrashHandler] v2 listo. Crash dir → $CRASH_DIR');
	}

	/**
	 * Reporta un error manualmente (útil en try/catch para loguear y continuar).
	 */
	public static function report(error:Dynamic, ?context:String, fatal:Bool = false) : Void
	{
		var stack   = CallStack.exceptionStack(true);
		var message = _buildReport(Std.string(error), context, stack.length > 0 ? stack : CallStack.callStack());

		#if sys
		Sys.println(message);
		var path = _saveLog(message);
		if (path != null) Sys.println('[CrashHandler] Log → ${Path.normalize(path)}');
		#end

		if (fatal)
			_showAndExit(message);
		#if debug
		else
			_nativeDialog('[NON-FATAL]\n\n' + message, "Cool Engine — Error no fatal");
		#end
	}

	// =========================================================================
	//  HOOKS INTERNOS
	// =========================================================================

	private static function _onUncaughtError(e:UncaughtErrorEvent) : Void
	{
		if (_handling) return;
		_handling = true;

		var stack   = CallStack.exceptionStack(true);
		var message = _buildReport(Std.string(e.error), "UncaughtErrorEvent", stack);

		#if sys
		Sys.println(message);
		_saveLog(message);
		#end

		_showAndExit(message);
	}

	/**
	 * Llamado desde hxcpp cuando hay un error C++ crítico (null ptr, etc.).
	 *
	 * Reglas:
	 *  - Sys.time() para el timestamp (Float, tipo valor, sin GC)
	 *  - sys.io.File para escribir el log (try/catch independiente)
	 *  - Sys.command() para el diálogo (proceso separado → sin deadlock)
	 *  - _staticInfo ya está pre-construido, es un String existente
	 */
	#if cpp
	private static function _onCriticalError(cppMessage:String) : Void
	{
		if (_handling) return;
		_handling = true;

		// ── 1. Reporte ────────────────────────────────────────────────────────
		var report =
			"===========================================\n" +
			"       COOL ENGINE — CRASH REPORT\n" +
			"===========================================\n\n" +
			"Tipo     : C++ Critical Error\n" +
			"           (null object reference / stack overflow / assert)\n\n" +
			_staticInfo +
			"\n--- Mensaje de C++ ---\n" +
			cppMessage +
			"\n\n===========================================\n" +
			"Reporta este error en:\n" +
			REPORT_URL + "\n" +
			"===========================================\n";

		// ── 2. Guardar log ────────────────────────────────────────────────────
		// Sys.time() = epoch como Float, tipo valor → sin GC.
		var logPath : String = "";
		#if sys
		try
		{
			if (!FileSystem.exists(CRASH_DIR))
				FileSystem.createDirectory(CRASH_DIR);
			var ts = Std.string(Std.int(Sys.time()));
			logPath = CRASH_DIR + LOG_PREFIX + ts + ".txt";
			File.saveContent(logPath, report + "\n");
		}
		catch (_) {}
		#end

		// ── 3. Diálogo nativo ─────────────────────────────────────────────────
		var dialogMessage = _truncate(report, 2000);
		if (logPath != "") dialogMessage += '\n\nLog guardado en:\n$logPath';
		_nativeDialog(dialogMessage, "Cool Engine — Error Fatal");

		// ── 4. Abrir carpeta ──────────────────────────────────────────────────
		if (logPath != "") _openCrashFolder(CRASH_DIR);

		Sys.exit(1);
	}
	#end

	// =========================================================================
	//  DIÁLOGOS NATIVOS (proceso separado → sin deadlock)
	// =========================================================================

	/**
	 * Muestra un diálogo modal usando el SO, sin pasar por Lime/OpenFL.
	 * Cada plataforma lanza un proceso separado → no hay deadlock posible
	 * aunque el render thread esté bloqueado.
	 *
	 * Windows → PowerShell + Windows.Forms.MessageBox
	 * macOS   → osascript
	 * Linux   → zenity → kdialog → xmessage
	 * Fallback → lime.app.Application (si lo anterior falla)
	 * Último recurso → stderr
	 */
	private static function _nativeDialog(message:String, title:String) : Void
	{
		var shown = false;

		#if (sys && windows)
		if (!shown)
		{
			try
			{
				// Escapar comillas simples para PowerShell
				var msg   = message.replace("'", "`'");
				var ttl   = title.replace("'", "`'");
				var ps    = "Add-Type -AssemblyName System.Windows.Forms;" +
				            "[System.Windows.Forms.MessageBox]::Show('" + msg + "','" + ttl + "',0,16)|Out-Null";
				var ret   = Sys.command("powershell", ["-NonInteractive", "-Command", ps]);
				if (ret != 9009) shown = true; // 9009 = powershell.exe not found
			}
			catch (_) {}
		}
		#end

		#if (sys && mac)
		if (!shown)
		{
			try
			{
				var escaped      = message.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
				var escapedTitle = title.replace("\"", "\\\"");
				Sys.command("osascript", ["-e", 'display alert "$escapedTitle" message "$escaped" as critical']);
				shown = true;
			}
			catch (_) {}
		}
		#end

		#if (sys && linux)
		if (!shown)
		{
			try
			{
				var ret = Sys.command("zenity", ["--error", '--title=$title', '--text=$message', "--width=600"]);
				if (ret != 127) shown = true;
			}
			catch (_) {}
		}
		if (!shown)
		{
			try
			{
				var ret = Sys.command("kdialog", ["--error", message, "--title", title]);
				if (ret != 127) shown = true;
			}
			catch (_) {}
		}
		if (!shown)
		{
			try
			{
				var ret = Sys.command("xmessage", ["-center", message]);
				if (ret != 127) shown = true;
			}
			catch (_) {}
		}
		#end

		// Fallback: intentar con Lime si el runtime lo permite
		if (!shown)
		{
			try
			{
				lime.app.Application.current.window.alert(_truncate(message, 3000), title);
				shown = true;
			}
			catch (_) {}
		}

		// Último recurso: stderr
		if (!shown)
		{
			try { Sys.stderr().writeString("=== FATAL CRASH ===\n" + message + "\n"); } catch (_) {}
		}
	}

	// =========================================================================
	//  CONSTRUCCIÓN DEL REPORTE
	// =========================================================================

	private static function _buildReport(error:String, ?context:String, stack:Array<StackItem>) : String
	{
		var sb = new StringBuf();
		_header(sb);

		if (context != null && context.length > 0)
			sb.add('Contexto : $context\n\n');

		sb.add('Error    : $error\n\n');
		_appendStack(sb, stack);
		_footer(sb);
		return sb.toString();
	}

	/** Pre-construye la info del sistema en init(), cuando el runtime está sano. */
	private static function _buildStaticInfo() : String
	{
		var sb = new StringBuf();

		sb.add('Versión  : $ENGINE_VERSION\n');
		sb.add('Fecha    : ${Date.now().toString()}\n');
		sb.add('Sistema  : ${_systemName()}\n');

		#if sys
		sb.add('Memoria  : ${_memMB()} MB usados\n');
		#end

		try
		{
			var app = lime.app.Application.current;
			if (app != null && app.window != null)
				sb.add('Ventana  : ${app.window.width}x${app.window.height}\n');
		}
		catch (_) {}

		sb.add('\n--- Estado Flixel ---\n');
		try
		{
			if (flixel.FlxG.game != null && flixel.FlxG.state != null)
			{
				var cls = Type.getClass(flixel.FlxG.state);
				sb.add('State    : ${cls != null ? Type.getClassName(cls) : "???"}\n');
				sb.add('FPS      : ${Math.round(openfl.Lib.current.stage.frameRate)}\n');
			}
			else sb.add('State    : (FlxG no disponible)\n');
		}
		catch (_) { sb.add('State    : (error al leer)\n'); }

		return sb.toString();
	}

	private static function _header(sb:StringBuf) : Void
	{
		sb.add("===========================================\n");
		sb.add("       COOL ENGINE — CRASH REPORT\n");
		sb.add("===========================================\n\n");
		sb.add(_staticInfo);
		sb.add("\n===========================================\n\n");
	}

	private static function _footer(sb:StringBuf) : Void
	{
		sb.add('\n===========================================\n');
		sb.add('Reporta este error en:\n');
		sb.add('$REPORT_URL\n');
		sb.add('===========================================\n');
	}

	private static function _appendStack(sb:StringBuf, stack:Array<StackItem>) : Void
	{
		if (stack == null || stack.length == 0)
		{
			sb.add("--- Call Stack no disponible ---\n");
			return;
		}

		sb.add("--- Call Stack ---\n");
		for (item in stack)
		{
			switch (item)
			{
				case FilePos(s, file, line, column):
					var col    = (column != null) ? ':$column' : '';
					var method = (s != null) ? switch (s) {
						case Method(cls, m): ' [$cls.$m()]';
						default: '';
					} : '';
					sb.add('  $file:$line$col$method\n');
				case CFunction:
					sb.add("  [C Function]\n");
				case Module(m):
					sb.add('  [Module: $m]\n');
				case Method(cls, method):
					sb.add('  $cls.$method()\n');
				case LocalFunction(v):
					sb.add('  [LocalFunction #$v]\n');
				default:
					sb.add('  ${Std.string(item)}\n');
			}
		}
	}

	// =========================================================================
	//  HELPERS
	// =========================================================================

	private static function _resolveCrashDir() : String
	{
		#if mobileC
		try
		{
			var base = lime.system.System.documentsDirectory;
			if (base == null || base == "") base = "./";
			if (!base.endsWith("/")) base += "/";
			return base + "CoolEngine/crash/";
		}
		catch (_:Dynamic) { return "./crash/"; }
		#else
		return "./crash/";
		#end
	}

	private static function _saveLog(content:String) : Null<String>
	{
		#if sys
		try
		{
			if (!FileSystem.exists(CRASH_DIR))
				FileSystem.createDirectory(CRASH_DIR);
			var ts   = Date.now().toString().replace(" ", "_").replace(":", "-");
			var path = CRASH_DIR + LOG_PREFIX + ts + ".txt";
			File.saveContent(path, content + "\n");
			return path;
		}
		catch (e:Dynamic)
		{
			try { Sys.println("[CrashHandler] No se pudo guardar el log: " + e); } catch (_) {}
		}
		#end
		return null;
	}

	private static function _showAndExit(message:String) : Void
	{
		#if (desktop && DISCORD_ALLOWED)
		try { DiscordClient.shutdown(); } catch (_) {}
		#end

		var logPath   = _saveLog(message);
		var dialogMsg = _truncate(message, 2800);
		if (logPath != null)
			dialogMsg += '\n\n─────────────────────\nLog guardado en:\n${Path.normalize(logPath)}';

		_nativeDialog(dialogMsg, "Cool Engine — Error Fatal");

		if (logPath != null) _openCrashFolder(CRASH_DIR);

		#if sys
		Sys.exit(1);
		#end
	}

	private static function _openCrashFolder(dir:String) : Void
	{
		try
		{
			#if windows
			Sys.command("explorer", [Path.normalize(dir).replace("/", "\\")]);
			#elseif mac
			Sys.command("open", [dir]);
			#elseif linux
			Sys.command("xdg-open", [dir]);
			#end
		}
		catch (_) {}
	}

	private static function _truncate(s:String, max:Int) : String
	{
		if (s.length <= max) return s;
		return s.substr(0, max) + "\n\n[... truncado. Ver archivo de log completo]";
	}

	private static function _systemName() : String
	{
		#if sys return Sys.systemName();
		#elseif windows return "Windows";
		#elseif linux return "Linux";
		#elseif mac return "macOS";
		#else return "Unknown"; #end
	}

	#if sys
	private static function _memMB() : String
	{
		try
		{
			#if cpp
			var bytes = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
			return Std.string(Math.round(bytes / 1024 / 1024));
			#else
			return Std.string(Math.round(openfl.system.System.totalMemory / 1024 / 1024));
			#end
		}
		catch (_) { return "??"; }
	}
	#end
}
