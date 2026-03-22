package funkin.debug.charting;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import funkin.data.Song.SwagSong;

using StringTools;

// ============================================================================
//  ToolsPanel — side tools panel that doesn't interact with the grid.
//
//  Features:
//    · Se abre/cierra con toolsPanel.toggle() (llamado desde toolbar)
//    · Consumes clicks and mouse scroll when open
//    · Has its own internal scroll (mouse wheel without affecting the grid)
//    · Secciones: PREVIEW (oponente, jugador, GF), OPCIONES (snap, hitsound…)
//
//  Uso en ChartingState:
//    toolsPanel = new ToolsPanel(this, _song, previewPanel, camHUD);
//    add(toolsPanel);
//    // abrir: toolsPanel.toggle();
// ============================================================================
class ToolsPanel extends FlxGroup
{
	// ── Layout ───────────────────────────────────────────────────────────────
	static inline var PANEL_W:Int = 240;
	static inline var PANEL_H:Int = 400; // altura visible del panel
	static inline var TOP_Y:Int = 80; // debajo de la toolbar
	static inline var TITLE_H:Int = 30;
	static inline var ROW_H:Int = 36;
	static inline var SCROLL_CONTENT_H:Int = 600; // contenido total scrolleable

	// ── Colors ───────────────────────────────────────────────────────────────
	static inline var C_BG:Int = 0xEE0A0A1A;
	static inline var C_TITLE_BAR:Int = 0xFF0D1223;
	static inline var C_BORDER:Int = 0xFF1A2A3A;
	static inline var C_SECTION:Int = 0xFF111830;
	static inline var C_ROW:Int = 0xFF0E1220;
	static inline var C_ROW_HOVER:Int = 0xFF1A2A40;
	static inline var C_TEXT:Int = 0xFFDDDDDD;
	static inline var C_TEXT_DIM:Int = 0xFF778899;
	static inline var C_ACCENT:Int = 0xFFFFAA00;
	static inline var C_BTN_ON:Int = 0xFF00D9FF;
	static inline var C_BTN_OFF:Int = 0xFF334455;
	static inline var C_CLOSE:Int = 0xFF3A0A0A;

	// ── State ─────────────────────────────────────────────────────────────────
	public var isOpen:Bool = false;

	var parent:ChartingState;
	var _song:SwagSong;
	var previewPanel:PreviewPanel;
	var camHUD:FlxCamera;

	// Position X of the panel (animada to the abrir/cerrar)
	var _panelX:Float;
	var _targetX:Float;
	var _panelY:Float = TOP_Y;

	// Scroll interno del panel
	var _scrollY:Float = 0;
	var _maxScrollY:Float = 0;

	// ── Sprites ───────────────────────────────────────────────────────────────
	var _bg:FlxSprite;
	var _border:FlxSprite;
	var _titleBar:FlxSprite;
	var _titleTxt:FlxText;
	var _closeBtnBg:FlxSprite;
	var _closeBtnTxt:FlxText;

	// Rows (visibles)
	var _rows:Array<PanelRow> = [];

	// Mask sprite (hides contenido outside of the area of the panel)
	// Note: FlxG no tiene a ClipRect native easy, usamos a overlay semi-transparente
	// in the top part/inferior of the area of contenido.
	// ── Constructor ───────────────────────────────────────────────────────────
	public function new(parent:ChartingState, song:SwagSong, preview:PreviewPanel, camHUD:FlxCamera)
	{
		super();
		this.parent = parent;
		this._song = song;
		this.previewPanel = preview;
		this.camHUD = camHUD;

		// Panel empieza fuera de pantalla a la derecha
		_panelX = FlxG.width + 10;
		_targetX = FlxG.width + 10;
		_maxScrollY = Math.max(0, SCROLL_CONTENT_H - PANEL_H + TITLE_H + 8);

		_buildPanel();
	}

	// ── Build ─────────────────────────────────────────────────────────────────
	function _buildPanel():Void
	{
		// Fondo
		_border = _spr(_panelX - 1, _panelY - 1, PANEL_W + 2, PANEL_H + 2, C_BORDER);
		_bg = _spr(_panelX, _panelY, PANEL_W, PANEL_H, C_BG);

		// Bar of title
		_titleBar = _spr(_panelX, _panelY, PANEL_W, TITLE_H, C_TITLE_BAR);

		// Line of acento in the parte superior
		var accentLine = _spr(_panelX, _panelY, PANEL_W, 3, C_ACCENT);

		// Title
		_titleTxt = _txt(_panelX + 10, _panelY + 8, PANEL_W - 50, "TOOLS", 12);
		_titleTxt.color = C_ACCENT;

		// Button cerrar [X]
		_closeBtnBg = _spr(_panelX + PANEL_W - 28, _panelY + 5, 22, 20, C_CLOSE);
		_closeBtnTxt = _txt(_panelX + PANEL_W - 28, _panelY + 6, 22, "X", 11);
		_closeBtnTxt.color = 0xFFFF4455;

		// Edge inferior of the title
		var titleBorder = _spr(_panelX, _panelY + TITLE_H, PANEL_W, 1, 0xFF223344);

		// ── Section PREVIEW of characters ──────────────────────────────────
		_addSectionHeader("CHARACTER PREVIEW");

		_addPreviewRow(0, "Opponent Preview");
		_addPreviewRow(1, "Player Preview");
		_addPreviewRow(2, "GF Preview");

		// ── Section options ───────────────────────────────────────────────
		_addSectionHeader("OPTIONS");

		_addToggleRow("Hitsounds", "T", _getHitsounds, _setHitsounds);
		_addToggleRow("Metronome", "M", _getMetronome, _setMetronome);
		_addToggleRow("Waveform", "BTN", _getWaveform, _setWaveform);

		// ── Section SNAP ───────────────────────────────────────────────────
		_addSectionHeader("NOTE SNAP");

		_addSnapRow();

		// ── Clip superior/inferior para "enmascarar" el scroll ─────────────
		// A sprite solid above of the contenido (below of the title bar)
		var clipTop = _spr(_panelX, _panelY, PANEL_W, TITLE_H + 1, C_BG);
		clipTop.alpha = 0; // transparente — the title already covers this area
		// Borde inferior del panel (tapa la zona fuera del clip)
		var clipBot = _spr(_panelX, _panelY + PANEL_H - 4, PANEL_W, 4, C_BG);
		clipBot.alpha = 0.95;

		// Mantener visible=false hasta que se abra
		_setVisible(false);
	}

	// ── Row builders ──────────────────────────────────────────────────────────
	function _rowBaseY():Float
	{
		return _panelY + TITLE_H + 4 + (_rows.length * ROW_H) - _scrollY;
	}

	function _addSectionHeader(label:String):Void
	{
		var y = _rowBaseY();
		var bg = _spr(_panelX, y, PANEL_W, 20, C_SECTION);
		var txt = _txt(_panelX + 8, y + 3, PANEL_W - 16, label, 9);
		txt.color = C_TEXT_DIM;
		var row = new PanelRow(bg, txt, null, null, 0);
		row.baseY = y;
		_rows.push(row);
	}

	function _addPreviewRow(charType:Int, label:String):Void
	{
		var y = _rowBaseY();
		var rowBg = _spr(_panelX, y, PANEL_W, ROW_H - 2, C_ROW);

		var lbl = _txt(_panelX + 10, y + 10, PANEL_W - 80, label, 10);

		var btnW = 60;
		var btnBg = _spr(_panelX + PANEL_W - btnW - 8, y + 6, btnW, ROW_H - 14, C_BTN_ON);
		var btnTxt = _txt(_panelX + PANEL_W - btnW - 8, y + 7, btnW, "SHOW", 9);
		btnTxt.color = 0xFF001A2A;

		var row = new PanelRow(rowBg, lbl, btnBg, btnTxt, charType);
		row.baseY = y;
		row.isPreview = true;
		row.charType = charType;
		row.active = false; // windows start closed
		_rows.push(row);
	}

	function _addToggleRow(label:String, key:String, getter:Void->Bool, setter:Bool->Void):Void
	{
		var y = _rowBaseY();
		var rowBg = _spr(_panelX, y, PANEL_W, ROW_H - 2, C_ROW);
		var keyLbl = _txt(_panelX + PANEL_W - 32, y + 10, 28, key, 8);
		keyLbl.color = C_TEXT_DIM;
		var lbl = _txt(_panelX + 10, y + 10, PANEL_W - 50, label, 10);

		var btnW = 40;
		var state = getter();
		var btnBg = _spr(_panelX + PANEL_W - btnW - 8, y + 6, btnW, ROW_H - 14, state ? C_BTN_ON : C_BTN_OFF);
		var btnTxt = _txt(_panelX + PANEL_W - btnW - 8, y + 7, btnW, state ? "ON" : "OFF", 9);
		btnTxt.color = state ? 0xFF001A2A : C_TEXT_DIM;

		var row = new PanelRow(rowBg, lbl, btnBg, btnTxt, 0);
		row.baseY = y;
		row.isToggle = true;
		row.active = state;
		row.getter = getter;
		row.setter = setter;
		_rows.push(row);
	}

	function _addSnapRow():Void
	{
		var y = _rowBaseY();
		var rowBg = _spr(_panelX, y, PANEL_W, ROW_H - 2, C_ROW);
		var lbl = _txt(_panelX + 10, y + 10, 80, "Snap:", 10);

		// Cuatro mini-botones de snap
		var snaps = [16, 32, 48, 64];
		var labels = ["1/4", "1/8", "1/12", "1/16"];
		var btnW = 42;
		var startX = _panelX + 60;
		for (i in 0...snaps.length)
		{
			var bx = startX + i * (btnW + 2);
			var active = (snaps[i] == parent.currentSnap);
			var b = _spr(bx, y + 6, btnW, ROW_H - 14, active ? C_BTN_ON : C_BTN_OFF);
			var t = _txt(bx, y + 7, btnW, labels[i], 8);
			t.color = active ? 0xFF001A2A : C_TEXT;
			var snapVal = snaps[i];
			var row = new PanelRow(b, t, null, null, snapVal);
			row.baseY = y;
			row.isSnap = true;
			row.active = active;
			_rows.push(row);
		}
	}

	// ── Getters / setters for toggles ─────────────────────────────────────────
	function _getHitsounds():Bool
		return parent.hitsoundsEnabled;

	function _setHitsounds(v:Bool):Void
	{
		parent.hitsoundsEnabled = v;
		parent.showMessage(v ? "Hitsounds ON" : "Hitsounds OFF", 0xFF00D9FF);
	}

	function _getMetronome():Bool
		return parent.metronomeEnabled;

	function _setMetronome(v:Bool):Void
	{
		parent.metronomeEnabled = v;
		parent.showMessage(v ? "Metronome ON" : "Metronome OFF", 0xFF00D9FF);
	}

	function _getWaveform():Bool
		return parent.waveformEnabled;

	function _setWaveform(v:Bool):Void
	{
		parent._toggleWaveform();
	}

	// ── Sprite helpers ────────────────────────────────────────────────────────
	var _allSprites:Array<FlxSprite> = [];
	var _allTexts:Array<FlxText> = [];

	function _spr(x:Float, y:Float, w:Int, h:Int, col:Int):FlxSprite
	{
		var s = new FlxSprite(x, y).makeGraphic(w, h, col);
		s.scrollFactor.set();
		s.cameras = [camHUD];
		add(s);
		_allSprites.push(s);
		return s;
	}

	function _txt(x:Float, y:Float, w:Int, str:String, size:Int):FlxText
	{
		var t = new FlxText(x, y, w, str, size);
		t.setFormat(Paths.font("vcr.ttf"), size, C_TEXT, CENTER);
		t.scrollFactor.set();
		t.cameras = [camHUD];
		add(t);
		_allTexts.push(t);
		return t;
	}

	function _setVisible(v:Bool):Void
	{
		for (s in _allSprites)
			s.visible = v;
		for (t in _allTexts)
			t.visible = v;
	}

	// ── Open / Close ──────────────────────────────────────────────────────────
	public function toggle():Void
	{
		if (isOpen)
			_close();
		else
			_open();
	}

	function _open():Void
	{
		if (isOpen)
			return;
		isOpen = true;
		_setVisible(true);
		_targetX = FlxG.width - PANEL_W - 8;

		// Animar slide-in desde la derecha
		var dx = _targetX - _panelX;
		_movePanel(dx, true);
	}

	function _close():Void
	{
		if (!isOpen)
			return;
		isOpen = false;
		_targetX = FlxG.width + 10;
		var dx = _targetX - _panelX;
		_movePanel(dx, false);
	}

	function _movePanel(dx:Float, show:Bool):Void
	{
		var dur = 0.22;
		var ease = show ? FlxEase.backOut : FlxEase.quintIn;

		for (s in _allSprites)
			FlxTween.tween(s, {x: s.x + dx}, dur, {
				ease: ease,
				onComplete: show ? null : function(_)
				{
					_setVisible(false);
				}
			});
		for (t in _allTexts)
			FlxTween.tween(t, {x: t.x + dx}, dur, {ease: ease});

		_panelX = _targetX;
		// Actualizar x para hit-test
		for (row in _rows)
			row.updateX(dx);
	}

	// ── Scroll ────────────────────────────────────────────────────────────────
	function _applyScroll(delta:Float):Void
	{
		_scrollY = FlxMath.bound(_scrollY + delta, 0, _maxScrollY);
		var contentTop = _panelY + TITLE_H + 4;

		for (row in _rows)
		{
			var newY = row.baseY - _scrollY;
			var visible = (newY >= contentTop - ROW_H && newY <= _panelY + PANEL_H);
			row.setY(newY, visible);
		}
	}

	// ── Hit-test ──────────────────────────────────────────────────────────────
	function _mouseOnPanel():Bool
	{
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		return mx >= _panelX && mx <= _panelX + PANEL_W && my >= _panelY && my <= _panelY + PANEL_H;
	}

	function _mouseOnCloseBtn():Bool
	{
		var bx = _panelX + PANEL_W - 28;
		var by = _panelY + 5;
		return FlxG.mouse.x >= bx && FlxG.mouse.x <= bx + 22 && FlxG.mouse.y >= by && FlxG.mouse.y <= by + 20;
	}

	function _mouseOnRow(row:PanelRow):Bool
	{
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		if (row.bgSpr == null)
			return false;
		return mx >= row.bgSpr.x && mx <= row.bgSpr.x + PANEL_W && my >= row.bgSpr.y && my <= row.bgSpr.y + ROW_H;
	}

	function _mouseOnRowBtn(row:PanelRow):Bool
	{
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		if (row.btnBg == null)
			return false;
		return mx >= row.btnBg.x && mx <= row.btnBg.x + row.btnBg.width && my >= row.btnBg.y && my <= row.btnBg.y + row.btnBg.height;
	}

	// ── Update ────────────────────────────────────────────────────────────────
	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (!isOpen)
			return;

		// Consumir events of the mouse when is over the panel
		if (_mouseOnPanel())
		{
			parent.clickConsumed = true;
			parent.wheelConsumed = true;

			// Scroll del panel con la rueda (no afecta al grid)
			if (FlxG.mouse.wheel != 0)
				_applyScroll(-FlxG.mouse.wheel * ROW_H);

			// Clicks
			if (FlxG.mouse.justPressed)
			{
				if (_mouseOnCloseBtn())
				{
					_close();
					return;
				}

				for (row in _rows)
				{
					if (!_mouseOnRow(row))
						continue;

					if (row.isPreview)
					{
						_handlePreviewRowClick(row);
					}
					else if (row.isToggle && _mouseOnRowBtn(row))
					{
						_handleToggleRowClick(row);
					}
					else if (row.isSnap)
					{
						_handleSnapRowClick(row);
					}
					break;
				}
			}
		}

		// Actualizar estado visual de las filas toggle (pueden cambiar por tecla T/M)
		for (row in _rows)
		{
			if (!row.isToggle || row.getter == null)
				continue;
			var cur = row.getter();
			if (cur != row.active)
			{
				row.active = cur;
				_refreshToggleRow(row);
			}
		}

		// Actualizar snap rows
		for (row in _rows)
		{
			if (!row.isSnap)
				continue;
			var cur = (row.snapValue == parent.currentSnap);
			if (cur != row.active)
			{
				row.active = cur;
				if (row.btnBg != null)
					row.btnBg.color = cur ? C_BTN_ON : C_BTN_OFF;
				if (row.btnTxt != null)
					row.btnTxt.color = cur ? 0xFF001A2A : C_TEXT;
			}
		}
	}

	// ── Row click handlers ────────────────────────────────────────────────────
	function _handlePreviewRowClick(row:PanelRow):Void
	{
		if (previewPanel == null)
			return;

		var win:PreviewPanel.CharacterPreviewWindow = null;
		for (w in previewPanel.windows)
			if (w.charType == row.charType)
			{
				win = w;
				break;
			}

		if (win == null)
			return;

		if (win.isClosed)
			win.openWindow();
		else
			win.closeWindow();

		row.active = !win.isClosed;
		_refreshPreviewRowBtn(row);
	}

	function _handleToggleRowClick(row:PanelRow):Void
	{
		if (row.setter == null)
			return;
		row.active = !row.active;
		row.setter(row.active);
		_refreshToggleRow(row);
	}

	function _handleSnapRowClick(row:PanelRow):Void
	{
		parent.currentSnap = row.snapValue;
		parent.showMessage('Snap: ${_snapName(row.snapValue)}', 0xFF00D9FF);
	}

	function _refreshToggleRow(row:PanelRow):Void
	{
		if (row.btnBg != null)
			row.btnBg.color = row.active ? C_BTN_ON : C_BTN_OFF;
		if (row.btnTxt != null)
		{
			row.btnTxt.text = row.active ? "ON" : "OFF";
			row.btnTxt.color = row.active ? 0xFF001A2A : C_TEXT_DIM;
		}
	}

	function _refreshPreviewRowBtn(row:PanelRow):Void
	{
		if (row.btnBg != null)
			row.btnBg.color = row.active ? C_BTN_ON : C_BTN_OFF;
		if (row.btnTxt != null)
		{
			row.btnTxt.text = row.active ? "SHOW" : "HIDE";
			row.btnTxt.color = row.active ? 0xFF001A2A : C_TEXT_DIM;
		}
	}

	function _snapName(snap:Int):String
	{
		return switch (snap)
		{
			case 16: "1/4";
			case 32: "1/8";
			case 48: "1/12";
			case 64: "1/16";
			default: "1/4";
		};
	}

	// ── Destroy ───────────────────────────────────────────────────────────────
	override public function destroy():Void
	{
		_rows = null;
		super.destroy();
	}
}

// ============================================================================
//  PanelRow — datos de una fila del panel.
// ============================================================================
class PanelRow
{
	public var bgSpr:FlxSprite;
	public var labelTxt:FlxText;
	public var btnBg:FlxSprite;
	public var btnTxt:FlxText;
	public var snapValue:Int;

	public var baseY:Float = 0;
	public var active:Bool = false;

	public var isPreview:Bool = false;
	public var isToggle:Bool = false;
	public var isSnap:Bool = false;
	public var charType:Int = 0;

	public var getter:Void->Bool = null;
	public var setter:Bool->Void = null;

	public function new(bg:FlxSprite, lbl:FlxText, bBg:FlxSprite, bTxt:FlxText, snap:Int)
	{
		bgSpr = bg;
		labelTxt = lbl;
		btnBg = bBg;
		btnTxt = bTxt;
		snapValue = snap;
	}

	public function setY(y:Float, visible:Bool):Void
	{
		var dy = y - (bgSpr != null ? bgSpr.y : y);
		if (bgSpr != null)
		{
			bgSpr.y += dy;
			bgSpr.visible = visible;
		}
		if (labelTxt != null)
		{
			labelTxt.y += dy;
			labelTxt.visible = visible;
		}
		if (btnBg != null)
		{
			btnBg.y += dy;
			btnBg.visible = visible;
		}
		if (btnTxt != null)
		{
			btnTxt.y += dy;
			btnTxt.visible = visible;
		}
	}

	public function updateX(dx:Float):Void
	{
		if (bgSpr != null)
			bgSpr.x += dx;
		if (labelTxt != null)
			labelTxt.x += dx;
		if (btnBg != null)
			btnBg.x += dx;
		if (btnTxt != null)
			btnTxt.x += dx;
	}
}
