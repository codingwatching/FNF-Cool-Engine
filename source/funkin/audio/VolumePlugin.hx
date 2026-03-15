package funkin.audio;

import flixel.FlxG;
import funkin.audio.SoundTray;

/**
 * VolumePlugin — Gestión de volumen al estilo V-Slice.
 *
 * ─── Cambio respecto a la versión anterior ───────────────────────────────────
 * Antes usaba FlxG.plugins.addPlugin() esperando que Flixel llamase update()
 * automáticamente. En Flixel 5, addPlugin() requiere IFlxPlugin; FlxBasic
 * no implementa esa interfaz → el update nunca se ejecutaba → las teclas
 * +/-/0 no hacían nada.
 *
 * Ahora se conecta directamente a FlxG.signals.preUpdate, igual que
 * SoundTrayContainer, garantizando que _onPreUpdate() se llame cada frame
 * independientemente del sistema de plugins.
 */
class VolumePlugin
{
	// ── Estado interno ────────────────────────────────────────────────────────

	/** true tras el primer repeat de hold (tanto PLUS como MINUS). */
	private var _volumeHeld:Bool = false;

	/** Tiempo acumulado entre pasos de volumen mientras se mantiene pulsado. */
	private var _volumeRepeatTimer:Float = 0.0;

	/** Pausa antes del primer repeat (seg). */
	static inline final REPEAT_DELAY:Float   = 0.5;
	/** Intervalo entre repeats (seg). */
	static inline final REPEAT_INTERVAL:Float = 0.08;
	/** Cuánto sube/baja el volumen por paso. */
	static inline final VOLUME_STEP:Float     = 0.1;

	/** Referencia al singleton activo. */
	private static var _instance:Null<VolumePlugin> = null;

	// ── Inicialización ────────────────────────────────────────────────────────

	private function new() {}

	/**
	 * Registra el plugin. Llamar UNA VEZ desde Main.setupGame()
	 * DESPUÉS de disableDefaultSoundTray().
	 */
	public static function initialize():Void
	{
		if (_instance != null) return;
		_instance = new VolumePlugin();
		FlxG.signals.preUpdate.add(_instance._onPreUpdate);
		trace('[VolumePlugin] Conectado a FlxG.signals.preUpdate');
	}

	/** Desconecta el plugin (útil para tests o reinicios). */
	public static function destroy():Void
	{
		if (_instance == null) return;
		FlxG.signals.preUpdate.remove(_instance._onPreUpdate);
		_instance = null;
	}

	// ── Update ────────────────────────────────────────────────────────────────

	private function _onPreUpdate():Void
	{
		// Respetar el flag de bloqueo (activo en campos de texto).
		if (SoundTray.blockInput) return;

		final elapsed:Float = FlxG.elapsed;

		// ── Mute (toggle) ──────────────────────────────────────────────────────
		if (FlxG.keys.justPressed.ZERO || FlxG.keys.justPressed.NUMPADZERO
		    || isGamepadMuteJustPressed())
		{
			final tray = SoundTray.instance;
			if (tray != null) tray.toggleMute();
			else               funkin.audio.CoreAudio.toggleMute();
		}

		// ── Volume up ─────────────────────────────────────────────────────────
		// PLUS  = tecla = / + del teclado principal
		// NUMPADPLUS = tecla + del teclado numérico
		final upJust    = FlxG.keys.justPressed.PLUS    || FlxG.keys.justPressed.NUMPADPLUS    || isGamepadVolumeUpJustPressed();
		final upHeld    = FlxG.keys.pressed.PLUS         || FlxG.keys.pressed.NUMPADPLUS         || isGamepadVolumeUpPressed();
		final upRelease = FlxG.keys.justReleased.PLUS    || FlxG.keys.justReleased.NUMPADPLUS    || isGamepadVolumeUpJustReleased();

		if (upJust)
		{
			final tray = SoundTray.instance;
			if (tray != null) tray.volumeUp();
			else               funkin.audio.CoreAudio.setMasterVolume(funkin.audio.CoreAudio.masterVolume + VOLUME_STEP);
			_volumeHeld = false;
			_volumeRepeatTimer = 0;
		}
		else if (upHeld)   { _handleVolumeHold(elapsed, true); }
		else if (upRelease){ _volumeRepeatTimer = 0; _volumeHeld = false; }

		// ── Volume down ───────────────────────────────────────────────────────
		final downJust    = FlxG.keys.justPressed.MINUS    || FlxG.keys.justPressed.NUMPADMINUS    || isGamepadVolumeDownJustPressed();
		final downHeld    = FlxG.keys.pressed.MINUS         || FlxG.keys.pressed.NUMPADMINUS         || isGamepadVolumeDownPressed();
		final downRelease = FlxG.keys.justReleased.MINUS    || FlxG.keys.justReleased.NUMPADMINUS    || isGamepadVolumeDownJustReleased();

		if (downJust)
		{
			final tray = SoundTray.instance;
			if (tray != null) tray.volumeDown();
			else               funkin.audio.CoreAudio.setMasterVolume(funkin.audio.CoreAudio.masterVolume - VOLUME_STEP);
			_volumeHeld = false;
			_volumeRepeatTimer = 0;
		}
		else if (downHeld)   { _handleVolumeHold(elapsed, false); }
		else if (downRelease){ _volumeRepeatTimer = 0; _volumeHeld = false; }
	}

	// ── Helpers de hold-repeat ────────────────────────────────────────────────

	private function _handleVolumeHold(elapsed:Float, isUp:Bool):Void
	{
		_volumeRepeatTimer += elapsed;
		final threshold:Float = _volumeHeld ? REPEAT_INTERVAL : REPEAT_DELAY;
		if (_volumeRepeatTimer >= threshold)
		{
			_volumeRepeatTimer -= threshold;
			_volumeHeld = true;

			final tray = SoundTray.instance;
			if (tray != null)
			{
				if (isUp) tray.volumeUp(); else tray.volumeDown();
			}
			else
			{
				final delta = isUp ? VOLUME_STEP : -VOLUME_STEP;
				funkin.audio.CoreAudio.setMasterVolume(funkin.audio.CoreAudio.masterVolume + delta);
			}
		}
	}

	// ── Gamepad helpers (stubs extensibles) ──────────────────────────────────

	private function isGamepadMuteJustPressed():Bool
	{
		return FlxG.gamepads.anyJustPressed(flixel.input.gamepad.FlxGamepadInputID.BACK);
	}

	private function isGamepadVolumeUpJustPressed():Bool    { return false; }
	private function isGamepadVolumeUpPressed():Bool         { return false; }
	private function isGamepadVolumeUpJustReleased():Bool    { return false; }
	private function isGamepadVolumeDownJustPressed():Bool   { return false; }
	private function isGamepadVolumeDownPressed():Bool        { return false; }
	private function isGamepadVolumeDownJustReleased():Bool  { return false; }
}
