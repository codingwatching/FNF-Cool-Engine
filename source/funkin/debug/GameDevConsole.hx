package funkin.debug;

import flixel.FlxG;
import flixel.util.FlxColor;
import openfl.display.Sprite;
import openfl.display.Graphics;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.events.KeyboardEvent;
import openfl.events.FocusEvent;
import openfl.ui.Keyboard;

/**
 * GameDevConsole — In-game developer console overlay for debug/dev builds.
 *
 * Renders as a persistent OpenFL overlay above all HaxeFlixel layers, so it
 * works in any game state (menus, PlayState, editors, substates, etc.).
 *
 * ══════════════════════════════════════════════════════════════════════════
 *  FEATURES
 * ══════════════════════════════════════════════════════════════════════════
 *  • Automatic trace() interception — every haxe.Log.trace() call is shown.
 *  • Script error display — call GameDevConsole.scriptError() from
 *    HScriptInstance / ScriptHandler to show structured script failures
 *    with script name, function, message, and line number.
 *  • Crash / uncaught-error capture — UncaughtErrorEvent is caught and
 *    shown in red with a full stack trace when available.
 *  • Command input field — type commands at the bottom and press Enter.
 *    Built-in commands: help, clear, quit, echo <msg>, and any custom
 *    commands registered with GameDevConsole.registerCommand().
 *  • Command history — navigate previous commands with ↑ / ↓.
 *  • Auto-scroll — the log follows the latest entry; scrollable via mouse
 *    wheel or keyboard.
 *  • Color-coded entries: trace (white), warn (yellow), error (red),
 *    success (green), script error (orange), crash (bright red), cmd (cyan).
 *  • Auto-show on errors — the console opens automatically when any error
 *    or crash is detected.
 *
 * ══════════════════════════════════════════════════════════════════════════
 *  KEYBOARD SHORTCUTS
 * ══════════════════════════════════════════════════════════════════════════
 *  F4          Toggle console visible / hidden
 *  F6          Clear the log
 *  ↑ / ↓      Scroll log (when input is empty) or navigate command history
 *  Enter       Submit command (when input is focused)
 *  Escape      Unfocus input / hide console
 *
 * ══════════════════════════════════════════════════════════════════════════
 *  USAGE
 * ══════════════════════════════════════════════════════════════════════════
 *  // 1. Initialize once (e.g. in Main.hx)
 *  GameDevConsole.init();
 *
 *  // 2. Log messages from anywhere
 *  GameDevConsole.log("Asset loaded");
 *  GameDevConsole.warn("Missing optional field");
 *  GameDevConsole.error("Failed to parse chart");
 *  GameDevConsole.success("Mod loaded OK");
 *
 *  // 3. Report a structured script error (called by ScriptHandler)
 *  GameDevConsole.scriptError("myMod.hx", "onBeatHit", "Unknown var 'foo'", 42);
 *
 *  // 4. Register a custom command
 *  GameDevConsole.registerCommand("reload", "Reload the current stage", function(args) {
 *      PlayState.instance.reloadStage();
 *      GameDevConsole.success("Stage reloaded.");
 *  });
 *
 *  // 5. Call update() each frame (e.g. in MusicBeatState.update)
 *  GameDevConsole.update();
 */
class GameDevConsole
{
	// ── Layout constants ───────────────────────────────────────────────────
	static inline var CONSOLE_W    : Int   = 620;
	static inline var CONSOLE_H    : Int   = 320;
	static inline var FONT_SIZE    : Int   = 11;
	static inline var MAX_LINES    : Int   = 300;
	static inline var LOG_AREA_H   : Int   = 266; // height of scrollable log area
	static inline var INPUT_H      : Int   = 22;  // height of command input row
	static inline var PADDING      : Int   = 6;
	static inline var HEADER_H     : Int   = 18;
	static inline var SCROLLBAR_W  : Int   = 5;
	static inline var BG_ALPHA     : Float = 0.92;

	// ── Colours ────────────────────────────────────────────────────────────
	static inline var COL_BG        : Int = 0xFF080C14; // deep dark navy
	static inline var COL_HEADER_BG : Int = 0xFF0D1526;
	static inline var COL_BORDER    : Int = 0xFF1E3A6E;
	static inline var COL_TITLE     : Int = 0xFF7EB8FF;
	static inline var COL_INPUT_BG  : Int = 0xFF0F1C30;
	static inline var COL_INPUT_BD  : Int = 0xFF2A4A80;
	static inline var COL_PROMPT    : Int = 0xFF4FC3F7;

	// Log entry colours
	static inline var COL_TRACE   : Int = 0xFFCDD5E0;
	static inline var COL_WARN    : Int = 0xFFFFD54F;
	static inline var COL_ERROR   : Int = 0xFFFF5252;
	static inline var COL_SUCCESS : Int = 0xFF69F0AE;
	static inline var COL_SCRIPT  : Int = 0xFFFF9800; // orange — script errors
	static inline var COL_CRASH   : Int = 0xFFFF1744; // bright red — crashes
	static inline var COL_CMD     : Int = 0xFF40E0FF; // cyan — command echo
	static inline var COL_DIM     : Int = 0xFF4A5568;
	static inline var COL_SCROLL  : Int = 0xFF2A4A80;

	// ── Typing for log entries ─────────────────────────────────────────────

	/**
	 * Internal log entry.
	 * label — optional left-side tag rendered before the message, e.g. "ERROR", "WARN", "CRASH".
	 *         null means no tag (plain trace).
	 */
	private static var Entry = {text: "", col: 0, label: ""};

	// ── Public state ───────────────────────────────────────────────────────

	/** Whether the console has been initialized. */
	public static var initialized : Bool = false;

	/** Whether the console overlay is currently visible. */
	public static var visible     : Bool = false;

	// ── Private state ──────────────────────────────────────────────────────

	private static var _overlay    : Sprite;
	private static var _bg         : Sprite;
	private static var _logField   : TextField;
	private static var _titleField : TextField;
	private static var _inputField : TextField;
	private static var _promptField: TextField;
	private static var _inputBg    : Sprite;

	private static var _lines      : Array<{text:String, col:Int, label:Null<String>}> = [];
	private static var _scrollPos  : Int  = 0;
	private static var _dirty      : Bool = false;
	private static var _origTrace  : Dynamic;

	/** Tracks whether the cursor was shown by us so we can restore it. */
	private static var _cursorWasHidden : Bool = false;

	/** Whether the command input field currently has keyboard focus. */
	private static var _inputFocused : Bool = false;

	// ── Command system ─────────────────────────────────────────────────────

	/** Registered custom commands: name → {desc, handler}. */
	private static var _commands : Map<String, {desc:String, fn:Array<String>->Void}> = [];

	/** History of submitted commands (most recent last). */
	private static var _history  : Array<String> = [];

	/** Current position in history navigation (−1 = not browsing). */
	private static var _histIdx  : Int = -1;

	/** Temporary buffer for the command being typed before browsing history. */
	private static var _histBuf  : String = "";

	static inline var MAX_HISTORY : Int = 50;

	// ══════════════════════════════════════════════════════════════════════
	//  INIT
	// ══════════════════════════════════════════════════════════════════════

	/**
	 * Initialize the console. Call once from Main.hx or your first game state.
	 * Subsequent calls are no-ops.
	 */
	public static function init():Void
	{
		if (initialized) return;

		_lines     = [];
		_scrollPos = 0;
		_commands  = [];
		_history   = [];

		// ── Root container ────────────────────────────────────────────────
		_overlay         = new Sprite();
		_overlay.x       = 8;
		_overlay.y       = 8;
		_overlay.visible = false;

		// Background panel
		_bg = new Sprite();
		_overlay.addChild(_bg);
		_drawBg();

		// Header / title bar
		_titleField = _makeTextField(PADDING, 2, CONSOLE_W - PADDING * 2, HEADER_H);
		_titleField.textColor = COL_TITLE;
		_titleField.text = _buildTitle();
		_overlay.addChild(_titleField);

		// Scrollable log area
		_logField = _makeTextField(PADDING, HEADER_H + 4, CONSOLE_W - PADDING * 2 - SCROLLBAR_W - 2, LOG_AREA_H);
		_logField.multiline = true;
		_logField.wordWrap  = true;
		_overlay.addChild(_logField);

		// Command input row ── background
		_inputBg = new Sprite();
		_overlay.addChild(_inputBg);
		_drawInputBg();

		// Prompt label ">"
		_promptField = _makeTextField(PADDING, CONSOLE_H - INPUT_H - 2, 14, INPUT_H);
		_promptField.textColor = COL_PROMPT;
		_promptField.text = ">";
		_overlay.addChild(_promptField);

		// Editable input field
		_inputField            = new TextField();
		_inputField.x          = PADDING + 16;
		_inputField.y          = CONSOLE_H - INPUT_H - 2;
		_inputField.width      = CONSOLE_W - PADDING * 2 - 20;
		_inputField.height     = INPUT_H;
		_inputField.type       = TextFieldType.INPUT;
		_inputField.multiline  = false;
		_inputField.wordWrap   = false;
		_inputField.selectable = true;
		_inputField.mouseEnabled = true;
		_inputField.defaultTextFormat = new TextFormat("_typewriter", FONT_SIZE, COL_PROMPT);
		_inputField.maxChars   = 512;
		_overlay.addChild(_inputField);

		// Add to the OpenFL stage above everything HaxeFlixel renders
		FlxG.stage.addChild(_overlay);

		// ── Intercept haxe.Log.trace ──────────────────────────────────────
		_origTrace = haxe.Log.trace;
		haxe.Log.trace = function(v:Dynamic, ?infos:haxe.PosInfos) {
			if (_origTrace != null) _origTrace(v, infos);
			var src = (infos != null) ? '${infos.fileName}:${infos.lineNumber}' : '';
			var msg = Std.string(v);
			_addLine(msg, _colorForMessage(msg), src);
		};

		// ── Stage event listeners ─────────────────────────────────────────
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);
		FlxG.stage.addEventListener(openfl.events.MouseEvent.MOUSE_WHEEL, _onMouseWheel);
		FlxG.stage.addEventListener(openfl.events.UncaughtErrorEvent.UNCAUGHT_ERROR, _onUncaughtError);

		_inputField.addEventListener(FocusEvent.FOCUS_IN,  function(_) _inputFocused = true);
		_inputField.addEventListener(FocusEvent.FOCUS_OUT, function(_) _inputFocused = false);

		// ── Register built-in commands ────────────────────────────────────
		_registerBuiltins();

		initialized = true;
		log("[GameDevConsole] Initialized. F4 = toggle | F6 = clear | type 'help' for commands.", COL_SUCCESS);
	}

	// ══════════════════════════════════════════════════════════════════════
	//  PUBLIC LOGGING API
	// ══════════════════════════════════════════════════════════════════════

	/**
	 * Log a generic message (white/grey).
	 * @param msg  The message string.
	 * @param col  Optional custom color override (0xAARRGGBB).
	 */
	public static function log(msg:String, ?col:Null<Int>):Void
	{
		if (!initialized) return;
		_addLine(msg, col != null ? col : COL_TRACE);
	}

	/**
	 * Log a warning (yellow).
	 * @param msg  Warning message.
	 */
	public static function warn(msg:String):Void
	{
		if (!initialized) return;
		_addLine(msg, COL_WARN, null, "WARN");
	}

	/**
	 * Log an error (red).
	 * The console is automatically revealed if it is currently hidden.
	 * @param msg  Error message.
	 */
	public static function error(msg:String):Void
	{
		if (!initialized) return;
		_addLine(msg, COL_ERROR, null, "ERROR");
		if (!visible) show();
	}

	/**
	 * Log a success / info message (green).
	 * @param msg  Success message.
	 */
	public static function success(msg:String):Void
	{
		if (!initialized) return;
		_addLine(msg, COL_SUCCESS);
	}

	/**
	 * Report a structured script error with optional source-line preview.
	 *
	 * Called automatically by HScriptInstance and ScriptHandler; you can also
	 * call it from any scripting layer.
	 *
	 * When `scriptSource` is provided, the console will extract the exact
	 * offending line and print it with a caret (^) pointing at the column,
	 * similar to how compilers like GCC or Python report syntax errors.
	 *
	 * Example output:
	 *   SCRIPT | [12:00:01] SCRIPT ERROR in [myMod.hx]  at onBeatHit  line 42
	 *   SCRIPT | [12:00:01]   Unknown identifier: "fpo"
	 *   SCRIPT | [12:00:01]   42 |  var x = fpo + 1;
	 *   SCRIPT | [12:00:01]            ^
	 *
	 * @param scriptName    File or logical name of the failing script.
	 * @param funcName      Function where the error occurred ("onBeatHit", "loadString", ...).
	 * @param message       Human-readable error message from the interpreter.
	 * @param lineNum       Line number inside the script (1-based; -1 if unknown).
	 * @param colNum        Column offset inside the line (0-based; -1 if unknown).
	 * @param scriptSource  Full source text of the script (optional). When supplied,
	 *                      the offending line is shown with a caret pointer.
	 */
	public static function scriptError(
		scriptName:String,
		funcName:String,
		message:String,
		lineNum:Int = -1,
		colNum:Int = -1,
		?scriptSource:String
	):Void
	{
		if (!initialized) return;

		// ── Header: script name + location ───────────────────────────────────
		var locPart = (lineNum >= 0) ? '  line ${lineNum}' : '';
		var fnPart  = (funcName != null && funcName.length > 0) ? '  at ${funcName}' : '';
		_addLine('SCRIPT ERROR in [${scriptName}]${fnPart}${locPart}', COL_SCRIPT, null, "SCRIPT");

		// ── Error message ─────────────────────────────────────────────────────
		// Try to extract extra position info embedded in the message string.
		// HScript often appends ":line:col" or "(line col)" to the message.
		var parsedLine = lineNum;
		var parsedCol  = colNum;
		_parsePositionFromMessage(message, parsedLine, parsedCol);

		_addLine('  ' + message, COL_SCRIPT, null, "SCRIPT");

		// ── Source-line preview with caret ────────────────────────────────────
		if (scriptSource != null && parsedLine >= 1)
		{
			var srcLines = scriptSource.split("\n");
			var zeroIdx  = parsedLine - 1; // convert 1-based to 0-based

			// Show one line of context before the error when available
			if (zeroIdx > 0)
			{
				var prevText = StringTools.trim(srcLines[zeroIdx - 1]);
				if (prevText.length > 0)
					_addLine('  ${parsedLine - 1} |  ${prevText}', COL_DIM, null, "SCRIPT");
			}

			// The offending line itself
			if (zeroIdx < srcLines.length)
			{
				var errLine = srcLines[zeroIdx];
				// Strip trailing \r so the display looks clean on Windows line endings
				errLine = StringTools.replace(errLine, "\r", "");
				_addLine('  ${parsedLine} |  ${errLine}', COL_WARN, null, "SCRIPT");

				// Caret line: position the ^ under the column if known
				if (parsedCol >= 0)
				{
					// Count leading whitespace in the raw line so the caret
					// lands on the right character even with indented code.
					var lineNumWidth = Std.string(parsedLine).length;
					var prefix       = StringTools.rpad("", " ", lineNumWidth + 4); // "  N |  " width
					var caretPad     = StringTools.rpad("", " ", parsedCol);
					_addLine(prefix + caretPad + "^", COL_ERROR, null, "SCRIPT");
				}
				else
				{
					// No column info — just underline the whole non-whitespace region
					var lineNumWidth = Std.string(parsedLine).length;
					var prefix       = StringTools.rpad("", " ", lineNumWidth + 4);
					var trimmed      = StringTools.ltrim(srcLines[zeroIdx].split("\r")[0]);
					var underline    = StringTools.rpad("", "^", Std.int(Math.min(trimmed.length, 40)));
					_addLine(prefix + underline, COL_ERROR, null, "SCRIPT");
				}
			}
		}

		if (!visible) show();
	}

	/**
	 * Report a crash or fatal error with an optional stack trace string.
	 *
	 * @param message     Short crash description.
	 * @param stackTrace  Full stack trace string (can be null).
	 */
	public static function crash(message:String, ?stackTrace:String):Void
	{
		if (!initialized) return;

		_addLine("CRASH: " + message, COL_CRASH, null, "CRASH");

		if (stackTrace != null && stackTrace.length > 0)
		{
			var lines = stackTrace.split("\n");
			for (line in lines)
			{
				var trimmed = StringTools.trim(line);
				if (trimmed.length > 0)
					_addLine("  " + trimmed, COL_DIM, null, "CRASH");
			}
		}

		if (!visible) show();
	}

	/**
	 * Clear the log and reset scroll position.
	 */
	public static function clear():Void
	{
		if (!initialized) return;
		_lines     = [];
		_scrollPos = 0;
		_dirty     = true;
		_render();
	}

	// ══════════════════════════════════════════════════════════════════════
	//  COMMAND SYSTEM
	// ══════════════════════════════════════════════════════════════════════

	/**
	 * Register a custom command callable from the console input.
	 *
	 * Example:
	 *   GameDevConsole.registerCommand("reload", "Reloads the current stage", function(args) {
	 *       PlayState.instance.reloadStage();
	 *       GameDevConsole.success("Stage reloaded.");
	 *   });
	 *
	 * Then type  reload  in the console to invoke it.
	 *
	 * @param name     Command name (case-insensitive, no spaces).
	 * @param desc     Short description shown by 'help'.
	 * @param handler  Function receiving a tokenised args array (args[0] = command name).
	 */
	public static function registerCommand(name:String, desc:String, handler:Array<String>->Void):Void
	{
		_commands.set(name.toLowerCase(), {desc: desc, fn: handler});
	}

	// ══════════════════════════════════════════════════════════════════════
	//  VISIBILITY
	// ══════════════════════════════════════════════════════════════════════

	/** Show the console overlay. */
	public static function show():Void
	{
		if (!initialized) return;
		visible              = true;
		_overlay.visible     = true;
		_dirty               = true;
		_render();

		@:privateAccess
		if (!funkin.system.CursorManager._visible)
		{
			funkin.system.CursorManager.show();
			_cursorWasHidden = true;
		}
	}

	/** Hide the console overlay. */
	public static function hide():Void
	{
		if (!initialized) return;
		visible          = false;
		_overlay.visible = false;

		// Return focus to the game when hiding
		FlxG.stage.focus = null;
		_inputFocused = false;

		@:privateAccess
		if (funkin.system.CursorManager._visible && _cursorWasHidden)
		{
			funkin.system.CursorManager.hide();
			_cursorWasHidden = false;
		}
	}

	/** Toggle the console between visible and hidden. */
	public static function toggle():Void
	{
		if (visible) hide(); else show();
	}

	// ══════════════════════════════════════════════════════════════════════
	//  UPDATE  (call from MusicBeatState.update or Main)
	// ══════════════════════════════════════════════════════════════════════

	/**
	 * Advance the console logic. Must be called every frame.
	 * Cheap when the console is hidden.
	 */
	public static function update():Void
	{
		if (!initialized || !visible) return;
		if (_dirty)
		{
			_render();
			_dirty = false;
		}
	}

	// ══════════════════════════════════════════════════════════════════════
	//  PRIVATE — log internals
	// ══════════════════════════════════════════════════════════════════════

	private static function _addLine(msg:String, col:Int, ?src:String, ?label:String):Void
	{
		var ts   = _timestamp();
		var full = '[$ts] ' + (src != null && src.length > 0 ? '($src) ' : '') + msg;

		_lines.push({text: full, col: col, label: label});
		if (_lines.length > MAX_LINES)
			_lines.shift();

		// Auto-scroll to bottom if the view was already at the bottom
		var maxScroll = Std.int(Math.max(0, _lines.length - _visibleLineCount()));
		if (_scrollPos >= maxScroll - 1)
			_scrollPos = maxScroll;

		_dirty = true;
		if (visible) _render();
	}

	private static function _render():Void
	{
		if (_logField == null) return;

		var visCount = _visibleLineCount();
		var start    = Std.int(Math.max(0, Math.min(_scrollPos, _lines.length - visCount)));
		var end      = Std.int(Math.min(start + visCount + 2, _lines.length));

		var sb = new StringBuf();
		for (i in start...end)
		{
			var entry   = _lines[i];
			var hex     = StringTools.hex(entry.col & 0xFFFFFF, 6);
			var escaped = _escapeHtml(entry.text);

			if (entry.label != null && entry.label.length > 0)
			{
				// Left-side label: "ERROR | message"
				// The label is right-padded to 6 chars so the pipe column stays fixed.
				var lbl    = StringTools.rpad(entry.label, " ", 6);
				var dimHex = StringTools.hex(COL_DIM & 0xFFFFFF, 6);
				sb.add('<font color="#$hex"><b>$lbl</b></font><font color="#$dimHex"> │ </font><font color="#$hex">$escaped</font><br/>');
			}
			else
			{
				// Plain trace — no label, indented to match the label column width
				var dimHex = StringTools.hex(COL_DIM & 0xFFFFFF, 6);
				sb.add('<font color="#$dimHex">       │ </font><font color="#$hex">$escaped</font><br/>');
			}
		}

		_logField.htmlText = sb.toString();

		_drawBg(start, end);
		_titleField.text = _buildTitle();
	}

	// ══════════════════════════════════════════════════════════════════════
	//  PRIVATE — command execution
	// ══════════════════════════════════════════════════════════════════════

	private static function _executeInput():Void
	{
		var raw = StringTools.trim(_inputField.text);
		_inputField.text = "";

		if (raw.length == 0) return;

		// Push to history
		if (_history.length == 0 || _history[_history.length - 1] != raw)
		{
			_history.push(raw);
			if (_history.length > MAX_HISTORY)
				_history.shift();
		}
		_histIdx = -1;
		_histBuf = "";

		// Echo the command
		_addLine("> " + raw, COL_CMD);

		// Tokenise
		var tokens = raw.split(" ");
		var cmd    = tokens[0].toLowerCase();

		if (_commands.exists(cmd))
		{
			try
			{
				_commands.get(cmd).fn(tokens);
			}
			catch (e:Dynamic)
			{
				_addLine("Command threw: " + Std.string(e), COL_ERROR, null, "ERROR");
			}
		}
		else
		{
			_addLine('Unknown command "${cmd}". Type help for a list.', COL_WARN, null, "WARN");
		}
	}

	private static function _registerBuiltins():Void
	{
		registerCommand("help", "List all available commands.", function(args) {
			_addLine("── Available commands ──────────────────────────", COL_TITLE);
			for (key in _commands.keys())
			{
				var entry = _commands.get(key);
				_addLine('  ' + StringTools.rpad(key.toUpperCase(), " ", 12) + ' ' + entry.desc, COL_TRACE);
			}
		});

		registerCommand("clear", "Clear the console log.", function(args) {
			clear();
		});

		registerCommand("echo", "Echo the remaining arguments as a log entry.", function(args) {
			var msg = args.slice(1).join(" ");
			_addLine(msg, COL_TRACE);
		});

		registerCommand("quit", "Hide the console.", function(args) {
			hide();
		});

		registerCommand("fps", "Display current FPS.", function(args) {
			_addLine("FPS: " + Math.round(FlxG.elapsed > 0 ? 1.0 / FlxG.elapsed : 0), COL_SUCCESS);
		});

		registerCommand("state", "Print the current FlxG state class name.", function(args) {
			_addLine("Current state: " + Type.getClassName(Type.getClass(FlxG.state)), COL_SUCCESS);
		});

		registerCommand("gc", "Force a Haxe garbage collection pass.", function(args) {
			openfl.system.System.gc();
			_addLine("GC pass requested.", COL_SUCCESS);
		});
	}

	// ══════════════════════════════════════════════════════════════════════
	//  PRIVATE — drawing helpers
	// ══════════════════════════════════════════════════════════════════════

	private static function _drawBg(?scrollStart:Int = 0, ?scrollEnd:Int = 0):Void
	{
		if (_bg == null) return;
		var g:Graphics = _bg.graphics;
		g.clear();

		// Main background
		g.beginFill(COL_BG, BG_ALPHA);
		g.drawRoundRect(0, 0, CONSOLE_W, CONSOLE_H, 8, 8);
		g.endFill();

		// Outer border
		g.lineStyle(1, COL_BORDER, 0.9);
		g.drawRoundRect(0, 0, CONSOLE_W, CONSOLE_H, 8, 8);
		g.lineStyle(0);

		// Header background strip
		g.beginFill(COL_HEADER_BG, 1.0);
		g.drawRect(1, 1, CONSOLE_W - 2, HEADER_H + 2);
		g.endFill();

		// Header separator
		g.beginFill(COL_BORDER, 0.7);
		g.drawRect(0, HEADER_H + 2, CONSOLE_W, 1);
		g.endFill();

		// Input area separator
		g.beginFill(COL_BORDER, 0.5);
		g.drawRect(0, CONSOLE_H - INPUT_H - 4, CONSOLE_W, 1);
		g.endFill();

		// Scrollbar track
		var trackX = CONSOLE_W - SCROLLBAR_W - 2;
		g.beginFill(COL_BG, 1.0);
		g.drawRoundRect(trackX, HEADER_H + 4, SCROLLBAR_W, LOG_AREA_H, 3, 3);
		g.endFill();

		// Scrollbar thumb
		if (_lines.length > 0)
		{
			var visCount  = _visibleLineCount();
			var totalLines = _lines.length;
			var thumbH    = Std.int(Math.max(10, LOG_AREA_H * visCount / totalLines));
			var maxOff    = Std.int(Math.max(1, totalLines - visCount));
			var thumbY    = HEADER_H + 4 + Std.int((LOG_AREA_H - thumbH) * scrollStart / maxOff);

			g.beginFill(COL_SCROLL, 0.8);
			g.drawRoundRect(trackX, thumbY, SCROLLBAR_W, thumbH, 3, 3);
			g.endFill();
		}
	}

	private static function _drawInputBg():Void
	{
		if (_inputBg == null) return;
		var g:Graphics = _inputBg.graphics;
		g.clear();

		// Input field background
		g.beginFill(COL_INPUT_BG, 1.0);
		g.drawRect(0, CONSOLE_H - INPUT_H - 3, CONSOLE_W, INPUT_H + 3);
		g.endFill();

		// Input field inner border
		g.lineStyle(1, COL_INPUT_BD, 0.6);
		g.drawRect(PADDING - 1, CONSOLE_H - INPUT_H - 2, CONSOLE_W - PADDING * 2 + 2, INPUT_H);
		g.lineStyle(0);
	}

	private static function _makeTextField(x:Float, y:Float, w:Float, h:Float):TextField
	{
		var tf              = new TextField();
		tf.x                = x;
		tf.y                = y;
		tf.width            = w;
		tf.height           = h;
		tf.selectable       = false;
		tf.mouseEnabled     = false;
		tf.embedFonts       = false;
		tf.defaultTextFormat = new TextFormat("_typewriter", FONT_SIZE, 0xFFFFFFFF);
		return tf;
	}

	private static function _buildTitle():String
	{
		return '[ DEV CONSOLE ]   ${_lines.length} entries   [F4 toggle]  [F6 clear]  [help for commands]';
	}

	// ══════════════════════════════════════════════════════════════════════
	//  PRIVATE — utility
	// ══════════════════════════════════════════════════════════════════════

	private static function _visibleLineCount():Int
	{
		return Std.int(LOG_AREA_H / (FONT_SIZE + 3));
	}

	private static function _timestamp():String
	{
		var d = Date.now();
		return '${_p2(d.getHours())}:${_p2(d.getMinutes())}:${_p2(d.getSeconds())}';
	}

	private static inline function _p2(n:Int):String
		return n < 10 ? '0$n' : '$n';

	/**
	 * Heuristic color selection for intercepted trace() messages.
	 * Explicit calls to warn/error/etc bypass this.
	 */
	private static function _colorForMessage(msg:String):Int
	{
		var lower = msg.toLowerCase();
		if (lower.indexOf("crash")     >= 0 || lower.indexOf("fatal") >= 0)                      return COL_CRASH;
		if (lower.indexOf("error")     >= 0 || lower.indexOf("exception") >= 0)                  return COL_ERROR;
		if (lower.indexOf("warn")      >= 0)                                                         return COL_WARN;
		if (lower.indexOf("ok") >= 0 || lower.indexOf("ready") >= 0)                                 return COL_SUCCESS;
		if (lower.indexOf("not found") >= 0 || lower.indexOf("missing") >= 0)                        return COL_WARN;
		if (lower.indexOf("script")    >= 0)                                                      return COL_SCRIPT;
		return COL_TRACE;
	}

	/**
	 * Try to extract line/column numbers embedded inside an interpreter error
	 * message string. HScript and other Haxe scripting libs often append
	 * position info in various formats:
	 *
	 *   "Unexpected , at line 7"
	 *   "myScript.hx:14: Unknown identifier"
	 *   "Parse error (line 3, col 12)"
	 *   "SyntaxError at 5:8"
	 *
	 * Updates `line` and `col` in-place only when the current values are -1
	 * (i.e. the caller didn't already know the position).
	 */
	private static function _parsePositionFromMessage(msg:String, line:Int, col:Int):Void
	{
		// Nothing to do if caller already provided both values
		if (line >= 0 && col >= 0) return;

		var patterns:Array<EReg> = [
			// "at line 7"  /  "line 7, col 12"
			~/\bline\s+(\d+)(?:[,\s]+col(?:umn)?\s+(\d+))?/i,
			// "myfile.hx:14:8"  or  "myfile.hx:14:"
			~/:(\d+):(\d+)/,
			~/:(\d+)/,
			// "at 5:8"
			~/\bat\s+(\d+):(\d+)/i,
			// "SyntaxError at 5"
			~/\bat\s+(\d+)/i,
			// "(line 3)"
			~/\(line\s+(\d+)\)/i,
		];

		for (r in patterns)
		{
			if (r.match(msg))
			{
				if (line < 0)
				{
					var l = Std.parseInt(r.matched(1));
					if (l != null && l > 0) line = l;
				}
				try {
					if (col < 0)
					{
						var c = Std.parseInt(r.matched(2));
						if (c != null && c >= 0) col = c;
					}
				} catch (_) {}
				break;
			}
		}
	}

	private static function _escapeHtml(s:String):String
	{
		s = StringTools.replace(s, "&", "&amp;");
		s = StringTools.replace(s, "<", "&lt;");
		s = StringTools.replace(s, ">", "&gt;");
		return s;
	}

	// ══════════════════════════════════════════════════════════════════════
	//  PRIVATE — event handlers
	// ══════════════════════════════════════════════════════════════════════

	private static function _onKeyDown(e:KeyboardEvent):Void
	{
		switch (e.keyCode)
		{
			// ── Global shortcuts (work regardless of input focus) ─────────
			case Keyboard.F4:
				toggle();

			case Keyboard.F6:
				if (visible) clear();

			// ── Shortcuts while console is visible ───────────────────────
			case Keyboard.ESCAPE:
				if (visible)
				{
					if (_inputFocused)
					{
						FlxG.stage.focus = null;
						_inputFocused = false;
					}
					else
					{
						hide();
					}
				}

			case Keyboard.ENTER, Keyboard.NUMPAD_ENTER:
				if (visible && _inputFocused)
					_executeInput();

			// ── History navigation ───────────────────────────────────────
			case Keyboard.UP:
				if (visible && _inputFocused && _history.length > 0)
				{
					if (_histIdx < 0)
					{
						_histBuf = _inputField.text;
						_histIdx = _history.length - 1;
					}
					else if (_histIdx > 0)
					{
						_histIdx--;
					}
					_inputField.text = _history[_histIdx];
					// Move caret to end
					_inputField.setSelection(_inputField.text.length, _inputField.text.length);
					e.stopImmediatePropagation();
				}
				else if (visible && !_inputFocused)
				{
					// Scroll log up
					_scrollPos = Std.int(Math.max(0, _scrollPos - 3));
					_dirty = true;
				}

			case Keyboard.DOWN:
				if (visible && _inputFocused && _histIdx >= 0)
				{
					_histIdx++;
					if (_histIdx >= _history.length)
					{
						_histIdx         = -1;
						_inputField.text = _histBuf;
					}
					else
					{
						_inputField.text = _history[_histIdx];
					}
					_inputField.setSelection(_inputField.text.length, _inputField.text.length);
					e.stopImmediatePropagation();
				}
				else if (visible && !_inputFocused)
				{
					var maxScroll = Std.int(Math.max(0, _lines.length - _visibleLineCount()));
					_scrollPos = Std.int(Math.min(maxScroll, _scrollPos + 3));
					_dirty = true;
				}

			// ── Click-to-focus shortcut: any printable key while visible ─
			default:
				if (visible && !_inputFocused && e.charCode >= 32)
				{
					FlxG.stage.focus = _inputField;
					_inputFocused = true;
				}
		}
	}

	private static function _onMouseWheel(e:openfl.events.MouseEvent):Void
	{
		if (!visible) return;
		#if !flash
		var delta     = Std.int(e.delta) * 3;
		var maxScroll = Std.int(Math.max(0, _lines.length - _visibleLineCount()));
		_scrollPos    = Std.int(Math.max(0, Math.min(_scrollPos - delta, maxScroll)));
		_dirty        = true;
		_render();
		_dirty = false;
		#end
	}

	/**
	 * Capture any UncaughtErrorEvent thrown by OpenFL / HaxeFlixel.
	 * Displays the error message and stack trace (when available) in the console.
	 */
	private static function _onUncaughtError(e:openfl.events.UncaughtErrorEvent):Void
	{
		var errObj = e.error;
		var msg    = Std.string(errObj);

		// Try to extract a stack trace if the error is an actual exception
		var stack:String = null;
		try
		{
			#if cpp
			if (Std.isOfType(errObj, haxe.Exception))
				stack = cast(errObj, haxe.Exception).stack.toString();
			#elseif js
			var errJs:js.lib.Error = cast errObj;
			if (errJs != null && errJs.stack != null)
				stack = errJs.stack;
			#end
		}
		catch (_) { /* stack trace unavailable */ }

		crash(msg, stack);
	}
}
