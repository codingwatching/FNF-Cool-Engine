package funkin.data.charts;

#if sys
import sys.io.File;
import sys.FileSystem;
#end
import haxe.Json;

/**
 * CodenameChartParser — Lector de charts en formato Codename Engine (.json).
 *
 * ─── Formato Codename Engine ─────────────────────────────────────────────────
 *
 *   {
 *     "codenameChart": true,        ← identificador del formato
 *     "scrollSpeed": 2.5,
 *     "validScore":  true,
 *     "noteTypes":   ["default", "alt"],
 *     "bpm":         150,
 *     "stage":       "stage",
 *     "characters": { "bf": "bf", "dad": "dad", "gf": "gf" },
 *     "events": [],
 *     "strumLines": [
 *       {
 *         "position":      "opponent",   ← "opponent" | "player" | "middle"
 *         "strumLineType": "cpu",        ← "cpu" | "player"
 *         "visible":       true,
 *         "notes": [
 *           { "time": 500, "id": 0, "sLen": 0,   "type": 0 },
 *           { "time": 750, "id": 2, "sLen": 200, "type": 0 }
 *         ]
 *       },
 *       {
 *         "position": "player",
 *         "notes": [
 *           { "time": 1000, "id": 1, "sLen": 0, "type": 0 }
 *         ]
 *       }
 *     ]
 *   }
 *
 *   "id"   → carril dentro del strumLine (0-3)
 *   "sLen" → duration of the hold in ms (0 = tap normal)
 *   "time" → tiempo en ms
 *
 * ─── Mapeo de columnas ────────────────────────────────────────────────────────
 *
 *   strumLine opponent → columnas 4-7  (igual que FNF base)
 *   strumLine player   → columnas 0-3
 *   strumLine middle   → columnas 0-3  (tratado como player)
 *
 * ─── Uso ─────────────────────────────────────────────────────────────────────
 *
 *   var data = CodenameChartParser.fromFile('mods/mymod/songs/bopeebo/chart.json');
 *   var song = ChartConverter.toSwagSong(data);
 *   PlayState.SONG = song;
 */
class CodenameChartParser
{
	// ── API public ────────────────────────────────────────────────────────

	/**
	 * Carga un chart de Codename Engine desde un archivo .json.
	 */
	public static function fromFile(path:String, ?difficulty:String):Null<ChartData>
	{
		#if sys
		if (!FileSystem.exists(path))
		{
			trace('[Codename] Archivo no encontrado: $path');
			return null;
		}
		try   { return fromString(File.getContent(path), difficulty); }
		catch (e:Dynamic) { trace('[Codename] Error leyendo "$path": $e'); return null; }
		#else
		return null;
		#end
	}

	/**
	 * Parsea el contenido JSON de un chart Codename Engine.
	 */
	public static function fromString(content:String, ?difficulty:String):Null<ChartData>
	{
		if (content == null || content.length == 0) return null;

		var parsed:Dynamic;
		try { parsed = Json.parse(content); }
		catch (e:Dynamic) { trace('[Codename] Invalid JSON: $e'); return null; }

		// Verificar que es un chart Codename
		if (Reflect.field(parsed, 'codenameChart') != true)
		{
			trace('[Codename] El JSON no tiene "codenameChart":true — no es formato Codename.');
			return null;
		}

		var bpm     = _float(parsed, 'bpm')         ?? 100.0;
		var speed   = _float(parsed, 'scrollSpeed') ?? 2.0;
		var stage   = _str(parsed, 'stage')         ?? 'stage';
		var diff    = difficulty ?? 'Normal';

		var chars:Dynamic   = Reflect.field(parsed, 'characters') ?? {};
		var player1  = _str(chars, 'bf')  ?? 'bf';
		var player2  = _str(chars, 'dad') ?? 'dad';
		var gf       = _str(chars, 'gf')  ?? 'gf';

		var strumLines:Array<Dynamic> = cast(Reflect.field(parsed, 'strumLines') ?? []);
		var notes:Array<ChartNote>    = [];

		for (sl in strumLines)
		{
			var position:String = (_str(sl, 'position') ?? 'player').toLowerCase();
			// Offset de columna: player/middle → 0, opponent → 4
			var colOffset = (position == 'opponent') ? 4 : 0;

			var rawNotes:Array<Dynamic> = cast(Reflect.field(sl, 'notes') ?? []);
			for (n in rawNotes)
			{
				var time = _float(n, 'time') ?? 0.0;
				var id   = Std.int(_float(n, 'id')   ?? 0);
				var sLen = _float(n, 'sLen') ?? 0.0;

				var col = colOffset + (id % 4);
				notes.push({
					time:     time,
					column:   col,
					duration: sLen,
					type:     sLen > 0 ? 'hold' : 'normal'
				});
			}
		}

		notes.sort((a, b) -> Std.int(a.time - b.time));

		// ── BPM changes ───────────────────────────────────────────────────
		var bpmChanges:Array<ChartBPMChange> = [];
		var rawBpmChanges:Array<Dynamic>      = cast(Reflect.field(parsed, 'bpmChanges') ?? []);
		for (ch in rawBpmChanges)
		{
			var t  = _float(ch, 'time') ?? 0.0;
			var b  = _float(ch, 'bpm')  ?? bpm;
			bpmChanges.push({ time: t, bpm: b });
		}

		var diffMap:Map<String, Array<ChartNote>> = new Map();
		diffMap.set(diff, notes);

		trace('[Codename] ${notes.length} notas — dif "$diff".');

		return {
			title:            _str(parsed, 'song') ?? 'Unknown',
			artist:           '',
			source:           'codename',
			bpm:              bpm,
			bpmChanges:       bpmChanges,
			audioFile:        '',
			offset:           0.0,
			keyCount:         8,
			difficulties:     diffMap,
			notes:            notes,
			activeDifficulty: diff,
			meta: {
				speed:     speed,
				stage:     stage,
				player1:   player1,
				player2:   player2,
				gf:        gf,
				events:    Reflect.field(parsed, 'events') ?? [],
				noteTypes: Reflect.field(parsed, 'noteTypes') ?? ['default']
			}
		};
	}

	// ── Helpers ────────────────────────────────────────────────────────────

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
}
