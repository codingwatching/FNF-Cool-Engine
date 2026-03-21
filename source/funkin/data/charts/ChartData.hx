package funkin.data.charts;

/**
 * ChartData — Formato interno normalizado de chart importado.
 *
 * Todos los parsers externos (osu!mania, StepMania) convierten su formato
 * nativo a esta estructura antes de que el engine la procese.
 *
 * ─── Compatibilidad ──────────────────────────────────────────────────────────
 *
 *   La estructura está diseñada para ser convertida a SwagSong (formato FNF)
 *   con ChartConverter.toSwagSong(data), o usada directamente si el PlayState
 *   acepta ChartData en el futuro.
 *
 * ─── Campos de ChartData ─────────────────────────────────────────────────────
 *
 *   title       → Título de la canción
 *   artist      → Artista
 *   source      → "osu" | "stepmania" | "fnf"
 *   bpm         → BPM inicial
 *   bpmChanges  → Cambios de BPM a lo largo de la canción
 *   audioFile   → Ruta al archivo de audio (relativa al .osz/.sm)
 *   offset      → Offset en ms
 *   keyCount    → Número de carriles (4 para FNF, variable en osu/SM)
 *   difficulties → Mapa nombre→notas  { "Hard": [...], "Normal": [...] }
 *   notes       → Lista aplanada de notas de la dificultad seleccionada
 *
 * ─── Nota (ChartNote) ────────────────────────────────────────────────────────
 *
 *   time      → Tiempo en ms desde el inicio
 *   column    → Carril (0-indexed, izquierda a derecha)
 *   duration  → 0 si es nota normal; >0 si es hold (longitud en ms)
 *   type      → "normal" | "hold" | "roll" | "mine"
 */

typedef ChartData =
{
	/** Título de la canción. */
	var title:String;
	/** Artista. */
	var artist:String;
	/** Origen del chart: "osu" | "stepmania" | "fnf". */
	var source:String;
	/** BPM inicial. */
	var bpm:Float;
	/** Cambios de BPM a lo largo de la canción. */
	var bpmChanges:Array<ChartBPMChange>;
	/** Ruta al archivo de audio relativa al archivo de chart. */
	var audioFile:String;
	/** Offset global en ms (positivo = notas más tarde). */
	var offset:Float;
	/** Número de carriles (4 en FNF). */
	var keyCount:Int;
	/**
	 * Mapa de dificultades disponibles.
	 * Clave = nombre de dificultad ("Easy", "Normal", "Hard", "OsuHard", etc.)
	 * Valor = lista de notas de esa dificultad.
	 */
	var difficulties:Map<String, Array<ChartNote>>;
	/** Notas de la dificultad actualmente seleccionada. */
	var notes:Array<ChartNote>;
	/** Nombre de la dificultad actualmente activa. */
	var activeDifficulty:String;
	/** Metadatos adicionales según la fuente (nullable). */
	var ?meta:Dynamic;
}

typedef ChartNote =
{
	/** Tiempo de la nota en milisegundos desde el inicio de la canción. */
	var time:Float;
	/** Carril (columna), empezando en 0. */
	var column:Int;
	/** Duración en ms. 0 = nota normal; >0 = hold/long note. */
	var duration:Float;
	/** Tipo: "normal" | "hold" | "roll" | "mine" | "lift". */
	var type:String;
}

typedef ChartBPMChange =
{
	/** Tiempo en ms donde ocurre el cambio de BPM. */
	var time:Float;
	/** Nuevo BPM. */
	var bpm:Float;
	/** Beat donde ocurre (calculado). */
	var ?beat:Float;
}
