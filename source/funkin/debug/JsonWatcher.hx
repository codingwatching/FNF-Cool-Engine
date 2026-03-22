package funkin.debug;

#if sys
import sys.FileSystem;
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.objects.stages.Stage;

/**
 * JsonWatcher — Watcher of files JSON with hot-reload automatic.
 *
 * Funcionamiento:
 *  • Registra paths de archivos JSON junto al nombre del recurso y su tipo.
 *  • Cada POLL_INTERVAL segundos, compara el mtime actual de cada archivo
 *    con el mtime registrado en el momento de `watch()`.
 *  • If the mtime changed → invalida the cache (Character or Stage) and fires
 *    el callback `onChange`.
 *
 * Uso:
 *  // Registrar un archivo a vigilar:
 *  JsonWatcher.watch('/absolute/path/to/bf.json', 'character', 'bf');
 *
 *  // Llamar desde MusicBeatState.update():
 *  JsonWatcher.poll(elapsed);
 *
 *  // Limpiar todo al cambiar de state:
 *  JsonWatcher.clear();
 *
 * El callback global `onChange` se llama con (resourceType, resourceName, path)
 * cuando se detecta un cambio. MusicBeatState lo usa para notificar al usuario
 * and, if is in PlayState + developerMode, reset automatically.
 */
class JsonWatcher
{
    // ── Entrada de registro ───────────────────────────────────────────────────

    private static var _entries : Map<String, WatchEntry> = [];

    // Acumulador de tiempo para throttle del poll
    private static var _timer : Float = 0.0;

    /** Intervalo entre polls en segundos. 0.5 = dos checks por segundo. */
    public static inline var POLL_INTERVAL : Float = 0.5;

    /**
     * Callback global invocado cuando se detecta un cambio en un archivo.
     * Firma: (type:String, name:String, path:String) → Void
     *
     * Tipos posibles: 'character', 'stage'
     */
    public static var onChange : (String, String, String) -> Void = null;

    // ── API public ───────────────────────────────────────────────────────────

    /**
     * Registra un archivo para ser vigilado.
     *
     * @param path  Path absoluto al archivo .json en disco.
     * @param type  Tipo de recurso: 'character' | 'stage'
     * @param name  Nombre del recurso (ej: 'bf', 'stage_week1')
     */
    public static function watch(path:String, type:String, name:String):Void
    {
        if (path == null || path == '' || !FileSystem.exists(path)) return;

        // Si ya estaba registrado con el mismo path, solo actualizamos el mtime
        // por si el archivo fue modificado entre el registro anterior y ahora.
        _entries.set(path, {
            path: path,
            type: type,
            name: name,
            mtime: _getMtime(path)
        });
    }

    /**
     * Llama esto cada frame desde MusicBeatState.update().
     * Hace el poll real solo cada POLL_INTERVAL segundos.
     */
    public static function poll(elapsed:Float):Void
    {
        _timer += elapsed;
        if (_timer < POLL_INTERVAL) return;
        _timer = 0;

        for (entry in _entries)
        {
            if (!FileSystem.exists(entry.path)) continue;

            final newMtime = _getMtime(entry.path);
            if (newMtime != entry.mtime)
            {
                entry.mtime = newMtime;
                _invalidate(entry);
            }
        }
    }

    /** Elimina todos los archivos registrados (llamar al cambiar de state). */
    public static function clear():Void
    {
        _entries.clear();
        _timer = 0;
    }

    /**
     * Elimina the log of a file specific.
     * Useful if a recurso is unloads but the state sigue active.
     */
    public static function unwatch(path:String):Void
        _entries.remove(path);

    /** Cantidad de archivos actualmente vigilados. */
    public static inline function count():Int
    {
        var n = 0;
        for (_ in _entries) n++;
        return n;
    }

    // ── Internos ──────────────────────────────────────────────────────────────

    /** Devuelve el mtime del archivo como Float (segundos epoch). */
    private static inline function _getMtime(path:String):Float
    {
        try { return FileSystem.stat(path).mtime.getTime(); }
        catch (_:Dynamic) { return 0; }
    }

    /**
     * Invalida the cache of the recurso and dispara the callback onChange.
     * Here is where is conecta with the systems of Character and Stage.
     */
    private static function _invalidate(entry:WatchEntry):Void
    {
        trace('[JsonWatcher] Cambio detectado: ${entry.type} "${entry.name}" → ${entry.path}');

        switch (entry.type)
        {
            case 'character':
                Character.invalidateCharCache(entry.name);

            case 'stage':
                Stage.invalidateStageCache(entry.name);

            case 'chart':
                // Without cache static — MusicBeatState.onChange resets the state.

            default:
                // Tipo desconocido — solo notificar
        }

        if (onChange != null)
            onChange(entry.type, entry.name, entry.path);
    }
}

// ── Estructura de entrada ─────────────────────────────────────────────────────

private typedef WatchEntry =
{
    path  : String,
    type  : String,
    name  : String,
    mtime : Float
}

#end // sys
