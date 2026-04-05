package funkin.gameplay.notes;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import funkin.gameplay.notes.Note;
import funkin.gameplay.notes.NoteSplash;
import funkin.gameplay.notes.NoteHoldCover;
import funkin.gameplay.notes.NoteBatcher;
import funkin.data.SaveData;

/**
 * NoteRenderer SUPER OPTIMIZADO
 *
 * ARQUITECTURA (patrón v-slice):
 * - NoteSplash    → solo splashes de hit en notas normales
 * - NoteHoldCover → covers visuales para hold notes (start → loop → end)
 * - Object pooling separado para cada tipo
 * - Cero allocs en los paths calientes (buffers preallocados)
 *
 * API pública usada por NoteManager:
 * - getNote / recycleNote
 * - spawnSplash        (notas normales)
 * - recycleSplash
 * - startHoldCover     (inicio de hold note)
 * - stopHoldCover      (release o miss)
 * - updateHoldCovers   (limpiar covers huérfanos, llamar 1×/frame)
 * - updateBatcher
 * - clearPools / destroy
 */
class NoteRenderer
{
    // Referencias
    private var playerStrums:FlxTypedGroup<FlxSprite>;
    private var cpuStrums:FlxTypedGroup<FlxSprite>;

    // BUGFIX: El batcher interno de NoteRenderer NUNCA se añade al FlxState
    // via add(), por lo que nunca se dibuja. Las notas se renderizan desde el
    // FlxTypedGroup<Note> que PlayState sí añade a la escena.
    public var noteBatcher:NoteBatcher = null;
    private var useBatching:Bool = false;

    // Config
    public var downscroll:Bool = false;
    public var strumLineY:Float = 50;
    public var noteSpeed:Float = 1.0;

    // OPTIMIZATION: pools separados para sustain vs normal.
    // BUGFIX skin cross-contamination: los pools ahora están separados por skin name.
    // Antes: un solo Array<Note> compartido → una nota de skin "cpuSkin" podía salir
    // del pool y asignarse a un personaje con skin "playerSkin". Si recycle() no
    // detectaba el cambio (campo _loadedSkinName stale, nombre coincidente, etc.),
    // la nota se mostraba con la skin incorrecta ("es rarísimo" pero reproducible).
    // Ahora: Map<skinName → Array<Note>> por tipo → una nota de skin X solo se
    // reutiliza para skin X. Si no hay nota disponible de la skin pedida, se busca
    // en otros pools (recycle() la actualizará) o se crea nueva.
    // Clave "" = skin global (groupSkin null/vacío).
    private var _notePoolMap:Map<String, Array<Note>>    = new Map();
    private var _sustainPoolMap:Map<String, Array<Note>> = new Map();
    private var maxPoolSize:Int = 24;  // máximo por skin-pool

    // OPTIMIZATION: pool de splashes de hit normales
    private var splashPool:Array<NoteSplash> = [];
    private var maxSplashPoolSize:Int = 16;
    private var _splashNext:Int = 0; // índice circular para O(1) amortizado en spawnSplash

    // NUEVO (v-slice): pool de NoteHoldCover
    public var holdCoverPool:Array<NoteHoldCover> = [];
    private var maxHoldCoverPoolSize:Int = 8;

    // Tracking de hold notes activas → cover asociado (keyed por dirección 0-3)
    private var activeHoldCovers:Map<Int, NoteHoldCover> = new Map();

    // Stats de pooling
    public var pooledNotes:Int = 0;
    public var pooledSplashes:Int = 0;
    public var createdNotes:Int = 0;
    public var createdSplashes:Int = 0;
    public var pooledHoldCovers:Int = 0;
    public var createdHoldCovers:Int = 0;

    // Constructor
    public function new(notes:FlxTypedGroup<Note>, playerStrums:FlxTypedGroup<FlxSprite>, cpuStrums:FlxTypedGroup<FlxSprite>)
    {
        this.playerStrums = playerStrums;
        this.cpuStrums = cpuStrums;

        trace('[NoteRenderer] Inicializado - Pool: $maxPoolSize notas, $maxSplashPoolSize splashes, $maxHoldCoverPoolSize holdCovers');
    }

    // ─────────────────────────── NOTE POOL ───────────────────────────────────

    /** Devuelve o inicializa el sub-pool para la skin dada (key "" = global). */
    private inline function _getPool(skinKey:String, isSustain:Bool):Array<Note>
    {
        final map = isSustain ? _sustainPoolMap : _notePoolMap;
        var pool = map.get(skinKey);
        if (pool == null) { pool = []; map.set(skinKey, pool); }
        return pool;
    }

    /**
     * Obtener nota del pool o crear una nueva.
     *
     * POOL STRATEGY (per-skin):
     *   1. Buscar en el pool exacto de la skin pedida → recycle sin cambiar skin.
     *   2. Si está vacío, buscar en cualquier otro pool → recycle cargará la skin nueva.
     *   3. Si todos vacíos, new Note() + loadSkin().
     *
     * Esto evita que una nota de skin "cpuSkin" se devuelva visualmente
     * con esa skin cuando el caller la espera con skin "playerSkin".
     */
    public function getNote(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?mustHitNote:Bool = false, ?groupSkin:String):Note
    {
        var note:Note = null;
        final skinKey:String = (groupSkin != null && groupSkin != '') ? groupSkin : '';
        final poolMap = sustainNote ? _sustainPoolMap : _notePoolMap;

        // 1. Pool de la skin exacta pedida
        final exactPool = _getPool(skinKey, sustainNote);
        if (exactPool.length > 0)
        {
            note = exactPool.pop();
            note.recycle(strumTime, noteData, prevNote, sustainNote, mustHitNote, groupSkin);
            pooledNotes++;
        }
        else
        {
            // 2. Cualquier otro pool disponible (recycle() cargará la skin correcta)
            var foundAny = false;
            for (pool in poolMap)
            {
                if (pool.length > 0)
                {
                    note = pool.pop();
                    note.recycle(strumTime, noteData, prevNote, sustainNote, mustHitNote, groupSkin);
                    pooledNotes++;
                    foundAny = true;
                    break;
                }
            }

            // 3. Sin notas en el pool: crear nueva
            if (!foundAny)
            {
                note = new Note(strumTime, noteData, prevNote, sustainNote, mustHitNote);
                if (groupSkin != null && groupSkin != '')
                {
                    var skinData = funkin.gameplay.notes.NoteSkinSystem.getCurrentSkinData(groupSkin);
                    if (skinData != null)
                        note.loadSkin(skinData);
                }
                createdNotes++;
            }
        }

        if (useBatching && noteBatcher != null)
            noteBatcher.addNoteToBatch(note);

        return note;
    }

    /**
     * Reciclar nota — devolverla al pool de su skin actual.
     * Usando note.loadedSkinName como clave, la nota vuelve al pool correcto
     * y solo será tomada por futuras notas de la misma skin.
     */
    public function recycleNote(note:Note):Void
    {
        if (note == null) return;

        if (useBatching && noteBatcher != null)
            noteBatcher.removeNoteFromBatch(note);

        try
        {
            // Clave del pool = skin cargada en la nota (loadedSkinName es public getter)
            final skinKey:String = (note.loadedSkinName != null && note.loadedSkinName != '') ? note.loadedSkinName : '';
            final pool = _getPool(skinKey, note.isSustainNote);

            if (pool.length < maxPoolSize)
            {
                note.kill();
                note.visible = false;
                note.active  = false;
                pool.push(note);
            }
            else
            {
                note.kill();
                note.destroy();
            }
        }
        catch (e:Dynamic)
        {
            trace('[NoteRenderer] Error reciclando nota: ' + e);
        }
    }

    // ────────────────────────── SPLASH POOL ──────────────────────────────────

    /**
     * Crear y devolver un splash de hit para una nota normal.
     * OPT: scan lineal reemplazado por búsqueda con índice circular (_splashNext).
     *      Los splashes se liberan rápido (animación corta) → casi siempre el
     *      primer candidato está libre. Caso peor: itera el pool 1× (16 items max).
     */
    public function spawnSplash(x:Float, y:Float, noteData:Int = 0, ?splashName:String):NoteSplash
    {
        final poolLen = splashPool.length;

        // Buscar desde _splashNext hacia adelante (circular)
        if (poolLen > 0)
        {
            for (k in 0...poolLen)
            {
                final idx = (_splashNext + k) % poolLen;
                final s = splashPool[idx];
                if (!s.inUse)
                {
                    _splashNext = (idx + 1) % poolLen;
                    s.setup(x, y, noteData, splashName);
                    pooledSplashes++;
                    return s;
                }
            }
        }

        // Pool lleno o vacío → crear nuevo si hay hueco, si no reusar más viejo
        var splash:NoteSplash;
        if (poolLen < maxSplashPoolSize)
        {
            splash = new NoteSplash();
            splashPool.push(splash);
            createdSplashes++;
        }
        else
        {
            splash = splashPool[_splashNext];
            _splashNext = (_splashNext + 1) % poolLen;
        }

        splash.setup(x, y, noteData, splashName);
        funkin.gameplay.notes.NoteSkinSystem.callSplashHook('onSplashSpawn', [splash, noteData, x, y]);
        return splash;
    }

    /**
     * Reciclar splash de hit.
     */
    public function recycleSplash(splash:NoteSplash):Void
    {
        if (splash == null) return;
        try { splash.kill(); }
        catch (e:Dynamic) { trace('[NoteRenderer] Error reciclando splash: ' + e); }
    }

    // ─────────────────────── HOLD COVER POOL (v-slice) ───────────────────────

    // strumCenterX / strumCenterY = centro visual del strum (strum.x + strum.width/2)
    private function _getHoldCover(strumCenterX:Float, strumCenterY:Float, noteData:Int, ?splashName:String):NoteHoldCover
    {
        // Buscar uno libre en el pool
        for (c in holdCoverPool)
        {
            if (!c.inUse)
            {
                c.setup(strumCenterX, strumCenterY, noteData, splashName);
                pooledHoldCovers++;
                return c;
            }
        }

        // Ninguno libre → crear siempre uno nuevo (nunca robar uno activo)
        // maxHoldCoverPoolSize es un techo suave — 4 dirs × 2 lados = 8 max simultáneos
        var cover = new NoteHoldCover();
        holdCoverPool.push(cover);
        createdHoldCovers++;
        cover.setup(strumCenterX, strumCenterY, noteData, splashName);
        return cover;
    }

    // ─────────────────────── API DE HOLD COVERS ──────────────────────────────

    /**
     * Registrar un cover pre-creado en el pool (usado para prewarm desde PlayState).
     * El cover debe estar muerto (kill() ya llamado) antes de registrar.
     */
    public function registerHoldCoverInPool(cover:NoteHoldCover):Void
    {
        if (holdCoverPool.indexOf(cover) < 0)
            holdCoverPool.push(cover);
    }

    /**
     * Iniciar cover visual para una hold note.
     * Reproduce start → loop (automático) → end (cuando se llama stopHoldCover).
     *
     * Solo llamar si SaveData.data.notesplashes == true (el check lo hace NoteManager).
     * El caller debe añadir el resultado al FlxGroup de la escena.
     *
     * @return El NoteHoldCover asignado, o null si ya había uno para esta nota.
     */
    // strumCenterX/Y = centro visual del strum (strum.x + strum.width/2, strum.y + strum.height/2)
    public function startHoldCover(direction:Int, strumCenterX:Float, strumCenterY:Float, isPlayer:Bool = true, strumsGroupIndex:Int = 0, ?splashName:String):NoteHoldCover
    {
        // BUG FIX: incluir strumsGroupIndex en la clave para que dos holds simultáneos
        // en la misma dirección pero distintos grupos no compartan el mismo cover.
        // Player: 0-3 (grupo 0), 8-11 (grupo 1), ...
        // CPU:    4-7 (grupo 0), 12-15 (grupo 1), ...
        var key:Int = direction + (isPlayer ? strumsGroupIndex * 8 : 4 + strumsGroupIndex * 8);
        if (activeHoldCovers.exists(key))
            return activeHoldCovers.get(key);

        var cover = _getHoldCover(strumCenterX, strumCenterY, direction, splashName);
        cover.playStart();
        activeHoldCovers.set(key, cover);
        funkin.gameplay.notes.NoteSkinSystem.callSplashHook('onHoldSplashSpawn', [cover, direction, strumCenterX, strumCenterY]);
        return cover;
    }

    /**
     * Detener el cover de una hold note (release o miss).
     * Reproduce la animación de fin; NoteHoldCover se mata solo al terminar.
     */
    public function stopHoldCover(direction:Int, isPlayer:Bool = true, strumsGroupIndex:Int = 0):Void
    {
        var key:Int = direction + (isPlayer ? strumsGroupIndex * 8 : 4 + strumsGroupIndex * 8);
        if (activeHoldCovers.exists(key))
        {
            var cover = activeHoldCovers.get(key);
            // Si playEnd() devuelve false → cover en estado "end_pending" (start aún no acabó)
            // Se eliminará del map igualmente; el cover se autodestruirá al terminar su start
            if (cover != null)
            {
                // CPU: matar el cover instantáneamente (sin animación de end), igual que V-Slice.
                // Player: reproducir la animación de end normalmente.
                if (!isPlayer)
                    cover.killInstant();
                else
                    cover.playEnd();
            }
            activeHoldCovers.remove(key);
        }
    }

    /**
     * Ya no necesario: el ciclo de vida se gestiona explícitamente
     * por dirección en NoteManager (startHoldCover / stopHoldCover).
     * Se mantiene por compatibilidad con llamadas existentes.
     */
    public function updateHoldCovers():Void {}

    /**
     * Re-center an active NoteHoldCover to a new strum position.
     * Called every frame from NoteManager._updateHoldCoverPositions() so
     * covers follow strums that move during modchart events or beat bumps.
     *
     * @param key  Internal key (same formula as startHoldCover/stopHoldCover).
     * @param cx   New strum center X in world coords.
     * @param cy   New strum center Y in world coords.
     */
    public function updateActiveCoverPosition(key:Int, cx:Float, cy:Float):Void
    {
        final cover = activeHoldCovers.get(key);
        if (cover != null && cover.inUse)
            cover.updatePosition(cx, cy);
    }

    // ─────────────────────── TOGGLE / STATS / BATCHER ────────────────────────

    public function updateBatcher():Void
    {
        if (useBatching && noteBatcher != null)
            noteBatcher.update(FlxG.elapsed);
    }

    public function toggleBatching():Void
    {
        useBatching = !useBatching;
        if (useBatching && noteBatcher == null)
            noteBatcher = new NoteBatcher();
        trace('[NoteRenderer] Batching: $useBatching');
    }

    /**
     * Alias mantenido para que NoteManager.toggleHoldSplashes() compile sin cambios.
     * Los hold covers se habilitan/deshabilitan mediante SaveData.data.notesplashes
     * en NoteManager.handleSustainNoteHit().
     */
    public function toggleHoldSplashes():Void
    {
        trace('[NoteRenderer] Hold covers controlados via SaveData.data.notesplashes en NoteManager');
    }

    public function getPoolStats():String
    {
        var normalCount = 0;
        var sustainCount = 0;
        for (p in _notePoolMap)    normalCount  += p.length;
        for (p in _sustainPoolMap) sustainCount += p.length;
        var stats = 'Notes: ${normalCount + sustainCount} (normal: $normalCount sustain: $sustainCount';
        stats += ' pooled: $pooledNotes created: $createdNotes)\n';
        stats += 'Splashes: ${splashPool.length}/$maxSplashPoolSize';
        stats += ' (pooled: $pooledSplashes created: $createdSplashes)\n';
        stats += 'HoldCovers: ${holdCoverPool.length}/$maxHoldCoverPoolSize';
        stats += ' (active: ${Lambda.count(activeHoldCovers)}';
        stats += ' pooled: $pooledHoldCovers created: $createdHoldCovers)\n';
        return stats;
    }

    // ──────────────────────────── LIMPIEZA ───────────────────────────────────

    /**
     * Pre-populate the note and sustain pools with dummy Note objects so that
     * the FIRST notes spawned in gameplay do not trigger a cold object-allocation
     * hitch.  Should be called after textures are already preloaded.
     *
     * @param normalCount   Notes to pre-create for normal (head) pool.
     * @param sustainCount  Notes to pre-create for sustain/hold pool.
     */
    public function prewarmPools(normalCount:Int = 8, sustainCount:Int = 16):Void
    {
        // Precalentar con la skin global (clave "") — suficiente para el inicio.
        // Las notas con skins de grupo se crean en el primer spawn (getNote step 3)
        // y luego quedan en su pool de skin correspondiente para los siguientes ciclos.
        final normalPool  = _getPool('', false);
        final sustainPool = _getPool('', true);

        for (i in 0...normalCount)
        {
            if (normalPool.length >= maxPoolSize) break;
            try
            {
                var n = new Note(0, i % 4, null, false, false);
                n.kill();
                normalPool.push(n);
            }
            catch (_:Dynamic) {}
        }
        for (i in 0...sustainCount)
        {
            if (sustainPool.length >= maxPoolSize) break;
            try
            {
                var n = new Note(0, i % 4, null, true, false);
                n.kill();
                sustainPool.push(n);
            }
            catch (_:Dynamic) {}
        }
        trace('[NoteRenderer] Pool pre-warmed: ${normalPool.length} normal + ${sustainPool.length} sustain notes (skin global)');
    }

    public function clearPools():Void
    {
        // Hold covers activos — solo kill, NO destroy
        for (dir in activeHoldCovers.keys())
        {
            var cover = activeHoldCovers.get(dir);
            if (cover != null) cover.kill();
        }
        activeHoldCovers.clear();

        // Note pools por skin — estas notas NO están en ningún FlxGroup → destruir
        for (pool in _notePoolMap)
            for (note in pool)
                if (note != null) note.destroy();
        _notePoolMap.clear();

        for (pool in _sustainPoolMap)
            for (note in pool)
                if (note != null) note.destroy();
        _sustainPoolMap.clear();

        // Splash pool — están en grpNoteSplashes → solo kill, NO destroy
        for (splash in splashPool)
            if (splash != null) splash.kill();
        splashPool = [];

        // HoldCover pool — están en grpHoldCovers → solo kill, NO destroy
        for (cover in holdCoverPool)
            if (cover != null) cover.kill();
        holdCoverPool = [];

        if (noteBatcher != null)
            noteBatcher.clearBatches();

        pooledNotes = 0;
        pooledSplashes = 0;
        _splashNext = 0;
        createdNotes = 0;
        createdSplashes = 0;
        pooledHoldCovers = 0;
        createdHoldCovers = 0;

        trace('[NoteRenderer] Pools limpiados');
    }

    public function destroy():Void
    {
        clearPools();

        if (noteBatcher != null)
        {
            noteBatcher.clearBatches();
            noteBatcher.destroy();
            noteBatcher = null;
        }

        playerStrums = null;
        cpuStrums = null;
    }
}
