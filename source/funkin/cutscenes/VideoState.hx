package funkin.cutscenes;

import lime.utils.Assets;
import funkin.states.MusicBeatState;
import flixel.FlxState;
import flixel.FlxG;
import funkin.cutscenes.MP4Handler;
import funkin.states.LoadingState;

// ────────────────────────────────────────────────────────────────────────────
// VideoState — standalone state that plays an MP4 cutscene then transitions.
//
// V-Slice parity:
//   • Desktop cpp  → MP4Handler with libVLC
//   • Mobile        → MP4Handler with OpenFL NetStream (no VLC, no crash)
//   • Other         → immediately skips to nextState
//   • Skip: ESCAPE only (avoids conflict with ENTER opening pause menu)
//   • If the file is missing the state transitions immediately.
// ────────────────────────────────────────────────────────────────────────────

class VideoState extends MusicBeatState
{
	var videoPath:String;
	var nextState:FlxState;

	var _handler:Null<MP4Handler>;

	public function new(path:String, state:FlxState)
	{
		super();
		this.videoPath = path;
		this.nextState = state;
	}

	public override function create():Void
	{
		FlxG.autoPause = true;

		// On any cpp target (desktop OR mobile) we have MP4Handler available.
		// On mobile it uses the NetStream path instead of VLC — safe on Android.
		#if cpp
		final resolvedPath = Paths.video(videoPath);
		final exists:Bool  =
			#if sys
			sys.FileSystem.exists(resolvedPath)
			#else
			Assets.exists(resolvedPath)
			#end;

		if (exists)
		{
			_handler = new MP4Handler();
			_handler.playMP4(resolvedPath);
			_handler.finishCallback = function()
			{
				_handler = null;
				_skipToNext();
			};
			VideoManager.onVideoStarted.dispatch();
		}
		else
		{
			trace('VideoState: file not found — $resolvedPath — skipping.');
			_skipToNext();
		}
		#else
		trace('VideoState: video playback not supported on this platform — skipping.');
		_skipToNext();
		#end

		super.create();
	}

	public override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		#if cpp
		if (FlxG.keys.justPressed.ESCAPE && _handler != null)
		{
			_handler.kill();
			_handler = null;
		}
		#end
	}

	public override function destroy():Void
	{
		// Guard against leaked handlers if the state is destroyed externally.
		if (_handler != null)
		{
			_handler.finishCallback = null;
			_handler.kill();
			_handler = null;
		}
		super.destroy();
	}

	function _skipToNext():Void
	{
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		LoadingState.loadAndSwitchState(nextState);
	}
}
