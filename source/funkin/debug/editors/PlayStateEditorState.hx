package funkin.debug.editors;
import funkin.debug.EditorDialogs.UnsavedChangesDialog;
import coolui.CoolInputText;
import coolui.CoolNumericStepper;
import coolui.CoolCheckBox;
import coolui.CoolDropDown;
import coolui.CoolTabMenu;


// ─── Core ─────────────────────────────────────────────────────────────────────
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;

import flixel.group.FlxGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
// ─── Gameplay ─────────────────────────────────────────────────────────────────
import funkin.data.Conductor;
import funkin.data.CoolUtil;
import funkin.data.MetaData;
import funkin.data.Song;
import funkin.data.Song.SwagSong;
import funkin.data.Song.CharacterSlotData;
import funkin.gameplay.CameraController;
import funkin.gameplay.CharacterController;
import funkin.gameplay.Countdown;
import funkin.gameplay.GameState;
import funkin.gameplay.PlayState;
import funkin.gameplay.UIScriptedManager;
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.objects.character.CharacterSlot;
import funkin.gameplay.objects.hud.ScoreManager;
import funkin.gameplay.objects.stages.Stage;
import funkin.scripting.events.EventManager;
import funkin.scripting.HScriptInstance;
import funkin.scripting.ScriptHandler;
import funkin.scripting.events.EventInfoSystem;
import funkin.transitions.StateTransition;
import funkin.menus.FreeplayState.SongMetadata;
// ─── System ───────────────────────────────────────────────────────────────────
import haxe.Json;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

// ═══════════════════════════════════════════════════════════════════════════════
//  Typedefs
// ═══════════════════════════════════════════════════════════════════════════════

/** Evento del PlayState Editor — se guarda en el JSON de la canción. */
typedef PSEEvent =
{
	var id          : String;        // UUID único
	var stepTime    : Float;         // Step en que ocurre
	var type        : String;        // Nombre del tipo de evento
	var value       : String;        // Valor (v1|v2)
	var difficulties: Array<String>; // ["easy","normal","hard"] o ["*"] = todos
	var trackIndex  : Int;           // Pista visual en la timeline
	@:optional var label : String;   // Etiqueta opcional
}

/** Script inline del PlayState Editor. */
typedef PSEScript =
{
	var id          : String;
	var name        : String;
	var code        : String;
	var triggerStep : Float;         // -1 = solo manual
	var difficulties: Array<String>;
	var enabled     : Bool;
	var autoTrigger : Bool;
}

/** Datos persistentes del editor guardados junto al chart. */
typedef PSEData =
{
	@:optional var events  : Array<PSEEvent>;
	@:optional var scripts : Array<PSEScript>;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PlayStateEditorState
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * PlayState Editor v1.0
 *
 * Editor visual completo del PlayState sin strums.
 * Muestra Stage + Personajes + HUD en tiempo real.
 * Permite insertar Eventos y Scripts con soporte de dificultad,
 * probarlos en tiempo real y guardar en el JSON de la canción.
 *
 * Controles:
 *   SPACE         — Play / Pause
 *   R             — Reiniciar desde el principio
 *   T             — Toggle timeline
 *   H             — Toggle panel derecho
 *   F5            — Guardar
 *   ESC           — Volver al menú anterior
 *   Click timeline — Seek a esa posición
 */
class PlayStateEditorState extends funkin.states.MusicBeatState
{
	// ── Layout ────────────────────────────────────────────────────────────────
	static inline final SW         : Int = 1280;
	static inline final SH         : Int = 720;
	static inline final TOP_H      : Int = 36;
	static inline final STATUS_H   : Int = 22;
	static inline final RIGHT_W    : Int = 292;
	static inline final TL_H       : Int = 236;  // TL_RULER_H(24) + 6*TL_TRACK_H2(22)=132 + HScroll(12) + TL_SCRUB_H(32) + TL_TRANS_H(36) = 236
	static inline final TL_RULER_H : Int = 24;
	static inline final TL_TRACK_H : Int = 28;
	static inline final TL_LABEL_W : Int = 110;

	// ── Colores del editor ────────────────────────────────────────────────────
	static inline final C_BG        : Int = 0xFF1A1A2A;
	static inline final C_PANEL     : Int = 0xFF23233A;
	static inline final C_TOPBAR    : Int = 0xFF16162A;
	static inline final C_BORDER    : Int = 0xFF3A3A5A;
	static inline final C_ACCENT    : Int = 0xFF00D9FF;
	static inline final C_TEXT      : Int = 0xFFDDDDFF;
	static inline final C_SUBTEXT   : Int = 0xFF8888AA;
	static inline final C_PLAYHEAD  : Int = 0xFFFF4444;
	static inline final C_TIMELINE  : Int = 0xFF0F0F1E;
	static inline final C_RULER     : Int = 0xFF1E1E38;
	static inline final C_UNSAVED   : Int = 0xFFFFAA00;
	static inline final C_SAVED     : Int = 0xFF00FF88;

	// Colores por pista
	static final TRACK_COLORS : Array<Int> = [
		0xFF4488FF, // Camera
		0xFF44FF88, // Character
		0xFFFF8844, // Visual
		0xFFCC44FF, // Script
		0xFFFFCC00, // Song
		0xFF44FFCC, // Custom
	];

	static final TRACK_NAMES : Array<String> = [
		"Camera", "Character", "Visual", "Script", "Song", "Custom"
	];

	// ── Cámaras ───────────────────────────────────────────────────────────────
	var camGame   : FlxCamera;
	var camHUD    : FlxCamera;
	var camUI     : FlxCamera;  // cameras[0], zoom=1 fixed, used by coolui.CoolUIGroup for hit detection
	var _gameZoom : Float = 1.0; // current zoom of the game viewport

	// ── Gameplay ──────────────────────────────────────────────────────────────
	var currentStage        : Stage;
	var characterSlots      : Array<CharacterSlot> = [];
	var boyfriend           : Character;
	var dad                 : Character;
	var gf                  : Character;
	var cameraController    : CameraController;
	var characterController : CharacterController;
	var uiManager           : UIScriptedManager;
	var gameState           : GameState;
	var metaData            : MetaData;

	// ── Audio ─────────────────────────────────────────────────────────────────
	var vocals    : FlxSound;
	var vocalsBf  : FlxSound;
	var vocalsDad : FlxSound;
	var _perCharVocals : Bool = false;

	// ── Reproducción ──────────────────────────────────────────────────────────
	var isPlaying      : Bool  = false;
	var songLength     : Float = 0;
	var autoSeekTime   : Float = -1;  // si != -1, hacer seek en próximo frame
	var _lastBeat      : Int   = -1;
	var _lastStep      : Int   = -1;
	var _nextEventIdx  : Int   = 0;   // puntero para eventos del editor
	var _nextScriptIdx : Int   = 0;

	// ── Datos del editor ──────────────────────────────────────────────────────
	var pseData        : PSEData;
	var sortedEvents   : Array<PSEEvent>  = [];
	var sortedScripts  : Array<PSEScript> = [];
	var hasUnsaved     : Bool = false;
	var currentSong    : String = '';
	var currentDiff    : String = 'normal';  // dificultad activa para filtrar
	var allDiffs       : Array<String> = []; // se rellena en _refreshDiffList()

	// Scripts en ejecución (HScriptInstance instanciados)
	var scriptInstances : Map<String, HScriptInstance> = new Map();

	// ── UI - Top Bar ──────────────────────────────────────────────────────────
	var topBar        : FlxSprite;
	var songTitleTxt  : FlxText;
	var playBtn       : MiniBtn2;
	var stopBtn       : MiniBtn2;
	var restartBtn    : MiniBtn2;
	var saveBtn       : MiniBtn2;
	var toggleTLBtn   : MiniBtn2;
	var togglePanelBtn: MiniBtn2;
	var diffDropdown  : CoolDropDown;
	var timeTxt       : FlxText;
	var unsavedDot    : FlxSprite;
	var statusTxt     : FlxText;
	var _unsavedDlg   : UnsavedChangesDialog = null;
	var _windowCloseFn : Void->Void = null;

	// ── UI - Timeline ─────────────────────────────────────────────────────────
	var timelineGroup  : FlxGroup;
	var tlBg           : FlxSprite;
	var tlRuler        : FlxSprite;
	var rulerTxt       : FlxTypedGroup<FlxText>;
	var tlPlayhead     : FlxSprite;
	var tlPlayheadTop  : FlxSprite;
	var tlTrackBgs     : Array<FlxSprite> = [];
	var tlTrackLabels  : Array<FlxText>   = [];
	var tlEventSprites : Array<TLEventSprite> = [];
	var timelineVisible: Bool = true;
	var tlScrollX      : Float = 0;    // desplazamiento horizontal en ms
	var tlZoom         : Float = 0.08; // px por ms
	var tlDragSeek     : Bool  = false;

	// ── UI - Right Panel ──────────────────────────────────────────────────────
	var rightPanel         : CoolTabMenu;
	var panelBg            : FlxSprite;
	var rightPanelVisible  : Bool = true;

	// Events tab
	var evtTypeDropdown    : CoolDropDown;
	var evtValueInput      : CoolInputText;
	var evtStepStepper     : CoolNumericStepper;
	var evtTrackStepper    : CoolNumericStepper;
	var evtLabelInput      : CoolInputText;
	var evtDiffChecks      : Array<CoolCheckBox> = [];
	var evtAddBtn          : MiniBtn2;
	var evtDeleteBtn       : MiniBtn2;
	var step_nowBtn        : MiniBtn2;       // Botón "insert at playhead"
	var evtListTxt         : FlxText;
	var evtListScroll      : Int = 0;
	var selectedEventId    : String = '';

	// Scripts tab
	var scrNameInput    : CoolInputText;
	var scrStepStepper  : CoolNumericStepper;
	var scrAutoCheck    : CoolCheckBox;
	var scrEnabledCheck : CoolCheckBox;
	var scrDiffChecks   : Array<CoolCheckBox> = [];
	var scrCodeInput    : CoolInputText;
	var scrAddBtn       : MiniBtn2;
	var scrDeleteBtn    : MiniBtn2;
	var scrRunBtn       : MiniBtn2;
	var scrListTxt      : FlxText;
	var scrListScroll   : Int = 0;
	var selectedScriptId: String = '';

	// ── Layout presets ────────────────────────────────────────────────────────
	var _layoutPreset  : Int   = 1;  // 0=full, 1=normal, 2=compact, 3=side-by-side
	var layoutPresetBtn: MiniBtn2;

	// ── Floating Game Viewport (tipo ZGameVisualizer) ─────────────────────────
	// Cuando _vpFloating=true, la cámara de juego se muestra en una sub-ventana
	// arrastrable y redimensionable en lugar de ocupar todo el fondo.
	var _vpFloating    : Bool  = false;
	var _vpX           : Float = 20;
	var _vpY           : Float = TOP_H + 10;
	var _vpW           : Int   = 640;   // se calcula en _initGameViewport
	var _vpH           : Int   = 360;
	var _vpDragging    : Bool  = false;
	var _vpResizing    : Bool  = false;
	var _vpResizeDir   : String = '';   // 'se' | 'sw' | 'ne' | 'nw' | 'e' | 'w' | 's' | 'n'
	var _vpDragOffX    : Float = 0;
	var _vpDragOffY    : Float = 0;
	var _vpResStartX   : Float = 0;
	var _vpResStartY   : Float = 0;
	var _vpResStartW   : Int   = 0;
	var _vpResStartH   : Int   = 0;
	var _vpMinW        : Int   = 200;
	var _vpMinH        : Int   = 150;
	// Sprites del marco de la ventana flotante (todos en camHUD)
	var _vpBorder      : FlxSprite;
	var _vpTitleBar    : FlxSprite;
	var _vpTitleTxt    : FlxText;
	var _vpHandleCorner: FlxSprite;    // esquina SE de resize
	var _vpFloatBtn    : MiniBtn2;     // botón en top bar para toggle

	// ── Timeline horizontal scrollbar ─────────────────────────────────────────
	// Un scrollbar delgado (12px) encima de la scrubber progress bar para
	// scrollear la zona de tracks sin usar la rueda del ratón.
	var tlHScrollBg    : FlxSprite;
	var tlHScrollThumb : FlxSprite;
	var _tlHScrollDrag : Bool  = false;
	var _tlHScrollDragOff : Float = 0;

	// ── Multi-personaje vocals ────────────────────────────────────────────────
	// Soporta vocals por personaje: vocalsMap["bf"] = FlxSound, etc.
	var vocalsMap      : Map<String, FlxSound> = new Map();

	// ── Skin de notas ─────────────────────────────────────────────────────────
	var _currentNoteSkin : String = 'default';
	var noteSkinDropdown : CoolDropDown;

	// ── Drag de personajes en el viewport ─────────────────────────────────────
	var _dragChar      : Character = null;
	var _dragCharOffX  : Float = 0;
	var _dragCharOffY  : Float = 0;
	var _showCharHandles : Bool = false;
	// Handles visuales de los personajes (uno por slot)
	var _charHandles   : Array<{spr:FlxSprite, char:Character}> = [];

	// ── Tween event builder ───────────────────────────────────────────────────
	var _tweenTargetInput  : CoolInputText;
	var _tweenPropInput    : CoolInputText;
	var _tweenFromInput    : CoolInputText;
	var _tweenToInput      : CoolInputText;
	var _tweenDurInput     : CoolInputText;
	var _tweenEaseDropdown : CoolDropDown;
	var _tweenBuilderGroup : Array<flixel.FlxBasic> = [];

	// ── Status message ────────────────────────────────────────────────────────
	var _statusTimer : Float = 0;
	var _statusMsg   : String = '';

	// ── Internal ──────────────────────────────────────────────────────────────
	var _songMeta      : SongMetadata;
	static var _uidCounter : Int = 0;

	// ─────────────────────────────────────────────────────────────────────────
	//  Constructor
	// ─────────────────────────────────────────────────────────────────────────

	public function new(?meta:SongMetadata)
	{
		super();
		_songMeta = meta;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Create
	// ─────────────────────────────────────────────────────────────────────────

	override public function create():Void
	{
		funkin.system.CursorManager.show();
		persistentDraw = true;
		persistentUpdate = true;

		// Validar SONG
		if (PlayState.SONG == null)
		{
			trace('[PSEditor] ERROR: PlayState.SONG es null — volviendo al menú');
			StateTransition.switchState(new FreeplayEditorState());
			return;
		}

		currentSong = PlayState.SONG.song != null ? PlayState.SONG.song : 'unknown';

		// Stop any music playing from previous menus (freeplay preview, etc.)
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}

		// Cámaras
		setupCameras();

		// GameState
		gameState = GameState.get();
		gameState.reset();
		gameState.health = 1.0; // keep health bar visible

		// Stage + Personajes
		loadStageAndCharacters();

		// MetaData
		metaData = MetaData.load(currentSong, CoolUtil.difficultySuffix());

		// HUD
		setupHUD();

		// Cargar datos del editor (pse_events, pse_scripts desde JSON)
		loadPSEData();

		// Audio
		setupAudio();

		// UI del editor
		setupTopBar();
		setupTimeline();
		setupRightPanel();
		setupStatusBar();

		// ── CRÍTICO: Inicializar posición al inicio de la canción ──────────────
		// Conductor.songPosition puede ser un valor residual de un estado anterior.
		// Forzar a 0 para que la timebar aparezca al inicio.
		Conductor.songPosition = 0;
		if (FlxG.sound.music != null) FlxG.sound.music.time = 0;
		_doSeek(0);
		rebuildTimelineRuler();
		rebuildTimelineEventSprites();

		// ── Viewport flotante: calcular tamaño inicial ────────────────────────
		_initGameViewport();
		_setupCharHandles();

		// ── Importar secciones mustHitSection como eventos de cámara ──────────
		_importSectionCameraEvents();

		// Exponer a scripts
		ScriptHandler.setOnScripts('playStateEditor', this);
		ScriptHandler.setOnScripts('game', this);

		// Empezar pausa (el usuario decide cuándo reproducir)
		isPlaying = false;
		showStatus('PlayState Editor listo. SPACE=play  T=timeline  H=panel  G=viewport flotante  C=drag personajes');

		// Window-close guard
		#if sys
		_windowCloseFn = function()
		{
			if (hasUnsaved)
				try { savePSEData(); } catch (_) {}
		};
		lime.app.Application.current.window.onClose.add(_windowCloseFn);
		#end

		super.create();
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Cameras
	// ─────────────────────────────────────────────────────────────────────────

	function setupCameras():Void
	{
		// ── CRITICAL: camUI must be cameras[0] = FlxG.camera ─────────────────────
		// coolui.CoolUIGroup / CoolTabMenu / CoolInputText use cameras[0] to map screen coords
		// to world coords for click detection. If cameras[0] has zoom != 1 (camGame
		// does after a Camera Zoom event fires), every button/input hitbox is offset.
		// Fix: same pattern as StageEditor and AnimationDebug — transparent camUI at
		// zoom=1 sits at cameras[0]; camGame and camHUD are added on top.
		camUI = new FlxCamera();
		camUI.bgColor.alpha = 0;
		FlxG.cameras.reset(camUI);      // cameras[0] → FlxG.camera = camUI (zoom=1 fixed)

		// camGame — game world (zoom changes with Camera Zoom events)
		camGame = new FlxCamera();
		camGame.bgColor = FlxColor.BLACK;
		FlxG.cameras.add(camGame, false);

		// camHUD — health bar, score, icons (transparent bg, renders above camGame)
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		@:privateAccess FlxCamera._defaultCameras = [camGame];
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Stage + Characters
	// ─────────────────────────────────────────────────────────────────────────

	function loadStageAndCharacters():Void
	{
		var SONG = PlayState.SONG;
		if (SONG.stage == null) SONG.stage = 'stage_week1';
		PlayState.curStage = SONG.stage;
		Paths.currentStage = SONG.stage;

		currentStage = new Stage(SONG.stage);
		currentStage.cameras = [camGame];
		_assignStageCameras(currentStage, [camGame]);
		add(currentStage);

		loadCharacters();

		if (currentStage.aboveCharsGroup != null && currentStage.aboveCharsGroup.length > 0)
			add(currentStage.aboveCharsGroup);

		// Asignar refs legacy
		for (slot in characterSlots)
		{
			if (slot.isGFSlot       && gf       == null) gf       = slot.character;
			else if (slot.isOpponentSlot && dad  == null) dad      = slot.character;
			else if (slot.isPlayerSlot   && boyfriend == null) boyfriend = slot.character;
		}

		if (currentStage.hideGirlfriend)
		{
			for (slot in characterSlots)
				if (slot.isGFSlot && slot.character != null)
					slot.character.visible = false;
		}

		// Camera controller
		if (boyfriend != null && dad != null)
		{
			cameraController = new CameraController(camGame, camHUD, boyfriend, dad, gf);
			if (currentStage != null)
			{
				if (currentStage.defaultCamZoom > 0)
					cameraController.defaultZoom = currentStage.defaultCamZoom;
				cameraController.stageOffsetBf.set(currentStage.cameraBoyfriend.x, currentStage.cameraBoyfriend.y);
				cameraController.stageOffsetDad.set(currentStage.cameraDad.x, currentStage.cameraDad.y);
				cameraController.stageOffsetGf.set(currentStage.cameraGirlfriend.x, currentStage.cameraGirlfriend.y);
				cameraController.lerpSpeed = CameraController.BASE_LERP_SPEED * currentStage.cameraSpeed;
			}
			// Snapshot AFTER stage overrides so resetToInitial() returns to correct state.
			cameraController.snapshotInitialState();
		}

		// Character controller
		characterController = new CharacterController();
		characterController.initFromSlots(characterSlots);
	}

	function loadCharacters():Void
	{
		var SONG = PlayState.SONG;
		if (SONG.characters == null || SONG.characters.length == 0)
		{
			SONG.characters = [];
			SONG.characters.push({ name: SONG.gfVersion ?? 'gf',  x:0,y:0, visible:true, isGF:true, type:'Girlfriend', strumsGroup:'gf_strums_0' });
			SONG.characters.push({ name: SONG.player2  ?? 'dad',  x:0,y:0, visible:true, type:'Opponent',   strumsGroup:'cpu_strums_0' });
			SONG.characters.push({ name: SONG.player1  ?? 'bf',   x:0,y:0, visible:true, type:'Player',     strumsGroup:'player_strums_0' });
		}

		for (i in 0...SONG.characters.length)
		{
			var charData = SONG.characters[i];
			var slot = new CharacterSlot(charData, i);

			if (charData.x == 0 && charData.y == 0)
			{
				switch (slot.charType)
				{
					case 'Girlfriend': slot.character.setPosition(currentStage.gfPosition.x, currentStage.gfPosition.y);
					case 'Opponent':   slot.character.setPosition(currentStage.dadPosition.x, currentStage.dadPosition.y);
					case 'Player':     slot.character.setPosition(currentStage.boyfriendPosition.x, currentStage.boyfriendPosition.y);
					default:
				}
			}
			else
			{
				slot.character.setPosition(charData.x, charData.y);
			}

			if (slot.character.characterData != null)
			{
				var posOff = slot.character.characterData.positionOffset;
				if (posOff != null && posOff.length >= 2)
				{
					slot.character.x += posOff[0];
					slot.character.y += posOff[1];
				}
			}

			characterSlots.push(slot);
			add(slot.character);
		}
	}

	function _assignStageCameras(obj:flixel.FlxBasic, cams:Array<FlxCamera>):Void
	{
		obj.cameras = cams;
		if (Std.isOfType(obj, FlxGroup))
		{
			var grp:FlxGroup = cast obj;
			for (member in grp.members)
				if (member != null)
					_assignStageCameras(member, cams);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  HUD
	// ─────────────────────────────────────────────────────────────────────────

	function setupHUD():Void
	{
		var icons:Array<String> = [PlayState.SONG.player1 ?? 'bf', PlayState.SONG.player2 ?? 'dad'];
		if (boyfriend != null && dad != null
			&& boyfriend.healthIcon != null && dad.healthIcon != null)
			icons = [boyfriend.healthIcon, dad.healthIcon];

		uiManager = new UIScriptedManager(camHUD, gameState, metaData);
		uiManager.setIcons(icons[0], icons[1]);
		uiManager.setStage(PlayState.curStage);
		// Assign camHUD explicitly: defaultCameras=[camGame] in this editor, so without
		// this the group wouldn't be drawn in the camHUD render pass → HUD invisible.
		uiManager.cameras = [camHUD];
		add(uiManager);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Audio
	// ─────────────────────────────────────────────────────────────────────────

	function setupAudio():Void
	{
		var SONG = PlayState.SONG;
		Conductor.changeBPM(SONG.bpm);

		// Parar cualquier música que venga de menús anteriores
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}

		var diffSuffix = (SONG.instSuffix != null && SONG.instSuffix != '')
			? '-' + SONG.instSuffix : CoolUtil.difficultySuffix();

		FlxG.sound.music = Paths.loadInst(SONG.song, diffSuffix);
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.volume = 1;
			FlxG.sound.music.pause();
			FlxG.sound.music.onComplete = _onSongComplete;
			songLength = FlxG.sound.music.length;
		}

		if (SONG.needsVoices)
		{
			// ── Vocales multi-personaje (nuevo sistema) ───────────────────────
			// Prioridad: por personaje (bf, dad, gf, etc.) → merged → base vocals
			var loadedAny = false;

			// 1. Intentar cargar vocales por cada personaje definido en SONG.characters
			if (SONG.characters != null)
			{
				for (charData in SONG.characters)
				{
					final cname = charData.name ?? '';
					if (cname == '') continue;
					// Alias comunes
					final aliases = [cname, _charVocalAlias(cname)];
					for (alias in aliases)
					{
						var snd = Paths.loadVoicesForChar(SONG.song, alias, diffSuffix);
						if (snd != null)
						{
							vocalsMap.set(alias, snd);
							FlxG.sound.list.add(snd);
							_perCharVocals = true;
							loadedAny = true;
							break;
						}
					}
				}
			}

			// 2. Fallback legacy: bf / dad por nombre
			if (!loadedAny)
			{
				var bfSnd  = Paths.loadVoicesForChar(SONG.song, 'bf',  diffSuffix);
				var dadSnd = Paths.loadVoicesForChar(SONG.song, 'dad', diffSuffix);

				if (bfSnd != null)
				{
					_perCharVocals = true;
					vocalsBf  = bfSnd;
					vocalsDad = dadSnd ?? Paths.loadVoices(SONG.song, diffSuffix);
					if (vocalsBf  != null) FlxG.sound.list.add(vocalsBf);
					if (vocalsDad != null) FlxG.sound.list.add(vocalsDad);
					loadedAny = true;
				}
			}

			// 3. Fallback: archivo vocals unificado
			if (!loadedAny)
			{
				vocals = Paths.loadVoices(SONG.song, diffSuffix);
				if (vocals != null) FlxG.sound.list.add(vocals);
			}
		}
	}

	/**
	 * Resuelve el alias de vocal para un nombre de personaje.
	 * "boyfriend" → "bf", "pico" → "pico", etc.
	 */
	function _charVocalAlias(name:String):String
	{
		return switch (name.toLowerCase())
		{
			case 'boyfriend' | 'bf-pixel' | 'bf-car' | 'bf-holding-gs': 'bf';
			case 'dad' | 'daddy-dearest': 'dad';
			case 'gf' | 'gf-christmas' | 'gf-car' | 'gf-pixel': 'gf';
			default: name;
		};
	}

	function _onSongComplete():Void
	{
		isPlaying = false;
		syncAudio(false);
		showStatus('♪ Canción terminada');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  PSE Data  (load / save)
	// ─────────────────────────────────────────────────────────────────────────

	function loadPSEData():Void
	{
		pseData = { events: [], scripts: [] };

		// ── 1. Bloque pse del .level (nuevo) ─────────────────────────────
		#if sys
		final parsed : Dynamic = funkin.data.LevelFile.loadPSE(currentSong);
		if (parsed != null)
		{
			if (parsed.events  != null) pseData.events  = parsed.events;
			if (parsed.scripts != null) pseData.scripts = parsed.scripts;
			trace('[PSEditor] PSE data cargado desde .level');
		}
		else
		{
			// ── 2. Fallback: -playstate.json legacy ───────────────────────
			var path = _pseLegacyPath();
			if (FileSystem.exists(path))
			{
				try
				{
					var raw     = File.getContent(path);
					var legacy  : PSEData = cast Json.parse(raw);
					if (legacy.events  != null) pseData.events  = legacy.events;
					if (legacy.scripts != null) pseData.scripts = legacy.scripts;
					trace('[PSEditor] PSE data cargado desde legacy $path');
				}
				catch (e:Dynamic)
				{
					trace('[PSEditor] Error cargando PSE legacy: $e');
				}
			}
		}
		#end

		_rebuildSorted();
		_refreshDiffList();
	}

	function savePSEData():Void
	{
		#if sys
		final ok = funkin.data.LevelFile.savePSE(currentSong, pseData);
		if (ok)
		{
			hasUnsaved = false;
			_updateUnsavedDot();
			showStatus('✓ Guardado en ${currentSong.toLowerCase()}.level');
		}
		else
		{
			showStatus('✗ Error al guardar (ver consola)');
		}
		#else
		showStatus('✗ Guardado solo disponible en desktop');
		#end
	}

	/** Ruta del archivo -playstate.json legacy (solo para leer datos viejos). */
	function _pseLegacyPath():String
	{
		var name = currentSong.toLowerCase();
		return Paths.resolve('songs/$name/$name-playstate.json');
	}

	function _rebuildSorted():Void
	{
		sortedEvents  = (pseData.events  ?? []).copy();
		sortedScripts = (pseData.scripts ?? []).copy();
		sortedEvents.sort( (a, b) -> Std.int(a.stepTime - b.stepTime) );
		sortedScripts.sort((a, b) -> Std.int(a.triggerStep - b.triggerStep) );
		_nextEventIdx  = 0;
		_nextScriptIdx = 0;
		rebuildTimelineEventSprites();
	}

	function _refreshDiffList():Void
	{
		// Obtener las dificultades reales de la canción (del .level o de los .json)
		final songDiffPairs = funkin.data.LevelFile.getAvailableDifficulties(currentSong);

		// Construir set: diffs reales + las que aparecen en los datos PSE
		var set : Map<String, Bool> = new Map();

		// Siempre incluir las diffs reales de la canción
		for (pair in songDiffPairs)
		{
			// pair[1] es el sufijo: '', '-easy', '-hard', etc.
			// Lo convertimos al nombre corto: '' → 'normal', '-hard' → 'hard'
			final suffix = pair[1];
			final name   = suffix == '' ? 'normal' : suffix.substr(1); // quitar '-'
			set.set(name, true);
		}

		// Agregar cualquier diff mencionada en eventos/scripts pero no en la canción
		for (e in (pseData.events ?? []))
			for (d in e.difficulties)
				if (d != '*') set.set(d, true);
		for (s in (pseData.scripts ?? []))
			for (d in s.difficulties)
				if (d != '*') set.set(d, true);

		allDiffs = [for (k in set.keys()) k];

		// Orden: easy, normal, hard, resto alfabético
		final priority = ['easy', 'normal', 'hard'];
		final ordered : Array<String> = [];
		for (p in priority)
			if (allDiffs.contains(p)) ordered.push(p);
		final rest = allDiffs.filter(d -> !priority.contains(d));
		rest.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		allDiffs = ordered.concat(rest);

		// Si no hay ninguna, fallback
		if (allDiffs.length == 0) allDiffs = ['easy', 'normal', 'hard'];

		// Validar que currentDiff siga existiendo
		if (!allDiffs.contains(currentDiff))
			currentDiff = allDiffs[0];
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Top Bar UI
	// ─────────────────────────────────────────────────────────────────────────

	function setupTopBar():Void
	{
		topBar = new FlxSprite(0, 0).makeGraphic(SW, TOP_H, C_TOPBAR);
		topBar.scrollFactor.set();
		topBar.cameras = [camHUD];
		add(topBar);

		// Borde inferior del topbar
		var topBorder = new FlxSprite(0, TOP_H - 2).makeGraphic(SW, 2, C_ACCENT);
		topBorder.scrollFactor.set(); topBorder.alpha = 0.5;
		topBorder.cameras = [camHUD]; add(topBorder);

		// Título
		songTitleTxt = new FlxText(8, 5, 260, '▶ PLAYSTATE EDITOR — ${currentSong.toUpperCase()}', 11);
		songTitleTxt.setFormat(Paths.font('vcr.ttf'), 11, C_ACCENT, LEFT);
		songTitleTxt.scrollFactor.set(); songTitleTxt.cameras = [camHUD]; add(songTitleTxt);

		// Punto de cambios no guardados
		unsavedDot = new FlxSprite(276, 12).makeGraphic(8, 8, C_UNSAVED);
		unsavedDot.scrollFactor.set(); unsavedDot.cameras = [camHUD];
		unsavedDot.visible = false; add(unsavedDot);

		// Botones de transporte
		var bx = 295.0;
		restartBtn   = _makeTopBtn(bx,      '⏮', C_PANEL,   _onRestart);   bx += 36;
		playBtn      = _makeTopBtn(bx,      '▶', 0xFF224422, _onPlayPause); bx += 36;
		stopBtn      = _makeTopBtn(bx,      '⏹', C_PANEL,   _onStop);      bx += 42;

		// Dropdown de dificultad
		var diffLabel = new FlxText(bx, 8, 0, 'DIFF:', 10);
		diffLabel.setFormat(Paths.font('vcr.ttf'), 10, C_SUBTEXT, LEFT);
		diffLabel.scrollFactor.set(); diffLabel.cameras = [camHUD]; add(diffLabel);
		bx += 36;

		if (diffDropdown != null) remove(diffDropdown);
		var ddItems = allDiffs.length > 0 ? allDiffs : ['normal'];
		diffDropdown = new CoolDropDown(bx, 6, CoolDropDown.makeStrIdLabelArray(ddItems, true), _onDiffChanged);
		diffDropdown.selectedLabel = currentDiff;
		diffDropdown.scrollFactor.set(); diffDropdown.cameras = [camHUD];
		add(diffDropdown); bx += 90;

		// Tiempo
		timeTxt = new FlxText(bx, 8, 120, '0:00 / 0:00', 10);
		timeTxt.setFormat(Paths.font('vcr.ttf'), 10, C_SUBTEXT, LEFT);
		timeTxt.scrollFactor.set(); timeTxt.cameras = [camHUD]; add(timeTxt);

		// Botones de la derecha
		var rbx = SW - 36.0;
		saveBtn        = _makeTopBtn(rbx, '💾', 0xFF222244, savePSEData);      rbx -= 40;
		togglePanelBtn = _makeTopBtn(rbx, '☰',  C_PANEL,   _toggleRightPanel); rbx -= 40;
		toggleTLBtn    = _makeTopBtn(rbx, '⏤',  C_PANEL,   _toggleTimeline);   rbx -= 44;
		layoutPresetBtn= _makeTopBtn(rbx, '⊞',  0xFF1A1A40, _cycleLayoutPreset); rbx -= 44;
		_vpFloatBtn    = _makeTopBtn(rbx, '🎮',  0xFF1A2A1A, _toggleFloatingViewport);
	}

	function _makeTopBtn(x:Float, label:String, color:Int, cb:Void->Void):MiniBtn2
	{
		var btn = new MiniBtn2(x, 3, 34, 29, label, color, C_TEXT, cb);
		btn.scrollFactor.set(); btn.cameras = [camHUD];
		btn.label.scrollFactor.set(); btn.label.cameras = [camHUD];
		add(btn); add(btn.label);
		return btn;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Status Bar
	// ─────────────────────────────────────────────────────────────────────────

	function setupStatusBar():Void
	{
		var sbY = SH - STATUS_H;
		var sb  = new FlxSprite(0, sbY).makeGraphic(SW, STATUS_H, C_TOPBAR);
		sb.scrollFactor.set(); sb.cameras = [camHUD]; add(sb);
		var sbBorder = new FlxSprite(0, sbY).makeGraphic(SW, 1, C_BORDER);
		sbBorder.scrollFactor.set(); sbBorder.cameras = [camHUD]; add(sbBorder);

		statusTxt = new FlxText(8, sbY + 4, SW - 16, '', 10);
		statusTxt.setFormat(Paths.font('vcr.ttf'), 10, C_SUBTEXT, LEFT);
		statusTxt.scrollFactor.set(); statusTxt.cameras = [camHUD]; add(statusTxt);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Timeline  (estilo ChartingState / imagen de referencia)
	//
	//  Layout vertical (de arriba abajo, TL_H total):
	//   ┌─────────────────────────────────────────────────────────────────┐
	//   │ RULER   (TL_RULER_H=22)  Bar:Beat markers + beat-grid lines     │
	//   │ SCRUBBER (TL_SCRUB_H=32) Progress fill + waveform ticks         │
	//   │ TRACKS  (TL_TRACK_H*N)   Label col | event diamonds per track   │
	//   │ TRANSPORT (TL_TRANS_H=36) |< << ▶/⏸ >> >|  BPM  time remaining │
	//   └─────────────────────────────────────────────────────────────────┘
	// ─────────────────────────────────────────────────────────────────────────

	// Extra sub-layout constants
	// TL_RULER_H already declared above (= 24); use the canonical value.
	static inline final TL_SCRUB_H  : Int = 32;
	static inline final TL_TRACK_H2 : Int = 22;   // altura de cada pista en el nuevo layout
	static inline final TL_TRANS_H  : Int = 36;
	static inline final TL_HSCROLL_H_REAL : Int = 12; // scrollbar horizontal sobre el scrubber

	// Additional UI elements for the new timeline
	var tlScrubBg       : FlxSprite;       // fondo del scrubber
	var tlScrubFill     : FlxSprite;       // relleno de progreso (se redimensiona cada frame)
	var tlScrubHandle   : FlxSprite;       // círculo del playhead en el scrubber
	var tlTransportBar  : FlxSprite;       // fondo del transport
	var tlTimeLbl       : FlxText;         // "00:00" tiempo actual
	var tlTimeRemLbl    : FlxText;         // "-01:21" tiempo restante
	var tlBpmLbl        : FlxText;         // "Normal BPM: 100"
	var tlBeatGridLines : Array<FlxSprite> = [];   // líneas verticales del beat en los tracks
	var tlTransBtns     : Array<MiniBtn2>  = [];   // botones del transport

	// Dragging scrubber
	var _scrubDragging  : Bool  = false;

	function setupTimeline():Void
	{
		timelineGroup = new FlxGroup();

		var tlY       = _tlY();
		var trackN    = TRACK_NAMES.length;
		var tracksH   = trackN * TL_TRACK_H2;
		var areaW     = _tlAreaW();

		// ── Fondo general de la timeline ─────────────────────────────────────
		tlBg = new FlxSprite(0, tlY).makeGraphic(SW, TL_H, C_TIMELINE);
		tlBg.scrollFactor.set(); tlBg.cameras = [camHUD];
		timelineGroup.add(tlBg); add(tlBg);

		// Línea de separación superior (accent)
		var topLine = new FlxSprite(0, tlY).makeGraphic(SW, 2, C_ACCENT);
		topLine.scrollFactor.set(); topLine.cameras = [camHUD]; topLine.alpha = 0.5;
		timelineGroup.add(topLine); add(topLine);

		// ── Ruler (bar:beat) ─────────────────────────────────────────────────
		var rulerBg = new FlxSprite(0, tlY).makeGraphic(SW, TL_RULER_H, C_RULER);
		rulerBg.scrollFactor.set(); rulerBg.cameras = [camHUD];
		timelineGroup.add(rulerBg); add(rulerBg);

		// Separador bajo el ruler
		var rulerSep = new FlxSprite(0, tlY + TL_RULER_H - 1).makeGraphic(SW, 1, C_BORDER);
		rulerSep.scrollFactor.set(); rulerSep.cameras = [camHUD]; rulerSep.alpha = 0.5;
		timelineGroup.add(rulerSep); add(rulerSep);

		rulerTxt = new FlxTypedGroup<FlxText>();
		for (i in 0...60)
		{
			var t = new FlxText(0, tlY + 4, 50, '', 9);
			t.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, CENTER);
			t.scrollFactor.set(); t.cameras = [camHUD]; t.visible = false;
			rulerTxt.add(t); add(t);
		}

		// Beat-grid lines (vertical, en el track area)
		for (i in 0...60)
		{
			var gl = new FlxSprite(0, tlY + TL_RULER_H).makeGraphic(1, tracksH, 0xFF2A2A44);
			gl.scrollFactor.set(); gl.cameras = [camHUD]; gl.visible = false;
			tlBeatGridLines.push(gl);
			timelineGroup.add(gl); add(gl);
		}

		// ── Track area ───────────────────────────────────────────────────────
		var tracksY = tlY + TL_RULER_H;

		// Columna de labels (lado izquierdo, fondo)
		var labelColBg = new FlxSprite(0, tracksY).makeGraphic(TL_LABEL_W, tracksH, 0xFF111122);
		labelColBg.scrollFactor.set(); labelColBg.cameras = [camHUD];
		timelineGroup.add(labelColBg); add(labelColBg);

		// Borde derecho de la columna de labels
		var labelBorder = new FlxSprite(TL_LABEL_W - 1, tracksY).makeGraphic(1, tracksH, C_BORDER);
		labelBorder.scrollFactor.set(); labelBorder.cameras = [camHUD]; labelBorder.alpha = 0.6;
		timelineGroup.add(labelBorder); add(labelBorder);

		for (i in 0...trackN)
		{
			var ty     = tracksY + i * TL_TRACK_H2;
			var tColor = TRACK_COLORS[i];

			// Fondo de la pista (área de eventos)
			var trackBg = new FlxSprite(TL_LABEL_W, ty).makeGraphic(_tlAreaW(), TL_TRACK_H2, C_TIMELINE);
			trackBg.scrollFactor.set(); trackBg.cameras = [camHUD]; trackBg.alpha = 0.7;
			timelineGroup.add(trackBg); add(trackBg);
			tlTrackBgs.push(trackBg);

			// Separador inferior de la pista
			var sep = new FlxSprite(0, ty + TL_TRACK_H2 - 1).makeGraphic(SW, 1, C_BORDER);
			sep.scrollFactor.set(); sep.cameras = [camHUD]; sep.alpha = 0.25;
			timelineGroup.add(sep); add(sep);

			// Acento de color izquierdo (barra de 3px del color de la pista)
			var accent = new FlxSprite(0, ty + 2).makeGraphic(3, TL_TRACK_H2 - 4, tColor);
			accent.scrollFactor.set(); accent.cameras = [camHUD]; accent.alpha = 0.8;
			timelineGroup.add(accent); add(accent);

			// Icono circular de color de pista
			var dot = new FlxSprite(7, ty + TL_TRACK_H2 / 2 - 4).makeGraphic(8, 8, tColor);
			dot.scrollFactor.set(); dot.cameras = [camHUD];
			timelineGroup.add(dot); add(dot);

			// Label de la pista
			var lbl = new FlxText(18, ty + 5, TL_LABEL_W - 22, TRACK_NAMES[i], 9);
			lbl.setFormat(Paths.font('vcr.ttf'), 9, tColor, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			timelineGroup.add(lbl); add(lbl);
			tlTrackLabels.push(lbl);
		}

		// ── Scrollbar horizontal (para scrollear tlScrollX) ──────────────────
		// Aparece justo encima del scrubber. Thumb proporcional al ratio visible/total.
		var hsBg = new FlxSprite(TL_LABEL_W, tracksY + tracksH).makeGraphic(_tlAreaW(), TL_HSCROLL_H_REAL, 0xFF080814);
		hsBg.scrollFactor.set(); hsBg.cameras = [camHUD]; hsBg.alpha = 0.9;
		timelineGroup.add(hsBg); add(hsBg);
		tlHScrollBg = hsBg;

		var hsSepTop = new FlxSprite(0, tracksY + tracksH).makeGraphic(SW, 1, C_BORDER);
		hsSepTop.scrollFactor.set(); hsSepTop.cameras = [camHUD]; hsSepTop.alpha = 0.4;
		timelineGroup.add(hsSepTop); add(hsSepTop);

		tlHScrollThumb = new FlxSprite(TL_LABEL_W, tracksY + tracksH + 2).makeGraphic(60, TL_HSCROLL_H_REAL - 4, C_ACCENT);
		tlHScrollThumb.scrollFactor.set(); tlHScrollThumb.cameras = [camHUD]; tlHScrollThumb.alpha = 0.55;
		timelineGroup.add(tlHScrollThumb); add(tlHScrollThumb);

		// ── Scrubber / Progress bar ───────────────────────────────────────────
		var scrubY = tlY + TL_RULER_H + tracksH + TL_HSCROLL_H_REAL; // +scrollbar

		tlScrubBg = new FlxSprite(0, scrubY).makeGraphic(SW, TL_SCRUB_H, 0xFF0A0A1A);
		tlScrubBg.scrollFactor.set(); tlScrubBg.cameras = [camHUD];
		timelineGroup.add(tlScrubBg); add(tlScrubBg);

		// Separador superior del scrubber
		var scrubTopSep = new FlxSprite(0, scrubY).makeGraphic(SW, 1, C_BORDER);
		scrubTopSep.scrollFactor.set(); scrubTopSep.cameras = [camHUD]; scrubTopSep.alpha = 0.5;
		timelineGroup.add(scrubTopSep); add(scrubTopSep);

		// Relleno de progreso (ancho se actualiza cada frame)
		tlScrubFill = new FlxSprite(0, scrubY + 1).makeGraphic(1, TL_SCRUB_H - 2, 0xFF1A3A5A);
		tlScrubFill.scrollFactor.set(); tlScrubFill.cameras = [camHUD];
		timelineGroup.add(tlScrubFill); add(tlScrubFill);

		// Tick lines de waveform simulada (estética)
		var tickW = SW / 80;
		for (i in 0...80)
		{
			var tickH = 4 + Std.int(Math.random() * (TL_SCRUB_H - 10));
			var tickY = scrubY + (TL_SCRUB_H - tickH) / 2;
			var tick  = new FlxSprite(i * tickW, tickY).makeGraphic(Std.int(tickW - 1), tickH, 0xFF1E3050);
			tick.scrollFactor.set(); tick.cameras = [camHUD]; tick.alpha = 0.7;
			timelineGroup.add(tick); add(tick);
		}

		// Handle del scrubber (círculo del playhead en el scrubber)
		tlScrubHandle = new FlxSprite(0, scrubY + TL_SCRUB_H / 2 - 7).makeGraphic(4, 14, C_PLAYHEAD);
		tlScrubHandle.scrollFactor.set(); tlScrubHandle.cameras = [camHUD];
		timelineGroup.add(tlScrubHandle); add(tlScrubHandle);

		// ── Transport Bar ─────────────────────────────────────────────────────
		var transY = scrubY + TL_SCRUB_H;

		tlTransportBar = new FlxSprite(0, transY).makeGraphic(SW, TL_TRANS_H, 0xFF0C0C1C);
		tlTransportBar.scrollFactor.set(); tlTransportBar.cameras = [camHUD];
		timelineGroup.add(tlTransportBar); add(tlTransportBar);

		var transSep = new FlxSprite(0, transY).makeGraphic(SW, 1, C_BORDER);
		transSep.scrollFactor.set(); transSep.cameras = [camHUD]; transSep.alpha = 0.6;
		timelineGroup.add(transSep); add(transSep);

		// Tiempo actual (izquierda)
		tlTimeLbl = new FlxText(10, transY + 9, 80, '00:00', 13);
		tlTimeLbl.setFormat(Paths.font('vcr.ttf'), 13, 0xFFCCCCDD, LEFT);
		tlTimeLbl.scrollFactor.set(); tlTimeLbl.cameras = [camHUD];
		timelineGroup.add(tlTimeLbl); add(tlTimeLbl);

		// Separador vertical izquierdo del transport
		var tSepL = new FlxSprite(90, transY + 6).makeGraphic(1, TL_TRANS_H - 12, C_BORDER);
		tSepL.scrollFactor.set(); tSepL.cameras = [camHUD]; tSepL.alpha = 0.5;
		timelineGroup.add(tSepL); add(tSepL);

		// Botones de transport: |< << ▶/⏸ >> >|
		var btnLabels  = ['|<', '<<', '▶', '>>', '>|'];
		var btnActions : Array<Void->Void> = [
			function() { autoSeekTime = 0; },
			function() { autoSeekTime = Math.max(0, Conductor.songPosition - Conductor.crochet * 4); },
			_onPlayPause,
			function() { autoSeekTime = Math.min(songLength, Conductor.songPosition + Conductor.crochet * 4); },
			function() { autoSeekTime = songLength > 0 ? songLength - 100 : 0; }
		];
		var btnColors = [C_PANEL, C_PANEL, 0xFF1A3A1A, C_PANEL, C_PANEL];
		var centerX   = SW / 2 - 115.0;

		for (i in 0...btnLabels.length)
		{
			var bw = (i == 2) ? 48 : 38;  // ▶ más ancho
			var btn = new MiniBtn2(centerX, transY + 4, bw, TL_TRANS_H - 8, btnLabels[i],
				btnColors[i], i == 2 ? 0xFF88FF88 : C_TEXT, btnActions[i]);
			btn.scrollFactor.set(); btn.cameras = [camHUD];
			tlTransBtns.push(btn);
			timelineGroup.add(btn); add(btn); add(btn.label);
			centerX += bw + 4;
		}

		// Separador vertical derecho del transport
		var tSepR = new FlxSprite(SW - 290, transY + 6).makeGraphic(1, TL_TRANS_H - 12, C_BORDER);
		tSepR.scrollFactor.set(); tSepR.cameras = [camHUD]; tSepR.alpha = 0.5;
		timelineGroup.add(tSepR); add(tSepR);

		// BPM label (derecha)
		tlBpmLbl = new FlxText(SW - 285, transY + 5, 160, 'Normal BPM: ${Std.int(Conductor.bpm)}', 10);
		tlBpmLbl.setFormat(Paths.font('vcr.ttf'), 10, C_TIMELINE, LEFT);
		tlBpmLbl.scrollFactor.set(); tlBpmLbl.cameras = [camHUD];
		timelineGroup.add(tlBpmLbl); add(tlBpmLbl);

		// Tiempo restante (extremo derecho, rojo)
		tlTimeRemLbl = new FlxText(SW - 120, transY + 5, 110, '-00:00', 13);
		tlTimeRemLbl.setFormat(Paths.font('vcr.ttf'), 13, 0xFFFF4444, RIGHT);
		tlTimeRemLbl.scrollFactor.set(); tlTimeRemLbl.cameras = [camHUD];
		timelineGroup.add(tlTimeRemLbl); add(tlTimeRemLbl);

		// Botones de zoom (en el ruler, esquina izquierda)
		var zmOut = _makeTLBtn(TL_LABEL_W - 44, tlY + 3, '−', function() { tlZoom = Math.max(0.005, tlZoom * 0.65); rebuildTimelineRuler(); rebuildTimelineEventSprites(); });
		var zmIn  = _makeTLBtn(TL_LABEL_W - 22, tlY + 3, '+', function() { tlZoom = Math.min(2.0,  tlZoom * 1.5); rebuildTimelineRuler();  rebuildTimelineEventSprites(); });
		timelineGroup.add(zmOut); add(zmOut); add(zmOut.label);
		timelineGroup.add(zmIn);  add(zmIn);  add(zmIn.label);

		// ── Playhead ──────────────────────────────────────────────────────────
		// Línea vertical roja que cruza ruler + tracks + scrubber
		var phH = TL_RULER_H + tracksH + TL_SCRUB_H;
		tlPlayhead = new FlxSprite(TL_LABEL_W, tlY).makeGraphic(2, phH, C_PLAYHEAD);
		tlPlayhead.scrollFactor.set(); tlPlayhead.cameras = [camHUD]; tlPlayhead.alpha = 0.85;
		timelineGroup.add(tlPlayhead); add(tlPlayhead);

		// Triángulo en la cabeza del playhead (ruler)
		tlPlayheadTop = new FlxSprite(TL_LABEL_W - 4, tlY).makeGraphic(10, TL_RULER_H, C_PLAYHEAD);
		tlPlayheadTop.scrollFactor.set(); tlPlayheadTop.cameras = [camHUD]; tlPlayheadTop.alpha = 0.9;
		timelineGroup.add(tlPlayheadTop); add(tlPlayheadTop);

		rebuildTimelineRuler();
		rebuildTimelineEventSprites();
	}

	function _makeTLBtn(x:Float, y:Float, label:String, cb:Void->Void):MiniBtn2
	{
		var btn = new MiniBtn2(x, y, 18, 16, label, 0xFF1A1A2E, C_TEXT, cb);
		btn.scrollFactor.set(); btn.cameras = [camHUD];
		btn.label.scrollFactor.set(); btn.label.cameras = [camHUD];
		return btn;
	}

	function rebuildTimelineRuler():Void
	{
		if (rulerTxt == null) return;
		for (t in rulerTxt.members) t.visible = false;
		for (gl in tlBeatGridLines) gl.visible = false;

		var tlY       = _tlY();
		var areaW     = _tlAreaW();
		var beatMs    = Conductor.crochet;
		var startMs   = tlScrollX;
		var endMs     = startMs + areaW / tlZoom;
		var trackN    = TRACK_NAMES.length;
		var tracksH   = trackN * TL_TRACK_H2;

		var beat  = Math.floor(startMs / beatMs);
		var rIdx  = 0;
		var glIdx = 0;
		var maxX  = SW - (rightPanelVisible ? RIGHT_W : 0);

		while (beat * beatMs <= endMs
			&& rIdx < rulerTxt.members.length
			&& glIdx < tlBeatGridLines.length)
		{
			var xPos = TL_LABEL_W + (beat * beatMs - startMs) * tlZoom;
			if (xPos >= TL_LABEL_W && xPos <= maxX)
			{
				var bar = Math.floor(beat / 4) + 1;
				var b   = beat % 4;
				var isBar = (b == 0);

				// Ruler tick texto
				var t = rulerTxt.members[rIdx];
				t.text    = isBar ? '$bar' : '$bar.${b + 1}';
				t.x       = xPos - 25;
				t.y       = tlY + 4;
				t.color   = isBar ? 0xFF000000 : C_SUBTEXT;
				t.visible = true;
				rIdx++;

				// Beat tick vertical en el ruler
				var tickH = isBar ? TL_RULER_H - 4 : TL_RULER_H / 2;
				// (reusamos el sprite de gridLine si está visible, sino tomamos el siguiente)
				var gl = tlBeatGridLines[glIdx];
				gl.x       = xPos;
				gl.y       = tlY + TL_RULER_H - tickH;
				gl.makeGraphic(isBar ? 2 : 1, Std.int(tickH + tracksH), isBar ? 0xFF3A3A5A : 0xFF222240);
				gl.alpha   = isBar ? 0.7 : 0.35;
				gl.visible = true;
				glIdx++;
			}
			beat++;
		}
	}

	function rebuildTimelineEventSprites():Void
	{
		for (s in tlEventSprites)
		{
			remove(s);
			if (s.labelTxt != null) { remove(s.labelTxt); s.labelTxt.destroy(); }
			s.destroy();
		}
		tlEventSprites = [];

		if (!timelineVisible || pseData == null) return;

		var tlY      = _tlY();
		var tracksY  = tlY + TL_RULER_H;
		var areaW    = _tlAreaW();
		var startMs  = tlScrollX;
		var endMs    = startMs + areaW / tlZoom;

		for (evt in (pseData.events ?? []))
		{
			if (!_isEventForDiff(evt, currentDiff)) continue;

			var evtMs  = Conductor.stepCrochet * evt.stepTime;
			if (evtMs < startMs - 60 || evtMs > endMs + 60) continue;

			var xPos   = TL_LABEL_W + (evtMs - startMs) * tlZoom;
			var trackI = Std.int(Math.min(evt.trackIndex, TRACK_NAMES.length - 1));
			var yPos   = tracksY + trackI * TL_TRACK_H2 + 2;
			var isSel  = (evt.id == selectedEventId);

			var spr = new TLEventSprite(xPos - 2, yPos, TL_TRACK_H2 - 4, TRACK_COLORS[trackI], evt.id, isSel);
			spr.scrollFactor.set(); spr.cameras = [camHUD];
			tlEventSprites.push(spr);
			add(spr);

			// Label del evento
			var lbl = new FlxText(xPos + 10, yPos + 2, 90, (evt.label != null && evt.label != '') ? evt.label : evt.type, 8);
			lbl.setFormat(Paths.font('vcr.ttf'), 8, isSel ? FlxColor.WHITE : 0xFFCCCCCC, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			spr.labelTxt = lbl;
			add(lbl);
		}
	}

	function _updateTimelinePlayhead():Void
	{
		if (!timelineVisible) return;

		var tlY       = _tlY();
		var posMs     = Conductor.songPosition;
		var areaW     = _tlAreaW();
		var trackN    = TRACK_NAMES.length;
		var tracksH   = trackN * TL_TRACK_H2;

		// Auto-scroll en modo play
		if (isPlaying && !_scrubDragging && !_tlHScrollDrag)
		{
			var xPosRel = (posMs - tlScrollX) * tlZoom;
			if (xPosRel > areaW * 0.82) tlScrollX = posMs - areaW * 0.25 / tlZoom;
			if (xPosRel < 0)            tlScrollX = posMs;
			if (tlScrollX < 0)          tlScrollX = 0;
		}

		var xPos = TL_LABEL_W + (posMs - tlScrollX) * tlZoom;

		// Playhead vertical
		if (tlPlayhead    != null) { tlPlayhead.x    = xPos;      tlPlayhead.y    = tlY; }
		if (tlPlayheadTop != null) { tlPlayheadTop.x = xPos - 4;  tlPlayheadTop.y = tlY; }

		// ── Horizontal scrollbar thumb ─────────────────────────────────────────
		if (tlHScrollThumb != null && songLength > 0)
		{
			var hsY      = tlY + TL_RULER_H + tracksH + 2;
			var hsW      = _tlAreaW();
			var totalMs  = songLength;
			// Ancho del thumb proporcional a la ventana visible
			var visibleMs   = areaW / tlZoom;
			var thumbRatio  = Math.min(1.0, visibleMs / totalMs);
			var thumbW      = Std.int(Math.max(20, hsW * thumbRatio));
			// Posición del thumb
			var scrollRatio = tlScrollX / Math.max(1, totalMs - visibleMs);
			var thumbX      = TL_LABEL_W + Std.int((hsW - thumbW) * FlxMath.bound(scrollRatio, 0, 1));
			tlHScrollThumb.x = thumbX;
			tlHScrollThumb.y = hsY;
			tlHScrollThumb.makeGraphic(thumbW, TL_HSCROLL_H_REAL - 4, C_ACCENT);
		}

		// ── Scrubber progress fill + handle ───────────────────────────────────
		var scrubY = tlY + TL_RULER_H + tracksH + TL_HSCROLL_H_REAL;
		if (tlScrubFill != null && songLength > 0)
		{
			var fillW = Std.int(Math.max(1, (posMs / songLength) * SW));
			tlScrubFill.makeGraphic(fillW, TL_SCRUB_H - 2, 0xFF1A3A5A);
			tlScrubFill.y = scrubY + 1;
		}
		if (tlScrubHandle != null && songLength > 0)
		{
			var hx = (posMs / songLength) * SW - 2;
			tlScrubHandle.x = hx;
			tlScrubHandle.y = scrubY + TL_SCRUB_H / 2 - 7;
		}

		// Actualizar tiempo en el transport bar
		if (tlTimeLbl != null)
			tlTimeLbl.text = _fmtTime(posMs);
		if (tlTimeRemLbl != null && songLength > 0)
			tlTimeRemLbl.text = '-' + _fmtTime(songLength - posMs);
		if (tlBpmLbl != null)
			tlBpmLbl.text = 'Normal BPM: ${Std.int(Conductor.bpm)}';

		// Botón play ▶/⏸ (índice 2)
		if (tlTransBtns.length > 2 && tlTransBtns[2] != null)
		{
			tlTransBtns[2].label.text = isPlaying ? '⏸' : '▶';
			tlTransBtns[2].label.color = isPlaying ? 0xFFFFAA00 : 0xFF88FF88;
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Right Panel (CoolTabMenu)
	// ─────────────────────────────────────────────────────────────────────────

	function setupRightPanel():Void
	{
		var panelX = SW - RIGHT_W;
		var panelH = SH - TOP_H - STATUS_H - (timelineVisible ? TL_H : 0);

		panelBg = new FlxSprite(panelX, TOP_H).makeGraphic(RIGHT_W, panelH, C_PANEL);
		panelBg.scrollFactor.set(); panelBg.cameras = [camHUD]; add(panelBg);

		var borderLine = new FlxSprite(panelX, TOP_H).makeGraphic(2, panelH, C_ACCENT);
		borderLine.scrollFactor.set(); borderLine.cameras = [camHUD]; borderLine.alpha = 0.35; add(borderLine);

		var tabs = [
			{name:'Events',  label:'Events'},
			{name:'Scripts', label:'Scripts'},
			{name:'Song',    label:'Song'},
		];

		rightPanel = new CoolTabMenu(null, tabs, true);
		rightPanel.resize(RIGHT_W - 2, panelH);
		rightPanel.x = panelX + 2;
		rightPanel.y = TOP_H;
		rightPanel.scrollFactor.set();
		rightPanel.cameras = [camHUD];
		add(rightPanel);

		_buildEventsTab();
		_buildScriptsTab();
		_buildSongTab();
	}

	// ── Events Tab ────────────────────────────────────────────────────────────

	function _buildEventsTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = 'Events';

		var y = 6.0;

		function lbl(t:String, ly:Float):FlxText
		{
			var tx = new FlxText(6, ly, 0, t, 10);
			tx.color = C_TIMELINE; tab.add(tx); return tx;
		}
		function sep(sy:Float):FlxSprite
		{
			var s = new FlxSprite(4, sy).makeGraphic(RIGHT_W - 16, 1, C_BORDER);
			s.alpha = 0.3; tab.add(s); return s;
		}

		lbl('Event Type:', y);
		var eventTypeList = _getEventTypeList();
		evtTypeDropdown = new CoolDropDown(6, y + 13, CoolDropDown.makeStrIdLabelArray(eventTypeList, true),
			function(id:String) { _onEventTypeSelected(id); });
		evtTypeDropdown.selectedLabel = eventTypeList.length > 0 ? eventTypeList[0] : 'Camera Follow';
		tab.add(evtTypeDropdown); y += 40;

		lbl('Value (v1|v2):', y);
		evtValueInput = new CoolInputText(6, y + 13, RIGHT_W - 20, '', 10);
		tab.add(evtValueInput); y += 38;

		lbl('Step Time:', y);
		evtStepStepper = new CoolNumericStepper(6, y + 13, 1, 0, 0, 9999, 0);
		tab.add(evtStepStepper);

		// Botón "At Playhead" — establece el step al tiempo actual
		var atPlayheadBtn = _makeTabBtn(RIGHT_W / 2 + 4, y + 12, '⏱ NOW', 0xFF223344, function()
		{
			var step = Conductor.songPosition / Conductor.stepCrochet;
			if (evtStepStepper != null) evtStepStepper.value = step;
			showStatus('Step → ${Std.int(step)} (${_fmtTime(Conductor.songPosition)})');
		});
		step_nowBtn = atPlayheadBtn;
		tab.add(atPlayheadBtn); tab.add(atPlayheadBtn.label);
		add(atPlayheadBtn); add(atPlayheadBtn.label);
		y += 36;

		lbl('Track (0-5):', y);
		evtTrackStepper = new CoolNumericStepper(6, y + 13, 1, 0, 0, TRACK_NAMES.length - 1, 0);
		tab.add(evtTrackStepper); y += 36;

		lbl('Label (opcional):', y);
		evtLabelInput = new CoolInputText(6, y + 13, RIGHT_W - 20, '', 10);
		tab.add(evtLabelInput); y += 36;

		// ── Tween Builder (visible solo cuando tipo = "Tween") ────────────────
		var tweenSep = sep(y); y += 6;
		var tweenHdr = lbl('Tween Builder:', y); y += 14;

		lbl('Target:', y);
		_tweenTargetInput = new CoolInputText(6, y + 13, Std.int(RIGHT_W - 20), 'camGame', 10);
		tab.add(_tweenTargetInput); y += 36;

		lbl('Property:', y);
		_tweenPropInput = new CoolInputText(6, y + 13, Std.int(RIGHT_W / 2 - 10), 'zoom', 10);
		tab.add(_tweenPropInput);
		lbl('Duration:', y);
		_tweenDurInput = new CoolInputText(Std.int(RIGHT_W / 2 + 2), y + 13, Std.int(RIGHT_W / 2 - 10), '1.0', 10);
		tab.add(_tweenDurInput); y += 36;

		lbl('From:', y);
		_tweenFromInput = new CoolInputText(6, y + 13, Std.int(RIGHT_W / 2 - 10), '', 10);
		tab.add(_tweenFromInput);
		lbl('To:', y);
		_tweenToInput = new CoolInputText(Std.int(RIGHT_W / 2 + 2), y + 13, Std.int(RIGHT_W / 2 - 10), '1.2', 10);
		tab.add(_tweenToInput); y += 36;

		lbl('Ease:', y);
		final easeNames = ['linear','quadIn','quadOut','quadInOut','cubeIn','cubeOut','cubeInOut',
		                   'elasticIn','elasticOut','bounceIn','bounceOut','sineIn','sineOut','sineInOut'];
		_tweenEaseDropdown = new CoolDropDown(6, y + 13, CoolDropDown.makeStrIdLabelArray(easeNames, true), null);
		_tweenEaseDropdown.selectedLabel = 'linear';
		tab.add(_tweenEaseDropdown); y += 40;

		// Botón que genera el value compuesto para el tween
		var buildTweenBtn = _makeTabBtn(6, y, '⚙ BUILD TWEEN VALUE', 0xFF1A2244, _buildTweenValue);
		tab.add(buildTweenBtn); tab.add(buildTweenBtn.label);
		add(buildTweenBtn); add(buildTweenBtn.label);
		y += 30;

		// Guardar refs a los elementos del tween builder para mostrar/ocultar
		_tweenBuilderGroup = [tweenSep, tweenHdr, _tweenTargetInput, _tweenPropInput,
		                      _tweenDurInput, _tweenFromInput, _tweenToInput, _tweenEaseDropdown,
		                      buildTweenBtn, buildTweenBtn.label];
		_setTweenBuilderVisible(false);

		sep(y); y += 8;
		lbl('Dificultades:', y); y += 14;

		evtDiffChecks = [];
		var dx = 6.0;
		// Usar las dificultades reales de la canción + opción 'all'
		final diffOptions = allDiffs.concat(['*']);
		for (diff in diffOptions)
		{
			var chk = new CoolCheckBox(dx, y, null, null, diff == '*' ? 'all' : diff, 60);
			chk.checked = (diff == '*');
			tab.add(chk); evtDiffChecks.push(chk);
			dx += 68; if (dx > RIGHT_W - 70) { dx = 6; y += 22; }
		}
		y += 28;

		sep(y); y += 6;

		// Botones añadir / eliminar — añadidos AL TAB (visibilidad controlada por CoolTabMenu)
		// y también al estado raíz para que se dibujen en camHUD.
		evtAddBtn    = _makeTabBtn(6,         y, 'ADD',    0xFF224422, _onAddEvent);
		evtDeleteBtn = _makeTabBtn(RIGHT_W/2, y, 'DELETE', 0xFF441122, _onDeleteEvent);
		tab.add(evtAddBtn); tab.add(evtAddBtn.label);
		tab.add(evtDeleteBtn); tab.add(evtDeleteBtn.label);
		add(evtAddBtn); add(evtAddBtn.label);
		add(evtDeleteBtn); add(evtDeleteBtn.label);
		y += 32;

		sep(y); y += 6;

		// Lista de eventos
		lbl('Events [' + currentDiff + ']:', y); y += 14;
		evtListTxt = new FlxText(6, y, RIGHT_W - 12, '', 9);
		evtListTxt.setFormat(Paths.font('vcr.ttf'), 9, C_TEXT, LEFT);
		evtListTxt.wordWrap = false;
		tab.add(evtListTxt);

		rightPanel.addGroup(tab);
		_refreshEventList();
	}

	function _makeTabBtn(x:Float, y:Float, label:String, color:Int, cb:Void->Void):MiniBtn2
	{
		var btn = new MiniBtn2(x, y, Std.int(RIGHT_W / 2 - 8), 24, label, color, C_TEXT, cb);
		btn.scrollFactor.set(); btn.cameras = [camHUD];
		btn.label.scrollFactor.set(); btn.label.cameras = [camHUD];
		return btn;
	}

	function _getEventTypeList():Array<String>
	{
		EventInfoSystem.reload();
		var list = EventInfoSystem.eventList.copy();
		if (list.length == 0)
			list = ['Camera Follow','Camera Focus','Camera Zoom','BPM Change','Play Animation','Hey!','Screen Shake','Camera Flash','Change Character'];
		return list;
	}

	function _refreshEventList():Void
	{
		if (evtListTxt == null) return;
		var filtered = (pseData.events ?? []).filter(e -> _isEventForDiff(e, currentDiff));
		filtered.sort((a,b) -> Std.int(a.stepTime - b.stepTime));

		var lines = [];
		var start = evtListScroll;
		var end   = Std.int(Math.min(start + 14, filtered.length));
		for (i in start...end)
		{
			var e    = filtered[i];
			var sel  = (e.id == selectedEventId) ? '►' : ' ';
			var bar  = Math.floor(e.stepTime / 16) + 1;
			var beat = Std.int(e.stepTime % 16);
			var val  = (e.value != null && e.value != '') ? ' = ${e.value}' : '';
			var lbl  = (e.label != null && e.label != '') ? ' [${e.label}]' : '';
			lines.push('$sel $bar:$beat  ${e.type}$val$lbl');
		}
		if (filtered.length == 0) lines.push('(no events for $currentDiff)');
		else if (filtered.length > 14) lines.push('... ${filtered.length - end} more (↑↓)');
		evtListTxt.text = lines.join('\n');
	}

	// ── Scripts Tab ───────────────────────────────────────────────────────────

	function _buildScriptsTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = 'Scripts';

		var y = 6.0;

		function lbl(t:String, ly:Float):FlxText
		{
			var tx = new FlxText(6, ly, 0, t, 10);
			tx.color = C_TIMELINE; tab.add(tx); return tx;
		}
		function sep(sy:Float):FlxSprite
		{
			var s = new FlxSprite(4, sy).makeGraphic(RIGHT_W - 16, 1, C_BORDER);
			s.alpha = 0.3; tab.add(s); return s;
		}

		lbl('Script Name:', y);
		scrNameInput = new CoolInputText(6, y + 13, RIGHT_W - 20, 'myScript', 10);
		tab.add(scrNameInput); y += 38;

		lbl('Trigger Step (-1 = manual):', y);
		scrStepStepper = new CoolNumericStepper(6, y + 13, 1, -1, -1, 9999, 0);
		tab.add(scrStepStepper); y += 36;

		scrAutoCheck    = new CoolCheckBox(6, y, null, null, 'Auto-trigger on step', RIGHT_W - 20);
		scrAutoCheck.checked = false; tab.add(scrAutoCheck); y += 22;
		scrEnabledCheck = new CoolCheckBox(6, y, null, null, 'Enabled', 80);
		scrEnabledCheck.checked = true; tab.add(scrEnabledCheck); y += 28;

		sep(y); y += 6;
		lbl('Dificultades:', y); y += 14;

		scrDiffChecks = [];
		var dx = 6.0;
		final diffOptions = allDiffs.concat(['*']);
		for (diff in diffOptions)
		{
			var chk = new CoolCheckBox(dx, y, null, null, diff == '*' ? 'all' : diff, 60);
			chk.checked = (diff == '*');
			tab.add(chk); scrDiffChecks.push(chk);
			dx += 68; if (dx > RIGHT_W - 70) { dx = 6; y += 22; }
		}
		y += 28;

		sep(y); y += 6;
		lbl('Script Code (HScript):', y); y += 14;

		scrCodeInput = new CoolInputText(6, y, RIGHT_W - 20, '// Your script here\n// Available: game, boyfriend, dad, gf, stage, camGame, camHUD\n\nfunction onBeatHit(beat) {\n\t// called on beat\n}', 9);
		scrCodeInput.lines = 14;
		tab.add(scrCodeInput); y += 145;

		sep(y); y += 6;

		// Botones
		scrAddBtn    = _makeTabBtn(6,           y, 'ADD / UPDATE', 0xFF224422, _onAddScript);
		scrDeleteBtn = _makeTabBtn(RIGHT_W/2,   y, 'DELETE',       0xFF441122, _onDeleteScript);
		tab.add(scrAddBtn); tab.add(scrAddBtn.label);
		tab.add(scrDeleteBtn); tab.add(scrDeleteBtn.label);
		add(scrAddBtn); add(scrAddBtn.label);
		add(scrDeleteBtn); add(scrDeleteBtn.label);
		y += 30;

		scrRunBtn = _makeTabBtn(6, y, '▶ TEST NOW', 0xFF223344, _onRunScript);
		tab.add(scrRunBtn); tab.add(scrRunBtn.label);
		add(scrRunBtn); add(scrRunBtn.label);
		y += 30;

		sep(y); y += 6;
		lbl('Scripts [' + currentDiff + ']:', y); y += 14;
		scrListTxt = new FlxText(6, y, RIGHT_W - 12, '', 9);
		scrListTxt.setFormat(Paths.font('vcr.ttf'), 9, C_TEXT, LEFT);
		tab.add(scrListTxt);
		y += 110;

		sep(y); y += 6;
		// Botón para abrir el ScriptEditorSubState completo
		var openScriptEditorBtn = _makeTabBtn(6, y, '📝 OPEN FULL EDITOR', 0xFF1A1A40, function()
		{
			var scriptName = selectedScriptId != '' ? _getSelectedScriptName() : (scrNameInput != null ? scrNameInput.text.trim() : 'new_script');
			openSubState(new ScriptEditorSubState(PlayState.SONG, scriptName, camHUD));
		});
		tab.add(openScriptEditorBtn); tab.add(openScriptEditorBtn.label);
		add(openScriptEditorBtn); add(openScriptEditorBtn.label);

		rightPanel.addGroup(tab);
		_refreshScriptList();
	}

	function _refreshScriptList():Void
	{
		if (scrListTxt == null) return;
		var filtered = (pseData.scripts ?? []).filter(s -> _isScriptForDiff(s, currentDiff));
		var lines = [];
		var start = scrListScroll;
		var end   = Std.int(Math.min(start + 8, filtered.length));
		for (i in start...end)
		{
			var s   = filtered[i];
			var sel = (s.id == selectedScriptId) ? '► ' : '  ';
			var en  = s.enabled ? '✓' : '✗';
			lines.push('$sel$en ${s.name} @${s.triggerStep < 0 ? "manual" : Std.string(Std.int(s.triggerStep))}');
		}
		if (filtered.length == 0) lines.push('(no scripts for $currentDiff)');
		scrListTxt.text = lines.join('\n');
	}

	// ── Song Tab ──────────────────────────────────────────────────────────────

	function _buildSongTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = 'Song';

		var SONG = PlayState.SONG;
		var y    = 8.0;

		function lbl(label:String, ly:Float):Void
		{
			var lTxt = new FlxText(6, ly, RIGHT_W - 12, label + ':', 9);
			lTxt.color = C_SUBTEXT; tab.add(lTxt);
		}
		function info(label:String, value:String, ly:Float):Void
		{
			lbl(label, ly);
			var vTxt = new FlxText(6, ly + 12, RIGHT_W - 12, value, 10);
			vTxt.color = C_TEXT; tab.add(vTxt);
		}
		function sep(sy:Float):FlxSprite
		{
			var s = new FlxSprite(4, sy).makeGraphic(RIGHT_W - 16, 1, C_BORDER);
			s.alpha = 0.3; tab.add(s); return s;
		}

		// ── Info básica ───────────────────────────────────────────────────────
		info('Song',    currentSong, y);      y += 28;
		info('Stage',   SONG.stage ?? '?', y); y += 28;

		sep(y); y += 8;

		// ── BPM live edit ─────────────────────────────────────────────────────
		lbl('BPM (live)', y); y += 13;
		var bpmStepper = new CoolNumericStepper(6, y, 1, SONG.bpm, 40, 400, 1);
		tab.add(bpmStepper); y += 28;
		var applyBpmBtn = new MiniBtn2(6, y, RIGHT_W - 20, 22, 'APPLY BPM', 0xFF1A2A3A, C_TEXT, function()
		{
			SONG.bpm = Std.int(bpmStepper.value);
			Conductor.changeBPM(SONG.bpm);
			hasUnsaved = true; _updateUnsavedDot();
			rebuildTimelineRuler();
			showStatus('BPM → ${SONG.bpm}');
		});
		applyBpmBtn.scrollFactor.set(); applyBpmBtn.cameras = [camHUD];
		applyBpmBtn.label.scrollFactor.set(); applyBpmBtn.label.cameras = [camHUD];
		tab.add(applyBpmBtn); add(applyBpmBtn); add(applyBpmBtn.label); y += 28;

		// ── Speed live edit ───────────────────────────────────────────────────
		lbl('Speed (scroll speed)', y); y += 13;
		var speedStepper = new CoolNumericStepper(6, y, 0.1, SONG.speed, 0.1, 10.0, 1);
		tab.add(speedStepper); y += 28;
		var applySpeedBtn = new MiniBtn2(6, y, RIGHT_W - 20, 22, 'APPLY SPEED', 0xFF1A2A3A, C_TEXT, function()
		{
			SONG.speed = speedStepper.value;
			hasUnsaved = true; _updateUnsavedDot();
			showStatus('Speed → ${SONG.speed}');
		});
		applySpeedBtn.scrollFactor.set(); applySpeedBtn.cameras = [camHUD];
		applySpeedBtn.label.scrollFactor.set(); applySpeedBtn.label.cameras = [camHUD];
		tab.add(applySpeedBtn); add(applySpeedBtn); add(applySpeedBtn.label); y += 28;

		sep(y); y += 8;

		// ── Note skin ─────────────────────────────────────────────────────────
		lbl('Note Skin (live)', y); y += 13;
		var skins = _getAvailableNoteSkins();
		noteSkinDropdown = new CoolDropDown(6, y, CoolDropDown.makeStrIdLabelArray(skins, true),
			function(id:String) {
				var i = Std.parseInt(id);
				if (i != null && i >= 0 && i < skins.length) _applyNoteSkin(skins[i]);
			});
		noteSkinDropdown.selectedLabel = (Reflect.hasField(SONG, 'noteSkin') ? Reflect.field(SONG, 'noteSkin') : null) ?? 'default';
		noteSkinDropdown.scrollFactor.set(); noteSkinDropdown.cameras = [camHUD];
		tab.add(noteSkinDropdown); y += 32;

		sep(y); y += 8;

		// ── Personajes ────────────────────────────────────────────────────────
		info('Player1', SONG.player1 ?? 'bf', y); y += 24;
		info('Player2', SONG.player2 ?? 'dad', y); y += 24;
		info('GF',      SONG.gfVersion ?? 'gf', y); y += 24;

		var charCount = SONG.characters != null ? SONG.characters.length : 0;
		info('Characters', '$charCount slots', y); y += 24;

		if (SONG.characters != null)
		{
			for (ch in SONG.characters)
			{
				var vLine = _perCharVocals && (vocalsMap.exists(ch.name) || vocalsMap.exists(_charVocalAlias(ch.name)));
				var icon  = vLine ? '🎤' : '🔇';
				var t = new FlxText(6, y, RIGHT_W - 12, '$icon ${ch.name} (${ch.type ?? "?"})', 9);
				t.color = vLine ? C_ACCENT : C_TEXT; tab.add(t); y += 14;
			}
		}

		sep(y); y += 8;

		// ── Drag personajes ────────────────────────────────────────────────────
		var toggleCharBtn = new MiniBtn2(6, y, RIGHT_W - 20, 22, '🎭 DRAG CHARS (C)', 0xFF1A2A1A, C_TEXT, function()
		{
			_showCharHandles = !_showCharHandles;
			showStatus(_showCharHandles ? '🎭 Char drag ON' : '🎭 Char drag OFF', 2.0);
		});
		toggleCharBtn.scrollFactor.set(); toggleCharBtn.cameras = [camHUD];
		toggleCharBtn.label.scrollFactor.set(); toggleCharBtn.label.cameras = [camHUD];
		tab.add(toggleCharBtn); add(toggleCharBtn); add(toggleCharBtn.label); y += 28;

		sep(y); y += 8;

		// ── Botones de acción ─────────────────────────────────────────────────
		var saveInfoBtn = new MiniBtn2(6, y, RIGHT_W - 20, 24, 'SAVE PSE DATA (F5)', 0xFF224422, C_TEXT, savePSEData);
		saveInfoBtn.scrollFactor.set(); saveInfoBtn.cameras = [camHUD];
		saveInfoBtn.label.scrollFactor.set(); saveInfoBtn.label.cameras = [camHUD];
		tab.add(saveInfoBtn); add(saveInfoBtn); add(saveInfoBtn.label);
		y += 30;

		var importSecBtn = new MiniBtn2(6, y, RIGHT_W - 20, 24, 'IMPORT CAM SECTIONS', 0xFF1A2244, C_TEXT, function()
		{
			_importSectionCameraEvents();
			showStatus('✓ Secciones mustHitSection importadas como eventos');
			rebuildTimelineEventSprites();
		});
		importSecBtn.scrollFactor.set(); importSecBtn.cameras = [camHUD];
		importSecBtn.label.scrollFactor.set(); importSecBtn.label.cameras = [camHUD];
		tab.add(importSecBtn); add(importSecBtn); add(importSecBtn.label);

		rightPanel.addGroup(tab);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Update
	// ─────────────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Seek diferido
		if (autoSeekTime >= 0)
		{
			_doSeek(autoSeekTime);
			autoSeekTime = -1;
		}

		// Sincronizar conductor con audio — sincronización directa con el tiempo del audio
		if (isPlaying && FlxG.sound.music != null && FlxG.sound.music.playing)
		{
			var musicTime = FlxG.sound.music.time;

			// Suavizar: si el audio retrocede ligeramente por jitter del backend, avanzar por elapsed
			if (musicTime < Conductor.songPosition - 100 && musicTime > 0)
				Conductor.songPosition += FlxG.elapsed * 1000.0;
			else
				Conductor.songPosition = musicTime;

			// Beat / Step hits
			var curBeat = Math.floor(Conductor.songPosition / Conductor.crochet);
			var curStep = Math.floor(Conductor.songPosition / Conductor.stepCrochet);

			if (curStep != _lastStep)
			{
				_lastStep = curStep;
				_onStepHit(curStep);
			}
			if (curBeat != _lastBeat)
			{
				_lastBeat = curBeat;
				_onBeatHit(curBeat);
			}

			// Disparar eventos del editor
			_fireEditorEvents();
		}

		// Controllers
		if (cameraController != null)
			cameraController.update(elapsed);
		if (characterController != null)
			characterController.update(elapsed);

		// Timeline
		_updateTimelinePlayhead();
		if (FlxG.mouse.justReleased) rebuildTimelineRuler();

		// Seek por click en la timeline
		if (timelineVisible) _handleTimelineInput();

		// ── Viewport flotante ─────────────────────────────────────────────────
		_handleGameViewport();

		// ── Arrastre de personajes ────────────────────────────────────────────
		_handleCharDrag();
		_updateCharHandles();

		// Clicks en event sprites
		_handleEventSpriteClicks();

		// Tiempo
		_updateTimeTxt();

		// Status timeout
		if (_statusTimer > 0)
		{
			_statusTimer -= elapsed;
			if (_statusTimer <= 0) statusTxt.text = '';
		}

		// Botones top bar
		for (btn in [playBtn, stopBtn, restartBtn, saveBtn, toggleTLBtn, togglePanelBtn, layoutPresetBtn])
			if (btn != null) btn.updateInput();

		// Botones del transport (timeline)
		for (btn in tlTransBtns)
			if (btn != null) btn.updateInput();

		// Teclado
		_handleKeys();
	}

	function _onBeatHit(beat:Int):Void
	{
		if (characterController != null)
			characterController.danceOnBeat(beat);
		if (uiManager != null)
			uiManager.onBeatHit(beat);
		if (currentStage != null)
			currentStage.beatHit(beat);

		// Llamar a scripts del editor que estén activos
		for (key in scriptInstances.keys())
		{
			var inst = scriptInstances.get(key);
			if (inst != null && inst.active)
				inst.call('onBeatHit', [beat]);
		}
	}

	function _onStepHit(step:Int):Void
	{
		if (uiManager != null)
			uiManager.onStepHit(step);
		for (key in scriptInstances.keys())
		{
			var inst = scriptInstances.get(key);
			if (inst != null && inst.active)
				inst.call('onStepHit', [step]);
		}
	}

	function _fireEditorEvents():Void
	{
		var posMs = Conductor.songPosition;

		// Eventos del editor
		while (_nextEventIdx < sortedEvents.length)
		{
			var evt = sortedEvents[_nextEventIdx];
			if (!_isEventForDiff(evt, currentDiff)) { _nextEventIdx++; continue; }
			var evtMs = Conductor.stepCrochet * evt.stepTime;
			if (evtMs > posMs) break;

			// Disparar evento via EventManager
			_triggerEvent(evt);
			_nextEventIdx++;
		}

		// Scripts auto-trigger
		while (_nextScriptIdx < sortedScripts.length)
		{
			var scr = sortedScripts[_nextScriptIdx];
			if (!scr.enabled || !scr.autoTrigger || !_isScriptForDiff(scr, currentDiff))
			{
				_nextScriptIdx++; continue;
			}
			if (scr.triggerStep < 0) { _nextScriptIdx++; continue; }
			var scrMs = Conductor.stepCrochet * scr.triggerStep;
			if (scrMs > posMs) break;

			_executeScript(scr);
			_nextScriptIdx++;
		}
	}

	function _triggerEvent(evt:PSEEvent):Void
	{
		// Usar EventManager para disparar si el tipo existe
		var v1 = evt.value ?? '';
		var v2 = '';
		if (v1.contains('|'))
		{
			var parts = v1.split('|');
			v1 = parts[0].trim();
			v2 = parts.length > 1 ? parts[1].trim() : '';
		}

		// Intentar usar el sistema de eventos nativo
		EventManager.fireEvent(evt.type, v1, v2);

		// Flash en el sprite de la timeline si existe
		for (s in tlEventSprites)
		{
			if (s.eventId == evt.id)
			{
				FlxTween.cancelTweensOf(s);
				s.alpha = 1.0;
				FlxTween.tween(s, {alpha: 0.5}, 0.3, {ease: FlxEase.quadOut, onComplete:_ -> s.alpha = 0.8});
				break;
			}
		}

		showStatus('▶ Event: ${evt.type} — ${evt.value}', 2.0);
	}

	function _executeScript(scr:PSEScript):Void
	{
		#if HSCRIPT_ALLOWED
		var inst = scriptInstances.get(scr.id);
		if (inst == null || !inst.active)
		{
			inst = new HScriptInstance(scr.name, scr.id);
			inst.priority = 0;
			_exposeScriptVars(inst);
			inst.loadString(scr.code);
			scriptInstances.set(scr.id, inst);
		}
		inst.call('onTrigger', [Conductor.songPosition]);
		showStatus('▶ Script: ${scr.name}', 2.0);
		#else
		showStatus('⚠ HScript no disponible en esta build');
		#end
	}

	function _exposeScriptVars(inst:HScriptInstance):Void
	{
		#if HSCRIPT_ALLOWED
		inst.set('game',       this);
		inst.set('playStateEditor', this);
		inst.set('boyfriend',  boyfriend);
		inst.set('dad',        dad);
		inst.set('gf',         gf);
		inst.set('stage',      currentStage);
		inst.set('camGame',    camGame);
		inst.set('camHUD',     camHUD);
		inst.set('gameState',  gameState);
		inst.set('FlxG',       FlxG);
		inst.set('FlxTween',   FlxTween);
		inst.set('FlxTimer',   FlxTimer);
		inst.set('FlxColor',   {
			RED:         (FlxColor.RED         : Int),
			GREEN:       (FlxColor.GREEN       : Int),
			BLUE:        (FlxColor.BLUE        : Int),
			WHITE:       (FlxColor.WHITE       : Int),
			BLACK:       (FlxColor.BLACK       : Int),
			TRANSPARENT: (FlxColor.TRANSPARENT : Int),
			YELLOW:      (FlxColor.YELLOW      : Int),
			CYAN:        (FlxColor.CYAN        : Int),
			MAGENTA:     (FlxColor.MAGENTA     : Int),
			ORANGE:      (FlxColor.ORANGE      : Int),
			PINK:        (FlxColor.PINK        : Int),
			PURPLE:      (FlxColor.PURPLE      : Int),
			GRAY:        (FlxColor.GRAY        : Int),
			fromRGB:     FlxColor.fromRGB,
			fromHSB:     FlxColor.fromHSB,
			fromString:  FlxColor.fromString
		});
		inst.set('conductor',  Conductor);
		inst.set('Paths',      Paths);
		inst.set('trace',      function(v:Dynamic) trace('[PSEScript] $v'));
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Input handlers
	// ─────────────────────────────────────────────────────────────────────────

	function _handleKeys():Void
	{
		if (FlxG.keys.justPressed.SPACE)  _onPlayPause();
		if (FlxG.keys.justPressed.R)      _onRestart();
		if (FlxG.keys.justPressed.T)      _toggleTimeline();
		if (FlxG.keys.justPressed.H)      _toggleRightPanel();
		if (FlxG.keys.justPressed.F5)     savePSEData();
		if (FlxG.keys.justPressed.ESCAPE) _goBack();
		// C = toggle drag handles de personajes
		if (FlxG.keys.justPressed.C && !_anyInputFocused())
		{
			_showCharHandles = !_showCharHandles;
			showStatus(_showCharHandles ? '🎭 Char drag ON (arrastra los puntos amarillos)' : '🎭 Char drag OFF', 2.0);
		}
		// G = toggle viewport flotante
		if (FlxG.keys.justPressed.G && !_anyInputFocused())
			_toggleFloatingViewport();

		// Navegar lista de eventos con flechas cuando el foco no está en input
		if (!_anyInputFocused())
		{
			if (FlxG.keys.justPressed.UP)
			{
				if (evtListScroll > 0) evtListScroll--;
				_refreshEventList();
			}
			if (FlxG.keys.justPressed.DOWN)
			{
				evtListScroll++;
				_refreshEventList();
			}
		}
	}

	function _anyInputFocused():Bool
	{
		for (input in [evtValueInput, evtLabelInput, scrNameInput, scrCodeInput])
			if (input != null && input.hasFocus) return true;
		return false;
	}

	function _handleTimelineInput():Void
	{
		if (tlBg == null) return;

		var tlY      = _tlY();
		var trackN   = TRACK_NAMES.length;
		var tracksH  = trackN * TL_TRACK_H2;
		var hsY      = tlY + TL_RULER_H + tracksH;             // scrollbar Y
		var scrubY   = hsY + TL_HSCROLL_H_REAL;               // scrubber Y
		var transY   = scrubY + TL_SCRUB_H;
		var mx       = FlxG.mouse.x;
		var my       = FlxG.mouse.y;
		var areaW    = _tlAreaW();

		// ── Horizontal scrollbar drag ─────────────────────────────────────────
		var inHScroll = my >= hsY && my <= hsY + TL_HSCROLL_H_REAL && mx >= TL_LABEL_W && mx <= TL_LABEL_W + areaW;
		if (FlxG.mouse.justPressed && inHScroll)
		{
			_tlHScrollDrag = true;
			_tlHScrollDragOff = mx;
		}
		if (FlxG.mouse.justReleased) _tlHScrollDrag = false;

		if (_tlHScrollDrag && songLength > 0)
		{
			var visibleMs   = areaW / tlZoom;
			var maxScroll   = Math.max(0, songLength - visibleMs);
			var ratio       = (mx - TL_LABEL_W) / areaW;
			tlScrollX       = FlxMath.bound(ratio * songLength, 0, maxScroll);
			rebuildTimelineRuler();
			rebuildTimelineEventSprites();
		}

		// ── Scrubber: click o drag para seek rápido ───────────────────────────
		var inScrub = my >= scrubY && my <= scrubY + TL_SCRUB_H && mx >= 0 && mx <= SW;
		if (FlxG.mouse.justPressed && inScrub)   _scrubDragging = true;
		if (FlxG.mouse.justReleased)              _scrubDragging = false;

		if (_scrubDragging && songLength > 0)
		{
			var ratio = Math.max(0, Math.min(1, mx / SW));
			autoSeekTime = ratio * songLength;
		}

		// ── Click en el ruler (bar:beat) → seek preciso ───────────────────────
		if (FlxG.mouse.justPressed
			&& mx >= TL_LABEL_W && mx <= TL_LABEL_W + areaW
			&& my >= tlY && my <= tlY + TL_RULER_H)
		{
			var clickMs = (mx - TL_LABEL_W) / tlZoom + tlScrollX;
			autoSeekTime = Math.max(0, clickMs);
		}

		// ── Drag playhead en el ruler ─────────────────────────────────────────
		if (FlxG.mouse.pressed
			&& mx >= TL_LABEL_W && mx <= TL_LABEL_W + areaW
			&& my >= tlY && my <= tlY + TL_RULER_H)
		{
			var dragMs = (mx - TL_LABEL_W) / tlZoom + tlScrollX;
			autoSeekTime = Math.max(0, dragMs);
		}

		// ── Scroll horizontal (rueda del ratón en el track area) ──────────────
		if (my >= tlY && my <= transY)
		{
			var wheel = FlxG.mouse.wheel;
			if (wheel != 0)
			{
				if (FlxG.keys.pressed.CONTROL)
				{
					tlZoom = Math.max(0.005, Math.min(2.0, tlZoom * (wheel > 0 ? 1.25 : 0.8)));
				}
				else
				{
					tlScrollX -= wheel * Conductor.crochet * 2;
					if (tlScrollX < 0) tlScrollX = 0;
				}
				rebuildTimelineRuler();
				rebuildTimelineEventSprites();
			}
		}

		// ── Rueda en el área de juego = zoom de camGame ────────────────────────
		var gameAreaBottom = _tlY();
		if (!FlxG.keys.pressed.CONTROL
			&& my >= TOP_H && my < gameAreaBottom
			&& mx >= 0    && mx < SW - (rightPanelVisible ? RIGHT_W : 0)
			&& !_vpDragging && !_vpResizing)
		{
			var wheel = FlxG.mouse.wheel;
			if (wheel != 0)
			{
				_gameZoom = FlxMath.bound(_gameZoom * (wheel > 0 ? 1.15 : 0.87), 0.2, 3.0);
				if (camGame != null) camGame.zoom = _gameZoom;
				showStatus('Zoom: ${Math.round(_gameZoom * 100)}%', 0.8);
			}
		}
	}

	function _handleEventSpriteClicks():Void
	{
		// ── Scroll de la lista de eventos con la rueda cuando el ratón está sobre el panel ──
		if (rightPanelVisible && FlxG.mouse.wheel != 0)
		{
			var panelX = SW - RIGHT_W;
			if (FlxG.mouse.x >= panelX && FlxG.mouse.x <= SW)
			{
				var filtered = (pseData.events ?? []).filter(e -> _isEventForDiff(e, currentDiff));
				evtListScroll = Std.int(FlxMath.bound(evtListScroll - FlxG.mouse.wheel, 0, Math.max(0, filtered.length - 14)));
				_refreshEventList();
			}
		}

		if (!FlxG.mouse.justPressed) return;
		for (s in tlEventSprites)
		{
			if (FlxG.mouse.overlaps(s, camHUD))
			{
				selectedEventId = s.eventId;
				_loadEventToPanel(selectedEventId);
				_refreshEventList();
				rebuildTimelineEventSprites();
				return;
			}
		}
	}

	function _loadEventToPanel(id:String):Void
	{
		for (evt in (pseData.events ?? []))
		{
			if (evt.id != id) continue;
			if (evtTypeDropdown  != null) evtTypeDropdown.selectedLabel  = evt.type;
			if (evtValueInput    != null) evtValueInput.text             = evt.value ?? '';
			if (evtStepStepper   != null) evtStepStepper.value           = evt.stepTime;
			if (evtTrackStepper  != null) evtTrackStepper.value          = evt.trackIndex;
			if (evtLabelInput    != null) evtLabelInput.text             = evt.label ?? '';
			_setDiffChecks(evtDiffChecks, evt.difficulties);
			return;
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Transport callbacks
	// ─────────────────────────────────────────────────────────────────────────

	function _onPlayPause():Void
	{
		isPlaying = !isPlaying;
		syncAudio(isPlaying);
		if (isPlaying)
		{
			playBtn.label.text = '⏸';
			showStatus('▶ Reproduciendo');
		}
		else
		{
			playBtn.label.text = '▶';
			showStatus('⏸ Pausado');
		}
	}

	function _onStop():Void
	{
		isPlaying = false;
		syncAudio(false);
		_doSeek(0);
		playBtn.label.text = '▶';
		showStatus('⏹ Detenido');
	}

	function _onRestart():Void
	{
		_doSeek(0);

		// Reset camera to initial state (undoes Camera Follow/Zoom events that
		// fired during playback — the snapshot was taken after stage setup).
		if (cameraController != null)
			cameraController.resetToInitial();

		// Return characters to idle (undoes any mid-song anim changes).
		if (characterController != null)
			characterController.forceIdleAll();

		isPlaying = true;
		syncAudio(true);
		playBtn.label.text = '⏸';
		showStatus('⏮ Reiniciando');
	}

	function _onDiffChanged(id:String):Void
	{
		currentDiff = id;
		_refreshEventList();
		_refreshScriptList();
		rebuildTimelineEventSprites();
		showStatus('Dificultad: $currentDiff');
	}

	function _doSeek(ms:Float):Void
	{
		Conductor.songPosition = ms;
		if (FlxG.sound.music != null) FlxG.sound.music.time = ms;
		_syncVocals(ms);
		_lastBeat  = -1;
		_lastStep  = -1;
		_nextEventIdx  = 0;
		_nextScriptIdx = 0;
		// Avanzar punteros hasta el tiempo actual
		while (_nextEventIdx < sortedEvents.length
			&& Conductor.stepCrochet * sortedEvents[_nextEventIdx].stepTime < ms)
			_nextEventIdx++;
		while (_nextScriptIdx < sortedScripts.length
			&& sortedScripts[_nextScriptIdx].triggerStep >= 0
			&& Conductor.stepCrochet * sortedScripts[_nextScriptIdx].triggerStep < ms)
			_nextScriptIdx++;
	}

	function syncAudio(play:Bool):Void
	{
		if (FlxG.sound.music == null) return;
		if (play) { FlxG.sound.music.volume = 1; FlxG.sound.music.play(); }
		else      { FlxG.sound.music.pause(); }
		_syncVocals(FlxG.sound.music.time, play);
	}

	function _syncVocals(time:Float, play:Bool = false):Void
	{
		// ── Nuevo sistema: vocalsMap por personaje ────────────────────────────
		for (snd in vocalsMap)
		{
			if (snd == null) continue;
			snd.time = time;
			if (play) snd.play(); else snd.pause();
		}

		// ── Legacy: vocalsBf / vocalsDad ─────────────────────────────────────
		if (_perCharVocals && Lambda.count(vocalsMap) == 0)
		{
			if (vocalsBf  != null) { vocalsBf.time  = time; if (play) vocalsBf.play();  else vocalsBf.pause(); }
			if (vocalsDad != null) { vocalsDad.time = time; if (play) vocalsDad.play(); else vocalsDad.pause(); }
		}
		else if (vocals != null)
		{
			vocals.time = time;
			if (play) vocals.play(); else vocals.pause();
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Event CRUD
	// ─────────────────────────────────────────────────────────────────────────

	function _onAddEvent():Void
	{
		if (evtTypeDropdown == null) return;

		var type  = evtTypeDropdown.selectedLabel ?? 'Camera Follow';
		var value = evtValueInput  != null ? evtValueInput.text  : '';
		var step  = evtStepStepper != null ? evtStepStepper.value : 0.0;
		var track = evtTrackStepper != null ? Std.int(evtTrackStepper.value) : 0;
		var label = evtLabelInput  != null ? evtLabelInput.text  : '';
		var diffs = _getDiffChecks(evtDiffChecks);

		// Si hay uno seleccionado, actualizar en lugar de añadir
		if (selectedEventId != '')
		{
			for (evt in (pseData.events ?? []))
			{
				if (evt.id == selectedEventId)
				{
					evt.type        = type;
					evt.value       = value;
					evt.stepTime    = step;
					evt.trackIndex  = track;
					evt.label       = label;
					evt.difficulties = diffs;
					hasUnsaved      = true;
					_updateUnsavedDot();
					_rebuildSorted();
					_refreshEventList();
					showStatus('✓ Evento actualizado: $type');
					return;
				}
			}
		}

		// Nuevo evento
		var evt:PSEEvent = {
			id:           _uid(),
			stepTime:     step,
			type:         type,
			value:        value,
			difficulties: diffs,
			trackIndex:   track,
			label:        label
		};

		if (pseData.events == null) pseData.events = [];
		pseData.events.push(evt);
		hasUnsaved = true;
		_updateUnsavedDot();
		_rebuildSorted();
		_refreshEventList();
		showStatus('✓ Evento añadido: $type @ step ${Std.int(step)}');
	}

	function _onDeleteEvent():Void
	{
		if (selectedEventId == '' || pseData.events == null) return;
		pseData.events = pseData.events.filter(e -> e.id != selectedEventId);
		selectedEventId = '';
		hasUnsaved = true;
		_updateUnsavedDot();
		_rebuildSorted();
		_refreshEventList();
		showStatus('✓ Evento eliminado');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Script CRUD
	// ─────────────────────────────────────────────────────────────────────────

	function _onAddScript():Void
	{
		if (scrNameInput == null) return;

		var name    = scrNameInput.text.trim();
		if (name == '') name = 'script_' + _uid();
		var code    = scrCodeInput    != null ? scrCodeInput.text    : '';
		var step    = scrStepStepper  != null ? scrStepStepper.value : -1.0;
		var autoT   = scrAutoCheck    != null ? scrAutoCheck.checked : false;
		var enabled = scrEnabledCheck != null ? scrEnabledCheck.checked : true;
		var diffs   = _getDiffChecks(scrDiffChecks);

		// Actualizar si existe
		if (selectedScriptId != '')
		{
			for (scr in (pseData.scripts ?? []))
			{
				if (scr.id == selectedScriptId)
				{
					scr.name        = name;
					scr.code        = code;
					scr.triggerStep = step;
					scr.autoTrigger = autoT;
					scr.enabled     = enabled;
					scr.difficulties = diffs;
					// Invalidar instancia vieja
					var old = scriptInstances.get(scr.id);
					if (old != null) { old.active = false; scriptInstances.remove(scr.id); }
					hasUnsaved = true;
					_updateUnsavedDot();
					_rebuildSorted();
					_refreshScriptList();
					showStatus('✓ Script actualizado: $name');
					return;
				}
			}
		}

		var scr:PSEScript = {
			id:           _uid(),
			name:         name,
			code:         code,
			triggerStep:  step,
			difficulties: diffs,
			enabled:      enabled,
			autoTrigger:  autoT
		};

		if (pseData.scripts == null) pseData.scripts = [];
		pseData.scripts.push(scr);
		hasUnsaved = true;
		_updateUnsavedDot();
		_rebuildSorted();
		_refreshScriptList();
		showStatus('✓ Script añadido: $name');
	}

	function _onDeleteScript():Void
	{
		if (selectedScriptId == '' || pseData.scripts == null) return;
		var old = scriptInstances.get(selectedScriptId);
		if (old != null) { old.active = false; scriptInstances.remove(selectedScriptId); }
		pseData.scripts = pseData.scripts.filter(s -> s.id != selectedScriptId);
		selectedScriptId = '';
		hasUnsaved = true;
		_updateUnsavedDot();
		_rebuildSorted();
		_refreshScriptList();
		showStatus('✓ Script eliminado');
	}

	function _onRunScript():Void
	{
		#if HSCRIPT_ALLOWED
		if (scrCodeInput == null) return;
		var code = scrCodeInput.text;
		var name = scrNameInput != null ? scrNameInput.text.trim() : 'testScript';
		if (name == '') name = 'testScript';

		// Destruir instancia anterior si existe
		var old = scriptInstances.get('__test__');
		if (old != null) { old.active = false; scriptInstances.remove('__test__'); }

		var inst = new HScriptInstance(name, '__test__');
		_exposeScriptVars(inst);
		inst.loadString(code);
		inst.call('onCreate', []);
		inst.call('onTrigger', [Conductor.songPosition]);
		scriptInstances.set('__test__', inst);
		showStatus('▶ Script ejecutado: $name');
		#else
		showStatus('⚠ HScript no disponible');
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Layout helpers
	// ─────────────────────────────────────────────────────────────────────────

	function _toggleTimeline():Void
	{
		timelineVisible = !timelineVisible;

		// Ocultar / mostrar todos los miembros del grupo de la timeline
		if (timelineGroup != null)
			timelineGroup.forEach(m -> if (m != null) m.visible = timelineVisible);

		// Sprites de eventos
		for (s in tlEventSprites)
		{
			s.visible = timelineVisible;
			if (s.labelTxt != null) s.labelTxt.visible = timelineVisible;
		}

		// Textos del ruler
		if (rulerTxt != null)
			for (t in rulerTxt.members)
				t.visible = timelineVisible && t.text != '';

		// Beat grid lines
		for (gl in tlBeatGridLines) gl.visible = timelineVisible && gl.visible;

		// Botones del transport
		for (btn in tlTransBtns)
		{
			if (btn == null) continue;
			btn.visible = timelineVisible;
			if (btn.label != null) btn.label.visible = timelineVisible;
		}

		// Labels del ruler + time
		if (tlTimeLbl    != null) tlTimeLbl.visible    = timelineVisible;
		if (tlTimeRemLbl != null) tlTimeRemLbl.visible = timelineVisible;
		if (tlBpmLbl     != null) tlBpmLbl.visible     = timelineVisible;

		// Redimensionar panel derecho
		_repositionRightPanel();
		showStatus(timelineVisible ? 'Timeline visible (T para ocultar)' : 'Timeline oculta (T para mostrar)');
	}

	function _toggleRightPanel():Void
	{
		rightPanelVisible = !rightPanelVisible;
		if (rightPanel != null) rightPanel.visible = rightPanelVisible;
		if (panelBg    != null) panelBg.visible    = rightPanelVisible;
		showStatus(rightPanelVisible ? 'Panel visible' : 'Panel oculto');
	}

	function _repositionRightPanel():Void
	{
		if (rightPanel == null || panelBg == null) return;
		var panelH = SH - TOP_H - STATUS_H - (timelineVisible ? TL_H : 0);
		rightPanel.resize(RIGHT_W - 2, panelH);
		panelBg.makeGraphic(RIGHT_W, panelH, C_PANEL);
	}

	/** Y absoluta donde empieza la timeline */
	inline function _tlY():Int
		return TOP_H + _gameH();

	/** Altura disponible del área de juego (entre topbar y timeline) */
	inline function _gameH():Int
		return SH - TOP_H - STATUS_H - (timelineVisible ? TL_H : 0);

	/** Ancho del área de eventos en la timeline */
	inline function _tlAreaW():Int
		return SW - TL_LABEL_W - (rightPanelVisible ? RIGHT_W : 0);









	// ─────────────────────────────────────────────────────────────────────────
	//  Misc UI helpers
	// ─────────────────────────────────────────────────────────────────────────

	function _updateTimeTxt():Void
	{
		if (timeTxt == null) return;
		var pos = Conductor.songPosition;
		var len = songLength;
		timeTxt.text = '${_fmtTime(pos)} / ${_fmtTime(len)}';
	}

	function _fmtTime(ms:Float):String
	{
		var secs   = Math.floor(ms / 1000);
		var mins   = Math.floor(secs / 60);
		var secStr = Std.string(secs % 60);
		if (secStr.length < 2) secStr = '0' + secStr;
		return '$mins:$secStr';
	}

	function showStatus(msg:String, duration:Float = 3.0):Void
	{
		_statusMsg   = msg;
		_statusTimer = duration;
		if (statusTxt != null) statusTxt.text = msg;
	}

	function _updateUnsavedDot():Void
	{
		if (unsavedDot != null) unsavedDot.visible = hasUnsaved;
	}

	function _getDiffChecks(checks:Array<CoolCheckBox>):Array<String>
	{
		final diffOptions = allDiffs.concat(['*']); // mismo orden que los checkboxes
		var diffs:Array<String> = [];
		for (i in 0...checks.length)
		{
			if (i < diffOptions.length && checks[i] != null && checks[i].checked)
			{
				if (diffOptions[i] == '*') return ['*'];
				diffs.push(diffOptions[i]);
			}
		}
		return diffs.length > 0 ? diffs : ['*'];
	}

	function _setDiffChecks(checks:Array<CoolCheckBox>, diffs:Array<String>):Void
	{
		final diffOptions = allDiffs.concat(['*']);
		final isAll = diffs.contains('*');
		for (i in 0...checks.length)
		{
			if (checks[i] == null || i >= diffOptions.length) continue;
			checks[i].checked = isAll ? (diffOptions[i] == '*') : diffs.contains(diffOptions[i]);
		}
	}

	function _getSelectedScriptName():String
	{
		for (scr in (pseData.scripts ?? []))
			if (scr.id == selectedScriptId) return scr.name;
		return 'new_script';
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Import mustHitSection sections as Camera Follow events
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Lee las secciones de PlayState.SONG y genera eventos "Camera Follow" en el
	 * track 0 (Camera) cada vez que mustHitSection cambia, para que las secciones
	 * ya colocadas sean visibles en la tabla de eventos del editor.
	 * Solo añade los eventos que aún no existen (compara stepTime y tipo).
	 */
	function _importSectionCameraEvents():Void
	{
		var SONG = PlayState.SONG;
		if (SONG == null || SONG.notes == null || SONG.notes.length == 0) return;

		var stepAccum  : Float = 0;
		var prevMustHit: Bool  = true; // primer valor por defecto = cámara en BF

		for (i in 0...SONG.notes.length)
		{
			var section = SONG.notes[i];
			final mustHit = section.mustHitSection ?? true;

			// Insertar evento si es la primera sección o si cambia respecto a la anterior
			if (i == 0 || mustHit != prevMustHit)
			{
				final target = mustHit ? 'bf' : 'dad';
				var exists   = false;
				for (evt in (pseData.events ?? []))
				{
					if (evt.type == 'Camera Follow' && Math.abs(evt.stepTime - stepAccum) < 0.5)
					{
						exists = true;
						break;
					}
				}

				if (!exists)
				{
					var evt : PSEEvent = {
						id          : _uid(),
						stepTime    : stepAccum,
						type        : 'Camera Follow',
						value       : target,
						difficulties: ['*'],
						trackIndex  : 0,
						label       : 'Cam→$target'
					};
					if (pseData.events == null) pseData.events = [];
					pseData.events.push(evt);
				}
				prevMustHit = mustHit;
			}

			stepAccum += (section.lengthInSteps ?? 16);
		}

		_rebuildSorted();
		_refreshEventList();
	}

	function _isEventForDiff(evt:PSEEvent, diff:String):Bool
	{
		if (evt.difficulties == null || evt.difficulties.length == 0) return true;
		return evt.difficulties.contains('*') || evt.difficulties.contains(diff);
	}

	function _isScriptForDiff(scr:PSEScript, diff:String):Bool
	{
		if (scr.difficulties == null || scr.difficulties.length == 0) return true;
		return scr.difficulties.contains('*') || scr.difficulties.contains(diff);
	}

	function _uid():String
	{
		return 'pse_' + Std.string(Std.int(haxe.Timer.stamp() * 1000)) + '_' + (++_uidCounter);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Navigation
	// ─────────────────────────────────────────────────────────────────────────

	// ─────────────────────────────────────────────────────────────────────────
	//  Layout presets  (⊞ button — cicla entre modos de vista)
	// ─────────────────────────────────────────────────────────────────────────

	// ─────────────────────────────────────────────────────────────────────────
	//  Floating Game Viewport  (tipo ZGameVisualizer de FL Studio)
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Calcula el tamaño inicial del viewport flotante basándose en el espacio
	 * disponible entre topbar y timeline.
	 */
	function _initGameViewport():Void
	{
		_vpW = SW - (rightPanelVisible ? RIGHT_W : 0);
		_vpH = _gameH();
		_vpX = 0;
		_vpY = TOP_H;
		// Aplicar al camGame directamente (coordenadas de pantalla OpenFL)
		_applyViewportToCam();

		// Marco visual (se crea cuando se entra en modo flotante)
	}

	function _applyViewportToCam():Void
	{
		if (camGame == null) return;
		if (_vpFloating)
		{
			// Modo flotante: la cámara ocupa solo el rectángulo _vp*
			camGame.x      = Std.int(_vpX);
			camGame.y      = Std.int(_vpY);
			camGame.width  = _vpW;
			camGame.height = _vpH;
			// El scroll del camGame sigue centrado en el mundo (no offset)
		}
		else
		{
			// Modo normal: ocupa todo el área de juego
			camGame.x      = 0;
			camGame.y      = 0;
			camGame.width  = SW - (rightPanelVisible ? RIGHT_W : 0);
			camGame.height = _gameH();
		}
	}

	function _toggleFloatingViewport():Void
	{
		_vpFloating = !_vpFloating;

		if (_vpFloating)
		{
			// Tamaño y posición inicial de la ventana flotante
			_vpW = Std.int((SW - (rightPanelVisible ? RIGHT_W : 0)) * 0.65);
			_vpH = Std.int(_gameH() * 0.65);
			_vpX = (SW - (rightPanelVisible ? RIGHT_W : 0) - _vpW) / 2;
			_vpY = TOP_H + (_gameH() - _vpH) / 2;
			_buildFloatingWindowUI();
			showStatus('🎮 Viewport flotante activado — arrastra el título, esquina SE para redimensionar', 4.0);
		}
		else
		{
			// Destruir el marco
			_destroyFloatingWindowUI();
			showStatus('🎮 Viewport normal', 1.5);
		}
		_applyViewportToCam();
		if (_vpFloatBtn != null)
		{
			_vpFloatBtn.makeGraphic(34, 29, _vpFloating ? 0xFF1A4A1A : 0xFF1A2A1A);
		}
	}

	function _buildFloatingWindowUI():Void
	{
		_destroyFloatingWindowUI();

		// Borde del viewport flotante
		_vpBorder = new FlxSprite(_vpX - 2, _vpY - 20).makeGraphic(_vpW + 4, _vpH + 22, 0x00000000, true);
		flixel.util.FlxSpriteUtil.drawRect(_vpBorder, 0, 0, _vpW + 4, _vpH + 22, 0x00000000);
		flixel.util.FlxSpriteUtil.drawRect(_vpBorder, 0, 0, _vpW + 4, 2, C_ACCENT);
		flixel.util.FlxSpriteUtil.drawRect(_vpBorder, 0, _vpH + 20, _vpW + 4, 2, C_ACCENT);
		flixel.util.FlxSpriteUtil.drawRect(_vpBorder, 0, 0, 2, _vpH + 22, C_ACCENT);
		flixel.util.FlxSpriteUtil.drawRect(_vpBorder, _vpW + 2, 0, 2, _vpH + 22, C_ACCENT);
		_vpBorder.scrollFactor.set(); _vpBorder.cameras = [camHUD]; add(_vpBorder);

		// Título / drag handle
		_vpTitleBar = new FlxSprite(_vpX - 2, _vpY - 20).makeGraphic(_vpW + 4, 20, 0xCC101020);
		_vpTitleBar.scrollFactor.set(); _vpTitleBar.cameras = [camHUD]; add(_vpTitleBar);

		_vpTitleTxt = new FlxText(_vpX + 4, _vpY - 17, _vpW - 60, '🎮 GAME VIEW  —  drag to move | SE corner to resize  |  scroll = zoom', 9);
		_vpTitleTxt.setFormat(Paths.font('vcr.ttf'), 9, C_ACCENT, LEFT);
		_vpTitleTxt.scrollFactor.set(); _vpTitleTxt.cameras = [camHUD]; add(_vpTitleTxt);

		// Esquina SE para resize (triángulo visual)
		_vpHandleCorner = new FlxSprite(_vpX + _vpW - 14, _vpY + _vpH - 14).makeGraphic(14, 14, C_ACCENT);
		_vpHandleCorner.alpha = 0.5;
		_vpHandleCorner.scrollFactor.set(); _vpHandleCorner.cameras = [camHUD]; add(_vpHandleCorner);
	}

	function _destroyFloatingWindowUI():Void
	{
		function kill(s:FlxSprite) { if (s != null) { remove(s); s.destroy(); } }
		function killT(t:FlxText)  { if (t != null) { remove(t); t.destroy(); } }
		kill(_vpBorder);     _vpBorder     = null;
		kill(_vpTitleBar);   _vpTitleBar   = null;
		killT(_vpTitleTxt);  _vpTitleTxt   = null;
		kill(_vpHandleCorner); _vpHandleCorner = null;
	}

	function _repositionFloatingWindowUI():Void
	{
		if (!_vpFloating) return;
		if (_vpBorder != null)
		{
			_vpBorder.x = _vpX - 2;
			_vpBorder.y = _vpY - 20;
			_vpBorder.makeGraphic(_vpW + 4, _vpH + 22, 0x00000000, true);
			flixel.util.FlxSpriteUtil.drawRect(_vpBorder, 0, 0, _vpW + 4, 2, C_ACCENT);
			flixel.util.FlxSpriteUtil.drawRect(_vpBorder, 0, _vpH + 20, _vpW + 4, 2, C_ACCENT);
			flixel.util.FlxSpriteUtil.drawRect(_vpBorder, 0, 0, 2, _vpH + 22, C_ACCENT);
			flixel.util.FlxSpriteUtil.drawRect(_vpBorder, _vpW + 2, 0, 2, _vpH + 22, C_ACCENT);
		}
		if (_vpTitleBar  != null) { _vpTitleBar.x = _vpX - 2; _vpTitleBar.y = _vpY - 20; _vpTitleBar.makeGraphic(_vpW + 4, 20, 0xCC101020); }
		if (_vpTitleTxt  != null) { _vpTitleTxt.x = _vpX + 4; _vpTitleTxt.y = _vpY - 17; }
		if (_vpHandleCorner != null) { _vpHandleCorner.x = _vpX + _vpW - 14; _vpHandleCorner.y = _vpY + _vpH - 14; }
	}

	function _handleGameViewport():Void
	{
		if (!_vpFloating) return;

		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		// ── Inicio de drag (título) / resize (esquina SE) ────────────────────
		if (FlxG.mouse.justPressed)
		{
			// Resize: esquina SE (14×14)
			var inSE = mx >= _vpX + _vpW - 14 && mx <= _vpX + _vpW + 2
			        && my >= _vpY + _vpH - 14 && my <= _vpY + _vpH + 2;
			if (inSE)
			{
				_vpResizing   = true;
				_vpResizeDir  = 'se';
				_vpResStartX  = mx;
				_vpResStartY  = my;
				_vpResStartW  = _vpW;
				_vpResStartH  = _vpH;
			}
			else
			{
				// Drag: barra de título
				var inTitle = mx >= _vpX - 2 && mx <= _vpX + _vpW + 2
				           && my >= _vpY - 20 && my <= _vpY;
				if (inTitle)
				{
					_vpDragging = true;
					_vpDragOffX = mx - _vpX;
					_vpDragOffY = my - _vpY;
				}
			}
		}

		if (FlxG.mouse.justReleased)
		{
			_vpDragging = false;
			_vpResizing = false;
		}

		// ── Drag posición ────────────────────────────────────────────────────
		if (_vpDragging)
		{
			_vpX = FlxMath.bound(mx - _vpDragOffX, 0, SW - _vpW);
			_vpY = FlxMath.bound(my - _vpDragOffY, TOP_H, SH - _vpH - 40);
			_applyViewportToCam();
			_repositionFloatingWindowUI();
		}

		// ── Resize ────────────────────────────────────────────────────────────
		if (_vpResizing)
		{
			var dx = mx - _vpResStartX;
			var dy = my - _vpResStartY;
			_vpW = Std.int(Math.max(_vpMinW, _vpResStartW + dx));
			_vpH = Std.int(Math.max(_vpMinH, _vpResStartH + dy));
			// Clamp al área visible
			_vpW = Std.int(Math.min(_vpW, SW - Std.int(_vpX) - (rightPanelVisible ? RIGHT_W : 0)));
			_vpH = Std.int(Math.min(_vpH, SH - Std.int(_vpY) - STATUS_H));
			_applyViewportToCam();
			_repositionFloatingWindowUI();
		}

		// ── Scroll en el viewport flotante = zoom ─────────────────────────────
		var inViewport = mx >= _vpX && mx <= _vpX + _vpW && my >= _vpY && my <= _vpY + _vpH;
		if (inViewport && FlxG.mouse.wheel != 0 && !FlxG.keys.pressed.CONTROL)
		{
			_gameZoom = FlxMath.bound(_gameZoom * (FlxG.mouse.wheel > 0 ? 1.15 : 0.87), 0.2, 3.0);
			if (camGame != null) camGame.zoom = _gameZoom;
			showStatus('Zoom: ${Math.round(_gameZoom * 100)}%', 0.8);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Character drag handles
	// ─────────────────────────────────────────────────────────────────────────

	function _setupCharHandles():Void
	{
		_charHandles = [];
		for (slot in characterSlots)
		{
			if (slot.character == null) continue;
			var h = new FlxSprite(0, 0).makeGraphic(16, 16, 0xBBFFFFFF, true);
			flixel.util.FlxSpriteUtil.drawCircle(h, 8, 8, 7, 0xBBFFFF00);
			h.scrollFactor.set(1, 1); // sigue al mundo (camGame)
			h.cameras = [camGame];
			h.visible = false;
			add(h);
			_charHandles.push({spr: h, char: slot.character});
		}
	}

	function _updateCharHandles():Void
	{
		for (entry in _charHandles)
		{
			if (entry.spr == null || entry.char == null) continue;
			entry.spr.visible = _showCharHandles;
			if (_showCharHandles)
			{
				// Centro visual del personaje
				entry.spr.x = entry.char.x + entry.char.width  / 2 - 8;
				entry.spr.y = entry.char.y + entry.char.height / 4  - 8;
			}
		}
	}

	function _handleCharDrag():Void
	{
		if (!_showCharHandles) return;
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		if (FlxG.mouse.justPressed && _dragChar == null)
		{
			for (entry in _charHandles)
			{
				if (entry.spr == null || !entry.spr.visible) continue;
				if (FlxG.mouse.overlaps(entry.spr, camGame))
				{
					_dragChar    = entry.char;
					_dragCharOffX = mx - entry.char.x;
					_dragCharOffY = my - entry.char.y;
					break;
				}
			}
		}

		if (_dragChar != null && FlxG.mouse.pressed)
		{
			_dragChar.x = mx - _dragCharOffX;
			_dragChar.y = my - _dragCharOffY;
		}

		if (FlxG.mouse.justReleased) _dragChar = null;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Tween event builder helpers
	// ─────────────────────────────────────────────────────────────────────────

	function _onEventTypeSelected(id:String):Void
	{
		var selectedIdx = Std.parseInt(id);
		if (selectedIdx == null) return;
		var eventTypeList = _getEventTypeList();
		if (selectedIdx < 0 || selectedIdx >= eventTypeList.length) return;
		var typeName = eventTypeList[selectedIdx];
		_setTweenBuilderVisible(typeName.toLowerCase().contains('tween'));
	}

	function _setTweenBuilderVisible(v:Bool):Void
	{
		for (el in _tweenBuilderGroup)
			if (el != null) el.visible = v;
	}

	function _buildTweenValue():Void
	{
		var target   = _tweenTargetInput  != null ? _tweenTargetInput.text.trim()  : 'camGame';
		var prop     = _tweenPropInput    != null ? _tweenPropInput.text.trim()    : 'zoom';
		var fromVal  = _tweenFromInput    != null ? _tweenFromInput.text.trim()    : '';
		var toVal    = _tweenToInput      != null ? _tweenToInput.text.trim()      : '1.2';
		var dur      = _tweenDurInput     != null ? _tweenDurInput.text.trim()     : '1.0';
		var ease     = _tweenEaseDropdown != null ? _tweenEaseDropdown.selectedLabel : 'linear';

		// Formato: target.property|toValue|duration|ease|fromValue
		var value = '$target.$prop|$toVal|$dur|$ease';
		if (fromVal != '') value += '|from:$fromVal';

		if (evtValueInput != null) evtValueInput.text = value;
		if (evtTypeDropdown != null) evtTypeDropdown.selectedLabel = 'Tween';
		showStatus('Tween value generado: $value', 3.0);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Note skin + Song meta live edit
	// ─────────────────────────────────────────────────────────────────────────

	function _getAvailableNoteSkins():Array<String>
	{
		var skins = ['default'];
		// Intentar leer de Paths si está disponible
		#if sys
		var dir = Paths.resolve('images/NOTE_assets');
		if (sys.FileSystem.exists(dir))
		{
			for (f in sys.FileSystem.readDirectory(dir))
				if (f.endsWith('.png') || f.endsWith('.xml'))
				{
					var name = f.split('.')[0];
					if (!skins.contains(name)) skins.push(name);
				}
		}
		#end
		if (skins.length < 2) skins = skins.concat(['pixel','week6','neon','arrows']);
		return skins;
	}

	function _applyNoteSkin(skin:String):Void
	{
		_currentNoteSkin = skin;
		// Actualizar el meta del PlayState (SwagSong puede no tener noteSkin nativo → Reflect)
		if (PlayState.SONG != null)
		{
			final cur:Dynamic = Reflect.field(PlayState.SONG, 'noteSkin');
			if (cur == null || cur != skin)
			{
				Reflect.setField(PlayState.SONG, 'noteSkin', skin);
				hasUnsaved = true;
				_updateUnsavedDot();
			}
		}
		// Recargar el HUD si soporta reloadNoteSkin (reflección para no romper builds)
		if (uiManager != null)
		{
			try { Reflect.callMethod(uiManager, Reflect.field(uiManager, 'reloadNoteSkin'), [skin]); }
			catch (e:Dynamic) { /* método no disponible en esta build */ }
		}
		showStatus('Note skin: $skin (guarda con F5 para persistir)', 3.0);
	}

	/**
	 * Cicla entre cuatro presets de layout del viewport de juego:
	 *   0 = Full  — maximiza la ventana de gameplay, oculta panel + timeline
	 *   1 = Normal — layout por defecto (panel + timeline visibles)
	 *   2 = Compact — timeline oculta, panel visible, viewport más grande
	 *   3 = Side-by-side — panel izquierdo de 40%, viewport derecho 60%
	 */
	function _cycleLayoutPreset():Void
	{
		_layoutPreset = (_layoutPreset + 1) % 4;

		switch (_layoutPreset)
		{
			case 0: // Full — sin panel ni timeline
				if (rightPanelVisible) _toggleRightPanel();
				if (timelineVisible)   _toggleTimeline();
				_gameZoom = 1.0;
				if (camGame != null) camGame.zoom = _gameZoom;
				showStatus('Layout: Full (panel+timeline ocultos)', 2.0);

			case 1: // Normal
				if (!rightPanelVisible) _toggleRightPanel();
				if (!timelineVisible)   _toggleTimeline();
				_gameZoom = 1.0;
				if (camGame != null) camGame.zoom = _gameZoom;
				showStatus('Layout: Normal', 2.0);

			case 2: // Compact — timeline oculta
				if (!rightPanelVisible) _toggleRightPanel();
				if (timelineVisible)    _toggleTimeline();
				_gameZoom = 0.9;
				if (camGame != null) camGame.zoom = _gameZoom;
				showStatus('Layout: Compact (timeline oculta)', 2.0);

			case 3: // Side-by-side
				if (!rightPanelVisible) _toggleRightPanel();
				if (timelineVisible)    _toggleTimeline();
				_gameZoom = 0.55;
				if (camGame != null) camGame.zoom = _gameZoom;
				showStatus('Layout: Side-by-side (juego + panel)', 2.0);
		}

		rebuildTimelineRuler();
		rebuildTimelineEventSprites();
		if (!_vpFloating) _applyViewportToCam();
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Navigation
	// ─────────────────────────────────────────────────────────────────────────

	function _goBack():Void
	{
		if (_unsavedDlg != null) return; // dialog already open
		if (hasUnsaved)
		{
			_unsavedDlg = new UnsavedChangesDialog([camHUD]);
			_unsavedDlg.onSaveAndExit = () -> { savePSEData(); _exitNow(); };
			_unsavedDlg.onSave        = () -> { savePSEData(); remove(_unsavedDlg); _unsavedDlg = null; };
			_unsavedDlg.onExit        = () -> { _exitNow(); };
			add(_unsavedDlg);
		}
		else
		{
			_exitNow();
		}
	}

	function _exitNow():Void
	{
		funkin.system.CursorManager.hide();
		syncAudio(false);
		StateTransition.switchState(new FreeplayEditorState());
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Destroy
	// ─────────────────────────────────────────────────────────────────────────

	override public function destroy():Void
	{
		// Destruir scripts activos
		for (key in scriptInstances.keys())
		{
			var inst = scriptInstances.get(key);
			if (inst != null) inst.active = false;
		}
		scriptInstances.clear();

		if (vocals    != null) { vocals.stop();    vocals.destroy();    vocals    = null; }
		if (vocalsBf  != null) { vocalsBf.stop();  vocalsBf.destroy();  vocalsBf  = null; }
		if (vocalsDad != null) { vocalsDad.stop(); vocalsDad.destroy(); vocalsDad = null; }

		// Destruir vocales del nuevo mapa multi-personaje
		for (snd in vocalsMap)
			if (snd != null) { snd.stop(); snd.destroy(); }
		vocalsMap.clear();

		for (s in tlEventSprites)
		{
			if (s.labelTxt != null) s.labelTxt.destroy();
			s.destroy();
		}
		tlEventSprites = [];

		// Destruir char handles
		for (entry in _charHandles)
			if (entry.spr != null) { remove(entry.spr); entry.spr.destroy(); }
		_charHandles = [];

		// Limpiar ventana flotante
		_destroyFloatingWindowUI();

		// Restaurar camGame a pantalla completa para que no quede "pequeño" en el estado siguiente
		if (camGame != null) { camGame.x = 0; camGame.y = 0; camGame.width = SW; camGame.height = SH; }

		#if sys
		if (_windowCloseFn != null)
		{
			try { lime.app.Application.current.window.onClose.remove(_windowCloseFn); } catch (_) {}
			_windowCloseFn = null;
		}
		#end

		super.destroy();
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Helper: MiniBtn2
// ═══════════════════════════════════════════════════════════════════════════════

private class MiniBtn2 extends FlxSprite
{
	public var label   : FlxText;
	public var onClick : Void->Void;
	var _hovered       : Bool = false;
	var _baseColor     : Int;
	var _hoverColor    : Int;

	public function new(x:Float, y:Float, w:Int, h:Int, txt:String, color:Int, txtColor:Int, ?cb:Void->Void)
	{
		super(x, y);
		makeGraphic(w, h, color);
		_baseColor  = color;
		_hoverColor = _lightenColor(color, 15);
		onClick     = cb;

		label = new FlxText(x, y, w, txt, 11);
		label.setFormat(Paths.font('vcr.ttf'), 11, txtColor, CENTER);
		label.scrollFactor.set();
	}

	// Propagate camera assignment to the label so it always renders on the same
	// camera as the button body (fixes text appearing in camGame/world space).
	override private function set_cameras(value:Array<flixel.FlxCamera>):Array<flixel.FlxCamera>
	{
		if (label != null) label.cameras = value;
		return super.set_cameras(value);
	}

	// Auto-call updateInput so buttons inside coolui.CoolUIGroup tabs work without manual wiring.
	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (alive && exists && visible) updateInput();
	}

	public function updateInput():Void
	{
		// camera-aware overlap so hit-boxes work regardless of coolui.CoolUIGroup tab offsets
		var cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		var over = FlxG.mouse.overlaps(this, cam);

		if (over && !_hovered)
		{
			makeGraphic(Std.int(width), Std.int(height), _hoverColor);
			_hovered = true;
		}
		else if (!over && _hovered)
		{
			makeGraphic(Std.int(width), Std.int(height), _baseColor);
			_hovered = false;
		}

		// Keep label centred on the button body (position may be changed by coolui.CoolUIGroup layout)
		label.x = x;
		label.y = y + (height - label.height) / 2;

		if (over && FlxG.mouse.justPressed && onClick != null)
			onClick();
	}

	/** Lightens a packed 0xAARRGGBB color by `amount` (0-100). */
	static function _lightenColor(c:Int, amount:Int):Int
	{
		final a = (c >> 24) & 0xFF;
		var r = (c >> 16) & 0xFF;
		var g = (c >>  8) & 0xFF;
		var b =  c        & 0xFF;
		final f = amount / 100.0;
		r = Std.int(Math.min(255, r + (255 - r) * f));
		g = Std.int(Math.min(255, g + (255 - g) * f));
		b = Std.int(Math.min(255, b + (255 - b) * f));
		return (a << 24) | (r << 16) | (g << 8) | b;
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Helper: TLEventSprite (sprite en la timeline)
// ═══════════════════════════════════════════════════════════════════════════════

private class TLEventSprite extends FlxSprite
{
	public var eventId  : String;
	public var labelTxt : FlxText;

	/**
	 * Diamond-shaped event marker in the timeline.
	 * isSel = true → white outline + brighter fill.
	 */
	public function new(x:Float, y:Float, h:Int, color:Int, id:String, isSel:Bool = false)
	{
		super(x, y);
		// Draw a little diamond: 8px wide, h px tall
		var w = isSel ? 10 : 8;
		makeGraphic(w, h, color);
		eventId = id;
		alpha   = isSel ? 1.0 : 0.82;
		if (isSel)
		{
			// Draw white border on top
			var border = new flixel.FlxSprite(x - 1, y - 1);
			border.makeGraphic(w + 2, h + 2, flixel.util.FlxColor.WHITE);
			border.alpha = 0.4;
		}
	}
}
