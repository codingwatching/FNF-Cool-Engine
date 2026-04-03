package funkin.gameplay;

import flixel.FlxG;
import funkin.gameplay.notes.Note;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.input.keyboard.FlxKey;
import funkin.data.Conductor;
import funkin.data.SaveData;
import openfl.events.KeyboardEvent;
import openfl.Lib;
#if mobileC
import flixel.ui.FlxButton;
#end

using StringTools;

/**
 * InputHandler — Input del jugador con detección sub-frame via OpenFL.
 *
 * ── POR QUÉ OPENFL EN VEZ DE FlxG.keys ──────────────────────────────────
 *
 *  FlxG.keys.anyJustPressed() solo detecta pulsaciones al INICIO de cada
 *  frame (update loop). A 60fps eso son ~16.7ms de lag potencial; a 120fps
 *  ~8.3ms. En un juego de ritmo, esos ms importan.
 *
 *  openfl.events.KeyboardEvent.KEY_DOWN/KEY_UP se dispara en el momento
 *  exacto en que el sistema operativo entrega el evento, completamente
 *  independiente del framerate. Usamos openfl.Lib.getTimer() (ms desde
 *  el arranque del juego) para guardar el timestamp preciso de cada
 *  pulsación. Así la ventana de hit compara tiempos reales en ms en vez
 *  de "¿estaba pulsado cuando arrancó este frame?".
 *
 * ── MEJORAS vs versión anterior ──────────────────────────────────────────
 *
 *  1. DETECCIÓN SUB-FRAME: KEY_DOWN/KEY_UP se captura inmediatamente,
 *     no al próximo update(). Si el jugador pulsa y suelta dentro de un
 *     mismo frame (pulsación muy rápida), ambos eventos se registran.
 *
 *  2. TIMESTAMPS EN MS: _pressTimeMs[dir] guarda openfl.Lib.getTimer()
 *     del momento exacto del keydown. El buffer usa esos ms directamente
 *     en vez de FlxG.game.ticks / 1000.
 *
 *  3. REPEAT FILTERING: KEY_DOWN repite el evento mientras la tecla está
 *     pulsada. _rawHeld filtra los repeats — solo el primer evento cuenta
 *     como justPressed.
 *
 *  4. API COMPATIBLE: pressed/held/released/callbacks sin cambios.
 *     PlayState no necesita modificaciones.
 *
 * ── GHOST TAP OFF — misses diferidos ─────────────────────────────────────
 *
 *  Cuando ghost tapping está OFF y se pulsa sin nota en rango, el miss NO
 *  se dispara inmediatamente. Queda "pendiente" durante la ventana del
 *  buffer. Si una nota entra en canBeHit antes de que expire el buffer,
 *  se golpea normalmente y el miss se cancela. Solo si el buffer expira
 *  sin nota disponible se dispara el miss. Esto corrige false-misses cuando
 *  el jugador pulsa ligeramente antes de que la nota entre en la ventana.
 */
class InputHandler
{
	// === KEYBINDS ===
	public var leftBind:Array<FlxKey>  = [A, LEFT];
	public var downBind:Array<FlxKey>  = [S, DOWN];
	public var upBind:Array<FlxKey>    = [W, UP];
	public var rightBind:Array<FlxKey> = [D, RIGHT];
	public var killBind:Array<FlxKey>  = [R];

	// === INPUT STATE (consumidos en update, escritos por los listeners OpenFL) ===
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
	/** Ventana del buffer en SEGUNDOS (igual que antes, 0.1 = 100ms). */
	public var bufferTime:Float    = 0.1;

	// === ANTI-MASH ===
	private var mashCounter:Int    = 0;
	private var mashViolations:Int = 0;
	private static inline var MAX_MASH_VIOLATIONS:Int = 8;

	// === ESTADO CRUDO DEL LISTENER OPENFL ====================================
	// Estos flags los escribe el KEY_DOWN/KEY_UP handler inmediatamente,
	// y los consume update() al principio de cada frame.
	// _rawHeld    → la tecla está físicamente pulsada ahora mismo
	// _rawPressed → evento KEY_DOWN recibido desde el último update()
	//               (puede haber >1 si el framerate es bajo, solo nos importa 1)
	// _rawReleased→ evento KEY_UP recibido desde el último update()
	// _pressTimeMs→ openfl.Lib.getTimer() del KEY_DOWN más reciente (ms)
	private var _rawHeld:Array<Bool>     = [false, false, false, false];
	private var _rawPressed:Array<Bool>  = [false, false, false, false];
	private var _rawReleased:Array<Bool> = [false, false, false, false];
	private var _pressTimeMs:Array<Float> = [0, 0, 0, 0];

	// === PRESS-TIME SONG POSITION =============================================
	// Stores Conductor.songPosition at the exact moment of each keypress.
	// Used by PlayState.onPlayerNoteHit() so noteDiff reflects when the player
	// actually pressed, not when the buffered input fires (which can be up to
	// 100ms later, causing incorrect Sick ratings on early presses).
	public var pressSongPos:Array<Float> = [-1, -1, -1, -1];

	// === INPUT BUFFER ========================================================
	// bufferedInputs almacena el timestamp (ms) de la última pulsación no procesada.
	// inputProcessed se pone a true cuando esa pulsación logra golpear una nota.
	private var bufferedInputs:Array<Float> = [0, 0, 0, 0];
	private var inputProcessed:Array<Bool>  = [false, false, false, false];

	// === GHOST-TAP MISS DEFERRAL =============================================
	private var _pendingGhostMiss:Array<Bool> = [false, false, false, false];

	// === NOTAS POR DIRECCIÓN (preallocadas, cero allocs en hot path) =========
	private var _notesByDir0:Array<Note> = [];
	private var _notesByDir1:Array<Note> = [];
	private var _notesByDir2:Array<Note> = [];
	private var _notesByDir3:Array<Note> = [];

	// === CONTROLES MÓVILES ===================================================
	#if mobileC
	public var mobileLeft:FlxButton  = null;
	public var mobileDown:FlxButton  = null;
	public var mobileUp:FlxButton    = null;
	public var mobileRight:FlxButton = null;
	#end

	// ── CONSTRUCTOR ──────────────────────────────────────────────────────────

	public function new()
	{
		leftBind[0]  = FlxKey.fromString(SaveData.data.leftBind);
		downBind[0]  = FlxKey.fromString(SaveData.data.downBind);
		upBind[0]    = FlxKey.fromString(SaveData.data.upBind);
		rightBind[0] = FlxKey.fromString(SaveData.data.rightBind);
		killBind[0]  = FlxKey.fromString(SaveData.data.killBind);

		// Registrar listeners OpenFL — detección sub-frame
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown, false, 10);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP,   _onKeyUp,   false, 10);
	}

	/**
	 * Llamar cuando el InputHandler ya no se necesita (p.ej. en PlayState.destroy).
	 * Remueve los listeners de OpenFL para evitar fugas de memoria.
	 */
	public function destroy():Void
	{
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP,   _onKeyUp);
	}

	// ── LISTENERS OPENFL (sub-frame, máxima precisión) ───────────────────────

	/**
	 * Llamado en el momento exacto que el OS entrega el KEY_DOWN.
	 * NOTA: KEY_DOWN repite mientras la tecla está pulsada (key repeat del OS).
	 * _rawHeld filtra los repeats — solo el primer evento activa _rawPressed.
	 */
	private function _onKeyDown(e:KeyboardEvent):Void
	{
		var dir:Int = _keyCodeToDir(e.keyCode);
		if (dir < 0) return;

		if (!_rawHeld[dir])
		{
			// Primera pulsación real (no repeat) — guardar timestamp en ms
			_rawPressed[dir]  = true;
			_pressTimeMs[dir] = Lib.getTimer();
		}
		_rawHeld[dir] = true;
	}

	/**
	 * Llamado en el momento exacto que el OS entrega el KEY_UP.
	 */
	private function _onKeyUp(e:KeyboardEvent):Void
	{
		var dir:Int = _keyCodeToDir(e.keyCode);
		if (dir < 0) return;

		_rawHeld[dir]     = false;
		_rawReleased[dir] = true;
	}

	/**
	 * Mapea un keyCode de OpenFL a una dirección (0=L, 1=D, 2=U, 3=R).
	 * Devuelve -1 si el keyCode no corresponde a ningún bind.
	 * FlxKey es un Int que coincide con los keyCodes de OpenFL en todas
	 * las plataformas objetivo de Flixel.
	 */
	private function _keyCodeToDir(keyCode:Int):Int
	{
		// leftBind
		for (k in leftBind)  if ((k:Int) == keyCode) return 0;
		// downBind
		for (k in downBind)  if ((k:Int) == keyCode) return 1;
		// upBind
		for (k in upBind)    if ((k:Int) == keyCode) return 2;
		// rightBind
		for (k in rightBind) if ((k:Int) == keyCode) return 3;
		return -1;
	}

	// ── UPDATE ───────────────────────────────────────────────────────────────

	/**
	 * Consume los flags crudos escritos por los listeners OpenFL y los
	 * convierte en los arrays públicos pressed/held/released.
	 * Llamado una vez por frame desde PlayState.update().
	 */
	public function update():Void
	{
		for (dir in 0...4)
		{
			// pressed: hubo KEY_DOWN desde el último update
			pressed[dir]  = _rawPressed[dir];
			// held: la tecla está físicamente pulsada ahora
			held[dir]     = _rawHeld[dir];
			// released: hubo KEY_UP desde el último update
			released[dir] = _rawReleased[dir];

			// Disparar callbacks de release + limpiar flag
			if (_rawReleased[dir])
			{
				_rawReleased[dir] = false;
				if (onKeyRelease != null) onKeyRelease(dir);
			}

			// Limpiar pressed DESPUÉS de haberlo leído
			_rawPressed[dir] = false;
		}

		// ── Controles táctiles (mobile) ───────────────────────────────────
		#if mobileC
		_updateMobileButton(mobileLeft,  0);
		_updateMobileButton(mobileDown,  1);
		_updateMobileButton(mobileUp,    2);
		_updateMobileButton(mobileRight, 3);
		#end
	}

	#if mobileC
	private inline function _updateMobileButton(btn:FlxButton, dir:Int):Void
	{
		if (btn == null) return;

		var isPressed = (btn.status == flixel.ui.FlxButton.PRESSED);

		if (isPressed && !held[dir])
		{
			pressed[dir]      = true;
			_pressTimeMs[dir] = Lib.getTimer();
		}

		if (isPressed)
			held[dir] = true;

		if (!isPressed && held[dir] && !_rawHeld[dir])
		{
			released[dir] = true;
			if (onKeyRelease != null) onKeyRelease(dir);
		}
	}
	#end

	// ── PROCESS INPUTS ───────────────────────────────────────────────────────

	public function processInputs(notes:FlxTypedGroup<Note>):Void
	{
		if (funkin.gameplay.PlayState.isBotPlay)
		{
			pressed[0] = pressed[1] = pressed[2] = pressed[3] = false;
			held[0]    = held[1]    = held[2]    = held[3]    = false;
			released[0]= released[1]= released[2]= released[3]= false;

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

		// Timestamp actual en ms (OpenFL, sub-frame precision)
		final nowMs:Float = Lib.getTimer();

		var keysPressed:Int = 0;
		if (pressed[0]) keysPressed++;
		if (pressed[1]) keysPressed++;
		if (pressed[2]) keysPressed++;
		if (pressed[3]) keysPressed++;
		mashCounter = keysPressed;

		// Registrar nuevas pulsaciones en el buffer usando el timestamp OpenFL
		// (_pressTimeMs ya fue guardado en el momento exacto del KEY_DOWN,
		// no al inicio de este frame como hacía FlxG.game.ticks)
		for (dir in 0...4)
		{
			if (pressed[dir])
			{
				bufferedInputs[dir]    = _pressTimeMs[dir]; // ms del KEY_DOWN real
				inputProcessed[dir]    = false;
				_pendingGhostMiss[dir] = false;
				pressSongPos[dir]      = Conductor.songPosition; // song pos at actual keypress
			}
		}

		// Limpiar buckets preallocados
		_notesByDir0.resize(0);
		_notesByDir1.resize(0);
		_notesByDir2.resize(0);
		_notesByDir3.resize(0);

		// Clasificar notas por dirección
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

		if (_notesByDir0.length > 1) _notesByDir0.sort(_compareByStrumTime);
		if (_notesByDir1.length > 1) _notesByDir1.sort(_compareByStrumTime);
		if (_notesByDir2.length > 1) _notesByDir2.sort(_compareByStrumTime);
		if (_notesByDir3.length > 1) _notesByDir3.sort(_compareByStrumTime);

		_processDir(0, _notesByDir0, nowMs);
		_processDir(1, _notesByDir1, nowMs);
		_processDir(2, _notesByDir2, nowMs);
		_processDir(3, _notesByDir3, nowMs);

		// ── Misses diferidos de ghost-tap OFF ─────────────────────────────
		if (!ghostTapping)
		{
			for (dir in 0...4)
			{
				if (!_pendingGhostMiss[dir]) continue;
				if ((nowMs - bufferedInputs[dir]) > bufferTime * 1000)
				{
					_pendingGhostMiss[dir] = false;
					inputProcessed[dir]    = true;
					if (onNoteMiss != null) onNoteMiss(null);
				}
				else if (inputProcessed[dir])
				{
					_pendingGhostMiss[dir] = false;
				}
			}
		}
	}

	static function _compareByStrumTime(a:Note, b:Note):Int
		return Std.int(a.strumTime - b.strumTime);

	private inline function _processDir(dir:Int, possibleNotes:Array<Note>, nowMs:Float):Void
	{
		var hasValidInput = pressed[dir];

		// Buffer: la pulsación OpenFL fue hace menos de bufferTime segundos
		if (!hasValidInput && inputBuffering && !inputProcessed[dir])
			hasValidInput = (nowMs - bufferedInputs[dir]) <= bufferTime * 1000;

		if (!hasValidInput) return;

		if (possibleNotes.length > 0)
		{
			var canHit = !ghostTapping
				|| (mashCounter <= possibleNotes.length + 1)
				|| (mashViolations > MAX_MASH_VIOLATIONS);

			if (canHit)
			{
				if (onNoteHit != null)
				{
					onNoteHit(possibleNotes[0]);
					inputProcessed[dir]    = true;
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
			_pendingGhostMiss[dir] = true;
		}
	}

	// ── PROCESS SUSTAINS ─────────────────────────────────────────────────────

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

	// ── UTILIDADES ───────────────────────────────────────────────────────────

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
		pressSongPos[0] = pressSongPos[1] = pressSongPos[2] = pressSongPos[3] = -1;
	}

	public function anyKeyHeld():Bool
		return held[0] || held[1] || held[2] || held[3];
}
