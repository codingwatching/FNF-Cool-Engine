package funkin.gameplay;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxBasic;
import flixel.group.FlxGroup;
import flixel.sound.FlxSound;
import funkin.data.Conductor;
import funkin.data.CoolUtil;
import funkin.data.Song.SwagSong;
import funkin.data.Song.CharacterSlotData;
import funkin.data.Section;
import funkin.data.Section.SwagSection;
import funkin.gameplay.CameraController;
import funkin.gameplay.CharacterController;
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.objects.character.CharacterSlot;
import funkin.gameplay.objects.stages.Stage;
import funkin.scripting.events.EventManager;
import funkin.scripting.ScriptHandler;

/**
 * FlxSubState wrapper that executes PlayState in modo cinemático:
 * stage + characters + audio + scripts + events + camera with follow.
 *
 * Replica fielmente el pipeline de create() / update() / beatHit() / stepHit()
 * de PlayState limitado al modo cinematicMode (sin notas, sin HUD de juego).
 *
 * Usado por CutsceneEditorState para poder llamar openSubState() con un
 * FlxSubState actual (PlayState extiende FlxState and no puede usarse ahí).
 */
class PlayStateSubState extends funkin.states.MusicBeatSubstate
{
	// ── Cameras ───────────────────────────────────────────────────────────────
	/** Camera of the mundo of game, renderizada under the overlay of the editor. */
	public var camGame:FlxCamera;

	// ── Escena ────────────────────────────────────────────────────────────────
	public var currentStage:Stage;
	public var characterSlots:Array<CharacterSlot> = [];

	// Referencias legacy (compatibilidad con scripts)
	public var boyfriend:Character;
	public var dad:Character;
	public var gf:Character;

	// ── Controladores ─────────────────────────────────────────────────────────
	public var cameraController:CameraController;
	public var characterController:CharacterController;

	// ── Audio ─────────────────────────────────────────────────────────────────
	public var vocals:FlxSound;
	public var vocalsPerChar:Map<String, FlxSound> = new Map();

	private var _usingPerCharVocals:Bool = false;
	private var _vocalsPlayerKeys:Array<String>   = [];
	private var _vocalsOpponentKeys:Array<String> = [];
	private var _resyncCooldown:Int = 0;

	// ── Callbacks ─────────────────────────────────────────────────────────────
	/** Disparado cuando el instrumental llega al final. */
	public var onSongEnd:Void->Void = null;

	// ── Estado interno ────────────────────────────────────────────────────────
	var _scriptsEnabled:Bool = false;
	var _cachedSectionIndex:Int = -1;

	// ── Autoplay ──────────────────────────────────────────────────────────────
	// Lista plana de todas las notas del chart, ordenadas por strumTime.
	// Is generates a sola vez in create() and is consume with a index incremental
	// → O(1) por frame en lugar de iterar todo el array.
	var _autoplayNotes:Array<{strumTime:Float, noteData:Int, mustPress:Bool,
	                           isSustain:Bool, gfSing:Bool, altAnim:Bool}> = [];
	var _autoplayIdx:Int = 0;

	// ─────────────────────────────────────────────────────────────────────────

	public function new() { super(); }

	// ── Lifecycle ─────────────────────────────────────────────────────────────

	override function create():Void
	{
		var SONG = PlayState.SONG;
		if (SONG == null) { super.create(); return; }

		// ── Camera ────────────────────────────────────────────────────────────
		// camGame is adds before of construir the stage for that _defaultCameras
		// apunte to it during the adds (igual that PlayState.setupCameras).
		camGame = new FlxCamera();
		camGame.bgColor = 0xFF000000;
		FlxG.cameras.add(camGame, false);
		@:privateAccess FlxCamera._defaultCameras = [camGame];

		// ── Scripts — fase 1: song (before of the stage, igual that PlayState) ──
		#if HSCRIPT_ALLOWED
		ScriptHandler.init();
		ScriptHandler.loadSongScripts(SONG.song);
		EventManager.loadEventsFromSong();

		ScriptHandler.setOnScripts('playState', this);
		ScriptHandler.setOnScripts('game',      this);
		ScriptHandler.setOnScripts('SONG',      SONG);
		ScriptHandler.setOnScripts('camGame',   camGame);

		ScriptHandler.callOnScripts('onCreate', ScriptHandler._argsEmpty);
		_scriptsEnabled = true;
		#end

		// ── Stage ─────────────────────────────────────────────────────────────
		if (SONG.stage == null || SONG.stage == '')
			SONG.stage = 'stage_week1';

		PlayState.curStage = SONG.stage;
		Paths.currentStage = SONG.stage;

		currentStage = new Stage(SONG.stage);
		currentStage.cameras = [camGame];
		_assignCameras(currentStage, [camGame]);
		add(currentStage);

		// ── Personajes ────────────────────────────────────────────────────────
		_loadCharacters(SONG);

		if (currentStage.aboveCharsGroup != null && currentStage.aboveCharsGroup.length > 0)
			add(currentStage.aboveCharsGroup);

		// ── CameraController ──────────────────────────────────────────────────
		if (boyfriend != null && dad != null)
		{
			cameraController = new CameraController(camGame, camGame, boyfriend, dad, gf);
			if (currentStage.defaultCamZoom > 0)
				cameraController.defaultZoom = currentStage.defaultCamZoom;
			cameraController.stageOffsetBf.set(currentStage.cameraBoyfriend.x,  currentStage.cameraBoyfriend.y);
			cameraController.stageOffsetDad.set(currentStage.cameraDad.x,       currentStage.cameraDad.y);
			cameraController.stageOffsetGf.set(currentStage.cameraGirlfriend.x, currentStage.cameraGirlfriend.y);
			cameraController.lerpSpeed = CameraController.BASE_LERP_SPEED * currentStage.cameraSpeed;
			cameraController.snapshotInitialState();
		}

		// ── CharacterController ───────────────────────────────────────────────
		characterController = new CharacterController();
		characterController.initFromSlots(characterSlots);

		// ── Scripts — fase 2: variables de escena ─────────────────────────────
		#if HSCRIPT_ALLOWED
		if (_scriptsEnabled)
		{
			ScriptHandler.setOnScripts('boyfriend',           boyfriend);
			ScriptHandler.setOnScripts('dad',                 dad);
			ScriptHandler.setOnScripts('gf',                  gf);
			ScriptHandler.setOnScripts('stage',               currentStage);
			ScriptHandler.setOnScripts('cameraController',    cameraController);
			ScriptHandler.setOnScripts('characterController', characterController);

			for (slot in characterSlots)
			{
				final char = slot.character;
				if (char == null) continue;
				ScriptHandler.loadCharacterScripts(char.curCharacter);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'character', char);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'char',      char);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'game',      this);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'playState', this);
				ScriptHandler.callOnCharacterScripts(char.curCharacter, 'postCreate', ScriptHandler._argsEmpty);
			}

			ScriptHandler.callOnNonStageScripts('onStageCreate', ScriptHandler._argsEmpty);
			ScriptHandler.callOnScripts('postCreate', ScriptHandler._argsEmpty);
		}
		#end

		// ── Audio ─────────────────────────────────────────────────────────────
		Conductor.changeBPM(SONG.bpm);
		_setupAudio(SONG);

		// ── Autoplay ──────────────────────────────────────────────────────────
		// Parsear el chart una sola vez para poder disparar animaciones de canto
		// sin necesitar NoteManager, strums ni input.
		_buildAutoplayNotes(SONG);

		super.create();
	}

	// ── Audio ─────────────────────────────────────────────────────────────────

	function _setupAudio(SONG:SwagSong):Void
	{
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}
		funkin.audio.MusicManager.invalidate();
		funkin.audio.CoreAudio.clearVocals();

		final diffSuffix = (SONG.instSuffix != null && SONG.instSuffix != '')
			? '-' + SONG.instSuffix
			: CoolUtil.difficultySuffix();

		// Instrumental
		final inst = Paths.loadInst(SONG.song, diffSuffix);
		if (inst != null)
		{
			funkin.audio.CoreAudio.setInst(inst);
			FlxG.sound.music      = inst;
			inst.onComplete       = _onSongEnd;
			Conductor.songPosition = 0;
			inst.time              = 0;
			funkin.audio.CoreAudio.play(inst);
		}
		else
		{
			trace('[PlayStateSubState] WARNING: No se pudo cargar el instrumental de "${SONG.song}".');
		}

		// Vocals
		if (SONG.needsVoices)
		{
			_usingPerCharVocals = _tryLoadPerCharVocals(SONG, diffSuffix);
			if (!_usingPerCharVocals)
				vocals = Paths.loadVoices(SONG.song, diffSuffix);
		}

		if (!_usingPerCharVocals)
		{
			if (vocals == null) vocals = new FlxSound();
			vocals.pause();
			FlxG.sound.list.add(vocals);
			funkin.audio.CoreAudio.addVocal('vocals', vocals);
		}

		// Arrancar vocals desde el inicio junto con el inst
		if (_usingPerCharVocals)
		{
			for (snd in vocalsPerChar)
			{
				if (snd == null) continue;
				snd.time = 0;
				funkin.audio.CoreAudio.play(snd);
			}
		}
		else if (SONG.needsVoices && vocals != null)
		{
			vocals.time = 0;
			funkin.audio.CoreAudio.play(vocals);
		}
	}

	function _tryLoadPerCharVocals(SONG:SwagSong, diffSuffix:String):Bool
	{
		_vocalsPlayerKeys   = [];
		_vocalsOpponentKeys = [];

		var candidates:Array<{name:String, type:String}> = [];

		if (SONG.characters != null && SONG.characters.length > 0)
		{
			for (c in SONG.characters)
			{
				final t = c.type != null ? c.type : 'Opponent';
				if (t == 'Girlfriend' || t == 'Other') continue;
				var dup = false;
				for (prev in candidates) if (prev.name == c.name) { dup = true; break; }
				if (!dup) candidates.push({name: c.name, type: t});
			}
		}

		if (candidates.length == 0)
		{
			final p1 = SONG.player1 != null ? SONG.player1 : 'bf';
			final p2 = SONG.player2 != null ? SONG.player2 : 'dad';
			candidates.push({name: p1, type: 'Player'});
			if (p2 != p1) candidates.push({name: p2, type: 'Opponent'});
		}

		var loaded = 0;
		for (cand in candidates)
		{
			final snd = Paths.loadVoicesForChar(SONG.song, cand.name, diffSuffix);
			if (snd == null) continue;
			snd.pause();
			FlxG.sound.list.add(snd);
			vocalsPerChar.set(cand.name, snd);
			funkin.audio.CoreAudio.addVocal(cand.name, snd);
			if (cand.type == 'Player' || cand.type == 'Boyfriend')
				_vocalsPlayerKeys.push(cand.name);
			else
				_vocalsOpponentKeys.push(cand.name);
			loaded++;
		}
		return loaded > 0;
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override function update(elapsed:Float):Void
	{
		// Sincronizar Conductor with the music (igual that PlayState)
		if (FlxG.sound.music != null && FlxG.sound.music.playing)
			Conductor.songPosition = FlxG.sound.music.time;

		super.update(elapsed); // dispara stepHit / beatHit via MusicBeatSubstate

		if (characterController != null)
			characterController.update(elapsed);

		if (cameraController != null)
			cameraController.update(elapsed);

		// Autoplay: fire animations of canto according to the chart
		_tickAutoplay();

		#if HSCRIPT_ALLOWED
		if (_scriptsEnabled)
		{
			EventManager.update(Conductor.songPosition);
			ScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		}
		#end
	}

	// ── Beat / Step ───────────────────────────────────────────────────────────

	override function beatHit():Void
	{
		super.beatHit();

		if (currentStage != null)
			currentStage.beatHit(curBeat);

		if (characterController != null)
			characterController.danceOnBeat(curBeat);

		// Zoom bump cada 4 beats (igual que PlayState)
		if (cameraController != null && curBeat % 4 == 0)
			cameraController.bumpZoom();

		#if HSCRIPT_ALLOWED
		if (_scriptsEnabled)
		{
			ScriptHandler._argsBeat[0] = curBeat;
			ScriptHandler.callOnScripts('onBeatHit', ScriptHandler._argsBeat);
		}
		#end
	}

	override function stepHit():Void
	{
		super.stepHit();

		if (currentStage != null)
			currentStage.stepHit(curStep);

		// Resync vocals si hay desfase > 100ms
		if (FlxG.sound.music != null && Math.abs(FlxG.sound.music.time - Conductor.songPosition) > 100)
		{
			if (_resyncCooldown <= 0)
			{
				_resyncVocals();
				_resyncCooldown = 8;
			}
		}
		if (_resyncCooldown > 0) _resyncCooldown--;

		#if HSCRIPT_ALLOWED
		if (_scriptsEnabled)
		{
			ScriptHandler._argsStep[0] = curStep;
			ScriptHandler.callOnScripts('onStepHit', ScriptHandler._argsStep);

			final section = Math.floor(curStep / 16);
			if (section != _cachedSectionIndex)
			{
				_cachedSectionIndex = section;
				ScriptHandler.callOnScripts('onSectionHit', [section]);
			}
		}
		#end
	}

	// ── Autoplay ──────────────────────────────────────────────────────────────

	/**
	 * Parsea SONG.notes una sola vez y construye una lista plana de notas
	 * ordenadas por strumTime, anotando si son del jugador u oponente,
	 * if are sustain (is omiten — no disparan animation extra), and the altAnim
	 * of the section to the that pertenecen.
	 */
	function _buildAutoplayNotes(SONG:SwagSong):Void
	{
		if (SONG.notes == null) return;

		for (section in SONG.notes)
		{
			if (section == null || section.sectionNotes == null) continue;
			final altAnim  = section.altAnim  == true;
			final gfSing   = section.gfSing   == true;
			final mustHit  = section.mustHitSection;

			for (noteArr in section.sectionNotes)
			{
				// noteArr = [strumTime, noteData, sustainLength, ...]
				if (noteArr == null) continue;
				final strumTime:Float = noteArr[0];
				var   noteData:Int    = Std.int(noteArr[1]);
				final sustainLen:Float = noteArr.length > 2 ? Std.parseFloat(Std.string(noteArr[2])) : 0;

				// noteData >= 4 → nota del oponente en formato legacy Psych
				var mustPress = mustHit;
				if (noteData >= 4)
				{
					noteData -= 4;
					mustPress = !mustHit;
				}

				// Only the note head dispara the animation, no the sustain ticks
				_autoplayNotes.push({
					strumTime : strumTime,
					noteData  : noteData % 4,
					mustPress : mustPress,
					isSustain : false,
					gfSing    : gfSing,
					altAnim   : altAnim
				});
			}
		}

		// Ordenar by strumTime for that the index incremental funcione
		_autoplayNotes.sort((a, b) -> a.strumTime < b.strumTime ? -1 : (a.strumTime > b.strumTime ? 1 : 0));
	}

	/**
	 * Llamado cada frame. Dispara las animaciones de canto de los personajes
	 * cuando Conductor.songPosition alcanza el strumTime de cada nota.
	 * Use a index incremental (_autoplayIdx) → or(1) amortizado.
	 */
	function _tickAutoplay():Void
	{
		if (characterController == null) return;

		while (_autoplayIdx < _autoplayNotes.length)
		{
			final note = _autoplayNotes[_autoplayIdx];
			if (Conductor.songPosition < note.strumTime) break;

			_autoplayIdx++;

			final altSuffix = note.altAnim ? '-alt' : '';
			final dir       = note.noteData;

			if (note.gfSing)
			{
				// Section with gfSing: the GF canta
				characterController.singGF(dir, altSuffix);
			}
			else if (note.mustPress)
			{
				// Note of the jugador → boyfriend (index Player)
				final bfIdx = characterController.findPlayerIndex();
				if (bfIdx >= 0)
				{
					characterController.singByIndex(bfIdx, dir, altSuffix);
					final bfChar = characterController.getCharacter(bfIdx);
					if (bfChar != null && cameraController != null)
						cameraController.applyNoteOffset(bfChar, dir);
				}
				else if (boyfriend != null)
				{
					characterController.sing(boyfriend, dir, altSuffix);
					if (cameraController != null)
						cameraController.applyNoteOffset(boyfriend, dir);
				}
			}
			else
			{
				// Nota del oponente → dad
				final dadIdx = characterController.findOpponentIndex();
				if (dadIdx >= 0)
				{
					characterController.singByIndex(dadIdx, dir, altSuffix);
					final dadChar = characterController.getCharacter(dadIdx);
					if (dadChar != null && cameraController != null)
						cameraController.applyNoteOffset(dadChar, dir);
				}
				else if (dad != null)
				{
					characterController.sing(dad, dir, altSuffix);
					if (cameraController != null)
						cameraController.applyNoteOffset(dad, dir);
				}
			}
		}
	}

	// ── Resync ────────────────────────────────────────────────────────────────

	function _resyncVocals():Void
	{
		if (FlxG.sound.music != null)
		{
			if (!FlxG.sound.music.playing)
				funkin.audio.CoreAudio.play(FlxG.sound.music);
			Conductor.songPosition = FlxG.sound.music.time;
		}

		if (_usingPerCharVocals)
		{
			for (snd in vocalsPerChar)
			{
				if (snd == null) continue;
				snd.time = Conductor.songPosition;
				if (!snd.playing) funkin.audio.CoreAudio.play(snd);
			}
		}
		else if (vocals != null)
		{
			vocals.time = Conductor.songPosition;
			if (!vocals.playing) funkin.audio.CoreAudio.play(vocals);
		}
	}

	// ── Fin of song ────────────────────────────────────────────────────────

	function _onSongEnd():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.pause();
		if (_usingPerCharVocals)
			for (snd in vocalsPerChar) if (snd != null) snd.pause();
		else if (vocals != null)
			vocals.pause();

		#if HSCRIPT_ALLOWED
		if (_scriptsEnabled)
			ScriptHandler.callOnScripts('onSongEnd', ScriptHandler._argsEmpty);
		#end

		if (onSongEnd != null) onSongEnd();
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	function _loadCharacters(SONG:SwagSong):Void
	{
		if (SONG.characters == null || SONG.characters.length == 0)
		{
			SONG.characters = [];
			SONG.characters.push({ name: SONG.gfVersion ?? 'gf',  x: 0, y: 0, visible: true, isGF: true,
			                       type: 'Girlfriend', strumsGroup: 'gf_strums_0' });
			SONG.characters.push({ name: SONG.player2  ?? 'dad',  x: 0, y: 0, visible: true,
			                       type: 'Opponent',   strumsGroup: 'cpu_strums_0' });
			SONG.characters.push({ name: SONG.player1  ?? 'bf',   x: 0, y: 0, visible: true,
			                       type: 'Player',     strumsGroup: 'player_strums_0' });
		}

		for (i in 0...SONG.characters.length)
		{
			final charData = SONG.characters[i];
			final slot     = new CharacterSlot(charData, i);

			if (charData.x == 0 && charData.y == 0)
			{
				switch (slot.charType)
				{
					case 'Girlfriend': slot.character.setPosition(currentStage.gfPosition.x,       currentStage.gfPosition.y);
					case 'Opponent':   slot.character.setPosition(currentStage.dadPosition.x,       currentStage.dadPosition.y);
					case 'Player':     slot.character.setPosition(currentStage.boyfriendPosition.x, currentStage.boyfriendPosition.y);
					default:
				}
			}
			else
				slot.character.setPosition(charData.x, charData.y);

			if (slot.character.characterData != null)
			{
				final off = slot.character.characterData.positionOffset;
				if (off != null && off.length >= 2) { slot.character.x += off[0]; slot.character.y += off[1]; }
			}

			slot.character.cameras = [camGame];
			characterSlots.push(slot);
			add(slot.character);

			// Referencias legacy
			if      (slot.isGFSlot       && gf          == null) gf          = slot.character;
			else if (slot.isOpponentSlot  && dad         == null) dad         = slot.character;
			else if (slot.isPlayerSlot    && boyfriend   == null) boyfriend   = slot.character;
		}

		if (currentStage.hideGirlfriend)
			for (s in characterSlots)
				if (s.isGFSlot && s.character != null) s.character.visible = false;
	}

	function _assignCameras(obj:FlxBasic, cams:Array<FlxCamera>):Void
	{
		obj.cameras = cams;
		if (Std.isOfType(obj, FlxGroup))
			for (m in (cast obj : FlxGroup).members)
				if (m != null) _assignCameras(m, cams);
	}

	// ── Destroy ───────────────────────────────────────────────────────────────

	override function destroy():Void
	{
		#if HSCRIPT_ALLOWED
		if (_scriptsEnabled)
		{
			ScriptHandler.callOnScripts('onDestroy', ScriptHandler._argsEmpty);
			EventManager.clear();
			ScriptHandler.clearSongScripts();
			ScriptHandler.clearStageScripts();
			ScriptHandler.clearCharScripts();
		}
		#end

		// Vocals
		funkin.audio.CoreAudio.clearVocals();
		if (vocals != null)
		{
			FlxG.sound.list.remove(vocals, true);
			vocals.destroy();
			vocals = null;
		}
		for (snd in vocalsPerChar)
		{
			if (snd == null) continue;
			FlxG.sound.list.remove(snd, true);
			snd.stop();
			snd.destroy();
		}
		vocalsPerChar.clear();

		// Controladores
		if (characterController != null) { characterController.destroy(); characterController = null; }
		cameraController = null;

		// Camera
		if (camGame != null) { FlxG.cameras.remove(camGame, true); camGame = null; }

		super.destroy();
	}
}
