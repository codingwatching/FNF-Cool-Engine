package funkin.scripting;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.Lib;

/**
 * ScriptErrorNotifier — Non-blocking in-game popup for script errors.
 *
 * Sits on top of the entire OpenFL display stack so it works in any game
 * state (menus, PlayState, editors, etc.) without interrupting gameplay.
 *
 * Features:
 *  • Queue — multiple errors are shown one at a time; a counter badge
 *    ("2 more…") indicates pending ones.
 *  • Per-error dedup — identical (script + message) pairs are collapsed
 *    so a spammy script doesn't flood the queue.
 *  • Close button [×] and optional keyboard shortcut (Escape / Enter).
 *  • Auto-dismiss after AUTO_DISMISS_MS ms if the player ignores it.
 *  • Works on all platforms (OpenFL Sprite, no native calls → non-blocking).
 *
 * Usage (called automatically by HScriptInstance and ScriptHandler):
 *
 *   ScriptErrorNotifier.notify("myScript.hx", "onUpdate",
 *       "Unknown variable \"foo\"", 42);
 */
class ScriptErrorNotifier
{
	// ── PANEL DIMENSIONS ─────────────────────────────────────────────────────
	private static inline final PANEL_W:Float       = 540;
	private static inline final PANEL_H_BASE:Float  = 220;   // minimum height
	private static inline final PANEL_H_MAX:Float   = 380;   // maximum height
	private static inline final CORNER_R:Float      = 8;
	private static inline final PADDING:Float       = 16;
	private static inline final HEADER_H:Float      = 40;
	private static inline final BTN_SIZE:Float      = 28;

	// ── COLOURS ──────────────────────────────────────────────────────────────
	private static inline final C_BG:Int            = 0xFF1A1A2E;  // dark navy
	private static inline final C_HEADER:Int        = 0xFFB71C1C;  // deep red
	private static inline final C_BORDER:Int        = 0xFFE53935;  // red border
	private static inline final C_TEXT:Int          = 0xFFEEEEEE;
	private static inline final C_TEXT_DIM:Int      = 0xFFAAAAAA;
	private static inline final C_CODE:Int          = 0xFFFFCC00;  // yellow for identifiers
	private static inline final C_BTN_HOVER:Int     = 0xFFFF5252;
	private static inline final C_BADGE:Int         = 0xFFE53935;

	// ── TIMING ───────────────────────────────────────────────────────────────
	/** Auto-dismiss delay in milliseconds (0 = never auto-dismiss). */
	private static inline final AUTO_DISMISS_MS:Int = 12000;

	// ── QUEUE & STATE ─────────────────────────────────────────────────────────
	private static inline final MAX_QUEUE:Int = 15;

	private static var _queue:Array<ErrorEntry>  = [];
	private static var _overlay:Sprite           = null;
	private static var _isShowing:Bool           = false;
	private static var _spawnTime:Float          = 0;
	private static var _ticker:openfl.events.EventDispatcher = null;

	// ── PUBLIC API ────────────────────────────────────────────────────────────

	/**
	 * Show a non-fatal script error popup.
	 *
	 * @param scriptName  Name or path of the script that failed.
	 * @param funcName    Function name where the error occurred ("onUpdate", "loadString", …).
	 * @param message     Human-readable error message.
	 * @param lineNum     Line number in the script (−1 if unknown).
	 */
	public static function notify(scriptName:String, funcName:String, message:String, lineNum:Int = -1):Void
	{
		// Deduplicate: same script + same message → just bump a counter
		for (entry in _queue)
		{
			if (entry.script == scriptName && entry.msg == message)
			{
				entry.count++;
				// Update the badge on the active overlay if it's this entry
				if (_isShowing && _queue.length > 0 && _queue[0] == entry)
					_refreshBadge();
				return;
			}
		}

		if (_queue.length >= MAX_QUEUE)
			return; // silently drop; game is already telling the dev plenty

		_queue.push({
			script : scriptName,
			func   : funcName,
			msg    : message,
			line   : lineNum,
			count  : 1
		});

		if (!_isShowing)
			_showNext();
		else
			_refreshBadge(); // update "N more…" counter on current card
	}

	// ── INTERNAL ──────────────────────────────────────────────────────────────

	private static function _showNext():Void
	{
		if (_queue.length == 0)
		{
			_isShowing = false;
			return;
		}
		_isShowing = true;
		_buildOverlay(_queue[0]);
	}

	private static function _buildOverlay(entry:ErrorEntry):Void
	{
		_destroyOverlay();

		final stage = Lib.current.stage;
		if (stage == null) return;

		// Measure how tall the text will be so the panel grows if needed
		final msgLines  = _countLines(entry.msg, Std.int(PANEL_W - PADDING * 2), 13);
		final panelH    = Math.min(PANEL_H_MAX, PANEL_H_BASE + (msgLines - 3) * 16);

		_overlay = new Sprite();
		_overlay.mouseEnabled  = true;
		_overlay.mouseChildren = true;

		// ── Shadow ────────────────────────────────────────────────────────────
		final shadow = new Shape();
		shadow.graphics.beginFill(0x000000, 0.45);
		_roundRect(shadow.graphics, 4, 4, PANEL_W, panelH, CORNER_R);
		shadow.graphics.endFill();
		_overlay.addChild(shadow);

		// ── Background ───────────────────────────────────────────────────────
		final bg = new Shape();
		bg.graphics.lineStyle(2, C_BORDER, 1);
		bg.graphics.beginFill(C_BG, 0.97);
		_roundRect(bg.graphics, 0, 0, PANEL_W, panelH, CORNER_R);
		bg.graphics.endFill();
		_overlay.addChild(bg);

		// ── Header bar ───────────────────────────────────────────────────────
		final header = new Shape();
		header.graphics.beginFill(C_HEADER, 1);
		_roundRectTop(header.graphics, 0, 0, PANEL_W, HEADER_H, CORNER_R);
		header.graphics.endFill();
		_overlay.addChild(header);

		// Header label
		_addText(_overlay,
			'⚠  Script Error',
			PADDING, 0, PANEL_W - PADDING * 2 - BTN_SIZE - 4, HEADER_H,
			0xFFFFFFFF, 14, true);

		// ── Close button ─────────────────────────────────────────────────────
		final btn = new Sprite();
		btn.graphics.beginFill(C_HEADER, 1);
		_roundRect(btn.graphics, 0, 0, BTN_SIZE, BTN_SIZE, 5);
		btn.graphics.endFill();
		_addText(btn, '×', 0, 2, BTN_SIZE, BTN_SIZE - 2, 0xFFFFFFFF, 18, true);
		btn.x = PANEL_W - BTN_SIZE - 6;
		btn.y = (HEADER_H - BTN_SIZE) / 2;
		btn.buttonMode  = true;
		btn.useHandCursor = true;
		btn.addEventListener(MouseEvent.CLICK,        _onClose);
		btn.addEventListener(MouseEvent.MOUSE_OVER,   function(_) { btn.graphics.clear(); btn.graphics.beginFill(C_BTN_HOVER, 1); _roundRect(btn.graphics, 0, 0, BTN_SIZE, BTN_SIZE, 5); btn.graphics.endFill(); _addText(btn, '×', 0, 2, BTN_SIZE, BTN_SIZE - 2, 0xFFFFFFFF, 18, true); });
		btn.addEventListener(MouseEvent.MOUSE_OUT,    function(_) { btn.graphics.clear(); btn.graphics.beginFill(C_HEADER, 1);    _roundRect(btn.graphics, 0, 0, BTN_SIZE, BTN_SIZE, 5); btn.graphics.endFill(); _addText(btn, '×', 0, 2, BTN_SIZE, BTN_SIZE - 2, 0xFFFFFFFF, 18, true); });
		_overlay.addChild(btn);

		// ── Script name & location ────────────────────────────────────────────
		var y = HEADER_H + PADDING;

		final loc = entry.line > 0 ? '${entry.script}  :  line ${entry.line}' : entry.script;
		_addText(_overlay, loc, PADDING, y, PANEL_W - PADDING * 2, 20, C_CODE, 12, true);
		y += 20;

		final fn = 'in  ${entry.func}()';
		_addText(_overlay, fn, PADDING, y, PANEL_W - PADDING * 2, 18, C_TEXT_DIM, 11, false);
		y += 22;

		// Divider
		final div = new Shape();
		div.graphics.lineStyle(1, C_BORDER, 0.3);
		div.graphics.moveTo(PADDING, 0);
		div.graphics.lineTo(PANEL_W - PADDING, 0);
		div.y = y;
		_overlay.addChild(div);
		y += 8;

		// ── Error message (scrollable TextField) ──────────────────────────────
		final msgH = panelH - y - PADDING - (entry.count > 1 ? 22 : 0);
		final tf = new TextField();
		tf.defaultTextFormat = new TextFormat('_sans', 13, C_TEXT, false, false, false, null, null, 'left');
		tf.text        = entry.msg;
		tf.multiline   = true;
		tf.wordWrap    = true;
		tf.selectable  = true;
		tf.type        = TextFieldType.DYNAMIC;
		tf.border      = false;
		tf.x = PADDING;
		tf.y = y;
		tf.width  = PANEL_W - PADDING * 2;
		tf.height = msgH;
		tf.scrollV = 1;
		_overlay.addChild(tf);
		y += msgH + 4;

		// ── "N more errors…" badge ────────────────────────────────────────────
		if (_queue.length > 1)
		{
			final badge = new Shape();
			badge.name = 'badge';
			badge.graphics.beginFill(C_BADGE, 1);
			badge.graphics.drawRoundRect(0, 0, 120, 18, 9);
			badge.graphics.endFill();
			badge.x = PANEL_W - 120 - PADDING;
			badge.y = panelH - 20;
			_overlay.addChild(badge);

			final badgeTf = new TextField();
			badgeTf.name = 'badgeTf';
			badgeTf.defaultTextFormat = new TextFormat('_sans', 11, 0xFFFFFF, true);
			badgeTf.text     = '${_queue.length - 1} more error${_queue.length > 2 ? "s" : ""}…';
			badgeTf.selectable = false;
			badgeTf.width    = 120;
			badgeTf.x        = badge.x;
			badgeTf.y        = badge.y + 1;
			_overlay.addChild(badgeTf);
		}

		// ── Position: top-right corner, 12px inset ────────────────────────────
		final sw = stage.stageWidth;
		_overlay.x = sw - PANEL_W - 12;
		_overlay.y = 12;

		// ── Keyboard listener (Escape or Enter to close) ──────────────────────
		stage.addEventListener(openfl.events.KeyboardEvent.KEY_DOWN, _onKey, false, 999);

		// ── Auto-dismiss ticker ───────────────────────────────────────────────
		_spawnTime = openfl.Lib.getTimer();
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _onFrame, false, 999);

		stage.addChild(_overlay);
	}

	private static function _refreshBadge():Void
	{
		if (_overlay == null) return;
		final badge   = _overlay.getChildByName('badge');
		final badgeTf = _overlay.getChildByName('badgeTf');
		final pending = _queue.length - 1;
		if (pending <= 0)
		{
			if (badge != null)   _overlay.removeChild(badge);
			if (badgeTf != null) _overlay.removeChild(badgeTf);
			return;
		}
		if (badgeTf != null)
			cast(badgeTf, TextField).text = '$pending more error${pending > 1 ? "s" : ""}…';
	}

	private static function _onClose(?_:MouseEvent):Void
	{
		_queue.shift();
		_destroyOverlay();
		_isShowing = false;
		_showNext();
	}

	private static function _onKey(e:openfl.events.KeyboardEvent):Void
	{
		// Escape (27) or Enter (13) dismiss the current error
		if (e.keyCode == 27 || e.keyCode == 13)
			_onClose(null);
	}

	private static function _onFrame(_:openfl.events.Event):Void
	{
		if (AUTO_DISMISS_MS > 0 && (openfl.Lib.getTimer() - _spawnTime) >= AUTO_DISMISS_MS)
			_onClose(null);
	}

	private static function _destroyOverlay():Void
	{
		if (_overlay == null) return;
		final stage = Lib.current.stage;
		if (stage != null)
		{
			stage.removeEventListener(openfl.events.Event.ENTER_FRAME,          _onFrame);
			stage.removeEventListener(openfl.events.KeyboardEvent.KEY_DOWN,     _onKey);
			if (_overlay.parent != null)
				_overlay.parent.removeChild(_overlay);
		}
		_overlay = null;
	}

	// ── DRAWING HELPERS ───────────────────────────────────────────────────────

	private static function _addText(parent:Sprite, text:String, x:Float, y:Float,
	                                  w:Float, h:Float, color:Int, size:Int, bold:Bool):TextField
	{
		final tf = new TextField();
		tf.defaultTextFormat = new TextFormat('_sans', size, color, bold);
		tf.text       = text;
		tf.selectable = false;
		tf.multiline  = false;
		tf.wordWrap   = false;
		tf.width      = w;
		tf.height     = h;
		tf.x          = x;
		tf.y          = y;
		parent.addChild(tf);
		return tf;
	}

	private static function _roundRect(g:openfl.display.Graphics, x:Float, y:Float,
	                                    w:Float, h:Float, r:Float):Void
	{
		g.drawRoundRect(x, y, w, h, r * 2, r * 2);
	}

	/** Round rect with rounded top corners only (for header bar). */
	private static function _roundRectTop(g:openfl.display.Graphics, x:Float, y:Float,
	                                       w:Float, h:Float, r:Float):Void
	{
		// Manual path: top-left arc, top-right arc, straight bottom corners
		g.moveTo(x + r, y);
		g.lineTo(x + w - r, y);
		g.curveTo(x + w, y,       x + w, y + r);
		g.lineTo(x + w, y + h);
		g.lineTo(x,     y + h);
		g.lineTo(x,     y + r);
		g.curveTo(x,    y,        x + r, y);
	}

	/** Rough line-count estimate for dynamic panel height calculation. */
	private static function _countLines(text:String, widthPx:Int, fontSize:Int):Int
	{
		final charsPerLine = Std.int(widthPx / (fontSize * 0.6));
		if (charsPerLine <= 0) return 3;
		var lines = 0;
		for (para in text.split('\n'))
			lines += Std.int(Math.ceil(para.length / charsPerLine)) + 1;
		return Std.int(Math.max(3, lines));
	}
}

// ── Error entry typedef ───────────────────────────────────────────────────────

private typedef ErrorEntry =
{
	var script : String;
	var func   : String;
	var msg    : String;
	var line   : Int;
	var count  : Int;
}
