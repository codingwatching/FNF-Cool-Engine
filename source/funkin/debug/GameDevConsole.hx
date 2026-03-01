package funkin.debug;

import flixel.FlxG;
import flixel.FlxBasic;
import flixel.util.FlxColor;
import openfl.display.Sprite;
import openfl.display.Graphics;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;

/**
 * GameDevConsole — Consola visual in-game para modo desarrollador.
 *
 * Muestra traces y errores directamente en pantalla (overlay OpenFL),
 * sin necesidad de abrir una terminal externa.
 *
 * USO:
 *   GameDevConsole.init();           // en Main.hx o MusicBeatState
 *   GameDevConsole.log("Hola");      // log manual
 *   GameDevConsole.warn("Ojo!");     // advertencia (amarillo)
 *   GameDevConsole.error("Fallo!"); // error (rojo)
 *
 * CONTROLES:
 *   F4           → toggle visible/oculto
 *   F5           → limpiar log
 *   Scroll arriba/abajo → desplazar historial
 *
 * INTERCEPTACIÓN AUTOMÁTICA:
 *   Sobreescribe haxe.Log.trace para capturar TODOS los trace() del juego.
 *   Los errores no capturados de OpenFL también se muestran si está activo.
 */
class GameDevConsole
{
	// ─── Config visual ────────────────────────────────────────────────────────
	static inline var CONSOLE_W   : Int   = 560;
	static inline var CONSOLE_H   : Int   = 280;
	static inline var FONT_SIZE   : Int   = 11;
	static inline var MAX_LINES   : Int   = 200;
	static inline var VISIBLE_H   : Int   = 240;
	static inline var PADDING     : Int   = 6;
	static inline var BG_ALPHA    : Float = 0.88;

	// ─── Colores ──────────────────────────────────────────────────────────────
	static inline var COL_BG      : Int = 0xFF0A0A18;
	static inline var COL_BORDER  : Int = 0xFF2233AA;
	static inline var COL_TITLE   : Int = 0xFF4FC3F7;
	static inline var COL_TRACE   : Int = 0xFFCCCCDD;
	static inline var COL_WARN    : Int = 0xFFFFD54F;
	static inline var COL_ERROR   : Int = 0xFFFF5252;
	static inline var COL_SUCCESS : Int = 0xFF69F0AE;
	static inline var COL_DIM     : Int = 0xFF666688;

	// ─── Estado ───────────────────────────────────────────────────────────────
	public static var initialized : Bool = false;
	public static var visible     : Bool = false;

	private static var _overlay   : Sprite;
	private static var _bg        : Sprite;
	private static var _logField  : TextField;
	private static var _titleField: TextField;
	private static var _lines     : Array<{text:String, col:Int}> = [];
	private static var _scrollPos : Int  = 0;
	private static var _dirty     : Bool = false;
	private static var _origTrace : Dynamic;

	private static var mousetrue:Bool = false;

	// ─── INIT ─────────────────────────────────────────────────────────────────

	/**
	 * Inicializa la consola. Llama esto en Main.hx o al entrar al primer estado.
	 * Si ya está inicializada, no hace nada.
	 */
	public static function init():Void
	{
		if (initialized) return;

		_lines = [];
		_scrollPos = 0;

		// ── Contenedor principal ──────────────────────────────────────────────
		_overlay = new Sprite();
		_overlay.x = 8;
		_overlay.y = 8;
		_overlay.visible = false;

		// Fondo
		_bg = new Sprite();
		_overlay.addChild(_bg);
		_drawBg();

		// Campo título / toolbar
		_titleField = _makeTextField(PADDING, PADDING, CONSOLE_W - PADDING * 2, 16);
		_titleField.textColor = COL_TITLE;
		_titleField.text = "▣ DEV CONSOLE  [F4 toggle]  [F5 clean]";
		_overlay.addChild(_titleField);

		// Campo de log scrollable
		_logField = _makeTextField(PADDING, 22, CONSOLE_W - PADDING * 2, VISIBLE_H);
		_logField.multiline = true;
		_logField.wordWrap  = true;
		_overlay.addChild(_logField);

		// Añadir al stage OpenFL (encima de todo, incluido HaxeFlixel)
		FlxG.stage.addChild(_overlay);

		// ── Interceptar haxe.Log.trace ────────────────────────────────────────
		_origTrace = haxe.Log.trace;
		haxe.Log.trace = function(v:Dynamic, ?infos:haxe.PosInfos) {
			// Llamar al handler original (así sigue apareciendo en el log nativo)
			if (_origTrace != null) _origTrace(v, infos);

			var src = (infos != null) ? '${infos.fileName}:${infos.lineNumber}' : '';
			var msg = Std.string(v);
			var col = _colorForMessage(msg);
			_addLine(msg, col, src);
		};

		// ── Escuchar teclado en el stage para toggle ──────────────────────────
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);

		// ── Capturar errores no controlados ───────────────────────────────────
		FlxG.stage.addEventListener(openfl.events.UncaughtErrorEvent.UNCAUGHT_ERROR, _onUncaughtError);

		initialized = true;
		log("[GameDevConsole] INICIALIZED. F4 = toggle, F5 = clean.", COL_SUCCESS);
	}

	// ─── API pública ──────────────────────────────────────────────────────────

	/** Log genérico (blanco/gris) */
	public static function log(msg:String, ?col:Null<Int>):Void
	{
		if (!initialized) return;
		_addLine(msg, col != null ? col : COL_TRACE);
	}

	/** Advertencia (amarillo) */
	public static function warn(msg:String):Void
	{
		if (!initialized) return;
		_addLine("⚠ " + msg, COL_WARN);
	}

	/** Error (rojo) */
	public static function error(msg:String):Void
	{
		if (!initialized) return;
		_addLine("✖ " + msg, COL_ERROR);
		// Auto-mostrar consola al recibir un error
		if (!visible) show();
	}

	/** Éxito / info verde */
	public static function success(msg:String):Void
	{
		if (!initialized) return;
		_addLine("✔ " + msg, COL_SUCCESS);
	}

	/** Vaciar log */
	public static function clear():Void
	{
		if (!initialized) return;
		_lines = [];
		_scrollPos = 0;
		_dirty = true;
		_render();
	}

	/** Mostrar consola */
	public static function show():Void
	{
		if (!initialized) return;
		visible = true;
		_overlay.visible = true;
		_dirty = true;
		_render();
		if (!FlxG.mouse.visible){
			FlxG.mouse.visible = true;
			mousetrue = true;
		}
	}

	/** Ocultar consola */
	public static function hide():Void
	{
		if (!initialized) return;
		visible = false;
		_overlay.visible = false;
		if (FlxG.mouse.visible && mousetrue)
		{
			FlxG.mouse.visible = false;
			mousetrue = false;
		}
	}

	/** Toggle visible/oculto */
	public static function toggle():Void
	{
		if (visible) hide(); else show();
	}

	/**
	 * Actualiza la consola. Llamar desde MusicBeatState.update() (o Main).
	 * Maneja scroll con rueda del ratón cuando está visible.
	 */
	public static function update():Void
	{
		if (!initialized) return;
		if (!visible) return;

		#if !flash
		var wheel = FlxG.mouse.wheel;
		if (wheel != 0)
		{
			_scrollPos = Std.int(Math.max(0, Math.min(_scrollPos - wheel * 2,
			                             Std.int(Math.max(0, _lines.length - _visibleLineCount())))));
			_dirty = true;
		}
		#end

		if (_dirty)
		{
			_render();
			_dirty = false;
		}
	}

	// ─── Internos ─────────────────────────────────────────────────────────────

	private static function _addLine(msg:String, col:Int, ?src:String):Void
	{
		var ts = _timestamp();
		var full = '[$ts] ' + (src != null && src.length > 0 ? '($src) ' : '') + msg;

		// Fragmentar líneas largas para que el TextField las envuelva bien
		_lines.push({text: full, col: col});
		if (_lines.length > MAX_LINES)
			_lines.shift();

		// Auto-scroll al fondo si ya estábamos ahí
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

		// Reconstruir htmlText con colores
		var sb = new StringBuf();
		for (i in start...end)
		{
			var entry = _lines[i];
			var hex   = StringTools.hex(entry.col & 0xFFFFFF, 6);
			var escaped = _escapeHtml(entry.text);
			sb.add('<font color="#$hex">$escaped</font><br/>');
		}

		_logField.htmlText = sb.toString();

		// Scrollbar visual simplificado en el fondo
		_drawBg(start, end);

		// Título con conteo
		_titleField.text = '▣ DEV CONSOLE  ${_lines.length} msgs  [F4 toogle]  [F5 clean]';
	}

	private static function _drawBg(?scrollStart:Int = 0, ?scrollEnd:Int = 0):Void
	{
		if (_bg == null) return;
		var g:Graphics = _bg.graphics;
		g.clear();

		// Fondo principal
		g.beginFill(COL_BG, BG_ALPHA);
		g.drawRoundRect(0, 0, CONSOLE_W, CONSOLE_H, 6, 6);
		g.endFill();

		// Borde
		g.lineStyle(1, COL_BORDER, 0.8);
		g.drawRoundRect(0, 0, CONSOLE_W, CONSOLE_H, 6, 6);
		g.lineStyle(0);

		// Separador título
		g.beginFill(COL_BORDER, 0.4);
		g.drawRect(PADDING, 20, CONSOLE_W - PADDING * 2, 1);
		g.endFill();

		// Scrollbar derecho (si hay contenido)
		if (_lines.length > 0 && scrollEnd > scrollStart)
		{
			var totalLines = _lines.length;
			var visH       = VISIBLE_H - 4;
			var sbH        = Std.int(Math.max(8, visH * visH / (totalLines * FONT_SIZE)));
			var sbY        = 22 + Std.int((visH - sbH) * scrollStart / Math.max(1, totalLines - _visibleLineCount()));

			g.beginFill(COL_BORDER, 0.6);
			g.drawRoundRect(CONSOLE_W - 6, 22 + sbY, 4, sbH, 2, 2);
			g.endFill();
		}
	}

	private static function _makeTextField(x:Float, y:Float, w:Float, h:Float):TextField
	{
		var tf = new TextField();
		tf.x = x; tf.y = y;
		tf.width  = w;
		tf.height = h;
		tf.selectable  = false;
		tf.mouseEnabled= false;
		tf.embedFonts   = false;
		var fmt = new TextFormat("_sans", FONT_SIZE, 0xFFFFFFFF);
		tf.defaultTextFormat = fmt;
		return tf;
	}

	private static function _visibleLineCount():Int
	{
		return Std.int(VISIBLE_H / (FONT_SIZE + 2));
	}

	private static function _timestamp():String
	{
		var d = Date.now();
		return '${_p2(d.getHours())}:${_p2(d.getMinutes())}:${_p2(d.getSeconds())}';
	}

	private static inline function _p2(n:Int):String
		return n < 10 ? '0$n' : '$n';

	private static function _colorForMessage(msg:String):Int
	{
		var lower = msg.toLowerCase();
		if (lower.indexOf("error") >= 0 || lower.indexOf("exception") >= 0 || lower.indexOf("crash") >= 0)
			return COL_ERROR;
		if (lower.indexOf("warn") >= 0 || lower.indexOf("⚠") >= 0)
			return COL_WARN;
		if (lower.indexOf("✔") >= 0 || lower.indexOf("✓") >= 0 || lower.indexOf("ready") >= 0)
			return COL_SUCCESS;
		if (lower.indexOf("not found") >= 0 || lower.indexOf("no encontr") >= 0 || lower.indexOf("missing") >= 0)
			return COL_WARN;
		return COL_TRACE;
	}

	private static function _escapeHtml(s:String):String
	{
		s = StringTools.replace(s, "&", "&amp;");
		s = StringTools.replace(s, "<", "&lt;");
		s = StringTools.replace(s, ">", "&gt;");
		return s;
	}

	// ─── Eventos ──────────────────────────────────────────────────────────────

	private static function _onKeyDown(e:KeyboardEvent):Void
	{
		switch (e.keyCode)
		{
			case Keyboard.F4:
				toggle();
			case Keyboard.F5:
				if (visible) clear();
		}
	}

	private static function _onUncaughtError(e:openfl.events.UncaughtErrorEvent):Void
	{
		var msg:String = "Uncaught error: " + Std.string(e.error);
		error(msg);
	}
}
