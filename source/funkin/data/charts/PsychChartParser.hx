package funkin.data.charts;

#if sys
import sys.io.File;
import sys.FileSystem;
#end
import haxe.Json;

/**
 * PsychChartParser — Lector de charts en formato Psych Engine (.json).
 *
 * ─── Formato Psych Engine ────────────────────────────────────────────────────
 *
 *   Archivo: songs/<name>/<difficulty>.json  (easy.json, normal.json, hard.json)
 *   O:       songs/<name>/<name>.json        (dificultad hard por defecto)
 *
 *   {
 *     "song": {
 *       "song":        "Bopeebo",
 *       "bpm":         150,
 *       "speed":       2.5,
 *       "needsVoices": true,
 *       "player1":     "bf",
 *       "player2":     "dad",
 *       "gfVersion":   "gf",
 *       "stage":       "stage",
 *       "notes": [
 *         {
 *           "sectionNotes":  [[time, col, holdLen], ...],
 *           "mustHitSection": true,
 *           "lengthInSteps": 16,
 *           "bpm":           150,
 *           "changeBPM":     false,
 *           "altAnim":       false
 *         }
 *       ],
 *       "events": [
 *         [time, [ ["eventName", val1, val2], ... ]]
 *       ]
 *     }
 *   }
 *
 *   sectionNotes columns:
 *     mustHitSection=true  → 0-3 = player,   4-7 = opponent
 *     mustHitSection=false → 0-3 = opponent, 4-7 = player
 *
 * ─── Uso ─────────────────────────────────────────────────────────────────────
 *
 *   var data = PsychChartParser.fromFile('songs/bopeebo/hard.json');
 *   // O cargar ambas dificultades del mismo directorio:
 *   var all  = PsychChartParser.fromDirectory('songs/bopeebo/');
 *
 *   // Ya tienes un SwagSong — puedes usarlo directamente:
 *   PlayState.SONG = data.meta.swagSong;
 *   FlxG.switchState(new PlayState());
 *
 *   // O convertirlo si necesitas el ChartData normalizado:
 *   var song = ChartConverter.toSwagSong(data);
 */
class PsychChartParser
{
	// ── API public ────────────────────────────────────────────────────────

	/**
	 * Carga un archivo JSON de Psych Engine.
	 *
	 * @param path        Ruta al .json.
	 * @param difficulty  Name to asignar (default = name of the file without extension).
	 * @return            ChartData, o null si falla.
	 */
	public static function fromFile(path:String, ?difficulty:String):Null<ChartData>
	{
		#if sys
		if (!FileSystem.exists(path))
		{
			trace('[Psych] Archivo no encontrado: $path');
			return null;
		}
		try
		{
			var raw  = File.getContent(path);
			var diff = difficulty ?? _diffFromPath(path);
			return fromString(raw, diff);
		}
		catch (e:Dynamic) { trace('[Psych] Error leyendo "$path": $e'); return null; }
		#else
		return null;
		#end
	}

	/**
	 * Load all the difficulties of a directorio of song Psych.
	 * Detecta automatically easy.json, normal.json, hard.json (and its variantes).
	 *
	 * @param dir   Ruta to the directorio of the song (and.g. "songs/bopeebo/").
	 * @return      ChartData con todas las dificultades cargadas, o null.
	 */
	public static function fromDirectory(dir:String):Null<ChartData>
	{
		#if sys
		if (!FileSystem.isDirectory(dir)) { trace('[Psych] Directorio no encontrado: $dir'); return null; }

		var diffs:Map<String, Array<ChartNote>> = new Map();
		var baseData:ChartData = null;

		for (file in FileSystem.readDirectory(dir))
		{
			if (!file.endsWith('.json')) continue;
			var full = '$dir/$file';
			var diff = _diffFromPath(file);
			var d    = fromFile(full, diff);
			if (d == null) continue;
			diffs.set(diff, d.notes);
			if (baseData == null) baseData = d;
		}

		if (baseData == null) return null;
		baseData.difficulties    = diffs;
		baseData.activeDifficulty = [for (k in diffs.keys()) k][0] ?? 'Normal';
		baseData.notes            = diffs.get(baseData.activeDifficulty) ?? [];
		return baseData;
		#else
		return null;
		#end
	}

	/**
	 * Parsea el JSON de Psych Engine desde un string.
	 */
	public static function fromString(content:String, ?difficulty:String):Null<ChartData>
	{
		if (content == null || content.length == 0) return null;

		var parsed:Dynamic;
		try { parsed = Json.parse(content); }
		catch (e:Dynamic) { trace('[Psych] Invalid JSON: $e'); return null; }

		// Psych wrappea todo en { "song": { ... } }
		var song:Dynamic = Reflect.field(parsed, 'song') ?? parsed;

		var title       = _str(song, 'song')       ?? 'Unknown';
		var bpm         = _float(song, 'bpm')       ?? 100.0;
		var speed       = _float(song, 'speed')     ?? 2.0;
		var player1     = _str(song, 'player1')     ?? 'bf';
		var player2     = _str(song, 'player2')     ?? 'dad';
		var gfVer       = _str(song, 'gfVersion')   ?? 'gf';
		var stage       = _str(song, 'stage')       ?? 'stage';
		var needsVoices = Reflect.field(song, 'needsVoices') == true;
		var diff        = difficulty ?? 'Normal';

		var rawSections:Array<Dynamic> = cast(Reflect.field(song, 'notes') ?? []);

		// ── Construir BPM changes ─────────────────────────────────────────
		var bpmChanges:Array<ChartBPMChange> = [];
		var timeAccum = 0.0;
		var curBpm    = bpm;

		for (sec in rawSections)
		{
			if (_bool(sec, 'changeBPM'))
			{
				var newBpm = _float(sec, 'bpm') ?? curBpm;
				if (newBpm != curBpm)
				{
					bpmChanges.push({ time: timeAccum, bpm: newBpm });
					curBpm = newBpm;
				}
			}
			var steps = Std.int(_float(sec, 'lengthInSteps') ?? 16);
			timeAccum += steps * (60000.0 / curBpm / 4.0);
		}

		// ── Aplanar notas ─────────────────────────────────────────────────
		var notes:Array<ChartNote> = [];
		var sectionTime = 0.0;
		curBpm = bpm;

		for (sec in rawSections)
		{
			if (_bool(sec, 'changeBPM'))
				curBpm = _float(sec, 'bpm') ?? curBpm;

			var mustHit = _bool(sec, 'mustHitSection');
			var rawNotes:Array<Dynamic> = cast(Reflect.field(sec, 'sectionNotes') ?? []);

			for (n in rawNotes)
			{
				var arr:Array<Dynamic> = cast n;
				if (arr == null || arr.length < 2) continue;

				var noteTime = _dynFloat(arr[0]) ?? 0.0;
				var rawCol   = Std.int(_dynFloat(arr[1]) ?? 0);
				var holdLen  = _dynFloat(arr[2]) ?? 0.0;

				// Psych: col 0-3 = based on mustHitSection, 4-7 = opposite
				// Normalizar a col absoluto: 0-3 = player, 4-7 = opponent
				var absCol:Int;
				if (mustHit)
					absCol = rawCol; // 0-3 ya es player, 4-7 ya es opponent
				else
					absCol = rawCol < 4 ? rawCol + 4 : rawCol - 4;

				notes.push({ time: noteTime, column: absCol, duration: holdLen, type: holdLen > 0 ? 'hold' : 'normal' });
			}

			var steps = Std.int(_float(sec, 'lengthInSteps') ?? 16);
			sectionTime += steps * (60000.0 / curBpm / 4.0);
		}

		notes.sort((a, b) -> Std.int(a.time - b.time));

		var diffMap:Map<String, Array<ChartNote>> = new Map();
		diffMap.set(diff, notes);

		// Guardar el SwagSong original en meta para uso directo
		var swagSong:Dynamic = {
			song: title, notes: rawSections, bpm: bpm,
			needsVoices: needsVoices, speed: speed,
			player1: player1, player2: player2,
			gfVersion: gfVer, stage: stage
		};

		trace('[Psych] "$title" — ${notes.length} notas — dif "$diff".');

		return {
			title:            title,
			artist:           '',
			source:           'psych',
			bpm:              bpm,
			bpmChanges:       bpmChanges,
			audioFile:        '',
			offset:           0.0,
			keyCount:         8,
			difficulties:     diffMap,
			notes:            notes,
			activeDifficulty: diff,
			meta: {
				swagSong:    swagSong,
				speed:       speed,
				player1:     player1,
				player2:     player2,
				gfVersion:   gfVer,
				stage:       stage,
				needsVoices: needsVoices,
				events:      Reflect.field(song, 'events') ?? []
			}
		};
	}

	// ── Helpers ────────────────────────────────────────────────────────────

	static function _diffFromPath(path:String):String
	{
		var file = path.split('/').pop().split('\\').pop();
		var name = file.split('.')[0].toLowerCase();
		return switch (name)
		{
			case 'easy':   'Easy';
			case 'normal': 'Normal';
			case 'hard':   'Hard';
			case 'erect':  'Erect';
			default:       name.charAt(0).toUpperCase() + name.substr(1);
		};
	}

	static inline function _str(o:Dynamic, k:String):Null<String>
	{
		var v = Reflect.field(o, k);
		return v != null ? Std.string(v) : null;
	}

	static inline function _float(o:Dynamic, k:String):Null<Float>
	{
		var v = Reflect.field(o, k);
		if (v == null) return null;
		var f = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? null : f;
	}

	static inline function _dynFloat(v:Dynamic):Null<Float>
	{
		if (v == null) return null;
		var f = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? null : f;
	}

	static inline function _bool(o:Dynamic, k:String):Bool
		return Reflect.field(o, k) == true;
}
