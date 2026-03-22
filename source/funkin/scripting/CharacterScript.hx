package funkin.scripting;

import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.PlayState;
import funkin.data.Conductor;

/**
 * CharacterScript — Script para personalizar un personaje con acceso COMPLETO
 * a todas las variables y funciones de Character.
 *
 * ─── Canonical path (recommended) ────────────────────────────────────────────
 *
 *   assets/characters/scripts/{nombrePersonaje}/scripts.hx
 *   mods/{mod}/characters/scripts/{nombrePersonaje}/scripts.hx
 *
 *   Ejemplo para "bf":
 *     assets/characters/scripts/bf/scripts.hx
 *
 * ─── Rutas heredadas (siguen funcionando) ────────────────────────────────────
 *
 *   assets/characters/{nombrePersonaje}/scripts/
 *   mods/{mod}/characters/{nombrePersonaje}/scripts/
 *   mods/{mod}/characters/{nombrePersonaje}/{script}.hx
 *
 * The engine inyecta automatically:
 *   `character` → instancia de Character (acceso TOTAL)
 *   `game`      → instance of PlayState (if is in gameplay)
 *
 * ─── Basic example ─────────────────────────────────────────────────────────
 *
 *   function onCreate() {
 *     character.scale.set(1.1, 1.1);
 *     character.updateHitbox();
 *     log("Personaje listo: " + character.curCharacter);
 *   }
 *
 *   function onDance() {
 *     // Hacer algo especial al bailar
 *     if (game != null && game.health > 1.5) {
 *       character.playAnim("hey", true);
 *     }
 *   }
 *
 *   function onBeatHit(beat) {
 *     if (beat % 8 == 0) {
 *       character.color = FlxColor.fromRGB(255, 200, 200);
 *       timer(0.3, function() { character.color = FlxColor.WHITE; });
 *     }
 *   }
 *
 *   function onSingStart(direction, anim) {
 *     // Personalizar el inicio de un sing
 *     log("Cantando: " + anim);
 *   }
 *
 * ─── Variables disponibles (en character.*) ──────────────────────────────────
 *
 *   character.curCharacter          — nombre del personaje ("bf", "dad"...)
 *   character.isPlayer              — es el personaje del jugador?
 *   character.animOffsets            — mapa of offsets of animation
 *   character.characterData          — datos JSON del personaje
 *   character.healthIcon             — nombre del icono de salud
 *   character.healthBarColor         — color de la barra de salud
 *   character.cameraOffset           — offset of the camera to the enfocarlo
 *   character.debugMode              — modo debug (desactiva auto-animate)
 *   character.stunned                — personaje aturdido (no anima)
 *   character.holdTimer              — tiempo sosteniendo una nota
 *   character.x / character.and       — position
 *   character.scale                  — escala (FlxPoint)
 *   character.alpha                  — transparencia (0..1)
 *   character.angle                  — angle of rotation
 *   character.flipX                  — voltear horizontalmente
 *   character.color                  — tinte de color (FlxColor)
 *   character.visible                — visible?
 *   character.shader                 — shader aplicado
 *   character.antialiasing           — suavizado activado?
 *   character.animation              — controlador de animaciones Flixel
 *   character.offset                 — offset manual adicional (FlxPoint)
 *   character.width / height         — dimensiones del sprite
 *
 * ─── Methods disponibles (in character.*) ────────────────────────────────────
 *
 *   character.playAnim(name, force, reversed, frame) — play animation
 *   character.dance()                                — ejecutar animation idle/dance
 *   character.returnToIdle()                         — volver al idle
 *   character.addOffset(name, x, and)                  — add offset to animation
 *   character.updateOffset(name, x, y)               — modificar offset existente
 *   character.getOffset(name)                        — get offset of animation
 *   character.hasAnimation(name)                     — tiene this animation?
 *   character.getAnimationList()                     — lista de todas las animaciones
 *   character.getCurAnimName()                       — nombre of the animation current
 *   character.isCurAnimFinished()                    — acabó the animation current?
 *   character.isPlayingSpecialAnim()                 — is in animation especial?
 *   character.reloadCharacter(newName)               — recargar como otro personaje
 *   character.makeGraphic(w, h, color)               — create sprite of color solid
 *   character.loadGraphic(path)                      — cargar una imagen
 *   character.updateHitbox()                         — actualizar hitbox tras escalar
 *   character.setPosition(x, y)                      — mover personaje
 *   character.screenCenter()                         — centrar en pantalla
 *
 * ─── Callbacks disponibles ───────────────────────────────────────────────────
 *
 *   LIFECYCLE:
 *     onCreate()                    — personaje creado y cargado
 *     postCreate()                  — stage y juego listos (game puede ser null si no hay PlayState)
 *     onUpdate(elapsed)             — cada frame
 *     onDestroy()                   — al destruir
 *
 *   animation:
 *     onDance()                     — to the start animation of baile
 *     onReturnToIdle()              — al volver al idle
 *     onAnimStart(name)             — to the start cualquier animation
 *     onAnimEnd(name)               — to the terminar a animation
 *     onSingStart(direction, anim)  — al iniciar sing (dir: 0=LEFT,1=DOWN,2=UP,3=RIGHT)
 *     onSingEnd(direction)          — al terminar el sing y volver al idle
 *     onMissStart(direction, anim)  — to the start animation of miss
 *
 *   GAMEPLAY (solo si hay PlayState activo):
 *     onBeatHit(beat)               — cada beat musical
 *     onStepHit(step)               — cada step musical
 *     onNoteHit(note)               — nota golpeada (si es el personaje del jugador)
 *     onNoteMiss(note)              — nota perdida (si es el personaje del jugador)
 *     onSongStart()                 — when empieza the song
 *     onSongEnd()                   — when termina the song
 *     onHealthChange(prev, curr)    — salud of the player changed
 */
class CharacterScript
{
	// ── Metadata ──────────────────────────────────────────────────────────────
	public var name        : String    = 'CharacterScript';
	public var description : String    = '';
	public var author      : String    = '';
	public var version     : String    = '1.0.0';
	public var active      : Bool      = true;

	/** The character to the that pertenece this script. Asignado automatically. */
	public var character   : Character;

	/** The PlayState active. Puede be null if the character no is in gameplay. */
	public var game        : PlayState;

	public function new() {}

	// ─── Lifecycle ────────────────────────────────────────────────────────────

	/** Llamado cuando el personaje ha sido creado y sus datos cargados. */
	public function onCreate():Void {}

	/** Calldo after of the creation of the stage/PlayState (game puede already no be null). */
	public function postCreate():Void {}

	/** Llamado cada frame. */
	public function onUpdate(elapsed:Float):Void {}

	/** Llamado al destruir el personaje. */
	public function onDestroy():Void {}

	// ─── Animation ────────────────────────────────────────────────────────────

	/** Calldo when the character starts a animation of baile (danceLeft/danceRight/idle). */
	public function onDance():Void {}

	/** Llamado cuando el personaje vuelve al idle. */
	public function onReturnToIdle():Void {}

	/** Calldo to the start cualquier animation. */
	public function onAnimStart(animName:String):Void {}

	/** Calldo to the terminar cualquier animation. */
	public function onAnimEnd(animName:String):Void {}

	/**
	 * Calldo to the start a animation of sing.
	 * @param direction  Direction (0=LEFT, 1=DOWN, 2=UP, 3=RIGHT)
	 * @param animName   Nombre complete of the animation (ej: "singLEFT")
	 */
	public function onSingStart(direction:Int, animName:String):Void {}

	/**
	 * Llamado cuando el personaje termina el sing y vuelve al idle.
	 * @param direction  Direction that was cantando
	 */
	public function onSingEnd(direction:Int):Void {}

	/**
	 * Calldo to the start a animation of miss.
	 * @param direction  Direction of the miss
	 * @param animName   Nombre of the animation (ej: "singLEFTmiss")
	 */
	public function onMissStart(direction:Int, animName:String):Void {}

	// ─── Gameplay ─────────────────────────────────────────────────────────────

	/** Llamado en cada beat musical. */
	public function onBeatHit(beat:Int):Void {}

	/** Llamado en cada step musical. */
	public function onStepHit(step:Int):Void {}

	/** Llamado cuando este personaje (jugador) golpea una nota. */
	public function onNoteHit(note:Dynamic):Void {}

	/** Llamado cuando este personaje (jugador) pierde una nota. */
	public function onNoteMiss(note:Dynamic):Void {}

	/** Calldo when empieza the song. */
	public function onSongStart():Void {}

	/** Calldo when termina the song. */
	public function onSongEnd():Void {}

	/**
	 * Llamado cuando la salud cambia.
	 * @param prev  Salud anterior (0..2)
	 * @param curr  Salud nueva (0..2)
	 */
	public function onHealthChange(prev:Float, curr:Float):Void {}

	// ─── Overrides de comportamiento ─────────────────────────────────────────

	/**
	 * Override del comportamiento de baile. Retorna true para cancelar el baile por defecto.
	 * If returnss true, the engine no callrá to danceLeft/danceRight/idle automatically.
	 */
	public function overrideDance():Bool return false;

	/**
	 * Override del comportamiento de sing timeout.
	 * Returns true for cancelar the vuelta automatic to the idle.
	 */
	public function overrideSingTimeout():Bool return false;

	// ─── Funciones de utilidad ────────────────────────────────────────────────

	/**
	 * Plays an animation en el personaje.
	 * @param name     Nombre of the animation
	 * @param force    Force although already is is reproduciendo
	 * @param reversed Play to the revés
	 * @param frame    Frame inicial
	 */
	public function playAnim(name:String, force:Bool = false, reversed:Bool = false, frame:Int = 0):Void
	{
		if (character != null) character.playAnim(name, force, reversed, frame);
	}

	/** Hace el personaje bailar (llamar al dance()). */
	public function dance():Void
		if (character != null) character.dance();

	/** Moves the character to the position indicada. */
	public function setPosition(x:Float, y:Float):Void
		if (character != null) character.setPosition(x, y);

	/** Escala el personaje. */
	public function setScale(x:Float, y:Float):Void
	{
		if (character != null)
		{
			character.scale.set(x, y);
			character.updateHitbox();
		}
	}

	/** Adds a offset to a animation. */
	public function addOffset(anim:String, x:Float, y:Float):Void
		if (character != null) character.addOffset(anim, x, y);

	/** Aplica un tween al personaje. */
	public function tween(values:Dynamic, duration:Float, ?options:Dynamic):Dynamic
		return character != null ? FlxTween.tween(character, values, duration, options) : null;

	/** Crea un timer. */
	public function timer(seconds:Float, callback:Void->Void):FlxTimer
		return new FlxTimer().start(seconds, function(_) callback());

	/** Cambia el color del personaje. */
	public function setColor(color:Int):Void
		if (character != null) character.color = color;

	/** Aplica un shader al personaje. */
	public function applyShader(shaderName:String):Void
	{
		if (character == null) return;
		try { shaders.ShaderManager.applyShader(character, shaderName); }
		catch (e:Dynamic) trace('[CharacterScript] Shader error: $e');
	}

	/** Quita el shader del personaje. */
	public function removeShader():Void
		if (character != null) character.shader = null;

	/**
	 * Lee a variable of the character by reflection.
	 * Useful for acceder to fields no expuestos directly.
	 */
	public inline function getVar(varName:String):Dynamic
		return character != null ? Reflect.getProperty(character, varName) : null;

	/** Modifica a variable of the character by reflection. */
	public inline function setVar(varName:String, value:Dynamic):Void
		if (character != null) Reflect.setProperty(character, varName, value);

	/** Call a method of the character by reflection. */
	public inline function callMethod(methodName:String, ?args:Array<Dynamic>):Dynamic
		return character != null
			? Reflect.callMethod(character, Reflect.field(character, methodName), args ?? [])
			: null;

	/** Lee a variable of the PlayState by reflection. */
	public inline function getGameVar(varName:String):Dynamic
		return game != null ? Reflect.getProperty(game, varName) : null;

	/** Modifica a variable of the PlayState by reflection. */
	public inline function setGameVar(varName:String, value:Dynamic):Void
		if (game != null) Reflect.setProperty(game, varName, value);

	/** Log con prefijo del nombre del script y el personaje. */
	public inline function log(msg:Dynamic):Void{
		trace('[CharacterScript($name)]:'  + character?.curCharacter + msg);
	}
}