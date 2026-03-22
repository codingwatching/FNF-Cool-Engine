package funkin.gameplay.objects.character;

import funkin.gameplay.objects.character.Character;
import funkin.data.Song.CharacterSlotData;

using StringTools;

/**
 * CharacterSlot — Representa un slot de personaje en la partida.
 *
 * Cada slot encapsula:
 *   • El Character instanciado
 *   • Its datos of configuration (CharacterSlotData)
 *   • Its index in the array of the chart
 *   • Su ROL normalizado (Player / Opponent / Girlfriend / Other)
 *   • The ID of the StrumsGroup to the that is vinculado
 *
 * ── Mejoras respecto to the version previous ──────────────────────────────────
 *
 *  BUG FIX A  charType / isGFSlot / strumsGroupId expuestos como propiedades
 *             tipadas. Before había that acceder to `slot.data.type` with string
 *             sin validar, causando que danceOnBeat, findPlayerIndex, etc.
 *             no funcionaran with chars in indices no standard.
 *
 *  BUG FIX B  `sing()` ahora respeta `isGFSlot`: si este slot es de GF
 *             (isGF:true or type:"Girlfriend"), ignorará calldas sing()
 *             a menos que se use `forceSing:true`. GF solo baila a menos
 *             that a section tenga gfSing=true.
 *
 *  BUG FIX C  `playMiss()` tiene fallback a `character.animation.getByName()`
 *             furthermore of `animOffsets`. The version previous fallaba silencio-
 *             samente con personajes que no usan el sistema de offsets.
 *
 *  BUG FIX D  `position by type` en el constructor: si `charData.x == 0 &&
 *             charData.and == 0`, the position the resuelve `PlayState.loadCharacters`
 *             usando the type in vez of the index hardcodeado.
 */
class CharacterSlot
{
	// ── Datos principales ────────────────────────────────────────────────────
	public var character:Character;
	public var data:CharacterSlotData;
	public var index:Int;
	public var isActive:Bool = true;

	// ── Propiedades de rol (BUG FIX A) ───────────────────────────────────────

	/**
	 * Tipo normalizado del personaje en este slot.
	 * Valores posibles: "Player" | "Opponent" | "Girlfriend" | "Other"
	 *
	 * Is deriva of `charData.type` in the build. If `type` no is
	 * definido en el JSON del chart, se infiere por nombre del personaje
	 * (bf → Player, gf → Girlfriend, resto → Opponent).
	 */
	public var charType(default, null):String;

	/**
	 * true si este slot es de Girlfriend (solo baila, no canta notas).
	 * Shorthand para `charType == "Girlfriend"` o `data.isGF == true`.
	 */
	public var isGFSlot(get, never):Bool;
	inline function get_isGFSlot():Bool
		return charType == 'Girlfriend' || (data.isGF == true);

	/**
	 * true si este slot es el jugador (recibe inputs del teclado/gamepad).
	 */
	public var isPlayerSlot(get, never):Bool;
	inline function get_isPlayerSlot():Bool return charType == 'Player';

	/**
	 * true if this slot is of the oponente (CPU canta automatically).
	 */
	public var isOpponentSlot(get, never):Bool;
	inline function get_isOpponentSlot():Bool return charType == 'Opponent';

	/**
	 * ID of the StrumsGroup to the that is vinculado this character.
	 * Null if no is vinculado to no grupo explicit.
	 */
	public var strumsGroupId(default, null):Null<String>;

	// ── Timers internos ───────────────────────────────────────────────────────
	public var holdTimer:Float   = 0;
	public var animFinished:Bool = true;

	// ── Tabla of sufijos of animation ─────────────────────────────────────────
	static final NOTES_ANIM:Array<String> = ['LEFT', 'DOWN', 'UP', 'RIGHT'];

	// ─────────────────────────────────────────────────────────────────────────
	// Constructor
	// ─────────────────────────────────────────────────────────────────────────

	public function new(charData:CharacterSlotData, index:Int)
	{
		this.data  = charData;
		this.index = index;

		// ── Resolver tipo de personaje (BUG FIX A) ───────────────────────────
		charType = _resolveCharType(charData);

		// ── StrumsGroup ID ────────────────────────────────────────────────────
		strumsGroupId = charData.strumsGroup;

		// ── Crear personaje ───────────────────────────────────────────────────
		final charName = charData.name != null ? charData.name : 'bf';
		character = new Character(charData.x, charData.y, charName, charType == 'Player');

		// Appliesr configuration of the slot
		if (charData.flip != null && charData.flip)
			character.flipX = !character.flipX;

		if (charData.scale != null && charData.scale != 1.0)
		{
			character.scale.set(charData.scale, charData.scale);
			character.updateHitbox();
		}

		if (charData.visible != null)
			character.visible = charData.visible;

		trace('[CharacterSlot] Slot $index: "$charName" (type=$charType, strumsGroup=$strumsGroupId)');

		// ── Companion 3D ──────────────────────────────────────────────────────────
		// If the character tiene renderType=model3d, add its Flx3DSprite to the state.
		if (character.model3D != null)
		{
			final ps = funkin.gameplay.PlayState.instance;
			if (ps != null)
				ps.add(character.model3D);
			trace('[CharacterSlot] Companion model3D added to the state for "$charName".');
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Animaciones
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Hace cantar to the character in the direction `noteData`.
	 *
	 * @param noteData   0=LEFT 1=DOWN 2=UP 3=RIGHT
	 * @param altAnim    Suffix of animation alternativa (ej: "-alt", "")
	 * @param forceSing  Si true, ignora el guard de GF. Usar cuando gfSing=true.
	 */
	public function sing(noteData:Int, ?altAnim:String = '', ?forceSing:Bool = false):Void
	{
		if (!isActive) return;

		// BUG FIX B: GF no canta to menos that sea a section gfSing
		if (isGFSlot && !forceSing) return;

		if (character.isPlayingSpecialAnim()) return;

		var animName:String = 'sing' + NOTES_ANIM[noteData] + altAnim;

		// Fallback if no exists the animation alterna
		if (!_animExists(animName))
			animName = 'sing' + NOTES_ANIM[noteData];

		// Si tampoco existe la base, salir silenciosamente
		if (!_animExists(animName)) return;

		character.playAnim(animName, true);

		// critical: Resetear the holdTimer for that Character.update() no fuerce
		// the idle in the next frame before of that is vea the animation.
		character.holdTimer = 0;
		animFinished = false;
	}

	/**
	 * Reproduce the animation of miss for `noteData`.
	 *
	 * BUG FIX C: tiene fallback a `animation.getByName()` si `animOffsets`
	 * no tiene the animation registrada (chars that no usan the system of offsets).
	 */
	public function playMiss(noteData:Int):Void
	{
		if (!isActive) return;

		final animName:String = 'sing' + NOTES_ANIM[noteData] + 'miss';

		if (_animExists(animName))
		{
			character.playAnim(animName, true);
			character.holdTimer = 0;
			animFinished = false;
		}
		// If no there is animation of miss, to the menos interrumpir the sing current
		// for dar feedback visual of that is failed the note.
	}

	/**
	 * Dance in beat. No interrumpe if is cantando or in special anim.
	 */
	public function dance():Void
	{
		if (!isActive) return;
		character.dance();
	}

	/**
	 * Plays an animation especial (hey, cheer, etc.) sin guards.
	 */
	public function playSpecialAnim(animName:String):Void
	{
		if (character == null) return;
		character.playAnim(animName, true);
		character.holdTimer = 0;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Update
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Update por frame.
	 *
	 * IMPORTANTE: no duplicar logic of animation here.
	 * Flixel call Character.update() automatically porque the character
	 * is add()-eado to the FlxState. Character.update() already manages holdTimer,
	 * sing→idle and special→idle. Execute that logic here causaría flickering.
	 */
	public function update(elapsed:Float):Void
	{
		// Reservado for logic futura of slot (no of animation of character).
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Control of visibility / activación
	// ─────────────────────────────────────────────────────────────────────────

	public function setActive(active:Bool):Void
	{
		isActive = active;
		character.visible = active && (data.visible != null ? data.visible : true);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Destruction
	// ─────────────────────────────────────────────────────────────────────────

	public function destroy():Void
	{
		if (character != null)
		{
			character.destroy();
			character = null;
		}
		data = null;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Helpers privados
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Checks if a animation exists, first in `animOffsets` (system
	 * de FunkinSprite/FlxAnimate) y luego en `animation` (sistema legacy FlxSprite).
	 *
	 * BUG FIX C: The version previous only comprobaba `animOffsets`, it that
	 * causaba que personajes sin offsets nunca cantaran.
	 */
	private inline function _animExists(name:String):Bool
	{
		return (character.animOffsets != null && character.animOffsets.exists(name))
			|| (character.animation != null && character.animation.getByName(name) != null);
	}

	/**
	 * Deduce the type canónico of the character to partir of CharacterSlotData.
	 *
	 * Orden de precedencia:
	 *   1. `charData.type` explicit in the JSON of the chart
	 *   2. `charData.isGF == true`
	 *   3. Inferencia por nombre (bf → Player, gf → Girlfriend, resto → Opponent)
	 */
	private static function _resolveCharType(charData:CharacterSlotData):String
	{
		// 1. Field explicit
		if (charData.type != null)
		{
			return switch (charData.type.toLowerCase().trim())
			{
				case 'player', 'bf', 'boyfriend': 'Player';
				case 'opponent', 'dad', 'enemy':  'Opponent';
				case 'girlfriend', 'gf':          'Girlfriend';
				default: charData.type; // Preservar tipos custom ("Other", etc.)
			};
		}

		// 2. Flag isGF
		if (charData.isGF == true) return 'Girlfriend';

		// 3. Inferencia por nombre de personaje
		final name = (charData.name ?? '').toLowerCase();
		if (name.startsWith('bf') || name.contains('boyfriend')) return 'Player';
		if (name.startsWith('gf') || name.contains('girlfriend')) return 'Girlfriend';

		return 'Opponent'; // default
	}
}
