package funkin.debug.editors;
import coolui.CoolInputText;
import coolui.CoolNumericStepper;
import coolui.CoolCheckBox;
import coolui.CoolDropDown;
import coolui.CoolTabMenu;
import flixel.math.FlxMath;
import funkin.gameplay.objects.character.Character.AnimData;
import funkin.gameplay.objects.character.Character.CharacterData;
import funkin.gameplay.objects.stages.Stage;
import funkin.states.MusicBeatState;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.FlxCamera;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;
import flixel.addons.display.FlxGridOverlay;
import flixel.group.FlxGroup.FlxTypedGroup;
import coolui.Cool9Slice;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import coolui.CoolButton;
import flixel.ui.FlxSpriteButton;
import funkin.gameplay.objects.character.Character;
import funkin.menus.FreeplayState;
import funkin.data.CoolUtil;
import funkin.states.LoadingState;
import haxe.Json;
import funkin.menus.MainMenuState;
import funkin.gameplay.objects.character.HealthIcon;
import funkin.debug.ColorPickerWheel;
#if sys
import sys.FileSystem;
import sys.io.File;
import lime.ui.FileDialog;
#end

using StringTools;

// ── Formato V2 de personaje (render.layers) ───────────────────────────────────
// Un objeto individual dentro de una capa (sprite, personaje, solid, etc.)
typedef LayerObjectData = {
	var name:String;
	var path:String;
	var position:Array<Float>;
	var scale:Array<Float>;
	var alpha:Float;
	var visible:Bool;
	var flipX:Bool;
	var flipY:Bool;
	var antialiasing:Bool;
	var animations:Array<AnimData>;
}

// Una capa es un CONTENEDOR de objetos, al estilo Photoshop.
// Los objetos solo son seleccionables en la capa activa.
typedef LayerData = {
	var name:String;
	var visible:Bool;      // ocultar/mostrar toda la capa
	var ?locked:Bool;      // si true, los objetos no son seleccionables
	var objects:Array<LayerObjectData>;
}

typedef CharDeathV2 = {
	var character:String;
	var sound:String;
	var endAnim:String;
}

typedef CharacterDataV2 = {
	var meta:Dynamic;       // { isPlayer:Bool }
	var gameplay:Dynamic;   // { position, cameraOffset, death, ?idleAfterSing }
	var render:Dynamic;     // { layers:Array<LayerData> }
	var icon:Dynamic;       // { path, flipX, animations, ... }
}

// ── CharacterEditor ────────────────────────────────────
class CharacterEditor extends MusicBeatState
{
	var UI_box:CoolTabMenu;

	var char:Character;
	var textAnim:FlxText;
	var textInfo:FlxText;
	var textControls:FlxText;
	var textHelp:FlxText;
	var dumbTexts:FlxTypedGroup<FlxText>;
	var layeringbullshit:FlxTypedGroup<FlxSprite>;
	var animList:Array<String> = [];
	var curAnim:Int = 0;
	var ghostAnimIdx:Int = 0;
	public var daAnim:String = 'bf';
	var camFollow:FlxObject;
	var camHUD:FlxCamera;
	var camGame:FlxCamera;
	var camUI:FlxCamera; // cámara invisible cameras[0]: da coordenadas estables al mouse (zoom siempre 1)
	var _file:FileReference;
	var ghostChar:Character;

	// UI Elements — Character tab
	var playerCheckbox:CoolCheckBox;
	var charFlipXCheckbox:CoolCheckBox;

	// UI Elements — Properties tab
	var antialiasingCheckbox:CoolCheckBox;
	var scaleStepper:CoolNumericStepper;
	var pathInput:CoolInputText;
	var spritemapNameInput:CoolInputText; // antes: animFileInput
	var isTxtCheckbox:CoolCheckBox;
	var isSpritesheetCheckbox:CoolCheckBox;
	var isFlxAnimateCheckbox:CoolCheckBox; // antes: isAdobeAnimateCheckbox
	var healthIconInput:CoolInputText;
	var healthBarColorInput:CoolInputText;

	// UI Elements — Animation tab
	var animNameInput:CoolInputText;
	var animPrefixInput:CoolInputText;
	var animFramerateStepper:CoolNumericStepper;
	var animLoopedCheckbox:CoolCheckBox;
	var animFlipXCheckbox:CoolCheckBox;
	// Multi-atlas: campos de sub-atlas por animación
	var animAssetPathInput:CoolInputText;
	var animRenderTypeInput:CoolInputText;
	var offsetXStepper:CoolNumericStepper;
	var offsetYStepper:CoolNumericStepper;

	var velocityPlus:Float = 1;
	var gridBG:FlxSprite;
	var showGrid:Bool = true;

	// ── Cache para actualizar labels en-lugar (evita recrear objetos cada frame) ─
	// generateOffsetTexts() los llena; updateOffsetTexts() los reutiliza.
	var _offsetLabels:Array<FlxText>  = [];
	var _ghostBadgeBgs:Array<FlxSprite> = [];
	var _ghostBadgeLabels:Array<FlxText> = [];
	var _rowBgs:Array<FlxSprite> = [];

	// Timer reutilizable para el flash amarillo de textInfo (un solo objeto)
	var _flashTimer:FlxTimer = null;

	// Mouse drag para offsets (click derecho)
	var isDraggingOffset:Bool = false;
	var dragLastX:Float = 0;
	var dragLastY:Float = 0;

	// Nombre original de la animación que se está editando.
	// null = modo "Add" (nueva animación). String = modo "Edit" (modificar existente).
	var editingAnimName:String = null;

	// Botón "Add Animation" — necesitamos referencia para cambiar su label
	var addAnimBtn:CoolButton;

	// Character data para exportar
	var characterData:CharacterData;
	var currentAnimData:Array<AnimData> = [];

	public var currentStage:Stage;

	// Icon preview
	var iconPreview:HealthIcon;
	var iconBG:FlxSprite;

	// Ruta de la carpeta FlxAnimate importada (assets/images/<char>/)
	var flxAnimateFolderPath:String = "";

	// ── Variables visuales ────────────────────────────────────────────────────
	// Panel oscuro detrás de la lista de offsets / controles (lado izquierdo)
	var leftPanel:FlxSprite;
	// Barra de header con nombre del personaje actual
	var charHeaderBg:FlxSprite;
	var charHeaderText:FlxText;
	// Barra de estado inferior (reemplaza textHelp flotante)
	var statusBar:FlxSprite;
	// Borde decorativo del panel UI derecho
	var uiPanelBg:FlxSprite;

	// Posición X de inicio fuera de pantalla para el slide-in del panel
	static inline var PANEL_HIDDEN_X:Float = 1500;

	// Fila de highlight para la animación seleccionada en la lista
	var animRowHighlight:FlxSprite;
	// Acento de color actual del estado (verde=ok, rojo=error, cyan=info)
	var statusAccentBar:FlxSprite;
	// Preview de healthBar en el HUD (esquina inferior, debajo del ícono)
	var hudHealthBar:FlxSprite;
	var hudHealthBarLabel:FlxText;
	var charDeathInput:coolui.CoolInputText;
	// ── Game Over fields ──────────────────────────────────────────────────────
	var gameOverSoundInput:CoolInputText;
	var gameOverMusicInput:CoolInputText;
	var gameOverEndInput:CoolInputText;
	var gameOverBpmStepper:CoolNumericStepper;
	var gameOverCamFrameStepper:CoolNumericStepper;
	// Position offset steppers (campo "positionOffset" del CharacterData)
	var posOffsetXStepper:CoolNumericStepper;
	var posOffsetYStepper:CoolNumericStepper;
	// Camera offset steppers (campo "cameraOffset" del CharacterData)
	var camOffsetXStepper:CoolNumericStepper;
	var camOffsetYStepper:CoolNumericStepper;
	// Color actual seleccionado para la healthBar
	var currentHealthBarColor:FlxColor = FlxColor.fromString("#31B0D1");

	// ── Unsaved-changes tracking ──────────────────────────────────────────────
	var _hasUnsaved:Bool = false;
	var _unsavedDlg:funkin.debug.EditorDialogs.UnsavedChangesDialog = null;
	var _windowCloseFn:Void->Void = null;

	// ── Undo stack ────────────────────────────────────────────────────────────
	// Cada entrada es un JSON snapshot de currentAnimData en ese momento.
	// _pushUndo() se llama ANTES de cualquier operación destructiva.
	// _doUndo() restaura el último snapshot y recarga el personaje.
	var _undoStack:Array<String> = [];
	static inline var MAX_UNDO:Int = 30;
	// Evita empujar un snapshot idéntico al que ya está en el tope de la pila
	// (p.ej. al mantener pulsada una flecha varias veces seguidas y luego hacer
	// Ctrl+Z: cada pulsación ya era distinta, pero si por algún bug se llama dos
	// veces sin cambio intermedio, no duplicamos entradas inútiles).
	var _lastUndoJson:String = "";

	// ── Layer system (formato V2 render.layers) ───────────────────────────────
	// layers: copia en memoria de render.layers del JSON cargado.
	// curLayerIdx: índice de la capa que se está editando actualmente.
	// _isV2Format: true si el JSON usa el nuevo formato CharacterDataV2.
	var layers:Array<LayerData> = [];
	var curLayerIdx:Int  = 0;   // capa activa
	var curObjectIdx:Int = 0;   // objeto seleccionado DENTRO de la capa activa
	var _isV2Format:Bool = false;

	// ── Visual layer panel (Adobe-Animate-style rows at bottom of left panel) ──
	var layerDropDown:CoolDropDown; // kept for compat, always hidden
	var layerPanelBg:FlxSprite;
	var layerPanelGroup:FlxTypedGroup<FlxSprite>;
	var layerPanelTexts:FlxTypedGroup<FlxText>;
	var layerPanelHits:Array<{x:Float, y:Float, w:Float, h:Float, zone:String, idx:Int}> = [];
	var layerPanelScroll:Int = 0;
	static inline var LP_ROW_H:Int  = 24;
	static inline var LP_MAX_VIS:Int = 6;
	static inline var LP_W:Int       = 340;

	// ── Layer drag-and-drop ───────────────────────────────────────────────────
	var _lpDragging:Bool   = false;
	var _lpDragPending:Bool = false;   // mouse held but not past threshold yet
	var _lpDragFromVis:Int = -1;       // visual-row index (0=top) that was grabbed
	var _lpDragFromIdx:Int = -1;       // layers[] index being dragged
	var _lpDragStartY:Float = 0;       // mouseY when drag began
	var _lpDropGap:Int     = -1;       // current drop gap (0..LP_MAX_VIS), local vis coords
	var _lpDragGhost:FlxSprite;
	var _lpDragGhostTxt:FlxText;
	var _lpDropLine:FlxSprite;

	// ── Context Menu (right-click, estilo Blender) ────────────────────────────
	var _ctxOpen:Bool        = false;
	var _ctxMX:Float         = 0;
	var _ctxMY:Float         = 0;
	var _ctxHover:Int        = -1;
	var _ctxBg:FlxSprite;
	var _ctxBorder:FlxSprite;
	var _ctxHeaderBg:FlxSprite;
	var _ctxHeaderTxt:FlxText;
	var _ctxItemBgs:Array<FlxSprite>   = [];
	var _ctxItemIcons:Array<FlxText>   = [];
	var _ctxItemLabels:Array<FlxText>  = [];
	var _ctxActions:Array<Void->Void>  = [];
	static inline var CTX_W:Int   = 230;
	static inline var CTX_IH:Int  = 30;
	static inline var CTX_HH:Int  = 26;
	// Right-click drag threshold: if released without moving, open context menu
	var _rcPressX:Float = 0;
	var _rcPressY:Float = 0;
	var _rcMoved:Bool   = false;

	// ── Transform Handles (scale estilo Photoshop) ────────────────────────────
	// 8 handles: 0=TL 1=TC 2=TR 3=RC 4=BR 5=BC 6=BL 7=LC
	var _txHandles:Array<FlxSprite>    = [];
	var _txHitBgs:Array<FlxSprite>     = [];   // zona de hit más grande (invisible)
	var _txDragging:Bool   = false;
	var _txDragIdx:Int     = -1;
	var _txDragMX0:Float   = 0;
	var _txDragMY0:Float   = 0;
	var _txDragSX0:Float   = 0;
	var _txDragSY0:Float   = 0;
	var _txDragCW0:Float   = 0;    // char.width at drag start
	var _txDragCH0:Float   = 0;
	static inline var TX_HS:Int = 10;  // handle size px

	// ── Layer copy / paste ────────────────────────────────────────────────────
	var _copiedLayer:Dynamic = null;   // JSON clone of last Ctrl+C'd LayerData

	// ── Selection state ───────────────────────────────────────────────────────
	// _hasSelection = true  → a layer/character is selected; props panel + anim list visible.
	// _hasSelection = false → nothing selected; props hidden, anim list empty.
	// Starts false; set to true the moment a character is loaded.
	var _hasSelection:Bool = false;
	var _selBorderT:FlxSprite;   // top edge of the selection box   (camGame world-space)
	var _selBorderB:FlxSprite;   // bottom edge
	var _selBorderL:FlxSprite;   // left edge
	var _selBorderR:FlxSprite;   // right edge
	var _selNameLabel:FlxText;   // layer / character name drawn above the box
	static inline var SEL_BW:Int = 2; // border thickness in px

	// ── Animation list scroll ─────────────────────────────────────────────────
	// How many rows to skip from the top of the animation list.
	// Controlled by mouse-wheel while the cursor is over the left panel
	// (but NOT over the layer panel at the bottom).
	var _animListScroll:Int = 0;

	// ── Layer inline rename (double-click) ───────────────────────────────────
	var _lpRenameInput:CoolInputText;  // overlay input que aparece sobre la fila
	var _lpRenameIdx:Int   = -1;       // índice de la capa que se está renombrando
	var _lpLastClickIdx:Int   = -1;    // para detectar doble clic
	var _lpLastClickMs:Float  = -9999; // stamp del último click en una fila

	// ── Animation inline rename (double-click en fila de anim) ───────────────
	var _animRenameInput:CoolInputText; // overlay input sobre la fila de animación
	var _animRenameIdx:Int    = -1;     // índice en currentAnimData que se renombra
	var _animLastClickIdx:Int = -1;     // para detectar doble clic en la lista
	var _animLastClickMs:Float = -9999; // timestamp del último clic en una fila

	// UI del panel flotante de propiedades de capa (antes "tab Layers")
	var layerNameInput:CoolInputText;
	var layerPathInput:CoolInputText;
	var layerAlphaStepper:CoolNumericStepper;
	var layerScaleXStepper:CoolNumericStepper;
	var layerScaleYStepper:CoolNumericStepper;
	var layerPosXStepper:CoolNumericStepper;
	var layerPosYStepper:CoolNumericStepper;
	var layerVisibleCheckbox:CoolCheckBox;
	var layerFlipXCheckbox:CoolCheckBox;
	var layerFlipYCheckbox:CoolCheckBox;
	var layerAntialiasingCheckbox:CoolCheckBox;

	// Gameplay V2 extra
	var idleAfterSingCheckbox:CoolCheckBox;

	// Icon V2
	var iconFlipXCheckbox:CoolCheckBox;
	var iconBumpInBeatsCheckbox:CoolCheckBox;
	var iconStepTempoStepper:CoolNumericStepper;

	public function new(daAnim:String = 'bf')
	{
		super();
		this.daAnim = daAnim;
	}

	// ── create ───────────────────────────────────────────────────────────────

	override function create()
	{
		funkin.debug.themes.EditorTheme.load();
		funkin.system.CursorManager.show();
		funkin.audio.MusicManager.play('configurator', 0.7);

		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;

		// camUI es una cámara completamente transparente y vacía que se pone
		// en cameras[0] para que FlxG.mouse.x/y use siempre zoom=1.
		// Sin esto, cuando camGame tiene zoom != 1, flixel-ui calcula mal
		// las posiciones de click en CoolInputText y el HUD deja de responder.
		camUI = new FlxCamera();
		camUI.bgColor.alpha = 0;

		FlxG.cameras.reset(camUI); // cameras[0] → FlxG.camera = camUI (zoom 1 fijo)
		FlxG.cameras.add(camGame, false); // renders encima de camUI
		FlxG.cameras.add(camHUD, false); // renders encima de todo

		currentStage = new Stage('stage_week1');
		currentStage.cameras = [camGame];
		add(currentStage);

		layeringbullshit = new FlxTypedGroup<FlxSprite>();
		layeringbullshit.cameras = [camGame];
		add(layeringbullshit);

		setupUI();

		dumbTexts = new FlxTypedGroup<FlxText>();
		dumbTexts.cameras = [camHUD];

		// ── Panel oscuro izquierdo ────────────────────────────────────────────
		// Cubre el área de controles + lista de offsets
		leftPanel = new FlxSprite(0, 0);
		leftPanel.makeGraphic(340, FlxG.height, (funkin.debug.themes.EditorTheme.current.bgPanel & 0x00FFFFFF) | 0xCC000000);
		leftPanel.cameras = [camHUD];
		leftPanel.scrollFactor.set();
		add(leftPanel);

		// Borde derecho del panel izquierdo (línea accent cyan)
		var leftPanelBorder = new FlxSprite(340, 0);
		leftPanelBorder.makeGraphic(2, FlxG.height, funkin.debug.themes.EditorTheme.current.accent);
		leftPanelBorder.cameras = [camHUD];
		leftPanelBorder.scrollFactor.set();
		add(leftPanelBorder);

		// ── Header del personaje (arriba del panel izquierdo) ─────────────────
		charHeaderBg = new FlxSprite(0, 0);
		charHeaderBg.makeGraphic(340, 36, funkin.debug.themes.EditorTheme.current.accent);
		charHeaderBg.cameras = [camHUD];
		charHeaderBg.scrollFactor.set();
		add(charHeaderBg);

		charHeaderText = new FlxText(8, 6, 330, '', 16);
		charHeaderText.color = funkin.debug.themes.EditorTheme.current.bgDark;
		charHeaderText.cameras = [camHUD];
		charHeaderText.scrollFactor.set();
		charHeaderText.font = "VCR OSD Mono";
		charHeaderText.text = "  CHARACTER EDITOR";
		add(charHeaderText);

		// Subtítulo con el nombre del personaje (debajo del header, más pequeño)
		var charSubText = new FlxText(8, 22, 330, '', 10);
		charSubText.color = (funkin.debug.themes.EditorTheme.current.bgDark & 0x00FFFFFF) | 0xAA000000;
		charSubText.cameras = [camHUD];
		charSubText.scrollFactor.set();
		charSubText.font = "VCR OSD Mono";
		add(charSubText);

		// Dropdown original — kept as compat stub, never shown
		layerDropDown = new CoolDropDown(54, 37, CoolDropDown.makeStrIdLabelArray(["(no layers)"], true), function(sel:String){});
		layerDropDown.visible = false;
		layerDropDown.cameras = [camHUD];
		layerDropDown.scrollFactor.set();
		add(layerDropDown);


		// ── Fila de highlight de la animación seleccionada ────────────────────
		animRowHighlight = new FlxSprite(4, 0);
		animRowHighlight.makeGraphic(332, 20, (funkin.debug.themes.EditorTheme.current.accent & 0x00FFFFFF) | 0x44000000);
		animRowHighlight.cameras = [camHUD];
		animRowHighlight.scrollFactor.set();
		animRowHighlight.visible = false;
		add(animRowHighlight);

		add(dumbTexts);

		// ── Textos de controles ───────────────────────────────────────────────
		var controlsBg = new FlxSprite(4, 40);
		controlsBg.makeGraphic(332, 85, 0x22FFFFFF);
		controlsBg.cameras = [camHUD];
		controlsBg.scrollFactor.set();
		add(controlsBg);

		textControls = new FlxText(8, 42, 328, '', 10);
		textControls.text = "W/S · Switch Anim   ARROWS · Offset (SHIFT=x10)\n" + "I/K · Cam Up/Down   J/L · Cam Left/Right\n"
			+ "SCROLL · Zoom   SPACE · Play   R · Reset   T · Ghost\n" + "CLICK ROW · Select+Edit Anim   RIGHT DRAG · Move Offset   Ctrl+Z · Undo";
		textControls.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		textControls.color = funkin.debug.themes.EditorTheme.current.textSecondary;
		textControls.cameras = [camHUD];
		textControls.scrollFactor.set();
		add(textControls);

		// ── Texto de animación actual ─────────────────────────────────────────
		textAnim = new FlxText(8, 132, 330, '', 18);
		textAnim.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 2);
		textAnim.color = funkin.debug.themes.EditorTheme.current.accent;
		textAnim.cameras = [camHUD];
		textAnim.scrollFactor.set();
		add(textAnim);

		// ── Texto de offset / zoom ────────────────────────────────────────────
		textInfo = new FlxText(8, 154, 330, '', 12);
		textInfo.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		textInfo.color = funkin.debug.themes.EditorTheme.current.warning;
		textInfo.cameras = [camHUD];
		textInfo.scrollFactor.set();
		add(textInfo);

		// ── Barra de estado inferior ──────────────────────────────────────────
		statusBar = new FlxSprite(0, FlxG.height - 30);
		statusBar.makeGraphic(FlxG.width, 30, (funkin.debug.themes.EditorTheme.current.bgDark & 0x00FFFFFF) | 0xDD000000);
		statusBar.cameras = [camHUD];
		statusBar.scrollFactor.set();
		add(statusBar);

		// Acento de color en la barra de estado (izquierda, 4px)
		statusAccentBar = new FlxSprite(0, FlxG.height - 30);
		statusAccentBar.makeGraphic(4, 30, funkin.debug.themes.EditorTheme.current.accent);
		statusAccentBar.cameras = [camHUD];
		statusAccentBar.scrollFactor.set();
		add(statusAccentBar);

		textHelp = new FlxText(12, FlxG.height - 24, FlxG.width - 200, '', 12);
		textHelp.text = "TIP · Use the UI tabs to edit properties and animations · Layer props panel at bottom-left";
		textHelp.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		textHelp.color = funkin.debug.themes.EditorTheme.current.accent;
		textHelp.cameras = [camHUD];
		textHelp.scrollFactor.set();
		add(textHelp);

		// ✨ Botón de tema en barra de estado (esquina inferior derecha)
		var _themeBtn = new coolui.CoolButton(FlxG.width - 75, FlxG.height - 28, "\u2728 Theme", function()
		{
			openSubState(new funkin.debug.themes.ThemePickerSubState());
		});
		_themeBtn.cameras = [camHUD];
		_themeBtn.scrollFactor.set();
		add(_themeBtn);

		// ── Icon preview ──────────────────────────────────────────────────────
		var iconAreaX = FlxG.width - 340 + 5; // dentro del panel derecho no existe aún, lo ponemos en la barra inferior
		// Lo dejamos en la esquina inferior izquierda del status bar a la derecha
		var iconX = FlxG.width - 185;
		var iconY = FlxG.height - 185;

		iconBG = new FlxSprite(iconX - 10, iconY - 28);
		iconBG.makeGraphic(170, 162, (funkin.debug.themes.EditorTheme.current.bgDark & 0x00FFFFFF) | 0xEE000000);
		iconBG.cameras = [camHUD];
		add(iconBG);

		// Borde superior del recuadro del ícono (línea cyan)
		var iconTopBorder = new FlxSprite(iconX - 10, iconY - 28);
		iconTopBorder.makeGraphic(170, 2, funkin.debug.themes.EditorTheme.current.accent);
		iconTopBorder.cameras = [camHUD];
		add(iconTopBorder);

		var iconLabel = new FlxText(iconX - 10, iconY - 22, 170, "ICON PREVIEW", 10);
		iconLabel.alignment = CENTER;
		iconLabel.color = funkin.debug.themes.EditorTheme.current.accent;
		iconLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		iconLabel.cameras = [camHUD];
		add(iconLabel);

		iconPreview = new HealthIcon('bf', false);
		iconPreview.setPosition(iconX, iconY - 8);
		iconPreview.cameras = [camHUD];
		iconPreview.scale.set(0.8, 0.8);
		add(iconPreview);

		// ── Preview de la healthBar en el HUD ─────────────────────────────────
		// Se muestra debajo del ícono, siempre visible con el color del personaje
		hudHealthBarLabel = new FlxText(iconX - 10, iconY + 150, 170, "HEALTH BAR", 10);
		hudHealthBarLabel.alignment = CENTER;
		hudHealthBarLabel.color = funkin.debug.themes.EditorTheme.current.accent;
		hudHealthBarLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		hudHealthBarLabel.cameras = [camHUD];
		add(hudHealthBarLabel);

		hudHealthBar = new FlxSprite(iconX - 10, iconY + 164);
		hudHealthBar.loadGraphic(Paths.image("UI/healthBar"));
		hudHealthBar.setGraphicSize(168, 20);
		hudHealthBar.updateHitbox();
		hudHealthBar.cameras = [camHUD];
		hudHealthBar.color = currentHealthBarColor;
		add(hudHealthBar);

		// ── Slide-in del panel derecho al abrir ───────────────────────────────
		UI_box.x = PANEL_HIDDEN_X + 30;
		uiPanelBg.x = PANEL_HIDDEN_X - 4 + 30;
		FlxTween.tween(UI_box, {x: FlxG.width - UI_box.width - 2}, 0.45, {ease: FlxEase.quartOut});
		FlxTween.tween(uiPanelBg, {x: FlxG.width - UI_box.width - 6}, 0.45, {ease: FlxEase.quartOut});

		// Fade-in del panel izquierdo
		leftPanel.alpha = 0;
		leftPanelBorder.alpha = 0;
		charHeaderBg.alpha = 0;
		charHeaderText.alpha = 0;
		FlxTween.tween(leftPanel, {alpha: 1}, 0.5, {ease: FlxEase.quartOut, startDelay: 0.1});
		FlxTween.tween(leftPanelBorder, {alpha: 1}, 0.5, {ease: FlxEase.quartOut, startDelay: 0.15});
		FlxTween.tween(charHeaderBg, {alpha: 1}, 0.4, {ease: FlxEase.quartOut, startDelay: 0.2});
		FlxTween.tween(charHeaderText, {alpha: 1}, 0.4, {ease: FlxEase.quartOut, startDelay: 0.25});

		// ── Visual layer panel (stacked rows, Adobe-Animate-style) ──────────
		buildLayerPanel();
		buildLayerPropsPanel();

		// ── Context menu ─────────────────────────────────────────────────────
		_buildContextMenu();

		// ── Transform handles ─────────────────────────────────────────────────
		_buildTransformHandles();

		// ── Selection border + name label (camGame world-space) ──────────────
		// Four thin sprites that form a rectangle around the selected object,
		// plus a text label. Updated every frame by _updateSelectionVisuals().
		var _selC = funkin.debug.themes.EditorTheme.current.accent;
		_selBorderT = new FlxSprite(); _selBorderT.makeGraphic(4, SEL_BW, _selC); _selBorderT.cameras = [camGame]; add(_selBorderT);
		_selBorderB = new FlxSprite(); _selBorderB.makeGraphic(4, SEL_BW, _selC); _selBorderB.cameras = [camGame]; add(_selBorderB);
		_selBorderL = new FlxSprite(); _selBorderL.makeGraphic(SEL_BW, 4, _selC); _selBorderL.cameras = [camGame]; add(_selBorderL);
		_selBorderR = new FlxSprite(); _selBorderR.makeGraphic(SEL_BW, 4, _selC); _selBorderR.cameras = [camGame]; add(_selBorderR);
		_selNameLabel = new FlxText(0, 0, 320, "", 14);
		_selNameLabel.setFormat(Paths.font("vcr.ttf"), 14, _selC, LEFT);
		_selNameLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2);
		_selNameLabel.cameras = [camGame];
		add(_selNameLabel);
		_setSelectionVisible(false);

		camFollow = new FlxObject(0, 0, 2, 2);
		camFollow.screenCenter();
		add(camFollow);
		camGame.follow(camFollow);

		displayCharacter(daAnim);
		loadCharacterData();

		// ── Window-close guard ────────────────────────────────────────────
		#if sys
		_windowCloseFn = function()
		{
			if (_hasUnsaved)
			{
				// Auto-guardar al cerrar para no perder trabajo
				try { reloadCharacterWithNewAnims(); } catch (_) {}
			}
		};
		lime.app.Application.current.window.onClose.add(_windowCloseFn);
		#end

		funkin.transitions.StateTransition.onStateCreated();

		super.create();
	}

	// ── UI Setup ──────────────────────────────────────────────────────────────

	function setupUI():Void
	{
		var tabs = [
			{name: "Character", label: "Character"},
			{name: "Animation", label: "Animation"},
			{name: "Properties", label: "Properties"},
			{name: "Import",    label: "Import Assets"},
			{name: "Export",    label: "Export"}
		];

		UI_box = new CoolTabMenu(null, tabs, true);
		UI_box.cameras = [camHUD];
		UI_box.resize(320, 450);
		UI_box.x = FlxG.width - UI_box.width - 2;
		UI_box.y = 10;

		// Panel oscuro detrás del tab menu (se crea aquí para poder referenciar el tamaño)
		uiPanelBg = new FlxSprite(UI_box.x - 4, UI_box.y - 4);
		uiPanelBg.makeGraphic(Std.int(UI_box.width) + 8, Std.int(UI_box.height) + 8, (funkin.debug.themes.EditorTheme.current.bgDark & 0x00FFFFFF) | 0xDD000000);
		uiPanelBg.cameras = [camHUD];
		add(uiPanelBg);

		add(UI_box);

		addCharacterTab();
		addAnimationTab();
		addPropertiesTab();
		addImportTab();
		addExportTab();
	}

	// ── Tab: Character ────────────────────────────────────────────────────────

	function addCharacterTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Character";

		playerCheckbox = new CoolCheckBox(10, 10, null, null, "Player Character", 150);
		playerCheckbox.checked = false;
		tab.add(playerCheckbox);

		charFlipXCheckbox = new CoolCheckBox(165, 10, null, null, "FlipX", 80);
		charFlipXCheckbox.checked = false;
		charFlipXCheckbox.callback = function(_:Bool)
		{
			if (char != null)      char.flipX      = charFlipXCheckbox.checked;
			if (ghostChar != null) ghostChar.flipX = charFlipXCheckbox.checked;
		};
		tab.add(charFlipXCheckbox);

		idleAfterSingCheckbox = new CoolCheckBox(10, 30, null, null, "Idle After Sing", 150);
		idleAfterSingCheckbox.checked = true;
		tab.add(idleAfterSingCheckbox);

		tab.add(new FlxText(10, 47, 0, "Death Character:", 10));
		charDeathInput = new CoolInputText(10, 58, 200, '', 8);
		tab.add(charDeathInput);
		var charDeathHint = new FlxText(10, 72, 280, "Ej: bf-dead  (empty = default)", 8);
		charDeathHint.color = FlxColor.WHITE;
		tab.add(charDeathHint);

		// ── Game Over ──────────────────────────────────────────────────────────
		var goLabel = new FlxText(10, 90, 0, "── Game Over ──", 10);
		goLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(goLabel);

		var yGO = 107;

		tab.add(new FlxText(10, yGO, 0, "Death SFX  (Paths.sound):", 8));
		gameOverSoundInput = new CoolInputText(10, yGO + 12, 200, '', 8);
		var goSndHint = new FlxText(10, yGO + 26, 280, "Default: fnf_loss_sfx", 7);
		goSndHint.color = FlxColor.WHITE;
		tab.add(gameOverSoundInput);
		tab.add(goSndHint);
		yGO += 42;

		tab.add(new FlxText(10, yGO, 0, "Loop Music  (Paths.music):", 8));
		gameOverMusicInput = new CoolInputText(10, yGO + 12, 200, '', 8);
		var goMusHint = new FlxText(10, yGO + 36, 280, "Default: gameplay/gameOver", 7);
		goMusHint.color = FlxColor.WHITE;
		tab.add(gameOverMusicInput);
		tab.add(goMusHint);
		yGO += 42;

		tab.add(new FlxText(10, yGO + 10, 0, "End/Retry SFX  (Paths.music):", 8));
		gameOverEndInput = new CoolInputText(10, yGO + 22, 200, '', 8);
		var goEndHint = new FlxText(10, yGO + 36, 280, "Default: gameplay/gameOverEnd", 7);
		goEndHint.color = FlxColor.WHITE;
		tab.add(gameOverEndInput);
		tab.add(goEndHint);
		yGO += 42;

		tab.add(new FlxText(10, yGO + 12, 0, "BPM:", 8));
		gameOverBpmStepper = new CoolNumericStepper(60, yGO + 11, 1, 100, 1, 999, 1);
		tab.add(gameOverBpmStepper);

		tab.add(new FlxText(150, yGO + 12, 0, "Cam Frame:", 8));
		gameOverCamFrameStepper = new CoolNumericStepper(200, yGO + 31, 1, 12, 0, 60, 0);
		tab.add(gameOverCamFrameStepper);

		yGO += 24;

		var refreshBtn = new CoolButton(10, yGO, "Refresh Character", function()
		{
			displayCharacter(daAnim);
			loadCharacterData();
		});
		tab.add(refreshBtn);

		tab.add(new CoolButton(170, yGO, "Reset Camera", function()
		{
			camFollow.setPosition(FlxG.width / 2, FlxG.height / 2);
			camGame.zoom = 1;
		}));
		UI_box.addGroup(tab);
	}

	// ── Tab: Layers ───────────────────────────────────────────────────────────
	// Gestión de capas para el nuevo formato V2 (render.layers)

	// ── Layer properties floating HUD panel ──────────────────────────────────
	// Panel flotante sobre el panel de filas de capas. Muestra las propiedades
	// de la capa seleccionada directamente en el HUD, sin tab extra.
	// ──────────────────────────────────────────────────────────────────────────
	static inline var LP_PROPS_H:Int = 200; // altura total del panel de props

	var layerPropsBg:FlxSprite;
	var _layerPropsElems:Array<flixel.FlxBasic> = [];

	function _lpPropsY():Int
	{
		return _lpTopY() - LP_PROPS_H - 2; // 2px gap entre paneles
	}

	function buildLayerPropsPanel():Void
	{
		var T = funkin.debug.themes.EditorTheme.current;
		var px = 0;      // X base del panel (mismo que el panel de filas)
		var py = _lpPropsY();
		var pw = LP_W;

		// Fondo
		layerPropsBg = new FlxSprite(px, py);
		layerPropsBg.makeGraphic(pw, LP_PROPS_H, (T.bgPanel & 0x00FFFFFF) | 0xEE000000);
		layerPropsBg.cameras = [camHUD];
		layerPropsBg.scrollFactor.set();
		layerPropsBg.visible = false;
		add(layerPropsBg);
		_layerPropsElems.push(layerPropsBg);

		// Borde superior
		var topBorder = new FlxSprite(px, py);
		topBorder.makeGraphic(pw, 2, T.accent);
		topBorder.cameras = [camHUD];
		topBorder.scrollFactor.set();
		topBorder.alpha = 0.6;
		add(topBorder);
		_layerPropsElems.push(topBorder);

		// ── título ────────────────────────────────────────────────────────────
		var hdrBg = new FlxSprite(px, py).makeGraphic(pw, 22, T.bgPanelAlt);
		hdrBg.cameras = [camHUD]; hdrBg.scrollFactor.set(); add(hdrBg);
		_layerPropsElems.push(hdrBg);

		var hdrTxt = new FlxText(px + 8, py + 4, 0, "\u25CF LAYER PROPS", 11);
		hdrTxt.setFormat(Paths.font("vcr.ttf"), 11, T.accent, LEFT);
		hdrTxt.cameras = [camHUD]; hdrTxt.scrollFactor.set(); add(hdrTxt);
		_layerPropsElems.push(hdrTxt);

		var iy = py + 26; // Y interior, debajo del header

		// ── Name ──────────────────────────────────────────────────────────────
		var lbName = new FlxText(px + 6, iy, 0, "Name:", 9);
		lbName.setFormat(Paths.font("vcr.ttf"), 9, T.textDim, LEFT);
		lbName.cameras = [camHUD]; lbName.scrollFactor.set(); add(lbName);
		_layerPropsElems.push(lbName);

		layerNameInput = new CoolInputText(px + 46, iy - 1, 130, '', 8);
		layerNameInput.cameras = [camHUD]; layerNameInput.scrollFactor.set(); add(layerNameInput);
		_layerPropsElems.push(layerNameInput);

		// ── Path ──────────────────────────────────────────────────────────────
		var lbPath = new FlxText(px + 6, iy + 20, 0, "Path:", 9);
		lbPath.setFormat(Paths.font("vcr.ttf"), 9, T.textDim, LEFT);
		lbPath.cameras = [camHUD]; lbPath.scrollFactor.set(); add(lbPath);
		_layerPropsElems.push(lbPath);

		layerPathInput = new CoolInputText(px + 46, iy + 19, 190, '', 8);
		layerPathInput.cameras = [camHUD]; layerPathInput.scrollFactor.set(); add(layerPathInput);
		_layerPropsElems.push(layerPathInput);

		iy += 42;

		// ── Alpha + Visible ───────────────────────────────────────────────────
		var lbAlpha = new FlxText(px + 6, iy + 4, 0, "Alpha:", 9);
		lbAlpha.setFormat(Paths.font("vcr.ttf"), 9, T.textDim, LEFT);
		lbAlpha.cameras = [camHUD]; lbAlpha.scrollFactor.set(); add(lbAlpha);
		_layerPropsElems.push(lbAlpha);

		layerAlphaStepper = new CoolNumericStepper(px + 50, iy, 0.05, 1.0, 0.0, 1.0, 2);
		layerAlphaStepper.cameras = [camHUD]; layerAlphaStepper.scrollFactor.set(); add(layerAlphaStepper);
		_layerPropsElems.push(layerAlphaStepper);

		layerVisibleCheckbox = new CoolCheckBox(px + 160, iy, null, null, "Visible", 80);
		layerVisibleCheckbox.checked = true;
		layerVisibleCheckbox.cameras = [camHUD]; layerVisibleCheckbox.scrollFactor.set(); add(layerVisibleCheckbox);
		_layerPropsElems.push(layerVisibleCheckbox);

		iy += 22;

		// ── Scale X/Y ────────────────────────────────────────────────────────
		var lbScale = new FlxText(px + 6, iy + 4, 0, "Scale X:", 9);
		lbScale.setFormat(Paths.font("vcr.ttf"), 9, T.textDim, LEFT);
		lbScale.cameras = [camHUD]; lbScale.scrollFactor.set(); add(lbScale);
		_layerPropsElems.push(lbScale);

		layerScaleXStepper = new CoolNumericStepper(px + 58, iy, 0.1, 1.0, 0.01, 20.0, 2);
		layerScaleXStepper.cameras = [camHUD]; layerScaleXStepper.scrollFactor.set(); add(layerScaleXStepper);
		_layerPropsElems.push(layerScaleXStepper);

		var lbScaleY = new FlxText(px + 148, iy + 4, 0, "Y:", 9);
		lbScaleY.setFormat(Paths.font("vcr.ttf"), 9, T.textDim, LEFT);
		lbScaleY.cameras = [camHUD]; lbScaleY.scrollFactor.set(); add(lbScaleY);
		_layerPropsElems.push(lbScaleY);

		layerScaleYStepper = new CoolNumericStepper(px + 158, iy, 0.1, 1.0, 0.01, 20.0, 2);
		layerScaleYStepper.cameras = [camHUD]; layerScaleYStepper.scrollFactor.set(); add(layerScaleYStepper);
		_layerPropsElems.push(layerScaleYStepper);

		iy += 22;

		// ── Pos X/Y ──────────────────────────────────────────────────────────
		var lbPosX = new FlxText(px + 6, iy + 4, 0, "Pos X:", 9);
		lbPosX.setFormat(Paths.font("vcr.ttf"), 9, T.textDim, LEFT);
		lbPosX.cameras = [camHUD]; lbPosX.scrollFactor.set(); add(lbPosX);
		_layerPropsElems.push(lbPosX);

		layerPosXStepper = new CoolNumericStepper(px + 50, iy, 1, 0, -2000, 2000, 0);
		layerPosXStepper.cameras = [camHUD]; layerPosXStepper.scrollFactor.set(); add(layerPosXStepper);
		_layerPropsElems.push(layerPosXStepper);

		var lbPosY = new FlxText(px + 148, iy + 4, 0, "Y:", 9);
		lbPosY.setFormat(Paths.font("vcr.ttf"), 9, T.textDim, LEFT);
		lbPosY.cameras = [camHUD]; lbPosY.scrollFactor.set(); add(lbPosY);
		_layerPropsElems.push(lbPosY);

		layerPosYStepper = new CoolNumericStepper(px + 158, iy, 1, 0, -2000, 2000, 0);
		layerPosYStepper.cameras = [camHUD]; layerPosYStepper.scrollFactor.set(); add(layerPosYStepper);
		_layerPropsElems.push(layerPosYStepper);

		iy += 22;

		// ── Flags ─────────────────────────────────────────────────────────────
		layerFlipXCheckbox = new CoolCheckBox(px + 6, iy, null, null, "FlipX", 54);
		layerFlipXCheckbox.checked = false;
		layerFlipXCheckbox.cameras = [camHUD]; layerFlipXCheckbox.scrollFactor.set(); add(layerFlipXCheckbox);
		_layerPropsElems.push(layerFlipXCheckbox);

		layerFlipYCheckbox = new CoolCheckBox(px + 68, iy, null, null, "FlipY", 54);
		layerFlipYCheckbox.checked = false;
		layerFlipYCheckbox.cameras = [camHUD]; layerFlipYCheckbox.scrollFactor.set(); add(layerFlipYCheckbox);
		_layerPropsElems.push(layerFlipYCheckbox);

		layerAntialiasingCheckbox = new CoolCheckBox(px + 130, iy, null, null, "Antialias", 100);
		layerAntialiasingCheckbox.checked = true;
		layerAntialiasingCheckbox.cameras = [camHUD]; layerAntialiasingCheckbox.scrollFactor.set(); add(layerAntialiasingCheckbox);
		_layerPropsElems.push(layerAntialiasingCheckbox);

		iy += 24;

		// ── Apply + Move Up/Down ─────────────────────────────────────────────
		var btnApply = new coolui.CoolButton(px + 6, iy, "Apply", function() { _applyLayerTabToCurrentLayer(); });
		btnApply.cameras = [camHUD]; btnApply.scrollFactor.set(); add(btnApply);
		_layerPropsElems.push(btnApply);

		var btnUp = new coolui.CoolButton(px + 90, iy, "▲ Up", function() { _moveObjectUp(); });
		btnUp.cameras = [camHUD]; btnUp.scrollFactor.set(); add(btnUp);
		_layerPropsElems.push(btnUp);

		var btnDown = new coolui.CoolButton(px + 175, iy, "▼ Down", function() { _moveObjectDown(); });
		btnDown.cameras = [camHUD]; btnDown.scrollFactor.set(); add(btnDown);
		_layerPropsElems.push(btnDown);

		// Oculto por defecto; se muestra cuando _isV2Format = true
		_setLayerPropsPanelVisible(false);
	}

	function _setLayerPropsPanelVisible(v:Bool):Void
	{
		for (e in _layerPropsElems)
			if (e != null) e.visible = v;
	}

	// ── Layer helpers ─────────────────────────────────────────────────────────

	/** Rellena los campos del tab Layers con los datos del objeto actual. */
	function _syncLayerTabToCurrentLayer():Void
	{
		var obj = _curObject();
		if (obj == null) return;
		if (layerNameInput != null)   layerNameInput.text   = obj.name;
		if (layerPathInput != null)   layerPathInput.text   = obj.path;
		if (layerAlphaStepper != null) layerAlphaStepper.value = obj.alpha;
		if (layerVisibleCheckbox != null) layerVisibleCheckbox.checked = obj.visible;
		if (layerScaleXStepper != null) layerScaleXStepper.value = (obj.scale != null && obj.scale.length > 0) ? obj.scale[0] : 1.0;
		if (layerScaleYStepper != null) layerScaleYStepper.value = (obj.scale != null && obj.scale.length > 1) ? obj.scale[1] : 1.0;
		if (layerPosXStepper != null) layerPosXStepper.value = (obj.position != null && obj.position.length > 0) ? obj.position[0] : 0;
		if (layerPosYStepper != null) layerPosYStepper.value = (obj.position != null && obj.position.length > 1) ? obj.position[1] : 0;
		if (layerFlipXCheckbox != null) layerFlipXCheckbox.checked = obj.flipX;
		if (layerFlipYCheckbox != null) layerFlipYCheckbox.checked = obj.flipY;
		if (layerAntialiasingCheckbox != null) layerAntialiasingCheckbox.checked = obj.antialiasing;

		// Sincronizar tab Properties con los valores del objeto seleccionado
		if (pathInput != null) pathInput.text = obj.path;
		if (antialiasingCheckbox != null) antialiasingCheckbox.checked = obj.antialiasing;
		if (charFlipXCheckbox != null) charFlipXCheckbox.checked = obj.flipX;
		if (scaleStepper != null && obj.scale != null && obj.scale.length > 0)
			scaleStepper.value = obj.scale[0];
	}

	/** Escribe los campos del panel de props en el objeto actual. */
	function _applyLayerTabToCurrentLayer():Void
	{
		var obj = _curObject();
		if (obj == null)
		{
			setHelp("⚠ No object selected", FlxColor.YELLOW);
			return;
		}
		if (layerNameInput != null)   obj.name   = layerNameInput.text.trim();
		if (layerPathInput != null)   obj.path   = layerPathInput.text.trim();
		if (layerAlphaStepper != null)  obj.alpha  = layerAlphaStepper.value;
		if (layerVisibleCheckbox != null) obj.visible = layerVisibleCheckbox.checked;
		if (layerScaleXStepper != null && layerScaleYStepper != null)
			obj.scale = [layerScaleXStepper.value, layerScaleYStepper.value];
		if (layerPosXStepper != null && layerPosYStepper != null)
			obj.position = [layerPosXStepper.value, layerPosYStepper.value];
		if (layerFlipXCheckbox != null) obj.flipX = layerFlipXCheckbox.checked;
		if (layerFlipYCheckbox != null) obj.flipY = layerFlipYCheckbox.checked;
		if (layerAntialiasingCheckbox != null) obj.antialiasing = layerAntialiasingCheckbox.checked;
		_refreshLayerDropdown();
		_hasUnsaved = true;
		setHelp("✓ Object updated: " + obj.name, FlxColor.LIME);
	}

	function _addNewLayer():Void
	{
		if (!_isV2Format)
		{
			setHelp("⚠ No layer data found — reload the character", FlxColor.YELLOW);
			return;
		}
		var newLayer:LayerData = {
			name: "layer" + layers.length,
			visible: true,
			objects: []
		};
		layers.push(newLayer);
		curLayerIdx  = layers.length - 1;
		curObjectIdx = -1; // sin objeto seleccionado aún
		currentAnimData = [];
		_refreshLayerDropdown();
		_syncLayerTabToCurrentLayer();
		_hasUnsaved = true;
		setHelp("✓ New layer: " + newLayer.name + "  (right-click to add objects)", FlxColor.LIME);
	}

	/** Añade un nuevo objeto al FINAL de la capa activa. */
	function _addNewObject():Void
	{
		if (!_isV2Format)
		{
			setHelp("⚠ Switch to V2 format first", FlxColor.YELLOW);
			return;
		}
		var lay = _curLayer();
		if (lay == null)
		{
			setHelp("⚠ No active layer — add a layer first", FlxColor.YELLOW);
			return;
		}
		var newObj:LayerObjectData = {
			name: "object" + lay.objects.length,
			path: "BOYFRIEND",
			position: [0.0, 0.0],
			scale: [1.0, 1.0],
			alpha: 1.0,
			visible: true,
			flipX: false,
			flipY: false,
			antialiasing: true,
			animations: []
		};
		lay.objects.push(newObj);
		curObjectIdx = lay.objects.length - 1;
		currentAnimData = newObj.animations;
		_refreshLayerDropdown();
		_syncLayerTabToCurrentLayer();
		_hasUnsaved = true;
		setHelp("✓ New object: " + newObj.name + " in layer [" + lay.name + "]", FlxColor.LIME);
	}

	function _deleteCurrentLayer():Void
	{
		if (!_isV2Format || layers.length <= 1)
		{
			setHelp("⚠ Cannot delete: need at least one layer", FlxColor.RED);
			return;
		}
		var deleted = layers[curLayerIdx].name;
		layers.splice(curLayerIdx, 1);
		curLayerIdx  = Std.int(Math.max(0, curLayerIdx - 1));
		curObjectIdx = 0;
		var lay = _curLayer();
		currentAnimData = (lay != null && lay.objects.length > 0) ? lay.objects[0].animations : [];
		_refreshLayerDropdown();
		_syncLayerTabToCurrentLayer();
		_hasUnsaved = true;
		setHelp("✓ Layer deleted: " + deleted, FlxColor.LIME);
	}

	/** Borra el objeto seleccionado de la capa activa. */
	function _deleteCurrentObject():Void
	{
		var lay = _curLayer();
		if (lay == null || lay.objects.length == 0)
		{
			setHelp("⚠ No object selected", FlxColor.YELLOW);
			return;
		}
		if (curObjectIdx < 0 || curObjectIdx >= lay.objects.length) return;
		var deleted = lay.objects[curObjectIdx].name;
		lay.objects.splice(curObjectIdx, 1);
		curObjectIdx = Std.int(Math.max(0, curObjectIdx - 1));
		var obj = _curObject();
		currentAnimData = (obj != null) ? obj.animations : [];
		_refreshLayerDropdown();
		_syncLayerTabToCurrentLayer();
		_hasUnsaved = true;
		setHelp("✓ Object deleted: " + deleted, FlxColor.LIME);
	}

	function _moveLayerUp():Void
	{
		if (!_isV2Format || curLayerIdx <= 0) return;
		var tmp = layers[curLayerIdx];
		layers[curLayerIdx] = layers[curLayerIdx - 1];
		layers[curLayerIdx - 1] = tmp;
		curLayerIdx--;
		_refreshLayerDropdown();
		_hasUnsaved = true;
	}

	function _moveLayerDown():Void
	{
		if (!_isV2Format || curLayerIdx >= layers.length - 1) return;
		var tmp = layers[curLayerIdx];
		layers[curLayerIdx] = layers[curLayerIdx + 1];
		layers[curLayerIdx + 1] = tmp;
		curLayerIdx++;
		_refreshLayerDropdown();
		_hasUnsaved = true;
	}

	/** Mueve el objeto seleccionado hacia arriba dentro de su capa. */
	function _moveObjectUp():Void
	{
		var lay = _curLayer();
		if (lay == null || curObjectIdx <= 0) return;
		var tmp = lay.objects[curObjectIdx];
		lay.objects[curObjectIdx] = lay.objects[curObjectIdx - 1];
		lay.objects[curObjectIdx - 1] = tmp;
		curObjectIdx--;
		_refreshLayerDropdown();
		_hasUnsaved = true;
	}

	/** Mueve el objeto seleccionado hacia abajo dentro de su capa. */
	function _moveObjectDown():Void
	{
		var lay = _curLayer();
		if (lay == null || lay.objects == null || curObjectIdx >= lay.objects.length - 1) return;
		var tmp = lay.objects[curObjectIdx];
		lay.objects[curObjectIdx] = lay.objects[curObjectIdx + 1];
		lay.objects[curObjectIdx + 1] = tmp;
		curObjectIdx++;
		_refreshLayerDropdown();
		_hasUnsaved = true;
	}


	// ── Visual layer panel — buildLayerPanel / refreshLayerPanel ─────────────
	// A fixed-position panel at the BOTTOM of the left panel (above status bar),
	// showing one row per layer exactly like Adobe Animate's timeline layers.
	// ──────────────────────────────────────────────────────────────────────────

	static inline var LP_HEADER_H:Int = 26;
	static inline var LP_PANEL_H:Int  = LP_HEADER_H + LP_ROW_H * LP_MAX_VIS + 4;

	function _lpTopY():Int
	{
		return FlxG.height - 30 - LP_PANEL_H; // 30 = statusBar height
	}

	function buildLayerPanel():Void
	{
		var T = funkin.debug.themes.EditorTheme.current;

		// Solid panel background
		layerPanelBg = new FlxSprite(0, _lpTopY());
		layerPanelBg.makeGraphic(LP_W, LP_PANEL_H, (T.bgPanel & 0x00FFFFFF) | 0xEE000000);
		layerPanelBg.cameras = [camHUD];
		layerPanelBg.scrollFactor.set();
		layerPanelBg.visible = false;
		add(layerPanelBg);

		// Top border of the panel (thin accent line)
		var topBorder = new FlxSprite(0, _lpTopY());
		topBorder.makeGraphic(LP_W, 2, T.accent);
		topBorder.cameras = [camHUD];
		topBorder.scrollFactor.set();
		topBorder.alpha = 0.6;
		add(topBorder);

		layerPanelGroup = new FlxTypedGroup<FlxSprite>();
		layerPanelTexts = new FlxTypedGroup<FlxText>();
		layerPanelGroup.cameras = [camHUD];
		layerPanelTexts.cameras = [camHUD];
		add(layerPanelGroup);
		add(layerPanelTexts);

		// ── Drag ghost row + drop indicator (always on top) ──────────────────
		_lpDragGhost = new FlxSprite(0, 0).makeGraphic(LP_W, LP_ROW_H, 0xCC1155AA);
		_lpDragGhost.cameras = [camHUD];
		_lpDragGhost.scrollFactor.set();
		_lpDragGhost.visible = false;
		add(_lpDragGhost);

		_lpDragGhostTxt = new FlxText(24, 0, LP_W - 30, "", 10);
		_lpDragGhostTxt.setFormat(Paths.font("vcr.ttf"), 10, 0xFFCCDDFF, LEFT);
		_lpDragGhostTxt.cameras = [camHUD];
		_lpDragGhostTxt.scrollFactor.set();
		_lpDragGhostTxt.visible = false;
		add(_lpDragGhostTxt);

		_lpDropLine = new FlxSprite(0, 0).makeGraphic(LP_W, 2, 0xFF44AAFF);
		_lpDropLine.cameras = [camHUD];
		_lpDropLine.scrollFactor.set();
		_lpDropLine.visible = false;
		add(_lpDropLine);

		// ── Inline rename input para capas (doble clic sobre la fila) ───────────
		// Se posiciona sobre la fila activa al activarse, oculto por defecto.
		_lpRenameInput = new CoolInputText(38, 0, 155, '', 10);
		_lpRenameInput.cameras = [camHUD];
		_lpRenameInput.scrollFactor.set();
		_lpRenameInput.visible = false;
		add(_lpRenameInput);

		// ── Inline rename input para animaciones (doble clic en la lista) ────────
		// Se posiciona sobre la fila de animación activa al activarse.
		_animRenameInput = new CoolInputText(10, 0, 270, '', 10);
		_animRenameInput.cameras = [camHUD];
		_animRenameInput.scrollFactor.set();
		_animRenameInput.visible = false;
		add(_animRenameInput);

		refreshLayerPanel();
	}

	function refreshLayerPanel():Void
	{
		if (layerPanelGroup == null) return;

		var T = funkin.debug.themes.EditorTheme.current;

		// ── Clear previous rows ───────────────────────────────────────────────
		for (s in layerPanelGroup.members)
			if (s != null) { remove(s, true); s.destroy(); }
		for (t in layerPanelTexts.members)
			if (t != null) { remove(t, true); t.destroy(); }
		layerPanelGroup.clear();
		layerPanelTexts.clear();
		layerPanelHits = [];

		var isV2 = _isV2Format && layers != null && layers.length > 0;
		layerPanelBg.visible = isV2;
		if (!isV2) return;

		var rowY:Float = _lpTopY();

		// ── Header row ────────────────────────────────────────────────────────
		var hdrBg = new FlxSprite(0, rowY).makeGraphic(LP_W, LP_HEADER_H, T.bgPanelAlt);
		hdrBg.cameras = [camHUD]; hdrBg.scrollFactor.set(); add(hdrBg);
		layerPanelGroup.add(hdrBg);

		var hdrTxt = new FlxText(8, rowY + 5, 0, "\u25A3 LAYERS", 11);
		hdrTxt.setFormat(Paths.font("vcr.ttf"), 11, T.accent, LEFT);
		hdrTxt.cameras = [camHUD]; hdrTxt.scrollFactor.set(); add(hdrTxt);
		layerPanelTexts.add(hdrTxt);

		// Total objects badge
		var totalObjs = 0;
		for (l in layers) if (l.objects != null) totalObjs += l.objects.length;
		var cntTxt = new FlxText(0, rowY + 6, LP_W - 32, layers.length + " layers · " + totalObjs + " obj", 9);
		cntTxt.setFormat(Paths.font("vcr.ttf"), 9, T.textDim, RIGHT);
		cntTxt.cameras = [camHUD]; cntTxt.scrollFactor.set(); add(cntTxt);
		layerPanelTexts.add(cntTxt);

		// [+ Layer] Add-layer button in header
		var addBg = new FlxSprite(LP_W - 26, rowY + 3).makeGraphic(22, 20, T.bgHover);
		addBg.cameras = [camHUD]; addBg.scrollFactor.set(); add(addBg);
		layerPanelGroup.add(addBg);
		var addTxt = new FlxText(LP_W - 26, rowY + 4, 22, "+", 12);
		addTxt.setFormat(Paths.font("vcr.ttf"), 12, T.success, CENTER);
		addTxt.cameras = [camHUD]; addTxt.scrollFactor.set(); add(addTxt);
		layerPanelTexts.add(addTxt);
		layerPanelHits.push({x: LP_W - 26.0, y: rowY + 3, w: 22.0, h: 20.0, zone: "addLayer", idx: -1});

		rowY += LP_HEADER_H;

		// ── Build flat list of rows: layer headers + indented object rows ─────
		// We iterate top→bottom (last layer = top in visual stack, index 0 = bottom)
		var drawnCount = 0;
		var i = layers.length - 1;
		while (i >= 0)
		{
			var layIdx = i;
			var lay    = layers[layIdx];
			var isActiveLay = (layIdx == curLayerIdx);
			var layVis = (lay.visible != false);

			// ── LAYER HEADER ROW ─────────────────────────────────────────────
			if (drawnCount >= layerPanelScroll && drawnCount < layerPanelScroll + LP_MAX_VIS)
			{
				// Eye / visibility toggle
				var eyeSprite = new FlxSprite(2, rowY + 3);
				eyeSprite.loadGraphic(layVis ? Paths.image('editors/visible') : Paths.image('editors/no_visible'));
				eyeSprite.setGraphicSize(18, 18); eyeSprite.updateHitbox();
				eyeSprite.cameras = [camHUD]; eyeSprite.scrollFactor.set(); add(eyeSprite);
				layerPanelGroup.add(eyeSprite);
				layerPanelHits.push({x: 0.0, y: rowY, w: 22.0, h: LP_ROW_H * 1.0, zone: "layerEye", idx: layIdx});

				// × Delete layer button
				var delTxt = new FlxText(LP_W - 36, rowY + 4, 16, "\u00D7", 11);
				delTxt.setFormat(Paths.font("vcr.ttf"), 11, isActiveLay ? T.error : T.textDim, CENTER);
				delTxt.cameras = [camHUD]; delTxt.scrollFactor.set(); add(delTxt);
				layerPanelTexts.add(delTxt);
				layerPanelHits.push({x: LP_W - 38.0, y: rowY, w: 20.0, h: LP_ROW_H * 1.0, zone: "delLayer", idx: layIdx});

				// + Add object button (next to delete)
				var addObjTxt = new FlxText(LP_W - 56, rowY + 4, 16, "+", 12);
				addObjTxt.setFormat(Paths.font("vcr.ttf"), 12, isActiveLay ? T.success : T.textDim, CENTER);
				addObjTxt.cameras = [camHUD]; addObjTxt.scrollFactor.set(); add(addObjTxt);
				layerPanelTexts.add(addObjTxt);
				layerPanelHits.push({x: LP_W - 58.0, y: rowY, w: 20.0, h: LP_ROW_H * 1.0, zone: "addObj", idx: layIdx});

				// Layer row background
				var layColor = isActiveLay ? (T.rowSelected) : (drawnCount % 2 == 0 ? T.rowEven : T.rowOdd);
				// Darken slightly for layer headers vs object rows
				var rowBg = new FlxSprite(0, rowY).makeGraphic(LP_W, LP_ROW_H, layColor);
				rowBg.cameras = [camHUD]; rowBg.scrollFactor.set(); add(rowBg);
				layerPanelGroup.add(rowBg);
				layerPanelHits.push({x: 0.0, y: rowY, w: LP_W * 1.0, h: LP_ROW_H * 1.0, zone: "layerRow", idx: layIdx});

				// Active layer indicator strip
				if (isActiveLay)
				{
					var strip = new FlxSprite(0, rowY).makeGraphic(3, LP_ROW_H, T.accent);
					strip.cameras = [camHUD]; strip.scrollFactor.set(); add(strip);
					layerPanelGroup.add(strip);
				}

				// Layer icon
				var layIcon = new FlxText(22, rowY + 5, 16, "\u25a1", 9);
				layIcon.setFormat(Paths.font("vcr.ttf"), 9, isActiveLay ? T.accent : T.textDim, CENTER);
				layIcon.cameras = [camHUD]; layIcon.scrollFactor.set(); add(layIcon);
				layerPanelTexts.add(layIcon);

				// Layer name
				var nameStr = lay.name ?? ("layer" + layIdx);
				if (nameStr.length > 18) nameStr = nameStr.substr(0, 16) + "..";
				var nameTxt = new FlxText(38, rowY + 5, 155, nameStr, 10);
				nameTxt.setFormat(Paths.font("vcr.ttf"), 10, isActiveLay ? T.accent : T.textPrimary, LEFT);
				nameTxt.bold = true;
				nameTxt.cameras = [camHUD]; nameTxt.scrollFactor.set(); add(nameTxt);
				layerPanelTexts.add(nameTxt);

				// Object count badge
				var objCount = lay.objects != null ? lay.objects.length : 0;
				var countBadge = new FlxText(193, rowY + 5, 60, objCount + " obj", 8);
				countBadge.setFormat(Paths.font("vcr.ttf"), 8, T.textDim, RIGHT);
				countBadge.cameras = [camHUD]; countBadge.scrollFactor.set(); add(countBadge);
				layerPanelTexts.add(countBadge);

				// Drag grip
				var gripTxt = new FlxText(LP_W - 16, rowY + 4, 14, "\u2261", 11);
				gripTxt.setFormat(Paths.font("vcr.ttf"), 11, _lpDragging && _lpDragFromIdx == layIdx ? 0xFF44AAFF : T.textDim, CENTER);
				gripTxt.cameras = [camHUD]; gripTxt.scrollFactor.set(); add(gripTxt);
				layerPanelTexts.add(gripTxt);

				rowY += LP_ROW_H;
			}
			drawnCount++;

			// ── OBJECT ROWS (indented, only visible when layer active or all) ─
			if (lay.objects != null)
			{
				for (oi in 0...lay.objects.length)
				{
					if (drawnCount >= layerPanelScroll && drawnCount < layerPanelScroll + LP_MAX_VIS)
					{
						var obj = lay.objects[oi];
						var isSelObj = isActiveLay && (oi == curObjectIdx);
						var isInactive = !isActiveLay; // objects in other layers are dimmed

						// Object row background (indented)
						var objColor = isSelObj
							? (T.accent & 0x00FFFFFF | 0x55000000)
							: (isInactive ? 0x11FFFFFF : (drawnCount % 2 == 0 ? 0x1AFFFFFF : 0x0AFFFFFF));
						var objBg = new FlxSprite(18, rowY).makeGraphic(LP_W - 18, LP_ROW_H, objColor);
						objBg.cameras = [camHUD]; objBg.scrollFactor.set(); add(objBg);
						layerPanelGroup.add(objBg);
						// Only active layer objects are clickable
						layerPanelHits.push({x: 18.0, y: rowY, w: LP_W - 18.0, h: LP_ROW_H * 1.0,
							zone: isActiveLay ? "objRow" : "objLocked", idx: layIdx * 1000 + oi});

						// Object selected indicator
						if (isSelObj)
						{
							var selStrip = new FlxSprite(18, rowY).makeGraphic(3, LP_ROW_H, T.accent);
							selStrip.cameras = [camHUD]; selStrip.scrollFactor.set(); add(selStrip);
							layerPanelGroup.add(selStrip);
						}

						// Indentation line
						var indentLine = new FlxSprite(18, rowY).makeGraphic(1, LP_ROW_H, isActiveLay ? (T.accent & 0x00FFFFFF | 0x44000000) : 0x22FFFFFF);
						indentLine.cameras = [camHUD]; indentLine.scrollFactor.set(); add(indentLine);
						layerPanelGroup.add(indentLine);

						// ◦ Object icon
						var objIcon = new FlxText(22, rowY + 5, 14, "\u25E6", 8);
						objIcon.setFormat(Paths.font("vcr.ttf"), 8, isSelObj ? T.accent : (isInactive ? T.textDim : 0xFFCCCCCC), CENTER);
						objIcon.cameras = [camHUD]; objIcon.scrollFactor.set(); add(objIcon);
						layerPanelTexts.add(objIcon);

						// Object name
						var oname = obj.name ?? "obj" + oi;
						if (oname.length > 14) oname = oname.substr(0, 12) + "..";
						var oTxt = new FlxText(36, rowY + 5, 130, oname, 9);
						oTxt.setFormat(Paths.font("vcr.ttf"), 9,
							isSelObj ? T.accent : (isInactive ? T.textDim : T.textPrimary), LEFT);
						oTxt.cameras = [camHUD]; oTxt.scrollFactor.set(); add(oTxt);
						layerPanelTexts.add(oTxt);

						// Path badge (short)
						var pathParts = (obj.path ?? "?").split("/");
						var pathBadge = pathParts[pathParts.length - 1];
						if (pathBadge.length > 7) pathBadge = pathBadge.substr(0, 5) + "..";
						var pTxt = new FlxText(168, rowY + 5, 60, pathBadge, 8);
						pTxt.setFormat(Paths.font("vcr.ttf"), 8, isInactive ? 0x33FFFFFF : 0xFF5577AA, RIGHT);
						pTxt.cameras = [camHUD]; pTxt.scrollFactor.set(); add(pTxt);
						layerPanelTexts.add(pTxt);

						// Anim count
						var animCount = obj.animations != null ? obj.animations.length : 0;
						var aTxt = new FlxText(230, rowY + 5, 60, animCount + " anim", 8);
						aTxt.setFormat(Paths.font("vcr.ttf"), 8, isInactive ? 0x33FFFFFF : T.textDim, RIGHT);
						aTxt.cameras = [camHUD]; aTxt.scrollFactor.set(); add(aTxt);
						layerPanelTexts.add(aTxt);

						// × delete object
						var delObjTxt = new FlxText(LP_W - 20, rowY + 5, 14, "\u00D7", 9);
						delObjTxt.setFormat(Paths.font("vcr.ttf"), 9, isSelObj ? T.error : T.textDim, CENTER);
						delObjTxt.cameras = [camHUD]; delObjTxt.scrollFactor.set(); add(delObjTxt);
						layerPanelTexts.add(delObjTxt);
						if (isActiveLay)
							layerPanelHits.push({x: LP_W - 22.0, y: rowY, w: 20.0, h: LP_ROW_H * 1.0, zone: "delObj", idx: layIdx * 1000 + oi});

						// Lock icon on inactive layer objects
						if (isInactive)
						{
							var lockTxt = new FlxText(LP_W - 20, rowY + 5, 14, "\u{1F512}", 8);
							lockTxt.setFormat(Paths.font("vcr.ttf"), 8, 0x33FFFFFF, CENTER);
							lockTxt.cameras = [camHUD]; lockTxt.scrollFactor.set(); add(lockTxt);
							layerPanelTexts.add(lockTxt);
						}

						rowY += LP_ROW_H;
					}
					drawnCount++;
				}
			}

			i--;
		}

		// ── Scroll indicator ──────────────────────────────────────────────────
		var totalRows = drawnCount;
		if (totalRows > LP_MAX_VIS)
		{
			var scrollTxt = new FlxText(0, rowY + 2, LP_W,
				"SCROLL: " + (layerPanelScroll + 1) + "-" + Std.int(Math.min(layerPanelScroll + LP_MAX_VIS, totalRows)) + " / " + totalRows, 8);
			scrollTxt.setFormat(Paths.font("vcr.ttf"), 8, T.textDim, CENTER);
			scrollTxt.cameras = [camHUD]; scrollTxt.scrollFactor.set(); add(scrollTxt);
			layerPanelTexts.add(scrollTxt);
		}
	}

	function _refreshLayerDropdown():Void
	{
		// Visual panel replaces the old dropdown
		refreshLayerPanel();
	}

	// ── Tab: Animation ────────────────────────────────────────────────────────

	function addAnimationTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Animation";

		var yPos = 10;

		var titleLabel = new FlxText(10, yPos, 0, "Add/Edit Animation", 14);
		titleLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(titleLabel);
		yPos += 25;

		tab.add(new FlxText(10, yPos, 0, "Name:", 10));
		yPos += 15;
		animNameInput = new CoolInputText(10, yPos, 200, '', 8);
		tab.add(animNameInput);
		yPos += 25;

		// Para FlxAnimate: este campo es el SN del símbolo
		// Para sprites normales: es el prefix del atlas XML
		tab.add(new FlxText(10, yPos, 0, "Prefix / Symbol SN:", 10));
		yPos += 15;
		animPrefixInput = new CoolInputText(10, yPos, 200, '', 8);
		tab.add(animPrefixInput);

		var prefixHint = new FlxText(10, yPos + 14, 280, "FlxAnimate: name exact of símbol (SN)", 8);
		prefixHint.color = FlxColor.WHITE;
		tab.add(prefixHint);
		yPos += 35;

		// Separador visual para la sección multi-atlas
		var atlasSection = new FlxSprite(10, yPos);
		atlasSection.makeGraphic(290, 1, 0x55FF90D0);
		tab.add(atlasSection);
		var atlasSectionLabel = new FlxText(14, yPos - 1, 0, "─ Multi-Atlas", 8);
		atlasSectionLabel.color = 0xFFFF90D0;
		atlasSectionLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(atlasSectionLabel);
		yPos += 12;

		tab.add(new FlxText(10, yPos, 0, "Framerate:", 10));
		yPos += 15;
		animFramerateStepper = new CoolNumericStepper(10, yPos, 1, 24, 1, 60, 0);
		tab.add(animFramerateStepper);
		yPos += 25;

		animLoopedCheckbox = new CoolCheckBox(10, yPos, null, null, "Looped", 100);
		animLoopedCheckbox.checked = false;
		tab.add(animLoopedCheckbox);

		animFlipXCheckbox = new CoolCheckBox(160, yPos, null, null, "FlipX (anim)", 120);
		animFlipXCheckbox.checked = false;
		tab.add(animFlipXCheckbox);
		yPos += 24;

		// ── Multi-Atlas: Asset Path (opcional) ───────────────────────────────
		// Si se deja vacío, la animación pertenece al atlas principal del personaje.
		// Si se rellena, esta animación se cargará del sub-atlas indicado.
		// Ejemplo: "tankman/bloody" → assets/characters/images/tankman/bloody/
		var atlasLabel = new FlxText(10, yPos, 0, "Sub-Atlas Path:", 10);
		atlasLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(atlasLabel);
		yPos += 14;
		animAssetPathInput = new CoolInputText(10, yPos, 290, '', 8);
		tab.add(animAssetPathInput);
		yPos += 14;
		var atlasHint = new FlxText(10, yPos, 290, "empty = main atlas  |  e.g: tankman/bloody", 8);
		atlasHint.color = FlxColor.fromRGB(100, 180, 255);
		tab.add(atlasHint);
		yPos += 20;

		// ── Render Type (opcional) ────────────────────────────────────────────
		// "animateatlas" para Adobe Animate, "sparrow" para XML atlas.
		// Dejar vacío para que el engine lo detecte automáticamente.
		var rtLabel = new FlxText(10, yPos, 0, "Render Type:", 10);
		rtLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(rtLabel);
		yPos += 14;
		animRenderTypeInput = new CoolInputText(10, yPos, 200, '', 8);
		tab.add(animRenderTypeInput);
		yPos += 14;
		var rtHint = new FlxText(10, yPos, 290, "animateatlas | sparrow | empty=auto", 8);
		rtHint.color = FlxColor.fromRGB(200, 200, 100);
		tab.add(rtHint);
		yPos += 20;

		tab.add(new FlxText(10, yPos, 0, "Offset X:", 10));
		yPos += 15;
		offsetXStepper = new CoolNumericStepper(10, yPos, 1, 0, -500, 500, 0);
		tab.add(offsetXStepper);
		yPos += 25;

		tab.add(new FlxText(10, yPos, 0, "Offset Y:", 10));
		yPos += 15;
		offsetYStepper = new CoolNumericStepper(10, yPos, 1, 0, -500, 500, 0);
		tab.add(offsetYStepper);
		yPos += 30;

		// Botón Add/Update — su label cambia según si estás editando o agregando
		addAnimBtn = new CoolButton(10, yPos, "Add Animation", function()
		{
			addNewAnimation();
		});
		tab.add(addAnimBtn);

		// Botón "New" — limpia los campos y vuelve a modo Add
		tab.add(new CoolButton(130, yPos, "New / Clear", function()
		{
			editingAnimName = null;
			animNameInput.text = "";
			animPrefixInput.text = "";
			animFramerateStepper.value = 24;
			animLoopedCheckbox.checked = false;
			offsetXStepper.value = 0;
			offsetYStepper.value = 0;
			if (animAssetPathInput != null) animAssetPathInput.text = "";
			if (animRenderTypeInput != null) animRenderTypeInput.text = "";
			if (animFlipXCheckbox != null) animFlipXCheckbox.checked = false;
			if (addAnimBtn != null)
				addAnimBtn.label = "Add Animation";
			setHelp("Cleared fields — Add mode", FlxColor.CYAN);
		}));
		yPos += 30;

		tab.add(new CoolButton(10, yPos, "Delete Current", function()
		{
			deleteCurrentAnimation();
		}));
		yPos += 30;

		tab.add(new CoolButton(10, yPos, "← Load Selected", function()
		{
			loadAnimIntoUI();
		}));

		var loadHint = new FlxText(10, yPos + 22, 280, "Load the selected animation (W/S) for editing", 8);
		loadHint.color = FlxColor.WHITE;
		tab.add(loadHint);

		UI_box.addGroup(tab);
	}

	// ── Tab: Properties ───────────────────────────────────────────────────────

	function addPropertiesTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Properties";

		var yPos = 10;

		var titleLabel = new FlxText(10, yPos, 0, "Character Properties", 14);
		titleLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(titleLabel);
		yPos += 25;

		// Path — para FlxAnimate es la carpeta completa, para sprites el nombre del atlas
		tab.add(new FlxText(10, yPos, 0, "Sprite Path / Folder:", 10));
		yPos += 15;
		pathInput = new CoolInputText(10, yPos, 200, 'BOYFRIEND', 8);
		tab.add(pathInput);

		var pathHint = new FlxText(10, yPos + 14, 280, "FlxAnimate: path to the character's folder", 8);
		pathHint.color = FlxColor.WHITE;
		tab.add(pathHint);
		yPos += 35;

		// Spritemap Name — solo relevante para FlxAnimate (por defecto "spritemap1")
		tab.add(new FlxText(10, yPos, 0, "Spritemap Name:", 10));
		yPos += 15;
		spritemapNameInput = new CoolInputText(10, yPos, 200, 'spritemap1', 8);
		tab.add(spritemapNameInput);

		var smHint = new FlxText(10, yPos + 14, 280, "FlxAnimate only · Default: spritemap1", 8);
		smHint.color = FlxColor.WHITE;
		tab.add(smHint);
		yPos += 35;

		// Health Icon
		tab.add(new FlxText(10, yPos, 0, "Health Icon:", 10));
		yPos += 15;
		healthIconInput = new CoolInputText(10, yPos, 200, 'bf', 8);
		healthIconInput.callback = function(text:String, action:String)
		{
			updateIconPreview(text);
		};
		tab.add(healthIconInput);
		yPos += 25;

		// Health Bar Color — campo de texto + swatch clickeable que abre el picker
		tab.add(new FlxText(10, yPos, 0, "Health Bar Color:", 10));
		yPos += 15;
		healthBarColorInput = new CoolInputText(10, yPos, 155, '#31B0D1', 8);
		healthBarColorInput.callback = function(text:String, action:String)
		{
			try
			{
				var parsed = FlxColor.fromString(text);
				currentHealthBarColor = parsed;
				if (hudHealthBar != null)
					hudHealthBar.color = parsed;
			}
			catch (_)
			{
			}
		};
		tab.add(healthBarColorInput);

		// Swatch de color (cuadrado que muestra el color actual)
		// Es un CoolButton sin texto que abre el ColorPickerWheel
		var colorSwatchBtn = new CoolButton(170, yPos - 1, "", function()
		{
			// Parsear el color actual del input para pasárselo al picker
			var startColor = currentHealthBarColor;
			try
			{
				startColor = FlxColor.fromString(healthBarColorInput.text);
			}
			catch (_)
			{
			}

			var picker = new ColorPickerWheel(startColor);
			picker.onColorSelected = function(selectedColor:FlxColor)
			{
				currentHealthBarColor = selectedColor;
				var hex = "#" + selectedColor.toHexString(false, false).toUpperCase();
				healthBarColorInput.text = hex;
				if (hudHealthBar != null)
				{
					hudHealthBar.color = selectedColor;
					// Pequeño bounce en la healthBar del HUD como feedback
					FlxTween.cancelTweensOf(hudHealthBar.scale);
					hudHealthBar.scale.set(1, 1.3);
					FlxTween.tween(hudHealthBar.scale, {x: 1, y: 1}, 0.25, {ease: FlxEase.backOut});
				}
			};
			picker.cameras = [camHUD];
			openSubState(picker);
		});

		// Pintar el botón con el color actual y darle tamaño de swatch
		colorSwatchBtn.resize(28, 20);
		tab.add(colorSwatchBtn);

		var pickBtn = new CoolButton(202, yPos - 1, "Pick", function()
		{
			var startColor = currentHealthBarColor;
			try
			{
				startColor = FlxColor.fromString(healthBarColorInput.text);
			}
			catch (_)
			{
			}

			var picker = new ColorPickerWheel(startColor);
			picker.onColorSelected = function(selectedColor:FlxColor)
			{
				currentHealthBarColor = selectedColor;
				var hex = "#" + selectedColor.toHexString(false, false).toUpperCase();
				healthBarColorInput.text = hex;
				if (hudHealthBar != null)
				{
					hudHealthBar.color = selectedColor;
					FlxTween.cancelTweensOf(hudHealthBar.scale);
					hudHealthBar.scale.set(1, 1.3);
					FlxTween.tween(hudHealthBar.scale, {x: 1, y: 1}, 0.25, {ease: FlxEase.backOut});
				}
				// Actualizar el swatch del botón
				colorSwatchBtn.resize(28, 20);
			};
			picker.cameras = [camHUD];
			openSubState(picker);
		});
		tab.add(pickBtn);
		yPos += 30;

		// Scale
		tab.add(new FlxText(10, yPos, 0, "Scale:", 10));
		yPos += 15;
		scaleStepper = new CoolNumericStepper(10, yPos, 0.1, 1.0, 0.1, 10.0, 1);
		scaleStepper.value = 1.0;
		tab.add(scaleStepper);
		yPos += 30;

		antialiasingCheckbox = new CoolCheckBox(10, yPos, null, null, "Antialiasing", 100);
		antialiasingCheckbox.checked = true;
		tab.add(antialiasingCheckbox);
		yPos += 25;

		// Formato — los tres son mutuamente exclusivos
		isTxtCheckbox = new CoolCheckBox(10, yPos, null, null, "TXT Spritesheet", 150);
		isTxtCheckbox.checked = false;
		isTxtCheckbox.callback = function(_:Bool)
		{
			if (isTxtCheckbox.checked)
			{
				isSpritesheetCheckbox.checked = false;
				isFlxAnimateCheckbox.checked = false;
			}
		};
		tab.add(isTxtCheckbox);
		yPos += 20;

		isSpritesheetCheckbox = new CoolCheckBox(10, yPos, null, null, "Spritesheet JSON", 150);
		isSpritesheetCheckbox.checked = false;
		isSpritesheetCheckbox.callback = function(_:Bool)
		{
			if (isSpritesheetCheckbox.checked)
			{
				isTxtCheckbox.checked = false;
				isFlxAnimateCheckbox.checked = false;
			}
		};
		tab.add(isSpritesheetCheckbox);
		yPos += 20;

		isFlxAnimateCheckbox = new CoolCheckBox(10, yPos, null, null, "FlxAnimate (Adobe Animate)", 200);
		isFlxAnimateCheckbox.checked = false;
		isFlxAnimateCheckbox.callback = function(_:Bool)
		{
			if (isFlxAnimateCheckbox.checked)
			{
				isTxtCheckbox.checked = false;
				isSpritesheetCheckbox.checked = false;
			}
			// Recordatorio visual
			spritemapNameInput.color = isFlxAnimateCheckbox.checked ? FlxColor.ORANGE : FlxColor.WHITE;
		};
		tab.add(isFlxAnimateCheckbox);
		yPos += 30;

		// ── Position Offset ───────────────────────────────────────────────────
		// El offset global del sprite que se SUMA a la posición del stage.
		// Equivalente al campo "position" de Psych Engine y al field nativo de Cool.
		var posOffsetTitle = new FlxText(10, yPos, 0, "Position Offset:", 10);
		tab.add(posOffsetTitle);
		yPos += 15;
		tab.add(new FlxText(10, yPos + 4, 0, "X:", 9));
		posOffsetXStepper = new CoolNumericStepper(22, yPos, 1, 0, -2000, 2000, 0);
		tab.add(posOffsetXStepper);
		tab.add(new FlxText(130, yPos + 4, 0, "Y:", 9));
		posOffsetYStepper = new CoolNumericStepper(142, yPos, 1, 0, -2000, 2000, 0);
		tab.add(posOffsetYStepper);
		yPos += 28;

		// ── Camera Offset ─────────────────────────────────────────────────────
		// Offset de la cámara relativo al personaje (cameraOffset en CharacterData).
		var camOffsetTitle = new FlxText(10, yPos, 0, "Camera Offset:", 10);
		tab.add(camOffsetTitle);
		yPos += 15;
		tab.add(new FlxText(10, yPos + 4, 0, "X:", 9));
		camOffsetXStepper = new CoolNumericStepper(22, yPos, 1, 0, -2000, 2000, 0);
		tab.add(camOffsetXStepper);
		tab.add(new FlxText(130, yPos + 4, 0, "Y:", 9));
		camOffsetYStepper = new CoolNumericStepper(142, yPos, 1, 0, -2000, 2000, 0);
		tab.add(camOffsetYStepper);
		yPos += 28;

		tab.add(new CoolButton(10, yPos, "Apply Properties", function()
		{
			if (char != null)
			{
				char.antialiasing = antialiasingCheckbox.checked;
				char.scale.set(scaleStepper.value, scaleStepper.value);
				char.updateHitbox();
				updateIconPreview(healthIconInput.text);

				// Aplicar positionOffset en vivo: recentrar y sumar el offset
				char.screenCenter();
				if (ghostChar != null) ghostChar.screenCenter();
				if (posOffsetXStepper != null && posOffsetYStepper != null)
				{
					char.x += posOffsetXStepper.value;
					char.y += posOffsetYStepper.value;
					if (ghostChar != null)
					{
						ghostChar.x += posOffsetXStepper.value;
						ghostChar.y += posOffsetYStepper.value;
					}
				}
				// Actualizar cameraOffset en el characterData en memoria
				if (char.characterData != null)
				{
					if (posOffsetXStepper != null && posOffsetYStepper != null)
						char.characterData.positionOffset = [posOffsetXStepper.value, posOffsetYStepper.value];
					if (camOffsetXStepper != null && camOffsetYStepper != null)
						char.characterData.cameraOffset = [camOffsetXStepper.value, camOffsetYStepper.value];
				}
			}
		}));

		UI_box.addGroup(tab);
	}

	// ── Tab: Import ───────────────────────────────────────────────────────────

	function addImportTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Import";

		var yPos = 10;

		var titleLabel = new FlxText(10, yPos, 0, "Import Assets", 14);
		titleLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(titleLabel);
		yPos += 25;

		// ── Standard sprite ──
		var stdLabel = new FlxText(10, yPos, 0, "Standard Sprite:", 12);
		stdLabel.color = FlxColor.CYAN;
		stdLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(stdLabel);
		yPos += 20;

		tab.add(new CoolButton(10, yPos, "Import Sprite PNG", function()
		{
			browseForFile("sprite");
		}));

		tab.add(new FlxText(10, yPos + 22, 280, "Automatically detects XML/TXT", 8));
		yPos += 50;

		// ── FlxAnimate ──
		var flxLabel = new FlxText(10, yPos, 0, "FlxAnimate (Adobe Animate):", 12);
		flxLabel.color = FlxColor.ORANGE;
		flxLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(flxLabel);
		yPos += 20;

		tab.add(new FlxText(10, yPos, 0, "Select the PNG spritemap.\nAutomatically detects spritemap.json and Animation.json\nfrom the same folder.", 9));
		yPos += 40;

		tab.add(new CoolButton(10, yPos, "Import FlxAnimate", function()
		{
			browseForFlxAnimate();
		}));
		yPos += 30;

		// Listar símbolos disponibles en Animation.json
		tab.add(new CoolButton(10, yPos, "List Symbols (Console)", function()
		{
			listAvailableSymbols();
		}));

		var symHint = new FlxText(10, yPos + 22, 280, "Shows the available SNs to use as a 'prefix''", 8);
		symHint.color = FlxColor.WHITE;
		tab.add(symHint);
		yPos += 50;

		// ── Health Icon ──
		var iconTitle = new FlxText(10, yPos, 0, "Health Icon:", 12);
		iconTitle.color = FlxColor.LIME;
		iconTitle.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(iconTitle);
		yPos += 20;

		tab.add(new CoolButton(10, yPos, "Import Icon PNG", function()
		{
			browseForFile("icon");
		}));
		tab.add(new FlxText(10, yPos + 22, 280, "300x150px (2 frames de 150x150)", 9));

		UI_box.addGroup(tab);
	}

	// ── Tab: Export ───────────────────────────────────────────────────────────

	function addExportTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Export";

		var yPos = 10;

		var titleLabel = new FlxText(10, yPos, 0, "Export Character", 14);
		titleLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(titleLabel);
		yPos += 30;

		tab.add(new CoolButton(10, yPos, "Export JSON", function()
		{
			exportCharacterJSON();
		}));
		yPos += 35;
		tab.add(new CoolButton(10, yPos, "Export Offsets TXT", function()
		{
			exportOffsetsTXT();
		}));
		yPos += 35;
		tab.add(new CoolButton(10, yPos, "Copy JSON", function()
		{
			copyJSONToClipboard();
		}));
		yPos += 40;

		// ── Convert V1 → V2 ───────────────────────────────────────────────────
		var sepLine = new FlxSprite(10, yPos);
		sepLine.makeGraphic(295, 1, 0x44AADDFF);
		tab.add(sepLine);
		yPos += 8;

		var convLabel = new FlxText(10, yPos, 295, "Convert V1 → V2 (render.layers)", 10);
		convLabel.color = FlxColor.CYAN;
		convLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(convLabel);
		yPos += 16;

		tab.add(new CoolButton(10, yPos, "Convert to V2 Format", function()
		{
			_convertV1ToV2();
		}));
		yPos += 30;

		tab.add(new FlxText(10, yPos, 280,
			"V2 format uses render.layers — supports\nmulti-sprite characters.\nExisting animations go to a 'body' layer.", 9));

		UI_box.addGroup(tab);
	}

	// ── Lógica de animaciones ─────────────────────────────────────────────────

	function addNewAnimation():Void
	{
		var newName = animNameInput.text.trim();
		var newPrefix = animPrefixInput.text.trim();

		if (newName == "" || newPrefix == "")
		{
			setHelp("✗ Name and prefix are required!", FlxColor.RED);
			return;
		}

		// Guardar estado anterior antes de modificar
		_pushUndo();

		var newAnim:AnimData = {
			name: newName,
			prefix: newPrefix,
			framerate: animFramerateStepper.value,
			looped: animLoopedCheckbox.checked,
			offsets: [offsetXStepper.value, offsetYStepper.value]
		};

		// Sub-atlas path (opcional): solo se guarda si se especificó algo
		var rawAssetPath = animAssetPathInput != null ? animAssetPathInput.text.trim() : "";
		if (rawAssetPath != "")
			newAnim.assetPath = rawAssetPath;

		// Render type (opcional): solo se guarda si no está vacío
		var rawRenderType = animRenderTypeInput != null ? animRenderTypeInput.text.trim().toLowerCase() : "";
		if (rawRenderType == "animateatlas" || rawRenderType == "sparrow")
			newAnim.renderType = rawRenderType;

		// flipX por animacion
		if (animFlipXCheckbox != null)
			newAnim.flipX = animFlipXCheckbox.checked;

		if (editingAnimName != null)
		{
			// ── Modo EDIT: actualizar la animación cuyo nombre original es editingAnimName ──
			var found = false;
			for (i in 0...currentAnimData.length)
			{
				if (currentAnimData[i].name == editingAnimName)
				{
					currentAnimData[i] = newAnim;
					found = true;
					break;
				}
			}

			if (!found)
			{
				// Por si acaso no existía, agregarla
				currentAnimData.push(newAnim);
			}

			reloadCharacterWithNewAnims();
			setHelp("✓ Animation updated: " + newName, FlxColor.LIME);

			// Mantener la selección apuntando a la anim recién editada
			var newIdx = animList.indexOf(newName);
			if (newIdx >= 0)
				curAnim = newIdx;

			// Volver a modo Add
			editingAnimName = null;
			if (addAnimBtn != null)
				addAnimBtn.label = "Add Animation";
		}
		else
		{
			// ── Modo ADD: nunca sobreescribir, error si el nombre ya existe ──
			var alreadyExists = false;
			for (anim in currentAnimData)
			{
				if (anim.name == newName)
				{
					alreadyExists = true;
					break;
				}
			}

			if (alreadyExists)
			{
				setHelp('✗ "' + newName + '" it already exists — use "← Load Selected" to edit it', FlxColor.RED);
				return;
			}

			currentAnimData.push(newAnim);
			reloadCharacterWithNewAnims();
			setHelp("✓ Animation add: " + newName, FlxColor.LIME);
		}

		_hasUnsaved = true;

		// Limpiar campos tras Add (no tras Edit, para comodidad)
		if (editingAnimName == null)
		{
			animNameInput.text = "";
			animPrefixInput.text = "";
		}
	}

	/**
	 * Rellena los campos del tab Animation con los datos de la animación
	 * seleccionada actualmente (curAnim). Así puedes editar cualquier anim
	 * sin tener que escribir todo desde cero.
	 */
	function loadAnimIntoUI():Void
	{
		if (animList.length == 0 || curAnim < 0 || curAnim >= animList.length)
		{
			setHelp("⚠ No animation selected", FlxColor.WHITE);
			return;
		}

		var animName = animList[curAnim];

		for (anim in currentAnimData)
		{
			if (anim.name == animName)
			{
				animNameInput.text = anim.name;
				animPrefixInput.text = anim.prefix != null ? anim.prefix : "";
				animFramerateStepper.value = anim.framerate != 0 ? anim.framerate : 24;
				animLoopedCheckbox.checked = anim.looped;
				offsetXStepper.value = anim.offsets[0];
				offsetYStepper.value = anim.offsets[1];

				// Cargar sub-atlas path y render type (nuevos campos opcionales)
				if (animAssetPathInput != null)
					animAssetPathInput.text = anim.assetPath != null ? anim.assetPath : "";
				if (animRenderTypeInput != null)
					animRenderTypeInput.text = anim.renderType != null ? anim.renderType : "";
				if (animFlipXCheckbox != null)
					animFlipXCheckbox.checked = anim.flipX == true;

				// Entrar en modo EDIT — guardar qué anim estamos modificando
				editingAnimName = animName;
				if (addAnimBtn != null)
					addAnimBtn.label = "Update Anim";

				setHelp('← Editing: $animName  |  "New / Clear" for cancel', FlxColor.CYAN);
				UI_box.selected_tab_id = "Animation";
				return;
			}
		}

		setHelp("⚠ Animation not found in dates", FlxColor.WHITE);
	}

	function deleteCurrentAnimation():Void
	{
		if (animList.length == 0 || curAnim < 0 || curAnim >= animList.length)
			return;

		// Guardar estado anterior antes de borrar
		_pushUndo();

		var animName = animList[curAnim];

		for (i in 0...currentAnimData.length)
		{
			if (currentAnimData[i].name == animName)
			{
				currentAnimData.splice(i, 1);
				break;
			}
		}

		reloadCharacterWithNewAnims();
		setHelp("✓ Animation erased: " + animName, FlxColor.LIME);
		_hasUnsaved = true;

		if (curAnim >= animList.length)
			curAnim = animList.length - 1;
		if (curAnim < 0)
			curAnim = 0;
	}

	// ── Import: Standard sprite ───────────────────────────────────────────────

	function browseForFile(fileType:String):Void
	{
		#if sys
		switch (fileType)
		{
			case "sprite":
				var _fdSpr = new FileDialog();
				_fdSpr.onSelect.add(function(path:String) { onSpriteSelected(path); });
				_fdSpr.browse(OPEN, "png", null, "Select Sprite PNG");
			case "icon":
				var _fdIco = new FileDialog();
				_fdIco.onSelect.add(function(path:String) { onFileSelected(path, "icon"); });
				_fdIco.browse(OPEN, "png", null, "Select Icon PNG");
		}
		#else
		FlxG.log.warn("File import solo disponible en desktop");
		#end
	}

	function onSpriteSelected(sourcePath:String):Void
	{
		#if sys
		try
		{
			var fileName = haxe.io.Path.withoutDirectory(sourcePath);
			var sourceDir = haxe.io.Path.directory(sourcePath) + "/";
			var baseName = haxe.io.Path.withoutExtension(fileName);

			var destDir = Paths.resolveWrite("characters/images/");
			Paths.ensureDir(destDir + "x");  // ensure dir exists

			File.copy(sourcePath, destDir + fileName);

			var xmlPath = sourceDir + baseName + ".xml";
			var txtPath = sourceDir + baseName + ".txt";

			if (FileSystem.exists(xmlPath))
			{
				File.copy(xmlPath, destDir + baseName + ".xml");
				setHelp("✓ PNG + XML importados — abriendo mapper…", FlxColor.LIME);

				// Parse unique prefixes from the XML and open the name mapper
				var rawAnims = _parseXmlPrefixes(destDir + baseName + ".xml");
				if (rawAnims.length > 0)
				{
					openSubState(new AnimMapperSubState(rawAnims, function(mapped:Array<funkin.gameplay.objects.character.Character.AnimData>)
					{
						// Guard: mapper returned empty (all rows deleted by user) — do not wipe existing anims
						if (mapped.length == 0)
						{
							setHelp("⚠ No animations confirmed — keeping existing list", FlxColor.YELLOW);
							return;
						}
						currentAnimData = mapped;
						reloadCharacterWithNewAnims();
						setHelp("✓ PNG + XML importados — " + mapped.length + " animaciones mapeadas", FlxColor.LIME);
					}));
				}
				else
				{
					// XML found but no parseable prefixes (e.g. non-Sparrow format)
					setHelp("⚠ PNG + XML importados — no se detectaron prefijos en el XML", FlxColor.YELLOW);
				}
			}
			else if (FileSystem.exists(txtPath))
			{
				File.copy(txtPath, destDir + baseName + ".txt");
				isTxtCheckbox.checked = true;
				setHelp("✓ PNG + TXT importados", FlxColor.LIME);
			}
			else
			{
				setHelp("⚠ PNG importado (sin XML/TXT)", FlxColor.WHITE);
			}

			pathInput.text = baseName;
		}
		catch (err:Dynamic)
		{
			setHelp("✗ Error: " + err, FlxColor.RED);
		}
		#end
	}

	function onFileSelected(sourcePath:String, fileType:String):Void
	{
		#if sys
		try
		{
			var fileName = haxe.io.Path.withoutDirectory(sourcePath);
			var destDir = (fileType == "icon") ? Paths.resolveWrite("images/icons/") : Paths.resolveWrite("characters/images/");
			var newFileName = fileName;

			Paths.ensureDir(destDir + "x");  // ensure dir exists

			if (fileType == "icon" && healthIconInput != null && healthIconInput.text != "")
			{
				var ext = haxe.io.Path.extension(fileName);
				newFileName = "icon-" + healthIconInput.text + "." + ext;
			}

			File.copy(sourcePath, destDir + newFileName);

			if (fileType == "icon" && healthIconInput != null)
				updateIconPreview(healthIconInput.text);

			setHelp("✓ " + newFileName + " imported!", FlxColor.LIME);
		}
		catch (err:Dynamic)
		{
			setHelp("✗ Error importing: " + err, FlxColor.RED);
		}
		#end
	}

	// ── Import: FlxAnimate ────────────────────────────────────────────────────

	/**
	 * Abre un FileDialog para seleccionar el PNG del spritemap.
	 * Detecta automáticamente el JSON del atlas y el Animation.json
	 * de la misma carpeta, y los copia todos a assets/images/<daAnim>/
	 */
	function browseForFlxAnimate():Void
	{
		#if sys
		var _fdAnim = new FileDialog();
		_fdAnim.onSelect.add(function(path:String) { onFlxAnimateSelected(path); });
		_fdAnim.browse(OPEN, "png", null, "Select Spritemap PNG (FlxAnimate)");
		#else
		FlxG.log.warn("File import only available on desktop");
		#end
	}

	function onFlxAnimateSelected(sourcePngPath:String):Void
	{
		#if sys
		try
		{
			var fileName = haxe.io.Path.withoutDirectory(sourcePngPath);
			var sourceDir = haxe.io.Path.directory(sourcePngPath) + "/";
			var baseName = haxe.io.Path.withoutExtension(fileName); // ej: "spritemap1"

			// Rutas que esperamos encontrar junto al PNG
			var atlasJsonSrc = sourceDir + baseName + ".json"; // spritemap1.json
			var animJsonSrc = sourceDir + "Animation.json";

			if (!FileSystem.exists(atlasJsonSrc))
			{
				setHelp("✗ Not found " + baseName + ".json next to PNG", FlxColor.RED);
				return;
			}

			// Destino: {root}/characters/images/<daAnim>/
			var destFolder = Paths.resolveWrite('characters/images/$daAnim/');
			Paths.ensureDir(destFolder + "x");  // ensure dir exists

			// Copiar los tres archivos
			File.copy(sourcePngPath, destFolder + fileName);
			FlxG.log.notice("Copied: " + destFolder + fileName);

			File.copy(atlasJsonSrc, destFolder + baseName + ".json");
			FlxG.log.notice("Copied: " + destFolder + baseName + ".json");

			var hasAnimJson = FileSystem.exists(animJsonSrc);
			if (hasAnimJson)
			{
				File.copy(animJsonSrc, destFolder + "Animation.json");
				FlxG.log.notice("Copied: " + destFolder + "Animation.json");
			}

			// Actualizar UI:
			// - path = nombre del personaje (ej: "myChar"), NO la ruta completa
			//   Character.hx lo convierte con Paths.characterFolder(path)
			// - spritemapName = nombre del PNG sin extensión (ej: "spritemap1")
			flxAnimateFolderPath = destFolder;
			pathInput.text = daAnim; // ← solo el nombre del personaje
			spritemapNameInput.text = baseName;
			isFlxAnimateCheckbox.checked = true;
			isTxtCheckbox.checked = false;
			isSpritesheetCheckbox.checked = false;

			// Si hay Animation.json, parsear símbolos y abrir el mapper de nombres
			if (hasAnimJson)
			{
				var rawAnims = _parseAnimJsonSymbols(destFolder + "Animation.json");
				if (rawAnims.length > 0)
				{
					setHelp("✓ FlxAnimate importado — abriendo mapper de símbolos…", FlxColor.LIME);
					openSubState(new AnimMapperSubState(rawAnims, function(mapped:Array<funkin.gameplay.objects.character.Character.AnimData>)
					{
						// Guard: mapper returned empty (all rows deleted by user) — do not wipe existing anims
						if (mapped.length == 0)
						{
							setHelp("⚠ No symbols confirmed — keeping existing animation list", FlxColor.YELLOW);
							return;
						}
						currentAnimData = mapped;
						reloadCharacterWithNewAnims();
						setHelp("✓ FlxAnimate importado — " + mapped.length + " símbolos mapeados", FlxColor.LIME);
					}));
				}
				else
				{
					loadAnimationsFromAnimationJson(destFolder + "Animation.json");
					setHelp("✓ FlxAnimate importado en " + destFolder, FlxColor.LIME);
				}
			}
			else
			{
				setHelp("✓ FlxAnimate importado\n⚠ Sin Animation.json — añade animaciones manualmente", FlxColor.WHITE);
			}
		}
		catch (err:Dynamic)
		{
			setHelp("✗ Error: " + err, FlxColor.RED);
		}
		#end
	}

	/**
	 * Lee el Animation.json y auto-genera currentAnimData con todos los
	 * símbolos del Symbol Dictionary (SD.S) como animaciones.
	 * El 'prefix' de cada animación = SN del símbolo.
	 */
	function loadAnimationsFromAnimationJson(animJsonPath:String):Void
	{
		#if sys
		try
		{
			var content = File.getContent(animJsonPath);
			var parsed:Dynamic = Json.parse(content);

			currentAnimData = [];

			// Registrar la animación principal (AN)
			if (parsed.AN != null)
			{
				currentAnimData.push({
					name: parsed.AN.SN,
					prefix: parsed.AN.SN,
					framerate: parsed.MD != null ? Std.int(parsed.MD.FRT) : 24,
					looped: true,
					offsets: [0, 0]
				});
			}

			// Registrar todos los símbolos del diccionario
			if (parsed.SD != null && parsed.SD.S != null)
			{
				for (sym in (cast parsed.SD.S : Array<Dynamic>))
				{
					currentAnimData.push({
						name: sym.SN,
						prefix: sym.SN,
						framerate: parsed.MD != null ? Std.int(parsed.MD.FRT) : 24,
						looped: false,
						offsets: [0, 0]
					});
				}
			}

			FlxG.log.notice('[CharacterEditor] Loaded ' + currentAnimData.length + ' simbols of Animation.json');
			reloadCharacterWithNewAnims();
		}
		catch (e:Dynamic)
		{
			FlxG.log.error('[CharacterEditor] Error reading Animation.json: ' + e);
			setHelp("✗ Error reading Animation.json: " + e, FlxColor.RED);
		}
		#end
	}

	/**
	 * Lista en consola todos los símbolos (SN) disponibles en el Animation.json
	 * del personaje actual. Útil para saber qué poner como "prefix" en cada animación.
	 */
	function listAvailableSymbols():Void
	{
		// Fallback: parsear Animation.json directamente
		#if sys
		var animJsonPath = flxAnimateFolderPath != "" ? flxAnimateFolderPath + "Animation.json" : Paths.characterFolder(pathInput.text) + "Animation.json";

		if (!FileSystem.exists(animJsonPath))
		{
			setHelp("⚠ Not found Animation.json in: " + animJsonPath, FlxColor.WHITE);
			return;
		}

		try
		{
			var content = File.getContent(animJsonPath);
			var parsed:Dynamic = Json.parse(content);

			trace("═══════════════════════════════════════════");
			trace("  SÍMBOLOS DISPONIBLES EN Animation.json");
			trace("  (usa el SN como 'prefix' en tus anims)");
			trace("═══════════════════════════════════════════");
			if (parsed.AN != null)
				trace("  [AN] " + parsed.AN.SN + "  ← Animación principal");

			if (parsed.SD != null && parsed.SD.S != null)
			{
				trace("  [SD] Símbols of diccionary:");
				for (sym in (cast parsed.SD.S : Array<Dynamic>))
					trace("    - " + sym.SN);
			}
			else
				trace("  (No Symbol Dictionary)");

			trace("═══════════════════════════════════════════");
			setHelp("✓ Símbols listed in console", FlxColor.LIME);
		}
		catch (e:Dynamic)
		{
			setHelp("✗ Error reading Animation.json: " + e, FlxColor.RED);
		}
		#else
		setHelp("⚠ Only available in desktop", FlxColor.RED);
		#end
	}

	// ── Character display ─────────────────────────────────────────────────────

	function displayCharacter(character:String):Void
	{
		// Al cambiar de personaje, cancelar cualquier edición pendiente
		editingAnimName = null;
		ghostAnimIdx = 0;
		_animListScroll = 0; // reset scroll so the list starts from the top
		if (addAnimBtn != null)
			addAnimBtn.label = "Add Animation";

		// FIX: cancelar tweens y destruir antes de limpiar para evitar tween-leaks.
		// Iterar en reversa para no alterar índices al hacer remove.
		var i = dumbTexts.members.length - 1;
		while (i >= 0)
		{
			var m = dumbTexts.members[i];
			if (m != null) { FlxTween.cancelTweensOf(m); m.destroy(); }
			i--;
		}
		dumbTexts.clear();
		// Limpiar caches de referencias — ya fueron destruidos arriba
		_offsetLabels.resize(0);
		_ghostBadgeBgs.resize(0);
		_ghostBadgeLabels.resize(0);
		_rowBgs.resize(0);
		animList = [];

		// FIX: destroy() libera la textura de VRAM; remove() solo quita del grupo.
		if (char != null)
		{
			layeringbullshit.remove(char, true);
			char.destroy();
			char = null;
		}
		if (ghostChar != null)
		{
			layeringbullshit.remove(ghostChar, true);
			ghostChar.destroy();
			ghostChar = null;
		}

		ghostChar = new Character(0, 0, character);
		ghostChar.alpha = 0.5;
		ghostChar.screenCenter();
		ghostChar.debugMode = false; // ghost never shows hitbox
		layeringbullshit.add(ghostChar);

		char = new Character(0, 0, character);
		char.screenCenter();
		char.debugMode = false; // controlled by _hasSelection via _updateSelectionVisuals()
		layeringbullshit.add(char);
		// NO sobreescribir flipX aquí — Character.hx ya lo aplica desde el JSON.
		// loadCharacterData() actualizará el checkbox y sincronizará tras esto.

		// Aplicar positionOffset al preview (igual que en PlayState)
		if (char.characterData != null)
		{
			final posOff = char.characterData.positionOffset;
			if (posOff != null && posOff.length >= 2)
			{
				char.x += posOff[0];
				char.y += posOff[1];
				if (ghostChar != null)
				{
					ghostChar.x += posOff[0];
					ghostChar.y += posOff[1];
				}
			}
		}

		// Actualizar header con el nombre del personaje
		if (charHeaderText != null)
		{
			charHeaderText.text = "  CHARACTER EDITOR";
			// Pequeño bounce en el header
			FlxTween.cancelTweensOf(charHeaderText);
			charHeaderText.alpha = 0;
			FlxTween.tween(charHeaderText, {alpha: 1}, 0.3, {ease: FlxEase.quartOut});
		}

		generateOffsetTexts();

		// By default the first layer/character is always selected when loaded.
		_hasSelection = true;
	}

	function generateOffsetTexts(pushList:Bool = true):Void
	{
		var daLoop   = 0; // absolute animation index
		var visRow   = 0; // row actually drawn on screen (0-based)
		var startY   = 174;
		var rowH     = 20;

		// How far down can we draw before hitting the layer panel (or status bar)?
		var bottomLimit = (_isV2Format && _lpTopY != null) ? _lpTopY() : (FlxG.height - 30);
		var maxVisRows  = Std.int((bottomLimit - startY) / rowH);
		if (maxVisRows < 1) maxVisRows = 1;

		// ── Build iteration list ──────────────────────────────────────────────
		// V2: show only the selected object's animations (fully independent per-object list).
		// V1: show all animations from char.animOffsets (legacy behaviour).
		var _iterList:Array<{name:String, offsets:Array<Float>}> = [];
		var _animSrc = _isV2Format ? currentAnimData : null;
		if (_isV2Format && _animSrc != null && _animSrc.length > 0)
		{
			for (_ad in currentAnimData)
			{
				var _offs:Array<Float> = char.animOffsets.exists(_ad.name)
					? cast char.animOffsets.get(_ad.name)
					: (_ad.offsets != null ? cast _ad.offsets : [0.0, 0.0]);
				_iterList.push({name: _ad.name, offsets: _offs});
			}
		}
		else
		{
			for (_an => _of in char.animOffsets)
				_iterList.push({name: _an, offsets: cast _of});
		}

		// Count total anims first (needed to clamp scroll)
		var totalAnimCount = _iterList.length;
		_animListScroll = Std.int(FlxMath.bound(_animListScroll, 0, Math.max(0, totalAnimCount - maxVisRows)));

		for (_entry in _iterList)
		{
			var anim    = _entry.name;
			var offsets = _entry.offsets;

			if (pushList)
				animList.push(anim);

			// Skip rows that are above the current scroll offset
			if (daLoop < _animListScroll) { daLoop++; continue; }
			// Stop once the visible area is full
			if (visRow >= maxVisRows)     { daLoop++; continue; }

			var rowY = startY + (rowH * visRow);
			var isCur = (daLoop == curAnim);

			// Fondo de fila alternado
			var rowBg = new FlxSprite(4, rowY);
			rowBg.makeGraphic(332, rowH - 1, isCur ? 0x5500E5FF : (visRow % 2 == 0 ? 0x22FFFFFF : 0x11FFFFFF));
			rowBg.scrollFactor.set();
			rowBg.cameras = [camHUD];
			rowBg.alpha = 0;
			dumbTexts.add(cast rowBg);
			_rowBgs.push(rowBg);
			FlxTween.tween(rowBg, {alpha: 1}, 0.2, {startDelay: visRow * 0.03, ease: FlxEase.quartOut});

			// Punto de color a la izquierda para la fila activa
			if (isCur)
			{
				var dot = new FlxSprite(4, rowY);
				dot.makeGraphic(4, rowH - 1, 0xFF00E5FF);
				dot.scrollFactor.set();
				dot.cameras = [camHUD];
				dumbTexts.add(cast dot);
			}

			// Buscar si esta animación tiene sub-atlas propio para mostrar indicador ◈
			var animAssetTag = "";
			for (ad in currentAnimData)
			{
				if (ad.name == anim && ad.assetPath != null && ad.assetPath != "")
				{
					var parts = ad.assetPath.split("/");
					animAssetTag = " ◈" + parts[parts.length - 1];
					break;
				}
			}
			var label = anim + animAssetTag + "  [" + offsets[0] + ", " + offsets[1] + "]";
			var text = new FlxText(10, rowY + 3, 295, label, 11);
			text.scrollFactor.set();
			text.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
			var hasCustomAtlas = animAssetTag != "";
			if (isCur)
				text.color = 0xFF00E5FF;
			else if (hasCustomAtlas)
				text.color = 0xFFFF90D0;
			else
				text.color = 0xFFCCCCCC;
			text.cameras = [camHUD];
			text.alpha = 0;
			dumbTexts.add(text);
			_offsetLabels.push(text); // guardar referencia para updates in-place
			FlxTween.tween(text, {alpha: 1}, 0.2, {startDelay: visRow * 0.03 + 0.05, ease: FlxEase.quartOut});

			var isGhostRow = (daLoop == ghostAnimIdx);
			var ghostBadgeBg = new FlxSprite(308, rowY);
			ghostBadgeBg.makeGraphic(28, rowH - 1, isGhostRow ? 0xCC7744CC : 0x33FFFFFF);
			ghostBadgeBg.scrollFactor.set();
			ghostBadgeBg.cameras = [camHUD];
			ghostBadgeBg.alpha = 0;
			dumbTexts.add(cast ghostBadgeBg);
			_ghostBadgeBgs.push(ghostBadgeBg);
			FlxTween.tween(ghostBadgeBg, {alpha: 1}, 0.2, {startDelay: visRow * 0.03, ease: FlxEase.quartOut});

			var ghostLabel = new FlxText(308, rowY + 3, 28, "[G]", 10);
			ghostLabel.scrollFactor.set();
			ghostLabel.alignment = CENTER;
			ghostLabel.color = isGhostRow ? 0xFFFFFFFF : 0x88FFFFFF;
			ghostLabel.cameras = [camHUD];
			ghostLabel.alpha = 0;
			dumbTexts.add(ghostLabel);
			_ghostBadgeLabels.push(ghostLabel);
			FlxTween.tween(ghostLabel, {alpha: 1}, 0.2, {startDelay: visRow * 0.03 + 0.05, ease: FlxEase.quartOut});

			daLoop++;
			visRow++;
		}

		// ── Scroll indicator (shown when list is taller than visible area) ──────
		if (totalAnimCount > maxVisRows)
		{
			var scrollHint = new FlxText(4, startY + maxVisRows * rowH - rowH + 4, 332, 
				"▲ " + _animListScroll + "  SCROLL  " + (totalAnimCount - maxVisRows - _animListScroll) + " ▼", 9);
			scrollHint.scrollFactor.set();
			scrollHint.cameras = [camHUD];
			scrollHint.alignment = CENTER;
			scrollHint.color = 0x88AADDFF;
			scrollHint.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF000000, 1);
			dumbTexts.add(scrollHint);
			// Not pushed to _offsetLabels — it's decorative only
		}

		// Mover el highlight a la posición correcta (visible row of curAnim)
		if (animRowHighlight != null)
		{
			var visIdx = curAnim - _animListScroll;
			if (visIdx >= 0 && visIdx < maxVisRows)
			{
				animRowHighlight.y = startY + (rowH * visIdx);
				animRowHighlight.visible = animList.length > 0;
			}
			else
			{
				animRowHighlight.visible = false; // current anim is scrolled out of view
			}
		}
	}

	function updateOffsetTexts():Void
	{
		// FIX: En lugar de destruir y recrear todos los objetos cada vez que
		// cambia un offset (incluyendo cada frame del drag), actualizamos solo
		// el texto de los labels ya existentes. Esto elimina la principal fuente
		// de memory leak (antes: ~75 objetos + tweens nuevos por frame durante drag).
		var daLoop = 0;
		// ── Build iteration list (same logic as generateOffsetTexts) ─────────
		var _iterList2:Array<{name:String, offsets:Array<Float>}> = [];
		if (_isV2Format && currentAnimData != null && currentAnimData.length > 0)
		{
			for (_ad2 in currentAnimData)
			{
				var _of2:Array<Float> = char.animOffsets.exists(_ad2.name)
					? cast char.animOffsets.get(_ad2.name)
					: (_ad2.offsets != null ? cast _ad2.offsets : [0.0, 0.0]);
				_iterList2.push({name: _ad2.name, offsets: _of2});
			}
		}
		else
		{
			for (_an2 => _of2b in char.animOffsets)
				_iterList2.push({name: _an2, offsets: cast _of2b});
		}

		for (_e2 in _iterList2)
		{
			var anim    = _e2.name;
			var offsets = _e2.offsets;

			// Skip animations that are scrolled out of view at the top
			if (daLoop < _animListScroll) { daLoop++; continue; }

			// visIdx is the position within _offsetLabels/_ghostBadgeLabels
			var visIdx = daLoop - _animListScroll;
			if (visIdx >= _offsetLabels.length) { daLoop++; continue; }

			// Actualizar label de offset
			var animAssetTag = "";
			for (ad in currentAnimData)
			{
				if (ad.name == anim && ad.assetPath != null && ad.assetPath != "")
				{
					var parts = ad.assetPath.split("/");
					animAssetTag = " ◈" + parts[parts.length - 1];
					break;
				}
			}
			var isCur = (daLoop == curAnim);
			var hasCustomAtlas = animAssetTag != "";
			_offsetLabels[visIdx].text = anim + animAssetTag + "  [" + offsets[0] + ", " + offsets[1] + "]";
			if (isCur)
				_offsetLabels[visIdx].color = 0xFF00E5FF;
			else if (hasCustomAtlas)
				_offsetLabels[visIdx].color = 0xFFFF90D0;
			else
				_offsetLabels[visIdx].color = 0xFFCCCCCC;

			// Actualizar badge [G] del ghost
			if (visIdx < _ghostBadgeLabels.length)
				_ghostBadgeLabels[visIdx].color = (daLoop == ghostAnimIdx) ? 0xFFFFFFFF : 0x88FFFFFF;

			daLoop++;
		}

		// Mover el highlight a la nueva posición (visible row of curAnim)
		if (animRowHighlight != null && animList.length > 0)
		{
			var visIdx = curAnim - _animListScroll;
			if (visIdx >= 0 && visIdx < _offsetLabels.length)
			{
				animRowHighlight.y = 174.0 + (20.0 * visIdx);
				animRowHighlight.visible = true;
			}
			else
			{
				animRowHighlight.visible = false;
			}
		}
	}

	// ── loadCharacterData — carga el JSON del personaje en la UI ──────────────

	function loadCharacterData():Void
	{
		try
		{
			var jsonPath = Paths.characterJSON(daAnim);
			var content:String;

			#if sys
			if (FileSystem.exists(jsonPath))
				content = File.getContent(jsonPath);
			else
				content = lime.utils.Assets.getText(jsonPath);
			#else
			content = lime.utils.Assets.getText(jsonPath);
			#end

			var parsed:Dynamic = Json.parse(content);

			// ── Detectar formato: V2 tiene "render" con "layers" ─────────────────
			_isV2Format = parsed.render != null && parsed.render.layers != null;

			if (_isV2Format)
				_loadCharacterDataV2(parsed);
			else
			{
				characterData = cast parsed;
				_loadCharacterDataV1();
			}
		}
		catch (e:Dynamic)
		{
			trace('[CharacterEditor] No data found for: ' + daAnim);
			currentAnimData = [];
		}
	}

	/** Carga el formato antiguo (V1) — campo plano "animations". */
	function _loadCharacterDataV1():Void
	{
		layers = [];
		_isV2Format = false;

		// Mostrar/ocultar dropdown de capas
		_setLayerDropdownVisible(false);

		if (pathInput != null)          pathInput.text = characterData.path;
		if (scaleStepper != null)       scaleStepper.value = characterData.scale;
		if (antialiasingCheckbox != null) antialiasingCheckbox.checked = characterData.antialiasing;
		if (playerCheckbox != null)     playerCheckbox.checked = characterData.isPlayer;

		if (charFlipXCheckbox != null)
		{
			var fx = characterData.flipX != null ? characterData.flipX : false;
			charFlipXCheckbox.checked = fx;
			if (char != null)      char.flipX      = fx;
			if (ghostChar != null) ghostChar.flipX = fx;
		}

		if (charDeathInput != null)
			charDeathInput.text = characterData.charDeath != null ? characterData.charDeath : "";

		if (isTxtCheckbox != null)
			isTxtCheckbox.checked = characterData.isTxt != null ? characterData.isTxt : false;

		if (isSpritesheetCheckbox != null)
			isSpritesheetCheckbox.checked = characterData.isSpritemap != null ? characterData.isSpritemap : false;

		var usingFlxAnimate = characterData.isFlxAnimate != null ? characterData.isFlxAnimate : false;
		if (isFlxAnimateCheckbox != null)
			isFlxAnimateCheckbox.checked = usingFlxAnimate;

		if (spritemapNameInput != null)
		{
			spritemapNameInput.text = (characterData.spritemapName != null && characterData.spritemapName != "") ? characterData.spritemapName : "spritemap1";
			spritemapNameInput.color = usingFlxAnimate ? FlxColor.YELLOW : FlxColor.WHITE;
		}

		if (healthIconInput != null)
		{
			healthIconInput.text = characterData.healthIcon != null ? characterData.healthIcon : daAnim;
			updateIconPreview(healthIconInput.text);
		}

		if (healthBarColorInput != null)
		{
			var colorStr = characterData.healthBarColor != null ? characterData.healthBarColor : "#31B0D1";
			healthBarColorInput.text = colorStr;
			try
			{
				currentHealthBarColor = FlxColor.fromString(colorStr);
				if (hudHealthBar != null)
					hudHealthBar.color = currentHealthBarColor;
			}
			catch (_) {}
		}

		// ── Game Over fields ────────────────────────────────────────────────────
		if (gameOverSoundInput != null) gameOverSoundInput.text = characterData.gameOverSound ?? '';
		if (gameOverMusicInput != null) gameOverMusicInput.text = characterData.gameOverMusic ?? '';
		if (gameOverEndInput != null)   gameOverEndInput.text   = characterData.gameOverEnd   ?? '';
		if (gameOverBpmStepper != null) gameOverBpmStepper.value = characterData.gameOverBpm ?? 100;
		if (gameOverCamFrameStepper != null) gameOverCamFrameStepper.value = characterData.gameOverCamFrame ?? 12;

		// ── Position / Camera Offset ──────────────────────────────────────────
		if (posOffsetXStepper != null && posOffsetYStepper != null)
		{
			var posOff = characterData.positionOffset;
			posOffsetXStepper.value = (posOff != null && posOff.length > 0) ? posOff[0] : 0;
			posOffsetYStepper.value = (posOff != null && posOff.length > 1) ? posOff[1] : 0;
		}
		if (camOffsetXStepper != null && camOffsetYStepper != null)
		{
			var camOff = characterData.cameraOffset;
			camOffsetXStepper.value = (camOff != null && camOff.length > 0) ? camOff[0] : 0;
			camOffsetYStepper.value = (camOff != null && camOff.length > 1) ? camOff[1] : 0;
		}

		currentAnimData = characterData.animations;

		if (usingFlxAnimate)
			flxAnimateFolderPath = Paths.characterFolder(characterData.path);

		// ── Auto-wrap V1 como una sola capa "body" con un objeto ─────────────
		var bodyObj:LayerObjectData = {
			name:         "body",
			path:         pathInput != null ? pathInput.text : (characterData.path != null ? characterData.path : "BOYFRIEND"),
			position:     [
				posOffsetXStepper != null ? posOffsetXStepper.value : 0.0,
				posOffsetYStepper != null ? posOffsetYStepper.value : 0.0
			],
			scale:        [
				scaleStepper != null ? scaleStepper.value : 1.0,
				scaleStepper != null ? scaleStepper.value : 1.0
			],
			alpha:        1.0,
			visible:      true,
			flipX:        charFlipXCheckbox != null ? charFlipXCheckbox.checked : false,
			flipY:        false,
			antialiasing: antialiasingCheckbox != null ? antialiasingCheckbox.checked : true,
			animations:   currentAnimData.copy()
		};
		var bodyLayer:LayerData = {
			name:    "character",
			visible: true,
			objects: [bodyObj]
		};
		layers = [bodyLayer];
		curLayerIdx  = 0;
		curObjectIdx = 0;
		_isV2Format  = true;
		currentAnimData = bodyObj.animations;
		_setLayerDropdownVisible(true);
		_refreshLayerDropdown();
		_syncLayerTabToCurrentLayer();
		_rebuildAnimListDisplay(); // FIX: reconstruir lista con orden correcto
	}

	/** Carga el nuevo formato V2 (render.layers). */
	function _loadCharacterDataV2(parsed:Dynamic):Void
	{
		_isV2Format = true;

		// ── meta ───────────────────────────────────────────────────────────────
		var meta:Dynamic = parsed.meta;
		if (playerCheckbox != null && meta != null)
			playerCheckbox.checked = meta.isPlayer == true;

		// ── gameplay ──────────────────────────────────────────────────────────
		var gp:Dynamic = parsed.gameplay;
		if (gp != null)
		{
			if (posOffsetXStepper != null && gp.position != null && gp.position.length >= 2)
			{
				posOffsetXStepper.value = gp.position[0];
				posOffsetYStepper.value = gp.position[1];
			}
			if (camOffsetXStepper != null && gp.cameraOffset != null && gp.cameraOffset.length >= 2)
			{
				camOffsetXStepper.value = gp.cameraOffset[0];
				camOffsetYStepper.value = gp.cameraOffset[1];
			}
			if (idleAfterSingCheckbox != null)
				idleAfterSingCheckbox.checked = gp.idleAfterSing != false; // default true

			// ── death ──────────────────────────────────────────────────────────
			var death:Dynamic = gp.death;
			if (death != null)
			{
				if (charDeathInput != null)    charDeathInput.text    = death.character ?? '';
				if (gameOverSoundInput != null) gameOverSoundInput.text = death.sound    ?? '';
				if (gameOverEndInput != null)   gameOverEndInput.text   = death.endAnim  ?? '';
			}
		}

		// ── render.layers ─────────────────────────────────────────────────────
		var renderLayers:Array<Dynamic> = parsed.render.layers;
		layers = [];
		for (rawLayer in renderLayers)
		{
			var layObjs:Array<LayerObjectData> = [];

			// New format: layer has "objects" array
			if (rawLayer.objects != null)
			{
				for (rawObj in (cast rawLayer.objects : Array<Dynamic>))
				{
					var lo:LayerObjectData = {
						name:         rawObj.name        ?? 'object',
						path:         rawObj.path        ?? '',
						position:     rawObj.position    != null ? rawObj.position    : [0.0, 0.0],
						scale:        rawObj.scale       != null ? rawObj.scale       : [1.0, 1.0],
						alpha:        rawObj.alpha       != null ? rawObj.alpha       : 1.0,
						visible:      rawObj.visible     != false,
						flipX:        rawObj.flipX       == true,
						flipY:        rawObj.flipY       == true,
						antialiasing: rawObj.antialiasing != false,
						animations:   rawObj.animations  != null ? cast rawObj.animations : []
					};
					layObjs.push(lo);
				}
			}
			else
			{
				// Backwards compat: old V2 stored object props directly in layer
				var lo:LayerObjectData = {
					name:         rawLayer.name        ?? 'body',
					path:         rawLayer.path        ?? '',
					position:     rawLayer.position    != null ? rawLayer.position    : [0.0, 0.0],
					scale:        rawLayer.scale       != null ? rawLayer.scale       : [1.0, 1.0],
					alpha:        rawLayer.alpha       != null ? rawLayer.alpha       : 1.0,
					visible:      rawLayer.visible     != false,
					flipX:        rawLayer.flipX       == true,
					flipY:        rawLayer.flipY       == true,
					antialiasing: rawLayer.antialiasing != false,
					animations:   rawLayer.animations  != null ? cast rawLayer.animations : []
				};
				layObjs.push(lo);
			}

			var ld:LayerData = {
				name:    rawLayer.name    ?? 'layer',
				visible: rawLayer.visible != false,
				objects: layObjs
			};
			layers.push(ld);
		}

		// Seleccionar primera capa + primer objeto por defecto
		curLayerIdx  = 0;
		curObjectIdx = 0;
		var firstObj = _curObject();
		currentAnimData = (firstObj != null) ? firstObj.animations : [];

		// Mostrar dropdown y rellenarlo
		_setLayerDropdownVisible(true);
		_refreshLayerDropdown();
		_syncLayerTabToCurrentLayer();

		// ── icon ──────────────────────────────────────────────────────────────
		var ic:Dynamic = parsed.icon;
		if (ic != null && healthIconInput != null)
		{
			healthIconInput.text = ic.path ?? daAnim;
			updateIconPreview(healthIconInput.text);
		}

		// Rellenar pathInput con la ruta del primer objeto de la primera capa (para Properties)
		if (pathInput != null && layers.length > 0 && layers[0].objects != null && layers[0].objects.length > 0)
			pathInput.text = layers[0].objects[0].path;

		setHelp("✓ V2 format loaded — " + layers.length + " layer(s)", FlxColor.CYAN);
		_rebuildAnimListDisplay(); // FIX: reconstruir lista con orden correcto
	}


	// ── Context Menu (right-click estilo Blender) ─────────────────────────────

	function _buildContextMenu():Void
	{
		var items:Array<{icon:String, label:String, action:Void->Void}> = [
			{ icon: "▣", label: "Create Object  (makeGraphic)", action: _ctxCreateObject },
			{ icon: "⬚", label: "Import Image",                 action: _ctxImportImage  },
			{ icon: "▦", label: "Import Spritesheet",           action: _ctxImportSpritesheet },
			{ icon: "◈", label: "Import Atlas  (XML/JSON)",     action: _ctxImportAtlas  }
		];

		var totalH = CTX_HH + items.length * CTX_IH + 6;

		_ctxBorder = new FlxSprite(0, 0);
		_ctxBorder.makeGraphic(CTX_W + 4, totalH + 4, 0xBB000000);
		_ctxBorder.cameras = [camHUD];
		_ctxBorder.scrollFactor.set();
		_ctxBorder.visible = false;
		add(_ctxBorder);

		_ctxBg = new FlxSprite(0, 0);
		_ctxBg.makeGraphic(CTX_W, totalH, 0xF21A1A26);
		_ctxBg.cameras = [camHUD];
		_ctxBg.scrollFactor.set();
		_ctxBg.visible = false;
		add(_ctxBg);

		_ctxHeaderBg = new FlxSprite(0, 0);
		_ctxHeaderBg.makeGraphic(CTX_W, CTX_HH, funkin.debug.themes.EditorTheme.current.accent);
		_ctxHeaderBg.cameras = [camHUD];
		_ctxHeaderBg.scrollFactor.set();
		_ctxHeaderBg.visible = false;
		add(_ctxHeaderBg);

		_ctxHeaderTxt = new FlxText(0, 0, CTX_W, "  \u2736  Add Object", 12);
		_ctxHeaderTxt.color = funkin.debug.themes.EditorTheme.current.bgDark;
		_ctxHeaderTxt.font = "VCR OSD Mono";
		_ctxHeaderTxt.cameras = [camHUD];
		_ctxHeaderTxt.scrollFactor.set();
		_ctxHeaderTxt.visible = false;
		add(_ctxHeaderTxt);

		for (i in 0...items.length)
		{
			var itemBg = new FlxSprite(0, 0);
			itemBg.makeGraphic(CTX_W, CTX_IH - 1, 0x00000000);
			itemBg.cameras = [camHUD];
			itemBg.scrollFactor.set();
			itemBg.visible = false;
			add(itemBg);
			_ctxItemBgs.push(itemBg);

			var iconTxt = new FlxText(0, 0, 28, items[i].icon, 14);
			iconTxt.alignment = CENTER;
			iconTxt.color = funkin.debug.themes.EditorTheme.current.accent;
			iconTxt.cameras = [camHUD];
			iconTxt.scrollFactor.set();
			iconTxt.visible = false;
			add(iconTxt);
			_ctxItemIcons.push(iconTxt);

			var labelTxt = new FlxText(0, 0, CTX_W - 32, items[i].label, 11);
			labelTxt.color = FlxColor.WHITE;
			labelTxt.cameras = [camHUD];
			labelTxt.scrollFactor.set();
			labelTxt.visible = false;
			add(labelTxt);
			_ctxItemLabels.push(labelTxt);

			_ctxActions.push(items[i].action);
		}
	}

	function _openContextMenu(mx:Float, my:Float):Void
	{
		_ctxOpen  = true;
		_ctxHover = -1;
		var totalH = CTX_HH + _ctxActions.length * CTX_IH + 6;

		var cx = mx;
		var cy = my;
		if (cx + CTX_W > FlxG.width  - 4) cx = FlxG.width  - CTX_W - 4;
		if (cy + totalH > FlxG.height - 4) cy = FlxG.height - totalH - 4;
		_ctxMX = cx;
		_ctxMY = cy;

		_ctxBorder.setPosition(cx - 2, cy - 2);
		_ctxBorder.visible = true;
		_ctxBg.setPosition(cx, cy);
		_ctxBg.visible = true;
		_ctxHeaderBg.setPosition(cx, cy);
		_ctxHeaderBg.visible = true;
		_ctxHeaderTxt.setPosition(cx + 4, cy + 5);
		_ctxHeaderTxt.visible = true;

		for (i in 0..._ctxActions.length)
		{
			var iy = cy + CTX_HH + i * CTX_IH + 3;
			_ctxItemBgs[i].setPosition(cx, iy);
			_ctxItemBgs[i].makeGraphic(CTX_W, CTX_IH - 1, 0x00000000);
			_ctxItemBgs[i].visible = true;
			_ctxItemIcons[i].setPosition(cx + 8, iy + 7);
			_ctxItemIcons[i].visible = true;
			_ctxItemLabels[i].setPosition(cx + 32, iy + 8);
			_ctxItemLabels[i].visible = true;
		}
	}

	function _closeContextMenu():Void
	{
		_ctxOpen  = false;
		_ctxHover = -1;
		if (_ctxBg        != null) _ctxBg.visible        = false;
		if (_ctxBorder    != null) _ctxBorder.visible    = false;
		if (_ctxHeaderBg  != null) _ctxHeaderBg.visible  = false;
		if (_ctxHeaderTxt != null) _ctxHeaderTxt.visible = false;
		for (i in 0..._ctxItemBgs.length)
		{
			if (i < _ctxItemBgs.length)    _ctxItemBgs[i].visible    = false;
			if (i < _ctxItemIcons.length)  _ctxItemIcons[i].visible  = false;
			if (i < _ctxItemLabels.length) _ctxItemLabels[i].visible = false;
		}
	}

	// Returns true if a context-menu action was executed this frame (used to
	// prevent the same justPressed event from also triggering viewport selection).
	function _updateContextMenu():Bool
	{
		if (!_ctxOpen) return false;
		var mx = FlxG.mouse.gameX;
		var my = FlxG.mouse.gameY;

		var newHover = -1;
		for (i in 0..._ctxActions.length)
		{
			var iy = _ctxMY + CTX_HH + i * CTX_IH + 3;
			if (mx >= _ctxMX && mx < _ctxMX + CTX_W && my >= iy && my < iy + CTX_IH - 1)
				newHover = i;
		}

		if (newHover != _ctxHover)
		{
			for (i in 0..._ctxItemBgs.length)
			{
				var isH = (i == newHover);
				_ctxItemBgs[i].makeGraphic(CTX_W, CTX_IH - 1,
					isH ? ((funkin.debug.themes.EditorTheme.current.accent & 0x00FFFFFF) | 0x55000000) : 0x00000000);
				_ctxItemLabels[i].color = isH ? funkin.debug.themes.EditorTheme.current.accent : FlxColor.WHITE;
				_ctxItemIcons[i].color  = isH ? FlxColor.WHITE : funkin.debug.themes.EditorTheme.current.accent;
			}
			_ctxHover = newHover;
		}

		if (FlxG.mouse.justPressed)
		{
			if (newHover >= 0)
			{
				var act = _ctxActions[newHover];
				_closeContextMenu();
				act();
				return true; // consumed — don't let viewport selection also fire
			}
			else
			{
				var totalH = CTX_HH + _ctxActions.length * CTX_IH + 6;
				var inside = mx >= _ctxMX && mx < _ctxMX + CTX_W
				          && my >= _ctxMY && my < _ctxMY + totalH;
				if (!inside) _closeContextMenu();
			}
		}
		if (FlxG.keys.justPressed.ESCAPE)
			_closeContextMenu();
		return false;
	}

	// Context menu action handlers ─────────────────────────────────────────────

	function _ctxCreateObject():Void
	{
		var layName = "solid_" + (layers.length + 1);
		var newObj:LayerObjectData = {
			name: layName, path: "__makeGraphic__",
			position: [0.0, 0.0], scale: [1.0, 1.0], alpha: 1.0,
			visible: true, flipX: false, flipY: false,
			antialiasing: false, animations: []
		};
		var newLay:LayerData = { name: layName, visible: true, objects: [newObj] };
		if (!_isV2Format) { _isV2Format = true; layers = []; }
		layers.push(newLay);
		curLayerIdx  = layers.length - 1;
		curObjectIdx = 0;
		currentAnimData = newObj.animations;
		_refreshLayerDropdown(); _syncLayerTabToCurrentLayer(); refreshLayerPanel();
		_hasUnsaved = true;
		setHelp("\u25a3 Created solid layer: " + layName, funkin.debug.themes.EditorTheme.current.accent);
	}

	function _ctxImportImage():Void
	{
		#if sys
		var dialog = new lime.ui.FileDialog();
		dialog.onSelect.add(function(path:String) {
			var name = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path));
			var newObj:LayerObjectData = {
				name: name, path: path,
				position: [0.0,0.0], scale: [1.0,1.0], alpha: 1.0,
				visible: true, flipX: false, flipY: false,
				antialiasing: true, animations: []
			};
			var newLay:LayerData = { name: name, visible: true, objects: [newObj] };
			if (!_isV2Format) { _isV2Format = true; layers = []; }
			layers.push(newLay);
			curLayerIdx  = layers.length - 1;
			curObjectIdx = 0;
			currentAnimData = newObj.animations;
			_refreshLayerDropdown(); _syncLayerTabToCurrentLayer(); refreshLayerPanel();
			_hasUnsaved = true;
			setHelp("\u2b1a Image: " + name, funkin.debug.themes.EditorTheme.current.accent);
		});
		dialog.browse(lime.ui.FileDialogType.OPEN, "png,jpg", null, "Select image");
		#else
		setHelp("\u26a0 Desktop only", FlxColor.YELLOW);
		#end
	}

	function _ctxImportSpritesheet():Void
	{
		#if sys
		var dialog = new lime.ui.FileDialog();
		dialog.onSelect.add(function(path:String) {
			var name = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path));
			var newObj:LayerObjectData = {
				name: name, path: haxe.io.Path.withoutExtension(path),
				position: [0.0,0.0], scale: [1.0,1.0], alpha: 1.0,
				visible: true, flipX: false, flipY: false,
				antialiasing: true, animations: []
			};
			var newLay:LayerData = { name: name, visible: true, objects: [newObj] };
			if (!_isV2Format) { _isV2Format = true; layers = []; }
			layers.push(newLay);
			curLayerIdx  = layers.length - 1;
			curObjectIdx = 0;
			currentAnimData = newObj.animations;
			_refreshLayerDropdown(); _syncLayerTabToCurrentLayer(); refreshLayerPanel();
			_hasUnsaved = true;
			setHelp("\u25a6 Spritesheet: " + name, funkin.debug.themes.EditorTheme.current.accent);
		});
		dialog.browse(lime.ui.FileDialogType.OPEN, "png", null, "Select spritesheet PNG");
		#else
		setHelp("\u26a0 Desktop only", FlxColor.YELLOW);
		#end
	}

	function _ctxImportAtlas():Void
	{
		#if sys
		var dialog = new lime.ui.FileDialog();
		dialog.onSelect.add(function(path:String) {
			var name = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path));
			var anims = _parseXmlPrefixes(path);
			var newObj:LayerObjectData = {
				name: name, path: haxe.io.Path.withoutExtension(path),
				position: [0.0,0.0], scale: [1.0,1.0], alpha: 1.0,
				visible: true, flipX: false, flipY: false,
				antialiasing: true, animations: anims
			};
			var newLay:LayerData = { name: name, visible: true, objects: [newObj] };
			if (!_isV2Format) { _isV2Format = true; layers = []; }
			layers.push(newLay);
			curLayerIdx  = layers.length - 1;
			curObjectIdx = 0;
			currentAnimData = newObj.animations;
			_refreshLayerDropdown(); _syncLayerTabToCurrentLayer(); refreshLayerPanel();
			_hasUnsaved = true;
			setHelp("\u25c8 Atlas: " + name + " (" + anims.length + " anims)", funkin.debug.themes.EditorTheme.current.accent);
		});
		dialog.browse(lime.ui.FileDialogType.OPEN, "xml", null, "Select Sparrow atlas XML");
		#else
		setHelp("\u26a0 Desktop only", FlxColor.YELLOW);
		#end
	}

	// ── Transform Handles (Photoshop-style scale) ─────────────────────────────

	function _buildTransformHandles():Void
	{
		for (i in 0...8)
		{
			var hitBg = new FlxSprite(0, 0);
			hitBg.makeGraphic(TX_HS + 10, TX_HS + 10, 0x00000000);
			hitBg.cameras = [camGame];
			hitBg.visible = false;
			hitBg.scrollFactor.set(1, 1);
			add(hitBg);
			_txHitBgs.push(hitBg);

			var h = new FlxSprite(0, 0);
			h.makeGraphic(TX_HS, TX_HS, FlxColor.WHITE);
			h.cameras = [camGame];
			h.visible = false;
			h.scrollFactor.set(1, 1);
			add(h);
			_txHandles.push(h);
		}
	}

	function _updateTransformHandles():Void
	{
		if (char == null || !_hasSelection)
		{
			for (h in _txHandles) h.visible = false;
			for (h in _txHitBgs) h.visible = false;
			return;
		}

		var _pad = 10;
		var bx = char.x - char.offset.x - _pad;
		var by = char.y - char.offset.y - _pad;
		var bw = char.width  + _pad * 2;
		var bh = char.height + _pad * 2;

		// 0=TL 1=TC 2=TR 3=RC 4=BR 5=BC 6=BL 7=LC
		var hx:Array<Float> = [ bx, bx+bw/2, bx+bw, bx+bw, bx+bw, bx+bw/2, bx, bx ];
		var hy:Array<Float> = [ by, by,       by,    by+bh/2, by+bh, by+bh, by+bh, by+bh/2 ];

		for (i in 0...8)
		{
			var hxi = hx[i] - TX_HS / 2;
			var hyi = hy[i] - TX_HS / 2;
			_txHandles[i].setPosition(hxi, hyi);
			_txHitBgs[i].setPosition(hxi - 5, hyi - 5);
			_txHandles[i].visible = true;
			_txHitBgs[i].visible  = true;
			var isCorner = (i % 2 == 0);
			var col:FlxColor = (_txDragging && _txDragIdx == i)
				? funkin.debug.themes.EditorTheme.current.accent
				: (isCorner ? FlxColor.WHITE : 0xFFCCCCCC);
			_txHandles[i].color = col;
		}
	}

	function _updateTransformDrag():Bool
	{
		if (!_hasSelection || char == null || _ctxOpen) return false;

		// World-space mouse
		var mx = camGame.scroll.x + (FlxG.mouse.gameX - camGame.x) / camGame.zoom;
		var my = camGame.scroll.y + (FlxG.mouse.gameY - camGame.y) / camGame.zoom;

		if (!_txDragging && FlxG.mouse.justPressed && !isMouseOverHUD())
		{
			for (i in 0...8)
			{
				var hb = _txHitBgs[i];
				if (!hb.visible) continue;
				if (mx >= hb.x && mx <= hb.x + hb.width && my >= hb.y && my <= hb.y + hb.height)
				{
					_txDragging  = true;
					_txDragIdx   = i;
					_txDragMX0   = FlxG.mouse.gameX;
					_txDragMY0   = FlxG.mouse.gameY;
					_txDragSX0   = (_isV2Format && _curObject() != null) ? _curObject().scale[0] : char.scale.x;
					_txDragSY0   = (_isV2Format && _curObject() != null) ? _curObject().scale[1] : char.scale.y;
					_txDragCW0   = (char.width  / char.scale.x);
					_txDragCH0   = (char.height / char.scale.y);
					_pushUndo();
					return true;
				}
			}
		}

		if (_txDragging)
		{
			if (FlxG.mouse.pressed)
			{
				var dx = FlxG.mouse.gameX - _txDragMX0;
				var dy = FlxG.mouse.gameY - _txDragMY0;

				var newSX = _txDragSX0;
				var newSY = _txDragSY0;
				var refW  = _txDragCW0 > 0 ? _txDragCW0 : 1.0;
				var refH  = _txDragCH0 > 0 ? _txDragCH0 : 1.0;

				var affR = (_txDragIdx == 2 || _txDragIdx == 3 || _txDragIdx == 4);
				var affL = (_txDragIdx == 0 || _txDragIdx == 6 || _txDragIdx == 7);
				var affB = (_txDragIdx == 4 || _txDragIdx == 5 || _txDragIdx == 6);
				var affT = (_txDragIdx == 0 || _txDragIdx == 1 || _txDragIdx == 2);

				if (affR || affL)
				{
					var sign = affR ? 1.0 : -1.0;
					newSX = Math.max(0.05, _txDragSX0 + (dx * sign) / (refW * camGame.zoom));
				}
				if (affB || affT)
				{
					var sign = affB ? 1.0 : -1.0;
					newSY = Math.max(0.05, _txDragSY0 + (dy * sign) / (refH * camGame.zoom));
				}

				var isCorner = (_txDragIdx % 2 == 0);
				if (isCorner && FlxG.keys.pressed.SHIFT)
				{
					var ratio = (_txDragSX0 != 0) ? (_txDragSY0 / _txDragSX0) : 1.0;
					if (Math.abs(dx) >= Math.abs(dy)) newSY = newSX * ratio;
					else                               newSX = newSY / ratio;
				}

				char.scale.set(newSX, newSY);
				char.updateHitbox();
				if (ghostChar != null) { ghostChar.scale.set(newSX, newSY); ghostChar.updateHitbox(); }
				if (_isV2Format && _curObject() != null)
					_curObject().scale = [newSX, newSY];
				if (scaleStepper != null) scaleStepper.value = newSX;
				_hasUnsaved = true;
				setHelp("\u2194 Scale: " + FlxMath.roundDecimal(newSX, 3) + " x " + FlxMath.roundDecimal(newSY, 3)
					+ (isCorner ? "  (SHIFT = proporcional)" : ""), FlxColor.WHITE);
				return true;
			}
			else
			{
				_txDragging = false;
				_txDragIdx  = -1;
				setHelp("\u2714 Scale applied. Press Ctrl+Z to undo.", funkin.debug.themes.EditorTheme.current.success ?? FlxColor.LIME);
			}
		}
		return _txDragging;
	}

	// ── _rebuildAnimListDisplay ───────────────────────────────────────────────
	/**
	 * BUG FIX: displayCharacter() llama generateOffsetTexts() antes que
	 * loadCharacterData() termine, por lo que animList queda en orden del Map
	 * (char.animOffsets) en vez del orden del JSON. Este método reconstruye
	 * correctamente la lista una vez que _isV2Format y currentAnimData son
	 * los definitivos.
	 */
	function _rebuildAnimListDisplay():Void
	{
		if (dumbTexts == null || animList == null) return;
		var i = dumbTexts.members.length - 1;
		while (i >= 0)
		{
			var m = dumbTexts.members[i];
			if (m != null) { FlxTween.cancelTweensOf(m); m.destroy(); }
			i--;
		}
		dumbTexts.clear();
		_offsetLabels.resize(0);
		_ghostBadgeBgs.resize(0);
		_ghostBadgeLabels.resize(0);
		_rowBgs.resize(0);
		animList = [];
		generateOffsetTexts();
	}

	function _setLayerDropdownVisible(vis:Bool):Void
	{
		if (layerDropDown != null) layerDropDown.visible = vis;
		_setLayerPropsPanelVisible(vis);
	}

	// ── Helpers de selección ──────────────────────────────────────────────────

	/** Devuelve la capa activa o null si no hay ninguna. */
	inline function _curLayer():Null<LayerData>
		return (layers != null && curLayerIdx >= 0 && curLayerIdx < layers.length)
			? layers[curLayerIdx] : null;

	/** Devuelve el objeto seleccionado (capa activa + curObjectIdx) o null. */
	function _curObject():Null<LayerObjectData>
	{
		var lay = _curLayer();
		if (lay == null || lay.objects == null) return null;
		return (curObjectIdx >= 0 && curObjectIdx < lay.objects.length)
			? lay.objects[curObjectIdx] : null;
	}

	/** Selecciona un objeto por (layerIdx, objectIdx) y sincroniza todo. */
	function _selectObject(layIdx:Int, objIdx:Int):Void
	{
		curLayerIdx  = layIdx;
		curObjectIdx = objIdx;
		var obj = _curObject();
		currentAnimData = (obj != null) ? obj.animations : [];
		_syncLayerTabToCurrentLayer();
		refreshLayerPanel();
		_hasSelection = (obj != null);
		curAnim = 0;
		_animListScroll = 0;
		_animLastClickIdx = -1;
		_animLastClickMs  = -9999;
		animList = [];
		var i = dumbTexts.members.length - 1;
		while (i >= 0) { var m = dumbTexts.members[i]; if (m != null) { FlxTween.cancelTweensOf(m); m.destroy(); } i--; }
		dumbTexts.clear();
		_offsetLabels.resize(0); _ghostBadgeBgs.resize(0); _ghostBadgeLabels.resize(0); _rowBgs.resize(0);
		generateOffsetTexts();
		if (obj != null) setHelp("◉ " + obj.name + " (layer: " + (_curLayer()?.name ?? "?") + ")", funkin.debug.themes.EditorTheme.current.accent);
	}

	// ── reloadCharacterWithNewAnims ───────────────────────────────────────────

	function reloadCharacterWithNewAnims():Void
	{
		// Guardar las animaciones del objeto actual antes de recargar (V2)
		if (_isV2Format)
		{
			var curObj = _curObject();
			if (curObj != null) curObj.animations = currentAnimData;
		}

		var jsonString = Json.stringify(buildExportData(), null, '\t');

		#if sys
		try
		{
			final charPath = Paths.ensureDir(Paths.resolveWrite('characters/$daAnim.json'));
			File.saveContent(charPath, jsonString);
			_hasUnsaved = false;
			displayCharacter(daAnim);
			loadCharacterData();
		}
		catch (e:Dynamic)
		{
			FlxG.log.error('[CharacterEditor] Error saving temp data: ' + e);
		}
		#end
	}

	// ── Export ────────────────────────────────────────────────────────────────

	function buildExportData():Dynamic
	{
		if (_isV2Format)
			return _buildExportDataV2();
		return _buildExportDataV1();
	}

	/** Construye el JSON de exportación en formato V2 (render.layers). */
	function _buildExportDataV2():Dynamic
	{
		// Guardar animaciones del objeto actual antes de exportar
		var curObj = _curObject();
		if (curObj != null)
			curObj.animations = currentAnimData;

		var death:Dynamic = {
			character: charDeathInput != null ? charDeathInput.text.trim() : '',
			sound: gameOverSoundInput != null ? gameOverSoundInput.text.trim() : '',
			endAnim: gameOverEndInput != null ? gameOverEndInput.text.trim() : ''
		};

		var gameplay:Dynamic = {
			position: [
				posOffsetXStepper != null ? posOffsetXStepper.value : 0,
				posOffsetYStepper != null ? posOffsetYStepper.value : 0
			],
			cameraOffset: [
				camOffsetXStepper != null ? camOffsetXStepper.value : 0,
				camOffsetYStepper != null ? camOffsetYStepper.value : 0
			],
			death: death,
			idleAfterSing: idleAfterSingCheckbox != null ? idleAfterSingCheckbox.checked : true
		};

		var exportLayers:Array<Dynamic> = [];
		for (lay in layers)
		{
			var exportObjects:Array<Dynamic> = [];
			if (lay.objects != null)
			{
				for (obj in lay.objects)
				{
					exportObjects.push({
						name:         obj.name,
						path:         obj.path,
						position:     obj.position,
						scale:        obj.scale,
						alpha:        obj.alpha,
						visible:      obj.visible,
						flipX:        obj.flipX,
						flipY:        obj.flipY,
						antialiasing: obj.antialiasing,
						animations:   obj.animations
					});
				}
			}
			exportLayers.push({
				name:    lay.name,
				visible: lay.visible,
				objects: exportObjects
			});
		}

		var iconPath = healthIconInput != null ? healthIconInput.text : daAnim;

		return {
			meta: { isPlayer: playerCheckbox != null ? playerCheckbox.checked : false },
			gameplay: gameplay,
			render: { layers: exportLayers },
			icon: {
				path: iconPath,
				flipX: charFlipXCheckbox != null ? charFlipXCheckbox.checked : false,
				isGrid: false,
				bumpInBeats: iconBumpInBeatsCheckbox != null ? iconBumpInBeatsCheckbox.checked : true,
				stepTempo: iconStepTempoStepper != null ? Std.int(iconStepTempoStepper.value) : 4
			}
		};
	}

	/** Construye el JSON de exportación en formato V1 (legado). */
	function _buildExportDataV1():CharacterData
	{
		var exportData:CharacterData = {
			path: pathInput.text,
			animations: currentAnimData,
			isPlayer: playerCheckbox.checked,
			antialiasing: antialiasingCheckbox.checked,
			scale: scaleStepper.value
		};
		if (charFlipXCheckbox != null && charFlipXCheckbox.checked)
			exportData.flipX = true;

		if (isTxtCheckbox.checked)
			exportData.isTxt = true;

		if (isSpritesheetCheckbox.checked)
			exportData.isSpritemap = true;

		if (isFlxAnimateCheckbox.checked)
		{
			exportData.isFlxAnimate = true;
			var sm = spritemapNameInput.text.trim();
			if (sm != "" && sm != "spritemap1")
				exportData.spritemapName = sm;
		}

		if (healthIconInput.text != "" && healthIconInput.text != daAnim)
			exportData.healthIcon = healthIconInput.text;

		if (healthBarColorInput.text != "" && healthBarColorInput.text != "#31B0D1")
			exportData.healthBarColor = healthBarColorInput.text;

		if (charDeathInput != null && charDeathInput.text.trim() != "")
			exportData.charDeath = charDeathInput.text.trim();

		// ── Game Over ──────────────────────────────────────────────────────────
		if (gameOverSoundInput != null && gameOverSoundInput.text.trim() != "")
			exportData.gameOverSound = gameOverSoundInput.text.trim();
		if (gameOverMusicInput != null && gameOverMusicInput.text.trim() != "")
			exportData.gameOverMusic = gameOverMusicInput.text.trim();
		if (gameOverEndInput != null && gameOverEndInput.text.trim() != "")
			exportData.gameOverEnd = gameOverEndInput.text.trim();
		if (gameOverBpmStepper != null && gameOverBpmStepper.value != 100)
			exportData.gameOverBpm = gameOverBpmStepper.value;
		if (gameOverCamFrameStepper != null && Std.int(gameOverCamFrameStepper.value) != 12)
			exportData.gameOverCamFrame = Std.int(gameOverCamFrameStepper.value);

		// ── Position Offset ────────────────────────────────────────────────────
		if (posOffsetXStepper != null && posOffsetYStepper != null)
		{
			final px = posOffsetXStepper.value;
			final py = posOffsetYStepper.value;
			if (px != 0 || py != 0)
				exportData.positionOffset = [px, py];
		}

		// ── Camera Offset ──────────────────────────────────────────────────────
		if (camOffsetXStepper != null && camOffsetYStepper != null)
		{
			final cx = camOffsetXStepper.value;
			final cy = camOffsetYStepper.value;
			if (cx != 0 || cy != 0)
				exportData.cameraOffset = [cx, cy];
		}

		return exportData;
	}

	// ── V1 → V2 conversion ───────────────────────────────────────────────────

	/**
	 * Convierte el personaje del formato V1 (animations planas) al V2
	 * (render.layers). Las animaciones actuales pasan a ser la capa "body".
	 */
	function _convertV1ToV2():Void
	{
		if (_isV2Format)
		{
			setHelp("⚠ Already V2 format", FlxColor.YELLOW);
			return;
		}

		var bodyObj:LayerObjectData = {
			name:         "body",
			path:         pathInput != null ? pathInput.text : "BOYFRIEND",
			position:     [
				posOffsetXStepper != null ? posOffsetXStepper.value : 0.0,
				posOffsetYStepper != null ? posOffsetYStepper.value : 0.0
			],
			scale:        [
				scaleStepper != null ? scaleStepper.value : 1.0,
				scaleStepper != null ? scaleStepper.value : 1.0
			],
			alpha:        1.0,
			visible:      true,
			flipX:        charFlipXCheckbox != null ? charFlipXCheckbox.checked : false,
			flipY:        false,
			antialiasing: antialiasingCheckbox != null ? antialiasingCheckbox.checked : true,
			animations:   currentAnimData.copy()
		};
		var bodyLayer:LayerData = {
			name:    "character",
			visible: true,
			objects: [bodyObj]
		};

		layers = [bodyLayer];
		curLayerIdx  = 0;
		curObjectIdx = 0;
		currentAnimData = bodyObj.animations;
		_isV2Format = true;

		_setLayerDropdownVisible(true);
		_refreshLayerDropdown();
		_syncLayerTabToCurrentLayer();

		reloadCharacterWithNewAnims();
		setHelp("✓ Converted to V2 — 1 layer, 1 object (body)", FlxColor.LIME);
	}

	// ── Export ────────────────────────────────────────────────────────────────

	function exportCharacterJSON():Void
	{
		var jsonString = Json.stringify(buildExportData(), null, '\t');

		_file = new FileReference();
		_file.addEventListener(Event.COMPLETE, onSaveComplete);
		_file.addEventListener(Event.CANCEL, onSaveCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file.save(jsonString, daAnim + ".json");
	}

	function exportOffsetsTXT():Void
	{
		var data = '';
		for (anim in animList)
		{
			if (char.animOffsets.exists(anim))
			{
				var offsets = char.animOffsets.get(anim);
				data += anim + " " + offsets[0] + " " + offsets[1] + "\n";
			}
		}

		if (data.length > 0)
		{
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), daAnim + "Offsets.txt");
		}
	}

	function copyJSONToClipboard():Void
	{
		var jsonString = Json.stringify(buildExportData(), null, '\t');
		#if desktop
		lime.system.Clipboard.text = jsonString;
		setHelp("✓ JSON copied to clipboard!", FlxColor.LIME);
		#else
		FlxG.log.warn("Clipboard not supported on this platform");
		#end
	}

	// ── File save events ──────────────────────────────────────────────────────

	function onSaveComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		_hasUnsaved = false;
		setHelp("✓ File saved!", FlxColor.LIME);
	}

	function onSaveCancel(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	function onSaveError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		setHelp("✗ Error saving file!", FlxColor.RED);
	}

	// ── Icon preview ──────────────────────────────────────────────────────────

	function updateIconPreview(iconName:String):Void
	{
		if (iconPreview != null && iconName != null && iconName != "")
			iconPreview.updateIcon(iconName, false);
	}

	// ── Selection helpers ─────────────────────────────────────────────────────

	/** Shows or hides the 4-sided selection border + name label + transform handles. */
	function _setSelectionVisible(v:Bool):Void
	{
		if (_selBorderT    != null) _selBorderT.visible    = v;
		if (_selBorderB    != null) _selBorderB.visible    = v;
		if (_selBorderL    != null) _selBorderL.visible    = v;
		if (_selBorderR    != null) _selBorderR.visible    = v;
		if (_selNameLabel  != null) _selNameLabel.visible  = v;
		// Also hide handles when deselecting
		if (!v)
		{
			for (h in _txHandles) if (h != null) h.visible = false;
			for (h in _txHitBgs)  if (h != null) h.visible = false;
		}
	}

	/**
	 * Called every frame. Keeps the selection border and name label positioned
	 * around the current char bounds, and syncs char.debugMode with _hasSelection.
	 */
	function _updateSelectionVisuals():Void
	{
		if (char != null)
			char.debugMode = _hasSelection;
		if (ghostChar != null)
			ghostChar.debugMode = false;

		if (!_hasSelection || char == null)
		{
			_setSelectionVisible(false);
			return;
		}

		var _pad = 10;
		// Use visual position (char.x - char.offset.x) so the selection box
		// wraps the rendered sprite, not the hitbox (which is shifted by the offset).
		var _bx  = char.x - char.offset.x - _pad;
		var _by  = char.y - char.offset.y - _pad;
		var _bw  = Std.int(char.width  + _pad * 2);
		var _bh  = Std.int(char.height + _pad * 2);
		if (_bw < SEL_BW * 2) _bw = SEL_BW * 2;
		if (_bh < SEL_BW * 2) _bh = SEL_BW * 2;

		// Resize and reposition the 4 border lines
		_selBorderT.setGraphicSize(_bw, SEL_BW); _selBorderT.updateHitbox(); _selBorderT.setPosition(_bx, _by);
		_selBorderB.setGraphicSize(_bw, SEL_BW); _selBorderB.updateHitbox(); _selBorderB.setPosition(_bx, _by + _bh - SEL_BW);
		_selBorderL.setGraphicSize(SEL_BW, _bh); _selBorderL.updateHitbox(); _selBorderL.setPosition(_bx, _by);
		_selBorderR.setGraphicSize(SEL_BW, _bh); _selBorderR.updateHitbox(); _selBorderR.setPosition(_bx + _bw - SEL_BW, _by);

		// Name label above the box
		var _selLN:String;
		if (_isV2Format)
		{
			var obj = _curObject();
			var lay = _curLayer();
			_selLN = (obj != null ? obj.name : daAnim) + (lay != null ? "  [" + lay.name + "]" : "");
		}
		else
			_selLN = daAnim;
		_selNameLabel.text = _selLN;
		_selNameLabel.x    = _bx;
		_selNameLabel.y    = _by - 20;

		_setSelectionVisible(true);
		_updateTransformHandles();
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// Keep the selection box + char.debugMode in sync every frame
		_updateSelectionVisuals();

		// Context menu (must run every frame so hover highlights work).
		// Returns true if an action was executed this frame — prevents the same
		// justPressed event from also firing viewport selection / offset drag.
		var _ctxConsumed = _updateContextMenu();
		if (_ctxOpen || _ctxConsumed) return;

		// Transform handle drag (intercepts left-click on handles)
		var _txHandled = _updateTransformDrag();
		if (_txHandled) return; // handle consumed mouse input this frame
/*
		// Usar char.hasCurAnim() para ser compatible con FlxAnimate y sprites normales
		if (char == null || !char.hasCurAnim())
			return;*/

		var curAnimName = char.getCurAnimName();

		// Display
		textAnim.text = "▶  " + curAnimName + "  [" + (curAnim + 1) + "/" + animList.length + "]";

		if (animList.length > 0 && curAnim >= 0 && curAnim < animList.length)
		{
			var offsets = char.animOffsets.get(animList[curAnim]);
			if (offsets != null)
				textInfo.text = "Offset: [" + offsets[0] + ", " + offsets[1] + "]   Zoom: " + FlxMath.roundDecimal(camGame.zoom, 2);
		}

		if (animRowHighlight != null && animList.length > 0)
		{
			var _hlVisRow = curAnim - _animListScroll;
			if (_hlVisRow >= 0 && _hlVisRow < _offsetLabels.length)
			{
				var targetY = 174.0 + (20.0 * _hlVisRow);
				animRowHighlight.y += (targetY - animRowHighlight.y) * 0.25;
				animRowHighlight.visible = true;
			}
			else
			{
				// La animación activa está fuera del área visible (scrolleada) → ocultar
				animRowHighlight.visible = false;
			}
		}

		if (ghostChar != null)
			ghostChar.flipX = char.flipX;

		// Exit — ESC siempre funciona aunque estés escribiendo
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (_unsavedDlg != null)
			{
				// Ya hay diálogo abierto — ignorar ESC para evitar doble-close
			}
			else if (_hasUnsaved)
			{
				_unsavedDlg = new funkin.debug.EditorDialogs.UnsavedChangesDialog([camHUD]);
				_unsavedDlg.onSaveAndExit = () ->
				{
					reloadCharacterWithNewAnims();
					_hasUnsaved = false;
					remove(_unsavedDlg, true);
					_unsavedDlg = null;
					funkin.system.CursorManager.hide();
					LoadingState.loadAndSwitchState(new MainMenuState());
				};
				_unsavedDlg.onSave = () ->
				{
					reloadCharacterWithNewAnims();
					_hasUnsaved = false;
					remove(_unsavedDlg, true);
					_unsavedDlg = null;
				};
				_unsavedDlg.onExit = () ->
				{
					remove(_unsavedDlg, true);
					_unsavedDlg = null;
					funkin.system.CursorManager.hide();
					LoadingState.loadAndSwitchState(new MainMenuState());
				};
				add(_unsavedDlg);
			}
			else
			{
				funkin.system.CursorManager.hide();
				LoadingState.loadAndSwitchState(new MainMenuState());
			}
		}

		// ── Zoom con rueda del mouse (siempre activo, no requiere teclado) ────
		if (FlxG.mouse.wheel != 0 && !isMouseOverHUD())
		{
			camGame.zoom = Math.max(0.1, camGame.zoom + FlxG.mouse.wheel * 0.1);
		}

		// ── Scroll de la lista de animaciones con la ruedita ─────────────────
		// Se activa cuando el cursor está en el panel izquierdo pero FUERA del
		// panel de layers (que ya tiene su propio scroll más abajo).
		{
			var amx = FlxG.mouse.gameX;
			var amy = FlxG.mouse.gameY;
			var lpTop = _isV2Format ? _lpTopY() : (FlxG.height - 30);
			var overAnimList = amx >= 0 && amx < LP_W && amy >= 174 && amy < lpTop;
			if (FlxG.mouse.wheel != 0 && overAnimList && animList.length > 0)
			{
				// Compute max visible rows same way generateOffsetTexts does
				var rowH = 20;
				var bottomLimit = _isV2Format ? _lpTopY() : (FlxG.height - 30);
				var maxVisRows = Std.int((bottomLimit - 174) / rowH);
				if (maxVisRows < 1) maxVisRows = 1;
				_animListScroll = Std.int(FlxMath.bound(
					_animListScroll - FlxG.mouse.wheel,
					0,
					Math.max(0, animList.length - maxVisRows)
				));
				// Rebuild the animation list with the new scroll offset
				var i = dumbTexts.members.length - 1;
				while (i >= 0)
				{
					var m = dumbTexts.members[i];
					if (m != null) { FlxTween.cancelTweensOf(m); m.destroy(); }
					i--;
				}
				dumbTexts.clear();
				_offsetLabels.resize(0);
				_ghostBadgeBgs.resize(0);
				_ghostBadgeLabels.resize(0);
				_rowBgs.resize(0);
				generateOffsetTexts(false); // false = don't rebuild animList, just redraw
			}
		}

		// ── Undo — Ctrl+Z (siempre activo, incluso si hay texto enfocado) ──────
		// Se permite fuera de isTyping() para que funcione aunque un campo esté
		// activo; no modifica el texto del campo.
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Z)
		{
			_doUndo();
		}

		// ── Todo lo demás se bloquea si el usuario está escribiendo en un campo ─
		if (isTyping())
			return;

		// ── Viewport click: select / deselect character or empty space ────────
		// Left click OUTSIDE the HUD and outside the anim-list / layer-panel zone:
		//   • On the character bounds  → select (show hitbox, props, anim list)
		//   • On empty space           → deselect (clear everything)
		if (FlxG.mouse.justPressed && !isMouseOverHUD())
		{
			var _vpMX = FlxG.mouse.gameX;
			var _vpMY = FlxG.mouse.gameY;
			// Don't intercept clicks that belong to the anim list or ghost badge area
			var _vpBotLimit = _isV2Format ? _lpTopY() : (FlxG.height - 30);
			var _inAnimZone = _vpMX >= 4 && _vpMX < 336 && _vpMY >= 174 && _vpMY < _vpBotLimit;
			if (!_inAnimZone && char != null)
			{
				// Convert screen (camUI) coords → world coords in camGame space
				var _vpWX = camGame.scroll.x + (_vpMX - camGame.x) / camGame.zoom;
				var _vpWY = camGame.scroll.y + (_vpMY - camGame.y) / camGame.zoom;
				var _vpPad = 12; // a little extra margin so edge clicks register
				// Use VISUAL position (char.x - char.offset.x), NOT hitbox position (char.x).
				// Animation offsets shift the rendered sprite without moving the hitbox,
				// so clicking on the visible character would miss if we used char.x directly.
				var _charVisX = char.x - char.offset.x;
				var _charVisY = char.y - char.offset.y;
				var _onChar = _vpWX >= _charVisX - _vpPad && _vpWX <= _charVisX + char.width  + _vpPad
				           && _vpWY >= _charVisY - _vpPad && _vpWY <= _charVisY + char.height + _vpPad;

				if (_onChar)
				{
					if (_isV2Format && layers != null && layers.length > 0
						&& !_hasSelection
						&& (currentAnimData == null || currentAnimData.length == 0))
					{
						for (_autoLi in 0...layers.length)
						{
							var _autoObjs = layers[_autoLi].objects;
							if (_autoObjs != null && _autoObjs.length > 0 && _autoObjs[0].animations != null && _autoObjs[0].animations.length > 0)
							{
								curLayerIdx    = _autoLi;
								curObjectIdx   = 0;
								currentAnimData = _autoObjs[0].animations;
								curAnim        = 0;
								_animListScroll = 0;
								_animLastClickIdx = -1;
								_animLastClickMs  = -9999;
								animList = [];
								var _alI = dumbTexts.members.length - 1;
								while (_alI >= 0)
								{
									var _alM = dumbTexts.members[_alI];
									if (_alM != null) { FlxTween.cancelTweensOf(_alM); _alM.destroy(); }
									_alI--;
								}
								dumbTexts.clear();
								_offsetLabels.resize(0); _ghostBadgeBgs.resize(0); _ghostBadgeLabels.resize(0); _rowBgs.resize(0);
								_syncLayerTabToCurrentLayer();
								refreshLayerPanel();
								break;
							}
						}
					}

					if (!_hasSelection)
					{
						// Restore selection
						_hasSelection = true;
						animList = [];
						var _vri = dumbTexts.members.length - 1;
						while (_vri >= 0) { var _vrm = dumbTexts.members[_vri]; if (_vrm != null) { FlxTween.cancelTweensOf(_vrm); _vrm.destroy(); } _vri--; }
						dumbTexts.clear();
						_offsetLabels.resize(0); _ghostBadgeBgs.resize(0); _ghostBadgeLabels.resize(0); _rowBgs.resize(0);
						generateOffsetTexts();
						_setLayerPropsPanelVisible(_isV2Format);
					}
					var _vpSelN = (_isV2Format && layers.length > 0) ? layers[curLayerIdx].name : daAnim;
					setHelp("✓ Selected: " + _vpSelN, funkin.debug.themes.EditorTheme.current.accent);
				}
				else
				{
					if (_hasSelection)
					{
						// Deselect — clear props and anim list
						_hasSelection = false;
						_setLayerPropsPanelVisible(false);
						animList = [];
						var _vdi = dumbTexts.members.length - 1;
						while (_vdi >= 0) { var _vdm = dumbTexts.members[_vdi]; if (_vdm != null) { FlxTween.cancelTweensOf(_vdm); _vdm.destroy(); } _vdi--; }
						dumbTexts.clear();
						_offsetLabels.resize(0); _ghostBadgeBgs.resize(0); _ghostBadgeLabels.resize(0); _rowBgs.resize(0);
						if (animRowHighlight != null) animRowHighlight.visible = false;
						setHelp("Click on the character to select it", FlxColor.WHITE);
					}
				}
			}
		}

		// ── Layer panel: mouse input (drag-and-drop, click, scroll) ─────────
		if (_isV2Format && layers != null && layers.length > 0)
		{
			var mx = FlxG.mouse.gameX;
			var my = FlxG.mouse.gameY;
			var panelTop     = _lpTopY() * 1.0;
			var contentTop   = panelTop + LP_HEADER_H;
			var inPanel      = mx >= 0 && mx < LP_W && my >= panelTop;
			var visCount     = Std.int(Math.min(layers.length, LP_MAX_VIS));
			var totalLayers  = layers.length;

			// ── INLINE RENAME: commit con Enter, cancelar con Escape, ─────────
			// o al hacer clic fuera del input.
			if (_lpRenameInput != null && _lpRenameInput.visible)
			{
				var commitRename = false;
				var cancelRename = false;

				if (FlxG.keys.justPressed.ENTER)
					commitRename = true;
				else if (FlxG.keys.justPressed.ESCAPE)
					cancelRename = true;
				else if (FlxG.mouse.justPressed && !_lpRenameInput.hasFocus)
					cancelRename = true;

				if (commitRename && _lpRenameIdx == -99)
				{
					var _roObj = _curObject();
					if (_roObj != null)
					{
						var newObjName = _lpRenameInput.text.trim();
						if (newObjName == "") newObjName = _roObj.name;
						_roObj.name = newObjName;
						if (layerNameInput != null) layerNameInput.text = newObjName;
						_refreshLayerDropdown();
						_hasUnsaved = true;
						setHelp("✓ Object renamed: " + newObjName, FlxColor.LIME);
					}
				}
				else if (commitRename && _lpRenameIdx >= 0 && _lpRenameIdx < layers.length)
				{
					var newName = _lpRenameInput.text.trim();
					if (newName == "") newName = "layer" + _lpRenameIdx;
					layers[_lpRenameIdx].name = newName;
					if (layerNameInput != null) layerNameInput.text = newName;
					_refreshLayerDropdown();
					_hasUnsaved = true;
					setHelp("✓ Renamed: " + newName, FlxColor.LIME);
				}
				else if (cancelRename)
				{
					setHelp("Rename cancelled", funkin.debug.themes.EditorTheme.current.textDim);
				}

				if (commitRename || cancelRename)
				{
					_lpRenameInput.visible  = false;
					_lpRenameInput.hasFocus = false;
					_lpRenameIdx = -1;
					refreshLayerPanel();
				}
			}

			// ── ANIMATION INLINE RENAME: commit con Enter, cancelar con Escape ────
			// o al hacer clic fuera del input.
			if (_animRenameInput != null && _animRenameInput.visible)
			{
				var commitAnimRename = false;
				var cancelAnimRename = false;

				if (FlxG.keys.justPressed.ENTER)
					commitAnimRename = true;
				else if (FlxG.keys.justPressed.ESCAPE)
					cancelAnimRename = true;
				else if (FlxG.mouse.justPressed && !_animRenameInput.hasFocus)
					cancelAnimRename = true;

				if (commitAnimRename && _animRenameIdx >= 0 && _animRenameIdx < currentAnimData.length)
				{
					var oldAnimName = currentAnimData[_animRenameIdx].name;
					var newAnimName = _animRenameInput.text.trim();
					if (newAnimName == "") newAnimName = oldAnimName;

					if (newAnimName != oldAnimName)
					{
						_pushUndo();
						currentAnimData[_animRenameIdx].name = newAnimName;
						// Migrar los offsets en el mapa del personaje
						if (char != null && char.animOffsets.exists(oldAnimName))
						{
							var _renamedOff = char.animOffsets.get(oldAnimName);
							char.animOffsets.remove(oldAnimName);
							char.animOffsets.set(newAnimName, _renamedOff);
						}
						_hasUnsaved = true;
						reloadCharacterWithNewAnims();
						setHelp("✓ Anim renombrada: " + oldAnimName + " → " + newAnimName, FlxColor.LIME);
					}
				}
				else if (cancelAnimRename)
				{
					setHelp("Rename cancelado", funkin.debug.themes.EditorTheme.current.textDim);
				}

				if (commitAnimRename || cancelAnimRename)
				{
					_animRenameInput.visible  = false;
					_animRenameInput.hasFocus = false;
					_animRenameIdx = -1;
					// Redibujar la lista de animaciones
					var _arI = dumbTexts.members.length - 1;
					while (_arI >= 0)
					{
						var _arM = dumbTexts.members[_arI];
						if (_arM != null) { FlxTween.cancelTweensOf(_arM); _arM.destroy(); }
						_arI--;
					}
					dumbTexts.clear();
					_offsetLabels.resize(0); _ghostBadgeBgs.resize(0); _ghostBadgeLabels.resize(0); _rowBgs.resize(0);
					generateOffsetTexts(false);
				}
			}

			// ── PRESS: check hits or start drag-pending ───────────────────────
			if (FlxG.mouse.justPressed)
			{
				var hitSomething = false;
				for (hit in layerPanelHits)
				{
					if (mx >= hit.x && mx < hit.x + hit.w && my >= hit.y && my < hit.y + hit.h)
					{
						hitSomething = true;
						switch (hit.zone)
						{
							case "addLayer":
								_addNewLayer();
							case "addObj":
								// hit.idx = layIdx — add object to that specific layer
								if (hit.idx >= 0 && hit.idx < layers.length)
								{
									curLayerIdx = hit.idx;
									_addNewObject();
								}
							case "layerEye":
								if (hit.idx >= 0 && hit.idx < layers.length)
								{
									layers[hit.idx].visible = !layers[hit.idx].visible;
									refreshLayerPanel();
									_hasUnsaved = true;
									setHelp((layers[hit.idx].visible ? "● Visible: " : "– Hidden: ") + layers[hit.idx].name, funkin.debug.themes.EditorTheme.current.success);
								}
							case "delLayer":
								if (hit.idx >= 0 && hit.idx < layers.length)
								{
									curLayerIdx  = hit.idx;
									curObjectIdx = 0;
									var _dlo = _curObject();
									currentAnimData = _dlo != null ? _dlo.animations : [];
								}
								_deleteCurrentLayer();
							case "delObj":
								// hit.idx = layIdx*1000 + objIdx
								var _doLay = Std.int(hit.idx / 1000);
								var _doObj = hit.idx % 1000;
								if (_doLay >= 0 && _doLay < layers.length)
								{
									curLayerIdx  = _doLay;
									curObjectIdx = _doObj;
									var _odo = _curObject();
									currentAnimData = _odo != null ? _odo.animations : [];
								}
								_deleteCurrentObject();
							case "objRow":
								// hit.idx = layIdx*1000 + objIdx
								var _selLay = Std.int(hit.idx / 1000);
								var _selObj = hit.idx % 1000;
								if (_selLay >= 0 && _selLay < layers.length)
								{
									var now2 = haxe.Timer.stamp();
									var selLay = layers[_selLay];
									if (selLay.objects != null && _selObj >= 0 && _selObj < selLay.objects.length)
									{
										_selectObject(_selLay, _selObj);
										// Double-click to rename object inline (reuse _lpRenameInput)
										if ((_lpLastClickIdx == hit.idx) && (now2 - _lpLastClickMs < 0.4))
										{
											_lpRenameIdx = -99; // sentinel: renaming an object, not a layer
											_lpRenameInput.text = selLay.objects[_selObj].name ?? "";
											_lpRenameInput.y    = hit.y + 3;
											_lpRenameInput.x    = 36;
											_lpRenameInput.visible = true;
											_lpRenameInput.hasFocus = true;
											_lpLastClickIdx = -1;
											_lpLastClickMs  = -9999;
										}
										else
										{
											_lpLastClickIdx = hit.idx;
											_lpLastClickMs  = now2;
										}
									}
								}
							case "objLocked":
								// Object belongs to an inactive layer — inform user
								var _lockLay = Std.int(hit.idx / 1000);
								var _lockLayName = (_lockLay >= 0 && _lockLay < layers.length) ? layers[_lockLay].name : "?";
								setHelp("⚠ Object is in layer [" + _lockLayName + "] — click that layer's header first to activate it", FlxColor.YELLOW);
							case "layerRow":
								if (hit.idx >= 0 && hit.idx < layers.length)
								{
									var now3 = haxe.Timer.stamp();
									var isDoubleClick = (_lpLastClickIdx == hit.idx) && (now3 - _lpLastClickMs < 0.4);

									// Activate layer
									curLayerIdx = hit.idx;
									var lay3 = layers[hit.idx];
									// Clamp curObjectIdx to valid range for this layer
									if (lay3.objects == null || lay3.objects.length == 0)
										curObjectIdx = -1;
									else
										curObjectIdx = Std.int(Math.min(curObjectIdx, lay3.objects.length - 1));
									var obj3 = _curObject();
									currentAnimData = (obj3 != null) ? obj3.animations : [];
									_syncLayerTabToCurrentLayer();
									refreshLayerPanel();
									_hasSelection = (obj3 != null);
									setHelp("◧ Layer: " + lay3.name + (obj3 != null ? " → " + obj3.name : "  (empty)"),
										funkin.debug.themes.EditorTheme.current.accent);

									// Rebuild animation list
									curAnim = 0;
									_animListScroll = 0;
									_animLastClickIdx = -1;
									_animLastClickMs  = -9999;
									animList = [];
									var _lpSwI = dumbTexts.members.length - 1;
									while (_lpSwI >= 0)
									{
										var _lpSwM = dumbTexts.members[_lpSwI];
										if (_lpSwM != null) { FlxTween.cancelTweensOf(_lpSwM); _lpSwM.destroy(); }
										_lpSwI--;
									}
									dumbTexts.clear();
									_offsetLabels.resize(0); _ghostBadgeBgs.resize(0); _ghostBadgeLabels.resize(0); _rowBgs.resize(0);
									generateOffsetTexts();

									if (isDoubleClick)
									{
										_lpRenameIdx = hit.idx;
										_lpRenameInput.text = layers[hit.idx].name ?? "";
										_lpRenameInput.y    = hit.y + 3;
										_lpRenameInput.x    = 38;
										_lpRenameInput.visible = true;
										_lpRenameInput.hasFocus = true;
										_lpLastClickIdx = -1;
										_lpLastClickMs  = -9999;
									}
									else
									{
										_lpLastClickIdx = hit.idx;
										_lpLastClickMs  = now3;
										_lpDragPending  = true;
										_lpDragFromIdx  = hit.idx;
										_lpDragFromVis  = (layers.length - 1 - hit.idx) - layerPanelScroll;
										_lpDragStartY  = my;
									}
								}
						}
						break;
					}
				}
			}

			// ── HELD: promote pending → active drag once past threshold ──────
			if (_lpDragPending && FlxG.mouse.pressed && Math.abs(my - _lpDragStartY) > 5)
			{
				_lpDragging    = true;
				_lpDragPending = false;
				refreshLayerPanel(); // redraws grip highlight
			}

			// ── DRAGGING: update ghost + drop indicator ───────────────────────
			if (_lpDragging && FlxG.mouse.pressed && _lpDragGhost != null && _lpDragGhostTxt != null)
			{
				// Ghost follows cursor (clamped to panel content area)
				var ghostY = FlxMath.bound(my - LP_ROW_H / 2, contentTop, contentTop + visCount * LP_ROW_H - LP_ROW_H);
				_lpDragGhost.y       = ghostY;
				_lpDragGhostTxt.y    = ghostY + 5;
				_lpDragGhost.visible = true;
				_lpDragGhostTxt.visible = true;
				if (_lpDragFromIdx >= 0 && _lpDragFromIdx < layers.length)
					_lpDragGhostTxt.text = layers[_lpDragFromIdx].name ?? "";

				// Compute drop gap (0 = before top row, visCount = after last row)
				var relY = my - contentTop;
				_lpDropGap = Std.int(FlxMath.bound(Math.round(relY / LP_ROW_H), 0, visCount));
				// Show drop line between rows
				var lineY = contentTop + _lpDropGap * LP_ROW_H - 1;
				_lpDropLine.y       = lineY;
				_lpDropLine.visible = true;
			}

			// ── RELEASE: commit the drop ──────────────────────────────────────
			if ((_lpDragging || _lpDragPending) && FlxG.mouse.justReleased)
			{
				if (_lpDragging && _lpDropGap >= 0 && _lpDragFromIdx >= 0)
				{
					// vpFrom = visual position (0 = top) of the dragged layer
					var vpFrom = (totalLayers - 1 - _lpDragFromIdx) - layerPanelScroll;
					// vpDrop  = absolute visual gap (accounting for scroll)
					var vpDrop = layerPanelScroll + _lpDropGap;
					vpDrop = Std.int(FlxMath.bound(vpDrop, 0, totalLayers));
					// Absolute vpFrom
					var vpFromAbs = totalLayers - 1 - _lpDragFromIdx;

					if (vpDrop != vpFromAbs && vpDrop != vpFromAbs + 1)
					{
						// Guard: index must still be valid (layers could theoretically change)
						if (_lpDragFromIdx < layers.length)
						{
						var item = layers.splice(_lpDragFromIdx, 1)[0];
						var adjGap = (vpDrop > vpFromAbs) ? vpDrop - 1 : vpDrop;
						// Insert at array index: (total-1) - adjGap
						var insertIdx = Std.int(FlxMath.bound((layers.length) - adjGap, 0, layers.length));
						layers.insert(insertIdx, item);
						curLayerIdx = insertIdx;
						var _dndObj = (item.objects != null && item.objects.length > 0) ? item.objects[0] : null;
						curObjectIdx = 0;
						currentAnimData = _dndObj != null ? _dndObj.animations : [];
						_hasUnsaved = true;
						setHelp("↕ Moved: " + item.name, funkin.debug.themes.EditorTheme.current.accent);
						}
					}
				}
				_lpDragging    = false;
				_lpDragPending = false;
				_lpDragFromIdx = -1;
				_lpDropGap     = -1;
				if (_lpDragGhost  != null) _lpDragGhost.visible  = false;
				if (_lpDragGhostTxt != null) _lpDragGhostTxt.visible = false;
				if (_lpDropLine   != null) _lpDropLine.visible   = false;
				refreshLayerPanel();
			}

		// ── SCROLL with mouse wheel over panel ────────────────────────────
			if (FlxG.mouse.wheel != 0 && inPanel)
			{
				layerPanelScroll = Std.int(FlxMath.bound(layerPanelScroll - FlxG.mouse.wheel, 0, Math.max(0, totalLayers - LP_MAX_VIS)));
				refreshLayerPanel();
			}

			// ── COPY / PASTE / DUPLICATE shortcuts ───────────────────────────
			if (FlxG.keys.pressed.CONTROL && !isTyping())
			{
				if (FlxG.keys.justPressed.C && curLayerIdx >= 0 && curLayerIdx < layers.length)
				{
					_copiedLayer = haxe.Json.parse(haxe.Json.stringify(layers[curLayerIdx]));
					setHelp("⎘ Copied: " + layers[curLayerIdx].name, funkin.debug.themes.EditorTheme.current.accent);
				}
				if (FlxG.keys.justPressed.V && _copiedLayer != null)
				{
					var pasted:LayerData = haxe.Json.parse(haxe.Json.stringify(_copiedLayer));
					pasted.name = pasted.name + "_copy";
					layers.insert(curLayerIdx + 1, pasted);
					curLayerIdx = curLayerIdx + 1;
					curObjectIdx = 0;
					var _pastedObj = (pasted.objects != null && pasted.objects.length > 0) ? pasted.objects[0] : null;
					currentAnimData = _pastedObj != null ? _pastedObj.animations : [];
					_syncLayerTabToCurrentLayer();
					_refreshLayerDropdown();
					_hasUnsaved = true;
					setHelp("⎘ Pasted: " + pasted.name, funkin.debug.themes.EditorTheme.current.success);
				}
				if (FlxG.keys.justPressed.D && curLayerIdx >= 0 && curLayerIdx < layers.length)
				{
					var dup:LayerData = haxe.Json.parse(haxe.Json.stringify(layers[curLayerIdx]));
					dup.name = dup.name + "_dup";
					layers.insert(curLayerIdx + 1, dup);
					curLayerIdx = curLayerIdx + 1;
					curObjectIdx = 0;
					var _dupObj = (dup.objects != null && dup.objects.length > 0) ? dup.objects[0] : null;
					currentAnimData = _dupObj != null ? _dupObj.animations : [];
					_syncLayerTabToCurrentLayer();
					_refreshLayerDropdown();
					_hasUnsaved = true;
					setHelp("⎘ Duplicated: " + dup.name, funkin.debug.themes.EditorTheme.current.success);
				}
			}
		}

		// ── Click en fila de animación → seleccionar + cargar en tab Animation ─
		// Un clic izquierdo en el área de la fila (x: 4–307) cambia la animación
		// activa Y rellena los campos del tab Animation automáticamente, sin
		// necesidad de pulsar "← Load Selected". Doble clic no hace nada extra.
		if (FlxG.mouse.justPressed && char != null && animList.length > 0)
		{
			var _amxC = FlxG.mouse.gameX;
			var _amyC = FlxG.mouse.gameY;
			var _listStartYC = 174;
			var _rowHC = 20;
			var _bottomLimitC = _isV2Format ? _lpTopY() : (FlxG.height - 30);

			// Only the name/offset column — avoid the [G] badge zone (x≥308)
			if (_amxC >= 4 && _amxC < 308 && _amyC >= _listStartYC && _amyC < _bottomLimitC)
			{
				var _visIdxC  = Std.int((_amyC - _listStartYC) / _rowHC);
				var _absIdxC  = _visIdxC + _animListScroll;
				if (_absIdxC >= 0 && _absIdxC < animList.length)
				{
					var _nowAnimClick = haxe.Timer.stamp();
					var _isAnimDblClick = (_animLastClickIdx == _absIdxC) && (_nowAnimClick - _animLastClickMs < 0.4);

					curAnim = _absIdxC;
					char.playAnim(animList[curAnim]);
					if (ghostChar != null)
						ghostChar.playAnim(animList[ghostAnimIdx]);
					updateOffsetTexts();

					// Auto-load selected anim into the Animation tab fields
					loadAnimIntoUI();

					// Bounce on anim label
					FlxTween.cancelTweensOf(textAnim);
					textAnim.scale.set(1.12, 1.12);
					FlxTween.tween(textAnim.scale, {x: 1, y: 1}, 0.22, {ease: FlxEase.backOut});

					if (_isAnimDblClick)
					{
						// ── Doble clic: abrir rename inline sobre la fila ────────────
						var _animDataRenameIdx = -1;
						for (_rni in 0...currentAnimData.length)
						{
							if (currentAnimData[_rni].name == animList[_absIdxC])
							{ _animDataRenameIdx = _rni; break; }
						}
						if (_animDataRenameIdx >= 0 && _animRenameInput != null)
						{
							_animRenameIdx = _animDataRenameIdx;
							_animRenameInput.text = currentAnimData[_animDataRenameIdx].name;
							_animRenameInput.y    = _listStartYC + (_visIdxC * _rowHC) + 3;
							_animRenameInput.visible  = true;
							_animRenameInput.hasFocus = true;
							// Resetear para no volver a disparar doble clic
							_animLastClickIdx = -1;
							_animLastClickMs  = -9999;
						}
					}
					else
					{
						_animLastClickIdx = _absIdxC;
						_animLastClickMs  = _nowAnimClick;
					}
				}
			}
		}

		// ── Click en el badge [G] de cada fila para cambiar la anim del ghost ─
		// La columna del badge está en x=308–335, filas desde y=174 cada 20px.
		if (FlxG.mouse.justPressed && ghostChar != null && animList.length > 0)
		{
			var mx = FlxG.mouse.gameX;
			var my = FlxG.mouse.gameY;
			var listStartY = 174;
			var rowH2 = 20;
			if (mx >= 308 && mx <= 336 && my >= listStartY && my < listStartY + animList.length * rowH2)
			{
				var clickedIdx = Std.int((my - listStartY) / rowH2);
				if (clickedIdx >= 0 && clickedIdx < animList.length)
				{
					ghostAnimIdx = clickedIdx;
					if (ghostChar.visible)
						ghostChar.playAnim(animList[ghostAnimIdx]);
					updateOffsetTexts();
					setHelp("[G] Ghost → " + animList[ghostAnimIdx], 0xFFAA88FF);
				}
			}
		}

		// Reset camera
		if (FlxG.keys.justPressed.R)
		{
			camFollow.setPosition(FlxG.width / 2, FlxG.height / 2);
			camGame.zoom = 1;
		}

		// Ghost
		if (FlxG.keys.justPressed.T && ghostChar != null)
			ghostChar.visible = !ghostChar.visible;

		// Camera movement
		var camSpeed = 90 * (FlxG.keys.pressed.SHIFT ? 2 : 1);
		var moveH = FlxG.keys.pressed.J ? -1 : FlxG.keys.pressed.L ? 1 : 0;
		var moveV = FlxG.keys.pressed.I ? -1 : FlxG.keys.pressed.K ? 1 : 0;
		camFollow.velocity.set(moveH * camSpeed, moveV * camSpeed);

		// Animation switching — only when something is selected
		if (_hasSelection)
		{
		if (FlxG.keys.justPressed.W)
		{
			curAnim--;
			if (curAnim < 0)
				curAnim = animList.length - 1;
		}
		if (FlxG.keys.justPressed.S)
		{
			curAnim++;
			if (curAnim >= animList.length)
				curAnim = 0;
		}

		if (FlxG.keys.justPressed.S || FlxG.keys.justPressed.W || FlxG.keys.justPressed.SPACE)
		{
			if (animList.length > 0 && curAnim >= 0 && curAnim < animList.length)
			{
				char.playAnim(animList[curAnim]);
				if (ghostChar != null)
					ghostChar.playAnim(animList[ghostAnimIdx]);
				updateOffsetTexts();

				// Bounce visual en el texto de animación
				FlxTween.cancelTweensOf(textAnim);
				textAnim.scale.set(1.15, 1.15);
				FlxTween.tween(textAnim.scale, {x: 1, y: 1}, 0.25, {ease: FlxEase.backOut});

				// Solo auto-cargar en la UI si YA estábamos en modo Edit,
				// para no pisar lo que el usuario estaba escribiendo
				if (editingAnimName != null)
					loadAnimIntoUI();
			}
		}
		} // end _hasSelection guard (anim switching)

		// ── Offset adjustment por teclado ─────────────────────────────────────
		var upP = FlxG.keys.anyJustPressed([UP]);
		var rightP = FlxG.keys.anyJustPressed([RIGHT]);
		var downP = FlxG.keys.anyJustPressed([DOWN]);
		var leftP = FlxG.keys.anyJustPressed([LEFT]);
		var mult = FlxG.keys.pressed.SHIFT ? 10 : 1;

		if (_hasSelection && (upP || rightP || downP || leftP) && animList.length > 0 && curAnim >= 0 && curAnim < animList.length)
		{
			var selAnim = animList[curAnim];
			var offsets = char.animOffsets.get(selAnim);

			if (offsets != null)
			{
				// Guardar estado anterior una vez por pulsación de tecla
				_pushUndo();

				if (upP)
					offsets[1] += 1 * mult;
				if (downP)
					offsets[1] -= 1 * mult;
				if (leftP)
					offsets[0] += 1 * mult;
				if (rightP)
					offsets[0] -= 1 * mult;

				for (anim in currentAnimData)
				{
					if (anim.name == selAnim)
					{
						anim.offsets = [offsets[0], offsets[1]];
						break;
					}
				}

				char.playAnim(selAnim);
				if (ghostChar != null)
					ghostChar.playAnim(animList[ghostAnimIdx]);
				updateOffsetTexts();
				_hasUnsaved = true;

				// Flash amarillo → normal en textInfo como feedback
				// FIX: reusar _flashTimer en vez de crear new FlxTimer() cada keypress.
				// Antes: mantener flecha pulsada = 60 timers/segundo acumulados.
				FlxTween.cancelTweensOf(textInfo);
				textInfo.color = 0xFFFFFFFF;
				if (_flashTimer != null)
					_flashTimer.reset(0.3);
				else
					_flashTimer = new FlxTimer().start(0.3, function(_)
					{
						if (textInfo != null)
							textInfo.color = 0xFFFFE566;
					});
			}
		}

		// ── Click derecho: context menu (sin arrastrar) o drag de offset ────────
		// • Right press  → registrar posición inicial
		// • Right held + arrastrar > 5px → drag de offset (comportamiento original)
		// • Right release sin haber arrastrado → abrir context menu estilo Blender
		if (!isMouseOverHUD())
		{
			var mouseMult = FlxG.keys.pressed.SHIFT ? 3 : 1;

			if (FlxG.mouse.justPressedRight)
			{
				_rcPressX   = FlxG.mouse.gameX;
				_rcPressY   = FlxG.mouse.gameY;
				_rcMoved    = false;
				isDraggingOffset = false;
				dragLastX = FlxG.mouse.gameX;
				dragLastY = FlxG.mouse.gameY;
			}

			// Activate drag once threshold exceeded
			if (FlxG.mouse.pressedRight && !isDraggingOffset)
			{
				var _rcDX = FlxG.mouse.gameX - _rcPressX;
				var _rcDY = FlxG.mouse.gameY - _rcPressY;
				if (Math.sqrt(_rcDX * _rcDX + _rcDY * _rcDY) > 5)
				{
					_rcMoved = true;
					isDraggingOffset = true;
					_pushUndo();
				}
			}

			if (isDraggingOffset && FlxG.mouse.pressedRight)
			{
				var dx = (FlxG.mouse.gameX - dragLastX) * mouseMult;
				var dy = (FlxG.mouse.gameY - dragLastY) * mouseMult;
				dragLastX = FlxG.mouse.gameX;
				dragLastY = FlxG.mouse.gameY;

				if ((Math.abs(dx) > 0 || Math.abs(dy) > 0) && animList.length > 0 && curAnim >= 0 && curAnim < animList.length)
				{
					var selAnim = animList[curAnim];
					var offsets = char.animOffsets.get(selAnim);

					if (offsets != null)
					{
						offsets[0] -= dx;
						offsets[1] -= dy;

						for (anim in currentAnimData)
						{
							if (anim.name == selAnim)
							{
								anim.offsets = [offsets[0], offsets[1]];
								break;
							}
						}

						char.playAnim(selAnim);
						if (ghostChar != null)
							ghostChar.playAnim(animList[ghostAnimIdx]);
						updateOffsetTexts();
						_hasUnsaved = true;
					}
				}
			}

			if (FlxG.mouse.justReleasedRight)
			{
				if (!_rcMoved)
				{
					// No drag → open context menu at click position
					_openContextMenu(_rcPressX, _rcPressY);
				}
				isDraggingOffset = false;
				_rcMoved = false;
			}
		}
		else
		{
			if (FlxG.mouse.justReleasedRight)
			{
				isDraggingOffset = false;
				_rcMoved = false;
			}
		}
	} // end update

	// ── Undo helpers ──────────────────────────────────────────────────────────

	/**
	 * Guarda un snapshot de currentAnimData en el stack de undo.
	 * Llama esto ANTES de cualquier operación que modifique datos.
	 *
	 * No duplica el snapshot si currentAnimData no cambió respecto al
	 * último push (evita entradas inútiles al mantener teclas pulsadas).
	 */
	function _pushUndo():Void
	{
		var snap = Json.stringify(currentAnimData);
		if (snap == _lastUndoJson)
			return; // sin cambios desde el último push → no apilar duplicado
		_undoStack.push(snap);
		_lastUndoJson = snap;
		if (_undoStack.length > MAX_UNDO)
			_undoStack.shift();
	}

	/**
	 * Restaura el último snapshot del stack, recarga el personaje y
	 * sincroniza los offsets en memoria (char.animOffsets).
	 *
	 * Usa reloadCharacterWithNewAnims() para garantizar consistencia
	 * tanto si se deshace un cambio de offset como si se deshace
	 * un add/delete de animación.
	 */
	function _doUndo():Void
	{
		if (_undoStack.length == 0)
		{
			setHelp("↩ Nothing to undo", FlxColor.WHITE);
			return;
		}
		var snap = _undoStack.pop();
		_lastUndoJson = snap; // actualizar marca para evitar re-push inmediato
		currentAnimData = cast Json.parse(snap);
		reloadCharacterWithNewAnims();
		setHelp("↩ Undo  (" + _undoStack.length + " left)", FlxColor.CYAN);
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	/**
	 * Devuelve true si el cursor está sobre cualquier elemento del HUD
	 * (panel izquierdo, panel UI derecho, barra inferior, área de ícono).
	 * Se usa para bloquear el drag de offsets cuando el usuario hace click
	 * sobre la interfaz en lugar del área de juego.
	 */
	function isMouseOverHUD():Bool
	{
		// Usamos gameX/Y (flixel-git: screenX/Y están deprecated y siempre valen 0).
		// (sus coordenadas de mundo == coordenadas de pantalla).
		// FlxG.mouse.overlaps() en flixel-git no maneja bien cámaras no-default.
		var mx = FlxG.mouse.gameX;
		var my = FlxG.mouse.gameY;

		// Panel derecho (UI_box)
		if (mx >= UI_box.x && mx <= UI_box.x + UI_box.width
			&& my >= UI_box.y && my <= UI_box.y + UI_box.height)
			return true;

		// Panel izquierdo (leftPanel)
		if (mx >= leftPanel.x && mx <= leftPanel.x + leftPanel.width
			&& my >= leftPanel.y && my <= leftPanel.y + leftPanel.height)
			return true;

		// Barra de estado (statusBar)
		if (mx >= statusBar.x && mx <= statusBar.x + statusBar.width
			&& my >= statusBar.y && my <= statusBar.y + statusBar.height)
			return true;

		// Preview del ícono (iconBG)
		if (mx >= iconBG.x && mx <= iconBG.x + iconBG.width
			&& my >= iconBG.y && my <= iconBG.y + iconBG.height)
			return true;

		// Layer panel (bottom of left panel)
		if (_isV2Format && layerPanelBg != null && layerPanelBg.visible
			&& mx >= 0 && mx < LP_W && my >= _lpTopY())
			return true;

		return false;
	}

	function setHelp(msg:String, color:FlxColor):Void
	{
		if (textHelp != null)
		{
			textHelp.text = msg;
			textHelp.color = color;
		}

		// Pulsar el acento de la barra de estado con el color del mensaje
		if (statusAccentBar != null)
		{
			statusAccentBar.color = color;
			FlxTween.cancelTweensOf(statusAccentBar);
			statusAccentBar.alpha = 1;
			FlxTween.tween(statusAccentBar, {alpha: 0.4}, 1.2, {ease: FlxEase.quartOut, onComplete: function(_)
			{
				statusAccentBar.alpha = 0.4;
			}});
		}
	}

	/**
	 * Devuelve true si cualquier campo de texto tiene el foco actualmente.
	 * Se usa para bloquear los atajos de teclado mientras el usuario escribe.
	 */
	function isTyping():Bool
	{
		// CoolInputText tiene hasFocus cuando está activo
		if (animNameInput != null && animNameInput.hasFocus)
			return true;
		if (animPrefixInput != null && animPrefixInput.hasFocus)
			return true;
		if (pathInput != null && pathInput.hasFocus)
			return true;
		if (spritemapNameInput != null && spritemapNameInput.hasFocus)
			return true;
		if (healthIconInput != null && healthIconInput.hasFocus)
			return true;
		if (healthBarColorInput != null && healthBarColorInput.hasFocus)
			return true;
		if (animAssetPathInput != null && animAssetPathInput.hasFocus)
			return true;
		if (animRenderTypeInput != null && animRenderTypeInput.hasFocus)
			return true;
		if (layerNameInput != null && layerNameInput.hasFocus)
			return true;
		if (layerPathInput != null && layerPathInput.hasFocus)
			return true;
		if (_lpRenameInput != null && _lpRenameInput.hasFocus)
			return true;
		if (_animRenameInput != null && _animRenameInput.hasFocus)
			return true;
		return false;
	}

	// ── _parseXmlPrefixes ────────────────────────────────────────────────────
	/**
	 * Lee un XML de Sparrow atlas y extrae los prefijos únicos de SubTexture
	 * (quitando los dígitos finales del nombre).
	 * Devuelve un Array<AnimData> listo para pasar a AnimMapperSubState.
	 */
	function _parseXmlPrefixes(xmlPath:String, framerate:Int = 24):Array<AnimData>
	{
		var result:Array<AnimData> = [];
		#if sys
		var seen = new Map<String, Bool>();
		try
		{
			var root = Xml.parse(sys.io.File.getContent(xmlPath)).firstElement();
			for (node in root.elements())
			{
				if (node.nodeName != "SubTexture") continue;
				var raw    = node.get("name") != null ? node.get("name") : "";
				var prefix = ~/\d+$/.replace(raw, ""); // strip trailing digits
				prefix = StringTools.trim(prefix);
				if (prefix != "" && !seen.exists(prefix))
				{
					seen.set(prefix, true);
					result.push({
						name:      prefix,
						prefix:    prefix,
						framerate: framerate,
						looped:    false,
						offsets:   [0, 0]
					});
				}
			}
		}
		catch (e:Dynamic) { FlxG.log.error("[CharacterEditor] _parseXmlPrefixes error: " + e); }
		#end
		return result;
	}

	// ── _parseAnimJsonSymbols ─────────────────────────────────────────────────
	/**
	 * Lee un Animation.json de FlxAnimate y devuelve todos los símbolos (SN)
	 * como Array<AnimData> listo para AnimMapperSubState.
	 * A diferencia de loadAnimationsFromAnimationJson, NO modifica currentAnimData.
	 */
	function _parseAnimJsonSymbols(animJsonPath:String, framerate:Int = 24):Array<AnimData>
	{
		var result:Array<AnimData> = [];
		#if sys
		try
		{
			var parsed:Dynamic = haxe.Json.parse(sys.io.File.getContent(animJsonPath));
			var fps:Int = (parsed.MD != null) ? Std.int(parsed.MD.FRT) : framerate;
			// Deduplicate by SN so AN.SN never creates a duplicate of an SD.S entry
			var seen = new Map<String, Bool>();

			// Main animation (AN)
			if (parsed.AN != null && parsed.AN.SN != null && !seen.exists(parsed.AN.SN))
			{
				seen.set(parsed.AN.SN, true);
				result.push({ name: parsed.AN.SN, prefix: parsed.AN.SN,
					framerate: fps, looped: true, offsets: [0, 0] });
			}

			// Symbol dictionary (SD.S)
			if (parsed.SD != null && parsed.SD.S != null)
				for (sym in (cast parsed.SD.S : Array<Dynamic>))
					if (sym.SN != null && !seen.exists(sym.SN))
					{
						seen.set(sym.SN, true);
						result.push({ name: sym.SN, prefix: sym.SN,
							framerate: fps, looped: false, offsets: [0, 0] });
					}
		}
		catch (e:Dynamic) { FlxG.log.error("[CharacterEditor] _parseAnimJsonSymbols error: " + e); }
		#end
		return result;
	}

	override function destroy():Void
	{
		// ── Quitar listener de cierre de ventana ───────────────────────────
		#if sys
		if (_windowCloseFn != null)
		{
			try { lime.app.Application.current.window.onClose.remove(_windowCloseFn); }
			catch (_) {}
			_windowCloseFn = null;
		}
		#end

		// Limpiar timer reutilizable
		if (_flashTimer != null)
		{
			_flashTimer.cancel();
			_flashTimer.destroy();
			_flashTimer = null;
		}

		// Vaciar caches de referencias (los objetos se destruyen con el grupo)
		_offsetLabels.resize(0);
		_ghostBadgeBgs.resize(0);
		_ghostBadgeLabels.resize(0);
		_rowBgs.resize(0);

		_unsavedDlg = null;
		_animRenameInput = null;
		super.destroy();
	}

}