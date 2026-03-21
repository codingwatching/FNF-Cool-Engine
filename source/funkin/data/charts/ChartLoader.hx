package funkin.data.charts;

#if sys
import sys.FileSystem;
#end

// Importar sub-tipos del módulo ChartData.hx explícitamente.
import funkin.data.charts.ChartData.ChartNote;
import funkin.data.charts.ChartData.ChartBPMChange;

/**
 * ChartLoader — Punto de entrada unificado para cargar charts de cualquier formato.
 *
 * Detecta automáticamente el formato por la extensión del archivo y usa
 * el parser correcto: OsuManiaParser (.osu), StepManiaParser (.sm / .ssc).
 *
 * ─── Uso básico ──────────────────────────────────────────────────────────────
 *
 *   // Detecta formato automáticamente
 *   var data = ChartLoader.load('mods/mymod/charts/song.osu');
 *   var data = ChartLoader.load('mods/mymod/charts/song.sm', 'Hard');
 *   var data = ChartLoader.load('mods/mymod/charts/song.ssc', 'Challenge');
 *
 *   // Convertir a SwagSong y reproducir
 *   if (data != null) {
 *     var song = ChartConverter.toSwagSong(data, { scrollSpeed: 2.5 });
 *     PlayState.SONG = song;
 *     FlxG.switchState(new PlayState());
 *   }
 *
 * ─── Uso desde HScript ───────────────────────────────────────────────────────
 *
 *   // En un script de mod:
 *   var data = ChartLoader.load('mods/mymod/charts/song.osu');
 *   if (data != null) {
 *     trace('Título: ' + data.title);
 *     trace('BPM: '    + data.bpm);
 *     trace('Notas: '  + data.notes.length);
 *
 *     var song = ChartConverter.toSwagSong(data);
 *     PlayState.SONG = song;
 *   }
 *
 * ─── Uso desde Lua ───────────────────────────────────────────────────────────
 *
 *   local data = ChartLoader.load("mods/mymod/charts/song.sm", "Hard")
 *   if data ~= nil then
 *     log("Título: " .. data.title)
 *     log("Notas: "  .. #data.notes)
 *     local song = ChartConverter.toSwagSong(data)
 *     PlayState.SONG = song
 *   end
 *
 * ─── Dificultades disponibles ─────────────────────────────────────────────────
 *
 *   var data = ChartLoader.load('song.sm');
 *   var diffs = ChartLoader.getDifficulties(data);
 *   // ["Easy", "Normal", "Hard", "Challenge"]
 *
 *   // Cambiar dificultad activa sin releer el archivo
 *   data = ChartLoader.selectDifficulty(data, 'Hard');
 */
class ChartLoader
{
	// ── API principal ──────────────────────────────────────────────────────

	/**
	 * Carga un archivo de chart detectando su formato por la extensión.
	 *
	 * Formatos soportados:
	 *   .osu  → osu!mania  (OsuManiaParser)
	 *   .sm   → StepMania legacy (StepManiaParser)
	 *   .ssc  → StepMania 5 extendido (StepManiaParser)
	 *
	 * @param path        Ruta al archivo de chart.
	 * @param difficulty  Dificultad a activar (null = primera disponible).
	 * @return            ChartData listo para usar con ChartConverter, o null.
	 */
	public static function load(path:String, ?difficulty:String):Null<ChartData>
	{
		#if sys
		if (path == null || !FileSystem.exists(path))
		{
			trace('[ChartLoader] Archivo no encontrado: "$path".');
			return null;
		}

		var ext = _ext(path);
		return switch (ext)
		{
			case 'osu':
				OsuManiaParser.fromFile(path, difficulty);

			case 'sm':
				StepManiaParser.fromFile(path, difficulty);

			case 'ssc':
				StepManiaParser.fromFile(path, difficulty);

			default:
				trace('[ChartLoader] Extensión no soportada: ".$ext" en "$path".');
				null;
		};
		#else
		trace('[ChartLoader] load() requiere target sys.');
		return null;
		#end
	}

	/**
	 * Devuelve la lista de nombres de dificultad disponibles en un ChartData.
	 *
	 * @param data  ChartData devuelto por load() u otro parser.
	 * @return      Array de nombres (e.g. ["Easy", "Normal", "Hard"]).
	 */
	public static function getDifficulties(data:ChartData):Array<String>
	{
		if (data == null || data.difficulties == null) return [];
		var names:Array<String> = [];
		for (k in data.difficulties.keys()) names.push(k);
		return names;
	}

	/**
	 * Cambia la dificultad activa en un ChartData existente sin releer el archivo.
	 * Actualiza data.notes y data.activeDifficulty.
	 *
	 * @param data        ChartData a modificar.
	 * @param difficulty  Nombre de la nueva dificultad.
	 * @return            El mismo objeto data modificado, o null si no existe esa dif.
	 */
	public static function selectDifficulty(data:ChartData,
		difficulty:String):Null<ChartData>
	{
		if (data == null) return null;
		if (!data.difficulties.exists(difficulty))
		{
			trace('[ChartLoader] Dificultad "$difficulty" no existe. Disponibles: '
				+ getDifficulties(data).join(', '));
			return null;
		}
		data.notes            = data.difficulties.get(difficulty);
		data.activeDifficulty = difficulty;
		return data;
	}

	/**
	 * Comprueba si una ruta corresponde a un formato de chart soportado.
	 */
	public static function isSupported(path:String):Bool
	{
		var ext = _ext(path);
		return ext == 'osu' || ext == 'sm' || ext == 'ssc';
	}

	// ── Helpers ────────────────────────────────────────────────────────────

	static function _ext(path:String):String
	{
		var dot = path.lastIndexOf('.');
		if (dot < 0) return '';
		return path.substring(dot + 1).toLowerCase();
	}
}
