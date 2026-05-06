package;

import flixel.util.FlxTimer;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.data.KeyBinds;
import funkin.menus.TitleState;
import funkin.gameplay.objects.hud.Highscore;
import data.PlayerSettings;
import funkin.states.LoadingState;
import funkin.graphics.shaders.ShaderManager;
import funkin.scripting.ScriptHandler;
import openfl.utils.Assets as OpenFlAssets;

using StringTools;

import Paths;

class CacheState extends funkin.states.MusicBeatState {
	var loadingBar:FlxSprite;
	var loadingText:FlxText;
	var loadingPercentage:FlxText;

	var assetsToCache:Array<AssetInfo> = [];
	var currentAssetIndex:Int = 0;
	var totalAssets:Int = 0;

	var loadingComplete:Bool = false;
	var barMaxWidth:Float = 0;

	var _asyncPending:Bool = false;

	#if (android || mobileC)
	static inline final ASSETS_PER_FRAME:Int = 1;
	#else
	static inline final ASSETS_PER_FRAME:Int = 8;
	#end

	override function create() {
		funkin.system.CursorManager.hide();

		// ── UI ─────────────────────────────────────────────────────────────
		var barBG:FlxSprite = new FlxSprite(0, 500).makeGraphic(FlxG.width - 100, 40, 0xFF333333);
		barBG.screenCenter(X);
		add(barBG);

		barMaxWidth = FlxG.width - 110;

		loadingBar = new FlxSprite(barBG.x + 5, barBG.y + 5).makeGraphic(10, 30, FlxColor.LIME);
		add(loadingBar);

		loadingText = new FlxText(0, 450, FlxG.width, "Loading...");
		loadingText.setFormat(Paths.font("Funkin.otf"), 28, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		add(loadingText);

		loadingPercentage = new FlxText(0, 550, FlxG.width, "0%");
		loadingPercentage.setFormat(Paths.font("Funkin.otf"), 24, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		add(loadingPercentage);

		// Assets List
		buildEssentialList();

		assetsToCache.push({type: SCRIPTS, path: '', permanent: false});

		totalAssets = assetsToCache.length;
		super.create();
	}

	function buildEssentialList():Void {
		#if (!android && !mobileC && !ios)
		final sounds:Array<String> = [
			"menus/confirmMenu",
			"menus/cancelMenu",
			"menus/scrollMenu",
			"intro3",
			"intro2",
			"intro1",
			"introGo",
			"soundtray/Volup",
			"soundtray/Voldown",
			"soundtray/VolMAX"
		];
		for (s in sounds)
			assetsToCache.push({type: SOUND, path: s, permanent: true});
		#end

		#if (!android && !mobileC && !ios)
		final images:Array<String> = ["UI/alphabet", "soundtray/volumebox", "menu/cursor/cursor-default"];
		for (i in images)
			assetsToCache.push({type: IMAGE, path: i, permanent: true});
		#end

		#if (android || mobileC || ios)
		final titleImages:Array<String> = [
			"menu/menuBGtitle",
			"titlestate/logoBumpin",
			"titlestate/gfDanceTitle",
			"titlestate/titleEnter"
		];
		for (i in titleImages)
			assetsToCache.push({type: IMAGE, path: i, permanent: false});

		assetsToCache.push({type: MUSIC, path: 'freakyMenu', permanent: false});
		#end
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (loadingComplete)
			return;

		if (_asyncPending)
			return;

		// Assets frame by frame.
		var processed = 0;
		while (processed < ASSETS_PER_FRAME && currentAssetIndex < totalAssets) {
			#if (android || mobileC || ios)
			var asset = assetsToCache[currentAssetIndex];
			if (asset.type == IMAGE || asset.type == MUSIC) {
				_asyncPending = true;
				_cacheAssetAsync(asset, function() {
					currentAssetIndex++;
					_asyncPending = false;
				});
				break;
			}
			#end

			cacheAsset(assetsToCache[currentAssetIndex]);
			currentAssetIndex++;
			processed++;
		}

		final pct:Float = totalAssets > 0 ? currentAssetIndex / totalAssets : 1.0;
		final targetW = barMaxWidth * pct;
		loadingBar.scale.x = targetW / 10;
		loadingBar.updateHitbox();
		loadingPercentage.text = Math.floor(pct * 100) + "%";

		if (currentAssetIndex >= totalAssets && !_asyncPending)
			completeLoading();
	}

	function cacheAsset(asset:AssetInfo):Void {
		try {
			switch (asset.type) {
				case SOUND:
					final path = Paths.sound(asset.path);
					final snd = Paths.getSound(path);
					if (snd != null && asset.permanent)
						Paths.cache.addExclusion(path);

				case IMAGE:
					final path = Paths.image(asset.path);
					final g = Paths.getGraphic(asset.path);
					if (g != null && asset.permanent)
						Paths.cache.addExclusion(path);

				case MUSIC:
					final path = Paths.music(asset.path);
					final snd = Paths.getSound(path);
					if (snd != null && asset.permanent)
						Paths.cache.addExclusion(path);

				case SCRIPTS:
					ScriptHandler.loadGlobalScripts();
			}
		} catch (_:Dynamic) {}
	}

	#if (android || mobileC || ios)
	// Caching for mobile
	function _cacheAssetAsync(asset:AssetInfo, onDone:Void->Void):Void {
		switch (asset.type) {
			case IMAGE:
				final path = Paths.image(asset.path);
				if (Paths.cache.hasValidGraphic(path)) {
					if (asset.permanent)
						Paths.cache.addExclusion(path);
					onDone();
					return;
				}
				OpenFlAssets.loadBitmapData(path).onComplete(function(bmp:openfl.display.BitmapData) {
					if (bmp != null) {
						var optimized = funkin.assets.AssetOptimizer.optimizeBitmapData(bmp);
						if (optimized != bmp)
							try {
								funkin.cache.FunkinCache.instance.setBitmapData(path, optimized);
							} catch (_:Dynamic) {}
						Paths.cache.getGraphic(path, optimized, true);
						if (asset.permanent)
							Paths.cache.addExclusion(path);
					}
					onDone();
				}).onError(function(_) {
					onDone();
				});

			case MUSIC:
				final path = Paths.music(asset.path);
				if (Paths.cache.hasSound(path)) {
					if (asset.permanent)
						Paths.cache.addExclusion(path);
					onDone();
					return;
				}
				OpenFlAssets.loadSound(path).onComplete(function(snd:openfl.media.Sound) {
					if (snd != null) {
						Paths.cache.getSound(path, snd);
						if (asset.permanent)
							Paths.cache.addExclusion(path);
					}
					onDone();
				}).onError(function(_) {
					onDone();
				});

			default:
				cacheAsset(asset);
				onDone();
		}
	}
	#end

	function completeLoading():Void {
		loadingComplete = true;
		loadingText.text = "Ready!";
		loadingPercentage.text = "100%";

		#if (android || mobileC || ios)
		FlxG.signals.postStateSwitch.addOnce(function() {
			var stage = openfl.Lib.current.stage;
			var listener:openfl.events.Event->Void = null;
			listener = function(_:openfl.events.Event):Void {
				stage.removeEventListener(openfl.events.Event.ENTER_FRAME, listener);
				ShaderManager.init();
			};
			stage.addEventListener(openfl.events.Event.ENTER_FRAME, listener);
		});

		funkin.transitions.StateTransition.setNext('none');

		var framesLeft:Int = 6;
		var stage = openfl.Lib.current.stage;
		var frameListener:openfl.events.Event->Void = null;
		frameListener = function(_:openfl.events.Event):Void {
			framesLeft--;
			if (framesLeft > 0)
				return;
			stage.removeEventListener(openfl.events.Event.ENTER_FRAME, frameListener);
			haxe.Timer.delay(goToTitle, 400);
		};
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, frameListener);
		#else
		new FlxTimer().start(0.016, function(_) {
			new FlxTimer().start(0.3, function(_) {
				try {
					FlxG.sound.play(Paths.sound('menus/cacheLoaded'), 0.7);
				} catch (_:Dynamic) {}
				new FlxTimer().start(0.3, function(_) {
					goToTitle();
				});
			});
		});
		#end
	}

	function goToTitle():Void {
		#if (!mobileC && !android && !ios)
		FlxG.autoPause = false;
		#else
		FlxG.autoPause = true;
		#end

		funkin.data.EngineSettings.applyFPS();

		#if (!mobileC && !android && !ios)
		funkin.data.EngineSettings.ensureWindowSize();
		ShaderManager.init();
		#end

		if (!funkin.menus.IntroState.finished && funkin.menus.IntroState.introExists())
			LoadingState.loadAndSwitchState(new funkin.menus.IntroState(), true);
		else
			LoadingState.loadAndSwitchState(new TitleState(), true);
	}
}

typedef AssetInfo = {var type:AssetType; var path:String; var permanent:Bool;}

enum AssetType {
	SOUND;
	IMAGE;
	MUSIC;
	SCRIPTS;
}
