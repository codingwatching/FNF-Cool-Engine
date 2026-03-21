package funkin.scripting;

/**
 * ScriptEvent — objeto de evento cancelable para el sistema de scripts.
 *
 * Permite que un script detenga el comportamiento por defecto del engine
 * devolviendo `true` desde un hook, o usando cancel() explícitamente.
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
	/** true si algún script llamó cancel() o devolvió true. */
	public var cancelled(default, null):Bool = false;

	/** Datos extra que el engine o el script pueden adjuntar al evento. */
	public var data:Dynamic = null;

	public function new(?data:Dynamic)
	{
		this.data = data;
	}

	/**
	 * Cancela el evento — el engine no ejecutará el comportamiento por defecto.
	 */
	public function cancel():Void
	{
		cancelled = true;
	}

	/**
	 * Restaura el evento a su estado inicial (no cancelado).
	 * Útil para reutilizar la misma instancia en varios scripts.
	 */
	public function reset(?newData:Dynamic):Void
	{
		cancelled = false;
		if (newData != null) data = newData;
	}
}
