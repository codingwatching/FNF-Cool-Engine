package funkin.audio;

import flixel.FlxG;
import funkin.audio.CoreAudio;

using StringTools;

/**
 * MusicManager — gestor centralizado of music of menus.
 *
 * ─── Historia ─────────────────────────────────────────────────────────────────
 * The logic actual vive now in CoreAudio (funkin/audio/CoreAudio.hx).
 * MusicManager exists for compatibility with all the code of menus existente
 * que ya llama MusicManager.play() / MusicManager.stop() / etc.
 *
 * All the methods delegan to CoreAudio, that resuelve:
 *   • Volumen/mute propagado correctamente (fix defaultMusicGroup).
 *   • No resets the music if the same track already is sonando.
 *   • Fade-in inteligente cuando el volumen global es 0 (estado muted en save).
 *
 * ─── Uso ──────────────────────────────────────────────────────────────────────
 *   MusicManager.play('freakyMenu', 0.7);       // igual que antes
 *   MusicManager.stop();
 *   MusicManager.currentTrack                   // track activa
 *   MusicManager.isPlaying('freakyMenu')        // → bool
 */
class MusicManager
{
	/** Name of the pista that is currently sonando. '' if no there is music. */
	public static var currentTrack(get, never):String;
	private static inline function get_currentTrack():String
		return CoreAudio.menuTrack;

	/** Volumen current of the music of menu. */
	public static var currentVolume(default, null):Float = 1.0;

	// ── API principal ──────────────────────────────────────────────────────────

	/**
	 * Reproduce a pista of music of menu.
	 * If the pista already is sonando and forceRestart=false, no hace nothing.
	 *
	 * @param track        Nombre del music (igual que Paths.music(track))
	 * @param volume       Volumen inicial (0.0–1.0)
	 * @param forceRestart If true, resets the pista although already is sonando
	 * @param loop         If true, the music hace loop (default: true)
	 */
	public static function play(track:String, volume:Float = 1.0,
		forceRestart:Bool = false, loop:Bool = true):Void
	{
		if (track == null || track.trim() == '') return;
		currentVolume = volume;
		CoreAudio.playMenu(track, volume, forceRestart, loop);
	}

	/**
	 * Igual que play() pero hace fade-in desde 0 al volumen objetivo.
	 * Useful for the first vez that suena the pista (p.ej. TitleState).
	 */
	public static function playWithFade(track:String, targetVolume:Float = 0.7,
		fadeDuration:Float = 4.0, forceRestart:Bool = false):Void
	{
		if (track == null || track.trim() == '') return;
		currentVolume = targetVolume;
		CoreAudio.playMenuFade(track, targetVolume, fadeDuration, forceRestart);
	}

	/** For the music and clears the track current. */
	public static function stop():Void
	{
		CoreAudio.stopMenu();
	}

	/** Returns true if the pista `track` is currently sonando. */
	public static function isPlaying(track:String):Bool
		return CoreAudio.isMenuPlaying(track);

	/**
	 * Stops the music of the MusicManager and cede the control of audio
	 * a PlayState. Llama esto ANTES de asignar FlxG.sound.music al instrumental.
	 */
	public static function invalidate():Void
	{
		CoreAudio.stopMenu();
		// Asegurar that cualquier track of menu no quede in persist
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.persist = false;
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}
	}
}
