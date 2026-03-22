package funkin.system;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.system.scaleModes.RatioScaleMode;
import flixel.system.scaleModes.StageSizeScaleMode;
import openfl.display.Sprite;
import openfl.display.Stage;
import openfl.events.Event;
import lime.app.Application;

using StringTools;

/**
 * WindowManager — management of window, scaling, opacidad and visibilidad of sprites.
 *
 * ─── Features (v2) ────────────────────────────────────────────────────
 *  1. Modos de escala: LETTERBOX, STRETCH, PIXEL_PERFECT.
 *  2. Invalidación of caches of cameras in resize (anti-artefactos).
 *  3. DPI-awareness en Windows.
 *  4. NUEVO: Control de opacidad de ventana (setWindowOpacity).
 *  5. NUEVO: Ocultar/mostrar la ventana (hide / show / setWindowVisible).
 *  6. new: Modo "spotlight" — only ciertos sprites are visibles,
 *            the resto is oculta automatically. Ideal for cutscenes where
 *            a unique character habla over a fondo negro, or for effects
 *            de "foco" en un personaje durante el gameplay.
 *  7. new: setLayerVisible — oculta/muestra grupos of sprites by camera.
 *
 * ─── API de visibilidad de sprites ──────────────────────────────────────────
 *
 *   // Ocultar ventana completamente (cursor visible, sin contenido):
 *   WindowManager.hide();
 *   WindowManager.show();
 *
 *   // Opacidad de ventana (0.0 = invisible, 1.0 = normal):
 *   WindowManager.setWindowOpacity(0.5);
 *
 *   // Spotlight: only bf visible, all it demás is hides:
 *   WindowManager.beginSpotlight([bfCharacter]);
 *   WindowManager.endSpotlight(); // restaura visibilidades
 *
 *   // Spotlight with sprites individuales + camera negra of fondo:
 *   WindowManager.beginSpotlight([bfSprite, dialogueBox], blackBackground: true);
 *
 * @author  Cool Engine Team
 * @since   0.5.2
 */
class WindowManager
{
	// ── Configuration ──────────────────────────────────────────────────────────

	public static var scaleMode(default, null):ScaleMode = LETTERBOX;
	public static var minWidth:Int     = 640;
	public static var minHeight:Int    = 360;
	public static var repositionHUD:Bool = true;
	public static var initialized(default, null):Bool = false;

	static var _baseWidth:Int  = 1280;
	static var _baseHeight:Int = 720;

	// ── Spotlight state ────────────────────────────────────────────────────────

	/** true while the modo spotlight is active. */
	public static var spotlightActive(default, null):Bool = false;

	/**
	 * Sprites that are in the spotlight (only ellos are visibles).
	 * Save also the FlxSprite of the fondo negro if blackBackground = true.
	 */
	static var _spotlightSprites:Array<FlxSprite> = [];

	/**
	 * Snapshots de visibilidad antes del spotlight.
	 * key → objeto FlxBasic, value → visibilidad original.
	 */
	static var _visibilitySnapshot:Map<Int, Bool> = [];

	/** Fondo negro creado por beginSpotlight cuando blackBackground = true. */
	static var _spotlightBg:FlxSprite = null;

	/** ID unique for the Map of snapshot (usamos object.ID of Flixel) */
	static var _snapshotTaken:Bool = false;

	// ── Init ─────────────────────────────────────────────────────────────────

	public static function init(mode:ScaleMode = LETTERBOX, minW:Int = 640, minH:Int = 360,
		baseW:Int = 1280, baseH:Int = 720):Void
	{
		if (initialized) return;

		_baseWidth  = baseW;
		_baseHeight = baseH;
		minWidth    = minW;
		minHeight   = minH;

		_registerDPIAwareness();
		applyScaleMode(mode);

		FlxG.signals.gameResized.add(_onResize);

		#if !html5
		if (Application.current != null && Application.current.window != null)
			Application.current.window.onResize.add(_onLimeResize);
		#end

		initialized = true;
		trace('[WindowManager] Inicializado. Modo=$mode  Base=${baseW}×${baseH}  Min=${minW}×${minH}');
	}

	// ── Scale modes ────────────────────────────────────────────────────────────

	public static function applyScaleMode(mode:ScaleMode):Void
	{
		scaleMode = mode;
		switch (mode)
		{
			case LETTERBOX:
				FlxG.scaleMode = new RatioScaleMode(false);
			case STRETCH:
				FlxG.scaleMode = new StageSizeScaleMode();
			case PIXEL_PERFECT:
				FlxG.scaleMode = new PixelPerfectScaleMode(_baseWidth, _baseHeight);
			case WIDESCREEN:
				FlxG.scaleMode = new WideRatioScaleMode(_baseWidth, _baseHeight);
		}
	}

	/**
	 * Version string of applyScaleMode — for callr from scripts without
	 * necesitar importar el enum ScaleMode.
	 * Valores: "letterbox" (default), "stretch", "pixel" / "pixel_perfect", "widescreen"
	 */
	public static function applyScaleModeByName(name:String):Void
	{
		applyScaleMode(switch (name.toLowerCase())
		{
			case 'stretch':                     STRETCH;
			case 'pixel', 'pixel_perfect':      PIXEL_PERFECT;
			case 'widescreen', 'wide':          WIDESCREEN;
			default:                            LETTERBOX;
		});
	}

	/**
	 * Is the modo widescreen active in this momento?
	 * Useful for that PlayState and the HUD sepan if deben redistribuirse.
	 */
	public static var isWidescreen(get, never):Bool;
	static inline function get_isWidescreen():Bool return scaleMode == WIDESCREEN;

	// ── Fullscreen ────────────────────────────────────────────────────────────

	public static function toggleFullscreen():Void
		FlxG.fullscreen = !FlxG.fullscreen;

	public static var isFullscreen(get, never):Bool;
	static inline function get_isFullscreen():Bool return FlxG.fullscreen;

	public static function minimize():Void
	{
		#if !html5
		if (Application.current?.window != null)
			Application.current.window.minimized = true;
		#end
	}

	public static function restore():Void
	{
		#if !html5
		if (Application.current?.window != null)
			Application.current.window.minimized = false;
		#end
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  BRANDING of mod: title and icono in runtime, without recompiling
	// ══════════════════════════════════════════════════════════════════════════

	/** Title that use the engine if no there is mod active ni title capturado of the window. */
	static inline var DEFAULT_TITLE:String = "Friday Night Funkin\': Cool Engine";
	/** Title original of the app, saved the first vez that is changes. */
	static var _defaultTitle:Null<String> = null;
	/** true si el icono actual fue cargado desde un mod (para restaurarlo). */
	static var _usingModIcon:Bool = false;

	/** Avoid appliesr the icon by default more of a vez to the start. */
	static var _defaultIconApplied:Bool = false;

	/**
	 * Paths candidatas of the PNG of icon by default (in orden of preferencia).
	 * Ajusta a donde tengas tu iconOG.png.
	 */
	static final DEFAULT_ICON_PATHS:Array<String> = [
		'art/iconOG.png',
		'art/icon64.png',
		'art/icon32.png',
		'assets/images/icon.png',
		'icon.png',
	];

	/**
	 * Load the PNG of icon by default from disco and call to win.setIcon().
	 *
	 * FIX: openfl.Assets.getBitmapData('icon.png') crasheaba porque Lime
	 * incrusta the icon in the .exe with <icon> but no it registra in the
	 * manifiesto de OpenFL → getBitmapData lanza "asset not found".
	 * Cargarlo directamente desde disco con lime.graphics.Image.fromFile()
	 * funciona siempre que el PNG exista en la carpeta del ejecutable.
	 */
	static function _restoreDefaultIcon(win:lime.ui.Window):Void
	{
		// Option 1 — haxe.Resource (GARANTIZADO dentro of the exe)
		// Project.xml: <haxeresource path="art/iconOG.png" name="AppIcon" />
		// Lime compila el PNG como recurso Haxe. haxe.Resource.getBytes() siempre
		// works without importar from where is ejecute the binario.
		try
		{
			final bytes = haxe.Resource.getBytes('AppIcon');
			if (bytes != null)
			{
				final img = lime.graphics.Image.fromBytes(bytes);
				if (img != null)
				{
					win.setIcon(img);
					trace('[WindowManager] Icono cargado desde haxe.Resource.');
					return;
				}
			}
		}
		catch (_:Dynamic) {}

		// Option 2 — openfl.Assets (by if there is otra forma of embed active)
		try
		{
			final limeImg = lime.utils.Assets.getImage('AppIcon');
			if (limeImg != null) { win.setIcon(limeImg); trace('[WindowManager] Icono desde lime.Assets.'); return; }
		}
		catch (_:Dynamic) {}

		// Option 3 — fallback in disco (desarrollo local)
		#if sys
		final exeDir = haxe.io.Path.directory(Sys.programPath()).replace('\\', '/');
		for (rel in DEFAULT_ICON_PATHS)
		{
			for (base in [exeDir, Sys.getCwd().replace('\\', '/')])
			{
				final path = '$base/$rel';
				if (!sys.FileSystem.exists(path)) continue;
				try
				{
					final img = lime.graphics.Image.fromFile(path);
					if (img != null) { win.setIcon(img); trace('[WindowManager] Icono desde disco: $path'); return; }
				}
				catch (_:Dynamic) {}
			}
		}
		trace('[WindowManager] No is encontró PNG of icon in none path.');
		#end
	}

	/**
	 * Applies the branding (title and icono) of a ModInfo to the startup or to the change of mod.
	 * Si info es null, restaura los valores por defecto del engine.
	 *
	 * Fields leídos of mod.json:
	 *   "appTitle": "Mi Mod — FNF"   ← title of the window of the OS
	 *   "appIcon":  "icon"            ← PNG in the root of the mod, without extension
	 *
	 * Ejemplo de uso en Main.hx:
	 *   ModManager.onModChanged = function(id) {
	 *       WindowManager.applyModBranding(ModManager.activeInfo());
	 *   };
	 */
	public static function applyModBranding(info:mods.ModManager.ModInfo):Void
	{
		#if !html5
		final win = lime.app.Application.current?.window;
		if (win == null) return;

		// ── Save title default the first vez ─────────────────────────────
		if (_defaultTitle == null)
			_defaultTitle = win.title;

		// ── Title ───────────────────────────────────────────────────────────
		if (info != null && info.appTitle != null && info.appTitle.trim() != '')
			win.title = info.appTitle;
		else
			win.title = (_defaultTitle != null && _defaultTitle.trim() != '') ? _defaultTitle : DEFAULT_TITLE;

		// ── Icono ────────────────────────────────────────────────────────────
		#if sys
		// FIX: to the startup always appliesr the icon by default via setIcon().
		// Lime incrusta el PNG en el .exe pero Windows solo lo muestra en el
		// explorador — the window in runtime necesita setIcon() explicit.
		if (!_defaultIconApplied)
		{
			_defaultIconApplied = true;
			_restoreDefaultIcon(win);
		}
		if (info != null && info.appIcon != null && info.appIcon.trim() != '')
		{
			// Search the PNG: first with the name tal cual, then adding .png
			var iconPath = '${info.folder}/${info.appIcon}';
			if (!sys.FileSystem.exists(iconPath))
				iconPath = '$iconPath.png';

			if (sys.FileSystem.exists(iconPath))
			{
				try
				{
					// lime.graphics.Image.fromFile() carga el PNG directamente en memoria
					// Application.window.setIcon() sends it to the OS without recompiling
					final img = lime.graphics.Image.fromFile(iconPath);
					if (img != null)
					{
						win.setIcon(img);
						_usingModIcon = true;
						trace('[WindowManager] Icono de mod aplicado: $iconPath');
					}
				}
				catch (e:Dynamic)
				{
					trace('[WindowManager] Error cargando icono de mod "$iconPath": $e');
				}
			}
			else
			{
				trace('[WindowManager] Icono de mod not found: $iconPath');
			}
		}
		else if (_usingModIcon)
		{
			// Without icon of mod → restaurar the icon by default from disco.
			_restoreDefaultIcon(win);
			_usingModIcon = false;
		}
		#end

		trace('[WindowManager] Branding appliesdo → title="${win.title}" modIcon=$_usingModIcon');
		#end
	}

	public static function setWindowBounds(x:Int, y:Int, w:Int, h:Int):Void
	{
		#if !html5
		final win = Application.current?.window;
		if (win == null) return;
		w = Std.int(Math.max(w, minWidth));
		h = Std.int(Math.max(h, minHeight));
		win.move(x, y);
		win.resize(w, h);
		#end
	}

	public static function centerOnScreen():Void
	{
		#if !html5
		final win = Application.current?.window;
		if (win == null) return;
		final sw = lime.system.System.getDisplay(0)?.currentMode?.width  ?? 1920;
		final sh = lime.system.System.getDisplay(0)?.currentMode?.height ?? 1080;
		win.move(Std.int((sw - win.width) / 2), Std.int((sh - win.height) / 2));
		#end
	}

	// ── Size ────────────────────────────────────────────────────────────────

	public static var windowWidth(get, never):Int;
	static inline function get_windowWidth():Int
	{
		#if !html5
		return Application.current?.window?.width ?? FlxG.stage.stageWidth;
		#else
		return FlxG.stage.stageWidth;
		#end
	}

	public static var windowHeight(get, never):Int;
	static inline function get_windowHeight():Int
	{
		#if !html5
		return Application.current?.window?.height ?? FlxG.stage.stageHeight;
		#else
		return FlxG.stage.stageHeight;
		#end
	}

	public static var aspectRatio(get, never):Float;
	static inline function get_aspectRatio():Float return windowWidth / windowHeight;

	// ══════════════════════════════════════════════════════════════════════════
	//  NUEVO: VISIBILIDAD DE VENTANA Y OPACIDAD
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Oculta la ventana del juego (la ventana desaparece del escritorio).
	 * The process sigue corriendo. Useful for fondos of screen interactivos,
	 * ventanas HUD secundarias, o durante transiciones de pantalla completa.
	 */
	public static function hide():Void
	{
		#if !html5
		if (Application.current?.window != null)
			Application.current.window.minimized = true;
		#end
	}

	/**
	 * Muestra la ventana si estaba oculta.
	 */
	public static function show():Void
	{
		#if !html5
		if (Application.current?.window != null)
			Application.current.window.minimized = false;
		#end
	}

	/** Oculta o muestra la ventana. */
	public static function setWindowVisible(visible:Bool):Void
	{
		if (visible) show() else hide();
	}

	/** Is the window currently visible? */
	public static var isWindowVisible(get, never):Bool;
	static function get_isWindowVisible():Bool
	{
		#if !html5
		return !(Application.current?.window?.hidden ?? false);
		#else
		return true;
		#end
	}

	/**
	 * Cambia la opacidad de toda la ventana (incluyendo decoraciones OS).
	 *
	 * @param alpha  0.0 = completamente transparente, 1.0 = opaco normal.
	 *
	 * Requiere soporte del OS:
	 *  • Windows: SetLayeredWindowAttributes via CppAPI (configurado en project.xml)
	 *  • Linux:   compositor compatible con _NET_WM_WINDOW_OPACITY
	 *  • Web:     no soportado (ignorado silenciosamente)
	 *
	 * NOTA: La opacidad de ventana es diferente a FlxSprite.alpha — afecta
	 * a TODOS los sprites y la interfaz OS de la ventana.
	 * For ocultar only the contenido of the game, use setGameAlpha() in its lugar.
	 */
	public static function setWindowOpacity(alpha:Float):Void
	{
		alpha = Math.max(0.0, Math.min(1.0, alpha));
		#if (windows && cpp)
		extensions.CppAPI.setWindowOpacity(alpha);
		#elseif (!html5)
		// En Linux via lime: lime no expone opacity directamente,
		// pero podemos usar el alpha del stage container de OpenFL.
		if (FlxG.game != null)
			FlxG.game.alpha = alpha;
		#end
	}

	/**
	 * Cambia el alpha del contenedor principal de Flixel (no de la ventana OS).
	 * More portátil that setWindowOpacity: works in all the plataformas.
	 * @param alpha 0.0 = invisible, 1.0 = normal
	 */
	public static function setGameAlpha(alpha:Float):Void
	{
		alpha = Math.max(0.0, Math.min(1.0, alpha));
		if (FlxG.game != null)
			FlxG.game.alpha = alpha;
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  new: SPOTLIGHT — do visible only determinados sprites
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Activa el modo spotlight: oculta TODOS los sprites de la escena actual
	 * excepto los especificados en `sprites`.
	 *
	 * ─── How it works ────────────────────────────────────────────────────────
	 *  1. Toma un snapshot de la visibilidad de todos los miembros de FlxG.state.
	 *  2. Oculta todo.
	 *  3. Hace visibles only the sprites in `sprites`.
	 *  4. Opcionalmente adds a fondo black over the cameras of fondo.
	 *
	 * ─── Ejemplo ─────────────────────────────────────────────────────────────
	 *   // Only bf and the cuadro of dialogue are visibles
	 *   WindowManager.beginSpotlight([bf, dialogBox], true);
	 *   // ... cutscene ...
	 *   WindowManager.endSpotlight();
	 *
	 * @param sprites          Sprites que DEBEN seguir visibles.
	 * @param blackBackground  If true, adds a overlay black over the cameras
	 *                         de background para aislar los sprites del stage.
	 * @param bgAlpha          Opacidad del fondo negro (0.0-1.0). Default: 0.85.
	 */
	public static function beginSpotlight(sprites:Array<FlxSprite>, blackBackground:Bool = false,
		bgAlpha:Float = 0.85):Void
	{
		if (spotlightActive)
			endSpotlight(); // Limpiar spotlight anterior antes de iniciar uno nuevo

		_spotlightSprites = sprites != null ? sprites.copy() : [];
		_visibilitySnapshot.clear();
		_snapshotTaken = true;
		spotlightActive = true;

		// ── Snapshot + hide de todos los miembros del state ───────────────────
		if (FlxG.state != null)
		{
			_snapshotGroup(FlxG.state.members);
		}

		// ── Mostrar only the sprites of the spotlight ────────────────────────────
		for (spr in _spotlightSprites)
		{
			if (spr != null)
				spr.visible = true;
		}

		// ── Fondo negro opcional ──────────────────────────────────────────────
		if (blackBackground)
		{
			_spotlightBg = new FlxSprite(0, 0);
			_spotlightBg.makeGraphic(FlxG.width, FlxG.height, 0xFF000000);
			_spotlightBg.alpha   = Math.max(0.0, Math.min(1.0, bgAlpha));
			_spotlightBg.scrollFactor.set(0, 0);
			_spotlightBg.cameras = [FlxG.camera]; // camera main
			FlxG.state.add(_spotlightBg);

			// The fondo black debe be behind of the sprites of the spotlight
			// → moverlo al inicio del array de miembros del state
			final members = FlxG.state.members;
			if (members != null && members.length > 1)
			{
				members.remove(_spotlightBg);
				// Insertar justo antes del primer sprite del spotlight
				var insertIdx = 0;
				for (i in 0...members.length)
				{
					if (_spotlightSprites.contains(cast members[i]))
					{
						insertIdx = i;
						break;
					}
				}
				members.insert(insertIdx, _spotlightBg);
			}
		}

		trace('[WindowManager] Spotlight iniciado con ${_spotlightSprites.length} sprites.');
	}

	/**
	 * Termina el modo spotlight y restaura las visibilidades originales.
	 */
	public static function endSpotlight():Void
	{
		if (!spotlightActive) return;

		// ── Restaurar visibilidades ───────────────────────────────────────────
		if (FlxG.state != null && _snapshotTaken)
			_restoreGroup(FlxG.state.members);

		// ── Eliminar fondo negro ──────────────────────────────────────────────
		if (_spotlightBg != null)
		{
			FlxG.state.remove(_spotlightBg, true);
			_spotlightBg.destroy();
			_spotlightBg = null;
		}

		_spotlightSprites.resize(0);
		_visibilitySnapshot.clear();
		_snapshotTaken  = false;
		spotlightActive = false;

		trace('[WindowManager] Spotlight terminado.');
	}

	/**
	 * Changes the conjunto of sprites visibles while the spotlight is active,
	 * sin necesidad de llamar end/beginSpotlight de nuevo.
	 *
	 * @param sprites  Nuevo conjunto de sprites que deben ser visibles.
	 */
	public static function updateSpotlight(sprites:Array<FlxSprite>):Void
	{
		if (!spotlightActive) return;

		// Ocultar todos primero (usando snapshot como referencia)
		if (FlxG.state != null)
			_hideAllExceptBg(FlxG.state.members);

		_spotlightSprites = sprites != null ? sprites.copy() : [];

		for (spr in _spotlightSprites)
		{
			if (spr != null)
				spr.visible = true;
		}

		// Mantener el fondo negro visible
		if (_spotlightBg != null)
			_spotlightBg.visible = true;
	}

	/**
	 * Adds a sprite to the spotlight current without reconfigurar all.
	 */
	public static function addToSpotlight(sprite:FlxSprite):Void
	{
		if (sprite == null) return;
		if (!_spotlightSprites.contains(sprite))
			_spotlightSprites.push(sprite);
		if (spotlightActive)
			sprite.visible = true;
	}

	/**
	 * Quita a sprite of the spotlight (it hides if the spotlight is active).
	 */
	public static function removeFromSpotlight(sprite:FlxSprite):Void
	{
		if (sprite == null) return;
		_spotlightSprites.remove(sprite);
		if (spotlightActive)
			sprite.visible = false;
	}

	// ── Snapshot helpers ──────────────────────────────────────────────────────

	/** Guarda la visibilidad de todos los miembros y los oculta. */
	static function _snapshotGroup(members:Array<FlxBasic>):Void
	{
		if (members == null) return;
		for (obj in members)
		{
			if (obj == null) continue;
			_visibilitySnapshot.set(obj.ID, obj.visible);
			obj.visible = false;
		}
	}

	/** Restaura the visibility of all the miembros according to the snapshot. */
	static function _restoreGroup(members:Array<FlxBasic>):Void
	{
		if (members == null) return;
		for (obj in members)
		{
			if (obj == null) continue;
			if (_visibilitySnapshot.exists(obj.ID))
				obj.visible = _visibilitySnapshot.get(obj.ID);
		}
	}

	/** Oculta todos los miembros excepto el fondo negro de spotlight. */
	static function _hideAllExceptBg(members:Array<FlxBasic>):Void
	{
		if (members == null) return;
		for (obj in members)
		{
			if (obj == null || obj == (_spotlightBg : FlxBasic)) continue;
			obj.visible = false;
		}
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  new: VISIBILIDAD by camera
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Hides or muestra all the sprites that are asignados to a camera
	 * specific. Useful for hide layers enteras (HUD, background, etc.)
	 * without afectar to the sprites of otras cameras.
	 *
	 * @param camera   The camera cuya "layer" quieres afectar.
	 * @param visible  true = mostrar, false = ocultar.
	 */
	public static function setCameraLayerVisible(camera:FlxCamera, visible:Bool):Void
	{
		if (FlxG.state == null || camera == null) return;

		for (obj in FlxG.state.members)
		{
			if (obj == null) continue;
			final spr = Std.downcast(obj, FlxSprite);
			if (spr == null) continue;
			if (spr.cameras != null && spr.cameras.contains(camera))
				spr.visible = visible;
		}
	}

	/**
	 * Oculta or muestra all the sprites of all the cameras excepto the
	 * especificada. Complementario a setCameraLayerVisible.
	 *
	 * @param exceptCamera  Camera cuyos sprites no is afectan.
	 * @param visible       true = mostrar el resto, false = ocultar el resto.
	 */
	public static function setOtherCamerasVisible(exceptCamera:FlxCamera, visible:Bool):Void
	{
		for (cam in FlxG.cameras.list)
		{
			if (cam != exceptCamera)
				setCameraLayerVisible(cam, visible);
		}
	}

	// ── Handlers ─────────────────────────────────────────────────────────────

	@:access(flixel.FlxCamera)
	static function _onResize(w:Int, h:Int):Void
	{
		if (FlxG.cameras != null)
		{
			for (cam in FlxG.cameras.list)
			{
				if (cam != null && cam.filters != null)
					_resetSpriteCache(cam.flashSprite);
			}
		}

		if (FlxG.game != null)
			_resetSpriteCache(FlxG.game);

		if (scaleMode == PIXEL_PERFECT)
			applyScaleMode(PIXEL_PERFECT);

		// If the spotlight is active with fondo black, redimensionarlo
		if (spotlightActive && _spotlightBg != null)
		{
			_spotlightBg.makeGraphic(w, h, 0xFF000000);
		}

		trace('[WindowManager] Resize → ${w}×${h}  Ratio=${Math.round(aspectRatio * 100) / 100}');
	}

	static function _onLimeResize(w:Int, h:Int):Void
	{
		#if !html5
		if (minWidth <= 0 && minHeight <= 0) return;
		final win = Application.current?.window;
		if (win == null) return;
		var clamped = false;
		var newW = w;
		var newH = h;
		if (minWidth > 0 && w < minWidth)  { newW = minWidth;  clamped = true; }
		if (minHeight > 0 && h < minHeight) { newH = minHeight; clamped = true; }
		if (clamped) win.resize(newW, newH);
		#end
	}

	@:access(openfl.display.DisplayObject)
	static function _resetSpriteCache(sprite:Sprite):Void
	{
		if (sprite == null) return;
		@:privateAccess
		{
			sprite.__cacheBitmap     = null;
			sprite.__cacheBitmapData = null;
		}
	}

	// ── DPI awareness ─────────────────────────────────────────────────────────

	static function _registerDPIAwareness():Void
	{
		#if (windows && cpp)
		extensions.InitAPI.setDPIAware();
		#end
	}
}

// ── Enums ────────────────────────────────────────────────────────────────────

/**
 * Modos de escala disponibles.
 * Equivalencias con Godot 4.x:
 *  - LETTERBOX     → Viewport stretch + Keep aspect
 *  - STRETCH       → Canvas Items + Ignore aspect
 *  - PIXEL_PERFECT → Viewport stretch + Keep aspect + Integer scale
 *  - WIDESCREEN    → Expande FlxG.width in screens >16:9 mostrando more stage
 */
enum ScaleMode
{
	LETTERBOX;
	STRETCH;
	PIXEL_PERFECT;
	WIDESCREEN;
}

@:access(flixel.system.scaleModes.BaseScaleMode)
class PixelPerfectScaleMode extends RatioScaleMode
{
	var _baseW:Int;
	var _baseH:Int;

	public function new(baseW:Int, baseH:Int)
	{
		super(false);
		_baseW = baseW;
		_baseH = baseH;
	}

	override public function updateGameSize(Width:Int, Height:Int):Void
	{
		var scale:Int = Std.int(Math.max(1, Math.min(Math.floor(Width / _baseW), Math.floor(Height / _baseH))));
		gameSize.x = _baseW * scale;
		gameSize.y = _baseH * scale;
	}
}

/**
 * WideRatioScaleMode — modo widescreen al estilo V-Slice.
 *
 * Comportamiento:
 *  • En pantallas 16:9 exactas funciona igual que LETTERBOX.
 *  • In screens more ANCHAS (21:9, 32:9…) the game ocupa all the width.
 *    FlxG.width is expande proporcionalmente, mostrando more stage
 *    a los lados sin deformar la imagen.
 *  • In screens more ALTAS (4:3, 16:10…) is añaden barras negras up/down
 *    igual que LETTERBOX.
 *
 * La altura base (FlxG.height) no cambia.
 * The width lógico (FlxG.width) puede crecer until maxWidthScale × baseWidth.
 * Los elementos HUD con scrollFactor (0,0) quedan fijos en pantalla.
 * The sprites of the stage, to the usar camGame, is ven more to the lados.
 *
 * Limit maximum of ratio: 21:9 (~2.333). Screens more anchas reciben barras.
 */
@:access(flixel.system.scaleModes.BaseScaleMode)
class WideRatioScaleMode extends RatioScaleMode
{
	/** Ratio maximum soportado (default: 21:9 ≈ 2.333). */
	public static var maxRatio:Float = 21 / 9;

	var _baseW:Int;
	var _baseH:Int;

	public function new(baseW:Int, baseH:Int)
	{
		super(false); // false = no stretch
		_baseW = baseW;
		_baseH = baseH;
	}

	override public function updateGameSize(Width:Int, Height:Int):Void
	{
		var screenRatio:Float = Width / Height;
		var baseRatio:Float   = _baseW / _baseH;

		if (screenRatio > baseRatio)
		{
			// Screen more ancha that 16:9 → expandir width lógico
			var clampedRatio = Math.min(screenRatio, maxRatio);
			var newW = Math.ceil(_baseH * clampedRatio);

			// Mantener múltiplos of 2 for avoid artefactos sub-pixel
			if (newW % 2 != 0) newW++;

			gameSize.y = Height;
			gameSize.x = Width;

			// Expandir the width lógico of Flixel
			untyped FlxG.width  = newW;
			untyped FlxG.height = _baseH;
		}
		else
		{
			// Screen igual or more alta that 16:9 → comportamiento normal
			gameSize.y = Height;
			gameSize.x = Math.ceil(Height * baseRatio);

			untyped FlxG.width  = _baseW;
			untyped FlxG.height = _baseH;
		}
	}
}
