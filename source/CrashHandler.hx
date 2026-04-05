package;

/**
 * CrashHandler — Cool Engine (v3)
 *
 * ── What changed from v2 ────────────────────────────────────────────────────
 *
 *  v2 already handled Haxe-level errors (UncaughtErrorEvent) and C++-level
 *  crashes (hxcpp critical hook) by spawning native dialogs via PowerShell /
 *  osascript / zenity from within the game process.
 *
 *  The remaining failure mode is a crash so catastrophic that:
 *    a) The hxcpp critical hook itself cannot run  (heap too corrupt, or
 *       the crash happens in a thread where the hook is not installed), OR
 *    b) The PowerShell / zenity call starts but is killed along with the
 *       game process (e.g. by a watchdog or antivirus).
 *
 *  v3 fixes this by launching CrashWatcher.exe at startup as a sibling process.
 *  The watcher is completely independent: it has its own heap, its own message
 *  loop, and it monitors the game's PID.  If the game exits with any non-zero
 *  code — including native access violations (0xC0000005), out-of-memory, or
 *  anything a mod or HScript error could cause — the watcher shows the crash
 *  report guaranteed, with no dependency on the game's runtime state.
 *
 * ── Architecture ─────────────────────────────────────────────────────────────
 *
 *  1. CrashHandler.init() calls _spawnWatcher() before anything else.
 *  2. _spawnWatcher() launches CrashWatcher.exe --pid <own_pid> --logdir ./crash/
 *  3. CrashWatcher.exe silently waits for the game PID to exit.
 *  4. Meanwhile, the in-process hooks (v2) still run when possible:
 *       Hook A — UncaughtErrorEvent  : Haxe/HScript exceptions
 *       Hook B — hxcpp critical hook : null ptr, assert, stack overflow
 *     Both write a crash log to ./crash/ before calling Sys.exit(1).
 *  5. When the game exits with code != 0, CrashWatcher reads the newest log
 *     and shows a proper dialog window (scrollable, copy-to-clipboard, etc.).
 *
 * ── Getting the own PID ──────────────────────────────────────────────────────
 *
 *  Haxe's stdlib does not expose Sys.pid().  On CPP targets we call the OS
 *  directly via __cpp__ inline C++:
 *    Windows  → GetCurrentProcessId()  (from <windows.h>)
 *    Linux    → getpid()               (from <unistd.h>)
 *    macOS    → getpid()               (from <unistd.h>)
 *
 *  On non-CPP targets (HL, interp) we fall back to a pipe-based approach:
 *  the watcher is not spawned (it is an .exe anyway), and the in-process hooks
 *  are sufficient for those targets.
 *
 * ── Usage ────────────────────────────────────────────────────────────────────
 *
 *  CrashHandler.init();  // once in Main, before createGame()
 *
 * ── Distribution ─────────────────────────────────────────────────────────────
 *
 *  Compile CrashWatcher.exe with tools/build_watcher.bat and place it next to
 *  the game executable.  If it is missing, CrashHandler silently falls back to
 *  the v2 in-process dialogs (no runtime error).
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

// ── C++ declarations needed by _getOwnPid() ───────────────────────────────────
//
// We need the OS "get current process ID" function but cannot include the full
// system headers because:
//   - <windows.h> re-introduces TRANSPARENT / DELETE / etc. macro names that
//     WinMacroFix was specifically built to eliminate from the HXCPP output.
//   - HXCPP does NOT auto-include <windows.h> or <unistd.h> in generated files.
//
// Solution for Windows:
//   Forward-declare GetCurrentProcessId() directly from kernel32.dll using
//   @:headerCode.  This injects the declaration into the generated .h file that
//   CrashHandler.cpp itself includes — no extra header, no macro pollution.
//
// Solution for Linux / macOS:
//   @:cppInclude("unistd.h") adds a safe #include to the generated .cpp.
//   POSIX headers carry no conflicting macro names.
#if (cpp && windows)
@:headerCode('
#ifndef _CE_GCPID_FWD_DECLARED_
#define _CE_GCPID_FWD_DECLARED_
// Minimal forward declaration of GetCurrentProcessId from kernel32.dll.
// __declspec(dllimport) tells the linker to look in the import table.
extern "C" __declspec(dllimport) unsigned long __stdcall GetCurrentProcessId(void);
#endif
')
#elseif (cpp && (linux || mac || android))
@:cppInclude("unistd.h")
#end
class CrashHandler
{
	// ── Configuration ─────────────────────────────────────────────────────────
	private static var CRASH_DIR:String = _resolveCrashDir();
	private static inline final LOG_PREFIX:String = "CoolEngine_";
	private static inline final REPORT_URL:String = "https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/issues";
	private static inline final ENGINE_VERSION:String = "0.6.1B";

	/**
	 * File name of the external watcher executable.
	 * Must be placed in the same directory as the game .exe.
	 * Compiled from tools/CrashWatcher.cs via tools/build_watcher.bat.
	 */
	private static inline final WATCHER_EXE:String = "CrashWatcher.exe";

	// ── Internal state ────────────────────────────────────────────────────────
	private static var _handling:Bool = false;
	private static var _initialized:Bool = false;

	/**
	 * True once CrashWatcher.exe has been successfully spawned.
	 * When true, _showAndExit and _onCriticalError skip the in-process
	 * dialog — the watcher will show its own full-featured crash window,
	 * so there is no reason to also pop up the PowerShell / Lime fallback.
	 */
	private static var _watcherRunning:Bool = false;

	/**
	 * System info pre-built in init() while the runtime is healthy.
	 * Used in _onCriticalError without allocating new objects.
	 */
	private static var _staticInfo:String = "";

	// =========================================================================
	//  PUBLIC API
	// =========================================================================

	public static function init():Void
	{
		if (_initialized)
			return;
		_initialized = true;

		_staticInfo = _buildStaticInfo();

		// ── External watcher (v3, highest priority) ───────────────────────────
		// Spawned first so it is already monitoring before any hook fires.
		_spawnWatcher();

		// ── Hook A: Haxe / OpenFL uncaught errors ────────────────────────────
		// Priority 1000 ensures we run before any OpenFL default handler that
		// could call stopImmediatePropagation() and swallow the event.
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, _onUncaughtError, false, // useCapture
			1000 // priority
		);

		// ── Hook B: C++ null ptr / stack overflow / assert ───────────────────
		#if cpp
		untyped __global__.__hxcpp_set_critical_error_handler(_onCriticalError);
		#end

		trace('[CrashHandler] v3 ready. Crash dir → $CRASH_DIR');
	}

	/**
	 * Manually report an error (useful in try/catch to log and optionally exit).
	 */
	public static function report(error:Dynamic, ?context:String, fatal:Bool = false):Void
	{
		var message:String = "";
		try
		{
			var stack = [];
			try
			{
				stack = CallStack.exceptionStack(true);
			}
			catch (_se:Dynamic)
			{
			}
			if (stack.length == 0)
				try
				{
					stack = CallStack.callStack();
				}
				catch (_cs:Dynamic)
				{
				}

			var errorStr:String = "";
			try
			{
				errorStr = Std.string(error);
			}
			catch (_e:Dynamic)
			{
				errorStr = "(non-serialisable error)";
			}

			var ctx:Null<String> = null;
			try
			{
				ctx = context;
			}
			catch (_)
			{
			}

			message = _buildReport(errorStr, ctx, stack);
		}
		catch (_reportErr:Dynamic)
		{
			try
			{
				message = "COOL ENGINE — ERROR\n" + Std.string(error);
			}
			catch (_)
			{
				message = "COOL ENGINE — ERROR";
			}
		}

		#if sys
		try
		{
			Sys.println(message);
		}
		catch (_)
		{
		}
		try
		{
			var path = _saveLog(message);
			if (path != null)
				Sys.println('[CrashHandler] Log → ${haxe.io.Path.normalize(path)}');
		}
		catch (_)
		{
		}
		#end

		if (fatal)
		{
			try
			{
				_showAndExit(message);
			}
			catch (_)
			{
				try
				{
					_nativeDialog(_truncate(message, 2000), "Cool Engine — Fatal Error");
				}
				catch (_)
				{
				}
				#if sys try
				{
					Sys.exit(1);
				}
				catch (_)
				{
				} #end
			}
		}
		#if debug
		else
		{
			try
			{
				_nativeDialog('[NON-FATAL]\n\n' + message, "Cool Engine — Non-Fatal Error");
			}
			catch (_)
			{
			}
		}
		#end
	}

	// =========================================================================
	//  EXTERNAL WATCHER (v3)
	// =========================================================================

	/**
	 * Launches CrashWatcher.exe as a detached sibling process.
	 *
	 * The watcher receives:
	 *   --pid    <own PID>       so it can wait for us to exit
	 *   --logdir <crash dir>     so it can read the crash log we write
	 *   --url    <report URL>    for the "Report Bug" button in its dialog
	 *
	 * If CrashWatcher.exe is not found, we do nothing — the v2 in-process
	 * dialogs remain active as the fallback.
	 */
	private static function _spawnWatcher():Void
	{
		// Only on CPP desktop targets — the watcher is a Windows .exe.
		// On Linux / macOS the watcher won't exist; the in-process hooks suffice.
		// (A future CrashWatcher build for those platforms would remove this guard.)
		#if (cpp && desktop)
		try
		{
			#if sys
			if (!FileSystem.exists(WATCHER_EXE))
			{
				trace('[CrashHandler] CrashWatcher.exe not found — skipping external watcher.');
				return;
			}
			#end

			var pid = _getOwnPid();
			if (pid <= 0)
			{
				trace('[CrashHandler] Could not determine own PID — skipping external watcher.');
				return;
			}

			var dir = CRASH_DIR;
			if (dir == null || dir == "")
				dir = "./crash/";

			// Resolve to an absolute path before handing it to the watcher.
			// CrashWatcher.exe is spawned via "start /B" which may inherit a
			// different working directory, so a relative "./crash/" would point
			// to the wrong location and the watcher would never find the log.
			#if sys
			try
			{
				var abs = sys.FileSystem.absolutePath(dir);
				if (abs != null && abs != "")
					dir = abs;
			}
			catch (_)
			{
			}
			#end

			// Build the argument list
			// We do NOT quote pid (it is a plain integer).
			// We DO quote logdir and url in case they contain spaces.
			var args = [
				   "--pid", Std.string(pid),
				"--logdir",             dir,
				   "--url",      REPORT_URL,
			];

			// Sys.command() blocks — we need a non-blocking spawn.
			// On Windows we use 'start "" /B' to detach immediately.
			// On Linux/macOS we use '&' via bash.
			#if windows
			// 'start "" /B <exe> <args>' launches detached with no new window.
			var cmdArgs = ["/C", "start", "", "/B", WATCHER_EXE].concat(args);
			Sys.command("cmd", cmdArgs);
			#elseif (linux || mac)
			// Build a single shell string: "CrashWatcher.exe --pid X ... &"
			// (Unlikely to be needed in practice, but kept for completeness.)
			var shellCmd = WATCHER_EXE + " " + args.join(" ") + " &";
			Sys.command("sh", ["-c", shellCmd]);
			#end

			trace('[CrashHandler] CrashWatcher launched (game PID = $pid).');
			_watcherRunning = true;
		}
		catch (e:Dynamic)
		{
			// Non-fatal: watcher failed to spawn, fall back to in-process hooks.
			try
			{
				trace('[CrashHandler] Could not launch CrashWatcher: ' + Std.string(e));
			}
			catch (_)
			{
			}
		}
		#end
	}

	/**
	 * Returns the current process ID using a direct OS call via inline C++.
	 * Returns -1 on non-CPP targets or if the call fails.
	 */
	private static function _getOwnPid():Int
	{
		#if cpp
		try
		{
			#if windows
			// Declared via @:headerCode above — no <windows.h> needed.
			return untyped __cpp__("(int)GetCurrentProcessId()");
			#else
			// Declared via @:cppInclude("unistd.h") above.
			return untyped __cpp__("(int)getpid()");
			#end
		}
		catch (_:Dynamic)
		{
			return -1;
		}
		#else
		return -1;
		#end
	}

	// =========================================================================
	//  INTERNAL HOOKS
	// =========================================================================

	private static function _onUncaughtError(e:UncaughtErrorEvent):Void
	{
		if (_handling)
			return;
		_handling = true;

		var message:String = "COOL ENGINE — UNCAUGHT ERROR\n(failed to build report)";
		try
		{
			var stack = [];
			try
			{
				stack = CallStack.exceptionStack(true);
			}
			catch (_se:Dynamic)
			{
			}

			var errorStr:String = "";
			try
			{
				errorStr = Std.string(e.error);
			}
			catch (_es:Dynamic)
			{
				errorStr = "(unknown error)";
			}

			message = _buildReport(errorStr, "UncaughtErrorEvent", stack);
		}
		catch (_reportErr:Dynamic)
		{
			try
			{
				var errorStr = "";
				try
				{
					errorStr = Std.string(e.error);
				}
				catch (_)
				{
				}
				message = "COOL ENGINE — UNCAUGHT ERROR\n\n" + errorStr;
			}
			catch (_)
			{
			}
		}

		#if sys
		try
		{
			Sys.println(message);
		}
		catch (_)
		{
		}
		try
		{
			_saveLog(message);
		}
		catch (_)
		{
		}
		#end

		try
		{
			_showAndExit(message);
		}
		catch (_exitErr:Dynamic)
		{
			try
			{
				_nativeDialog(_truncate(message, 2000), "Cool Engine — Fatal Error");
			}
			catch (_)
			{
			}
			try
			{
				Sys.stderr().writeString("=== FATAL UNCAUGHT ERROR ===\n" + message + "\n");
			}
			catch (_)
			{
			}
			#if sys
			try
			{
				Sys.exit(1);
			}
			catch (_)
			{
			}
			#end
		}
	}

	/**
	 * Called by hxcpp when a C++ critical error occurs (null ptr, etc.).
	 *
	 * Rules — keep each block in its own independent try/catch:
	 *   • Sys.time()    → Float value type, no GC needed
	 *   • sys.io.File   → OS call, independent of Haxe heap
	 *   • Sys.command() → spawns a new process, safe even if our heap is corrupt
	 *   • _staticInfo   → pre-built String, already on the heap from init()
	 */
	#if cpp
	private static function _onCriticalError(cppMessage:String):Void
	{
		if (_handling)
			return;
		_handling = true;

		// ── 1. Build report ───────────────────────────────────────────────────
		var report:String = "COOL ENGINE — CRASH REPORT\nC++ Critical Error\n";
		try
		{
			var si = _staticInfo;
			if (si == null)
				si = "(system info unavailable)";
			var cpp = cppMessage;
			if (cpp == null)
				cpp = "(no message)";

			// Attempt to capture the call stack.
			// We try exceptionStack first (more informative when hxcpp has one),
			// then fall back to callStack (always available at the Haxe level).
			// Both are wrapped in their own try/catch because the heap may be
			// partially corrupt at this point — we must not let stack capture
			// itself crash the handler.
			var stack = [];
			try
			{
				stack = haxe.CallStack.exceptionStack(true);
			}
			catch (_se:Dynamic)
			{
			}
			if (stack.length == 0)
			{
				try
				{
					stack = haxe.CallStack.callStack();
				}
				catch (_cs:Dynamic)
				{
				}
			}

			// Build the report using the shared helper so the format is identical
			// to UncaughtErrorEvent reports (header, system info, stack, footer).
			// We pass the C++ message as the error string and annotate the context
			// so it is clear this came from the hxcpp critical-error hook.
			report = _buildReport(cpp, "C++ Critical Error (null object reference / null function pointer / stack overflow / assert)", stack);
		}
		catch (_buildErr:Dynamic)
		{
			try
			{
				report += "\n" + Std.string(cppMessage);
			}
			catch (_)
			{
			}
		}

		// ── 2. Save log ───────────────────────────────────────────────────────
		var logPath:String = "";
		#if sys
		try
		{
			var dir = CRASH_DIR;
			if (dir == null || dir == "")
				dir = "./crash/";
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			var ts = Std.string(Std.int(Sys.time()));
			logPath = dir + LOG_PREFIX + ts + ".txt";
			File.saveContent(logPath, report + "\n");
		}
		catch (_logErr:Dynamic)
		{
			logPath = "";
		}
		#end

		// ── 3. In-process native dialog (best-effort, only if watcher absent) ──
		// If CrashWatcher.exe is running it will show the crash report itself.
		// Showing a second dialog here would be redundant and confusing.
		if (!_watcherRunning)
		{
			try
			{
				var dialogMessage = _truncate(report, 2000);
				if (logPath != null && logPath != "")
					try
					{
						dialogMessage += '\n\nLog saved at:\n$logPath';
					}
					catch (_)
					{
					}
				_nativeDialog(dialogMessage, "Cool Engine — Fatal Error");
			}
			catch (_dlgErr:Dynamic)
			{
				try
				{
					Sys.stderr().writeString("=== FATAL C++ CRASH ===\n" + report + "\n");
				}
				catch (_)
				{
				}
			}
		}

		// ── 4. Open crash folder ──────────────────────────────────────────────
		try
		{
			if (logPath != null && logPath != "")
				_openCrashFolder(CRASH_DIR);
		}
		catch (_)
		{
		}

		// ── 5. Exit — the watcher detects the non-zero exit code ──────────────
		try
		{
			Sys.exit(1);
		}
		catch (_)
		{
		}
	}
	#end

	// =========================================================================
	//  NATIVE DIALOGS (spawned as separate processes — no deadlock)
	// =========================================================================

	/**
	 * Shows a modal error dialog using OS tools, without going through Lime/OpenFL.
	 * Each platform spawns an independent process so there is no deadlock even
	 * if the render thread is blocked.
	 *
	 * Windows → PowerShell + Windows.Forms.MessageBox
	 * macOS   → osascript
	 * Linux   → zenity → kdialog → xmessage
	 * Fallback → lime.app.Application (if the above all fail)
	 * Last resort → stderr
	 */
	private static function _nativeDialog(message:String, title:String):Void
	{
		if (message == null)
			message = "(no message)";
		if (title == null)
			title = "Cool Engine — Error";

		var shown = false;

		#if (sys && windows)
		if (!shown)
		{
			try
			{
				// In PowerShell single-quoted strings the only escape is '' (two quotes).
				// Backtick-quote (`') does NOT work inside '...', it is only valid in "...".
				var msg = message.replace("'", "''");
				var ttl = title.replace("'", "''");
				var ps = "Add-Type -AssemblyName System.Windows.Forms;"
					+ "[System.Windows.Forms.MessageBox]::Show('"
					+ msg
					+ "','"
					+ ttl
					+ "',0,16)|Out-Null";
				var ret = Sys.command("powershell", ["-NonInteractive", "-Command", ps]);
				if (ret != 9009)
					shown = true;
			}
			catch (_)
			{
			}
		}
		#end

		#if (sys && mac)
		if (!shown)
		{
			try
			{
				var escaped = message.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
				var escapedTitle = title.replace("\"", "\\\"");
				Sys.command("osascript", ["-e", 'display alert "$escapedTitle" message "$escaped" as critical']);
				shown = true;
			}
			catch (_)
			{
			}
		}
		#end

		#if (sys && linux)
		if (!shown)
		{
			try
			{
				var ret = Sys.command("zenity", ["--error", '--title=$title', '--text=$message', "--width=600"]);
				if (ret != 127)
					shown = true;
			}
			catch (_)
			{
			}
		}
		if (!shown)
		{
			try
			{
				var ret = Sys.command("kdialog", ["--error", message, "--title", title]);
				if (ret != 127)
					shown = true;
			}
			catch (_)
			{
			}
		}
		if (!shown)
		{
			try
			{
				var ret = Sys.command("xmessage", ["-center", message]);
				if (ret != 127)
					shown = true;
			}
			catch (_)
			{
			}
		}
		#end

		if (!shown)
		{
			try
			{
				lime.app.Application.current.window.alert(_truncate(message, 3000), title);
				shown = true;
			}
			catch (_)
			{
			}
		}

		if (!shown)
		{
			try
			{
				Sys.stderr().writeString("=== FATAL CRASH ===\n" + message + "\n");
			}
			catch (_)
			{
			}
		}
	}

	// =========================================================================
	//  REPORT BUILDING
	// =========================================================================

	private static function _buildReport(error:String, ?context:String, stack:Array<StackItem>):String
	{
		var sb = new StringBuf();
		_header(sb);

		if (context != null && context.length > 0)
			sb.add('Context  : $context\n\n');

		sb.add('Error    : $error\n\n');
		_appendStack(sb, stack);
		_footer(sb);
		return sb.toString();
	}

	/** Pre-builds system info in init() while the runtime is healthy. */
	private static function _buildStaticInfo():String
	{
		var sb = new StringBuf();

		sb.add('Version  : $ENGINE_VERSION\n');
		sb.add('Date     : ${Date.now().toString()}\n');
		sb.add('System   : ${_systemName()}\n');

		#if sys
		sb.add('Memory   : ${_memMB()} MB used\n');
		#end

		try
		{
			var app = lime.app.Application.current;
			if (app != null && app.window != null)
				sb.add('Window   : ${app.window.width}x${app.window.height}\n');
		}
		catch (_)
		{
		}

		sb.add('\n--- Flixel State ---\n');
		try
		{
			if (flixel.FlxG.game != null && flixel.FlxG.state != null)
			{
				var cls = Type.getClass(flixel.FlxG.state);
				sb.add('State    : ${cls != null ? Type.getClassName(cls) : "???"}\n');
				sb.add('FPS      : ${Math.round(openfl.Lib.current.stage.frameRate)}\n');
			}
			else
				sb.add('State    : (FlxG not available)\n');
		}
		catch (_)
		{
			sb.add('State    : (error reading state)\n');
		}

		return sb.toString();
	}

	private static function _header(sb:StringBuf):Void
	{
		sb.add("===========================================\n");
		sb.add("       COOL ENGINE — CRASH REPORT\n");
		sb.add("===========================================\n\n");
		sb.add(_staticInfo);
		sb.add("\n===========================================\n\n");
	}

	private static function _footer(sb:StringBuf):Void
	{
		sb.add('\n===========================================\n');
		sb.add('Report this error at:\n');
		sb.add('$REPORT_URL\n');
		sb.add('===========================================\n');
	}

	private static function _appendStack(sb:StringBuf, stack:Array<StackItem>):Void
	{
		if (stack == null || stack.length == 0)
		{
			sb.add("--- Call Stack not available ---\n");
			return;
		}

		sb.add("--- Call Stack ---\n");
		for (item in stack)
		{
			switch (item)
			{
				case FilePos(s, file, line, column):
					var col = (column != null) ? ':$column' : '';
					var method = (s != null) ? switch (s)
					{
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

	private static function _resolveCrashDir():String
	{
		#if mobileC
		try
		{
			var base = lime.system.System.documentsDirectory;
			if (base == null || base == "")
				base = "./";
			if (!base.endsWith("/"))
				base += "/";
			return base + "CoolEngine/crash/";
		}
		catch (_:Dynamic)
		{
			return "./crash/";
		}
		#else
		return "./crash/";
		#end
	}

	private static function _saveLog(content:String):Null<String>
	{
		#if sys
		try
		{
			var dir = CRASH_DIR;
			if (dir == null || dir == "")
				dir = "./crash/";
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			var ts = "";
			try
			{
				ts = Date.now().toString().replace(" ", "_").replace(":", "-");
			}
			catch (_dateErr:Dynamic)
			{
				try
				{
					ts = Std.string(Std.int(Sys.time()));
				}
				catch (_)
				{
					ts = "unknown";
				}
			}
			var safeContent = (content != null) ? content : "(empty content)";
			var path = dir + LOG_PREFIX + ts + ".txt";
			File.saveContent(path, safeContent + "\n");
			return path;
		}
		catch (e:Dynamic)
		{
			try
			{
				Sys.println("[CrashHandler] Could not save log: " + Std.string(e));
			}
			catch (_)
			{
			}
		}
		#end
		return null;
	}

	private static function _showAndExit(message:String):Void
	{
		#if (desktop && DISCORD_ALLOWED)
		try
		{
			DiscordClient.shutdown();
		}
		catch (_)
		{
		}
		#end

		var logPath:Null<String> = null;
		try
		{
			logPath = _saveLog(message);
		}
		catch (_)
		{
		}

		var dialogMsg:String = "(no message)";
		try
		{
			dialogMsg = _truncate(message, 2800);
			if (logPath != null)
				dialogMsg += '\n\n─────────────────────\nLog saved at:\n${Path.normalize(logPath)}';
		}
		catch (_)
		{
			try
			{
				dialogMsg = message;
			}
			catch (_)
			{
			}
		}

		// If CrashWatcher is already running it will show its own full-featured
		// crash dialog after we exit — no need to also show an in-process one.
		// Only fall back to the native dialog when the watcher is not available.
		if (!_watcherRunning)
			try
			{
				_nativeDialog(dialogMsg, "Cool Engine — Fatal Error");
			}
			catch (_)
			{
				try
				{
					Sys.stderr().writeString("=== FATAL ERROR ===\n" + message + "\n");
				}
				catch (_)
				{
				}
			}

		try
		{
			if (logPath != null)
				_openCrashFolder(CRASH_DIR);
		}
		catch (_)
		{
		}

		#if sys
		try
		{
			Sys.exit(1);
		}
		catch (_)
		{
		}
		#end
	}

	private static function _openCrashFolder(dir:String):Void
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
		catch (_)
		{
		}
	}

	private static function _truncate(s:String, max:Int):String
	{
		if (s.length <= max)
			return s;
		return s.substr(0, max) + "\n\n[... truncated. See full log file.]";
	}

	private static function _systemName():String
	{
		#if sys
		return Sys.systemName();
		#elseif windows
		return "Windows";
		#elseif linux
		return "Linux";
		#elseif mac
		return "macOS";
		#else
		return "Unknown";
		#end
	}

	#if sys
	private static function _memMB():String
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
		catch (_)
		{
			return "??";
		}
	}
	#end
}
