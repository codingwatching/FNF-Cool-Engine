package funkin.debug.editors;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxUICheckBox;
import flixel.addons.ui.FlxUIDropDownMenu;
import flixel.addons.ui.FlxUIInputText;
import flixel.addons.ui.FlxUINumericStepper;
import funkin.debug.CoolTabMenu;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.ui.FlxButton;
import flixel.util.FlxTimer;
import animationdata.FunkinSprite;
import flixel.util.FlxColor;
import funkin.cutscenes.SpriteCutsceneData;
import funkin.debug.themes.EditorTheme;
import funkin.gameplay.PlayState;
import funkin.transitions.StateTransition;
import haxe.Json;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

// ─────────────────────────────────────────────────────────────────────────────
//  CutsceneEditor
// ─────────────────────────────────────────────────────────────────────────────

@:access(flixel.FlxCamera)
class CutsceneEditor extends funkin.states.MusicBeatState
{
	// ── Layout ────────────────────────────────────────────────────────────────
	static inline final TITLE_H:Int  = 34;
	static inline final TOOLBAR_H:Int = 40;
	static inline final TOP_H:Int    = TITLE_H + TOOLBAR_H;
	static inline final STATUS_H:Int = 24;
	static inline final LEFT_W:Int   = 272;
	static inline final RIGHT_W:Int  = 272;
	static inline final ROW_H:Int    = 27;
	static inline final MAX_ROWS:Int = 20;

	// ── Preview panel constants ───────────────────────────────────────────────
	static inline final PREV_W:Int         = 380;
	static inline final PREV_TITLE_H:Int   = 22;
	static inline final PREV_CONTENT_H:Int = 214;  // ≈ PREV_W × 9/16
	static inline final PREV_BTN_H:Int     = 26;
	static inline final PREV_PANEL_H:Int   = 262;  // PREV_TITLE_H + PREV_CONTENT_H + PREV_BTN_H

	// ── Colors ────────────────────────────────────────────────────────────────
	static inline final C_ACCENT:Int     = 0xFF00E5FF;
	static inline final C_ACCENT2:Int    = 0xFFFF4081;
	static inline final C_ACCENT3:Int    = 0xFF69FF47;
	static inline final C_ACCENT4:Int    = 0xFFFFB300;
	static inline final C_ACCENT5:Int    = 0xFFCE93D8;   // animate type
	static inline final C_DANGER:Int     = 0xFFF44336;

	// ── Cameras ───────────────────────────────────────────────────────────────
	var camUI:FlxCamera;
	var camHUD:FlxCamera;

	// ── Document data ─────────────────────────────────────────────────────────
	var doc:CutsceneDocument;
	var spriteKeys:Array<String> = [];
	var currentFilePath:String   = '';
	var hasUnsavedChanges:Bool   = false;

	// ── Selection ─────────────────────────────────────────────────────────────
	var selectedSprKey:String = null;   // selected sprite key
	var selectedStepIdx:Int   = -1;     // selected step index

	// ── Left panel: sprite list ────────────────────────────────────────────────
	var sprPanelBg:FlxSprite;
	var sprRowsGrp:FlxTypedGroup<FlxSprite>;
	var sprTextsGrp:FlxTypedGroup<FlxText>;
	var sprHitData:Array<{y:Float, key:String}> = [];
	var sprScrollStart:Int = 0;

	// ── Right panel: step timeline ─────────────────────────────────────────────
	var stepPanelBg:FlxSprite;
	var stepRowsGrp:FlxTypedGroup<FlxSprite>;
	var stepTextsGrp:FlxTypedGroup<FlxText>;
	var stepHitData:Array<{y:Float, idx:Int}> = [];
	var stepScrollStart:Int = 0;
	var stepActionDropdown:FlxUIDropDownMenu;

	// ── Center: FlxUITabMenu ───────────────────────────────────────────────────
	var centerPanel:CoolTabMenu;
	static inline final CENTER_X:Int = LEFT_W + 2;
	var CENTER_W(get, never):Int;
	inline function get_CENTER_W() return FlxG.width - LEFT_W - RIGHT_W - 4;

	// ── SPRITE tab widgets ─────────────────────────────────────────────────────
	var spr_idInput:FlxUIInputText;
	var spr_typeDropdown:FlxUIDropDownMenu;
	// rect
	var spr_colorInput:FlxUIInputText;
	var spr_widthStepper:FlxUINumericStepper;
	var spr_heightStepper:FlxUINumericStepper;
	// image / atlas / packer
	var spr_imageInput:FlxUIInputText;
	var spr_xmlInput:FlxUIInputText;
	// position / transform
	var spr_xStepper:FlxUINumericStepper;
	var spr_yStepper:FlxUINumericStepper;
	var spr_alphaStepper:FlxUINumericStepper;
	var spr_angleStepper:FlxUINumericStepper;
	var spr_scaleStepper:FlxUINumericStepper;
	var spr_scaleXStepper:FlxUINumericStepper;
	var spr_scaleYStepper:FlxUINumericStepper;
	var spr_scrollStepper:FlxUINumericStepper;
	var spr_flipXCheck:FlxUICheckBox;
	var spr_flipYCheck:FlxUICheckBox;
	var spr_centerCheck:FlxUICheckBox;
	var spr_aaCheck:FlxUICheckBox;
	var spr_camDropdown:FlxUIDropDownMenu;
	// visibility helpers (shown/hidden based on type)
	var spr_rectGroup:FlxTypedGroup<flixel.FlxBasic>;
	var spr_imageGroup:FlxTypedGroup<flixel.FlxBasic>;
	var spr_xmlGroup:FlxTypedGroup<flixel.FlxBasic>;
	var spr_animateHintLabel:FlxText;

	// ── PATHS tab: dynamic path list for "animate" type ────────────────────────
	//  Built/rebuilt outside FlxUITabMenu (same trick as StageEditor anim list)
	var pathRowsBg:FlxTypedGroup<FlxSprite>;
	var pathRowsInputs:FlxTypedGroup<FlxUIInputText>;
	var pathRowsBtns:FlxTypedGroup<FlxSprite>;      // del button bg
	var pathHitData:Array<{y:Float, idx:Int}> = [];
	var pathTabVisible:Bool = false;

	// ── ANIMS tab widgets ──────────────────────────────────────────────────────
	var anim_nameInput:FlxUIInputText;
	var anim_prefixInput:FlxUIInputText;
	var anim_fpsStepper:FlxUINumericStepper;
	var anim_loopCheck:FlxUICheckBox;
	var anim_indicesInput:FlxUIInputText;
	var animListBg:FlxTypedGroup<FlxSprite>;
	var animListText:FlxTypedGroup<FlxText>;
	var animHitData:Array<{y:Float, idx:Int}> = [];
	var selectedAnimIdx:Int = -1;

	// ── STEP tab widgets ───────────────────────────────────────────────────────
	var step_sprDropdown:FlxUIDropDownMenu;
	var step_alphaStepper:FlxUINumericStepper;
	var step_xStepper:FlxUINumericStepper;
	var step_yStepper:FlxUINumericStepper;
	var step_timeStepper:FlxUINumericStepper;
	var step_targetStepper:FlxUINumericStepper;
	var step_stepStepper:FlxUINumericStepper;
	var step_intervalStepper:FlxUINumericStepper;
	var step_durationStepper:FlxUINumericStepper;
	var step_colorInput:FlxUIInputText;
	var step_keyInput:FlxUIInputText;
	var step_animInput:FlxUIInputText;
	var step_idInput:FlxUIInputText;
	var step_funcInput:FlxUIInputText;
	var step_easeDropdown:FlxUIDropDownMenu;
	var step_axisDropdown:FlxUIDropDownMenu;
	var step_asyncCheck:FlxUICheckBox;
	var step_forceCheck:FlxUICheckBox;
	var step_visibleCheck:FlxUICheckBox;
	var step_fadeInCheck:FlxUICheckBox;
	var step_intensityStepper:FlxUINumericStepper;
	var step_volumeStepper:FlxUINumericStepper;
	var step_propsInput:FlxUIInputText;
	// groups shown/hidden per action
	var step_sprGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_alphaGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_xyGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_timeGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_fadeTimerGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_tweenGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_colorGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_soundGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_animGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_axisGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_camGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_shakeGroup:FlxTypedGroup<flixel.FlxBasic>;
	var step_funcGroup:FlxTypedGroup<flixel.FlxBasic>;

	// ── JSON tab ───────────────────────────────────────────────────────────────
	var jsonDisplayText:FlxText;

	// ── HUD helpers ────────────────────────────────────────────────────────────
	var titleText:FlxText;
	var unsavedDot:FlxText;
	var statusText:FlxText;
	var _fileRef:FileReference;
	var _applyLock:Bool = false; // prevents feedback loops when populating widgets

	// Modo de entrada de ruta por teclado (LOAD en desktop)
	var _pathInputMode:Bool   = false;
	var _pathInputBuf:String  = '';
	var _pathInputLbl:FlxText = null;

	// ── Preview panel ─────────────────────────────────────────────────────────
	// Cámara separada que vive SOBRE camHUD — su flashSprite se posiciona
	// con @:access para crear la ventana flotante de preview.
	var camPreview:FlxCamera;

	// Posición de la ventana (esquina sup-izq del panel completo, en pantalla)
	var _prevX:Float = 0;
	var _prevY:Float = 0;

	// UI del panel (en camHUD, coords de pantalla absolutas)
	var _prevPanelBg:FlxSprite;
	var _prevTitleBg:FlxSprite;
	var _prevTitleLbl:FlxText;
	var _prevSep1:FlxSprite;
	var _prevStatusLbl:FlxText;
	var _prevBtnPlay:FlxButton;
	var _prevBtnStop:FlxButton;
	var _prevBtnReset:FlxButton;
	var _prevBtnClose:FlxButton;

	// Sprites de preview (en camPreview, coords de mundo del juego)
	var _previewSprGrp:FlxTypedGroup<FlxSprite>;
	var _previewSprites:Map<String, FlxSprite> = [];

	// Estado inicial para reset (coords de mundo)
	var _previewInitState:Map<String, _PrevInitState> = [];

	// Drag
	var _prevDragging:Bool  = false;
	var _prevDragOffX:Float = 0;
	var _prevDragOffY:Float = 0;

	// Playback
	var _prevPlaying:Bool             = false;
	var _prevStepIdx:Int              = -1;
	var _prevActiveTimers:Array<FlxTimer> = [];
	var _prevActiveTweens:Array<FlxTween> = [];

	// ─────────────────────────────────────────────────────────────────────────
	//  LIFECYCLE
	// ─────────────────────────────────────────────────────────────────────────

	override public function create():Void
	{
		super.create();
		EditorTheme.load();
		var T = EditorTheme.current;

		funkin.system.CursorManager.show();
		funkin.audio.MusicManager.play('chartEditorLoop/chartEditorLoop', 0.6);

		// ── Cameras ───────────────────────────────────────────────────────────
		camUI  = new FlxCamera();
		camUI.bgColor.alpha = 0;

		// camPreview debe estar en la lista ANTES de camHUD para que el HUD
		// (panel, botones) se renderice encima de la preview, no al revés.
		// buildPreviewPanel() la reposiciona pero NO la re-añade.
		camPreview = new FlxCamera(0, 0, PREV_W, PREV_CONTENT_H);
		camPreview.bgColor = 0xFF0B0D1A;
		camPreview.zoom    = PREV_W / FlxG.width;

		camHUD = new FlxCamera();
		camHUD.bgColor = T.bgDark;

		FlxG.cameras.reset(camUI);
		FlxG.cameras.add(camPreview, false);  // ← bajo el HUD
		FlxG.cameras.add(camHUD, false);       // ← HUD encima de todo

		// ── Initial document ──────────────────────────────────────────────────
		doc = { sprites: {}, steps: [], skippable: true };
		_rebuildSpriteKeys();

		// ── Build UI ──────────────────────────────────────────────────────────
		buildPanelBackgrounds();
		buildTitle();
		buildToolbar();
		buildStatus();
		buildSpriteList();
		buildStepList();
		buildPathsOverlay(); // DEBE ir antes de buildCenterTabMenu — éste llama buildSpriteTab()
		                     // → _updateSpriteTypeVisibility() → refreshPathsOverlay(), que
		                     // necesita pathRowsBg/pathRowsInputs/pathRowsBtns ya inicializados.
		buildCenterTabMenu();
		// buildAnimListOverlay: los grupos animListBg/animListText se crean
		// dentro de buildAnimTab() al registrar la pestaña Anim. No se necesita
		// un paso separado — la llamada queda como no-op para compatibilidad.

		refreshSpriteList();
		refreshStepList();
		buildPreviewPanel();
		setStatus('New cutscene — ready.');
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		handleMouse();

		// ── Preview panel drag ────────────────────────────────────────────────
		if (_prevDragging)
		{
			if (FlxG.mouse.pressed)
			{
				_prevX = FlxG.mouse.screenX - _prevDragOffX;
				_prevY = FlxG.mouse.screenY - _prevDragOffY;
				// Clamp dentro de la pantalla
				_prevX = Math.max(0, Math.min(FlxG.width  - PREV_W,      _prevX));
				_prevY = Math.max(0, Math.min(FlxG.height - PREV_PANEL_H, _prevY));
				_applyPreviewPanelPos();
			}
			else _prevDragging = false;
		}

		// ── Actualizar blockInput según el foco de los inputs de texto ─────────
		// Cuando un FlxUIInputText tiene el foco, las teclas van a él, no al juego.
		// Sincronizamos blockInput para que VolumePlugin (tecla 0, +, -) no intente
		// procesar pulsaciones que ya se tragó el input.
		funkin.audio.SoundTray.blockInput = _isTyping();

		if (FlxG.keys.pressed.CONTROL)
		{
			if (FlxG.keys.justPressed.S) saveCutscene();
			if (FlxG.keys.justPressed.O) loadCutscene();
			if (FlxG.keys.justPressed.Z) { /* TODO undo */ }
		}
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (hasUnsavedChanges)
				setStatus('ESC: unsaved changes — press again or save first.');
			else
				StateTransition.switchState(new funkin.menus.MainMenuState());
		}
		if (FlxG.keys.justPressed.DELETE)
		{
			if (selectedSprKey != null) deleteSprite(selectedSprKey);
			else if (selectedStepIdx >= 0) deleteStep(selectedStepIdx);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  PANEL BACKGROUNDS
	// ─────────────────────────────────────────────────────────────────────────

	function buildPanelBackgrounds():Void
	{
		var T = EditorTheme.current;
		var h = FlxG.height - TOP_H - STATUS_H;

		// Left panel bg
		sprPanelBg = new FlxSprite(0, TOP_H).makeGraphic(LEFT_W, h, T.bgPanel);
		sprPanelBg.cameras = [camHUD]; sprPanelBg.scrollFactor.set(); add(sprPanelBg);

		// Right panel bg
		stepPanelBg = new FlxSprite(FlxG.width - RIGHT_W, TOP_H).makeGraphic(RIGHT_W, h, T.bgPanel);
		stepPanelBg.cameras = [camHUD]; stepPanelBg.scrollFactor.set(); add(stepPanelBg);

		// Center panel bg
		var cBg = new FlxSprite(CENTER_X, TOP_H).makeGraphic(CENTER_W, h, T.bgPanelAlt);
		cBg.cameras = [camHUD]; cBg.scrollFactor.set(); add(cBg);

		// Dividers
		function vline(x:Float):Void
		{
			var d = new FlxSprite(x, TOP_H).makeGraphic(2, h, T.borderColor);
			d.cameras = [camHUD]; d.scrollFactor.set(); add(d);
		}
		vline(LEFT_W);
		vline(FlxG.width - RIGHT_W - 2);

		// Panel headers
		function header(x:Float, w:Int, label:String, col:Int):Void
		{
			var bg = new FlxSprite(x, TOP_H).makeGraphic(w, ROW_H + 2, T.bgPanelAlt);
			bg.cameras = [camHUD]; bg.scrollFactor.set(); add(bg);
			var t = new FlxText(x + 8, TOP_H + 5, w, label, 11);
			t.setFormat(Paths.font('vcr.ttf'), 11, col, LEFT);
			t.cameras = [camHUD]; t.scrollFactor.set(); add(t);
			var sep = new FlxSprite(x, TOP_H + ROW_H + 2).makeGraphic(w, 1, T.borderColor);
			sep.cameras = [camHUD]; sep.scrollFactor.set(); add(sep);
		}
		header(0, LEFT_W, 'SPRITES', C_ACCENT);
		header(FlxG.width - RIGHT_W, RIGHT_W, 'TIMELINE', C_ACCENT2);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  TITLE & TOOLBAR
	// ─────────────────────────────────────────────────────────────────────────

	function buildTitle():Void
	{
		var T = EditorTheme.current;
		var bg = new FlxSprite(0, 0).makeGraphic(FlxG.width, TITLE_H, T.bgPanelAlt);
		bg.cameras = [camHUD]; bg.scrollFactor.set(); add(bg);
		var sep = new FlxSprite(0, TITLE_H - 1).makeGraphic(FlxG.width, 1, T.borderColor);
		sep.cameras = [camHUD]; sep.scrollFactor.set(); add(sep);

		titleText = new FlxText(10, 6, 0, 'CUTSCENE EDITOR', 16);
		titleText.setFormat(Paths.font('vcr.ttf'), 16, C_ACCENT, LEFT);
		titleText.cameras = [camHUD]; titleText.scrollFactor.set(); add(titleText);

		unsavedDot = new FlxText(0, 8, 0, '  ● UNSAVED', 11);
		unsavedDot.setFormat(Paths.font('vcr.ttf'), 11, T.warning, LEFT);
		unsavedDot.visible = false;
		unsavedDot.cameras = [camHUD]; unsavedDot.scrollFactor.set(); add(unsavedDot);
	}

	function buildToolbar():Void
	{
		var T = EditorTheme.current;
		var tbBg = new FlxSprite(0, TITLE_H).makeGraphic(FlxG.width, TOOLBAR_H, T.bgPanel);
		tbBg.cameras = [camHUD]; tbBg.scrollFactor.set(); add(tbBg);
		var sep = new FlxSprite(0, TITLE_H + TOOLBAR_H - 1).makeGraphic(FlxG.width, 1, T.borderColor);
		sep.cameras = [camHUD]; sep.scrollFactor.set(); add(sep);

		function btn(x:Int, label:String, col:Int, cb:Void->Void):FlxButton
		{
			var b = new FlxButton(x, TITLE_H + 8, label, cb);
			b.cameras = [camHUD]; b.scrollFactor.set(); add(b);
			return b;
		}
		btn(8,   'NEW',          0xFF334422, newDocument);
		btn(80,  'LOAD',         0xFF333344, loadCutscene);
		btn(152, 'LOAD SONG',    0xFF333355, loadFromSong);
		btn(248, 'SAVE',         0xFF334422, saveCutscene);
		btn(320, 'SAVE TO MOD',  0xFF332233, saveCutsceneMod);

		// + Sprite and + Step quick buttons
		btn(FlxG.width - RIGHT_W + 6, '+ SPRITE', 0xFF004422, addSpriteDialog);
		btn(FlxG.width - RIGHT_W + 86, 'SKIPPABLE', 0xFF222244, toggleSkippable);

		// Unsaved dot position after title
		unsavedDot.x = titleText.x + titleText.width + 4;
	}

	function buildStatus():Void
	{
		var T = EditorTheme.current;
		var bg = new FlxSprite(0, FlxG.height - STATUS_H).makeGraphic(FlxG.width, STATUS_H, T.bgPanelAlt);
		bg.cameras = [camHUD]; bg.scrollFactor.set(); add(bg);
		var sep = new FlxSprite(0, FlxG.height - STATUS_H).makeGraphic(FlxG.width, 1, T.borderColor);
		sep.cameras = [camHUD]; sep.scrollFactor.set(); add(sep);

		statusText = new FlxText(8, FlxG.height - STATUS_H + 5, FlxG.width - 16, '', 11);
		statusText.setFormat(Paths.font('vcr.ttf'), 11, T.textSecondary, LEFT);
		statusText.cameras = [camHUD]; statusText.scrollFactor.set(); add(statusText);
	}

	function setStatus(msg:String):Void
	{
		if (statusText != null) statusText.text = msg;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  SPRITE LIST  (left panel)
	// ─────────────────────────────────────────────────────────────────────────

	function buildSpriteList():Void
	{
		sprRowsGrp  = new FlxTypedGroup<FlxSprite>();
		sprTextsGrp = new FlxTypedGroup<FlxText>();
		sprRowsGrp.cameras  = [camHUD];
		sprTextsGrp.cameras = [camHUD];
		add(sprRowsGrp);
		add(sprTextsGrp);

		var MAX = MAX_ROWS;
		for (i in 0...MAX)
		{
			var row = new FlxSprite();
			row.scrollFactor.set();
			sprRowsGrp.add(row);

			var t1 = new FlxText(0, 0, LEFT_W - 80, '', 10);
			t1.setFormat(Paths.font('vcr.ttf'), 10, 0xFFCCCCCC, LEFT);
			t1.scrollFactor.set();
			sprTextsGrp.add(t1);

			var t2 = new FlxText(0, 0, 60, '', 9);
			t2.setFormat(Paths.font('vcr.ttf'), 9, 0xFF888888, RIGHT);
			t2.scrollFactor.set();
			sprTextsGrp.add(t2);
		}
	}

	function refreshSpriteList():Void
	{
		var T   = EditorTheme.current;
		var panH = FlxG.height - TOP_H - STATUS_H - ROW_H - 4;
		var maxVis = Std.int(panH / ROW_H);
		var startY = TOP_H + ROW_H + 4;

		// Scroll clamp
		var total = spriteKeys.length;
		if (sprScrollStart > total - maxVis && total > maxVis)
			sprScrollStart = total - maxVis;
		if (sprScrollStart < 0) sprScrollStart = 0;

		sprHitData = [];
		var count  = 0;

		for (i in 0...MAX_ROWS)
		{
			var row   = sprRowsGrp.members[i];
			var tName = sprTextsGrp.members[i * 2];
			var tType = sprTextsGrp.members[i * 2 + 1];
			if (row == null) continue;

			var dataIdx = i + sprScrollStart;
			if (dataIdx >= total)
			{
				row.visible = tName.visible = tType.visible = false;
				continue;
			}

			var key  = spriteKeys[dataIdx];
			var data:CutsceneSpriteData = Reflect.field(doc.sprites, key);
			var type = data != null ? (data.type ?? 'rect') : '?';
			var sel  = (key == selectedSprKey);

			var rowY = startY + count * ROW_H;
			row.makeGraphic(LEFT_W, ROW_H - 1, sel ? 0x22FFFFFF : (count % 2 == 0 ? T.rowEven : T.rowOdd));
			row.x = 0; row.y = rowY; row.visible = true;
			if (sel)
			{
				var acc = new FlxSprite(0, rowY).makeGraphic(3, ROW_H - 1, C_ACCENT);
				acc.cameras = [camHUD]; acc.scrollFactor.set();
				// inline draw accent
				row.makeGraphic(LEFT_W, ROW_H - 1, 0x22FFFFFF);
			}

			tName.x = 12; tName.y = rowY + 7; tName.text = key; tName.visible = true;
			tName.color = sel ? C_ACCENT : T.textPrimary;

			var typeColor = switch(type) {
				case 'atlas':   C_ACCENT;
				case 'animate': C_ACCENT5;
				case 'image':   C_ACCENT3;
				case 'packer':  C_ACCENT2;
				default:        C_ACCENT4;  // rect
			};
			tType.x = LEFT_W - 68; tType.y = rowY + 7; tType.text = '[${type}]'; tType.visible = true;
			tType.color = typeColor;

			sprHitData.push({ y: rowY, key: key });
			count++;
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  STEP LIST  (right panel)
	// ─────────────────────────────────────────────────────────────────────────

	function buildStepList():Void
	{
		var T = EditorTheme.current;
		stepRowsGrp  = new FlxTypedGroup<FlxSprite>();
		stepTextsGrp = new FlxTypedGroup<FlxText>();
		stepRowsGrp.cameras  = [camHUD];
		stepTextsGrp.cameras = [camHUD];
		add(stepRowsGrp);
		add(stepTextsGrp);

		// "Add step" dropdown + button — lives on camHUD, above the list
		var actions = [
			'add','remove','setAlpha','setColor','setVisible','setPosition','screenCenter',
			'playAnim','wait','fadeTimer','tween','playSound','waitSound',
			'cameraFade','cameraFlash','cameraShake','script','end'
		];
		var dropX = FlxG.width - RIGHT_W + 4;
		var dropY = TOP_H + ROW_H + 4;
		stepActionDropdown = new FlxUIDropDownMenu(dropX, dropY,
			FlxUIDropDownMenu.makeStrIdLabelArray(actions, true), null);
		stepActionDropdown.cameras = [camHUD];
		stepActionDropdown.scrollFactor.set();
		add(stepActionDropdown);

		var addBtn = new FlxButton(dropX + 160, dropY, '+ ADD', addStepFromDropdown);
		addBtn.cameras = [camHUD]; addBtn.scrollFactor.set(); add(addBtn);

		for (i in 0...MAX_ROWS)
		{
			var row = new FlxSprite();
			row.scrollFactor.set();
			stepRowsGrp.add(row);

			var t1 = new FlxText(0, 0, 20, '', 9);
			t1.setFormat(Paths.font('vcr.ttf'), 9, 0xFF666688, LEFT);
			t1.scrollFactor.set();
			stepTextsGrp.add(t1);

			var t2 = new FlxText(0, 0, RIGHT_W - 70, '', 10);
			t2.setFormat(Paths.font('vcr.ttf'), 10, 0xFFCCCCCC, LEFT);
			t2.scrollFactor.set();
			stepTextsGrp.add(t2);

			var t3 = new FlxText(0, 0, RIGHT_W - 70, '', 9);
			t3.setFormat(Paths.font('vcr.ttf'), 9, 0xFF888888, LEFT);
			t3.scrollFactor.set();
			stepTextsGrp.add(t3);
		}
	}

	function refreshStepList():Void
	{
		var T      = EditorTheme.current;
		var dropRowH = ROW_H + 8;
		var startY = TOP_H + ROW_H + 4 + dropRowH + 4;
		var panH   = FlxG.height - startY - STATUS_H;
		var maxVis = Std.int(panH / ROW_H);
		var total  = doc.steps.length;

		if (stepScrollStart > total - maxVis && total > maxVis)
			stepScrollStart = total - maxVis;
		if (stepScrollStart < 0) stepScrollStart = 0;

		stepHitData = [];
		var count   = 0;

		for (i in 0...MAX_ROWS)
		{
			var row  = stepRowsGrp.members[i];
			var tNum = stepTextsGrp.members[i * 3];
			var tAct = stepTextsGrp.members[i * 3 + 1];
			var tDsc = stepTextsGrp.members[i * 3 + 2];
			if (row == null) continue;

			var dataIdx = i + stepScrollStart;
			if (dataIdx >= total)
			{
				row.visible = tNum.visible = tAct.visible = tDsc.visible = false;
				continue;
			}

			var step = doc.steps[dataIdx];
			var sel  = (dataIdx == selectedStepIdx);
			var rowY = startY + count * ROW_H;

			row.makeGraphic(RIGHT_W, ROW_H - 1, sel ? 0x22FFFFFF : (count % 2 == 0 ? T.rowEven : T.rowOdd));
			row.x = FlxG.width - RIGHT_W; row.y = rowY; row.visible = true;

			tNum.x = FlxG.width - RIGHT_W + 4; tNum.y = rowY + 8; tNum.text = '${dataIdx + 1}'; tNum.visible = true;

			var actCol = _actionColor(step.action);
			tAct.x = FlxG.width - RIGHT_W + 26; tAct.y = rowY + 5;
			tAct.text = step.action; tAct.visible = true; tAct.color = sel ? 0xFFFFFFFF : actCol;

			var desc = _stepDesc(step);
			tDsc.x = FlxG.width - RIGHT_W + 26; tDsc.y = rowY + 16;
			tDsc.text = desc; tDsc.visible = true; tDsc.color = 0xFF8899AA;

			stepHitData.push({ y: rowY, idx: dataIdx });
			count++;
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  CENTER TAB MENU
	// ─────────────────────────────────────────────────────────────────────────

	function buildCenterTabMenu():Void
	{
		var T      = EditorTheme.current;
		var panelH = FlxG.height - TOP_H - STATUS_H;
		var cx     = CENTER_X;
		var cw     = CENTER_W;

		var tabs = [
			{ name: 'Anim',   label: 'ANIMACIONES' },
			{ name: 'JSON',   label: 'JSON' },
			{ name: 'Sprite', label: 'SPRITE' },
			{ name: 'Step',   label: 'STEP' },
		];

		centerPanel = new CoolTabMenu(null, tabs, true);
		centerPanel.resize(cw, panelH);
		centerPanel.x = cx;
		centerPanel.y = TOP_H;
		centerPanel.scrollFactor.set();
		centerPanel.cameras = [camHUD];
		add(centerPanel);

		buildSpriteTab();
		buildAnimTab();
		buildStepTab();
		buildJSONTab();
	}

	// ── SPRITE tab ────────────────────────────────────────────────────────────

	function buildSpriteTab():Void
	{
		var T   = EditorTheme.current;
		var tab = new FlxUI(null, centerPanel);
		tab.name = 'Sprite';
		var W   = CENTER_W - 20;
		var y   = 8.0;

		inline function lbl(txt:String):FlxText
		{
			var t = new FlxText(8, y, 0, txt, 10);
			t.color = T.textSecondary;
			tab.add(t);
			return t;
		}
		inline function sep():Void
		{
			var s = new FlxSprite(4, y).makeGraphic(W, 1, T.borderColor);
			s.alpha = 0.3;
			tab.add(s);
			y += 6;
		}

		// ID
		lbl('Sprite ID:');  y += 14;
		spr_idInput = new FlxUIInputText(8, y, W, '', 10);
		tab.add(spr_idInput);
		var applyIdBtn = new FlxButton(W - 36, y, 'RENAME', applySpriteId);
		tab.add(applyIdBtn);
		y += 28;

		sep();
		lbl('Type:');  y += 14;
		var types = ['rect', 'image', 'atlas', 'packer', 'animate'];
		spr_typeDropdown = new FlxUIDropDownMenu(8, y, FlxUIDropDownMenu.makeStrIdLabelArray(types, true),
			function(sel:String) {
				if (_applyLock || selectedSprKey == null) return;
				var d:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
				if (d == null) return;
				d.type = types[Std.parseInt(sel)];
				_markUnsaved();
				_updateSpriteTypeVisibility(d.type);
				refreshSpriteList();
			});
		tab.add(spr_typeDropdown);
		y += 30;

		sep();
		// ── rect fields ──
		spr_rectGroup = new FlxTypedGroup<flixel.FlxBasic>();
		var rectLbl = new FlxText(8, y, 0, 'Color (hex / name):', 10);
		rectLbl.color = T.textSecondary; spr_rectGroup.add(rectLbl);
		spr_colorInput = new FlxUIInputText(8, y + 13, W, '0xFF000000', 10);
		spr_rectGroup.add(spr_colorInput);
		var wlbl = new FlxText(8, y + 32, 0, 'Width ×:', 10); wlbl.color = T.textSecondary; spr_rectGroup.add(wlbl);
		var hlbl = new FlxText(120, y + 32, 0, 'Height ×:', 10); hlbl.color = T.textSecondary; spr_rectGroup.add(hlbl);
		spr_widthStepper  = new FlxUINumericStepper(8, y + 44, 0.1, 2, 0.1, 20, 2);
		spr_heightStepper = new FlxUINumericStepper(120, y + 44, 0.1, 2, 0.1, 20, 2);
		spr_rectGroup.add(spr_widthStepper);
		spr_rectGroup.add(spr_heightStepper);
		for (m in spr_rectGroup.members) tab.add(cast m);
		y += 68;

		// ── image / atlas / packer fields ──
		spr_imageGroup = new FlxTypedGroup<flixel.FlxBasic>();
		var imgLbl = new FlxText(8, y, 0, 'Image path (no ext):',10); imgLbl.color = T.textSecondary; spr_imageGroup.add(imgLbl);
		spr_imageInput = new FlxUIInputText(8, y + 13, W, '', 10);
		spr_imageGroup.add(spr_imageInput);
		var imgHint = new FlxText(8, y + 28, W, 'ej: weeb/senpaiCrazy  o  characters/dad', 8);
		imgHint.color = T.textDim; spr_imageGroup.add(imgHint);
		for (m in spr_imageGroup.members) tab.add(cast m);

		spr_xmlGroup = new FlxTypedGroup<flixel.FlxBasic>();
		var xmlLbl = new FlxText(8, y + 38, 0, 'XML override (vacío = igual que image):', 10);
		xmlLbl.color = T.textSecondary; spr_xmlGroup.add(xmlLbl);
		spr_xmlInput = new FlxUIInputText(8, y + 51, W, '', 10);
		spr_xmlGroup.add(spr_xmlInput);
		for (m in spr_xmlGroup.members) tab.add(cast m);
		y += 72;

		// ── animate hint ──
		spr_animateHintLabel = new FlxText(8, y, W,
			'tipo "animate": usa la pestaña PATHS para\nconfigurar las carpetas de atlas.', 10);
		spr_animateHintLabel.color = C_ACCENT5;
		tab.add(spr_animateHintLabel);
		y += 36;

		sep();
		// ── Position / Transform ──
		lbl('Posición  X:');  y += 14;
		spr_xStepper = new FlxUINumericStepper(8,   y, 5, 0, -4000, 4000, 0);
		spr_yStepper = new FlxUINumericStepper(130, y, 5, 0, -4000, 4000, 0);
		tab.add(spr_xStepper); tab.add(spr_yStepper);
		var ylbl2 = new FlxText(122, y - 14, 0, 'Y:', 10); ylbl2.color = T.textSecondary; tab.add(ylbl2);
		y += 28;

		lbl('Alpha:');  y += 14;
		spr_alphaStepper = new FlxUINumericStepper(8, y, 0.05, 1, 0, 1, 2);
		tab.add(spr_alphaStepper);
		var angleLbl = new FlxText(100, y - 14, 0, 'Angle:', 10); angleLbl.color = T.textSecondary; tab.add(angleLbl);
		spr_angleStepper = new FlxUINumericStepper(100, y, 1, 0, -360, 360, 0);
		tab.add(spr_angleStepper);
		y += 28;

		lbl('Scale:');  y += 14;
		spr_scaleStepper = new FlxUINumericStepper(8, y, 0.1, 1, 0.01, 20, 2);
		tab.add(spr_scaleStepper);
		var sxLbl = new FlxText(100, y-14, 0, 'ScaleX:', 10); sxLbl.color = T.textSecondary; tab.add(sxLbl);
		spr_scaleXStepper = new FlxUINumericStepper(100, y, 0.1, 1, 0.01, 20, 2);
		tab.add(spr_scaleXStepper);
		var syLbl = new FlxText(200, y-14, 0, 'ScaleY:', 10); syLbl.color = T.textSecondary; tab.add(syLbl);
		spr_scaleYStepper = new FlxUINumericStepper(200, y, 0.1, 1, 0.01, 20, 2);
		tab.add(spr_scaleYStepper);
		y += 28;

		lbl('Scroll Factor:');  y += 14;
		spr_scrollStepper = new FlxUINumericStepper(8, y, 0.05, 0, 0, 1, 2);
		tab.add(spr_scrollStepper);
		var camLbl = new FlxText(110, y-14, 0, 'Cámara:', 10); camLbl.color = T.textSecondary; tab.add(camLbl);
		spr_camDropdown = new FlxUIDropDownMenu(110, y, FlxUIDropDownMenu.makeStrIdLabelArray(['game','hud'], true), null);
		tab.add(spr_camDropdown);
		y += 28;

		sep();
		spr_flipXCheck  = new FlxUICheckBox(8,   y, null, null, 'flipX', 70);
		spr_flipYCheck  = new FlxUICheckBox(80,  y, null, null, 'flipY', 70);
		spr_centerCheck = new FlxUICheckBox(152, y, null, null, 'center', 80);
		spr_aaCheck     = new FlxUICheckBox(8,   y + 22, null, null, 'antialiasing', 120);
		tab.add(spr_flipXCheck); tab.add(spr_flipYCheck);
		tab.add(spr_centerCheck); tab.add(spr_aaCheck);
		y += 48;

		sep();
		var applyBtn = new FlxButton(8, y, 'APPLY CHANGES', applySprite);
		tab.add(applyBtn);
		var delBtn = new FlxButton(120, y, 'DELETE SPRITE', function() {
			if (selectedSprKey != null) deleteSprite(selectedSprKey);
		});
		delBtn.color = C_DANGER;
		tab.add(delBtn);

		centerPanel.addGroup(tab);
		_updateSpriteTypeVisibility('rect');
	}

	// ── ANIMACIONES tab ───────────────────────────────────────────────────────

	function buildAnimTab():Void
	{
		var T   = EditorTheme.current;
		var tab = new FlxUI(null, centerPanel);
		tab.name = 'Anim';
		var y   = 8.0;
		var W   = CENTER_W - 20;

		inline function lbl(txt:String):Void
		{
			var t = new FlxText(8, y, 0, txt, 10);
			t.color = T.textSecondary;
			tab.add(t);
		}

		var info = new FlxText(8, y, W,
			'Animaciones del sprite seleccionado.\nHaz click en una fila para editar.', 10);
		info.color = T.textSecondary; tab.add(info);
		y += 30;

		var addBtn = new FlxButton(8, y, '+ NUEVA ANIMACIÓN', addAnimation);
		tab.add(addBtn);
		y += 28;

		// Selected animation fields
		lbl('Nombre:'); y += 14;
		anim_nameInput = new FlxUIInputText(8, y, W, '', 10); tab.add(anim_nameInput);
		y += 22;
		lbl('Prefix (nombre en el atlas):'); y += 14;
		anim_prefixInput = new FlxUIInputText(8, y, W, '', 10); tab.add(anim_prefixInput);
		y += 22;
		lbl('FPS:'); y += 14;
		anim_fpsStepper = new FlxUINumericStepper(8, y, 1, 24, 1, 120, 0); tab.add(anim_fpsStepper);
		anim_loopCheck = new FlxUICheckBox(100, y, null, null, 'loop', 60); tab.add(anim_loopCheck);
		y += 26;
		lbl('Indices (vacío = todos):'); y += 14;
		anim_indicesInput = new FlxUIInputText(8, y, W, '', 10); tab.add(anim_indicesInput);
		var hint = new FlxText(8, y + 14, W, 'ej: 0,1,2,3  o  0..12', 8);
		hint.color = T.textDim; tab.add(hint);
		y += 30;

		var saveAnimBtn = new FlxButton(8, y, 'GUARDAR ANIMACIÓN', applyAnim);
		tab.add(saveAnimBtn);
		var delAnimBtn = new FlxButton(120, y, 'BORRAR', deleteAnim);
		delAnimBtn.color = C_DANGER; tab.add(delAnimBtn);
		y += 28;

		// Animation list is built as overlay (outside FlxUITabMenu)
		var listHintLabel = new FlxText(8, y, W, '↓  Lista de animaciones del sprite ↓', 9);
		listHintLabel.color = T.textDim; tab.add(listHintLabel);

		centerPanel.addGroup(tab);

		// Build the overlay list groups
		animListBg   = new FlxTypedGroup<FlxSprite>();
		animListText = new FlxTypedGroup<FlxText>();
		animListBg.cameras   = [camHUD];
		animListText.cameras = [camHUD];
		add(animListBg);
		add(animListText);
	}

	// ── STEP tab ──────────────────────────────────────────────────────────────

	function buildStepTab():Void
	{
		var T   = EditorTheme.current;
		var tab = new FlxUI(null, centerPanel);
		tab.name = 'Step';
		var y   = 8.0;
		var W   = CENTER_W - 20;

		inline function lbl(txt:String, ?lx:Float, ?ly:Float):FlxText
		{
			var t = new FlxText(lx ?? 8, ly ?? y, 0, txt, 10);
			t.color = T.textSecondary;
			tab.add(t);
			return t;
		}
		inline function sep():Void
		{
			var s = new FlxSprite(4, y).makeGraphic(W, 1, T.borderColor);
			s.alpha = 0.25; tab.add(s); y += 6;
		}

		var noSelLbl = new FlxText(8, y, W,
			'Selecciona un paso en la TIMELINE (panel derecho)\npara editar sus propiedades aquí.', 10);
		noSelLbl.color = T.textDim; tab.add(noSelLbl);
		y += 30;
		sep();

		// ── shared: sprite selector ──
		step_sprGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_sprGroup.add(lbl('Sprite:', 8, y));
		y += 14;
		step_sprDropdown = new FlxUIDropDownMenu(8, y, FlxUIDropDownMenu.makeStrIdLabelArray(['(ninguno)'], true), null);
		step_sprGroup.add(step_sprDropdown);
		y += 28;
		sep();
		for (m in step_sprGroup.members) if (m != null) tab.add(cast m);

		// ── alpha ──
		step_alphaGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_alphaGroup.add(lbl('Alpha:', 8, y)); y += 14;
		step_alphaStepper = new FlxUINumericStepper(8, y, 0.05, 1, 0, 1, 2);
		step_alphaGroup.add(step_alphaStepper); y += 26; sep();
		for (m in step_alphaGroup.members) if (m != null) tab.add(cast m);

		// ── xy ──
		step_xyGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_xyGroup.add(lbl('X:', 8, y));
		step_xyGroup.add(lbl('Y:', 110, y)); y += 14;
		step_xStepper = new FlxUINumericStepper(8, y, 1, 0, -4000, 4000, 0);
		step_yStepper = new FlxUINumericStepper(110, y, 1, 0, -4000, 4000, 0);
		step_xyGroup.add(step_xStepper); step_xyGroup.add(step_yStepper); y += 28; sep();
		for (m in step_xyGroup.members) if (m != null) tab.add(cast m);

		// ── axis ──
		step_axisGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_axisGroup.add(lbl('Axis (screenCenter):', 8, y)); y += 14;
		step_axisDropdown = new FlxUIDropDownMenu(8, y, FlxUIDropDownMenu.makeStrIdLabelArray(['xy','x','y'], true), null);
		step_axisGroup.add(step_axisDropdown); y += 28; sep();
		for (m in step_axisGroup.members) if (m != null) tab.add(cast m);

		// ── time ──
		step_timeGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_timeGroup.add(lbl('Tiempo (segundos):', 8, y)); y += 14;
		step_timeStepper = new FlxUINumericStepper(8, y, 0.1, 1, 0, 60, 2);
		step_timeGroup.add(step_timeStepper); y += 26; sep();
		for (m in step_timeGroup.members) if (m != null) tab.add(cast m);

		// ── fadeTimer ──
		step_fadeTimerGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_fadeTimerGroup.add(lbl('Target α:', 8, y));
		step_fadeTimerGroup.add(lbl('Step:', 110, y)); y += 14;
		step_targetStepper   = new FlxUINumericStepper(8,   y, 0.05, 0, 0, 1, 2);
		step_stepStepper     = new FlxUINumericStepper(110, y, 0.01, 0.15, 0, 1, 2);
		step_fadeTimerGroup.add(step_targetStepper); step_fadeTimerGroup.add(step_stepStepper);
		y += 28;
		step_fadeTimerGroup.add(lbl('Interval (s):', 8, y)); y += 14;
		step_intervalStepper = new FlxUINumericStepper(8, y, 0.05, 0.3, 0.01, 5, 2);
		step_fadeTimerGroup.add(step_intervalStepper); y += 26; sep();
		for (m in step_fadeTimerGroup.members) if (m != null) tab.add(cast m);

		// ── tween ──
		step_tweenGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_tweenGroup.add(lbl('Props JSON (ej: {"alpha":1,"x":100}):', 8, y)); y += 14;
		step_propsInput = new FlxUIInputText(8, y, W, '{}', 10);
		step_tweenGroup.add(step_propsInput); y += 22;
		step_tweenGroup.add(lbl('Duration:', 8, y));
		step_tweenGroup.add(lbl('Ease:', 110, y)); y += 14;
		step_durationStepper = new FlxUINumericStepper(8, y, 0.1, 1, 0.01, 60, 2);
		var eases = ['linear','quadIn','quadOut','quadInOut','sineIn','sineOut','sineInOut',
		             'cubeIn','cubeOut','elasticIn','elasticOut','bounceOut','backIn','backOut'];
		step_easeDropdown = new FlxUIDropDownMenu(110, y, FlxUIDropDownMenu.makeStrIdLabelArray(eases, true), null);
		step_tweenGroup.add(step_durationStepper); step_tweenGroup.add(step_easeDropdown);
		y += 28;
		step_asyncCheck = new FlxUICheckBox(8, y, null, null, 'async (no esperar)', 160);
		step_tweenGroup.add(step_asyncCheck); y += 26; sep();
		for (m in step_tweenGroup.members) if (m != null) tab.add(cast m);

		// ── color ──
		step_colorGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_colorGroup.add(lbl('Color (WHITE / BLACK / 0xFFRRGGBB):', 8, y)); y += 14;
		step_colorInput = new FlxUIInputText(8, y, W, 'WHITE', 10);
		step_colorGroup.add(step_colorInput);
		step_fadeInCheck = new FlxUICheckBox(8, y + 20, null, null, 'fadeIn (desde el color)', 200);
		step_colorGroup.add(step_fadeInCheck); y += 50; sep();
		for (m in step_colorGroup.members) if (m != null) tab.add(cast m);

		// ── camera fade/flash duration ──
		step_camGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_camGroup.add(lbl('Duración (s):', 8, y)); y += 14;
		step_durationStepper = new FlxUINumericStepper(8, y, 0.05, 0.5, 0.01, 10, 2);
		step_camGroup.add(step_durationStepper); y += 26; sep();
		for (m in step_camGroup.members) if (m != null) tab.add(cast m);

		// ── sound ──
		step_soundGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_soundGroup.add(lbl('Clave de sonido (sin ext):', 8, y)); y += 14;
		step_keyInput = new FlxUIInputText(8, y, W, '', 10);
		step_soundGroup.add(step_keyInput); y += 22;
		step_soundGroup.add(lbl('ID (para waitSound):', 8, y));
		step_soundGroup.add(lbl('Volumen:', 130, y)); y += 14;
		step_idInput = new FlxUIInputText(8, y, 100, '', 10);
		step_volumeStepper = new FlxUINumericStepper(130, y, 0.05, 1, 0, 1, 2);
		step_soundGroup.add(step_idInput); step_soundGroup.add(step_volumeStepper);
		y += 26; sep();
		for (m in step_soundGroup.members) if (m != null) tab.add(cast m);

		// ── anim ──
		step_animGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_animGroup.add(lbl('Nombre de animación:', 8, y)); y += 14;
		step_animInput = new FlxUIInputText(8, y, W, '', 10);
		step_animGroup.add(step_animInput);
		step_forceCheck = new FlxUICheckBox(8, y + 20, null, null, 'force (reiniciar si ya estaba)', 200);
		step_animGroup.add(step_forceCheck); y += 46; sep();
		for (m in step_animGroup.members) if (m != null) tab.add(cast m);

		// ── cameraShake intensity ──
		step_shakeGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_shakeGroup.add(lbl('Intensity:', 8, y));
		step_shakeGroup.add(lbl('Duration:', 110, y)); y += 14;
		step_intensityStepper = new FlxUINumericStepper(8, y, 0.005, 0.03, 0, 1, 3);
		step_shakeGroup.add(step_intensityStepper); y += 26; sep();
		for (m in step_shakeGroup.members) if (m != null) tab.add(cast m);

		// ── script func ──
		step_funcGroup = new FlxTypedGroup<flixel.FlxBasic>();
		step_funcGroup.add(lbl('Función a llamar en el script:', 8, y)); y += 14;
		step_funcInput = new FlxUIInputText(8, y, W, '', 10);
		step_funcGroup.add(step_funcInput); y += 26; sep();
		for (m in step_funcGroup.members) if (m != null) tab.add(cast m);

		var applyBtn = new FlxButton(8, y, 'APPLY STEP', applyStep);
		tab.add(applyBtn);
		var delBtn = new FlxButton(110, y, 'DELETE STEP', function() {
			if (selectedStepIdx >= 0) deleteStep(selectedStepIdx);
		});
		delBtn.color = C_DANGER; tab.add(delBtn);

		centerPanel.addGroup(tab);
	}

	// ── JSON tab ──────────────────────────────────────────────────────────────

	function buildJSONTab():Void
	{
		var T   = EditorTheme.current;
		var tab = new FlxUI(null, centerPanel);
		tab.name = 'JSON';
		var W   = CENTER_W - 16;

		var info = new FlxText(8, 8, W, 'JSON del documento actual:', 10);
		info.color = T.textSecondary; tab.add(info);

		jsonDisplayText = new FlxText(8, 24, W, '', 9);
		jsonDisplayText.setFormat(Paths.font('vcr.ttf'), 9, T.textPrimary, LEFT);
		tab.add(jsonDisplayText);

		var copyBtn = new FlxButton(8, 8 + W / 2 + 4, 'REFRESH JSON', refreshJSONTab);
		tab.add(copyBtn);

		centerPanel.addGroup(tab);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  PATHS OVERLAY  (for "animate" multi-atlas)
	// ─────────────────────────────────────────────────────────────────────────

	function buildPathsOverlay():Void
	{
		// These groups live outside FlxUITabMenu, drawn directly on camHUD
		// positioned over the SPRITE tab's "animate" hint area.
		// They are rebuilt on demand via refreshPathsOverlay().
		pathRowsBg     = new FlxTypedGroup<FlxSprite>();
		pathRowsInputs = new FlxTypedGroup<FlxUIInputText>();
		pathRowsBtns   = new FlxTypedGroup<FlxSprite>();

		pathRowsBg.cameras     = [camHUD];
		pathRowsInputs.cameras = [camHUD];
		pathRowsBtns.cameras   = [camHUD];

		add(pathRowsBg);
		add(pathRowsInputs);
		add(pathRowsBtns);
	}

	function refreshPathsOverlay():Void
	{
		// Clear
		for (s in pathRowsBg.members)     { s.visible = false; }
		for (i in pathRowsInputs.members) { i.visible = false; }
		for (s in pathRowsBtns.members)   { s.visible = false; }
		pathHitData = [];

		if (!pathTabVisible || selectedSprKey == null) return;

		var T = EditorTheme.current;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null || data.type != 'animate') return;

		var paths:Array<String> = data.paths ?? [];

		// Position: below the animate hint in the SPRITE tab
		// SPRITE tab content starts at TOP_H + tab_button_height (~28px)
		var tabContentY:Float = TOP_H + 28;
		var baseX:Float  = CENTER_X + 8;
		var baseY:Float  = tabContentY + 210; // approx position of animate hint section
		var rowW:Int     = CENTER_W - 50;
		var rowH:Int     = 22;

		var headerLbl = new FlxText(baseX, baseY - 20, rowW,
			'PATHS (animate multi-atlas)  —  1er path = atlas principal:', 9);
		headerLbl.color = C_ACCENT5;
		headerLbl.cameras = [camHUD]; headerLbl.scrollFactor.set();
		// We just add it to the state directly (static, doesn't need a group)
		// NOTE: in a full implementation you'd manage these lifecycle carefully.
		// For simplicity here they are rebuild each time.

		for (i in 0...paths.length + 1) // +1 for "Add Path" button slot
		{
			var rowY = baseY + i * (rowH + 4);

			if (i < paths.length)
			{
				// Ensure row bg exists
				var bg:FlxSprite;
				if (i < pathRowsBg.length)
					bg = pathRowsBg.members[i];
				else {
					bg = new FlxSprite();
					bg.scrollFactor.set();
					pathRowsBg.add(bg);
				}
				bg.makeGraphic(rowW, rowH, i == 0 ? 0x22CE93D8 : T.rowOdd);
				bg.x = baseX - 4; bg.y = rowY; bg.visible = true;

				// Input
				var inp:FlxUIInputText;
				if (i < pathRowsInputs.length)
					inp = pathRowsInputs.members[i];
				else {
					inp = new FlxUIInputText(0, 0, rowW - 26, '', 9);
					inp.cameras = [camHUD]; inp.scrollFactor.set();
					pathRowsInputs.add(inp);
				}
				inp.x = baseX; inp.y = rowY + 2; inp.text = paths[i]; inp.visible = true;

				// Delete button bg
				var dBg:FlxSprite;
				if (i < pathRowsBtns.length)
					dBg = pathRowsBtns.members[i];
				else {
					dBg = new FlxSprite();
					dBg.scrollFactor.set();
					pathRowsBtns.add(dBg);
				}
				dBg.makeGraphic(22, rowH, C_DANGER);
				dBg.x = baseX + rowW - 22; dBg.y = rowY; dBg.visible = true;
				// We'll detect del button clicks in handleMouse with pathHitData
				pathHitData.push({ y: rowY, idx: i });
			}
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  ANIM LIST OVERLAY
	// ─────────────────────────────────────────────────────────────────────────

	function refreshAnimListOverlay():Void
	{
		for (s in animListBg.members)   s.visible = false;
		for (t in animListText.members) t.visible = false;
		animHitData = [];

		if (selectedSprKey == null) return;
		var T = EditorTheme.current;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null || data.animations == null) return;

		var anims = data.animations;
		var baseX:Float = CENTER_X + 8;
		var baseY:Float = TOP_H + 28 + 190;
		var rowW:Int = CENTER_W - 16;

		for (i in 0...anims.length)
		{
			var anim = anims[i];
			var rowY = baseY + i * 24;
			var sel  = (i == selectedAnimIdx);

			var bg:FlxSprite;
			if (i < animListBg.length) bg = animListBg.members[i];
			else { bg = new FlxSprite(); bg.scrollFactor.set(); animListBg.add(bg); }
			bg.makeGraphic(rowW, 22, sel ? 0x330088FF : T.rowOdd);
			bg.x = baseX; bg.y = rowY; bg.visible = true;

			var t:FlxText;
			if (i < animListText.length) t = animListText.members[i];
			else {
				t = new FlxText(0, 0, rowW, '', 9);
				t.setFormat(Paths.font('vcr.ttf'), 9, T.textPrimary, LEFT);
				t.scrollFactor.set();
				animListText.add(t);
			}
			t.x = baseX + 4; t.y = rowY + 5;
			t.text = '${i}. ${anim.name}  —  prefix: "${anim.prefix}"  fps:${anim.fps ?? 24}  loop:${anim.loop ?? false}';
			t.visible = true;
			t.color = sel ? C_ACCENT : T.textPrimary;

			animHitData.push({ y: rowY, idx: i });
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  MOUSE HANDLING
	// ─────────────────────────────────────────────────────────────────────────

	function handleMouse():Void
	{
		if (!FlxG.mouse.justPressed) return;
		var mx = FlxG.mouse.screenX;
		var my = FlxG.mouse.screenY;

		// ── Preview panel title bar — drag ────────────────────────────────────
		if (mx >= _prevX && mx < _prevX + PREV_W
		    && my >= _prevY && my < _prevY + PREV_TITLE_H)
		{
			_prevDragging  = true;
			_prevDragOffX  = mx - _prevX;
			_prevDragOffY  = my - _prevY;
			return;
		}

		// ── Sprite list (left panel) ──────────────────────────────────────────
		if (mx >= 0 && mx < LEFT_W)
		{
			for (hit in sprHitData)
			{
				if (my >= hit.y && my < hit.y + ROW_H)
				{
					selectSprite(hit.key);
					return;
				}
			}
		}

		// ── Step list (right panel) ────────────────────────────────────────────
		if (mx >= FlxG.width - RIGHT_W)
		{
			for (hit in stepHitData)
			{
				if (my >= hit.y && my < hit.y + ROW_H)
				{
					selectStep(hit.idx);
					return;
				}
			}
		}

		// ── Path delete buttons ────────────────────────────────────────────────
		if (pathTabVisible && selectedSprKey != null)
		{
			var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
			if (data != null && data.type == 'animate')
			{
				for (hit in pathHitData)
				{
					// Delete btn is last 22px of row
					var btnX:Float = CENTER_X + CENTER_W - 30;
					if (my >= hit.y && my < hit.y + 22 && mx >= btnX)
					{
						deletePathAt(hit.idx);
						return;
					}
				}
			}
		}

		// ── Anim list rows ────────────────────────────────────────────────────
		for (hit in animHitData)
		{
			if (my >= hit.y && my < hit.y + 24)
			{
				selectedAnimIdx = hit.idx;
				populateAnimFields();
				refreshAnimListOverlay();
				return;
			}
		}

		// ── Scroll: sprite list ───────────────────────────────────────────────
		if (mx >= 0 && mx < LEFT_W && FlxG.mouse.wheel != 0)
		{
			sprScrollStart = Std.int(Math.max(0, sprScrollStart - FlxG.mouse.wheel));
			refreshSpriteList();
		}

		// ── Scroll: step list ─────────────────────────────────────────────────
		if (mx >= FlxG.width - RIGHT_W && FlxG.mouse.wheel != 0)
		{
			stepScrollStart = Std.int(Math.max(0, stepScrollStart - FlxG.mouse.wheel));
			refreshStepList();
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  SELECTION
	// ─────────────────────────────────────────────────────────────────────────

	function selectSprite(key:String):Void
	{
		selectedSprKey = key;
		selectedAnimIdx = -1;
		populateSpriteFields();
		refreshSpriteList();
		refreshAnimListOverlay();
		setStatus('Sprite seleccionado: $key');
	}

	function selectStep(idx:Int):Void
	{
		selectedStepIdx = idx;
		populateStepFields();
		refreshStepList();
		setStatus('Step ${idx + 1} seleccionado: ${doc.steps[idx].action}');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  POPULATE WIDGETS  (data → UI)
	// ─────────────────────────────────────────────────────────────────────────

	function populateSpriteFields():Void
	{
		if (selectedSprKey == null) return;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null) return;
		_applyLock = true;

		spr_idInput.text  = selectedSprKey;
		var typeIdx = ['rect','image','atlas','packer','animate'].indexOf(data.type ?? 'rect');
		if (typeIdx < 0) typeIdx = 0;
		spr_typeDropdown.selectedLabel = (['rect','image','atlas','packer','animate'])[typeIdx];

		spr_colorInput.text = data.color ?? '0xFF000000';
		spr_widthStepper.value  = data.width  ?? 2;
		spr_heightStepper.value = data.height ?? 2;
		spr_imageInput.text = data.image ?? '';
		spr_xmlInput.text   = data.xml   ?? '';
		spr_xStepper.value  = data.x ?? 0;
		spr_yStepper.value  = data.y ?? 0;
		spr_alphaStepper.value  = data.alpha  ?? 1;
		spr_angleStepper.value  = data.angle  ?? 0;
		spr_scaleStepper.value  = data.scale  ?? 1;
		spr_scaleXStepper.value = data.scaleX ?? 1;
		spr_scaleYStepper.value = data.scaleY ?? 1;
		spr_scrollStepper.value = data.scrollFactor ?? 0;
		spr_flipXCheck.checked  = data.flipX  ?? false;
		spr_flipYCheck.checked  = data.flipY  ?? false;
		spr_centerCheck.checked = data.center ?? false;
		spr_aaCheck.checked     = data.antialiasing ?? true;
		var camIdx = (data.camera ?? 'game') == 'hud' ? 1 : 0;
		spr_camDropdown.selectedLabel = camIdx == 1 ? 'hud' : 'game';

		_updateSpriteTypeVisibility(data.type ?? 'rect');
		_applyLock = false;
		refreshPathsOverlay();
		refreshAnimListOverlay();
	}

	function populateStepFields():Void
	{
		if (selectedStepIdx < 0 || selectedStepIdx >= doc.steps.length) return;
		var step = doc.steps[selectedStepIdx];
		_applyLock = true;

		// Rebuild sprite dropdown
		var sprLabels = [{ id: '0', label: '(ninguno)' }];
		for (i in 0...spriteKeys.length)
			sprLabels.push({ id: Std.string(i + 1), label: spriteKeys[i] });
		step_sprDropdown.setData(cast sprLabels);
		var sprSelIdx = step.sprite != null ? spriteKeys.indexOf(step.sprite) + 1 : 0;
		step_sprDropdown.selectedLabel = sprSelIdx > 0 ? step.sprite : '(ninguno)';

		step_alphaStepper.value    = step.alpha    ?? 1;
		step_xStepper.value        = step.x        ?? 0;
		step_yStepper.value        = step.y        ?? 0;
		step_timeStepper.value     = step.time     ?? 1;
		step_targetStepper.value   = step.target   ?? 0;
		step_stepStepper.value     = step.step     ?? 0.15;
		step_intervalStepper.value = step.interval ?? 0.3;
		step_durationStepper.value = step.duration ?? 0.5;
		step_colorInput.text       = step.color    ?? 'WHITE';
		step_keyInput.text         = step.key      ?? '';
		step_animInput.text        = step.anim     ?? '';
		step_idInput.text          = step.id       ?? '';
		step_funcInput.text        = step.func     ?? '';
		step_propsInput.text       = step.props != null ? Json.stringify(step.props) : '{}';
		step_intensityStepper.value = step.intensity ?? 0.03;
		step_volumeStepper.value   = step.volume   ?? 1;
		step_asyncCheck.checked    = step.async    ?? false;
		step_forceCheck.checked    = step.force    ?? false;
		step_visibleCheck.checked  = step.visible  ?? true;
		step_fadeInCheck.checked   = step.fadeIn   ?? false;

		if (step.ease != null)
			step_easeDropdown.selectedLabel = step.ease;
		if (step.axis != null)
			step_axisDropdown.selectedLabel = step.axis;

		_updateStepFieldVisibility(step.action);
		_applyLock = false;
	}

	function populateAnimFields():Void
	{
		if (selectedSprKey == null || selectedAnimIdx < 0) return;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null || data.animations == null || selectedAnimIdx >= data.animations.length) return;
		var anim = data.animations[selectedAnimIdx];
		_applyLock = true;
		anim_nameInput.text    = anim.name   ?? '';
		anim_prefixInput.text  = anim.prefix ?? '';
		anim_fpsStepper.value  = anim.fps    ?? 24;
		anim_loopCheck.checked = anim.loop   ?? false;
		anim_indicesInput.text = anim.indices != null ? anim.indices.join(',') : '';
		_applyLock = false;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  APPLY CHANGES  (UI → data)
	// ─────────────────────────────────────────────────────────────────────────

	function applySpriteId():Void
	{
		if (selectedSprKey == null) return;
		var newId = spr_idInput.text.trim();
		if (newId == '' || newId == selectedSprKey) return;
		if (Reflect.hasField(doc.sprites, newId)) { setStatus('ID ya en uso: $newId'); return; }

		var data = Reflect.field(doc.sprites, selectedSprKey);
		Reflect.deleteField(doc.sprites, selectedSprKey);
		Reflect.setField(doc.sprites, newId, data);

		// Update references in steps
		for (step in doc.steps)
			if (step.sprite == selectedSprKey) step.sprite = newId;

		var oldKey = selectedSprKey;
		var idx = spriteKeys.indexOf(oldKey);
		if (idx >= 0) spriteKeys[idx] = newId;
		selectedSprKey = newId;

		_markUnsaved();
		refreshSpriteList();
		setStatus('Sprite renombrado: $oldKey → $newId');
	}

	function applySprite():Void
	{
		if (selectedSprKey == null) return;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null) return;

		var types = ['rect','image','atlas','packer','animate'];
		data.type  = types[Std.parseInt(spr_typeDropdown.selectedId)] ?? 'rect';
		data.color = spr_colorInput.text.trim();
		data.width  = spr_widthStepper.value;
		data.height = spr_heightStepper.value;
		data.image  = spr_imageInput.text.trim() == '' ? null : spr_imageInput.text.trim();
		data.xml    = spr_xmlInput.text.trim()   == '' ? null : spr_xmlInput.text.trim();
		data.x      = spr_xStepper.value;
		data.y      = spr_yStepper.value;
		data.alpha  = spr_alphaStepper.value;
		data.angle  = spr_angleStepper.value;
		data.scale  = spr_scaleStepper.value;
		data.scaleX = spr_scaleXStepper.value;
		data.scaleY = spr_scaleYStepper.value;
		data.scrollFactor = spr_scrollStepper.value;
		data.flipX  = spr_flipXCheck.checked;
		data.flipY  = spr_flipYCheck.checked;
		data.center = spr_centerCheck.checked;
		data.antialiasing = spr_aaCheck.checked;
		data.camera = spr_camDropdown.selectedLabel;

		// Save path list for animate type
		if (data.type == 'animate')
		{
			var newPaths:Array<String> = [];
			for (inp in pathRowsInputs.members)
				if (inp.visible) { var v = inp.text.trim(); if (v != '') newPaths.push(v); }
			data.paths = newPaths;
		}

		Reflect.setField(doc.sprites, selectedSprKey, data);
		_markUnsaved();
		refreshSpriteList();
		if (_previewSprGrp != null) rebuildPreviewSprites();
		setStatus('Sprite "$selectedSprKey" actualizado.');
	}

	function applyStep():Void
	{
		if (selectedStepIdx < 0 || selectedStepIdx >= doc.steps.length) return;
		var step = doc.steps[selectedStepIdx];

		var sprList = [''].concat(spriteKeys);
		var sprIdx  = Std.parseInt(step_sprDropdown.selectedId);
		step.sprite  = (sprIdx > 0 && sprIdx <= spriteKeys.length) ? spriteKeys[sprIdx - 1] : null;

		step.alpha    = step_alphaStepper.value;
		step.x        = step_xStepper.value;
		step.y        = step_yStepper.value;
		step.time     = step_timeStepper.value;
		step.target   = step_targetStepper.value;
		step.step     = step_stepStepper.value;
		step.interval = step_intervalStepper.value;
		step.duration = step_durationStepper.value;
		step.color    = step_colorInput.text.trim() == '' ? null : step_colorInput.text.trim();
		step.key      = step_keyInput.text.trim()   == '' ? null : step_keyInput.text.trim();
		step.anim     = step_animInput.text.trim()  == '' ? null : step_animInput.text.trim();
		step.id       = step_idInput.text.trim()    == '' ? null : step_idInput.text.trim();
		step.func     = step_funcInput.text.trim()  == '' ? null : step_funcInput.text.trim();
		step.intensity = step_intensityStepper.value;
		step.volume   = step_volumeStepper.value;
		step.async    = step_asyncCheck.checked;
		step.force    = step_forceCheck.checked;
		step.visible  = step_visibleCheck.checked;
		step.fadeIn   = step_fadeInCheck.checked;
		step.ease     = step_easeDropdown.selectedLabel;
		step.axis     = step_axisDropdown.selectedLabel;
		try { step.props = Json.parse(step_propsInput.text); } catch (_) {}

		_markUnsaved();
		refreshStepList();
		setStatus('Step ${selectedStepIdx + 1} actualizado.');
	}

	function applyAnim():Void
	{
		if (selectedSprKey == null) return;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null) return;
		if (data.animations == null) data.animations = [];

		var animData:CutsceneSpriteAnim = {
			name:   anim_nameInput.text.trim(),
			prefix: anim_prefixInput.text.trim(),
			fps:    Std.int(anim_fpsStepper.value),
			loop:   anim_loopCheck.checked,
			indices: _parseIndices(anim_indicesInput.text)
		};

		if (selectedAnimIdx >= 0 && selectedAnimIdx < data.animations.length)
			data.animations[selectedAnimIdx] = animData;
		else
		{
			data.animations.push(animData);
			selectedAnimIdx = data.animations.length - 1;
		}

		_markUnsaved();
		refreshAnimListOverlay();
		setStatus('Animación "${animData.name}" guardada.');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  ADD / DELETE OPERATIONS
	// ─────────────────────────────────────────────────────────────────────────

	function addSpriteDialog():Void
	{
		// Find a unique ID
		var base = 'sprite';
		var idx  = 0;
		while (Reflect.hasField(doc.sprites, '$base$idx')) idx++;
		var id   = '$base$idx';

		var newData:CutsceneSpriteData = {
			type:   'rect',
			color:  '0xFF000000',
			width:  2,
			height: 2
		};
		Reflect.setField(doc.sprites, id, newData);
		spriteKeys.push(id);
		selectedSprKey = id;

		_markUnsaved();
		refreshSpriteList();
		populateSpriteFields();
		setStatus('Sprite "$id" creado. Edita sus propiedades en la pestaña SPRITE.');
	}

	function deleteSprite(key:String):Void
	{
		Reflect.deleteField(doc.sprites, key);
		spriteKeys.remove(key);
		if (selectedSprKey == key) selectedSprKey = null;
		_markUnsaved();
		refreshSpriteList();
		if (_previewSprGrp != null) rebuildPreviewSprites();
		setStatus('Sprite "$key" eliminado.');
	}

	function addStepFromDropdown():Void
	{
		var actions = [
			'add','remove','setAlpha','setColor','setVisible','setPosition','screenCenter',
			'playAnim','wait','fadeTimer','tween','playSound','waitSound',
			'cameraFade','cameraFlash','cameraShake','script','end'
		];
		var idx = Std.parseInt(stepActionDropdown.selectedId);
		var action = idx >= 0 && idx < actions.length ? actions[idx] : 'wait';

		var step:CutsceneStep = { action: action };
		doc.steps.push(step);
		selectedStepIdx = doc.steps.length - 1;
		_markUnsaved();
		refreshStepList();
		populateStepFields();
		setStatus('Step "${action}" añadido.');
	}

	function deleteStep(idx:Int):Void
	{
		if (idx < 0 || idx >= doc.steps.length) return;
		doc.steps.splice(idx, 1);
		if (selectedStepIdx >= doc.steps.length) selectedStepIdx = doc.steps.length - 1;
		_markUnsaved();
		refreshStepList();
		setStatus('Step ${idx + 1} eliminado.');
	}

	function addAnimation():Void
	{
		if (selectedSprKey == null) return;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null) return;
		if (data.animations == null) data.animations = [];
		var newAnim:CutsceneSpriteAnim = { name: 'idle', prefix: 'idle', fps: 24, loop: false };
		data.animations.push(newAnim);
		selectedAnimIdx = data.animations.length - 1;
		populateAnimFields();
		_markUnsaved();
		refreshAnimListOverlay();
	}

	function deleteAnim():Void
	{
		if (selectedSprKey == null || selectedAnimIdx < 0) return;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null || data.animations == null) return;
		data.animations.splice(selectedAnimIdx, 1);
		selectedAnimIdx = -1;
		_markUnsaved();
		refreshAnimListOverlay();
	}

	function addPathToSprite():Void
	{
		if (selectedSprKey == null) return;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null) return;
		if (data.paths == null) data.paths = [];
		data.paths.push('');
		_markUnsaved();
		refreshPathsOverlay();
		setStatus('Path vacío añadido — edítalo y pulsa APPLY CHANGES.');
	}

	function deletePathAt(idx:Int):Void
	{
		if (selectedSprKey == null) return;
		var data:CutsceneSpriteData = Reflect.field(doc.sprites, selectedSprKey);
		if (data == null || data.paths == null) return;
		data.paths.splice(idx, 1);
		_markUnsaved();
		refreshPathsOverlay();
	}

	function toggleSkippable():Void
	{
		doc.skippable = !(doc.skippable ?? true);
		_markUnsaved();
		setStatus('Skippable: ${doc.skippable}');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  VISIBILITY HELPERS
	// ─────────────────────────────────────────────────────────────────────────

	function _updateSpriteTypeVisibility(type:String):Void
	{
		var isRect    = type == 'rect';
		var isImage   = type == 'image' || type == 'atlas' || type == 'packer';
		var hasXML    = type == 'atlas' || type == 'packer';
		var isAnimate = type == 'animate';

		for (m in spr_rectGroup.members)   if (m != null) cast(m, flixel.FlxSprite).visible = isRect;
		for (m in spr_imageGroup.members)  if (m != null) cast(m, flixel.FlxSprite).visible = isImage || isAnimate;
		for (m in spr_xmlGroup.members)    if (m != null) cast(m, flixel.FlxSprite).visible = hasXML;
		spr_animateHintLabel.visible = isAnimate;
		pathTabVisible = isAnimate;
		refreshPathsOverlay();
	}

	function _updateStepFieldVisibility(action:String):Void
	{
		// Hide all optional groups
		function setGrp(grp:FlxTypedGroup<flixel.FlxBasic>, v:Bool):Void
		{
			for (m in grp.members) if (m != null)
			{
				try { cast(m, flixel.FlxSprite).visible = v; } catch (_) {}
			}
		}
		// Show sprite selector for actions that affect a sprite
		var hasSpr = ['add','remove','setAlpha','setColor','setVisible','setPosition',
		              'screenCenter','playAnim','fadeTimer','tween'].contains(action);
		setGrp(step_sprGroup, hasSpr);
		setGrp(step_alphaGroup, ['add','setAlpha'].contains(action));
		setGrp(step_xyGroup, ['setPosition'].contains(action));
		setGrp(step_axisGroup, ['screenCenter'].contains(action));
		setGrp(step_timeGroup, ['wait'].contains(action));
		setGrp(step_fadeTimerGroup, ['fadeTimer'].contains(action));
		setGrp(step_tweenGroup, ['tween'].contains(action));
		setGrp(step_colorGroup, ['setColor','cameraFade','cameraFlash'].contains(action));
		setGrp(step_camGroup, ['cameraFade','cameraFlash','cameraShake'].contains(action));
		setGrp(step_shakeGroup, ['cameraShake'].contains(action));
		setGrp(step_soundGroup, ['playSound','waitSound'].contains(action));
		setGrp(step_animGroup, ['playAnim'].contains(action));
		setGrp(step_funcGroup, ['script'].contains(action));
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  JSON TAB
	// ─────────────────────────────────────────────────────────────────────────

	function refreshJSONTab():Void
	{
		if (jsonDisplayText == null) return;
		try
		{
			jsonDisplayText.text = Json.stringify(_buildCleanDoc(), null, '\t');
		}
		catch (e)
		{
			jsonDisplayText.text = 'Error al serializar: $e';
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  SAVE / LOAD
	// ─────────────────────────────────────────────────────────────────────────

	function newDocument():Void
	{
		doc = { sprites: {}, steps: [], skippable: true };
		spriteKeys = [];
		selectedSprKey  = null;
		selectedStepIdx = -1;
		hasUnsavedChanges = false;
		unsavedDot.visible = false;
		currentFilePath = '';
		refreshSpriteList();
		refreshStepList();
		setStatus('Nuevo documento creado.');
	}

	function saveCutscene():Void
	{
		#if sys
		// Si ya tenemos una ruta (cargado con LOAD SONG o previo SAVE), usar esa.
		// Esto respeta que el archivo esté en assets/songs/, mods/songs/, etc.
		var path = (currentFilePath != '')
			? currentFilePath
			: 'assets/data/cutscenes/${_cutsceneKey()}.json';
		try
		{
			_ensureDir(path);
			File.saveContent(path, Json.stringify(_buildCleanDoc(), null, '\t'));
			currentFilePath = path;
			hasUnsavedChanges = false;
			unsavedDot.visible = false;
			setStatus('Guardado: $path');
		}
		catch (e) { setStatus('ERROR guardando: $e'); }
		#else
		setStatus('Guardado solo disponible en plataformas sys (desktop).');
		#end
	}

	function saveCutsceneMod():Void
	{
		#if sys
		if (!mods.ModManager.isActive()) { saveCutscene(); return; }
		// Si la ruta actual ya está dentro del mod, guardar ahí directamente.
		var modRoot = mods.ModManager.modRoot();
		var path = (currentFilePath != '' && currentFilePath.startsWith(modRoot))
			? currentFilePath
			: '$modRoot/songs/${(PlayState.SONG?.song ?? 'cutscene').toLowerCase()}/${_cutsceneKey()}.json';
		try
		{
			_ensureDir(path);
			File.saveContent(path, Json.stringify(_buildCleanDoc(), null, '\t'));
			currentFilePath = path;
			hasUnsavedChanges = false;
			unsavedDot.visible = false;
			setStatus('Guardado en mod: $path');
		}
		catch (e) { setStatus('ERROR: $e'); }
		#end
	}

	function loadCutscene():Void
	{
		#if sys
		// En desktop usamos un input de texto en el status bar para que el usuario
		// escriba la ruta. Más simple y robusto que FileReference en targets nativos.
		// Si currentFilePath ya apunta a algo, se recarga desde ahí directamente.
		if (currentFilePath != '' && FileSystem.exists(currentFilePath))
		{
			_loadCutsceneFromPath(currentFilePath);
			return;
		}
		setStatus('Escribe la ruta del JSON y pulsa ENTER — o usa LOAD SONG para cargar la cutscene del song actual.');
		#else
		// Fallback web/flash: FileReference
		_fileRef = new FileReference();
		_fileRef.addEventListener(Event.SELECT, function(_)
		{
			_fileRef.addEventListener(Event.COMPLETE, function(_)
			{
				try
				{
					var raw:String = _fileRef.data.toString();
					_applyRawDoc(raw, _fileRef.name);
				}
				catch (e) { setStatus('Error parseando JSON: $e'); }
			});
			_fileRef.load();
		});
		_fileRef.addEventListener(Event.CANCEL, function(_) {});
		_fileRef.addEventListener(IOErrorEvent.IO_ERROR, function(_) { setStatus('Error leyendo archivo.'); });
		_fileRef.browse([new openfl.net.FileFilter('Cutscene JSON', '*.json')]);
		#end
	}

	/**
	 * Busca la cutscene del song actual (del PlayState o el último usado)
	 * probando las rutas estándar, y la carga automáticamente.
	 * Si no existe, prepara un documento vacío con la clave correcta.
	 */
	function loadFromSong():Void
	{
		#if sys
		var song = (PlayState.SONG?.song ?? '').toLowerCase();
		if (song == '') { setStatus('No hay canción activa. Entra desde el PlayState.'); return; }

		var modRoot = mods.ModManager.modRoot();

		// Mismas rutas que SpriteCutscene._resolvePath(), en el mismo orden.
		var keysToTry = ['$song-intro', '$song-outro', song];
		var found = false;
		for (key in keysToTry)
		{
			var candidates:Array<String> = [];
			if (modRoot != null)
			{
				candidates.push('$modRoot/data/cutscenes/$song/$key.json');
				candidates.push('$modRoot/data/cutscenes/$key.json');
				candidates.push('$modRoot/songs/$song/$key.json');   // ← dentro de songs/
			}
			candidates.push('assets/data/cutscenes/$song/$key.json');
			candidates.push('assets/songs/$song/$key.json');         // ← dentro de songs/
			candidates.push('assets/data/cutscenes/$key.json');

			for (p in candidates)
			{
				if (FileSystem.exists(p))
				{
					_loadCutsceneFromPath(p);
					found = true;
					break;
				}
			}
			if (found) break;
		}

		if (!found)
		{
			newDocument();
			// Ruta de guardado por defecto: songs/{song}/{song}-intro.json
			currentFilePath = (modRoot != null)
				? '$modRoot/songs/$song/$song-intro.json'
				: 'assets/songs/$song/$song-intro.json';
			setStatus('No se encontró cutscene para "$song". Doc vacío — SAVE guardará en: $currentFilePath');
		}
		#else
		setStatus('loadFromSong solo disponible en desktop.');
		#end
	}

	function _loadCutsceneFromPath(path:String):Void
	{
		#if sys
		try
		{
			var raw = File.getContent(path);
			_applyRawDoc(raw, path);
		}
		catch (e) { setStatus('Error leyendo "$path": $e'); }
		#end
	}

	function _applyRawDoc(raw:String, sourcePath:String):Void
	{
		try
		{
			doc = haxe.Json.parse(raw);
			_rebuildSpriteKeys();
			selectedSprKey  = null;
			selectedStepIdx = -1;
			hasUnsavedChanges = false;
			unsavedDot.visible = false;
			currentFilePath = sourcePath;
			refreshSpriteList();
			refreshStepList();
			if (_previewSprGrp != null) rebuildPreviewSprites();
			setStatus('Cargado: $sourcePath');
		}
		catch (e) { setStatus('Error parseando JSON: $e'); }
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  HELPERS
	// ─────────────────────────────────────────────────────────────────────────

	function _rebuildSpriteKeys():Void
	{
		spriteKeys = [];
		if (doc.sprites == null) doc.sprites = {};
		for (k in Reflect.fields(doc.sprites)) spriteKeys.push(k);
	}

	function _markUnsaved():Void
	{
		hasUnsavedChanges = true;
		if (unsavedDot != null) unsavedDot.visible = true;
	}

	function _buildCleanDoc():CutsceneDocument
	{
		// Return a copy with null/default fields stripped
		var out:Dynamic = {};
		if (doc.skippable != true) out.skippable = doc.skippable;

		// Sprites
		var sprsOut:Dynamic = {};
		for (key in spriteKeys)
		{
			var d:CutsceneSpriteData = Reflect.field(doc.sprites, key);
			if (d == null) continue;
			var ds:Dynamic = { type: d.type ?? 'rect' };
			_copyIfNotNull(d, ds, 'color');
			_copyIfNotDefault(d, ds, 'width',  2.0);
			_copyIfNotDefault(d, ds, 'height', 2.0);
			_copyIfNotNull(d, ds, 'image');
			_copyIfNotNull(d, ds, 'xml');
			if (d.paths != null && d.paths.length > 0) ds.paths = d.paths;
			if (d.animations != null && d.animations.length > 0) ds.animations = d.animations;
			_copyIfNotDefault(d, ds, 'x', 0.0);
			_copyIfNotDefault(d, ds, 'y', 0.0);
			_copyIfNotDefault(d, ds, 'alpha', 1.0);
			_copyIfNotDefault(d, ds, 'angle', 0.0);
			_copyIfNotDefault(d, ds, 'scale', 1.0);
			_copyIfNotNull(d, ds, 'scaleX');
			_copyIfNotNull(d, ds, 'scaleY');
			if (d.flipX  == true)  ds.flipX  = true;
			if (d.flipY  == true)  ds.flipY  = true;
			if (d.center == true)  ds.center = true;
			if (d.antialiasing == false) ds.antialiasing = false;
			_copyIfNotNull(d, ds, 'camera');
			_copyIfNotDefault(d, ds, 'scrollFactor', 0.0);
			Reflect.setField(sprsOut, key, ds);
		}
		out.sprites = sprsOut;
		out.steps   = doc.steps;
		return cast out;
	}

	static inline function _copyIfNotNull(src:Dynamic, dst:Dynamic, field:String):Void
	{
		var v = Reflect.field(src, field);
		if (v != null && (Type.typeof(v) != TNull)) Reflect.setField(dst, field, v);
	}

	static inline function _copyIfNotDefault(src:Dynamic, dst:Dynamic, field:String, def:Dynamic):Void
	{
		var v = Reflect.field(src, field);
		if (v != null && v != def) Reflect.setField(dst, field, v);
	}

	function _cutsceneKey():String
	{
		if (currentFilePath != '')
		{
			var parts = currentFilePath.replace('\\', '/').split('/');
			var last = parts[parts.length - 1];
			if (last.endsWith('.json')) return last.substr(0, last.length - 5);
		}
		var song = PlayState.SONG?.song ?? 'cutscene';
		return '${song.toLowerCase()}-intro';
	}

	static function _parseIndices(s:String):Null<Array<Int>>
	{
		s = s.trim();
		if (s == '') return null;
		var arr:Array<Int> = [];
		for (part in s.split(','))
		{
			part = part.trim();
			if (part.indexOf('..') >= 0)
			{
				var rng = part.split('..');
				var from = Std.parseInt(rng[0]);
				var to   = Std.parseInt(rng[1]);
				if (from != null && to != null)
					for (n in from...(to + 1)) arr.push(n);
			}
			else
			{
				var n = Std.parseInt(part);
				if (n != null) arr.push(n);
			}
		}
		return arr.length > 0 ? arr : null;
	}

	/**
	 * Devuelve true si algún FlxUIInputText del editor tiene el foco.
	 * Se usa para sincronizar SoundTray.blockInput y evitar que teclas como
	 * 0 / + / - se interpreten como controles de volumen mientras el usuario escribe.
	 */
	function _isTyping():Bool
	{
		// Inputs del tab SPRITE
		inline function chk(i:FlxUIInputText) return i != null && i.hasFocus;
		if (chk(spr_idInput))      return true;
		if (chk(spr_colorInput))   return true;
		if (chk(spr_imageInput))   return true;
		if (chk(spr_xmlInput))     return true;
		// Inputs del tab ANIM
		if (chk(anim_nameInput))   return true;
		if (chk(anim_prefixInput)) return true;
		if (chk(anim_indicesInput))return true;
		// Inputs del tab STEP
		if (chk(step_colorInput))  return true;
		if (chk(step_keyInput))    return true;
		if (chk(step_animInput))   return true;
		if (chk(step_idInput))     return true;
		if (chk(step_funcInput))   return true;
		if (chk(step_propsInput))  return true;
		// Inputs dinámicos de paths (animate)
		if (pathRowsInputs != null)
			for (inp in pathRowsInputs.members)
				if (inp != null && inp.hasFocus) return true;
		return false;
	}

	override public function destroy():Void
	{
		// Garantía: limpiar blockInput al salir del editor,
		// independientemente del camino de salida.
		funkin.audio.SoundTray.blockInput = false;
		super.destroy();
	}

	static function _ensureDir(path:String):Void
	{
		#if sys
		var dir = path.replace('\\', '/');
		var idx = dir.lastIndexOf('/');
		if (idx > 0) {
			var d = dir.substr(0, idx);
			if (!FileSystem.exists(d)) FileSystem.createDirectory(d);
		}
		#end
	}

	static function _actionColor(action:String):Int
	{
		return switch (action) {
			case 'add':                  0xFF69FF47;
			case 'remove':               0xFFF44336;
			case 'wait':                 0xFFFFB300;
			case 'fadeTimer':            0xFFFFF59D;
			case 'tween':                0xFF80DEEA;
			case 'playSound','waitSound':0xFFF48FB1;
			case 'cameraFade','cameraFlash','cameraShake': 0xFFCE93D8;
			case 'playAnim':             0xFFFF4081;
			case 'end':                  0xFF00E5FF;
			case 'setAlpha','setColor','setVisible','setPosition','screenCenter': 0xFFCCCCCC;
			default:                     0xFF888888;
		};
	}

	static function _stepDesc(step:CutsceneStep):String
	{
		var p:Array<String> = [];
		if (step.sprite   != null) p.push('spr:${step.sprite}');
		if (step.time     != null) p.push('${step.time}s');
		if (step.duration != null) p.push('${step.duration}s');
		if (step.key      != null) p.push('key:${step.key}');
		if (step.anim     != null) p.push('anim:${step.anim}');
		if (step.target   != null) p.push('→${step.target}');
		if (step.color    != null) p.push(step.color);
		if (step.id       != null) p.push('id:${step.id}');
		if (step.func     != null) p.push('fn:${step.func}');
		return p.join(' · ');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  PREVIEW PANEL
	// ─────────────────────────────────────────────────────────────────────────

	function buildPreviewPanel():Void
	{
		// Default position: bottom-centre of the centre column
		_prevX = CENTER_X + (CENTER_W - PREV_W) / 2.0;
		_prevY = FlxG.height - STATUS_H - PREV_PANEL_H - 8.0;

		// camPreview ya fue creada y añadida a FlxG.cameras en create(),
		// entre camUI y camHUD para que quede bajo el HUD.
		// Aquí solo actualizamos sus propiedades si hace falta.

		// ── Background panel sprite (camHUD) ──────────────────────────────────
		_prevPanelBg = new FlxSprite();
		_prevPanelBg.makeGraphic(PREV_W, PREV_PANEL_H, 0xEE0A1020);
		_prevPanelBg.scrollFactor.set();
		_prevPanelBg.cameras = [camHUD];
		add(_prevPanelBg);

		// ── Title bar ─────────────────────────────────────────────────────────
		_prevTitleBg = new FlxSprite();
		_prevTitleBg.makeGraphic(PREV_W, PREV_TITLE_H, 0xFF0D3050);
		_prevTitleBg.scrollFactor.set();
		_prevTitleBg.cameras = [camHUD];
		add(_prevTitleBg);

		_prevTitleLbl = new FlxText(0, 0, PREV_W - 4, '▶ PREVIEW  •  drag', 10);
		_prevTitleLbl.color = C_ACCENT;
		_prevTitleLbl.scrollFactor.set();
		_prevTitleLbl.cameras = [camHUD];
		add(_prevTitleLbl);

		// 1-px accent line below title bar
		_prevSep1 = new FlxSprite();
		_prevSep1.makeGraphic(PREV_W, 1, C_ACCENT);
		_prevSep1.scrollFactor.set();
		_prevSep1.cameras = [camHUD];
		add(_prevSep1);

		// ── Status label ──────────────────────────────────────────────────────
		_prevStatusLbl = new FlxText(0, 0, PREV_W - 4, 'Ready.', 9);
		_prevStatusLbl.color = 0xFFAAAAAA;
		_prevStatusLbl.scrollFactor.set();
		_prevStatusLbl.cameras = [camHUD];
		add(_prevStatusLbl);

		// ── Buttons row ───────────────────────────────────────────────────────
		_prevBtnPlay  = _mkPrevBtn(4,              0, '▶ PLAY',  previewPlay);
		_prevBtnStop  = _mkPrevBtn(100,             0, '■ STOP',  previewStop);
		_prevBtnReset = _mkPrevBtn(196,             0, '⟳ RESET', previewReset);
		_prevBtnClose = _mkPrevBtn(PREV_W - 76,    0, '✕ HIDE',  _prevToggleVisible);

		// ── Preview sprite group (draws on camPreview) ─────────────────────────
		_previewSprGrp = new FlxTypedGroup<FlxSprite>();
		_previewSprGrp.cameras = [camPreview];
		add(_previewSprGrp);

		_applyPreviewPanelPos();
		rebuildPreviewSprites();
	}

	/** Helper: create a small FlxButton assigned to camHUD. */
	function _mkPrevBtn(offX:Float, offY:Float, label:String, cb:Void->Void):FlxButton
	{
		var btn = new FlxButton(0, 0, label, cb);
		btn.scale.set(0.85, 0.85);
		btn.updateHitbox();
		btn.scrollFactor.set();
		btn.cameras = [camHUD];
		add(btn);
		return btn;
	}

	/**
	 * Reposition every piece of the preview panel to (_prevX, _prevY).
	 * Also repositions the camPreview flashSprite viewport on screen.
	 */
	function _applyPreviewPanelPos():Void
	{
		if (_prevPanelBg == null) return;

		var px:Float = _prevX;
		var py:Float = _prevY;

		_prevPanelBg.x  = px;  _prevPanelBg.y  = py;
		_prevTitleBg.x  = px;  _prevTitleBg.y  = py;
		_prevTitleLbl.x = px + 4; _prevTitleLbl.y = py + 4;
		_prevSep1.x     = px;  _prevSep1.y     = py + PREV_TITLE_H;

		_prevStatusLbl.x = px + 4;
		_prevStatusLbl.y = py + PREV_TITLE_H + PREV_CONTENT_H + 4;

		// Button row y = below content area
		var btnY:Float = py + PREV_TITLE_H + PREV_CONTENT_H + 1;
		_prevBtnPlay.x  = px + 4;              _prevBtnPlay.y  = btnY;
		_prevBtnStop.x  = px + 100;            _prevBtnStop.y  = btnY;
		_prevBtnReset.x = px + 196;            _prevBtnReset.y = btnY;
		_prevBtnClose.x = px + PREV_W - 76;   _prevBtnClose.y = btnY;

		// Move camPreview viewport on the OpenFL stage using @:access
		// The flashSprite x/y controls the on-screen position of the camera.
		if (camPreview != null)
		{
			camPreview.x = Std.int(px);
			camPreview.y = Std.int(py + PREV_TITLE_H + 1);
		}
	}

	/** Show/hide the entire preview panel. */
	function _prevToggleVisible():Void
	{
		var v = !_prevPanelBg.visible;
		_prevPanelBg.visible  = v;
		_prevTitleBg.visible  = v;
		_prevTitleLbl.visible = v;
		_prevSep1.visible     = v;
		_prevStatusLbl.visible = v;
		_prevBtnPlay.visible  = v;
		_prevBtnStop.visible  = v;
		_prevBtnReset.visible = v;
		_prevBtnClose.visible = v;
		if (camPreview != null) camPreview.visible = v;
	}

	// ── Sprite building ───────────────────────────────────────────────────────

	/**
	 * Destroy any existing preview sprites and re-create them from doc.sprites.
	 * The sprites are added to _previewSprGrp (renders on camPreview) but start
	 * invisible — the playback steps call 'add' to show them, matching the real
	 * cutscene behaviour.  After rebuild the preview is reset automatically.
	 */
	function rebuildPreviewSprites():Void
	{
		_prevStopPlayback();

		if (_previewSprGrp != null) _previewSprGrp.clear();
		_previewSprites   = [];
		_previewInitState = [];

		if (doc == null || doc.sprites == null) return;

		// ── Fondo de rejilla (para que la preview no parezca vacía) ───────────
		var gridBg = new FlxSprite(0, 0);
		gridBg.makeGraphic(FlxG.width, FlxG.height, 0xFF111622);
		// Dibujamos líneas de rejilla de 80px directamente en el BitmapData
		var bmd = gridBg.pixels;
		bmd.lock();
		final gridCol:Int = 0xFF1E2A40;
		final gStep:Int   = 80;
		for (gx in 0...Std.int(FlxG.width / gStep) + 2)
		{
			var xx = gx * gStep;
			if (xx >= FlxG.width) break;
			for (py in 0...FlxG.height) bmd.setPixel32(xx, py, gridCol);
		}
		for (gy in 0...Std.int(FlxG.height / gStep) + 2)
		{
			var yy = gy * gStep;
			if (yy >= FlxG.height) break;
			for (px in 0...FlxG.width) bmd.setPixel32(px, yy, gridCol);
		}
		bmd.unlock();
		gridBg.scrollFactor.set(0, 0);
		gridBg.cameras = [camPreview];
		_previewSprGrp.add(gridBg);

		// ── Sprites del documento — visibles en la vista estática inicial ─────
		for (key in spriteKeys)
		{
			var data:CutsceneSpriteData = Reflect.field(doc.sprites, key);
			if (data == null) continue;

			var spr:FlxSprite = _buildPreviewSprite(key, data);
			if (spr == null) continue;

			spr.scrollFactor.set(0, 0);
			spr.cameras = [camPreview];
			spr.visible = true;           // Vista estática: se ven todos en su posición inicial
			spr.alpha   = data.alpha ?? 1.0;
			_previewSprGrp.add(spr);
			_previewSprites.set(key, spr);

			_previewInitState.set(key, {
				x:       spr.x,
				y:       spr.y,
				alpha:   data.alpha ?? 1.0,
				angle:   spr.angle,
				scaleX:  spr.scale.x,
				scaleY:  spr.scale.y,
				centered: data.center == true
			});
		}

		var count = [for (_ in _previewSprites.keys()) true].length;
		_prevSetStatus('Vista estática — $count sprite(s). ▶ PLAY para animar.');
	}

	/** Build a lightweight FlxSprite (or FunkinSprite) from CutsceneSpriteData. */
	function _buildPreviewSprite(id:String, data:CutsceneSpriteData):FlxSprite
	{
		var spr:FlxSprite;
		switch (data.type ?? 'rect')
		{
			case 'rect':
				spr = new FlxSprite();
				var w = Std.int((data.width  ?? 1.0) * FlxG.width);
				var h = Std.int((data.height ?? 1.0) * FlxG.height);
				spr.makeGraphic(w, h, _parseColorPreview(data.color ?? '0xFF000000'));

			case 'image':
				var fs = new FunkinSprite();
				var g  = Paths.getGraphic(data.image ?? id);
				if (g != null) fs.loadGraphic(g);
				else           fs.makeGraphic(150, 150, 0x44FFFFFF);
				spr = fs;

			case 'atlas', 'sparrow', 'packer', 'animate', 'auto':
				var fs = new FunkinSprite();
				var pathList:Array<String> = data.paths;
				try {
					if (pathList != null && pathList.length > 1)
						fs.loadMultiAnimateAtlas(pathList);
					else if (pathList != null && pathList.length == 1)
						fs.loadAsset(pathList[0]);
					else
						fs.loadAsset(data.image ?? id);
					// Register animations
					if (data.animations != null)
						for (a in (data.animations : Array<CutsceneSpriteAnim>))
							fs.addAnim(a.name, a.prefix, a.fps ?? 24, a.loop ?? false, a.indices);
					// Play first anim if any
					if (data.animations != null && data.animations.length > 0)
						try fs.playAnim(data.animations[0].name) catch (_) {}
				} catch (e:Dynamic) {
					trace('[Preview] Error cargando "$id": $e');
					fs.makeGraphic(60, 60, 0x44FF4444);
				}
				spr = fs;

			default:
				spr = new FlxSprite();
				spr.makeGraphic(60, 60, 0x44FF0000);
		}

		// Apply initial transform
		if (data.x     != null) spr.x     = data.x;
		if (data.y     != null) spr.y     = data.y;
		if (data.alpha != null) spr.alpha = data.alpha;
		if (data.angle != null) spr.angle = data.angle;
		if (data.flipX == true) spr.flipX = true;
		if (data.flipY == true) spr.flipY = true;
		spr.antialiasing = data.antialiasing ?? true;

		if (data.scale != null) {
			spr.setGraphicSize(Std.int(spr.width * data.scale));
			spr.updateHitbox();
		} else if (data.scaleX != null || data.scaleY != null) {
			spr.scale.set(data.scaleX ?? 1.0, data.scaleY ?? 1.0);
			spr.updateHitbox();
		}

		if (data.center == true) {
			spr.x = (FlxG.width  - spr.width)  / 2;
			spr.y = (FlxG.height - spr.height) / 2;
		}

		return spr;
	}

	// ── Playback ──────────────────────────────────────────────────────────────

	function previewPlay():Void
	{
		if (doc == null || doc.steps == null || doc.steps.length == 0)
		{
			_prevSetStatus('No hay steps para reproducir.');
			return;
		}
		// Resetear posiciones pero ocultar sprites —
		// los steps 'add' los van a ir mostrando en orden, igual que en el juego real.
		_prevStopPlayback();
		for (key => spr in _previewSprites)
		{
			var init = _previewInitState.get(key);
			if (init == null) { spr.visible = false; continue; }
			spr.alpha   = init.alpha;
			spr.angle   = init.angle;
			spr.scale.set(init.scaleX, init.scaleY);
			spr.color   = 0xFFFFFFFF;
			if (init.centered)
			{
				spr.x = (FlxG.width  - spr.width)  / 2;
				spr.y = (FlxG.height - spr.height) / 2;
			}
			else { spr.x = init.x; spr.y = init.y; }
			spr.visible = false;   // ocultos hasta que el step 'add' los muestre
		}
		_prevPlaying = true;
		_prevStepIdx = 0;
		_prevSetStatus('▶ Playing...');
		_prevRunStep();
	}

	function previewStop():Void
	{
		_prevStopPlayback();
		// Volver a la vista estática con todos los sprites visibles
		previewReset();
		_prevSetStatus('Detenido. Vista estática.');
	}

	function previewReset():Void
	{
		_prevStopPlayback();

		// Restaurar cada sprite a su estado inicial y mostrarlo
		// (modo estático: todos visibles en su posición de partida)
		for (key => spr in _previewSprites)
		{
			var init = _previewInitState.get(key);
			if (init == null) continue;
			spr.alpha   = init.alpha;
			spr.angle   = init.angle;
			spr.scale.set(init.scaleX, init.scaleY);
			spr.color   = 0xFFFFFFFF;
			if (init.centered)
			{
				spr.x = (FlxG.width  - spr.width)  / 2;
				spr.y = (FlxG.height - spr.height) / 2;
			}
			else
			{
				spr.x = init.x;
				spr.y = init.y;
			}
			spr.visible = true;   // vista estática → todos visibles
		}
		_prevSetStatus('Reset. Vista estática — ▶ PLAY para animar.');
	}

	function _prevStopPlayback():Void
	{
		_prevPlaying = false;
		_prevStepIdx = -1;
		for (t in _prevActiveTimers) if (t != null) { try t.cancel() catch (_) {} }
		for (tw in _prevActiveTweens) if (tw != null) { try tw.cancel() catch (_) {} }
		_prevActiveTimers  = [];
		_prevActiveTweens  = [];
	}

	function _prevRunStep():Void
	{
		if (!_prevPlaying) return;
		if (_prevStepIdx < 0 || _prevStepIdx >= doc.steps.length)
		{
			_prevPlaying = false;
			_prevSetStatus('Terminado. (${doc.steps.length} steps)');
			return;
		}

		var step:CutsceneStep = doc.steps[_prevStepIdx];
		_prevStepIdx++;

		switch (step.action)
		{
			// ── add ────────────────────────────────────────────────────────
			case 'add':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr != null)
				{
					spr.visible = true;
					if (step.alpha != null) spr.alpha = step.alpha;
				}
				_prevRunStep();

			// ── remove ─────────────────────────────────────────────────────
			case 'remove':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr != null) spr.visible = false;
				_prevRunStep();

			// ── setAlpha ───────────────────────────────────────────────────
			case 'setAlpha':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr != null && step.alpha != null) spr.alpha = step.alpha;
				_prevRunStep();

			// ── setColor ───────────────────────────────────────────────────
			case 'setColor':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr != null && step.color != null)
					spr.color = _parseColorPreview(step.color);
				_prevRunStep();

			// ── setVisible ─────────────────────────────────────────────────
			case 'setVisible':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr != null && step.visible != null) spr.visible = step.visible;
				_prevRunStep();

			// ── setPosition ────────────────────────────────────────────────
			case 'setPosition':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr != null) {
					if (step.x != null) spr.x = step.x;
					if (step.y != null) spr.y = step.y;
				}
				_prevRunStep();

			// ── screenCenter ───────────────────────────────────────────────
			case 'screenCenter':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr != null) {
					var axis = step.axis ?? 'xy';
					if (axis != 'y') spr.x = (FlxG.width  - spr.width)  / 2;
					if (axis != 'x') spr.y = (FlxG.height - spr.height) / 2;
				}
				_prevRunStep();

			// ── wait ───────────────────────────────────────────────────────
			case 'wait':
				var t = step.time ?? 1.0;
				_prevSetStatus('⏳ wait ${t}s...');
				var tmr = new FlxTimer();
				_prevActiveTimers.push(tmr);
				tmr.start(t, function(_) {
					_prevActiveTimers.remove(tmr);
					_prevRunStep();
				});

			// ── fadeTimer ──────────────────────────────────────────────────
			case 'fadeTimer':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr == null) { _prevRunStep(); return; }
				var target   = step.target   ?? 0.0;
				var stepAmt  = step.step     ?? 0.15;
				var interval = step.interval ?? 0.3;
				_prevSetStatus('⏳ fadeTimer → ${step.sprite}...');
				var tmr = new FlxTimer();
				_prevActiveTimers.push(tmr);
				tmr.start(interval, function(ft:FlxTimer) {
					if (!_prevPlaying) { ft.cancel(); return; }
					spr.alpha = (target < spr.alpha)
						? Math.max(target, spr.alpha - stepAmt)
						: Math.min(target, spr.alpha + stepAmt);
					if (Math.abs(spr.alpha - target) < 0.001) {
						spr.alpha = target;
						_prevActiveTimers.remove(tmr);
						ft.cancel();
						_prevRunStep();
					} else {
						ft.reset(interval);
					}
				});

			// ── tween ──────────────────────────────────────────────────────
			case 'tween':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr == null || step.props == null) { _prevRunStep(); return; }
				var dur  = step.duration ?? 1.0;
				var ease = _parsePrevEase(step.ease);
				_prevSetStatus('⏳ tween ${step.sprite} (${dur}s)...');
				var tw = FlxTween.tween(spr, step.props, dur, {
					ease: ease,
					onComplete: function(_) {
						_prevActiveTweens.remove(_);
						if (!(step.async ?? false)) _prevRunStep();
					}
				});
				_prevActiveTweens.push(tw);
				if (step.async ?? false) _prevRunStep();

			// ── playAnim ───────────────────────────────────────────────────
			case 'playAnim':
				var spr = _previewSprites.get(step.sprite ?? '');
				if (spr != null && step.anim != null)
					try cast(spr, FunkinSprite).playAnim(step.anim, step.force ?? false)
					catch (_) {}
				_prevRunStep();

			// ── playSound / waitSound ──────────────────────────────────────
			// Skip audio in preview — just advance
			case 'playSound', 'waitSound':
				_prevRunStep();

			// ── cameraFade ─────────────────────────────────────────────────
			case 'cameraFade':
				var dur   = step.duration ?? 1.0;
				var col   = _parseColorPreview(step.color ?? 'BLACK');
				var fadeIn = step.fadeIn ?? false;
				_prevSetStatus('⏳ cameraFade (${dur}s)...');
				if (fadeIn)
					camPreview.fade(col, dur, true, function() _prevRunStep());
				else
					camPreview.fade(col, dur, false, function() _prevRunStep());

			// ── cameraFlash ────────────────────────────────────────────────
			case 'cameraFlash':
				var dur = step.duration ?? 1.0;
				var col = _parseColorPreview(step.color ?? 'WHITE');
				camPreview.flash(col, dur);
				_prevRunStep();

			// ── cameraShake ────────────────────────────────────────────────
			case 'cameraShake':
				camPreview.shake(step.intensity ?? 0.05, step.duration ?? 0.5);
				_prevRunStep();

			// ── end ────────────────────────────────────────────────────────
			case 'end':
				_prevPlaying = false;
				_prevSetStatus('✓ Fin de la cutscene.');

			// ── script / unknown ───────────────────────────────────────────
			default:
				_prevRunStep();
		}
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	inline function _prevSetStatus(msg:String):Void
	{
		if (_prevStatusLbl != null) _prevStatusLbl.text = msg;
	}

	function _parseColorPreview(s:String):FlxColor
	{
		if (s == null) return FlxColor.BLACK;
		return switch (s.toUpperCase()) {
			case 'BLACK':   FlxColor.BLACK;
			case 'WHITE':   FlxColor.WHITE;
			case 'RED':     FlxColor.RED;
			case 'GREEN':   FlxColor.GREEN;
			case 'BLUE':    FlxColor.BLUE;
			case 'YELLOW':  FlxColor.YELLOW;
			case 'CYAN':    0xFF00FFFF;
			case 'MAGENTA': FlxColor.MAGENTA;
			case 'ORANGE':  FlxColor.ORANGE;
			case 'TRANSPARENT': FlxColor.TRANSPARENT;
			default:
				try Std.parseInt(s) catch (_) FlxColor.BLACK;
		};
	}

	function _parsePrevEase(s:String):Float->Float
	{
		if (s == null) return FlxEase.linear;
		return switch (s) {
			case 'quadIn':    FlxEase.quadIn;
			case 'quadOut':   FlxEase.quadOut;
			case 'quadInOut': FlxEase.quadInOut;
			case 'cubeIn':    FlxEase.cubeIn;
			case 'cubeOut':   FlxEase.cubeOut;
			case 'cubeInOut': FlxEase.cubeInOut;
			case 'sineIn':    FlxEase.sineIn;
			case 'sineOut':   FlxEase.sineOut;
			case 'sineInOut': FlxEase.sineInOut;
			case 'quartIn':   FlxEase.quartIn;
			case 'quartOut':  FlxEase.quartOut;
			case 'elasticIn': FlxEase.elasticIn;
			case 'elasticOut':FlxEase.elasticOut;
			case 'bounceOut': FlxEase.bounceOut;
			case 'bounceIn':  FlxEase.bounceIn;
			default:          FlxEase.linear;
		};
	}
}

/** Estado inicial de un sprite de preview — usado para reset. */
typedef _PrevInitState = {
	x:Float, y:Float, alpha:Float, angle:Float,
	scaleX:Float, scaleY:Float, centered:Bool
}
