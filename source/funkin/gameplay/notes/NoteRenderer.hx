package funkin.gameplay.notes;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import funkin.gameplay.notes.Note;
import funkin.gameplay.notes.NoteSplash;
import funkin.gameplay.notes.NoteHoldCover;
import funkin.gameplay.notes.NoteBatcher;

/**
 * NoteRenderer SUPER OPTIMIZADO
 *
 * ARQUITECTURA (pattern v-slice):
 * - NoteSplash    → solo splashes de hit en notas normales
 * - NoteHoldCover → covers visuales para hold notes (start → loop → end)
 * - Object pooling separado para cada tipo
 * - Cero allocs en los paths calientes (buffers preallocados)
 *
 * API public usada by NoteManager:
 * - getNote / recycleNote
 * - spawnSplash        (notas normales)
 * - recycleSplash
 * - startHoldCover     (inicio de hold note)
 * - stopHoldCover      (release o miss)
 * - updateHoldCovers   (clear covers orphaned, callr 1×/frame)
 * - updateBatcher
 * - clearPools / destroy
 */
class NoteRenderer
{
    // Referencias
    private var playerStrums:FlxTypedGroup<FlxSprite>;
    private var cpuStrums:FlxTypedGroup<FlxSprite>;

    // BUGFIX: The batcher internal of NoteRenderer never is adds to the FlxState
    // via add(), por lo que nunca se dibuja. Las notas se renderizan desde el
    // FlxTypedGroup<Note> that PlayState itself adds to the escena.
    public var noteBatcher:NoteBatcher = null;
    private var useBatching:Bool = false;

    // Config
    public var downscroll:Bool = false;
    public var strumLineY:Float = 50;
    public var noteSpeed:Float = 1.0;

    // OPTIMIZATION: pools separados para sustain vs normal.
    // BUGFIX: mezclarlos causaba que note.recycle() cambiara isSustainNote sin
    // recargar animaciones → WARNING "No animation called 'purpleScroll'" etc.
    // 24 + 24 = 48 objetos poolados — suficiente para canciones densas.
    // The value previous (50+50=100) mantenía demasiados FlxSprites vivos with
    // its textures, contribuyendo to the presión of RAM during gameplay.
    private var notePool:Array<Note>    = [];   // notas normales (cabeza)
    private var sustainPool:Array<Note> = [];   // hold pieces + tails
    private var maxPoolSize:Int = 24;

    // OPTIMIZATION: pool de splashes de hit normales
    private var splashPool:Array<NoteSplash> = [];
    private var maxSplashPoolSize:Int = 16;
    private var _splashNext:Int = 0; // index circular for or(1) amortizado in spawnSplash

    // NUEVO (v-slice): pool de NoteHoldCover
    public var holdCoverPool:Array<NoteHoldCover> = [];
    private var maxHoldCoverPoolSize:Int = 8;

    // Tracking of hold notes activas → cover asociado (keyed by direction 0-3)
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

    /**
     * Obtener nota del pool o crear una nueva.
     */
    public function getNote(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?mustHitNote:Bool = false):Note
    {
        var note:Note = null;
        final pool = sustainNote ? sustainPool : notePool;

        if (pool.length > 0)
        {
            note = pool.pop();
            note.recycle(strumTime, noteData, prevNote, sustainNote, mustHitNote);
            pooledNotes++;
        }
        else
        {
            note = new Note(strumTime, noteData, prevNote, sustainNote, mustHitNote);
            createdNotes++;
        }

        if (useBatching && noteBatcher != null)
            noteBatcher.addNoteToBatch(note);

        return note;
    }

    /**
     * Reciclar nota — devolverla al pool.
     */
    public function recycleNote(note:Note):Void
    {
        if (note == null) return;

        // Hold cover lifecycle is managed by direction in NoteManager.releaseHoldNote()

        if (useBatching && noteBatcher != null)
            noteBatcher.removeNoteFromBatch(note);

        try
        {
            final pool = note.isSustainNote ? sustainPool : notePool;
            if (pool.length < maxPoolSize)
            {
                note.kill();
                note.visible = false;
                note.active = false;
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
     * OPT: scan lineal reemplazado by search with index circular (_splashNext).
     *      The splashes is liberan fast (animation corta) → casi always the
     *      primer candidato is libre. Caso peor: itera the pool 1× (16 items max).
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

        // Pool full or empty → create new if there is hueco, if no reusar more old
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
        // maxHoldCoverPoolSize is a techo smooth — 4 dirs × 2 lados = 8 max simultáneos
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
     * Reproduce start → loop (automatic) → end (when is call stopHoldCover).
     *
     * Solo llamar si FlxG.save.data.notesplashes == true (el check lo hace NoteManager).
     * The caller debe add the resultado to the FlxGroup of the escena.
     *
     * @return The NoteHoldCover assigned, or null if already había uno for this note.
     */
    // strumCenterX/Y = centro visual del strum (strum.x + strum.width/2, strum.y + strum.height/2)
    public function startHoldCover(direction:Int, strumCenterX:Float, strumCenterY:Float, isPlayer:Bool = true, strumsGroupIndex:Int = 0, ?splashName:String):NoteHoldCover
    {
        // BUG FIX: include strumsGroupIndex in the key for that dos holds simultáneos
        // in the same direction but distintos grupos no compartan the same cover.
        // Player: 0-3 (grupo 0), 8-11 (grupo 1), ...
        // CPU:    4-7 (grupo 0), 12-15 (grupo 1), ...
        var key:Int = direction + (isPlayer ? strumsGroupIndex * 8 : 4 + strumsGroupIndex * 8);
        if (activeHoldCovers.exists(key))
            return activeHoldCovers.get(key);

        var cover = _getHoldCover(strumCenterX, strumCenterY, direction, splashName);
        cover.playStart();
        activeHoldCovers.set(key, cover);
        return cover;
    }

    /**
     * Detener el cover de una hold note (release o miss).
     * Reproduce the animation of fin; NoteHoldCover is mata only to the terminar.
     */
    public function stopHoldCover(direction:Int, isPlayer:Bool = true, strumsGroupIndex:Int = 0):Void
    {
        var key:Int = direction + (isPlayer ? strumsGroupIndex * 8 : 4 + strumsGroupIndex * 8);
        if (activeHoldCovers.exists(key))
        {
            var cover = activeHoldCovers.get(key);
            // If playEnd() returns false → cover in state "end_pending" (start still no acabó)
            // Is eliminará of the map igualmente; the cover is autodestruirá to the terminar its start
            if (cover != null) cover.playEnd();
            activeHoldCovers.remove(key);
        }
    }

    /**
     * Already no necesario: the lifecycle is manages explicitly
     * by direction in NoteManager (startHoldCover / stopHoldCover).
     * Se mantiene por compatibilidad con llamadas existentes.
     */
    public function updateHoldCovers():Void {}

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
     * Los hold covers se habilitan/deshabilitan mediante FlxG.save.data.notesplashes
     * en NoteManager.handleSustainNoteHit().
     */
    public function toggleHoldSplashes():Void
    {
        trace('[NoteRenderer] Hold covers controlados via FlxG.save.data.notesplashes en NoteManager');
    }

    public function getPoolStats():String
    {
        var stats = 'Notes: ${notePool.length + sustainPool.length}/$maxPoolSize';
        stats += ' (normal: ${notePool.length} sustain: ${sustainPool.length}';
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
        // Create dummy notes that immediately go back into the pool.
        for (i in 0...normalCount)
        {
            if (notePool.length >= maxPoolSize) break;
            try
            {
                var n = new Note(0, i % 4, null, false, false);
                n.kill(); // mark as dead so it's safe to recycle later
                notePool.push(n);
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
        trace('[NoteRenderer] Pool pre-warmed: ${notePool.length} normal + ${sustainPool.length} sustain notes');
    }

    public function clearPools():Void
    {
        // Hold covers activos — solo kill, NO destroy
        // (are in grpHoldCovers that PlayState destruirá correctly)
        for (dir in activeHoldCovers.keys())
        {
            var cover = activeHoldCovers.get(dir);
            if (cover != null) cover.kill();
        }
        activeHoldCovers.clear();

        // Note pool — these notes no are in no FlxGroup → destroy
        for (note in notePool)
            if (note != null) note.destroy();
        notePool = [];

        for (note in sustainPool)
            if (note != null) note.destroy();
        sustainPool = [];

        // Splash pool — are in grpNoteSplashes → only kill, no destroy
        for (splash in splashPool)
            if (splash != null) splash.kill();
        splashPool = [];

        // HoldCover pool — are in grpHoldCovers → only kill, no destroy
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
