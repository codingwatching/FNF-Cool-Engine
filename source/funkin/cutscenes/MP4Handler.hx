package funkin.cutscenes;

import funkin.states.LoadingState;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.util.FlxTimer;
import openfl.display.Shape;
import openfl.events.Event;

using StringTools;

// =============================================================================
//  NATIVE CPP — hxvlc.flixel.FlxVideo  (desktop + Android + iOS)
//
//  API real de hxvlc 2.x:
//    • hxvlc.flixel.FlxVideo   — Bitmap-based, se añade al stage con addChildBelowMouse
//    • Callbacks son signals:  onEndReached.add() / onEncounteredError.add()
//    • onFormatSetup.add()     — resolución lista, aquí se dimensiona y se quita el cover
//    • load(path) + play()     — en dos pasos, con pequeño timer entre ellos
//    • volume                  — Int 0-200 (100 = normal, 200 = boost)
//    • width/height            — read-only en Bitmap, se ajustan via scaleX/scaleY
// =============================================================================
#if cpp
import hxvlc.flixel.FlxVideo;
import openfl.filters.BitmapFilter;

class MP4Handler
{
	public var finishCallback:Null<Void->Void>;
	public var stateCallback:Null<FlxState>;

	public var bitmap:Dynamic         = null; // compatibilidad legacy
	public var sprite:Null<FlxSprite> = null;

	var _video:Null<FlxVideo>;
	var _cover:Null<Shape>;
	var _killed:Bool = false;
	var _filters:Array<BitmapFilter> = [];

	// Deferred fps restore: how many ENTER_FRAME ticks remain before restoring fps.
	// Set to N when video starts; _update() counts it down and restores on 0.
	var _bootFrames:Int = 0;
	var _bootSavedFps:Int = 0;

	public function new() {}

	// ── Playback ──────────────────────────────────────────────────────────────

	public function playMP4(path:String, ?midSong:Bool = false, ?repeat:Bool = false,
	                        ?outputTo:Null<FlxSprite> = null, ?isWindow:Bool = false,
	                        ?isFullscreen:Bool = false):Void
	{
		_killed  = false;
		_filters = [];

		if (!midSong && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// FIX SampleDataEvent crash (OpenFL 9.3.0): lower fps briefly so the audio
		// backend initialises its buffer with ≥ 2048 samples.
		// We only need this for the first few frames; after that the buffer size is
		// locked in and we can restore the user's target fps.
		// Using AudioConfig.frequency for the exact safe-fps calculation so that
		// non-44100 Hz configurations (e.g. 48 kHz → safe fps = 23) dip less.
		_bootSavedFps = FlxG.save.data.fpsTarget != null ? Std.int(FlxG.save.data.fpsTarget) : 60;
		final safeFps:Int = Std.int(Math.floor(funkin.audio.AudioConfig.frequency / 2048));
		final main = cast(openfl.Lib.current.getChildAt(0), Main);
		if (main != null) main.setMaxFps(safeFps);
		#if lime
		final _limeWin = lime.app.Application.current?.window;
		if (_limeWin != null) _limeWin.frameRate = safeFps;
		#end
		_bootFrames = 4; // restore after 4 rendered frames (~66 ms at safe fps)

		// Cover negro mientras el decoder arranca
		_cover = new Shape();
		_cover.graphics.beginFill(0x000000);
		_cover.graphics.drawRect(0, 0, FlxG.stage.stageWidth, FlxG.stage.stageHeight);
		_cover.graphics.endFill();
		try FlxG.addChildBelowMouse(_cover) catch (_:Dynamic) {}

		// ── FlxVideo ──────────────────────────────────────────────────────────
		_video = new FlxVideo();

		sprite = outputTo;

		// onFormatSetup — resolución lista, dimensionar el video
		_video.onFormatSetup.add(function()
		{
			if (_video == null || _killed) return;

			final sw:Float    = FlxG.stage.stageWidth;
			final sh:Float    = FlxG.stage.stageHeight;
			final ratio:Float = 16.0 / 9.0;
			final vw:Float    = (sw / sh > ratio) ? sh * ratio : sw;
			final vh:Float    = (sw / sh > ratio) ? sh          : sw / ratio;

			// FlxVideo extiende Bitmap — width/height son read-only.
			// Usar scaleX/scaleY para dimensionar.
			if (_video.bitmapData != null && _video.bitmapData.width > 0)
			{
				_video.scaleX = vw / _video.bitmapData.width;
				_video.scaleY = vh / _video.bitmapData.height;
			}
			_video.x = (sw - vw) / 2;
			_video.y = (sh - vh) / 2;

			// Si se usa como outputTo, copiar el primer frame
			if (sprite != null && _video.bitmapData != null)
				try sprite.loadGraphic(_video.bitmapData) catch (_:Dynamic) {}

			// Quitar cover — en hxvlc el primer frame ya está renderizado en onFormatSetup
			_removeCover();

			// Aplicar filtros pendientes
			if (_filters.length > 0)
				try _video.filters = _filters.copy() catch (_:Dynamic) {}

			_syncVolume();
		});

		// onEndReached — fin del video
		_video.onEndReached.add(function()
		{
			if (!_killed) _finish();
		});

		// onEncounteredError — tratar como fin, el juego nunca se queda colgado
		_video.onEncounteredError.add(function(msg:String)
		{
			trace('[MP4Handler] hxvlc error — ' + msg);
			if (!_killed) _finish();
		});

		// Sincronizar volumen cada frame
		FlxG.stage.addEventListener(Event.ENTER_FRAME, _update);

		// Si es outputTo, no añadir al stage (renderizar en el sprite)
		if (outputTo == null)
			try FlxG.addChildBelowMouse(_video) catch (_:Dynamic) {}

		// Cargar y reproducir — esperar 3 frames para que stage.frameRate=60 esté activo
		// antes de que hxvlc registre su SampleDataEvent listener.
		new FlxTimer().start(0.1, function(_)
		{
			if (_video == null || _killed) return;
			if (_video.load(path))
				new FlxTimer().start(0.001, function(_) { if (_video != null && !_killed) _video.play(); });
			else
			{
				trace('[MP4Handler] hxvlc: no se pudo cargar "$path"');
				_finish();
			}
		});
	}

	// ── Shader / Filter API ───────────────────────────────────────────────────

	public function applyFilter(filter:BitmapFilter):Void
	{
		if (filter == null) return;
		_filters.push(filter);
		if (_video != null) try _video.filters = _filters.copy() catch (_:Dynamic) {}
	}

	public function removeFilter(filter:BitmapFilter):Void
	{
		_filters.remove(filter);
		if (_video != null) try _video.filters = _filters.copy() catch (_:Dynamic) {}
	}

	public function clearFilters():Void
	{
		_filters = [];
		if (_video != null) try _video.filters = [] catch (_:Dynamic) {}
	}

	// ── Controls ──────────────────────────────────────────────────────────────

	public function kill():Void
	{
		if (_killed) return;
		_killed = true;

		FlxG.stage.removeEventListener(Event.ENTER_FRAME, _update);
		_removeCover();
		_stopAndDispose();
		_restoreFrameRate();

		if (finishCallback != null)
		{
			final cb = finishCallback;
			finishCallback = null;
			cb();
		}
	}

	public function pause():Void
	{
		if (_video == null) return;
		// Just pause playback. The video bitmap stays in its current position in
		// the display list so it remains visible behind the pause-menu overlay.
		try _video.pause() catch (_:Dynamic) {}
	}

	public function resume():Void
	{
		if (_video == null) return;
		// Video never moved, nothing to reorder. Just resume playback.
		try _video.resume() catch (_:Dynamic) {}
		_syncVolume();
	}

	// ── Internals ─────────────────────────────────────────────────────────────

	function _update(_:Event):Void
	{
		// Deferred fps restore: once the audio backend has fired its first
		// SampleDataEvent (after a few frames), we can go back to the target fps.
		if (_bootFrames > 0)
		{
			_bootFrames--;
			if (_bootFrames == 0)
				_restoreFrameRate();
		}

		_syncVolume();

		// Copiar frame al sprite si se usa como outputTo
		if (sprite != null && _video != null && _video.bitmapData != null)
			try sprite.loadGraphic(_video.bitmapData) catch (_:Dynamic) {}
	}

	function _syncVolume():Void
	{
		if (_video == null) return;
		// hxvlc volume: 0-200 (100 = nivel normal)
		final vol:Float = FlxG.sound.muted ? 0.0 : FlxG.sound.volume;
		try _video.volume = Std.int(vol * 100) catch (_:Dynamic) {}
	}

	function _finish():Void
	{
		if (_killed) return;
		_killed = true;

		FlxG.stage.removeEventListener(Event.ENTER_FRAME, _update);

		new FlxTimer().start(0.1, function(_)
		{
			_removeCover();
			_stopAndDispose();
			_restoreFrameRate();

			if (finishCallback != null)
			{
				final cb = finishCallback;
				finishCallback = null;
				cb();
			}
			else if (stateCallback != null)
				LoadingState.loadAndSwitchState(stateCallback);
		});
	}

	function _removeCover():Void
	{
		if (_cover == null) return;
		try FlxG.removeChild(_cover) catch (_:Dynamic) {}
		_cover = null;
	}

	function _stopAndDispose():Void
	{
		if (_video == null) return;
		try FlxG.removeChild(_video) catch (_:Dynamic) {}
		try _video.stop()    catch (_:Dynamic) {}
		try _video.dispose() catch (_:Dynamic) {}
		_video  = null;
		sprite  = null;
		bitmap  = null;
	}

	/** Restaura el FPS al valor previo al video via Main.setMaxFps(). */
	function _restoreFrameRate():Void
	{
		// Only restore if there's a saved value (avoids double-restore).
		if (_bootSavedFps <= 0) return;
		var main = cast(openfl.Lib.current.getChildAt(0), Main);
		if (main != null) main.setMaxFps(_bootSavedFps);
		#if lime
		final _limeWin = lime.app.Application.current?.window;
		if (_limeWin != null) _limeWin.frameRate = _bootSavedFps;
		#end
		_bootSavedFps = 0;
		_bootFrames   = 0;
	}
}

// =============================================================================
//  STUB — HTML5 y plataformas sin hxvlc.
// =============================================================================
#else

class MP4Handler
{
	public var finishCallback:Null<Void->Void>;
	public var stateCallback:Null<FlxState>;
	public var bitmap:Dynamic = null;
	public var sprite:Dynamic = null;

	public function new() {}

	public function playMP4(path:String, ?midSong:Bool = false, ?repeat:Bool = false,
	                        ?outputTo:Dynamic = null, ?isWindow:Bool = false,
	                        ?isFullscreen:Bool = false):Void
	{
		trace("MP4Handler: hxvlc no disponible en esta plataforma.");
		_skip();
	}

	public function applyFilter(_:Dynamic):Void  {}
	public function removeFilter(_:Dynamic):Void {}
	public function clearFilters():Void          {}
	public function kill():Void                  { _skip(); }
	public function pause():Void                 {}
	public function resume():Void                {}

	inline function _skip():Void
	{
		if (finishCallback != null) { final cb = finishCallback; finishCallback = null; cb(); }
		else if (stateCallback != null) funkin.states.LoadingState.loadAndSwitchState(stateCallback);
	}
}

#end
