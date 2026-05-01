package funkin.data.charts;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
import haxe.Json;

// Importar sub-tipos del módulo ChartData.hx explícitamente.
import funkin.data.charts.ChartData.ChartNote;
import funkin.data.charts.ChartData.ChartBPMChange;

/**
 * ChartLoader — Punto de entrada unificado para cargar charts de cualquier formato.
 *
 * Detecta automáticamente el formato por extensión y, para .json, por contenido:
 *   .osu         → OsuManiaParser
 *   .sm / .ssc   → StepManiaParser
 *   .json        → CodenameChartParser  (si contiene "codenameChart":true)
 *
 * ─── Uso básico ──────────────────────────────────────────────────────────────
 *
 *   var data = ChartLoader.load('mods/mymod/songs/bopeebo/hard.json');
 *   var data = ChartLoader.load('mods/mymod/charts/song.osu', 'Hard');
 *   var data = ChartLoader.load('mods/mymod/charts/song.sm',  'Challenge');
 *
 *   if (data != null) {
 *     var song = ChartConverter.toSwagSong(data);
 *     PlayState.SONG = song;
 *     FlxG.switchState(new PlayState());
 *   }
 */
class ChartLoader
{
	// ── API principal ──────────────────────────────────────────────────────

	/**
	 * Carga un archivo de chart detectando su formato.
	 *
	 * @param path        Ruta al archivo de chart.
	 * @param difficulty  Dificultad a activar (null = primera disponible).
	 * @return            ChartData listo para usar, o null si hay error.
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

			case 'json':
				// Detectar si es un chart Codename (contiene "codenameChart":true).
				// Se lee el JSON de forma ligera antes de pasarlo al parser completo.
				_loadJson(path, difficulty);

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
	 * Para .json la comprobación real ocurre al leer el archivo.
	 */
	public static function isSupported(path:String):Bool
	{
		var ext = _ext(path);
		return ext == 'osu' || ext == 'sm' || ext == 'ssc' || ext == 'json';
	}

	// ── Helpers ────────────────────────────────────────────────────────────

	static function _ext(path:String):String
	{
		var dot = path.lastIndexOf('.');
		if (dot < 0) return '';
		return path.substring(dot + 1).toLowerCase();
	}

	#if sys
	static function _loadJson(path:String, ?difficulty:String):Null<ChartData>
	{
		var content:String;
		try { content = File.getContent(path); }
		catch (e:Dynamic)
		{
			trace('[ChartLoader] No se pudo leer "$path": $e');
			return null;
		}

		var parsed:Dynamic;
		try { parsed = Json.parse(content); }
		catch (e:Dynamic)
		{
			trace('[ChartLoader] JSON inválido en "$path": $e');
			return null;
		}

		// Formato Codename Engine
		if (Reflect.field(parsed, 'codenameChart') == true)
			return CodenameChartParser.fromString(content, difficulty);

		// Aquí puedes añadir más formatos JSON en el futuro (Psych, V-Slice, etc.)
		trace('[ChartLoader] El archivo JSON "$path" no tiene un formato reconocido.');
		return null;
	}
	#end
}
