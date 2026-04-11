package data;

import funkin.gameplay.controls.Controls;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.util.FlxSignal;

// import ui.DeviceManager;
// import props.Player;
class PlayerSettings
{
	static public var numPlayers(default, null) = 0;
	static public var numAvatars(default, null) = 0;
	static public var player1(default, null):PlayerSettings;
	static public var player2(default, null):PlayerSettings;
	static public var gfVersion(default, null):PlayerSettings;

	#if (haxe >= "4.0.0")
	static public final onAvatarAdd = new FlxTypedSignal<PlayerSettings->Void>();
	static public final onAvatarRemove = new FlxTypedSignal<PlayerSettings->Void>();
	#else
	static public var onAvatarAdd = new FlxTypedSignal<PlayerSettings->Void>();
	static public var onAvatarRemove = new FlxTypedSignal<PlayerSettings->Void>();
	#end

	public var id(default, null):Int;

	#if (haxe >= "4.0.0")
	public final controls:Controls;
	#else
	public var controls:Controls;
	#end

	// public var avatar:Player;
	// public var camera(get, never):PlayCamera;

	function new(id, scheme)
	{
		this.id = id;
		this.controls = new Controls('player$id', scheme);
	}

	public function setKeyboardScheme(scheme)
	{
		controls.setKeyboardScheme(scheme);
	}

	// ouh yeah
	static public function init():Void
	{
		if (player1 == null)
		{
			player1 = new PlayerSettings(0, Solo);
			++numPlayers;
		}

		// Escaneo inmediato: añadir bindings de gamepad si ya hay mandos conectados.
		_scanAndAddGamepads();

		FlxG.gamepads.deviceConnected.add(_onGamepadConnected);
		FlxG.gamepads.deviceDisconnected.add(_onGamepadDisconnected);

		// Escaneo DIFERIDO: SDL puede no haber enumerado todos los gamepads
		// durante init() (ocurre porque setupGame() se ejecuta antes del primer
		// frame de OpenFL y el subsistema SDL_JOYSTICK no siempre está listo).
		// Repetimos el scan a los 5 frames para capturar cualquier mando que
		// ya estuviera enchufado pero que SDL entregó tarde.
		var framesLeft:Int = 5;
		var stage = openfl.Lib.current.stage;
		var listener:openfl.events.Event->Void = null;
		listener = function(_:openfl.events.Event):Void
		{
			if (--framesLeft > 0) return;
			stage.removeEventListener(openfl.events.Event.ENTER_FRAME, listener);
			_scanAndAddGamepads();
			trace('[PlayerSettings] Deferred gamepad scan done.');
		};
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, listener);
	}

	/**
	 * Escanea los gamepads activos y añade los bindings por defecto
	 * si aún no se han configurado. Seguro de llamar múltiples veces.
	 */
	static function _scanAndAddGamepads():Void
	{
		// addDefaultGamepad() ya usa FlxInputDeviceID.ALL, así que un solo
		// llamado es suficiente para todos los gamepads conectados.
		// La guarda interna de addDefaultGamepad() evita duplicados.
		if (player1 != null && FlxG.gamepads.numActiveGamepads > 0)
		{
			player1.controls.addDefaultGamepad(0);
			trace('[PlayerSettings] Gamepad bindings applied (${FlxG.gamepads.numActiveGamepads} pad(s) active).');
		}
	}

	/**
	 * Llamado cuando se conecta un mando en caliente.
	 * addDefaultGamepad() ya usa ALL y tiene guarda contra duplicados,
	 * así que basta con llamarlo — se ignorará si ya estaba configurado.
	 */
	static function _onGamepadConnected(gamepad:flixel.input.gamepad.FlxGamepad):Void
	{
		if (player1 != null)
			player1.controls.addDefaultGamepad(gamepad.id);
		trace('[PlayerSettings] Gamepad connected: id=${gamepad.id}');
	}

	/**
	 * Llamado cuando se desconecta un mando.
	 * Como usamos ALL, no quitamos los bindings — siguen disponibles
	 * para si el jugador vuelve a conectar cualquier mando.
	 */
	static function _onGamepadDisconnected(gamepad:flixel.input.gamepad.FlxGamepad):Void
	{
		trace('[PlayerSettings] Gamepad disconnected: id=${gamepad.id}');
	}

	static public function reset()
	{
		// Quitar los listeners antes de limpiar el estado para evitar fugas.
		FlxG.gamepads.deviceConnected.remove(_onGamepadConnected);
		FlxG.gamepads.deviceDisconnected.remove(_onGamepadDisconnected);
		player1 = null;
		player2 = null;
		gfVersion = null;
		numPlayers = 0;
	}
}
