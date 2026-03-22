package funkin.data.charts;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

// ChartNote and ChartBPMChange are sub-types of the module ChartData.hx;
// in Haxe require explicit import even if they're in the same package.
import funkin.data.charts.ChartData.ChartNote;
import funkin.data.charts.ChartData.ChartBPMChange;

using StringTools;

/**
 * StepManiaParser — Lector de charts en formato StepMania (.sm / .ssc).
 *
 * Soporta:
 *  • Formato .sm  (StepMania 3/4/5 legacy)
 *  • Formato .ssc (StepMania 5 extendido)
 *  • Multiple difficulties in the mismo file
 *  • Modos: dance-single (4), dance-double (8), pump-single (5), pump-double (10)
 *  • BPM changes y stops
 *  • Notas normales, holds, rolls, mines y lifts
 *  • Offset global
 *
 * ─── Formato .sm (resumen) ───────────────────────────────────────────────────
 *
 *   #TITLE:Song Name;
 *   #ARTIST:Artist Name;
 *   #MUSIC:audio.ogg;
 *   #OFFSET:-0.009;          ← offset en segundos (negativo = notas antes)
 *   #BPMS:0.000=120.000,     ← beat=BPM, beat=BPM, ...
 *         64.000=140.000;
 *   #STOPS:;                 ← pausas (beat=duration in segundos)
 *
 *   #NOTES:
 *     dance-single:          ← tipo de modo
 *     :                      ← description (empty normally)
 *     Hard:                  ← dificultad
 *     10:                    ← meter (difficulty numérica)
 *     0.000,0.000,...:       ← groove radar
 *     0000                   ← medida (4 lines = 1 beat in 4ths)
 *     0100
 *     0000
 *     0010
 *     ,                      ← separador de medida
 *     ...
 *     ;
 *
 * ─── Tipos de nota en .sm ────────────────────────────────────────────────────
 *
 *   0  → empty
 *   1  → nota normal (tap)
 *   2  → inicio de hold
 *   3  → fin de hold
 *   4  → inicio de roll
 *   M  → mine
 *   L  → lift
 *
 * ─── Uso ─────────────────────────────────────────────────────────────────────
 *
 *   // Cargar todas las dificultades de un .sm
 *   var data = StepManiaParser.fromFile('mods/mymod/charts/song.sm');
 *   if (data != null) {
 *     trace('Dificultades: ' + [for (k in data.difficulties.keys()) k].join(', '));
 *
 *     // Seleccionar una dificultad
 *     var hard = StepManiaParser.fromFile('song.sm', 'Hard');
 *     var song = ChartConverter.toSwagSong(hard);
 *   }
 */
class StepManiaParser
{
	// ── API public ────────────────────────────────────────────────────────

	/**
	 * Parsea un archivo .sm o .ssc desde el sistema de archivos.
	 *
	 * @param path        Ruta al archivo .sm / .ssc.
	 * @param difficulty  Si se especifica, la dificultad activa en ChartData.
	 *                    Si es null, se usa la primera encontrada.
	 * @return            ChartData con todas las dificultades, o null si falla.
	 */
	public static function fromFile(path:String, ?difficulty:String):Null<ChartData>
	{
		#if sys
		if (!FileSystem.exists(path))
		{
			trace('[StepMania] Archivo no encontrado: $path');
			return null;
		}
		try
		{
			var content = File.getContent(path);
			var isSsc   = path.toLowerCase().endsWith('.ssc');
			return fromString(content, isSsc, difficulty);
		}
		catch (e:Dynamic)
		{
			trace('[StepMania] Error leyendo "$path": $e');
			return null;
		}
		#else
		trace('[StepMania] fromFile() requiere target sys.');
		return null;
		#end
	}

	/**
	 * Parsea el contenido de un archivo .sm / .ssc como string.
	 *
	 * @param content     Contenido del archivo.
	 * @param isSsc       true si el formato es .ssc (StepMania 5 extended).
	 * @param difficulty  Dificultad a activar por defecto.
	 * @return            ChartData con todas las dificultades.
	 */
	public static function fromString(content:String, isSsc:Bool = false,
		?difficulty:String):Null<ChartData>
	{
		if (content == null || content.length == 0) return null;

		// ── Leer tags de nivel de archivo ─────────────────────────────────
		var title     = _tag(content, 'TITLE')     ?? 'Unknown';
		var subtitle  = _tag(content, 'SUBTITLE')  ?? '';
		var artist    = _tag(content, 'ARTIST')    ?? 'Unknown';
		var audioFile = _tag(content, 'MUSIC')     ?? '';
		var offsetStr = _tag(content, 'OFFSET')    ?? '0';
		var bpmsStr   = _tag(content, 'BPMS')      ?? '';
		var stopsStr  = _tag(content, 'STOPS')     ?? '';

		var offsetSec = Std.parseFloat(offsetStr);
		if (Math.isNaN(offsetSec)) offsetSec = 0.0;
		var offsetMs = -offsetSec * 1000.0; // SM: negativo = nota antes → offset positivo

		// ── BPM changes ───────────────────────────────────────────────────
		var bpmChanges = _parseBPMs(bpmsStr);
		var initialBpm = bpmChanges.length > 0 ? bpmChanges[0].bpm : 120.0;

		// Convertir beats a ms en los bpmChanges
		_bpmChangesBeatsToMs(bpmChanges);

		// ── Paradas (stops) ───────────────────────────────────────────────
		var stops = _parseStops(stopsStr, bpmChanges);

		// ── Leer todos los bloques #NOTES / #NOTEDATA ─────────────────────
		var difficulties:Map<String, Array<ChartNote>> = new Map();
		var diffNames:Array<String> = [];

		if (isSsc)
			_parseSscNotes(content, bpmChanges, stops, difficulties, diffNames);
		else
			_parseSmNotes(content, bpmChanges, stops, difficulties, diffNames);

		if (diffNames.length == 0)
		{
			trace('[StepMania] No se encontraron notas en el archivo.');
			return null;
		}

		// Seleccionar dificultad activa
		var activeDiff = difficulty;
		if (activeDiff == null || !difficulties.exists(activeDiff))
			activeDiff = diffNames[0];

		var activeNotes = difficulties.get(activeDiff) ?? [];

		// Detect keyCount from the notes (maximum column + 1)
		var keyCount = 4;
		for (n in activeNotes)
			if (n.column + 1 > keyCount) keyCount = n.column + 1;

		trace('[StepMania] Parseado: "$title" — ${diffNames.length} difs — ${activeNotes.length} notas en "$activeDiff".');

		return {
			title:            subtitle.length > 0 ? '$title - $subtitle' : title,
			artist:           artist,
			source:           'stepmania',
			bpm:              initialBpm,
			bpmChanges:       bpmChanges,
			audioFile:        audioFile,
			offset:           offsetMs,
			keyCount:         keyCount,
			difficulties:     difficulties,
			notes:            activeNotes,
			activeDifficulty: activeDiff,
			meta: {
				stops:     stops,
				allDiffs:  diffNames
			}
		};
	}

	// ── Parseo de secciones ────────────────────────────────────────────────

	/**
	 * Lee todos los bloques #NOTES del formato .sm.
	 * Cada bloque tiene:
	 *   noteType : description : difficulty : meter : radar : <notedata>;
	 */
	static function _parseSmNotes(content:String,
		bpmChanges:Array<ChartBPMChange>,
		stops:Array<_Stop>,
		out:Map<String, Array<ChartNote>>,
		names:Array<String>):Void
	{
		// Extraer todos los valores de #NOTES:...;
		var rx = ~/#NOTES:([\s\S]*?);/g;
		rx.map(content, function(r) {
			var block = r.matched(1);
			_parseSmBlock(block, bpmChanges, stops, out, names);
			return '';
		});
	}

	static function _parseSmBlock(block:String,
		bpmChanges:Array<ChartBPMChange>,
		stops:Array<_Stop>,
		out:Map<String, Array<ChartNote>>,
		names:Array<String>):Void
	{
		// Separar los campos por ':'
		var fields = block.split(':');
		if (fields.length < 6) return;

		var noteType   = fields[0].trim().toLowerCase(); // e.g. "dance-single"
		// fields[1] = description (ignorar)
		var difficulty = fields[2].trim();               // e.g. "Hard"
		// fields[3] = meter (ignorar para nosotros)
		// fields[4] = groove radar
		var noteData   = fields[5];                      // notas

		var keyCount = _keyCountFromType(noteType);
		var notes    = _parseNoteData(noteData, keyCount, bpmChanges, stops);

		// If already exists that difficulty, add suffix for no perderla
		var diffKey = difficulty;
		var i = 2;
		while (out.exists(diffKey)) diffKey = '$difficulty$i';

		out.set(diffKey, notes);
		names.push(diffKey);
	}

	/**
	 * Lee los bloques del formato .ssc (StepMania 5).
	 * Usa tags #NOTEDATA ... #ENDSONG con #STEPSTYPE, #DIFFICULTY, #NOTES.
	 */
	static function _parseSscNotes(content:String,
		bpmChanges:Array<ChartBPMChange>,
		stops:Array<_Stop>,
		out:Map<String, Array<ChartNote>>,
		names:Array<String>):Void
	{
		// Dividir en bloques entre #NOTEDATA: y ;
		var rx = ~/#NOTEDATA:([\s\S]*?);[\s\S]*?#NOTES:([\s\S]*?);/g;
		rx.map(content, function(r) {
			var meta     = r.matched(1);
			var noteData = r.matched(2);

			var noteType   = _tagInline(meta, 'STEPSTYPE') ?? 'dance-single';
			var difficulty = _tagInline(meta, 'DIFFICULTY') ?? 'Normal';

			var keyCount = _keyCountFromType(noteType.toLowerCase());
			var notes    = _parseNoteData(noteData, keyCount, bpmChanges, stops);

			var diffKey = difficulty;
			var i = 2;
			while (out.exists(diffKey)) diffKey = '$difficulty$i';

			out.set(diffKey, notes);
			names.push(diffKey);
			return '';
		});
	}

	// ── Parseo de notedata ─────────────────────────────────────────────────

	/**
	 * Convierte los datos de notas (medidas separadas por comas)
	 * a un array de ChartNote en ms.
	 *
	 * @param data        Bloque de texto con medidas (measures).
	 * @param keyCount    Number of columnas.
	 * @param bpmChanges  Cambios de BPM ya con tiempo en ms.
	 * @param stops       Paradas del nivel.
	 */
	static function _parseNoteData(data:String, keyCount:Int,
		bpmChanges:Array<ChartBPMChange>,
		stops:Array<_Stop>):Array<ChartNote>
	{
		var notes:Array<ChartNote> = [];

		// Limpiar comentarios // ...
		var clean = ~/\/\/[^\n]*/g.replace(data, '');

		// Dividir en medidas
		var measures = clean.split(',');
		var beat     = 0.0;

		// Holds activos: column → { startBeat, startMs }
		var holdStarts:Map<Int, { beat:Float, ms:Float }> = new Map();
		var rollStarts:Map<Int, { beat:Float, ms:Float }> = new Map();

		for (measure in measures)
		{
			var rows = _cleanRows(measure, keyCount);
			if (rows.length == 0) { beat += 4.0; continue; }

			var beatsPerRow = 4.0 / rows.length;

			for (r in 0...rows.length)
			{
				var row = rows[r];
				var currentBeat = beat + r * beatsPerRow;
				var timeMs = _beatToMs(currentBeat, bpmChanges) + _stopOffsetAt(currentBeat, stops);

				for (col in 0...row.length)
				{
					if (col >= keyCount) break;
					var ch = row.charAt(col);

					switch (ch)
					{
						case '1': // tap normal
							notes.push({ time: timeMs, column: col, duration: 0.0, type: 'normal' });

						case '2': // inicio de hold
							holdStarts.set(col, { beat: currentBeat, ms: timeMs });

						case '3': // fin de hold
							var hs = holdStarts.get(col);
							if (hs != null)
							{
								notes.push({ time: hs.ms, column: col, duration: timeMs - hs.ms, type: 'hold' });
								holdStarts.remove(col);
							}

						case '4': // inicio de roll
							rollStarts.set(col, { beat: currentBeat, ms: timeMs });

						case 'M', 'm': // mine
							notes.push({ time: timeMs, column: col, duration: 0.0, type: 'mine' });

						case 'L', 'l': // lift
							notes.push({ time: timeMs, column: col, duration: 0.0, type: 'lift' });

						// end of roll (also marked with '3' in SM)
						// si hay un rollStart activo, lo cerramos
						default:
							if (ch == '3')
							{
								var rs = rollStarts.get(col);
								if (rs != null)
								{
									notes.push({ time: rs.ms, column: col, duration: timeMs - rs.ms, type: 'roll' });
									rollStarts.remove(col);
								}
							}
					}
				}
			}

			beat += 4.0;
		}

		// Cerrar holds que quedaron abiertos (fin de archivo)
		for (col => hs in holdStarts)
			notes.push({ time: hs.ms, column: col, duration: 0.0, type: 'hold' });
		for (col => rs in rollStarts)
			notes.push({ time: rs.ms, column: col, duration: 0.0, type: 'roll' });

		notes.sort((a, b) -> Std.int(a.time - b.time));
		return notes;
	}

	/** Clears a medida: quita espacios/lines vacías and returns the filas. */
	static function _cleanRows(measure:String, keyCount:Int):Array<String>
	{
		var rows:Array<String> = [];
		for (line in measure.split('\n'))
		{
			var l = line.trim();
			// A fila valid tiene exactly keyCount caracteres of note
			if (l.length >= keyCount && ~/^[0-9A-Za-z]+$/.match(l))
				rows.push(l);
		}
		return rows;
	}

	// ── BPMs y Stops ──────────────────────────────────────────────────────

	/** Parsea "beat=bpm,beat=bpm,..." → array de { beat, bpm }. */
	static function _parseBPMs(raw:String):Array<ChartBPMChange>
	{
		var result:Array<ChartBPMChange> = [];
		if (raw == null || raw.trim().length == 0) return result;

		for (pair in raw.split(','))
		{
			var parts = pair.trim().split('=');
			if (parts.length < 2) continue;
			var beat = Std.parseFloat(parts[0].trim());
			var bpm  = Std.parseFloat(parts[1].trim());
			if (!Math.isNaN(beat) && !Math.isNaN(bpm) && bpm > 0)
				result.push({ time: beat, bpm: bpm }); // time = beat por ahora
		}

		result.sort((a, b) -> Std.int(a.time - b.time));
		return result;
	}

	/** Parsea "beat=seconds,beat=seconds,..." → array de stops. */
	static function _parseStops(raw:String, bpmChanges:Array<ChartBPMChange>):Array<_Stop>
	{
		var result:Array<_Stop> = [];
		if (raw == null || raw.trim().length == 0) return result;

		for (pair in raw.split(','))
		{
			var parts = pair.trim().split('=');
			if (parts.length < 2) continue;
			var beat    = Std.parseFloat(parts[0].trim());
			var durSec  = Std.parseFloat(parts[1].trim());
			if (!Math.isNaN(beat) && !Math.isNaN(durSec))
			{
				var ms = _beatToMsRaw(beat, bpmChanges);
				result.push({ beat: beat, ms: ms, durationMs: durSec * 1000.0 });
			}
		}
		result.sort((a, b) -> Std.int(a.beat - b.beat));
		return result;
	}

	/**
	 * Convierte los tiempos de bpmChanges de beats a ms (in-place).
	 * The primer cambio always is in beat=0 → ms=0.
	 */
	static function _bpmChangesBeatsToMs(changes:Array<ChartBPMChange>):Void
	{
		if (changes.length == 0) return;

		var msAccum   = 0.0;
		var lastBeat  = 0.0;
		var lastBpm   = changes[0].bpm;

		for (i in 0...changes.length)
		{
			var ch   = changes[i];
			var beat = ch.time; // still in beats

			msAccum  += (beat - lastBeat) * (60000.0 / lastBpm);
			ch.time   = msAccum;         // reemplazar beat por ms
			ch.beat   = beat;
			lastBeat  = beat;
			lastBpm   = ch.bpm;
		}
	}

	/** Convierte beat a ms usando el array de bpmChanges (ya en ms). */
	static function _beatToMs(beat:Float, changes:Array<ChartBPMChange>):Float
	{
		if (changes.length == 0) return beat * 500.0; // 120 BPM fallback

		var lastMs   = 0.0;
		var lastBeat = 0.0;
		var lastBpm  = changes[0].bpm;

		for (ch in changes)
		{
			var chBeat = ch.beat ?? 0.0;
			if (chBeat > beat) break;
			lastMs   = ch.time;
			lastBeat = chBeat;
			lastBpm  = ch.bpm;
		}

		return lastMs + (beat - lastBeat) * (60000.0 / lastBpm);
	}

	/** Version raw (before of convert) that trabaja with beats as tiempo. */
	static function _beatToMsRaw(beat:Float, changes:Array<ChartBPMChange>):Float
	{
		if (changes.length == 0) return beat * 500.0;
		var msAccum  = 0.0;
		var lastBeat = 0.0;
		var lastBpm  = changes[0].bpm;
		for (ch in changes)
		{
			var chBeat = ch.time; // still in beats in this fase
			if (chBeat > beat) break;
			msAccum  += (chBeat - lastBeat) * (60000.0 / lastBpm);
			lastBeat  = chBeat;
			lastBpm   = ch.bpm;
		}
		msAccum += (beat - lastBeat) * (60000.0 / lastBpm);
		return msAccum;
	}

	/**
	 * Calcula el offset total acumulado por stops antes del beat dado.
	 * Las paradas desplazan todas las notas posteriores.
	 */
	static function _stopOffsetAt(beat:Float, stops:Array<_Stop>):Float
	{
		var total = 0.0;
		for (s in stops)
		{
			if (s.beat < beat) total += s.durationMs;
			else break;
		}
		return total;
	}

	// ── Helpers de texto ──────────────────────────────────────────────────

	/** Extrae #TAG:Value; del contenido principal. */
	static function _tag(content:String, tag:String):Null<String>
	{
		var rx = new EReg('#$tag:([^;]*);', 'i');
		if (rx.match(content))
			return rx.matched(1).trim();
		return null;
	}

	/** Extrae #TAG:Value; dentro de un bloque inline (para .ssc). */
	static function _tagInline(block:String, tag:String):Null<String>
	{
		var rx = new EReg('#$tag:([^;\\r\\n]*);?', 'i');
		if (rx.match(block))
			return rx.matched(1).trim();
		return null;
	}

	/** Number of columnas according to the type of paso. */
	static function _keyCountFromType(noteType:String):Int
	{
		return switch (noteType)
		{
			case 'dance-single':   4;
			case 'dance-double':   8;
			case 'dance-solo':     6;
			case 'pump-single':    5;
			case 'pump-double':   10;
			case 'pump-halfdouble': 6;
			case 'ez2-single':     5;
			case 'para-single':    5;
			default:
				// Try to extract number from the type (e.g. "kb7-single" → 7)
				var rx = ~/(\d+)/;
				if (rx.match(noteType)) Std.parseInt(rx.matched(1)) ?? 4 else 4;
		};
	}
}

// ── Tipos internos ─────────────────────────────────────────────────────────────

private typedef _Stop =
{
	var beat:Float;
	var ms:Float;
	var durationMs:Float;
}
