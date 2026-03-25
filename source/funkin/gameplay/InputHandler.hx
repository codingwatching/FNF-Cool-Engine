package funkin.gameplay;

import flixel.FlxG;
import funkin.gameplay.notes.Note;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.input.keyboard.FlxKey;
import funkin.data.SaveData;
#if mobileC
import flixel.ui.FlxButton;
#end

using StringTools;

/**
 * InputHandler — Manejo de inputs del jugador.
 *
 * OPTIMIZACIONES vs versión anterior:
 *
 *  1. possibleNotesByDir es un Array<Array<Note>> PREALLOCADO como campo de instancia.
 *     Antes se creaba `[[], [], [], []]` cada frame → 5 allocs × 60fps = 300 allocs/seg
 *     de objetos de corta vida que presionan el GC. Ahora se hace .resize(0) en su lugar.
 *
 *  2. forEachAlive() eliminado del hot path. Creaba un closure (heap alloc) en cada llamada.
 *     Reemplazado por iteración directa sobre members[i] con chequeo manual alive/canBeHit.
 *
 *  3. Sort lambda reemplazado por función estática — cero closures en el sort.
 *
 *  4. processInputs y processSustains son llamados ~60-120 veces/seg;
 *     eliminar los closures es lo más importante de todo.
 *
 * GHOST TAP OFF — misses diferidos:
 *
 *  Cuando ghost tapping está desactivado, el miss NO se dispara inmediatamente
 *  al pulsar una tecla sin nota en rango. En su lugar queda "pendiente" durante
 *  la ventana del input buffer (~100ms). Si durante ese tiempo una nota entra en
 *  canBeHit, el input bufferizado la golpea normalmente y el miss se cancela.
 *  Solo si el buffer expira sin nota disponible se dispara el miss.
 *
 *  Esto corrige el problema de false-misses cuando el jugador pulsa ligeramente
 *  antes de que la nota entre en la ventana de hit (canBeHit usa una ventana early
 *  reducida de hitWindow/2.7 ≈ 61ms), que con ghost tap OFF resultaba en miss +
 *  buffer consumido + nota sin golpear.
 */
class InputHandler
{
	// === KEYBINDS ===
	public var leftBind:Array<FlxKey>  = [A, LEFT];
	public var downBind:Array<FlxKey>  = [S, DOWN];
	public var upBind:Array<FlxKey>    = [W, UP];
	public var rightBind:Array<FlxKey> = [D, RIGHT];
	public var killBind:Array<FlxKey>  = [R];

	// === INPUT STATE ===
	public var pressed:Array<Bool>  = [false, false, false, false];
	public var held:Array<Bool>     = [false, false, false, false];
	public var released:Array<Bool> = [false, false, false, false];

	// === CALLBACKS ===
	public var onNoteHit:Note->Void    = null;
	public var onNoteMiss:Note->Void   = null;
	public var onKeyRelease:Int->Void  = null;
	public var onKeyPress:Int->Void    = null;

	// === CONFIG ===
	public var ghostTapping:Bool   = true;
	public var inputBuffering:Bool = true;
	public var bufferTime:Float    = 0.1;

	// === ANTI-MASH ===
	private var mashCounter:Int    = 0;
	private var mashViolations:Int = 0;
	private static inline var MAX_MASH_VIOLATIONS:Int = 8;

	// === INPUT BUFFER ===
	private var bufferedInputs:Array<Float> = [0, 0, 0, 0];
	private var inputProcessed:Array<Bool>  = [false, false, false, false];

	// === GHOST-TAP MISS DEFERRAL ===
	// Cuando ghost tap está OFF y se pulsa sin nota disponible, el miss queda
	// pendiente aquí en lugar de dispararse inmediatamente. Se dispara al
	// expirar el buffer (si no se golpeó ninguna nota en ese tiempo).
	private var _pendingGhostMiss:Array<Bool> = [false, false, false, false];

	// ── PREALLOCADOS — cero allocs en el hot path ────────────────────────────
	// Antes: [[], [], [], []] nuevo cada frame = 5 allocs × 60fps = 300 allocs/seg
	// Ahora: resize(0) en su lugar — el array interno no se reasigna.
	private var _notesByDir0:Array<Note> = [];
	private var _notesByDir1:Array<Note> = [];
	private var _notesByDir2:Array<Note> = [];
	private var _notesByDir3:Array<Note> = [];

	// === CONTROLES MÓVILES ===
	// Se asignan desde PlayState cuando se compila con el flag mobileC.
	// Cada campo es un FlxButton cuya state (PRESSED/JUST_PRESSED/JUST_RELEASED)
	// se combina con el input de teclado para que ambos funcionen simultáneamente.
	#if mobileC
	public var mobileLeft:FlxButton  = null;
	public var mobileDown:FlxButton  = null;
	public var mobileUp:FlxButton    = null;
	public var mobileRight:FlxButton = null;
	#end

	public function new()
	{
		leftBind[0]  = FlxKey.fromString(SaveData.data.leftBind);
		downBind[0]  = FlxKey.fromString(SaveData.data.downBind);
		upBind[0]    = FlxKey.fromString(SaveData.data.upBind);
		rightBind[0] = FlxKey.fromString(SaveData.data.rightBind);
		killBind[0]  = FlxKey.fromString(SaveData.data.killBind);
	}

	// ─── UPDATE ──────────────────────────────────────────────────────────────

	public function update():Void
	{
		pressed[0] = pressed[1] = pressed[2] = pressed[3] = false;
		released[0] = released[1] = released[2] = released[3] = false;

		if (FlxG.keys.anyJustPressed(leftBind))  pressed[0] = true;
		if (FlxG.keys.anyJustPressed(downBind))  pressed[1] = true;
		if (FlxG.keys.anyJustPressed(upBind))    pressed[2] = true;
		if (FlxG.keys.anyJustPressed(rightBind)) pressed[3] = true;

		held[0] = FlxG.keys.anyPressed(leftBind);

		held[1] = FlxG.keys.anyPressed(downBind);
		held[2] = FlxG.keys.anyPressed(upBind);
		held[3] = FlxG.keys.anyPressed(rightBind);

		if (FlxG.keys.anyJustReleased(leftBind))
		{
			released[0] = true;
			if (onKeyRelease != null) onKeyRelease(0);
		}
		if (FlxG.keys.anyJustReleased(downBind))
		{
			released[1] = true;
			if (onKeyRelease != null) onKeyRelease(1);
		}
		if (FlxG.keys.anyJustReleased(upBind))
		{
			released[2] = true;
			if (onKeyRelease != null) onKeyRelease(2);
		}
		if (FlxG.keys.anyJustReleased(rightBind))
		{
			released[3] = true;
			if (onKeyRelease != null) onKeyRelease(3);
		}

		// ── Controles táctiles (mobile) ───────────────────────────────────────
		// Se combinan con OR con el teclado: si cualquiera de los dos registra
		// una pulsación, el estado queda activado para ese frame.
		#if mobileC
		_updateMobileButton(mobileLeft,  0);
		_updateMobileButton(mobileDown,  1);
		_updateMobileButton(mobileUp,    2);
		_updateMobileButton(mobileRight, 3);
		#end
	}

	#if mobileC
	/**
	 * Lee el estado de un FlxButton y lo combina (OR) con pressed/held/released.
	 * Inline para no generar overhead de llamada en el hot-path de 120fps.
	 */
	private inline function _updateMobileButton(btn:FlxButton, dir:Int):Void
	{
		if (btn == null) return;

		// FlxButton.status: FlxButton.NORMAL=0, HIGHLIGHT=1, PRESSED=2
		var isPressed = (btn.status == flixel.ui.FlxButton.PRESSED);

		// justPressed: estaba sin presionar el frame anterior, ahora sí
		if (isPressed && !held[dir])
			pressed[dir] = true;

		// held: mantenido (puede solapar con keyboard held)
		if (isPressed)
			held[dir] = true;

		// justReleased: estaba presionado el frame anterior, ahora no
		if (!isPressed && held[dir] && !FlxG.keys.anyPressed(
			switch (dir)
			{
				case 0: leftBind;
				case 1: downBind;
				case 2: upBind;
				default: rightBind;
			}))
		{
			released[dir] = true;
			if (onKeyRelease != null) onKeyRelease(dir);
		}
	}
	#end

	// ─── PROCESS INPUTS ──────────────────────────────────────────────────────

	/**
	 * Procesa inputs del jugador contra las notas disponibles.
	 *
	 * OPT: iteración directa sobre members[] en lugar de forEachAlive().
	 *      forEachAlive() asigna un closure nuevo en el heap cada llamada.
	 *      Con iteración directa hay cero allocs en este path.
	 *
	 * OPT: possibleNotesByDir usa arrays preallocados (resize vs new).
	 *
	 * OPT: sort comparator es función estática — cero closures.
	 */
	public function processInputs(notes:FlxTypedGroup<Note>):Void
	{
		if (funkin.gameplay.PlayState.isBotPlay)
		{
			pressed[0] = pressed[1] = pressed[2] = pressed[3] = false;
			held[0]    = held[1]    = held[2]    = held[3]    = false;
			released[0]= released[1]= released[2]= released[3]= false;

			// Iteración directa — sin closure
			final members = notes.members;
			final len = members.length;
			for (i in 0...len)
			{
				final note = members[i];
				if (note == null || !note.alive) continue;
				if (note.canBeHit && note.mustPress && !note.tooLate
					&& !note.wasGoodHit && !note.isSustainNote)
				{
					if (onNoteHit != null) onNoteHit(note);
					pressed[note.noteData] = true;
					if (onKeyPress != null) onKeyPress(note.noteData);
				}
			}
			return;
		}

		var keysPressed:Int = 0;
		if (pressed[0]) keysPressed++;
		if (pressed[1]) keysPressed++;
		if (pressed[2]) keysPressed++;
		if (pressed[3]) keysPressed++;
		mashCounter = keysPressed;

		final currentTime = FlxG.game.ticks / 1000.0;
		for (dir in 0...4)
		{
			if (pressed[dir])
			{
				bufferedInputs[dir] = currentTime;
				inputProcessed[dir] = false;
				// Nueva pulsación — cancelar cualquier miss pendiente de ghost tap
				// para esta dirección (el jugador volvió a pulsar antes de que
				// expirara el buffer anterior).
				_pendingGhostMiss[dir] = false;
			}
		}

		// Limpiar buckets preallocados — resize(0) no reasigna memoria interna
		_notesByDir0.resize(0);
		_notesByDir1.resize(0);
		_notesByDir2.resize(0);
		_notesByDir3.resize(0);

		// Clasificar notas por dirección — iteración directa, sin closure
		final members = notes.members;
		final len = members.length;
		for (i in 0...len)
		{
			final note = members[i];
			if (note == null || !note.alive) continue;
			if (note.canBeHit && note.mustPress && !note.tooLate
				&& !note.wasGoodHit && !note.isSustainNote)
			{
				switch (note.noteData)
				{
					case 0: _notesByDir0.push(note);
					case 1: _notesByDir1.push(note);
					case 2: _notesByDir2.push(note);
					case 3: _notesByDir3.push(note);
				}
			}
		}

		// Ordenar por tiempo (función estática — cero closures)
		if (_notesByDir0.length > 1) _notesByDir0.sort(_compareByStrumTime);
		if (_notesByDir1.length > 1) _notesByDir1.sort(_compareByStrumTime);
		if (_notesByDir2.length > 1) _notesByDir2.sort(_compareByStrumTime);
		if (_notesByDir3.length > 1) _notesByDir3.sort(_compareByStrumTime);

		_processDir(0, _notesByDir0, currentTime);
		_processDir(1, _notesByDir1, currentTime);
		_processDir(2, _notesByDir2, currentTime);
		_processDir(3, _notesByDir3, currentTime);

		// ── Misses diferidos de ghost-tap OFF ─────────────────────────────────
		// Disparar el miss pendiente solo si el buffer ya expiró Y no se golpeó
		// ninguna nota en esta dirección (inputProcessed sigue en false).
		// Si se golpeó una nota, inputProcessed pasó a true dentro de _processDir
		// y el miss queda cancelado.
		if (!ghostTapping)
		{
			for (dir in 0...4)
			{
				if (!_pendingGhostMiss[dir]) continue;
				// Buffer expirado sin nota → disparar miss
				if ((currentTime - bufferedInputs[dir]) > bufferTime)
				{
					_pendingGhostMiss[dir] = false;
					inputProcessed[dir]    = true;
					if (onNoteMiss != null) onNoteMiss(null);
				}
				// Si inputProcessed se puso a true por un hit en _processDir
				// (nota golpeada durante el buffer), también limpiar el pending.
				else if (inputProcessed[dir])
				{
					_pendingGhostMiss[dir] = false;
				}
			}
		}
	}

	/** Comparador estático — reutilizado por todos los sorts, cero allocs. */
	static function _compareByStrumTime(a:Note, b:Note):Int
		return Std.int(a.strumTime - b.strumTime);

	private inline function _processDir(dir:Int, possibleNotes:Array<Note>, currentTime:Float):Void
	{
		var hasValidInput = pressed[dir];

		if (!hasValidInput && inputBuffering && !inputProcessed[dir])
			hasValidInput = (currentTime - bufferedInputs[dir]) <= bufferTime;

		if (!hasValidInput) return;

		if (possibleNotes.length > 0)
		{
			// Sin ghost tapping el jugador ya paga misses por teclas sueltas,
			// así que la protección anti-mash no debe bloquear hits válidos.
			// Con ghost tapping ON la protección sigue activa para evitar
			// que el jugador spamee sin perder salud.
			var canHit = !ghostTapping
				|| (mashCounter <= possibleNotes.length + 1)
				|| (mashViolations > MAX_MASH_VIOLATIONS);

			if (canHit)
			{
				if (onNoteHit != null)
				{
					onNoteHit(possibleNotes[0]);
					inputProcessed[dir] = true;
					// Nota golpeada → cancelar miss pendiente si lo había
					_pendingGhostMiss[dir] = false;
				}
			}
			else
			{
				mashViolations++;
			}
		}
		else if (!ghostTapping && pressed[dir])
		{
			// No hay nota en rango pero el jugador pulsó — NO disparar miss
			// todavía. Marcar como pendiente para que el sistema de deferred
			// misses lo dispare solo cuando el buffer expire sin nota.
			// Esto evita falsos misses cuando el jugador pulsa ligeramente antes
			// de que la nota entre en la ventana de hit (canBeHit early window).
			_pendingGhostMiss[dir] = true;
			// NOTA: inputProcessed[dir] NO se pone a true aquí, para que el
			// buffer siga activo y pueda golpear la nota si llega a tiempo.
		}
	}

	// ─── PROCESS SUSTAINS ────────────────────────────────────────────────────

	/**
	 * Procesa sustain notes del jugador.
	 * OPT: iteración directa — sin forEachAlive/closure.
	 */
	public function processSustains(notes:FlxTypedGroup<Note>):Void
	{
		final members = notes.members;
		final len = members.length;

		if (funkin.gameplay.PlayState.isBotPlay)
		{
			for (i in 0...len)
			{
				final note = members[i];
				if (note == null || !note.alive) continue;
				if (note.mustPress && note.isSustainNote && !note.wasGoodHit
					&& note.canBeHit && !note.tooLate)
				{
					held[note.noteData] = true;
					if (onNoteHit != null) onNoteHit(note);
				}
			}
			return;
		}

		for (i in 0...len)
		{
			final note = members[i];
			if (note == null || !note.alive) continue;
			if (note.canBeHit && note.mustPress && note.isSustainNote
				&& !note.wasGoodHit && held[note.noteData])
			{
				if (onNoteHit != null) onNoteHit(note);
			}
		}
	}

	// No-op mantenido por compatibilidad
	public function checkMisses(notes:FlxTypedGroup<Note>):Void {}

	public function resetMash():Void
	{
		mashViolations = 0;
		mashCounter    = 0;
	}

	public function clearBuffer():Void
	{
		bufferedInputs[0] = bufferedInputs[1] = bufferedInputs[2] = bufferedInputs[3] = 0;
		inputProcessed[0] = inputProcessed[1] = inputProcessed[2] = inputProcessed[3] = false;
		_pendingGhostMiss[0] = _pendingGhostMiss[1] = _pendingGhostMiss[2] = _pendingGhostMiss[3] = false;
	}

	public function anyKeyHeld():Bool
		return held[0] || held[1] || held[2] || held[3];
}
