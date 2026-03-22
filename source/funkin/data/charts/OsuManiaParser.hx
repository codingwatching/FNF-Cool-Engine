package funkin.data.charts;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

// ChartNote y ChartBPMChange son sub-tipos del módulo ChartData.hx;
// en Haxe requieren import explícito aunque estén en el mismo package.
import funkin.data.charts.ChartData.ChartNote;
import funkin.data.charts.ChartData.ChartBPMChange;

using StringTools;

/**
 * OsuManiaParser — Lector de charts en formato osu! (.osu).
 *
 * Soporta:
 *  • Formato osu!mania (Mode: 3)
 *  • Notas normales y long notes (hold)
 *  • Múltiples timing points (cambios de BPM y offset)
 *  • Mapas con cualquier número de teclas (keyCount)
 *  • Lectura de metadatos (título, artista, offset, audio)
 *
 * ─── Formato .osu (resumen) ──────────────────────────────────────────────────
 *
 *   [General]
 *   AudioFilename: audio.mp3
 *   Mode: 3              ← 3 = osu!mania
 *
 *   [Metadata]
 *   Title: Nombre canción
 *   Artist: Nombre artista
 *   Version: Hard         ← nombre de la dificultad
 *
 *   [Difficulty]
 *   CircleSize: 4         ← número de teclas
 *
 *   [TimingPoints]
 *   offset,msPerBeat,meter,sampleSet,sampleIndex,volume,uninherited,effects
 *   0,500,4,1,0,100,1,0   ← BPM = 60000/500 = 120, offset=0
 *
 *   [HitObjects]
 *   x,y,time,type,hitSound,...
 *   256,192,1000,1,0,0:0:0:0:   ← nota normal en time=1000ms
 *   256,192,2000,128,0,3000,0:0:0:0:  ← hold desde 2000ms hasta 3000ms
 *
 * ─── Uso ─────────────────────────────────────────────────────────────────────
 *
 *   // Cargar un .osu directamente
 *   var data = OsuManiaParser.fromFile('mods/mymod/charts/song.osu');
 *   if (data != null) {
 *     trace('${data.title} — ${data.notes.length} notas');
 *     var song = ChartConverter.toSwagSong(data);
 *     PlayState.SONG = song;
 *   }
 *
 *   // Cargar desde string (útil si el .osz ya está extraído en memoria)
 *   var data = OsuManiaParser.fromString(osuFileContent, 'myDiff');
 *
 * ─── Mapeo de columnas ────────────────────────────────────────────────────────
 *
 *   osu! usa coordenadas X (0–512) para indicar la columna:
 *     column = floor(x * keyCount / 512)
 *
 *   Para keyCount=4 (FNF):
 *     x=64  → columna 0 (izquierda)
 *     x=192 → columna 1
 *     x=320 → columna 2
 *     x=448 → columna 3 (derecha)
 */
class OsuManiaParser
{
	// ── Constantes ─────────────────────────────────────────────────────────

	/** Type bit para HitObject normal (círculo / nota). */
	static inline final HIT_CIRCLE  = 1;
	/** Type bit para HitObject hold (LN). */
	static inline final HOLD_NOTE   = 128;

	// ── API pública ────────────────────────────────────────────────────────

	/**
	 * Parsea un archivo .osu desde el sistema de archivos.
	 *
	 * @param path        Ruta al archivo .osu.
	 * @param difficulty  Nombre a asignar a esta dificultad (default = "Version" del archivo).
	 * @return            ChartData listo para usar, o null si falla.
	 */
	public static function fromFile(path:String, ?difficulty:String):Null<ChartData>
	{
		#if sys
		if (!FileSystem.exists(path))
		{
			trace('[OsuMania] Archivo no encontrado: $path');
			return null;
		}
		try
		{
			var content = File.getContent(path);
			return fromString(content, difficulty);
		}
		catch (e:Dynamic)
		{
			trace('[OsuMania] Error leyendo "$path": $e');
			return null;
		}
		#else
		trace('[OsuMania] fromFile() requiere target sys.');
		return null;
		#end
	}

	/**
	 * Parsea el contenido de un archivo .osu como string.
	 *
	 * @param content     Contenido del archivo .osu.
	 * @param difficulty  Nombre de la dificultad (default = Version del archivo).
	 * @return            ChartData, o null si el modo no es osu!mania.
	 */
	public static function fromString(content:String, ?difficulty:String):Null<ChartData>
	{
		if (content == null || content.length == 0) return null;

		var lines = content.split('\n');
		var section = '';

		// ── Metadatos ────────────────────────────────────────────────────
		var title     = 'Unknown';
		var artist    = 'Unknown';
		var version   = difficulty ?? 'Normal';
		var audioFile = '';
		var offset    = 0.0;
		var keyCount  = 4;
		var mode      = -1;

		// ── Timing ───────────────────────────────────────────────────────
		var timingPoints:Array<_TimingPoint> = [];

		// ── Notas ────────────────────────────────────────────────────────
		var notes:Array<ChartNote> = [];

		for (raw in lines)
		{
			var line = raw.trim();
			if (line.length == 0 || line.startsWith('//')) continue;

			// Detectar sección
			if (line.startsWith('[') && line.endsWith(']'))
			{
				section = line.substring(1, line.length - 1).toLowerCase();
				continue;
			}

			switch (section)
			{
				case 'general':
					var kv = _kv(line);
					if (kv != null) switch (kv.key)
					{
						case 'AudioFilename': audioFile = kv.val;
						case 'Mode':
							mode = Std.parseInt(kv.val) ?? -1;
							if (mode != 3)
							{
								trace('[OsuMania] Modo $mode no es osu!mania (3) — ignorando.');
								return null;
							}
					}

				case 'metadata':
					var kv = _kv(line);
					if (kv != null) switch (kv.key)
					{
						case 'Title':   title   = kv.val;
						case 'Artist':  artist  = kv.val;
						case 'Version': if (difficulty == null) version = kv.val;
					}

				case 'difficulty':
					var kv = _kv(line);
					if (kv != null && kv.key == 'CircleSize')
						keyCount = Std.int(Std.parseFloat(kv.val));

				case 'timingpoints':
					var tp = _parseTimingPoint(line);
					if (tp != null) timingPoints.push(tp);

				case 'hitobjects':
					var note = _parseHitObject(line, keyCount);
					if (note != null) notes.push(note);
			}
		}

		if (mode == -1)
		{
			trace('[OsuMania] No se encontró la sección [General] con Mode:3.');
			return null;
		}

		// ── Construir bpmChanges desde timingPoints uninherited ───────────
		var bpmChanges:Array<ChartBPMChange> = [];
		var initialBpm = 120.0;

		timingPoints.sort((a, b) -> Std.int(a.offset - b.offset));

		for (tp in timingPoints)
		{
			if (!tp.uninherited) continue; // heredados = velocidad, no BPM
			var bpm = tp.msPerBeat > 0 ? (60000.0 / tp.msPerBeat) : initialBpm;
			if (bpmChanges.length == 0)
			{
				initialBpm = bpm;
				offset     = tp.offset; // el primer timing point define el offset
			}
			bpmChanges.push({ time: tp.offset, bpm: bpm });
		}

		// Ordenar notas por tiempo
		notes.sort((a, b) -> Std.int(a.time - b.time));

		var diffMap:Map<String, Array<ChartNote>> = new Map();
		diffMap.set(version, notes);

		trace('[OsuMania] Parseado: "$title" — $keyCount teclas — ${notes.length} notas — dif "$version".');

		return {
			title:           title,
			artist:          artist,
			source:          'osu',
			bpm:             initialBpm,
			bpmChanges:      bpmChanges,
			audioFile:       audioFile,
			offset:          -offset, // osu usa offset positivo = retraso
			keyCount:        keyCount,
			difficulties:    diffMap,
			notes:           notes,
			activeDifficulty: version,
			meta: {
				rawTimingPoints: timingPoints.map(tp -> { offset: tp.offset, bpm: 60000.0 / tp.msPerBeat, uninherited: tp.uninherited })
			}
		};
	}

	// ── Internos ───────────────────────────────────────────────────────────

	/** Parsea "Key: Value" → { key, val }. */
	static function _kv(line:String):Null<{ key:String, val:String }>
	{
		var idx = line.indexOf(':');
		if (idx < 0) return null;
		return {
			key: line.substring(0, idx).trim(),
			val: line.substring(idx + 1).trim()
		};
	}

	static function _parseTimingPoint(line:String):Null<_TimingPoint>
	{
		var parts = line.split(',');
		if (parts.length < 2) return null;
		try
		{
			var offsetMs  = Std.parseFloat(parts[0]);
			var msPerBeat = Std.parseFloat(parts[1]);
			var uninherited = parts.length >= 7 ? parts[6].trim() == '1' : true;
			return { offset: offsetMs, msPerBeat: msPerBeat, uninherited: uninherited };
		}
		catch (e:Dynamic) { return null; }
	}

	/**
	 * Parsea una línea de [HitObjects].
	 * Formato: x,y,time,type,hitSound[,extras]
	 *
	 * Normal: x,y,time,1,hitSound,sampleInfo
	 * Hold:   x,y,time,128,hitSound,endTime:sampleInfo
	 */
	static function _parseHitObject(line:String, keyCount:Int):Null<ChartNote>
	{
		var parts = line.split(',');
		if (parts.length < 5) return null;
		try
		{
			var x       = Std.parseFloat(parts[0]);
			var time    = Std.parseFloat(parts[2]);
			var typeInt = Std.parseInt(parts[3]) ?? 0;

			// Calcular columna desde X (0..512)
			var column = Std.int(Math.floor(x * keyCount / 512.0));
			if (column < 0) column = 0;
			if (column >= keyCount) column = keyCount - 1;

			var duration = 0.0;
			var noteType = 'normal';

			if ((typeInt & HOLD_NOTE) != 0)
			{
				// Hold note: parte[5] = "endTime:sampleInfo"
				noteType = 'hold';
				if (parts.length >= 6)
				{
					var endPart = parts[5].split(':')[0].trim();
					var endTime = Std.parseFloat(endPart);
					if (!Math.isNaN(endTime) && endTime > time)
						duration = endTime - time;
				}
			}

			return { time: time, column: column, duration: duration, type: noteType };
		}
		catch (e:Dynamic) { return null; }
	}
}

// ── Tipo interno ──────────────────────────────────────────────────────────────

private typedef _TimingPoint =
{
	var offset:Float;
	var msPerBeat:Float;
	var uninherited:Bool;
}
