package funkin.audio;

import flixel.FlxG;
import Paths;

using StringTools;
/**
 * MusicManager — gestor centralizado de música de menús.
 *
 * ─── Problema que resuelve ────────────────────────────────────────────────────
 * Antes cada state llamaba FlxG.sound.playMusic(...) directamente sin saber si
 * la pista correcta ya estaba sonando, lo que hacía que la música se reiniciara
 * desde el principio al cambiar entre menús aunque fuera la misma canción.
 *
 * ─── Uso ──────────────────────────────────────────────────────────────────────
 *   // Cambiar a una pista (solo hace playMusic si es diferente a la actual):
 *   MusicManager.play('freakyMenu', 0.7);
 *
 *   // Cambiar a una pista siempre (fuerza restart aunque ya suene):
 *   MusicManager.play('freakyMenu', 0.7, true);
 *
 *   // Parar la música:
 *   MusicManager.stop();
 *
 *   // Saber qué pista suena:
 *   MusicManager.currentTrack  → 'freakyMenu' | ''
 */
class MusicManager
{
	/** Nombre de la pista que está actualmente sonando ('freakyMenu', 'girlfriendsRingtone/girlfriendsRingtone', etc.)
	 *  Cadena vacía si no hay música. */
	public static var currentTrack(default, null):String = '';

	/** Volumen actual de la música. */
	public static var currentVolume(default, null):Float = 1.0;

	// ── API principal ──────────────────────────────────────────────────────────

	/**
	 * Reproduce una pista de música.
	 * Si la pista ya está sonando y forceRestart=false, no hace nada.
	 *
	 * @param track        Nombre del music (igual que Paths.music(track))
	 * @param volume       Volumen inicial (0.0–1.0)
	 * @param forceRestart Si true, reinicia la pista aunque ya esté sonando
	 * @param loop         Si true, la música hace loop (default: true)
	 */
	public static function play(track:String, volume:Float = 1.0, forceRestart:Bool = false, loop:Bool = true):Void
	{
		if (track == null || track.trim() == '') return;

		// Ya suena la pista correcta — no hacer nada
		if (!forceRestart && isPlaying(track))
			return;

		currentTrack  = track;
		currentVolume = volume;

		final snd = Paths.loadMusic(track);
		if (snd != null)
			FlxG.sound.playMusic(snd, volume, loop);
		else
			FlxG.sound.playMusic(Paths.music(track), volume, loop);

		// BUGFIX (Flixel git): playMusic() añade el FlxSound a defaultMusicGroup
		// pero NO a FlxG.sound.list. El setter set_volume de SoundFrontEnd solo
		// itera list → el volumen global nunca llega a la música de menús.
		// Añadir a list manualmente hace que updateTransform() la alcance igual
		// que a cualquier SFX.
		if (FlxG.sound.music != null && !FlxG.sound.list.members.contains(FlxG.sound.music))
			FlxG.sound.list.add(FlxG.sound.music);

		// FIX: sin persist=true, Flixel destruye FlxG.sound.music en cada
		// state switch → isPlaying() devuelve false → la música se reinicia.
		if (FlxG.sound.music != null)
			FlxG.sound.music.persist = true;
	}

	/**
	 * Igual que play() pero hace fade-in desde 0 al volumen objetivo.
	 * Útil para la primera vez que suena la pista (p.ej. TitleState).
	 *
	 * FIX: si el volumen global (FlxG.sound.volume) es 0 porque el SoundTray
	 * cargó un estado muteado, el fade del FlxSound local (0→targetVolume)
	 * resulta en silencio total porque gain_real = globalVol × localVol = 0.
	 * En ese caso reproducimos directamente al volumen objetivo sin fade,
	 * ya que el usuario verá la barra de volumen en 0 y podrá subirla.
	 */
	public static function playWithFade(track:String, targetVolume:Float = 0.7, fadeDuration:Float = 4.0, forceRestart:Bool = false):Void
	{
		if (track == null || track.trim() == '') return;

		if (!forceRestart && isPlaying(track))
			return;

		currentTrack  = track;
		currentVolume = targetVolume;

		// Intentar primero con el Sound cacheado; si falla, pasar el path string directamente.
		final snd = Paths.loadMusic(track);
		if (snd != null)
			FlxG.sound.playMusic(snd, 0);
		else
			FlxG.sound.playMusic(Paths.music(track), 0);

		// Si playMusic falló silenciosamente (asset no encontrado), intentar con el path directo
		if (FlxG.sound.music == null)
		{
			trace('[MusicManager] playWithFade: primer intento falló para "$track", reintentando con path raw');
			FlxG.sound.playMusic(Paths.music(track), 0);
		}

		if (FlxG.sound.music != null)
		{
			if (!FlxG.sound.list.members.contains(FlxG.sound.music))
				FlxG.sound.list.add(FlxG.sound.music);
			FlxG.sound.music.persist = true;
			// Forzar play() explícito antes del fadeIn por si playMusic lo dejó pausado
			if (!FlxG.sound.music.playing)
				FlxG.sound.music.play();

			// FIX: si el volumen global es 0 (estado muted guardado en save), el fade
			// del volumen LOCAL del FlxSound no produce sonido alguno porque:
			//   gain_real = FlxG.sound.volume(0) × music.volume(0→0.7) = 0 siempre.
			// Detectamos este caso y seteamos el volumen del FlxSound directamente al
			// target sin fade, para que la música sea audible tan pronto como el usuario
			// suba el volumen. El fade visual (barra creciendo) no tiene sentido si
			// el volumen global ya es 0 por decisión del usuario.
			final globalVol:Float = FlxG.sound.muted ? 0.0 : FlxG.sound.volume;
			if (globalVol <= 0.0)
			{
				// Volumen global en 0 — poner el FlxSound en targetVolume para que
				// suene cuando el usuario suba el volumen.
				FlxG.sound.music.volume = targetVolume;
			}
			else
			{
				// Volumen global > 0 — fade-in normal.
				FlxG.sound.music.fadeIn(fadeDuration, 0, targetVolume);
			}
		}
		else
		{
			trace('[MusicManager] playWithFade: no se pudo cargar "$track" — revisa que el archivo exista');
		}
	}

	/** Para la música y limpia el track actual. */
	public static function stop():Void
	{
		currentTrack = '';
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
	}

	/** Devuelve true si la pista `track` está actualmente sonando. */
	public static function isPlaying(track:String):Bool
	{
		if (track == null || track.trim() == '') return false;
		return (currentTrack == track)
		    && (FlxG.sound.music != null)
		    && FlxG.sound.music.playing;
	}

	/** Detiene la música del MusicManager y cede el control de audio
	 *  a PlayState. Llama esto ANTES de asignar FlxG.sound.music al instrumental. */
	public static function invalidate():Void
	{
		currentTrack = '';
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.persist = false;
			FlxG.sound.music.stop();
		}
	}
}
