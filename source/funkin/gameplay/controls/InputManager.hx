package funkin.gameplay.controls;

import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import openfl.events.KeyboardEvent;
import openfl.Lib;

/**
 * InputManager — Estado global de teclas de gameplay para uso fuera de PlayState
 * (p.ej. UI, editores, scripts).
 *
 * Usa OpenFL KeyboardEvent igual que InputHandler para consistencia y precisión.
 * Los keyCodes de OpenFL coinciden con los valores Int de FlxKey en todas las
 * plataformas objetivo de Flixel.
 */
class InputManager
{
	public static inline var LEFT  = 0;
	public static inline var DOWN  = 1;
	public static inline var UP    = 2;
	public static inline var RIGHT = 3;

	public static var justPressed:Array<Bool> = [false, false, false, false];
	public static var pressed:Array<Bool>     = [false, false, false, false];
	public static var released:Array<Bool>    = [false, false, false, false];

	// Estado crudo escrito por los listeners, consumido en update()
	private static var _rawPressed:Array<Bool>  = [false, false, false, false];
	private static var _rawHeld:Array<Bool>     = [false, false, false, false];
	private static var _rawReleased:Array<Bool> = [false, false, false, false];

	private static var _initialized:Bool = false;

	/** Registra los listeners OpenFL. Llamar una vez al arrancar. */
	public static function init():Void
	{
		if (_initialized) return;
		_initialized = true;
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown, false, 10);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP,   _onKeyUp,   false, 10);
	}

	/** Remueve los listeners. Llamar al destruir la escena si procede. */
	public static function destroy():Void
	{
		if (!_initialized) return;
		_initialized = false;
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP,   _onKeyUp);
	}

	private static function _onKeyDown(e:KeyboardEvent):Void
	{
		var dir = _keyCodeToDir(e.keyCode);
		if (dir < 0) return;
		if (!_rawHeld[dir]) _rawPressed[dir] = true; // filtrar key-repeat del OS
		_rawHeld[dir] = true;
	}

	private static function _onKeyUp(e:KeyboardEvent):Void
	{
		var dir = _keyCodeToDir(e.keyCode);
		if (dir < 0) return;
		_rawHeld[dir]     = false;
		_rawReleased[dir] = true;
	}

	private static inline function _keyCodeToDir(keyCode:Int):Int
	{
		return switch (keyCode)
		{
			case 37 | 65:  LEFT;   // LEFT, A
			case 40 | 83:  DOWN;   // DOWN, S
			case 38 | 87:  UP;     // UP,   W
			case 39 | 68:  RIGHT;  // RIGHT, D
			default:       -1;
		}
	}

	/** Consumir los flags crudos y exponerlos en los arrays públicos. */
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
