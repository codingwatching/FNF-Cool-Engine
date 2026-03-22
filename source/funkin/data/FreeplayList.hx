package funkin.data;

import haxe.Json;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * FreeplayList — formato de canciones para Freeplay.
 *
 * ─── Archivo: assets/songs/freeplayList.json ─────────────────────────────────
 *
 * {
 *   "songs": [
 *     {
 *       "name":      "bopeebo",
 *       "icon":      "icon-dad",
 *       "color":     "0xFFAF66CE",
 *       "bpm":       180,
 *       "artist":    "Kawai Sprite",
 *       "album":     "week1",
 *       "albumText": "week1-text",
 *       "group":     0
 *     }
 *   ]
 * }
 *
 * ─── Compatibilidad con songList.json ────────────────────────────────────────
 *
 * Si no existe freeplayList.json, se intenta leer el antiguo songList.json
 * and is converts to the formato new automatically (without escribir nada to disco).
 *
 * @version 1.0.0
 */
typedef FreeplayListData =
{
	var songs : Array<FreeplaySongEntry>;
}

typedef FreeplaySongEntry =
{
	var name   : String;
	@:optional var icon      : String;
	@:optional var color     : String;
	@:optional var bpm       : Float;
	@:optional var artist    : String;
	@:optional var album     : String;
	@:optional var albumText : String;
	/** Number of grupo (for organizar songs in freeplay). */
	@:optional var group     : Int;
}

class FreeplayList
{
	// ── Rutas ─────────────────────────────────────────────────────────────────

	static inline final FILE_NAME = 'freeplayList.json';

	/** Resuelve la ruta de freeplayList.json (mod primero, luego base). */
	public static function resolvePath():Null<String>
	{
		#if sys
		if (mods.ModManager.isActive())
		{
			final p = '${mods.ModManager.modRoot()}/songs/$FILE_NAME';
			if (FileSystem.exists(p)) return p;
		}
		final base = 'assets/songs/$FILE_NAME';
		if (FileSystem.exists(base)) return base;
		#end
		return null;
	}

	/** Ruta de escritura (mod activo si existe, si no base). */
	public static function writePath():String
	{
		#if sys
		if (mods.ModManager.isActive())
			return '${mods.ModManager.modRoot()}/songs/$FILE_NAME';
		#end
		return 'assets/songs/$FILE_NAME';
	}

	// ── Load ──────────────────────────────────────────────────────────────────

	/**
	 * Carga freeplayList.json.
	 * Si no existe, intenta convertir el antiguo songList.json al vuelo.
	 * Returns always a object valid (never null).
	 */
	public static function load():FreeplayListData
	{
		var raw:String = null;

		#if sys
		// 1. freeplayList.json del mod activo
		if (mods.ModManager.isActive())
		{
			final p = '${mods.ModManager.modRoot()}/songs/$FILE_NAME';
			if (FileSystem.exists(p)) raw = File.getContent(p);
		}

		// 2. freeplayList.json base
		if (raw == null)
		{
			final p = 'assets/songs/$FILE_NAME';
			if (FileSystem.exists(p)) raw = File.getContent(p);
		}

		// 3. Fallback: convertir songList.json al formato nuevo
		if (raw == null)
			return _fromLegacy();
		#end

		if (raw == null)
		{
			try   { raw = lime.utils.Assets.getText(Paths.jsonSong(FILE_NAME.replace('.json', ''))); }
			catch (_) {}
		}

		if (raw == null || raw.trim() == '')
			return { songs: [] };

		try
		{
			final parsed:FreeplayListData = cast Json.parse(raw);
			if (parsed.songs == null) parsed.songs = [];
			trace('[FreeplayList] Loaded ${parsed.songs.length} songs from $FILE_NAME');
			return parsed;
		}
		catch (e:Dynamic)
		{
			trace('[FreeplayList] Parse error: $e');
			return { songs: [] };
		}
	}

	// ── Save ──────────────────────────────────────────────────────────────────

	/** Guarda freeplayList.json. */
	public static function save(data:FreeplayListData):Bool
	{
		#if (sys && desktop)
		try
		{
			final path = writePath();
			final dir  = haxe.io.Path.directory(path);
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			File.saveContent(path, Json.stringify(data, null, '\t'));
			trace('[FreeplayList] Saved ${data.songs.length} songs → $path');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[FreeplayList] Save error: $e');
			return false;
		}
		#else
		return false;
		#end
	}

	/**
	 * Adds or updates a entry of song.
	 * If already exists a song with that name the updates, if no the adds.
	 */
	public static function upsert(data:FreeplayListData, entry:FreeplaySongEntry):FreeplayListData
	{
		final key = entry.name.toLowerCase();
		var found = false;
		for (i in 0...data.songs.length)
		{
			if (data.songs[i].name.toLowerCase() == key)
			{
				data.songs[i] = entry;
				found = true;
				break;
			}
		}
		if (!found) data.songs.push(entry);
		return data;
	}

	/** Elimina a song by nombre. */
	public static function remove(data:FreeplayListData, name:String):FreeplayListData
	{
		final key = name.toLowerCase();
		data.songs = data.songs.filter(s -> s.name.toLowerCase() != key);
		return data;
	}

	// ── Conversion from songList.json legacy ─────────────────────────────────

	/**
	 * Lee el antiguo songList.json y lo convierte al formato FreeplayListData.
	 * No escribe nada a disco. Los campos de story mode se ignoran.
	 */
	static function _fromLegacy():FreeplayListData
	{
		#if sys
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

		if (raw != null && raw.trim() != '')
		{
			try
			{
				final legacy:Dynamic = Json.parse(raw);
				final weeks:Array<Dynamic> = cast Reflect.field(legacy, 'songsWeeks') ?? [];
				final songs:Array<FreeplaySongEntry> = [];
				for (i in 0...weeks.length)
				{
					final w:Dynamic = weeks[i];
					final ws:Array<String>  = cast (Reflect.field(w, 'weekSongs') ?? []);
					final si:Array<String>  = cast (Reflect.field(w, 'songIcons') ?? []);
					final cl:Array<String>  = cast (Reflect.field(w, 'color')     ?? []);
					final bp:Array<Float>   = cast (Reflect.field(w, 'bpm')       ?? []);
					final sa:Array<Dynamic> = cast (Reflect.field(w, 'songArtists')   ?? []);
					final salb:Array<Dynamic> = cast (Reflect.field(w, 'songAlbums')  ?? []);
					final satx:Array<Dynamic> = cast (Reflect.field(w, 'songAlbumTexts') ?? []);
					final weekAlbum:String  = Reflect.field(w, 'album') ?? '';
					final weekAlbTx:String  = Reflect.field(w, 'albumText') ?? '';

					for (j in 0...ws.length)
					{
						final colorStr = (cl != null && cl.length > 0) ? cl[0] : '0xFFFFD900';
						songs.push({
							name:      ws[j],
							icon:      (si != null && j < si.length) ? si[j] : 'bf',
							color:     colorStr,
							bpm:       (bp != null && j < bp.length) ? bp[j] : 120.0,
							artist:    (sa != null && j < sa.length && sa[j] != null) ? Std.string(sa[j]) : '',
							album:     (salb != null && j < salb.length && salb[j] != null) ? Std.string(salb[j]) : weekAlbum,
							albumText: (satx != null && j < satx.length && satx[j] != null) ? Std.string(satx[j]) : weekAlbTx,
							group:     i
						});
					}
				}
				trace('[FreeplayList] Converted ${songs.length} songs from legacy songList.json');
				return { songs: songs };
			}
			catch (e:Dynamic) { trace('[FreeplayList] Legacy parse error: $e'); }
		}
		#end
		return { songs: [] };
	}
}
