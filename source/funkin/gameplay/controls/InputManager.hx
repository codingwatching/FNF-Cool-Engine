package funkin.gameplay.controls;

import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import flixel.util.FlxSignal.FlxTypedSignal;
import haxe.Int64;
import openfl.events.KeyboardEvent;
import openfl.Lib;

/**
 * InputManager — Estado global de teclas de gameplay para uso fuera de PlayState
 * (p.ej. UI, editores, scripts, sistemas externos).
 *
 * ── MEJORAS vs versión anterior (inspiradas en V-Slice PreciseInputManager) ──
 *
 *  1. TIMESTAMPS Int64 en NANOSEGUNDOS:
 *     Lib.getTimer() × NS_PER_MS. getCurrentTimestamp() y getTimeSincePressed()
 *     exponen esta precisión directamente.
 *
 *  2. FlxTypedSignal:
 *     onInputPressed / onInputReleased permiten múltiples suscriptores externos
 *     sin polling manual. Se disparan sub-frame desde el handler de KeyboardEvent.
 *
 *  3. LOOKUP O(1) con _keyMap:
 *     Mapa preconstruido en init(). rebuildKeyMap() para binds dinámicos.
 *
 *  4. Binds configurables:
 *     leftKeys/downKeys/upKeys/rightKeys pueden modificarse antes de init()
 *     o en runtime con rebuildKeyMap().
 *
 *  5. API pública idéntica a la versión anterior:
 *     justPressed, pressed, released (Array<Bool>) sin cambios.
 *
 * ── USO ─────────────────────────────────────────────────────────────────────
 *
 *   InputManager.init();
 *
 *   // En el update loop externo
 *   InputManager.update();
 *   if (InputManager.justPressed[InputManager.LEFT]) doSomething();
 *
 *   // Suscribirse a eventos precisos (V-Slice style)
 *   InputManager.onInputPressed.add(function(e:PreciseInputEvent) {
 *     trace('Dir ${e.dir} pulsada @ ${e.timestamp}ns');
 *   });
 *
 *   InputManager.destroy(); // al destruir la escena
 */
class InputManager
{
	// ── CONSTANTE DE TIEMPO ───────────────────────────────────────────────────

	/** Nanosegundos por milisegundo. Lib.getTimer() devuelve ms; × NS_PER_MS = ns. */
	public static inline var NS_PER_MS:Int = 1_000_000;

	// ── ÍNDICES DE DIRECCIÓN ──────────────────────────────────────────────────

	public static inline var LEFT  = 0;
	public static inline var DOWN  = 1;
	public static inline var UP    = 2;
	public static inline var RIGHT = 3;

	// ── INPUT STATE PÚBLICO ───────────────────────────────────────────────────

	/** true durante el frame en que cada dirección fue pulsada. */
	public static var justPressed:Array<Bool> = [false, false, false, false];
	/** true mientras cada dirección está físicamente pulsada. */
	public static var pressed:Array<Bool>     = [false, false, false, false];
	/** true durante el frame en que cada dirección fue soltada. */
	public static var released:Array<Bool>    = [false, false, false, false];

	// ── SEÑALES PRECISAS (V-Slice style) ─────────────────────────────────────

	/**
	 * Disparada sub-frame, en el momento del KEY_DOWN.
	 * Múltiples suscriptores pueden añadirse con .add() sin sobrescribirse.
	 */
	public static var onInputPressed:FlxTypedSignal<PreciseInputEvent->Void>;

	/** Disparada sub-frame, en el momento del KEY_UP. */
	public static var onInputReleased:FlxTypedSignal<PreciseInputEvent->Void>;

	// ── ESTADO CRUDO ─────────────────────────────────────────────────────────

	private static var _rawPressed:Array<Bool>    = [false, false, false, false];
	private static var _rawHeld:Array<Bool>       = [false, false, false, false];
	private static var _rawReleased:Array<Bool>   = [false, false, false, false];

	/** Timestamp en ns del KEY_DOWN más reciente por dirección. */
	private static var _pressTimeNs:Array<Int64>   = [0, 0, 0, 0];

	/** Timestamp en ns del KEY_UP más reciente por dirección. */
	private static var _releaseTimeNs:Array<Int64> = [0, 0, 0, 0];

	// ── MAPA DE TECLAS O(1) ───────────────────────────────────────────────────

	/** FlxKey(Int) → dirección (0-3). Construido en init(). */
	private static var _keyMap:Map<Int, Int> = new Map<Int, Int>();

	// ── BINDS CONFIGURABLES ───────────────────────────────────────────────────

	/** Teclas para cada dirección. Modificar antes de init() o llamar rebuildKeyMap(). */
	public static var leftKeys:Array<FlxKey>  = [FlxKey.LEFT,  FlxKey.A];
	public static var downKeys:Array<FlxKey>  = [FlxKey.DOWN,  FlxKey.S];
	public static var upKeys:Array<FlxKey>    = [FlxKey.UP,    FlxKey.W];
	public static var rightKeys:Array<FlxKey> = [FlxKey.RIGHT, FlxKey.D];

	private static var _initialized:Bool = false;

	// ── CICLO DE VIDA ─────────────────────────────────────────────────────────

	/**
	 * Registra los listeners OpenFL y construye el mapa de teclas.
	 * Llamar una vez al arrancar la escena que use InputManager.
	 */
	public static function init():Void
	{
		if (_initialized) return;
		_initialized = true;

		onInputPressed  = new FlxTypedSignal<PreciseInputEvent->Void>();
		onInputReleased = new FlxTypedSignal<PreciseInputEvent->Void>();

		_buildKeyMap();

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown, false, 10);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP,   _onKeyUp,   false, 10);
	}

	/**
	 * Elimina los listeners y limpia las señales.
	 * Llamar al destruir la escena para evitar fugas de memoria.
	 */
	public static function destroy():Void
	{
		if (!_initialized) return;
		_initialized = false;
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP,   _onKeyUp);
		if (onInputPressed  != null) onInputPressed.removeAll();
		if (onInputReleased != null) onInputReleased.removeAll();
	}

	// ── TIMESTAMPS ────────────────────────────────────────────────────────────

	/**
	 * Timestamp actual en nanosegundos, compatible con _pressTimeNs.
	 */
	public static inline function getCurrentTimestamp():Int64
		return haxe.Int64.fromFloat(Lib.getTimer()) * NS_PER_MS;

	/**
	 * Tiempo transcurrido en ns desde la última pulsación de `dir`.
	 * Equivalente a PreciseInputManager.getTimeSincePressed() de V-Slice.
	 */
	public static inline function getTimeSincePressed(dir:Int):Int64
		return getCurrentTimestamp() - _pressTimeNs[dir];

	/**
	 * Tiempo transcurrido en ns desde el último release de `dir`.
	 */
	public static inline function getTimeSinceReleased(dir:Int):Int64
		return getCurrentTimestamp() - _releaseTimeNs[dir];

	// ── GESTIÓN DE BINDS ──────────────────────────────────────────────────────

	/**
	 * Reconstruye el mapa de teclas. Llamar si los binds cambian en runtime.
	 */
	public static function rebuildKeyMap():Void
		_buildKeyMap();

	private static function _buildKeyMap():Void
	{
		_keyMap.clear();
		for (k in leftKeys)  _keyMap.set((k:Int), LEFT);
		for (k in downKeys)  _keyMap.set((k:Int), DOWN);
		for (k in upKeys)    _keyMap.set((k:Int), UP);
		for (k in rightKeys) _keyMap.set((k:Int), RIGHT);
	}

	// ── HANDLERS OPENFL ───────────────────────────────────────────────────────

	private static function _onKeyDown(e:KeyboardEvent):Void
	{
		final tsNs:Int64 = haxe.Int64.fromFloat(Lib.getTimer()) * NS_PER_MS;

		var dir:Int = _keyMap.exists(e.keyCode) ? _keyMap.get(e.keyCode) : -1;
		if (dir < 0) return;

		if (!_rawHeld[dir])
		{
			_rawPressed[dir]  = true;
			_pressTimeNs[dir] = tsNs;

			onInputPressed.dispatch({dir: dir, timestamp: tsNs, keyCode: e.keyCode});
		}
		_rawHeld[dir] = true;
	}

	private static function _onKeyUp(e:KeyboardEvent):Void
	{
		final tsNs:Int64 = haxe.Int64.fromFloat(Lib.getTimer()) * NS_PER_MS;

		var dir:Int = _keyMap.exists(e.keyCode) ? _keyMap.get(e.keyCode) : -1;
		if (dir < 0) return;

		_rawHeld[dir]       = false;
		_rawReleased[dir]   = true;
		_releaseTimeNs[dir] = tsNs;

		onInputReleased.dispatch({dir: dir, timestamp: tsNs, keyCode: e.keyCode});
	}

	// ── UPDATE ────────────────────────────────────────────────────────────────

	/**
	 * Consume los flags crudos y actualiza los arrays públicos.
	 * Llamar una vez por frame desde el update loop externo.
	 */
	public static function update():Void
	{
		for (dir in 0...4)
		{
			justPressed[dir] = _rawPressed[dir];
			pressed[dir]     = _rawHeld[dir];
			released[dir]    = _rawReleased[dir];

			_rawPressed[dir]  = false;
			_rawReleased[dir] = false;
		}
	}
}
