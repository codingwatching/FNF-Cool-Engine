package funkin.data.charts;

#if sys
import sys.io.File;
import sys.FileSystem;
#end
import haxe.Json;

import funkin.data.charts.ChartData.ChartNote;
import funkin.data.charts.ChartData.ChartBPMChange;

/**
 * CodenameChartParser — Lector de charts en formato Codename Engine (.json).
 *
 * CORRECCIONES respecto a la versión anterior:
 *
 *  1. Detección de strumLine por "type" (int) en vez de "position" (string).
 *       type 0 → oponente  → columnas 4-7
 *       type 1 → jugador   → columnas 0-3
 *       type 2 → espectador (ignorado en el juego)
 *     El campo "position" contiene el nombre del personaje ("dad", "boyfriend"),
 *     NO "opponent"/"player" como asumía la versión anterior.
 *
 *  2. BPM leído desde los eventos "BPM Change" del array "events".
 *     El formato Codename 1.6 no tiene "bpm" top-level.
 *
 *  3. Personajes leídos desde strumLines[].characters[], no desde un objeto
 *     top-level "characters".
 */
class CodenameChartParser
{
	// ── API pública ────────────────────────────────────────────────────────

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

	public static function fromString(content:String, ?difficulty:String):Null<ChartData>
	{
		if (content == null || content.length == 0) return null;

		var parsed:Dynamic;
		try { parsed = Json.parse(content); }
		catch (e:Dynamic) { trace('[Codename] JSON inválido: $e'); return null; }

		if (Reflect.field(parsed, 'codenameChart') != true)
		{
			trace('[Codename] El JSON no tiene "codenameChart":true — no es formato Codename.');
			return null;
		}

		var speed = _float(parsed, 'scrollSpeed') ?? 2.0;
		var stage = _str(parsed, 'stage')         ?? 'stage';
		var diff  = difficulty ?? 'Normal';

		// ── BPM desde events ───────────────────────────────────────────────
		// En Codename 1.6 los cambios de BPM llegan como:
		//   { "name": "BPM Change", "params": [192], "time": 0 }
		var rawEvents:Array<Dynamic> = cast(Reflect.field(parsed, 'events') ?? []);
		var bpmChanges:Array<ChartBPMChange> = [];
		var firstBpm:Float = 100.0;

		for (ev in rawEvents)
		{
			if (_str(ev, 'name') == 'BPM Change')
			{
				var params:Array<Dynamic> = cast(Reflect.field(ev, 'params') ?? []);
				var t   = _float(ev, 'time') ?? 0.0;
				var bpm = (params.length > 0) ? (_dynFloat(params[0]) ?? firstBpm) : firstBpm;
				if (bpmChanges.length == 0) firstBpm = bpm;
				bpmChanges.push({ time: t, bpm: bpm });
			}
		}
		// Soporte para versiones antiguas con "bpm" top-level
		var topBpm = _float(parsed, 'bpm');
		if (topBpm != null && bpmChanges.length == 0)
		{
			firstBpm = topBpm;
			bpmChanges.push({ time: 0.0, bpm: firstBpm });
		}

		// ── Personajes desde strumLines ────────────────────────────────────
		var strumLines:Array<Dynamic> = cast(Reflect.field(parsed, 'strumLines') ?? []);
		var player1 = 'bf';
		var player2 = 'dad';
		var gf      = 'gf';

		for (sl in strumLines)
		{
			var slType = Std.int(_float(sl, 'type') ?? -1);
			var chars:Array<Dynamic> = cast(Reflect.field(sl, 'characters') ?? []);
			if (chars.length == 0) continue;
			var name = Std.string(chars[0]);
			switch (slType)
			{
				case 1: player1 = name;
				case 0: player2 = name;
				case 2: gf      = name;
				default:
			}
		}

		// ── Notas ──────────────────────────────────────────────────────────
		var notes:Array<ChartNote> = [];

		for (sl in strumLines)
		{
			var slType = Std.int(_float(sl, 'type') ?? -1);
			if (slType == 2) continue;           // espectador — no tiene notas de juego

			// type 0 = oponente → columnas 4-7
			// type 1 = jugador  → columnas 0-3
			var colOffset = (slType == 0) ? 4 : 0;

			var rawNotes:Array<Dynamic> = cast(Reflect.field(sl, 'notes') ?? []);
			for (n in rawNotes)
			{
				var time = _float(n, 'time') ?? 0.0;
				var id   = Std.int(_float(n, 'id') ?? 0);
				var sLen = _float(n, 'sLen') ?? 0.0;
				notes.push({
					time:     time,
					column:   colOffset + (id % 4),
					duration: sLen,
					type:     sLen > 0 ? 'hold' : 'normal'
				});
			}
		}

		notes.sort((a, b) -> Std.int(a.time - b.time));

		var diffMap:Map<String, Array<ChartNote>> = new Map();
		diffMap.set(diff, notes);

		trace('[Codename] ${notes.length} notas — dif "$diff" — BPM inicial $firstBpm.');

		return {
			title:            _str(parsed, 'song') ?? 'Unknown',
			artist:           '',
			source:           'codename',
			bpm:              firstBpm,
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
				events:    rawEvents,
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

	static inline function _dynFloat(v:Dynamic):Null<Float>
	{
		if (v == null) return null;
		var f = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? null : f;
	}
}
