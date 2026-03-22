package funkin.debug.editors;

#if desktop
import lime.ui.FileDialog;
#end
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.ui.FlxButton;
import flixel.addons.ui.FlxInputText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.math.FlxMath;
import flixel.group.FlxGroup.FlxTypedGroup;
import haxe.Json;
import lime.utils.Assets;
import sys.io.File;
import sys.FileSystem;
import funkin.menus.FreeplayState.SongMetadata;
import funkin.data.MetaData;
import funkin.data.LevelFile;
import funkin.data.Song.SwagSong;
import funkin.data.FreeplayList;
import funkin.data.FreeplayList.FreeplayListData;
import funkin.data.FreeplayList.FreeplaySongEntry;
import funkin.debug.ColorPickerWheel;

using StringTools;

/** Slot dinámico de vocals por personaje en AddSongSubState. */
typedef VocalSlot =
{
	var charName:String;
	var filePath:String;
	var loaded:Bool;
	var btn:FlxButton;
	var statusText:FlxText;
	var nameInput:FlxInputText;
	/** Icono de salud del personaje (visible en edit mode si existe). */
	@:optional var charIcon:FlxSprite;
	/** Texto con nombre de archivo y duración (visible en edit mode). */
	@:optional var infoText:FlxText;
}

/**
 * Una entrada de dificultad en el paso de dificultades / importación de chart.
 * label   = nombre visible  ("Easy", "Normal", "Hard", "Nightmare"…)
 * suffix  = sufijo de archivo ("-easy", "", "-hard", "-nightmare"…)
 * enabled = si esta dificultad estará activa en el juego
 * chartPath / chartFormat / chartDiffKey = info del chart importado (si hay)
 */
typedef DiffEntry =
{
	var label:String;
	var suffix:String;
	var enabled:Bool;
	var chartPath:String;
	var chartFormat:String;   // "vslice", "psych", "osu", "sm", "codename", "level", ""
	var chartDiffKey:String;  // clave de dificultad dentro del archivo fuente (para multi-diff)
	/** Dificultades disponibles en el archivo importado (para multi-diff). */
	@:optional var availableKeys:Array<String>;
	// UI refs
	@:optional var enableBtn:FlxButton;
	@:optional var enableTxt:FlxText;
	@:optional var labelInput:FlxInputText;
	@:optional var importBtn:FlxButton;
	@:optional var statusTxt:FlxText;
	@:optional var formatBadge:FlxText;
	@:optional var keyBtn:FlxButton;   // selector de clave para multi-diff
}

/**
 * AddSongSubState — ventana multipaso para añadir / editar canciones.
 *
 * PASO 1 — Archivos & BPM:
 *   • Nombre de canción
 *   • Load Inst.ogg / Vocals.ogg / Icon.png
 *   • BPM
 *   • Toggle "Needs Voices"
 *
 * PASO 2 — Metadatos:
 *   • Icon Name (◄ ► para presets)
 *   • UI Script / Note Skin
 *   • Intro Video / Outro Video
 *   • Artist
 *
 * PASO 3 — Story Menu:
 *   • Week Index
 *   • Toggle "Show in Story Mode"
 *   • Color del menú (paleta)
 */
class AddSongSubState extends FlxSubState
{
	// ── Constantes de paso ────────────────────────────────────────────────────
	static inline var STEP_FILES  = 1;
	static inline var STEP_DIFFS  = 2;
	static inline var STEP_META   = 3;
	static inline var STEP_STORY  = 4;
	static inline var TOTAL_STEPS = 4;

	// ── Window layout ─────────────────────────────────────────────────────────
	var windowWidth:Int  = 860;
	var windowHeight:Int = 620;
	var windowX:Float;
	var windowY:Float;

	// ── Common UI ─────────────────────────────────────────────────────────────
	var bgDarkener:FlxSprite;
	var windowBg:FlxSprite;
	var topBar:FlxSprite;
	var titleText:FlxText;
	var statusText:FlxText;
	var stepIndicator:FlxText;

	// ── Nav buttons ───────────────────────────────────────────────────────────
	var prevBtn:FlxButton;
	var nextBtn:FlxButton;
	var saveBtn:FlxButton;
	var cancelBtn:FlxButton;

	// ── Step containers (groups that get shown/hidden) ─────────────────────
	var stepGroups:Array<FlxTypedGroup<Dynamic>> = [];
	var currentStep:Int = STEP_FILES;

	/**
	 * Posiciones X originales de cada objeto en cada step group.
	 * FIX: _slideIn leía obj.x en mitad de un tween → acumulaba el offset
	 * en cada navegación. Guardando las X al construir cada paso y
	 * restaurándolas antes de la animación, el drift queda eliminado.
	 */
	var _stepOrigX:Array<Map<flixel.FlxObject, Float>> = [];

	// ─── PASO 1: Archivos & BPM ───────────────────────────────────────────────
	var songNameInput:FlxInputText;
	var bpmInput:FlxInputText;
	var loadInstBtn:FlxButton;
	var loadVocalsBtn:FlxButton;
	var loadIconBtn:FlxButton;
	var instStatusText:FlxText;
	var vocalsStatusText:FlxText;
	var iconStatusText:FlxText;
	var needsVoicesToggleBtn:FlxButton;
	var needsVoicesToggleText:FlxText;
	var needsVoices:Bool = true;

	// ─── PASO 2: Dificultades & Import ────────────────────────────────────────
	/** Entrada de dificultad: label visible, sufijo interno, estado y chart importado. */
	var diffEntries:Array<DiffEntry>  = [];
	var _diffRowContainer:FlxTypedGroup<Dynamic> = null;
	var _addDiffBtn:FlxButton = null;
	/** Scroll offset para la lista de diffs (en píxeles) */
	var _diffScrollY:Float = 0;
	var _diffListY:Float   = 0;   // Y absoluta donde empieza la lista

	// ─── PASO 3: Metadatos ────────────────────────────────────────────────────
	var iconNameInput:FlxInputText;
	var uiInput:FlxInputText;
	var noteSkinInput:FlxInputText;
	var introVideoInput:FlxInputText;
	var outroVideoInput:FlxInputText;
	var artistInput:FlxInputText;
	var albumInput:FlxInputText;
	var albumTextInput:FlxInputText;

	// ─── PASO 3: Story Menu ───────────────────────────────────────────────────
	var weekInput:FlxInputText;
	var selectedColor:String = "0xFFAF66CE";
	// Swatch visual que muestra el color elegido
	var colorSwatchBtn:FlxButton = null;
	var colorSwatchLabel:FlxText = null;

	// ── File data ─────────────────────────────────────────────────────────────
	var currentInstPath:String  = "";
	var currentVocalsPath:String = ""; // Voices.ogg (modo unificado)
	var currentIconPath:String  = "";
	var instLoaded:Bool     = false;
	var vocalsLoaded:Bool   = false;
	var iconFileLoaded:Bool = false;

	/** true = vocales separadas por personaje (Voices-<name>.ogg). */
	var splitVocals:Bool = false;

	/** Slots dinámicos de vocals por personaje. */
	var vocalSlots:Array<VocalSlot> = [];

	// Botones de control del panel dinámico de slots
	var _addSlotBtn:FlxButton                 = null;
	var _slotContainer:FlxTypedGroup<Dynamic> = null;

	// Info bars (edit mode)
	var instInfoText:FlxText    = null;
	var vocalsInfoText:FlxText  = null;

	// ── Song list & edit mode ─────────────────────────────────────────────────
	var freeplayListData:FreeplayListData;
	var editMode:Bool = false;
	var editingSong:funkin.menus.FreeplayState.SongMetadata = null;

	// ── Presets ───────────────────────────────────────────────────────────────
	var iconPresets:Array<String> = [
		"bf", "bf-pixel", "gf", "dad", "mom", "pico",
		"spooky", "monster", "parents-christmas",
		"senpai", "senpai-angry", "spirit", "face"
	];
	var currentIconIndex:Int = 0;



	// ─────────────────────────────────────────────────────────────────────────

	public function new(?editSong:SongMetadata)
	{
		super();
		if (editSong != null) { editMode = true; editingSong = editSong; }
		loadSongList();
	}

	override function create()
	{
		super.create();
		funkin.debug.themes.EditorTheme.load();

		windowX = (FlxG.width  - windowWidth)  / 2;
		windowY = (FlxG.height - windowHeight) / 2;

		// ── Background ────────────────────────────────────────────────────────
		bgDarkener = new FlxSprite();
		bgDarkener.makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bgDarkener.alpha = 0;
		add(bgDarkener);
		FlxTween.tween(bgDarkener, {alpha: 0.7}, 0.3, {ease: FlxEase.quadOut});

		windowBg = new FlxSprite(windowX, windowY);
		windowBg.makeGraphic(windowWidth, windowHeight, funkin.debug.themes.EditorTheme.current.bgPanel);
		windowBg.alpha = 0;
		windowBg.scale.set(0.85, 0.85);
		add(windowBg);
		FlxTween.tween(windowBg, {alpha: 0.98, "scale.x": 1, "scale.y": 1}, 0.4, {ease: FlxEase.backOut, startDelay: 0.05});

		topBar = new FlxSprite(windowX, windowY);
		topBar.makeGraphic(windowWidth, 50, funkin.debug.themes.EditorTheme.current.bgPanelAlt);
		topBar.alpha = 0;
		add(topBar);
		FlxTween.tween(topBar, {alpha: 1}, 0.3, {startDelay: 0.1});

		// ── Título ────────────────────────────────────────────────────────────
		titleText = new FlxText(windowX + 20, windowY + 13, 0,
			editMode ? "EDIT SONG" : "ADD NEW SONG", 22);
		titleText.setFormat(Paths.font("vcr.ttf"), 22, FlxColor.WHITE, LEFT);
		titleText.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		titleText.alpha = 0;
		add(titleText);
		FlxTween.tween(titleText, {alpha: 1}, 0.3, {startDelay: 0.15});

		// ── Indicador de paso ─────────────────────────────────────────────────
		stepIndicator = new FlxText(windowX + windowWidth - 130, windowY + 15, 0, "", 16);
		stepIndicator.setFormat(Paths.font("vcr.ttf"), 16, funkin.debug.themes.EditorTheme.current.accent, RIGHT);
		stepIndicator.alpha = 0;
		add(stepIndicator);
		FlxTween.tween(stepIndicator, {alpha: 1}, 0.3, {startDelay: 0.15});

		// ── Status ────────────────────────────────────────────────────────────
		statusText = new FlxText(windowX, windowY + windowHeight - 38, windowWidth, "", 13);
		statusText.setFormat(Paths.font("vcr.ttf"), 13,
			funkin.debug.themes.EditorTheme.current.accent, CENTER);
		statusText.alpha = 0;
		add(statusText);
		FlxTween.tween(statusText, {alpha: 1}, 0.3, {startDelay: 0.2});

		// ── Nav y action buttons ──────────────────────────────────────────────
		_buildNavButtons();

		// ── Pasos ─────────────────────────────────────────────────────────────
		for (_ in 0...TOTAL_STEPS) stepGroups.push(new FlxTypedGroup<Dynamic>());

		_buildStep1();
		_buildStep2();
		_buildStep3();
		_buildStep4();

		for (g in stepGroups) add(g);

		// ── Snapshot de posiciones X originales (anti-drift en transiciones) ─
		// Debe hacerse DESPUÉS de _buildStep* y ANTES de cualquier animación
		// de slide, para que las X capturadas sean siempre las de diseño.
		for (_ in 0...TOTAL_STEPS) _stepOrigX.push(new Map<flixel.FlxObject, Float>());
		for (i in 0...stepGroups.length)
		{
			var map = _stepOrigX[i];
			for (m in stepGroups[i].members)
				if (m != null && Std.isOfType(m, flixel.FlxObject))
					map.set(cast m, (cast m : flixel.FlxObject).x);
		}

		// ── Theme button ──────────────────────────────────────────────────────
		var themeBtn = new FlxButton(windowX + 10, windowY + 10, "\u2728 Theme", function()
			openSubState(new funkin.debug.themes.ThemePickerSubState()));
		themeBtn.alpha = 0;
		add(themeBtn);
		FlxTween.tween(themeBtn, {alpha: 0.85}, 0.3, {startDelay: 0.25});

		// ── Cargar datos en modo edición ──────────────────────────────────────
		if (editMode && editingSong != null) loadEditData();

		_showStep(currentStep);

		funkin.system.CursorManager.show();
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  BUILDERS DE PASOS
	// ═════════════════════════════════════════════════════════════════════════

	function _buildStep1():Void
	{
		var g = stepGroups[0];
		var cx = windowX + 40;
		var cy = windowY + 68;

		// ── Song Name ─────────────────────────────────────────────────────────
		_lbl(g, cx, cy, "Song Name:", 0.3);
		songNameInput = _inp(g, cx, cy + 22, windowWidth - 80, "", 60, 0.35);
		cy += 68;

		// ── BPM ───────────────────────────────────────────────────────────────
		_lbl(g, cx, cy, "BPM:", 0.35);
		bpmInput = _inpNum(g, cx, cy + 22, 200, "120", 0.4);

		// ── Needs Voices toggle ───────────────────────────────────────────────
		_lbl(g, cx + 260, cy, "Needs Voices:", 0.38);
		needsVoicesToggleBtn = _toggleBtn(g, cx + 430, cy + 18, function()
		{
			needsVoices = !needsVoices;
			_refreshVoicesToggle();
			_rebuildVocalSlots();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.6);
		}, 0.42);
		needsVoicesToggleText = _toggleTxt(g, cx + 437, cy + 20, 0.44);
		_refreshVoicesToggle();
		cy += 68;

		// ── Separador ─────────────────────────────────────────────────────────
		var sep = new FlxSprite(windowX + 20, cy);
		sep.makeGraphic(windowWidth - 40, 2, funkin.debug.themes.EditorTheme.current.borderColor);
		sep.alpha = 0; g.add(sep);
		FlxTween.tween(sep, {alpha: 0.5}, 0.3, {startDelay: 0.42});
		cy += 14;

		// ── Inst ──────────────────────────────────────────────────────────────
		var fileW = windowWidth - 80;
		loadInstBtn = _fileBtn(g, cx, cy, "  [Inst]  Load Inst.ogg",
			funkin.debug.themes.EditorTheme.current.bgHover, fileW, function()
		{
			#if desktop
			var fd = new FileDialog();
			fd.onSelect.add(function(p:String)
			{
				currentInstPath = p; instLoaded = true;
				if (instInfoText != null)
				{
					var dur = _fmtDuration(p);
					instInfoText.text    = haxe.io.Path.withoutDirectory(p) + (dur != "" ? "  ·  " + dur : "");
					instInfoText.visible = true;
				}
				updateFileStatus();
				updateStatus("\u2713 Inst.ogg selected");
			});
			fd.browse(OPEN, "ogg", null, "Select Inst.ogg");
			#else updateStatus("Desktop only"); #end
		}, 0.44);
		instStatusText = _statusIcon(g, cx + fileW + 6, cy + 10, 0.46);

		instInfoText = new FlxText(cx, cy + 40, fileW, "", 10);
		instInfoText.setFormat(Paths.font("vcr.ttf"), 10,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		instInfoText.visible = false;
		g.add(instInfoText);
		cy += 52;

		// ── Toggle: Split vocals por personaje ────────────────────────────────
		_lbl(g, cx, cy, "Split vocals per character:", 0.44);
		var splitToggleBtn = _toggleBtn(g, cx + 280, cy - 4, function()
		{
			splitVocals = !splitVocals;
			_refreshSplitToggle();
			_rebuildVocalSlots();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.6);
		}, 0.45);
		var splitToggleText = _toggleTxt(g, cx + 287, cy, 0.46);
		_splitToggleBtn  = splitToggleBtn;
		_splitToggleText = splitToggleText;
		_refreshSplitToggle();

		var hintSplit = new FlxText(cx + 390, cy + 2, windowWidth - cx - 430,
			"Voices-<character>.ogg", 11);
		hintSplit.setFormat(Paths.font("vcr.ttf"), 11,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		hintSplit.alpha = 0; g.add(hintSplit);
		FlxTween.tween(hintSplit, {alpha: 0.65}, 0.3, {startDelay: 0.47});
		cy += 40;

		// ── Área de vocales (cy fijado aquí) ──────────────────────────────────
		// Guardar la Y base para que _buildVocalSlotUI y _repositionSlotControls
		// usen siempre la posición correcta, sin hardcodear ni depender de cy local.
		_vocalAreaY = cy;

		// ── Vocals unificadas (Voices.ogg) — visibles cuando split=false ──────
		loadVocalsBtn = _fileBtn(g, cx, cy, "  [Voice]  Load Voices.ogg",
			funkin.debug.themes.EditorTheme.current.bgHover, fileW, function()
		{
			#if desktop
			var fd = new FileDialog();
			fd.onSelect.add(function(p:String)
			{
				currentVocalsPath = p; vocalsLoaded = true;
				if (vocalsInfoText != null)
				{
					var dur = _fmtDuration(p);
					vocalsInfoText.text    = haxe.io.Path.withoutDirectory(p) + (dur != "" ? "  ·  " + dur : "");
					vocalsInfoText.visible = true;
				}
				updateFileStatus();
				updateStatus("\u2713 Voices.ogg selected");
			});
			fd.browse(OPEN, "ogg", null, "Selected Voices.ogg");
			#else updateStatus("Desktop only"); #end
		}, 0.47);
		vocalsStatusText = _statusIcon(g, cx + fileW + 6, cy + 10, 0.49);

		vocalsInfoText = new FlxText(cx, cy + 40, fileW, "", 10);
		vocalsInfoText.setFormat(Paths.font("vcr.ttf"), 10,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		vocalsInfoText.visible = false;
		g.add(vocalsInfoText);

		// ── Contenedor dinámico de slots (visible cuando split=true) ──────────
		_slotContainer = new FlxTypedGroup<Dynamic>();
		g.add(_slotContainer);

		// Slots iniciales: bf + dad
		vocalSlots = [];
		_buildVocalSlotUI({charName: "bf",  filePath: "", loaded: false, btn: null, statusText: null, nameInput: null});
		_buildVocalSlotUI({charName: "dad", filePath: "", loaded: false, btn: null, statusText: null, nameInput: null});

		// ── Botón + agregar slot (debajo de los slots) ────────────────────────
		_addSlotBtn = new FlxButton(cx, _vocalAreaY + vocalSlots.length * 54 - 6,
			"+ Add character", _onAddSlot);
		_styleBtn(_addSlotBtn, 0xFF388E3C, 180);
		_addSlotBtn.alpha = 0; _slotContainer.add(_addSlotBtn);
		FlxTween.tween(_addSlotBtn, {alpha: 1}, 0.3, {startDelay: 0.52});

		// ── Icon ──────────────────────────────────────────────────────────────
		// Se posiciona dinámicamente; _repositionSlotControls lo mueve siempre.
		final iconY = _vocalAreaY + 50;   // posición inicial (sin split)
		loadIconBtn = _fileBtn(g, cx, iconY, "  [Img]  Load Icon.png",
			funkin.debug.themes.EditorTheme.current.bgHover, fileW, function()
		{
			#if desktop
			var fd = new FileDialog();
			fd.onSelect.add(function(p:String)
			{
				currentIconPath = p; iconFileLoaded = true;
				updateFileStatus();
				updateStatus("\u2713 Icon.png selected");
			});
			fd.browse(OPEN, "png", null, "Select Icon.png");
			#else updateStatus("Desktop only"); #end
		}, 0.50);
		iconStatusText = _statusIcon(g, cx + fileW + 6, iconY + 10, 0.52);

		updateFileStatus();
		_rebuildVocalSlots();

		// Posicionar icon según el estado inicial (sin split)
		_repositionSlotControls();
	}

	/**
	 * Crea la UI de un slot vocal en _slotContainer.
	 * Si el slot ya tiene btn/statusText/nameInput, los reutiliza.
	 */
	function _buildVocalSlotUI(slot:VocalSlot):Void
	{
		var g     = _slotContainer;
		var cx    = windowX + 40;
		var fileW = windowWidth - 80;
		var slotIndex = vocalSlots.length;

		// Posición correcta: justo debajo de _vocalAreaY, apilados verticalmente.
		var slotY = _vocalAreaY + slotIndex * 54;

		// Icono del personaje — reserva 36px a la izquierda del nameInput
		// (inicialmente oculto; _populateExistingAudioInfo lo llena en edit mode)
		var icon = new FlxSprite(cx, slotY + 3);
		icon.makeGraphic(32, 32, 0x00000000); // transparente hasta ser cargado
		icon.visible = false;
		icon.scrollFactor.set();
		g.add(icon);
		slot.charIcon = icon;

		// Input de nombre del personaje (desplazado 38px para dejar hueco al icono)
		var nameIn = _inp(g, cx + 38, slotY, 88, slot.charName, 30, 0.47 + slotIndex * 0.02);
		nameIn.callback = function(t:String, _:String) slot.charName = t;

		// Botón de carga
		var charCapture = slot;
		var btn = _fileBtn(g, cx + 134, slotY, "  [Voice]  Voices-" + slot.charName + ".ogg",
			0xFF1565C0, fileW - 174, function()
		{
			#if desktop
			var label = charCapture.charName != "" ? charCapture.charName : "character";
			var fd = new FileDialog();
			fd.onSelect.add(function(p:String)
			{
				charCapture.filePath = p;
				charCapture.loaded   = true;
				// Refresca info text con el nuevo archivo
				if (charCapture.infoText != null)
				{
					var dur = _fmtDuration(p);
					charCapture.infoText.text    = haxe.io.Path.withoutDirectory(p) + (dur != "" ? "  ·  " + dur : "");
					charCapture.infoText.visible = true;
				}
				updateFileStatus();
				updateStatus("\u2713 Voices-" + label + ".ogg selected");
			});
			fd.browse(OPEN, "ogg", null, "Select Voices-" + label + ".ogg");
			#else updateStatus("Desktop only"); #end
		}, 0.47 + slotIndex * 0.02);

		// Botón − quitar slot (no en los dos primeros por defecto)
		if (slotIndex >= 2)
		{
			var removeBtn = new FlxButton(cx + fileW - 30, slotY, "✕", function()
			{
				_removeVocalSlot(charCapture);
			});
			_styleBtn(removeBtn, 0xFFc0392b, 34);
			removeBtn.alpha = 0; g.add(removeBtn);
			FlxTween.tween(removeBtn, {alpha: 1}, 0.3, {startDelay: 0.5 + slotIndex * 0.02});
		}

		var statusTxt = _statusIcon(g, cx + fileW + 6, slotY + 10, 0.49 + slotIndex * 0.02);

		slot.nameInput  = nameIn;
		slot.btn        = btn;
		slot.statusText = statusTxt;

		// Info de archivo (nombre + duración) — oculto hasta edit mode
		var info = new FlxText(cx + 134, slotY + 40, fileW - 174, "", 10);
		info.setFormat(Paths.font("vcr.ttf"), 10,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		info.visible = false;
		g.add(info);
		slot.infoText = info;

		vocalSlots.push(slot);
	}

	function _onAddSlot():Void
	{
		var newSlot:VocalSlot = {charName: "char" + (vocalSlots.length + 1), filePath: "", loaded: false,
		                          btn: null, statusText: null, nameInput: null};
		_buildVocalSlotUI(newSlot);
		_repositionSlotControls();
		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.5);
	}

	function _removeVocalSlot(slot:VocalSlot):Void
	{
		vocalSlots.remove(slot);
		_repositionSlotControls();
		FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.5);
	}

	/** Reposiciona iconBtn y _addSlotBtn después de añadir/quitar slots. */
	function _repositionSlotControls():Void
	{
		var cx    = windowX + 40;
		var fileW = windowWidth - 80;
		// Cuántos slots hay ahora (en split) — en unified siempre 0 slot visible
		var slotsBottom = _vocalAreaY + (splitVocals ? vocalSlots.length * 54 : 50);

		if (_addSlotBtn   != null) _addSlotBtn.y   = slotsBottom - 6;
		if (loadIconBtn   != null) loadIconBtn.y   = slotsBottom + 44;
		if (iconStatusText != null) iconStatusText.y = slotsBottom + 54;
	}

	/**
	 * Muestra/oculta los controles de vocals (unificado vs split)
	 * y el panel dinámico de slots.
	 */
	function _rebuildVocalSlots():Void
	{
		var showUnified = needsVoices && !splitVocals;
		var showSplit   = needsVoices &&  splitVocals;

		if (loadVocalsBtn    != null) loadVocalsBtn.visible    = showUnified;
		if (vocalsStatusText != null) vocalsStatusText.visible = showUnified;

		if (_slotContainer != null)
		{
			// FIX: Reflect.hasField falla para propiedades con setter en Haxe.
			// Usar isOfType + cast directo para acceder a visible correctamente.
			for (m in _slotContainer.members)
			{
				if (m == null) continue;
				if (Std.isOfType(m, flixel.FlxBasic))
					cast(m, flixel.FlxBasic).visible = showSplit;
			}
		}
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  PASO 2 — DIFICULTADES & IMPORT DE CHART
	// ═════════════════════════════════════════════════════════════════════════

	/**
	 * Construye el UI del paso 2: selección de dificultades y opción de importar
	 * charts en cualquier formato soportado (V-Slice, Psych, osu!mania,
	 * StepMania, Codename, .level).
	 *
	 * Cada fila de dificultad tiene:
	 *   [ON/OFF] [Label editable] [Sufijo editable] [Import chart…] [estado] [badge formato]
	 * El botón de importar detecta el formato automáticamente y, en archivos
	 * multi-dificultad, muestra un selector de clave para elegir qué diff usar.
	 */
	function _buildStep2():Void
	{
		var g  = stepGroups[1];
		var cx = windowX + 40;
		var cy = windowY + 68;

		// ── Cabecera ──────────────────────────────────────────────────────────
		_lbl(g, cx, cy, "Difficulties & Chart Import", 0.28);

		var hint = new FlxText(cx, cy + 22, windowWidth - 80,
			"Toggle which difficulties you want. Optionally import a chart for each one.", 11);
		hint.setFormat(Paths.font("vcr.ttf"), 11,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		hint.alpha = 0; g.add(hint);
		FlxTween.tween(hint, {alpha: 0.75}, 0.3, {startDelay: 0.3});

		cy += 48;

		// ── Separador ─────────────────────────────────────────────────────────
		var sep = new FlxSprite(windowX + 20, cy);
		sep.makeGraphic(windowWidth - 40, 2,
			funkin.debug.themes.EditorTheme.current.borderColor);
		sep.alpha = 0; g.add(sep);
		FlxTween.tween(sep, {alpha: 0.5}, 0.3, {startDelay: 0.32});
		cy += 10;

		// ── Encabezados de columna ────────────────────────────────────────────
		var colHeader = new FlxText(cx + 96, cy, 0, "LABEL               SUFFIX    IMPORT CHART", 11);
		colHeader.setFormat(Paths.font("vcr.ttf"), 11,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		colHeader.alpha = 0; g.add(colHeader);
		FlxTween.tween(colHeader, {alpha: 0.65}, 0.3, {startDelay: 0.34});
		cy += 18;

		_diffListY = cy;

		// ── Contenedor de filas ───────────────────────────────────────────────
		_diffRowContainer = new FlxTypedGroup<Dynamic>();
		g.add(_diffRowContainer);

		// Inicializar dificultades por defecto
		if (diffEntries.length == 0)
			_initDefaultDiffs();

		_rebuildDiffRows();

		// ── Botón + Añadir dificultad ─────────────────────────────────────────
		_addDiffBtn = new FlxButton(cx, _diffListY + diffEntries.length * _diffRowH() + 6,
			"+ Add difficulty", _onAddDiff);
		_styleBtn(_addDiffBtn, 0xFF388E3C, 180);
		_addDiffBtn.alpha = 0; g.add(_addDiffBtn);
		FlxTween.tween(_addDiffBtn, {alpha: 1}, 0.3, {startDelay: 0.55});

		// ── Nota de formatos soportados ───────────────────────────────────────
		var fmtNote = new FlxText(cx, _diffListY + diffEntries.length * _diffRowH() + 52,
			windowWidth - 80,
			"Supported: V-Slice JSON · Psych JSON · osu!mania · StepMania SM/SSC · Codename JSON · .level", 10);
		fmtNote.setFormat(Paths.font("vcr.ttf"), 10,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		fmtNote.alpha = 0; g.add(fmtNote);
		FlxTween.tween(fmtNote, {alpha: 0.6}, 0.3, {startDelay: 0.6});
		_fmtNoteLabel = fmtNote;
	}

	/** Referencia al label de nota de formatos (para reposicionarlo al cambiar nº de diffs). */
	var _fmtNoteLabel:FlxText = null;

	/** Altura de cada fila de dificultad en píxeles. */
	inline function _diffRowH():Int return 52;

	/** Inicializa las 3 dificultades clásicas (easy / normal / hard). */
	function _initDefaultDiffs():Void
	{
		// En edit mode: intentar auto-detectar desde el chart existente
		#if sys
		if (editMode && editingSong != null)
		{
			var songLower = editingSong.songName.toLowerCase();
			var detected  = funkin.data.Song.getAvailableDifficulties(songLower);
			if (detected != null && detected.length > 0)
			{
				// Comprobar si ya existe un .level para este song
				var levelPath = _contentRoot() + '/songs/$songLower/$songLower.level';
				var hasLevel  = sys.FileSystem.exists(levelPath);

				for (pair in detected)
				{
					var suffix = pair[1];
					var entry:DiffEntry = {
						label:        pair[0],
						suffix:       suffix,
						enabled:      true,
						chartPath:    '',
						chartFormat:  '',
						chartDiffKey: ''
					};

					// Si ya existe el .level, marcar la diff como ya importada
					if (hasLevel)
					{
						entry.chartPath    = levelPath;
						entry.chartFormat  = 'level';
						// La clave dentro del .level es el sufijo (sin el guion inicial)
						entry.chartDiffKey = suffix.startsWith('-') ? suffix.substr(1) : suffix;
					}

					diffEntries.push(entry);
				}

				// Auto-leer BPM del .level si el campo está en el default (120 o vacío)
				if (hasLevel && bpmInput != null)
					_autoFillBpmFromLevel(levelPath);

				return;
			}
		}
		#end
		// Fallback: easy / normal / hard
		diffEntries = [
			{ label:'Easy',   suffix:'-easy',   enabled:true, chartPath:'', chartFormat:'', chartDiffKey:'' },
			{ label:'Normal', suffix:'',         enabled:true, chartPath:'', chartFormat:'', chartDiffKey:'' },
			{ label:'Hard',   suffix:'-hard',    enabled:true, chartPath:'', chartFormat:'', chartDiffKey:'' }
		];
	}

	/**
	 * Lee el BPM del primer diff disponible en un .level y rellena bpmInput
	 * si el campo todavía está en el valor por defecto.
	 */
	function _autoFillBpmFromLevel(levelPath:String):Void
	{
		#if sys
		if (bpmInput == null) return;
		final _curBpm = Std.parseFloat(bpmInput.text);
		// Solo sobreescribir si está en default o vacío
		if (!Math.isNaN(_curBpm) && _curBpm > 0 && bpmInput.text != '120') return;
		try
		{
			var bpm = _extractBpmFromChart(levelPath, 'level', '');
			if (bpm > 0)
			{
				bpmInput.text = bpm == Math.ffloor(bpm)
					? Std.string(Std.int(bpm))
					: Std.string(Math.round(bpm * 100) / 100);
			}
		}
		catch (_:Dynamic) {}
		#end
	}

	/**
	 * Reconstruye todas las filas de dificultad en _diffRowContainer.
	 * Se llama al añadir/quitar diffs y al entrar en el paso.
	 */
	function _rebuildDiffRows():Void
	{
		if (_diffRowContainer == null) return;
		_diffRowContainer.clear();

		var cx = windowX + 40;
		var delay = 0.36;
		for (i in 0...diffEntries.length)
		{
			_buildDiffRow(diffEntries[i], i, cx, delay + i * 0.03);
		}

		// Reposicionar botón añadir y nota
		_repositionDiffFooter();
	}

	/** Construye los controles de UNA fila de dificultad. */
	function _buildDiffRow(entry:DiffEntry, idx:Int, cx:Float, delay:Float):Void
	{
		var g  = _diffRowContainer;
		var rY = _diffListY + idx * _diffRowH();

		// ── Toggle habilitado ──────────────────────────────────────────────────
		var eBtn = new FlxButton(cx, rY + 8, "", function()
		{
			entry.enabled = !entry.enabled;
			_refreshDiffRowToggle(entry);
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.55);
			// Actualizar el botón de importar (deshabilitado si la diff está off)
			if (entry.importBtn != null)
				entry.importBtn.alpha = entry.enabled ? 1.0 : 0.35;
		});
		eBtn.makeGraphic(88, 34, entry.enabled ? 0xFF4CAF50 : 0xFFFF5252);
		eBtn.alpha = 0; g.add(eBtn);
		FlxTween.tween(eBtn, {alpha: 1}, 0.25, {startDelay: delay});
		entry.enableBtn = eBtn;

		var eTxt = new FlxText(cx + 7, rY + 10, 74, entry.enabled ? "ON" : "OFF", 13);
		eTxt.setFormat(Paths.font("vcr.ttf"), 13,
			entry.enabled ? 0xFF4CAF50 : 0xFFFF5252, CENTER);
		eTxt.alpha = 0; g.add(eTxt);
		FlxTween.tween(eTxt, {alpha: 1}, 0.25, {startDelay: delay});
		entry.enableTxt = eTxt;

		// ── Input: Label (ej. "Easy") ──────────────────────────────────────────
		var labIn = new FlxInputText(cx + 96, rY + 8, 120, entry.label, 13);
		labIn.backgroundColor      = funkin.debug.themes.EditorTheme.current.bgHover;
		labIn.fieldBorderColor     = funkin.debug.themes.EditorTheme.current.borderColor;
		labIn.fieldBorderThickness = 2;
		labIn.color    = flixel.util.FlxColor.WHITE;
		labIn.maxLength = 20;
		labIn.callback = function(t:String, _:String) entry.label = t;
		labIn.alpha = 0; g.add(labIn);
		FlxTween.tween(labIn, {alpha: 1}, 0.25, {startDelay: delay});
		entry.labelInput = labIn;

		// ── Input: Sufijo (ej. "-easy") ────────────────────────────────────────
		var sufIn = new FlxInputText(cx + 224, rY + 8, 90, entry.suffix, 13);
		sufIn.backgroundColor      = funkin.debug.themes.EditorTheme.current.bgHover;
		sufIn.fieldBorderColor     = funkin.debug.themes.EditorTheme.current.borderColor;
		sufIn.fieldBorderThickness = 2;
		sufIn.color    = flixel.util.FlxColor.WHITE;
		sufIn.maxLength = 20;
		sufIn.callback = function(t:String, _:String) entry.suffix = t;
		sufIn.alpha = 0; g.add(sufIn);
		FlxTween.tween(sufIn, {alpha: 1}, 0.25, {startDelay: delay});

		// ── Botón Import chart ─────────────────────────────────────────────────
		var entryCapture = entry;
		var impW = 190;
		// Texto del botón: si ya hay chart importado mostrar "✓ Replace chart…",
		// si es .level existente mostrar "✓ In .level  [Re-import]"
		var impLabel = entry.chartPath != ''
			? (entry.chartFormat == 'level' ? "  \u2713 In .level \u2014 Replace?" : "  \u2713 Replace chart\u2026")
			: "  Import chart\u2026";
		var impBtn = new FlxButton(cx + 322, rY + 4, impLabel, function()
		{
			if (!entryCapture.enabled) return;
			_importChartForDiff(entryCapture);
		});
		impBtn.makeGraphic(impW, 38,
			entry.chartPath != '' ? 0xFF1565C0 : funkin.debug.themes.EditorTheme.current.bgHover);
		impBtn.label.setFormat(Paths.font("vcr.ttf"), 13,
			flixel.util.FlxColor.WHITE, LEFT);
		impBtn.alpha = entry.enabled ? 0.0 : 0.35;
		g.add(impBtn);
		if (entry.enabled)
			FlxTween.tween(impBtn, {alpha: 1}, 0.25, {startDelay: delay});
		entry.importBtn = impBtn;

		// ── Icono de estado (✓/✗) ─────────────────────────────────────────────
		var sTxt = new FlxText(cx + 520, rY + 12, 0,
			entry.chartPath != '' ? "\u2713" : "\u2014", 18);
		sTxt.setFormat(Paths.font("vcr.ttf"), 18,
			entry.chartPath != '' ? flixel.util.FlxColor.GREEN
			                      : funkin.debug.themes.EditorTheme.current.textSecondary,
			LEFT);
		sTxt.alpha = 0; g.add(sTxt);
		FlxTween.tween(sTxt, {alpha: 1}, 0.25, {startDelay: delay});
		entry.statusTxt = sTxt;

		// ── Badge de formato ───────────────────────────────────────────────────
		var fmtTxt = new FlxText(cx + 540, rY + 14, 240,
			entry.chartFormat != '' ? _formatLabel(entry) : "", 11);
		fmtTxt.setFormat(Paths.font("vcr.ttf"), 11, 0xFFCE93D8, LEFT);
		fmtTxt.alpha = 0; g.add(fmtTxt);
		FlxTween.tween(fmtTxt, {alpha: entry.chartFormat != '' ? 1.0 : 0.0}, 0.25, {startDelay: delay});
		entry.formatBadge = fmtTxt;

		// ── Selector de clave (para multi-diff) ───────────────────────────────
		// Solo visible cuando hay availableKeys con >1 opción
		var kBtnW = 160;
		var kBtn = new FlxButton(cx + 322, rY + 38 + 4, "", function()
		{
			_cycleChartDiffKey(entryCapture);
		});
		kBtn.makeGraphic(kBtnW, 22, 0xFF37474F);
		kBtn.label.setFormat(Paths.font("vcr.ttf"), 10,
			flixel.util.FlxColor.WHITE, LEFT);
		kBtn.visible = (entry.availableKeys != null && entry.availableKeys.length > 1);
		kBtn.alpha   = 0; g.add(kBtn);
		if (kBtn.visible)
			FlxTween.tween(kBtn, {alpha: 1}, 0.25, {startDelay: delay});
		entry.keyBtn = kBtn;
		_refreshKeyBtn(entry);

		// ── Botón − eliminar (no en las 3 primeras si solo hay 3) ─────────────
		if (idx >= 3 || diffEntries.length > 3)
		{
			var delBtn = new FlxButton(cx + windowWidth - 100, rY + 8, "✕", function()
			{
				diffEntries.remove(entryCapture);
				_rebuildDiffRows();
				FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.5);
			});
			_styleBtn(delBtn, 0xFFc0392b, 34);
			delBtn.alpha = 0; g.add(delBtn);
			FlxTween.tween(delBtn, {alpha: 1}, 0.25, {startDelay: delay});
		}
	}

	/** Refresca el botón de toggle ON/OFF y su texto. */
	function _refreshDiffRowToggle(entry:DiffEntry):Void
	{
		if (entry.enableBtn == null) return;
		entry.enableBtn.makeGraphic(88, 34, entry.enabled ? 0xFF4CAF50 : 0xFFFF5252);
		if (entry.enableTxt != null)
		{
			entry.enableTxt.text  = entry.enabled ? "ON" : "OFF";
			entry.enableTxt.color = entry.enabled ? 0xFF4CAF50 : 0xFFFF5252;
		}
	}

	/** Reposiciona el botón de añadir y el label de formatos. */
	function _repositionDiffFooter():Void
	{
		var footerY = _diffListY + diffEntries.length * _diffRowH() + 6;
		if (_addDiffBtn   != null) _addDiffBtn.y   = footerY;
		if (_fmtNoteLabel != null) _fmtNoteLabel.y = footerY + 46;
	}

	/** Callback: añadir una nueva fila de dificultad. */
	function _onAddDiff():Void
	{
		diffEntries.push({
			label:       'Diff${diffEntries.length + 1}',
			suffix:      '-diff${diffEntries.length + 1}',
			enabled:     true,
			chartPath:   '',
			chartFormat: '',
			chartDiffKey: ''
		});
		_rebuildDiffRows();
		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.5);
	}

	// ── Importación de charts ─────────────────────────────────────────────────

	/**
	 * Abre el selector de archivo para importar un chart para `entry`.
	 * Detecta el formato automáticamente y extrae dificultades disponibles
	 * para formatos multi-diff.
	 */
	function _importChartForDiff(entry:DiffEntry):Void
	{
		#if desktop
		var fd = new lime.ui.FileDialog();
		fd.onSelect.add(function(path:String)
		{
			_processImportedChart(entry, path);
		});
		// Filtro de extensiones (no todos los FileDialog soportan múltiples)
		fd.browse(OPEN, null, null, "Select chart (JSON / .osu / .sm / .ssc / .level / .hxc)");
		#else
		updateStatus("Chart import is desktop-only.");
		#end
	}

	/**
	 * Detecta el formato del archivo y rellena los campos de `entry`.
	 */
	function _processImportedChart(entry:DiffEntry, path:String):Void
	{
		#if sys
		if (!sys.FileSystem.exists(path))
		{
			updateStatus("\u26a0 File not found: " + haxe.io.Path.withoutDirectory(path));
			return;
		}

		var ext = path.toLowerCase();
		var dotIdx = ext.lastIndexOf('.');
		var extStr = dotIdx >= 0 ? ext.substr(dotIdx + 1) : '';

		entry.chartPath    = path;
		entry.availableKeys = [];
		entry.chartDiffKey  = '';

		if (extStr == 'osu')
		{
			// osu!mania — un solo diff por archivo
			entry.chartFormat = 'osu';
			entry.availableKeys = ['(default)'];
			entry.chartDiffKey  = '';
		}
		else if (extStr == 'sm' || extStr == 'ssc')
		{
			// StepMania — puede tener múltiples diffs dentro
			entry.chartFormat = 'sm';
			var keys = _smDiffKeys(path);
			entry.availableKeys = keys.length > 0 ? keys : ['(default)'];
			entry.chartDiffKey  = entry.availableKeys[0];
		}
		else if (extStr == 'json' || extStr == 'level')
		{
			// Detectar sub-formato por contenido
			try
			{
				var raw:Dynamic = extStr == 'level'
					? haxe.Json.parse(sys.io.File.getContent(path))
					: haxe.Json.parse(sys.io.File.getContent(path));

				if (extStr == 'level')
				{
					// Cool Engine .level
					entry.chartFormat   = 'level';
					var diffs = raw.difficulties != null
						? [for (k in Reflect.fields(raw.difficulties)) k]
						: ['(default)'];
					entry.availableKeys = diffs;
					entry.chartDiffKey  = _pickClosestDiff(diffs, entry.suffix);
				}
				else if (raw.version != null && Std.isOfType(raw.version, String)
				         && (raw.notes != null || raw.scrollSpeed != null))
				{
					// V-Slice JSON (tiene "version": "2.x.x" + "notes" objeto)
					entry.chartFormat = 'vslice';
					var keys:Array<String> = [];
					if (raw.notes != null)
						for (k in Reflect.fields(raw.notes)) keys.push(k);
					entry.availableKeys = keys.length > 0 ? keys : ['(default)'];
					entry.chartDiffKey  = _pickClosestDiff(entry.availableKeys, entry.suffix);
				}
				else if (raw.song != null && Std.isOfType(raw.song, Dynamic)
				         && Reflect.hasField(raw.song, 'notes'))
				{
					// Psych Engine JSON (tiene "song": { "notes": [...] })
					entry.chartFormat   = 'psych';
					entry.availableKeys = ['(default)'];
					entry.chartDiffKey  = '';
				}
				else if (raw.sprites != null || raw.props != null)
				{
					// Codename Engine JSON (stage / chart)
					entry.chartFormat   = 'codename';
					var keys:Array<String> = raw.difficulties != null
						? [for (k in Reflect.fields(raw.difficulties)) k]
						: ['(default)'];
					entry.availableKeys = keys;
					entry.chartDiffKey  = _pickClosestDiff(keys, entry.suffix);
				}
				else
				{
					// JSON genérico — intentar como Psych
					entry.chartFormat   = 'psych';
					entry.availableKeys = ['(default)'];
					entry.chartDiffKey  = '';
				}
			}
			catch (e:Dynamic)
			{
				updateStatus("\u26a0 Could not parse chart: " + haxe.io.Path.withoutDirectory(path));
				entry.chartPath   = '';
				entry.chartFormat = '';
				return;
			}
		}
		else if (extStr == 'hxc' || extStr == 'hx' || extStr == 'hscript')
		{
			// Script de stage/chart — no convertible directamente
			updateStatus("\u26a0 .hxc/.hx files are stage scripts, not charts.");
			entry.chartPath   = '';
			entry.chartFormat = '';
			return;
		}
		else
		{
			updateStatus("\u26a0 Unsupported format: ." + extStr);
			entry.chartPath   = '';
			entry.chartFormat = '';
			return;
		}

		_refreshDiffRowStatus(entry);

		// ── Auto-detectar BPM del chart importado ─────────────────────────────
		// Si el campo BPM está vacío, en 0 o aún en el default "120", intentar
		// extraer el BPM del archivo para evitar que el usuario tenga que buscarlo.
		final _detectedBpm = _extractBpmFromChart(path, entry.chartFormat, entry.chartDiffKey);
		if (_detectedBpm > 0 && bpmInput != null)
		{
			final _curBpm = Std.parseFloat(bpmInput.text);
			final _isDefault = Math.isNaN(_curBpm) || _curBpm <= 0
			                || bpmInput.text == '120' || bpmInput.text == '0';
			if (_isDefault)
			{
				bpmInput.text = _detectedBpm == Math.ffloor(_detectedBpm)
					? Std.string(Std.int(_detectedBpm))
					: Std.string(Math.round(_detectedBpm * 100) / 100);
				updateStatus('\u2713 Chart imported \u2014 BPM auto-detected: ${bpmInput.text} (' + _formatLabel(entry) + ')');
			}
			else
			{
				updateStatus('\u2713 Chart imported for ${entry.label} (${_formatLabel(entry)}) \u2014 detected BPM: ${_detectedBpm}');
			}
		}
		else
		{
			updateStatus('\u2713 Chart imported for ' + entry.label + ' (' + _formatLabel(entry) + ')');
		}
		FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);
		#end
	}

	/**
	 * Lee las dificultades disponibles de un archivo StepMania (.sm/.ssc).
	 * Extrae los nombres de NOTES o CHART blocks.
	 */
	function _smDiffKeys(path:String):Array<String>
	{
		#if sys
		var keys:Array<String> = [];
		try
		{
			var content = sys.io.File.getContent(path);
			// En .sm: #NOTES: / dance-single / <description> / <difficulty> / <meter> / <data>
			// Buscamos líneas que empiecen con la dificultad tras el segundo ":"
			var lines = content.split('\n');
			var ext   = path.toLowerCase();
			if (ext.endsWith('.ssc'))
			{
				// SSC: #DIFFICULTY:Easy;
				for (l in lines)
				{
					var lt = l.trim().toUpperCase();
					if (lt.startsWith('#DIFFICULTY:'))
					{
						var val = lt.substr(12).replace(';', '').trim();
						if (val != '' && !keys.contains(val)) keys.push(val);
					}
				}
			}
			else
			{
				// SM legacy: buscar tokens de dificultad en bloque NOTES
				var inNotes = false;
				var fieldIdx = 0;
				for (l in lines)
				{
					var lt = l.trim();
					if (lt.toUpperCase().startsWith('#NOTES:')) { inNotes = true; fieldIdx = 0; continue; }
					if (inNotes)
					{
						if (lt == ';' || (lt.endsWith(';') && fieldIdx >= 5)) { inNotes = false; fieldIdx = 0; continue; }
						if (lt.endsWith(':')) fieldIdx++;
						if (fieldIdx == 3)   // 3er campo = dificultad
						{
							var val = lt.replace(':', '').replace(';', '').trim().toUpperCase();
							if (val != '' && !keys.contains(val)) keys.push(val);
						}
					}
				}
			}
		}
		catch (_) {}
		return keys;
		#else
		return [];
		#end
	}

	/**
	 * Extrae el BPM de un archivo de chart importado según su formato.
	 * Soporta: V-Slice JSON, Psych JSON, Codename JSON, osu!mania, StepMania SM/SSC, .level.
	 * Devuelve 0 si no se puede determinar.
	 *
	 * Se llama automáticamente en _processImportedChart() para rellenar bpmInput.
	 */
	function _extractBpmFromChart(path:String, format:String, diffKey:String):Float
	{
		#if sys
		if (path == '' || !sys.FileSystem.exists(path)) return 0;
		try
		{
			var ext = path.toLowerCase();
			ext = ext.substr(ext.lastIndexOf('.') + 1);

			switch (ext)
			{
				case 'json' | 'level':
					var raw:Dynamic = haxe.Json.parse(sys.io.File.getContent(path));

					switch (format)
					{
						case 'vslice':
							// V-Slice chart JSON: "timeChanges": [{"bpm":120.0,...}]
							if (raw.timeChanges != null)
							{
								var tc:Array<Dynamic> = cast raw.timeChanges;
								if (tc.length > 0 && tc[0].bpm != null)
									return Std.parseFloat(Std.string(tc[0].bpm));
							}
							// Fallback: campo bpm directo (algunos exports custom)
							if (raw.bpm != null) return Std.parseFloat(Std.string(raw.bpm));

						case 'psych':
							// Psych: {"song": {"bpm": 120}} o {"bpm": 120}
							var songObj:Dynamic = (raw.song != null && !Std.isOfType(raw.song, String))
								? raw.song : raw;
							if (songObj.bpm != null)
								return Std.parseFloat(Std.string(songObj.bpm));

						case 'codename':
							// Codename: bpm a nivel raíz o en strumLines
							if (raw.bpm != null)
								return Std.parseFloat(Std.string(raw.bpm));
							if (raw.meta != null && raw.meta.bpm != null)
								return Std.parseFloat(Std.string(raw.meta.bpm));

						case 'level':
							// .level: { "difficulties": { "": { "bpm": 120 } } }
							if (raw.difficulties != null)
							{
								// Intentar con la clave exacta primero, luego la primera disponible
								var tryKey = diffKey != '' ? diffKey : null;
								if (tryKey != null)
								{
									var song:Dynamic = Reflect.field(raw.difficulties, tryKey);
									if (song != null && song.bpm != null)
										return Std.parseFloat(Std.string(song.bpm));
								}
								for (k in Reflect.fields(raw.difficulties))
								{
									var song:Dynamic = Reflect.field(raw.difficulties, k);
									if (song != null && song.bpm != null)
										return Std.parseFloat(Std.string(song.bpm));
								}
							}

						case _:
							// JSON genérico — intentar campo bpm en varias posiciones
							var songObj:Dynamic = (raw.song != null && !Std.isOfType(raw.song, String))
								? raw.song : raw;
							if (songObj.bpm != null) return Std.parseFloat(Std.string(songObj.bpm));
					}

				case 'osu':
					// osu!mania TimingPoints: offset,interval,...
					// BPM = 60000 / interval (solo el primero que sea positivo = timing real)
					var content = sys.io.File.getContent(path);
					var inTP    = false;
					for (line in content.split('\n'))
					{
						var lt = line.trim();
						if (lt == '[TimingPoints]') { inTP = true; continue; }
						if (lt.startsWith('[') && inTP) break;
						if (inTP && lt.length > 0 && !lt.startsWith('//'))
						{
							var parts = lt.split(',');
							if (parts.length >= 2)
							{
								var interval = Std.parseFloat(parts[1].trim());
								// Valores positivos = uninherited timing (BPM real)
								if (!Math.isNaN(interval) && interval > 0)
								{
									var bpm = Math.round((60000.0 / interval) * 100) / 100;
									if (bpm > 0) return bpm;
								}
							}
						}
					}

				case 'sm' | 'ssc':
					// StepMania: #BPMS:0.000=120.000,4.000=160.000;
					// o #BPM:120; (obsoleto)
					var content = sys.io.File.getContent(path);
					for (line in content.split('\n'))
					{
						var lt = line.trim().toUpperCase();
						if (lt.startsWith('#BPMS:'))
						{
							var val = lt.substr(6).replace(';', '').trim();
							for (pair in val.split(','))
							{
								var eq = pair.indexOf('=');
								if (eq >= 0)
								{
									var bpm = Std.parseFloat(pair.substr(eq + 1).trim());
									if (!Math.isNaN(bpm) && bpm > 0) return bpm;
								}
							}
						}
						else if (lt.startsWith('#BPM:'))
						{
							var bpm = Std.parseFloat(lt.substr(5).replace(';', '').trim());
							if (!Math.isNaN(bpm) && bpm > 0) return bpm;
						}
					}
			}
		}
		catch (e:Dynamic) { trace('[AddSong] BPM extraction error for "$path": $e'); }
		#end
		return 0;
	}
	function _pickClosestDiff(keys:Array<String>, suffix:String):String
	{
		if (keys == null || keys.length == 0) return '';
		var target = suffix.startsWith('-') ? suffix.substr(1).toLowerCase() : suffix.toLowerCase();
		for (k in keys)
			if (k.toLowerCase() == target) return k;
		// Partial match
		for (k in keys)
			if (k.toLowerCase().contains(target) || target.contains(k.toLowerCase())) return k;
		return keys[0];
	}

	/** Cicla al siguiente chartDiffKey disponible (botón keyBtn). */
	function _cycleChartDiffKey(entry:DiffEntry):Void
	{
		if (entry.availableKeys == null || entry.availableKeys.length <= 1) return;
		var idx = entry.availableKeys.indexOf(entry.chartDiffKey);
		idx = (idx + 1) % entry.availableKeys.length;
		entry.chartDiffKey = entry.availableKeys[idx];
		_refreshKeyBtn(entry);
		_refreshDiffRowStatus(entry);
		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.5);
	}

	/** Refresca el botón selector de clave con el valor actual. */
	function _refreshKeyBtn(entry:DiffEntry):Void
	{
		if (entry.keyBtn == null) return;
		var hasMultiple = entry.availableKeys != null && entry.availableKeys.length > 1;
		entry.keyBtn.visible = hasMultiple && entry.chartPath != '';
		if (!hasMultiple) return;
		var cur = entry.chartDiffKey != '' ? entry.chartDiffKey : entry.availableKeys[0];
		entry.keyBtn.label.text = "  \u25C4\u25BA diff: " + cur;
	}

	/** Refresca el icono de estado y el badge de formato de una fila. */
	function _refreshDiffRowStatus(entry:DiffEntry):Void
	{
		if (entry.statusTxt != null)
		{
			var hasChart = entry.chartPath != '';
			entry.statusTxt.text  = hasChart ? "\u2713" : "\u2014";
			entry.statusTxt.color = hasChart
				? flixel.util.FlxColor.GREEN
				: funkin.debug.themes.EditorTheme.current.textSecondary;
		}
		if (entry.formatBadge != null)
		{
			entry.formatBadge.text  = entry.chartFormat != '' ? _formatLabel(entry) : '';
			entry.formatBadge.alpha = entry.chartFormat != '' ? 1.0 : 0.0;
		}
		if (entry.importBtn != null)
		{
			entry.importBtn.makeGraphic(190, 38,
				entry.chartPath != '' ? 0xFF1565C0
				                      : funkin.debug.themes.EditorTheme.current.bgHover);
			// Refrescar el texto del botón según el estado
			var impLabel = entry.chartPath != ''
				? (entry.chartFormat == 'level' ? "  \u2713 In .level \u2014 Replace?" : "  \u2713 Replace chart\u2026")
				: "  Import chart\u2026";
			entry.importBtn.label.text = impLabel;
		}
		_refreshKeyBtn(entry);
	}

	/** Genera el texto del badge de formato para una DiffEntry. */
	function _formatLabel(entry:DiffEntry):String
	{
		var fmt = switch (entry.chartFormat)
		{
			case 'vslice':   'V-Slice';
			case 'psych':    'Psych';
			case 'osu':      'osu!mania';
			case 'sm':       'StepMania';
			case 'codename': 'Codename';
			case 'level':    '.level';
			default: entry.chartFormat;
		};
		var key = (entry.chartDiffKey != '' && entry.chartDiffKey != '(default)')
			? ' [' + entry.chartDiffKey + ']' : '';
		return fmt + key;
	}

	// ─────────────────────────────────────────────────────────────────────────

	function _buildStep3():Void
	{
		var g = stepGroups[2];
		var cx = windowX + 40;
		var cy = windowY + 68;

		// ── Icon Name ─────────────────────────────────────────────────────────
		_lbl(g, cx, cy, "Icon Name  (\u2190 \u2192 to change preset):", 0.3);
		iconNameInput = _inp(g, cx, cy + 22, windowWidth - 80, iconPresets[0], 40, 0.35);

		cy += 72;

		// ── UI Script / Note Skin ─────────────────────────────────────────────
		var colW = Std.int((windowWidth - 100) / 2);
		_lbl(g, cx,          cy, "UI Script:", 0.38);
		_lbl(g, cx + colW + 20, cy, "Note Skin:", 0.38);
		uiInput       = _inp(g, cx,          cy + 22, colW, "default", 40, 0.40);
		noteSkinInput = _inp(g, cx + colW + 20, cy + 22, colW, "default", 40, 0.42);
		var h1 = new FlxText(cx, cy + 52, windowWidth - 80,
			"Leave 'default' to use global settings", 11);
		h1.setFormat(Paths.font("vcr.ttf"), 11,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		h1.alpha = 0; g.add(h1);
		FlxTween.tween(h1, {alpha: 0.7}, 0.3, {startDelay: 0.44});

		cy += 74;

		// ── Intro / Outro Video ───────────────────────────────────────────────
		_lbl(g, cx,          cy, "Intro Video:", 0.44);
		_lbl(g, cx + colW + 20, cy, "Outro Video:", 0.44);
		introVideoInput = _inp(g, cx,          cy + 22, colW, "", 80, 0.46);
		outroVideoInput = _inp(g, cx + colW + 20, cy + 22, colW, "", 80, 0.46);
		var h2 = new FlxText(cx, cy + 52, windowWidth - 80,
			"File name without extension (empty = no cutscene)", 11);
		h2.setFormat(Paths.font("vcr.ttf"), 11,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		h2.alpha = 0; g.add(h2);
		FlxTween.tween(h2, {alpha: 0.7}, 0.3, {startDelay: 0.48});

		cy += 74;

		// ── Artist ────────────────────────────────────────────────────────────
		_lbl(g, cx, cy, "Artist:", 0.50);
		artistInput = _inp(g, cx, cy + 22, windowWidth - 80, "", 80, 0.52);
		var h3 = new FlxText(cx, cy + 52, windowWidth - 80,
			"Displayed in the pause menu and Freeplay. Empty = reads from chart metadata.", 11);
		h3.setFormat(Paths.font("vcr.ttf"), 11,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		h3.alpha = 0; g.add(h3);
		FlxTween.tween(h3, {alpha: 0.7}, 0.3, {startDelay: 0.54});

		cy += 74;

		// ── Album ─────────────────────────────────────────────────────────────
		var colW = Std.int((windowWidth - 100) / 2);
		_lbl(g, cx,          cy, "Album Art Key:", 0.56);
		_lbl(g, cx + colW + 20, cy, "Album Text Key:", 0.56);
		albumInput     = _inp(g, cx,          cy + 22, colW, "", 60, 0.58);
		albumTextInput = _inp(g, cx + colW + 20, cy + 22, colW, "", 60, 0.58);
		var h4 = new FlxText(cx, cy + 52, windowWidth - 80,
			"Optional. File: images/menu/freeplay/albums/{key}.png  |  {key}.png+xml (animated text)", 11);
		h4.setFormat(Paths.font("vcr.ttf"), 11,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		h4.alpha = 0; g.add(h4);
		FlxTween.tween(h4, {alpha: 0.7}, 0.3, {startDelay: 0.60});
	}

	function _buildStep4():Void
	{
		var g = stepGroups[3];
		var cx = windowX + 40;
		var cy = windowY + 68;

		// ── Week Index ────────────────────────────────────────────────────────
		_lbl(g, cx, cy, "Week Index:", 0.30);
		weekInput = _inpNum(g, cx, cy + 22, 160, "0", 0.35);
		var hw = new FlxText(cx + 170, cy + 28, 320,
			"0 = first week, 1 = second, etc.", 11);
		hw.setFormat(Paths.font("vcr.ttf"), 11,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		hw.alpha = 0; g.add(hw);
		FlxTween.tween(hw, {alpha: 0.7}, 0.3, {startDelay: 0.38});

		cy += 66;


		// ── Separador ─────────────────────────────────────────────────────────
		var sep = new FlxSprite(windowX + 20, cy);
		sep.makeGraphic(windowWidth - 40, 2, funkin.debug.themes.EditorTheme.current.borderColor);
		sep.alpha = 0; g.add(sep);
		FlxTween.tween(sep, {alpha: 0.5}, 0.3, {startDelay: 0.46});

		cy += 16;

		// ── Color del menú — ColorPickerWheel ────────────────────────────────
		var lc = new FlxText(cx, cy, 0, "Color in the menu:", 16);
		lc.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT);
		lc.alpha = 0; g.add(lc);
		FlxTween.tween(lc, {alpha: 1}, 0.3, {startDelay: 0.48});

		cy += 30;

		// Swatch cuadrado que muestra el color actual
		colorSwatchBtn = new FlxButton(cx, cy, "", _openColorPicker);
		colorSwatchBtn.makeGraphic(48, 48, Std.parseInt(selectedColor));
		colorSwatchBtn.alpha = 0; g.add(colorSwatchBtn);
		FlxTween.tween(colorSwatchBtn, {alpha: 1}, 0.3, {startDelay: 0.50});

		var pickerBtn = new FlxButton(cx + 58, cy + 7, "[Color]  Select color...", _openColorPicker);
		_styleBtn(pickerBtn, funkin.debug.themes.EditorTheme.current.bgHover, 170);
		pickerBtn.alpha = 0; g.add(pickerBtn);
		FlxTween.tween(pickerBtn, {alpha: 1}, 0.3, {startDelay: 0.52});

		colorSwatchLabel = new FlxText(cx + 238, cy + 16, 200, selectedColor, 13);
		colorSwatchLabel.setFormat(Paths.font("vcr.ttf"), 13, FlxColor.WHITE, LEFT);
		colorSwatchLabel.alpha = 0; g.add(colorSwatchLabel);
		FlxTween.tween(colorSwatchLabel, {alpha: 0.9}, 0.3, {startDelay: 0.54});

		_refreshColorSwatch();
	}

	/** Abre el ColorPickerWheel y aplica el color seleccionado al volver. */
	function _openColorPicker():Void
	{
		var current:flixel.util.FlxColor = Std.parseInt(selectedColor);
		var picker = new ColorPickerWheel(current);
		picker.onColorSelected = function(c:flixel.util.FlxColor)
		{
			selectedColor = "0x" + c.toHexString(true, true).toUpperCase();
			_refreshColorSwatch();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.5);
		};
		openSubState(picker);
	}

	/** Refresca el swatch y el label hex con el color actual. */
	function _refreshColorSwatch():Void
	{
		if (colorSwatchBtn   != null) colorSwatchBtn.makeGraphic(48, 48, Std.parseInt(selectedColor));
		if (colorSwatchLabel != null) colorSwatchLabel.text = selectedColor;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  EDIT MODE — Info de archivos existentes
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Llamado desde loadEditData().
	 * Muestra debajo de cada botón el nombre del archivo ya cargado, su duración
	 * y (en slots vocales) el icono del personaje.
	 */
	function _populateExistingAudioInfo(songLower:String):Void
	{
		// ── Inst ──────────────────────────────────────────────────────────────
		#if sys
		var instPath = Paths.inst(songLower);
		if (sys.FileSystem.exists(instPath) && instInfoText != null)
		{
			var dur = _fmtDuration(instPath);
			instInfoText.text    = haxe.io.Path.withoutDirectory(instPath) + (dur != "" ? "  ·  " + dur : "");
			instInfoText.visible = true;
			instLoaded           = true;
			currentInstPath      = instPath;
		}

		// ── Voices.ogg unificado ──────────────────────────────────────────────
		if (!splitVocals)
		{
			var vPath = Paths.voices(songLower);
			if (sys.FileSystem.exists(vPath) && vocalsInfoText != null)
			{
				var dur = _fmtDuration(vPath);
				vocalsInfoText.text    = haxe.io.Path.withoutDirectory(vPath) + (dur != "" ? "  ·  " + dur : "");
				vocalsInfoText.visible = true;
				vocalsLoaded           = true;
				currentVocalsPath      = vPath;
			}
		}

		// ── Slots vocales (split) ─────────────────────────────────────────────
		for (slot in vocalSlots)
		{
			var vp = Paths.voicesForChar(songLower, slot.charName);
			if (vp != null && sys.FileSystem.exists(vp))
			{
				slot.filePath = vp;
				slot.loaded   = true;

				// Info text
				if (slot.infoText != null)
				{
					var dur = _fmtDuration(vp);
					slot.infoText.text    = haxe.io.Path.withoutDirectory(vp) + (dur != "" ? "  ·  " + dur : "");
					slot.infoText.visible = splitVocals; // solo visible si el panel split está activo
				}

				// Icono del personaje
				if (slot.charIcon != null)
				{
					_loadCharIcon(slot.charIcon, slot.charName);
					slot.charIcon.visible = splitVocals;
				}
			}
		}

		updateFileStatus();
		#end
	}

	/**
	 * Intenta leer la duración de un archivo OGG/MP3 y la devuelve
	 * como "Xm Ys". Devuelve "" si no se puede determinar.
	 */
	function _fmtDuration(path:String):String
	{
		#if sys
		try
		{
			var snd = new openfl.media.Sound();
			snd.load(new openfl.net.URLRequest(path));
			var ms = snd.length;
			if (ms <= 0) return "";
			var totalSec = Std.int(ms / 1000);
			var m = Std.int(totalSec / 60);
			var s = totalSec % 60;
			return (m > 0 ? '${m}m ' : '') + '${s < 10 ? "0" : ""}${s}s';
		}
		catch (e:Dynamic) {}
		#end
		return "";
	}

	/**
	 * Carga el icono de salud de un personaje en un FlxSprite existente,
	 * escalado a 32×32. Si no existe, se oculta.
	 */
	function _loadCharIcon(spr:FlxSprite, charName:String):Void
	{
		#if sys
		var iconKey  = 'icons/icon-' + charName;
		var path     = Paths.image(iconKey);
		if (!sys.FileSystem.exists(path))
		{
			path = Paths.image('icons/' + charName);
			if (!sys.FileSystem.exists(path))
				path = Paths.image('icons/icon-face');
		}
		try
		{
			var bmp = openfl.display.BitmapData.fromFile(path);
			if (bmp != null)
			{
				// Cada icono es una tira de 150×150 — tomamos solo el primer frame
				var frame = new openfl.display.BitmapData(150, 150, true, 0);
				frame.copyPixels(bmp, new openfl.geom.Rectangle(0, 0, 150, 150),
				                 new openfl.geom.Point(0, 0));
				spr.pixels = frame;
				spr.setGraphicSize(32, 32);
				spr.updateHitbox();
				spr.visible = true;
				return;
			}
		}
		catch (e:Dynamic) { trace('[AddSong] icon load error: $e'); }
		#end
		spr.visible = false;
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  NAVEGACIÓN
	// ═════════════════════════════════════════════════════════════════════════

	function _buildNavButtons():Void
	{
		var bY = windowY + windowHeight - 52;
		var bX = windowX + windowWidth - 10;

		// Cancel (siempre visible)
		cancelBtn = new FlxButton(bX - 110, bY, "CANCEL", closeWindow);
		_styleBtn(cancelBtn, 0xFFe74c3c, 100);
		cancelBtn.alpha = 0; add(cancelBtn);
		FlxTween.tween(cancelBtn, {alpha: 1}, 0.3, {startDelay: 0.3});

		// Previous
		prevBtn = new FlxButton(bX - 230, bY, "< BACK", function() _goStep(currentStep - 1));
		_styleBtn(prevBtn, funkin.debug.themes.EditorTheme.current.bgHover, 110);
		prevBtn.alpha = 0; add(prevBtn);
		FlxTween.tween(prevBtn, {alpha: 1}, 0.3, {startDelay: 0.3});

		// Next
		nextBtn = new FlxButton(bX - 350, bY, "NEXT >", function() _goStep(currentStep + 1));
		_styleBtn(nextBtn, 0xFF3498db, 110);
		nextBtn.alpha = 0; add(nextBtn);
		FlxTween.tween(nextBtn, {alpha: 1}, 0.3, {startDelay: 0.3});

		// Save (solo en último paso)
		saveBtn = new FlxButton(bX - 350, bY, editMode ? "UPDATE" : "SAVE", saveSong);
		_styleBtn(saveBtn, 0xFF2ecc71, 110);
		saveBtn.alpha = 0; add(saveBtn);
		FlxTween.tween(saveBtn, {alpha: 1}, 0.3, {startDelay: 0.3});
	}

	function _showStep(step:Int):Void
	{
		currentStep = step;

		// FIX: _setGroupVisible usa cast directo a FlxBasic (no Reflect.hasField)
		// para garantizar que los pasos ocultos realmente queden invisible.
		// Además resetamos el alpha de los grupos ocultos a 1.0 para que
		// _slideIn pueda animarlos desde 0 correctamente cuando se activan.
		for (i in 0...stepGroups.length)
		{
			var vis = (i == currentStep - 1);
			_setGroupVisible(stepGroups[i], vis);
			if (!vis) _resetGroupAlpha(stepGroups[i], 1.0);
		}

		// Botones de nav
		prevBtn.visible = (currentStep > 1);
		nextBtn.visible = (currentStep < TOTAL_STEPS);
		saveBtn.visible = (currentStep == TOTAL_STEPS);

		// Indicador
		stepIndicator.text = 'Step $currentStep / $TOTAL_STEPS';

		// Título de paso
		var stepTitles = ["FILES & BPM", "DIFFS & IMPORT", "METADATA", "STORY MENU"];
		titleText.text = (editMode ? "EDIT: " : "ADD: ") + stepTitles[currentStep - 1];

		updateStatus(_stepHint(currentStep));
	}

	/** Fuerza el alpha de todos los FlxSprite en el grupo al valor dado. */
	function _resetGroupAlpha(g:FlxTypedGroup<Dynamic>, a:Float):Void
	{
		for (m in g.members)
		{
			if (m != null && Std.isOfType(m, flixel.FlxSprite))
				cast(m, flixel.FlxSprite).alpha = a;
		}
	}

	function _goStep(step:Int):Void
	{
		if (step < 1 || step > TOTAL_STEPS) return;

		// Validación al avanzar del paso 1
		if (step > currentStep && currentStep == STEP_FILES)
		{
			if (songNameInput.text.trim() == "")
			{
				updateStatus("\u26a0 The song title cannot be empty.");
				return;
			}
			var bpmVal = Std.parseFloat(bpmInput.text);
			if (Math.isNaN(bpmVal) || bpmVal <= 0)
			{
				updateStatus("\u26a0 BPM invalided.");
				return;
			}
			// Auto-detectar diffs disponibles al avanzar del paso 1 si aún no
			// se ha pasado por el paso de diffs (p.ej. primera vez).
			if (diffEntries.length == 0) _initDefaultDiffs();
		}

		// Validación al avanzar del paso 2 (diffs)
		if (step > currentStep && currentStep == STEP_DIFFS)
		{
			var enabledCount = 0;
			for (e in diffEntries) if (e.enabled) enabledCount++;
			if (enabledCount == 0)
			{
				updateStatus("\u26a0 At least one difficulty must be enabled.");
				return;
			}
		}

		// Animación de transición entre pasos
		var dir:Int = (step > currentStep) ? 1 : -1;
		var oldGroup  = stepGroups[currentStep - 1];
		var newGroup  = stepGroups[step - 1];
		var oldIndex  = currentStep - 1;
		var newIndex  = step - 1;

		_slideOut(oldGroup, oldIndex, dir, function()
		{
			_setGroupVisible(oldGroup, false);
			// Restaurar X originales del grupo saliente para que la próxima
			// vez que se muestre, los elementos partan desde la posición correcta.
			_restoreOrigX(oldIndex);
			_showStep(step);
			_slideIn(newGroup, newIndex, dir);
		});
	}

	function _slideOut(g:FlxTypedGroup<Dynamic>, groupIdx:Int, dir:Int, onDone:Void->Void):Void
	{
		var offset:Float = dir > 0 ? -80 : 80;
		var count:Int = 0;
		var total:Int = 0;
		for (m in g.members)
			if (m != null && Std.isOfType(m, flixel.FlxObject)) total++;
		if (total == 0) { onDone(); return; }

		var origMap = (groupIdx >= 0 && groupIdx < _stepOrigX.length) ? _stepOrigX[groupIdx] : null;

		for (m in g.members)
		{
			if (m == null || !Std.isOfType(m, flixel.FlxObject)) continue;
			var obj:flixel.FlxObject = cast m;
			FlxTween.cancelTweensOf(obj);

			// Partir siempre desde la X original (no desde obj.x que puede
			// estar en mitad de un tween previo → la fuente del drift).
			var origX:Float = (origMap != null && origMap.exists(obj)) ? origMap.get(obj) : obj.x;
			obj.x = origX;

			FlxTween.tween(obj, {alpha: 0, x: origX + offset}, 0.18,
			{
				ease: FlxEase.quadIn,
				onComplete: function(_) { count++; if (count >= total) onDone(); }
			});
		}
	}

	function _slideIn(g:FlxTypedGroup<Dynamic>, groupIdx:Int, dir:Int):Void
	{
		var startOff:Float = dir > 0 ? 80 : -80;
		_setGroupVisible(g, true);

		var origMap = (groupIdx >= 0 && groupIdx < _stepOrigX.length) ? _stepOrigX[groupIdx] : null;

		for (m in g.members)
		{
			if (m == null || !Std.isOfType(m, flixel.FlxObject)) continue;
			var obj:flixel.FlxObject = cast m;
			FlxTween.cancelTweensOf(obj);

			// Destino siempre = X original de diseño (no obj.x actual).
			var origX:Float = (origMap != null && origMap.exists(obj)) ? origMap.get(obj) : obj.x;

			obj.x = origX + startOff;
			if (Std.isOfType(obj, flixel.FlxSprite))
				cast(obj, flixel.FlxSprite).alpha = 0;
			FlxTween.tween(obj, {alpha: 1, x: origX}, 0.22, {ease: FlxEase.quadOut});
		}
	}

	/** Restaura todos los elementos de un grupo a sus X originales de diseño. */
	function _restoreOrigX(groupIdx:Int):Void
	{
		if (groupIdx < 0 || groupIdx >= _stepOrigX.length) return;
		var origMap = _stepOrigX[groupIdx];
		for (obj in origMap.keys()) obj.x = origMap.get(obj);
	}

	/**
	 * Muestra u oculta todos los miembros de un grupo de paso.
	 *
	 * FIX: Reflect.hasField(m, "visible") devuelve FALSE para propiedades
	 * con setter custom (visible(default,set) en FlxBasic), lo que causaba
	 * que TODOS los pasos quedasen visibles a la vez. Ahora se usa cast
	 * directo a FlxBasic para acceder al setter correctamente.
	 */
	function _setGroupVisible(g:FlxTypedGroup<Dynamic>, vis:Bool):Void
	{
		for (m in g.members)
		{
			if (m == null) continue;
			if (Std.isOfType(m, flixel.FlxBasic))
			{
				var fb:flixel.FlxBasic = cast m;
				fb.visible = vis;
				if (!vis) FlxTween.cancelTweensOf(fb);
			}
		}
	}

	function _stepHint(step:Int):String
	{
		return switch (step)
		{
			case STEP_FILES:  "Upload the audio files and enter the BPM of the song.";
			case STEP_DIFFS:  "Choose which difficulties to include and optionally import charts.";
			case STEP_META:   "Configure the icon, skins, cutscenes, and artist.";
			case STEP_STORY:  "Define how the song appears in the Story Menu.";
			default: "";
		};
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  SAVE / LOAD
	// ═════════════════════════════════════════════════════════════════════════

	function saveSong():Void
	{
		var songName = songNameInput.text.trim();
		if (songName == "") { updateStatus("¡The song title cannot be empty!"); return; }

		var weekIndex = Std.parseInt(weekInput.text);
		var bpmVal    = Std.parseFloat(bpmInput.text);
		if (Math.isNaN(bpmVal) || bpmVal <= 0) { updateStatus("¡BPM invalided!"); return; }

		FlxG.sound.play(Paths.sound('menus/confirmMenu'));

		if (editMode)
		{
			updateExistingSong(songName, weekIndex, bpmVal);
			updateStatus("¡Song updated!");
		}
		else
		{
			addNewSong(songName, weekIndex, bpmVal);
			updateStatus("¡Song added!");
		}

		saveJSON();
		saveMetaJSON(songName);
		closeWindow();
	}

	function addNewSong(songName:String, weekIndex:Int, bpmVal:Float):Void
	{
		createBaseChartJSON(songName.toLowerCase(), bpmVal);

		#if desktop
		if (instLoaded && currentInstPath != "") copySongFile(currentInstPath, songName, "Inst");
		if (!splitVocals)
		{
			if (vocalsLoaded && currentVocalsPath != "")
				copySongFile(currentVocalsPath, songName, "Voices");
		}
		else
		{
			// Copiar un Voices-<charName>.ogg por cada slot cargado
			for (slot in vocalSlots)
			{
				var label = (slot.charName != null && slot.charName != '') ? slot.charName : 'char';
				if (slot.loaded && slot.filePath != "")
					copySongFile(slot.filePath, songName, 'Voices-$label');
			}
		}
		if (iconFileLoaded && currentIconPath != "") copyIconFile(currentIconPath, iconNameInput.text.trim());
		#end
	}

	function updateExistingSong(songName:String, weekIndex:Int, bpmVal:Float):Void
	{
		// Remove old entry if the name changed
		if (editingSong != null && editingSong.songName != songName)
			freeplayListData = FreeplayList.remove(freeplayListData, editingSong.songName);

		final entry:FreeplaySongEntry = {
			name:      songName,
			icon:      iconNameInput.text.trim(),
			color:     selectedColor,
			bpm:       bpmVal,
			group:     weekIndex,
			artist:    (artistInput    != null) ? artistInput.text.trim()    : '',
			album:     (albumInput     != null) ? albumInput.text.trim()     : '',
			albumText: (albumTextInput != null) ? albumTextInput.text.trim() : ''
		};
		freeplayListData = FreeplayList.upsert(freeplayListData, entry);

		_migrateAndPatchCharts(songName.toLowerCase(), bpmVal);

		#if desktop
		if (instLoaded && currentInstPath != "") copySongFile(currentInstPath, songName, "Inst");
		if (!splitVocals)
		{
			if (vocalsLoaded && currentVocalsPath != "")
				copySongFile(currentVocalsPath, songName, "Voices");
		}
		else
		{
			// Copiar un Voices-<charName>.ogg por cada slot cargado
			for (slot in vocalSlots)
			{
				var label = (slot.charName != null && slot.charName != '') ? slot.charName : 'char';
				if (slot.loaded && slot.filePath != "")
					copySongFile(slot.filePath, songName, 'Voices-$label');
			}
		}
		if (iconFileLoaded && currentIconPath != "") copyIconFile(currentIconPath, iconNameInput.text.trim());
		#end
	}

	/**
	 * Escribe los campos songAlbums, songAlbumTexts y songArtists para la
	 * posición `idx` del objeto de semana. Extiende los arrays si hace falta.
	 * Llámalo siempre después de añadir/actualizar weekSongs[idx].
	 */
	function _writePerSongFields(week:Dynamic, idx:Int):Void
	{
		var album     = albumInput     != null ? albumInput.text.trim()     : '';
		var albumTxt  = albumTextInput != null ? albumTextInput.text.trim() : '';
		var artist    = artistInput    != null ? artistInput.text.trim()    : '';

		// ── songAlbums ────────────────────────────────────────────────────────
		if (album != '' || Reflect.field(week, 'songAlbums') != null)
		{
			var arr:Array<Dynamic> = Reflect.field(week, 'songAlbums') ?? [];
			while (arr.length <= idx) arr.push(null);
			arr[idx] = album != '' ? album : null;
			Reflect.setField(week, 'songAlbums', arr);
		}

		// ── songAlbumTexts ────────────────────────────────────────────────────
		if (albumTxt != '' || Reflect.field(week, 'songAlbumTexts') != null)
		{
			var arr:Array<Dynamic> = Reflect.field(week, 'songAlbumTexts') ?? [];
			while (arr.length <= idx) arr.push(null);
			arr[idx] = albumTxt != '' ? albumTxt : null;
			Reflect.setField(week, 'songAlbumTexts', arr);
		}

		// ── songArtists ───────────────────────────────────────────────────────
		if (artist != '' || Reflect.field(week, 'songArtists') != null)
		{
			var arr:Array<Dynamic> = Reflect.field(week, 'songArtists') ?? [];
			while (arr.length <= idx) arr.push(null);
			arr[idx] = artist != '' ? artist : null;
			Reflect.setField(week, 'songArtists', arr);
		}
	}

	function saveMetaJSON(songName:String):Void
	{
		var ui         = uiInput        != null ? uiInput.text.trim()        : 'default';
		var noteSkin   = noteSkinInput  != null ? noteSkinInput.text.trim()  : 'default';
		var introVideo = introVideoInput != null ? introVideoInput.text.trim() : '';
		var outroVideo = outroVideoInput != null ? outroVideoInput.text.trim() : '';
		var artist     = artistInput    != null ? artistInput.text.trim()    : '';

		// ── Sufijos de las dificultades habilitadas ────────────────────────────
		// Se guardan en "difficulties" del meta para que getAvailableDifficulties()
		// filtre correctamente y el jugador solo vea las diffs elegidas.
		var enabledSuffixes:Array<String> = [];
		for (e in diffEntries)
			if (e.enabled) enabledSuffixes.push(e.suffix);

		var meta:funkin.data.MetaData.SongMetaData = {
			ui:           ui       != '' ? ui       : 'default',
			noteSkin:     noteSkin != '' ? noteSkin : 'default',
			introVideo:   introVideo != '' ? introVideo : null,
			outroVideo:   outroVideo != '' ? outroVideo : null,
			artist:       artist     != '' ? artist     : null,
			// Solo escribir el campo si hay diffs configuradas explícitamente.
			// Si el array está vacío (nadie pasó por el paso 2), lo dejamos null
			// para mantener el comportamiento legacy (mostrar todo).
			difficulties: enabledSuffixes.length > 0 ? enabledSuffixes : null
		};

		#if sys
		try
		{
			var songKey = songName.toLowerCase();
			var existingSong = _loadAnyExistingDiff(songKey);
			if (existingSong != null)
				LevelFile.saveDiff(songKey, '', existingSong, meta);
			else
			{
				var dir  = _songDir(songKey);
				File.saveContent('$dir/meta.json', Json.stringify(meta, null, "\t"));
			}
		}
		catch (e:Dynamic) { trace('[AddSong] Error saving meta: $e'); }
		#else
		MetaData.save(songName, ui != '' ? ui : 'default', noteSkin != '' ? noteSkin : 'default');
		#end
	}

	function loadEditData():Void
	{
		if (editingSong == null) return;

		songNameInput.text = editingSong.songName;
		iconNameInput.text = editingSong.songCharacter;
		weekInput.text     = Std.string(editingSong.week);



		updateColorButtons();

		var m = MetaData.load(editingSong.songName);
		if (uiInput         != null) uiInput.text         = m.ui;
		if (noteSkinInput   != null) noteSkinInput.text   = m.noteSkin;
		if (introVideoInput != null) introVideoInput.text = m.introVideo ?? '';
		if (outroVideoInput != null) outroVideoInput.text = m.outroVideo ?? '';

		// Artista y álbum desde freeplayListData (prioridad) o meta.json
		for (entry in freeplayListData.songs)
		{
			if (entry.name.toLowerCase() != editingSong.songName.toLowerCase()) continue;
			if (artistInput    != null) artistInput.text    = (entry.artist != null && entry.artist != '') ? entry.artist : (m.artist ?? '');
			if (albumInput     != null) albumInput.text     = entry.album     ?? '';
			if (albumTextInput != null) albumTextInput.text = entry.albumText ?? '';
			break;
		}

		needsVoices = _readNeedsVoicesFromChart(editingSong.songName);
		_refreshVoicesToggle();

		// Auto-leer BPM desde el chart existente si el campo está en "120" (default)
		// Nota: _initDefaultDiffs() también puede haber cargado el BPM si fue llamado antes.
		#if sys
		if (bpmInput != null && (bpmInput.text == '120' || bpmInput.text == '' || bpmInput.text == '0'))
		{
			var songLower  = editingSong.songName.toLowerCase();
			var levelPath  = _contentRoot() + '/songs/$songLower/$songLower.level';
			if (sys.FileSystem.exists(levelPath))
				_autoFillBpmFromLevel(levelPath);
		}
		#end

		// Detectar personajes con vocals split desde el chart
		var songLower = editingSong.songName.toLowerCase();
		var chart = _loadAnyExistingDiff(songLower);

		// Construir lista de candidatos desde SONG.characters o player1/player2
		var candidates:Array<{name:String}> = [];
		if (chart != null && chart.characters != null && chart.characters.length > 0)
		{
			for (c in chart.characters)
			{
				var t = c.type != null ? c.type : '';
				if (t == 'Girlfriend' || t == 'Other') continue;
				var dup = false;
				for (prev in candidates) if (prev.name == c.name) { dup = true; break; }
				if (!dup) candidates.push({name: c.name});
			}
		}
		if (candidates.length == 0 && chart != null)
		{
			var p1 = chart.player1 ?? 'bf';
			var p2 = chart.player2 ?? 'dad';
			candidates.push({name: p1});
			if (p2 != p1) candidates.push({name: p2});
		}
		if (candidates.length == 0)
		{
			candidates.push({name: 'bf'});
			candidates.push({name: 'dad'});
		}

		// Ver si algún candidato tiene Voices-<name>.ogg
		var detectedSplit = false;
		for (cand in candidates)
			if (Paths.hasVoicesForChar(songLower, cand.name)) { detectedSplit = true; break; }

		if (detectedSplit)
		{
			splitVocals = true;
			_refreshSplitToggle();
			// Reemplazar slots con los personajes detectados
			vocalSlots = [];
			if (_slotContainer != null) _slotContainer.clear();
			for (cand in candidates)
				_buildVocalSlotUI({charName: cand.name, filePath: "", loaded: false, btn: null, statusText: null, nameInput: null});
			_rebuildVocalSlots();
		}

		// Mostrar info de archivos ya existentes (nombre, duración, icono)
		_populateExistingAudioInfo(songLower);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  RUTAS HELPERS (copiados sin cambios del original)
	// ═════════════════════════════════════════════════════════════════════════

	static function _contentRoot():String
	{
		#if sys
		if (mods.ModManager.isActive()) return mods.ModManager.modRoot();
		#end
		return 'assets';
	}

	static function _songDir(songName:String):String
	{
		var dir = _contentRoot() + '/songs/' + songName.toLowerCase();
		#if sys if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir); #end
		return dir;
	}

	static function _songAudioDir(songName:String):String
	{
		var base = _songDir(songName); var dir = '$base/song';
		#if sys if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir); #end
		return dir;
	}

	static function _songListPath():String
	{
		var dir = _contentRoot() + '/songs';
		#if sys if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir); #end
		return '$dir/songList.json';
	}

	static function _iconsDir():String
	{
		var dir = _contentRoot() + '/images/icons';
		#if sys if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir); #end
		return dir;
	}

	function createBaseChartJSON(songName:String, bpm:Float):Void
	{
		#if desktop
		try
		{
			var dir       = _songDir(songName);
			var levelPath = '$dir/$songName.level';
			if (sys.FileSystem.exists(levelPath)) return;

			var tmpl = _makeBlankSong(songName, bpm);

			// Construir mapa de dificultades desde diffEntries
			// Solo las que están habilitadas.
			var diffMap:Map<String, SwagSong> = [];
			var enabledDiffs = [for (e in diffEntries) if (e.enabled) e];

			if (enabledDiffs.length == 0)
			{
				// Fallback: 3 dificultades clásicas
				diffMap = ['' => tmpl, '-easy' => tmpl, '-hard' => tmpl];
			}
			else
			{
				for (entry in enabledDiffs)
				{
					var song:SwagSong = null;

					// Si hay un chart importado, convertirlo
					if (entry.chartPath != '' && sys.FileSystem.exists(entry.chartPath))
					{
						song = _convertImportedChart(entry, songName, bpm);
					}

					if (song == null) song = _makeBlankSong(songName, bpm);
					diffMap.set(entry.suffix, song);
				}
			}

			LevelFile.saveAll(songName, diffMap, null, songName, null);
		}
		catch (e:Dynamic) { trace('Error creating chart: $e'); }
		#end
	}

	function _makeBlankSong(songName:String, bpm:Float):SwagSong
	{
		return {song:songName, bpm:bpm, speed:2.5, needsVoices:needsVoices,
			player1:'bf', player2:'dad', gfVersion:'gf', stage:'stage_week1',
			validScore:true, notes:[], events:[], characters:null, strumsGroups:null};
	}

	/**
	 * Convierte el chart importado de `entry` al formato SwagSong de Cool Engine.
	 * Devuelve null si la conversión falla (el caller usa el chart en blanco como fallback).
	 */
	function _convertImportedChart(entry:DiffEntry, songName:String, bpm:Float):Null<SwagSong>
	{
		#if sys
		try
		{
			var path    = entry.chartPath;
			var diffKey = entry.chartDiffKey != '' ? entry.chartDiffKey : entry.suffix;
			// Limpiar sufijo inicial ("-easy" → "easy")
			if (diffKey.startsWith('-')) diffKey = diffKey.substr(1);

			return switch (entry.chartFormat)
			{
				case 'vslice':
					var raw = sys.io.File.getContent(path);
					var song = mods.compat.VSliceConverter.convertChart(raw, diffKey, path);
					if (song != null) song.song = songName;
					song;

				case 'psych':
					var raw = sys.io.File.getContent(path);
					var parsed:Dynamic = haxe.Json.parse(raw);
					// Psych: { "song": { ... } } o directo
					var songObj:Dynamic = (parsed.song != null && !Std.isOfType(parsed.song, String))
						? parsed.song : parsed;
					var converted:SwagSong = cast songObj;
					converted.song = songName;
					converted;

				case 'codename':
					var raw = sys.io.File.getContent(path);
					var song = mods.compat.CodenameConverter.convertChart(raw, diffKey);
					if (song != null) song.song = songName;
					song;

				case 'osu':
					var data = funkin.data.charts.ChartLoader.load(path);
					if (data == null) null;
					else
					{
						var raw = funkin.data.charts.ChartConverter.toSwagSong(data);
						var song:SwagSong = raw != null ? cast raw : null;
						if (song != null) song.song = songName;
						song;
					}

				case 'sm':
					var data = funkin.data.charts.ChartLoader.load(path, diffKey);
					if (data == null) null;
					else
					{
						var raw = funkin.data.charts.ChartConverter.toSwagSong(data);
						var song:SwagSong = raw != null ? cast raw : null;
						if (song != null) song.song = songName;
						song;
					}

				case 'level':
					var levelData:funkin.data.LevelFile.LevelData =
						cast haxe.Json.parse(sys.io.File.getContent(path));
					if (levelData.difficulties == null) null;
					else
					{
						// Buscar la dificultad más cercana al sufijo de esta entry
						var fields = Reflect.fields(levelData.difficulties);
						var key    = _pickClosestDiff(fields, entry.suffix);
						var song:SwagSong = cast Reflect.field(levelData.difficulties, key);
						if (song != null) song.song = songName;
						song;
					}

				default:
					trace('[AddSong] Unknown chart format: ${entry.chartFormat}');
					null;
			};
		}
		catch (e:Dynamic)
		{
			trace('[AddSong] Error converting chart for diff "${entry.label}": $e');
			return null;
		}
		#else
		return null;
		#end
	}

	function _migrateAndPatchCharts(songLower:String, bpmVal:Float):Void
	{
		#if sys
		if (!LevelFile.exists(songLower)) LevelFile.migrateFromJson(songLower);

		// Si el usuario configuró dificultades en el paso 2, usarlas.
		var enabledDiffs = [for (e in diffEntries) if (e.enabled) e];
		if (enabledDiffs.length > 0)
		{
			var diffMap:Map<String, SwagSong> = [];
			for (entry in enabledDiffs)
			{
				// Intentar cargar chart existente para este sufijo
				var existing = LevelFile.loadDiff(songLower, entry.suffix);

				// Si hay un chart importado nuevo, convertirlo; si no, parchear el existente
				if (entry.chartPath != '' && sys.FileSystem.exists(entry.chartPath))
				{
					var converted = _convertImportedChart(entry, songLower, bpmVal);
					if (converted != null)
					{
						converted.bpm        = bpmVal;
						converted.needsVoices = needsVoices;
						diffMap.set(entry.suffix, converted);
						continue;
					}
				}

				// Sin importación: parchear el existente o crear en blanco
				if (existing != null)
				{
					existing.bpm        = bpmVal;
					existing.needsVoices = needsVoices;
					diffMap.set(entry.suffix, existing);
				}
				else
				{
					diffMap.set(entry.suffix, _makeBlankSong(songLower, bpmVal));
				}
			}
			// Guardar todas las dificultades de golpe
			for (suffix => song in diffMap)
				LevelFile.saveDiff(songLower, suffix, song, null);
			trace('[AddSong] Patched/created ${[for (k in diffMap.keys()) k].length} diffs for $songLower');
			return;
		}

		// Fallback: parchear todas las dificultades existentes (comportamiento anterior)
		var allDiffs = LevelFile.getAvailableDifficulties(songLower);
		if (allDiffs == null || allDiffs.length == 0) return;
		var patched = 0;
		for (pair in allDiffs)
		{
			var suffix = pair[1];
			var song   = LevelFile.loadDiff(songLower, suffix);
			if (song == null) continue;
			song.bpm        = bpmVal;
			song.needsVoices = needsVoices;
			LevelFile.saveDiff(songLower, suffix, song, null);
			patched++;
		}
		trace('[AddSong] Patched $patched diffs for $songLower');
		#end
	}

	function _loadAnyExistingDiff(songLower:String):Null<SwagSong>
	{
		#if sys
		var dir = _contentRoot() + '/songs/$songLower';
		var levelPath = '$dir/$songLower.level';
		if (sys.FileSystem.exists(levelPath))
		{
			try
			{
				var data:funkin.data.LevelFile.LevelData = cast haxe.Json.parse(sys.io.File.getContent(levelPath));
				if (data.difficulties != null)
				{
					var fields = Reflect.fields(data.difficulties);
					if (fields.length > 0)
						return cast Reflect.field(data.difficulties, fields[0]);
				}
			}
			catch (_) {}
		}
		if (sys.FileSystem.exists(dir))
		{
			for (suffix in ["", "-easy", "-hard"])
			{
				var p = '$dir/$songLower$suffix.json';
				if (!sys.FileSystem.exists(p)) continue;
				try
				{
					var raw:Dynamic = haxe.Json.parse(sys.io.File.getContent(p));
					return cast ((raw.song != null && !Std.isOfType(raw.song, String)) ? raw.song : raw);
				}
				catch (_) {}
			}
		}
		#end
		return null;
	}

	function _readNeedsVoicesFromChart(songName:String):Bool
	{
		#if sys
		var lower = songName.toLowerCase();
		var dir   = _contentRoot() + '/songs/$lower';
		var levelPath = '$dir/$lower.level';
		if (FileSystem.exists(levelPath))
		{
			try
			{
				var data:funkin.data.LevelFile.LevelData = cast haxe.Json.parse(File.getContent(levelPath));
				if (data.difficulties != null)
					for (key in Reflect.fields(data.difficulties))
					{
						var song:SwagSong = cast Reflect.field(data.difficulties, key);
						if (song != null && Reflect.hasField(song, 'needsVoices'))
							return (song.needsVoices == true);
					}
			}
			catch (_:Dynamic) {}
		}
		if (FileSystem.exists(dir))
			for (suffix in ["", "-hard", "-easy"])
			{
				var p = '$dir/$lower$suffix.json';
				if (!FileSystem.exists(p)) continue;
				try
				{
					var raw:Dynamic = haxe.Json.parse(File.getContent(p));
					var songObj:Dynamic = (raw.song != null) ? raw.song : raw;
					if (Reflect.hasField(songObj, 'needsVoices'))
						return (songObj.needsVoices == true);
				}
				catch (_:Dynamic) {}
			}
		#end
		return true;
	}

	// ── File ops ──────────────────────────────────────────────────────────────

	function copySongFile(sourcePath:String, songName:String, fileType:String):Void
	{
		#if desktop
		try { File.copy(sourcePath, '${_songAudioDir(songName)}/$fileType.ogg'); }
		catch (e:Dynamic) { updateStatus('Error copying $fileType.ogg'); }
		#end
	}

	function copyIconFile(sourcePath:String, iconName:String):Void
	{
		#if desktop
		try
		{
			var fname = iconName.startsWith('icon-') ? '$iconName.png' : 'icon-$iconName.png';
			File.copy(sourcePath, '${_iconsDir()}/$fname');
		}
		catch (e:Dynamic) { updateStatus('Error copying icon'); }
		#end
	}

	function saveJSON():Void
	{
		#if desktop
		if (!FreeplayList.save(freeplayListData))
			updateStatus('Error saving freeplayList.json');
		#end
	}

	function loadSongList():Void
	{
		freeplayListData = FreeplayList.load();
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UI HELPERS
	// ═════════════════════════════════════════════════════════════════════════

	/** Alias mantenido para compatibilidad con loadEditData. */
	function updateColorButtons():Void
	{
		_refreshColorSwatch();
	}

	function updateFileStatus():Void
	{
		if (instStatusText   != null) { instStatusText.text   = instLoaded      ? "\u2713" : "\u2717"; instStatusText.color   = instLoaded      ? FlxColor.GREEN : FlxColor.RED; }
		if (vocalsStatusText != null) { vocalsStatusText.text = vocalsLoaded    ? "\u2713" : "\u2717"; vocalsStatusText.color = vocalsLoaded    ? FlxColor.GREEN : FlxColor.RED; }
		if (iconStatusText   != null) { iconStatusText.text   = iconFileLoaded  ? "\u2713" : "\u2717"; iconStatusText.color   = iconFileLoaded  ? FlxColor.GREEN : FlxColor.RED; }
		// Slots dinámicos
		for (slot in vocalSlots)
			if (slot.statusText != null) { slot.statusText.text = slot.loaded ? "\u2713" : "\u2717"; slot.statusText.color = slot.loaded ? FlxColor.GREEN : FlxColor.RED; }
	}

	function updateStatus(text:String):Void
	{
		statusText.text = text;
		FlxTween.cancelTweensOf(statusText);
		statusText.alpha = 1;
		statusText.scale.set(1.08, 1.08);
		FlxTween.tween(statusText.scale, {x: 1, y: 1}, 0.18);
	}



	function _refreshVoicesToggle():Void
	{
		var on = needsVoices;
		needsVoicesToggleBtn.makeGraphic(88, 34, on ? 0xFF4CAF50 : 0xFFFF5252);
		needsVoicesToggleText.text  = on ? "YES" : "NO";
		needsVoicesToggleText.color = on ? 0xFF4CAF50 : 0xFFFF5252;
	}

	function closeWindow():Void
	{
		FlxG.sound.play(Paths.sound('menus/cancelMenu'));
		FlxTween.tween(bgDarkener, {alpha: 0}, 0.25);
		FlxTween.tween(windowBg, {alpha: 0, "scale.x": 0.85, "scale.y": 0.85}, 0.25,
		{
			ease: FlxEase.backIn,
			onComplete: function(_) close()
		});
	}

	// ── Widget factories ──────────────────────────────────────────────────────

	function _lbl(g:FlxTypedGroup<Dynamic>, x:Float, y:Float, text:String, delay:Float):Void
	{
		var l = new FlxText(x, y, 0, text, 15);
		l.setFormat(Paths.font("vcr.ttf"), 15, FlxColor.WHITE, LEFT);
		l.alpha = 0; g.add(l);
		FlxTween.tween(l, {alpha: 1}, 0.3, {startDelay: delay});
	}

	function _inp(g:FlxTypedGroup<Dynamic>, x:Float, y:Float, w:Int, def:String, maxLen:Int, delay:Float):FlxInputText
	{
		var f = new FlxInputText(x, y, w, def, 15);
		f.backgroundColor      = funkin.debug.themes.EditorTheme.current.bgHover;
		f.fieldBorderColor     = funkin.debug.themes.EditorTheme.current.borderColor;
		f.fieldBorderThickness = 2;
		f.color    = FlxColor.WHITE;
		f.maxLength = maxLen;
		f.alpha = 0; g.add(f);
		FlxTween.tween(f, {alpha: 1}, 0.3, {startDelay: delay});
		return f;
	}

	function _inpNum(g:FlxTypedGroup<Dynamic>, x:Float, y:Float, w:Int, def:String, delay:Float):FlxInputText
	{
		var f = _inp(g, x, y, w, def, 10, delay);
		f.filterMode = FlxInputText.ONLY_NUMERIC;
		return f;
	}

	function _toggleBtn(g:FlxTypedGroup<Dynamic>, x:Float, y:Float, cb:Void->Void, delay:Float):FlxButton
	{
		var b = new FlxButton(x, y, "", cb);
		b.makeGraphic(88, 34, 0xFF4CAF50);
		b.alpha = 0; g.add(b);
		FlxTween.tween(b, {alpha: 1}, 0.3, {startDelay: delay});
		return b;
	}

	function _toggleTxt(g:FlxTypedGroup<Dynamic>, x:Float, y:Float, delay:Float):FlxText
	{
		var t = new FlxText(x, y, 74, "SÍ", 14);
		t.setFormat(Paths.font("vcr.ttf"), 14, 0xFF4CAF50, CENTER);
		t.alpha = 0; g.add(t);
		FlxTween.tween(t, {alpha: 1}, 0.3, {startDelay: delay});
		return t;
	}

	function _statusIcon(g:FlxTypedGroup<Dynamic>, x:Float, y:Float, delay:Float):FlxText
	{
		var t = new FlxText(x, y, 0, "\u2717", 20);
		t.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.RED, LEFT);
		t.alpha = 0; g.add(t);
		FlxTween.tween(t, {alpha: 1}, 0.3, {startDelay: delay});
		return t;
	}

	function _fileBtn(g:FlxTypedGroup<Dynamic>, x:Float, y:Float, label:String,
		color:Int, w:Int, cb:Void->Void, delay:Float):FlxButton
	{
		var b = new FlxButton(x, y, label, cb);
		b.makeGraphic(w, 38, color);
		b.label.setFormat(Paths.font("vcr.ttf"), 15, FlxColor.WHITE, LEFT);
		b.alpha = 0; g.add(b);
		FlxTween.tween(b, {alpha: 1}, 0.3, {startDelay: delay});
		return b;
	}

	function _styleBtn(btn:FlxButton, color:Int, w:Int):Void
	{
		btn.makeGraphic(w, 40, color);
		btn.label.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER);
	}

	// ── refs internas para split toggle (asignadas en _buildStep1) ─────────
	var _splitToggleBtn:FlxButton  = null;
	var _splitToggleText:FlxText   = null;

	/** Y absoluta donde empieza el área de vocales (después del toggle split). */
	var _vocalAreaY:Float = 0;

	function _refreshSplitToggle():Void
	{
		if (_splitToggleBtn  == null) return;
		if (_splitToggleText == null) return;
		_splitToggleBtn.makeGraphic(88, 34, splitVocals ? 0xFF9C27B0 : 0xFF607D8B);
		_splitToggleText.text  = splitVocals ? "SPLIT" : "ONLY";
		_splitToggleText.color = splitVocals ? 0xFFCE93D8 : 0xFFB0BEC5;
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UPDATE
	// ═════════════════════════════════════════════════════════════════════════

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// Teclas de navegación de icono (solo en paso 3 = METADATA)
		if (currentStep == STEP_META && iconNameInput != null)
		{
			if (FlxG.keys.justPressed.LEFT)
			{
				currentIconIndex = (currentIconIndex - 1 + iconPresets.length) % iconPresets.length;
				iconNameInput.text = iconPresets[currentIconIndex];
				FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);
			}
			else if (FlxG.keys.justPressed.RIGHT)
			{
				currentIconIndex = (currentIconIndex + 1) % iconPresets.length;
				iconNameInput.text = iconPresets[currentIconIndex];
				FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);
			}
		}

		// Escape cierra
		if (FlxG.keys.justPressed.ESCAPE) closeWindow();

		// Enter avanza / guarda
		if (FlxG.keys.justPressed.ENTER)
		{
			if (currentStep < TOTAL_STEPS) _goStep(currentStep + 1);
			else saveSong();
		}
	}
}
