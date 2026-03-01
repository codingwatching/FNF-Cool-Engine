package funkin.gameplay.modchart;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import funkin.gameplay.objects.StrumsGroup;
import funkin.gameplay.notes.StrumNote;
import funkin.gameplay.notes.Note;
import funkin.transitions.StateTransition;
import funkin.gameplay.modchart.ModChartEvent;
import funkin.gameplay.modchart.ModChartManager;
import funkin.gameplay.PlayState;
import funkin.data.Conductor;
import funkin.data.Song.StrumsGroupData;
import funkin.data.Song;

/**
 * ══════════════════════════════════════════════════════════════════════
 *  ModChartEditorState  v4 — Editor visual de ModCharts
 * ══════════════════════════════════════════════════════════════════════
 *
 *  NUEVAS FEATURES v4:
 *    • Scrollbar horizontal dedicado en la timeline
 *    • Timeline con grupos visuales (headers, colores, separadores)
 *    • Soporte de scripts externos (importar JSON de eventos)
 *    • Previsualización de curva de easing (ventana separada)
 *    • Guardado mejorado con backup automático
 *    • Collapsible grupos en timeline
 */

// ─── Typedef ventana flotante ─────────────────────────────────────────────────
typedef WinData =
{
	var title      : String;
	var x          : Float;
	var y          : Float;
	var w          : Float;
	var h          : Float;
	var visible    : Bool;
	var minimized  : Bool;
	var allSprites : Array<flixel.FlxBasic>;
	var bg         : FlxSprite;
	var shadow     : FlxSprite;
	var titleBar   : FlxSprite;
	var titleTxt   : FlxText;
	var minBtn     : FlxText;
	var closeBtn   : FlxText;
	@:optional var contentGroup : FlxGroup;
}

// ─── Patrón de ritmo predefinido ──────────────────────────────────────────────
typedef RhythmPattern =
{
	var name      : String;
	var events    : Array<{beat:Float, type:ModEventType, value:Float, dur:Float, ease:ModEase}>;
}

// ═════════════════════════════════════════════════════════════════════════════

class ModChartEditorState extends FlxState
{
	// ── Datos transferidos desde PlayState vía statics ────────────────────────
	public static var pendingManager    : ModChartManager       = null;
	public static var pendingStrumsData : Array<StrumsGroupData> = null;

	// ── Referencias externas ──────────────────────────────────────────────────
	private var manager       : ModChartManager;
	private var srcStrumsGrps : Array<StrumsGroupData>;

	// ── Cámara ────────────────────────────────────────────────────────────────
	private var editorCam : FlxCamera;

	// ── Layout ────────────────────────────────────────────────────────────────
	static inline var SW       = 1280;
	static inline var SH       = 720;
	static inline var BAR_H    = 32;      // barra superior
	static inline var STAT_H   = 24;      // barra estado inferior
	static inline var TL_H     = 220;     // altura timeline
	static inline var TL_RH    = 30;      // altura ruler
	static inline var TL_SB_H  = 14;      // altura scrollbar horizontal dedicado
	static inline var PANEL_L  = 300;     // panel izquierdo (propiedades)
	static inline var PANEL_R  = 240;     // panel derecho (tools + inspector)

	private var tlY       : Float;
	private var gameAreaY : Float;
	private var gameAreaH : Float;
	private var gameAreaX : Float;
	private var gameAreaW : Float;

	// ── STRUMS PROPIOS DEL EDITOR ─────────────────────────────────────────────
	private var editorGroups      : Array<StrumsGroup>    = [];
	private var editorStrumBaseX  : Array<Array<Float>>   = [];
	private var editorStrumBaseY  : Array<Array<Float>>   = [];
	private var strumLineY        : Float = 0;

	// ── Hitbox visual por strum ───────────────────────────────────────────────
	private var strumHitGroup  : FlxGroup;
	private var strumHitBoxes  : Array<Array<FlxSprite>> = [];
	private var strumLabels    : Array<Array<FlxText>>   = [];
	private var strumHoverBox  : FlxSprite;

	// ── Selection boxes sobre strums ──────────────────────────────────────────
	private var selBoxGroup : FlxGroup;
	private var selBoxes    : Array<Array<FlxSprite>> = [];

	// ── Beat Line Animator ────────────────────────────────────────────────────
	private var beatLine   : FlxSprite;
	private var beatAlpha  : Float = 0;

	// ── Playback ──────────────────────────────────────────────────────────────
	private var playheadBeat : Float = 0;
	private var isPlaying    : Bool  = false;
	private var songPosition : Float = 0;
	private var lastBeatInt  : Int   = -1;

	// ── Audio ─────────────────────────────────────────────────────────────────
	private var vocals   : FlxSound = null;
	private var volValue : Float    = 1.0;
	private var audioLbl : FlxText;
	private var volLbl   : FlxText;

	// ── Timeline ──────────────────────────────────────────────────────────────
	private var tlScroll     : Float = 0;
	private var beatsVisible : Float = 16;
	static inline var BV_MIN = 2.0;
	static inline var BV_MAX = 256.0;

	private var tlGroup     : FlxGroup;
	private var evSprites   : Array<{sp:FlxSprite, lbl:FlxText, valLbl:FlxText, ev:ModChartEvent}> = [];
	private var playheadSpr : FlxSprite;
	private var zoomLbl     : FlxText;
	private var beatInfoLbl : FlxText;
	private var rowCount    : Int   = 0;
	private var rowH        : Float = 20;
	private var snapDiv     : Int   = 4;

	// ── Scrollbar horizontal dedicado ─────────────────────────────────────────
	private var tlScrollbarBg      : FlxSprite;
	private var tlScrollbarThumb   : FlxSprite;
	private var scrollbarDragging  : Bool  = false;
	private var scrollbarDragOX    : Float = 0;
	private var sbTrackX           : Float = 0;
	private var sbTrackW           : Float = 0;
	private var sbY                : Float = 0;

	// ── Timeline grupos colapsables ───────────────────────────────────────────
	private var collapsedGroups : Array<Bool> = [];

	// ── Easing Preview Window ─────────────────────────────────────────────────
	private var easingPreviewWin    : WinData      = null;
	private var easingPreviewOpen   : Bool         = false;
	private var easingCurveSprites  : Array<FlxSprite> = [];
	private var easingPreviewLbl    : FlxText      = null;
	private var easingPrevEase      : String       = "";

	// ── Script externo ────────────────────────────────────────────────────────
	private var scriptWin        : WinData = null;
	private var scriptStatusTxt  : FlxText = null;
	private var scriptFilePath   : String  = "";

	// ── Evento seleccionado ───────────────────────────────────────────────────
	private var selectedEv : ModChartEvent = null;

	// ── Undo / Redo ───────────────────────────────────────────────────────────
	private var undoStack : Array<String> = [];
	private var redoStack : Array<String> = [];

	// ── Ventanas ──────────────────────────────────────────────────────────────
	private var windows     : Array<WinData> = [];
	private var windowGroup : FlxGroup;
	private var draggingWin : WinData = null;
	private var dragOX      : Float   = 0;
	private var dragOY      : Float   = 0;

	// ── Modo UI ───────────────────────────────────────────────────────────────
	private var previewMode  : Bool = false;
	private var uiHidden     : Bool = false;
	private var fullGameView : Bool = false;

	// ── Formulario de nuevo evento ────────────────────────────────────────────
	private var newType   : ModEventType = MOVE_X;
	private var newTarget : String       = "player";
	private var newStrumI : Int          = -1;
	private var newBeat   : Float        = 0;
	private var newValue  : Float        = 0;
	private var newDur    : Float        = 1;
	private var newEase   : ModEase      = QUAD_OUT;
	private var focusField: String       = "";
	private var fieldBufs : Map<String, String> = new Map();

	// Labels del formulario
	private var lblType   : FlxText;
	private var lblTarget : FlxText;
	private var lblStrum  : FlxText;
	private var lblEase   : FlxText;
	private var fldBeat   : FlxText;
	private var fldVal    : FlxText;
	private var fldDur    : FlxText;

	// ── Inspector panel ───────────────────────────────────────────────────────
	private var inspTxt       : FlxText;
	private var inspListGroup : FlxGroup;
	private var inspScrollOff : Int = 0;

	// ── Status bar ────────────────────────────────────────────────────────────
	private var statusTxt : FlxText;
	private var snapLbl   : FlxText;

	// ── Strum Properties ─────────────────────────────────────────────────────
	private var strumPropWin  : WinData;
	private var strumPropTxts : Array<FlxSprite> = [];

	private var selectedGroupIdx : Int = -1;
	private var selectedStrumIdx : Int = -1;

	// ── Hit-areas ─────────────────────────────────────────────────────────────
	private var hitBtns  : Array<{x:Float,y:Float,w:Float,h:Float,cb:Void->Void}> = [];
	private var hitFields: Array<{x:Float,y:Float,w:Float,h:Float,key:String}>    = [];

	// ── Ayuda ─────────────────────────────────────────────────────────────────
	private var helpOverlay : FlxSprite;
	private var helpTxt     : FlxText;
	private var showHelp    : Bool = false;

	// ── Zoom del área de juego ────────────────────────────────────────────────
	private var gameZoom  : Float = 1.0;
	static inline var ZOOM_MIN = 0.5;
	static inline var ZOOM_MAX = 2.5;

	// ── Patrones de ritmo ─────────────────────────────────────────────────────
	private var rhythmPatterns : Array<RhythmPattern> = [];

	// ─── Lista eventos panel izquierdo ────────────────────────────────────────
	private var evListStartY : Float = 0;
	private var evListEndY   : Float = 0;
	private var evListTxts   : Array<FlxSprite> = [];

	// ─── Strum props panel ────────────────────────────────────────────────────
	private var strumPropStartY : Float = 0;
	private var strumPropEndY   : Float = 0;
	private var strumPropBtns   : Array<{x:Float,y:Float,w:Float,h:Float,cb:Void->Void}> = [];

	// ─── Paleta de colores ────────────────────────────────────────────────────
	static inline var C_BG        = 0xFF06060F;
	static inline var C_GAME_BG   = 0xFF080815;
	static inline var C_GRID_V    = 0xFF0E0E20;
	static inline var C_GRID_H    = 0xFF0A0A18;
	static inline var C_TL_BG     = 0xFF040410;
	static inline var C_TL_BORDER = 0xFF1A2A88;
	static inline var C_RULER     = 0xFF0C0C1E;
	static inline var C_BEAT_LINE = 0xFF162260;
	static inline var C_STEP_LINE = 0xFF0C1035;
	static inline var C_PLAYHEAD  = 0xFFFF1E55;
	static inline var C_ROW_A     = 0xFF090915;
	static inline var C_ROW_B     = 0xFF070712;
	static inline var C_WIN_BG    = 0xEE07071C;
	static inline var C_WIN_TITLE = 0xFF0F0F28;
	static inline var C_WIN_BORD  = 0xFF1A2888;
	static inline var C_ACCENT    = 0xFF4466FF;
	static inline var C_ACCENT2   = 0xFFFF3366;
	static inline var C_GREEN     = 0xFF33DD88;
	static inline var C_YELLOW    = 0xFFFFCC33;
	static inline var C_TEXT      = 0xFFE0E0FF;
	static inline var C_DIM       = 0xFF4455AA;
	static inline var C_SEL_BOX   = 0xAAFFCC00;
	static inline var C_HOVER     = 0x334488FF;
	static inline var C_BAR_BG    = 0xFF08081E;
	static inline var C_STATUS_BG = 0xFF060618;

	// Colores de grupos en timeline
	static final GROUP_BG_COLS = [0xFF09091E, 0xFF090E16, 0xFF0A0916, 0xFF0E0910];
	static final GROUP_AC_COLS = [0xFF2244AA, 0xFF1A7A3A, 0xFF6A2A9A, 0xFF8A4A1A];

	// ═════════════════════════════════════════════════════════════════════════
	// CONSTRUCTOR
	// ═════════════════════════════════════════════════════════════════════════

	public function new()
	{
		super();

		manager       = pendingManager    ?? new ModChartManager([]);
		srcStrumsGrps = pendingStrumsData ?? [];
		pendingManager    = null;
		pendingStrumsData = null;

		rowCount  = srcStrumsGrps.length * 4;
		tlY       = SH - STAT_H - TL_H;
		gameAreaY = BAR_H;
		gameAreaH = tlY - BAR_H;
		gameAreaX = PANEL_L;
		gameAreaW = SW - PANEL_L - PANEL_R;

		fieldBufs.set("beat",     "0.00");
		fieldBufs.set("value",    "0.00");
		fieldBufs.set("duration", "1.00");

		// Inicializar estado colapsado de grupos
		for (_ in srcStrumsGrps) collapsedGroups.push(false);

		buildRhythmPatterns();
	}

	// ═════════════════════════════════════════════════════════════════════════
	// CREATE
	// ═════════════════════════════════════════════════════════════════════════

	override function create():Void
	{
		super.create();
		FlxG.mouse.visible = true;

		editorCam         = FlxG.camera;
		editorCam.bgColor = FlxColor.fromInt(C_BG);
		camera            = editorCam;

		var gameBgGrp = new FlxGroup(); add(gameBgGrp);
		selBoxGroup   = new FlxGroup(); add(selBoxGroup);
		strumHitGroup = new FlxGroup(); add(strumHitGroup);

		tlGroup       = new FlxGroup(); add(tlGroup);
		windowGroup   = new FlxGroup(); add(windowGroup);
		inspListGroup = new FlxGroup(); add(inspListGroup);

		buildGameBackground(gameBgGrp);
		setupEditorStrums();
		manager.replaceStrumsGroups(editorGroups);

		buildTopBar();
		buildStatusBar();
		buildTimeline();
		buildLeftPanel();
		buildRightPanel();

		beatLine = new FlxSprite(0, BAR_H);
		beatLine.makeGraphic(SW, Std.int(gameAreaH), FlxColor.fromInt(0x00FFFFFF));
		beatLine.alpha   = 0;
		beatLine.cameras = [editorCam];
		add(beatLine);

		strumHoverBox = new FlxSprite();
		strumHoverBox.makeGraphic(70, 70, FlxColor.fromInt(C_HOVER));
		strumHoverBox.alpha   = 0;
		strumHoverBox.cameras = [editorCam];
		strumHitGroup.add(strumHoverBox);

		buildHelpOverlay();
		buildEasingPreviewWindow();
		buildScriptWindow();

		initAudio();

		var bps       = bps();
		playheadBeat  = Math.max(0, Conductor.songPosition * bps / 1000.0);
		songPosition  = playheadBeat * Conductor.crochet;
		newBeat       = Math.round(playheadBeat * snapDiv) / snapDiv;
		fieldBufs.set("beat", fmt(newBeat));

		manager.seekToBeat(playheadBeat);
		applyManagerToStrums();
		pushUndo();
		refreshTimeline();
		refreshStrumPropWindow();
		setStatus("Editor v4 listo. Tab=Preview | H=HideUI | F11=FullGame | F1=Ayuda");
	}

	// ─────────────────────────────────────────────────────────────────────────
	// FONDO DEL ÁREA DE JUEGO
	// ─────────────────────────────────────────────────────────────────────────

	function buildGameBackground(grp:FlxGroup):Void
	{
		grp.add(mkBg(0, 0, SW, SH, C_BG));
		grp.add(mkBg(gameAreaX, gameAreaY, gameAreaW, gameAreaH, C_GAME_BG));

		var cols = 8;
		for (c in 0...(cols + 1))
		{
			var gx = gameAreaX + Std.int(c * gameAreaW / cols);
			grp.add(mkBg(gx, gameAreaY, 1, gameAreaH, C_GRID_V));
		}
		for (r in 0...9)
		{
			var gy = gameAreaY + Std.int(r * gameAreaH / 8);
			grp.add(mkBg(gameAreaX, gy, gameAreaW, 1, C_GRID_H));
		}

		grp.add(mkBg(gameAreaX, gameAreaY, 2, gameAreaH, 0xFF0F1A44));
		grp.add(mkBg(gameAreaX + gameAreaW - 2, gameAreaY, 2, gameAreaH, 0xFF0F1A44));

		grp.add(mkBg(0, BAR_H, PANEL_L, gameAreaH, 0xFF050510));
		grp.add(mkBg(PANEL_L, BAR_H, 1, gameAreaH + TL_H, 0xFF1020AA));

		grp.add(mkBg(SW - PANEL_R, BAR_H, PANEL_R, gameAreaH + TL_H, 0xFF050510));
		grp.add(mkBg(SW - PANEL_R, BAR_H, 1, gameAreaH + TL_H, 0xFF1020AA));
	}

	// ─────────────────────────────────────────────────────────────────────────
	// CREAR STRUMS DEL EDITOR
	// ─────────────────────────────────────────────────────────────────────────

	function setupEditorStrums():Void
	{
		editorGroups     = [];
		editorStrumBaseX = [];
		editorStrumBaseY = [];
		selBoxes         = [];
		strumHitBoxes    = [];
		strumLabels      = [];

		var ng    = srcStrumsGrps.length;
		var zoneW = gameAreaW / Math.max(1, ng);

		strumLineY = gameAreaY + gameAreaH * 0.22;

		var dirs      = ["←","↓","↑","→"];
		var dirColors = [0xFFDD44FF, 0xFF44CCFF, 0xFF44FF88, 0xFFFF4444];

		for (gi in 0...ng)
		{
			var src     = srcStrumsGrps[gi];
			var centerX = gameAreaX + gi * zoneW + zoneW / 2.0;
			var swag    = Note.swagWidth;
			var fitFact = Math.min(1.0, (zoneW * 0.85) / (swag * 4));
			var spacing = swag * fitFact;
			var startX  = centerX - spacing * 1.5;

			var gdata:StrumsGroupData = {
				id      : src.id,
				x       : startX,
				y       : strumLineY,
				cpu     : src.cpu,
				visible : true,
				spacing : spacing,
				scale   : 1.0
			};

			var edGrp = new StrumsGroup(gdata);
			editorGroups.push(edGrp);

			edGrp.strums.forEach(function(s:FlxSprite) {
				s.setGraphicSize(Std.int(s.width * fitFact));
				s.updateHitbox();
				s.centerOffsets();
				s.cameras = [editorCam];
				add(s);
			});

			var bx  : Array<Float>     = [];
			var by  : Array<Float>     = [];
			var sel : Array<FlxSprite> = [];
			var hbs : Array<FlxSprite> = [];
			var lbs : Array<FlxText>   = [];

			for (si in 0...4)
			{
				var strum = edGrp.getStrum(si);
				if (strum != null)
				{
					bx.push(strum.x);
					by.push(strum.y);

					var hitSz = Std.int(Math.max(64, Math.max(strum.width, strum.height) + 16));

					var selBox = new FlxSprite(strum.x - hitSz/2 + strum.width/2,
					                          strum.y - hitSz/2 + strum.height/2);
					selBox.makeGraphic(hitSz + 8, hitSz + 8, 0x00000000);
					drawBorderSprite(selBox, hitSz + 8, hitSz + 8, dirColors[si], 3);
					selBox.cameras = [editorCam];
					selBox.visible = false;
					selBoxGroup.add(selBox);
					sel.push(selBox);

					var hbSpr = new FlxSprite(strum.x - hitSz/2 + strum.width/2,
					                          strum.y - hitSz/2 + strum.height/2);
					hbSpr.makeGraphic(hitSz + 4, hitSz + 4, 0x00000000);
					drawBorderSprite(hbSpr, hitSz + 4, hitSz + 4, 0xFFFFFFFF, 1);
					hbSpr.alpha   = 0.12;
					hbSpr.cameras = [editorCam];
					strumHitGroup.add(hbSpr);
					hbs.push(hbSpr);

					var lbl = mkTxt(strum.x + strum.width/2 - 6,
					                strum.y + strum.height + 4,
					                dirs[si], 10, dirColors[si]);
					lbl.cameras = [editorCam];
					strumHitGroup.add(lbl);
					lbs.push(lbl);
				}
				else
				{
					bx.push(0); by.push(0);
					sel.push(null); hbs.push(null); lbs.push(null);
				}
			}

			editorStrumBaseX.push(bx);
			editorStrumBaseY.push(by);
			selBoxes.push(sel);
			strumHitBoxes.push(hbs);
			strumLabels.push(lbs);

			var gLabel = mkTxt(centerX - 40, strumLineY - 20,
			                   src.id + (src.cpu ? " [CPU]" : " [PLY]"), 10, C_DIM);
			gLabel.cameras = [editorCam];
			strumHitGroup.add(gLabel);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// DIBUJAR BORDE EN SPRITE
	// ─────────────────────────────────────────────────────────────────────────

	function drawBorderSprite(spr:FlxSprite, w:Int, h:Int, color:Int, thickness:Int):Void
	{
		var pix = spr.pixels;
		var c   = FlxColor.fromInt(color);
		// fillRect es órdenes de magnitud más rápido que setPixel32 en bucle.
		// Un sprite de 1160×678 con bucle pixel-a-pixel bloquea create() durante
		// varios segundos (>786 k iteraciones); con fillRect son 4 llamadas.
		pix.fillRect(new openfl.geom.Rectangle(0,         0,         w,         thickness), c); // top
		pix.fillRect(new openfl.geom.Rectangle(0,         h - thickness, w,     thickness), c); // bottom
		pix.fillRect(new openfl.geom.Rectangle(0,         0,         thickness, h),         c); // left
		pix.fillRect(new openfl.geom.Rectangle(w - thickness, 0,     thickness, h),         c); // right
		spr.pixels = pix;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// BARRA SUPERIOR
	// ─────────────────────────────────────────────────────────────────────────

	function buildTopBar():Void
	{
		add(mkBg(0, 0, SW, BAR_H, C_BAR_BG));
		add(mkBg(0, BAR_H - 1, SW, 1, C_TL_BORDER));

		var title = mkTxt(8, 7, "◈ MODCHART EDITOR v4", 13, C_ACCENT);
		title.bold = true;
		add(title);

		beatInfoLbl = mkTxt(200, 8, "Beat: 0.00  Step: 0  BPM: 120  0ms", 11, C_TEXT);
		add(beatInfoLbl);

		audioLbl = mkTxt(SW - 440, 8, "♪ Detenido", 11, 0xFF77FF99);
		add(audioLbl);

		volLbl = mkTxt(SW - 330, 8, "Vol: 100%", 11, C_DIM);
		add(volLbl);

		addBarBtn(SW - 250, 4,  "Vol−",       function() { volValue = Math.max(0, volValue - 0.1); applyVolume(); });
		addBarBtn(SW - 212, 4,  "Vol+",       function() { volValue = Math.min(1, volValue + 0.1); applyVolume(); });
		addBarBtn(SW - 172, 4,  "[H]ide",     function() toggleUIWindows());
		addBarBtn(SW - 122, 4,  "[Tab]Preview", function() togglePreview());
		addBarBtn(SW - 50,  4,  "[ESC]",      exitEditor);
	}

	function addBarBtn(x:Float, y:Float, lbl:String, cb:Void->Void):Void
	{
		var bg = mkBg(x - 2, y, lbl.length * 7.2 + 8, 22, 0xFF0A0A22);
		bg.alpha = 0.7;
		add(bg);
		var t = mkTxt(x + 2, y + 4, lbl, 9, C_ACCENT);
		add(t);
		hitBtns.push({ x: x - 2, y: y, w: lbl.length * 7.2 + 8, h: 22.0, cb: cb });
	}

	// ─────────────────────────────────────────────────────────────────────────
	// STATUS BAR
	// ─────────────────────────────────────────────────────────────────────────

	function buildStatusBar():Void
	{
		add(mkBg(0, SH - STAT_H, SW, STAT_H, C_STATUS_BG));
		add(mkBg(0, SH - STAT_H, SW, 1, C_TL_BORDER));

		statusTxt = mkTxt(8, SH - STAT_H + 5, "Listo.", 11, 0xFF77FF99);
		add(statusTxt);

		snapLbl = mkTxt(SW / 2 - 60, SH - STAT_H + 5,
		                'Snap: 1/${snapDiv}  |  Eventos: 0', 11, C_DIM);
		add(snapLbl);

		var sx = SW - 260.0;
		var sy = SH - STAT_H + 3.0;
		addStatusBtn(sx,      sy, "1/4",  function() { snapDiv = 4;  updateSnapLbl(); });
		addStatusBtn(sx + 38, sy, "1/8",  function() { snapDiv = 8;  updateSnapLbl(); });
		addStatusBtn(sx + 78, sy, "1/16", function() { snapDiv = 16; updateSnapLbl(); });
		addStatusBtn(sx + 122, sy, "Free", function() { snapDiv = 1;  updateSnapLbl(); });
		addStatusBtn(sx + 165, sy, "F11",  function() toggleFullGame());
	}

	function addStatusBtn(x:Float, y:Float, lbl:String, cb:Void->Void):Void
	{
		var t = mkTxt(x, y, lbl, 10, C_DIM);
		add(t);
		hitBtns.push({ x: x, y: y, w: lbl.length * 7.0 + 4, h: 18.0, cb: cb });
	}

	function updateSnapLbl():Void
	{
		if (snapLbl != null)
			snapLbl.text = 'Snap: 1/${snapDiv}  |  Eventos: ${manager.data.events.length}';
	}

	// ─────────────────────────────────────────────────────────────────────────
	// PANEL IZQUIERDO
	// ─────────────────────────────────────────────────────────────────────────

	function buildLeftPanel():Void
	{
		var px = 6.0;
		var py = BAR_H + 8.0;
		var pw = PANEL_L - 12.0;

		addSection(px, py, pw, "NUEVO EVENTO"); py += 22;

		add(mkBgRnd(px, py, pw, 18, 0xFF0A0A1E));
		add(mkTxt(px + 4, py + 2, "Tipo:", 10, C_DIM));
		lblType = mkTxt(px + 50, py + 2, (newType:String), 10, 0xFF4FC3F7);
		add(lblType);
		addSmBtn(px + pw - 28, py, "◄", function() cycleType(-1));
		addSmBtn(px + pw - 14, py, "►", function() cycleType(1));
		py += 22;

		add(mkBgRnd(px, py, pw, 18, 0xFF0A0A1E));
		add(mkTxt(px + 4, py + 2, "Target:", 10, C_DIM));
		lblTarget = mkTxt(px + 55, py + 2, newTarget, 10, 0xFF81C784);
		add(lblTarget);
		addSmBtn(px + pw - 28, py, "◄", function() cycleTarget(-1));
		addSmBtn(px + pw - 14, py, "►", function() cycleTarget(1));
		py += 22;

		add(mkBgRnd(px, py, pw, 18, 0xFF0A0A1E));
		add(mkTxt(px + 4, py + 2, "Strum:", 10, C_DIM));
		lblStrum = mkTxt(px + 55, py + 2, strumLbl(), 10, 0xFFFFB74D);
		add(lblStrum);
		addSmBtn(px + pw - 28, py, "◄", function() { newStrumI--; if (newStrumI<-1) newStrumI=3; });
		addSmBtn(px + pw - 14, py, "►", function() { newStrumI++; if (newStrumI>3) newStrumI=-1; });
		py += 22;

		add(mkTxt(px + 4, py + 2, "Beat:", 10, C_DIM));
		fldBeat = buildField(px + 55, py, pw - 59, "beat");
		py += 20;

		add(mkTxt(px + 4, py + 2, "Valor:", 10, C_DIM));
		fldVal = buildField(px + 55, py, pw - 59, "value");
		py += 20;

		add(mkTxt(px + 4, py + 2, "Dur (b):", 10, C_DIM));
		fldDur = buildField(px + 55, py, pw - 59, "duration");
		py += 20;

		add(mkBgRnd(px, py, pw, 18, 0xFF0A0A1E));
		add(mkTxt(px + 4, py + 2, "Ease:", 10, C_DIM));
		lblEase = mkTxt(px + 55, py + 2, (newEase:String), 10, 0xFFBA68C8);
		add(lblEase);
		addSmBtn(px + pw - 28, py, "◄", function() { cycleEaseDir(-1); drawEasingCurve(newEase); });
		addSmBtn(px + pw - 14, py, "►", function() { cycleEaseDir(1);  drawEasingCurve(newEase); });
		// Mini botón "👁" para preview de easing
		var eyeBg = mkBg(px, py, 48, 18, 0xFF0E0A20);
		add(eyeBg);
		var eyeTxt = mkTxt(px + 3, py + 2, "👁 Ease", 8, 0xFFBB88FF);
		add(eyeTxt);
		hitBtns.push({ x: px, y: py, w: 48.0, h: 18.0, cb: function() {
			toggleEasingPreview();
			drawEasingCurve(newEase);
		}});
		py += 26;

		var addBg = mkBgRnd(px, py, pw, 28, C_ACCENT);
		addBg.alpha = 0.9;
		add(addBg);
		var addTxt = mkTxt(px + pw / 2 - 40, py + 7, "+ AÑADIR EVENTO", 12, 0xFFFFFFFF);
		addTxt.bold = true;
		add(addTxt);
		hitBtns.push({ x: px, y: py, w: pw, h: 28, cb: onClickAdd });
		py += 34;

		var phBg = mkBgRnd(px, py, pw, 24, 0xFF224433);
		phBg.alpha = 0.9;
		add(phBg);
		add(mkTxt(px + pw / 2 - 50, py + 5, "⊕ Añadir en Playhead", 10, 0xFFAAFFCC));
		hitBtns.push({ x: px, y: py, w: pw, h: 24, cb: function() {
			newBeat = snapBeat(playheadBeat);
			fieldBufs.set("beat", fmt(newBeat));
			onClickAdd();
		}});
		py += 30;

		addSection(px, py, pw, "PATRONES RÁPIDOS"); py += 22;
		buildRhythmButtons(px, py, pw);
		py += 24 * Std.int((rhythmPatterns.length + 1) / 2) + 6;

		addSection(px, py, pw, "EVENTOS"); py += 22;

		evListStartY = py;
		evListEndY   = tlY - 4;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// PANEL DERECHO
	// ─────────────────────────────────────────────────────────────────────────

	function buildRightPanel():Void
	{
		var px = SW - PANEL_R + 6.0;
		var py = BAR_H + 8.0;
		var pw = PANEL_R - 12.0;

		addSection(px, py, pw, "ACCIONES"); py += 22;

		function toolBtn(label:String, col:Int, cb:Void->Void):Void {
			var b = mkBgRnd(px, py, pw, 26, col); b.alpha = 0.85; add(b);
			add(mkTxt(px + 8, py + 6, label, 11, 0xFFEEEEFF));
			hitBtns.push({ x: px, y: py, w: pw, h: 26, cb: cb });
			py += 30;
		}

		toolBtn("▶  PLAY / PAUSA  [Space]", 0xFF153A1A, onClickPlay);
		toolBtn("■  STOP + REINICIAR",       0xFF3A1515, onClickStop);
		toolBtn("💾  GUARDAR   Ctrl+S",       0xFF0E2244, onClickSave);
		toolBtn("📂  CARGAR",                 0xFF1A2030, onClickLoad);
		toolBtn("✕  LIMPIAR TODO",            0xFF3A1515, onClickNew);
		toolBtn("↩  DESHACER   Ctrl+Z",      0xFF1A1A2A, doUndo);
		toolBtn("↪  REHACER   Ctrl+Y",       0xFF1A1A2A, doRedo);
		toolBtn("📜  SCRIPTS",               0xFF121A2A, function() {
			if (scriptWin != null) { if (scriptWin.visible) hideWin(scriptWin); else { showWin(scriptWin); bringFront(scriptWin); } }
		});
		toolBtn("〜  EASE PREVIEW",          0xFF1A1030, function() {
			toggleEasingPreview();
			drawEasingCurve(newEase);
		});
		toolBtn("❓  AYUDA   F1",             0xFF152030, function() {
			showHelp = !showHelp;
			helpOverlay.visible = helpTxt.visible = showHelp;
		});

		py += 4;
		add(mkBg(px, py, pw, 1, C_TL_BORDER)); py += 8;

		addSection(px, py, pw, "INSPECTOR"); py += 22;

		inspTxt = mkTxt(px, py, "(sin selección)", 9, C_DIM);
		inspTxt.wordWrap  = true;
		inspTxt.fieldWidth = pw;
		add(inspTxt);
		py += 96;

		add(mkBg(px, py, pw, 1, C_TL_BORDER)); py += 8;
		addSection(px, py, pw, "STRUM PROPERTIES"); py += 22;
		strumPropStartY = py;
		strumPropEndY   = tlY - 4;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// HELPERS DE PANEL
	// ─────────────────────────────────────────────────────────────────────────

	function addSection(x:Float, y:Float, w:Float, title:String):Void
	{
		add(mkBgRnd(x, y, w, 18, 0xFF0C0C24));
		add(mkTxt(x + 6, y + 2, "— " + title + " —", 10, C_ACCENT));
	}

	function addSmBtn(x:Float, y:Float, label:String, cb:Void->Void):Void
	{
		add(mkBg(x, y, 14, 18, 0xFF0C0C24));
		add(mkTxt(x + 1, y + 2, label, 10, C_ACCENT));
		hitBtns.push({ x: x, y: y, w: 14.0, h: 18.0, cb: cb });
	}

	function buildField(x:Float, y:Float, w:Float, key:String):FlxText
	{
		add(mkBgRnd(x, y, w, 16, 0xFF040414));
		add(mkBg(x, y + 14, w, 1, C_ACCENT));
		var t = mkTxt(x + 4, y + 2, fieldBufs.get(key) ?? "0", 10, 0xFFFFDD44);
		add(t);
		hitFields.push({ x: x, y: y, w: w, h: 16.0, key: key });
		return t;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// PATRONES DE RITMO
	// ─────────────────────────────────────────────────────────────────────────

	function buildRhythmButtons(px:Float, py:Float, pw:Float):Void
	{
		var cols = 2;
		var bw   = (pw - 4) / cols;
		var bh   = 22.0;

		for (i in 0...rhythmPatterns.length)
		{
			var pat   = rhythmPatterns[i];
			var col   = i % cols;
			var row   = Std.int(i / cols);
			var bx    = px + col * (bw + 2);
			var byPos = py + row * (bh + 2);

			var bg = mkBgRnd(bx, byPos, bw, bh, 0xFF0E1A30); bg.alpha = 0.8; add(bg);
			add(mkTxt(bx + 4, byPos + 5, pat.name, 9, 0xFF88BBFF));
			var captPat = pat;
			hitBtns.push({ x: bx, y: byPos, w: bw, h: bh, cb: function() applyPattern(captPat) });
		}
	}

	function buildRhythmPatterns():Void
	{
		rhythmPatterns.push({ name: "Bounce X", events: [
			{beat:0, type:MOVE_X, value: 80, dur:2, ease:SINE_IN_OUT},
			{beat:2, type:MOVE_X, value:-80, dur:2, ease:SINE_IN_OUT},
			{beat:4, type:MOVE_X, value:  0, dur:1, ease:SINE_OUT}
		]});
		rhythmPatterns.push({ name: "Drop", events: [
			{beat:0, type:MOVE_Y, value:120, dur:1, ease:BOUNCE_OUT},
			{beat:2, type:MOVE_Y, value:0,   dur:1, ease:QUAD_IN}
		]});
		rhythmPatterns.push({ name: "Spin", events: [
			{beat:0, type:SPIN, value:720, dur:4, ease:LINEAR},
			{beat:4, type:SPIN, value:0,   dur:0, ease:INSTANT}
		]});
		rhythmPatterns.push({ name: "Pulse", events: [
			{beat:0,    type:SCALE, value:1.5, dur:0.25, ease:QUAD_OUT},
			{beat:0.25, type:SCALE, value:1,   dur:0.25, ease:QUAD_IN},
			{beat:0.5,  type:SCALE, value:1.5, dur:0.25, ease:QUAD_OUT},
			{beat:0.75, type:SCALE, value:1,   dur:0.25, ease:QUAD_IN}
		]});
		rhythmPatterns.push({ name: "Fade", events: [
			{beat:0, type:ALPHA, value:0, dur:2, ease:QUAD_IN},
			{beat:2, type:ALPHA, value:1, dur:2, ease:QUAD_OUT}
		]});
		rhythmPatterns.push({ name: "Shake", events: [
			{beat:0,   type:MOVE_X, value: 30, dur:0.1, ease:INSTANT},
			{beat:0.1, type:MOVE_X, value:-30, dur:0.1, ease:INSTANT},
			{beat:0.2, type:MOVE_X, value: 20, dur:0.1, ease:INSTANT},
			{beat:0.3, type:MOVE_X, value:-20, dur:0.1, ease:INSTANT},
			{beat:0.4, type:MOVE_X, value:  0, dur:0.1, ease:INSTANT}
		]});
	}

	function applyPattern(pat:RhythmPattern):Void
	{
		pushUndo();
		var baseBeat = snapBeat(playheadBeat);
		for (e in pat.events)
		{
			var ev = ModChartHelpers.makeEvent(
				baseBeat + e.beat, newTarget, newStrumI,
				e.type, e.value, e.dur, e.ease
			);
			manager.addEvent(ev);
		}
		manager.seekToBeat(playheadBeat);
		applyManagerToStrums();
		refreshTimeline();
		updateSnapLbl();
		setStatus('Patrón "${pat.name}" aplicado en beat ${fmt(baseBeat)}');
	}

	// ─────────────────────────────────────────────────────────────────────────
	// AUDIO
	// ─────────────────────────────────────────────────────────────────────────

	function initAudio():Void
	{
		if (FlxG.sound.music != null && FlxG.sound.music.playing)
			FlxG.sound.music.pause();
		vocals = null;
		applyVolume();
	}

	function applyVolume():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.volume = volValue;
		if (vocals != null)           vocals.volume           = volValue;
		if (volLbl != null)           volLbl.text = 'Vol: ${Std.int(volValue * 100)}%';
	}

	function seekAudioTo(ms:Float):Void
	{
		ms = Math.max(0, ms);
		if (FlxG.sound.music != null) FlxG.sound.music.time = ms;
		if (vocals != null)           vocals.time           = ms;
	}

	function pauseAudio():Void
	{
		if (FlxG.sound.music != null && FlxG.sound.music.playing) FlxG.sound.music.pause();
		if (vocals != null && vocals.playing) vocals.pause();
	}

	function resumeAudio():Void
	{
		if (FlxG.sound.music != null && !FlxG.sound.music.playing) FlxG.sound.music.resume();
		if (vocals != null && !vocals.playing) vocals.resume();
	}

	function updateAudioLabel():Void
	{
		if (audioLbl == null) return;
		var ms = (isPlaying && FlxG.sound.music != null) ? FlxG.sound.music.time : songPosition;
		var s  = Std.int(ms / 1000);
		var ts = '${Std.int(s / 60)}:${s % 60 < 10 ? "0" : ""}${s % 60}';
		audioLbl.text = isPlaying ? '♪ ▶ $ts' : '♪ ⏸ $ts';
	}

	// ─────────────────────────────────────────────────────────────────────────
	// APLICAR MODCHART A STRUMS
	// ─────────────────────────────────────────────────────────────────────────

	function applyManagerToStrums():Void
	{
		for (gi in 0...editorGroups.length)
		{
			var grp = editorGroups[gi];
			var src = gi < srcStrumsGrps.length ? srcStrumsGrps[gi] : null;
			var id  = src != null ? src.id : grp.id;

			for (si in 0...4)
			{
				var strum = grp.getStrum(si);
				if (strum == null || gi >= editorStrumBaseX.length) continue;

				var st = manager.getState(id, si);
				if (st != null)
				{
					strum.x     = editorStrumBaseX[gi][si] + st.offsetX;
					strum.y     = editorStrumBaseY[gi][si] + st.offsetY;
					strum.angle = st.angle;
					strum.alpha = FlxMath.bound(st.alpha, 0.05, 1.0);
					strum.scale.set(st.scaleX, st.scaleY);
				}
				else
				{
					strum.x     = editorStrumBaseX[gi][si];
					strum.y     = editorStrumBaseY[gi][si];
					strum.angle = 0;
					strum.alpha = 1;
					strum.scale.set(1, 1);
				}

				strum.updateHitbox();
				strum.centerOffsets();

				if (gi < strumHitBoxes.length && si < strumHitBoxes[gi].length && strumHitBoxes[gi][si] != null)
				{
					var hb    = strumHitBoxes[gi][si];
					var hitSz = Std.int(Math.max(64, Math.max(strum.width, strum.height) + 16));
					hb.x = strum.x - hitSz/2 + strum.width/2;
					hb.y = strum.y - hitSz/2 + strum.height/2;
				}
				if (gi < strumLabels.length && si < strumLabels[gi].length && strumLabels[gi][si] != null)
				{
					var lbl = strumLabels[gi][si];
					lbl.x = strum.x + strum.width/2 - 6;
					lbl.y = strum.y + strum.height + 2;
				}
				if (gi < selBoxes.length && si < selBoxes[gi].length && selBoxes[gi][si] != null)
				{
					var box   = selBoxes[gi][si];
					var hitSz = Std.int(Math.max(64, Math.max(strum.width, strum.height) + 16));
					box.x = strum.x - hitSz/2 + strum.width/2;
					box.y = strum.y - hitSz/2 + strum.height/2;
				}
			}
		}
	}

	// ═════════════════════════════════════════════════════════════════════════
	// TIMELINE MEJORADA CON GRUPOS + SCROLLBAR DEDICADO
	// ═════════════════════════════════════════════════════════════════════════

	function buildTimeline():Void
	{
		// Fondo base
		tlGroup.add(mkBg(0, tlY, SW, TL_H, C_TL_BG));
		tlGroup.add(mkBg(0, tlY, SW, 2, C_TL_BORDER));
		tlGroup.add(mkBg(0, tlY, SW, TL_RH, C_RULER));
		tlGroup.add(mkBg(0, tlY + TL_RH, SW, 1, C_TL_BORDER));

		// Label zoom
		zoomLbl = mkTxt(SW - PANEL_R - 160, tlY + 9, "Zoom: 16b", 11, C_DIM);
		tlGroup.add(zoomLbl);

		// Botones zoom
		addTLBtn(SW - PANEL_R - 215, tlY + 6, " + ", function() { beatsVisible = Math.max(BV_MIN, beatsVisible / 2);   refreshTimeline(); });
		addTLBtn(SW - PANEL_R - 193, tlY + 6, " − ", function() { beatsVisible = Math.min(BV_MAX, beatsVisible * 2);   refreshTimeline(); });
		addTLBtn(SW - PANEL_R - 169, tlY + 6, "ALL", function() { tlScroll = 0; beatsVisible = FlxMath.bound(getMaxBeat() + 4, BV_MIN, BV_MAX); refreshTimeline(); });

		// Botones adicionales en la ruler
		addTLBtn(PANEL_L + 6,  tlY + 6, "Scripts",  function() {
			if (scriptWin != null) { if (scriptWin.visible) hideWin(scriptWin); else { showWin(scriptWin); bringFront(scriptWin); } }
		});
		addTLBtn(PANEL_L + 60, tlY + 6, "Ease〜", function() {
			toggleEasingPreview();
			drawEasingCurve(newEase);
		});

		// Playhead (sin cubrir la scrollbar)
		playheadSpr = new FlxSprite(0, tlY);
		playheadSpr.makeGraphic(2, TL_H - TL_SB_H - 1, FlxColor.fromInt(C_PLAYHEAD));
		playheadSpr.cameras = [editorCam];
		tlGroup.add(playheadSpr);

		// ── Scrollbar horizontal dedicado ─────────────────────────────────────
		sbY      = tlY + TL_H - TL_SB_H - 1;
		sbTrackX = (PANEL_L : Float);
		sbTrackW = ((SW - PANEL_L - PANEL_R) : Float);

		// Separador top del scrollbar
		tlGroup.add(mkBg(0, Std.int(sbY), SW, 1, C_TL_BORDER));

		// Fondo del track
		var sbBg = mkBg(Std.int(sbTrackX), Std.int(sbY + 1), Std.int(sbTrackW), TL_SB_H - 1, 0xFF030310);
		tlGroup.add(sbBg);

		// Fondo interactivo del scrollbar (se dibuja en add() para mouse hit)
		tlScrollbarBg = new FlxSprite(sbTrackX, sbY + 1);
		tlScrollbarBg.makeGraphic(Std.int(sbTrackW), TL_SB_H - 1, FlxColor.fromInt(0xFF050518));
		tlScrollbarBg.cameras = [editorCam];
		add(tlScrollbarBg);

		// Thumb del scrollbar
		tlScrollbarThumb = new FlxSprite(sbTrackX, sbY + 2);
		tlScrollbarThumb.makeGraphic(60, TL_SB_H - 4, FlxColor.fromInt(0xFF2244BB));
		tlScrollbarThumb.cameras = [editorCam];
		add(tlScrollbarThumb);

		// Arrows en los extremos del scrollbar
		addTLBtn(0, sbY + 1, "◀", function() { tlScroll = Math.max(0, tlScroll - 1); refreshTimeline(); });
		addTLBtn(SW - PANEL_R - 18, sbY + 1, "▶", function() { tlScroll += 1; refreshTimeline(); });

		rowH = Math.max(12.0, (TL_H - TL_RH - TL_SB_H - 4) / Math.max(1, getVisibleRowCount()));
	}

	/** Cuenta filas visibles (excluyendo grupos colapsados) */
	function getVisibleRowCount():Int
	{
		var count = 0;
		for (gi in 0...srcStrumsGrps.length)
		{
			if (gi < collapsedGroups.length && collapsedGroups[gi])
				count += 1;  // solo la cabecera
			else
				count += 4;
		}
		return Std.int(Math.max(1, count));
	}

	public function refreshTimeline():Void
	{
		// Limpiar eventos anteriores
		for (es in evSprites)
		{
			tlGroup.remove(es.sp,     true); es.sp.destroy();
			tlGroup.remove(es.lbl,    true); es.lbl.destroy();
			tlGroup.remove(es.valLbl, true); es.valLbl.destroy();
		}
		evSprites = [];

		var ppb  = (SW - PANEL_L - PANEL_R) / beatsVisible;
		var tlOX = (PANEL_L : Float);   // x origen de la timeline
		var dirs = ["L","D","U","R"];

		// ── Filas con grupos visuales ─────────────────────────────────────────
		var curRow = 0;
		for (gi in 0...srcStrumsGrps.length)
		{
			var gc         = srcStrumsGrps[gi];
			var collapsed  = (gi < collapsedGroups.length) ? collapsedGroups[gi] : false;
			var groupBgCol = GROUP_BG_COLS[gi % GROUP_BG_COLS.length];
			var groupAcCol = GROUP_AC_COLS[gi % GROUP_AC_COLS.length];

			if (collapsed)
			{
				// ── Grupo colapsado: solo un header ──────────────────────────
				var ry = tlY + TL_RH + curRow * rowH;
				tlGroup.add(mkBg(0, ry, SW, rowH - 1, groupBgCol));
				tlGroup.add(mkBg(0, ry, 4, rowH - 1, groupAcCol));

				var hTxt = mkTxt(8, ry + 2, '▶ ${gc.id}  (${gc.cpu?"CPU":"PLY"}) — collapsed', 9, FlxColor.fromInt(groupAcCol + 0x004444FF));
				tlGroup.add(hTxt);

				// Click para expandir
				var captGi = gi;
				hitBtns.push({ x: 0, y: ry, w: PANEL_L + 80.0, h: rowH,
				               cb: function() { collapsedGroups[captGi] = false; rowH = Math.max(12.0, (TL_H - TL_RH - TL_SB_H - 4) / Math.max(1, getVisibleRowCount())); refreshTimeline(); }});
				curRow++;
			}
			else
			{
				// ── Grupo expandido ──────────────────────────────────────────
				var groupStartRow = curRow;

				for (si in 0...4)
				{
					var ry = tlY + TL_RH + curRow * rowH;
					var rowCol = si % 2 == 0 ? groupBgCol : (groupBgCol + 0x00030303);
					tlGroup.add(mkBg(0, ry, SW, rowH - 1, rowCol));

					// Borde izquierdo de color de grupo
					tlGroup.add(mkBg(0, ry, 4, rowH - 1, groupAcCol));

					// Etiqueta de strum
					var rowLbl = mkTxt(tlOX + 4, ry + 2, '${gc.id.substr(0,4)}.${dirs[si]}', 8, C_DIM);
					tlGroup.add(rowLbl);

					curRow++;
				}

				// Header del grupo a la izquierda (ocupa toda la altura del grupo)
				var groupH = 4 * rowH - 1;
				var ghY    = tlY + TL_RH + groupStartRow * rowH;
				tlGroup.add(mkBg(0, ghY, PANEL_L - 1, Std.int(groupH), 0xFF06061C));
				tlGroup.add(mkBg(0, ghY, 4, Std.int(groupH), groupAcCol));

				// Nombre del grupo centrado verticalmente
				var ghTxt = mkTxt(6, ghY + groupH / 2 - 10,
				                  gc.id + "\n" + (gc.cpu ? "[CPU]" : "[PLY]"), 9,
				                  FlxColor.fromInt(groupAcCol + 0x00333377));
				ghTxt.alignment = "center";
				ghTxt.fieldWidth = PANEL_L - 10;
				tlGroup.add(ghTxt);

				// Click en header para colapsar
				var captGi = gi;
				hitBtns.push({ x: 0, y: ghY, w: PANEL_L - 1, h: groupH,
				               cb: function() { collapsedGroups[captGi] = true; rowH = Math.max(12.0, (TL_H - TL_RH - TL_SB_H - 4) / Math.max(1, getVisibleRowCount())); refreshTimeline(); }});

				// Separador entre grupos
				if (gi < srcStrumsGrps.length - 1)
				{
					var sepY = ghY + groupH;
					tlGroup.add(mkBg(0, Std.int(sepY), SW, 2, FlxColor.fromInt(groupAcCol)));
				}
			}
		}

		// ── Líneas de beat / step en el área de la timeline ──────────────────
		var startB = Std.int(tlScroll);
		var endB   = Std.int(tlScroll + beatsVisible) + 2;
		var trackH = TL_H - TL_RH - TL_SB_H - 4;

		for (b in startB...(endB + 1))
		{
			var bx = Std.int(tlOX + (b - tlScroll) * ppb);
			if (bx < PANEL_L - 10 || bx > SW - PANEL_R + 10) continue;

			var isMeasure = b % 4 == 0;
			tlGroup.add(mkBg(bx, tlY + TL_RH, 1, trackH,
			             isMeasure ? 0xFF2233AA : C_BEAT_LINE));

			var numTxt = mkTxt(bx + 3, tlY + 8,
			             b % 4 == 0 ? 'M${Std.int(b/4)}b${b}' : Std.string(b),
			             isMeasure ? 11 : 9,
			             isMeasure ? C_TEXT : C_DIM);
			tlGroup.add(numTxt);

			for (st in 1...snapDiv)
			{
				var sx = Std.int(bx + st * ppb / snapDiv);
				if (sx >= PANEL_L && sx < SW - PANEL_R)
					tlGroup.add(mkBg(sx, tlY + TL_RH, 1, trackH,
					            st % (snapDiv / 4) == 0 ? C_BEAT_LINE : C_STEP_LINE));
			}
		}

		// ── Sprites de eventos ────────────────────────────────────────────────
		for (ev in manager.data.events)
		{
			for (ri in getEvRows(ev))
			{
				var ry  = tlY + TL_RH + ri * rowH;
				var ex  = tlOX + (ev.beat - tlScroll) * ppb;
				var ew  = Math.max(8.0, ev.duration * ppb);

				if (ex + ew < PANEL_L || ex > SW - PANEL_R) continue;

				var isSelected = selectedEv == ev;

				var sp = new FlxSprite(ex, ry + 1);
				sp.makeGraphic(Std.int(Math.max(8, ew)), Std.int(rowH - 3),
				               FlxColor.fromInt(ev.color));
				sp.alpha   = isSelected ? 1.0 : 0.8;
				sp.cameras = [editorCam];

				if (isSelected)
					drawBorderSprite(sp, Std.int(sp.width), Std.int(sp.height), 0xFFFFFFFF, 2);

				var typeStr = (ev.type:String);
				var lbl = mkTxt(ex + 3, ry + 2, typeStr.substr(0, 7), 8, 0xFF000000);
				lbl.cameras = [editorCam];

				var valLbl = mkTxt(ex + 3, ry + rowH / 2, '→${fmt(ev.value)}', 7, 0xFF000000);
				valLbl.alpha   = 0.8;
				valLbl.cameras = [editorCam];

				tlGroup.add(sp);
				tlGroup.add(lbl);
				tlGroup.add(valLbl);

				evSprites.push({ sp: sp, lbl: lbl, valLbl: valLbl, ev: ev });
			}
		}

		// Playhead siempre al frente
		tlGroup.remove(playheadSpr);
		syncPlayhead();
		tlGroup.add(playheadSpr);

		if (zoomLbl != null) zoomLbl.text = 'Zoom: ${Std.int(beatsVisible)}b';
		updateSnapLbl();
		refreshScrollbar();
	}

	function syncPlayhead():Void
	{
		var ppb = (SW - PANEL_L - PANEL_R) / beatsVisible;
		playheadSpr.x = PANEL_L + (playheadBeat - tlScroll) * ppb;
	}

	function getEvRows(ev:ModChartEvent):Array<Int>
	{
		// Mapear eventos a filas visibles (respetando grupos colapsados)
		var rows:Array<Int> = [];
		var curRow = 0;

		for (gi in 0...srcStrumsGrps.length)
		{
			var g         = srcStrumsGrps[gi];
			var collapsed = (gi < collapsedGroups.length) ? collapsedGroups[gi] : false;
			var ok = ev.target == "all"
				|| (ev.target == "player" && !g.cpu)
				|| (ev.target == "cpu"    &&  g.cpu)
				|| ev.target == g.id;

			if (!ok) { curRow += collapsed ? 1 : 4; continue; }

			if (collapsed)
			{
				rows.push(curRow);
				curRow++;
			}
			else
			{
				if (ev.strumIdx == -1)
					for (si in 0...4) rows.push(curRow + si);
				else
					rows.push(curRow + ev.strumIdx);
				curRow += 4;
			}
		}
		return rows;
	}

	// ═════════════════════════════════════════════════════════════════════════
	// SCROLLBAR HORIZONTAL DEDICADO
	// ═════════════════════════════════════════════════════════════════════════

	function refreshScrollbar():Void
	{
		if (tlScrollbarThumb == null) return;

		var maxBeat = Math.max(beatsVisible + 1, getMaxBeat() + 8);
		var ratio   = beatsVisible / maxBeat;
		var thumbW  = Math.max(16.0, sbTrackW * ratio);
		var maxScroll = maxBeat - beatsVisible;
		var scrollRatio = maxScroll > 0 ? tlScroll / maxScroll : 0;
		var thumbX  = sbTrackX + scrollRatio * (sbTrackW - thumbW);

		tlScrollbarThumb.setGraphicSize(Std.int(thumbW), TL_SB_H - 4);
		tlScrollbarThumb.updateHitbox();
		tlScrollbarThumb.x = thumbX;
		tlScrollbarThumb.y = sbY + 2;

		// Color del thumb: más brillante cuando se arrastra
		var col = scrollbarDragging ? 0xFF4488FF : 0xFF2244BB;
		tlScrollbarThumb.makeGraphic(Std.int(thumbW), TL_SB_H - 4, FlxColor.fromInt(col));
	}

	// ═════════════════════════════════════════════════════════════════════════
	// EASING PREVIEW WINDOW
	// ═════════════════════════════════════════════════════════════════════════

	function buildEasingPreviewWindow():Void
	{
		var ww = 280.0;
		var wh = 260.0;
		var wx = gameAreaX + gameAreaW / 2 - ww / 2;
		var wy = gameAreaY + 10.0;

		easingPreviewWin = mkWin("〜 Ease Preview", wx, wy, ww, wh);
		addToWinGroup(easingPreviewWin);
		windows.push(easingPreviewWin);
		hideWin(easingPreviewWin);
	}

	function toggleEasingPreview():Void
	{
		easingPreviewOpen = !easingPreviewOpen;
		if (easingPreviewOpen)
		{
			showWin(easingPreviewWin);
			bringFront(easingPreviewWin);
			easingPrevEase = "";  // forzar redibujado
			drawEasingCurve(newEase);
		}
		else hideWin(easingPreviewWin);
		setStatus(easingPreviewOpen ? "Ease Preview abierto" : "Ease Preview cerrado");
	}

	function drawEasingCurve(ease:ModEase):Void
	{
		if (easingPreviewWin == null) return;
		if (!easingPreviewOpen)       return;
		if ((ease:String) == easingPrevEase) return;
		easingPrevEase = (ease:String);

		// Limpiar sprites anteriores
		for (s in easingCurveSprites)
		{
			if (easingPreviewWin.contentGroup != null)
				easingPreviewWin.contentGroup.remove(s, true);
			s.destroy();
		}
		easingCurveSprites = [];

		if (easingPreviewLbl != null)
		{
			if (easingPreviewWin.contentGroup != null)
				easingPreviewWin.contentGroup.remove(easingPreviewLbl, true);
			easingPreviewLbl.destroy();
			easingPreviewLbl = null;
		}

		var wx  = easingPreviewWin.x;
		var wy  = easingPreviewWin.y;
		var pad = 22.0;
		var cw  = easingPreviewWin.w - pad * 2;
		var ch  = easingPreviewWin.h - 52.0 - pad;
		var ox  = wx + pad;
		var oy  = wy + 40.0 + pad;

		inline function addC(s:FlxSprite):Void
		{
			s.cameras = [editorCam];
			easingPreviewWin.contentGroup.add(s);
			easingCurveSprites.push(s);
		}

		// Fondo
		addC(mkRaw(ox - 2, oy - 2, Std.int(cw + 4), Std.int(ch + 4), 0xFF030312));

		// Grid
		var gSteps = 4;
		for (i in 0...(gSteps + 1))
		{
			addC(mkRaw(Std.int(ox + i * cw / gSteps), Std.int(oy), 1, Std.int(ch), 0xFF0E0E28));
			addC(mkRaw(Std.int(ox), Std.int(oy + i * ch / gSteps), Std.int(cw), 1, 0xFF0E0E28));
		}

		// Eje Y central (t=0.5 reference)
		addC(mkRaw(Std.int(ox + cw / 2), Std.int(oy), 1, Std.int(ch), 0xFF151530));

		// Bordes del gráfico
		addC(mkRaw(Std.int(ox),           Std.int(oy),      Std.int(cw), 1, 0xFF1A3A8A));
		addC(mkRaw(Std.int(ox),           Std.int(oy + ch), Std.int(cw), 1, 0xFF1A3A8A));
		addC(mkRaw(Std.int(ox),           Std.int(oy),      1, Std.int(ch), 0xFF1A3A8A));
		addC(mkRaw(Std.int(ox + cw - 1),  Std.int(oy),      1, Std.int(ch + 1), 0xFF1A3A8A));

		// Curva de easing
		var samples = Std.int(cw);
		var prevPy  = -999.0;
		var prevPx  = 0.0;

		for (si in 0...samples)
		{
			var t   = si / (samples - 1);
			var val = ModChartHelpers.applyEase(ease, t);
			var px  = ox + t * cw;
			var py  = oy + ch - val * ch;
			var clampPy = Math.max(oy - 10, Math.min(oy + ch + 10, py));

			// Punto principal
			var dot = mkRaw(Std.int(px), Std.int(clampPy), 2, 2, 0xFF4466FF);
			addC(dot);

			// Linha entre pontos
			if (prevPy > -900 && Math.abs(py - prevPy) > 1)
			{
				var steps2 = Std.int(Math.min(30, Math.abs(py - prevPy)));
				for (li in 1...steps2)
				{
					var lx  = prevPx + (px - prevPx) * li / steps2;
					var ly  = prevPy + (py - prevPy) * li / steps2;
					var cly = Math.max(oy - 10, Math.min(oy + ch + 10, ly));
					var lp  = mkRaw(Std.int(lx), Std.int(cly), 1, 1, 0xFF3355EE);
					lp.alpha = 0.7;
					addC(lp);
				}
			}
			prevPy = py;
			prevPx = px;
		}

		// Marcadores inicio/fin
		addC(mkRaw(Std.int(ox),       Std.int(oy + ch - 3), 5, 5, 0xFF33DD88));
		addC(mkRaw(Std.int(ox+cw-4), Std.int(oy - 2),        5, 5, 0xFFFF3366));

		// Etiqueta de nombre del ease
		easingPreviewLbl = mkTxt(ox, wy + 30.0, (ease:String), 11, FlxColor.fromInt(C_ACCENT));
		easingPreviewLbl.bold    = true;
		easingPreviewLbl.cameras = [editorCam];
		if (easingPreviewWin.contentGroup != null)
			easingPreviewWin.contentGroup.add(easingPreviewLbl);

		// Etiqueta "0 → 1"
		var rangeLbl = mkTxt(ox + cw - 28, wy + 30.0, "0→1", 8, FlxColor.fromInt(C_DIM));
		rangeLbl.cameras = [editorCam];
		if (easingPreviewWin.contentGroup != null)
			easingPreviewWin.contentGroup.add(rangeLbl);

		setStatus('Ease preview: ${(ease:String)}');
	}

	// ═════════════════════════════════════════════════════════════════════════
	// SCRIPTS EXTERNOS
	// ═════════════════════════════════════════════════════════════════════════

	function buildScriptWindow():Void
	{
		var ww = 320.0;
		var wh = 300.0;
		var wx = SW / 2 - ww / 2;
		var wy = gameAreaY + gameAreaH / 2 - wh / 2;

		scriptWin = mkWin("📜 Scripts Externos", wx, wy, ww, wh);
		addToWinGroup(scriptWin);
		windows.push(scriptWin);

		var cx = wx + 10.0;
		var cy = wy + 32.0;
		var cw = ww - 20.0;

		var desc = mkTxt(cx, cy,
			"Importa eventos desde un archivo JSON externo.\nFormato: array de objetos de evento.", 9, C_DIM);
		desc.fieldWidth = cw;
		desc.wordWrap = true;
		scriptWin.contentGroup.add(desc);
		cy += 34;

		// Botón cargar
		var lBg = mkRaw(cx, cy, cw, 26, 0xFF081828); scriptWin.contentGroup.add(lBg);
		var lTxt = mkTxt(cx + cw/2 - 62, cy + 6, "📂  Cargar Script (.json)", 10, FlxColor.fromInt(C_ACCENT));
		scriptWin.contentGroup.add(lTxt);
		hitBtns.push({ x: cx, y: cy, w: cw, h: 26.0, cb: onLoadScript });
		cy += 32;

		// Botón exportar
		var eBg = mkRaw(cx, cy, cw, 26, 0xFF082820); scriptWin.contentGroup.add(eBg);
		var eTxt = mkTxt(cx + cw/2 - 60, cy + 6, "💾  Exportar como Script", 10, FlxColor.fromInt(C_GREEN));
		scriptWin.contentGroup.add(eTxt);
		hitBtns.push({ x: cx, y: cy, w: cw, h: 26.0, cb: onExportScript });
		cy += 32;

		// Separador
		scriptWin.contentGroup.add(mkRaw(cx, cy, cw, 1, C_TL_BORDER));
		cy += 8;

		// Formato de ejemplo
		var fmtBg = mkRaw(cx, cy, cw, 80, 0xFF040412);
		scriptWin.contentGroup.add(fmtBg);
		var fmtTxt = mkTxt(cx + 4, cy + 4,
			'Formato esperado:\n[\n  {\n    "beat":0, "type":"moveX",\n    "value":100, "dur":2,\n    "ease":"quadOut",\n    "target":"player", "strum":-1\n  }\n]',
			8, 0xFF3355AA);
		fmtTxt.fieldWidth = cw - 8;
		fmtTxt.wordWrap = true;
		scriptWin.contentGroup.add(fmtTxt);
		cy += 84;

		// Status
		scriptStatusTxt = mkTxt(cx, cy, "Sin script cargado.", 9, C_DIM);
		scriptStatusTxt.fieldWidth = cw;
		scriptStatusTxt.wordWrap = true;
		scriptWin.contentGroup.add(scriptStatusTxt);

		hideWin(scriptWin);
	}

	function onLoadScript():Void
	{
		#if sys
		var songName = manager.data.song.toLowerCase();
		var searchPaths = [
			'modcharts/scripts/${songName}.json',
			'assets/scripts/modcharts/${songName}.json',
			'scripts/modchart_${songName}.json',
			'modchart_${songName}.json'
		];

		for (p in searchPaths)
		{
			if (sys.FileSystem.exists(p))
			{
				try {
					var content = sys.io.File.getContent(p);
					var count   = parseModScript(content);
					scriptFilePath = p;
					if (scriptStatusTxt != null)
						scriptStatusTxt.text = '✓ ${count} eventos importados\nArchivo: ${p}';
					setStatus('Script: ${count} eventos importados de "${p}"');
					return;
				} catch (e:Dynamic) {
					if (scriptStatusTxt != null)
						scriptStatusTxt.text = 'Error al parsear: ${e}';
					setStatus('Error en script: ${e}');
					return;
				}
			}
		}

		if (scriptStatusTxt != null)
			scriptStatusTxt.text = 'No encontrado para "${songName}".\nBusqué en:\n${searchPaths.join("\n")}';
		setStatus('Script no encontrado para: ${songName}');
		#else
		// HTML5: usar FlxG.save
		if (FlxG.save.data.modchart_script != null)
		{
			try {
				var count = parseModScript(FlxG.save.data.modchart_script);
				if (scriptStatusTxt != null) scriptStatusTxt.text = '✓ ${count} eventos desde save.';
				setStatus('Script cargado desde save: ${count} eventos.');
			} catch (e:Dynamic) {
				if (scriptStatusTxt != null) scriptStatusTxt.text = 'Error: ${e}';
			}
		}
		else
		{
			if (scriptStatusTxt != null) scriptStatusTxt.text = 'Sin script en save.';
		}
		#end
	}

	function onExportScript():Void
	{
		var evArr = manager.data.events;
		var arr:Array<Dynamic> = [];
		for (ev in evArr)
		{
			arr.push({
				beat   : ev.beat,
				type   : (ev.type:String),
				value  : ev.value,
				dur    : ev.duration,
				ease   : (ev.ease:String),
				target : ev.target,
				strum  : ev.strumIdx,
				label  : ev.label
			});
		}
		var json = haxe.Json.stringify(arr, null, "  ");

		#if sys
		var songName = manager.data.song.toLowerCase();
		try {
			var dir = 'modcharts/scripts/';
			if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			var p   = '${dir}${songName}.json';
			sys.io.File.saveContent(p, json);
			if (scriptStatusTxt != null) scriptStatusTxt.text = '✓ Exportado: ${p}';
			setStatus('Script exportado: ${p}');
		} catch (e:Dynamic) {
			setStatus('Error al exportar: ${e}');
		}
		#else
		FlxG.save.data.modchart_script = json;
		FlxG.save.flush();
		if (scriptStatusTxt != null) scriptStatusTxt.text = '✓ Exportado en save.';
		setStatus('Script exportado en save.');
		#end
	}

	function parseModScript(json:String):Int
	{
		pushUndo();
		var arr:Array<Dynamic> = haxe.Json.parse(json);
		if (arr == null || !Std.isOfType(arr, Array))
			throw "JSON inválido: se esperaba un array";

		var count = 0;
		for (raw in arr)
		{
			var beat   : Float        = (raw.beat   != null) ? raw.beat   : 0.0;
			var type   : ModEventType = (raw.type   != null) ? (raw.type:String)  : "moveX";
			var value  : Float        = (raw.value  != null) ? raw.value  : 0.0;
			var dur    : Float        = (raw.dur    != null) ? raw.dur    : 0.0;
			var ease   : ModEase      = (raw.ease   != null) ? (raw.ease:String) : "linear";
			var target : String       = (raw.target != null) ? raw.target : "player";
			var strum  : Int          = (raw.strum  != null) ? Std.int(raw.strum) : -1;

			var ev = ModChartHelpers.makeEvent(beat, target, strum, type, value, dur, ease);
			if (raw.label != null) ev.label = raw.label;
			manager.addEvent(ev);
			count++;
		}

		refreshTimeline();
		updateSnapLbl();
		return count;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// STRUM PROPERTIES
	// ─────────────────────────────────────────────────────────────────────────

	function refreshStrumPropWindow():Void
	{
		for (t in strumPropTxts) { remove(t, true); t.destroy(); }
		strumPropTxts = [];
		strumPropBtns = [];

		var px = SW - PANEL_R + 6.0;
		var py = strumPropStartY;
		var pw = PANEL_R - 12.0;

		if (selectedGroupIdx < 0 || selectedStrumIdx < 0)
		{
			var t = mkTxt(px + 4, py, "Haz click sobre una flecha\ndel área de juego.", 9, C_DIM);
			t.wordWrap   = true;
			t.fieldWidth = pw;
			add(t);
			strumPropTxts.push(t);
			return;
		}

		var gi     = selectedGroupIdx;
		var si     = selectedStrumIdx;
		var src    = srcStrumsGrps[gi];
		var st     = manager.getState(src.id, si);
		var dnames = ["LEFT","DOWN","UP","RIGHT"];

		var title = mkTxt(px, py, '${src.id} / ${dnames[si]}', 10, C_ACCENT);
		title.bold = true;
		add(title); strumPropTxts.push(title); py += 16;

		var tgtBg = mkBgRnd(px, py, pw, 18, 0xFF0E2215); add(tgtBg); strumPropTxts.push(tgtBg);
		var tgtT  = mkTxt(px + 6, py + 2, "→ Usar como target", 9, C_GREEN);
		add(tgtT); strumPropTxts.push(tgtT);
		strumPropBtns.push({ x: px, y: py, w: pw, h: 18,
		                      cb: function() { newTarget = src.id; newStrumI = si; }});
		py += 22;

		function propRow(label:String, val:Float, etype:ModEventType, step:Float):Void
		{
			var bg = mkBgRnd(px, py, pw, 18, 0xFF080818); add(bg); strumPropTxts.push(bg);
			var lt = mkTxt(px + 4, py + 2, '$label: ${fmt2(val)}', 10, C_TEXT);
			add(lt); strumPropTxts.push(lt);
			var bm = mkTxt(px + pw - 26, py + 2, "−", 11, C_ACCENT2);
			var bp = mkTxt(px + pw - 12, py + 2, "+", 11, C_GREEN);
			add(bm); add(bp); strumPropTxts.push(bm); strumPropTxts.push(bp);
			var cT = etype; var cS = step; var cGi = gi; var cSi = si; var cId = src.id;
			strumPropBtns.push({ x: px+pw-26, y: py, w: 14, h: 18, cb: function() addQuickEvent(cGi,cSi,cT,-cS,cId) });
			strumPropBtns.push({ x: px+pw-12, y: py, w: 14, h: 18, cb: function() addQuickEvent(cGi,cSi,cT, cS,cId) });
			py += 22;
		}

		propRow("X",     st != null ? st.offsetX : 0.0, MOVE_X,  10.0);
		propRow("Y",     st != null ? st.offsetY : 0.0, MOVE_Y,  10.0);
		propRow("Angle", st != null ? st.angle   : 0.0, ANGLE,   15.0);
		propRow("Alpha", st != null ? st.alpha   : 1.0, ALPHA,    0.1);
		propRow("ScaleX",st != null ? st.scaleX  : 1.0, SCALE_X,  0.1);
		propRow("ScaleY",st != null ? st.scaleY  : 1.0, SCALE_Y,  0.1);

		var rstBg = mkBgRnd(px, py, pw, 20, 0xFF221010); add(rstBg); strumPropTxts.push(rstBg);
		var rstT  = mkTxt(px + pw/2 - 24, py + 3, "RESET STRUM", 10, C_ACCENT2);
		add(rstT); strumPropTxts.push(rstT);
		strumPropBtns.push({ x: px, y: py, w: pw, h: 20, cb: function() {
			pushUndo();
			var ev = ModChartHelpers.makeEvent(snapBeat(playheadBeat), src.id, si, RESET, 0, 0, INSTANT);
			manager.addEvent(ev);
			manager.seekToBeat(playheadBeat);
			applyManagerToStrums();
			refreshTimeline();
			refreshStrumPropWindow();
		}});
	}

	function addQuickEvent(gi:Int, si:Int, etype:ModEventType, delta:Float, srcId:String):Void
	{
		pushUndo();
		var ev = ModChartHelpers.makeEvent(snapBeat(playheadBeat), srcId, si, etype, delta, 0, INSTANT);
		manager.addEvent(ev);
		manager.seekToBeat(playheadBeat);
		applyManagerToStrums();
		refreshTimeline();
		refreshStrumPropWindow();
		setStatus('+ ${(etype:String)} ${delta>0?"+":""}${fmt(delta)} @b${fmt(ev.beat)}');
	}

	// ═════════════════════════════════════════════════════════════════════════
	// UPDATE
	// ═════════════════════════════════════════════════════════════════════════

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		handleKeyboard();
		handleMouse(elapsed);

		if (isPlaying)
		{
			if (FlxG.sound.music != null && FlxG.sound.music.playing)
				songPosition = FlxG.sound.music.time;
			else
				songPosition += elapsed * 1000;

			playheadBeat = songPosition / Conductor.crochet;

			var margin = beatsVisible * 0.1;
			if (playheadBeat > tlScroll + beatsVisible - margin)
				tlScroll = playheadBeat - beatsVisible + margin;
			else if (playheadBeat < tlScroll)
				tlScroll = Math.max(0, playheadBeat - margin);

			manager.seekToBeat(playheadBeat);
			applyManagerToStrums();
			syncPlayhead();
			refreshScrollbar();

			var bi = Std.int(playheadBeat);
			if (bi != lastBeatInt) { lastBeatInt = bi; beatAlpha = 0.35; }
		}

		if (beatAlpha > 0)
		{
			beatAlpha = Math.max(0, beatAlpha - elapsed * 3.5);
			beatLine.alpha = beatAlpha;
		}

		for (edGrp in editorGroups) edGrp.update();

		Conductor.songPosition = songPosition;
		updateLabels();
		refreshEvList();
		updateAudioLabel();

		// Actualizar easing preview si cambió el ease
		if (easingPreviewOpen && lblEase != null && (newEase:String) != easingPrevEase)
			drawEasingCurve(newEase);
	}

	function updateLabels():Void
	{
		if (beatInfoLbl != null)
			beatInfoLbl.text = 'Beat: ${fmt(playheadBeat)}  Step: ${Std.int(playheadBeat*4)}  BPM: ${fmt(Conductor.bpm)}  ${Std.int(songPosition)}ms';

		if (lblType   != null) lblType.text    = ModChartHelpers.typeLabel(newType);
		if (lblTarget != null) lblTarget.text  = newTarget;
		if (lblStrum  != null) lblStrum.text   = strumLbl();
		if (lblEase   != null) lblEase.text    = (newEase:String);

		var fp = focusField;
		if (fldBeat != null) fldBeat.text = (fp=="beat"     ? "▌" : "") + (fieldBufs.get("beat")     ?? "0");
		if (fldVal  != null) fldVal.text  = (fp=="value"    ? "▌" : "") + (fieldBufs.get("value")    ?? "0");
		if (fldDur  != null) fldDur.text  = (fp=="duration" ? "▌" : "") + (fieldBufs.get("duration") ?? "1");
	}

	// ── Teclado ───────────────────────────────────────────────────────────────

	function handleKeyboard():Void
	{
		if (FlxG.keys.justPressed.ESCAPE) { exitEditor(); return; }
		if (FlxG.keys.justPressed.F1)
		{
			showHelp = !showHelp;
			helpOverlay.visible = helpTxt.visible = showHelp;
		}
		if (FlxG.keys.justPressed.TAB)    togglePreview();
		if (FlxG.keys.justPressed.H && focusField == "") toggleUIWindows();
		if (FlxG.keys.justPressed.F11)    toggleFullGame();
		if (FlxG.keys.justPressed.SPACE)  togglePlay();
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Z) doUndo();
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Y) doRedo();
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S) onClickSave();

		if (FlxG.keys.justPressed.ONE   && focusField == "") { snapDiv = 4;  updateSnapLbl(); }
		if (FlxG.keys.justPressed.TWO   && focusField == "") { snapDiv = 8;  updateSnapLbl(); }
		if (FlxG.keys.justPressed.THREE && focusField == "") { snapDiv = 16; updateSnapLbl(); }

		if (focusField == "")
		{
			var step = 1.0 / snapDiv;
			if (FlxG.keys.justPressed.LEFT)  seekToBeat(playheadBeat - step);
			if (FlxG.keys.justPressed.RIGHT) seekToBeat(playheadBeat + step);
			if (FlxG.keys.justPressed.UP)    seekToBeat(playheadBeat - 4);
			if (FlxG.keys.justPressed.DOWN)  seekToBeat(playheadBeat + 4);

			if (FlxG.keys.justPressed.DELETE && selectedEv != null)
				deleteEvent(selectedEv);
		}

		if (focusField != "") handleTextInput();
	}

	function seekToBeat(beat:Float):Void
	{
		playheadBeat = Math.max(0, beat);
		songPosition = playheadBeat * Conductor.crochet;
		seekAudioTo(songPosition);
		manager.seekToBeat(playheadBeat);
		applyManagerToStrums();
		syncPlayhead();
		refreshScrollbar();
		refreshStrumPropWindow();
		centerTimelineOnPlayhead();
	}

	function centerTimelineOnPlayhead():Void
	{
		var margin = beatsVisible * 0.1;
		if (playheadBeat > tlScroll + beatsVisible - margin || playheadBeat < tlScroll + margin)
		{
			tlScroll = Math.max(0, playheadBeat - beatsVisible / 2);
			refreshTimeline();
		}
	}

	function togglePlay():Void
	{
		isPlaying = !isPlaying;
		if (isPlaying)
		{
			seekAudioTo(songPosition);
			resumeAudio();
			manager.seekToBeat(playheadBeat);
			setStatus("▶ Reproduciendo...");
		}
		else
		{
			pauseAudio();
			setStatus("⏸ Pausado.");
		}
	}

	function togglePreview():Void
	{
		previewMode = !previewMode;
		var show = !previewMode;
		windowGroup.visible   = show;
		tlGroup.visible       = show;
		strumHitGroup.visible = show;
		selBoxGroup.visible   = show;
		if (tlScrollbarBg    != null) tlScrollbarBg.visible    = show;
		if (tlScrollbarThumb != null) tlScrollbarThumb.visible  = show;
		if (show) setStatus("Preview OFF");
		else      setStatus("◈ PREVIEW MODE — Tab para salir");
	}

	function toggleUIWindows():Void
	{
		uiHidden = !uiHidden;
		for (wd in windows)
		{
			if (!uiHidden) showWin(wd);
			else           hideWin(wd);
		}
		setStatus(uiHidden ? "UI Oculta — H para mostrar" : "UI Visible");
	}

	function toggleFullGame():Void
	{
		fullGameView = !fullGameView;
		setStatus(fullGameView ? "Vista completa [F11 para volver]" : "Vista normal");
	}

	function handleTextInput():Void
	{
		if (FlxG.keys.justPressed.BACKSPACE)
		{
			var b = fieldBufs.get(focusField);
			if (b != null && b.length > 0) fieldBufs.set(focusField, b.substr(0, b.length - 1));
		}
		if (FlxG.keys.justPressed.ENTER) { commitField(focusField); focusField = ""; }
		if (FlxG.keys.justPressed.ESCAPE) { focusField = ""; }
		if (FlxG.keys.justPressed.TAB)
		{
			commitField(focusField);
			var ord = ["beat","value","duration"];
			focusField = ord[(ord.indexOf(focusField) + 1) % ord.length];
		}
		var numKeys = [
			{k:FlxG.keys.justPressed.ZERO,   c:"0"}, {k:FlxG.keys.justPressed.ONE,   c:"1"},
			{k:FlxG.keys.justPressed.TWO,    c:"2"}, {k:FlxG.keys.justPressed.THREE,  c:"3"},
			{k:FlxG.keys.justPressed.FOUR,   c:"4"}, {k:FlxG.keys.justPressed.FIVE,   c:"5"},
			{k:FlxG.keys.justPressed.SIX,    c:"6"}, {k:FlxG.keys.justPressed.SEVEN,  c:"7"},
			{k:FlxG.keys.justPressed.EIGHT,  c:"8"}, {k:FlxG.keys.justPressed.NINE,   c:"9"},
			{k:FlxG.keys.justPressed.PERIOD, c:"."}, {k:FlxG.keys.justPressed.MINUS,  c:"-"}
		];
		for (nk in numKeys)
			if (nk.k) fieldBufs.set(focusField, (fieldBufs.get(focusField) ?? "") + nk.c);
	}

	function commitField(key:String):Void
	{
		var v = Std.parseFloat(fieldBufs.get(key));
		if (Math.isNaN(v)) v = 0;
		switch (key) {
			case "beat":     newBeat  = Math.max(0, v);
			case "value":    newValue = v;
			case "duration": newDur   = Math.max(0, v);
		}
		fieldBufs.set(key, fmt(Math.round(v * 1000) / 1000));
	}

	// ── Mouse ──────────────────────────────────────────────────────────────────

	function handleMouse(elapsed:Float):Void
	{
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		var lp = FlxG.mouse.justPressed;
		var lr = FlxG.mouse.justReleased;
		var rp = FlxG.mouse.justPressedRight;

		if (lr)
		{
			draggingWin       = null;
			scrollbarDragging = false;
		}

		// ── Drag scrollbar ────────────────────────────────────────────────────
		if (scrollbarDragging)
		{
			var maxBeat   = Math.max(beatsVisible + 1, getMaxBeat() + 8);
			var thumbW    = Math.max(16.0, sbTrackW * beatsVisible / maxBeat);
			var maxScroll = maxBeat - beatsVisible;
			var relX      = mx - sbTrackX - scrollbarDragOX;
			var ratio     = relX / (sbTrackW - thumbW);
			tlScroll      = Math.max(0, Math.min(maxScroll, ratio * maxScroll));
			syncPlayhead();
			refreshScrollbar();
			// Re-render timeline sin rebuildar todo (solo actualizar sprites de eventos)
			// Para perf, refresh completo solo si necesario
			refreshTimeline();
			return;
		}

		// ── Drag ventana ──────────────────────────────────────────────────────
		if (draggingWin != null)
		{
			var nx = FlxMath.bound(mx - dragOX, 0, SW - draggingWin.w);
			var ny = FlxMath.bound(my - dragOY, 0, SH - draggingWin.h - 10);
			moveWin(draggingWin, nx, ny);
			return;
		}

		// ── Hover sobre strums ────────────────────────────────────────────────
		var hoveredStrum = getStrumAt(mx, my);
		if (hoveredStrum != null)
		{
			var s = editorGroups[hoveredStrum.gi].getStrum(hoveredStrum.si);
			if (s != null)
			{
				var hitSz = Math.max(64, Math.max(s.width, s.height) + 16);
				strumHoverBox.setGraphicSize(Std.int(hitSz + 4), Std.int(hitSz + 4));
				strumHoverBox.updateHitbox();
				strumHoverBox.x     = s.x - hitSz / 2 + s.width / 2 - 2;
				strumHoverBox.y     = s.y - hitSz / 2 + s.height / 2 - 2;
				strumHoverBox.alpha = 0.25;
				openfl.ui.Mouse.cursor   = openfl.ui.MouseCursor.BUTTON;
			}
		}
		else
		{
			strumHoverBox.alpha = 0;
			openfl.ui.Mouse.cursor   = openfl.ui.MouseCursor.AUTO;
		}

		if (lp)
		{
			// ── Click en scrollbar ────────────────────────────────────────────
			if (my >= sbY && my <= sbY + TL_SB_H && mx >= sbTrackX && mx <= sbTrackX + sbTrackW)
			{
				// Click en thumb → drag
				if (tlScrollbarThumb != null &&
				    mx >= tlScrollbarThumb.x && mx <= tlScrollbarThumb.x + tlScrollbarThumb.width)
				{
					scrollbarDragging = true;
					scrollbarDragOX   = mx - tlScrollbarThumb.x;
					return;
				}
				// Click fuera del thumb → jump
				var maxBeat   = Math.max(beatsVisible + 1, getMaxBeat() + 8);
				var thumbW    = Math.max(16.0, sbTrackW * beatsVisible / maxBeat);
				var relX      = mx - sbTrackX - thumbW / 2;
				var ratio     = relX / (sbTrackW - thumbW);
				tlScroll      = Math.max(0, Math.min(maxBeat - beatsVisible, ratio * (maxBeat - beatsVisible)));
				refreshTimeline();
				return;
			}

			// ── Check ventanas flotantes ──────────────────────────────────────
			var i = windows.length - 1;
			while (i >= 0)
			{
				var wd = windows[i];
				if (!wd.visible) { i--; continue; }
				if (inR(mx,my, wd.x+wd.w-22, wd.y+4,  18, 18)) { hideWin(wd); return; }
				if (inR(mx,my, wd.x+wd.w-42, wd.y+4,  18, 18)) { wd.minimized = !wd.minimized; applyMinimize(wd); return; }
				if (inR(mx,my, wd.x, wd.y, wd.w-44, 24))       { draggingWin = wd; dragOX = mx-wd.x; dragOY = my-wd.y; bringFront(wd); return; }
				if (!wd.minimized && inR(mx,my, wd.x, wd.y+24, wd.w, wd.h-24))
				{
					for (btn in strumPropBtns) if (inR(mx,my,btn.x,btn.y,btn.w,btn.h)) { btn.cb(); return; }
					for (btn in hitBtns)       if (inR(mx,my,btn.x,btn.y,btn.w,btn.h)) { btn.cb(); return; }
					for (hf  in hitFields)     if (inR(mx,my,hf.x,hf.y,hf.w,hf.h))    { focusField = hf.key; return; }
					return;
				}
				i--;
			}

			// Barra superior y status
			if (my < BAR_H || my >= SH - STAT_H)
				for (btn in hitBtns) if (inR(mx,my,btn.x,btn.y,btn.w,btn.h)) { btn.cb(); return; }

			// Panel izquierdo
			if (mx < PANEL_L && my >= BAR_H && my < tlY)
			{
				for (btn in hitBtns)   if (inR(mx,my,btn.x,btn.y,btn.w,btn.h)) { btn.cb(); return; }
				for (hf  in hitFields) if (inR(mx,my,hf.x,hf.y,hf.w,hf.h))    { focusField = hf.key; return; }
			}

			// Panel derecho
			if (mx >= SW - PANEL_R && my >= BAR_H && my < tlY)
			{
				for (btn in strumPropBtns) if (inR(mx,my,btn.x,btn.y,btn.w,btn.h)) { btn.cb(); return; }
				for (btn in hitBtns)       if (inR(mx,my,btn.x,btn.y,btn.w,btn.h)) { btn.cb(); return; }
			}

			// Click en strum
			if (mx >= gameAreaX && mx <= gameAreaX + gameAreaW && my >= BAR_H && my < tlY)
			{
				var hit = getStrumAt(mx, my);
				if (hit != null)
				{
					selectStrum(hit.gi, hit.si);
					return;
				}
			}

			// Click en timeline
			if (my >= tlY && my < sbY)
			{
				for (btn in hitBtns) if (inR(mx,my,btn.x,btn.y,btn.w,btn.h)) { btn.cb(); return; }

				var hitEv = false;
				for (es in evSprites)
					if (inR(mx,my, es.sp.x, es.sp.y, es.sp.width + 2, es.sp.height + 2))
					{
						selectEvent(es.ev); hitEv = true; break;
					}

				if (!hitEv && mx >= PANEL_L && mx <= SW - PANEL_R)
				{
					var rawBeat = Math.max(0, tlScroll + (mx - PANEL_L) / ((SW - PANEL_L - PANEL_R) / beatsVisible));
					seekToBeat(snapDiv > 1 ? snapBeat(rawBeat) : rawBeat);
					selectedEv = null;
					if (inspTxt != null) inspTxt.text = "(sin selección)";
					refreshTimeline();
				}
			}
		}

		// RMB en timeline → borrar
		if (rp && my >= tlY && my < sbY)
		{
			for (es in evSprites)
				if (inR(mx,my, es.sp.x, es.sp.y, es.sp.width + 2, es.sp.height + 2))
				{
					deleteEvent(es.ev); return;
				}
		}

		// RMB en strum → target
		if (rp && mx >= gameAreaX && mx <= gameAreaX + gameAreaW && my >= BAR_H && my < tlY)
		{
			var hit = getStrumAt(mx, my);
			if (hit != null && hit.gi < srcStrumsGrps.length)
			{
				selectStrum(hit.gi, hit.si);
				newTarget = srcStrumsGrps[hit.gi].id;
				newStrumI = hit.si;
				setStatus('Target → ${srcStrumsGrps[hit.gi].id}[${hit.si}]');
			}
		}

		// Rueda
		var wheel = FlxG.mouse.wheel;
		if (wheel != 0 && my >= tlY && my < SH - STAT_H)
		{
			if (FlxG.keys.pressed.CONTROL)
			{
				beatsVisible = FlxMath.bound(wheel > 0 ? beatsVisible / 1.5 : beatsVisible * 1.5, BV_MIN, BV_MAX);
				refreshTimeline();
			}
			else
			{
				tlScroll = Math.max(0, tlScroll - wheel * beatsVisible * 0.08);
				syncPlayhead();
				refreshTimeline();
			}
		}

		if (wheel != 0 && mx >= gameAreaX && mx <= gameAreaX + gameAreaW && my >= BAR_H && my < tlY)
		{
			if (FlxG.keys.pressed.CONTROL)
			{
				volValue = FlxMath.bound(volValue + wheel * 0.05, 0, 1);
				applyVolume();
			}
		}
	}

	// ─── Strum helpers ────────────────────────────────────────────────────────

	function getStrumAt(mx:Float, my:Float):Null<{gi:Int, si:Int}>
	{
		for (gi in 0...editorGroups.length)
		{
			for (si in 0...4)
			{
				var s = editorGroups[gi].getStrum(si);
				if (s == null) continue;
				var hitSz = Math.max(64, Math.max(s.width, s.height) + 16);
				var hx    = s.x - hitSz / 2 + s.width / 2;
				var hy    = s.y - hitSz / 2 + s.height / 2;
				if (inR(mx, my, hx, hy, hitSz + 8, hitSz + 8))
					return { gi: gi, si: si };
			}
		}
		return null;
	}

	function selectStrum(gi:Int, si:Int):Void
	{
		selectedGroupIdx = gi;
		selectedStrumIdx = si;

		for (gBoxes in selBoxes) for (box in gBoxes) if (box != null) box.visible = false;
		if (gi < selBoxes.length && si < selBoxes[gi].length && selBoxes[gi][si] != null)
			selBoxes[gi][si].visible = true;

		refreshStrumPropWindow();
		var dnames = ["LEFT","DOWN","UP","RIGHT"];
		setStatus('✓ Strum: ${srcStrumsGrps[gi].id} [${dnames[si]}]  — RMB = usar como target');
	}

	// ── Lista de eventos ──────────────────────────────────────────────────────

	function refreshEvList():Void
	{
		for (t in evListTxts) { remove(t, true); t.destroy(); }
		evListTxts = [];

		if (evListStartY <= 0) return;

		var cx  = 6.0;
		var cy  = evListStartY;
		var cw  = PANEL_L - 12.0;
		var lh  = 13;
		var max = Std.int((evListEndY - cy) / lh);

		var evs = manager.data.events;
		for (i in 0...Std.int(Math.min(max, evs.length)))
		{
			var ev  = evs[i];
			var col = (selectedEv == ev) ? FlxColor.fromInt(C_ACCENT2) : FlxColor.fromInt(C_DIM);
			var ts  = (ev.type:String).substr(0, 9);
			var tgt = ev.target.substr(0, 6);
			var txt = 'b${fmt(ev.beat)} ${ts} ${tgt}[${ev.strumIdx==-1?"A":Std.string(ev.strumIdx)}]=>${fmt(ev.value)}';
			var t   = mkTxt(cx, cy, txt, 9, col);

			if (selectedEv == ev)
			{
				var selBg = mkBg(cx, cy, cw, lh, 0x22AACCFF);
				add(selBg); evListTxts.push(selBg);
			}

			add(t); evListTxts.push(t);
			var captEv = ev;
			hitBtns.push({ x: cx, y: cy, w: cw, h: lh + 1.0, cb: function() selectEvent(captEv) });
			cy += lh;
		}

		if (evs.length > max)
		{
			var more = mkTxt(cx, cy, '... +${evs.length - max} más', 9, C_DIM);
			add(more); evListTxts.push(more);
		}
	}

	// ═════════════════════════════════════════════════════════════════════════
	// ACCIONES
	// ═════════════════════════════════════════════════════════════════════════

	function onClickAdd():Void
	{
		commitField("beat"); commitField("value"); commitField("duration");
		pushUndo();
		var ev = ModChartHelpers.makeEvent(newBeat, newTarget, newStrumI, newType, newValue, newDur, newEase);
		manager.addEvent(ev);
		refreshTimeline();
		selectEvent(ev);
		setStatus('+ ${ModChartHelpers.typeLabel(newType)} en beat ${fmt(newBeat)} → ${newTarget}[${strumLbl()}]');
		newBeat += newDur > 0 ? newDur : 1.0 / snapDiv;
		fieldBufs.set("beat", fmt(Math.round(newBeat * 1000) / 1000));
	}

	function onClickPlay():Void
	{
		if (isPlaying) { togglePlay(); return; }
		isPlaying = true;
		seekAudioTo(songPosition);
		resumeAudio();
		manager.seekToBeat(playheadBeat);
		setStatus("▶ Reproduciendo...");
	}

	function onClickStop():Void
	{
		isPlaying    = false;
		playheadBeat = 0;
		songPosition = 0;
		lastBeatInt  = -1;
		pauseAudio();
		seekAudioTo(0);
		manager.seekToBeat(0);
		applyManagerToStrums();
		refreshTimeline();
		setStatus("■ Detenido. Beat: 0");
	}

	// ── Guardar / Cargar mejorado ─────────────────────────────────────────────

	function onClickSave():Void
	{
		#if sys
		try {
			var songName = manager.data.song.toLowerCase();
			var dir      = 'modcharts/';
			if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);

			var mainPath = '${dir}${songName}.json';

			// Backup del archivo anterior
			if (sys.FileSystem.exists(mainPath))
			{
				var backupDir = '${dir}backup/';
				if (!sys.FileSystem.exists(backupDir)) sys.FileSystem.createDirectory(backupDir);

				var stamp   = Date.now();
				var datePart= '${stamp.getFullYear()}${pad2(stamp.getMonth()+1)}${pad2(stamp.getDate())}_${pad2(stamp.getHours())}${pad2(stamp.getMinutes())}';
				var bkp     = '${backupDir}${songName}_${datePart}.json';
				sys.io.File.copy(mainPath, bkp);

				// Mantener solo los últimos 5 backups
				var bkpFiles = sys.FileSystem.readDirectory(backupDir)
					.filter(f -> StringTools.startsWith(f, songName) && StringTools.endsWith(f, '.json'));
				bkpFiles.sort((a, b) -> Reflect.compare(a, b));
				while (bkpFiles.length > 5) {
					sys.FileSystem.deleteFile(backupDir + bkpFiles.shift());
				}
			}

			sys.io.File.saveContent(mainPath, manager.toJson());
			setStatus('✓ Guardado: ${mainPath}  (backup auto)');
		} catch (e:Dynamic) { setStatus("Error al guardar: " + e); }
		#else
		FlxG.save.data.modchart_last = manager.toJson();
		FlxG.save.flush();
		setStatus("✓ Guardado en save.");
		#end
	}

	inline function pad2(n:Int):String return n < 10 ? '0$n' : '$n';

	function onClickLoad():Void
	{
		#if sys
		var songName = manager.data.song.toLowerCase();
		var mainPath = 'modcharts/${songName}.json';
		if (sys.FileSystem.exists(mainPath))
		{
			try {
				manager.loadFromJson(sys.io.File.getContent(mainPath));
				refreshTimeline();
				setStatus('✓ ${manager.data.events.length} eventos cargados de ${mainPath}');
			} catch (e:Dynamic) { setStatus("Error al cargar: " + e); }
		}
		else setStatus("Archivo no encontrado: " + mainPath);
		#else
		if (FlxG.save.data.modchart_last != null)
		{
			manager.loadFromJson(FlxG.save.data.modchart_last);
			refreshTimeline();
			setStatus("✓ Cargado desde save.");
		}
		else setStatus("No hay save.");
		#end
	}

	function onClickNew():Void
	{
		pushUndo();
		manager.clearEvents();
		refreshTimeline();
		setStatus("Modchart limpiado.");
	}

	function selectEvent(ev:ModChartEvent):Void
	{
		selectedEv = ev;

		if (inspTxt != null)
			inspTxt.text =
				'Tipo:   ${ModChartHelpers.typeLabel(ev.type)}\n' +
				'Beat:   ${fmt(ev.beat)}\n' +
				'Target: ${ev.target}\n' +
				'Strum:  ${ev.strumIdx == -1 ? "TODOS" : ["L","D","U","R"][ev.strumIdx]}\n' +
				'Valor:  ${fmt2(ev.value)}\n' +
				'Dur:    ${fmt(ev.duration)}b\n' +
				'Ease:   ${(ev.ease:String)}';

		newType=ev.type; newTarget=ev.target; newStrumI=ev.strumIdx;
		newBeat=ev.beat; newValue=ev.value; newDur=ev.duration; newEase=ev.ease;
		fieldBufs.set("beat",     fmt(ev.beat));
		fieldBufs.set("value",    fmt2(ev.value));
		fieldBufs.set("duration", fmt(ev.duration));

		// Actualizar preview de easing con el ease del evento seleccionado
		easingPrevEase = "";
		drawEasingCurve(newEase);

		seekToBeat(ev.beat);
		refreshTimeline();
	}

	function deleteEvent(ev:ModChartEvent):Void
	{
		pushUndo();
		manager.data.events.remove(ev);
		if (selectedEv == ev) { selectedEv = null; if (inspTxt != null) inspTxt.text = "(sin selección)"; }
		manager.seekToBeat(playheadBeat);
		applyManagerToStrums();
		refreshTimeline();
		setStatus("Evento eliminado.");
	}

	function doUndo():Void
	{
		if (undoStack.length == 0) { setStatus("Nada que deshacer."); return; }
		redoStack.push(manager.toJson());
		manager.loadFromJson(undoStack.pop());
		refreshTimeline();
		setStatus("↩ Deshecho.");
	}

	function doRedo():Void
	{
		if (redoStack.length == 0) { setStatus("Nada que rehacer."); return; }
		undoStack.push(manager.toJson());
		manager.loadFromJson(redoStack.pop());
		refreshTimeline();
		setStatus("↪ Rehecho.");
	}

	function pushUndo():Void
	{
		undoStack.push(manager.toJson());
		redoStack = [];
		if (undoStack.length > 80) undoStack.shift();
	}

	function setStatus(msg:String):Void
	{
		if (statusTxt != null) statusTxt.text = msg;
		trace('[MCEditor] $msg');
	}

	// ═════════════════════════════════════════════════════════════════════════
	// SISTEMA DE VENTANAS
	// ═════════════════════════════════════════════════════════════════════════

	function mkWin(title:String, x:Float, y:Float, w:Float, h:Float):WinData
	{
		var wd:WinData = {
			title:title, x:x, y:y, w:w, h:h, visible:true, minimized:false,
			allSprites:[], bg:null, shadow:null, titleBar:null,
			titleTxt:null, minBtn:null, closeBtn:null, contentGroup: new FlxGroup()
		};

		wd.shadow   = mkRaw(x+4, y+4, w, h, 0xAA000000);
		wd.bg       = mkRaw(x, y+24, w, h-24, 0xEE06061A);
		var brd     = mkRaw(x, y+24, 2, h-24, C_WIN_BORD); brd.alpha = 0.7;
		var brdR    = mkRaw(x+w-2, y+24, 2, h-24, C_WIN_BORD); brdR.alpha = 0.3;
		var brdB    = mkRaw(x, y+h-2, w, 2, C_WIN_BORD); brdB.alpha = 0.3;

		wd.titleBar = mkRaw(x, y, w, 24, C_WIN_TITLE);
		wd.titleTxt = mkTxt(x+10, y+5, title, 12, C_TEXT);
		(wd.titleTxt:FlxText).fieldWidth = w - 52;
		wd.minBtn   = mkTxt(x+w-42, y+5, "─", 12, 0xFF8888FF);
		wd.closeBtn = mkTxt(x+w-22, y+5, "✕", 12, C_ACCENT2);

		for (s in [wd.shadow, wd.bg, brd, brdR, brdB, wd.titleBar])
			wd.allSprites.push(s);
		for (t in [wd.titleTxt, wd.minBtn, wd.closeBtn])
			wd.allSprites.push(t);
		return wd;
	}

	function addToWinGroup(wd:WinData):Void
	{
		for (s in wd.allSprites) windowGroup.add(s);
		if (wd.contentGroup != null) windowGroup.add(wd.contentGroup);
	}

	function moveWin(wd:WinData, nx:Float, ny:Float):Void
	{
		var dx = nx - wd.x; var dy = ny - wd.y;
		wd.x = nx; wd.y = ny;
		for (s in wd.allSprites) shiftBasic(s, dx, dy);
		if (wd.contentGroup != null)
			wd.contentGroup.forEach(function(b:flixel.FlxBasic) {
				shiftBasic(b, dx, dy);
				if (Std.isOfType(b, FlxGroup))
					(cast b:FlxGroup).forEach(function(bb:flixel.FlxBasic) shiftBasic(bb, dx, dy));
			});
		if (wd == strumPropWin) refreshStrumPropWindow();

		// Redibujar easing si se mueve la ventana
		if (wd == easingPreviewWin && easingPreviewOpen)
		{
			easingPrevEase = "";
			drawEasingCurve(newEase);
		}
	}

	inline function shiftBasic(b:flixel.FlxBasic, dx:Float, dy:Float):Void
	{
		if      (Std.isOfType(b, FlxSprite)) { var s:FlxSprite=cast b; s.x+=dx; s.y+=dy; }
		else if (Std.isOfType(b, FlxText))   { var t:FlxText=cast b;   t.x+=dx; t.y+=dy; }
	}

	function bringFront(wd:WinData):Void
	{
		windows.remove(wd); windows.push(wd);
		if (wd.contentGroup != null) { windowGroup.remove(wd.contentGroup); windowGroup.add(wd.contentGroup); }
	}

	function hideWin(wd:WinData):Void
	{
		for (s in wd.allSprites) if (s != null) s.visible = false;
		if (wd.contentGroup != null) wd.contentGroup.visible = false;
		wd.visible = false;
	}

	function showWin(wd:WinData):Void
	{
		for (s in wd.allSprites) if (s != null) s.visible = true;
		if (wd.contentGroup != null) wd.contentGroup.visible = !wd.minimized;
		wd.visible = true;
		applyMinimize(wd);
	}

	function applyMinimize(wd:WinData):Void
	{
		var show = !wd.minimized;
		if (wd.bg != null) wd.bg.visible = show;
		for (s in wd.allSprites)
		{
			if (s==wd.shadow||s==wd.titleBar||s==wd.titleTxt||s==wd.minBtn||s==wd.closeBtn) continue;
			s.visible = show;
		}
		if (wd.contentGroup != null) wd.contentGroup.visible = show;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// AYUDA OVERLAY
	// ─────────────────────────────────────────────────────────────────────────

	function buildHelpOverlay():Void
	{
		helpOverlay = new FlxSprite(60, 15);
		helpOverlay.makeGraphic(1160, 678, FlxColor.fromInt(0xF4020210));
		helpOverlay.cameras = [editorCam];
		helpOverlay.visible = false;
		add(helpOverlay);

		drawBorderSprite(helpOverlay, 1160, 678, C_ACCENT, 3);
		helpOverlay.pixels = helpOverlay.pixels;

		helpTxt = new FlxText(80, 30, 1120,
			"══════════════════  AYUDA EDITOR MODCHART v4  ══════════════════\n\n" +
			"ATAJOS RÁPIDOS\n" +
			"  Space          → Play / Pausa\n" +
			"  Flechas ← →    → Navegar beats (con snap)\n" +
			"  Flechas ↑ ↓    → Navegar 4 beats\n" +
			"  Delete          → Eliminar evento seleccionado\n" +
			"  Tab             → Modo Preview (oculta todo el UI)\n" +
			"  H               → Ocultar/mostrar ventanas flotantes\n" +
			"  F11             → Vista pantalla completa del área de juego\n" +
			"  1 / 2 / 3       → Snap: 1/4 | 1/8 | 1/16\n" +
			"  Ctrl+Z          → Deshacer  |  Ctrl+Y → Rehacer\n" +
			"  Ctrl+S          → Guardar (con backup automático)\n" +
			"  F1              → Esta ayuda  |  ESC → Cerrar editor\n\n" +
			"TIMELINE (v4 — con grupos y scrollbar)\n" +
			"  LMB vacío               → Mover playhead al beat clickeado\n" +
			"  LMB sobre evento        → Seleccionar evento\n" +
			"  RMB sobre evento        → Eliminar evento\n" +
			"  LMB sobre header grupo  → Colapsar / expandir grupo\n" +
			"  Rueda                   → Scroll horizontal\n" +
			"  Ctrl+Rueda              → Zoom in/out\n" +
			"  Scrollbar inferior      → Arrastrar thumb para navegar\n" +
			"  ◀ / ▶ (extremos bar)   → Scroll fino\n" +
			"  Botón ALL               → Ver toda la canción\n\n" +
			"EASE PREVIEW\n" +
			"  Botón 'Ease〜' (timeline) o '〜 EASE PREVIEW' (panel derecho)\n" +
			"  → Abre ventana flotante con curva del easing actual\n" +
			"  → Se actualiza automáticamente al cambiar el ease\n\n" +
			"SCRIPTS EXTERNOS\n" +
			"  Botón 'Scripts' (timeline) o '📜 SCRIPTS' (panel derecho)\n" +
			"  → Importar eventos desde JSON externo\n" +
			"  → Exportar eventos actuales como script JSON\n" +
			"  → Ruta automática: modcharts/scripts/<cancion>.json\n\n" +
			"GUARDAR (mejorado)\n" +
			"  Ctrl+S o botón GUARDAR → Guarda + backup automático\n" +
			"  → Backup en modcharts/backup/ (últimos 5)\n\n" +
			"[F1 para cerrar esta ayuda]", 11);
		helpTxt.color   = FlxColor.fromInt(C_TEXT);
		helpTxt.cameras = [editorCam];
		helpTxt.visible = false;
		add(helpTxt);
	}

	// ═════════════════════════════════════════════════════════════════════════
	// SALIR AL PLAYSTATE
	// ═════════════════════════════════════════════════════════════════════════

	function exitEditor():Void
	{
		onClickSave();
		manager.captureBasePositions();
		manager.resetToStart();

		for (edGrp in editorGroups) edGrp.destroy();
		editorGroups = [];

		FlxG.mouse.visible = false;

		trace('[MCEditor] Cerrado. Eventos: ${manager.data.events.length}');
		StateTransition.switchState(new PlayState());
	}

	override function destroy():Void
	{
		manager = null;
		srcStrumsGrps = null;
		vocals = null;
		super.destroy();
	}

	// ═════════════════════════════════════════════════════════════════════════
	// UTILIDADES
	// ═════════════════════════════════════════════════════════════════════════

	function addTLBtn(x:Float, y:Float, label:String, cb:Void->Void):FlxText
	{
		var bg = mkBg(x-1, y, label.length * 7.0 + 6, 18, 0xFF0A0A1E);
		tlGroup.add(bg);
		var t = mkTxt(x, y + 2, label, 10, C_ACCENT);
		tlGroup.add(t);
		hitBtns.push({ x: x-1, y: y, w: label.length * 7.0 + 6, h: 18.0, cb: cb });
		return t;
	}

	inline function snapBeat(beat:Float):Float
		return snapDiv > 1 ? Math.round(beat * snapDiv) / snapDiv : beat;

	inline function bps():Float
		return Conductor.crochet > 0 ? 1000.0 / Conductor.crochet : 2.0;

	inline function fmt(v:Float):String
		return Std.string(Math.round(v * 100) / 100);

	inline function fmt2(v:Float):String
		return Std.string(Math.round(v * 1000) / 1000);

	function getMaxBeat():Float
	{
		var m = 16.0;
		for (ev in manager.data.events)
			if (ev.beat + ev.duration > m) m = ev.beat + ev.duration;
		return m;
	}

	function cycleType(d:Int):Void
	{
		var all = ModChartHelpers.ALL_TYPES;
		var i   = all.indexOf(newType);
		newType = all[((i + d) % all.length + all.length) % all.length];
	}

	function cycleEaseDir(d:Int):Void
	{
		var all = ModChartHelpers.ALL_EASES;
		var i   = all.indexOf(newEase);
		newEase = all[((i + d) % all.length + all.length) % all.length];
	}

	function cycleTarget(d:Int):Void
	{
		var opts = ["player","cpu","all"];
		for (g in srcStrumsGrps) if (opts.indexOf(g.id) == -1) opts.push(g.id);
		var i     = opts.indexOf(newTarget);
		newTarget = opts[((i + d) % opts.length + opts.length) % opts.length];
	}

	inline function strumLbl():String
		return newStrumI == -1 ? "TODOS" : ["LEFT","DOWN","UP","RIGHT"][newStrumI];

	// ─── Primitivas de render ─────────────────────────────────────────────────

	function mkRaw(x:Float, y:Float, w:Float, h:Float, col:Int):FlxSprite
	{
		var s = new FlxSprite(x, y);
		s.makeGraphic(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), FlxColor.fromInt(col));
		s.cameras = [editorCam];
		return s;
	}

	inline function mkBg(x:Float, y:Float, w:Float, h:Float, col:Int):FlxSprite
		return mkRaw(x, y, w, h, col);

	function mkBgRnd(x:Float, y:Float, w:Float, h:Float, col:Int):FlxSprite
		return mkRaw(x, y, w, h, col);

	function mkTxt(x:Float, y:Float, txt:String, size:Int, col:Int = 0xFFDDDDFF):FlxText
	{
		var t = new FlxText(x, y, 0, txt, size);
		t.color   = FlxColor.fromInt(col);
		t.cameras = [editorCam];
		return t;
	}

	inline function inR(mx:Float, my:Float, rx:Float, ry:Float, rw:Float, rh:Float):Bool
		return mx >= rx && mx <= rx + rw && my >= ry && my <= ry + rh;
}
