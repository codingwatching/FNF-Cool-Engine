package funkin.menus;

#if desktop
import data.Discord.DiscordClient;
#end
import funkin.scripting.StateScriptHandler;
import funkin.gameplay.controls.CustomControlsState;
import funkin.gameplay.notes.NoteSkinOptions;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.FlxG;
import funkin.transitions.StateTransition;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import funkin.data.CoolUtil;
import funkin.gameplay.PlayState;
import funkin.states.MusicBeatState;
import funkin.states.MusicBeatSubstate;
import funkin.menus.MainMenuState;
import funkin.audio.MusicManager;
import data.PlayerSettings;
import openfl.Lib;

/**
 * Options Menu - Sistema de tabs integrado con keybinds
 * EXTENSIBLE: Usa StateScriptHandler para opciones dinámicas
 */
class OptionsMenuState extends MusicBeatSubstate
{
	// Categorías principales (se pueden agregar más desde scripts)
	#if mobileC
	var categories:Array<String> = ['General', 'Graphics', 'Gameplay', 'Note Skin', 'Offset', 'Mobile'];
	#else
	var categories:Array<String> = ['General', 'Graphics', 'Gameplay', 'Controls', 'Note Skin', 'Offset'];
	#end

	// ── FPS Cap — rango 30–240 en pasos de 5, luego Unlimited (0) ──────────────
	static inline final FPS_MIN:Int  = 30;
	static inline final FPS_MAX:Int  = 240;
	static inline final FPS_STEP:Int = 5;

	/** Devuelve el valor actual guardado (0 = Unlimited, default 60). */
	static function _getCurrentFPS():Int
	{
		return FlxG.save.data.fpsTarget != null ? Std.int(FlxG.save.data.fpsTarget) : 60;
	}

	/** Siguiente valor al pulsar → (Right/Toggle): sube 5, al llegar a 240 pasa a Unlimited,
	    desde Unlimited vuelve a 30. */
	static function _nextFPS(current:Int):Int
	{
		if (current <= 0)        return FPS_MIN;       // Unlimited → 30
		if (current >= FPS_MAX)  return 0;             // 240 → Unlimited
		// Redondear al múltiplo de 5 más cercano por encima
		final snapped = Math.ceil(current / FPS_STEP) * FPS_STEP;
		final next    = (snapped == current) ? current + FPS_STEP : snapped;
		return next > FPS_MAX ? 0 : next;
	}

	/** Anterior valor al pulsar ←: baja 5, desde 30 pasa a Unlimited. */
	static function _prevFPS(current:Int):Int
	{
		if (current <= 0)        return FPS_MAX;       // Unlimited → 240
		if (current <= FPS_MIN)  return 0;             // 30 → Unlimited
		final snapped = Math.floor(current / FPS_STEP) * FPS_STEP;
		final prev    = (snapped == current) ? current - FPS_STEP : snapped;
		return prev < FPS_MIN ? 0 : prev;
	}

	var curCategory:Int = 0;

	// UI Elements
	var menuBG:FlxSprite;
	var categoryTexts:FlxTypedGroup<FlxText>;
	var contentPanel:FlxTypedGroup<FlxSprite>;

	// Current tab content
	var optionNames:FlxTypedGroup<FlxText>;
	var optionValues:FlxTypedGroup<FlxText>;
	var curSelected:Int = 0;
	var currentOptions:Array<Dynamic> = [];

	// ── Scroll de opciones ────────────────────────────────────────────────
	// Desplazamiento vertical en píxeles para cuando hay más opciones que espacio
	var _optScrollY:Float = 0.0;
	// Área visible de opciones: desde startY hasta el footer
	static inline var OPT_START_Y:Int  = 180;
	static inline var OPT_SPACING:Int  = 55;
	static inline var OPT_VISIBLE_H:Int = 370; // FlxG.height(720) - footer(100) - startY(180) - margen(70)

	// ── Scrollbar ─────────────────────────────────────────────────────────
	var _scrollbarTrack:FlxSprite = null;  // barra gris de fondo
	var _scrollbarThumb:FlxSprite = null;  // barra blanca indicadora
	static inline var SCROLLBAR_W:Int  = 6;
	static var SCROLLBAR_X:Int  = FlxG.width - 58; // pegado al borde derecho del panel

	// Keybind state
	var bindingState:String = "select"; // "select", "binding", "editing"
	var tempKey:String = "";
	var keyBindNames:Array<String>    = ["LEFT", "DOWN", "UP", "RIGHT", "RESET", "ACCEPT", "BACK", "PAUSE", "SCREENSHOT", "CHEAT"];
	var defaultKeys:Array<String>     = ["A",    "S",    "W",  "D",     "R",     "ENTER",  "ESCAPE","ENTER", "F12",    "SEVEN"];
	var blacklistKeys:Array<String>   = ["SPACE"];
	// Teclas que solo pueden usarse en ciertos controles:
	var reservedKeys:Array<String>    = ["ESCAPE", "ENTER", "BACKSPACE"]; // solo para ACCEPT/BACK/PAUSE
	var keys:Array<String> = [];

	// ── Edit mode (opciones multi-valor: ENTER entra, A/D cambia, ENTER/ESC sale) ──
	var _editMode:Bool = false;
	var _editModeIndicator:flixel.text.FlxText;

	// ── Flechas de scroll ─────────────────────────────────────────────────────
	var _scrollArrowUp:flixel.text.FlxText;
	var _scrollArrowDown:flixel.text.FlxText;

	var warningText:FlxText;
	var bindingIndicator:FlxText;

	public static var fromPause:Bool = false;

	/** Si se cambia una opción que requiere restart mientras en pausa, este flag
	 *  le indica a PauseSubState que dispare el rewind al volver. */
	public static var pendingRewind:Bool = false;

	public static var isOpenOptions:Bool = false;

	override function create()
	{
		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('OptionsMenuState', this);

		if (fromPause)
			isOpenOptions = true;

		// Cargar categorías custom desde scripts
		loadCustomCategoriesFromScripts();

		StateScriptHandler.callOnScripts('onCreate', []);
		#end

		#if desktop
		DiscordClient.changePresence("Options Menu", null);
		#end

		// Inicializar keybinds
		loadKeyBinds();

		// Background semi-transparente (ajustar alpha si viene desde pause)
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = fromPause ? 0.5 : 0.7;
		bg.scrollFactor.set();
		add(bg);

		// Borde del panel (agregar primero para que esté detrás)
		var borderThickness = 3;
		var panelBorder = new FlxSprite(50 - borderThickness,
			80 - borderThickness).makeGraphic(Std.int(FlxG.width - 100 + borderThickness * 2), Std.int(FlxG.height - 160 + borderThickness * 2), 0xFF2a2a2a);
		panelBorder.scrollFactor.set();
		add(panelBorder);

		// Panel principal con borde
		menuBG = new FlxSprite(50, 80).makeGraphic(FlxG.width - 100, FlxG.height - 160, 0xFF0a0a0a);
		menuBG.scrollFactor.set();
		add(menuBG);

		// Título del menú
		var titleText = new FlxText(0, 20, FlxG.width, "OPTIONS MENU", 48);
		titleText.setFormat(Paths.font("Funkin.otf"), 48, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 3;
		titleText.scrollFactor.set();
		titleText.antialiasing = FlxG.save.data.antialiasing;
		add(titleText);

		// Crear contentPanel ANTES de usarlo
		contentPanel = new FlxTypedGroup<FlxSprite>();
		add(contentPanel);

		// Categorías en la parte superior con backgrounds individuales
		categoryTexts = new FlxTypedGroup<FlxText>();
		add(categoryTexts);

		var categoryWidth = (FlxG.width - 120) / categories.length;
		var tabHeight = 40;
		var tabY = 85;

		for (i in 0...categories.length)
		{
			// Background de la pestaña (inicialmente inactiva)
			var tabBG = new FlxSprite(60 + (i * categoryWidth), tabY).makeGraphic(Std.int(categoryWidth - 4), tabHeight, 0xFF1a1a1a);
			tabBG.scrollFactor.set();
			tabBG.ID = i;
			contentPanel.add(tabBG);

			// Borde superior de la pestaña
			var tabBorder = new FlxSprite(tabBG.x, tabBG.y - 2).makeGraphic(Std.int(tabBG.width), 2, 0xFF444444);
			tabBorder.scrollFactor.set();
			tabBorder.ID = i;
			contentPanel.add(tabBorder);

			var categoryText:FlxText = new FlxText(60 + (i * categoryWidth), tabY + 8, categoryWidth, categories[i], 24);
			categoryText.setFormat(Paths.font("Funkin.otf"), 22, 0xFF888888, CENTER, OUTLINE, FlxColor.BLACK);
			categoryText.borderSize = 2;
			categoryText.antialiasing = FlxG.save.data.antialiasing;
			categoryText.ID = i;
			categoryText.scrollFactor.set();
			categoryTexts.add(categoryText);
		}

		// Separador horizontal entre pestañas y contenido
		var separator = new FlxSprite(menuBG.x, tabY + tabHeight).makeGraphic(Std.int(menuBG.width), 3, 0xFF444444);
		separator.scrollFactor.set();
		add(separator);

		// Indicador de pestaña activa (barra inferior)
		var activeIndicator = new FlxSprite(0, tabY + tabHeight - 3).makeGraphic(Std.int(categoryWidth - 4), 3, FlxColor.CYAN);
		activeIndicator.scrollFactor.set();
		activeIndicator.ID = -1; // ID especial para el indicador
		contentPanel.add(activeIndicator);

		optionNames = new FlxTypedGroup<FlxText>();
		add(optionNames);

		optionValues = new FlxTypedGroup<FlxText>();
		add(optionValues);

		// Warning text para keybinds
		warningText = new FlxText(0, 140, FlxG.width, "", 20);
		warningText.setFormat(Paths.font("Funkin.otf"), 20, FlxColor.RED, CENTER, OUTLINE, FlxColor.BLACK);
		warningText.borderSize = 2;
		warningText.antialiasing = FlxG.save.data.antialiasing;
		warningText.alpha = 0;
		warningText.scrollFactor.set();
		add(warningText);

		// Binding indicator
		bindingIndicator = new FlxText(0, FlxG.height - 120, FlxG.width, "", 22);
		bindingIndicator.setFormat(Paths.font("Funkin.otf"), 22, FlxColor.YELLOW, CENTER, OUTLINE, FlxColor.BLACK);
		bindingIndicator.borderSize = 2;
		bindingIndicator.visible = false;
		bindingIndicator.antialiasing = FlxG.save.data.antialiasing;
		bindingIndicator.scrollFactor.set();
		add(bindingIndicator);

		// Footer con ayuda de controles
		var footerBG = new FlxSprite(menuBG.x, FlxG.height - 100).makeGraphic(Std.int(menuBG.width), 50, 0xFF1a1a1a);
		footerBG.scrollFactor.set();
		add(footerBG);

		var footerBorder = new FlxSprite(footerBG.x, footerBG.y).makeGraphic(Std.int(footerBG.width), 2, 0xFF444444);
		footerBorder.scrollFactor.set();
		add(footerBorder);

		var helpText = new FlxText(footerBG.x + 20, footerBG.y + 12, footerBG.width - 40,
			"← → : Tab  |  ↑ ↓ : Navigate  |  ENTER : Toggle/Edit  |  A/D : Adjust  |  ESC : Back", 18);
		helpText.setFormat(Paths.font("Funkin.otf"), 18, 0xFFAAAAAA, CENTER, OUTLINE, FlxColor.BLACK);
		helpText.borderSize = 1.5;
		helpText.antialiasing = FlxG.save.data.antialiasing;
		helpText.scrollFactor.set();
		add(helpText);

		// ── Edit mode indicator ────────────────────────────────────────────────
		_editModeIndicator = new FlxText(0, footerBG.y - 32, FlxG.width, "", 20);
		_editModeIndicator.setFormat(Paths.font("Funkin.otf"), 20, FlxColor.LIME, CENTER, OUTLINE, FlxColor.BLACK);
		_editModeIndicator.borderSize = 2;
		_editModeIndicator.visible = false;
		_editModeIndicator.antialiasing = FlxG.save.data.antialiasing;
		_editModeIndicator.scrollFactor.set();
		add(_editModeIndicator);

		// ── Flechas de scroll ──────────────────────────────────────────────────
		_scrollArrowUp = new FlxText(0, OPT_START_Y - 28, FlxG.width, "▲  More Options Up", 18);
		_scrollArrowUp.setFormat(Paths.font("Funkin.otf"), 18, 0xFF888888, CENTER, NONE);
		_scrollArrowUp.visible = false;
		_scrollArrowUp.antialiasing = FlxG.save.data.antialiasing;
		_scrollArrowUp.scrollFactor.set();
		add(_scrollArrowUp);

		_scrollArrowDown = new FlxText(0, OPT_START_Y + OPT_VISIBLE_H + 4, FlxG.width, "▼  More Options Down", 18);
		_scrollArrowDown.setFormat(Paths.font("Funkin.otf"), 18, 0xFF888888, CENTER, NONE);
		_scrollArrowDown.visible = false;
		_scrollArrowDown.antialiasing = FlxG.save.data.antialiasing;
		_scrollArrowDown.scrollFactor.set();
		add(_scrollArrowDown);

		// ── Scrollbar ─────────────────────────────────────────────────────────
		_scrollbarTrack = new FlxSprite(SCROLLBAR_X, OPT_START_Y).makeGraphic(SCROLLBAR_W, OPT_VISIBLE_H, 0xFF222222);
		_scrollbarTrack.scrollFactor.set();
		_scrollbarTrack.visible = false;
		add(_scrollbarTrack);

		_scrollbarThumb = new FlxSprite(SCROLLBAR_X, OPT_START_Y).makeGraphic(SCROLLBAR_W, 40, 0xFFFFFFFF);
		_scrollbarThumb.scrollFactor.set();
		_scrollbarThumb.visible = false;
		add(_scrollbarThumb);

		loadCategory(curCategory);

		// Configurar cámaras si se abre desde pause menu
		if (fromPause)
		{
			cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];
		}

		super.create();
	}

	#if HSCRIPT_ALLOWED
	/**
	 * Carga categorías custom registradas desde scripts
	 */
	function loadCustomCategoriesFromScripts():Void
	{
		var customCategories = StateScriptHandler.getCustomCategories();
		for (categoryName in customCategories)
		{
			if (!categories.contains(categoryName))
			{
				categories.push(categoryName);
			}
		}
	}
	#end

	function loadKeyBinds()
	{
		// Verificar que existan los keybinds
		if (FlxG.save.data.leftBind   == null) FlxG.save.data.leftBind   = "A";
		if (FlxG.save.data.downBind   == null) FlxG.save.data.downBind   = "S";
		if (FlxG.save.data.upBind     == null) FlxG.save.data.upBind     = "W";
		if (FlxG.save.data.rightBind  == null) FlxG.save.data.rightBind  = "D";
		if (FlxG.save.data.killBind   == null) FlxG.save.data.killBind   = "R";
		if (FlxG.save.data.acceptBind == null) FlxG.save.data.acceptBind = "ENTER";
		if (FlxG.save.data.backBind   == null) FlxG.save.data.backBind   = "ESCAPE";
		if (FlxG.save.data.pauseBind  == null) FlxG.save.data.pauseBind  = "ENTER";
		if (FlxG.save.data.screenshotBind  == null) FlxG.save.data.screenshotBind  = "F12";
		if (FlxG.save.data.cheatBind  == null) FlxG.save.data.cheatBind  = "SEVEN";

		keys = [
			FlxG.save.data.leftBind,
			FlxG.save.data.downBind,
			FlxG.save.data.upBind,
			FlxG.save.data.rightBind,
			FlxG.save.data.killBind,
			FlxG.save.data.acceptBind,
			FlxG.save.data.backBind,
			FlxG.save.data.pauseBind,
			FlxG.save.data.screenshotBind,
			FlxG.save.data.cheatBind
		];
	}

	function saveKeyBinds()
	{
		FlxG.save.data.leftBind   = keys[0];
		FlxG.save.data.downBind   = keys[1];
		FlxG.save.data.upBind     = keys[2];
		FlxG.save.data.rightBind  = keys[3];
		FlxG.save.data.killBind   = keys[4];
		FlxG.save.data.acceptBind = keys[5];
		FlxG.save.data.backBind   = keys[6];
		FlxG.save.data.pauseBind  = keys[7];
		FlxG.save.data.screenshotBind  = keys[8];
		FlxG.save.data.cheatBind  = keys[9];

		FlxG.save.flush();
		PlayerSettings.player1.controls.loadKeyBinds();
	}

	function loadCategory(index:Int)
	{
		// Limpiar contenido anterior
		optionNames.clear();
		optionValues.clear();
		currentOptions = [];
		curSelected = 0;
		_optScrollY  = 0.0;
		if (_scrollbarTrack != null) _scrollbarTrack.visible = false;
		if (_scrollbarThumb != null) _scrollbarThumb.visible = false;
		bindingState = "select";
		bindingIndicator.visible = false;
		_editMode = false;
		if (_editModeIndicator != null) _editModeIndicator.visible = false;

		var categoryName = categories[index];

		switch (categoryName)
		{
			case 'General':
				loadGeneralOptions();
			case 'Graphics':
				loadGraphicsOptions();
			case 'Gameplay':
				loadGameplayOptions();
			case 'Controls':
				loadControlsOptions();
			case 'Note Skin':
				loadNoteSkinOptions();
			case 'Offset':
				loadOffsetOptions();
			case 'Mobile':
				#if mobileC
				loadMobileControlsOptions();
				#end
			default:
				// Categoría custom desde script
				#if HSCRIPT_ALLOWED
				loadCustomCategory(categoryName);
				#end
		}

		// Agregar opciones custom a categorías existentes desde scripts
		#if HSCRIPT_ALLOWED
		loadCustomOptionsForCategory(categoryName);
		#end

		updateCategoryDisplay();
		updateOptionDisplay();
		_updateScroll(); // ← CRITICAL: clip items beyond visible area from the start
	}

	#if HSCRIPT_ALLOWED
	/**
	 * Carga una categoría custom completa desde scripts
	 */
	function loadCustomCategory(categoryName:String):Void
	{
		// Llamar a los scripts para obtener opciones de esta categoría
		var customOptions = StateScriptHandler.callOnScriptsReturn('getOptionsForCategory', [categoryName]);

		if (customOptions != null && Std.isOfType(customOptions, Array))
		{
			var optionsArray:Array<Dynamic> = cast customOptions;
			for (opt in optionsArray)
			{
				currentOptions.push(opt);
			}
		}

		createOptionTexts();
	}

	/**
	 * Carga opciones custom que se agregan a categorías existentes
	 */
	function loadCustomOptionsForCategory(categoryName:String):Void
	{
		// Llamar a los scripts para obtener opciones adicionales para esta categoría
		var additionalOptions = StateScriptHandler.callOnScriptsReturn('getAdditionalOptionsForCategory', [categoryName]);

		if (additionalOptions != null && Std.isOfType(additionalOptions, Array))
		{
			var optionsArray:Array<Dynamic> = cast additionalOptions;
			for (opt in optionsArray)
			{
				currentOptions.push(opt);
			}

			// Recrear los textos con las opciones adicionales
			optionNames.clear();
			optionValues.clear();
			createOptionTexts();
		}
	}
	#end

	function loadGeneralOptions()
	{
		currentOptions = [
			{
				name: "Flashing Lights",
				get: function() return FlxG.save.data.flashing ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.flashing = !FlxG.save.data.flashing;
				}
			},
			{
				name: "Camera Zoom",
				get: function() return FlxG.save.data.camZoom ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.camZoom = !FlxG.save.data.camZoom;
				}
			},
			{
				name: "Show HUD",
				get: function() return FlxG.save.data.HUD ? "OFF" : "ON",
				toggle: function()
				{
					FlxG.save.data.HUD = !FlxG.save.data.HUD;
				}
			},
			{
				name: "FPS Counter",
				get: function()
				{
					var mainInstance = cast(openfl.Lib.current.getChildAt(0), Main);
					return mainInstance.data.visible ? "ON" : "OFF";
				},
				toggle: function()
				{
					var mainInstance = cast(openfl.Lib.current.getChildAt(0), Main);
					mainInstance.data.visible = !mainInstance.data.visible;
				}
			},
			#if !mobileC
			{
				// ── FPS Cap ─────────────────────────────────────────────────────
				// ← / → suben/bajan de 5 en 5 entre 30 y 240, luego Unlimited (0).
				// Se guarda en FlxG.save.data.fpsTarget y se aplica de inmediato.
				name: "FPS Cap",
				get: function()
				{
					var t:Int = _getCurrentFPS();
					return t == 0 ? "Unlimited" : t + " FPS";
				},
				toggle: function()
				{
					applyFPSCap(_nextFPS(_getCurrentFPS()));
				},
				left: function()
				{
					applyFPSCap(_prevFPS(_getCurrentFPS()));
				},
				right: function()
				{
					applyFPSCap(_nextFPS(_getCurrentFPS()));
				}
			},
			{
				// ── VSync ────────────────────────────────────────────────────────
				name: "VSync",
				get: function()
				{
					return (FlxG.save.data.vsync == true) ? "ON" : "OFF";
				},
				toggle: function()
				{
					applyVSync(!(FlxG.save.data.vsync == true));
				}
			}
			#end
		];

		createOptionTexts();
	}

	/** Aplica el FPS cap y lo persiste en el save */
	function applyFPSCap(fps:Int):Void
	{
		FlxG.save.data.fpsTarget = fps;
		FlxG.save.flush();

		// Delegar SIEMPRE en Main.setMaxFps() — es el único punto que sabe
		// si usar FrameLimiterAPI (desktop/cpp) o stage.frameRate (mobile/html5).
		// NO tocar stage.frameRate directamente aquí:
		//   • stage.frameRate = 0 → OpenFL deja de disparar ENTER_FRAME → juego congelado.
		//   • En desktop el throttle real ya lo hace FrameLimiterAPI, no Lime.
		var main = cast(openfl.Lib.current.getChildAt(0), Main);
		if (main != null) main.setMaxFps(fps);

		trace('[Options] FPS cap -> ' + (fps <= 0 ? 'Unlimited' : fps + ' FPS'));
	}

	/** Aplica/quita VSync via extensión nativa y lo persiste en el save */
	function applyVSync(value:Bool):Void
	{
		FlxG.save.data.vsync = value;
		FlxG.save.flush();
		#if cpp
		extensions.VSyncAPI.setVSync(value);
		#end
		trace('[Options] VSync -> ' + (value ? 'ON' : 'OFF'));
	}

	function loadGraphicsOptions()
	{
		currentOptions = [
			#if mobileC
			{
				name: "Widescreen",
				get: function()
				{
					var s = FlxG.save.data.scaleMode;
					return (s == 'widescreen') ? "ON" : "OFF";
				},
				toggle: function()
				{
					var cur = FlxG.save.data.scaleMode;
					var next = (cur == 'widescreen') ? 'letterbox' : 'widescreen';
					FlxG.save.data.scaleMode = next;
					FlxG.save.flush();
					funkin.system.WindowManager.applyScaleModeByName(next);
				}
			},
			#end
			{
				name: "GPU Texture Caching",
				get: function() return FlxG.save.data.gpuCaching ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.gpuCaching = !FlxG.save.data.gpuCaching;
					funkin.cache.PathsCache.gpuCaching = FlxG.save.data.gpuCaching;
					FlxG.save.flush();
				}
			},
			{
				name: "Low Memory Mode",
				get: function() return FlxG.save.data.lowMemoryMode ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.lowMemoryMode = !FlxG.save.data.lowMemoryMode;
					funkin.cache.PathsCache.lowMemoryMode = FlxG.save.data.lowMemoryMode;
					FlxG.save.flush();
				}
			},
			{
				name: "Shaders",
				get: function() return FlxG.save.data.shaders ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.shaders = !FlxG.save.data.shaders;
				}
			},
			{
				name: "Streamed Music",
				get: function() return FlxG.save.data.streamedMusic ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.streamedMusic = !FlxG.save.data.streamedMusic;
					funkin.cache.PathsCache.streamedMusic = FlxG.save.data.streamedMusic;
					FlxG.save.flush();
				}
			},
			{
				name: "Anti-Aliasing",
				get: function() return FlxG.save.data.antialiasing ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.antialiasing = !FlxG.save.data.antialiasing;
				}
			},
			{
				name: "Note Splashes",
				get: function() return FlxG.save.data.notesplashes ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.notesplashes = !FlxG.save.data.notesplashes;
				}
			},
			{
				name: "Visual Effects",
				get: function() return FlxG.save.data.specialVisualEffects ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.specialVisualEffects = !FlxG.save.data.specialVisualEffects;
				}
			},
			{
				name: "Static Stage",
				get: function() return FlxG.save.data.staticstage ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.staticstage = !FlxG.save.data.staticstage;
				}
			}
		];

		createOptionTexts();
	}

	function loadGameplayOptions()
	{
		currentOptions = [
			{
				name: "Downscroll",
				get: function() return FlxG.save.data.downscroll ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.downscroll = !FlxG.save.data.downscroll;
				}
			},
			{
				name: "Middlescroll",
				get: function() return FlxG.save.data.middlescroll ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.middlescroll = !FlxG.save.data.middlescroll;
				}
			},
			{
				name: "Ghost Tapping",
				get: function() return FlxG.save.data.ghosttap ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.ghosttap = !FlxG.save.data.ghosttap;
				}
			},
			{
				name: "Accuracy Display",
				get: function() return FlxG.save.data.accuracyDisplay ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.accuracyDisplay = !FlxG.save.data.accuracyDisplay;
				}
			},
			{
				name: "Sick Mode",
				get: function() return FlxG.save.data.sickmode ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.sickmode = !FlxG.save.data.sickmode;
				}
			},
			{
				name: "Hit Sounds",
				get: function() return FlxG.save.data.hitsounds ? "ON" : "OFF",
				toggle: function()
				{
					FlxG.save.data.hitsounds = !FlxG.save.data.hitsounds;
				}
			},
			// ── Lane Backdrop (osu-style) ───────────────────────────────────────
			// Fondo negro semitransparente detrás del carril de notas del jugador.
			// La posición se adapta automáticamente a Middlescroll / Downscroll / Upscroll.
			// Alpha 0% = transparente (por defecto). Ajustar con ← / → o A / D.
			{
				name: "Lane Backdrop",
				get: function()
				{
					var a:Float = (FlxG.save.data.laneAlpha != null) ? FlxG.save.data.laneAlpha : 0.0;
					return Std.int(a * 100) + "%";
				},
				left: function()
				{
					var a:Float = (FlxG.save.data.laneAlpha != null) ? FlxG.save.data.laneAlpha : 0.0;
					a = Math.max(0.0, Math.round((a - 0.05) * 100) / 100);
					FlxG.save.data.laneAlpha = a;
					_applyLaneBackdropAlpha(a);
				},
				right: function()
				{
					var a:Float = (FlxG.save.data.laneAlpha != null) ? FlxG.save.data.laneAlpha : 0.0;
					a = Math.min(1.0, Math.round((a + 0.05) * 100) / 100);
					FlxG.save.data.laneAlpha = a;
					_applyLaneBackdropAlpha(a);
				}
			},
			// ── Rating Position ────────────────────────────────────────────────
			// Abre un substate visual donde se puede mover la posición del popup
			// de rating (Sick, Good, Bad, etc.) en pantalla.
			{
				name: "Rating Position",
				get: function()
				{
					var ox:Int = FlxG.save.data.ratingOffsetX != null ? FlxG.save.data.ratingOffsetX : 0;
					var oy:Int = FlxG.save.data.ratingOffsetY != null ? FlxG.save.data.ratingOffsetY : 0;
					return 'X:$ox  Y:$oy';
				},
				toggle: function()
				{
					openSubState(new RatingPositionSubState());
				}
			}
		];

		createOptionTexts();
	}

	function loadControlsOptions()
	{
		currentOptions = [];

		// Cargar keybinds actuales (todos los 9 controles)
		for (i in 0...keyBindNames.length)
		{
			var keyIndex = i;
			currentOptions.push({
				name: keyBindNames[i],
				get: function() return keys[keyIndex],
				toggle: function()
				{
					startBinding(keyIndex);
				},
				isKeybind: true
			});
		}

		// Opción de resetear
		currentOptions.push({
			name: "Reset to Default",
			get: function() return "BACKSPACE",
			toggle: function()
			{
				resetKeybinds();
			},
			isKeybind: false
		});

		createOptionTexts();
	}

	function loadNoteSkinOptions()
	{
		currentOptions = [
			{
				name: "Note Skin Settings",
				get: function() return "PRESS ENTER",
				toggle: function()
				{
					StateTransition.switchState(new NoteSkinOptions());
				}
			}
		];

		createOptionTexts();
	}

	#if mobileC
	/** Nombres de esquemas de control en el mismo orden que Config.getcontrolmode() devuelve */
	static final MOBILE_SCHEME_NAMES:Array<String> = [
		"VirtualPad Right",   // 0
		"VirtualPad Left",    // 1
		"Keyboard Only",      // 2
		"VirtualPad Custom",  // 3
		"Hitbox"              // 4
	];

	function loadMobileControlsOptions()
	{
		var config = new data.Config();
		currentOptions = [
			{
				name: "Control Scheme",
				get: function()
				{
					var mode = config.getcontrolmode();
					return MOBILE_SCHEME_NAMES[mode < MOBILE_SCHEME_NAMES.length ? mode : 0];
				},
				toggle: function()
				{
					// Cicla al siguiente esquema
					var mode = config.getcontrolmode();
					config.setcontrolmode((mode + 1) % MOBILE_SCHEME_NAMES.length);
				},
				left: function()
				{
					var mode = config.getcontrolmode();
					config.setcontrolmode((mode - 1 + MOBILE_SCHEME_NAMES.length) % MOBILE_SCHEME_NAMES.length);
				},
				right: function()
				{
					var mode = config.getcontrolmode();
					config.setcontrolmode((mode + 1) % MOBILE_SCHEME_NAMES.length);
				}
			},
			{
				name: "Pad Opacity",
				get: function()
				{
					var v = FlxG.save.data.mobileAlpha != null ? Std.int(FlxG.save.data.mobileAlpha * 100) : 75;
					return v + "%";
				},
				left: function()
				{
					var v:Float = FlxG.save.data.mobileAlpha != null ? FlxG.save.data.mobileAlpha : 0.75;
					v = Math.max(0.1, v - 0.05);
					FlxG.save.data.mobileAlpha = v;
					FlxG.save.flush();
				},
				right: function()
				{
					var v:Float = FlxG.save.data.mobileAlpha != null ? FlxG.save.data.mobileAlpha : 0.75;
					v = Math.min(1.0, v + 0.05);
					FlxG.save.data.mobileAlpha = v;
					FlxG.save.flush();
				},
				toggle: function() {}
			},
			{
				name: "Edit Custom Layout",
				get: function() return "PRESS ENTER",
				toggle: function()
				{
					// Solo disponible en modo VirtualPad Custom
					var mode = config.getcontrolmode();
					if (mode == 3)
						openSubState(new ui.MobileControlsEditor());
					else
						showWarning("Switch to 'VirtualPad Custom' first!");
				}
			},
			{
				name: "Reset Custom Layout",
				get: function() return "BACKSPACE",
				toggle: function()
				{
					FlxG.save.data.mobilePadLayout = null;
					FlxG.save.flush();
					showWarning("Custom layout reset!");
					FlxG.sound.play(Paths.sound('menus/cancelMenu'));
				}
			},
			{
				name: "Touch Indicator",
				get: function()
				{
					var on = FlxG.save.data.touchIndicator != null ? FlxG.save.data.touchIndicator : true;
					return on ? "ON" : "OFF";
				},
				toggle: function()
				{
					var cur = FlxG.save.data.touchIndicator != null ? FlxG.save.data.touchIndicator : true;
					FlxG.save.data.touchIndicator = !cur;
					FlxG.save.flush();
					funkin.util.plugins.TouchPointerPlugin.enabled = FlxG.save.data.touchIndicator;
				}
			}
		];

		createOptionTexts();
	}
	#end

	function loadOffsetOptions()
	{
		currentOptions = [
			{
				name: "Audio Offset",
				get: function() return FlxG.save.data.offset + " ms",
				toggle: function()
				{
					openSubState(new OffsetCalibrationState());
				}
			}
		];

		createOptionTexts();
	}

	function createOptionTexts()
	{
		for (i in 0...currentOptions.length)
		{
			var nameText:FlxText = new FlxText(90, OPT_START_Y + (i * OPT_SPACING), 600, currentOptions[i].name, 26);
			nameText.setFormat(Paths.font("Funkin.otf"), 26, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
			nameText.borderSize = 2;
			nameText.ID = i;
			nameText.scrollFactor.set();
			nameText.antialiasing = FlxG.save.data.antialiasing;
			optionNames.add(nameText);

			var valueText:FlxText = new FlxText(FlxG.width - 400, OPT_START_Y + (i * OPT_SPACING), 320, currentOptions[i].get(), 26);
			valueText.setFormat(Paths.font("Funkin.otf"), 26, FlxColor.CYAN, RIGHT, OUTLINE, FlxColor.BLACK);
			valueText.antialiasing = FlxG.save.data.antialiasing;
			valueText.borderSize = 2;
			valueText.ID = i;
			valueText.scrollFactor.set();
			optionValues.add(valueText);
		}
	}

	// Recalcula _optScrollY para que curSelected siempre sea visible
	function _updateScroll()
	{
		if (currentOptions.length == 0) return;

		// Posición Y del item seleccionado (relativa al area, sin scroll)
		var itemY:Float = curSelected * OPT_SPACING;

		// Asegurar que el item seleccionado esté dentro del área visible
		if (itemY < _optScrollY)
			_optScrollY = itemY;
		if (itemY + OPT_SPACING > _optScrollY + OPT_VISIBLE_H)
			_optScrollY = itemY + OPT_SPACING - OPT_VISIBLE_H;

		// Clamp: no desplazar más allá del contenido
		var maxScroll:Float = Math.max(0, currentOptions.length * OPT_SPACING - OPT_VISIBLE_H);
		if (_optScrollY < 0)   _optScrollY = 0;
		if (_optScrollY > maxScroll) _optScrollY = maxScroll;

		// Aplicar scroll a los textos
		var clip = new flixel.math.FlxRect(0, OPT_START_Y, FlxG.width, OPT_VISIBLE_H);

		optionNames.forEach(function(txt:FlxText)
		{
			txt.y = OPT_START_Y + (txt.ID * OPT_SPACING) - _optScrollY;
			txt.visible = (txt.y >= OPT_START_Y - OPT_SPACING) && (txt.y < OPT_START_Y + OPT_VISIBLE_H);
		});

		optionValues.forEach(function(txt:FlxText)
		{
			txt.y = OPT_START_Y + (txt.ID * OPT_SPACING) - _optScrollY;
			txt.visible = (txt.y >= OPT_START_Y - OPT_SPACING) && (txt.y < OPT_START_Y + OPT_VISIBLE_H);
		});

		// ── Actualizar flechas de scroll ─────────────────────────────────────
		if (_scrollArrowUp   != null) _scrollArrowUp.visible   = (_optScrollY > 0);
		if (_scrollArrowDown != null)
		{
			var maxScroll2:Float = Math.max(0, currentOptions.length * OPT_SPACING - OPT_VISIBLE_H);
			_scrollArrowDown.visible = (_optScrollY < maxScroll2 - 1);
		}
		{
			var totalH    = currentOptions.length * OPT_SPACING;
			var needsBar  = totalH > OPT_VISIBLE_H;
			_scrollbarTrack.visible = needsBar;
			_scrollbarThumb.visible = needsBar;
			if (needsBar)
			{
				// Altura del thumb proporcional al contenido visible
				var thumbH = Std.int(Math.max(20, OPT_VISIBLE_H * OPT_VISIBLE_H / totalH));
				var thumbTravel = OPT_VISIBLE_H - thumbH;
				var thumbY = OPT_START_Y + Std.int(thumbTravel * (_optScrollY / maxScroll));
				_scrollbarThumb.makeGraphic(SCROLLBAR_W, thumbH, 0xFFFFFFFF);
				_scrollbarThumb.y = thumbY;
			}
		}
	}

	function updateCategoryDisplay()
	{
		var categoryWidth = (FlxG.width - 120) / categories.length;

		// Actualizar textos de categorías
		categoryTexts.forEach(function(txt:FlxText)
		{
			if (txt.ID == curCategory)
			{
				txt.color = FlxColor.WHITE;
				txt.setFormat(Paths.font("Funkin.otf"), 24, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);

				// Animar el texto
				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1.05, y: 1.05}, 0.2, {ease: FlxEase.quadOut});
			}
			else
			{
				txt.color = 0xFF888888;
				txt.setFormat(Paths.font("Funkin.otf"), 22, 0xFF888888, CENTER, OUTLINE, FlxColor.BLACK);

				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1, y: 1}, 0.2, {ease: FlxEase.quadOut});
			}
		});

		// Actualizar backgrounds de pestañas
		contentPanel.forEach(function(sprite:FlxSprite)
		{
			if (sprite.ID >= 0 && sprite.ID < categories.length)
			{
				if (sprite.ID == curCategory)
				{
					// Pestaña activa - más clara y brillante
					sprite.color = 0xFF2a2a2a;
					sprite.alpha = 1;
				}
				else
				{
					// Pestaña inactiva - más oscura
					sprite.color = 0xFF1a1a1a;
					sprite.alpha = 0.7;
				}
			}

			// Mover el indicador de pestaña activa
			if (sprite.ID == -1) // El indicador tiene ID -1
			{
				var targetX = 60 + (curCategory * categoryWidth);
				FlxTween.cancelTweensOf(sprite);
				FlxTween.tween(sprite, {x: targetX}, 0.3, {ease: FlxEase.quadOut});
			}
		});
	}

	function updateOptionDisplay()
	{
		optionNames.forEach(function(txt:FlxText)
		{
			if (txt.ID == curSelected)
			{
				txt.color = FlxColor.CYAN;
				txt.alpha = 1;

				// Animar el texto seleccionado
				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1.08, y: 1.08}, 0.15, {ease: FlxEase.quadOut});
			}
			else
			{
				txt.color = FlxColor.WHITE;
				txt.alpha = 0.6;

				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1, y: 1}, 0.15, {ease: FlxEase.quadOut});
			}
		});

		optionValues.forEach(function(txt:FlxText)
		{
			if (txt.ID == curSelected)
			{
				txt.alpha = 1;
				txt.color = FlxColor.YELLOW;

				// Animar el valor seleccionado
				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1.08, y: 1.08}, 0.15, {ease: FlxEase.quadOut});
			}
			else
			{
				txt.alpha = 0.6;
				txt.color = FlxColor.CYAN;

				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1, y: 1}, 0.15, {ease: FlxEase.quadOut});
			}

			txt.text = currentOptions[txt.ID].get();
		});
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end

		// Si estamos esperando un keybind
		if (bindingState == "binding")
		{
			handleKeyBinding();
			return;
		}

		// ── Modo edición: A/D cambia el valor, ENTER o ESC confirma y sale ────
		if (_editMode)
		{
			final opt = currentOptions[curSelected];
			var changed = false;
			if (FlxG.keys.justPressed.A || FlxG.keys.justPressed.LEFT)
			{
				if (opt.left != null) { opt.left(); changed = true; }
			}
			if (FlxG.keys.justPressed.D || FlxG.keys.justPressed.RIGHT)
			{
				if (opt.right != null) { opt.right(); changed = true; }
			}
			if (changed)
			{
				FlxG.sound.play(Paths.sound('menus/scrollMenu'));
				updateOptionDisplay();
				FlxG.save.flush();
			}
			// Salir del modo edición con ENTER o ESC
			if (controls.ACCEPT || controls.BACK)
			{
				_editMode = false;
				_editModeIndicator.visible = false;
				FlxG.sound.play(Paths.sound('menus/confirmMenu'));
			}
			return;
		}

		// Navegación de categorías con ← →
		if (controls.LEFT_P && currentOptions.length > 0)
		{
			changeCategory(-1);
		}
		if (controls.RIGHT_P && currentOptions.length > 0)
		{
			changeCategory(1);
		}

		// Navegación de opciones ↑ ↓
		if (controls.UP_P)
		{
			changeSelection(-1);
		}
		if (controls.DOWN_P)
		{
			changeSelection(1);
		}

		// Ajuste izquierda/derecha para opciones con slider (p.ej. FPS Cap)
		// Cuando NO estamos en modo edición y la opción tiene funciones left/right.
		if (categories[curCategory] != 'Controls' && currentOptions.length > 0)
		{
			final opt = currentOptions[curSelected];
			if (FlxG.keys.justPressed.A || FlxG.keys.justPressed.LEFT)
			{
				if (opt.left != null)
				{
					FlxG.sound.play(Paths.sound('menus/scrollMenu'));
					opt.left();
					updateOptionDisplay();
				}
			}
			if (FlxG.keys.justPressed.D || FlxG.keys.justPressed.RIGHT)
			{
				if (opt.right != null)
				{
					FlxG.sound.play(Paths.sound('menus/scrollMenu'));
					opt.right();
					updateOptionDisplay();
				}
			}
		}

		// Aceptar/Toggle opción
		if (controls.ACCEPT && currentOptions.length > 0)
		{
			final opt = currentOptions[curSelected];

			// Si la opción tiene left/right (multi-valor), entrar en edit mode al pulsar ENTER
			if (opt.left != null || opt.right != null)
			{
				_editMode = true;
				_editModeIndicator.text = "⟵ A / D ⟶   Adjusting: " + opt.name + "   ENTER / ESC to confirm";
				_editModeIndicator.visible = true;
				FlxG.sound.play(Paths.sound('menus/scrollMenu'));
				return;
			}

			FlxG.sound.play(Paths.sound('menus/confirmMenu'));
			var optionName = opt.name;
			opt.toggle();
			updateOptionDisplay();
			FlxG.save.flush();

			// Si estamos en pause menu
			if (fromPause)
			{
				// Verificar si es una configuración SEGURA para aplicar en tiempo real
				if (isGameplaySetting(optionName))
				{
					applyGameplaySettingsRealtime();
				}
				// Si requiere reinicio y estamos en pausa dentro del PlayState → señalar rewind
				else if (requiresRestart(optionName))
				{
					if (fromPause && PlayState.instance != null)
					{
						FlxG.save.flush();
						pendingRewind = true;
						close(); // vuelve a PauseSubState que detectará pendingRewind
						isOpenOptions = false;
					}
					else
					{
						showWarning("Restart song to apply changes");
					}
				}
			}
		}

		// Reset keybinds con BACKSPACE (solo en Controls)
		if (FlxG.keys.justPressed.BACKSPACE && categories[curCategory] == 'Controls')
		{
			resetKeybinds();
		}

		// Volver
		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));

			if (fromPause)
			{
				fromPause = false;
				close();
				isOpenOptions = false;
			}
			else
			{
				StateTransition.switchState(new MainMenuState());
			}
		}

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	function changeCategory(change:Int)
	{
		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);
		curCategory += change;

		if (curCategory < 0)
			curCategory = categories.length - 1;
		if (curCategory >= categories.length)
			curCategory = 0;

		loadCategory(curCategory);
	}

	function changeSelection(change:Int)
	{
		if (currentOptions.length == 0)
			return;

		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);
		curSelected += change;

		if (curSelected < 0)
			curSelected = currentOptions.length - 1;
		if (curSelected >= currentOptions.length)
			curSelected = 0;

		updateOptionDisplay();
		_updateScroll();
	}

	// === KEYBIND FUNCTIONS ===

	function startBinding(keyIndex:Int)
	{
		bindingState = "binding";
		tempKey = keys[keyIndex];

		bindingIndicator.text = "Press any key for " + keyBindNames[keyIndex] + "...\nESC to cancel";
		bindingIndicator.visible = true;

		// Cambiar el valor mostrado a "?"
		optionValues.members[curSelected].text = "?";
	}

	function handleKeyBinding()
	{
		// Cancelar con ESC
		if (FlxG.keys.justPressed.ESCAPE)
		{
			keys[curSelected] = tempKey;
			bindingState = "select";
			bindingIndicator.visible = false;
			updateOptionDisplay();
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			return;
		}

		// Esperar cualquier tecla
		if (FlxG.keys.justPressed.ANY)
		{
			var pressedKey = FlxG.keys.getIsDown()[0].ID.toString();

			if (isKeyValid(pressedKey, curSelected))
			{
				keys[curSelected] = pressedKey;
				saveKeyBinds();
				bindingState = "select";
				bindingIndicator.visible = false;
				updateOptionDisplay();
				FlxG.sound.play(Paths.sound('menus/scrollMenu'));

				// Advertir si hay duplicados (pero permitirlos)
				if (hasDuplicateKeys())
				{
					showWarning("Warning: Duplicate keys detected");
				}
			}
			else
			{
				// Mostrar warning
				keys[curSelected] = tempKey;
				showWarning("Invalid key! Key is blocked.");
				bindingState = "select";
				bindingIndicator.visible = false;
				updateOptionDisplay();
				FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			}
		}
	}

	function isKeyValid(key:String, keyIndex:Int):Bool
	{
		// SPACE nunca se permite (se usa para UI)
		if (key == "SPACE") return false;

		// Para controles de dirección (0-3) y RESET (4): no permitir teclas reservadas de sistema
		if (keyIndex <= 4)
		{
			if (key == "ESCAPE" || key == "ENTER" || key == "BACKSPACE") return false;
		}

		// Para RESET (4): no puede coincidir con direcciones
		if (keyIndex == 4)
		{
			for (i in 0...4)
				if (keys[i] == key) return false;
		}

		return true;
	}

	/**
	 * Verifica si hay teclas duplicadas en las direcciones
	 */
	function hasDuplicateKeys():Bool
	{
		for (i in 0...4)
		{
			for (j in i + 1...4)
			{
				if (keys[i] == keys[j])
					return true;
			}
		}
		return false;
	}

	function resetKeybinds()
	{
		FlxG.sound.play(Paths.sound('menus/confirmMenu'));

		for (i in 0...keyBindNames.length)
		{
			keys[i] = defaultKeys[i];
		}

		saveKeyBinds();
		loadCategory(curCategory); // Recargar para actualizar valores

		showWarning("Keybinds reset to default!");
	}

	function showWarning(text:String)
	{
		warningText.text = text;
		warningText.alpha = 1;

		FlxTween.tween(warningText, {alpha: 0}, 0.5, {
			ease: FlxEase.circOut,
			startDelay: 2
		});
	}

	/**
	 * Determina si una configuración es SEGURA para aplicar en tiempo real
	 * Solo configuraciones visuales/UI que no afectan la lógica del juego
	 */
	function isGameplaySetting(optionName:String):Bool
	{
		var safeGameplaySettings = [
			"Ghost Tapping", // Seguro: solo afecta siguiente input
			"Show HUD", // Seguro: solo visual
			"Note Splashes", // Seguro: solo visual
			"Accuracy Display", // Seguro: solo visual
			"Anti-Aliasing" // Seguro: solo visual
		];

		// Configuraciones que REQUIEREN REINICIO (NO en tiempo real):
		// - Downscroll: requiere reposicionar strums y notas en vuelo
		// - Middlescroll: requiere reorganizar layout completo
		// - Perfect Mode/Sick Mode: cambian lógica de scoring
		// - Static Stage: puede causar memory leaks

		return safeGameplaySettings.contains(optionName);
	}

	/**
	 * Verifica si una configuración requiere reiniciar la canción
	 */
	function requiresRestart(optionName:String):Bool
	{
		var restartRequired = [
			"Downscroll",
			"Middlescroll",
			"Perfect Mode",
			"Sick Mode",
			"Static Stage",
			"Special Visual Effects",
			"GF Bye",
			"Background Bye",
			"Render Resolution"
		];

		return restartRequired.contains(optionName);
	}

	/**
	 * Aplica el alpha del lane backdrop al PlayState activo si existe.
	 * Si no hay PlayState activo (options desde menú), el cambio solo se
	 * persiste en FlxG.save.data y se aplicará al siguiente gameplay.
	 */
	private function _applyLaneBackdropAlpha(alpha:Float):Void
	{
		if (funkin.gameplay.PlayState.instance != null
			&& funkin.gameplay.PlayState.instance.laneBackdrop != null)
		{
			funkin.gameplay.PlayState.instance.laneBackdrop.alpha = alpha;
		}
	}

	/**
	 * Aplica las configuraciones de gameplay en tiempo real al PlayState
	 */
	function applyGameplaySettingsRealtime():Void
	{
		if (PlayState.instance != null)
		{
			trace('[OptionsMenuState] Applying gameplay settings in real-time');
			PlayState.instance.updateGameplaySettings();
		}
	}

	// === CLASE DE COMPATIBILIDAD PARA Main.hx ===

	/**
	 * Inicializa los valores por defecto de las opciones
	 * Llamado desde Main.hx
	 */
	public static function initSave():Void
	{
		OptionsData.initSave();
	}
}

/**
 * Clase de compatibilidad con el sistema antiguo
 */
class OptionsData
{
	public static function initSave():Void
	{
		if (FlxG.save.data.downscroll == null)
			FlxG.save.data.downscroll = false;

		// ── Display / Resolution ──────────────────────────────────────────────
		if (FlxG.save.data.renderResolution == null)
			FlxG.save.data.renderResolution = '1080p'; // '720p' o '1080p'

		if (FlxG.save.data.scaleMode == null)
			FlxG.save.data.scaleMode = 'letterbox'; // 'letterbox', 'widescreen', 'stretch', 'pixel'

		if (FlxG.save.data.shaders == null)
			FlxG.save.data.shaders = true;

		if (FlxG.save.data.vsync == null)
			FlxG.save.data.vsync = false;

		if (FlxG.save.data.accuracyDisplay == null)
			FlxG.save.data.accuracyDisplay = true;

		if (FlxG.save.data.notesplashes == null)
			FlxG.save.data.notesplashes = true;

		if (FlxG.save.data.middlescroll == null)
			FlxG.save.data.middlescroll = false;

		if (FlxG.save.data.HUD == null)
			FlxG.save.data.HUD = false;

		if (FlxG.save.data.camZoom == null)
			FlxG.save.data.camZoom = false;

		if (FlxG.save.data.flashing == null)
			FlxG.save.data.flashing = false;

		if (FlxG.save.data.offset == null)
			FlxG.save.data.offset = 0;

		if (FlxG.save.data.sickmode == null)
			FlxG.save.data.sickmode = false;

		if (FlxG.save.data.staticstage == null)
			FlxG.save.data.staticstage = false;

		if (FlxG.save.data.specialVisualEffects == null)
			FlxG.save.data.specialVisualEffects = true;

		if (FlxG.save.data.ghosttap == null)
			FlxG.save.data.ghosttap = true;

		if (FlxG.save.data.hitsounds == null)
			FlxG.save.data.hitsounds = false;

		if (FlxG.save.data.antialiasing == null)
			FlxG.save.data.antialiasing = true;

		// ── PathsCache: GPU texture caching ──────────────────────────────────
		// Por defecto activo en desktop (false en web/mobile sin context3D fiable).
		// Cuando está activo, los bitmaps se suben a VRAM y la copia en RAM se
		// libera → ahorro de ~4 MB por textura 1024×1024.
		if (FlxG.save.data.gpuCaching == null)
			FlxG.save.data.gpuCaching = #if (desktop && !hl) true #else false #end;

		// Sincronizar con PathsCache al arrancar
		funkin.cache.PathsCache.gpuCaching = FlxG.save.data.gpuCaching;

		// ── Low Memory Mode (inspirado en Codename Engine) ───────────────────
		if (FlxG.save.data.lowMemoryMode == null)
			FlxG.save.data.lowMemoryMode = false;
		funkin.cache.PathsCache.lowMemoryMode = FlxG.save.data.lowMemoryMode;

		// ── Streamed Music (no cachear audio de canciones) ───────────────────
		if (FlxG.save.data.streamedMusic == null)
			FlxG.save.data.streamedMusic = false;
		funkin.cache.PathsCache.streamedMusic = FlxG.save.data.streamedMusic;

		// ── Mobile controls ───────────────────────────────────────────────────
		#if mobileC
		if (FlxG.save.data.mobileAlpha == null)
			FlxG.save.data.mobileAlpha = 0.75;
		// mobilePadLayout se inicializa como null → Mobilecontrols usará posiciones default
		#end
	}
}

/**
 * OffsetCalibrationState — Calibración de offset de audio al estilo pro.
 *
 * Reproduce un click track generado por código a exactamente 120 BPM.
 * El usuario presiona SPACE en cada beat; tras 8 taps se calcula el offset
 * como promedio de (tiempo_tap - tiempo_beat_más_cercano).
 *
 * Teclas:
 *   SPACE   → Tap en el beat
 *   ← / →   → Ajustar offset ±1 ms manualmente
 *   R       → Resetear taps
 *   ESC     → Guardar y salir
 */
class OffsetCalibrationState extends MusicBeatSubstate
{
	// ── Constantes de ritmo ───────────────────────────────────────────────────
	static final BPM:Float         = 120.0;
	static final BEAT_SEC:Float    = 60.0 / BPM;      // 0.5 s
	static final MAX_TAPS:Int      = 8;
	static final CLICK_MUSIC:String = "offsetMusic";
	static final CLICK_SOUND:String = "menus/chartingSounds/metronome";

	// ── Estado del metrónomo ──────────────────────────────────────────────────
	var _beatTimer:Float  = 0.0;
	var _beatCount:Int    = 0;

	/** Timestamps de cada click (segundos absolutos desde apertura). */
	var _clickTimes:Array<Float> = [];

	/** Timestamps de cada tap del usuario. */
	var _tapTimes:Array<Float>   = [];

	/** Tiempo transcurrido desde que se abrió el substate. */
	var _elapsed:Float = 0.0;

	/** Countdown inicial de 2 s antes de empezar. */
	var _countdown:Float  = 2.0;
	var _counting:Bool    = true;

	// ── UI ────────────────────────────────────────────────────────────────────
	var _panel:FlxSprite;
	var _pulseDot:FlxSprite;
	var _tapBar:FlxSprite;          // Barra de progreso de taps
	var _tapBarFill:FlxSprite;
	var _offsetTxt:FlxText;
	var _tapsTxt:FlxText;
	var _feedbackTxt:FlxText;
	var _countdownTxt:FlxText;
	var _resultsTxt:FlxText;

	// Línea de tiempo visual — último tap vs último beat
	var _timelineBg:FlxSprite;
	var _timelineBeat:FlxSprite;
	var _timelineTap:FlxSprite;

	override function create()
	{
		super.create();
		funkin.audio.SoundTray.blockInput = true; // No cambiar volumen con +/-

		MusicManager.playWithFade(CLICK_MUSIC, 0.7, 4.0);

		// ── Fondo oscuro ──────────────────────────────────────────────────────
		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF000000);
		bg.alpha = 0.88;
		add(bg);

		// ── Panel central ─────────────────────────────────────────────────────
		_panel = new FlxSprite(0, 0).makeGraphic(820, 580, 0xFF141428);
		_panel.screenCenter();
		add(_panel);

		// Borde del panel
		var border = new FlxSprite(_panel.x - 2, _panel.y - 2).makeGraphic(824, 584, 0xFF5555FF);
		border.alpha = 0.4;
		addBehindSprite(_panel, border);
		add(border);

		// ── Título ────────────────────────────────────────────────────────────
		var title = new FlxText(0, _panel.y + 24, FlxG.width, "OFFSET CALIBRATION", 38);
		title.setFormat(Paths.font("vcr.ttf"), 38, FlxColor.WHITE, CENTER, OUTLINE, 0xFF5555FF);
		title.borderSize = 2;
		add(title);

		var bpmLabel = new FlxText(0, _panel.y + 68, FlxG.width, "♩ = " + Std.int(BPM) + " BPM", 18);
		bpmLabel.setFormat(Paths.font("vcr.ttf"), 18, 0xFF8888FF, CENTER);
		add(bpmLabel);

		// ── Instrucciones ─────────────────────────────────────────────────────
		var instr = new FlxText(0, _panel.y + 100, FlxG.width,
			"Press SPACE in sync with the metronome beat.\nRepeat " + MAX_TAPS + " times to calculate offset.", 20);
		instr.setFormat(Paths.font("vcr.ttf"), 20, 0xFFCCCCCC, CENTER);
		add(instr);

		// ── Punto pulsante central ────────────────────────────────────────────
		_pulseDot = new FlxSprite(0, _panel.y + 200).makeGraphic(80, 80, 0xFF5555FF);
		_pulseDot.screenCenter(X);
		_pulseDot.alpha = 0.15;
		add(_pulseDot);

		// ── Línea de tiempo (diff visual entre tap y beat) ────────────────────
		_timelineBg = new FlxSprite(0, _panel.y + 305).makeGraphic(500, 6, 0xFF333355);
		_timelineBg.screenCenter(X);
		add(_timelineBg);

		// Marcador central (= beat perfecto)
		var centerMark = new FlxSprite(_timelineBg.x + 247, _panel.y + 296).makeGraphic(6, 24, 0xFF5555FF);
		add(centerMark);

		// Indicador de beat (azul, siempre en el centro)
		_timelineBeat = new FlxSprite(_timelineBg.x + 247, _panel.y + 299).makeGraphic(6, 18, 0xFF4488FF);
		add(_timelineBeat);

		// Indicador de tap (amarillo, se mueve según el error)
		_timelineTap = new FlxSprite(_timelineBg.x + 247, _panel.y + 299).makeGraphic(6, 18, FlxColor.YELLOW);
		_timelineTap.alpha = 0;
		add(_timelineTap);

		var earlyLabel = new FlxText(_timelineBg.x - 2, _panel.y + 315, 50, "EARLY", 11);
		earlyLabel.setFormat(Paths.font("vcr.ttf"), 11, 0xFF8888CC, LEFT);
		add(earlyLabel);
		var lateLabel = new FlxText(_timelineBg.x + 460, _panel.y + 315, 50, "LATE", 11);
		lateLabel.setFormat(Paths.font("vcr.ttf"), 11, 0xFF8888CC, RIGHT);
		add(lateLabel);

		// ── Barra de progreso de taps ─────────────────────────────────────────
		_tapBar = new FlxSprite(0, _panel.y + 345).makeGraphic(500, 16, 0xFF222244);
		_tapBar.screenCenter(X);
		add(_tapBar);
		_tapBarFill = new FlxSprite(_tapBar.x, _tapBar.y).makeGraphic(4, 16, 0xFF5555FF);
		add(_tapBarFill);

		// ── Textos de estado ─────────────────────────────────────────────────
		_tapsTxt = new FlxText(0, _panel.y + 368, FlxG.width, "Taps: 0 / " + MAX_TAPS, 20);
		_tapsTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER);
		add(_tapsTxt);

		_feedbackTxt = new FlxText(0, _panel.y + 396, FlxG.width, "", 18);
		_feedbackTxt.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.YELLOW, CENTER, OUTLINE, FlxColor.BLACK);
		_feedbackTxt.borderSize = 1;
		add(_feedbackTxt);

		_resultsTxt = new FlxText(0, _panel.y + 422, FlxG.width, "", 22);
		_resultsTxt.setFormat(Paths.font("vcr.ttf"), 22, FlxColor.LIME, CENTER, OUTLINE, FlxColor.BLACK);
		_resultsTxt.borderSize = 2;
		add(_resultsTxt);

		// ── Offset actual ─────────────────────────────────────────────────────
		_offsetTxt = new FlxText(0, _panel.y + 462, FlxG.width,
			"Current Offset: " + (FlxG.save.data.offset ?? 0) + " ms", 26);
		_offsetTxt.setFormat(Paths.font("vcr.ttf"), 26, FlxColor.YELLOW, CENTER, OUTLINE, FlxColor.BLACK);
		_offsetTxt.borderSize = 2;
		add(_offsetTxt);

		// ── Controles ─────────────────────────────────────────────────────────
		var ctrl = new FlxText(0, _panel.y + 510, FlxG.width,
			"SPACE: Tap  |  ← →: ±1 ms  |  R: Reset  |  ESC: Save & Back", 15);
		ctrl.setFormat(Paths.font("vcr.ttf"), 15, 0xFF888888, CENTER);
		add(ctrl);

		// ── Countdown overlay ─────────────────────────────────────────────────
		_countdownTxt = new FlxText(0, 0, FlxG.width, "2", 90);
		_countdownTxt.setFormat(Paths.font("vcr.ttf"), 90, FlxColor.WHITE, CENTER, OUTLINE, 0xFF5555FF);
		_countdownTxt.borderSize = 4;
		_countdownTxt.screenCenter(Y);
		add(_countdownTxt);

		if (FlxG.save.data.offset == null) FlxG.save.data.offset = 0;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		_elapsed += elapsed;

		// ── Countdown ─────────────────────────────────────────────────────────
		if (_counting)
		{
			_countdown -= elapsed;
			var display = Math.ceil(_countdown);
			_countdownTxt.text = display > 0 ? Std.string(display) : "GO!";
			_countdownTxt.alpha = FlxMath.lerp(_countdownTxt.alpha, _countdown > 0 ? 1.0 : 0.0, elapsed * 8);

			if (_countdown <= -0.3)
			{
				_counting = false;
				_countdownTxt.visible = false;
				_beatTimer = 0;
				_elapsed   = 0;
			}
			return; // no input durante countdown
		}

		// ── Metrónomo ─────────────────────────────────────────────────────────
		_beatTimer += elapsed;
		if (_beatTimer >= BEAT_SEC)
		{
			_beatTimer -= BEAT_SEC;
			_beatCount++;
			FlxG.sound.play(Paths.soundRandom(CLICK_SOUND,1,2), 0.3);
			_clickTimes.push(_elapsed - _beatTimer); // tiempo exacto del beat
			_pulseDot.alpha = 1.0;
			_pulseDot.scale.set(1.35, 1.35);
		}

		// Animar punto pulsante
		_pulseDot.alpha   = FlxMath.lerp(_pulseDot.alpha,   0.12, elapsed * 9);
		_pulseDot.scale.x = FlxMath.lerp(_pulseDot.scale.x, 1.0,  elapsed * 9);
		_pulseDot.scale.y = FlxMath.lerp(_pulseDot.scale.y, 1.0,  elapsed * 9);
		_pulseDot.updateHitbox();
		_pulseDot.screenCenter(X);

		// Fade del indicador de tap en la timeline
		if (_timelineTap.alpha > 0)
			_timelineTap.alpha = FlxMath.lerp(_timelineTap.alpha, 0.0, elapsed * 3);

		// ── Input ─────────────────────────────────────────────────────────────
		if (FlxG.keys.justPressed.SPACE) _doTap();

		if (FlxG.keys.justPressed.LEFT || FlxG.keys.justPressed.A)
		{
			FlxG.save.data.offset -= 1;
			_updateOffsetTxt();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.5);
		}
		if (FlxG.keys.justPressed.RIGHT || FlxG.keys.justPressed.D)
		{
			FlxG.save.data.offset += 1;
			_updateOffsetTxt();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.5);
		}

		if (FlxG.keys.justPressed.R) _reset();

		if (FlxG.keys.justPressed.ESCAPE || controls.BACK)
		{
			funkin.audio.SoundTray.blockInput = false;
			FlxG.save.flush();
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			MusicManager.playWithFade('freakyMenu', 0.7, 4.0);
			close();
		}
	}

	function _doTap():Void
	{
		if (_beatCount == 0) return; // Esperar al menos un beat

		// Calcular diferencia con el beat más cercano
		var tapTime = _elapsed - _beatTimer; // tiempo absoluto del tap en la escala del metrónomo
		var beatPhase = _beatTimer;           // fracción de beat actual (0 = justo en el beat)
		// Normalizar al rango [-BEAT_SEC/2, BEAT_SEC/2]
		var diff = beatPhase;
		if (diff > BEAT_SEC / 2) diff -= BEAT_SEC;
		var diffMs = Std.int(diff * 1000);

		_tapTimes.push(diffMs);
		_tapsTxt.text = "Taps: " + _tapTimes.length + " / " + MAX_TAPS;

		// Barra de progreso
		var pct = Math.min(1.0, _tapTimes.length / MAX_TAPS);
		_tapBarFill.makeGraphic(Std.int(Math.max(4, Std.int(500 * pct))), 16, 0xFF5555FF);

		// Timeline visual: posición del tap relativa al beat
		var lineW:Float = 500;
		var halfBeat    = BEAT_SEC / 2;
		var normDiff    = (diff / halfBeat) * 0.5; // -0.5 .. +0.5
		_timelineTap.x  = _timelineBg.x + 247 + normDiff * lineW * 0.5;
		_timelineTap.alpha = 1.0;
		_timelineTap.color = diffMs < -20 ? 0xFF4488FF
		                   : diffMs >  20 ? FlxColor.RED
		                   :                FlxColor.LIME;

		// Feedback inmediato
		if (Math.abs(diffMs) < 15)
			_feedbackTxt.text = "Perfect!";
		else if (diffMs < 0)
			_feedbackTxt.text = "Early (" + diffMs + " ms)";
		else
			_feedbackTxt.text = "Late (+" + diffMs + " ms)";

		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);

		if (_tapTimes.length >= MAX_TAPS) _calculateOffset();
	}

	function _calculateOffset():Void
	{
		var sum:Float = 0;
		for (t in _tapTimes) sum += t;
		var avg = Std.int(sum / _tapTimes.length);

		FlxG.save.data.offset = avg;
		_updateOffsetTxt();
		_resultsTxt.text = "Calculated: " + avg + " ms — Saved!";
		FlxG.sound.play(Paths.sound('menus/confirmMenu'));

		// Flash del panel
		_pulseDot.alpha = 1.0;
		_pulseDot.color = FlxColor.LIME;
		_tapTimes = [];
		_tapsTxt.text = "Taps: 0 / " + MAX_TAPS;
		_tapBarFill.makeGraphic(4, 16, 0xFF5555FF);
	}

	function _reset():Void
	{
		_tapTimes = [];
		_tapsTxt.text = "Taps: 0 / " + MAX_TAPS;
		_feedbackTxt.text = "";
		_resultsTxt.text = "";
		_tapBarFill.makeGraphic(4, 16, 0xFF5555FF);
		FlxG.save.data.offset = 0;
		_updateOffsetTxt();
		FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.6);
	}

	function _updateOffsetTxt():Void
	{
		_offsetTxt.text = "Current Offset: " + (FlxG.save.data.offset ?? 0) + " ms";
	}

	/** Añade un sprite justo detrás de otro en la display list. */
	function addBehindSprite(target:FlxSprite, spr:FlxSprite):Void
	{
		// simplificado — spr ya se añade antes que _panel, así que queda detrás
	}
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * RatingPositionSubState — Editor visual de posición del popup de rating.
 *
 * Muestra una recreación simplificada del HUD de gameplay y un popup de
 * rating de ejemplo que el usuario puede mover con WASD / flechas o arrastrando
 * con el ratón. Guarda los offsets en FlxG.save.data.ratingOffsetX / ratingOffsetY.
 */
class RatingPositionSubState extends FlxSubState
{
	// Offset acumulado (píxeles desde la posición base del juego)
	var _offsetX:Int = 0;
	var _offsetY:Int = 0;

	// Sprites de la preview
	var _ratingPreview:FlxSprite;
	var _sickLabel:FlxText;
	var _comboPreview:Array<FlxSprite> = [];

	// HUD simulado
	var _healthBarFill:FlxSprite;
	var _scoreTxt:FlxText;

	// UI del editor
	var _crosshairH:FlxSprite;
	var _crosshairV:FlxSprite;
	var _positionTxt:FlxText;

	// Velocidad de movimiento (px/frame)
	static final MOVE_SPEED:Float = 2.0;
	static final FAST_SPEED:Float = 10.0;

	// Posición base del rating (igual que en script.hx por defecto)
	var _baseX:Float;
	var _baseY:Float;

	// Demo bounce
	var _demoTimer:Float = 0.0;

	// ── Mouse drag ────────────────────────────────────────────────────────────
	var _dragging:Bool    = false;
	var _dragStartMouseX:Float = 0;
	var _dragStartMouseY:Float = 0;
	var _dragStartOffX:Int = 0;
	var _dragStartOffY:Int = 0;

	var posX:Float = 0;
	var posY:Float = 0;

	function onInit()
	{
		// Leer los offsets guardados (default: posición base original = -50, 0)
		posX = (FlxG.save.data.ratingOffsetX != null) ? FlxG.save.data.ratingOffsetX : -100;
		posY = (FlxG.save.data.ratingOffsetY != null) ? FlxG.save.data.ratingOffsetY : 0;
	}

	override function create()
	{
		super.create();

		_offsetX = FlxG.save.data.ratingOffsetX != null ? FlxG.save.data.ratingOffsetX : 0;
		_offsetY = FlxG.save.data.ratingOffsetY != null ? FlxG.save.data.ratingOffsetY : 0;

		// ── Fondo oscuro ──────────────────────────────────────────────────────
		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.82;
		add(bg);

		// ── HUD simulado ──────────────────────────────────────────────────────
		_buildSimulatedHUD();

		// ── Posición base ─────────────────────────────────────────────────────
		_baseX = FlxG.width  * 0.55 - 40;
		_baseY = FlxG.height * 0.5  - 90;

		// Línea de referencia Y base
		var refLine = new FlxSprite(0, _baseY).makeGraphic(FlxG.width, 1, 0xFF5555FF);
		refLine.alpha = 0.30;
		add(refLine);

		var baseRef = new FlxText(_baseX, _baseY - 14, 0, "▼ BASE", 11);
		baseRef.setFormat(Paths.font("vcr.ttf"), 11, 0xFF5555FF, LEFT);
		add(baseRef);

		// ── Crosshairs ────────────────────────────────────────────────────────
		_crosshairH = new FlxSprite(0, 0).makeGraphic(FlxG.width, 1, 0xFFFFFF00);
		_crosshairH.alpha = 0.30;
		add(_crosshairH);

		_crosshairV = new FlxSprite(0, 0).makeGraphic(1, FlxG.height, 0xFFFFFF00);
		_crosshairV.alpha = 0.30;
		add(_crosshairV);

		onInit();

		// ── Rating preview ────────────────────────────────────────────────────
		_ratingPreview = new FlxSprite(FlxG.width * 0.55 - 40 + posX,FlxG.height * 0.5 - 90 + posY);
		_ratingPreview.loadGraphic(Paths.image('UI/normal/score/sick'));
		_ratingPreview.setGraphicSize(Std.int(_ratingPreview.width * 0.7));
		_ratingPreview.antialiasing = FlxG.save.data.antialiasing;
		_ratingPreview.updateHitbox();
		add(_ratingPreview);

		// Borde del preview
		var previewBorder = new FlxSprite();
		previewBorder.makeGraphic(204, 94, 0xFF5555FF);
		previewBorder.alpha = 0.6;
		add(previewBorder);

		_sickLabel = new FlxText(0, 0, 200, "SICK!", 32);
		_sickLabel.setFormat(Paths.font("vcr.ttf"), 32, 0xFFCCCCFF, CENTER, OUTLINE, FlxColor.BLACK);
		_sickLabel.borderSize = 2;
		_sickLabel.visible = false;
		add(_sickLabel);

		// Números del combo de demo
		for (i in 0...3)
		{
			var num = new FlxSprite();
			num.makeGraphic(40, 40, 0xFF1A2244);
			add(num);
			_comboPreview.push(num);
		}

		// Etiqueta "drag me"
		var dragLabel = new FlxText(0, 0, 200, "drag me ↕↔", 11);
		dragLabel.setFormat(Paths.font("vcr.ttf"), 11, 0xFF888888, CENTER);
		add(dragLabel);

		// ── Panel inferior ────────────────────────────────────────────────────
		var infoBg = new FlxSprite(0, FlxG.height - 64).makeGraphic(FlxG.width, 64, 0xFF0A0A1A);
		infoBg.alpha = 0.95;
		add(infoBg);

		_positionTxt = new FlxText(0, FlxG.height - 58, FlxG.width, "", 18);
		_positionTxt.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER);
		add(_positionTxt);

		var hint = new FlxText(0, FlxG.height - 36, FlxG.width,
			"WASD/Arrows: Move  |  SHIFT: Fast  |  Mouse Drag  |  R: Reset  |  ENTER/ESC: Save", 14);
		hint.setFormat(Paths.font("vcr.ttf"), 14, 0xFF888888, CENTER);
		add(hint);

		// ── Título superior ───────────────────────────────────────────────────
		var titleBg = new FlxSprite(0, 0).makeGraphic(FlxG.width, 36, 0xFF0A0A1A);
		titleBg.alpha = 0.92;
		add(titleBg);
		var title = new FlxText(0, 6, FlxG.width, "RATING POSITION EDITOR", 20);
		title.setFormat(Paths.font("vcr.ttf"), 20, 0xFF8888FF, CENTER);
		add(title);

		FlxG.mouse.visible = true;
		_applyPosition();
		_updateUI();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// ── Mouse drag ────────────────────────────────────────────────────────
		if (FlxG.mouse.justPressed)
		{
			// Solo iniciar drag si el clic está sobre el rating preview
			var mx = FlxG.mouse.x;
			var my = FlxG.mouse.y;
			if (mx >= _ratingPreview.x && mx <= _ratingPreview.x + _ratingPreview.width
			&&  my >= _ratingPreview.y && my <= _ratingPreview.y + _ratingPreview.height + 50)
			{
				_dragging       = true;
				_dragStartMouseX = mx;
				_dragStartMouseY = my;
				_dragStartOffX  = _offsetX;
				_dragStartOffY  = _offsetY;
			}
		}

		if (FlxG.mouse.justReleased)
			_dragging = false;

		if (_dragging)
		{
			_offsetX = _dragStartOffX + Std.int(FlxG.mouse.x - _dragStartMouseX);
			_offsetY = _dragStartOffY + Std.int(FlxG.mouse.y - _dragStartMouseY);
			_applyPosition();
			_updateUI();
		}

		// ── Teclado ───────────────────────────────────────────────────────────
		if (!_dragging)
		{
			var fast  = FlxG.keys.pressed.SHIFT;
			var speed = fast ? FAST_SPEED : MOVE_SPEED;
			var moved = false;

			if (FlxG.keys.pressed.LEFT  || FlxG.keys.pressed.A) { _offsetX -= Std.int(speed); moved = true; }
			if (FlxG.keys.pressed.RIGHT || FlxG.keys.pressed.D) { _offsetX += Std.int(speed); moved = true; }
			if (FlxG.keys.pressed.UP    || FlxG.keys.pressed.W) { _offsetY -= Std.int(speed); moved = true; }
			if (FlxG.keys.pressed.DOWN  || FlxG.keys.pressed.S) { _offsetY += Std.int(speed); moved = true; }

			if (FlxG.keys.justPressed.R)
			{
				_offsetX = 0; _offsetY = 0;
				moved = true;
				FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.6);
			}

			if (moved) { _applyPosition(); _updateUI(); }
		}

		// Demo bounce
		_demoTimer += elapsed;
		var bounce = Math.sin(_demoTimer * 3.5) * 3;
		if (!_dragging)
			_ratingPreview.y = _baseY + _offsetY + bounce;

		// Cursor de mano cuando está sobre el rating
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		var overPreview = (mx >= _ratingPreview.x && mx <= _ratingPreview.x + _ratingPreview.width
		               &&  my >= _ratingPreview.y && my <= _ratingPreview.y + _ratingPreview.height + 50);
		FlxG.mouse.useSystemCursor = !overPreview;

		// Sincronizar sickLabel y combo con ratingPreview.y (que puede estar en bounce)
		_sickLabel.x = _ratingPreview.x;
		_sickLabel.y = _ratingPreview.y + 20;
		for (i in 0..._comboPreview.length)
			_comboPreview[i].setPosition(
				_ratingPreview.x + (44 * i) - 10 + 140,
				_ratingPreview.y + _ratingPreview.height + 4);

		if (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.ESCAPE)
		{
			FlxG.mouse.useSystemCursor = false;
			_save();
			close();
		}
	}

	function _buildSimulatedHUD():Void
	{
		var hbY = FlxG.height * 0.88;

		var hbBg = new FlxSprite(0, hbY).makeGraphic(600, 22, 0xFF333333);
		hbBg.screenCenter(X);
		add(hbBg);

		_healthBarFill = new FlxSprite(hbBg.x + 2, hbY + 2).makeGraphic(296, 18, 0xFF66FF33);
		add(_healthBarFill);

		// Iconos de salud simulados
		var iconP1 = new FlxSprite(hbBg.x + 296 - 20, hbY - 10).makeGraphic(30, 30, 0xFF44AAFF);
		add(iconP1);
		var iconP2 = new FlxSprite(hbBg.x + 296 - 48, hbY - 10).makeGraphic(30, 30, 0xFFFF4444);
		add(iconP2);

		_scoreTxt = new FlxText(0, hbY - 28, FlxG.width, "Score: 123,456   Misses: 0   Acc: 100.00%", 18);
		_scoreTxt.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		_scoreTxt.borderSize = 1;
		add(_scoreTxt);
	}

	function _applyPosition():Void
	{
		var rx:Float = _baseX + _offsetX;
		var ry:Float = _baseY + _offsetY;

		_ratingPreview.x = rx;
		_ratingPreview.y = ry;

		_crosshairH.y = ry + _ratingPreview.height / 2;
		_crosshairV.x = rx + _ratingPreview.width  / 2;
	}

	function _updateUI():Void
	{
		var label = (_offsetX == 0 && _offsetY == 0) ? "  (default)" : "";
		_positionTxt.text = 'Offset   X: $_offsetX px    Y: $_offsetY px$label';
	}

	function _save():Void
	{
		FlxG.save.data.ratingOffsetX = _offsetX;
		FlxG.save.data.ratingOffsetY = _offsetY;
		FlxG.save.flush();
		FlxG.sound.play(Paths.sound('menus/confirmMenu'));
	}
}
