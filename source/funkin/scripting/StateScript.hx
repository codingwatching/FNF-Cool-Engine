package funkin.scripting;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;

/**
 * StateScript — Script base para cualquier FlxState o SubState del juego.
 *
 * Extiende esta clase en tus scripts HScript para personalizar cualquier
 * estado (FreeplayState, MainMenuState, TitleState, OptionsMenuState...).
 *
 * Para usar:
 *   Coloca un archivo .hx en:
 *     assets/states/{NombreDelEstado}/
 *     mods/{mod}/states/{NombreDelEstado}/
 *
 * El engine inyecta automáticamente:
 *   `state`  → instancia del FlxState  (acceso a TODOS los campos públicos)
 *
 * ─── Ejemplo básico ─────────────────────────────────────────────────────────
 *
 *   class MiScript extends StateScript {
 *     override function onCreate() {
 *       var txt = createText(10, 10, "Hola desde el script!");
 *       txt.color = FlxColor.CYAN;
 *       addSprite(txt);
 *     }
 *
 *     override function onBeatHit(beat) {
 *       if (beat % 4 == 0) {
 *         FlxG.camera.flash(FlxColor.WHITE, 0.1);
 *       }
 *     }
 *
 *     override function onBack():Bool {
 *       trace("El jugador intentó salir");
 *       return false; // no cancelar la acción
 *     }
 *   }
 *
 * ─── Variables del estado disponibles ────────────────────────────────────────
 *
 *   getVar("nombreVariable")    — leer cualquier campo del estado
 *   setVar("nombreVariable", v) — modificar cualquier campo del estado
 *   callMethod("metodo", args)  — llamar cualquier método del estado
 *
 *   // Ejemplo: acceder a estado de FreeplayState
 *   var currentSong = getVar("selectedSong");
 *   setVar("canSelect", false);
 *
 * ─── Callbacks disponibles ────────────────────────────────────────────────────
 *
 *   LIFECYCLE:
 *     onCreate()                   — al crear el estado
 *     postCreate()                 — después de crear
 *     onUpdate(elapsed)            — cada frame
 *     onUpdatePost(elapsed)        — después del update
 *     onDestroy()                  — al destruir
 *     onFocusLost()                — al perder foco de la ventana
 *     onFocus()                    — al recuperar foco
 *
 *   INPUT:
 *     onBack()  → Bool             — acción "atrás/escape" (true=cancelar)
 *     onAccept() → Bool            — acción "aceptar/enter" (true=cancelar)
 *     onKeyPressed(key)            — tecla presionada (string con nombre)
 *     onKeyJustPressed(key)        — tecla recién presionada
 *     onKeyReleased(key)           — tecla soltada
 *
 *   BEAT/STEP (si el estado hereda de MusicBeatState):
 *     onBeatHit(beat)              — cada beat musical
 *     onStepHit(step)              — cada step musical
 *
 *   MENÚ PRINCIPAL:
 *     getCustomMenuItems() → Array<String>   — ítems extra en el menú
 *     onMenuItemSelected(item, index)        — ítem seleccionado
 *
 *   OPCIONES:
 *     getCustomOptions() → Array<Dynamic>    — opciones extra
 *     getCustomCategories() → Array<String>  — categorías extra
 *     onOptionSelected(name)                 — opción seleccionada
 *     onOptionChanged(name, value)           — valor de opción cambió
 *     onSelectionChanged(index)              — selección movida
 *
 *   FREEPLAY:
 *     onSongSelected(song)                   — canción seleccionada
 *     onDifficultyChanged(diff)              — dificultad cambiada
 *     getCustomSongs() → Array<Dynamic>      — canciones extra
 *
 *   STORY:
 *     onWeekSelected(weekIndex)              — semana seleccionada
 *     getCustomWeeks() → Array<Dynamic>      — semanas extra
 *
 *   TITLE:
 *     onIntroComplete()                      — intro terminada
 *     onIntroBeat(beat)                      — beat de la intro
 *     getIntroText() → Array<String>         — texto de intro personalizado
 *
 *   TRANSICIONES:
 *     onTransitionIn()                       — al entrar al estado
 *     onTransitionOut()                      — al salir del estado
 */
class StateScript
{
	// ── Metadata ──────────────────────────────────────────────────────────────
	public var name        : String   = 'StateScript';
	public var description : String   = '';
	public var author      : String   = '';
	public var version     : String   = '1.0.0';
	public var active      : Bool     = true;

	/** El FlxState al que pertenece este script. Asignado automáticamente. */
	public var state       : FlxState;

	public function new() {}

	// ─── Lifecycle ────────────────────────────────────────────────────────────

	public function onCreate():Void {}
	public function postCreate():Void {}
	public function onUpdate(elapsed:Float):Void {}
	public function onUpdatePost(elapsed:Float):Void {}
	public function onDestroy():Void {}
	public function onFocusLost():Void {}
	public function onFocus():Void {}

	// ─── Input ────────────────────────────────────────────────────────────────

	/** @return true para cancelar el comportamiento por defecto. */
	public function onBack():Bool   return false;

	/** @return true para cancelar el comportamiento por defecto. */
	public function onAccept():Bool return false;

	/** Llamado cuando una tecla es presionada (mantenida). */
	public function onKeyPressed(key:String):Void {}

	/** Llamado cuando una tecla es recién presionada (solo el primer frame). */
	public function onKeyJustPressed(key:String):Void {}

	/** Llamado cuando una tecla es soltada. */
	public function onKeyReleased(key:String):Void {}

	// ─── Beat/Step ────────────────────────────────────────────────────────────

	/** Llamado en cada beat musical (si el estado es MusicBeatState). */
	public function onBeatHit(beat:Int):Void {}

	/** Llamado en cada step musical (si el estado es MusicBeatState). */
	public function onStepHit(step:Int):Void {}

	// ─── Menú ─────────────────────────────────────────────────────────────────

	/** Añade items extra al menú principal. */
	public function getCustomMenuItems():Array<String>     return [];
	public function onMenuItemSelected(item:String, index:Int):Void {}

	// ─── Opciones ─────────────────────────────────────────────────────────────

	public function getCustomOptions():Array<Dynamic>      return [];
	public function getCustomCategories():Array<String>    return [];
	public function onOptionSelected(name:String):Void {}
	public function onOptionChanged(name:String, value:Dynamic):Void {}
	public function onSelectionChanged(index:Int):Void {}

	// ─── Freeplay ─────────────────────────────────────────────────────────────

	public function onSongSelected(song:String):Void {}
	public function onDifficultyChanged(diff:Int):Void {}

	/** Devuelve canciones extra para el freeplay. */
	public function getCustomSongs():Array<Dynamic>        return [];

	// ─── Story ────────────────────────────────────────────────────────────────

	public function onWeekSelected(weekIndex:Int):Void {}

	/** Devuelve semanas extra para el story mode. */
	public function getCustomWeeks():Array<Dynamic>        return [];

	// ─── Title ────────────────────────────────────────────────────────────────

	public function onIntroComplete():Void {}
	public function onIntroBeat(beat:Int):Void {}

	/** Sobreescribe el texto de intro. Array vacío = usar el por defecto. */
	public function getIntroText():Array<String>           return [];

	// ─── Transiciones ─────────────────────────────────────────────────────────

	public function onTransitionIn():Void {}
	public function onTransitionOut():Void {}

	// ─── Acceso completo al estado ────────────────────────────────────────────

	/**
	 * Obtiene CUALQUIER campo del estado por reflexión.
	 * Funciona incluso con campos privados o específicos del estado.
	 *
	 * Ejemplo:
	 *   var selectedSong = getVar("selectedSong");
	 *   var bpm = getVar("Conductor.bpm");
	 */
	public inline function getVar(name:String):Dynamic
		return state != null ? Reflect.getProperty(state, name) : null;

	/**
	 * Modifica CUALQUIER campo del estado por reflexión.
	 *
	 * Ejemplo:
	 *   setVar("canSelect", false);
	 *   setVar("curSelected", 2);
	 */
	public inline function setVar(name:String, value:Dynamic):Void
	{
		if (state != null)
			Reflect.setProperty(state, name, value);
	}

	/**
	 * Llama CUALQUIER método del estado por reflexión.
	 *
	 * Ejemplo:
	 *   callMethod("changeSelection", [1]);
	 *   callMethod("selectSong", []);
	 */
	public function callMethod(methodName:String, ?args:Array<Dynamic>):Dynamic
	{
		if (state == null) return null;
		var method = Reflect.field(state, methodName);
		if (method != null && Reflect.isFunction(method))
			return Reflect.callMethod(state, method, args ?? []);
		return null;
	}

	/**
	 * Intenta obtener el valor de una variable del estado de forma segura.
	 * Si no existe, devuelve el valor por defecto.
	 */
	public function tryGetVar(name:String, defaultValue:Dynamic = null):Dynamic
	{
		if (state == null) return defaultValue;
		try
		{
			var val = Reflect.getProperty(state, name);
			return val != null ? val : defaultValue;
		}
		catch (_) return defaultValue;
	}

	// ─── Utilidades de UI ─────────────────────────────────────────────────────

	/** Añade un FlxSprite al estado. */
	public inline function addSprite(sprite:FlxSprite):FlxSprite
	{
		if (state != null) state.add(sprite);
		return sprite;
	}

	/** Elimina un FlxSprite del estado. */
	public inline function removeSprite(sprite:FlxSprite):FlxSprite
	{
		if (state != null) state.remove(sprite);
		return sprite;
	}

	/** Crea un FlxText con los parámetros dados. */
	public function createText(x:Float, y:Float, text:String, size:Int = 16, ?width:Float):FlxText
		return new FlxText(x, y, width != null ? Std.int(width) : 0, text, size);

	/** Crea un FlxSprite de color sólido. */
	public function createRect(x:Float, y:Float, w:Int, h:Int, color:Int = 0xFFFFFFFF):FlxSprite
	{
		var spr = new FlxSprite(x, y);
		spr.makeGraphic(w, h, color);
		return spr;
	}

	// ─── Tweens / Timers ─────────────────────────────────────────────────────

	/** Hace un tween de Flixel. */
	public function tween(object:Dynamic, values:Dynamic, duration:Float, ?options:Dynamic):Dynamic
		return FlxTween.tween(object, values, duration, options);

	/** Crea un timer de Flixel. */
	public function timer(seconds:Float, callback:Void->Void):FlxTimer
		return new FlxTimer().start(seconds, function(_) callback());

	// ─── Cámara ───────────────────────────────────────────────────────────────

	/** Flash de la cámara actual. */
	public function cameraFlash(color:Int = 0xFFFFFFFF, duration:Float = 0.5):Void
		FlxG.camera.flash(color, duration);

	/** Shake de la cámara actual. */
	public function cameraShake(intensity:Float = 0.05, duration:Float = 0.3):Void
		FlxG.camera.shake(intensity, duration);

	// ─── Sonido ───────────────────────────────────────────────────────────────

	/** Reproduce un sonido. */
	public function playSound(path:String, volume:Float = 1.0):Dynamic
		return FlxG.sound.play(Paths.sound(path), volume);

	/** Reproduce música. */
	public function playMusic(path:String, volume:Float = 1.0):Void
		FlxG.sound.playMusic(Paths.music(path), volume);

	// ─── Logging ─────────────────────────────────────────────────────────────

	public inline function log(msg:Dynamic):Void
		trace('[StateScript: $name] $msg');
}
