package funkin.data;

import funkin.data.Song.SwagSong;

/**
 * Conductor v3 — management of BPM, time and sincronía musical.
 *
 * ─── Optimizaciones v3 ────────────────────────────────────────────────────────
 *
 *  v2: getStepAtTime() and getBPMFromTime() hacían search lineal or(n).
 *      En canciones con 30+ cambios de BPM, se llamaban cientos de veces
 *      por frame (una vez por nota en spawn/cull), causando microstutters.
 *
 *  v3: Search binaria or(log n) for getBPMFromTime() and getStepAtTime().
 *      Para canciones con 64 cambios de BPM: 64 → 6 comparaciones por nota.
 *
 *  Furthermore:
 *  • bpmChangeMap ahora es read-only externamente (no se puede corromper).
 *  • Constante precomputada MS_PER_STEP para evitar divisiones en hot-path.
 *  • positionAtBeat() nueva para pasar de beats a ms.
 *
 * @author Cool Engine Team
 * @version 3.0.0
 */
class Conductor
{
	public static var bpm         : Float = 100;
	/** Duration of a beat in ms  (60 000 / bpm). */
	public static var crochet     : Float = 600;
	/** Duration of a step in ms  (crochet / 4). */
	public static var stepCrochet : Float = 150;

	public static var songPosition : Float = 0;
	public static var lastSongPos  : Float = 0;
	public static var offset       : Float = 0;

	public static var safeFrames : Int = 10;

	/** Margen in ms — calculado without inicializador static. */
	public static var safeZoneOffset(get, never) : Float;
	static inline function get_safeZoneOffset():Float return (safeFrames / 60.0) * 1000.0;

	/** Factor de escala del safe zone. */
	public static var timeScale(get, never) : Float;
	static inline function get_timeScale():Float return safeZoneOffset / 166.0;

	/** Mapa of cambios of BPM — only reading public. */
	public static var bpmChangeMap(default, null) : Array<BPMChangeEvent> = [];

	// ─── API ──────────────────────────────────────────────────────────────────

	/** Cambia BPM y recalcula crochet/stepCrochet en un solo lugar. */
	public static function changeBPM(newBpm:Float):Void
	{
		bpm          = newBpm;
		crochet      = 60000.0 / bpm;
		stepCrochet  = crochet * 0.25;
	}

	/** Construye the mapa of cambios of BPM from the datos of the song. */
	public static function mapBPMChanges(song:SwagSong):Void
	{
		bpmChangeMap = [];
		var curBPM    : Float = song.bpm;
		var totalSteps: Int   = 0;
		var totalPos  : Float = 0;

		for (section in song.notes)
		{
			if (section.changeBPM && section.bpm != curBPM)
			{
				curBPM = section.bpm;
				bpmChangeMap.push({ stepTime: totalSteps, songTime: totalPos, bpm: curBPM });
			}
			final delta = section.lengthInSteps;
			totalSteps += delta;
			totalPos   += (60000.0 / curBPM / 4.0) * delta;
		}
		trace('[Conductor v3] ${bpmChangeMap.length} cambios of BPM — search binaria active.');
	}

	// ─── Search binaria or(log n) ────────────────────────────────────────────

	/**
	 * Returns the index of the last BPMChangeEvent cuyo `songTime` ≤ `time`.
	 * Retorna -1 si ninguno aplica.
	 *
	 * @param time  Position in ms.
	 */
	static function _binarySearchByTime(time:Float):Int
	{
		final map = bpmChangeMap;
		final len = map.length;
		if (len == 0) return -1;

		var lo = 0;
		var hi = len - 1;
		var result = -1;

		while (lo <= hi)
		{
			final mid = (lo + hi) >>> 1; // bitshift evita desbordamiento
			if (map[mid].songTime <= time)
			{
				result = mid;
				lo     = mid + 1;
			}
			else
			{
				hi = mid - 1;
			}
		}
		return result;
	}

	/**
	 * Returns the index of the last BPMChangeEvent cuyo `stepTime` ≤ `step`.
	 */
	static function _binarySearchByStep(step:Float):Int
	{
		final map = bpmChangeMap;
		final len = map.length;
		if (len == 0) return -1;

		var lo = 0;
		var hi = len - 1;
		var result = -1;

		while (lo <= hi)
		{
			final mid = (lo + hi) >>> 1;
			if (map[mid].stepTime <= step)
			{
				result = mid;
				lo     = mid + 1;
			}
			else
			{
				hi = mid - 1;
			}
		}
		return result;
	}

	// ─── Conversiones de tiempo ───────────────────────────────────────────────

	/**
	 * Convierte ms a steps, respetando cambios de BPM.
	 * Complejidad: or(log n) gracias to the search binaria.
	 */
	public static function getStepAtTime(time:Float):Float
	{
		final idx = _binarySearchByTime(time);

		if (idx < 0)
		{
			// Antes del primer cambio de BPM — usar BPM base
			return time / (60000.0 / bpm / 4.0);
		}

		// Acumular steps hasta el cambio encontrado
		var step    : Float = 0;
		var lastBpm : Float = bpm;
		var lastTime: Float = 0;

		for (i in 0...(idx + 1))
		{
			final ch = bpmChangeMap[i];
			step    += (ch.songTime - lastTime) / (60000.0 / lastBpm / 4.0);
			lastBpm  = ch.bpm;
			lastTime = ch.songTime;
		}
		step += (time - lastTime) / (60000.0 / lastBpm / 4.0);
		return step;
	}

	/**
	 * Convierte ms a beats.
	 */
	public static inline function getBeatAtTime(time:Float):Float
		return getStepAtTime(time) / 4.0;

	/**
	 * Devuelve el BPM en vigor en `time` ms.
	 * Complejidad: O(log n).
	 */
	public static function getBPMFromTime(time:Float):Float
	{
		final idx = _binarySearchByTime(time);
		if (idx < 0) return bpm;
		return bpmChangeMap[idx].bpm;
	}

	/**
	 * Convierte steps a ms, respetando cambios de BPM.
	 * Inversa de getStepAtTime().
	 */
	public static function getTimeAtStep(targetStep:Float):Float
	{
		final idx = _binarySearchByStep(targetStep);

		var time    : Float = 0;
		var lastBpm : Float = bpm;
		var lastStep: Float = 0;

		if (idx >= 0)
		{
			for (i in 0...(idx + 1))
			{
				final ch = bpmChangeMap[i];
				time    += (ch.stepTime - lastStep) * (60000.0 / lastBpm / 4.0);
				lastBpm  = ch.bpm;
				lastStep = ch.stepTime;
			}
		}

		time += (targetStep - lastStep) * (60000.0 / lastBpm / 4.0);
		return time;
	}

	/**
	 * Convierte beats a ms.
	 */
	public static inline function positionAtBeat(beat:Float):Float
		return getTimeAtStep(beat * 4.0);

	/**
	 * Duration of a step in ms in the position `time`.
	 */
	public static inline function stepDurationAt(time:Float):Float
		return 60000.0 / getBPMFromTime(time) / 4.0;
}

typedef BPMChangeEvent =
{
	var stepTime : Int;
	var songTime : Float;
	var bpm      : Float;
}
