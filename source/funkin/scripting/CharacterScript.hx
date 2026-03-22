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
 * ─── Ruta canónica (recomendada) ────────────────────────────────────────────
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
 * El engine inyecta automáticamente:
 *   `character` → instancia de Character (acceso TOTAL)
 *   `game`      → instancia de PlayState (si está en gameplay)
 *
 * ─── Ejemplo básico ─────────────────────────────────────────────────────────
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
 *   character.animOffsets            — mapa de offsets de animación
 *   character.characterData          — datos JSON del personaje
 *   character.healthIcon             — nombre del icono de salud
 *   character.healthBarColor         — color de la barra de salud
 *   character.cameraOffset           — offset de la cámara al enfocarlo
 *   character.debugMode              — modo debug (desactiva auto-animate)
 *   character.stunned                — personaje aturdido (no anima)
 *   character.holdTimer              — tiempo sosteniendo una nota
 *   character.x / character.y       — posición
 *   character.scale                  — escala (FlxPoint)
 *   character.alpha                  — transparencia (0..1)
 *   character.angle                  — ángulo de rotación
 *   character.flipX                  — voltear horizontalmente
 *   character.color                  — tinte de color (FlxColor)
 *   character.visible                — visible?
 *   character.shader                 — shader aplicado
 *   character.antialiasing           — suavizado activado?
 *   character.animation              — controlador de animaciones Flixel
 *   character.offset                 — offset manual adicional (FlxPoint)
 *   character.width / height         — dimensiones del sprite
 *
 * ─── Métodos disponibles (en character.*) ────────────────────────────────────
 *
 *   character.playAnim(name, force, reversed, frame) — reproducir animación
 *   character.dance()                                — ejecutar animación idle/dance
 *   character.returnToIdle()                         — volver al idle
 *   character.addOffset(name, x, y)                  — añadir offset a animación
 *   character.updateOffset(name, x, y)               — modificar offset existente
 *   character.getOffset(name)                        — obtener offset de animación
 *   character.hasAnimation(name)                     — ¿tiene esta animación?
 *   character.getAnimationList()                     — lista de todas las animaciones
 *   character.getCurAnimName()                       — nombre de la animación actual
 *   character.isCurAnimFinished()                    — ¿acabó la animación actual?
 *   character.isPlayingSpecialAnim()                 — ¿está en animación especial?
 *   character.reloadCharacter(newName)               — recargar como otro personaje
 *   character.makeGraphic(w, h, color)               — crear sprite de color sólido
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
 *   ANIMACIÓN:
 *     onDance()                     — al iniciar animación de baile
 *     onReturnToIdle()              — al volver al idle
 *     onAnimStart(name)             — al iniciar cualquier animación
 *     onAnimEnd(name)               — al terminar una animación
 *     onSingStart(direction, anim)  — al iniciar sing (dir: 0=LEFT,1=DOWN,2=UP,3=RIGHT)
 *     onSingEnd(direction)          — al terminar el sing y volver al idle
 *     onMissStart(direction, anim)  — al iniciar animación de miss
 *
 *   GAMEPLAY (solo si hay PlayState activo):
 *     onBeatHit(beat)               — cada beat musical
 *     onStepHit(step)               — cada step musical
 *     onNoteHit(note)               — nota golpeada (si es el personaje del jugador)
 *     onNoteMiss(note)              — nota perdida (si es el personaje del jugador)
 *     onSongStart()                 — cuando empieza la canción
 *     onSongEnd()                   — cuando termina la canción
 *     onHealthChange(prev, curr)    — salud del jugador cambió
 */
class CharacterScript
{
	// ── Metadata ──────────────────────────────────────────────────────────────
	public var name        : String    = 'CharacterScript';
	public var description : String    = '';
	public var author      : String    = '';
	public var version     : String    = '1.0.0';
	public var active      : Bool      = true;

	/** El personaje al que pertenece este script. Asignado automáticamente. */
	public var character   : Character;

	/** El PlayState activo. Puede ser null si el personaje no está en gameplay. */
	public var game        : PlayState;

	public function new() {}

	// ─── Lifecycle ────────────────────────────────────────────────────────────

	/** Llamado cuando el personaje ha sido creado y sus datos cargados. */
	public function onCreate():Void {}

	/** Llamado después de la creación del stage/PlayState (game puede ya no ser null). */
	public function postCreate():Void {}

	/** Llamado cada frame. */
	public function onUpdate(elapsed:Float):Void {}

	/** Llamado al destruir el personaje. */
	public function onDestroy():Void {}

	// ─── Animación ────────────────────────────────────────────────────────────

	/** Llamado cuando el personaje inicia una animación de baile (danceLeft/danceRight/idle). */
	public function onDance():Void {}

	/** Llamado cuando el personaje vuelve al idle. */
	public function onReturnToIdle():Void {}

	/** Llamado al iniciar cualquier animación. */
	public function onAnimStart(animName:String):Void {}

	/** Llamado al terminar cualquier animación. */
	public function onAnimEnd(animName:String):Void {}

	/**
	 * Llamado al iniciar una animación de sing.
	 * @param direction  Dirección (0=LEFT, 1=DOWN, 2=UP, 3=RIGHT)
	 * @param animName   Nombre completo de la animación (ej: "singLEFT")
	 */
	public function onSingStart(direction:Int, animName:String):Void {}

	/**
	 * Llamado cuando el personaje termina el sing y vuelve al idle.
	 * @param direction  Dirección que estaba cantando
	 */
	public function onSingEnd(direction:Int):Void {}

	/**
	 * Llamado al iniciar una animación de miss.
	 * @param direction  Dirección del miss
	 * @param animName   Nombre de la animación (ej: "singLEFTmiss")
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

	/** Llamado cuando empieza la canción. */
	public function onSongStart():Void {}

	/** Llamado cuando termina la canción. */
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
	 * Si devuelves true, el engine NO llamará a danceLeft/danceRight/idle automáticamente.
	 */
	public function overrideDance():Bool return false;

	/**
	 * Override del comportamiento de sing timeout.
	 * Retorna true para cancelar la vuelta automática al idle.
	 */
	public function overrideSingTimeout():Bool return false;

	// ─── Funciones de utilidad ────────────────────────────────────────────────

	/**
	 * Reproduce una animación en el personaje.
	 * @param name     Nombre de la animación
	 * @param force    Forzar aunque ya se esté reproduciendo
	 * @param reversed Reproducir al revés
	 * @param frame    Frame inicial
	 */
	public function playAnim(name:String, force:Bool = false, reversed:Bool = false, frame:Int = 0):Void
	{
		if (character != null) character.playAnim(name, force, reversed, frame);
	}

	/** Hace el personaje bailar (llamar al dance()). */
	public function dance():Void
		if (character != null) character.dance();

	/** Mueve el personaje a la posición indicada. */
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

	/** Añade un offset a una animación. */
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
	 * Lee una variable del personaje por reflexión.
	 * Útil para acceder a campos no expuestos directamente.
	 */
	public inline function getVar(varName:String):Dynamic
		return character != null ? Reflect.getProperty(character, varName) : null;

	/** Modifica una variable del personaje por reflexión. */
	public inline function setVar(varName:String, value:Dynamic):Void
		if (character != null) Reflect.setProperty(character, varName, value);

	/** Llama un método del personaje por reflexión. */
	public inline function callMethod(methodName:String, ?args:Array<Dynamic>):Dynamic
		return character != null
			? Reflect.callMethod(character, Reflect.field(character, methodName), args ?? [])
			: null;

	/** Lee una variable del PlayState por reflexión. */
	public inline function getGameVar(varName:String):Dynamic
		return game != null ? Reflect.getProperty(game, varName) : null;

	/** Modifica una variable del PlayState por reflexión. */
	public inline function setGameVar(varName:String, value:Dynamic):Void
		if (game != null) Reflect.setProperty(game, varName, value);

	/** Log con prefijo del nombre del script y el personaje. */
	public inline function log(msg:Dynamic):Void{
		trace('[CharacterScript($name)]:'  + character?.curCharacter + msg);
	}
}