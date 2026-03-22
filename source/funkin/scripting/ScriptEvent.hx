package funkin.scripting;

/**
 * ScriptEvent — objeto de evento cancelable para el sistema de scripts.
 *
 * Permite que un script detenga el comportamiento por defecto del engine
 * devolviendo `true` from a hook, or usando cancel() explicitly.
 *
 * ─── Uso desde HScript ───────────────────────────────────────────────────────
 *
 *   // En el script:
 *   function onNoteHit(note, event) {
 *     if (note.noteType == 'mine') {
 *       event.cancel();   // evitar que el engine procese esta nota
 *     }
 *   }
 *
 *   // En el engine (PlayState, etc.):
 *   var ev = new ScriptEvent();
 *   ScriptHandler.callOnScripts('onNoteHit', [note, ev]);
 *   if (!ev.cancelled) { /* comportamiento por defecto *\/ }
 *
 * ─── Uso desde Lua ────────────────────────────────────────────────────────────
 *
 *   function onNoteHit(note, event)
 *     if note.noteType == "mine" then
 *       event:cancel()
 *     end
 *   end
 */
class ScriptEvent
{
	/** true if some script llamó cancel() or devolvió true. */
	public var cancelled(default, null):Bool = false;

	/** Datos extra que el engine o el script pueden adjuntar al evento. */
	public var data:Dynamic = null;

	public function new(?data:Dynamic)
	{
		this.data = data;
	}

	/**
	 * Cancela the event — the engine no executeá the comportamiento by default.
	 */
	public function cancel():Void
	{
		cancelled = true;
	}

	/**
	 * Restaura el evento a su estado inicial (no cancelado).
	 * Useful for reutilizar the same instance in various scripts.
	 */
	public function reset(?newData:Dynamic):Void
	{
		cancelled = false;
		if (newData != null) data = newData;
	}
}
