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

		// Hook 1: errores Haxe/OpenFL (throw, null object reference, etc.)
		//
		// PRIORIDAD ALTA (1000): OpenFL puede registrar su propio handler de
		// UncaughtErrorEvent con prioridad 0 durante el bootstrap (si
		// openfl_enable_handle_error estuviese activo). Sin prioridad alta,
		// el handler de OpenFL dispara primero y puede silenciar el evento
		// con stopImmediatePropagation() antes de que CrashHandler lo vea.
		// Con priority=1000 garantizamos que CrashHandler siempre va primero.
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(
			UncaughtErrorEvent.UNCAUGHT_ERROR,
			_onUncaughtError,
			false,  // useCapture
			1000    // priority — mayor que el default 0 de OpenFL
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
		// Envolver todo el cuerpo — cualquier cosa puede fallar si el caller
		// nos pasa un objeto roto o el runtime está en estado parcial.
		var message : String = "";
		try
		{
			var stack = [];
			try { stack = CallStack.exceptionStack(true); } catch (_se:Dynamic) {}
			if (stack.length == 0)
				try { stack = CallStack.callStack(); } catch (_cs:Dynamic) {}

			var errorStr : String = "";
			try { errorStr = Std.string(error); } catch (_e:Dynamic) { errorStr = "(error no serializable)"; }

			var ctx : Null<String> = null;
			try { ctx = context; } catch (_) {}

			message = _buildReport(errorStr, ctx, stack);
		}
		catch (_reportErr:Dynamic)
		{
			try { message = "COOL ENGINE — ERROR\n" + Std.string(error); } catch (_) { message = "COOL ENGINE — ERROR"; }
		}

		#if sys
		try { Sys.println(message); } catch (_) {}
		try
		{
			var path = _saveLog(message);
			if (path != null) Sys.println('[CrashHandler] Log → ${haxe.io.Path.normalize(path)}');
		}
		catch (_) {}
		#end

		if (fatal)
		{
			try { _showAndExit(message); } catch (_)
			{
				try { _nativeDialog(_truncate(message, 2000), "Cool Engine — Error Fatal"); } catch (_) {}
				#if sys try { Sys.exit(1); } catch (_) {} #end
			}
		}
		#if debug
		else
		{
			try { _nativeDialog('[NON-FATAL]\n\n' + message, "Cool Engine — Error no fatal"); } catch (_) {}
		}
		#end
	}

	// =========================================================================
	//  HOOKS INTERNOS
	// =========================================================================

	private static function _onUncaughtError(e:UncaughtErrorEvent) : Void
	{
		if (_handling) return;
		_handling = true;

		// ── Construir el reporte de forma defensiva ───────────────────────────
		// CallStack.exceptionStack() puede lanzar si el runtime está dañado.
		// _buildReport() crea StringBuf (GC); envolvemos cada paso por separado.
		var message : String = "COOL ENGINE — UNCAUGHT ERROR\n(error al construir reporte)";
		try
		{
			var stack = [];
			try { stack = CallStack.exceptionStack(true); } catch (_se:Dynamic) {}

			var errorStr : String = "";
			try { errorStr = Std.string(e.error); } catch (_es:Dynamic) { errorStr = "(error desconocido)"; }

			message = _buildReport(errorStr, "UncaughtErrorEvent", stack);
		}
		catch (_reportErr:Dynamic)
		{
			// _buildReport falló — construir mínimo plano
			try
			{
				var errorStr = "";
				try { errorStr = Std.string(e.error); } catch (_) {}
				message = "COOL ENGINE — UNCAUGHT ERROR\n\n" + errorStr;
			}
			catch (_) {}
		}

		// ── Guardar log ───────────────────────────────────────────────────────
		#if sys
		try { Sys.println(message); } catch (_) {}
		try { _saveLog(message); } catch (_) {}
		#end

		// ── Mostrar diálogo y salir ───────────────────────────────────────────
		try
		{
			_showAndExit(message);
		}
		catch (_exitErr:Dynamic)
		{
			// _showAndExit falló — intentar diálogo directo y salir igualmente
			try { _nativeDialog(_truncate(message, 2000), "Cool Engine — Error Fatal"); } catch (_) {}
			try { Sys.stderr().writeString("=== FATAL UNCAUGHT ERROR ===\n" + message + "\n"); } catch (_) {}
			#if sys
			try { Sys.exit(1); } catch (_) {}
			#end
		}
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

		// ── REGLA CRÍTICA: cada bloque va en su propio try/catch independiente.
		// Si el heap de Haxe está corrupto por un null ptr, incluso crear un
		// String con + puede fallar. Ningún bloque puede matar al siguiente.

		// ── 1. Reporte ────────────────────────────────────────────────────────
		// Usar literales cortos y concatenar en pasos pequeños.
		// Cada operación está aislada; si falla, se usa un fallback hardcodeado.
		var report : String = "COOL ENGINE — CRASH REPORT\nC++ Critical Error\n";
		try
		{
			// Null-guard de _staticInfo por si init() nunca se llamó
			var si = _staticInfo;
			if (si == null) si = "(system info unavailable)";
			var cpp = cppMessage;
			if (cpp == null) cpp = "(no message)";
			report =
				"===========================================\n" +
				"       COOL ENGINE — CRASH REPORT\n" +
				"===========================================\n\n" +
				"Tipo     : C++ Critical Error\n" +
				"           (null object reference / stack overflow / assert)\n\n" +
				si +
				"\n--- Mensaje de C++ ---\n" +
				cpp +
				"\n\n===========================================\n" +
				"Reporta este error en:\n" +
				REPORT_URL + "\n" +
				"===========================================\n";
		}
		catch (_buildErr:Dynamic)
		{
			// El reporte mínimo hardcodeado ya está asignado arriba.
			// Intentar agregar el mensaje C++ de forma segura:
			try { report += "\n" + Std.string(cppMessage); } catch (_) {}
		}

		// ── 2. Guardar log ────────────────────────────────────────────────────
		// Sys.time() = Float, tipo valor, sin GC → más seguro que Date.now().
		var logPath : String = "";
		#if sys
		try
		{
			var dir = CRASH_DIR;
			if (dir == null || dir == "") dir = "./crash/";
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			var ts = Std.string(Std.int(Sys.time()));
			logPath = dir + LOG_PREFIX + ts + ".txt";
			File.saveContent(logPath, report + "\n");
		}
		catch (_logErr:Dynamic) { logPath = ""; }
		#end

		// ── 3. Diálogo nativo ─────────────────────────────────────────────────
		try
		{
			var dialogMessage = _truncate(report, 2000);
			if (logPath != null && logPath != "")
				try { dialogMessage += '\n\nLog guardado en:\n$logPath'; } catch (_) {}
			_nativeDialog(dialogMessage, "Cool Engine — Error Fatal");
		}
		catch (_dlgErr:Dynamic)
		{
			// Último recurso: stderr — siempre disponible aunque el runtime esté muy dañado
			try { Sys.stderr().writeString("=== FATAL C++ CRASH ===\n" + report + "\n"); } catch (_) {}
		}

		// ── 4. Abrir carpeta ──────────────────────────────────────────────────
		try { if (logPath != null && logPath != "") _openCrashFolder(CRASH_DIR); } catch (_) {}

		// ── 5. Salir ──────────────────────────────────────────────────────────
		try { Sys.exit(1); } catch (_) {}
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
		// Null-guard: si message o title son null el replace crashea con NullObjectRef.
		if (message == null) message = "(sin mensaje)";
		if (title   == null) title   = "Cool Engine — Error";

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
			var dir = CRASH_DIR;
			if (dir == null || dir == "") dir = "./crash/";
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			// Intentar formato legible; si Date falla por runtime dañado, usar Sys.time()
			var ts = "";
			try { ts = Date.now().toString().replace(" ", "_").replace(":", "-"); }
			catch (_dateErr:Dynamic)
			{
				try { ts = Std.string(Std.int(Sys.time())); } catch (_) { ts = "unknown"; }
			}
			var safeContent = (content != null) ? content : "(contenido vacío)";
			var path = dir + LOG_PREFIX + ts + ".txt";
			File.saveContent(path, safeContent + "\n");
			return path;
		}
		catch (e:Dynamic)
		{
			try { Sys.println("[CrashHandler] No se pudo guardar el log: " + Std.string(e)); } catch (_) {}
		}
		#end
		return null;
	}

	private static function _showAndExit(message:String) : Void
	{
		#if (desktop && DISCORD_ALLOWED)
		try { DiscordClient.shutdown(); } catch (_) {}
		#end

		var logPath : Null<String> = null;
		try { logPath = _saveLog(message); } catch (_) {}

		var dialogMsg : String = "(sin mensaje)";
		try
		{
			dialogMsg = _truncate(message, 2800);
			if (logPath != null)
				dialogMsg += '\n\n─────────────────────\nLog guardado en:\n${Path.normalize(logPath)}';
		}
		catch (_) { try { dialogMsg = message; } catch (_) {} }

		try { _nativeDialog(dialogMsg, "Cool Engine — Error Fatal"); } catch (_)
		{
			// Si el diálogo nativo falla, escribir al menos en stderr
			try { Sys.stderr().writeString("=== FATAL ERROR ===\n" + message + "\n"); } catch (_) {}
		}

		try { if (logPath != null) _openCrashFolder(CRASH_DIR); } catch (_) {}

		#if sys
		try { Sys.exit(1); } catch (_) {}
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
