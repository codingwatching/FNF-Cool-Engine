package funkin.data;

import haxe.Json;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * WeekFile — sistema de semanas para Story Mode.
 *
 * ─── Estructura de carpetas ───────────────────────────────────────────────────
 *
 *   assets/data/storymenu/weeks/          ← base del juego
 *     week1.json
 *     week2.json
 *     ...
 *
 *   mods/{mod}/data/storymenu/weeks/      ← mod override / extensión
 *     myWeek.json
 *
 * ─── Formato de cada week JSON ───────────────────────────────────────────────
 *
 * {
 *   "id":             "week1",
 *   "weekName":       "Daddy Dearest",
 *   "weekPath":       "menu/storymenu/titles/week1",
 *   "weekCharacters": ["dad", "bf", "gf"],
 *   "weekSongs":      ["Bopeebo", "Fresh", "Dadbattle"],
 *   "color":          "0xFFAF66CE",
 *   "locked":         false,
 *   "order":          1
 * }
 *
 * ─── Compatibilidad hacia atrás ───────────────────────────────────────────────
 *
 * Si la carpeta weeks/ no existe, se lee el antiguo songList.json y se
 * extraen las semanas que tenían weekName o datos de story mode.
 * Los archivos legacy NO se modifican.
 *
 * @version 1.0.0
 */
typedef WeekData =
{
	/** Identificador único (nombre del archivo sin extensión). */
	@:optional var id             : String;
	var weekName        : String;
	@:optional var weekPath       : String;
	/** [opponentChar, bfChar, gfChar] */
	@:optional var weekCharacters : Array<String>;
	var weekSongs       : Array<String>;
	/** Color hex de la barra amarilla, ej: "0xFFAF66CE" */
	@:optional var color          : String;
	@:optional var locked         : Bool;
	/** Orden de aparición. Si no se especifica se usa el orden de lectura. */
	@:optional var order          : Int;
}

class WeekFile
{
	static inline final WEEKS_DIR_BASE = 'assets/data/storymenu/weeks';
	static inline final WEEKS_DIR_MOD  = 'data/storymenu/weeks';

	// ── Load ──────────────────────────────────────────────────────────────────

	/**
	 * Carga TODAS las semanas en orden (base + mod).
	 * El mod puede añadir semanas nuevas o sobreescribir las base por id.
	 * Las semanas se ordenan por `order` (si existe) o por orden de lectura.
	 */
	public static function loadAll():Array<WeekData>
	{
		final byId:Map<String, WeekData> = new Map();
		final order:Array<String> = [];

		#if sys
		// ── 1. Base game weeks ────────────────────────────────────────────────
		_readFolder(WEEKS_DIR_BASE, byId, order);

		// ── 2. Mod weeks (añade o sobreescribe por id) ────────────────────────
		if (mods.ModManager.isActive())
			_readFolder('${mods.ModManager.modRoot()}/$WEEKS_DIR_MOD', byId, order);

		// ── 3. Fallback: convertir songList.json legacy si no hay weeks ────────
		if (Lambda.count(byId) == 0)
			return _fromLegacy();
		#end

		// Construir array final ordenado
		var weeks:Array<WeekData> = [for (id in order) if (byId.exists(id)) byId.get(id)];

		// Ordenar por campo `order` si está presente en alguna semana
		final hasOrder = Lambda.exists(weeks, w -> w.order != null);
		if (hasOrder)
			weeks.sort((a, b) -> (a.order ?? 999) - (b.order ?? 999));

		trace('[WeekFile] ${weeks.length} weeks loaded.');
		return weeks;
	}

	/**
	 * Carga una semana específica por id (nombre de archivo sin .json).
	 */
	public static function loadById(id:String):Null<WeekData>
	{
		#if sys
		// Mod primero
		if (mods.ModManager.isActive())
		{
			final p = '${mods.ModManager.modRoot()}/$WEEKS_DIR_MOD/$id.json';
			if (FileSystem.exists(p)) return _parse(File.getContent(p), id);
		}
		// Base
		final p = '$WEEKS_DIR_BASE/$id.json';
		if (FileSystem.exists(p)) return _parse(File.getContent(p), id);
		#end
		return null;
	}

	// ── Save ──────────────────────────────────────────────────────────────────

	/**
	 * Guarda o actualiza una semana en disco.
	 * Siempre escribe en el mod activo si hay uno, si no en base.
	 */
	public static function save(week:WeekData):Bool
	{
		#if (sys && desktop)
		if (week.id == null || week.id == '')
		{
			trace('[WeekFile] Cannot save week with no id');
			return false;
		}
		try
		{
			final dir = _writeDir();
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			final path = '$dir/${week.id}.json';
			File.saveContent(path, Json.stringify(week, null, '\t'));
			trace('[WeekFile] Saved week "${week.id}" → $path');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[WeekFile] Save error: $e');
			return false;
		}
		#else
		return false;
		#end
	}

	/** Directorio de escritura (mod si activo, si no base). */
	static function _writeDir():String
	{
		#if sys
		if (mods.ModManager.isActive())
			return '${mods.ModManager.modRoot()}/$WEEKS_DIR_MOD';
		#end
		return WEEKS_DIR_BASE;
	}

	// ── Internos ──────────────────────────────────────────────────────────────

	#if sys
	static function _readFolder(folder:String, byId:Map<String, WeekData>, order:Array<String>):Void
	{
		if (!FileSystem.exists(folder) || !FileSystem.isDirectory(folder)) return;
		final files = FileSystem.readDirectory(folder);
		files.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		for (file in files)
		{
			if (!file.endsWith('.json')) continue;
			try
			{
				final id   = file.substr(0, file.length - 5);
				final week = _parse(File.getContent('$folder/$file'), id);
				if (week == null) continue;
				if (!byId.exists(id)) order.push(id);
				byId.set(id, week);
			}
			catch (e:Dynamic) { trace('[WeekFile] Error reading $folder/$file: $e'); }
		}
	}

	/**
	 * Fallback: construye semanas desde el antiguo songList.json.
	 * Solo se incluyen entradas que tenían `weekName` o datos de personajes/story.
	 */
	static function _fromLegacy():Array<WeekData>
	{
		var raw:String = null;
		if (mods.ModManager.isActive())
		{
			final p = '${mods.ModManager.modRoot()}/songs/songList.json';
			if (FileSystem.exists(p)) raw = File.getContent(p);
		}
		if (raw == null)
		{
			final p = 'assets/songs/songList.json';
			if (FileSystem.exists(p)) raw = File.getContent(p);
		}
		if (raw == null)
			try { raw = lime.utils.Assets.getText(Paths.jsonSong('songList')); } catch (_) {}

		if (raw == null || raw.trim() == '') return [];

		try
		{
			final legacy:Dynamic = Json.parse(raw);
			final weeks:Array<Dynamic> = cast (Reflect.field(legacy, 'songsWeeks') ?? []);
			final result:Array<WeekData> = [];
			for (i in 0...weeks.length)
			{
				final w:Dynamic = weeks[i];
				final ws:Array<String> = cast (Reflect.field(w, 'weekSongs') ?? []);
				if (ws.length == 0) continue;

				// Filtrar por showInStoryMode si existe (backwards compat)
				var storySongs:Array<String> = [];
				final sim:Array<Dynamic> = cast (Reflect.field(w, 'showInStoryMode') ?? []);
				for (j in 0...ws.length)
				{
					final show = (sim != null && j < sim.length) ? (sim[j] == true) : true;
					if (show) storySongs.push(ws[j]);
				}
				if (storySongs.length == 0) continue;

				final cl:Array<String> = cast (Reflect.field(w, 'color') ?? []);
				result.push({
					id:             'week${i + 1}',
					weekName:       Reflect.field(w, 'weekName') ?? 'Week ${i + 1}',
					weekPath:       Reflect.field(w, 'weekPath') ?? '',
					weekCharacters: cast (Reflect.field(w, 'weekCharacters') ?? ['', 'bf', 'gf']),
					weekSongs:      storySongs,
					color:          (cl != null && cl.length > 0) ? cl[0] : '0xFFFFD900',
					locked:         Reflect.field(w, 'locked') == true,
					order:          i
				});
			}
			trace('[WeekFile] Converted ${result.length} weeks from legacy songList.json');
			return result;
		}
		catch (e:Dynamic)
		{
			trace('[WeekFile] Legacy parse error: $e');
			return [];
		}
	}
	#end

	static function _parse(raw:String, id:String):Null<WeekData>
	{
		try
		{
			final week:WeekData = cast Json.parse(raw);
			if (week.id == null || week.id == '') week.id = id;
			if (week.weekSongs == null) week.weekSongs = [];
			if (week.weekCharacters == null) week.weekCharacters = ['', 'bf', 'gf'];
			return week;
		}
		catch (e:Dynamic)
		{
			trace('[WeekFile] Parse error ($id): $e');
			return null;
		}
	}
}
