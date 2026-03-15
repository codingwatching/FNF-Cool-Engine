package funkin.audio;

import flixel.FlxG;
import funkin.audio.CoreAudio;

using StringTools;

/**
 * MusicManager — gestor centralizado de música de menús.
 *
 * ─── Historia ─────────────────────────────────────────────────────────────────
 * La lógica real vive ahora en CoreAudio (funkin/audio/CoreAudio.hx).
 * MusicManager existe para compatibilidad con todo el código de menús existente
 * que ya llama MusicManager.play() / MusicManager.stop() / etc.
 *
 * Todos los métodos delegan a CoreAudio, que resuelve:
 *   • Volumen/mute propagado correctamente (fix defaultMusicGroup).
 *   • No reinicia la música si la misma track ya está sonando.
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
	/** Nombre de la pista que está actualmente sonando. '' si no hay música. */
	public static var currentTrack(get, never):String;
	private static inline function get_currentTrack():String
		return CoreAudio.menuTrack;

	/** Volumen actual de la música de menú. */
	public static var currentVolume(default, null):Float = 1.0;

	// ── API principal ──────────────────────────────────────────────────────────

	/**
	 * Reproduce una pista de música de menú.
	 * Si la pista ya está sonando y forceRestart=false, no hace nada.
	 *
	 * @param track        Nombre del music (igual que Paths.music(track))
	 * @param volume       Volumen inicial (0.0–1.0)
	 * @param forceRestart Si true, reinicia la pista aunque ya esté sonando
	 * @param loop         Si true, la música hace loop (default: true)
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
	 * Útil para la primera vez que suena la pista (p.ej. TitleState).
	 */
	public static function playWithFade(track:String, targetVolume:Float = 0.7,
		fadeDuration:Float = 4.0, forceRestart:Bool = false):Void
	{
		if (track == null || track.trim() == '') return;
		currentVolume = targetVolume;
		CoreAudio.playMenuFade(track, targetVolume, fadeDuration, forceRestart);
	}

	/** Para la música y limpia el track actual. */
	public static function stop():Void
	{
		CoreAudio.stopMenu();
	}

	/** Devuelve true si la pista `track` está actualmente sonando. */
	public static function isPlaying(track:String):Bool
		return CoreAudio.isMenuPlaying(track);

	/**
	 * Detiene la música del MusicManager y cede el control de audio
	 * a PlayState. Llama esto ANTES de asignar FlxG.sound.music al instrumental.
	 */
	public static function invalidate():Void
	{
		CoreAudio.stopMenu();
		// Asegurar que cualquier track de menú no quede en persist
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.persist = false;
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}
	}
}
