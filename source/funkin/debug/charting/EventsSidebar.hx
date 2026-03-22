package funkin.debug.charting;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.group.FlxGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import flixel.addons.ui.*;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import funkin.data.Song.SwagSong;
import funkin.scripting.events.EventInfoSystem;
import funkin.scripting.events.EventInfoSystem.EventParamType;
import funkin.scripting.events.EventInfoSystem.EventParamDef;

typedef ChartEvent =
{
	var stepTime:Float;
	var type:String;
	var value:String;
}

/**
 * Sidebar izquierdo para el sistema de eventos.
 *
 * v3 — New: double click on a pill opens EventStackPopup,
 * that muestra all the events in that step and allows editar/borrar/add.
 */
class EventsSidebar extends FlxGroup
{
	var parent:ChartingState;
	var _song:SwagSong;
	var camGame:FlxCamera;
	var camHUD:FlxCamera;

	var gridX:Float;
	var gridY:Float;
	var gridScrollY:Float = 0;
	var GRID_SIZE:Int = 40;

	var eventSprites:FlxTypedGroup<FlxSprite>;
	var eventLabels:FlxTypedGroup<FlxText>;

	var addEventBtn:FlxSprite;
	var addEventBtnText:FlxText;
	var hoverBeatY:Float = -1;

	public var eventPopup:EventPopup;
	var stackPopup:EventStackPopup;

	// Drag-to-move
	var _dragging:Bool        = false;
	var _dragEvt:ChartEvent   = null;
	var _dragSprite:FlxSprite = null;
	var _dragLabel:FlxText    = null;
	var _dragOffsetY:Float    = 0;

	// Click vs Drag
	var _potentialClickEvt:ChartEvent = null;
	var _clickStartX:Float = 0;
	var _clickStartY:Float = 0;
	static inline var DRAG_THRESHOLD:Float = 5.0;

	// Ctrl+Z
	var _evtHistory:Array<String> = [];
	var _evtHistIdx:Int = -1;
	static inline var MAX_EVT_HIST:Int = 50;

	static inline var SIDEBAR_WIDTH:Int = 130;
	static inline var EVENT_H:Int       = 28;  // 2 lines of text
	static inline var GRID_TOP:Int      = 118;

	public function new(parent:ChartingState, song:SwagSong, camGame:FlxCamera, camHUD:FlxCamera, gridX:Float, gridY:Float)
	{
		super();
		this.parent  = parent;
		this._song   = song;
		this.camGame = camGame;
		this.camHUD  = camHUD;
		this.gridX   = gridX;
		this.gridY   = gridY;

		funkin.scripting.events.EventRegistry.reload();

		if (_song.events == null) _song.events = [];
		_evtHistory.push(haxe.Json.stringify(_song.events));
		_evtHistIdx = 0;

		eventSprites = new FlxTypedGroup<FlxSprite>();
		eventLabels  = new FlxTypedGroup<FlxText>();
		add(eventSprites);
		add(eventLabels);

		_buildAddButton();

		// El EventPopup va primero para que stackPopup renderice encima
		eventPopup = new EventPopup(parent, song, camHUD, this);
		add(eventPopup);

		stackPopup = new EventStackPopup(parent, song, camHUD, this);
		add(stackPopup);

		refreshEvents();
	}

	function _buildAddButton():Void
	{
		addEventBtn = new FlxSprite(0, 0).makeGraphic(28, 28, 0xFF1A3A2A);
		addEventBtn.scrollFactor.set();
		addEventBtn.cameras = [camHUD];
		addEventBtn.visible = false;
		add(addEventBtn);

		addEventBtnText = new FlxText(0, 0, 28, "+", 16);
		addEventBtnText.setFormat(Paths.font("vcr.ttf"), 16, 0xFF00FF88, CENTER);
		addEventBtnText.scrollFactor.set();
		addEventBtnText.cameras = [camHUD];
		addEventBtnText.visible = false;
		add(addEventBtnText);

		_dragSprite = new FlxSprite().makeGraphic(SIDEBAR_WIDTH, EVENT_H, 0xFFAAAAAA);
		_dragSprite.scrollFactor.set();
		_dragSprite.cameras = [camHUD];
		_dragSprite.visible = false;
		_dragSprite.alpha   = 0.75;
		add(_dragSprite);

		_dragLabel = new FlxText(0, 0, SIDEBAR_WIDTH - 4, "", 9);
		_dragLabel.setFormat(Paths.font("vcr.ttf"), 9, 0xFF000000, LEFT);
		_dragLabel.scrollFactor.set();
		_dragLabel.cameras = [camHUD];
		_dragLabel.visible = false;
		add(_dragLabel);
	}

	public function setScrollY(scrollY:Float, currentGridY:Float):Void
	{
		this.gridScrollY = scrollY;
		refreshEvents();
	}

	public function isAnyPopupOpen():Bool
		return (eventPopup != null && eventPopup.isOpen)
		    || (stackPopup != null && stackPopup.isOpen);

	public function refreshEvents():Void
	{
		eventSprites.clear();
		eventLabels.clear();

		if (_song.events == null) return;

		// FIX: rastrear how many events there is in each step for desplazarlos verticalmente
		// si se solapan. Mapa stepTime→stackIndex.
		var stepStack:Map<String, Int> = new Map();

		for (evt in _song.events)
		{
			if (_dragging && _dragEvt == evt) continue;

			var evtY = (GRID_TOP - gridScrollY) + (evt.stepTime * GRID_SIZE);
			if (evtY < 80 || evtY > FlxG.height - 30) continue;

			// Stack offset: si hay varios eventos en el mismo step, los apilamos
			var stepKey = Std.string(Std.int(evt.stepTime * 1000));
			var stackIdx = stepStack.exists(stepKey) ? stepStack.get(stepKey) : 0;
			stepStack.set(stepKey, stackIdx + 1);
			var offsetY = stackIdx * (EVENT_H + 2); // cada evento ocupa EVENT_H + 2px

			var drawY = evtY - EVENT_H / 2 + offsetY;

			var evtColor   = _eventColor(evt.type);
			// Fondo semi-oscuro: mezclar el color del evento con negro para el bg del pill
			var bgColor:Int = _darkenColor(evtColor, 0.55);

			// ── Fondo del pill ────────────────────────────────────────────────
			var pill = new FlxSprite(gridX - SIDEBAR_WIDTH - 5, drawY);
			pill.makeGraphic(SIDEBAR_WIDTH, EVENT_H, bgColor);
			pill.scrollFactor.set();
			pill.cameras = [camHUD];
			eventSprites.add(pill);

			// ── Borde izquierdo de color ───────────────────────────────────────
			var leftBar = new FlxSprite(gridX - SIDEBAR_WIDTH - 5, drawY);
			leftBar.makeGraphic(3, EVENT_H, evtColor);
			leftBar.scrollFactor.set();
			leftBar.cameras = [camHUD];
			eventSprites.add(leftBar);

			// ── Conector hacia el grid ─────────────────────────────────────────
			var conY = Std.int(drawY + EVENT_H / 2);
			var con = new FlxSprite(gridX - 5, conY);
			con.makeGraphic(5, 2, evtColor);
			con.scrollFactor.set();
			con.cameras = [camHUD];
			eventSprites.add(con);

			// ── Type of the event (line 1) ──────────────────────────────────────
			var typeStr = evt.type.length > 15 ? evt.type.substr(0, 13) + ".." : evt.type;
			var typeLbl = new FlxText(gridX - SIDEBAR_WIDTH - 2, drawY + 2, SIDEBAR_WIDTH - 6, typeStr, 9);
			typeLbl.setFormat(Paths.font("vcr.ttf"), 9, 0xFFFFFFFF, LEFT);
			typeLbl.bold = true;
			typeLbl.scrollFactor.set();
			typeLbl.cameras = [camHUD];
			eventLabels.add(typeLbl);

			// ── Value of the event (line 2, if there is espacio) ────────────────────
			if (evt.value != null && evt.value != "" && EVENT_H >= 24)
			{
				var maxValChars = Std.int((SIDEBAR_WIDTH - 8) / 5); // aprox 5px por char
				var valStr = evt.value.length > maxValChars ? evt.value.substr(0, maxValChars - 2) + ".." : evt.value;
				var valLbl = new FlxText(gridX - SIDEBAR_WIDTH - 2, drawY + EVENT_H - 12, SIDEBAR_WIDTH - 6, valStr, 8);
				valLbl.setFormat(Paths.font("vcr.ttf"), 8, 0xFFCCDDCC, LEFT);
				valLbl.scrollFactor.set();
				valLbl.cameras = [camHUD];
				eventLabels.add(valLbl);
			}
		}
	}

	/** Oscurece a color mezclándolo with black. factor=0 → black, factor=1 → color original. */
	static function _darkenColor(color:Int, factor:Float):Int
	{
		var r = Std.int(((color >> 16) & 0xFF) * factor);
		var g = Std.int(((color >> 8)  & 0xFF) * factor);
		var b = Std.int(( color        & 0xFF) * factor);
		return 0xFF000000 | (r << 16) | (g << 8) | b;
	}

	public function _eventColor(type:String):Int
	{
		if (EventInfoSystem.eventColors.exists(type))
			return EventInfoSystem.eventColors.get(type);
		return switch (type)
		{
			case "Camera":      0xFF88CCFF;
			case "BPM Change":  0xFFFFAA00;
			case "Alt Anim":    0xFFFF88CC;
			case "Play Anim":   0xFF88FF88;
			case "Camera Zoom": 0xFFCCAAFF;
			default:            0xFFAAAAAA;
		}
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (eventPopup.isOpen || stackPopup.isOpen) return;

		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Z)
		{
			_undoEvt();
			return;
		}

		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		// ── Drag activo ───────────────────────────────────────────────────────
		if (_dragging && _dragEvt != null)
		{
			_dragSprite.y = my + _dragOffsetY;
			_dragLabel.y  = _dragSprite.y + 3;

			if (FlxG.mouse.justReleased)
			{
				var relY    = (_dragSprite.y + EVENT_H / 2) - (GRID_TOP - gridScrollY);
				var newStep = Math.max(0, Math.round(relY / GRID_SIZE));
				_saveEvtHistory();
				_dragEvt.stepTime = newStep;
				_song.events.sort(function(a, b) return Std.int(a.stepTime - b.stepTime));
				_stopDrag();
				refreshEvents();
				parent.showMessage('Evento movido a step ${newStep}', 0xFF00FF88);
			}
			return;
		}

		// ── Hover borde izq → button "+" ───────────────────────────────────────
		var isHoveringBorder = (mx >= gridX - 20 && mx <= gridX && my >= GRID_TOP && my <= FlxG.height - 30);

		if (isHoveringBorder)
		{
			var base      = GRID_TOP - gridScrollY;
			var relY      = my - base;
			// FIX: respetar el snap actual del editor (igual que las notas)
			var snapSteps = parent.currentSnap / 16.0; // 1.0 = 16vo, 0.5 = 32vo, 2.0 = 8vo...
			var snapPx    = GRID_SIZE * snapSteps;
			hoverBeatY    = base + (Math.floor(relY / snapPx) * snapPx);

			var justShown = !addEventBtn.visible;
			addEventBtn.x     = gridX - 24;
			addEventBtn.y     = hoverBeatY - 14;
			addEventBtnText.x = gridX - 24;
			addEventBtnText.y = hoverBeatY - 14 + 2;

			if (justShown)
			{
				addEventBtn.alpha = addEventBtnText.alpha = 0;
				addEventBtn.visible = addEventBtnText.visible = true;
				FlxTween.cancelTweensOf(addEventBtn);
				FlxTween.cancelTweensOf(addEventBtnText);
				FlxTween.tween(addEventBtn,     {alpha: 0.85}, 0.12, {ease: FlxEase.quadOut});
				FlxTween.tween(addEventBtnText, {alpha: 1.0},  0.12, {ease: FlxEase.quadOut});
			}

			var overBtn = FlxG.mouse.overlaps(addEventBtn, camHUD);
			addEventBtn.alpha = overBtn ? 1.0 : 0.75;

			if (FlxG.mouse.justPressed && overBtn)
			{
				var rawStep  = (hoverBeatY - (gridY - gridScrollY)) / GRID_SIZE;
				var snapStps = parent.currentSnap / 16.0;
				var snapped  = Math.floor(rawStep / snapStps) * snapStps;
				eventPopup.openAtStep(snapped);
			}
		}
		else if (addEventBtn.visible && !FlxG.mouse.overlaps(addEventBtn, camHUD))
		{
			FlxTween.cancelTweensOf(addEventBtn);
			FlxTween.cancelTweensOf(addEventBtnText);
			FlxTween.tween(addEventBtn,     {alpha: 0}, 0.10, {ease: FlxEase.quadIn, onComplete: function(_) { addEventBtn.visible = false; }});
			FlxTween.tween(addEventBtnText, {alpha: 0}, 0.10, {ease: FlxEase.quadIn, onComplete: function(_) { addEventBtnText.visible = false; }});
		}

		// ── Click izquierdo: register posible click over pill ─────────────
		if (FlxG.mouse.justPressed && !FlxG.mouse.overlaps(addEventBtn, camHUD))
			_handlePillClick(mx, my);

		// Mouse pulsado: si se mueve → drag; si suelta sin moverse → popup
		if (_potentialClickEvt != null && FlxG.mouse.pressed)
		{
			var dx = mx - _clickStartX;
			var dy = my - _clickStartY;
			if (Math.sqrt(dx * dx + dy * dy) > DRAG_THRESHOLD)
			{
				_startDrag(_potentialClickEvt, _clickStartX, _clickStartY);
				_potentialClickEvt = null;
			}
		}
		if (_potentialClickEvt != null && FlxG.mouse.justReleased)
		{
			var step = _potentialClickEvt.stepTime;
			_potentialClickEvt = null;
			stackPopup.openForStep(step);
		}

		// ── Click derecho → borrar ────────────────────────────────────────────
		if (FlxG.mouse.justPressedRight)
			_removeEventAtMouse(mx, my);
	}

	/**
	 * Manages click over pill with detection of double click.
	 * - Primer click  → inicia drag normalmente.
		 *   → cancela el drag y abre el EventStackPopup.
	 */
	/** Calcula el drawY de un evento respetando el stack de eventos en el mismo step. */
	function _getEvtDrawY(evt:ChartEvent):Float
	{
		var evtY = (GRID_TOP - gridScrollY) + (evt.stepTime * GRID_SIZE);
		var stepKey = Std.string(Std.int(evt.stepTime * 1000));
		var stackIdx = 0;
		if (_song.events != null)
			for (other in _song.events)
			{
				if (other == evt) break;
				if (Std.string(Std.int(other.stepTime * 1000)) == stepKey)
					stackIdx++;
			}
		return evtY - EVENT_H / 2 + stackIdx * (EVENT_H + 2);
	}

	function _handlePillClick(mx:Float, my:Float):Void
	{
		if (_song.events == null) return;
		for (evt in _song.events)
		{
			var drawY = _getEvtDrawY(evt);
			var evtX  = gridX - SIDEBAR_WIDTH - 5;
			if (mx >= evtX && mx <= gridX - 5 && my >= drawY && my <= drawY + EVENT_H)
			{
				_potentialClickEvt = evt;
				_clickStartX = mx;
				_clickStartY = my;
				return;
			}
		}
	}

	function _startDrag(evt:ChartEvent, mx:Float, my:Float):Void
	{
		var drawY = _getEvtDrawY(evt);
		var evtX  = gridX - SIDEBAR_WIDTH - 5;

		_dragging    = true;
		_dragEvt     = evt;
		_dragOffsetY = drawY - my;

		var color = _eventColor(evt.type);
		_dragSprite.makeGraphic(SIDEBAR_WIDTH, EVENT_H, color);
		_dragSprite.x = evtX;
		_dragSprite.y = my + _dragOffsetY;
		_dragSprite.visible = true;

		_dragLabel.text    = '${evt.type}: ${evt.value}';
		_dragLabel.x       = evtX + 2;
		_dragLabel.y       = _dragSprite.y + 3;
		_dragLabel.visible = true;

		refreshEvents();
	}

	function _stopDrag():Void
	{
		_dragging = false;
		_dragEvt  = null;
		_dragSprite.visible = false;
		_dragLabel.visible  = false;
	}

	function _removeEventAtMouse(mx:Float, my:Float):Void
	{
		if (_song.events == null) return;
		for (evt in _song.events)
		{
			var drawY = _getEvtDrawY(evt);
			var evtX  = gridX - SIDEBAR_WIDTH - 5;
			if (mx >= evtX && mx <= gridX && my >= drawY && my <= drawY + EVENT_H)
			{
				_saveEvtHistory();
				_song.events.remove(evt);
				refreshEvents();
				parent.showMessage('Evento "${evt.type}" eliminado', 0xFFFF3366);
				return;
			}
		}
	}

	// ── Historia (Ctrl+Z) ─────────────────────────────────────────────────────

	function _saveEvtHistory():Void
	{
		if (_song.events == null) _song.events = [];
		if (_evtHistIdx < _evtHistory.length - 1)
			_evtHistory.splice(_evtHistIdx + 1, _evtHistory.length - _evtHistIdx - 1);
		_evtHistory.push(haxe.Json.stringify(_song.events));
		_evtHistIdx = _evtHistory.length - 1;
		if (_evtHistory.length > MAX_EVT_HIST) { _evtHistory.shift(); _evtHistIdx--; }
	}

	function _undoEvt():Void
	{
		if (_evtHistIdx <= 0) { parent.showMessage('No there is more acciones that deshacer', 0xFFFFAA00); return; }
		_evtHistIdx--;
		_song.events = haxe.Json.parse(_evtHistory[_evtHistIdx]);
		refreshEvents();
		parent.showMessage('Undo evento (${_evtHistIdx + 1}/${_evtHistory.length})', 0xFF00CCFF);
	}

	public function addEvent(stepTime:Float, type:String, value:String):Void
	{
		if (_song.events == null) _song.events = [];

		for (existing in _song.events)
		{
			if (Math.abs(existing.stepTime - stepTime) < 0.1 && existing.type == type)
			{
				_saveEvtHistory();
				existing.value = value;
				refreshEvents();
				parent.showMessage('Evento "${type}" actualizado en step ${stepTime}', 0xFF00FF88);
				return;
			}
		}

		_saveEvtHistory();
		_song.events.push({ stepTime: stepTime, type: type, value: value });
		_song.events.sort(function(a, b) return Std.int(a.stepTime - b.stepTime));
		refreshEvents();
		parent.showMessage('Event "${type}" added in step ${stepTime}', 0xFF00FF88);
	}

	public function removeEvent(evt:ChartEvent):Void
	{
		if (_song.events == null) return;
		_saveEvtHistory();
		_song.events.remove(evt);
		refreshEvents();
		parent.showMessage('Evento "${evt.type}" eliminado', 0xFFFF3366);
	}

	/** Devuelve todos los eventos en el step indicado (tolerancia 0.5). */
	public function getEventsAtStep(step:Float):Array<ChartEvent>
	{
		if (_song.events == null) return [];
		return _song.events.filter(function(e) return Math.abs(e.stepTime - step) < 0.5);
	}
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * Popup of "pila of events" — is abre with double click over a pill.
 *
 * Muestra una tabla con TODOS los eventos del mismo step:
 *   ┌─────────────────────────────────────────┐
 *   │  Events at Step 4              [×]      │
 *   ├────────────┬────────────────────┬───────┤
 *   │ TYPE       │ VALUE              │       │
 *   ├────────────┼────────────────────┼───────┤
 *   │ [Camera  ] │ Dad                │ [X]  │
 *   │ [BPM Chg ] │ 120                │ [X]  │
 *   ├────────────┴────────────────────┴───────┤
 *   │         [+ Add Event at Step 4]         │
 *   └─────────────────────────────────────────┘
 */
class EventStackPopup extends FlxGroup
{
	var parent:ChartingState;
	var _song:SwagSong;
	var camHUD:FlxCamera;
	var sidebar:EventsSidebar;

	public var isOpen:Bool = false;
	var _step:Float = 0;

	// Elementos static of the panel
	var _overlay:FlxSprite;
	var _panel:FlxSprite;
	var _title:FlxText;
	var _headerType:FlxText;
	var _headerVal:FlxText;
	var _addBtn:FlxButton;
	var _closeBtn:FlxSprite;
	var _closeBtnTxt:FlxText;

	// Filas dynamic (recreadas in each apertura)
	var _rowGroup:FlxGroup;

	// Hitboxes por fila: borrar (X) y editar (click en la fila)
	var _deleteHitboxes:Array<{spr:FlxSprite, evt:ChartEvent}> = [];
	var _editHitboxes:Array<{spr:FlxSprite, evt:ChartEvent}>   = [];

	static inline var PW:Int  = 440;   // panel width
	static inline var ROW_H:Int = 28;  // altura por fila de evento
	static inline var HEADER_H:Int = 22;
	static inline var FOOTER_H:Int = 44;
	static inline var PAD:Int = 12;
	static inline var COL_TYPE:Int = 130; // ancho columna tipo
	static inline var COL_VAL:Int  = 200; // ancho columna valor

	static inline var C_BG:Int      = 0xFF101820;
	static inline var C_BORDER:Int  = 0xFF00CCFF;
	static inline var C_HEADER:Int  = 0xFF162430;
	static inline var C_ROW_A:Int   = 0xFF0D1820;
	static inline var C_ROW_B:Int   = 0xFF111E2A;
	static inline var C_TEXT:Int    = 0xFFCCDDEE;
	static inline var C_SUBTEXT:Int = 0xFF778899;
	static inline var C_DEL:Int     = 0xFF882233;
	static inline var C_DEL_H:Int   = 0xFFFF3355;
	static inline var C_ADD:Int     = 0xFF1A3A1A;
	static inline var C_ADD_H:Int   = 0xFF00FF88;

	public function new(parent:ChartingState, song:SwagSong, camHUD:FlxCamera, sidebar:EventsSidebar)
	{
		super();
		this.parent  = parent;
		this._song   = song;
		this.camHUD  = camHUD;
		this.sidebar = sidebar;

		// Overlay semitransparente de fondo
		_overlay = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xBB000000);
		_overlay.scrollFactor.set();
		_overlay.cameras = [camHUD];
		add(_overlay);

		_rowGroup = new FlxGroup();
		add(_rowGroup);

		visible = false;
		active  = false;
	}

	// ── Apertura ──────────────────────────────────────────────────────────────

	public function openForStep(step:Float):Void
	{
		_step = step;
		_rebuildRows();

		isOpen  = true;
		visible = true;
		active  = true;

		// Animar entrada
		_overlay.alpha = 0;
		FlxTween.cancelTweensOf(_overlay);
		FlxTween.tween(_overlay, {alpha: 0.73}, 0.14, {ease: FlxEase.quadOut});

		if (_panel != null)
		{
			var cy = _panelY();
			_panel.y = cy + 24;
			_panel.alpha = 0;
			FlxTween.cancelTweensOf(_panel);
			FlxTween.tween(_panel, {alpha: 1.0, y: cy}, 0.20, {ease: FlxEase.backOut});
		}
	}

	function _panelY():Float
		return (FlxG.height - _panelH()) / 2;

	function _panelH():Int
	{
		var events = sidebar.getEventsAtStep(_step);
		return HEADER_H + PAD + ROW_H + (events.length * ROW_H) + FOOTER_H + PAD;
	}

	function _panelX():Float
		return (FlxG.width - PW) / 2;

	// ── Construir filas ───────────────────────────────────────────────────────

	function _rebuildRows():Void
	{
		// Limpiar filas previas
		_rowGroup.forEach(function(m:flixel.FlxBasic) m.destroy());
		_rowGroup.clear();
		_deleteHitboxes = [];
		_editHitboxes   = [];

		var events = sidebar.getEventsAtStep(_step);
		var ph     = _panelH();
		var px     = _panelX();
		var py     = _panelY();

		// Panel de fondo
		_panel = new FlxSprite(px, py).makeGraphic(PW, ph, C_BG);
		_panel.scrollFactor.set(); _panel.cameras = [camHUD];
		_rowGroup.add(_panel);

		// Borde superior coloreado
		var topBar = new FlxSprite(px, py).makeGraphic(PW, 3, C_BORDER);
		topBar.scrollFactor.set(); topBar.cameras = [camHUD];
		_rowGroup.add(topBar);

		// Title
		var stepLabel = Std.int(_step);
		_title = new FlxText(px + PAD, py + 7, PW - 50, 'Events at Step $stepLabel   (${events.length} event${events.length == 1 ? "" : "s"})', 13);
		_title.setFormat(Paths.font("vcr.ttf"), 13, C_BORDER, LEFT);
		_title.scrollFactor.set(); _title.cameras = [camHUD];
		_rowGroup.add(_title);

		// Button cerrar [×]
		_closeBtn = new FlxSprite(px + PW - 28, py + 5).makeGraphic(22, 20, 0xFF331111);
		_closeBtn.scrollFactor.set(); _closeBtn.cameras = [camHUD];
		_rowGroup.add(_closeBtn);
		_closeBtnTxt = new FlxText(px + PW - 28, py + 6, 22, "X", 14);
		_closeBtnTxt.setFormat(Paths.font("vcr.ttf"), 14, 0xFFFF5566, CENTER);
		_closeBtnTxt.scrollFactor.set(); _closeBtnTxt.cameras = [camHUD];
		_rowGroup.add(_closeBtnTxt);

		// Header de columnas
		var hy = py + HEADER_H + 4;
		var headerBg = new FlxSprite(px, hy).makeGraphic(PW, ROW_H, C_HEADER);
		headerBg.scrollFactor.set(); headerBg.cameras = [camHUD];
		_rowGroup.add(headerBg);

		var hType = new FlxText(px + PAD, hy + 7, COL_TYPE, "TYPE", 9);
		hType.setFormat(Paths.font("vcr.ttf"), 9, C_SUBTEXT, LEFT);
		hType.scrollFactor.set(); hType.cameras = [camHUD];
		_rowGroup.add(hType);

		var hVal = new FlxText(px + PAD + COL_TYPE, hy + 7, COL_VAL, "VALUE", 9);
		hVal.setFormat(Paths.font("vcr.ttf"), 9, C_SUBTEXT, LEFT);
		hVal.scrollFactor.set(); hVal.cameras = [camHUD];
		_rowGroup.add(hVal);

		var hDel = new FlxText(px + PAD + COL_TYPE + COL_VAL, hy + 7, PW - COL_TYPE - COL_VAL - PAD * 2, "DEL", 9);
		hDel.setFormat(Paths.font("vcr.ttf"), 9, C_SUBTEXT, CENTER);
		hDel.scrollFactor.set(); hDel.cameras = [camHUD];
		_rowGroup.add(hDel);

		// Filas de eventos
		var ry = hy + ROW_H;
		for (i in 0...events.length)
		{
			var evt    = events[i];
			var rowCol = (i % 2 == 0) ? C_ROW_A : C_ROW_B;

			// Fondo de fila
			var rowBg = new FlxSprite(px, ry).makeGraphic(PW, ROW_H, rowCol);
			rowBg.scrollFactor.set(); rowBg.cameras = [camHUD];
			_rowGroup.add(rowBg);

			// Pastilla de color con el tipo
			var typeColor = sidebar._eventColor(evt.type);
			var badge = new FlxSprite(px + PAD, ry + 5).makeGraphic(COL_TYPE - PAD * 2, 18, typeColor);
			badge.scrollFactor.set(); badge.cameras = [camHUD];
			_rowGroup.add(badge);

			var typeTxt = new FlxText(px + PAD + 3, ry + 7, COL_TYPE - PAD * 2 - 3, evt.type, 9);
			typeTxt.setFormat(Paths.font("vcr.ttf"), 9, 0xFF000000, LEFT);
			typeTxt.scrollFactor.set(); typeTxt.cameras = [camHUD];
			_rowGroup.add(typeTxt);

			// Valor
			var valStr = evt.value.length > 24 ? evt.value.substr(0, 22) + "…" : evt.value;
			var valTxt = new FlxText(px + PAD + COL_TYPE, ry + 7, COL_VAL - PAD, valStr == "" ? "(empty)" : valStr, 10);
			valTxt.setFormat(Paths.font("vcr.ttf"), 10, valStr == "" ? C_SUBTEXT : C_TEXT, LEFT);
			valTxt.scrollFactor.set(); valTxt.cameras = [camHUD];
			_rowGroup.add(valTxt);

			// Button borrar
			var delW  = 28;
			var delX  = px + PW - PAD - delW;
			var delBg = new FlxSprite(delX, ry + 5).makeGraphic(delW, 18, C_DEL);
			delBg.scrollFactor.set(); delBg.cameras = [camHUD];
			_rowGroup.add(delBg);

			var delTxt = new FlxText(delX, ry + 5, delW, "X", 10);
			delTxt.setFormat(Paths.font("vcr.ttf"), 10, 0xFFFFCCCC, CENTER);
			delTxt.scrollFactor.set(); delTxt.cameras = [camHUD];
			_rowGroup.add(delTxt);

			// Hitbox de borrar
			_deleteHitboxes.push({ spr: delBg, evt: evt });

			// Hitbox of editar (all the fila excepto the button X)
			_editHitboxes.push({ spr: rowBg, evt: evt });

			ry += ROW_H;
		}

		// Mensaje empty if no there is events
		if (events.length == 0)
		{
			var emptyTxt = new FlxText(px + PAD, ry + 8, PW - PAD * 2, "No events at this step yet.", 10);
			emptyTxt.setFormat(Paths.font("vcr.ttf"), 10, C_SUBTEXT, CENTER);
			emptyTxt.scrollFactor.set(); emptyTxt.cameras = [camHUD];
			_rowGroup.add(emptyTxt);
			ry += ROW_H;
		}

		// Separador
		var sep = new FlxSprite(px, ry).makeGraphic(PW, 1, 0xFF223344);
		sep.scrollFactor.set(); sep.cameras = [camHUD];
		_rowGroup.add(sep);

		// Button "+ Add Event at Step X"
		var addBg = new FlxSprite(px + PAD, ry + 8).makeGraphic(PW - PAD * 2, 26, C_ADD);
		addBg.scrollFactor.set(); addBg.cameras = [camHUD];
		_rowGroup.add(addBg);

		var addTxt = new FlxText(px + PAD, ry + 13, PW - PAD * 2, '+ Add Event at Step $stepLabel', 11);
		addTxt.setFormat(Paths.font("vcr.ttf"), 11, 0xFF00FF88, CENTER);
		addTxt.scrollFactor.set(); addTxt.cameras = [camHUD];
		_rowGroup.add(addTxt);

		// Save referencia to the button add for hit-test
		// Usamos _addBtn como sprite invisible de hitbox reutilizable
		// (no FlxButton para evitar overhead de FlxUI)
		if (_addBtn == null)
		{
			// Solo creamos el FlxButton la primera vez; lo reposicionamos cada apertura
			_addBtn = new FlxButton(0, 0, "", function()
			{
				close();
				// Small delay for that the popup cierre before of abrir EventPopup
				new flixel.util.FlxTimer().start(0.05, function(_)
					sidebar.eventPopup.openAtStep(_step)
				);
			});
			_addBtn.cameras = [camHUD];
			_addBtn.scrollFactor.set();
			add(_addBtn); // fuera del rowGroup para persistir entre rebuilds
		}
		_addBtn.x = px + PAD;
		_addBtn.y = ry + 8;
		_addBtn.makeGraphic(PW - PAD * 2, 26, 0x00000000); // transparente, solo hitbox
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		if (!isOpen) return;
		super.update(elapsed);

		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		if (FlxG.keys.justPressed.ESCAPE)
		{
			close();
			return;
		}

		if (FlxG.mouse.justPressed)
		{
			// Button ×
			if (_closeBtn != null && _mouseOver(_closeBtn, mx, my))
			{
				close();
				return;
			}

			// Button borrar (X) — tiene prioridad over editar
			for (entry in _deleteHitboxes)
			{
				if (_mouseOver(entry.spr, mx, my))
				{
					sidebar.removeEvent(entry.evt);
					var remaining = sidebar.getEventsAtStep(_step);
					if (remaining.length == 0)
						close();
					else
						_rebuildRows();
					return;
				}
			}

			// Click en fila (fuera del X) → editar ese evento
			for (entry in _editHitboxes)
			{
				if (_mouseOver(entry.spr, mx, my))
				{
					var evtToEdit = entry.evt;
					close();
					new flixel.util.FlxTimer().start(0.05, function(_)
						sidebar.eventPopup.openForEdit(evtToEdit)
					);
					return;
				}
			}

			// Click fuera del panel → cerrar
			if (_panel != null)
			{
				var px = _panelX();
				var py = _panelY();
				if (!(mx >= px && mx <= px + PW && my >= py && my <= py + _panelH()))
					close();
			}
		}
	}

	function _mouseOver(spr:FlxSprite, mx:Float, my:Float):Bool
		return spr != null && mx >= spr.x && mx <= spr.x + spr.width
		                   && my >= spr.y && my <= spr.y + spr.height;

	// ── Cierre ────────────────────────────────────────────────────────────────

	public function close():Void
	{
		if (!isOpen) return;
		isOpen = false;

		FlxTween.cancelTweensOf(_overlay);
		FlxTween.tween(_overlay, {alpha: 0}, 0.13, {ease: FlxEase.quadIn});

		if (_panel != null)
		{
			FlxTween.cancelTweensOf(_panel);
			FlxTween.tween(_panel, {alpha: 0, y: _panel.y + 16}, 0.16,
			{
				ease: FlxEase.quadIn,
				onComplete: function(_) { visible = false; active = false; }
			});
		}
		else
		{
			visible = false;
			active  = false;
		}
	}
}

// ─────────────────────────────────────────────────────────────────────────────

class EventPopup extends FlxGroup
{
	var parent:ChartingState;
	var _song:SwagSong;
	var camHUD:FlxCamera;
	var sidebar:EventsSidebar;

	public var isOpen:Bool = false;
	var targetStep:Float   = 0;
	/** Event that is is editando (null = add new). */
	var _editingEvt:ChartEvent = null;

	var overlay:FlxSprite;
	var panel:FlxSprite;
	var titleText:FlxText;
	var typeDropDown:FlxUIDropDownMenu;
	var descText:FlxText;

	var _selectedType:String        = "";
	var _paramWidgets:Array<Dynamic>     = [];
	var _paramDefs:Array<EventParamDef> = [];
	var _dynamicGroup:FlxGroup;

	var addBtn:FlxButton;
	var closeBtn:FlxButton;

	static inline var POPUP_W:Int  = 360;
	static inline var POPUP_H:Int  = 310;
	static inline var BG:Int       = 0xFF0D1F0D;
	static inline var ACCENT:Int   = 0xFF00FF88;
	static inline var GRAY:Int     = 0xFFAAAAAA;
	static inline var DESC_COLOR:Int = 0xFF88BBAA;
	static inline var FIELD_W:Int  = 320;

	public function new(parent:ChartingState, song:SwagSong, camHUD:FlxCamera, sidebar:EventsSidebar)
	{
		super();
		this.parent  = parent;
		this._song   = song;
		this.camHUD  = camHUD;
		this.sidebar = sidebar;
		_build();
		visible = false;
		close();
	}

	function _build():Void
	{
		var cx = (FlxG.width  - POPUP_W) / 2;
		var cy = (FlxG.height - POPUP_H) / 2;

		overlay = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xAA000000);
		overlay.scrollFactor.set(); overlay.cameras = [camHUD]; add(overlay);

		panel = new FlxSprite(cx, cy).makeGraphic(POPUP_W, POPUP_H, BG);
		panel.scrollFactor.set(); panel.cameras = [camHUD]; add(panel);

		var bar = new FlxSprite(cx, cy).makeGraphic(POPUP_W, 4, ACCENT);
		bar.scrollFactor.set(); bar.cameras = [camHUD]; add(bar);

		titleText = new FlxText(cx + 15, cy + 10, POPUP_W - 30, "Add Event", 16);
		titleText.setFormat(Paths.font("vcr.ttf"), 16, ACCENT, LEFT);
		titleText.scrollFactor.set(); titleText.cameras = [camHUD]; add(titleText);

		var typeLbl = new FlxText(cx + 15, cy + 38, 0, "Type:", 11);
		typeLbl.setFormat(Paths.font("vcr.ttf"), 11, GRAY, LEFT);
		typeLbl.scrollFactor.set(); typeLbl.cameras = [camHUD]; add(typeLbl);

		var typeNames = funkin.scripting.events.EventRegistry.getNamesForContext('chart');
		if (typeNames.length == 0) typeNames.push("(no events)");

		typeDropDown = new FlxUIDropDownMenu(cx + 15, cy + 53, FlxUIDropDownMenu.makeStrIdLabelArray(typeNames, true), function(id:String)
		{
			var idx = Std.parseInt(id);
			if (idx != null && idx >= 0 && idx < typeNames.length)
				_switchToType(typeNames[idx]);
		});
		typeDropDown.scrollFactor.set(); typeDropDown.cameras = [camHUD]; add(typeDropDown);

		descText = new FlxText(cx + 15, cy + 88, POPUP_W - 30, "", 9);
		descText.setFormat(Paths.font("vcr.ttf"), 9, DESC_COLOR, LEFT);
		descText.scrollFactor.set(); descText.cameras = [camHUD]; add(descText);

		_dynamicGroup = new FlxGroup();
		add(_dynamicGroup);

		addBtn = new FlxButton(cx + 15, cy + POPUP_H - 42, "Add Event", _onAddPressed);
		addBtn.scrollFactor.set(); addBtn.cameras = [camHUD]; add(addBtn);

		closeBtn = new FlxButton(cx + POPUP_W - 110, cy + POPUP_H - 42, "Cancel", close);
		closeBtn.scrollFactor.set(); closeBtn.cameras = [camHUD]; add(closeBtn);
	}

	function _switchToType(type:String):Void
	{
		_selectedType = type;
		_clearDynamic();

		final def = funkin.scripting.events.EventRegistry.get(type);
		_paramDefs  = def != null ? def.params : (EventInfoSystem.eventParams.exists(type) ? EventInfoSystem.eventParams.get(type) : []);
		_paramWidgets = [];

		if (descText != null)
			descText.text = (def != null && def.description != null && def.description != '') ? def.description : '';

		var cx   = (FlxG.width  - POPUP_W) / 2;
		var cy   = (FlxG.height - POPUP_H) / 2;
		var yOff = cy + 108;
		var maxY = cy + POPUP_H - 55;

		for (i in 0..._paramDefs.length)
		{
			if (yOff > maxY) break;
			var p = _paramDefs[i];

			final labelTxt = p.description != null && p.description != ''
				? '${p.name}: (${p.description})'
				: '${p.name}:';
			var lbl = new FlxText(cx + 15, yOff, POPUP_W - 30, labelTxt, 10);
			lbl.setFormat(Paths.font("vcr.ttf"), 10, GRAY, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			_dynamicGroup.add(lbl);
			yOff += 16;

			var widget:Dynamic = null;
			switch (p.type)
			{
				case PDBool:
					var temp:FlxUIDropDownMenu = new FlxUIDropDownMenu(cx + 15, yOff, FlxUIDropDownMenu.makeStrIdLabelArray(["true","false"], true), function(_){});
					temp.cameras = [camHUD];
					widget = temp;

				case PDDropDown(opts):
					var temp:FlxUIDropDownMenu = new FlxUIDropDownMenu(cx + 15, yOff, FlxUIDropDownMenu.makeStrIdLabelArray(opts, true), function(_){});
					temp.cameras = [camHUD];
					widget = temp;

				default:
					var inp = new FlxUIInputText(cx + 15, yOff, FIELD_W, p.defValue, 12);
					inp.scrollFactor.set(); inp.cameras = [camHUD];
					widget = inp;
			}

			if (widget != null)
			{
				widget.scrollFactor.set();
				_dynamicGroup.add(widget);
				_paramWidgets.push(widget);
				yOff += 30;
			}
		}
	}

	function _clearDynamic():Void
	{
		_dynamicGroup.forEach(function(m:flixel.FlxBasic) { m.destroy(); });
		_dynamicGroup.clear();
		_paramWidgets = [];
	}

	function _readValues():String
	{
		var parts:Array<String> = [];
		for (i in 0..._paramWidgets.length)
		{
			var w = _paramWidgets[i];
			var val:String = "";
			if (Std.isOfType(w, FlxUIInputText))
				val = cast(w, FlxUIInputText).text;
			else if (Std.isOfType(w, FlxUIDropDownMenu))
			{
				var dd  = cast(w, FlxUIDropDownMenu);
				var idx = Std.parseInt(dd.selectedId);
				var p   = _paramDefs[i];
				switch (p.type)
				{
					case PDBool:
						val = (idx == 0) ? "true" : "false";
					case PDDropDown(opts):
						val = (idx != null && idx >= 0 && idx < opts.length) ? opts[idx] : "";
					default:
						val = dd.selectedId;
				}
			}
			parts.push(val);
		}
		return parts.join("|");
	}

	function _onAddPressed():Void
	{
		if (_selectedType == "" || _selectedType == "(no events)") return;
		if (_editingEvt != null)
		{
			// Modo edition: if the type changed, borrar the old and add the new
			if (_editingEvt.type != _selectedType)
				sidebar.removeEvent(_editingEvt);
			_editingEvt = null;
		}
		sidebar.addEvent(targetStep, _selectedType, _readValues());
		close();
	}

	public function openAtStep(step:Float):Void
	{
		_editingEvt = null;
		targetStep = step;
		titleText.text = 'Add Event @ step ${Std.int(step)}';
		if (addBtn != null) addBtn.label.text = "Add Event";

		var types = funkin.scripting.events.EventRegistry.getNamesForContext('chart');
		if (types.length == 0) types = EventInfoSystem.eventList;
		if (types.length > 0) _switchToType(types[0]);

		isOpen = true;
		visible = true;
		active  = true;

		var cx = (FlxG.width  - POPUP_W) / 2;
		var cy = (FlxG.height - POPUP_H) / 2;
		overlay.alpha = 0;
		FlxTween.cancelTweensOf(overlay);
		FlxTween.tween(overlay, {alpha: 0.60}, 0.16, {ease: FlxEase.quadOut});
		panel.y = cy + 30; panel.alpha = 0;
		FlxTween.cancelTweensOf(panel);
		FlxTween.tween(panel, {alpha: 1, y: cy}, 0.22, {ease: FlxEase.backOut});
		_fadeKids(true);
	}

	/**
	 * Abre el popup pre-rellenado con los datos de un evento existente para editarlo.
	 * To the save: if the type changed is borra the old; if no, updates the value.
	 */
	public function openForEdit(evt:ChartEvent):Void
	{
		_editingEvt = evt;
		targetStep  = evt.stepTime;
		titleText.text = 'Edit Event @ step ${Std.int(evt.stepTime)}';
		if (addBtn != null) addBtn.label.text = "Save Changes";

		// Pre-seleccionar el tipo del evento
		_switchToType(evt.type);

		// Pre-rellenar los valores: el formato es "val1|val2|val3"
		var parts = evt.value.split("|");
		for (i in 0..._paramWidgets.length)
		{
			if (i >= parts.length) break;
			var w = _paramWidgets[i];
			var v = parts[i];
			if (Std.isOfType(w, FlxUIInputText))
				cast(w, FlxUIInputText).text = v;
			else if (Std.isOfType(w, FlxUIDropDownMenu))
			{
				var dd  = cast(w, FlxUIDropDownMenu);
				var p   = _paramDefs[i];
				switch (p.type)
				{
					case PDBool:
						dd.selectedLabel = v;
					case PDDropDown(opts):
						dd.selectedLabel = v;
					default:
				}
			}
		}

		// Animar apertura igual que openAtStep
		isOpen = true;
		visible = true;
		active  = true;

		var cx = (FlxG.width  - POPUP_W) / 2;
		var cy = (FlxG.height - POPUP_H) / 2;
		overlay.alpha = 0;
		FlxTween.cancelTweensOf(overlay);
		FlxTween.tween(overlay, {alpha: 0.60}, 0.16, {ease: FlxEase.quadOut});
		panel.y = cy + 30; panel.alpha = 0;
		FlxTween.cancelTweensOf(panel);
		FlxTween.tween(panel, {alpha: 1, y: cy}, 0.22, {ease: FlxEase.backOut});
		_fadeKids(true);
	}

	public function close():Void
	{
		if (!isOpen && !visible) { visible = false; active = false; return; }
		isOpen = false; active = false;
		if (!visible) { visible = false; return; }
		var cy = (FlxG.height - POPUP_H) / 2;
		FlxTween.cancelTweensOf(overlay);
		FlxTween.tween(overlay, {alpha: 0}, 0.14, {ease: FlxEase.quadIn});
		FlxTween.cancelTweensOf(panel);
		FlxTween.tween(panel, {alpha: 0, y: cy + 20}, 0.17, {ease: FlxEase.quadIn, onComplete: function(_) { visible = false; }});
		_fadeKids(false);
	}

	function _fadeKids(opening:Bool):Void
	{
		forEach(function(m:flixel.FlxBasic)
		{
			if (m == overlay || m == panel || m == _dynamicGroup) return;
			if (Std.isOfType(m, FlxSprite))
			{
				var spr:FlxSprite = cast m;
				FlxTween.cancelTweensOf(spr);
				FlxTween.tween(spr, {alpha: opening ? 1.0 : 0.0}, opening ? 0.18 : 0.12,
					{ease: opening ? FlxEase.quadOut : FlxEase.quadIn, startDelay: opening ? 0.10 : 0.0});
			}
		});
	}

	override public function update(elapsed:Float):Void
	{
		if (!isOpen) return;
		super.update(elapsed);
		if (FlxG.keys.justPressed.ESCAPE) close();
	}
}
