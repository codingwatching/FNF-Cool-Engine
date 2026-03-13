package funkin.gameplay;

// Core imports
import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.transitions.StateTransition;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.tweens.FlxEase;
import flixel.FlxSubState;
// Game objects
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.objects.stages.Stage;
import funkin.gameplay.notes.Note;
import funkin.gameplay.notes.NoteSplash;
import funkin.gameplay.notes.NoteHoldCover;
import funkin.gameplay.notes.StrumNote;
import funkin.gameplay.notes.NoteSkinSystem;
import funkin.gameplay.notes.NotePool;
import funkin.optimization.GPURenderer;
import funkin.optimization.OptimizationManager;
import funkin.system.MemoryUtil;
import funkin.gameplay.objects.character.CharacterSlot;
import funkin.gameplay.objects.StrumsGroup;
import funkin.debug.StageEditor;
import funkin.data.Song.CharacterSlotData;
import funkin.data.Song.StrumsGroupData;
// NUEVO: Import de batching
import funkin.gameplay.notes.NoteBatcher;
// Gameplay modules
import funkin.gameplay.*;
// Scripting
import funkin.scripting.ScriptHandler;
import funkin.scripting.EventManager;
// Other
import funkin.data.Song.SwagSong;
import funkin.data.Song;
import funkin.data.Section.SwagSection;
import funkin.data.Section;
import funkin.data.Conductor;
import funkin.data.CoolUtil;
import funkin.gameplay.objects.hud.Highscore;
import funkin.states.LoadingState;
import funkin.states.GameOverSubstate;
import funkin.menus.RatingState;
import funkin.gameplay.objects.hud.ScoreManager;
import funkin.transitions.StickerTransition;
// Menu Pause
import funkin.menus.GitarooPause;
import funkin.menus.PauseSubState;
import funkin.debug.charting.ChartingState;
import funkin.debug.DialogueEditor;
#if desktop
import data.Discord.DiscordClient;
#end
// Cutscenes
import funkin.cutscenes.dialogue.DialogueBoxImproved;
import funkin.cutscenes.dialogue.DialogueData;
import funkin.cutscenes.VideoManager;
import funkin.cutscenes.SpriteCutscene;
import funkin.data.MetaData;
import funkin.gameplay.UIScriptedManager;
// ModChart
import funkin.gameplay.modchart.ModChartEvent;
import funkin.gameplay.modchart.ModChartManager;
import funkin.gameplay.modchart.ModChartEditorState;
import funkin.gameplay.notes.NoteSkinSystem.NoteSkinData;

using StringTools;

class PlayState extends funkin.states.MusicBeatState
{
	// === SINGLETON ===
	public static var instance:PlayState = null;

	// === STATIC DATA ===
	public static var SONG:SwagSong;
	public static var curStage:String = '';
	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;
	public static var weekSong:Int = 0;

	// ✨ CHART TESTING: Tiempo desde el cual empezar (para testear secciones específicas)
	public static var startFromTime:Null<Float> = null;

	// === LEGACY STATS ===
	public static var misses:Int = 0;
	public static var shits:Int = 0;
	public static var bads:Int = 0;
	public static var goods:Int = 0;
	public static var sicks:Int = 0;
	public static var songScore:Int = 0;
	public static var accuracy:Float = 0.00;
	public static var campaignScore:Int = 0;
	public static var maxCombo:Int = 0;

	/** Proxy to gameState.health for compatibility. */
	public var health(get, set):Float;

	inline function get_health():Float
		return gameState != null ? gameState.health : 1.0;

	inline function set_health(v:Float):Float
	{
		if (gameState != null)
			gameState.health = v;
		return v;
	}

	// === CORE SYSTEMS ===
	public var gameState:GameState;

	public var noteManager:NoteManager;

	private var inputHandler:InputHandler;

	#if mobileC
	/** Controles táctiles (hitbox / virtual pad) — solo en compilación mobile. */
	private var mobileControls:ui.Mobilecontrols;
	#end

	public var cameraController:CameraController;

	public var uiManager:UIScriptedManager;

	public var characterController:CharacterController;

	public var metaData:MetaData;

	public var scriptsEnabled:Bool = true;

	var isCutscene:Bool = false;

	public var scoreManager:ScoreManager;

	// === CAMERAS ===
	public var camGame:FlxCamera;
	public var camHUD:FlxCamera;
	public var camCountdown:FlxCamera;

	// === CHARACTERS ===
	public var boyfriend:Character;
	public var dad:Character;
	public var gf:Character;

	// === STAGE ===
	public var currentStage:Stage;

	// ── MODCHART ──
	public var modChartManager:ModChartManager;

	private var gfSpeed:Int = 1;

	// === NOTES ===
	public var notes:FlxTypedGroup<Note>;

	/** Grupo de notas sustain — se añade ANTES que notes para que los holds
	 *  se dibujen DEBAJO de las notas normales (z-order correcto). */
	public var sustainNotes:FlxTypedGroup<Note>;

	public var strumLineNotes:FlxTypedGroup<FlxSprite>;

	private var playerStrums:FlxTypedGroup<FlxSprite>;

	public static var cpuStrums:FlxTypedGroup<FlxSprite> = null;

	public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;
	public var grpHoldCovers:FlxTypedGroup<NoteHoldCover>;

	// === AUDIO ===
	public var vocals:FlxSound;

	/**
	 * Mapa dinámico de vocales por personaje.
	 * Clave = nombre del personaje (ej: "bf", "dad", "pico").
	 * Soporta cualquier número de personajes — no solo bf+dad.
	 */
	public var vocalsPerChar:Map<String, FlxSound> = new Map();

	/** Alias de compatibilidad legacy/scripts — apunta al track del primer Player. */
	public var vocalsBf(get, never):FlxSound;
	inline function get_vocalsBf():FlxSound
	{
		for (k in _vocalsPlayerKeys) { var v = vocalsPerChar.get(k); if (v != null) return v; }
		return null;
	}

	/** Alias de compatibilidad legacy/scripts — apunta al track del primer Opponent. */
	public var vocalsDad(get, never):FlxSound;
	inline function get_vocalsDad():FlxSound
	{
		for (k in _vocalsOpponentKeys) { var v = vocalsPerChar.get(k); if (v != null) return v; }
		return null;
	}

	/** true si se cargaron vocales por personaje en lugar de un único Voices.ogg */
	private var _usingPerCharVocals:Bool = false;

	/** Personajes de tipo Player — sus tracks se activan en note-hit del jugador. */
	private var _vocalsPlayerKeys:Array<String>   = [];
	/** Personajes de tipo Opponent — sus tracks se activan en note-hit del CPU. */
	private var _vocalsOpponentKeys:Array<String> = [];

	// === STATE ===
	private var generatedMusic:Bool = false;
	private var _gcPausedForSong:Bool = false; // evita doble-pausa si la canción reinicia

	public static var startingSong:Bool = false;

	public var inCutscene:Bool = false;

	public static var isPlaying:Bool = false;

	/** Si está activo, el CPU juega en lugar del jugador (solo disponible en Developer Mode). */
	public static var isBotPlay:Bool = false;

	public var canPause:Bool = true;

	public var paused:Bool = false;

	// === HOOKS ===
	// Almacenados como Map para registro por nombre (add/remove O(1))
	// pero iterados via arrays cacheados para evitar el overhead del iterador de Map.
	public var onBeatHitHooks:Map<String, Int->Void> = new Map();
	public var onStepHitHooks:Map<String, Int->Void> = new Map();
	public var onUpdateHooks:Map<String, Float->Void> = new Map();
	public var onNoteHitHooks:Map<String, Note->Void> = new Map();
	public var onNoteMissHooks:Map<String, Note->Void> = new Map();

	// Arrays cacheados para iteración en el game loop (se reconstruyen al modificar los Maps)
	private var _beatHookArr:Array<Int->Void> = [];
	private var _stepHookArr:Array<Int->Void> = [];
	private var _updateHookArr:Array<Float->Void> = [];
	private var _noteHitHookArr:Array<Note->Void> = [];
	private var _noteMissHookArr:Array<Note->Void> = [];

	/** Llama tras añadir/quitar cualquier hook para reconstruir los arrays cacheados. */
	public function rebuildHookArrays():Void
	{
		_beatHookArr = [for (h in onBeatHitHooks) h];
		_stepHookArr = [for (h in onStepHitHooks) h];
		_updateHookArr = [for (h in onUpdateHooks) h];
		_noteHitHookArr = [for (h in onNoteHitHooks) h];
		_noteMissHookArr = [for (h in onNoteMissHooks) h];
	}

	// === OPTIMIZATION ===
	private var strumLiney:Float = PlayStateConfig.STRUM_LINE_Y;

	public var optimizationManager:OptimizationManager;

	// === SECTION CACHE ===
	private var cachedSection:SwagSection = null;
	private var cachedSectionIndex:Int = -1;

	// Wrapper de Section reutilizable — evita new Section() en cada nota del CPU
	private var _cachedSectionClass:Section = null;
	private var _cachedSectionClassIdx:Int = -2;

	// === NEW: BATCHING AND HOLD NOTES ===
	private var noteBatcher:NoteBatcher;
	private var heldNotes:Map<Int, Note> = new Map(); // dirección -> nota (tracking local para la cámara/personajes)

	// ── Lane Backdrop (osu-style) ─────────────────────────────────────────
	/** Fondo negro semitransparente detrás del carril del jugador, estilo osu!.
	 *  Alpha configurable en opciones (0.0 = transparente por defecto). */
	public var laneBackdrop:FlxSprite;

	// NEW: CONFIG OPTIMIZATIONS
	public var enableBatching:Bool = true;

	private var showDebugStats:Bool = false;
	private var debugText:FlxText;

	// ─── Rewind Restart (V-Slice style) ──────────────────────────────────────

	/** true mientras la animación de rewind está en curso */
	private var isRewinding:Bool = false;

	private var _rewindTimer:Float = 0;
	private var _rewindDuration:Float = 1.0;
	private var _rewindFromPos:Float = 0;

	/** Posición objetivo: inicio del countdown (-crochet * 5) */
	private var _rewindToPos:Float = 0;

	/** Controlador de countdown desacoplado. */
	public var countdown:Countdown;

	// ─── Cooldown para resync de vocals (evita resyncs demasiado frecuentes) ───
	private var _resyncCooldown:Int = 0;

	// ─── Audio boot: mantiene FPS bajo por N frames tras _safePlay para que ───
	// ─── el buffer de SampleDataEvent se inicialice con ≥2048 samples.       ───
	private var _audioBootFrames:Int  = 0;
	private var _audioBootSavedFps:Int = 0;

	private var characterSlots:Array<CharacterSlot> = [];

	public var strumsGroups:Array<StrumsGroup> = [];

	// Mapeos para acceso rápido
	public var strumsGroupMap:Map<String, StrumsGroup> = new Map();

	private var activeCharIndices:Array<Int> = []; // Personajes activos en la sección actual

	// ✅ Referencias directas a los grupos de strums
	public var playerStrumsGroup:StrumsGroup = null;
	public var cpuStrumsGroup:StrumsGroup = null;

	var skinSystem:NoteSkinData;

	#if desktop
	var storyDifficultyText:String = "";
	var iconRPC:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	override public function create()
	{
		// Iniciar sesión de caché: mueve _currentGraphics → _previousGraphics.
		// Los assets cargados durante create() se rastrean en CURRENT.
		// Los assets que el nuevo estado COMPARTE con el anterior son "rescatados"
		// de _previousGraphics a CURRENT la primera vez que se piden, evitando
		// recarga desde disco.
		// clearPreviousSession() se llama al FINAL de create() para destruir
		// lo que nadie rescató — no al principio, para dar tiempo al rescue.
		// NOTA: PathsCache.beginSession() es llamado automáticamente por la señal
		// preStateSwitch en FunkinCache.init(). Llamarlo aquí de nuevo causa que los
		// assets del state anterior (menú, etc.) queden huérfanos entre las dos capas.
		// FunkinCache ya rota sus capas en preStateSwitch, así que OpenFL también
		// libera bitmaps correctamente. Paths.clearStoredMemory() ya no se necesita al inicio.

		// NOTA: FunkinCache ya rota sus capas en preStateSwitch (justo antes de
		// llegar aquí), así que OpenFL también libera bitmaps correctamente.
		// Paths.clearStoredMemory() ya no se necesita al inicio.

		if (StickerTransition.enabled)
		{
			transIn = null;
			transOut = null;
		}
		instance = this;
		isPlaying = true;

		FlxG.mouse.visible = false;
		#if android
		// En Android, el botón "atrás" del sistema se mapea a ESCAPE en OpenFL.
		// Lo capturamos en el update() y lo tratamos como pausa.
		lime.app.Application.current.window.onKeyDown.add(_onAndroidKeyDown);
		#end

		if (scriptsEnabled)
		{
			ScriptHandler.init();
			ScriptHandler.loadSongScripts(SONG.song);
			EventManager.loadEventsFromSong();

			// Exponer PlayState a los scripts
			ScriptHandler.setOnScripts('playState', this);
			ScriptHandler.setOnScripts('game', this);
			ScriptHandler.setOnScripts('SONG', SONG);
			// Llamar onCreate en scripts
			ScriptHandler.callOnScripts('onCreate', ScriptHandler._argsEmpty);
		}

		// Validar SONG
		if (SONG.stage == null)
			SONG.stage = 'stage_week1';

		curStage = SONG.stage;
		Paths.currentStage = curStage; // sync Paths para resolución de assets de stage

		// Discord RPC
		#if desktop
		setupDiscord();
		#end

		// Crear cámaras
		setupCameras();

		// BUGFIX: inyectar camGame/camHUD ANTES de loadStageAndCharacters().
		// loadStageAndCharacters() → loadStageScripts() → onStageCreate() donde
		// los scripts del stage ya usan camGame (e.g. setFilters, shaders).
		// Si se inyecta después (como estaba antes, línea ~460) camGame es null
		// durante onStageCreate y cualquier llamada a setFilters/clearFilters falla.
		if (scriptsEnabled)
		{
			ScriptHandler.setOnScripts('camGame', camGame);
			ScriptHandler.setOnScripts('camHUD', camHUD);
			ScriptHandler.setOnScripts('camCountdown', camCountdown);
		}

		// Crear core systems
		gameState = GameState.get();
		gameState.reset();

		RatingManager.reload(SONG.song);

		// Crear stage y personajes
		loadStageAndCharacters();

		metaData = MetaData.load(SONG.song, funkin.data.CoolUtil.difficultySuffix());
		NoteSkinSystem.init();
		// Aplicar defaults del mod (global.json) después de init().
		// Ahora es seguro: _initializing=false, initialized=true.
		// Usamos applyGlobalConfigToSkinSystem() en lugar de reload() para no
		// releer el archivo de disco en cada canción.
		funkin.data.GlobalConfig.applyToSkinSystem();

		// Crear UI
		setupUI();

		// ── Aplicar skin de notas con jerarquía de prioridad ─────────────────
		// Prioridad: meta.noteSkin > meta.stageSkins[stage] > stage-default > global player
		//
		// 1. Si el meta.json tiene "noteSkin" → override total para toda la canción.
		// 2. Si tiene "stageSkins" → registrar los overrides por stage en el sistema.
		//    El stage actual se resuelve via applySkinForStage().
		// 3. Si no hay nada en meta → applySkinForStage() usa el mapping global
		//    (los defaults "school"→"DefaultPixel" etc. o lo que haya en NoteSkinSystem).
		if (metaData.noteSkin != null && metaData.noteSkin != 'default' && metaData.noteSkin != '')
		{
			// Override total: toda la canción usa esta skin sin importar el stage
			NoteSkinSystem.setTemporarySkin(metaData.noteSkin);
			trace('[PlayState] Skin override from meta.json: "${metaData.noteSkin}"');
		}
		else
		{
			// Sin override global → registrar stageSkins del meta si los hay,
			// luego resolver la skin según el stage actual
			if (metaData.stageSkins != null)
			{
				for (stageName in metaData.stageSkins.keys())
					NoteSkinSystem.registerStageSkin(stageName, metaData.stageSkins.get(stageName));
				trace('[PlayState] stageSkins from meta.json applied');
			}
			NoteSkinSystem.applySkinForStage(curStage);
		}

		// ── Aplicar splash de notas ───────────────────────────────────────────
		// meta.noteSplash > global player preference (NoteSkinSystem ya cargo la global)
		// BUGFIX: usar setTemporarySplash() en lugar de setSplash() para NO guardar
		// permanentemente en disco. setSplash() hacia flush() y contaminaba la
		// preferencia global del jugador — cualquier cancion de school cambiaba el
		// splash a "PixelSplash" para TODAS las canciones siguientes.
		if (metaData.noteSplash != null && metaData.noteSplash != '')
			NoteSkinSystem.setTemporarySplash(metaData.noteSplash);
		else
			NoteSkinSystem.applySplashForStage(curStage);

		StickerTransition.clearStickers();

		if (scriptsEnabled)
		{
			ScriptHandler.setOnScripts('boyfriend', boyfriend);
			ScriptHandler.setOnScripts('dad', dad);
			ScriptHandler.setOnScripts('gf', gf);
			ScriptHandler.setOnScripts('stage', currentStage);
			// onStageCreate ya fue disparado por loadStageScripts() una vez que los elementos existen.
			// Llamarlo aqui de nuevo (via callOnScripts) dispara TODOS los layers incluyendo stage,
			// causando una segunda ejecucion con los sprites aun no registrados. Solo llamamos
			// a los scripts que NO son de stage (global, song, ui, etc.).
			ScriptHandler.callOnNonStageScripts('onStageCreate', ScriptHandler._argsEmpty);
			ScriptHandler.callOnScripts('postCreate', ScriptHandler._argsEmpty);
			// Resolver listArtist con prioridad: meta.json > chart field > default.
			// meta.json permite overridear el artista sin modificar el chart.
			if (metaData != null && metaData.artist != null && metaData.artist != '')
				GameState.listArtist = metaData.artist;
			else if (SONG.artist != null && SONG.artist != '')
				GameState.listArtist = SONG.artist;
			ScriptHandler.setOnScripts('author', GameState.listArtist);
		}

		// Crear UI groups
		createNoteGroups();

		// Crear controllers
		setupControllers();

		modChartManager = new ModChartManager(strumsGroups);
		modChartManager.data.song = SONG.song;
		modChartManager.loadFromFile(SONG.song); // carga assets/modcharts/<song>.json si existe

		// Exponer modchart y strums a scripts
		if (scriptsEnabled)
		{
			ScriptHandler.setOnScripts('modChart', modChartManager);
			ScriptHandler.setOnScripts('playerStrumsGroup', playerStrumsGroup);
			ScriptHandler.setOnScripts('cpuStrumsGroup', cpuStrumsGroup);
			ScriptHandler.setOnScripts('strumsGroups', strumsGroups);
			ScriptHandler.setOnScripts('strumsGroupMap', strumsGroupMap);
		}

		// Generar música
		generateSong();

		// Pool de sonidos de golpe (evita alloc por nota)
		initHitSoundPool();

		// NUEVO: Setup debug display
		setupDebugDisplay();

		optimizationManager = new OptimizationManager();
		optimizationManager.init();

		// Configurar pipeline de renderizado para GPU
		funkin.optimization.RenderOptimizer.init();
		funkin.optimization.RenderOptimizer.optimizeCameras(camGame, camHUD);

		countdown.preload();

		// StickerTransition.clearStickers(function() {
		startCountdown();
		// });

		Paths.clearPreviousSession();

		super.create();

		// ── Pausa global al perder foco ───────────────────────────────────────
		// FlxG.signals.focusLost se dispara EN CUALQUIER momento, sin importar
		// qué estado o substate esté activo (al contrario que override onFocusLost,
		// que solo se invoca cuando PlayState es el estado raíz activo).
		// Lo suscribimos aquí y lo quitamos en destroy() para no dejar listeners huérfanos.
		FlxG.signals.focusLost.add(_onGlobalFocusLost);

		// ── GPU flush post-primer-render ─────────────────────────────────────
		// BUGFIX: el timer anterior se registraba ANTES de super.create() →
		// los primeros frames de render aún no habían ocurrido cuando disparaba,
		// por lo que getTexture() podía devolver null o las texturas no estaban
		// subidas a VRAM todavía → disposeImage() borraba pixels antes del upload.
		//
		// SOLUCIÓN: escuchar ENTER_FRAME en el stage nativo de OpenFL.
		// Esperamos 5 frames para garantizar que context3D procesó TODOS los
		// draw calls del create() (personajes, stage, strums, HUD, countdown).
		// En el frame 5 hacemos:
		//   1. flushGPUCache()  — disposeImage() de todas las texturas subidas
		//   2. Gc.run(true)     — ciclo GC mayor: recoge los Image.pixels liberados
		//   3. Gc.compact()     — compacta el heap → System.totalMemory baja realmente
		//
		// Gc.compact() is slow (~50-200ms) but happens only once per song.
		// We use 3 frames (was 5) to still guarantee GPU upload is done while
		// running the compact as early as possible — during the very first
		// countdown beat where the freeze is least noticeable.
		#if (desktop && cpp && !hl)
		var _flushFrameCount:Int = 0;
		final _flushFramesNeeded:Int = 3;
		var _flushListener:openfl.events.EventDispatcher = null;
		_flushListener = FlxG.stage;
		function _onFlushFrame(_:openfl.events.Event):Void
		{
			_flushFrameCount++;
			if (_flushFrameCount < _flushFramesNeeded)
				return;
			FlxG.stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _onFlushFrame);
			// Paso 1: liberar CPU pixels de texturas ya en VRAM
			funkin.cache.PathsCache.instance.flushGPUCache();
			// Paso 2 + 3: GC mayor + compactación → System.totalMemory refleja uso real
			cpp.vm.Gc.run(true);
			cpp.vm.Gc.compact();
			trace('[PlayState] GPU flush + GC compact completado tras ${_flushFramesNeeded} frames');
		}
		FlxG.stage.addEventListener(openfl.events.Event.ENTER_FRAME, _onFlushFrame);
		#end
	}

	/**
	 * Setup Discord RPC
	 */
	#if desktop
	private function setupDiscord():Void
	{
		storyDifficultyText = CoolUtil.difficultyString();
		// Lee discordIcon del JSON del personaje oponente (campo opcional).
		// Si el personaje no define discordIcon se usa el healthIcon o el nombre directo.
		// Esto elimina el switch hardcodeado 'monster-christmas'→'monster', etc.:
		// cualquier personaje con nombre que no coincida con su clave Discord
		// solo necesita añadir "discordIcon": "clave" en su JSON.
		var _dadChar = dad != null ? dad : null;
		var _dadData = _dadChar != null ? _dadChar.characterData : null;
		if (_dadData != null && _dadData.discordIcon != null && _dadData.discordIcon != '')
			iconRPC = _dadData.discordIcon;
		else if (_dadData != null && _dadData.healthIcon != null && _dadData.healthIcon != '')
			iconRPC = _dadData.healthIcon;
		else
			iconRPC = SONG.player2;

		if (isStoryMode)
			detailsText = "Story Mode: Week " + storyWeek;
		else
			detailsText = "Freeplay";

		detailsPausedText = "Paused - " + detailsText;
		updatePresence();
	}

	function updatePresence():Void
	{
		DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconRPC);
	}
	#end

	/**
	 * Crear cámaras
	 */
	private function setupCameras():Void
	{
		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camCountdown = new FlxCamera();
		camCountdown.bgColor.alpha = 0;
		// Detectar si el stage es pixel leyendo el campo "isPixelStage" del
		// stage JSON. Stage.getStageData() reutiliza el mismo caché que new Stage(),
		// así que no hay I/O extra cuando más tarde se construya el stage.
		// Reemplaza el hardcode curStage.startsWith('school').
		final _sd = funkin.gameplay.objects.stages.Stage.getStageData(curStage);
		final isPixelStage = (_sd != null && _sd.isPixelStage == true);

		countdown = new Countdown(this, camCountdown, isPixelStage);

		if (scriptsEnabled)
			ScriptHandler.setOnScripts('countdown', countdown);

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camCountdown, false);
	}

	/**
	 * Cargar stage y personajes
	 */
	private function loadStageAndCharacters():Void
	{
		// Crear stage (elementos sin aboveChars se añaden al propio grupo Stage)
		currentStage = new Stage(curStage);
		// Propagar camGame a todos los sprites del stage (incluyendo sub-grupos)
		// ANTES de add() para que estén listos cuando scripts les apliquen shaders.
		currentStage.cameras = [camGame];
		_assignStageCameras(currentStage, [camGame]);
		add(currentStage);

		// Crear personajes desde stage
		loadCharacters();

		// ── Capas por encima de los personajes ───────────────────────────────
		// Los elementos marcados con aboveChars:true en el JSON del stage se
		// añaden AQUÍ, después de todos los personajes, para que se rendericen
		// encima de ellos (cámaras, capas de luz, foreground, bokeh…)
		// Equivalente a poner sprites DESPUÉS de <boyfriend> en Codename Engine.
		if (currentStage.aboveCharsGroup != null && currentStage.aboveCharsGroup.length > 0)
			add(currentStage.aboveCharsGroup);

		// Asignar refs legacy buscando por tipo (no por índice)
		for (slot in characterSlots)
		{
			if (slot.isGFSlot && gf == null)
				gf = slot.character;
			else if (slot.isOpponentSlot && dad == null)
				dad = slot.character;
			else if (slot.isPlayerSlot && boyfriend == null)
				boyfriend = slot.character;
		}

		// Cargar scripts de personaje e inyectar variables
		if (scriptsEnabled)
		{
			for (slot in characterSlots)
			{
				final char = slot.character;
				if (char == null)
					continue;
				ScriptHandler.loadCharacterScripts(char.curCharacter);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'character', char);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'char', char);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'game', this);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'playState', this);
				ScriptHandler.callOnCharacterScripts(char.curCharacter, 'postCreate', ScriptHandler._argsEmpty);
				trace('[PlayState] Scripts de personaje cargados para "${char.curCharacter}"');
			}
		}
	}

	private function loadCharacters():Void
	{
		// BUGFIX: La condición original era:
		//   if (SONG.characters != null)          ← outer
		//       if (SONG.characters == null ...) { // NUNCA se ejecuta — outer ya garantiza != null
		// El bloque de compatibilidad legacy era código muerto. Corregido:
		if (SONG.characters == null || SONG.characters.length == 0)
		{
			// Compatibilidad legacy. BUG FIX: usar 'type' explícito.
			// Sin 'type', CharacterSlot infiere por nombre de personaje.
			// Nombres no estándar como 'ray' (player1) o 'mighty' (player2)
			// no empiezan por 'bf'/'gf' → se tipifican como 'Opponent' →
			// BF se coloca en dadPosition (visible) en lugar de boyfriendPosition.
			SONG.characters = [];

			SONG.characters.push({
				name: SONG.gfVersion != null ? SONG.gfVersion : 'gf',
				x: 0,
				y: 0,
				visible: true,
				isGF: true,
				type: 'Girlfriend',
				strumsGroup: 'gf_strums_0'
			});

			SONG.characters.push({
				name: SONG.player2 != null ? SONG.player2 : 'dad',
				x: 0,
				y: 0,
				visible: true,
				type: 'Opponent',
				strumsGroup: 'cpu_strums_0'
			});

			SONG.characters.push({
				name: SONG.player1 != null ? SONG.player1 : 'bf',
				x: 0,
				y: 0,
				visible: true,
				type: 'Player',
				strumsGroup: 'player_strums_0'
			});
		}

		// Crear slots de personajes
		for (i in 0...SONG.characters.length)
		{
			var charData = SONG.characters[i];
			var slot = new CharacterSlot(charData, i);

			// Si la posición es (0,0), usar posición del stage según el TIPO del personaje
			if (charData.x == 0 && charData.y == 0)
			{
				switch (slot.charType)
				{
					case 'Girlfriend':
						slot.character.setPosition(currentStage.gfPosition.x, currentStage.gfPosition.y);
					case 'Opponent':
						slot.character.setPosition(currentStage.dadPosition.x, currentStage.dadPosition.y);
					case 'Player':
						slot.character.setPosition(currentStage.boyfriendPosition.x, currentStage.boyfriendPosition.y);
					default:
						// Personajes tipo "Other" o sin tipo: sin posición automática
				}
			}
			else
			{
				// Usar posición del JSON
				slot.character.setPosition(charData.x, charData.y);
			}

			// BUG FIX #CHARPOS: Aplicar el offset de posición del personaje (campo "position"
			// en Psych). En Psych Engine, este offset se SUMA a la posición del stage.
			// Ejemplo: dad en el stage está en x=100, pero su JSON tiene position=[50, 0]
			// → posición final = x=150. Sin este fix, el personaje siempre aparece en x=100.
			if (slot.character.characterData != null)
			{
				final posOff = slot.character.characterData.positionOffset;
				if (posOff != null && posOff.length >= 2)
				{
					slot.character.x += posOff[0];
					slot.character.y += posOff[1];
				}
			}

			characterSlots.push(slot);
			add(slot.character);
		}

		// BUG FIX #HIDEGF: hide_girlfriend del stage de Psych (y el campo nativo de Cool).
		// La versión anterior leía hideGirlfriend en Stage.hx pero nunca lo aplicaba
		// a la visibilidad del personaje GF en PlayState. La GF seguía visible siempre.
		if (currentStage != null && currentStage.hideGirlfriend)
		{
			for (slot in characterSlots)
			{
				if (slot.isGFSlot && slot.character != null)
				{
					slot.character.visible = false;
					trace('[PlayState] hideGirlfriend: ocultando "${slot.character.curCharacter}"');
				}
			}
		}
	}

	/**
	 * Crear grupos de notas - MEJORADO con batching
	 */
	private function createNoteGroups():Void
	{
		// ✅ Inicializar strumLineNotes ANTES de loadStrums()
		strumLineNotes = new FlxTypedGroup<FlxSprite>();
		strumLineNotes.cameras = [camHUD];

		// loadStrums asigna playerStrums/cpuStrums — debe ir ANTES del backdrop
		// para que _updateLaneBackdrop() pueda leer las posiciones reales.
		loadStrums();

		// ─── Lane Backdrop (osu-style) ───────────────────────────────────────
		// Se crea DESPUÉS de loadStrums para conocer las coords de playerStrums.
		// Se añade ANTES que strumLineNotes/notes para quedar detrás de todo.
		laneBackdrop = new FlxSprite();
		laneBackdrop.cameras = [camHUD];
		laneBackdrop.scrollFactor.set(0, 0);
		_updateLaneBackdrop();
		add(laneBackdrop);
		// ────────────────────────────────────────────────────────────────────

		// NUEVO: Crear batcher
		noteBatcher = new NoteBatcher();
		noteBatcher.cameras = [camHUD];
		add(noteBatcher);

		// Añadir strums (encima del backdrop y del batcher)
		add(strumLineNotes);

		// sustainNotes se añade PRIMERO → se dibuja DEBAJO de notes normales
		sustainNotes = new FlxTypedGroup<Note>();
		sustainNotes.cameras = [camHUD];
		add(sustainNotes);

		notes = new FlxTypedGroup<Note>();
		notes.cameras = [camHUD];
		add(notes);

		grpNoteSplashes = new FlxTypedGroup<NoteSplash>();
		grpNoteSplashes.cameras = [camHUD];
		add(grpNoteSplashes);

		grpHoldCovers = new FlxTypedGroup<NoteHoldCover>();
		grpHoldCovers.cameras = [camHUD];
		add(grpHoldCovers);
	}

	/**
	 * Actualiza posición y alpha del lane backdrop basándose en los strums
	 * del jugador actuales y el valor guardado de laneAlpha.
	 * Llamar tras loadStrums() y tras rewind restart.
	 */
	private function _updateLaneBackdrop():Void
	{
		if (laneBackdrop == null)
			return;

		var alpha:Float = (FlxG.save.data.laneAlpha != null) ? FlxG.save.data.laneAlpha : 0.0;
		laneBackdrop.alpha = alpha;

		if (playerStrums == null || playerStrums.members == null || playerStrums.members.length < 4)
		{
			// Fallback: sprite oculto y fuera de pantalla
			laneBackdrop.makeGraphic(4, FlxG.height, flixel.util.FlxColor.BLACK);
			laneBackdrop.x = -999;
			return;
		}

		var firstStrum:FlxSprite = playerStrums.members[0];
		var lastStrum:FlxSprite  = playerStrums.members[playerStrums.members.length - 1];

		if (firstStrum == null || lastStrum == null)
			return;

		// Ancho = desde la izquierda del primer strum hasta la derecha del último
		var startX:Float = firstStrum.x;
		var endX:Float   = lastStrum.x + lastStrum.width;
		var bw:Int       = Std.int(endX - startX + 20); // +20px padding lateral
		if (bw < 4) bw = 4;

		laneBackdrop.makeGraphic(bw, FlxG.height, flixel.util.FlxColor.BLACK);
		laneBackdrop.setPosition(startX - 10, 0); // -10 para padding izquierdo
	}

	private function loadStrums():Void
	{
		if (SONG.strumsGroups == null || SONG.strumsGroups.length == 0)
		{
			return;
		}

		// Crear grupos
		for (groupData in SONG.strumsGroups)
		{
			var group = new StrumsGroup(groupData);
			strumsGroups.push(group);
			strumsGroupMap.set(groupData.id, group);

			// Añadir strums al juego
			group.strums.forEach(function(strum:FlxSprite)
			{
				strumLineNotes.add(strum);
			});

			// Separar CPU y Player strums (para compatibilidad)
			if (groupData.cpu && cpuStrums == null)
			{
				// El primer grupo CPU que NO es de GF se asigna como cpuStrums principal
				// Los grupos de GF (visible:false, id empieza con 'gf_') son auxiliares
				var isGFGroup = groupData.id.startsWith('gf_') || (!groupData.visible && groupData.id.indexOf('gf') >= 0);
				if (!isGFGroup)
				{
					cpuStrums = group.strums;
					cpuStrumsGroup = group;
					if (FlxG.save.data.downscroll)
					{
						for (i in 0...cpuStrums.members.length)
							cpuStrums.members[i].y = FlxG.height - 150;
					}
					if (FlxG.save.data.middlescroll)
					{
						for (i in 0...cpuStrums.members.length)
						{
							cpuStrums.members[i].visible = false;
							cpuStrums.members[i].alpha = 0;
						}
					}
				}
			}
			else if (!groupData.cpu && playerStrums == null)
			{
				playerStrums = group.strums;
				playerStrumsGroup = group;

				for (i in 0...playerStrums.members.length)
				{
					if (FlxG.save.data.downscroll)
						playerStrums.members[i].y = FlxG.height - 150;
					if (FlxG.save.data.middlescroll)
						playerStrums.members[i].x -= (FlxG.width / 4);
				}
			}
		}
	}

	/**
	 * Setup controllers - MEJORADO con splashes
	 */
	private function setupControllers():Void
	{
		// ✅ Verificar que boyfriend y dad existan antes de crear CameraController
		if (boyfriend == null || dad == null)
		{
			// En modo debug, crear personajes de emergencia
			#if debug
			if (boyfriend == null)
			{
				boyfriend = new Character(100, 100, 'bf');
				add(boyfriend);
			}
			if (dad == null)
			{
				dad = new Character(100, 100, 'dad');
				add(dad);
			}
			#else
			// En producción, volver al menú
			StateTransition.switchState(new funkin.menus.MainMenuState());
			return;
			#end
		}

		// Camera controller
		cameraController = new CameraController(camGame, camHUD, boyfriend, dad, gf);

		if (currentStage.defaultCamZoom > 0)
			cameraController.defaultZoom = currentStage.defaultCamZoom;

		// Aplicar los offsets de cámara definidos en el stage JSON.
		cameraController.stageOffsetBf.set(currentStage.cameraBoyfriend.x, currentStage.cameraBoyfriend.y);
		cameraController.stageOffsetDad.set(currentStage.cameraDad.x, currentStage.cameraDad.y);
		cameraController.stageOffsetGf.set(currentStage.cameraGirlfriend.x, currentStage.cameraGirlfriend.y);
		// cameraSpeed es un multiplicador: 1.0 = default. Se aplica sobre BASE_LERP_SPEED.
		cameraController.lerpSpeed = CameraController.BASE_LERP_SPEED * currentStage.cameraSpeed;

		// Snapshot the final initial state NOW (after stage overrides) so that
		// resetToInitial() on rewind/restart knows where to return to.
		cameraController.snapshotInitialState();

		// Character controller
		characterController = new CharacterController();
		characterController.initFromSlots(characterSlots);

		ScriptHandler.setOnScripts('characterController', characterController);

		// Input handler
		inputHandler = new InputHandler();
		inputHandler.ghostTapping = FlxG.save.data.ghosttap;
		inputHandler.onNoteHit = onPlayerNoteHit;
		inputHandler.onNoteMiss = onPlayerNoteMiss;

		// NUEVO: Configurar buffering si lo deseas
		inputHandler.inputBuffering = true;
		inputHandler.bufferTime = 0.1; // 100ms

		// NUEVO: Callback para release de hold notes — dispara animación fin del hold cover
		inputHandler.onKeyRelease = onKeyRelease;

		// ── Controles táctiles (mobile) ───────────────────────────────────────
		// Se crean DESPUÉS del inputHandler para poder pasarle las referencias
		// de los FlxButtons directamente. La cámara de los controles es camHUD
		// para que queden por encima del juego y no se vean afectados por zoom.
		#if mobileC
		mobileControls = new ui.Mobilecontrols();
		mobileControls.cameras = [camHUD];
		mobileControls.scrollFactor.set(0, 0);
		add(mobileControls);

		// Conectar botones del hitbox / virtual pad al InputHandler
		var _hitbox = mobileControls._hitbox;
		var _vpad = mobileControls._virtualPad;
		if (_hitbox != null)
		{
			inputHandler.mobileLeft = _hitbox.buttonLeft;
			inputHandler.mobileDown = _hitbox.buttonDown;
			inputHandler.mobileUp = _hitbox.buttonUp;
			inputHandler.mobileRight = _hitbox.buttonRight;
		}
		else if (_vpad != null)
		{
			inputHandler.mobileLeft = _vpad.buttonLeft;
			inputHandler.mobileDown = _vpad.buttonDown;
			inputHandler.mobileUp = _vpad.buttonUp;
			inputHandler.mobileRight = _vpad.buttonRight;
		}
		#end

		// AJUSTE: Calcular posición de strums según downscroll
		if (FlxG.save.data.downscroll)
			strumLiney = FlxG.height - 150; // Flechas abajo
		else
			strumLiney = PlayStateConfig.STRUM_LINE_Y; // Flechas arriba (50 por defecto)

		// Note manager - MEJORADO con splashes
		// ✅ Pasar referencias a StrumsGroup para animaciones de confirm
		// ✅ Pasar lista completa de grupos para soporte de personajes extra
		noteManager = new NoteManager(notes, playerStrums, cpuStrums, grpNoteSplashes, grpHoldCovers, playerStrumsGroup, cpuStrumsGroup, strumsGroups,
			sustainNotes);

		noteManager.strumLineY = strumLiney;
		noteManager.downscroll = FlxG.save.data.downscroll;
		noteManager.middlescroll = FlxG.save.data.middlescroll;
		noteManager.onCPUNoteHit = onCPUNoteHit;
		noteManager.onNoteHit = null; // Hold covers now managed by NoteManager internally
		noteManager.onNoteMiss = onPlayerNoteMiss; // FIX: sin esto missNote() llama a null y la penalización nunca se aplica
	}

	/**
	 * NUEVO: Setup debug display
	 */
	private function setupDebugDisplay():Void
	{
		debugText = new FlxText(10, 10, 0, "", 14);
		debugText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2);
		debugText.cameras = [camHUD];
		debugText.visible = showDebugStats;
		add(debugText);
	}

	/**
	 * Crear UI
	 */
	public function setupUI():Void
	{
		var icons:Array<String> = [SONG.player1, SONG.player2];

		// ✅ Verificar que existan antes de acceder a sus propiedades
		if (boyfriend != null && dad != null)
		{
			if (boyfriend.healthIcon != null && dad.healthIcon != null)
				icons = [boyfriend.healthIcon, dad.healthIcon];
		}

		uiManager = new UIScriptedManager(camHUD, gameState, metaData);
		uiManager.setIcons(icons[0], icons[1]);
		uiManager.setStage(curStage);
		add(uiManager);
		// BUGFIX: Evitar que super.update() llame a uiManager.update() automáticamente,
		// ya que PlayState lo actualiza manualmente dentro de if(!paused && !inCutscene).
		// Sin esto, el UI se actualizaba dos veces por frame causando lag y animaciones dobles.
		uiManager.active = false;
	}

	/**
	 * Generar flechas estáticas
	 */
	private function generateStaticArrows(player:Int):Void
	{
		for (i in 0...4)
		{
			var targetAlpha:Float = 1;
			if (player < 1 && FlxG.save.data.middlescroll)
				targetAlpha = 0;

			var babyArrow:StrumNote = new StrumNote(0, strumLiney, i);
			babyArrow.ID = i;

			// Posición
			var xPos = 100 + (Note.swagWidth * i);
			if (player == 1)
			{
				if (FlxG.save.data.middlescroll)
					xPos = FlxG.width / 2 - (Note.swagWidth * 2) + (Note.swagWidth * i);
				else
					xPos += FlxG.width / 2;

				playerStrums.add(babyArrow);
			}
			else
			{
				if (FlxG.save.data.middlescroll)
					xPos = -275 + (Note.swagWidth * i);

				cpuStrums.add(babyArrow);
			}

			babyArrow.x = xPos;
			babyArrow.alpha = 0;

			FlxTween.tween(babyArrow, {alpha: targetAlpha}, 0.5, {
				startDelay: 0.5 + (0.2 * i)
			});

			babyArrow.animation.play('static');
			babyArrow.cameras = [camHUD];
			strumLineNotes.add(babyArrow);
		}
	}

	/**
	 * Generar canción
	 */
	private function generateSong():Void
	{
		Conductor.changeBPM(SONG.bpm);

		// Sufijo de dificultad para cargar Inst-diff.ogg / Voices-diff.ogg si existen.
		// Si el metadata V-Slice define "instrumental" (playData.characters.instrumental),
		// ese valor tiene prioridad sobre el sufijo de dificultad — permite que varias
		// dificultades (ej: erect + nightmare) compartan los mismos archivos de audio.
		final _diffSuffix:String = (SONG.instSuffix != null && SONG.instSuffix != '') ? '-' + SONG.instSuffix : funkin.data.CoolUtil.difficultySuffix();

		trace('[PlayState] Audio suffix: "$_diffSuffix" (instSuffix=${SONG.instSuffix})');

		// Cargar instrumental usando el método seguro que soporta archivos externos
		// MusicManager ya no controla el audio — PlayState lo toma directamente.
		funkin.audio.MusicManager.invalidate();
		FlxG.sound.music = Paths.loadInst(SONG.song, _diffSuffix);
		// FIX: loadInst can return null on Android if the file is missing or OOM.
		// Guard every access so a bad song doesn't crash the whole game.
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.volume = 0;
			FlxG.sound.music.pause();
		}
		else
		{
			trace('[PlayState] WARNING: Paths.loadInst returned null for "${SONG.song}" — audio will be silent.');
		}

		// Limpiar vocals anterior si existía (por si se llama generateSong más de una vez)
		if (vocals != null)
		{
			FlxG.sound.list.remove(vocals, true);
			vocals.stop();
			vocals.destroy();
			vocals = null;
		}
		_cleanPerCharVocals();

		// Cargar voces usando el método seguro
		if (SONG.needsVoices)
		{
			_usingPerCharVocals = _tryLoadPerCharVocals(_diffSuffix);
			if (!_usingPerCharVocals)
				vocals = Paths.loadVoices(SONG.song, _diffSuffix);
		}

		if (!_usingPerCharVocals)
		{
			if (vocals == null)
				vocals = new FlxSound();
			vocals.volume = 0;
			vocals.pause();
			FlxG.sound.list.add(vocals);
		}

		// Limpiar NotePool antes de regenerar (evita acumulación en retry)
		// Codename Engine siempre resetea el pool al generar notas nuevas.
		NotePool.clear();

		// Generar notas

		noteManager.generateNotes(SONG);

		generatedMusic = true;

		// Pausar GC durante gameplay — evita stutter por colección en medio de la canción.
		// Se reanuda en destroy() cuando la canción termina o el jugador sale.
		if (!_gcPausedForSong)
		{
			_gcPausedForSong = true;
			MemoryUtil.pauseGC();
		}

		_prewarmNoteTextures();
	}

	private function _prewarmNoteTextures():Void
	{
		var skinData = NoteSkinSystem.getCurrentSkinData();
		if (skinData == null)
			return;
		// Forzar la carga del atlas en caché sin crear notas reales
		NoteSkinSystem.loadSkinFrames(skinData.texture, skinData.folder);
		if (skinData.holdTexture != null)
			NoteSkinSystem.loadSkinFrames(skinData.holdTexture, skinData.folder);

		// ── Pre-calentar textura de splash ──────────────────────────────────
		// CRÍTICO: cargar la textura de splash durante create() para que quede
		// registrada en PathsCache._currentGraphics. Sin esto, al volver del
		// ChartingState la primera vez que se intenta usar el splash el atlas
		// puede estar invalidado y tardar un frame extra en recargarse, haciendo
		// que el primer splash sea invisible.
		try
		{
			NoteSkinSystem.getSplashTexture(); // carga y cachea la textura activa
		}
		catch (e:Dynamic)
		{
			trace('[PlayState] Warning: could not pre-warm splash texture: $e');
		}

		// ── Pre-poblar el pool de splashes ───────────────────────────────────
		// Igual que Nightmare Engine: crear un splash "dummy" para que el primer
		// hit de nota no tarde en instanciar el objeto.
		if (grpNoteSplashes != null && grpNoteSplashes.length == 0)
		{
			try
			{
				var warmSplash = new NoteSplash();
				warmSplash.cameras = [camHUD];
				warmSplash.kill(); // matar inmediatamente → queda en pool listo
				grpNoteSplashes.add(warmSplash);
			}
			catch (e:Dynamic)
			{
				trace('[PlayState] Warning: could not pre-warm splash pool: $e');
			}
		}

		// ── Pre-calentar texturas de hold cover (las 4 direcciones) ────────
		// Sin esto, el primer hold note del juego provoca un hitch mientras
		// carga el atlas desde disco.
		var coverColors = ["Purple", "Blue", "Green", "Red"];
		for (color in coverColors)
		{
			try
			{
				NoteSkinSystem.getHoldCoverTexture(color);
			}
			catch (e:Dynamic)
			{
				trace('[PlayState] Warning: could not pre-warm holdCover$color texture: $e');
			}
		}

		// ── Pre-poblar el pool de hold covers y registrarlos en el renderer ──
		// CRÍTICO: los covers se añaden tanto a grpHoldCovers (para que Flixel los
		// actualice/dibuje) como al holdCoverPool del renderer (para que los
		// reutilice sin crear nuevos objetos ni recargar animaciones en runtime).
		if (grpHoldCovers != null && grpHoldCovers.length == 0)
		{
			for (i in 0...4)
			{
				try
				{
					var warmCover = new NoteHoldCover();
					warmCover.cameras = [camHUD];
					warmCover.setup(0, 0, i);
					warmCover.kill();
					grpHoldCovers.add(warmCover);
					// Registrar en el pool del renderer para reutilización sin hitch
					if (noteManager != null && noteManager.renderer != null)
						noteManager.renderer.holdCoverPool.push(warmCover);
				}
				catch (e:Dynamic)
				{
					trace('[PlayState] Warning: could not pre-warm holdCover pool dir $i: $e');
				}
			}
		}

		// Registrar los covers pre-creados en el pool interno del renderer
		if (noteManager != null && noteManager.renderer != null)
		{
			for (cover in grpHoldCovers.members)
				if (cover != null)
					noteManager.renderer.registerHoldCoverInPool(cover);
		}

		// ── Pre-warm note sprite pool ─────────────────────────────────────────
		// Create a small batch of Note objects (normal + sustain) so the FIRST
		// notes that appear in gameplay are recycled from the pool rather than
		// allocated cold, eliminating the hitch on the opening notes.
		if (noteManager != null && noteManager.renderer != null)
			noteManager.renderer.prewarmPools(8, 16);

		trace('[PlayState] Note + Splash + HoldCover textures pre-warmed');
	}

	public var startedCountdown:Bool = false;

	public function startCountdown():Void
	{
		if (scriptsEnabled)
		{
			var result = ScriptHandler.callOnScriptsReturn('onCountdownStarted', ScriptHandler._argsEmpty, false);
			if (result == true)
				return; // Script canceló el countdown
		}

		if (startedCountdown)
		{
			return;
		}

		// ── Intro video (meta.json: "introVideo": "my-video") ─────────────────
		// ── Intro sprite cutscene (meta.json: "introCutscene": "my-cutscene") ────
		if (metaData != null && metaData.introCutscene != null && isStoryMode)
		{
			final cutKey  = metaData.introCutscene;
			metaData.introCutscene = null; // evitar loop
			if (SpriteCutscene.exists(cutKey, SONG?.song?.toLowerCase()))
			{
				inCutscene = true;
				SpriteCutscene.create(this, cutKey, SONG?.song?.toLowerCase(), function()
				{
					inCutscene = false;
					startCountdown();
				});
				return;
			}
		}

		// If there is a defined introduction video, it plays BEFORE the dialogue/countdown.
		if (metaData != null && metaData.introVideo != null && isStoryMode)
		{
			final vidKey = metaData.introVideo;
			metaData.introVideo = null; // avoid loop if called again

			if (VideoManager._resolvePath(vidKey) != null)
			{
				inCutscene = true;
				VideoManager.playCutscene(vidKey, function()
				{
					inCutscene = false;

					fixInstandVocals();

					startCountdown(); // continuar flujo normal
				});
				return;
			}
		}

		if (checkForDialogue('intro') && isStoryMode)
		{
			inCutscene = true;

			showDialogue('intro', function()
			{
				// CRÍTICO: Restaurar FlxG.sound.music con el instrumental de la canción
				// El diálogo pudo haber usado FlxG.sound.music, así que lo restauramos
				fixInstandVocals();
				// Cuando termina el diálogo, ejecutar el countdown
				executeCountdown();
			});
			return;
		}
		else
			executeCountdown();
	}

	function fixInstandVocals():Void
	{
		final _diffSuffix:String = (SONG.instSuffix != null && SONG.instSuffix != '') ? '-' + SONG.instSuffix : funkin.data.CoolUtil.difficultySuffix();
		if (FlxG.sound.music == null || !FlxG.sound.music.active)
			FlxG.sound.music = Paths.loadInst(SONG.song, _diffSuffix);
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.volume = 0;
			FlxG.sound.music.pause();
		}

		// CRÍTICO: Recargar las vocales también
		if (vocals != null)
		{
			FlxG.sound.list.remove(vocals, true);
			vocals.stop();
			vocals.destroy();
			vocals = null;
		}
		_cleanPerCharVocals();

		if (SONG.needsVoices)
		{
			_usingPerCharVocals = _tryLoadPerCharVocals(_diffSuffix);
			if (!_usingPerCharVocals)
				vocals = Paths.loadVoices(SONG.song, _diffSuffix);
		}

		if (!_usingPerCharVocals)
		{
			if (vocals == null)
				vocals = new FlxSound();
			vocals.volume = 0;
			vocals.pause();
			FlxG.sound.list.add(vocals);
		}
	}

	public function executeCountdown():Void
	{
		isCutscene = false;

		// ✨ CHART TESTING: Si hay un tiempo de inicio específico, skipear countdown
		if (startFromTime != null)
		{
			// Verificar que la música esté cargada
			if (FlxG.sound.music == null)
			{
				startFromTime = null;
				// Continuar con countdown normal como fallback
			}
			else
			{
				var targetTime = startFromTime; // Guardar el tiempo antes de resetear

				// Configurar estado del juego
				startingSong = false;
				startedCountdown = true;

				// Resetear startFromTime inmediatamente
				startFromTime = null;

				// 2. Limpiar cualquier nota que ya esté en el grupo activo por error
				notes.forEachAlive(function(note:Note)
				{
					if (note.strumTime < targetTime - 100)
					{
						note.kill();
						notes.remove(note, true);
					}
				});

				// 3. Limpiar el buffer de entrada para evitar inputs residuales
				if (inputHandler != null)
				{
					inputHandler.resetMash();
					inputHandler.clearBuffer();
				}

				// ✨ Usar un delay para asegurar que la música esté lista
				new FlxTimer().start(0.2, function(tmr:FlxTimer)
				{
					if (FlxG.sound.music == null)
					{
						return;
					}

					// Configurar callbacks y volumen
					FlxG.sound.music.volume = 1;
					FlxG.sound.music.onComplete = endSong;

					// ✨ CRITICAL: Primero REPRODUCIR, luego setear el tiempo
					_safePlay(FlxG.sound.music);

					// Ahora setear el tiempo DESPUÉS de play()
					FlxG.sound.music.time = targetTime;
					var actualTime = FlxG.sound.music.time;

					// Verificar que el tiempo se haya seteado correctamente
					if (Math.abs(actualTime - targetTime) > 100)
					{
						FlxG.sound.music.time = targetTime;
						actualTime = FlxG.sound.music.time;
					}

					// Setear tiempo para vocals
					if (_usingPerCharVocals)
					{
						for (snd in vocalsPerChar)
						{
							if (snd == null) continue;
							snd.volume = 1;
							_safePlay(snd);
							snd.time = targetTime;
						}
					}
					else if (vocals != null)
					{
						vocals.volume = 1;
						_safePlay(vocals);
						vocals.time = targetTime;
					}

					// Actualizar Conductor.songPosition
					Conductor.songPosition = actualTime;
				});

				return;
			}
		}

		// Countdown normal
		Conductor.songPosition = -Conductor.crochet * 5;
		startingSong = true;
		startedCountdown = true;

		// FIX: Re-aplicar 'static' en todos los strums justo antes de que
		// empiece el countdown para garantizar que los offsets de skin
		// (centerOffsets + _animOffsets['static']) estén correctos desde el
		// primer frame visible, independientemente de si el scale del grupo
		// o la skin se ajustaron después del constructor.
		for (group in strumsGroups)
		{
			group.strums.forEach(function(s:FlxSprite)
			{
				if (Std.isOfType(s, funkin.gameplay.notes.StrumNote))
					cast(s, funkin.gameplay.notes.StrumNote).playAnim('static', true);
			});
		}

		countdown.start(function()
		{
			// onComplete: el countdown terminó, el juego puede comenzar
			// (PlayState ya maneja esto en su update loop revisando startingSong)
		});
	}

	override public function update(elapsed:Float)
	{
		// ── Audio-boot FPS restore ────────────────────────────────────────────
		// After _safePlay lowers FPS to ensure ≥2048 SampleDataEvent samples,
		// wait a few frames so the audio backend can initialise its buffers,
		// then restore the user's target FPS.
		if (_audioBootFrames > 0)
		{
			_audioBootFrames--;
			if (_audioBootFrames == 0 && _audioBootSavedFps > 0)
			{
				final main = Std.downcast(openfl.Lib.current.getChildAt(0), Main);
				if (main != null)
					main.setMaxFps(_audioBootSavedFps);
				else
					openfl.Lib.current.stage.frameRate = _audioBootSavedFps;
				_audioBootSavedFps = 0;
			}
		}
		// ─────────────────────────────────────────────────────────────────────

		if (scriptsEnabled)
		{
			ScriptHandler._argsUpdate[0] = elapsed;
			ScriptHandler.callOnScripts('onUpdate', ScriptHandler._argsUpdate);
		}

		// ── Frame-lag protección (no auto-pausa) ─────────────────────────────
		// Si el frame tardó más de 200ms (p.ej. tras un miss con sonidos recién
		// cargados, GC spike, etc.) simplemente recortamos elapsed a 1 frame para
		// que la física/conductor no salte. Esto evita el "lagazo al fallar" que
		// antes abría el pause menu automáticamente y rompía el flujo de juego.
		if (elapsed > 0.2)
			elapsed = 1.0 / 60.0;
		// ─────────────────────────────────────────────────────────────────────

		// Update ModChart
		if (modChartManager != null && !paused && generatedMusic)
			modChartManager.update(Conductor.songPosition);

		super.update(elapsed);

		if (optimizationManager != null)
			optimizationManager.update(elapsed);

		// ═══ REWIND RESTART — actualizar cada frame mientras se rebobina ════
		if (isRewinding)
		{
			_rewindTimer += elapsed;
			var t:Float = Math.min(1.0, _rewindTimer / _rewindDuration);

			// Ease: rápido al inicio, desacelera al final (efecto cassette)
			var eased:Float = flixel.tweens.FlxEase.quadIn(t);
			Conductor.songPosition = _rewindFromPos + (_rewindToPos - _rewindFromPos) * eased;

			// Actualizar posiciones de notas para el efecto visual de retroceso
			if (noteManager != null)
				noteManager.updatePositionsForRewind(Conductor.songPosition);

			// Mantener cámara y HUD activos durante el rewind
			if (cameraController != null)
				cameraController.update(elapsed);
			if (uiManager != null)
				uiManager.update(elapsed);

			// Cuando termina el rewind, resetear y arrancar el countdown
			if (t >= 1.0)
				_finishRestart();

			return; // saltar toda la lógica de gameplay normal
		}
		// ════════════════════════════════════════════════════════════════════
		if (!paused && !inCutscene)
		{
			if (startingSong && startedCountdown)
			{
				// Durante countdown, usar tiempo basado en elapsed
				Conductor.songPosition += FlxG.elapsed * 1000;
			}
			else if (FlxG.sound.music != null && FlxG.sound.music.playing)
			{
				// Durante la canción, sincronizar con la música
				Conductor.songPosition = FlxG.sound.music.time;
			}
		}

		// Hooks — iteración sobre arrays cacheados (sin overhead de Map iterator)
		for (hook in _updateHookArr)
			hook(elapsed);

		// Update controllers
		if (!paused && !inCutscene)
		{
			// Update characters
			characterController.update(elapsed);

			// Update camera — el target se controla por eventos (Camera Follow)
			cameraController.update(elapsed);

			// Update note manager
			if (generatedMusic)
			{
				// Sincronizar teclas al noteManager para deteccion de hold-miss
				if (inputHandler != null && noteManager != null)
				{
					noteManager.playerHeld[0] = inputHandler.held[0];
					noteManager.playerHeld[1] = inputHandler.held[1];
					noteManager.playerHeld[2] = inputHandler.held[2];
					noteManager.playerHeld[3] = inputHandler.held[3];
				}
				noteManager.update(Conductor.songPosition);
			}

			// Update input
			if (boyfriend != null && !boyfriend.stunned)
			{
				inputHandler.update();
				inputHandler.processInputs(notes);
				inputHandler.processSustains(sustainNotes);
				updatePlayerStrums();

				if (paused)
					inputHandler.clearBuffer();

				// checkMisses() eliminado: NoteManager.updateActiveNotes() ya detecta tooLate
				// y llama missNote() en el mismo frame — hacer checkMisses() después
				// causaba que las notas ya hubieran sido removidas (race condition).
			}

			// Update UI
			uiManager.update(elapsed);

			// Sync legacy stats
			syncLegacyStats();

			// Check death
			if (gameState.isDead() || FlxG.keys.anyJustPressed(inputHandler.killBind))
				gameOver();

			// NOTA: El CPU hold cleanup con key >= 4 fue removido — noteData siempre
			// es 0-3, por lo que esa condición era dead code. NoteManager gestiona
			// internamente los holds del CPU.
		}

		if (SONG.needsVoices && !inCutscene)
		{
			if (_usingPerCharVocals)
			{
				// Las per-char vocals se controlan directamente en los callbacks de notas
			}
			else if (vocals != null && vocals.volume < 1)
			{
				vocals.volume += elapsed * 2;
				if (vocals.volume > 1)
					vocals.volume = 1;
			}
		}

		// Abrir menú de pausa con ENTER.
		// Durante un video (VideoManager.isPlaying) siempre se permite,
		// sin importar startedCountdown ni canPause, para poder usar "Skip Cutscene".
		if (controls.PAUSE && !paused)
		{
			if (VideoManager.isPlaying)
				pauseMenu();
			else if (startedCountdown && canPause && !inCutscene)
				pauseMenu();
		}

		if (FlxG.keys.justPressed.SEVEN)
		{
			FlxG.mouse.visible = true;
			StateTransition.switchState(new ChartingState());
		}

		if (FlxG.keys.justPressed.F8 && startedCountdown && canPause)
		{
			// Transferir datos al editor vía statics ANTES de hacer el switch
			// (PlayState.destroy() se llamará después del switch)
			ModChartEditorState.pendingManager = modChartManager;
			ModChartEditorState.pendingStrumsData = strumsGroups.map(function(g) return g.data);
			// Nullear para que PlayState.destroy() no destruya el manager que el editor necesita
			modChartManager = null;

			FlxG.mouse.visible = true;
			StateTransition.switchState(new ModChartEditorState());
		}

		/*
			if (FlxG.keys.justPressed.EIGHT)
			{
				StateTransition.switchState(new StageEditor());
			}

			if (FlxG.keys.justPressed.NINE)
			{
				persistentUpdate = false;
				persistentDraw = true;
				paused = true;
				StateTransition.switchState(new DialogueEditor());
		}*/

		// Song time - SINCRONIZACIÓN MEJORADA
		if (startingSong && startedCountdown && !inCutscene)
		{
			if (FlxG.sound.music != null && Conductor.songPosition >= 0)
			{
				startSong();
			}
		}

		if (scriptsEnabled && !paused)
		{
			EventManager.update(Conductor.songPosition);
			ScriptHandler._argsUpdatePost[0] = elapsed;
			ScriptHandler.callOnScripts('onUpdatePost', ScriptHandler._argsUpdatePost);
		}
	}

	/**
	 * NUEVO: Debug controls
	 */
	private function updateDebugControls():Void
	{
		// F3: Toggle stats
		if (FlxG.keys.justPressed.F3)
		{
			showDebugStats = !showDebugStats;
			if (debugText != null)
				debugText.visible = showDebugStats;
		}
	}

	function pauseMenu()
	{
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		// BUGFIX: FlxTimer corre via FlxTimerManager (plugin global) y sigue
		// contando aunque persistentUpdate=false. Pausar el timer del countdown
		// para que no siga disparando ticks mientras el juego está en pausa.
		if (countdown != null && countdown.running)
			countdown.pause();

		// Si hay un video activo NO pausamos FlxG.sound.music ni llamamos FlxG.sound.pause()
		// porque FlxG.sound.pause() pondría _paused=true en music, y luego FlxG.sound.resume()
		// en _doResume() lo arrancaría automáticamente MIENTRAS el video sigue corriendo.
		if (VideoManager.isPlaying)
		{
			VideoManager.pause(); // baja el bitmap debajo del canvas de Flixel
		}
		else
		{
			FlxG.sound.pause(); // pausa música + sfx normalmente
		}

		// 1 / 1000 chance for Gitaroo Man easter egg
		if (FlxG.random.bool(0.1))
		{
			StateTransition.switchState(new GitarooPause());
		}
		else
		{
			openSubState(new PauseSubState(inCutscene && VideoManager.isPlaying));
		}
	}

	/**
	 * Start song - SINCRONIZACIÓN MEJORADA
	 */
	private function startSong():Void
	{
		startingSong = false;

		// Iniciar música e instrumental juntos
		if (FlxG.sound.music != null && !inCutscene)
		{
			// La música ya está cargada, solo necesitamos reproducirla
			FlxG.sound.music.volume = 1;
			FlxG.sound.music.time = 0;
			_safePlay(FlxG.sound.music);
			FlxG.sound.music.onComplete = endSong;
		}

		// Sincronizar vocales con música
		if (SONG.needsVoices && !inCutscene)
		{
			if (_usingPerCharVocals)
			{
				for (snd in vocalsPerChar)
				{
					if (snd == null) continue;
					snd.volume = 1;
					snd.time = 0;
					_safePlay(snd);
				}
			}
			else if (vocals != null)
			{
				vocals.volume = 1;
				vocals.time = 0;
				_safePlay(vocals);
			}
		}

		#if desktop
		DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconRPC, true, FlxG.sound.music?.length ?? 0);
		#end

		if (scriptsEnabled)
			ScriptHandler.callOnScripts('onSongStart', ScriptHandler._argsEmpty);
	}

	/**
	 * Update player strums
	 */
	private function updatePlayerStrums():Void
	{
		// ✅ Si tenemos StrumsGroup, usarlo directamente
		if (playerStrumsGroup != null)
		{
			for (i in 0...4)
			{
				if (!isPlayingConfirm(i))
				{
					if (inputHandler.pressed[i])
					{
						// Tecla recién pulsada: activar pressed inmediatamente
						playerStrumsGroup.playPressed(i);
					}
					else if (inputHandler.held[i])
					{
						// Tecla mantenida: si el confirm ya terminó y el strum volvió a
						// 'static', cambiarlo a 'pressed' para que no se vea en reposo
						// mientras el jugador sigue pulsando.
						var strum = playerStrumsGroup.getStrum(i);
						if (strum != null
							&& strum.animation != null
							&& strum.animation.curAnim != null
							&& strum.animation.curAnim.name == 'static')
						{
							playerStrumsGroup.playPressed(i);
						}
					}
				}

				if (inputHandler.released[i])
				{
					playerStrumsGroup.resetStrum(i);
				}
			}
			return;
		}

		// ✅ Fallback al sistema antiguo
		playerStrums.forEach(function(spr:FlxSprite)
		{
			// Verificar que animation y curAnim no sean null
			if (spr.animation == null || spr.animation.curAnim == null)
				return;

			if (Std.isOfType(spr, StrumNote))
			{
				var strumNote:StrumNote = cast(spr, StrumNote);
				var curAnim = strumNote.animation.curAnim.name;

				if (curAnim != 'confirm')
				{
					if (inputHandler.pressed[spr.ID])
					{
						strumNote.playAnim('pressed');
					}
					else if (inputHandler.held[spr.ID] && curAnim == 'static')
					{
						// Confirm terminó y el jugador sigue pulsando → mostrar pressed
						strumNote.playAnim('pressed');
					}
				}

				if (inputHandler.released[spr.ID])
				{
					strumNote.playAnim('static');
				}
			}
			else
			{
				// Fallback para FlxSprite genérico
				var curAnim = spr.animation.curAnim.name;

				if (curAnim != 'confirm')
				{
					if (inputHandler.pressed[spr.ID])
					{
						spr.animation.play('pressed');
					}
					else if (inputHandler.held[spr.ID] && curAnim == 'static')
					{
						spr.animation.play('pressed');
					}
				}

				if (inputHandler.released[spr.ID])
				{
					spr.animation.play('static');
					spr.centerOffsets();
				}
			}
		});
	}

	/**
	 * Helper para verificar si un strum está tocando 'confirm'
	 */
	private function isPlayingConfirm(direction:Int):Bool
	{
		if (playerStrumsGroup != null)
		{
			var strum = playerStrumsGroup.getStrum(direction);
			if (strum != null && strum.animation != null && strum.animation.curAnim != null)
			{
				return strum.animation.curAnim.name == 'confirm';
			}
		}
		return false;
	}

	/**
	 * NUEVO: Callback cuando se suelta una tecla (para hold notes)
	 */
	// ── Android: botón "atrás" del sistema ──────────────────────────────────
	#if android
	private function _onAndroidKeyDown(keyCode:Int, modifier:Int):Void
	{
		// KeyCode 27 = ESCAPE (mapeado al botón atrás en Android por OpenFL/Lime)
		if (keyCode == 27 && !paused)
			openSubState(new PauseSubState(false));
	}
	#end

	private function onKeyRelease(direction:Int):Void
	{
		// Validar dirección
		if (direction < 0 || direction > 3)
		{
			return;
		}

		// Notificar al note manager que se soltó una hold note
		if (noteManager != null)
		{
			noteManager.releaseHoldNote(direction);
		}

		// Limpiar tracking local
		if (heldNotes.exists(direction))
		{
			heldNotes.remove(direction);
		}
		else
		{
		}
	}

	/**
	 * Callback: Player hit note
	 */
	private function onPlayerNoteHit(note:Note):Void
	{
		// Process hit
		var noteDiff:Float = Math.abs(note.strumTime - Conductor.songPosition);
		// Regular note - GameState calcula el rating automáticamente
		var rating:String = gameState.processNoteHit(noteDiff, note.isSustainNote);
		if (scriptsEnabled)
		{
			ScriptHandler._argsNote[0] = note;
			ScriptHandler._argsNote[1] = rating;
			var cancel = ScriptHandler.callOnScriptsReturn('onPlayerNoteHit', ScriptHandler._argsNote, false);
			if (cancel == true)
				return;
		}

		// NoteType: onPlayerHit — true cancela la lógica normal
		var _ntCancelled:Bool = funkin.gameplay.notes.NoteTypeManager.onPlayerHit(note, this);

		if (!note.wasGoodHit)
		{
			if (!_ntCancelled)
			{
				if (!note.isSustainNote)
				{
					var health = getHealthForRating(rating);
					gameState.modifyHealth(health);
					uiManager.showRatingPopup(rating, gameState.combo);
					if (FlxG.save.data.hitsounds && rating == 'sick')
						playHitSound();
				}
				else
				{
					gameState.modifyHealth(0.023);
				}
			} // end !_ntCancelled

			// Animate character - BUSCAR ÍNDICE DEL JUGADOR POR TIPO
			var playerCharIndex:Int = characterController.findPlayerIndex();
			if (playerCharIndex < 0)
				playerCharIndex = 2; // fallback legacy
			if (characterSlots.length > playerCharIndex)
			{
				characterController.singByIndex(playerCharIndex, note.noteData);
				var playerChar = characterController.getCharacter(playerCharIndex);
				if (playerChar != null)
					cameraController.applyNoteOffset(playerChar, note.noteData);
				else if (boyfriend != null)
					cameraController.applyNoteOffset(boyfriend, note.noteData);
			}
			else if (boyfriend != null)
			{
				characterController.sing(boyfriend, note.noteData);
				cameraController.applyNoteOffset(boyfriend, note.noteData);
			}

			noteManager.hitNote(note, rating);
			if (_usingPerCharVocals)
			{
				for (k in _vocalsPlayerKeys)
				{
					var snd = vocalsPerChar.get(k);
					if (snd != null) snd.volume = 1;
				}
			}
			else
			{
				vocals.volume = 1;
			}

			for (hook in _noteHitHookArr)
				hook(note);
		}

		// NoteType: onPlayerHitPost (siempre)
		funkin.gameplay.notes.NoteTypeManager.onPlayerHitPost(note, this);

		if (scriptsEnabled)
		{
			ScriptHandler._argsNote[0] = note;
			ScriptHandler._argsNote[1] = rating;
			ScriptHandler.callOnScripts('onPlayerNoteHitPost', ScriptHandler._argsNote);
		}
	}

	/**
	 * Callback: Player miss note
	 */
	private function onPlayerNoteMiss(missedNote:funkin.gameplay.notes.Note):Void
	{
		if (scriptsEnabled)
		{
			ScriptHandler._argsNote[0] = missedNote;
			ScriptHandler._argsNote[1] = null;
			var cancel = ScriptHandler.callOnScriptsReturn('onPlayerNoteMiss', ScriptHandler._argsNote, false);
			if (cancel == true)
			{
				return;
			}
		}
		// Extraer dirección
		var direction:Int = missedNote != null ? missedNote.noteData : 0;

		// NoteType: onMiss — true cancela la lógica normal de miss
		var _ntMissCancelled:Bool = missedNote != null ? funkin.gameplay.notes.NoteTypeManager.onMiss(missedNote, this) : false;

		if (!_ntMissCancelled)
		{
			// Process miss
			gameState.processMiss();
			gameState.modifyHealth(PlayStateConfig.MISS_HEALTH);
			// Usar el pool de miss sounds pre-cacheados para evitar lag de disco
			if (_missSounds.length > 0)
			{
				var snd = _missSounds[_missSoundIdx % MISS_SOUND_POOL_SIZE];
				_missSoundIdx++;
				if (snd != null)
				{
					snd.volume = FlxG.random.float(0.1, 0.2);
					snd.play(true);
				}
			}
			else
			{
				FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
			}
		}

		// Animate - BUSCAR ÍNDICE DEL JUGADOR POR TIPO
		var playerCharIndex:Int = characterController.findPlayerIndex();
		if (playerCharIndex < 0)
			playerCharIndex = 2; // fallback legacy
		if (characterSlots.length > playerCharIndex)
		{
			var slot = characterSlots[playerCharIndex];
			if (slot != null)
				characterController.missByIndex(playerCharIndex, direction);
		}
		else if (boyfriend != null)
		{
			var anims = ['LEFT', 'DOWN', 'UP', 'RIGHT'];
			boyfriend.playAnim('sing' + anims[direction] + 'miss', true);
		}

		// GF sad anim - buscar por tipo (funciona aunque GF no esté en índice 0)
		var gfIdx = characterController.findGFIndex();
		var gfChar = gfIdx >= 0 ? characterController.getCharacter(gfIdx) : gf;
		if (gfChar != null && gfChar.animOffsets.exists('sad'))
			gfChar.playAnim('sad', true);

		if (!_ntMissCancelled)
			uiManager.showMissPopup();

		if (_usingPerCharVocals)
		{
			for (k in _vocalsPlayerKeys)
			{
				var snd = vocalsPerChar.get(k);
				if (snd != null) snd.volume = 0;
			}
		}
		else
		{
			vocals.volume = 0;
		}

		if (scriptsEnabled)
		{
			ScriptHandler._argsOne[0] = direction;
			ScriptHandler.callOnScripts('onPlayerNoteMissPost', ScriptHandler._argsOne);
			// Disparar onNoteMiss en el script del personaje del jugador
			if (boyfriend != null)
			{
				ScriptHandler._argsAnim[0] = direction;
				ScriptHandler._argsAnim[1] = null;
				ScriptHandler.callOnCharacterScripts(boyfriend.curCharacter, 'onNoteMiss', ScriptHandler._argsAnim);
			}
		}
	}

	/**
	 * Callback: CPU hit note
	 */
	private function onCPUNoteHit(note:Note):Void
	{
		if (scriptsEnabled)
		{
			ScriptHandler._argsNote[0] = note;
			ScriptHandler._argsNote[1] = null;
			ScriptHandler.callOnScripts('onOpponentNoteHit', ScriptHandler._argsNote);
			ScriptHandler._argsNote[0] = 'dad';
			ScriptHandler._argsNote[1] = note.noteData;
			ScriptHandler.callOnScripts('onCharacterSing', ScriptHandler._argsNote);
		}

		// NoteType: onCPUHit
		funkin.gameplay.notes.NoteTypeManager.onCPUHit(note, this);

		// Habilitar zoom al ritmo. Se respeta el flag "disableCameraZoom" del
		// meta.json (reemplaza el hardcode SONG.song != 'Tutorial').
		if (metaData == null || !metaData.disableCameraZoom)
			cameraController.zoomEnabled = true;

		var altAnim:String = getHasAltAnim(curStep) ? '-alt' : '';

		// ✅ FIX: Buscar índice del oponente por TIPO (no hardcodeado a 1)
		// Soporte para gfSing y múltiples grupos CPU
		var section = getSectionAsClass(curStep);
		if (section != null)
		{
			var charIndices = section.getActiveCharacterIndices(1, 2); // (dadIndex, bfIndex)

			// Índice dinámico del oponente
			var dadIndex:Int = characterController.findOpponentIndex();
			if (dadIndex < 0)
				dadIndex = 1; // fallback legacy

			// Soporte sección gfSing
			if (section.gfSing == true)
			{
				characterController.singGF(note.noteData, altAnim);
			}
			else if (characterSlots.length > dadIndex)
			{
				var dadSlot = characterSlots[dadIndex];
				if (dadSlot != null && dadSlot.isActive && dadSlot.character != null)
					characterController.singByIndex(dadIndex, note.noteData, altAnim);
			}
			else if (dad != null)
			{
				characterController.sing(dad, note.noteData, altAnim);
			}

			// Routing adicional para múltiples grupos CPU
			if (note.strumsGroupIndex > 0 && strumsGroups.length > note.strumsGroupIndex)
			{
				var sg = strumsGroups[note.strumsGroupIndex].data.id;
				var extraIdx = characterController.findByStrumsGroup(sg);
				if (extraIdx >= 0 && extraIdx != dadIndex)
					characterController.singByIndex(extraIdx, note.noteData, altAnim);
			}

			// Camera offset
			if (charIndices.length > 0)
			{
				var activeChar = characterController.getCharacter(charIndices[0]);
				if (activeChar != null)
					cameraController.applyNoteOffset(activeChar, note.noteData);
				else if (dad != null)
					cameraController.applyNoteOffset(dad, note.noteData);
			}
			else if (dad != null)
			{
				cameraController.applyNoteOffset(dad, note.noteData);
			}
		}
		else
		{
			// FALLBACK: Si la sección es null, animar solo al oponente (por tipo)
			var dadIndex:Int = characterController.findOpponentIndex();
			if (dadIndex < 0)
				dadIndex = 1; // fallback legacy

			if (characterSlots.length > dadIndex)
			{
				var dadSlot = characterSlots[dadIndex];
				if (dadSlot != null && dadSlot.isActive && dadSlot.character != null)
				{
					characterController.singByIndex(dadIndex, note.noteData, altAnim);
				}
			}
			else if (dad != null)
			{
				// Fallback al sistema legacy
				characterController.sing(dad, note.noteData, altAnim);
			}

			// Fallback para offset de cámara
			if (dad != null)
			{
				cameraController.applyNoteOffset(dad, note.noteData);
			}
		}

		// Vocals
		if (SONG.needsVoices)
		{
			if (_usingPerCharVocals)
			{
				for (k in _vocalsOpponentKeys)
				{
					var snd = vocalsPerChar.get(k);
					if (snd != null) snd.volume = 1;
				}
			}
			else
			{
				vocals.volume = 1;
			}
		}
	}

	/**
	 * Get health amount for rating
	 */
	private function getHealthForRating(rating:String):Float
	{
		var data = RatingManager.getByName(rating);
		return data != null ? data.health : 0.0;
	}

	// ── Hitsound pool (evita new FlxSound cada golpe) ─────────────────────
	private var _hitSounds:Array<FlxSound> = [];
	private var _hitSoundIdx:Int = 0;
	// ── Miss sound pool (evita lag de disco en el primer miss) ─────────────
	private var _missSounds:Array<FlxSound> = [];
	private var _missSoundIdx:Int = 0;

	private static inline var HIT_SOUND_POOL_SIZE:Int = 4;
	private static inline var MISS_SOUND_POOL_SIZE:Int = 6; // 3 variantes × 2 slots

	private function initHitSoundPool():Void
	{
		_hitSounds = [];
		for (i in 0...HIT_SOUND_POOL_SIZE)
		{
			var snd = new FlxSound();
			try
			{
				snd.loadEmbedded(Paths.sound('hitsounds/hit-1'));
			}
			catch (_:Dynamic)
			{
			}
			snd.looped = false;
			FlxG.sound.list.add(snd);
			_hitSounds.push(snd);
		}

		// ── Pre-cachear sonidos de miss (evita lag de disco en el primer miss) ──
		_missSounds = [];
		for (i in 0...MISS_SOUND_POOL_SIZE)
		{
			var snd = new FlxSound();
			final variant = (i % 3) + 1; // missnote1, missnote2, missnote3
			try
			{
				snd.loadEmbedded(Paths.sound('missnote$variant'));
			}
			catch (_:Dynamic)
			{
			}
			snd.looped = false;
			FlxG.sound.list.add(snd);
			_missSounds.push(snd);
		}
	}

	/**
	 * Play hitsound — usa pool de FlxSound para evitar alloc por golpe
	 */
	private function playHitSound():Void
	{
		if (_hitSounds.length == 0)
			initHitSoundPool();
		var snd = _hitSounds[_hitSoundIdx % HIT_SOUND_POOL_SIZE];
		_hitSoundIdx++;
		if (snd == null)
			return;
		snd.volume = 1 + FlxG.random.float(-0.2, 0.2);
		snd.play(true);
	}

	/**
	 * Sync legacy stats — solo copia cuando algo cambió realmente.
	 * Se comparan score+misses como proxy rápido; si coinciden, el resto tampoco cambia.
	 */
	private function syncLegacyStats():Void
	{
		if (gameState.score == songScore && gameState.misses == misses)
			return; // nada cambió — evitar 7 asignaciones por frame
		songScore = gameState.score;
		misses = gameState.misses;
		sicks = gameState.sicks;
		goods = gameState.goods;
		bads = gameState.bads;
		shits = gameState.shits;
		accuracy = gameState.accuracy;
	}

	override function openSubState(SubState:FlxSubState)
	{
		if (paused)
		{
			if (scriptsEnabled)
			{
				var cancel = ScriptHandler.callOnScriptsReturn('onPause', ScriptHandler._argsEmpty, false);
				if (cancel == true)
					return;
			}

			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				if (_usingPerCharVocals)
				{
					for (snd in vocalsPerChar)
						if (snd != null) snd.pause();
				}
				else if (vocals != null)
					vocals.pause();
			}

			#if desktop
			updatePresence();
			#end
		}

		super.openSubState(SubState);
	}

	override function closeSubState()
	{
		if (paused)
		{
			var shouldResync = isPlaying && !isRewinding && FlxG.sound.music != null && !startingSong && !VideoManager.isPlaying;
			if (shouldResync)
			{
				// BUGFIX: Si el audio ya está reproduciéndose (PauseSubState llamó
				// FlxG.sound.resume() antes de close()), NO llamar resyncVocals():
				// _safePlay() baja el FPS a 20 por 6 frames para inicializar el
				// buffer de audio, lo que causa el spike de FPS visible al reanudar.
				// Cuando el audio ya está activo el buffer está inicializado — solo
				// hay que sincronizar la posición del Conductor.
				if (FlxG.sound.music.playing)
					Conductor.songPosition = FlxG.sound.music.time;
				else
					resyncVocals(); // audio detenido por algún motivo: resync completo
			}
			paused = false;

			// BUGFIX: Reanudar el timer del countdown si estaba corriendo cuando
			// se pausó. Sin esto el countdown queda congelado al volver del pause.
			if (countdown != null && countdown.running)
				countdown.resume();

			if (scriptsEnabled)
				ScriptHandler.callOnScripts('onResume', ScriptHandler._argsEmpty);
		}

		super.closeSubState();
	}

	/**
	 * Beat hit
	 */
	override function beatHit()
	{
		super.beatHit();

		// Hooks
		for (hook in _beatHookArr)
			hook(curBeat);

		if (currentStage != null)
			currentStage.beatHit(curBeat);

		if (modChartManager != null)
			modChartManager.onBeatHit(curBeat);

		if (scriptsEnabled)
			ScriptHandler._argsBeat[0] = curBeat;
		ScriptHandler.callOnScripts('onBeatHit', ScriptHandler._argsBeat);

		// Character dance
		characterController.danceOnBeat(curBeat);

		// Camera zoom
		if (curBeat % 4 == 0)
			cameraController.bumpZoom();

		// UI bump
		uiManager.onBeatHit(curBeat);
	}

	/**
	 * Step hit
	 */
	override function stepHit()
	{
		super.stepHit();

		// Hooks
		for (hook in _stepHookArr)
			hook(curStep);

		if (modChartManager != null)
			modChartManager.onStepHit(curStep);

		if (currentStage != null)
			currentStage.stepHit(curStep);

		if (scriptsEnabled)
		{
			ScriptHandler._argsStep[0] = curStep;
			ScriptHandler.callOnScripts('onStepHit', ScriptHandler._argsStep);

			// Section change
			var section = Math.floor(curStep / 16);
			if (section != cachedSectionIndex)
				ScriptHandler.callOnScripts('onSectionHit', [section]);
		}

		// Resync music - MEJORADO
		// Umbral de 20ms era demasiado agresivo: disparaba resyncVocals() en casi cada step
		// causando llamadas repetidas a FlxG.sound.music.play() que generaban stutters.
		// Ahora se usa 100ms y un cooldown de 8 steps para evitar resyncs demasiado frecuentes.
		if (FlxG.sound.music != null && Math.abs(FlxG.sound.music.time - Conductor.songPosition) > 100)
		{
			if (_resyncCooldown <= 0)
			{
				resyncVocals();
				_resyncCooldown = 8;
			}
		}
		if (_resyncCooldown > 0)
			_resyncCooldown--;
	}

	/**
	 * Resync vocals - MEJORADO
	 */
	function resyncVocals():Void
	{
		if (_usingPerCharVocals)
		{
			for (snd in vocalsPerChar) if (snd != null) snd.pause();
		}
		else if (SONG.needsVoices && vocals != null)
		{
			vocals.pause();
		}

		if (FlxG.sound.music != null)
		{
			_safePlay(FlxG.sound.music);
			Conductor.songPosition = FlxG.sound.music.time;
		}

		if (_usingPerCharVocals)
		{
			for (snd in vocalsPerChar)
			{
				if (snd == null) continue;
				snd.time = Conductor.songPosition;
				_safePlay(snd);
			}
		}
		else if (SONG.needsVoices && vocals != null)
		{
			vocals.time = Conductor.songPosition;
			_safePlay(vocals);
		}
	}

	/**
	 * Plays a FlxSound safely, capping FPS so OpenFL's SampleDataEvent buffer ≥ 2048 samples.
	 *
	 * ROOT CAUSE
	 * ----------
	 * OpenFL computes the streaming audio buffer as:
	 *   bufferSize = ceil(sampleRate / stage.frameRate)   [samples per callback]
	 * Flash spec requires bufferSize ∈ [2048, 8192].
	 * At "unlimited" FPS (stage.frameRate = 1000):  ceil(44100/1000) = 45  → THROWS.
	 * At fps = 20:                                   ceil(44100/20)  = 2205 → OK.
	 *
	 * WHY THE OLD ONE-LINE FIX FAILED
	 * ---------------------------------
	 * The old code set stage.frameRate = 20 synchronously and restored it right after
	 * play(). But OpenFL's audio backend dispatches SampleDataEvent asynchronously
	 * from its own timer / audio callback, so by the time the first buffer is actually
	 * requested, stage.frameRate was already back to 1000 → still 45 samples → THROWS.
	 *
	 * Additionally, Main.setMaxFps() controls *both* stage.frameRate *and*
	 * FlxG.drawFramerate. Setting only stage.frameRate left FlxG.drawFramerate at 1000,
	 * which some OpenFL paths read instead of (or in addition to) stage.frameRate.
	 *
	 * FIX
	 * ---
	 * 1. Use Main.setMaxFps(20) to lower BOTH stage.frameRate and FlxG.drawFramerate.
	 * 2. Call snd.play() while FPS is safely low.
	 * 3. Do NOT restore immediately. Instead, set _audioBootFrames = 6 so that
	 *    update() waits 6 rendered frames before restoring the target FPS.
	 *    6 frames at 20fps ≈ 300ms — enough for the audio backend to fire its first
	 *    SampleDataEvent callback and lock in the 2205-sample buffer size.
	 * 4. Multiple rapid _safePlay calls (music + vocalsBf + vocalsDad) reset the
	 *    counter each time but share one deferred restore, so the FPS dip is a
	 *    single ~300ms window regardless of how many sounds are started.
	 */
	function _safePlay(snd:FlxSound):Void
	{
		if (snd == null) return;
		#if (!html5 && !mobileC)
		final stage = openfl.Lib.current.stage;
		final currentFps:Int = Std.int(stage.frameRate);
		if (currentFps > 21)
		{
			// Only save the "real" target fps once (first call in a batch).
			// Subsequent calls in the same batch see fps=20 already set.
			if (_audioBootSavedFps <= 0)
				_audioBootSavedFps = currentFps;

			final main = Std.downcast(openfl.Lib.current.getChildAt(0), Main);
			if (main != null)
				main.setMaxFps(20);   // lowers stage.frameRate AND FlxG.drawFramerate
			else
				stage.frameRate = 20;
		}
		else if (_audioBootSavedFps <= 0)
		{
			// FPS ya está en 20 o menos — ocurre cuando una sesión anterior salió
			// antes de que update() restaurara el FPS (mid-countdown).
			// destroy() debería haberlo corregido, pero como defensa adicional:
			// recuperar el target real desde el save para que el restore funcione.
			final savedTarget:Int = (FlxG.save.data.fpsTarget != null) ? Std.int(FlxG.save.data.fpsTarget) : 60;
			_audioBootSavedFps = savedTarget > 21 ? savedTarget : 60;
		}
		try snd.play() catch (e:Dynamic) trace('[PlayState] _safePlay error: $e');
		// Reset (or start) the deferred-restore countdown.
		// update() will call setMaxFps(_audioBootSavedFps) after 6 frames.
		_audioBootFrames = 6;
		#else
		try snd.play() catch (e:Dynamic) trace('[PlayState] _safePlay error: $e');
		#end
	}

	/**
	 * End song
	 */
	public function endSong():Void
	{
		if (scriptsEnabled)
		{
			ScriptHandler.callOnScripts('onSongEnd', ScriptHandler._argsEmpty);
		}

		canPause = false;
		if (FlxG.sound.music != null)
			FlxG.sound.music.volume = 0;
		if (_usingPerCharVocals)
		{
			for (snd in vocalsPerChar) if (snd != null) snd.volume = 0;
		}
		else if (vocals != null)
			vocals.volume = 0;
		isPlaying = false;

		if (SONG.validScore)
		{
			final diffSuffix = funkin.data.CoolUtil.difficultySuffix();
			Highscore.saveScore(SONG.song, songScore, diffSuffix);
			Highscore.saveRating(SONG.song, gameState.accuracy, diffSuffix);
		}

		// ── Outro sprite cutscene (meta.json: "outroCutscene": "my-cutscene") ──
		if (metaData != null && metaData.outroCutscene != null)
		{
			final cutKey  = metaData.outroCutscene;
			metaData.outroCutscene = null;
			if (SpriteCutscene.exists(cutKey, SONG?.song?.toLowerCase()))
			{
				isCutscene = true;
				SpriteCutscene.create(this, cutKey, SONG?.song?.toLowerCase(), function()
				{
					isCutscene = false;
					if (showOutroDialogue() && isStoryMode) return;
					continueAfterSong();
				});
				return;
			}
		}

		// ── Outro video (meta.json: "outroVideo": "mi-video") ─────────────────
		if (metaData != null && metaData.outroVideo != null)
		{
			final vidKey = metaData.outroVideo;
			metaData.outroVideo = null; // evitar doble reproducción

			if (VideoManager._resolvePath(vidKey) != null)
			{
				isCutscene = true;
				VideoManager.playCutscene(vidKey, function()
				{
					isCutscene = false;
					if (showOutroDialogue() && isStoryMode)
						return;
					continueAfterSong();
				});
				return;
			}
		}

		if (showOutroDialogue() && isStoryMode)
		{
			return; // El diálogo manejará el resto
		}

		if (!isCutscene)
			continueAfterSong();
	}

	/**
	 * Game over
	 */
	function gameOver():Void
	{
		if (scriptsEnabled)
		{
			var cancel = ScriptHandler.callOnScriptsReturn('onGameOver', ScriptHandler._argsEmpty, false);
			if (cancel == true)
				return;
		}

		// ✅ Verificar que boyfriend exista
		if (boyfriend == null)
		{
			// Forzar game over de emergencia
			StateTransition.switchState(new funkin.menus.MainMenuState());
			return;
		}

		GameState.deathCounter++;

		boyfriend.stunned = true;
		persistentUpdate = false;
		persistentDraw = false;
		paused = true;

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		openSubState(new GameOverSubstate(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y, boyfriend));

		#if desktop
		DiscordClient.changePresence("GAME OVER", SONG.song + " (" + storyDifficultyText + ")", iconRPC);
		#end
	}

	// ====================================
	// MÉTODOS HELPER PARA SECCIONES
	// ====================================

	/**
	 * Devuelve un personaje buscando por nombre de character (e.g. "bf-pixel-enemy"),
	 * por índice numérico de slot (0=GF, 1=CPU, 2=Player), o por alias (bf/dad/gf).
	 * Útil para eventos "Play Anim" y scripts.
	 */
	public function getCharacterByName(name:String):Null<Character>
	{
		if (name == null || name == '')
			return null;
		var n = name.toLowerCase().trim();

		// Índice numérico
		var idx = Std.parseInt(n);
		if (idx != null && idx >= 0 && idx < characterSlots.length)
			return characterSlots[idx].character;

		// Alias comunes
		switch (n)
		{
			case 'bf', 'boyfriend', 'player', 'player1':
				return boyfriend;
			case 'dad', 'opponent', 'player2':
				return dad;
			case 'gf', 'girlfriend', 'player3':
				return gf;
		}

		// Nombre exacto de personaje en cualquier slot
		for (slot in characterSlots)
			if (slot.character != null && slot.character.curCharacter.toLowerCase() == n)
				return slot.character;

		return null;
	}

	/**
	 * Obtener sección actual (con cache)
	 */
	public function getSection(step:Int):SwagSection
	{
		var sectionIndex = Math.floor(step / 16);

		// Cache hit
		if (cachedSectionIndex == sectionIndex && cachedSection != null)
			return cachedSection;

		// Cache miss
		cachedSectionIndex = sectionIndex;
		cachedSection = (SONG.notes[sectionIndex] != null) ? SONG.notes[sectionIndex] : null;

		return cachedSection;
	}

	/**
	 * Convert SwagSection to Section class for accessing methods.
	 * OPTIMIZADO: reutiliza un único objeto Section en lugar de crear uno nuevo
	 * en cada llamada (esto se llama en cada nota del CPU → muchas veces por segundo).
	 */
	public function getSectionAsClass(step:Int):Section
	{
		final sectionIndex = Math.floor(step / 16);

		// Cache hit — misma sección, mismo objeto
		if (_cachedSectionClassIdx == sectionIndex && _cachedSectionClass != null)
			return _cachedSectionClass;

		final swagSection = getSection(step);

		if (swagSection == null)
		{
			_cachedSectionClassIdx = sectionIndex;
			_cachedSectionClass = null;
			return null;
		}

		// Reutilizar el objeto si ya existe, crear uno solo la primera vez
		if (_cachedSectionClass == null)
			_cachedSectionClass = new Section();

		_cachedSectionClass.sectionNotes = swagSection.sectionNotes;
		_cachedSectionClass.lengthInSteps = swagSection.lengthInSteps;
		_cachedSectionClass.typeOfSection = swagSection.typeOfSection;
		_cachedSectionClass.mustHitSection = swagSection.mustHitSection;
		_cachedSectionClass.characterIndex = swagSection.characterIndex != null ? swagSection.characterIndex : -1;
		_cachedSectionClass.strumsGroupId = swagSection.strumsGroupId;
		_cachedSectionClass.activeCharacters = swagSection.activeCharacters;

		_cachedSectionClassIdx = sectionIndex;
		return _cachedSectionClass;
	}

	/**
	 * Verificar si la sección es del jugador
	 */
	public function getMustHitSection(step:Int):Bool
	{
		var section = getSection(step);
		return section != null ? section.mustHitSection : true;
	}

	/**
	 * Verificar si hay animación alterna
	 */
	public function getHasAltAnim(step:Int):Bool
	{
		var section = getSection(step);
		return section != null ? section.altAnim : false;
	}

	// draw() eliminado: la versión anterior añadía sprites al GPURenderer
	// Y luego llamaba super.draw() que los volvía a renderizar todos —
	// resultado: doble render de personajes, notas y splashes en cada frame.
	// Ahora usamos el pipeline estándar de Flixel (super.draw implícito).
	// OptimizationManager sigue activo para: adaptive quality, FPS tracking,
	// y NotePool. El GPURenderer se mantiene pero no interfiere con el draw.
	// ═══════════════════════════════════════════════════════════════
	// REWIND RESTART — V-Slice style
	// ═══════════════════════════════════════════════════════════════

	/**
	 * Inicia la animación de rewind.
	 * Llamar desde PauseSubState en lugar de FlxG.resetState().
	 * Las notas se deslizan visualmente hacia atrás durante ~0.5-1.5s,
	 * luego todo se resetea y el countdown arranca sin recargar el state.
	 */
	public function startRewindRestart():Void
	{
		if (isRewinding)
			return;

		// Parar audio inmediatamente
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.volume = 0; // Silenciar ANTES de pausar para que no suene
			FlxG.sound.music.pause(); // si PauseSubState.destroy() llama a resume()
		}
		if (vocals != null)
			vocals.pause();

		if (camHUD.alpha == 0)
			camHUD.alpha = 1;

		if (!camHUD.visible)
			camHUD.visible = true;

		// Configurar parámetros del rewind
		_rewindFromPos = Conductor.songPosition;
		_rewindToPos = -(Conductor.crochet * 5); // posición de inicio del countdown

		// Duración proporcional a qué tan avanzada estaba la canción (0.5s–1.5s)
		var songProgress:Float = Math.max(0, Conductor.songPosition);
		_rewindDuration = Math.max(0.5, Math.min(1.5, songProgress / 8000.0));

		// Si apenas empezó (<500ms), rewind instantáneo
		if (songProgress < 500)
			_rewindDuration = 0.1;

		_rewindTimer = 0;
		isRewinding = true;
		paused = false;
		canPause = false;
		inCutscene = false;

		// ── Congelar animación de GF para que no se vuelva loca ─────────────
		if (gf != null && gf.animation != null && gf.animation.curAnim != null)
			gf.animation.pause();
		if (dad != null && dad.animation != null && dad.animation.curAnim != null)
			dad.animation.pause();
		if (boyfriend != null && boyfriend.animation != null && boyfriend.animation.curAnim != null)
			boyfriend.animation.pause();

		// Limpiar buffer de inputs y estado de teclas presionadas
		if (inputHandler != null)
		{
			inputHandler.resetMash();
			inputHandler.clearBuffer();
			// Resetear held[] para que los strums no queden en animación 'pressed'
			for (i in 0...4)
				inputHandler.held[i] = false;
		}

		trace('[PlayState] Rewind restart iniciado — desde ${_rewindFromPos}ms, duración ${_rewindDuration}s');
	}

	/**
	 * Llamado cuando la animación de rewind termina.
	 * Resetea todo el estado del juego y arranca el countdown de nuevo.
	 */
	private function _finishRestart():Void
	{
		isRewinding = false;

		// ── 1. Flash de pantalla para señalar el reset ──────────────────────

		// ── 2. Resetear GameState (score, health, combo, etc.) ──────────────
		gameState.reset();
		PlayState.misses = 0;
		PlayState.shits = 0;
		PlayState.bads = 0;
		PlayState.goods = 0;
		PlayState.sicks = 0;
		PlayState.songScore = 0;
		PlayState.accuracy = 0;

		// ── 3. Resetear Conductor al BPM original ────────────────────────────
		Conductor.changeBPM(SONG.bpm);
		Conductor.mapBPMChanges(SONG);
		Conductor.songPosition = _rewindToPos;

		// ── 3b. Re-aplicar skin y splash ─────────────────────────────────────
		// BUGFIX: durante el rewind el currentSkin puede haberse corrompido.
		// Forzar la re-aplicación garantiza que los notes del pool y los strums
		// usen la skin correcta (Pixel scale 6.0, no Default scale 0.7).
		if (metaData != null && metaData.noteSkin != null && metaData.noteSkin != 'default' && metaData.noteSkin != '')
			NoteSkinSystem.setTemporarySkin(metaData.noteSkin);
		else
			NoteSkinSystem.applySkinForStage(curStage);

		if (metaData != null && metaData.noteSplash != null && metaData.noteSplash != '')
			NoteSkinSystem.setTemporarySplash(metaData.noteSplash);
		else
			NoteSkinSystem.applySplashForStage(curStage);

		// BUGFIX escala pixel: recargar skin en TODOS los strum groups para que
		// los strums tengan el scale correcto (pixel=6.0, default=0.7) ANTES de
		// que las notas los hereden via updateNotePosition. Iteramos strumsGroups
		// directamente (cubre todos los grupos, no solo playerStrums/cpuStrums).
		var _skinDataForReload = NoteSkinSystem.getCurrentSkinData();
		for (group in strumsGroups)
			group.reloadAllStrumSkins(_skinDataForReload);

		// ── 4. Rebobinar notas (matar activas + resetear índice de spawn) ────
		if (noteManager != null)
			noteManager.rewindTo(_rewindToPos);

		// ── 5. Rebobinar eventos ─────────────────────────────────────────────
		if (scriptsEnabled)
			EventManager.rewindToStart();

		// ── 5b. Resetear cámara al estado inicial ────────────────────────────
		// Los eventos de Camera Follow / Camera Zoom del editor pueden haber
		// dejado la cámara siguiendo a un personaje diferente o con un zoom
		// distinto. Hay que volver al estado que tenía ANTES de que corriera
		// cualquier evento (snapshot guardado en snapshotInitialState() al cargar).
		if (cameraController != null)
			cameraController.resetToInitial();

		// ── 6. Resetear personajes a idle ─────────────────────────────────────
		if (characterController != null)
			characterController.forceIdleAll();

		// ── 7. Resetear ModChart ──────────────────────────────────────────────
		if (modChartManager != null)
			modChartManager.resetToStart();

		// ── 8. Resetear audio ────────────────────────────────────────────────
		// CRÍTICO: pauseMenu() llamó FlxG.sound.pause() que pone el SoundManager
		// global en estado "paused". Ningún sonido puede reproducirse hasta que se
		// llame FlxG.sound.resume(). Sin esto, los sonidos del countdown y la música
		// quedan bloqueados por el flag global, causando el "traba" antes del restart.
		FlxG.sound.resume();

		if (_usingPerCharVocals)
		{
			for (snd in vocalsPerChar)
			{
				if (snd == null) continue;
				snd.time = 0;
				snd.volume = 0;
				snd.stop();
			}
		}
		else if (vocals != null)
		{
			vocals.time = 0;
			vocals.volume = 0;
			vocals.stop();
		}
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.time = 0;
			FlxG.sound.music.volume = 0;
			FlxG.sound.music.pause();
		}

		// ── 9. Resetear flags de gameplay ────────────────────────────────────
		startedCountdown = false;
		startingSong = false;
		generatedMusic = true; // las notas ya están generadas
		canPause = true;
		inCutscene = false;
		startFromTime = null;

		// Limpiar hold splashes residuales
		// NOTA: heldNotes solo puede tener keys 0-3 (noteData), nunca >= 4.
		// El bloque CPU cleanup que chequeaba key >= 4 en update() era código muerto
		// y fue eliminado — NoteManager maneja internamente los hold notes del CPU.
		heldNotes.clear();

		if (grpNoteSplashes != null)
			grpNoteSplashes.forEachAlive(function(s)
			{
				s.kill();
			});

		// ── 10. Resetear animaciones de strums a 'static' y re-aplicar posiciones ─
		// Aplica downscroll/middlescroll usando los datos originales del StrumsGroup
		// (respetando data.x y spacing) — más correcto que recalcular manualmente.
		var _isDownscroll = FlxG.save.data.downscroll;
		var _isMiddlescroll = FlxG.save.data.middlescroll;
		var _strumY:Float = _isDownscroll ? FlxG.height - 150 : PlayStateConfig.STRUM_LINE_Y;
		strumLiney = _strumY;
		if (noteManager != null)
		{
			noteManager.strumLineY = _strumY;
			noteManager.downscroll = _isDownscroll;
			noteManager.middlescroll = _isMiddlescroll;
		}

		// Refrescar el lane backdrop con las posiciones actuales de los strums
		_updateLaneBackdrop();

		// Repositionar todos los grupos y resetear animaciones a 'static'
		for (group in strumsGroups)
		{
			group.applyScrollSettings(_isDownscroll, _isMiddlescroll, PlayStateConfig.STRUM_LINE_Y);
			group.strums.forEach(function(s:FlxSprite)
			{
				if (Std.isOfType(s, funkin.gameplay.notes.StrumNote))
					cast(s, funkin.gameplay.notes.StrumNote).playAnim('static', true);
			});

			// BUGFIX: re-aplicar visibilidad siempre (no solo ocultar).
			// reloadAllStrumSkins() puede dejar strums visibles tras recargar el frameset.
			// Comparar contra `== true` previene fallos cuando isVisible es null
			// (campo "visible" ausente en el JSON → el typedef lo deja como null en Haxe).
			// Sin este fix, grupos de GF creados por la migración legacy (visible:false)
			// reaparecen en pantalla al reiniciar o hacer rewind.
			final shouldBeVisible:Bool = (group.isVisible == true);
			final _isMiddlescrollReset:Bool = (FlxG.save.data.middlescroll == true);
			group.strums.forEach(function(s:FlxSprite)
			{
				// CPU strums se ocultan en middlescroll independientemente de isVisible
				if (group.isCPU && _isMiddlescrollReset)
				{
					s.visible = false;
					s.alpha = 0;
				}
				else
				{
					s.visible = shouldBeVisible;
				}
			});
		}
		// Fallback para el caso (improbable) de strums fuera de strumsGroups
		if (playerStrums != null && strumsGroups.length == 0)
			playerStrums.forEach(function(s:FlxSprite)
			{
				if (Std.isOfType(s, funkin.gameplay.notes.StrumNote))
					cast(s, funkin.gameplay.notes.StrumNote).playAnim('static', true);
			});
		if (cpuStrums != null && strumsGroups.length == 0)
			cpuStrums.forEach(function(s:FlxSprite)
			{
				if (Std.isOfType(s, funkin.gameplay.notes.StrumNote))
					cast(s, funkin.gameplay.notes.StrumNote).playAnim('static', true);
			});

		// ── 11. Scripts ───────────────────────────────────────────────────────
		if (scriptsEnabled)
			ScriptHandler.callOnScripts('onRestart', ScriptHandler._argsEmpty);

		// ── 12. Pequeño delay antes del countdown (espera el flash) ──────────
		new flixel.util.FlxTimer().start(0.15, function(_)
		{
			startCountdown();
		});

		trace('[PlayState] Rewind restart completado.');
	}

	/**
	 * Destroy
	 */
	override function destroy()
	{
		// ── BUGFIX: Restaurar FPS si _safePlay lo bajó y destroy() ocurre ───
		//    antes de que update() completara el countdown de 6 frames.
		//    Sin esto el FPS queda atascado en 20 al salir mid-countdown o al
		//    entrar al PlayState por segunda vez (currentFps > 21 → false → no
		//    guarda _audioBootSavedFps → restore nunca ocurre).
		if (_audioBootSavedFps > 0)
		{
			final main = Std.downcast(openfl.Lib.current.getChildAt(0), Main);
			if (main != null)
				main.setMaxFps(_audioBootSavedFps);
			else
				openfl.Lib.current.stage.frameRate = _audioBootSavedFps;
			_audioBootSavedFps = 0;
			_audioBootFrames   = 0;
		}

		// ── Quitar listener global de foco ───────────────────────────────────
		FlxG.signals.focusLost.remove(_onGlobalFocusLost);

		// ── 1. Resetear estáticas ────────────────────────────────────────────────
		instance = null;
		isPlaying = false;
		cpuStrums = null;
		startingSong = false; // Era estático y podía quedar true si se salía mid-countdown

		#if android
		lime.app.Application.current.window.onKeyDown.remove(_onAndroidKeyDown);
		#end

		// ── 3. Limpiar vocals del sound list y destruirla
		//       vocals se añadió manualmente a FlxG.sound.list así que hay que quitarla
		if (vocals != null)
		{
			FlxG.sound.list.remove(vocals, true);
			vocals.stop();
			vocals.destroy();
			vocals = null;
		}
		_cleanPerCharVocals();

		// BUGFIX (Flixel git): el instrumental también fue añadido a FlxG.sound.list
		// por _loadStreamingSound → hay que quitarlo explícitamente igual que vocals.
		// Sin esto el FlxSound queda en list después del state switch → update() en
		// un objeto destruido → crash o audio zombie.
		if (FlxG.sound.music != null)
		{
			FlxG.sound.list.remove(FlxG.sound.music, true);
			FlxG.sound.music = null;
		}

		// ── 4. Scripts (antes de destruir objetos del stage que usen scripts)
		if (scriptsEnabled)
		{
			ScriptHandler.callOnScripts('onDestroy', ScriptHandler._argsEmpty);
			ScriptHandler.clearSongScripts();
			ScriptHandler.clearStageScripts(); // BUGFIX: sin esto los scripts del stage anterior
			ScriptHandler.clearCharScripts(); // quedan vivos al regresar al state → crash
			EventManager.clear();
		}

		// ── 5. OMITIR currentStage.destroy() manual ─────────────────────────────
		//       currentStage fue add()-eado al FlxState, así que super.destroy()
		//       ya lo destruye al recorrer sus miembros.
		//       Llamarlo aquí causaba DOBLE DESTROY → corrupción de texturas → crash.

		// ── 6. Optimization manager
		if (optimizationManager != null)
		{
			optimizationManager.destroy();
			optimizationManager = null;
		}

		// NOTA: No llamar forceGC() aquí — clearUnusedMemory() al final del destroy
		// ya hace Gc.run(true)+compact(). Llamarlo antes causaba un GC doble (~200ms extra).

		// ── 7. Controllers
		if (cameraController != null)
		{
			cameraController.destroy();
			cameraController = null;
		}

		if (noteManager != null)
		{
			noteManager.destroy();
			noteManager = null;
		}

		if (modChartManager != null)
		{
			modChartManager.destroy();
			modChartManager = null;
		}

		// ── 8. Note batcher
		if (noteBatcher != null)
		{
			remove(noteBatcher, true);
			noteBatcher.destroy();
			noteBatcher = null;
		}

		// ── 9. Limpiar estructuras internas
		NoteSkinSystem.restoreGlobalSkin();
		NoteSkinSystem.restoreGlobalSplash();
		heldNotes.clear();

		characterSlots = [];
		strumsGroups = [];
		strumsGroupMap.clear();
		activeCharIndices = [];

		GameState.destroy();

		RatingManager.destroy();

		// ── 10. Pool de hitsounds
		for (snd in _hitSounds)
		{
			if (snd != null)
			{
				snd.stop();
				FlxG.sound.list.remove(snd, true);
				snd.destroy();
			}
		}
		_hitSounds = [];

		if (countdown != null)
		{
			countdown.destroy();
			countdown = null;
		}

		// ── Pool de miss sounds
		for (snd in _missSounds)
		{
			if (snd != null)
			{
				snd.stop();
				FlxG.sound.list.remove(snd, true);
				snd.destroy();
			}
		}
		_missSounds = [];

		// ── 11. Hooks
		onBeatHitHooks.clear();
		onStepHitHooks.clear();
		onUpdateHooks.clear();
		onNoteHitHooks.clear();
		onNoteMissHooks.clear();
		_beatHookArr = [];
		_stepHookArr = [];
		_updateHookArr = [];
		_noteHitHookArr = [];
		_noteMissHookArr = [];

		// ── 12. Section wrapper cache
		_cachedSectionClass = null;
		_cachedSectionClassIdx = -2;

		// ── 13. Reanudar GC ANTES de super.destroy() ─────────────────────────
		// CRÍTICO: el GC debe estar activo cuando super.destroy() libera los
		// FlxSprites/Groups del state, para que los objetos muertos sean
		// elegibles para recolección sin acumularse en el heap.
		// Antes se reanudaba DESPUÉS de super.destroy() → el teardown completo
		// ocurría con el GC deshabilitado → el heap crecía innecesariamente.
		if (_gcPausedForSong)
		{
			_gcPausedForSong = false;
			MemoryUtil.resumeGC();
		}

		super.destroy();

		StickerTransition.invalidateCache();

		// ── 14. Limpieza de memoria ───────────────────────────────────────────
		// clearStoredMemory() ya no es necesario aquí: FunkinCache.postStateSwitch
		// llama clearSecondLayer() que usa FlxG.bitmap.removeByKey() (más correcto).
		// clearUnusedMemory() hace FlxG.bitmap.clearUnused() + Gc.run(true) + compact().
		// Solo llamarlo UNA vez para evitar el doble stutter.
		Paths.clearUnusedMemory();

		// Limpiar el atlasCache de Paths de entradas cuyo FlxGraphic fue dispuesto.
		// Debe hacerse DESPUÉS del GC para que los bitmap == null sean detectables.
		Paths.pruneAtlasCache();

		// GPU caching post-destroy: liberar RAM de texturas ya subidas a VRAM.
		// Se llama aquí porque en este punto FunkinCache ya completó su rotación
		// de capas y context3D debería estar disponible.
		funkin.cache.PathsCache.instance.flushGPUCache();
	}

	// ====================================
	// SISTEMA DE DIÁLOGOS
	// ====================================

	/**
	 * Verificar si existe un archivo de diálogo para la canción actual
	 */
	private function checkForDialogue(type:String = 'intro'):Bool
	{
		var songName = SONG.song.toLowerCase();
		var dialoguePath = Paths.resolve('songs/${songName}/${type}.json');

		#if sys
		return sys.FileSystem.exists(dialoguePath);
		#else
		// En web/móvil, intentar cargar y verificar
		try
		{
			var data = DialogueData.loadDialogue(dialoguePath);
			return (data != null);
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#end
	}

	/**
	 * Mostrar diálogo
	 */
	private function showDialogue(type:String = 'intro', ?onFinish:Void->Void):Void
	{
		isCutscene = true;

		var songName = SONG.song.toLowerCase();

		var doof:DialogueBoxImproved = null;

		try
		{
			doof = new DialogueBoxImproved(songName);
		}
		catch (e:Dynamic)
		{
			if (onFinish != null)
				onFinish();
			return;
		}

		if (doof == null)
		{
			if (onFinish != null)
				onFinish();
			return;
		}

		// Configurar callback de finalización
		doof.finishThing = function()
		{
			inCutscene = false;
			if (onFinish != null)
				onFinish();
		};

		// Agregar diálogo
		add(doof);

		doof.cameras = [camHUD];
	}

	/**
	 * Mostrar diálogo de outro (al final de la canción)
	 */
	private function showOutroDialogue():Bool
	{
		if (checkForDialogue('outro'))
		{
			isCutscene = true;

			showDialogue('outro', function()
			{
				// Continuar con el flujo normal después del diálogo
				if (FlxG.sound.music != null)
					FlxG.sound.music.stop();
				isCutscene = false;
				continueAfterSong();
			});
			return true;
		}
		return false;
	}

	/**
	 * Continuar después de la canción (separado para reutilizar)
	 */
	private function continueAfterSong():Void
	{
		if (isStoryMode)
		{
			campaignScore += songScore;
			storyPlaylist.remove(storyPlaylist[0]);

			if (storyPlaylist.length <= 0)
			{
				FlxG.sound.playMusic(Paths.music('freakyMenu'));

				if (SONG.validScore)
					Highscore.saveWeekScore(storyWeek, campaignScore, funkin.data.CoolUtil.difficultySuffix());

				FlxG.save.flush();
				LoadingState.loadAndSwitchState(new RatingState());
			}
			else
			{
				// Next song
				SONG = Song.loadFromJson(storyPlaylist[0].toLowerCase() + CoolUtil.difficultySuffix(), storyPlaylist[0]);
				if (FlxG.sound.music != null)
					FlxG.sound.music.stop();
				LoadingState.loadAndSwitchState(new PlayState());
			}
		}
		else
		{
			if (FlxG.sound.music != null)
				FlxG.sound.music.stop();
			// vocals puede ser null en charts V-Slice que usan vocales por personaje.
			if (_usingPerCharVocals)
			{
				for (snd in vocalsPerChar) if (snd != null) snd.stop();
			}
			else if (vocals != null)
				vocals.stop();
			LoadingState.loadAndSwitchState(new RatingState());
		}
	}

	/**
	 * Actualiza las configuraciones de gameplay en tiempo real
	 * Se llama cuando se modifican opciones desde el pause menu
	 * SOLO aplica cambios SEGUROS que no pueden causar bugs
	 */
	public function updateGameplaySettings():Void
	{
		// Verificación de seguridad: solo actualizar si el juego está pausado
		if (!paused)
		{
			return;
		}

		// === CAMBIOS SEGUROS (no afectan lógica del juego) ===

		// 1. Actualizar visibilidad del HUD (100% seguro)
		if (uiManager != null)
		{
			var hideHud = FlxG.save.data.HUD;
			uiManager.visible = !hideHud; // Controlar visibilidad del grupo completo
		}

		// 2. Actualizar antialiasing (solo visual, 100% seguro)
		updateAntialiasing();

		// 3. Actualizar ghost tapping (seguro, solo afecta siguiente input)
		if (inputHandler != null)
		{
			inputHandler.ghostTapping = FlxG.save.data.ghosttap;
		}

		// === CAMBIOS QUE REQUIEREN MÁS CUIDADO ===
		// NO actualizar downscroll/middlescroll en tiempo real
		// Estos cambios pueden causar confusión y bugs con las notas en vuelo
		// El usuario debe reiniciar la canción para aplicar estos cambios
	}

	/**
	 * Actualiza el antialiasing de todos los sprites del stage
	 */
	private function updateAntialiasing():Void
	{
		if (currentStage == null)
			return;

		// FIX: skinSystem nunca se asigna → null → crash en skinSystem.isPixel.
		// Usar NoteSkinSystem.getCurrentSkinData() igual que el resto del código.
		final skinData = NoteSkinSystem.getCurrentSkinData();
		if (skinData != null && skinData.isPixel == true)
			return;

		final aa:Bool = (FlxG.save.data.antialiasing == true);

		for (sprite in currentStage.members)
		{
			if (sprite != null && Std.isOfType(sprite, FlxSprite))
				(cast sprite:FlxSprite).antialiasing = aa;
		}

		if (boyfriend != null) boyfriend.antialiasing = aa;
		if (dad       != null) dad.antialiasing       = aa;
		if (gf        != null) gf.antialiasing        = aa;
	}

	/**
	 * Handler conectado a FlxG.signals.focusLost en create() y desconectado en destroy().
	 *
	 * FlxG.signals.focusLost se emite por FlxGame ANTES de propagar el evento a
	 * los states, por lo que se dispara siempre — incluso si hay un substate abierto,
	 * o si el state raíz activo NO es PlayState (ej. si otro state hace switchState
	 * mientras la música sigue sonando de fondo).
	 *
	 * Reglas:
	 *   • Ya pausado          → solo silenciar vocals (no re-abrir PauseSubState)
	 *   • canPause == false   → respetar el bloqueo explícito (cutscenes críticas)
	 *   • Cualquier otro caso → pauseMenu() sin condiciones adicionales
	 */
	function _onGlobalFocusLost():Void
	{
		if (paused)
		{
			_pauseVocalsOnly();
			return;
		}
		if (!canPause) return;
		pauseMenu();
	}

	/** Pausa únicamente los streams de vocals sin abrir el pause menu. */
	function _pauseVocalsOnly():Void
	{
		if (_usingPerCharVocals)
		{
			for (snd in vocalsPerChar) if (snd != null && snd.playing) snd.pause();
		}
		else if (vocals != null && vocals.playing)
		{
			vocals.pause();
		}
	}

	/**
	 * Llamado cuando el juego pierde foco (minimizar ventana)
	 * Pausa las vocals para que estén sincronizadas con el instrumental
	 */
	override public function onFocusLost():Void
	{
		super.onFocusLost();
		// _onGlobalFocusLost() ya se encarga de la pausa completa.
		// Este override solo existe para cubrir el caso en que el signal
		// no se haya conectado todavía (antes del final de create()).
		if (!paused && canPause) pauseMenu();
	}

	/**
	 * Llamado cuando el juego recupera foco (volver a la ventana)
	 * Reanuda TANTO el instrumental como las vocals
	 */
	override public function onFocus():Void
	{
		super.onFocus();

		// CRÍTICO: Con loadStream(), FlxG.sound.music NO se reanuda automáticamente
		// Necesitamos reanudarlo manualmente
		if (FlxG.sound.music != null && !startingSong && generatedMusic && !paused)
		{
			// Reanudar el instrumental
			_safePlay(FlxG.sound.music);

			// Reanudar vocals sincronizadas con el instrumental
			if (SONG.needsVoices)
			{
				if (_usingPerCharVocals)
				{
					for (snd in vocalsPerChar)
					{
						if (snd == null) continue;
						snd.time = FlxG.sound.music.time;
						_safePlay(snd);
					}
				}
				else if (vocals != null)
				{
					vocals.time = FlxG.sound.music.time;
					_safePlay(vocals);
				}
			}
		}
	}

	// ══════════════════════════════════════════════════════════════════
	// VOCALES POR PERSONAJE
	// ══════════════════════════════════════════════════════════════════

	/**
	 * Intenta cargar Voices-<charName>[-diff].ogg para TODOS los personajes
	 * definidos en SONG.characters (o player1/player2 en modo legacy).
	 *
	 * Devuelve true si se cargó al menos un track.
	 * En ese caso activa el modo per-char; si ninguno existe retorna false
	 * y el caller debe cargar el Voices.ogg genérico.
	 */
	private function _tryLoadPerCharVocals(diffSuffix:String):Bool
	{
		// Limpiar listas de roles
		_vocalsPlayerKeys   = [];
		_vocalsOpponentKeys = [];

		// Construir lista de candidatos: [{name, type}]
		var candidates:Array<{name:String, type:String}> = [];

		if (SONG.characters != null && SONG.characters.length > 0)
		{
			for (c in SONG.characters)
			{
				var t = c.type != null ? c.type : 'Opponent';
				// GF / Other nunca tienen vocals
				if (t == 'Girlfriend' || t == 'Other') continue;
				// Saltar duplicados por nombre
				var dup = false;
				for (prev in candidates) if (prev.name == c.name) { dup = true; break; }
				if (!dup) candidates.push({name: c.name, type: t});
			}
		}

		// Fallback legacy: player1 / player2
		if (candidates.length == 0)
		{
			var p1 = SONG.player1 != null ? SONG.player1 : 'bf';
			var p2 = SONG.player2 != null ? SONG.player2 : 'dad';
			candidates.push({name: p1, type: 'Player'});
			if (p2 != p1) candidates.push({name: p2, type: 'Opponent'});
		}

		var loaded = 0;
		for (cand in candidates)
		{
			var snd = Paths.loadVoicesForChar(SONG.song, cand.name, diffSuffix);
			if (snd == null) continue;

			snd.volume = 0;
			snd.pause();
			FlxG.sound.list.add(snd);
			vocalsPerChar.set(cand.name, snd);

			if (cand.type == 'Player' || cand.type == 'Boyfriend')
				_vocalsPlayerKeys.push(cand.name);
			else
				_vocalsOpponentKeys.push(cand.name);

			loaded++;
		}

		trace('[PlayState] Per-char vocals cargadas: $loaded / ${candidates.length} personajes');
		return loaded > 0;
	}

	/** Destruye y limpia todos los tracks de vocals por personaje. */
	private function _cleanPerCharVocals():Void
	{
		for (snd in vocalsPerChar)
		{
			if (snd == null) continue;
			FlxG.sound.list.remove(snd, true);
			snd.stop();
			snd.destroy();
		}
		vocalsPerChar.clear();
		_vocalsPlayerKeys   = [];
		_vocalsOpponentKeys = [];
		_usingPerCharVocals = false;
	}

	/**
	 * Propaga una lista de cámaras recursivamente a todos los miembros de un
	 * FlxGroup, incluyendo sub-grupos anidados.
	 *
	 * Necesario porque FlxGroup.cameras solo afecta a nuevos miembros añadidos
	 * DESPUÉS de la asignación — los ya existentes quedan con cameras=[] si el
	 * grupo fue construido antes de la asignación.  Un cameras=[] vacío impide
	 * que Flixel compile el programa GL del shader ("no camera detected").
	 */
	private function _assignStageCameras(group:flixel.group.FlxGroup, cams:Array<flixel.FlxCamera>):Void
	{
		for (member in group.members)
		{
			if (member == null)
				continue;
			member.cameras = cams;
			if (Std.isOfType(member, flixel.group.FlxGroup))
				_assignStageCameras(cast member, cams);
		}
	}
}
