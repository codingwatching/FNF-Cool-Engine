package funkin.gameplay;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import funkin.gameplay.notes.Note;
import funkin.gameplay.notes.NoteRenderer;
import funkin.gameplay.notes.NoteSplash;
import funkin.gameplay.notes.NoteHoldCover;
import funkin.gameplay.notes.StrumNote;
import funkin.gameplay.objects.StrumsGroup;
import funkin.data.Song.SwagSong;
import funkin.data.Conductor;
import funkin.gameplay.notes.NoteSkinSystem;
import funkin.gameplay.modchart.ModChartManager;
import funkin.gameplay.modchart.ModChartEvent;
import funkin.gameplay.notes.NoteTypeManager;

using StringTools;

/**
 * Datos crudos de una nota — sin FlxSprite, sin texturas, sin DisplayObject.
 * Solo primitivas (~50 bytes/nota). Los FlxSprite se crean on-demand en spawnNotes().
 */
typedef NoteRawData =
{
	var strumTime:Float;
	var noteData:Int;
	var isSustainNote:Bool;
	var mustHitNote:Bool;
	var strumsGroupIndex:Int;
	var noteType:String;
	var sustainLength:Float;
}

class NoteManager
{
	// === GROUPS ===
	public var notes:FlxTypedGroup<Note>;
	/** Grupo separado para notas sustain — se dibuja DEBAJO de notes para que
	 *  las notas normales siempre aparezcan por encima de los holds. */
	public var sustainNotes:FlxTypedGroup<Note>;
	public var splashes:FlxTypedGroup<NoteSplash>;
	public var holdCovers:FlxTypedGroup<NoteHoldCover>;

	// Datos crudos — solo primitivas, cero FlxSprites hasta spawnNotes()
	private var unspawnNotes:Array<NoteRawData> = [];
	private var _unspawnIdx:Int = 0;
	// BUGFIX: trackeado by direction for avoid cross-chain in holds simultáneos
	private var _prevSpawnedNote:Map<Int, Note> = new Map();

	/** Calcula the key of the mapa _prevSpawnedNote combinando direction and grupo of strums.
	 *  noteData 0-3, strumsGroupIndex 0-N → key single by grupo of strums.
	 *  Necesario para que notas de distintos personajes/grupos en la misma
	 *  direction no compartan entry and corrompan the cadena prevNote of the sustains. */
	private inline function _prevNoteKey(noteData:Int, strumsGroupIndex:Int):Int
		return noteData + strumsGroupIndex * 4;

	// === STRUMS ===
	private var playerStrums:FlxTypedGroup<FlxSprite>;
	private var cpuStrums:FlxTypedGroup<FlxSprite>;
	private var playerStrumsGroup:StrumsGroup;
	private var cpuStrumsGroup:StrumsGroup;
	private var allStrumsGroups:Array<StrumsGroup>;

	// optimization: Cache of strums by direction — avoids forEach or(n) by note by frame.
	// Antes: 20 notas × 1 forEach × 4 iteraciones = 80 iteraciones+closures/frame.
	// Ahora: lookup O(1) directo en el Map.
	private var _playerStrumCache:Map<Int, FlxSprite> = [];
	private var _cpuStrumCache:Map<Int, FlxSprite> = [];
	private var _strumGroupCache:Map<Int, Map<Int, FlxSprite>> = [];

	// === RENDERER ===
	public var renderer:NoteRenderer;

	// === CONFIG ===
	public var strumLineY:Float = 50;
	public var downscroll:Bool = false;
	public var middlescroll:Bool = false;

	private var songSpeed:Float = 1.0;

	/**
	 * Referencia al ModChartManager activo (si hay modchart cargado).
	 * PlayState the asigna in create() after of create the ModChartManager.
	 * NoteManager la usa en updateNotePosition() para aplicar modificadores per-nota.
	 */
	public var modManager:Null<ModChartManager> = null;

	private static inline var CULL_DISTANCE:Float = 2000;

	private var _scrollSpeed:Float = 0.45;
	/** Last value of _scrollSpeed with the that is calcularon the sustainBaseScaleY.
	 *  Si cambia (modchart o evento de velocidad), recalculamos todos los sustains activos. */
	private var _lastSustainSpeed:Float = -1.0;


	// === SAVE.DATA CACHE (evita acceso Dynamic en hot loop) ===
	// Is actualizan in generateNotes() and when changes the configuration.
	private var _cachedNoteSplashes:Bool = false;

	private var _cachedMiddlescroll:Bool = false;

	/** Updates the cache of options of the jugador. Callr if the jugador changes config. */
	public function refreshSaveDataCache():Void {
		_cachedNoteSplashes  = FlxG.save.data.notesplashes == true;
		_cachedMiddlescroll  = FlxG.save.data.middlescroll == true;
	}

	// === CALLBACKS ===
	public var onNoteMiss:Note->Void = null;
	public var onCPUNoteHit:Note->Void = null;
	public var onNoteHit:Note->Void = null;

	// Hold note tracking
	private var heldNotes:Map<Int, Note> = new Map();
	private var holdStartTimes:Map<Int, Float> = new Map();
	/**
	 * Time exacto in that termina each hold by direction.
	 * Calculado al golpear el head note: headNote.strumTime + headNote.sustainLength.
	 * Comparar con songPosition cada frame para disparar playEnd() puntualmente.
	 */
	private var holdEndTimes:Map<Int, Float> = new Map();
	/** Same for CPU (by direction 0-3). */
	private var cpuHoldEndTimes:Array<Float> = [-1, -1, -1, -1];

	/** strumsGroupIndex of the hold cover active of the CPU by direction. */
	private var _cpuHoldGroupIdx:Array<Int> = [0, 0, 0, 0];

	/**
	 * Estado de teclas presionadas — actualizado desde PlayState cada frame
	 * (inputHandler.held[0..3]).  Usado for distinguir if a sustain is
	 * siendo mantenido o fue soltado antes de tiempo.
	 */
	public var playerHeld:Array<Bool> = [false, false, false, false];

	/**
	 * Direcciones (0-3) cuyos sustains ya contaron un miss este ciclo.
	 * OPTIMIZADO: Bool[4] en lugar de Map<Int,Bool> — elimina allocs de Map.clear()
	 * that ocurrían 60 veces/seg. Map.clear() in Haxe/C++ resetea the hashmap internal
	 * and puede do pequeñas allocations. Array fijo is or(1) set and or(1) clear.
	 */
	private var _missedHoldDir:Array<Bool> = [false, false, false, false];

	/** Buffer preallocado para autoReleaseFinishedHolds — cero allocs por frame */
	private var _autoReleaseBuffer:Array<Int> = [];

	/**
	 * Tracking of what directions is "manteniendo" the CPU (for hold covers).
	 * OPTIMIZADO: Bool[4] en lugar de Map<Int,Bool> — mismo razonamiento que _missedHoldDir.
	 */
	private var _cpuHeldDirs:Array<Bool> = [false, false, false, false];

	/**
	 * Set of NoteHoldCovers already added to the grupo holdCovers.
	 * OPTIMIZADO: reemplaza holdCovers.members.indexOf(cover) O(n) con lookup O(1).
	 * indexOf se llamaba en cada nota de hold activa (cada frame CPU hit) — con
	 * songs densas this is sum rápidamente.
	 */
	private var _holdCoverSet:haxe.ds.ObjectMap<NoteHoldCover, Bool> = new haxe.ds.ObjectMap();

	/** ClipRect reutilizable para sustains en downscroll — elimina `new FlxRect()` por frame */
	private var _sustainClipRect:flixel.math.FlxRect = new flixel.math.FlxRect();

	public function new(notes:FlxTypedGroup<Note>, playerStrums:FlxTypedGroup<FlxSprite>, cpuStrums:FlxTypedGroup<FlxSprite>,
			splashes:FlxTypedGroup<NoteSplash>, holdCovers:FlxTypedGroup<NoteHoldCover>, ?playerStrumsGroup:StrumsGroup, ?cpuStrumsGroup:StrumsGroup, ?allStrumsGroups:Array<StrumsGroup>,
			?sustainNotes:FlxTypedGroup<Note>)
	{
		this.notes = notes;
		this.sustainNotes = sustainNotes != null ? sustainNotes : notes; // fallback: usar mismo grupo si no se pasa
		this.playerStrums = playerStrums;
		this.cpuStrums = cpuStrums;
		this.splashes = splashes;
		this.holdCovers = holdCovers;
		this.playerStrumsGroup = playerStrumsGroup;
		this.cpuStrumsGroup = cpuStrumsGroup;
		this.allStrumsGroups = allStrumsGroups;
		renderer = new NoteRenderer(notes, playerStrums, cpuStrums);

		_rebuildStrumCache();
	}

	/**
	 * Reconstruye the cache of strums by direction.
	 * Callr after of cualquier cambio in the grupos of strums.
	 */
	public function _rebuildStrumCache():Void
	{
		_playerStrumCache = [];
		_cpuStrumCache = [];
		_strumGroupCache = [];

		if (playerStrums != null)
			playerStrums.forEach(function(s:FlxSprite)
			{
				_playerStrumCache.set(s.ID, s);
			});
		if (cpuStrums != null)
			cpuStrums.forEach(function(s:FlxSprite)
			{
				_cpuStrumCache.set(s.ID, s);
			});

		if (allStrumsGroups != null)
		{
			for (i in 0...allStrumsGroups.length)
			{
				var grp = allStrumsGroups[i];
				if (grp == null)
					continue;
				var map:Map<Int, FlxSprite> = [];
				// StrumsGroup has getStrum(dir) — we iterate the 4 standard directions
				for (dir in 0...4)
				{
					var s = grp.getStrum(dir);
					if (s != null)
						map.set(dir, s);
				}
				_strumGroupCache.set(i, map);
			}
		}
	}

	/**
	 * Genera SOLO datos crudos desde SONG data — cero FlxSprites instanciados.
	 */
	public function generateNotes(SONG:SwagSong):Void
	{
		_unspawnIdx = 0;
		_prevSpawnedNote.clear();
		songSpeed = SONG.speed;
		_scrollSpeed = 0.45 * FlxMath.roundDecimal(songSpeed, 2);
		_lastSustainSpeed = _scrollSpeed; // reset so first frame recalculates all

		// Cachear opciones del jugador ahora — se usan en el hot loop de notas
		refreshSaveDataCache();

		// ── v2: pre-calcular capacidad total para evitar resizes del array ────
		// Cada push() que supera la capacidad interna copia el array completo.
		// In songs with 800+ notes this causaba ~12 copias during the generación.
		var noteCount:Int = 0;
		for (section in SONG.notes)
			for (songNotes in section.sectionNotes)
			{
				noteCount++;
				var susLength:Float = songNotes[2];
				if (susLength > 0)
					noteCount += Math.floor(susLength / Conductor.stepCrochet);
			}

		// Pre-reservar: llenar con nulls tipados para reservar memoria interna,
		// luego truncar a 0 sin liberar. Los push() posteriores no reasignan.
		var _preAlloc:Array<Null<NoteRawData>> = [for (_ in 0...noteCount) null];
		unspawnNotes = cast _preAlloc;
		#if (cpp || hl)
		unspawnNotes.resize(0);
		#else
		unspawnNotes = [];
		#end

		for (section in SONG.notes)
		{
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				var rawNoteData:Int = Std.int(songNotes[1]);
				var daNoteData:Int = rawNoteData % 4;
				var groupIdx:Int = Math.floor(rawNoteData / 4);

				var gottaHitNote:Bool;
				if (allStrumsGroups != null && groupIdx < allStrumsGroups.length && groupIdx >= 2)
					gottaHitNote = !allStrumsGroups[groupIdx].isCPU;
				else
				{
					gottaHitNote = section.mustHitSection;
					if (groupIdx == 1)
						gottaHitNote = !section.mustHitSection;
				}

				var noteType:String = (songNotes.length > 3 && songNotes[3] != null) ? Std.string(songNotes[3]) : '';
				var susLength:Float = songNotes[2];

				unspawnNotes.push({
					strumTime: daStrumTime,
					noteData: daNoteData,
					isSustainNote: false,
					mustHitNote: gottaHitNote,
					strumsGroupIndex: groupIdx,
					noteType: noteType,
					sustainLength: susLength
				});

				if (susLength > 0)
				{
					var floorSus:Int = Math.floor(susLength / Conductor.stepCrochet);
					for (susNote in 0...floorSus)
					{
						unspawnNotes.push({
							strumTime: daStrumTime + (Conductor.stepCrochet * susNote) + Conductor.stepCrochet,
							noteData: daNoteData,
							isSustainNote: true,
							mustHitNote: gottaHitNote,
							strumsGroupIndex: groupIdx,
							noteType: noteType,
							sustainLength: 0
						});
					}
				}
			}
		}

		unspawnNotes.sort((a, b) -> Std.int(a.strumTime - b.strumTime));
		trace('[NoteManager] ${unspawnNotes.length} notas en cola (datos crudos)');
	}

	public function update(songPosition:Float):Void
	{
		spawnNotes(songPosition);
		updateActiveNotes(songPosition);
		updateStrumAnimations();
		autoReleaseFinishedHolds();
		if (renderer != null)
		{
			renderer.updateBatcher();
			renderer.updateHoldCovers();
		}
	}

	/**
	 * Libera holds cuyas piezas de sustain ya se consumieron.
	 * IMPORTANTE: revisa tanto notes.members (spawneadas) como unspawnNotes
	 * (futuras). Sin el check de unspawnNotes, holds largos se liberaban
	 * prematuramente porque the pieces futuras still no estaban in the grupo.
	 */
	/**
	 * Libera holds cuyo tiempo de fin (strumTime + sustainLength del head note)
	 * ya fue alcanzado por songPosition.
	 *
	 * FIX: antes usaba _hasPendingSustain que esperaba a que las notas salieran
	 * de pantalla. Ahora usamos el tiempo exacto de fin, que es conocido desde
	 * que golpeamos el head note. Esto dispara playEnd() en el momento correcto.
	 */
	private function autoReleaseFinishedHolds():Void
	{
		final songPos = Conductor.songPosition;

		// ── Jugador ──────────────────────────────────────────────────────────
		if (heldNotes.keys().hasNext())
		{
			_autoReleaseBuffer.resize(0);
			for (dir in heldNotes.keys())
			{
				// Usar holdEndTime if is available; fallback to _hasPendingSustain
				var shouldRelease:Bool;
				if (holdEndTimes.exists(dir))
					shouldRelease = songPos >= holdEndTimes.get(dir);
				else
					shouldRelease = !_hasPendingSustain(dir, true, sustainNotes.members, sustainNotes.members.length);
				if (shouldRelease)
					_autoReleaseBuffer.push(dir);
			}
			for (dir in _autoReleaseBuffer)
				releaseHoldNote(dir);
		}

		// ── CPU ──────────────────────────────────────────────────────────────
		var _anyCpuHeld = false;
		for (d in 0...4) if (_cpuHeldDirs[d]) { _anyCpuHeld = true; break; }
		if (_anyCpuHeld)
		{
			_autoReleaseBuffer.resize(0);
			for (dir in 0...4)
			{
				if (!_cpuHeldDirs[dir]) continue;
				var shouldRelease:Bool;
				if (cpuHoldEndTimes[dir] >= 0)
					shouldRelease = songPos >= cpuHoldEndTimes[dir];
				else
					shouldRelease = !_hasPendingSustain(dir, false, sustainNotes.members, sustainNotes.members.length);
				if (shouldRelease) _autoReleaseBuffer.push(dir);
			}
			for (dir in _autoReleaseBuffer)
			{
				if (renderer != null) renderer.stopHoldCover(dir, false, _cpuHoldGroupIdx[dir]);
				_cpuHeldDirs[dir] = false;
				cpuHoldEndTimes[dir] = -1;
				_cpuHoldGroupIdx[dir] = 0;
			}
		}
	}

	/**
	 * Returns true if quedan pieces of sustain pending for a direction,
	 * buscando tanto en las notas ya spawneadas como en las futuras (unspawnNotes).
	 * Sin revisar unspawnNotes, los holds largos se liberaban prematuramente.
	 */
	/**
	 * Returns true if quedan pieces of sustain still no COMPLETADAS for this direction.
	 *
	 * FIX: antes comprobaba `n.alive` y esperaba a que los sustains se salieran de pantalla.
	 * Ahora checks `!n.wasGoodHit && !n.tooLate` — the hold termina in cuanto the last
	 * pieza de sustain cruza la ventana de hit (wasGoodHit=true), no cuando sale de pantalla.
	 * This dispara the animation of fin of the hold cover in the momento correct.
	 */
	private function _hasPendingSustain(dir:Int, isPlayer:Bool, members:Array<Note>, len:Int):Bool
	{
		// 1. Notes spawneadas: pending = vivas, still no golpeadas and no perdidas
		for (i in 0...len)
		{
			final n = members[i];
			if (n != null && n.alive && n.isSustainNote && n.noteData == dir
				&& n.mustPress == isPlayer && !n.wasGoodHit && !n.tooLate)
				return true;
		}
		// 2. Notes futuras still no spawneadas — critical for holds largos
		for (i in _unspawnIdx...unspawnNotes.length)
		{
			final raw = unspawnNotes[i];
			if (raw.isSustainNote && raw.noteData == dir && raw.mustHitNote == isPlayer)
				return true;
		}
		return false;
	}

	private function spawnNotes(songPosition:Float):Void
	{
		final spawnTime:Float = 1800 / songSpeed;
		while (_unspawnIdx < unspawnNotes.length && unspawnNotes[_unspawnIdx].strumTime - songPosition < spawnTime)
		{
			final raw = unspawnNotes[_unspawnIdx++];

			final _pnKey = _prevNoteKey(raw.noteData, raw.strumsGroupIndex);
			final note = renderer.getNote(raw.strumTime, raw.noteData, _prevSpawnedNote.get(_pnKey), raw.isSustainNote, raw.mustHitNote);
			note.strumsGroupIndex = raw.strumsGroupIndex;
			note.noteType = raw.noteType;
			note.sustainLength = raw.sustainLength;
			note.visible = true;
			note.active = true;
			note.alpha = raw.isSustainNote ? 0.6 : 1.0;

			_prevSpawnedNote.set(_pnKey, note);
			// Sustain notes van al grupo separado (se dibuja ANTES que notes →
			// las notas normales siempre quedan por encima visualmente).
			if (raw.isSustainNote)
				sustainNotes.add(note);
			else
				notes.add(note);
			// Sin splice: el array NoteRawData es ~50 bytes/nota (trivial en RAM).
			// The splice or(n) causaba a hiccup visible to the 75% of the song.
		}
	}

	private function updateActiveNotes(songPosition:Float):Void
	{
		final hitWindow:Float = Conductor.safeZoneOffset;

		// V-Slice: if the scroll speed changed (event of speed or modchart),
		// recalcular sustainBaseScaleY de todos los sustains activos para que
		// no queden gaps ni solapamientos a velocidades muy altas/bajas.
		if (_scrollSpeed != _lastSustainSpeed)
		{
			_lastSustainSpeed = _scrollSpeed;
			_recalcAllSustainScales();
		}

		// Limpiar el set de miss-por-hold al inicio de cada frame
		// OPTIMIZADO: assignment directa × 4 vs Map.clear() that rehashea internamente
		_missedHoldDir[0] = false;
		_missedHoldDir[1] = false;
		_missedHoldDir[2] = false;
		_missedHoldDir[3] = false;

		// Iterar ambos grupos: primero sustains, luego notas normales
		_updateNoteGroup(sustainNotes.members, sustainNotes.members.length, songPosition, hitWindow);
		// Avoid doble-iteration if sustainNotes apunta to the same object that notes (fallback)
		if (sustainNotes != notes)
			_updateNoteGroup(notes.members, notes.members.length, songPosition, hitWindow);
	}

	private inline function _updateNoteGroup(members:Array<Note>, len:Int, songPosition:Float, hitWindow:Float):Void
	{
		// BUGFIX: iterar towards back for avoid that removeNote() corrompa the iteration.
		// removeNote() llama sustainNotes.remove(note, splice=true), que desplaza todos
		// the elementos posteriores a index towards the left. With iteration towards adelante
		// (for i in 0...len), the note in i+1 pasa to i justo after of procesarlo → is SALTA.
		// With various notes largas active simultáneamente is saltan various each frame:
		// sus posiciones y clipRects no se actualizan → glitches visuales en los holds.
		// Iterando towards back (len-1 → 0), the splice only afecta indices ≥ i (already processed).
		var i:Int = len;
		while (i > 0)
		{
			i--;
			final note = members[i];
			if (note == null || !note.alive)
				continue;

			updateNotePosition(note, songPosition);

			// ── CPU notes ──────────────────────────────────────────────────
			if (!note.mustPress && note.strumTime <= songPosition)
			{
				handleCPUNote(note);
				continue;
			}

			// ── Notas del jugador ──────────────────────────────────────────
			if (note.mustPress && !note.wasGoodHit)
			{
				// ── SUSTAIN NOTES: logic especial ─────────────────────────
				// Los sustains NO se eliminan por ventana de tiempo como las
				// notas normales.  Solo se eliminan si:
				//   a) The key is held → processed as hit in processSustains()
				//   b) The key is not held and strumTime already passed → miss (fade)
				//
				// FIX del bug "notas largas se rompen al final":
				//   The bug occurred because the player's sustains were entering the
				//   mismo bloque de miss que las notas normales y se eliminaban
				//   pieza a pieza cuando el strumTime superaba hitWindow.
				if (note.isSustainNote)
				{
					if (songPosition > note.strumTime + hitWindow)
					{
						var dir = note.noteData;
						if (playerHeld[dir])
						{
							// Key held: mark as hit but don't remove yet.
							// Dejamos que el clipRect oculte la pieza suavemente mientras scrollea
							// beyond the strum, avoiding the disappearing pieces effect.
							// Will be removed by culling when completely off screen.
							note.wasGoodHit = true;
							// Start hold cover if not done yet (this piece passed
							// el hitWindow sin pasar por processSustains/hitNote).
							handleSustainNoteHit(note);
						}
						else
						{
							// Tecla soltada: fallar el sustain
							// Desvanecer la nota en lugar de eliminarla (feedback visual)
							note.alpha = 0.2;
							note.tooLate = true;

							// Contar UN miss por grupo de hold, no uno por pieza
							if (!_missedHoldDir[dir])
							{
								_missedHoldDir[dir] = true;
								if (onNoteMiss != null)
									onNoteMiss(note);
							}
							// Remove the faded piece after it goes off screen
							removeNote(note);
						}
					}
					// If strumTime hasn't passed yet, do nothing — processSustains() handles it
					continue;
				}

				// ── NOTAS NORMALES: miss si pasan la ventana ───────────────
				if (note.tooLate || songPosition > note.strumTime + hitWindow)
				{
					note.tooLate = true;
					missNote(note);
					continue;
				}
			}

			// ── Visibilidad y culling ──────────────────────────────────────
			if (note.y < -CULL_DISTANCE || note.y > FlxG.height + CULL_DISTANCE)
			{
				note.visible = false;
				// Eliminar sustains consumidas que ya salieron de pantalla
				if (note.isSustainNote && note.wasGoodHit)
					removeNote(note);
			}
			else
			{
				// No sobrescribir visible=false de sustains consumidas ocultas por clipRect
				if (!(note.isSustainNote && note.wasGoodHit))
					note.visible = true;
				if (!note.mustPress && middlescroll)
					note.alpha = 0;
			}
		}
	}

	private function handleCPUNote(note:Note):Void
	{
		note.wasGoodHit = true;
		if (onCPUNoteHit != null)
			onCPUNoteHit(note);
		// Solo animar el strum en la nota cabeza, NO en las piezas de sustain.
		handleStrumAnimation(note.noteData, note.strumsGroupIndex, false);
		// Guardar tiempo de fin del hold para la CPU al golpear el HEAD note.
		// FIX: usar Math.max en lugar de sobrescribir directamente. Si hay dos holds
		// solapados in the same direction and the segundo termina before that the first,
		// the assignment directa cortaba the loop of the cover of the primer hold prematuramente.
		if (!note.isSustainNote && note.sustainLength > 0)
		{
			var newEnd = note.strumTime + note.sustainLength;
			if (cpuHoldEndTimes[note.noteData] < 0)
				cpuHoldEndTimes[note.noteData] = newEnd;
			else
				cpuHoldEndTimes[note.noteData] = Math.max(cpuHoldEndTimes[note.noteData], newEnd);
		}/*
		if (!note.isSustainNote && !_cachedMiddlescroll && _cachedNoteSplashes && renderer != null)
			createNormalSplash(note, false);*/
		// Hold covers para CPU: solo en la primera pieza de sustain
		if (note.isSustainNote && !_cachedMiddlescroll && _cachedNoteSplashes && renderer != null)
		{
			var dir = note.noteData;
			if (!_cpuHeldDirs[dir])
			{
				_cpuHeldDirs[dir] = true;
				_cpuHoldGroupIdx[dir] = note.strumsGroupIndex;
				var strum = getStrumForDirection(dir, note.strumsGroupIndex, false);
				if (strum != null)
				{
					var holdSplashCPU = NoteTypeManager.getHoldSplashName(note.noteType);
					var cover = renderer.startHoldCover(dir, strum.x - strum.offset.x + strum.frameWidth * 0.5, strum.y - strum.offset.y + strum.frameHeight * 0.5, false, note.strumsGroupIndex, holdSplashCPU);
					if (cover != null && !_holdCoverSet.exists(cover) && holdCovers.members.indexOf(cover) < 0) {
						_holdCoverSet.set(cover, true);
						holdCovers.add(cover);
					}
				}
			}
		}

		removeNote(note);
	}

	private function updateStrumAnimations():Void
	{
		_resetStrumsGroup(cpuStrums);
		_resetStrumsGroup(playerStrums);
	}

	private static inline function _resetStrumsGroup(group:FlxTypedGroup<FlxSprite>):Void
	{
		if (group == null)
			return;
		final members = group.members;
		final len = members.length;
		for (i in 0...len)
		{
			final strum = members[i];
			if (strum == null || !strum.alive)
				continue;
			final strumNote = cast(strum, funkin.gameplay.notes.StrumNote);
			if (strumNote == null) continue;
			final anim = strumNote.animation.curAnim;
			// OPT: comparar primer char 'c' antes de llamar startsWith (evita scan completo)
			// En la mayoria de frames el anim es 'static', que falla en el primer char.
			if (anim != null && anim.finished
				&& anim.name.length >= 7
				&& anim.name.charCodeAt(0) == 99 // 'c' de 'confirm'
				&& anim.name.startsWith('confirm'))
				strumNote.playAnim('static');
		}
	}

	/**
	 * V-Slice style: recalcula sustainBaseScaleY de todos los sustains activos
	 * when the scroll speed changes in mitad of a song (events of velocidad,
	 * modcharts, etc.). Sin esto, al cambiar la velocidad quedan gaps o solapamientos
	 * permanentes en los holds que ya estaban spawneados con el speed anterior.
	 */
	private function _recalcAllSustainScales():Void
	{
		final conductor = funkin.data.Conductor;
		if (conductor.stepCrochet <= 0) return;

		// Calcular el scale.y correcto para el nuevo speed
		// Fórmula igual that Note.setupSustainNote() with V-Slice approach
		inline function calcScaleY(note:funkin.gameplay.notes.Note):Float
		{
			if (note.frameHeight <= 0) return note.sustainBaseScaleY; // sin datos de frame
			final _speed:Float = songSpeed;
			final _stretch:Float = note._skinHoldStretch; // field public in Note
			final _extra:Float = (_speed > 3.0) ? ((_speed - 3.0) * 0.02) : 0.0;
			final targetH:Float = conductor.stepCrochet * 0.45 * _speed;
			return (targetH * (_stretch + _extra)) / note.frameHeight;
		}

		// Iterar sobre todos los sustains activos en el grupo de notas largas
		for (note in sustainNotes.members)
		{
			if (note == null || !note.alive || !note.isSustainNote) continue;
			// Solo piezas hold (no las colas/tails — tienen frameHeight distinto)
			var newSY = calcScaleY(note);
			if (newSY > 0 && newSY != note.sustainBaseScaleY)
			{
				note.sustainBaseScaleY = newSY;
				note.scale.y = newSY;
				note.updateHitbox();
				// Re-aplicar offset de skin: updateHitbox() llama centerOffsets() que lo resetea
				note.offset.x += note.noteOffsetX;
				note.offset.y += note.noteOffsetY;
			}
		}
	}

	private function handleStrumAnimation(noteData:Int, groupIndex:Int, isPlayer:Bool):Void
	{
		var strum = getStrumForDirection(noteData, groupIndex, isPlayer);
		if (strum != null)
		{
			var strumNote = cast(strum, funkin.gameplay.notes.StrumNote);
			if (strumNote != null)
				strumNote.playAnim('confirm', true);
		}
	}

	private function updateNotePosition(note:Note, songPosition:Float):Void
	{
		// ── Middlescroll: notas CPU completamente invisibles — no calcular nada ─
		// Hacerlo here (before of cualquier calculation) avoids the flash of 1 frame
		// that ocurría when updateNotePosition asignaba alpha=0.05 (floor of the
		// FlxMath.bound) and the override to 0 llegaba a tick after.
		if (_cachedMiddlescroll && !note.mustPress)
		{
			note.visible = false;
			note.clipRect = null;
			return;
		}

		// ── Get the strum first — its and is the referencia actual of position ──
		// The notes already seguían the X of the strum (strum.x + centered).
		// Ahora also siguen the and of the strum for that cualquier offset of strum
		// (by script, by song with strums in positions distintas, etc.)
		// se refleje correctamente en la trayectoria de la nota.
		// FIX: if no there is strum (note huérfana, race condition to the spawn), usar
		// strumLineY como fallback para no crashear y mantener comportamiento previo.
		var strum = getStrumForDirection(note.noteData, note.strumsGroupIndex, note.mustPress);
		final _refY:Float = (strum != null) ? strum.y : strumLineY;

		// ── Leer modificadores per-nota del ModChartManager (si existe) ────────
		var _modState:funkin.gameplay.modchart.StrumState = null;
		if (modManager != null && modManager.enabled)
		{
			// Resolver el groupId a partir del strumsGroupIndex de la nota
			var _groupId:String = null;
			if (allStrumsGroups != null && note.strumsGroupIndex < allStrumsGroups.length)
				_groupId = allStrumsGroups[note.strumsGroupIndex].id;
			if (_groupId == null)
				_groupId = note.mustPress ? "player" : "cpu";
			_modState = modManager.getState(_groupId, note.noteData);
		}

		// ── Scroll speed con multiplicador per-strum ────────────────────────────
		final _scrollMult:Float = (_modState != null) ? _modState.scrollMult : 1.0;

		// INVERT: invierte el eje de scroll solo para este strum.
		// Con invert=1, el signo del desplazamiento de tiempo se invierte,
		// producing notes "to the revés" without tocar the downscroll global.
		final _invertSign:Float  = (_modState != null && _modState.invert > 0.5) ? -1.0 : 1.0;
		final _effectiveSpeed:Float = _scrollSpeed * _scrollMult;

		// ── Position and base (referenciada to the strum) ─────────────────────────────
		var noteY:Float;
		if (downscroll)
			noteY = _refY + (songPosition - note.strumTime) * _effectiveSpeed * _invertSign;
		else
			noteY = _refY - (songPosition - note.strumTime) * _effectiveSpeed * _invertSign;

		// ── Y modifiers (BUG FIX v3: drunkY, noteOffsetY, bumpy, wave nunca se aplicaban) ─
		var _noteYOffset:Float = 0;
		if (_modState != null)
		{
			// NOTE_OFFSET_Y: offset plano en Y para todas las notas
			_noteYOffset += _modState.noteOffsetY;

			// DRUNK_Y: onda senoidal in and according to strumTime (espejo of drunkX in the eje and)
			if (_modState.drunkY != 0)
				_noteYOffset += _modState.drunkY * Math.sin(
					note.strumTime * 0.001 * _modState.drunkFreq
					+ songPosition * 0.0008
				);

			// BUMPY: all the notes of the strum oscilan in and joints according to songPosition.
			// Produce una ola "en bloque" que baja y sube todas las notas al mismo tiempo.
			if (_modState.bumpy != 0)
				_noteYOffset += _modState.bumpy * Math.sin(songPosition * 0.001 * _modState.bumpySpeed);

			// WAVE: ola and viajante — each note tiene desfase according to its strumTime.
			// Produce ondas que "viajan" de abajo hacia arriba por la columna de notas.
			if (_modState.wave != 0)
				_noteYOffset += _modState.wave * Math.sin(
					songPosition * 0.001 * _modState.waveSpeed
					- note.strumTime * 0.001
				);
		}
		noteY += _noteYOffset;

		// Para notas normales, Y es directo
		if (!note.isSustainNote)
			note.y = noteY;

		if (strum != null)
		{
			// ── Angle base of the strum ─────────────────────────────────────────
			var _finalAngle:Float = strum.angle;

			if (_modState != null)
			{
				// CONFUSION: rotation plana extra in each note
				_finalAngle += _modState.confusion;

				// TORNADO: each note rota according to its strumTime (effect carrusel).
				if (_modState.tornado != 0)
					_finalAngle += _modState.tornado * Math.sin(
						note.strumTime * 0.001 * _modState.drunkFreq
					);
			}

			note.angle = _finalAngle;

			// ── Escala / alpha ────────────────────────────────────────────────
			var newSX = strum.scale.x;
			final newSY = note.isSustainNote ? note.sustainBaseScaleY : strum.scale.y;

			// BEAT_SCALE: pulso de escala lanzado en cada beat desde onBeatHit
			if (_modState != null && _modState._beatPulse > 0)
				newSX = newSX * (1.0 + _modState._beatPulse);

			final scaleChanged = note.scale.x != newSX || note.scale.y != newSY;
			note.scale.x = newSX;
			note.scale.y = newSY;
			if (scaleChanged)
			{
				note.updateHitbox();
				note.offset.x += note.noteOffsetX;
				note.offset.y += note.noteOffsetY;
			}

			// ── Alpha: strum + NOTE_ALPHA override + STEALTH ─────────────────
			var _baseAlpha:Float = FlxMath.bound(strum.alpha, 0.05, 1.0);
			if (_modState != null)
			{
				// NOTE_ALPHA: multiplicador de alpha per-nota (independent del strum)
				_baseAlpha *= FlxMath.bound(_modState.noteAlpha, 0.0, 1.0);

				// STEALTH: completely invisible notes but still hittable
				if (_modState.stealth > 0.5)
					_baseAlpha = 0.0;
			}
			note.alpha = _baseAlpha;

			// ── Position X base ───────────────────────────────────────────────
			var _noteX:Float = strum.x + (strum.width - note.width) / 2;

			if (_modState != null)
			{
				// NOTE_OFFSET_X: offset plano en X
				_noteX += _modState.noteOffsetX;

				// DRUNK_X: onda senoidal en X usando strumTime de la nota.
				if (_modState.drunkX != 0)
					_noteX += _modState.drunkX * Math.sin(
						note.strumTime * 0.001 * _modState.drunkFreq
						+ songPosition * 0.0008
					);

				// TIPSY: ola X global por songPosition (todas las notas oscilan juntas en X)
				if (_modState.tipsy != 0)
					_noteX += _modState.tipsy * Math.sin(
						songPosition * 0.001 * _modState.tipsySpeed
					);

				// ZIGZAG: pattern escalonado in X alternando +amp / -amp
				if (_modState.zigzag != 0)
				{
					// sign(sin(x)) gives exactly +1 or -1, producing the step
					var _zz = Math.sin(note.strumTime * 0.001 * _modState.zigzagFreq * Math.PI);
					_noteX += _modState.zigzag * (_zz >= 0 ? 1.0 : -1.0);
				}

				// FLIP_X: espejo horizontal alrededor del centro del strum
				if (_modState.flipX > 0.5)
				{
					final _strumCenter = strum.x + strum.width / 2;
					_noteX = _strumCenter - (_noteX - _strumCenter + note.width / 2) - note.width / 2;
				}
			}

			note.x = _noteX;

			// ── Deformation dynamic of sustains ─────────────────────────────
			// Orienta each pieza towards the position of the pieza previous (the more
			// cercana al strum). BUG FIX v3: _prevY ahora incluye TODOS los
			// offsets Y (drunkY, bumpy, wave, noteOffsetY) evaluados en
			// _prevStrumTime, igual que se hace para el X.
			if (note.isSustainNote)
			{
				final _prevStrumTime:Float = note.strumTime - Conductor.stepCrochet;

				// Y base de la pieza anterior
				var _prevY:Float = downscroll
					? _refY + (songPosition - _prevStrumTime) * _effectiveSpeed * _invertSign
					: _refY - (songPosition - _prevStrumTime) * _effectiveSpeed * _invertSign;

				// Sumar los mismos Y-offsets evaluados en _prevStrumTime
				if (_modState != null)
				{
					_prevY += _modState.noteOffsetY;

					if (_modState.drunkY != 0)
						_prevY += _modState.drunkY * Math.sin(
							_prevStrumTime * 0.001 * _modState.drunkFreq
							+ songPosition * 0.0008
						);

					// bumpy y wave: usan songPosition, no strumTime → igual para ambas piezas
					// pero se incluyen para mantener coherencia visual en offsets grandes
					if (_modState.bumpy != 0)
						_prevY += _modState.bumpy * Math.sin(
							songPosition * 0.001 * _modState.bumpySpeed
						);

					if (_modState.wave != 0)
						_prevY += _modState.wave * Math.sin(
							songPosition * 0.001 * _modState.waveSpeed
							- _prevStrumTime * 0.001
						);
				}

				// X of the piece previous (already existía, is mantiene)
				var _prevX:Float = strum.x + (strum.width - note.width) / 2;
				if (_modState != null)
				{
					_prevX += _modState.noteOffsetX;

					if (_modState.drunkX != 0)
						_prevX += _modState.drunkX * Math.sin(
							_prevStrumTime * 0.001 * _modState.drunkFreq
							+ songPosition * 0.0008
						);

					if (_modState.tipsy != 0)
						_prevX += _modState.tipsy * Math.sin(
							songPosition * 0.001 * _modState.tipsySpeed
						);

					if (_modState.zigzag != 0)
					{
						var _zzP = Math.sin(_prevStrumTime * 0.001 * _modState.zigzagFreq * Math.PI);
						_prevX += _modState.zigzag * (_zzP >= 0 ? 1.0 : -1.0);
					}

					if (_modState.flipX > 0.5)
					{
						final _sc:Float = strum.x + strum.width / 2;
						_prevX = _sc - (_prevX - _sc + note.width / 2) - note.width / 2;
					}
				}

				// Vector towards the piece previous → angle of deformation
				final _dX:Float = _prevX - note.x;
				final _dY:Float = _prevY - note.y;

				final _rad:Float    = Math.atan2(_dY, _dX);
				final _deg:Float    = _rad * (180.0 / Math.PI);
				final _deform:Float = downscroll ? (_deg - 90.0) : (_deg + 90.0);

				note.angle = _finalAngle + _deform;

				final _deformRadAbs:Float = Math.abs(_deform * (Math.PI / 180.0));
				final _cosDeform:Float    = Math.cos(_deformRadAbs);
				final _seamOverlap:Float  = 4.0 / (note.frameHeight > 0 ? note.frameHeight : 1.0);
				note.scale.y = note.sustainBaseScaleY / (_cosDeform > 0.1 ? _cosDeform : 0.1) + _seamOverlap;
			}
		}

		// ── V-Slice style fade: desvanecer notas que pasan el strum ─────────
		// Solo aplica a notas del jugador que no fueron golpeadas
		if (note.mustPress && !note.wasGoodHit && !note.isSustainNote)
		{
			// Distancia from the centro of the strum towards the direction "pasada"
			// En upscroll: las notas vienen de abajo, pasan el strum hacia arriba (Y decrece)
			// En downscroll: las notas vienen de arriba, pasan el strum hacia abajo (Y crece)
			var distPast:Float;
			if (downscroll)
				distPast = note.and - strumLineY;   // positivo = below of the strum (passed)
			else
				distPast = strumLineY - note.and;    // positivo = above of the strum (passed)

			// Empezar to desvanecer to partir of 20px before of the strum, llegar to alpha 0 to 120px after
			final FADE_START:Float = -20.0;
			final FADE_END:Float   = 120.0;
			if (distPast > FADE_START)
			{
				var t = FlxMath.bound((distPast - FADE_START) / (FADE_END - FADE_START), 0.0, 1.0);
				// alpha va of 1.0 → 0.0, but mantenemos a minimum of 0.05 for that no sea invisible bruscamente
				note.alpha = FlxMath.lerp(1.0, 0.05, t);
			}
		}

		// ── Modificadores Y per-nota (antes de asignar Y final) ──────────────
		if (_modState != null && !note.isSustainNote)
		{
			// NOTE_OFFSET_Y: offset plano
			if (_modState.noteOffsetY != 0)
				note.y += _modState.noteOffsetY;

			// DRUNK_Y: onda senoidal en Y por strumTime.
			// Fase ligeramente distinta to drunkX for that no sean idénticas.
			if (_modState.drunkY != 0)
				note.y += _modState.drunkY * Math.sin(
					note.strumTime * 0.001 * _modState.drunkFreq
					+ songPosition * 0.001
				);

			// BUMPY: toda la columna oscila al mismo tiempo (mismo phase para todas las notas).
			// A diferencia de DRUNK_Y, no depende del strumTime individual.
			if (_modState.bumpy != 0)
				note.y += _modState.bumpy * Math.sin(songPosition * 0.001 * _modState.bumpySpeed);
		}

		// Position and of sustains: noteY directo (fórmula original).
		// scale.y fue calculado en setupSustainNote() para que la altura de cada pieza
		// coincida con el espacio entre strumTimes adyacentes (stepCrochet * scrollSpeed).
		// Any compensación of offset.and rompe that alineación cuerpo↔tail.
		if (note.isSustainNote)
			note.y = noteY;

		// BUGFIX: El clip de sustains debe aplicarse a TODAS las notas largas
		// (jugador y CPU, upscroll y downscroll). Antes solo se aplicaba a
		// CPU en downscroll, lo que causaba que los cuerpos de los holds
		// se vieran "rotos" o solapados con el strum en el resto de casos.
		// Furthermore, the clipRect never is limpiaba when dejaba of be necesario,
		// dejando el rect viejo de la nota anterior asignado a la nota actual.
		if (note.isSustainNote)
		{
			// BUGFIX: Cortar la nota exactamente en el CENTRO del strum, no en
			// el borde superior. halfStrum = mitad del ancho de una nota/strum,
			// que aproxima la mitad de la altura visual del strum arrow.
			// Antes: player usaba 0 (borde superior), CPU usaba 28 (muy poco).
			// Ahora ambos usan halfStrum (~56px) para que la nota desaparezca
			// justo en la mitad del strum en lugar de quedarse visible hasta
			// el borde exacto o desaparecer demasiado pronto.
			final halfStrum:Float = Note.swagWidth * 0.5;

			// Threshold ajustado according to direction of scroll (same for player and CPU).
			var strumLineThreshold = downscroll
				? strumLineY - halfStrum   // downscroll: threshold desplazado hacia arriba
				: strumLineY + halfStrum;  // upscroll:   threshold desplazado hacia dentro del strum

			if (downscroll)
			{
				// Downscroll: la nota baja de arriba hacia el strum.
				// Con flipY=true, el FRAME TOP = WORLD BOTTOM (parte que pasa el strum).
				// Clipeamos siempre que el fondo de la nota cruce el threshold, sin
				// esperar a wasGoodHit. Esto evita que el cuerpo del hold "sobresalga"
				// visualmente by debajo of the line of strums mientras is acerca.
				//
				// BUG FIX: the previous code used
				//   noteEndPos = note.y - note.offset.y * note.scale.y + note.height
				// that multiplica the offset by scale a segunda vez (already is in px mundo).
				// Con hold notes de scale.y alto, noteEndPos era absurdamente grande →
				// el clip siempre se activaba → clipRect.y negativo → artefactos visuales.
				// Correction: simply use note.y + note.height (bottom of the hitbox).
				final noteBottom:Float = note.y + note.height;
				if (noteBottom >= strumLineThreshold)
				{
					var clipH:Float = (strumLineThreshold - note.y) / note.scale.y;
					if (clipH <= 0)
					{
						// Nota completamente por debajo del threshold: nada que mostrar.
						// Si ya fue consumida, eliminarla del grupo.
						note.clipRect = null;
						if (note.wasGoodHit)
						{
							note.visible = false;
							removeNote(note);
						}
					}
					else
					{
						// clipH = frame pixels to show (frame bottom = world top = above the strum)
						_sustainClipRect.x      = 0;
						_sustainClipRect.width  = note.frameWidth * 2;
						_sustainClipRect.height = clipH;
						_sustainClipRect.y      = note.frameHeight - clipH;
						// Usar copyFrom en lugar de asignar referencia directa para
						// que cada nota tenga su propio rect y no compartan el mismo objeto.
						if (note.clipRect == null) note.clipRect = new flixel.math.FlxRect();
						note.clipRect.copyFrom(_sustainClipRect);
						note.clipRect = note.clipRect; // forzar update interno de Flixel
					}
				}
				else
				{
					note.clipRect = null;
				}
			}
			else
			{
				// Upscroll: la nota sube hacia el strum (Y decrece).
				// We clip the top part that already passed above the strum.
				if (note.y < strumLineThreshold)
				{
					var clipY:Float = (strumLineThreshold - note.y) / note.scale.y;
					var clipH:Float = note.frameHeight - clipY;
					if (clipH > 0 && clipY >= 0)
					{
						_sustainClipRect.x      = 0;
						_sustainClipRect.width  = note.frameWidth * 2;
						_sustainClipRect.y      = clipY;
						_sustainClipRect.height = clipH;
						if (note.clipRect == null) note.clipRect = new flixel.math.FlxRect();
						note.clipRect.copyFrom(_sustainClipRect);
						note.clipRect = note.clipRect; // forzar update interno de Flixel
					}
					else
					{
						// Nota completamente por encima del strum: ocultar si ya fue consumida
						// and remove it from the group to stop processing it every frame.
						if (note.isSustainNote && note.wasGoodHit)
						{
							note.visible = false;
							removeNote(note);
						}
						note.clipRect = null;
					}
				}
				else
				{
					note.clipRect = null;
				}
			}
		}
	}

	private function removeNote(note:Note):Void
	{
		note.kill();
		// Remover of the grupo correct according to type of note
		if (note.isSustainNote && sustainNotes != notes)
			sustainNotes.remove(note, true);
		else
			notes.remove(note, true);
		if (renderer != null)
			renderer.recycleNote(note);
	}

	public function hitNote(note:Note, rating:String):Void
	{
		if (note.wasGoodHit)
			return;
		note.wasGoodHit = true;
		handleStrumAnimation(note.noteData, note.strumsGroupIndex, true);
		// Guardar el tiempo de fin del hold al golpear el HEAD note.
		// BUG FIX: no sobreescribir if already there is a hold active for this direction.
		// FIX: usar Math.max for that holds solapados in the same direction no is
		// corten mutuamente. If already exists a time of end more tardío, it respetamos.
		if (!note.isSustainNote && note.sustainLength > 0)
		{
			var newEnd = note.strumTime + note.sustainLength;
			if (!holdEndTimes.exists(note.noteData))
				holdEndTimes.set(note.noteData, newEnd);
			else
				holdEndTimes.set(note.noteData, Math.max(holdEndTimes.get(note.noteData), newEnd));
		}
		if (rating == "sick")
		{
			if (note.isSustainNote)
				handleSustainNoteHit(note);
			else if (_cachedNoteSplashes && renderer != null)
				createNormalSplash(note, true);
		}
		// BUGFIX: The notes sustain no is eliminan here — quedan in the grupo
		// para que el clipRect de updateNotePosition las vaya ocultando
		// conforme cruzan the line of strums. Before is eliminaban of inmediato
		// cuando canBeHit && playerHeld, haciendo que desaparecieran ~hitWindow
		// ms (≈90px) antes de llegar visualmente al strum. Solo las notas normales
		// (cabeza de hold y notas simples) se eliminan inmediatamente.
		if (!note.isSustainNote)
			removeNote(note);
		if (onNoteHit != null)
			onNoteHit(note);
	}

	private function handleSustainNoteHit(note:Note):Void
	{
		var direction = note.noteData;
		if (!heldNotes.exists(direction))
		{
			heldNotes.set(direction, note);
			holdStartTimes.set(direction, Conductor.songPosition);

			// Hold covers only if the note splashes are activados in options
			if (_cachedNoteSplashes && renderer != null)
			{
				var strum = getStrumForDirection(direction, note.strumsGroupIndex, true);
				if (strum != null)
				{
					var holdSplashPlayer = NoteTypeManager.getHoldSplashName(note.noteType);
					var cover = renderer.startHoldCover(direction, strum.x - strum.offset.x + strum.frameWidth * 0.5, strum.y - strum.offset.y + strum.frameHeight * 0.5, true, note.strumsGroupIndex, holdSplashPlayer);
					// BUGFIX: indexOf evita doble-add de covers pre-calentados que ya
					// are in the group → double update/draw caused duplicated animation.
					if (cover != null && !_holdCoverSet.exists(cover) && holdCovers.members.indexOf(cover) < 0) {
						_holdCoverSet.set(cover, true);
						holdCovers.add(cover);
					}
				}
			}
		}
		// No callr removeNote here — hitNote() already it hace after
	}

	public function releaseHoldNote(direction:Int):Void
	{
		if (!heldNotes.exists(direction))
			return;
		if (renderer != null)
			renderer.stopHoldCover(direction);
		heldNotes.remove(direction);
		holdStartTimes.remove(direction);
		holdEndTimes.remove(direction);
	}

	private function createNormalSplash(note:Note, isPlayer:Bool):Void
	{
		if (renderer == null)
			return;
		var strum = getStrumForDirection(note.noteData, note.strumsGroupIndex, isPlayer);
		if (strum != null)
		{
			var splashName = NoteTypeManager.getSplashName(note.noteType);
		var splash = renderer.spawnSplash(strum.x, strum.y, note.noteData, splashName);
			if (splash != null)
				splashes.add(splash);
		}
	}

	/**
	 * Gets the strum for a direction dada.
	 * OPTIMIZADO: use cache Map<Int, FlxSprite> for or(1) in vez of forEach or(n).
	 * El forEach anterior creaba una closure nueva cada llamada — ahora es solo
	 * un Map lookup. Con 20 notas en pantalla esto elimina ~80 closures por frame.
	 */
	private function getStrumForDirection(direction:Int, strumsGroupIndex:Int, isPlayer:Bool):FlxSprite
	{
		// Grupos adicionales (strumsGroupIndex >= 2) — cache by grupo
		if (allStrumsGroups != null && allStrumsGroups.length > 0 && strumsGroupIndex >= 2)
		{
			var groupMap = _strumGroupCache.get(strumsGroupIndex);
			if (groupMap != null)
				return groupMap.get(direction);
		}

		// Grupos 0 and 1 — cache by direction
		return isPlayer ? _playerStrumCache.get(direction) : _cpuStrumCache.get(direction);
	}

	public function missNote(note:Note):Void
	{
		if (note == null || note.wasGoodHit)
			return;
		// For sustains: already is contó the miss in updateActiveNotes, no return to contar
		if (heldNotes.exists(note.noteData))
			releaseHoldNote(note.noteData);
		if (onNoteMiss != null && !note.isSustainNote)
			onNoteMiss(note);
		removeNote(note);
	}

	// ─── Rewind Restart (V-Slice style) ──────────────────────────────────────

	/**
	 * Updates only the position visual of the notes activas — without spawn ni kill.
	 * Callr during the animation of rewind for that the notes deslicen towards back.
	 */
	public function updatePositionsForRewind(songPosition:Float):Void
	{
		_rewindUpdateGroup(sustainNotes.members, sustainNotes.members.length, songPosition);
		if (sustainNotes != notes)
			_rewindUpdateGroup(notes.members, notes.members.length, songPosition);
		if (renderer != null)
			renderer.updateBatcher();
	}

	private inline function _rewindUpdateGroup(members:Array<Note>, len:Int, songPosition:Float):Void
	{
		for (i in 0...len)
		{
			final note = members[i];
			if (note == null || !note.alive)
				continue;
			updateNotePosition(note, songPosition);
			if (note.y < -CULL_DISTANCE || note.y > FlxG.height + CULL_DISTANCE)
				note.visible = false;
			else
				note.visible = true;
		}
	}

	/**
	 * Mata all the notes activas and retrocede the index of spawn
	 * al punto correcto para `targetTime` (generalmente inicio del countdown).
	 * Callr to the finalizar the animation of rewind.
	 */
	public function rewindTo(targetTime:Float):Void
	{
		// Matar todas las notas vivas en ambos grupos
		if (sustainNotes != notes)
		{
			var i = sustainNotes.members.length - 1;
			while (i >= 0)
			{
				var n = sustainNotes.members[i];
				if (n != null && n.alive)
					removeNote(n);
				i--;
			}
		}
		var i = notes.members.length - 1;
		while (i >= 0)
		{
			var n = notes.members[i];
			if (n != null && n.alive)
				removeNote(n);
			i--;
		}

		_prevSpawnedNote.clear();
		heldNotes.clear();
		_cpuHeldDirs[0] = _cpuHeldDirs[1] = _cpuHeldDirs[2] = _cpuHeldDirs[3] = false;
		_cpuHoldGroupIdx[0] = _cpuHoldGroupIdx[1] = _cpuHoldGroupIdx[2] = _cpuHoldGroupIdx[3] = 0;
		holdStartTimes.clear();
		holdEndTimes.clear();
		cpuHoldEndTimes[0] = cpuHoldEndTimes[1] = cpuHoldEndTimes[2] = cpuHoldEndTimes[3] = -1;
		_missedHoldDir[0] = _missedHoldDir[1] = _missedHoldDir[2] = _missedHoldDir[3] = false;
		playerHeld = [false, false, false, false];
		_holdCoverSet.clear();

		// BUGFIX escala pixel: limpiar el pool de notas para que las nuevas se creen
		// desde cero con la skin activa correcta. Sin esto, notas recicladas del pool
		// pueden have _noteScale = 0.7 (Default) if the skin is corrompió during the game,
		// causando that the notes pixel (scale 6.0) aparezcan in size of notes normales.
		if (renderer != null)
			renderer.clearPools();

		// Retroceder the index of spawn:
		// queremos empezar a spawnear desde notas cuyo strumTime ≥ targetTime - spawnWindow
		final spawnWindow:Float = 1800.0 / (songSpeed > 0 ? songSpeed : 1.0);
		var cutoff:Float = targetTime - spawnWindow;

		_unspawnIdx = 0;
		// If targetTime is negativo (countdown), cutoff also is negativo → _unspawnIdx = 0 (correct)
		if (cutoff > 0)
		{
			while (_unspawnIdx < unspawnNotes.length && unspawnNotes[_unspawnIdx].strumTime < cutoff)
				_unspawnIdx++;
		}

		trace('[NoteManager] rewindTo($targetTime) → _unspawnIdx=$_unspawnIdx / ${unspawnNotes.length}');
	}

	public function destroy():Void
	{
		unspawnNotes = [];
		_unspawnIdx = 0;
		_prevSpawnedNote.clear();
		heldNotes.clear();
		_cpuHeldDirs[0] = _cpuHeldDirs[1] = _cpuHeldDirs[2] = _cpuHeldDirs[3] = false;
		_cpuHoldGroupIdx[0] = _cpuHoldGroupIdx[1] = _cpuHoldGroupIdx[2] = _cpuHoldGroupIdx[3] = 0;
		holdStartTimes.clear();
		holdEndTimes.clear();
		cpuHoldEndTimes[0] = cpuHoldEndTimes[1] = cpuHoldEndTimes[2] = cpuHoldEndTimes[3] = -1;
		_missedHoldDir[0] = _missedHoldDir[1] = _missedHoldDir[2] = _missedHoldDir[3] = false;
		_holdCoverSet.clear();
		_playerStrumCache = [];
		_cpuStrumCache = [];
		_strumGroupCache = [];
		sustainNotes = null;
		if (renderer != null)
		{
			renderer.clearPools();
			renderer.destroy();
		}
	}

	public function getPoolStats():String
		return renderer != null ? renderer.getPoolStats() : "No renderer";

	public function toggleBatching():Void
		if (renderer != null)
			renderer.toggleBatching();

	public function toggleHoldSplashes():Void
		if (renderer != null)
			renderer.toggleHoldSplashes();
}
