package funkin.gameplay.notes;

import flixel.FlxSprite;
import flixel.FlxG;
import funkin.gameplay.PlayState;
import lime.utils.Assets;
import funkin.gameplay.PlayStateConfig;

using StringTools;

class StrumNote extends FlxSprite
{
	public var noteID:Int = 0;

	var animArrow:Array<String> = ['LEFT', 'DOWN', 'UP', 'RIGHT'];

	// ── Estado de skin ────────────────────────────────────────────────────

	/** true si la skin tiene isPixel:true. */
	private var _isPixelSkin:Bool = false;

	/**
	 * Mapa animName → [offsetX, offsetY] construido desde la skin activa.
	 * Puede tener entradas para 'pressed' y/o 'confirm'.
	 * Si no hay entrada para una animación, no se aplica ningún offset extra.
	 */
	private var _animOffsets:Map<String, Array<Float>> = new Map();

	public function new(x:Float, y:Float, noteID:Int = 0)
	{
		super(x, y);

		this.noteID = noteID;

		NoteSkinSystem.init();
		loadSkin(NoteSkinSystem.getCurrentSkinData());

		updateHitbox();
		scrollFactor.set();
		// FIX: usar playAnim() en lugar de animation.play() para que los
		// _animOffsets de la skin (centerOffsets + offset de la anim 'static')
		// se apliquen desde el primer frame. Sin esto los strums aparecen
		// desplazados hasta que se reproduce otra animación y vuelven a 'static'.
		playAnim('static');
		// Los strums NO llevan NoteGlowShader — el glow de proximidad va en las notas entrantes
	}

	// ==================== CARGA DE SKIN ====================

	/**
	 * Carga la textura y las animaciones de strum desde un NoteSkinData.
	 *
	 * Sin ninguna referencia a PlayState.curStage.
	 * El índice noteID determina qué animaciones cargar (left/down/up/right).
	 */
	function loadSkin(skinData:NoteSkinSystem.NoteSkinData):Void
	{
		if (skinData == null)
			return;

		_isPixelSkin = skinData.isPixel == true;

		// Construir el mapa de offsets por animación desde la skin.
		// buildStrumOffsets() aplica la prioridad: offset del JSON > confirmOffset global > sin offset.
		_animOffsets = NoteSkinSystem.buildStrumOffsets(skinData, noteID);

		// ── Cargar textura de strums ────────────────────────────────────────────
		// Prioridad: strumsTexture > texture
		var tex = NoteSkinSystem.getStrumsTexture(skinData.name);
		// FunkinSprite en StrumNote (FlxSprite) no es posible directamente;
		// si el tipo es funkinsprite, fallback a texture principal.
		if (NoteSkinSystem.isFunkinSpriteType(tex))
		{
			trace('[StrumNote] FunkinSprite type detectado — fallback a texture principal (StrumNote es FlxSprite)');
			tex = skinData.texture;
		}
		frames = NoteSkinSystem.loadSkinFrames(tex, skinData.folder);

		// BUGFIX CRÍTICO: si frames sigue siendo null aquí (asset faltante, XML roto, etc.)
		// el sprite se renderizará en el primer frame de PlayState con frame=null
		// → FlxDrawQuadsItem::render line 119 crash.
		// makeGraphic() crea un BitmapData de 1x1 garantizado que evita el crash.
		// El sprite quedará invisible (scale 0.7 → 0.7×0.7 px) pero el juego no crashea.
		if (frames == null)
		{
			trace('[StrumNote] WARN: frames null para skin "${skinData.name}" noteID=$noteID — usando placeholder para evitar crash');
			makeGraphic(Std.int(Note.swagWidth), Std.int(Note.swagWidth), 0x00000000);
		}

		var noteScale = tex.scale != null ? tex.scale : 1.0;
		// BUGFIX: usar scale.set() directo en lugar de setGraphicSize(width*scale)
		// que usaría el hitbox stale si loadSkin() se llamara de nuevo (recarga de skin).
		scale.set(noteScale, noteScale);
		updateHitbox();

		antialiasing = tex.antialiasing != null ? tex.antialiasing : !_isPixelSkin;

		// ── Cargar animaciones ────────────────────────────────────────────
		var anims = skinData.animations;
		if (anims == null)
		{
			loadDefaultStrumAnimations();
			return;
		}

		var i = Std.int(Math.abs(noteID));

		var strumDefs = [anims.strumLeft, anims.strumDown, anims.strumUp, anims.strumRight];
		var pressDefs = [
			anims.strumLeftPress,
			anims.strumDownPress,
			anims.strumUpPress,
			anims.strumRightPress
		];
		var confirmDefs = [
			anims.strumLeftConfirm,
			anims.strumDownConfirm,
			anims.strumUpConfirm,
			anims.strumRightConfirm
		];

		// 'static' may loop freely; 'pressed' and 'confirm' must NOT loop so that
		// animation.curAnim.finished becomes true and the auto-reset to 'static'
		// fires correctly.  We pass overrideLoop=false for those two.
		// Previously the code tried to set FlxAnimation.looped after registration,
		// but that field is read-only in HaxeFlixel — this is the correct fix.
		NoteSkinSystem.addAnimToSprite(this, 'static', strumDefs[i]);
		NoteSkinSystem.addAnimToSprite(this, 'pressed', pressDefs[i], false);
		NoteSkinSystem.addAnimToSprite(this, 'confirm', confirmDefs[i], false);

		// Fallback si no se definió animación estática
		if (!animation.exists('static'))
		{
			trace('[StrumNote] "static" no encontrada en skin "${skinData.name}" para noteID $noteID — cargando defaults');
			loadDefaultStrumAnimations();
		}
	}

	/** Recarga la skin en un strum existente (útil en rewind para corregir scale). */
	public function reloadSkin(skinData:NoteSkinSystem.NoteSkinData):Void
	{
		loadSkin(skinData);
		animation.play('static');
		centerOffsets();
	}

	function loadDefaultStrumAnimations():Void
	{
		var i = Std.int(Math.abs(noteID));
		animation.addByPrefix('static', 'arrow' + animArrow[i]);
		animation.addByPrefix('pressed', animArrow[i].toLowerCase() + ' press', 24, false);
		animation.addByPrefix('confirm', animArrow[i].toLowerCase() + ' confirm', 24, false);
	}

	// ==================== ANIMACIÓN ====================

	/**
	 * Reproduce una animación de forma segura.
	 * Aplica el offset -13,-13 al confirm si la skin lo requiere (confirmOffset:true).
	 * centerOffsets() siempre resetea el offset, por lo que el ajuste se re-aplica
	 * en cada llamada a confirm para mantener la posición correcta.
	 */
	public function playAnim(animName:String, force:Bool = false):Void
	{
		if (animation == null)
			return;

		animation.play(animName, force);
		centerOffsets();

		// Aplicar offset de la skin para esta animación (pressed / confirm), si existe.
		var off = _animOffsets.get(animName);
		if (off != null)
		{
			offset.x += off[0];
			offset.y += off[1];
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Auto-reset confirm → static cuando termina la animación
		if (animation.curAnim != null && animation.curAnim.name == 'confirm' && animation.curAnim.finished)
		{
			playAnim('static');
		}
	}
}
