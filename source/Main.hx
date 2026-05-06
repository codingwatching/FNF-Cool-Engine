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
import funkin.data.SaveData;
#if mobileC
import funkin.util.plugins.TouchPointerPlugin;
#end

using StringTools;

class Main extends Sprite
{
	private static inline var GAME_WIDTH:Int = 1280;
	private static inline var GAME_HEIGHT:Int = 720;
	private static inline var BASE_FPS:Int = 2000;

	private var gameWidth:Int = GAME_WIDTH;
	private var gameHeight:Int = GAME_HEIGHT;
	private var zoom:Float = -1;
	private var framerate:Int = BASE_FPS;
	private var skipSplash:Bool = true;
	private var startFullscreen:Bool = false;

	private var initialState:Class<FlxState> = CacheState;

	// ── UI ────────────────────────────────────────────────────────────────────
	public final data:DataInfoUI = new DataInfoUI(10, 3);

	// Version
	public static inline var ENGINE_VERSION:String = "0.6.1B";

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

		#if (linux && cpp)
		InitAPI.setDarkMode(true);
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
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _applyWindowStylingDeferred);
		#elseif (mac && cpp)
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _applyWindowStylingDeferred);
		#end
	}

	private function setupGame():Void
	{
		calculateZoom();

		#if mobileC
		framerate = 60;
		#end

		AudioConfig.load();

		CrashHandler.init();

		createGame();
		FunkinCache.init();
		AudioConfig.applyToFlixel();

		#if !mobileC
		StickerTransition.init();
		#else
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _initStickersDeferred);
		#end

		// ── WindowManager ──────────────────────────────────────────────────────
		WindowManager.init(/* mode    */ LETTERBOX, /* minW    */ 960, /* minH    */ 540, /* baseW   */ GAME_WIDTH, /* baseH   */ GAME_HEIGHT);

		// Fix for widescreen - Android
		#if android
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _applyCutoutDeferred);
		#end

		#if (desktop && !html5)
		if (lime.app.Application.current?.window != null)
		{
			lime.app.Application.current.window.resize(1280, 720);
			WindowManager.centerOnScreen();
		}
		#end

		initializeSaveSystem();
		initializeGameSystems();

		funkin.util.plugins.ScreenshotPlugin.initialize();
		initializeFramerate();
		Main.applyVSync();
		initializeCameras();

		// ── UI overlays ───────────────────────────────────────────────────────
		addChild(data);

		funkin.audio.CoreAudio.initialize();
		FlxG.plugins.add(new SoundTray());
		disableDefaultSoundTray();

		funkin.audio.VolumePlugin.initialize();

		// save volume
		final _saveVolumeOnExit = function(_:openfl.events.Event) {
			funkin.audio.CoreAudio.saveVolume();
		};
		stage.addEventListener(openfl.events.Event.DEACTIVATE, _saveVolumeOnExit);
		#if (desktop || cpp)
		stage.addEventListener(openfl.events.Event.CLOSE, _saveVolumeOnExit);
		#end

		FlxG.sound.applySoundCurve  = function(v:Float) return v;
		FlxG.sound.reverseSoundCurve = function(v:Float) return v;

		#if mobileC
		stage.addEventListener(openfl.events.Event.ACTIVATE, _onMobileActivate);
		#end

		// ── Mods ──────────────────────────────────────────────────────────────
		#if android
		_requestAndroidStoragePermission(function() {
			mods.ModManager.init();
			mods.ModManager.applyStartupMod();
			AddonManager.init();
		});
		#else
		mods.ModManager.init();
		mods.ModManager.applyStartupMod();
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

			funkin.scripting.ScriptHandler.clearAll();
			funkin.scripting.ScriptHandler.loadGlobalScripts();

			funkin.gameplay.notes.NoteSkinSystem.destroyScripts();
			funkin.gameplay.notes.NoteSkinSystem.forceReinit();

			WindowManager.applyModBranding(mods.ModManager.activeInfo());
			#if (desktop && cpp)
			DiscordClient.applyModConfig(mods.ModManager.activeInfo());
			#end
		};

		// ── Discord ───────────────────────────────────────────────────────────
		#if (desktop && cpp)
		DiscordClient.initialize();
		#end

		#if (cpp && !mobileC)
		untyped FlxG.cameras = new funkin.graphics.FunkinCameraFrontEnd();
		#end

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

		SystemInfo.init();
	}

	#if ((windows || mac) && cpp)
	private static inline var _WIN_STYLE_MAX_RETRIES:Int = 120;
	private var _winStyleRetries:Int = 0;
	private var _winStyleApplied:Bool = false;

	private function _applyWindowStylingDeferred(_:openfl.events.Event):Void
	{
		if (!InitAPI.hasValidWindow())
		{
			if (++_winStyleRetries < _WIN_STYLE_MAX_RETRIES)
				return;
			stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _applyWindowStylingDeferred);
			return;
		}

		stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _applyWindowStylingDeferred);

		_doApplyWindowStyling();

		if (!_winStyleApplied)
		{
			_winStyleApplied = true;
			new flixel.util.FlxTimer().start(0.5, function(_) _doApplyWindowStyling());
		}
	}

	private function _doApplyWindowStyling():Void
	{
		InitAPI.setDarkMode(true);
		InitAPI.setWindowCaptionColor(0, 0, 0);
		InitAPI.setWindowBorderColor(0, 0, 0);
	}
	#end

	#if android
	private function _applyCutoutDeferred(_:openfl.events.Event):Void
	{
		stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _applyCutoutDeferred);
		_applyAndroidCutoutMode();
	}

	private function _applyAndroidCutoutMode():Void
	{
		try
		{
			var getInstance = lime.system.JNI.createStaticMethod(
				"org/haxe/lime/GameActivity", "getInstance",
				"()Lorg/haxe/lime/GameActivity;");
			var activity:Dynamic = getInstance();
			if (activity == null) return;

			var getWindow = lime.system.JNI.createMemberMethod(
				"android/app/Activity", "getWindow",
				"()Landroid/view/Window;");
			var win:Dynamic = getWindow(activity);
			if (win == null) return;

			var getAttribs = lime.system.JNI.createMemberMethod(
				"android/view/Window", "getAttributes",
				"()Landroid/view/WindowManager/$LayoutParams;");
			var attribs:Dynamic = getAttribs(win);
			if (attribs == null) return;

			var getClass_ = lime.system.JNI.createMemberMethod(
				"java/lang/Object", "getClass",
				"()Ljava/lang/Class;");
			var cls:Dynamic = getClass_(attribs);

			var getField_ = lime.system.JNI.createMemberMethod(
				"java/lang/Class", "getField",
				"(Ljava/lang/String;)Ljava/lang/reflect/Field;");
			var field:Dynamic = getField_(cls, "layoutInDisplayCutoutMode");
			if (field == null) return;

			var setAccessible = lime.system.JNI.createMemberMethod(
				"java/lang/reflect/AccessibleObject", "setAccessible", "(Z)V");
			setAccessible(field, true);

			var setInt_ = lime.system.JNI.createMemberMethod(
				"java/lang/reflect/Field", "setInt",
				"(Ljava/lang/Object;I)V");
			setInt_(field, attribs, 1);

			// ── 6. Aplicar LayoutParams actualizados ─────────────────────────
			var setAttribs = lime.system.JNI.createMemberMethod(
				"android/view/Window", "setAttributes",
				"(Landroid/view/WindowManager/$LayoutParams;)V");
			setAttribs(win, attribs);

			trace('[Main] Android display cutout mode → SHORT_EDGES.');
		}
		catch (e:Dynamic)
		{
			trace('[Main] _applyAndroidCutoutMode: no applied (API<28 or error): $e');
		}
	}
	#end

	#if mobileC
	private function _initStickersDeferred(_:openfl.events.Event):Void {
		stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _initStickersDeferred);
		StickerTransition.init();
	}
	#end

	#if mobileC
	// Fix to black screen
	private function _onMobileActivate(_:openfl.events.Event):Void
	{
		openfl.Lib.current.stage.invalidate();

		setMaxFps(60);

		Main.applyVSync();

		funkin.audio.CoreAudio.onMobileResume();

		haxe.Timer.delay(function() openfl.Lib.current.stage.invalidate(), 200);
	}
	#end

	private function calculateZoom():Void
	{
		var tempSave = new flixel.util.FlxSave();
		tempSave.bind('coolengine', 'CoolTeam');
		var use1080p = (tempSave.data != null && tempSave.data.renderResolution == '1080p');
		tempSave.destroy();

		gameWidth  = GAME_WIDTH;   // 1280
		gameHeight = GAME_HEIGHT;  // 720

		if (use1080p)
		{
			zoom = 1.5;
		}
		else
		{
			zoom = 1.0;
		}

		#if android
		var rawW:Int = Lib.current.stage.stageWidth;
		var rawH:Int = Lib.current.stage.stageHeight;

		if (rawW <= 0 || rawH <= 0)
		{
			final display = lime.system.System.getDisplay(0);
			if (display?.currentMode != null)
			{
				rawW = display.currentMode.width;
				rawH = display.currentMode.height;
				trace('[Main] calculateZoom: stage=0, using display hwinfo → ${rawW}×${rawH}');
			}
		}

		var stageW:Int = Std.int(Math.max(rawW, rawH));
		var stageH:Int = Std.int(Math.min(rawW, rawH));

		if (stageW <= 0 || stageH <= 0)
		{
			zoom       = 1.0;
			gameWidth  = GAME_WIDTH;
			gameHeight = GAME_HEIGHT;
		}
		else
		{
			zoom = Math.min(stageW / gameWidth, stageH / gameHeight);
			if (zoom <= 0) zoom = 1.0;
			gameWidth  = Math.ceil(stageW / zoom);
			gameHeight = Math.ceil(stageH / zoom);
		}
		#elseif ios
		var rawW:Int = Lib.current.stage.stageWidth;
		var rawH:Int = Lib.current.stage.stageHeight;

		if (rawW <= 0 || rawH <= 0)
		{
			final display = lime.system.System.getDisplay(0);
			if (display?.currentMode != null)
			{
				rawW = display.currentMode.width;
				rawH = display.currentMode.height;
				trace('[Main] calculateZoom iOS: stage=0, usando display hwinfo → ${rawW}×${rawH}');
			}
		}

		var stageW:Int = Std.int(Math.max(rawW, rawH));
		var stageH:Int = Std.int(Math.min(rawW, rawH));

		if (stageW <= 0 || stageH <= 0)
		{
			zoom       = 1.0;
			gameWidth  = GAME_WIDTH;
			gameHeight = GAME_HEIGHT;
		}
		else
		{
			zoom = Math.min(stageW / gameWidth, stageH / gameHeight);
			if (zoom <= 0) zoom = 1.0;
			gameWidth  = Math.ceil(stageW / zoom);
			gameHeight = Math.ceil(stageH / zoom);
		}
		#end
	}

	private function createGame():Void
	{
		addChild(new FlxGame(gameWidth, gameHeight, initialState, #if (flixel < "5.0.0") zoom, #end framerate, framerate, skipSplash, startFullscreen));

		FlxG.fullscreen = false;

		FlxSprite.defaultAntialiasing = false;
	}

	private function initializeSaveSystem():Void
	{
		FlxG.save.bind('coolengine', 'CoolTeam');
		
		SaveData.migrate();

		funkin.menus.OptionsMenuState.OptionsData.initSave();
		funkin.gameplay.objects.hud.Highscore.load();

		if (SaveData.data.scaleMode != null)
			WindowManager.applyScaleModeByName(SaveData.data.scaleMode);
	}

	private function initializeGameSystems():Void
	{
		NoteSkinSystem.init();
		KeyBinds.keyCheck();
		PlayerSettings.init();
		PlayerSettings.player1.controls.loadKeyBinds();

		#if (desktop && !html5)
		stage.addEventListener(openfl.events.KeyboardEvent.KEY_DOWN, function(e:openfl.events.KeyboardEvent) {
			if (e.keyCode == openfl.ui.Keyboard.F11)
				FlxG.fullscreen = !FlxG.fullscreen;
		});
		#end

		funkin.system.CursorManager.init();
		funkin.system.CursorManager.loadSkinPreference();

		#if mobileC
		TouchPointerPlugin.initialize();
		// Restaurar preferencia guardada
		if (SaveData.data.touchIndicator != null)
			TouchPointerPlugin.enabled = SaveData.data.touchIndicator;
		#end

		if (SaveData.data.gpuCaching != null)
			PathsCache.gpuCaching = SaveData.data.gpuCaching;

		Paths.addExclusion(Paths.music('freakyMenu'));
		Paths.addExclusion(Paths.image('menu/cursor/cursor-default'));
	}

	private function initializeFramerate():Void
	{
		FrameLimiterAPI.init();

		#if (!html5 && !mobileC)
		framerate = 120;
		#else
		framerate = 60;
		#end

		#if !mobileC
		if (SaveData.data.fpsTarget != null)
		{
			setMaxFps(Std.int(SaveData.data.fpsTarget));
		}
		else if (SaveData.data.FPSCap != null && SaveData.data.FPSCap > 0)
		{
			SaveData.data.fpsTarget = 120;
			setMaxFps(120);
		}
		else
		{
			SaveData.data.fpsTarget = 60;
			setMaxFps(60);
		}
		#else
		setMaxFps(60);
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
		#if (!html5 && !mobileC)
		final renderFps:Int = fps <= 0 ? 1000 : fps;
		final updateFps:Int = fps <= 0 ? 240  : fps;

		openfl.Lib.current.stage.frameRate = updateFps;
		FlxG.updateFramerate = updateFps;
		FlxG.drawFramerate   = renderFps;
		openfl.Lib.current.stage.frameRate = renderFps;
		#else
		final effective:Int = fps <= 0 ? 60 : fps;
		openfl.Lib.current.stage.frameRate = effective;
		FlxG.updateFramerate = effective;
		FlxG.drawFramerate   = effective;
		#end
	}

	public static function applyVSync():Void
	{
		#if cpp
		VSyncAPI.setVSync(SaveData.data.vsync != false);
		#elseif hl
		var win = lime.app.Application.current?.window;
		if (win != null)
			Reflect.setField(win, 'vsync', SaveData.data.vsync != false);
		#end
	}

	#if android
	static function _requestAndroidStoragePermission(onGranted:Void->Void):Void
	{
		#if (android && cpp)
		new flixel.util.FlxTimer().start(0.1, function(_) onGranted());
		#else
		onGranted();
		#end
	}
	#end

	public static function getGame():FlxGame
		return cast(Lib.current.getChildAt(0), FlxGame);
}