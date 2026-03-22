package;

import flixel.FlxG;
import flixel.FlxGame;
import flixel.FlxState;
import flixel.FlxSprite;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import openfl.display.StageAlign;
import CacheState;
import ui.DataInfoUI;
import funkin.audio.SoundTray;
import funkin.menus.TitleState;
import data.PlayerSettings;
import CrashHandler;
import funkin.transitions.StickerTransition;
import openfl.system.System;
import funkin.audio.AudioConfig;
import funkin.data.CameraUtil;
import funkin.system.MemoryUtil;
import funkin.system.SystemInfo;
import funkin.system.WindowManager;
import funkin.system.WindowManager.ScaleMode;
import funkin.cache.PathsCache;
import funkin.cache.FunkinCache;
import extensions.CppAPI;
import extensions.FrameLimiterAPI;
import extensions.InitAPI;
import extensions.VSyncAPI;
#if (desktop && cpp)
import data.Discord.DiscordClient;
import sys.thread.Thread;
#end
import funkin.data.KeyBinds;
import funkin.gameplay.notes.NoteSkinSystem;
import funkin.addons.AddonManager;
#if mobileC
import funkin.util.plugins.TouchPointerPlugin;
#end

using StringTools;

/**
 * Main — punto de entrada de Cool Engine.
 *
 * ─── Initialization order ─────────────────────────────────────────────────
 *  1. DPI-awareness + dark mode (antes de cualquier ventana)
 *  2. GC tuning (antes de cargar nada)
 *  3. Stage config
 *  4. AudioConfig.load() (antes de createGame → antes de que OpenAL se init)
 *  5. CrashHandler, DebugConsole
 *  6. createGame() → FlxG disponible
 *  7. AudioConfig.applyToFlixel()
 *  8. WindowManager.init() → resize subscription, scale mode
 *  9. Sistemas que dependen de FlxG (save, keybinds, nota skins…)
 * 10. UI overlays
 * 11. SystemInfo.init() (necesita context3D → after of the first frame)
 *
 * @author Cool Engine Team
 * @version 0.6.0
 */
class Main extends Sprite
{
	// ── Game configuration ────────────────────────────────────────────────
	private static inline var GAME_WIDTH:Int = 1280;
	private static inline var GAME_HEIGHT:Int = 720;
	private static inline var BASE_FPS:Int = 2000; // FlxGame construye con este valor para no bloquear FPS reales

	private var gameWidth:Int = GAME_WIDTH;
	private var gameHeight:Int = GAME_HEIGHT;
	private var zoom:Float = -1;
	private var framerate:Int = BASE_FPS;
	private var skipSplash:Bool = true;
	private var startFullscreen:Bool = false;

	private var initialState:Class<FlxState> = CacheState;

	// ── UI ────────────────────────────────────────────────────────────────────
	public final data:DataInfoUI = new DataInfoUI(10, 3);

	// ── Versiones ─────────────────────────────────────────────────────────────
	public static inline var ENGINE_VERSION:String = "0.6.0B";

	/** Factor de escala para compensar resoluciones mayores a 720p.
	 *  En 720p  → 1.0   (sin cambio)
	 *  En 1080p → 1.5   (1920/1280)
	 *  Use it to scale defaultZoom and absolute positions in the HUD. */
	public static inline var BASE_WIDTH:Int = 1280;
	public static function resolutionScale():Float
		return (FlxG.width > 0) ? FlxG.width / BASE_WIDTH : 1.0;

	// ── Entry point ───────────────────────────────────────────────────────────

	@:keep
	static function __init__():Void
	{
		#if (windows && cpp)
		InitAPI.setDPIAware();
		#end
	}

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new()
	{
		super();

		if (stage != null)
			init();
		else
			addEventListener(Event.ADDED_TO_STAGE, init);
	}

	// ── Init ─────────────────────────────────────────────────────────────────

	private function init(?e:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
			removeEventListener(Event.ADDED_TO_STAGE, init);

		setupStage();
		setupGame();
	}

	private function setupStage():Void
	{
		stage.scaleMode = StageScaleMode.NO_SCALE;
		stage.align = StageAlign.TOP_LEFT;
		stage.quality = openfl.display.StageQuality.LOW;

		#if cpp
		cpp.vm.Gc.setMinimumFreeSpace(32 * 1024 * 1024);
		cpp.vm.Gc.enable(true);
		#end

		#if (windows && cpp)
		InitAPI.setDarkMode(true);
		CppAPI.changeColor(0, 0, 0);
		#end
	}

	private function setupGame():Void
	{
		calculateZoom();

		// ── Audio (ANTES de createGame) ────────────────────────────────────────
		AudioConfig.load();

		// ── CrashHandler ──────────────────────────────────────────────────────
		CrashHandler.init();

		// ── Juego ─────────────────────────────────────────────────────────────
		createGame();
		FunkinCache.init();
		AudioConfig.applyToFlixel();
		// FIX: StickerTransition.init() creates a new FlxCamera internally.
		// On Android the OpenGL context (context3D) is not ready until after the
		// first rendered frame — creating GPU-backed objects here crashes the
		// Mali/Adreno driver. We defer to the first ENTER_FRAME on mobile,
		// exactly as we already do for FunkinCameraFrontEnd and SystemInfo.
		#if !mobileC
		StickerTransition.init();
		#else
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _initStickersDeferred);
		#end

		// ── WindowManager ──────────────────────────────────────────────────────
		WindowManager.init(/* mode    */ LETTERBOX, /* minW    */ 960, /* minH    */ 540, /* baseW   */ GAME_WIDTH, /* baseH   */ GAME_HEIGHT);

		// ── FIX: Larger initial window size (desktop only) ──────────
		// En Android window.resize() interfiere con la superficie SDL y puede
		// causing the EGL context to be in an invalid state.
		#if (desktop && !html5)
		if (lime.app.Application.current?.window != null)
		{
			lime.app.Application.current.window.resize(1280, 720);
			WindowManager.centerOnScreen();
		}
		#end

		// ── Sistemas que dependen de FlxG ─────────────────────────────────────
		initializeSaveSystem();
		initializeGameSystems();
		// Screenshots — MUST come after initializeGameSystems() so
		// that save and keybinds are already loaded before the plugin
		// empiece a leer controles (evita capturas en el frame 0 por null key).
		funkin.util.plugins.ScreenshotPlugin.initialize();
		initializeFramerate();
		Main.applyVSync();
		initializeCameras();

		// ── UI overlays ───────────────────────────────────────────────────────
		addChild(data);
		// CoreAudio PRIMERO: carga el save (masterVolume/muted) para que
		// SoundTray.loadVolume() lea valores correctos al construirse.
		funkin.audio.CoreAudio.initialize();
		FlxG.plugins.add(new SoundTray());
		disableDefaultSoundTray();
		// V-Slice style: plugin de volumen rebindable.
		funkin.audio.VolumePlugin.initialize();

		// ── BUGFIX (Flixel git): forzar curva de volumen lineal ───────────────
		// CoreAudio gestiona su propio volumen directamente sobre FlxSound.volume,
		// but we leave the linear curve in case any SFX uses FlxG.sound.play().
		FlxG.sound.applySoundCurve  = function(v:Float) return v;
		FlxG.sound.reverseSoundCurve = function(v:Float) return v;

		// ── Mods ──────────────────────────────────────────────────────────────
		#if android
		// En Android 6+ hay que pedir permisos de almacenamiento en runtime.
		// Sin esto el FileSystem no puede leer /sdcard/Android/data/.../files/mods/
		_requestAndroidStoragePermission(function() {
			mods.ModManager.init();
			mods.ModManager.applyStartupMod();
			// ── Addons (after mods so they can read the active folder) ──
			AddonManager.init();
		});
		#else
		mods.ModManager.init();
		mods.ModManager.applyStartupMod();
		// ── Addons (after mods so they can read the active folder) ────
		AddonManager.init();
		#end
		WindowManager.applyModBranding(mods.ModManager.activeInfo());
		#if (desktop && cpp)
		DiscordClient.applyModConfig(mods.ModManager.activeInfo());
		#end
		mods.ModManager.onModChanged = function(newMod:Null<String>)
		{
			Paths.forceClearCache();
			funkin.gameplay.objects.character.CharacterList.reload();
			MemoryUtil.collectMajor();
			trace('[Main] Cache cleaned. Mod active → ${newMod ?? "base"}');
			WindowManager.applyModBranding(mods.ModManager.activeInfo());
			#if (desktop && cpp)
			DiscordClient.applyModConfig(mods.ModManager.activeInfo());
			#end
		};

		// ── Discord ───────────────────────────────────────────────────────────
		#if (desktop && cpp)
		DiscordClient.initialize();
		#end

		// ── FunkinCamera frontend ─────────────────────────────────────────────
		// MUST be done here, AFTER createGame() but BEFORE the first
		// ENTER_FRAME. Reemplazar FlxG.cameras dentro del ENTER_FRAME provoca
		// un null pointer en el pipeline nativo de Lime/SDL en Android porque
		// the renderer is already iterating the camera list at that point.
		// FixedBitmapData ya tiene guarda contra context3D == null (usa
		// software bitmap as fallback), so this is safe on Android.
		// FunkinCamera usa RenderTexture de flixel-animate que crea texturas GPU.
		// On Android that context isn't ready here and crashes the OpenGL driver.
		// Los blend modes avanzados tampoco son necesarios en mobile.
		#if (cpp && !mobileC)
		untyped FlxG.cameras = new funkin.graphics.FunkinCameraFrontEnd();
		#end

		// SystemInfo._detectGPU() llama ctx.gl.getParameter() — GL call directa.
		// En Android el render corre en un thread nativo separado; hacerlo desde
		// ENTER_FRAME (event thread de Lime) viola el contexto OpenGL → crash.
		// En desktop es seguro deferir al primer frame.
		// En mobile solo inicializamos la parte no-GL (OS, CPU, RAM).
		#if (cpp && !mobileC)
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _initSystemInfoDeferred);
		#else
		SystemInfo.initSafe();
		#end
	}

	// ── ENTER_FRAME deferred ──────────────────────────────────────────────────

	private function _initSystemInfoDeferred(_:openfl.events.Event):Void
	{
		stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _initSystemInfoDeferred);

		// context3D.gl is available from the first rendered frame.
		// FunkinCameraFrontEnd was already initialized in setupGame() with the guard
		// of FixedBitmapData — this method only needs SystemInfo.
		SystemInfo.init();
	}

	#if mobileC
	/** Deferred init for StickerTransition on mobile — waits for the OpenGL context. */
	private function _initStickersDeferred(_:openfl.events.Event):Void
	{
		stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _initStickersDeferred);
		StickerTransition.init();
	}
	#end

	// ── Initialization helpers ─────────────────────────────────────────────

	private function calculateZoom():Void
	{
		// ── Saved resolution: 720p (default) or 1080p ───────────────────────
		var tempSave = new flixel.util.FlxSave();
		tempSave.bind('coolengine', 'CoolTeam');
		var use1080p = (tempSave.data != null && tempSave.data.renderResolution == '1080p');
		tempSave.destroy();

		// SIEMPRE mantenemos el espacio de juego en 1280x720.
		// Toda la geometria (stages, personajes, HUD) esta disenada para esas
		// coordenadas. En 1080p escalamos el renderer fisico a 1.5x para que
		// ocupe 1920x1080 en pantalla sin romper ninguna posicion.
		gameWidth  = GAME_WIDTH;   // 1280
		gameHeight = GAME_HEIGHT;  // 720

		if (use1080p)
		{
			// Zoom fisico 1.5 => output 1920x1080, coordenadas internas 1280x720
			zoom = 1.5;
		}
		else if (zoom == -1)
		{
			var rawW:Int = Lib.current.stage.stageWidth;
			var rawH:Int = Lib.current.stage.stageHeight;
			// En Android el stage puede reportar dimensiones en portrait antes de aplicar
			// landscape orientation, which causes SDL to send a buffer with transform
			// incorrecto → BLASTBufferQueue lo rechaza → Null Object Reference → crash.
			// Forzamos landscape: el lado mayor siempre es el ancho.
			#if android
			var stageW:Int = Std.int(Math.max(rawW, rawH));
			var stageH:Int = Std.int(Math.min(rawW, rawH));
			#else
			var stageW:Int = rawW;
			var stageH:Int = rawH;
			#end

			// FIX Bug #4: Some devices report 0×0 before the surface is created.
			// Math.min(0/1280, 0/720) = 0.0, then ceil(0/0.0) = NaN → Int overflow → crash.
			// Fall back to 1:1 zoom so FlxGame gets valid integer dimensions.
			if (stageW <= 0 || stageH <= 0)
			{
				zoom       = 1.0;
				gameWidth  = GAME_WIDTH;
				gameHeight = GAME_HEIGHT;
			}
			else
			{
				zoom = Math.min(stageW / gameWidth, stageH / gameHeight);
				if (zoom <= 0) zoom = 1.0;  // extra guard against any other degenerate value
				gameWidth  = Math.ceil(stageW / zoom);
				gameHeight = Math.ceil(stageH / zoom);
			}
		}
	}

	private function createGame():Void
	{
		addChild(new FlxGame(gameWidth, gameHeight, initialState, #if (flixel < "5.0.0") zoom, #end framerate, framerate, skipSplash, startFullscreen));

		// Garantizar que el juego siempre arranca en modo ventana,
		// ignorando cualquier valor de fullscreen guardado en save data.
		FlxG.fullscreen = false;

		// FIX: drawFramerate y updateFramerate se asignan solo en initializeFramerate()
		// to avoid the "Invalid field" error when calling them before FlxG is ready.
		// NOT duplicated here.

		FlxSprite.defaultAntialiasing = false;
	}

	private function initializeSaveSystem():Void
	{
		FlxG.save.bind('coolengine', 'CoolTeam');
		funkin.menus.OptionsMenuState.OptionsData.initSave();
		funkin.gameplay.objects.hud.Highscore.load();

		// ── Aplicar modo de escala guardado ────────────────────────────────────
		if (FlxG.save.data.scaleMode != null)
			WindowManager.applyScaleModeByName(FlxG.save.data.scaleMode);
	}

	private function initializeGameSystems():Void
	{
		NoteSkinSystem.init();
		KeyBinds.keyCheck();
		PlayerSettings.init();
		PlayerSettings.player1.controls.loadKeyBinds();

		// ── CursorManager: sistema de cursor personalizable ──────────────────
		funkin.system.CursorManager.init();
		funkin.system.CursorManager.loadSkinPreference();

		// ── Touch pointer visual (mobile) ──────────────────────────────────────
		#if mobileC
		TouchPointerPlugin.initialize();
		// Restaurar preferencia guardada
		if (FlxG.save.data.touchIndicator != null)
			TouchPointerPlugin.enabled = FlxG.save.data.touchIndicator;
		#end

		if (FlxG.save.data.gpuCaching != null)
			PathsCache.gpuCaching = FlxG.save.data.gpuCaching;

		Paths.addExclusion(Paths.music('freakyMenu'));
		Paths.addExclusion(Paths.image('menu/cursor/cursor-default'));
	}

	private function initializeFramerate():Void
	{
		// Inicializar el limitador nativo UNA VEZ (timeBeginPeriod + waitable timer).
		// This also improves Lime's loop precision as a side effect.
		FrameLimiterAPI.init();

		// FIX: was `!androidC` — that define never existed; `mobileC` is the correct one.
		// On Android at 120fps the SDL render thread overruns and produces a null-ptr
		// crash in the native pipeline. Mobile targets run at 60fps max.
		#if (!html5 && !mobileC)
		framerate = 120;
		#else
		framerate = 60;
		#end

		#if !mobileC
		if (FlxG.save.data.fpsTarget != null)
		{
			setMaxFps(Std.int(FlxG.save.data.fpsTarget));
		}
		else if (FlxG.save.data.FPSCap != null && FlxG.save.data.FPSCap)
		{
			FlxG.save.data.fpsTarget = 120;
			setMaxFps(120);
		}
		else
		{
			FlxG.save.data.fpsTarget = 60;
			setMaxFps(60);
		}
		#end
	}

	private function initializeCameras():Void
	{
		CameraUtil.pruneEmptyFilters(FlxG.camera);
	}

	private function disableDefaultSoundTray():Void
	{
		FlxG.sound.volumeUpKeys = null;
		FlxG.sound.volumeDownKeys = null;
		FlxG.sound.muteKeys = null;
		#if FLX_SOUND_SYSTEM
		@:privateAccess
		{
			if (FlxG.game.soundTray != null)
			{
				FlxG.game.soundTray.visible = false;
				FlxG.game.soundTray.active = false;
			}
		}
		#end
	}

	// ── Public API ────────────────────────────────────────────────────────────

	public function setMaxFps(fps:Int):Void
	{
		// fps = 0  → "Unlimited": render as fast as possible (1000 cap for safety),
		//            but logic updates capped at 240 so Flixel doesn't run 16+ steps/frame.
		// fps > 0  → exact cap for both render and logic.
		//
		// WHY separate updateFramerate cap:
		//   FlxGame.step() runs floor(elapsed / stepMS) update calls per rendered frame.
		//   updateFramerate=1000 → stepMS=1ms. At 60Hz display, elapsed≈16ms → 16 update
		//   calls per frame → 16x CPU cost → game feels slow/unresponsive at high FPS.
		//   Capping logic at 240 keeps 1-2 updates per frame at typical display rates.

		#if (!html5 && !mobileC)
		final renderFps:Int = fps <= 0 ? 1000 : fps;
		final updateFps:Int = fps <= 0 ? 240  : fps;
		openfl.Lib.current.stage.frameRate = renderFps;
		FlxG.updateFramerate = updateFps;
		FlxG.drawFramerate   = renderFps;
		#else
		final effective:Int = fps <= 0 ? 60 : fps;
		openfl.Lib.current.stage.frameRate = effective;
		FlxG.updateFramerate = effective;
		FlxG.drawFramerate   = effective;
		#end
	}

	/** Applies the state of VSync saved in save via extension nativa. */
	public static function applyVSync():Void
	{
		#if cpp
		VSyncAPI.setVSync(FlxG.save.data.vsync == true);
		#end
	}

	#if android
	/** Solicita READ/WRITE_EXTERNAL_STORAGE in Android 6+ and call onGranted() when is listo. */
	static function _requestAndroidStoragePermission(onGranted:Void->Void):Void
	{
		#if (android && cpp)
		// Android 10+ (API 29+): /Android/data/<package>/files/ es accesible sin permisos
		// of almacenamiento external. READ/WRITE_EXTERNAL_STORAGE are deprecados in
		// Android 13+ (API 33) y el sistema los deniega silenciosamente.
		// El JNI a HaxeObject::requestPermissions no existe en Lime y puede lanzar
		// a native exception that crashes the app before the first frame.
		// Simply esperamos a tick for that the FileSystem is listo and continuamos.
		new flixel.util.FlxTimer().start(0.1, function(_) onGranted());
		#else
		onGranted();
		#end
	}
	#end

	public static function getGame():FlxGame
		return cast(Lib.current.getChildAt(0), FlxGame);
}
