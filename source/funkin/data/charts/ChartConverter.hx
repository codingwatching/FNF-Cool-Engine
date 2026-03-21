package funkin.data.charts;

import funkin.data.Song;

// ChartBPMChange es sub-tipo del módulo ChartData.hx; requiere import explícito.
import funkin.data.charts.ChartData.ChartBPMChange;

/**
 * ChartConverter — Convierte ChartData (formato normalizado de parsers externos)
 * a SwagSong (formato nativo FNF) para usarlo directamente en PlayState.
 *
 * ─── Uso ─────────────────────────────────────────────────────────────────────
 *
 *   // Desde osu!mania
 *   var data = OsuManiaParser.fromFile('mods/mymod/charts/song.osu');
 *   var song = ChartConverter.toSwagSong(data);
 *   PlayState.SONG = song;
 *   FlxG.switchState(new PlayState());
 *
 *   // Desde StepMania con dificultad específica
 *   var data = StepManiaParser.fromFile('charts/song.sm', 'Hard');
 *   var song = ChartConverter.toSwagSong(data, { playerLane: 'left' });
 *   PlayState.SONG = song;
 *
 * ─── Mapeo de carriles ───────────────────────────────────────────────────────
 *
 *   FNF usa un layout fijo de 8 carriles (4 player + 4 oponent).
 *   Por defecto los carriles 0–3 del chart importado van al jugador (BF),
 *   y si hay carriles 4–7 van al oponente (DAD).
 *
 *   Puedes cambiar esto con options.playerLane:
 *     'left'  → columnas 0–3 = player (default)
 *     'right' → columnas 0–3 = opponent, 4–7 = player
 *
 * ─── Limitaciones ────────────────────────────────────────────────────────────
 *
 *   • Charts con más de 8 carriles se recortan a 8.
 *   • Los tipos 'mine', 'lift' y 'roll' se mapean a notas normales
 *     (FNF no tiene esos tipos de nota por defecto).
 *   • Las secciones se crean de 4 beats (16 steps) — el BPM de cada
 *     sección se toma del primer cambio de BPM que ocurre en ella.
 */
class ChartConverter
{
	// ── Constantes ─────────────────────────────────────────────────────────

	/** Steps por sección en FNF. */
	static inline final STEPS_PER_SECTION = 16;
	/** Beats por sección en FNF. */
	static inline final BEATS_PER_SECTION = 4;

	// ── API principal ──────────────────────────────────────────────────────

	/**
	 * Convierte un ChartData al SwagSong esperado por PlayState.
	 *
	 * @param data     ChartData devuelto por OsuManiaParser o StepManiaParser.
	 * @param options  Opciones opcionales de conversión.
	 * @return         SwagSong listo para asignar a PlayState.SONG.
	 */
	public static function toSwagSong(data:ChartData,
		?options:ConvertOptions):Null<SwagSong>
	{
		if (data == null || data.notes == null) return null;

		var opts = options ?? {};
		var swapLanes = (opts.playerLane ?? 'left') == 'right';

		// ── Calcular duración total de la canción ──────────────────────────
		var totalMs = 0.0;
		for (n in data.notes)
		{
			var end = n.time + n.duration;
			if (end > totalMs) totalMs = end;
		}
		totalMs += 4000.0; // buffer extra al final

		// ── Construir secciones ────────────────────────────────────────────
		var sections:Array<SwagSection> = [];
		var beatMs = 60000.0 / data.bpm;
		var sectionMs = beatMs * BEATS_PER_SECTION;

		var numSections = Math.ceil(totalMs / sectionMs) + 1;

		// Precalcular BPM por sección usando bpmChanges
		var sectionBpms:Array<Float> = [];
		for (s in 0...numSections)
		{
			var sectionStartMs = s * sectionMs;
			sectionBpms.push(_getBpmAtTime(sectionStartMs, data.bpmChanges, data.bpm));
		}

		// Crear secciones vacías
		for (s in 0...numSections)
		{
			var secBpm    = sectionBpms[s];
			var secBeatMs = 60000.0 / secBpm;
			sectionMs = secBeatMs * BEATS_PER_SECTION;

			sections.push({
				sectionNotes:  [],
				lengthInSteps: STEPS_PER_SECTION,
				typeOfSection: 0,
				mustHitSection: !swapLanes,
				bpm:            secBpm,
				changeBPM:      s == 0 || sectionBpms[s] != sectionBpms[s - 1],
				altAnim:        false
			});
		}

		// ── Distribuir notas en secciones ─────────────────────────────────
		for (note in data.notes)
		{
			// Ignorar mines en FNF (no existe ese tipo)
			if (note.type == 'mine') continue;

			var noteTime   = note.time + data.offset;
			var noteColumn = note.column;

			// Limitar a 8 carriles máximo
			if (noteColumn >= 8) continue;

			// Determinar si es nota del jugador o del oponente
			// FNF: 0-3 = BF (must-hit), 4-7 = DAD
			// Si swap: 0-3 → DAD, 4-7 → BF
			var fnfColumn:Int;
			if (noteColumn < 4)
				fnfColumn = swapLanes ? noteColumn + 4 : noteColumn;
			else
				fnfColumn = swapLanes ? noteColumn - 4 : noteColumn;

			// Hallar la sección correcta
			var secIdx = _sectionForTime(noteTime, sectionBpms, data.bpm);
			if (secIdx >= sections.length) secIdx = sections.length - 1;

			var noteType = note.type == 'hold' || note.type == 'roll' ? 0 : 0;

			sections[secIdx].sectionNotes.push([noteTime, fnfColumn, note.duration]);
		}

		// ── Ajustar mustHitSection ─────────────────────────────────────────
		// Una sección es "mustHit" si la mayoría de notas son del jugador (0–3)
		for (sec in sections)
		{
			var playerNotes = 0;
			var oppNotes    = 0;
			for (n in sec.sectionNotes)
			{
				var col:Int = Std.int(n[1]);
				if (col < 4) playerNotes++ else oppNotes++;
			}
			sec.mustHitSection = playerNotes >= oppNotes;
		}

		var song:SwagSong = {
			song:         data.title,
			notes:        sections,
			bpm:          data.bpm,
			needsVoices:  false,
			speed:        opts.scrollSpeed ?? 2.0,
			player1:      opts.player1 ?? 'bf',
			player2:      opts.player2 ?? 'dad',
			gfVersion:    opts.gf     ?? 'gf',
			stage:        opts.stage  ?? 'stage'
		};

		return song;
	}

	// ── Helpers ────────────────────────────────────────────────────────────

	/** Devuelve el BPM en vigor en el tiempo `ms`. */
	static function _getBpmAtTime(ms:Float, changes:Array<ChartBPMChange>,
		defaultBpm:Float):Float
	{
		if (changes == null || changes.length == 0) return defaultBpm;
		var bpm = defaultBpm;
		for (ch in changes)
		{
			if (ch.time <= ms) bpm = ch.bpm;
			else break;
		}
		return bpm;
	}

	/** Devuelve el índice de sección para un tiempo ms dado. */
	static function _sectionForTime(ms:Float, sectionBpms:Array<Float>,
		defaultBpm:Float):Int
	{
		var accumulated = 0.0;
		for (i in 0...sectionBpms.length)
		{
			var secMs = (60000.0 / sectionBpms[i]) * BEATS_PER_SECTION;
			if (ms < accumulated + secMs) return i;
			accumulated += secMs;
		}
		return sectionBpms.length - 1;
	}
}

// ── Opciones de conversión ─────────────────────────────────────────────────────

typedef ConvertOptions =
{
	/** 'left' (default) = player recibe columnas 0-3; 'right' = columnas 4-7. */
	var ?playerLane:String;
	/** Velocidad de scroll en PlayState. Default: 2.0. */
	var ?scrollSpeed:Float;
	/** Skin de player 1. Default: 'bf'. */
	var ?player1:String;
	/** Skin de player 2. Default: 'dad'. */
	var ?player2:String;
	/** Versión de GF. Default: 'gf'. */
	var ?gf:String;
	/** Stage. Default: 'stage'. */
	var ?stage:String;
}

// ── Tipos FNF ──────────────────────────────────────────────────────────────────
// Redefinición local para no depender de Song.hx en todos los targets.

typedef SwagSection =
{
	var sectionNotes   : Array<Array<Dynamic>>;
	var lengthInSteps  : Int;
	var typeOfSection  : Int;
	var mustHitSection : Bool;
	var bpm            : Float;
	var changeBPM      : Bool;
	var altAnim        : Bool;
}

typedef SwagSong =
{
	var song         : String;
	var notes        : Array<SwagSection>;
	var bpm          : Float;
	var needsVoices  : Bool;
	var speed        : Float;
	var player1      : String;
	var player2      : String;
	var ?gfVersion   : String;
	var ?stage       : String;
}
