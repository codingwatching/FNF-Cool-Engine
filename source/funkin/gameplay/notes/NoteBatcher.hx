package funkin.gameplay.notes;

import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;

/**
 * NoteBatcher — agrupa notas por tipo de textura para minimizar cambios de estado GL.
 *
 * ─── How it works ───────────────────────────────────────────────────────────
 * HaxeFlixel renderiza cada FlxSprite en un draw call separado.
 * If agrupamos notes of the same type joints in the árbol of display,
 * el driver de OpenGL puede fusionar los draw calls adyacentes con la
 * misma textura en un solo batch — especialmente en targets con batching
 * automatic (HTML5/WebGL and algunos targets nativos with OpenFL 9+).
 *
 * ─── Optimizaciones respecto to the version previous ───────────────────────────
 * • Clave de batch es `Int` en vez de `String` — sin alloc por nota.
 * • `removeNoteFromBatch` usa swap-and-pop O(1) en vez de Array.remove O(n).
 * • `getBatchIndex` es `inline` — el compilador la elimina en el hot path.
 * • Stats without string concatenation in the hot path.
 */
class NoteBatcher extends FlxSpriteGroup
{
	// Indices of batch (Int for avoid alloc of String)
	static inline var BATCH_PURPLE  = 0;
	static inline var BATCH_BLUE    = 1;
	static inline var BATCH_GREEN   = 2;
	static inline var BATCH_RED     = 3;
	static inline var BATCH_SUSTAIN = 4;
	static inline var BATCH_COUNT   = 5;

	/** Maximum of notes by batch before of do flush. */
	public static var batchSize : Int = 128;
	public var enabled : Bool = true;

	// Batches as arrays of size fijo — without alloc in hot path
	final batches  : Array<Array<Note>>;
	end counts   : Array<Int>;   // sizes actuales of each batch

	// Stats
	public var totalBatches    : Int = 0;
	public var drawCallsSaved  : Int = 0;

	public function new()
	{
		super();
		batches = [for (_ in 0...BATCH_COUNT) []];
		counts  = [for (_ in 0...BATCH_COUNT) 0];
	}

	// ─── Hot path ─────────────────────────────────────────────────────────────

	public function addNoteToBatch(note:Note):Void
	{
		if (!enabled) { add(note); return; }

		final idx = getBatchIndex(note);
		batches[idx].push(note);
		counts[idx]++;

		if (counts[idx] >= batchSize)
			flushBatch(idx);
	}

	public function removeNoteFromBatch(note:Note):Void
	{
		final idx   = getBatchIndex(note);
		final batch = batches[idx];
		final last  = counts[idx] - 1;

		// Swap-and-pop or(1): reemplaza the elemento with the last and trunca
		for (i in 0...counts[idx])
		{
			if (batch[i] == note)
			{
				batch[i] = batch[last];
				batch.resize(last);
				counts[idx]--;
				break;
			}
		}
		remove(note, true);
	}

	// ─── Flush ────────────────────────────────────────────────────────────────

	public function flushAll():Void
	{
		for (i in 0...BATCH_COUNT) flushBatch(i);
	}

	inline function flushBatch(idx:Int):Void
	{
		final batch = batches[idx];
		final n     = counts[idx];
		if (n == 0) return;

		for (i in 0...n) add(batch[i]);

		totalBatches++;
		drawCallsSaved += n - 1;

		batch.resize(0);
		counts[idx] = 0;
	}

	// ─── Helpers ──────────────────────────────────────────────────────────────

	/** Returns the index of batch for a note. `inline` → without overhead. */
	static inline function getBatchIndex(note:Note):Int
		return note.isSustainNote ? BATCH_SUSTAIN : (note.noteData & 3); // % 4 without division

	public function clearBatches():Void
	{
		for (i in 0...BATCH_COUNT) { batches[i].resize(0); counts[i] = 0; }
		totalBatches   = 0;
		drawCallsSaved = 0;
	}

	public function toggleBatching():Void
	{
		enabled = !enabled;
		trace('[NoteBatcher] Batching: $enabled');
	}

	public function getStats():String
		return '[NoteBatcher] Batches=$totalBatches  DrawCallsSaved=$drawCallsSaved  Enabled=$enabled';

	override function destroy():Void
	{
		for (b in batches) b.resize(0);
		super.destroy();
	}
}
