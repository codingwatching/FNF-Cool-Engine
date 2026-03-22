package funkin.gameplay.notes;

/**
 * NotePool — STUB. The pool actual is in NoteRenderer (instance by song).
 *
 * Why does this stub exist?
 *  - The version previous tenía DOS systems of pool simultáneos:
 *      1. NotePool (static, FlxTypedSpriteGroup) — inicializado but never usado for
 *         spawning real. Sus notas prewarm'd eran RAM desperdiciada.
 *      2. NoteRenderer.notePool/sustainPool (by instance, Array<Note>) — the that itself
 *         maneja todas las notas en gameplay via getNote()/recycleNote().
 *  - Tener dos pools duplicaba GC pressure: 32 Note prewarm'd × 2 grupos = 64 objetos
 *    with textures that never is utilizaban, more the overhead of FlxTypedSpriteGroup.
 *  - Este stub mantiene la API para que OptimizationManager y PlayState compilen
 *    sin cambios mientras se elimina el pool duplicado.
 *
 * The pool actual is puede consultar via NoteRenderer.getPoolStats().
 */
class NotePool
{
	// Stats delegados al renderer activo (solo lectura)
	public static var totalCreated  : Int = 0;
	public static var totalRecycled : Int = 0;

	public static var inUse(get, never) : Int;
	static inline function get_inUse():Int return 0;

	/** No-op: el pool real es NoteRenderer, gestionado por NoteManager. */
	public static inline function init():Void {}

	/** No-op: NoteRenderer limpia su pool interno al destruirse. */
	public static inline function clear():Void {}

	/** No-op. */
	public static inline function destroy():Void {}

	/** No-op. */
	public static inline function forceGC():Void
	{
		#if cpp  cpp.vm.Gc.run(true);  #end
		#if hl   hl.Gc.major();        #end
	}

	public static function getStats():String
	{
		// The stats reales the reporta NoteRenderer via NoteManager.getPoolStats()
		// que OptimizationManager puede consultar si tiene ref a PlayState.
		return '[NotePool] Delegado a NoteRenderer — ver NoteManager.getPoolStats()';
	}
}
