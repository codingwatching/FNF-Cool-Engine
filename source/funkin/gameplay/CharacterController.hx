package funkin.gameplay;

import funkin.gameplay.objects.character.Character;
import funkin.gameplay.objects.character.CharacterSlot;
import flixel.FlxG;
import funkin.data.Conductor;

using StringTools;

/**
 * CharacterController — Gestiona todos los personajes de la partida.
 *
 * ── Mejoras respecto to the version previous ──────────────────────────────────
 *
 *  BUG FIX 1  `initFromSlots` ya NO asume [0]=GF, [1]=DAD, [2]=BF.
 *             Las refs legacy (boyfriend / dad / gf) se resuelven buscando
 *             por `slot.charType`, por lo que funcionan aunque los personajes
 *             are in any position of the array.
 *
 *  BUG FIX 2  `danceOnBeat` ya NO usa `slot.index == 0` para identificar GF.
 *             Usa `slot.isGFSlot` (que lee `charType` y el flag `isGF`).
 *
 *  BUG FIX 3  `sing()` legacy ya NO suprime altAnim para BF.
 *             The supresión silenciosa (`if (char == boyfriend) altAnim = ""`)
 *             hacía that cartas with -alt never is mostraran for the player.
 *
 *  BUG FIX 4  `singByType()` nuevo: anima TODOS los chars de un tipo dado
 *             (useful when there is 2 oponentes activos to the vez).
 *
 *  BUG FIX 5  `findPlayerIndex()` / `findOpponentIndex()` / `findGFIndex()`
 *             buscan by type, no by index hardcodeado. PlayState the use
 *             en lugar de las constantes 2 / 1 / 0.
 *
 *  BUG FIX 6  `findByStrumsGroup(id)` devuelve el PRIMER slot vinculado a
 *             un StrumsGroup dado. Usado por PlayState para mapear notas CPU
 *             → character correct when there is multiple grupos CPU.
 *
 *  BUG FIX 7  `singGF(noteData)` — llama a `sing(..., forceSing:true)` en
 *             todos los slots GF. Llamado desde PlayState cuando gfSing=true.
 *
 *  BUG FIX 8  `updateLegacyAnimations` removida del path normal.
 *             The chars are add()-eados to the FlxState and Flixel already call its
 *             `update()` automatically. Ejecutar logic of idle here
 *             also causaba flickering. The bloque legacy only is active
 *             cuando `characterSlots.length == 0` (modo 100% legacy).
 */
class CharacterController
{
	// ── Array principal ───────────────────────────────────────────────────────
	public var characterSlots:Array<CharacterSlot> = [];

	// ── References legacy (for scripts and code old) ───────────────────
	public var boyfriend:Character;
	public var dad:Character;
	public var gf:Character;

	// ── Constantes ────────────────────────────────────────────────────────────
	private static inline var SING_DURATION:Float  = 0.6;
	private static inline var IDLE_THRESHOLD:Float = 0.001;

	private static final NOTES_ANIM:Array<String> = ['LEFT', 'DOWN', 'UP', 'RIGHT'];

	// ── GF speed ─────────────────────────────────────────────────────────────
	private var gfSpeed:Int = 1;

	// ─────────────────────────────────────────────────────────────────────────
	// Constructor
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Constructor legacy: acepta refs directas para compatibilidad con
	 * code that creates CharacterController(bf, dad, gf) directly.
	 */
	public function new(?boyfriend:Character, ?dad:Character, ?gf:Character)
	{
		this.boyfriend = boyfriend;
		this.dad       = dad;
		this.gf        = gf;

		if (gf != null || dad != null || boyfriend != null)
			_initFromLegacyCharacters();
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Initialization
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Inicializa el controlador desde un array de CharacterSlots ya creados.
	 * Callr from PlayState.loadCharacters() after of create all the slots.
	 *
	 * BUG FIX 1: The refs legacy is resuelven by type, no by index.
	 */
	public function initFromSlots(slots:Array<CharacterSlot>):Void
	{
		characterSlots = slots;
		_syncLegacyRefs();
		trace('[CharacterController] ${slots.length} slots — player=${findPlayerIndex()}, opponent=${findOpponentIndex()}, gf=${findGFIndex()}');
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Search by type (BUG FIX 5, 6)
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Returns the index of the PRIMER slot of type Player.
	 * Retorna -1 si no hay ninguno.
	 */
	public function findPlayerIndex():Int
	{
		for (i in 0...characterSlots.length)
			if (characterSlots[i] != null && characterSlots[i].isPlayerSlot)
				return i;
		return -1;
	}

	/**
	 * Returns the index of the PRIMER slot of type Opponent.
	 * Retorna -1 si no hay ninguno.
	 */
	public function findOpponentIndex():Int
	{
		for (i in 0...characterSlots.length)
			if (characterSlots[i] != null && characterSlots[i].isOpponentSlot)
				return i;
		return -1;
	}

	/**
	 * Returns the index of the PRIMER slot of type Girlfriend.
	 * Retorna -1 si no hay ninguno.
	 */
	public function findGFIndex():Int
	{
		for (i in 0...characterSlots.length)
			if (characterSlots[i] != null && characterSlots[i].isGFSlot)
				return i;
		return -1;
	}

	/**
	 * Returns all the indices of slots with the type indicado.
	 * Useful when there is multiple characters of the same rol.
	 */
	public function findAllByType(type:String):Array<Int>
	{
		final result:Array<Int> = [];
		final t = type.toLowerCase();
		for (i in 0...characterSlots.length)
		{
			final slot = characterSlots[i];
			if (slot != null && slot.charType.toLowerCase() == t)
				result.push(i);
		}
		return result;
	}

	/**
	 * Devuelve el PRIMER slot vinculado a un StrumsGroup por su ID.
	 * BUG FIX 6: Allows to PlayState saber what character animar for a
	 * grupo CPU that no is the first (ej: cpu_strums_1 → character index 3).
	 *
	 * @return index of the slot, or -1 if no is encontró.
	 */
	public function findByStrumsGroup(strumsGroupId:String):Int
	{
		for (i in 0...characterSlots.length)
		{
			final slot = characterSlots[i];
			if (slot != null && slot.strumsGroupId == strumsGroupId)
				return i;
		}
		return -1;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Sing / Miss
	// ─────────────────────────────────────────────────────────────────────────

	/** Hace cantar al personaje en el slot `charIndex`. */
	public function singByIndex(charIndex:Int, noteData:Int, ?altAnim:String = ''):Void
	{
		if (charIndex < 0 || charIndex >= characterSlots.length) return;
		final slot = characterSlots[charIndex];
		if (slot != null && slot.isActive)
			slot.sing(noteData, altAnim);
	}

	/** Hace cantar al personaje en el slot `charIndex` forzando incluso si es GF. */
	public function singByIndexForce(charIndex:Int, noteData:Int, ?altAnim:String = ''):Void
	{
		if (charIndex < 0 || charIndex >= characterSlots.length) return;
		final slot = characterSlots[charIndex];
		if (slot != null && slot.isActive)
			slot.sing(noteData, altAnim, true);
	}

	/**
	 * Hace cantar a TODOS los personajes de un tipo dado.
	 * BUG FIX 4: Useful for charts with 2 opponents active simultáneos.
	 *
	 * Ejemplo: `singByType('Opponent', 2)` hace cantar a dad Y a un 2.º enemigo.
	 */
	public function singByType(type:String, noteData:Int, ?altAnim:String = ''):Void
	{
		for (idx in findAllByType(type))
			singByIndex(idx, noteData, altAnim);
	}

	/**
	 * Hace cantar a la GF forzando el guard (para secciones gfSing=true).
	 * BUG FIX 7: Without this method, GF never recibía animations of canto.
	 */
	public function singGF(noteData:Int, ?altAnim:String = ''):Void
	{
		for (i in 0...characterSlots.length)
		{
			final slot = characterSlots[i];
			if (slot != null && slot.isActive && slot.isGFSlot)
				slot.sing(noteData, altAnim, true);
		}
	}

	/** Reproduce miss animation en el slot `charIndex`. */
	public function missByIndex(charIndex:Int, noteData:Int):Void
	{
		if (charIndex < 0 || charIndex >= characterSlots.length) return;
		final slot = characterSlots[charIndex];
		if (slot != null && slot.isActive)
			slot.playMiss(noteData);
	}

	/**
	 * Hace cantar al personaje usando referencia directa (API legacy).
	 *
	 * BUG FIX 3: Already no suprime altAnim for the player. The supresión silenciosa
	 * previous hacía that animations -alt never is mostraran for BF.
	 */
	public function sing(char:Character, noteData:Int, ?altAnim:String = ''):Void
	{
		if (char == null || char.isPlayingSpecialAnim()) return;

		var animName:String = 'sing' + NOTES_ANIM[noteData] + altAnim;

		if ((char.animOffsets == null || !char.animOffsets.exists(animName))
			&& char.animation.getByName(animName) == null)
		{
			animName = 'sing' + NOTES_ANIM[noteData];
		}

		char.playAnim(animName, true);
		char.holdTimer = 0;

		#if HSCRIPT_ALLOWED
		funkin.scripting.ScriptHandler._argsAnim[0] = noteData;
		funkin.scripting.ScriptHandler._argsAnim[1] = animName;
		funkin.scripting.ScriptHandler.callOnCharacterScripts(char.curCharacter, 'onSingStart', funkin.scripting.ScriptHandler._argsAnim);
		#end

		// Resetear holdTimer del slot correspondiente
		for (slot in characterSlots)
			if (slot != null && slot.character == char)
			{
				slot.holdTimer = 0;
				break;
			}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Dance / Update
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Dance en beat.
	 *
	 * BUG FIX 2: GF se identifica por `slot.isGFSlot`, no por `slot.index == 0`.
	 * With the system previous, if GF estaba in index != 0, never bailaba to the ritmo
	 * correcto (usaba gfSpeed solo cuando index==0).
	 */
	public function danceOnBeat(curBeat:Int):Void
	{
		for (slot in characterSlots)
		{
			if (slot == null || !slot.isActive) continue;

			if (slot.isGFSlot)
			{
				// GF baila en cada `gfSpeed` beats
				if (curBeat % gfSpeed == 0)
					slot.dance();
			}
			else
			{
				// Opponents y Players bailan cada beat
				slot.dance();
			}
		}

		// Legacy — solo si no hay slots (compatibilidad total)
		if (characterSlots.length == 0)
			_legacyDance(curBeat);
	}

	/**
	 * Update por frame.
	 *
	 * BUG FIX 8: El update de animaciones (hold timer → idle) lo gestiona
	 * Character.update() internamente, porque Character is add()-eado to the
	 * FlxState and Flixel it call only. Ejecutarlo here also causaba
	 * flickering entre animaciones de canto e idle.
	 *
	 * Solo se mantiene el bloque legacy para cuando no hay slots.
	 */
	public function update(elapsed:Float):Void
	{
		// Slots: slot.update() is empty by diseño (ver CharacterSlot.update)
		for (slot in characterSlots)
			if (slot != null && slot.isActive)
				slot.update(elapsed);

		// Legacy — solo si no hay slots
		if (characterSlots.length == 0)
			_legacyUpdate(elapsed);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Special anims
	// ─────────────────────────────────────────────────────────────────────────

	/** Plays an animation especial en el personaje del slot `charIndex`. */
	public function playSpecialAnimByIndex(charIndex:Int, animName:String):Void
	{
		if (charIndex < 0 || charIndex >= characterSlots.length) return;
		final slot = characterSlots[charIndex];
		if (slot != null)
			slot.playSpecialAnim(animName);
	}

	/** Plays an animation especial usando ref directa (API legacy). */
	public function playSpecialAnim(char:Character, animName:String):Void
	{
		if (char == null) return;
		char.playAnim(animName, true);
		char.holdTimer = 0;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Getters
	// ─────────────────────────────────────────────────────────────────────────

	/** Obtiene el Character del slot `index`. Null si fuera de rango. */
	public function getCharacter(index:Int):Character
	{
		if (index < 0 || index >= characterSlots.length) return null;
		final slot = characterSlots[index];
		return slot != null ? slot.character : null;
	}

	/** Obtiene el slot en `index`. Null si fuera de rango. */
	public function getSlot(index:Int):CharacterSlot
	{
		if (index < 0 || index >= characterSlots.length) return null;
		return characterSlots[index];
	}

	/** Number total of slots. */
	public function getCharacterCount():Int return characterSlots.length;

	/** Activa o desactiva un slot. */
	public function setCharacterActive(index:Int, active:Bool):Void
	{
		if (index < 0 || index >= characterSlots.length) return;
		final slot = characterSlots[index];
		if (slot != null) slot.setActive(active);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Misc
	// ─────────────────────────────────────────────────────────────────────────

	/** GF speed: each how many beats baila the GF. Default 1. */
	public function setGFSpeed(speed:Int):Void gfSpeed = speed;

	/** Fuerza idle a todos los personajes. */
	public function forceIdleAll():Void
	{
		for (slot in characterSlots)
		{
			if (slot != null && slot.character != null)
			{
				slot.character.holdTimer = 0;
				slot.character.returnToIdle();
			}
		}
		// Legacy
		if (boyfriend != null) { boyfriend.holdTimer = 0; boyfriend.returnToIdle(); }
		if (dad        != null) { dad.holdTimer       = 0; dad.returnToIdle();       }
		if (gf         != null) { gf.holdTimer        = 0; gf.returnToIdle();        }
	}

	/** Destruye todos los slots y limpia referencias. */
	public function destroy():Void
	{
		for (slot in characterSlots)
			if (slot != null) slot.destroy();
		characterSlots = [];
		boyfriend = null;
		dad       = null;
		gf        = null;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Privados
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Sincroniza las referencias legacy (boyfriend/dad/gf) buscando por tipo.
	 * BUG FIX 1: already no asume indices fijos 0/1/2.
	 */
	private function _syncLegacyRefs():Void
	{
		boyfriend = null;
		dad       = null;
		gf        = null;

		for (slot in characterSlots)
		{
			if (slot == null) continue;
			if (boyfriend == null && slot.isPlayerSlot)   boyfriend = slot.character;
			if (dad       == null && slot.isOpponentSlot) dad       = slot.character;
			if (gf        == null && slot.isGFSlot)       gf        = slot.character;
		}
	}

	private function _initFromLegacyCharacters():Void
	{
		characterSlots = [];
		if (gf        != null) characterSlots.push(_makeSlot(gf,        0, 'Girlfriend'));
		if (dad       != null) characterSlots.push(_makeSlot(dad,       1, 'Opponent'));
		if (boyfriend != null) characterSlots.push(_makeSlot(boyfriend, 2, 'Player'));
		trace('[CharacterController] Modo legacy: ${characterSlots.length} personajes');
	}

	private function _makeSlot(char:Character, index:Int, type:String):CharacterSlot
	{
		final data:funkin.data.Song.CharacterSlotData = {
			name:    char.curCharacter,
			x:       char.x,
			y:       char.y,
			visible: true,
			type:    type
		};
		final slot = new CharacterSlot(data, index);
		slot.character = char;
		return slot;
	}

	// ── Legacy paths ──────────────────────────────────────────────────────────

	private function _legacyUpdate(elapsed:Float):Void
	{
		_legacyIdle(dad,       SING_DURATION);
		_legacyIdle(gf,        SING_DURATION);
		_legacyIdleBF(boyfriend);
	}

	private inline function _legacyIdle(char:Character, threshold:Float):Void
	{
		if (char == null || char.animation == null || char.animation.curAnim == null) return;
		final name = char.animation.curAnim.name;
		if (name.startsWith('sing') && !name.endsWith('miss'))
			if (char.holdTimer > threshold)
				char.dance();
	}

	private inline function _legacyIdleBF(char:Character):Void
	{
		if (char == null || char.animation == null || char.animation.curAnim == null) return;
		final name = char.animation.curAnim.name;
		if (name.startsWith('sing') && !name.endsWith('miss'))
		{
			final threshold = Conductor.stepCrochet * 4 * IDLE_THRESHOLD;
			if (char.holdTimer > threshold)
			{
				char.playAnim('idle', true);
				char.holdTimer = 0;
			}
		}
	}

	private function _legacyDance(curBeat:Int):Void
	{
		if (gf != null && curBeat % gfSpeed == 0) gf.dance();

		if (boyfriend != null && boyfriend.animation != null && boyfriend.animation.curAnim != null)
			if (!boyfriend.animation.curAnim.name.startsWith('sing'))
				boyfriend.dance();

		if (dad != null && dad.animation != null && dad.animation.curAnim != null)
			if (!dad.animation.curAnim.name.startsWith('sing'))
				dad.dance();
	}
}
