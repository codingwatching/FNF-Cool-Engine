package funkin.audio;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.sound.FlxSound;
import flixel.util.FlxSignal.FlxTypedSignal;

using StringTools;
/**
 * CoreAudio — API de audio totalmente independiente de FlxG.sound.
 *
 * ─── Why ─────────────────────────────────────────────────────────────────
 * FlxG.sound.volume / FlxG.sound.muted son irrecuperablemente rotos:
 *   • set_volume itera FlxG.sound.list, but music is in defaultMusicGroup.
 *   • set_muted no dispara onVolumeChange, so that cualquier listener that
 *     dependa of that signal never is entera of the mute.
 *   • FlxSoundGroup multiplica volumenes de forma que un sound en dos grupos
 *     puede recibir el cambio dos veces o ninguna.
 *
 * ─── Solution ────────────────────────────────────────────────────────────────
 * CoreAudio gestiona su propio `masterVolume` y `muted`. El volumen se aplica
 * en dos capas:
 *
 *   1. FlxG.sound.volume = masterVolume
 *      → Flixel applies this to all the sounds (SFX, UI, menu) via
 *        updateTransform() automatically.
 *
 *   2. _applyTo(snd): snd.volume = baseVolume
 *      → Only for music/vocales (in defaultMusicGroup, fuera of list).
 *        El volumen efectivo final es:
 *          transform = FlxG.sound.volume × group.volume × snd._volume
 *                    = masterVolume × 1.0 × baseVolume
 *
 * ANTES (bug): FlxG.sound.volume se fijaba a 1.0 siempre → todos los sounds
 * fuera of the registry (SFX, UI) sonaban to the maximum ignorando masterVolume.
 *
 * ─── Basic usage ───────────────────────────────────────────────────────────────
 *
 *   // Main.setupGame():
 *   CoreAudio.initialize();
 *
 *   // PlayState.generateSong():
 *   CoreAudio.setInst(instSound);                 // registra instrumental
 *   CoreAudio.addVocal('bf', bfSound);            // registra vocal
 *
 *   // PlayState.startSong():
 *   CoreAudio.playAll();
 *
 *   // resyncVocals():
 *   CoreAudio.resync();
 *
 *   // PlayState.destroy():
 *   CoreAudio.stopAll();
 *
 *   // SoundTray / VolumePlugin:
 *   CoreAudio.setMasterVolume(0.7);
 *   CoreAudio.setMuted(true);
 *   CoreAudio.masterVolume   // → Float
 *   CoreAudio.muted          // → Bool
 */
class CoreAudio extends FlxBasic
{
	// ── Singleton ─────────────────────────────────────────────────────────────

	private static var _self:Null<CoreAudio> = null;

	/** Registra CoreAudio como plugin de Flixel. Llamar UNA VEZ en Main.setupGame(). */
	public static function initialize():Void
	{
		if (_self != null) return;
		// Cargar el volumen guardado ANTES de sincronizar FlxG.sound.volume,
		// para que masterVolume ya tenga el valor correcto desde el primer frame.
		loadVolume();
		// Sincronizar FlxG.sound.volume con masterVolume para que TODOS los
		// sounds (SFX, UI, music of menu) respeten the volumen maestro.
		// Flixel aplica FlxG.sound.volume como multiplicador global a cada
		// FlxSound.updateTransform(), por lo que basta con mantenerlo en sync.
		FlxG.sound.volume = muted ? 0.0 : masterVolume;
		FlxG.sound.muted  = false;
		// Vaciar las teclas de volumen por defecto de Flixel (ya las gestiona
		// VolumePlugin / SoundTray con CoreAudio).
		FlxG.sound.volumeUpKeys   = [];
		FlxG.sound.volumeDownKeys = [];
		FlxG.sound.muteKeys       = [];

		_self = new CoreAudio();
		FlxG.plugins.addPlugin(_self);
		trace('[CoreAudio] Inicializado. masterVolume=${masterVolume} muted=${muted}.');
	}

	// ── Volumen maestro (independiente de FlxG.sound) ─────────────────────────

	/** Volumen maestro (0.0–1.0). Afecta a todos los sounds registrados. */
	public static var masterVolume(default, null):Float = 1.0;

	/** Estado de mute maestro. */
	public static var muted(default, null):Bool = false;

	/**
	 * Cambia el volumen maestro y lo aplica inmediatamente a todos los sounds.
	 * @param v  Volumen (0.0–1.0). Se redondea a 1 decimal para evitar float drift.
	 */
	public static function setMasterVolume(v:Float):Void
	{
		masterVolume = Math.round(Math.max(0.0, Math.min(1.0, v)) * 10) / 10;
		// Auto-mute implicit when the volumen llega to 0 (bajando with '-').
		// Sin esto, SoundTray.isMuted y CoreAudio.muted quedan desincronizados
		// → la tecla 0 deja de funcionar correctamente.
		if (masterVolume <= 0 && !muted)
		{
			muted = true;
			// NO tocar _explicitMute: esto es mute por volumen, no por toggle.
		}
		// Auto-unmute when is sube from 0 (only if no era mute explicit).
		else if (masterVolume > 0 && muted && !_explicitMute)
		{
			muted = false;
		}
		FlxG.sound.volume = muted ? 0.0 : masterVolume;
		FlxG.sound.muted  = false;
		_applyAll();
		if (_sig != null) _sig.dispatch(muted ? 0.0 : masterVolume);
	}

	/**
	 * Activa o desactiva el mute maestro.
	 * @param m  true = silencio total, false = restaurar volumen.
	 */
	public static function setMuted(m:Bool):Void
	{
		_explicitMute = m;
		muted = m;
		// Sincronizar FlxG.sound.volume → SFX/UI en FlxG.sound.list
		FlxG.sound.volume = muted ? 0.0 : masterVolume;
		FlxG.sound.muted  = false;
		// Sincronizar sounds registrados (music/vocales in defaultMusicGroup
		// that no reciben the update of FlxG.sound.volume automatically).
		_applyAll();
		if (_sig != null) _sig.dispatch(muted ? 0.0 : masterVolume);
	}

	/** Alterna mute. Devuelve el nuevo estado. */
	public static function toggleMute():Bool
	{
		setMuted(!muted);
		return muted;
	}

	/** Volumen efectivo actual (0.0 si muted). */
	public static var effectiveVolume(get, never):Float;
	private static inline function get_effectiveVolume():Float
		return muted ? 0.0 : masterVolume;

	// ── Signal public ─────────────────────────────────────────────────────────

	/** Se dispara en cada cambio de volumen/mute. Valor = volumen efectivo. */
	public static var onVolumeChanged(get, never):FlxTypedSignal<Float->Void>;
	private static var _sig:Null<FlxTypedSignal<Float->Void>> = null;
	private static inline function get_onVolumeChanged():FlxTypedSignal<Float->Void>
	{
		if (_sig == null) _sig = new FlxTypedSignal<Float->Void>();
		return _sig;
	}

	// ── Estado de gameplay ────────────────────────────────────────────────────

	/** Instrumental active (null if no there is song). */
	public static var inst(default, null):Null<FlxSound> = null;

	/** Vocales por nombre de personaje. */
	public static var vocals(default, null):Map<String, FlxSound> = [];

	// ── State of menu ────────────────────────────────────────────────────────

	/** Track of menu active. '' if no there is. */
	public static var menuTrack(default, null):String = '';

	// ── Registro interno de sounds + baseVolume ───────────────────────────────

	/**
	 * Todos los FlxSounds registrados → su baseVolume (0.0–1.0).
	 * El volumen efectivo que se aplica a cada uno es:
	 *   snd.volume = muted ? 0 : masterVolume × baseVolume
	 */
	private static var _registry:Map<FlxSound, Float> = [];

	/** true if the mute was activado explicitly by toggleMute/setMuted(true). */
	private static var _explicitMute:Bool = false;

	// ── Constructor ───────────────────────────────────────────────────────────

	private function new()
	{
		super();
	}

	// ══════════════════════════════════════════════════════════════════════════
	// API — Registro de sounds
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Registra un FlxSound para que CoreAudio gestione su volumen.
	 * @param snd        El sound a registrar.
	 * @param baseVolume Volumen local deseado (0.0–1.0). Default: 1.0.
	 */
	public static function register(snd:FlxSound, baseVolume:Float = 1.0):Void
	{
		if (snd == null) return;
		_registry.set(snd, Math.max(0, Math.min(1, baseVolume)));
		_applyTo(snd);
	}

	/** Elimina un FlxSound del registro. */
	public static function unregister(snd:FlxSound):Void
	{
		if (snd == null) return;
		_registry.remove(snd);
	}

	/** Cambia el baseVolume de un sound ya registrado y lo aplica. */
	public static function setBaseVolume(snd:FlxSound, baseVolume:Float):Void
	{
		if (snd == null || !_registry.exists(snd)) return;
		_registry.set(snd, Math.max(0, Math.min(1, baseVolume)));
		_applyTo(snd);
	}

	/** Returns the baseVolume of a sound registered (1.0 if no is in the registry). */
	public static function getBaseVolume(snd:FlxSound):Float
	{
		if (snd == null) return 0.0;
		return _registry.exists(snd) ? _registry.get(snd) : 1.0;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// API — Gameplay (instrumental + vocales)
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Registra the instrumental of the song.
	 * Asigna el sound a FlxG.sound.music (Flixel lo gestiona fuera de la list).
	 * no it adds to FlxG.sound.list for avoid that Flixel it procese dos veces.
	 * @param snd  FlxSound cargado y pausado (null → no-op).
	 */
	public static function setInst(snd:Null<FlxSound>):Void
	{
		_unregisterInst();
		if (snd == null) return;

		inst = snd;
		FlxG.sound.music = snd;
		register(snd, 1.0); // baseVolume 1.0 — _applyTo it pondrá to masterVolume×1.0
	}

	/**
	 * Adds a track of vocales.
	 * @param key  Nombre del personaje ('bf', 'dad', etc.)
	 * @param snd  FlxSound cargado y pausado.
	 */
	public static function addVocal(key:String, snd:Null<FlxSound>):Void
	{
		if (snd == null) return;
		removeVocal(key);
		vocals.set(key, snd);
		_ensureInList(snd);
		register(snd, 1.0); // baseVolume 1.0 — PlayState no necesita sobreescribir .volume
	}

	/** Elimina y desregistra un vocal por clave. */
	public static function removeVocal(key:String):Void
	{
		final snd = vocals.get(key);
		if (snd == null) return;
		if (snd.alive) snd.stop();   // guarda contra FlxSounds ya destruidos
		unregister(snd);
		FlxG.sound.list.remove(snd, false);
		vocals.remove(key);
	}

	/** Elimina y desregistra todos los vocales. */
	public static function clearVocals():Void
	{
		for (_ => snd in vocals)
		{
			if (snd == null) continue;
			if (snd.alive) snd.stop();
			unregister(snd);
			FlxG.sound.list.remove(snd, false);
		}
		vocals.clear();
	}

	/**
	 * Limpia todo el estado de audio antes de cambiar de mod.
	 * Detiene y desregistra el inst, las voces y todos los sonidos registrados.
	 * Llamar justo antes de hacer switchState/resetGame al cambiar de mod.
	 */
	public static function flushForModSwitch():Void
	{
		// Parar y limpiar inst
		_unregisterInst();

		// Parar y limpiar voces
		clearVocals();

		// Parar music of menu
		_stopMenuInternal();
		menuTrack = '';

		// Vaciar the registry — any FlxSound that siga ahí is of the previous session
		for (snd => _ in _registry)
		{
			try { if (snd != null && snd.alive) snd.stop(); } catch (_) {}
		}
		_registry.clear();
	}

	/** Inicia el instrumental al volumen maestro actual. */
	public static function playInst():Void
	{
		if (inst == null) return;
		setBaseVolume(inst, 1.0);
		_applyTo(inst);
		_play(inst);
	}

	/** Inicia todos los vocales. */
	public static function playVocals():Void
	{
		for (_ => snd in vocals)
		{
			if (snd == null) continue;
			setBaseVolume(snd, 1.0);
			_applyTo(snd);
			_play(snd);
		}
	}

	/** Inicia instrumental + vocales. */
	public static function playAll():Void
	{
		playInst();
		playVocals();
	}

	/** Pausa instrumental + vocales. */
	public static function pauseAll():Void
	{
		if (inst != null) inst.pause();
		for (_ => snd in vocals) if (snd != null) snd.pause();
	}

	/** Reanuda instrumental + vocales sin reinicializar el backend. */
	public static function resumeAll():Void
	{
		if (inst != null && !inst.playing) inst.resume();
		for (_ => snd in vocals) if (snd != null && !snd.playing) snd.resume();
	}

	/**
	 * Resync: ajusta el tiempo de vocales al del instrumental.
	 * Usa pause()+time+resume() → CERO FPS drop (no reinicia el backend).
	 */
	public static function resync():Void
	{
		if (inst == null) return;
		if (!inst.playing) inst.resume();
		final t:Float = inst.time;
		funkin.data.Conductor.songPosition = t;
		for (_ => snd in vocals)
		{
			if (snd == null) continue;
			final was = snd.playing;
			snd.pause();
			snd.time = t;
			if (was) snd.resume();
		}
	}

	/** Mueve todos los sounds a un timestamp. */
	public static function syncTime(ms:Float):Void
	{
		if (inst != null) inst.time = ms;
		for (_ => snd in vocals) if (snd != null) snd.time = ms;
	}

	/** Detiene y desregistra instrumental + vocales. */
	public static function stopAll():Void
	{
		_unregisterInst();
		clearVocals();
	}

	// ── Volumen de gameplay ───────────────────────────────────────────────────

	/** Cambia el baseVolume del instrumental (0.0–1.0). */
	public static function setInstVolume(v:Float):Void
	{
		if (inst != null) setBaseVolume(inst, v);
	}

	/** Cambia el baseVolume de todos los vocales. */
	public static function setVocalsVolume(v:Float):Void
	{
		for (_ => snd in vocals) if (snd != null) setBaseVolume(snd, v);
	}

	// ══════════════════════════════════════════════════════════════════════════
	// API — Menu
	// ══════════════════════════════════════════════════════════════════════════

	/** Reproduce a track of menu. */
	public static function playMenu(track:String, volume:Float = 1.0,
		forceRestart:Bool = false, loop:Bool = true):Void
	{
		if (track == null || track.trim() == '') return;
		if (!forceRestart && menuTrack == track
			&& FlxG.sound.music != null && FlxG.sound.music.playing)
			return;

		_stopMenuInternal();
		menuTrack = track;

		final asset = Paths.loadMusic(track);
		if (asset != null)
			FlxG.sound.playMusic(asset, 1.0, loop);
		else
			FlxG.sound.playMusic(Paths.music(track), 1.0, loop);

		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.persist = true;
			_ensureInList(FlxG.sound.music);
			register(FlxG.sound.music, volume);   // baseVolume = the "volumen of menu"
		}
	}

	/** Igual que playMenu() pero con fade-in. */
	public static function playMenuFade(track:String, targetVolume:Float = 0.7,
		fadeDuration:Float = 4.0, forceRestart:Bool = false):Void
	{
		if (track == null || track.trim() == '') return;
		if (!forceRestart && menuTrack == track
			&& FlxG.sound.music != null && FlxG.sound.music.playing)
			return;

		_stopMenuInternal();
		menuTrack = track;

		final asset = Paths.loadMusic(track);
		if (asset != null) FlxG.sound.playMusic(asset, 1.0);
		else               FlxG.sound.playMusic(Paths.music(track), 1.0);

		if (FlxG.sound.music == null) return;
		FlxG.sound.music.persist = true;
		_ensureInList(FlxG.sound.music);

		// Registrar con baseVolume=0 y hacer fade manual sobre el baseVolume
		register(FlxG.sound.music, 0.0);
		if (!FlxG.sound.music.playing) FlxG.sound.music.play();

		if (masterVolume <= 0.0 || muted)
		{
			// Volumen global silenciado: poner baseVolume al target directamente
			// para que suene en cuanto el usuario suba el volumen.
			setBaseVolume(FlxG.sound.music, targetVolume);
		}
		else
		{
			// Fade manual: animar el baseVolume de 0 → targetVolume
			_fadeInSound(FlxG.sound.music, targetVolume, fadeDuration);
		}
	}

	/** For the music of menu. */
	public static function stopMenu():Void
	{
		_stopMenuInternal();
		menuTrack = '';
	}

	/** true if the track of menu indicada is sonando. */
	public static inline function isMenuPlaying(track:String):Bool
		return menuTrack == track && FlxG.sound.music != null && FlxG.sound.music.playing;

	/**
	 * Reproduce a FlxSound already loaded as music active (for previews in Freeplay
	 * u otros casos donde el caller ya tiene el FlxSound listo).
	 * Stops the music previous, registra the new sound in CoreAudio and it
	 * adds to FlxG.sound.list for that Flixel it pause/reanude automatically.
	 *
	 * @param snd         FlxSound already loaded. If is null, only for the music previous.
	 * @param baseVolume  Volumen local (0.0–1.0). The volumen efectivo will be masterVolume×baseVolume.
	 * @param loop        If true, the music hace loop.
	 */
	public static function playPreloadedMusic(snd:Null<FlxSound>, baseVolume:Float = 1.0, loop:Bool = true):Void
	{
		_stopMenuInternal();
		if (snd == null) return;

		menuTrack = '__preview__';
		FlxG.sound.music = snd;
		FlxG.sound.music.persist = true;
		FlxG.sound.music.looped = loop;
		_ensureInList(snd);
		register(snd, baseVolume);
		if (!snd.playing) snd.play();
	}

	// ══════════════════════════════════════════════════════════════════════════
	// play() public — without FPS drop in targets nativos
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Inicia un FlxSound directamente.
	 * En targets nativos (OpenAL): play() directo, sin tocar stage.frameRate.
	 * En Flash: solo baja FPS la primera vez (warm-up de backend).
	 */
	public static function play(snd:FlxSound):Void
	{
		if (snd == null) return;
		#if flash
		_warmPlayFlash(snd);
		#else
		try snd.play() catch (e:Dynamic) trace('[CoreAudio] play() error: $e');
		#end
	}

	// ══════════════════════════════════════════════════════════════════════════
	// Save / Load del volumen (independiente de FlxG.sound)
	// ══════════════════════════════════════════════════════════════════════════

	/** Guarda masterVolume y muted en FlxG.save. */
	public static function saveVolume():Void
	{
		// Guardamos el volumen REAL (antes del mute) para que al cargar
		// podamos restaurar correctamente aunque estuviera muteado.
		FlxG.save.data.coreVolume  = masterVolume;
		FlxG.save.data.coreMuted   = _explicitMute;
		FlxG.save.flush();
	}

	/** Carga masterVolume y muted desde FlxG.save. */
	public static function loadVolume():Void
	{
		final savedVol:Float = (FlxG.save.data.coreVolume != null)
			? FlxG.save.data.coreVolume : 1.0;
		masterVolume  = Math.max(0, Math.min(1, savedVol));
		_explicitMute = (FlxG.save.data.coreMuted == true);
		muted         = _explicitMute || (masterVolume <= 0.0);
		// No callr _applyAll() here: still no there is sounds registered in the boot.
		trace('[CoreAudio] Loaded: vol=${masterVolume} muted=${muted}');
	}

	// ══════════════════════════════════════════════════════════════════════════
	// Internals
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Aplica el volumen a un FlxSound concreto.
	 *
	 * Flixel calcula el volumen efectivo como:
	 *   transform = FlxG.sound.volume × group.volume × snd._volume
	 *
	 * As ahora FlxG.sound.volume = masterVolume (no 1.0), here only
	 * necesitamos fijar snd._volume = base. El resultado final es:
	 *   transform = masterVolume × 1.0 × base = masterVolume × base  ✓
	 *
	 * This is applies to music and vocales (that no are in FlxG.sound.list
	 * and by tanto no reciben the update of FlxG.sound.volume automatically).
	 */
	private static function _applyTo(snd:FlxSound):Void
	{
		if (snd == null) return;
		final base = _registry.exists(snd) ? _registry.get(snd) : 1.0;

		// FIX: doble-volumen in music / mute roto
		// ─────────────────────────────────────────────────────────────────────
		// The music vive in defaultMusicGroup (FlxG.sound.music), that Flixel
		// gestiona con su propio FlxSoundGroup.  El volumen efectivo de
		// cualquier FlxSound se calcula en updateTransform():
		//
		//   effective = FlxG.sound.volume  ← masterVolume (nosotros lo controlamos)
		//             × group.volume       ← 1.0 (defaultMusicGroup sin tocar)
		//             × snd._volume        ← lo que ponemos con snd.volume
		//
		// ANTES: snd.volume = masterVolume × base
		//   → effective = masterVolume × 1.0 × (masterVolume × base)
		//               = masterVolume²  × base   ← DOBLE appliesción
		//   to vol=0.7 the music sonaba to 0.49 in lugar of 0.70.
		//   Con muted=true, FlxG.sound.volume = 0, pero snd.volume
		//   is seteaba to 0 also → to the desmutear snd.volume seguía in 0
		//   until the next _applyAll() → is oía a frame of silencio
		//   extra and in race conditions the music no arrancaba.
		//
		// AHORA: snd.volume = base  (solo baseVolume, sin masterVolume)
		//   → effective = masterVolume × 1.0 × base   ← correcto
		//   Mute: FlxG.sound.volume = 0 → effective = 0 para todos los sounds
		//   sin necesidad de tocar snd.volume individualmente.
		// ─────────────────────────────────────────────────────────────────────
		if (muted)
			snd.volume = 0.0;  // silencio explicit by if defaultMusicGroup ignora FlxG.sound.volume
		else
			snd.volume = base; // FlxG.sound.volume = masterVolume already actúa of multiplier

		// Force appliesción inmediata to the backend OpenAL/SDL.
		// Without this, FlxSound.updateTransform() only is call in the next frame
		// de audio → hay un delay audible al mutear o bajar el volumen a 0.
		@:privateAccess snd.updateTransform();
	}

	/** Aplica el volumen efectivo a todos los sounds registrados. */
	private static function _applyAll():Void
	{
		for (snd => _ in _registry) _applyTo(snd);
	}

	private static function _unregisterInst():Void
	{
		if (inst == null) return;
		if (inst.alive) inst.stop();
		unregister(inst);
		// El inst vive en FlxG.sound.music, no en FlxG.sound.list — no hay que removarlo de la list.
		if (FlxG.sound.music == inst) FlxG.sound.music = null;
		inst = null;
	}

	private static function _stopMenuInternal():Void
	{
		if (FlxG.sound.music != null)
		{
			unregister(FlxG.sound.music);
			FlxG.sound.list.remove(FlxG.sound.music, false);
			FlxG.sound.music.persist = false;
			FlxG.sound.music.stop();
			FlxG.sound.music = null;   // evitar referencias fantasma al cambiar state
		}
	}

	/** Guarantees that the sound is in FlxG.sound.list (for pause/resume of Flixel). */
	private static inline function _ensureInList(snd:FlxSound):Void
	{
		if (snd != null && !FlxG.sound.list.members.contains(snd))
			FlxG.sound.list.add(snd);
	}

	/** Llama play() sin manipular FPS (OpenAL no lo necesita). */
	private static inline function _play(snd:FlxSound):Void
	{
		try snd.play() catch (e:Dynamic) trace('[CoreAudio] _play error: $e');
	}

	// ── Fade manual over baseVolume (for menu fade-in) ─────────────────────

	private static var _fadeSound:Null<FlxSound>   = null;
	private static var _fadeTarget:Float            = 0.0;
	private static var _fadeDuration:Float          = 1.0;
	private static var _fadeElapsed:Float           = 0.0;

	private static function _fadeInSound(snd:FlxSound, target:Float, duration:Float):Void
	{
		_fadeSound    = snd;
		_fadeTarget   = target;
		_fadeDuration = duration;
		_fadeElapsed  = 0.0;
	}

	private function _tickFade(elapsed:Float):Void
	{
		if (_fadeSound == null) return;
		_fadeElapsed += elapsed;
		final t = Math.min(_fadeElapsed / _fadeDuration, 1.0);
		final cur = _fadeTarget * t;
		setBaseVolume(_fadeSound, cur);
		if (t >= 1.0) _fadeSound = null;
	}

	// ── Flash warm-up (solo en target Flash) ─────────────────────────────────

	#if flash
	private static var _flashWarmed:Bool = false;
	private static function _warmPlayFlash(snd:FlxSound):Void
	{
		if (_flashWarmed) { try snd.play() catch (_:Dynamic) {}; return; }
		final s = openfl.Lib.current.stage;
		final fps = s.frameRate;
		s.frameRate = 20;
		try snd.play() catch (_:Dynamic) {};
		_flashWarmed = true;
		haxe.Timer.delay(function() { s.frameRate = fps; }, 200);
	}
	#end

	// ── Plugin update ─────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		// Tick of fade-in manual (menu).
		_tickFade(elapsed);
		// Mantener FlxG.sound.volume sincronizado con masterVolume.
		// Some code external (FlxGame, addons) podría cambiarlo.
		final expectedVol:Float = muted ? 0.0 : masterVolume;
		if (FlxG.sound.volume != expectedVol) FlxG.sound.volume = expectedVol;
		if (FlxG.sound.muted)                 FlxG.sound.muted  = false;
	}

	override public function destroy():Void
	{
		_self = null;
		_sig  = null;
		super.destroy();
	}
}
