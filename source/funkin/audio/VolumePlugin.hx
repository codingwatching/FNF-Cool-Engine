package funkin.audio;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import flixel.util.FlxSignal.FlxTypedSignal;
import ui.SoundTray;

/**
 * VolumePlugin — Gestión de volumen al estilo V-Slice.
 *
 * ─── ¿Qué resuelve? ──────────────────────────────────────────────────────────
 * Flixel por defecto usa hardcoded FlxKey.PLUS/MINUS/ZERO para el volumen.
 * Este plugin:
 *   1. Desactiva esas keys por defecto (hecho en Main.disableDefaultSoundTray)
 *   2. Proporciona control de volumen via FlxG.keys con soporte de gamepad
 *   3. Expone una señal onVolumeChanged para que el SoundTray custom reaccione
 *   4. Propaga correctamente el volumen a FlxG.sound.music (fix del bug de
 *      defaultMusicGroup que no recibe updates del volumen global)
 *
 * ─── Uso ─────────────────────────────────────────────────────────────────────
 *   // En Main.setupGame(), después de disableDefaultSoundTray():
 *   VolumePlugin.initialize();
 *
 *   // Suscribirse a cambios de volumen:
 *   VolumePlugin.onVolumeChanged.add(function(vol:Float) { ... });
 */
class VolumePlugin extends FlxBasic
{
	// ── Señal pública ─────────────────────────────────────────────────────────

	/**
	 * Se dispara cuando el volumen del juego cambia (subir, bajar, mutear).
	 * Recibe el nuevo volumen normalizado (0.0–1.0).
	 */
	public static var onVolumeChanged(get, never):FlxTypedSignal<Float->Void>;

	private static var _onVolumeChanged:Null<FlxTypedSignal<Float->Void>> = null;

	private static function get_onVolumeChanged():FlxTypedSignal<Float->Void>
	{
		if (_onVolumeChanged == null)
		{
			_onVolumeChanged = new FlxTypedSignal<Float->Void>();
			// Propagamos TAMBIÉN los cambios nativos de Flixel (SoundFrontEnd.set_volume)
			FlxG.sound.onVolumeChange.add(function(vol:Float) { _onVolumeChanged.dispatch(vol); });
		}
		return _onVolumeChanged;
	}

	// ── Estado interno ────────────────────────────────────────────────────────

	/** true tras el primer repeat de hold (tanto PLUS como MINUS). */
	private var _volumeHeld:Bool = false;

	/** Tiempo acumulado entre pasos de volumen mientras se mantiene pulsado. */
	private var _volumeRepeatTimer:Float = 0.0;

	/** Referencia cacheada al SoundTray (se busca la primera vez que se necesita). */
	private var _soundTray:Null<SoundTray> = null;

	/** Pausa antes del primer repeat (seg). */
	static inline final REPEAT_DELAY:Float  = 0.5;
	/** Intervalo entre repeats (seg). */
	static inline final REPEAT_INTERVAL:Float = 0.08;
	/** Cuánto sube/baja el volumen por paso. */
	static inline final VOLUME_STEP:Float = 0.1;

	// ── Inicialización ────────────────────────────────────────────────────────

	public function new()
	{
		super();
		// V-Slice: el plugin se añade directamente a FlxG.plugins para que
		// update() se llame cada frame sin necesidad de estar en la escena.
	}

	/**
	 * Registra el plugin. Llamar UNA VEZ desde Main.setupGame()
	 * DESPUÉS de disableDefaultSoundTray().
	 */
	public static function initialize():Void
	{
		// Evitar registrar duplicados si se llama dos veces
		for (p in FlxG.plugins.list)
			if (Std.isOfType(p, VolumePlugin)) return;

		FlxG.plugins.addPlugin(new VolumePlugin());
		trace('[VolumePlugin] Registrado en FlxG.plugins');
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// ── Mute (toggle) ──────────────────────────────────────────────────────
		// FIX: delegar al SoundTray para que su isMuted y volumeBeforeMute
		// estén siempre sincronizados con el estado real de Flixel.
		if (FlxG.keys.justPressed.ZERO || isGamepadMuteJustPressed())
		{
			var tray = _getSoundTray();
			if (tray != null) tray.toggleMute();
			else               { FlxG.sound.toggleMuted(); _dispatchVolumeChange(); }
		}

		// ── Volume up ─────────────────────────────────────────────────────────
		if (FlxG.keys.justPressed.PLUS || isGamepadVolumeUpJustPressed())
		{
			var tray = _getSoundTray();
			if (tray != null) tray.volumeUp();
			else               { FlxG.sound.changeVolume(VOLUME_STEP); _dispatchVolumeChange(); }
			_volumeHeld = false;
			_volumeRepeatTimer = 0;
		}
		else if (FlxG.keys.pressed.PLUS || isGamepadVolumeUpPressed())
		{
			_handleVolumeHold(elapsed, true);
		}
		else if (FlxG.keys.justReleased.PLUS || isGamepadVolumeUpJustReleased())
		{
			_volumeRepeatTimer = 0;
			_volumeHeld = false; // FIX: resetear al soltar para que el próximo hold use REPEAT_DELAY
		}

		// ── Volume down ───────────────────────────────────────────────────────
		if (FlxG.keys.justPressed.MINUS || isGamepadVolumeDownJustPressed())
		{
			var tray = _getSoundTray();
			if (tray != null) tray.volumeDown();
			else               { FlxG.sound.changeVolume(-VOLUME_STEP); _dispatchVolumeChange(); }
			_volumeHeld = false;
			_volumeRepeatTimer = 0;
		}
		else if (FlxG.keys.pressed.MINUS || isGamepadVolumeDownPressed())
		{
			_handleVolumeHold(elapsed, false);
		}
		else if (FlxG.keys.justReleased.MINUS || isGamepadVolumeDownJustReleased())
		{
			_volumeRepeatTimer = 0;
			_volumeHeld = false; // FIX: resetear al soltar
		}
	}

	// ── Helpers de hold-repeat ────────────────────────────────────────────────

	/**
	 * @param isUp  true = subir volumen, false = bajar volumen.
	 * Delega al SoundTray si está disponible para mantener su estado interno
	 * (isMuted, volumeBeforeMute, barra visual) siempre en sync.
	 */
	private function _handleVolumeHold(elapsed:Float, isUp:Bool):Void
	{
		_volumeRepeatTimer += elapsed;
		final threshold:Float = _volumeHeld ? REPEAT_INTERVAL : REPEAT_DELAY;
		if (_volumeRepeatTimer >= threshold)
		{
			_volumeRepeatTimer -= threshold;
			_volumeHeld = true;

			final tray = _getSoundTray();
			if (tray != null)
			{
				if (isUp) tray.volumeUp(); else tray.volumeDown();
			}
			else
			{
				FlxG.sound.changeVolume(isUp ? VOLUME_STEP : -VOLUME_STEP);
				_dispatchVolumeChange();
			}
		}
	}

	// ── SoundTray lookup ──────────────────────────────────────────────────────

	/**
	 * Devuelve el SoundTray registrado en FlxG.plugins, o null si no existe.
	 * Cachea el resultado en _soundTray para no iterar la lista cada frame.
	 */
	private function _getSoundTray():Null<SoundTray>
	{
		if (_soundTray != null && _soundTray.alive)
			return _soundTray;

		_soundTray = null;
		for (p in FlxG.plugins.list)
		{
			final t = Std.downcast(p, SoundTray);
			if (t != null) { _soundTray = t; break; }
		}
		return _soundTray;
	}

	// ── Dispatch (fallback cuando SoundTray no está disponible) ───────────────

	private function _dispatchVolumeChange():Void
	{
		// Propagar al music (fix de defaultMusicGroup)
		if (FlxG.sound.music != null)
		{
			final mv = FlxG.sound.music.volume;
			FlxG.sound.music.volume = mv; // dispara updateTransform()
		}

		// Notificar a los suscriptores
		if (_onVolumeChanged != null)
			_onVolumeChanged.dispatch(FlxG.sound.muted ? 0.0 : FlxG.sound.volume);
	}

	// ── Gamepad helpers (stubs extensibles) ──────────────────────────────────
	// Estas funciones devuelven false por defecto.
	// Sobrescríbelas o amplíalas con la lógica de tu Controls si quieres
	// soporte de gamepad para el volumen.

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

	// ── Ciclo de vida ─────────────────────────────────────────────────────────

	override public function destroy():Void
	{
		if (FlxG.plugins.list.contains(this))
			FlxG.plugins.remove(this);
		super.destroy();
	}
}
