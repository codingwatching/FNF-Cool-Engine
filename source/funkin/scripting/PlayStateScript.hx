package funkin.scripting;

import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.gameplay.PlayState;
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.objects.stages.Stage;
import funkin.gameplay.notes.Note;
import funkin.data.Conductor;

/**
 * PlayStateScript — Script de gameplay con acceso COMPLETO a PlayState.
 *
 * Para usar:
 *   Coloca un archivo .hx en:
 *     assets/songs/{nombre_cancion}/scripts/
 *     assets/stages/{nombre_stage}/scripts/
 *     mods/{mod}/songs/{cancion}/scripts/
 *
 * The engine inyecta automatically:
 *   `game`  → instance of PlayState  (acceso to all the fields public)
 *   `bf`    → boyfriend  (Character)
 *   `dad`   → dad        (Character)
 *   `gf`    → gf         (Character)
 *   `stage` → currentStage (Stage)
 *   `conductor` → Conductor (BPM, beat, step, etc.)
 *
 * ─── Basic example ─────────────────────────────────────────────────────────
 *
 *   function onCreate() {
 *     game.camGame.zoom = 0.9;
 *     bf.playAnim("hey", true);
 *     trace("Song started! BPM: " + Conductor.bpm);
 *   }
 *
 *   function onBeatHit(beat) {
 *     if (beat % 4 == 0) {
 *       game.camGame.zoom += 0.05;
 *       FlxTween.tween(game.camGame, { zoom: game.defaultCamZoom }, 0.4, { ease: FlxEase.expoOut });
 *     }
 *   }
 *
 *   function onNoteHit(note) {
 *     if (note.mustPress && note.rating == "sick") {
 *       bf.playAnim("hey", true);
 *     }
 *   }
 *
 * ─── Variables disponibles (inyectadas por el engine) ────────────────────────
 *
 *   game.boyfriend / game.dad / game.gf         — personajes principales
 *   game.currentStage                            — stage actual
 *   game.camGame / game.camHUD / game.camCountdown — cameras
 *   game.health                                  — salud del jugador (0..2)
 *   game.vocals / game.vocalsBf / game.vocalsDad — sonidos
 *   game.notes / game.sustainNotes               — grupos de notas
 *   game.paused / game.canPause                  — estado de pausa
 *   game.inCutscene                              — en cutscene?
 *   game.isBotPlay (static)                      — bot mode?
 *   game.scriptsEnabled                          — scripts activos?
 *   game.uiManager                               — manager del HUD
 *   game.noteManager                             — manager de notas
 *   game.characterController                     — controller de personajes
 *   game.cameraController                        — controller of camera
 *   game.gameState                               — estado interno del juego
 *   game.modChartManager                         — sistema modchart
 *   game.countdown                               — countdown del inicio
 *   game.strumsGroups                            — grupos de strums
 *   PlayState.SONG                               — datos del chart actual
 *   PlayState.isStoryMode                        — story mode?
 *   PlayState.misses / sicks / goods...          — estadísticas actuales
 *   Conductor.bpm / crochet / stepCrochet / beat / step — timing
 *
 * ─── Callbacks disponibles ──────────────────────────────────────────────────
 *
 *   LIFECYCLE:
 *     onCreate()                    — al crear el PlayState
 *     postCreate()                  — after of create (characters/stage listos)
 *     onUpdate(elapsed)             — cada frame
 *     onUpdatePost(elapsed)         — after of the update
 *     onDestroy()                   — al destruir
 *
 *   GAMEPLAY:
 *     onBeatHit(beat)               — cada beat musical
 *     onStepHit(step)               — cada step musical
 *     onNoteHit(note)               — nota golpeada por el jugador
 *     onNoteHitPost(note)           — after of the processing of note
 *     onNoteMiss(note)              — nota perdida
 *     onCpuNoteHit(note)            — nota del CPU
 *     onPlayerNoteHit(note, rating) — nota del jugador con rating
 *     onSustainHit(note)            — hold note en progreso
 *
 *   EVENTOS DEL CHART:
 *     onEvent(name, v1, v2, time)   — return true para cancelar el evento
 *     onFocusChange(focus)          — "bf", "dad", "gf"
 *
 *   ESTADO:
 *     onSongStart()                 — when empieza the music
 *     onSongEnd()                   — when termina the song
 *     onPause()                     — al pausar
 *     onResume()                    — al reanudar
 *     onGameOver()                  — al morir
 *     onCountdownStart()            — inicio del countdown
 *     onCountdownTick(tick)         — cada tick del countdown (0..4)
 *     onCountdownEnd()              — fin del countdown
 *     onCutsceneStart()             — inicio de cutscene
 *     onCutsceneEnd()               — fin de cutscene
 *
 *   PERSONAJES:
 *     onCharacterDance(char, name)  — un personaje baila
 *     onCharacterPlayAnim(char, anim) — un personaje anima
 *     onCharacterChange(slot, oldName, newName) — cambio de personaje
 *
 *   SALUD:
 *     onHealthChange(prev, curr)    — salud changed
 *     onHealthDanger(health)        — salud baja (<= 0.3)
 *
 *   camera:
 *     onCameraMove(x, and)            — the camera is moves
 *     onCameraZoom(zoom)            — the camera hace zoom
 *
 * ─── Funciones de ayuda disponibles ─────────────────────────────────────────
 *
 *   // Add a sprite to the game
 *   var spr = addSprite(new FlxSprite(100, 100));
 *   spr.makeGraphic(200, 200, FlxColor.RED);
 *
 *   // Add a text
 *   var txt = addText(100, 100, "Hola!", 32);
 *   txt.color = FlxColor.WHITE;
 *
 *   // Hacer un tween
 *   tween(game.camGame, { zoom: 1.2 }, 0.5, { ease: FlxEase.elasticOut });
 *
 *   // Timer
 *   timer(2.0, function() { trace("2 segundos!"); });
 *
 *   // Reproducir un sonido
 *   playSound("path/al/sonido");
 *
 *   // Acceder a personajes por nombre
 *   var char = getCharacter("bf");   // "bf", "dad", "gf"
 *
 *   // Log
 *   log("Mi mensaje");
 *
 * ─── Hooks de gameplay ───────────────────────────────────────────────────────
 *
 *   // Add a hook personalizado (useful if tienes multiple scripts)
 *   addUpdateHook("miHook", function(elapsed) {
 *     // ejecutado cada frame
 *   });
 *
 *   addBeatHook("miHook", function(beat) {
 *     // ejecutado cada beat
 *   });
 *
 *   addNoteHitHook("miHook", function(note) {
 *     // ejecutado al golpear una nota
 *   });
 */
class PlayStateScript
{
	// ── Metadata ──────────────────────────────────────────────────────────────
	public var name        : String = 'PlayStateScript';
	public var description : String = '';
	public var author      : String = '';
	public var version     : String = '1.0.0';
	public var active      : Bool   = true;

	/** Instancia of the PlayState. Asignada automatically by the engine. */
	public var game        : PlayState;

	// ── Shortcuts (asignados automatically) ─────────────────────────────────

	/** Alias de game.boyfriend */
	public var bf          : Character;
	/** Alias de game.dad */
	public var dad         : Character;
	/** Alias de game.gf */
	public var gf          : Character;
	/** Alias de game.currentStage */
	public var stage       : Stage;
	/** Alias de game.camGame */
	public var camGame     : FlxCamera;
	/** Alias de game.camHUD */
	public var camHUD      : FlxCamera;
	/** Alias de game.vocals */
	public var vocals      : FlxSound;

	public function new() {}

	// ─── Lifecycle ────────────────────────────────────────────────────────────

	/** Llamado cuando el PlayState termina de crear sus sistemas (personajes, stage, notas). */
	public function onCreate():Void {}

	/** Calldo justo after of onCreate, when all is listo. */
	public function postCreate():Void {}

	/** Calldo each frame. elapsed = segundos from the last frame. */
	public function onUpdate(elapsed:Float):Void {}

	/** Calldo after of the update of the engine. */
	public function onUpdatePost(elapsed:Float):Void {}

	/** Llamado al destruir el PlayState (cambio de estado). */
	public function onDestroy():Void {}

	// ─── Gameplay ─────────────────────────────────────────────────────────────

	/** Calldo in each beat musical (compás). beat = number of beat from the start. */
	public function onBeatHit(beat:Int):Void {}

	/** Calldo in each step musical (subdivisión of the beat). */
	public function onStepHit(step:Int):Void {}

	/** Llamado cuando el jugador golpea una nota. */
	public function onNoteHit(note:Note):Void {}

	/** Calldo after of process a golpe of note. */
	public function onNoteHitPost(note:Note):Void {}

	/** Llamado cuando el jugador pierde una nota. */
	public function onNoteMiss(note:Note):Void {}

	/** Llamado cuando el CPU golpea una nota. */
	public function onCpuNoteHit(note:Note):Void {}

	/**
	 * Llamado cuando el jugador golpea una nota, con el rating resultante.
	 * @param note   La nota golpeada
	 * @param rating "sick", "good", "bad", "shit"
	 */
	public function onPlayerNoteHit(note:Note, rating:String):Void {}

	/** Llamado mientras el jugador sostiene un hold note. */
	public function onSustainHit(note:Note):Void {}

	// ─── Eventos del chart ────────────────────────────────────────────────────

	/**
	 * Llamado cuando se dispara un evento del chart.
	 * @param name  Nombre del evento
	 * @param v1    Primer valor
	 * @param v2    Segundo valor
	 * @param time  Time in ms in the that is posicionado the event
	 * @return true para cancelar el comportamiento por defecto del evento
	 */
	public function onEvent(name:String, v1:String, v2:String, time:Float):Bool return false;

	/**
	 * Calldo when the camera changes of foco.
	 * @param focus "bf", "dad", "gf"
	 */
	public function onFocusChange(focus:String):Void {}

	// ─── Estado del juego ─────────────────────────────────────────────────────

	/** Calldo when empieza to sonar the music. */
	public function onSongStart():Void {}

	/** Calldo when the song termina (before of change of state). */
	public function onSongEnd():Void {}

	/** Llamado al pausar el juego. */
	public function onPause():Void {}

	/** Llamado al reanudar el juego desde la pausa. */
	public function onResume():Void {}

	/** Llamado cuando la salud llega a 0 (game over). */
	public function onGameOver():Void {}

	/** Llamado al iniciar el countdown (3, 2, 1, go!). */
	public function onCountdownStart():Void {}

	/**
	 * Llamado en cada tick del countdown.
	 * @param tick 0 = "three", 1 = "two", 2 = "one", 3 = "go", 4 = silence
	 */
	public function onCountdownTick(tick:Int):Void {}

	/** Calldo when the countdown termina and empieza the song. */
	public function onCountdownEnd():Void {}

	/** Llamado al inicio de una cutscene. */
	public function onCutsceneStart():Void {}

	/** Llamado al final de una cutscene. */
	public function onCutsceneEnd():Void {}

	// ─── Personajes ───────────────────────────────────────────────────────────

	/**
	 * Llamado cuando un personaje baila.
	 * @param char  El personaje ("bf", "dad", "gf" u otro nombre)
	 * @param anim  The animation that is reprodujo
	 */
	public function onCharacterDance(char:String, anim:String):Void {}

	/**
	 * Calldo when a character reproduce a animation.
	 * @param char  El personaje
	 * @param anim  The animation
	 */
	public function onCharacterPlayAnim(char:String, anim:String):Void {}

	/**
	 * Llamado cuando se cambia un personaje (evento ChangeCharacter).
	 * @param slot     "bf", "dad", "gf"
	 * @param oldName  Nombre del personaje anterior
	 * @param newName  Nombre del personaje nuevo
	 */
	public function onCharacterChange(slot:String, oldName:String, newName:String):Void {}

	// ─── Salud ────────────────────────────────────────────────────────────────

	/**
	 * Llamado cuando la salud cambia.
	 * @param prev   Salud anterior (0..2)
	 * @param curr   Salud nueva (0..2)
	 */
	public function onHealthChange(prev:Float, curr:Float):Void {}

	/**
	 * Calldo when the salud is in zona of peligro (<= 0.3).
	 * @param health  Salud actual
	 */
	public function onHealthDanger(health:Float):Void {}

	// ─── Camera ───────────────────────────────────────────────────────────────

	/** Calldo when the camera is moves to a new punto. */
	public function onCameraMove(x:Float, y:Float):Void {}

	/** Calldo when the camera hace zoom. */
	public function onCameraZoom(zoom:Float):Void {}

	// ─── Funciones de utilidad ────────────────────────────────────────────────

	/**
	 * Adds a FlxSprite to the game (to the camGame).
	 * @return El mismo sprite, para encadenar operaciones.
	 */
	public function addSprite(sprite:FlxSprite):FlxSprite
	{
		if (game != null) game.add(sprite);
		return sprite;
	}

	/**
	 * Adds a sprite to the HUD (camHUD).
	 */
	public function addToHUD(sprite:FlxSprite):FlxSprite
	{
		if (game != null)
		{
			sprite.cameras = [game.camHUD];
			game.add(sprite);
		}
		return sprite;
	}

	/** Elimina un sprite del juego. */
	public function removeSprite(sprite:FlxSprite):Void
		if (game != null) game.remove(sprite, true);

	/** Creates and adds a FlxText to the game. */
	public function addText(x:Float, y:Float, text:String, size:Int = 16):FlxText
	{
		var t = new FlxText(x, y, 0, text, size);
		addSprite(t);
		return t;
	}

	/**
	 * Accede a un personaje por nombre de slot.
	 * @param slot  "bf" / "boyfriend", "dad" / "opponent", "gf" / "girlfriend"
	 */
	public function getCharacter(slot:String):Character
	{
		if (game == null) return null;
		return switch (slot.toLowerCase())
		{
			case 'bf', 'boyfriend', 'player': game.boyfriend;
			case 'dad', 'opponent': game.dad;
			case 'gf', 'girlfriend': game.gf;
			default: null;
		};
	}

	/** Hace un tween de Flixel. Wrapper conveniente. */
	public function tween(object:Dynamic, values:Dynamic, duration:Float, ?options:Dynamic):Dynamic
		return FlxTween.tween(object, values, duration, options);

	/** Crea un timer de Flixel. Wrapper conveniente. */
	public function timer(seconds:Float, callback:Void->Void):FlxTimer
		return new FlxTimer().start(seconds, function(_) callback());

	/** Reproduce un sonido. */
	public function playSound(path:String, volume:Float = 1.0):FlxSound
		return flixel.FlxG.sound.play(Paths.sound(path), volume);

	/** Reproduce music. */
	public function playMusic(path:String, volume:Float = 1.0):Void
		flixel.FlxG.sound.playMusic(Paths.music(path), volume);

	/** Flash of the camera of the game. */
	public function cameraFlash(color:FlxColor = FlxColor.WHITE, duration:Float = 0.5):Void
	{
		if (game?.camGame != null)
			game.camGame.flash(color, duration);
	}

	/** Shake of the camera of the game. */
	public function cameraShake(intensity:Float = 0.05, duration:Float = 0.3):Void
	{
		if (game?.camGame != null)
			game.camGame.shake(intensity, duration);
	}

	/** Registra un hook de update personalizado. */
	public function addUpdateHook(id:String, fn:Float->Void):Void
	{
		if (game != null)
		{
			game.onUpdateHooks.set(id, fn);
			game.rebuildHookArrays();
		}
	}

	/** Registra un hook de beat hit. */
	public function addBeatHook(id:String, fn:Int->Void):Void
	{
		if (game != null)
		{
			game.onBeatHitHooks.set(id, fn);
			game.rebuildHookArrays();
		}
	}

	/** Registra un hook de step hit. */
	public function addStepHook(id:String, fn:Int->Void):Void
	{
		if (game != null)
		{
			game.onStepHitHooks.set(id, fn);
			game.rebuildHookArrays();
		}
	}

	/** Registra un hook de note hit. */
	public function addNoteHitHook(id:String, fn:Note->Void):Void
	{
		if (game != null)
		{
			game.onNoteHitHooks.set(id, fn);
			game.rebuildHookArrays();
		}
	}

	/** Registra un hook de note miss. */
	public function addNoteMissHook(id:String, fn:Note->Void):Void
	{
		if (game != null)
		{
			game.onNoteMissHooks.set(id, fn);
			game.rebuildHookArrays();
		}
	}

	/** Elimina un hook por id. */
	public function removeHook(id:String):Void
	{
		if (game != null)
		{
			game.onUpdateHooks.remove(id);
			game.onBeatHitHooks.remove(id);
			game.onStepHitHooks.remove(id);
			game.onNoteHitHooks.remove(id);
			game.onNoteMissHooks.remove(id);
			game.rebuildHookArrays();
		}
	}

	/**
	 * Gets a variable of the PlayState by reflection.
	 * Useful for acceder to fields privados or new without modificar this class.
	 */
	public inline function getVar(varName:String):Dynamic
		return game != null ? Reflect.getProperty(game, varName) : null;

	/** Modifica a variable of the PlayState by reflection. */
	public inline function setVar(varName:String, value:Dynamic):Void
		if (game != null) Reflect.setProperty(game, varName, value);

	/** Call a method of the PlayState by reflection. */
	public inline function callMethod(methodName:String, ?args:Array<Dynamic>):Dynamic
		return game != null ? Reflect.callMethod(game, Reflect.field(game, methodName), args ?? []) : null;

	/** Log con prefijo del nombre del script. */
	public inline function log(msg:Dynamic):Void
		trace('[PlayStateScript: $name] $msg');
}
