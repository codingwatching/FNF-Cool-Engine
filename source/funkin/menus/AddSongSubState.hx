package funkin.menus;

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
	static inline var STEP_META   = 2;
	static inline var STEP_STORY  = 3;
	static inline var TOTAL_STEPS = 3;

	// ── Window layout ─────────────────────────────────────────────────────────
	var windowWidth:Int  = 860;
	var windowHeight:Int = 560;
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

	// ─── PASO 2: Metadatos ────────────────────────────────────────────────────
	var iconNameInput:FlxInputText;
	var uiInput:FlxInputText;
	var noteSkinInput:FlxInputText;
	var introVideoInput:FlxInputText;
	var outroVideoInput:FlxInputText;
	var artistInput:FlxInputText;

	// ─── PASO 3: Story Menu ───────────────────────────────────────────────────
	var weekInput:FlxInputText;
	var showInStoryMode:Bool = true;
	var storyModeToggleBtn:FlxButton;
	var storyModeToggleText:FlxText;
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
	var songListData:StoryMenuState.Songs;
	var editMode:Bool = false;
	var editingSong:FreeplayState.SongMetadata = null;

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

		for (g in stepGroups) add(g);

		// ── Theme button ──────────────────────────────────────────────────────
		var themeBtn = new FlxButton(windowX + 10, windowY + 10, "\u2728 Theme", function()
			openSubState(new funkin.debug.themes.ThemePickerSubState()));
		themeBtn.alpha = 0;
		add(themeBtn);
		FlxTween.tween(themeBtn, {alpha: 0.85}, 0.3, {startDelay: 0.25});

		// ── Cargar datos en modo edición ──────────────────────────────────────
		if (editMode && editingSong != null) loadEditData();

		_showStep(currentStep);

		FlxG.mouse.visible = true;
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

		cy += 72;

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

		cy += 72;

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

		// Info bar de inst (edit mode — oculta al inicio)
		instInfoText = new FlxText(cx, cy + 40, fileW, "", 10);
		instInfoText.setFormat(Paths.font("vcr.ttf"), 10,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		instInfoText.visible = false;
		g.add(instInfoText);

		cy += 48;

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

		cy += 42;

		// ── Vocals unificadas (Voices.ogg) — visibles cuando split=false ──────
		loadVocalsBtn = _fileBtn(g, cx, cy, "  [Voz]  Load Voices.ogg",
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

		// Info bar de Voices.ogg unificado (edit mode)
		vocalsInfoText = new FlxText(cx, cy + 40, fileW, "", 10);
		vocalsInfoText.setFormat(Paths.font("vcr.ttf"), 10,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		vocalsInfoText.visible = false;
		g.add(vocalsInfoText);

		// ── Contenedor dinámico de slots (visible cuando split=true) ──────────
		_slotContainer = new FlxTypedGroup<Dynamic>();
		g.add(_slotContainer);

		// Slot inicial: bf + dad
		vocalSlots = [];
		_buildVocalSlotUI({charName: "bf",  filePath: "", loaded: false, btn: null, statusText: null, nameInput: null});
		_buildVocalSlotUI({charName: "dad", filePath: "", loaded: false, btn: null, statusText: null, nameInput: null});

		cy += 48;

		// ── Icon ──────────────────────────────────────────────────────────────
		loadIconBtn = _fileBtn(g, cx, cy + vocalSlots.length * 54, "  [Img]  Load Icon.png",
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
		iconStatusText = _statusIcon(g, cx + fileW + 6, cy + vocalSlots.length * 54 + 10, 0.52);

		// Botón + agregar slot
		_addSlotBtn = new FlxButton(cx, cy + vocalSlots.length * 54 - 6, "+ Add character", _onAddSlot);
		_styleBtn(_addSlotBtn, 0xFF388E3C, 180);
		_addSlotBtn.alpha = 0; _slotContainer.add(_addSlotBtn);
		FlxTween.tween(_addSlotBtn, {alpha: 1}, 0.3, {startDelay: 0.52});

		updateFileStatus();
		_rebuildVocalSlots();
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
		var slotY = windowY + 68 + 154 + slotIndex * 54; // debajo del toggle split

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
		var btn = _fileBtn(g, cx + 134, slotY, "  [Voz]  Voices-" + slot.charName + ".ogg",
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
		var cx  = windowX + 40;
		var baseY = windowY + 68 + 154;
		var fileW = windowWidth - 80;
		var bottomY = baseY + vocalSlots.length * 54 - 6;
		if (_addSlotBtn  != null) _addSlotBtn.y  = bottomY;
		if (loadIconBtn  != null) loadIconBtn.y  = bottomY + 48;
		if (iconStatusText != null) iconStatusText.y = bottomY + 58;
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
			for (m in _slotContainer.members)
				if (m != null && Reflect.hasField(m, "visible"))
					Reflect.setProperty(m, "visible", showSplit);
		}
	}

	function _buildStep2():Void
	{
		var g = stepGroups[1];
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
			"It is displayed in the pause menu. Empty = uses the artist field from the chart.", 11);
		h3.setFormat(Paths.font("vcr.ttf"), 11,
			funkin.debug.themes.EditorTheme.current.textSecondary, LEFT);
		h3.alpha = 0; g.add(h3);
		FlxTween.tween(h3, {alpha: 0.7}, 0.3, {startDelay: 0.54});
	}

	function _buildStep3():Void
	{
		var g = stepGroups[2];
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

		// ── Show in Story Mode toggle ──────────────────────────────────────────
		_lbl(g, cx, cy, "Show in Story Mode:", 0.38);
		storyModeToggleBtn = _toggleBtn(g, cx + 230, cy - 4, function()
		{
			showInStoryMode = !showInStoryMode;
			_refreshStoryToggle();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.6);
		}, 0.42);
		storyModeToggleText = _toggleTxt(g, cx + 237, cy, 0.44);
		_refreshStoryToggle();

		cy += 60;

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

		// Mostrar/ocultar grupos de paso
		for (i in 0...stepGroups.length)
			_setGroupVisible(stepGroups[i], i == currentStep - 1);

		// Botones de nav
		prevBtn.visible = (currentStep > 1);
		nextBtn.visible = (currentStep < TOTAL_STEPS);
		saveBtn.visible = (currentStep == TOTAL_STEPS);

		// Indicador
		stepIndicator.text = 'Paso $currentStep / $TOTAL_STEPS';

		// Título de paso
		var stepTitles = ["FILES & BPM", "METADATA", "STORY MENU"];
		titleText.text = (editMode ? "EDIT: " : "ADD: ") + stepTitles[currentStep - 1];

		updateStatus(_stepHint(currentStep));
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
		}

		// Animación de transición entre pasos
		var dir:Int = (step > currentStep) ? 1 : -1;
		var oldGroup = stepGroups[currentStep - 1];
		var newGroup = stepGroups[step - 1];

		_slideOut(oldGroup, dir, function()
		{
			_setGroupVisible(oldGroup, false);
			_showStep(step);
			_slideIn(newGroup, dir);
		});
	}

	function _slideOut(g:FlxTypedGroup<Dynamic>, dir:Int, onDone:Void->Void):Void
	{
		var targetX:Float = dir > 0 ? -80 : 80;
		var count = 0; var total = 0;
		for (m in g.members) if (m != null && Reflect.hasField(m, "x")) total++;
		if (total == 0) { onDone(); return; }
		for (m in g.members)
		{
			if (m == null || !Reflect.hasField(m, "x")) continue;
			FlxTween.tween(m, {alpha: 0, x: Reflect.getProperty(m, "x") + targetX},
				0.18, {ease: FlxEase.quadIn, onComplete: function(_)
				{
					count++;
					if (count >= total) onDone();
				}});
		}
	}

	function _slideIn(g:FlxTypedGroup<Dynamic>, dir:Int):Void
	{
		var startOff:Float = dir > 0 ? 80 : -80;
		_setGroupVisible(g, true);
		for (m in g.members)
		{
			if (m == null || !Reflect.hasField(m, "x")) continue;
			var tx = Reflect.getProperty(m, "x");
			Reflect.setProperty(m, "x", tx + startOff);
			Reflect.setProperty(m, "alpha", 0.0);
			FlxTween.tween(m, {alpha: 1, x: tx}, 0.22, {ease: FlxEase.quadOut});
		}
	}

	function _setGroupVisible(g:FlxTypedGroup<Dynamic>, visible:Bool):Void
	{
		for (m in g.members)
		{
			if (m == null) continue;
			if (Reflect.hasField(m, "visible"))
				Reflect.setProperty(m, "visible", visible);
		}
	}

	function _stepHint(step:Int):String
	{
		return switch (step)
		{
			case STEP_FILES:  "Upload the audio files and enter the BPM of the song.";
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
		while (songListData.songsWeeks.length <= weekIndex)
			songListData.songsWeeks.push({weekSongs:[], songIcons:[], color:[], bpm:[], showInStoryMode:[]});

		var week = songListData.songsWeeks[weekIndex];
		week.weekSongs.push(songName);
		week.songIcons.push(iconNameInput.text.trim());
		week.color.push(selectedColor);
		week.bpm.push(bpmVal);
		if (week.showInStoryMode == null) week.showInStoryMode = [];
		week.showInStoryMode.push(showInStoryMode);

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
		var foundWeekIdx = -1; var foundSongIdx = -1;
		for (wi in 0...songListData.songsWeeks.length)
		{
			var idx = songListData.songsWeeks[wi].weekSongs.indexOf(editingSong.songName);
			if (idx != -1) { foundWeekIdx = wi; foundSongIdx = idx; break; }
		}

		if (foundWeekIdx != -1 && foundWeekIdx == weekIndex)
		{
			var week = songListData.songsWeeks[foundWeekIdx];
			week.weekSongs[foundSongIdx]  = songName;
			week.songIcons[foundSongIdx]  = iconNameInput.text.trim();
			week.color[foundSongIdx]      = selectedColor;
			week.bpm[foundSongIdx]        = bpmVal;
			if (week.showInStoryMode == null) week.showInStoryMode = [];
			while (week.showInStoryMode.length <= foundSongIdx) week.showInStoryMode.push(true);
			week.showInStoryMode[foundSongIdx] = showInStoryMode;
		}
		else
		{
			if (foundWeekIdx != -1)
			{
				var oldWeek = songListData.songsWeeks[foundWeekIdx];
				oldWeek.weekSongs.splice(foundSongIdx, 1);
				oldWeek.songIcons.splice(foundSongIdx, 1);
				oldWeek.color.splice(foundSongIdx, 1);
				oldWeek.bpm.splice(foundSongIdx, 1);
				if (oldWeek.showInStoryMode != null && oldWeek.showInStoryMode.length > foundSongIdx)
					oldWeek.showInStoryMode.splice(foundSongIdx, 1);
			}
			while (songListData.songsWeeks.length <= weekIndex)
				songListData.songsWeeks.push({weekSongs:[], songIcons:[], color:[], bpm:[], showInStoryMode:[]});
			var week = songListData.songsWeeks[weekIndex];
			week.weekSongs.push(songName);
			week.songIcons.push(iconNameInput.text.trim());
			week.color.push(selectedColor);
			week.bpm.push(bpmVal);
			if (week.showInStoryMode == null) week.showInStoryMode = [];
			week.showInStoryMode.push(showInStoryMode);
		}

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

	function saveMetaJSON(songName:String):Void
	{
		var ui         = uiInput        != null ? uiInput.text.trim()        : 'default';
		var noteSkin   = noteSkinInput  != null ? noteSkinInput.text.trim()  : 'default';
		var introVideo = introVideoInput != null ? introVideoInput.text.trim() : '';
		var outroVideo = outroVideoInput != null ? outroVideoInput.text.trim() : '';
		var artist     = artistInput    != null ? artistInput.text.trim()    : '';

		var meta:funkin.data.MetaData.SongMetaData = {
			ui:         ui       != '' ? ui       : 'default',
			noteSkin:   noteSkin != '' ? noteSkin : 'default',
			introVideo: introVideo != '' ? introVideo : null,
			outroVideo: outroVideo != '' ? outroVideo : null,
			artist:     artist     != '' ? artist     : null
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

		for (week in songListData.songsWeeks)
		{
			var idx = week.weekSongs.indexOf(editingSong.songName);
			if (idx != -1)
			{
				if (week.bpm.length > idx)   bpmInput.text = Std.string(week.bpm[idx]);
				if (week.color.length > idx) selectedColor = week.color[idx];
				if (week.showInStoryMode != null && week.showInStoryMode.length > idx)
					showInStoryMode = week.showInStoryMode[idx];
				break;
			}
		}

		updateColorButtons();
		_refreshStoryToggle();

		var m = MetaData.load(editingSong.songName);
		if (uiInput         != null) uiInput.text         = m.ui;
		if (noteSkinInput   != null) noteSkinInput.text   = m.noteSkin;
		if (introVideoInput != null) introVideoInput.text = m.introVideo ?? '';
		if (outroVideoInput != null) outroVideoInput.text = m.outroVideo ?? '';
		if (artistInput     != null) artistInput.text     = m.artist    ?? '';

		needsVoices = _readNeedsVoicesFromChart(editingSong.songName);
		_refreshVoicesToggle();

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
			var dir = _songDir(songName); var levelPath = '$dir/$songName.level';
			if (FileSystem.exists(levelPath)) return;
			var tmpl = _makeBlankSong(songName, bpm);
			LevelFile.saveAll(songName, ['' => tmpl, '-easy' => tmpl, '-hard' => tmpl], null, songName, null);
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

	function _migrateAndPatchCharts(songLower:String, bpmVal:Float):Void
	{
		#if sys
		if (!LevelFile.exists(songLower)) LevelFile.migrateFromJson(songLower);
		var allDiffs = LevelFile.getAvailableDifficulties(songLower);
		if (allDiffs == null || allDiffs.length == 0) return;
		var patched = 0;
		for (pair in allDiffs)
		{
			var suffix = pair[1];
			var song = LevelFile.loadDiff(songLower, suffix);
			if (song == null) continue;
			song.bpm = bpmVal; song.needsVoices = needsVoices;
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
		try { File.saveContent(_songListPath(), Json.stringify(songListData, null, "\t")); }
		catch (e:Dynamic) { updateStatus('Error saving JSON'); }
		#end
	}

	function loadSongList():Void
	{
		var content:String = null;
		#if sys
		if (mods.ModManager.isActive())
		{
			var modPath = '${mods.ModManager.modRoot()}/songs/songList.json';
			if (sys.FileSystem.exists(modPath)) content = sys.io.File.getContent(modPath);
		}
		if (content == null)
		{
			var basePath = 'assets/songs/songList.json';
			if (sys.FileSystem.exists(basePath)) content = sys.io.File.getContent(basePath);
		}
		#end
		if (content == null)
		{
			try { content = lime.utils.Assets.getText(Paths.jsonSong('songList')); } catch (_:Dynamic) {}
		}
		try { songListData = (content != null && content.trim() != '') ? haxe.Json.parse(content) : {songsWeeks:[]}; }
		catch (e:Dynamic) { songListData = {songsWeeks:[]}; }
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

	function _refreshStoryToggle():Void
	{
		var on = showInStoryMode;
		storyModeToggleBtn.makeGraphic(88, 34, on ? 0xFF4CAF50 : 0xFFFF5252);
		storyModeToggleText.text  = on ? "YES" : "NO";
		storyModeToggleText.color = on ? 0xFF4CAF50 : 0xFFFF5252;
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

	function _refreshSplitToggle():Void
	{
		if (_splitToggleBtn  == null) return;
		if (_splitToggleText == null) return;
		_splitToggleBtn.makeGraphic(88, 34, splitVocals ? 0xFF9C27B0 : 0xFF607D8B);
		_splitToggleText.text  = splitVocals ? "SPLIT" : "ÚNICO";
		_splitToggleText.color = splitVocals ? 0xFFCE93D8 : 0xFFB0BEC5;
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UPDATE
	// ═════════════════════════════════════════════════════════════════════════

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// Teclas de navegación de icono (solo en paso 2)
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
