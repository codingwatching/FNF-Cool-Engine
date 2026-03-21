package funkin.gameplay;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.group.FlxGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.FlxBasic;
import funkin.data.Conductor;
import funkin.data.CoolUtil;
import funkin.data.Song.SwagSong;
import funkin.data.Song.CharacterSlotData;
import funkin.gameplay.objects.character.CharacterSlot;
import funkin.gameplay.objects.stages.Stage;

/**
 * FlxSubState wrapper that runs a PlayState-style scene in cinematic mode:
 * stage + characters + audio, no HUD, no strums, no notes.
 *
 * Used by CutsceneEditorState so it can call openSubState() with a proper
 * FlxSubState (PlayState itself extends FlxState and cannot be used there).
 *
 * Setup mirrors PlayState.loadStageAndCharacters() and the audio loading
 * block in PlayState.generateSong(), stripped to the cinematic-only path.
 */
class PlayStateSubState extends funkin.states.MusicBeatSubstate
{
	// ── Camera ────────────────────────────────────────────────────────────────
	/** Game-world camera — rendered below the editor's camHUD. */
	var _camGame:FlxCamera;

	// ── Scene ─────────────────────────────────────────────────────────────────
	var _currentStage:Stage;
	var _charSlots:Array<CharacterSlot> = [];

	/** Optional callback fired when the instrumental reaches its end. */
	public var onSongEnd:Void->Void = null;

	public function new() { super(); }

	// ── Lifecycle ─────────────────────────────────────────────────────────────

	override function create():Void
	{
		var SONG = PlayState.SONG;
		if (SONG == null)
		{
			super.create();
			return;
		}

		// ── Camera ────────────────────────────────────────────────────────────
		// Add camGame BEFORE calling super.create() so sprites added during
		// stage/character setup get assigned to it via _defaultCameras.
		// The editor's camHUD was already added by CutsceneEditorState, so
		// camGame goes in after it but is forced to render underneath via
		// _defaultCameras — CutsceneEditorState assigns its own sprites to camHUD.
		_camGame = new FlxCamera();
		_camGame.bgColor = 0xFF000000;
		FlxG.cameras.add(_camGame, false);
		@:privateAccess FlxCamera._defaultCameras = [_camGame];

		// ── Stage ─────────────────────────────────────────────────────────────
		if (SONG.stage == null || SONG.stage == '')
			SONG.stage = 'stage_week1';

		PlayState.curStage  = SONG.stage;
		Paths.currentStage  = SONG.stage;

		_currentStage = new Stage(SONG.stage);
		_currentStage.cameras = [_camGame];
		_assignCameras(_currentStage, [_camGame]);
		add(_currentStage);

		// ── Characters ────────────────────────────────────────────────────────
		_loadCharacters(SONG);

		if (_currentStage.aboveCharsGroup != null && _currentStage.aboveCharsGroup.length > 0)
			add(_currentStage.aboveCharsGroup);

		// ── Audio ─────────────────────────────────────────────────────────────
		Conductor.changeBPM(SONG.bpm);

		// Stop any leftover music from menus / previous sessions.
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}
		funkin.audio.MusicManager.invalidate();

		final diffSuffix = (SONG.instSuffix != null && SONG.instSuffix != '')
			? '-' + SONG.instSuffix
			: CoolUtil.difficultySuffix();

		final inst = Paths.loadInst(SONG.song, diffSuffix);
		if (inst != null)
		{
			funkin.audio.CoreAudio.setInst(inst);
			FlxG.sound.music = inst;
			inst.volume     = 1;
			inst.onComplete = _onSongEnd;
			// Cinematic mode: no countdown, start immediately.
			Conductor.songPosition = 0;
			inst.time = 0;
			inst.play();
		}
		else
		{
			trace('[PlayStateSubState] WARNING: Could not load instrumental for "${SONG.song}" — audio will be silent.');
		}

		super.create();
	}

	// ── Internal helpers ──────────────────────────────────────────────────────

	function _loadCharacters(SONG:SwagSong):Void
	{
		// Mirror PlayState.loadCharacters() — build legacy character list if absent.
		if (SONG.characters == null || SONG.characters.length == 0)
		{
			SONG.characters = [];
			SONG.characters.push({
				name: SONG.gfVersion != null ? SONG.gfVersion : 'gf',
				x: 0, y: 0, visible: true, isGF: true,
				type: 'Girlfriend', strumsGroup: 'gf_strums_0'
			});
			SONG.characters.push({
				name: SONG.player2 != null ? SONG.player2 : 'dad',
				x: 0, y: 0, visible: true,
				type: 'Opponent', strumsGroup: 'cpu_strums_0'
			});
			SONG.characters.push({
				name: SONG.player1 != null ? SONG.player1 : 'bf',
				x: 0, y: 0, visible: true,
				type: 'Player', strumsGroup: 'player_strums_0'
			});
		}

		for (i in 0...SONG.characters.length)
		{
			final charData = SONG.characters[i];
			final slot     = new CharacterSlot(charData, i);

			// Position: stage defaults when the JSON stores (0, 0).
			if (charData.x == 0 && charData.y == 0)
			{
				switch (slot.charType)
				{
					case 'Girlfriend':
						slot.character.setPosition(_currentStage.gfPosition.x,       _currentStage.gfPosition.y);
					case 'Opponent':
						slot.character.setPosition(_currentStage.dadPosition.x,       _currentStage.dadPosition.y);
					case 'Player':
						slot.character.setPosition(_currentStage.boyfriendPosition.x, _currentStage.boyfriendPosition.y);
					default:
				}
			}
			else
			{
				slot.character.setPosition(charData.x, charData.y);
			}

			// Apply per-character position offset (Psych compat).
			if (slot.character.characterData != null)
			{
				final off = slot.character.characterData.positionOffset;
				if (off != null && off.length >= 2)
				{
					slot.character.x += off[0];
					slot.character.y += off[1];
				}
			}

			slot.character.cameras = [_camGame];
			_charSlots.push(slot);
			add(slot.character);
		}

		// Hide GF if stage requests it.
		if (_currentStage.hideGirlfriend)
			for (s in _charSlots)
				if (s.isGFSlot && s.character != null)
					s.character.visible = false;
	}

	/** Recursively propagate a camera list to every member of a group. */
	function _assignCameras(obj:FlxBasic, cams:Array<FlxCamera>):Void
	{
		obj.cameras = cams;
		if (Std.isOfType(obj, FlxGroup))
			for (m in (cast obj : FlxGroup).members)
				if (m != null) _assignCameras(m, cams);
	}

	function _onSongEnd():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.pause();
		if (onSongEnd != null) onSongEnd();
	}

	override function destroy():Void
	{
		// Remove camGame from Flixel's list; MusicBeatSubstate.destroy handles the rest.
		if (_camGame != null)
		{
			FlxG.cameras.remove(_camGame, true);
			_camGame = null;
		}
		super.destroy();
	}
}
