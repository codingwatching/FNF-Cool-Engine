package funkin.cutscenes;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.util.FlxColor;
import flixel.util.FlxSignal;
import flixel.util.FlxTimer;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import funkin.states.LoadingState;

using StringTools;

// ─────────────────────────────────────────────────────────────────────────────
// VideoManager — sistema centralizado de reproducción de video.
//
// Re-worked following V-Slice (FunkinCrew/Funkin) patterns:
//   • FlxSignal hooks: onVideoStarted / onVideoEnded / onVideoPaused / onVideoResumed
//   • CutsceneType enum mirrors V-Slice behaviour
//   • Desktop cpp  → VLC via MP4Handler  (unchanged, works well)
//   • Mobile / mobileC → OpenFL NetStream via MP4Handler  (no VLC calls → no crash)
//   • Other / html5 → graceful skip
//   • Null-safety on every code path
//
// SKIP: videos only skippable from PauseSubState → "Skip Cutscene".
//       No keyboard listeners here.
//
// Usage:
//   VideoManager.playCutscene('intro', function() { startCountdown(); });
//   VideoManager.playMidSong('explosion', playState, callback);
//   VideoManager.playBackground('menuBG', mySprite);
//   VideoManager.playOnSprite('logo', mySprite, callback);
// ─────────────────────────────────────────────────────────────────────────────

class VideoManager
{
	// ── V-Slice–style signals ─────────────────────────────────────────────────

	/** Dispatched the moment a video starts playing. */
	public static final onVideoStarted:FlxSignal = new FlxSignal();

	/** Dispatched when the video is paused (e.g. pause menu opened). */
	public static final onVideoPaused:FlxSignal = new FlxSignal();

	/** Dispatched when the video resumes after being paused. */
	public static final onVideoResumed:FlxSignal = new FlxSignal();

	/** Dispatched when the video ends or is skipped. */
	public static final onVideoEnded:FlxSignal = new FlxSignal();

	// ── State ─────────────────────────────────────────────────────────────────

	/** True while a video is actively playing. */
	public static var isPlaying(get, never):Bool;
	static function get_isPlaying():Bool return current != null;

	/** The active MP4Handler, or null when idle. */
	public static var current:Null<MP4Handler> = null;

	static var _onComplete:Null<Void->Void> = null;

	// Path-resolution cache, invalidated on mod change.
	static var _pathCache:Map<String, String> = new Map();

	/** Active video shaders: name → {filter, instance} */
	static var _videoShaderInstances:Map<String, {
		filter  : openfl.filters.ShaderFilter,
		instance: flixel.addons.display.FlxRuntimeShader
	}> = new Map();

	/** Invalidate resolved-path cache (call when the active mod changes). */
	public static function clearPathCache():Void _pathCache.clear();

	// ─────────────────────────────────────────────────────────────────────────
	// Public API
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Play a video as a full-screen cutscene (pauses music, black background).
	 * On unsupported platforms the callback is called immediately.
	 */
	public static function playCutscene(key:String, ?onComplete:Void->Void):Void
	{
		final path = _resolvePath(key);
		if (path == null)
		{
			trace('[VideoManager] playCutscene: "$key" not found — skipping.');
			if (onComplete != null) onComplete();
			return;
		}

		_stopCurrent();
		_onComplete = onComplete;

		if (FlxG.sound.music != null && FlxG.sound.music.playing)
			FlxG.sound.music.pause();

		final handler = new MP4Handler();
		current = handler;

		// midSong=true so playMP4 does NOT call FlxG.sound.music.stop().
		// Music was already paused; stop() would invalidate the streaming FlxSound on CPP.
		handler.playMP4(path, true, false, null, false, false);
		handler.finishCallback = _buildFinish();

		onVideoStarted.dispatch();
	}

	/**
	 * Play a video mid-song. Pauses gameplay + music, restores them on finish.
	 */
	public static function playMidSong(key:String,
	                                   ?state:funkin.gameplay.PlayState,
	                                   ?onComplete:Void->Void):Void
	{
		final path = _resolvePath(key);
		if (path == null)
		{
			trace('[VideoManager] playMidSong: "$key" not found — skipping.');
			if (onComplete != null) onComplete();
			return;
		}

		_stopCurrent();
		_onComplete = onComplete;

		if (state != null)
		{
			state.paused     = true;
			state.canPause   = false;
			state.inCutscene = true;
		}
		if (FlxG.sound.music != null) FlxG.sound.music.pause();

		final handler = new MP4Handler();
		current = handler;

		handler.playMP4(path, true, false, null, false, false);
		handler.finishCallback = function()
		{
			if (state != null)
			{
				state.paused     = false;
				state.canPause   = true;
				state.inCutscene = false;
			}
			_buildFinish()();
		};

		onVideoStarted.dispatch();
	}

	/**
	 * Play a looping video as a background inside a FlxSprite.
	 */
	public static function playBackground(key:String, sprite:FlxSprite):Void
	{
		final path = _resolvePath(key);
		if (path == null)
		{
			trace('[VideoManager] playBackground: "$key" not found.');
			return;
		}

		_stopCurrent();

		final handler = new MP4Handler();
		current = handler;
		handler.playMP4(path, true, true, sprite, false, false);
	}

	/**
	 * Play a video rendered into a FlxSprite, with an optional finish callback.
	 */
	public static function playOnSprite(key:String, sprite:FlxSprite, ?onComplete:Void->Void):Void
	{
		final path = _resolvePath(key);
		if (path == null)
		{
			trace('[VideoManager] playOnSprite: "$key" not found.');
			if (onComplete != null) onComplete();
			return;
		}

		_stopCurrent();
		_onComplete = onComplete;

		final handler = new MP4Handler();
		current = handler;
		handler.playMP4(path, true, false, sprite, false, false);
		handler.finishCallback = _buildFinish();

		onVideoStarted.dispatch();
	}

	// ── Shader / Filter API ───────────────────────────────────────────────────

	/**
	 * Aplica un ShaderFilter al video en reproducción usando el ShaderManager.
	 * Seguro llamar desde HScript:
	 *
	 *   VideoManager.applyShader('chromaKey');
	 *   VideoManager.setVideoShaderParam('chromaKey', 'threshold', 0.3);
	 *
	 * @param shaderName  Nombre del shader (sin .frag)
	 * @return El ShaderFilter creado, o null si el video no está activo o el shader no existe.
	 */
	public static function applyShader(shaderName:String):Null<openfl.filters.ShaderFilter>
	{
		if (current == null)
		{
			trace('[VideoManager] applyShader: ningún video activo.');
			return null;
		}

		final cs = shaders.ShaderManager.getShader(shaderName);
		if (cs == null || cs.fragmentCode == null)
		{
			trace('[VideoManager] applyShader: shader "$shaderName" no encontrado.');
			return null;
		}

		var instance:flixel.addons.display.FlxRuntimeShader;
		try
		{
			instance = new flixel.addons.display.FlxRuntimeShader(cs.fragmentCode);
		}
		catch (e:Dynamic)
		{
			trace('[VideoManager] applyShader: error compilando "$shaderName": $e');
			return null;
		}

		final sf = new openfl.filters.ShaderFilter(cast instance);
		current.applyFilter(sf);

		// Registrar la instancia en ShaderManager para que setVideoShaderParam() funcione.
		shaders.ShaderManager.registerInstance(shaderName, instance);

		_videoShaderInstances.set(shaderName, {filter: sf, instance: instance});
		trace('[VideoManager] Shader "$shaderName" aplicado al video.');
		return sf;
	}

	/**
	 * Actualiza un uniform del shader del video en reproducción.
	 * Usa la misma API que ShaderManager.setShaderParam():
	 *
	 *   VideoManager.setVideoShaderParam('chromaKey', 'threshold', 0.25);
	 */
	public static function setVideoShaderParam(shaderName:String, paramName:String, value:Dynamic):Bool
		return shaders.ShaderManager.setShaderParam(shaderName, paramName, value);

	/**
	 * Quita el shader con nombre `shaderName` del video activo.
	 */
	public static function removeShader(shaderName:String):Void
	{
		if (current == null) return;
		final entry = _videoShaderInstances.get(shaderName);
		if (entry == null) return;
		current.removeFilter(entry.filter);
		shaders.ShaderManager.unregisterInstance(shaderName, entry.instance);
		_videoShaderInstances.remove(shaderName);
	}

	/**
	 * Quita TODOS los shaders del video activo.
	 */
	public static function clearVideoShaders():Void
	{
		if (current != null) current.clearFilters();
		for (name => entry in _videoShaderInstances)
			shaders.ShaderManager.unregisterInstance(name, entry.instance);
		_videoShaderInstances.clear();
	}

	/**
	 * Aplica directamente un BitmapFilter OpenFL al video (para shaders custom
	 * creados sin pasar por ShaderManager).
	 *
	 *   var sf = new openfl.filters.ShaderFilter(myCustomShader);
	 *   VideoManager.applyRawFilter(sf);
	 */
	public static function applyRawFilter(filter:openfl.filters.BitmapFilter):Void
	{
		if (current == null) return;
		current.applyFilter(filter);
	}

	/** Quita un BitmapFilter aplicado con applyRawFilter(). */
	public static function removeRawFilter(filter:openfl.filters.BitmapFilter):Void
	{
		if (current == null) return;
		current.removeFilter(filter);
	}

	// ── Controls ──────────────────────────────────────────────────────────────

	/**
	 * Stop playback and trigger the finish callback (use for skip from PauseSubState).
	 */
	public static function stop():Void
	{
		if (current == null) return;
		current.kill();
		_cleanup();
	}

	/**
	 * Pause the video and push it behind the Flixel canvas.
	 * Call when opening the pause menu during a cutscene.
	 */
	public static function pause():Void
	{
		if (current == null) return;
		current.pause();
		onVideoPaused.dispatch();
	}

	/**
	 * Resume a paused video and bring it back above the Flixel canvas.
	 */
	public static function resume():Void
	{
		if (current == null) return;
		current.resume();
		onVideoResumed.dispatch();
	}

	/**
	 * Silently kill the video without triggering any callback.
	 * Use when leaving a state that was playing a background video.
	 */
	public static function stopSilent():Void
	{
		if (current == null) return;
		_onComplete            = null;
		current.finishCallback = null;
		current.kill();
		current = null;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Helpers
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Resolve a video key to an absolute path.
	 * Checks the active mod first, then base assets.
	 * Cached per-key; call clearPathCache() when the mod changes.
	 */
	public static function _resolvePath(key:String):Null<String>
	{
		final cached = _pathCache.get(key);
		if (cached != null) return cached;

		final k = key.endsWith('.mp4') ? key.substr(0, key.length - 4) : key;

		final candidates:Array<String> = [];

		final mod = mods.ModManager.activeMod;
		if (mod != null)
		{
			final base = '${mods.ModManager.MODS_FOLDER}/$mod';
			candidates.push('$base/videos/$k.mp4');
			candidates.push('$base/cutscenes/videos/$k.mp4');
			final songName = funkin.gameplay.PlayState.SONG?.song?.toLowerCase();
			if (songName != null)
				candidates.push('$base/songs/$songName/$k.mp4');
		}

		candidates.push('assets/videos/$k.mp4');
		candidates.push('assets/cutscenes/videos/$k.mp4');

		final songName = funkin.gameplay.PlayState.SONG?.song?.toLowerCase();
		if (songName != null)
			candidates.push('assets/songs/$songName/$k.mp4');

		#if sys
		for (c in candidates)
			if (sys.FileSystem.exists(c)) { _pathCache.set(key, c); return c; }
		#else
		for (c in candidates)
			if (openfl.utils.Assets.exists(c)) { _pathCache.set(key, c); return c; }
		#end

		return null;
	}

	static function _stopCurrent():Void
	{
		if (current == null) return;
		_onComplete            = null;
		current.finishCallback = null;
		current.kill();
		current = null;
		_videoShaderInstances.clear();
	}

	static function _buildFinish():Void->Void
	{
		return function()
		{
			final cb = _onComplete;
			_cleanup();
			onVideoEnded.dispatch();
			if (cb != null) cb();
		};
	}

	static function _cleanup():Void
	{
		current     = null;
		_onComplete = null;
		_videoShaderInstances.clear();
	}
}
