package funkin.gameplay.notes;

import lime.utils.Assets;
import funkin.gameplay.PlayState;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.FlxG;
import funkin.data.Conductor;
import funkin.gameplay.PlayStateConfig;
import animationdata.FunkinSprite;

using StringTools;

class Note extends FlxSprite
{
	public var strumTime:Float = 0;
	public var mustPress:Bool = false;
	public var noteData:Int = 0;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;
	public var wasGoodHit:Bool = false;
	public var prevNote:Note;
	public var sustainLength:Float = 0;
	public var isSustainNote:Bool = false;
	/** Scale.y base de la pieza de sustain, calculado en setupSustainNote().
	 *  NoteManager lo usa en la compensacion de rotacion sin acumulacion:
	 *    note.scale.y = sustainBaseScaleY / cos(deformAngle)
	 */
	public var sustainBaseScaleY:Float = 1.0;
	public var noteScore:Float = 1;
	public var noteRating:String = 'sick';

	public var strumsGroupIndex:Int = 0;

	/** Tipo de nota personalizado. "" / "normal" = normal. */
	public var noteType:String = '';

	public static var swagWidth:Float = 160 * 0.7;
	public static var PURP_NOTE:Int = 0;
	public static var BLUE_NOTE:Int = 1;
	public static var GREEN_NOTE:Int = 2;
	public static var RED_NOTE:Int = 3;

	var animArrows:Array<String> = ['purple', 'blue', 'green', 'red'];

	// ── Estado de skin ────────────────────────────────────────────────────

	/** Nombre de la skin actualmente cargada. Usado para detectar cambios en recycle(). */
	private var _loadedSkinName:String = '';

	/** Type with the that is cargó the skin: true=sustain, false=normal. If changes there is that reload animations. */
	private var _loadedAsSustain:Bool = false;

	/** true si la skin cargada tiene isPixel:true. */
	private var isPixelNote:Bool = false;

	/** Scales appliesda to the sprite, leída of the JSON of skin. */
	private var _noteScale:Float = 1.0;

	/** Offset X extra for notes sustain, leído of the JSON of skin. */
	private var _skinSustainOffset:Float = 0.0;

	/** Multiplier of scale.and for hold chain, leído of the JSON of skin. */
	public var _skinHoldStretch:Float = 1.0;

	/**
	 * Offset X/and for notes scroll (cabeza), leído of the field `offset` of the
	 * animation of note in the JSON of skin (and.g. "left": { "offset": [2, -4] }).
	 * Is applies in NoteManager.updateNotePosition() to the position calculada.
	 * 0.0 por defecto → sin efecto si la skin no define offsets de nota.
	 */
	public var noteOffsetX:Float = 0.0;
	public var noteOffsetY:Float = 0.0;

	// ── Cache de hit window ───────────────────────────────────────────────
	private var _lastSongPos:Float = -1;
	private var _hitWindowCache:Float = 0;

	/** Referencia directa al shader de glow para actualizar intensidad por proximidad. */
	private var _glowShader:funkin.shaders.NoteGlowShader = null;


	/** Distancia maximum (ms) from the that starts the glow of approximation. */
	static inline final GLOW_START_MS:Float  = 500.0;
	/** Distancia (ms) in the that the glow alcanza its maximum before of the hit. */
	static inline final GLOW_PEAK_MS:Float   = 60.0;



	public function new(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?mustHitNote:Bool = false)
	{
		super();

		if (prevNote == null)
			prevNote = this;
		this.prevNote = prevNote;
		isSustainNote = sustainNote;
		this.mustPress = mustHitNote;

		// BUGFIX: appliesr the offset of direction here same — setupNoteDirection
		// ya no hace x += swagWidth*i para notas sustain (causaba WARNING),
		// so that calculamos the X final directamente igual that in recycle().
		x = _calcBaseX(mustHitNote) + (swagWidth * noteData);
		y = -2000;
		this.strumTime = strumTime + FlxG.save.data.offset;
		this.noteData = noteData;

		NoteSkinSystem.init();
		loadSkin(NoteSkinSystem.getCurrentSkinData());

		// NOTA: los offsets de nota se construyen dentro de loadSkin() para que
		// is reconstruyan automatically when the skin changes (recycle).

		// Glow de proximidad: shader propio en notas normales, no en sustain
		if (!isSustainNote && shaders.ShaderManager.enabled)
		{
			_glowShader = funkin.shaders.NoteGlowShader.forDirection(noteData % 4, 0.0);
			shader = _glowShader;
		}
		else
		{
			_glowShader = null;
		}

		setupNoteDirection();

		if (isSustainNote && prevNote != null)
			setupSustainNote();

		var hitWindowMultiplier = isSustainNote ? 1.05 : 1.0;
		_hitWindowCache = Conductor.safeZoneOffset * hitWindowMultiplier;

		if (NoteTypeManager.isCustomType(noteType))
			NoteTypeManager.onNoteSpawn(this);
	}

	// ==================== CARGA DE SKIN ====================

	/**
	 * Carga la textura y las animaciones desde un NoteSkinData.
	 *
	 * No there is ninguna referencia to PlayState.curStage here.
	 * El caller (constructor / recycle) pasa el skinData ya resuelto
	 * by NoteSkinSystem (that sabe what skin corresponds to the stage current).
	 */
	function loadSkin(skinData:NoteSkinSystem.NoteSkinData):Void
	{
		if (skinData == null)
			return;

		_loadedSkinName = skinData.name;
		_loadedAsSustain = isSustainNote; // rastrear tipo para detectar cambio en recycle
		isPixelNote = skinData.isPixel == true;
		_skinSustainOffset = skinData.sustainOffset != null ? skinData.sustainOffset : 0.0;
		_skinHoldStretch = skinData.holdStretch != null ? skinData.holdStretch : 1.0;

		// ── Offsets de nota desde la skin ────────────────────────────────────
		// buildNoteOffsets / buildHoldNoteOffsets leen el campo `offset` de las
		// animaciones de nota en el JSON de skin. Son [0,0] si no se definen.
		// TIMING: seguro — the skin already is cargada in NoteSkinSystem to the start of
		// PlayState. Is re-evalúan in each loadSkin() (constructor + recycle) by
		// if the skin changes to mitad of the song (stage with skin diferente, etc.).
		if (!isSustainNote)
		{
			var off = NoteSkinSystem.buildNoteOffsets(skinData, noteData);
			noteOffsetX = off[0];
			noteOffsetY = off[1];
		}
		else
		{
			var off = NoteSkinSystem.buildHoldNoteOffsets(skinData, noteData);
			noteOffsetX = off[0];
			noteOffsetY = off[1];
		}

		// ── Elegir textura ────────────────────────────────────────────────
		// Notas cabeza y strums → texture principal
		// Sustain pieces + tails → holdTexture (si existe) o fallback a texture
		var tex:NoteSkinSystem.NoteSkinTexture;
		// Por tipo de nota: hold usa holdTexture > notesTexture > texture
		//                   nota scroll usa notesTexture > texture
		// Strums usan strumsTexture en StrumNote.hx
		if (isSustainNote)
			tex = NoteSkinSystem.getHoldTexture(skinData.name);
		else
			tex = NoteSkinSystem.getNotesScrollTexture(skinData.name);

		// FunkinSprite (type:"funkinsprite") no puede usarse directamente
		// en Note (que extiende FlxSprite). Fallback a texture principal.
		if (NoteSkinSystem.isFunkinSpriteType(tex))
		{
			trace('[Note] FunkinSprite type detectado — fallback a texture principal (Note es FlxSprite)');
			tex = skinData.texture;
		}
		frames = NoteSkinSystem.loadSkinFrames(tex, skinData.folder);

		// ── NoteType: textura de sustain custom ───────────────────────────
		// If the noteType tiene its propio atlas of hold, sobreescribir here.
		// Solo aplica a sustain notes; las cabezas se sobreescriben en onNoteSpawn.
		if (isSustainNote && NoteTypeManager.isCustomType(noteType))
		{
			final typeHoldFrames = NoteTypeManager.getHoldFrames(noteType);
			if (typeHoldFrames != null) frames = typeHoldFrames;
		}

		// BUGFIX critical: if frames is null (asset faltante, XML roto, etc.)
		// el sprite crashea en FlxDrawQuadsItem::render al primer frame de PlayState.
		if (frames == null)
		{
			trace('[Note] WARN: frames null para skin "${skinData.name}" noteData=$noteData — usando placeholder');
			makeGraphic(Std.int(Note.swagWidth), Std.int(Note.swagWidth), 0x00000000);
		}

		// ── Escala ────────────────────────────────────────────────────────
		// BUGFIX: NO usar `width * _noteScale` porque `width` es el hitbox del
		// ciclo anterior (stale) hasta que se llame updateHitbox(). Usar
		// scale.set() directamente para evitar que el scale se multiplique
		// acumulativamente in each recycle (_noteScale^N in the N-ésima reutilización).
		_noteScale = tex.scale != null ? tex.scale : 1.0;
		scale.set(_noteScale, _noteScale);
		updateHitbox();

		// ── Antialiasing ──────────────────────────────────────────────────
		antialiasing = tex.antialiasing != null ? tex.antialiasing : !isPixelNote;

		// ── Animaciones ───────────────────────────────────────────────────
		var anims = skinData.animations;
		if (anims == null)
			return;

		if (!isSustainNote)
		{
			// Animaciones de notas (las que bajan por la pantalla)
			var defs = [anims.left, anims.down, anims.up, anims.right];
			for (i in 0...animArrows.length)
				NoteSkinSystem.addAnimToSprite(this, animArrows[i] + 'Scroll', defs[i]);
		}
		else
		{
			// Hold pieces
			var holdDefs = [anims.leftHold, anims.downHold, anims.upHold, anims.rightHold];
			// Hold tails/ends
			var holdEndDefs = [anims.leftHoldEnd, anims.downHoldEnd, anims.upHoldEnd, anims.rightHoldEnd];

			for (i in 0...animArrows.length)
			{
				NoteSkinSystem.addAnimToSprite(this, animArrows[i] + 'hold', holdDefs[i]);
				NoteSkinSystem.addAnimToSprite(this, animArrows[i] + 'holdend', holdEndDefs[i]);
			}
		}
	}

	// ==================== RECYCLE (Object Pooling) ====================

	public function recycle(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?mustHitNote:Bool = false):Void
	{
		this.strumTime = strumTime + FlxG.save.data.offset;
		this.noteData = noteData;
		this.prevNote = prevNote != null ? prevNote : this;
		this.isSustainNote = sustainNote;
		this.mustPress = mustHitNote;
		this.canBeHit = false;
		this.tooLate = false;
		this.wasGoodHit = false;
		this.noteScore = 1;
		this.noteRating = 'sick';
		this.strumsGroupIndex = 0;
		this.noteType = '';
		this.alpha = sustainNote ? 0.6 : 1.0;
		this.visible = true;
		// BUGFIX: limpiar clipRect al reciclar. Si esta nota fue una nota larga
		// cerca del strum en su vida anterior, el clipRect queda asignado. Sin
		// reset, la nueva nota aparece recortada hasta que updateNotePosition()
		// vuelve a calcular el clip — pero si la nota es saltada en ese frame
		// por el bug de splice (ya corregido en _updateNoteGroup), el clipRect
		// antiguo persiste y la nota larga nueva es visible con recorte incorrecto.
		this.clipRect = null;

		x = _calcBaseX(mustHitNote) + (swagWidth * noteData);
		y = -2000;

		var hitWindowMultiplier = isSustainNote ? 1.05 : 1.0;
		_hitWindowCache = Conductor.safeZoneOffset * hitWindowMultiplier;
		_lastSongPos = -1;

		revive();

		// Resetear offsets de nota — se recalculan en loadSkin() si la skin o tipo cambia,
		// and also in the bloque of restauración of animation down if the skin no changed.
		noteOffsetX = 0.0;
		noteOffsetY = 0.0;

		// ── Reload skin if changed name or if changed the type (sustain↔normal) ────
		// BUGFIX: el tipo de nota puede cambiar si el pool de NoteRenderer mezcla
		// sustain and normales. loadSkin registra animations distintas according to isSustainNote,
		// so that there is that recargar also when changes the type aunque the skin sea igual.
		var skinData = NoteSkinSystem.getCurrentSkinData();
		if (skinData.name != _loadedSkinName || isSustainNote != _loadedAsSustain)
			loadSkin(skinData); // loadSkin() ya recalcula noteOffsetX/Y
		else
		{
			// The skin no changed but noteData puede haber cambiado (note reciclada
			// to otra direction). Re-calculate the offsets of note for the new direction.
			var off = isSustainNote
				? NoteSkinSystem.buildHoldNoteOffsets(skinData, noteData)
				: NoteSkinSystem.buildNoteOffsets(skinData, noteData);
			noteOffsetX = off[0];
			noteOffsetY = off[1];
		}

		// ── Restaurar animation and scales ──────────────────────────────────
		if (!isSustainNote)
		{
			scale.set(_noteScale, _noteScale);
			updateHitbox();

			_applyNoteAnim(animArrows[noteData] + 'Scroll');

			// Re-create shader of glow to the reciclar (the direction puede haber cambiado)
			if (shaders.ShaderManager.enabled)
			{
				_glowShader = funkin.shaders.NoteGlowShader.forDirection(noteData % 4, 0.0);
				shader = _glowShader;
			}
			else
			{
				_glowShader = null;
				shader = null;
			}
		}
		else
		{
			scale.set(_noteScale, _noteScale);
			sustainBaseScaleY = _noteScale; // se actualizara en setupSustainNote
			updateHitbox();
			flipY = false;
			flipX = false;
			setupSustainNote();
		}
	}

	// ==================== SETUP HELPERS ====================

	function setupNoteDirection():Void
	{
		// BUGFIX: the notes sustain no tienen animation 'purpleScroll' registrada.
		// Furthermore, the X already was calculada in the constructor with swagWidth*noteData,
		// so that no necesitamos x += here.
		if (isSustainNote)
			return;

		// Only play the animation of scroll (X already calculada in constructor).
		// _applyNoteAnim aplica centerOffsets() + noteOffsetX/Y (igual que StrumNote.playAnim).
		_applyNoteAnim(animArrows[noteData] + 'Scroll');
	}

	function setupSustainNote():Void
	{
		noteScore * 0.2;
		alpha = 0.6;

		if (FlxG.save.data.downscroll)
		{
			flipY = true;
			flipX = true;
		}

		x += width / 2;

		for (i in 0...animArrows.length)
		{
			if (noteData == i)
			{
				// BUGFIX: check existence para no disparar WARNING si la skin
				// still no tiene this animation registered
				_applyNoteAnim(animArrows[i] + 'holdend');
				break;
			}
		}


		updateHitbox();
		// Re-aplicar offset de skin: el updateHitbox() de arriba (para recalcular
		// width y centrar x) llama centerOffsets() borrando el offset de _applyNoteAnim.
		offset.x += noteOffsetX;
		offset.y += noteOffsetY;
		x -= width / 2;

		// Offset X extra (leído of the JSON of skin — and.g. 30 for pixel, 0 for normal)
		x += _skinSustainOffset;

		if (prevNote.isSustainNote)
		{
			for (i in 0...animArrows.length)
			{
				if (prevNote.noteData == i)
				{
					prevNote._applyNoteAnim(animArrows[i] + 'hold');
					break;
				}
			}


			// ── V-Slice style sustain height ────────────────────────────────────
			// Fórmula previous: scale.and *= stepCrochet/100 * 1.5 * speed
			// → Asumía frameHeight = 30px for that the piece cubriera exactly the
			//   distancia stepCrochet * 0.45 * speed. With skins of otros sizes or
			//   velocidades very altas aparecían huecos between the cabeza and the cuerpo.
			//
			// Fórmula new (inspirada in SustainTrail.sustainHeight of V-Slice):
			//   targetHeight = stepCrochet * PIXELS_PER_MS * speed
			//   donde PIXELS_PER_MS = 0.45 (la misma constante de NoteManager)
			//   scale.y = targetHeight / frameHeight
			//
			// This guarantees that the pieza cubre exactamente the pixels that avanza
			// a note in stepCrochet ms, without asumir size of sprite.
			// _skinHoldStretch adds a small solapamiento (definido in the skin JSON,
			// e.g. 1.05) para eliminar el gap visible con velocidades muy altas.
			if (prevNote.frameHeight > 0)
			{
				final targetHeight:Float = Conductor.stepCrochet * 0.45 * PlayState.SONG.speed;
				prevNote.scale.y = (targetHeight * _skinHoldStretch) / prevNote.frameHeight;
			}
			else
			{
				// Fallback if frameHeight is 0 (frame not yet loaded)
				prevNote.scale.y *= Conductor.stepCrochet / 100 * 1.5 * PlayState.SONG.speed;
				prevNote.scale.y *= _skinHoldStretch;
			}
			// Guardar el scale.y base para que NoteManager pueda compensar la
			// rotacion de deformacion sin acumulacion (lee este valor, no scale.y).
			prevNote.sustainBaseScaleY = prevNote.scale.y;
			prevNote.updateHitbox();
			// Re-aplicar offset de skin: updateHitbox() borra el offset que
			// _applyNoteAnim('hold') aplicó justo up.
			prevNote.offset.x += prevNote.noteOffsetX;
			prevNote.offset.y += prevNote.noteOffsetY;
		}
	}

	// ==================== SETUP DE ANIMACIONES DE TIPO ====================

	/**
	 * Reconfigura animaciones cuando NoteTypeManager asigna sus propios frames.
	 * Llamado desde NoteTypeManager.onNoteSpawn().
	 */
	public function setupTypeAnimations():Void
	{
		var dirs = ['purple', 'blue', 'green', 'red'];
		if (!isSustainNote)
		{
			for (i in 0...dirs.length)
			{
				try
				{
					animation.addByPrefix(dirs[i] + 'Scroll', dirs[i] + '0');
				}
				catch (_:Dynamic)
				{
				}
				try
				{
					animation.addByPrefix(dirs[i] + 'Scroll', dirs[i]);
				}
				catch (_:Dynamic)
				{
				}
			}
			for (i in 0...dirs.length)
				if (noteData == i)
				{
					_applyNoteAnim(dirs[i] + 'Scroll');
					break;
				}
		}
		else
		{
			for (i in 0...dirs.length)
			{
				try
				{
					animation.addByPrefix(dirs[i] + 'holdend', dirs[i] + ' hold end');
				}
				catch (_:Dynamic)
				{
				}
				try
				{
					animation.addByPrefix(dirs[i] + 'holdend', dirs[i] + 'holdend');
				}
				catch (_:Dynamic)
				{
				}
				try
				{
					animation.addByPrefix(dirs[i] + 'hold', dirs[i] + ' hold piece');
				}
				catch (_:Dynamic)
				{
				}
				try
				{
					animation.addByPrefix(dirs[i] + 'hold', dirs[i] + 'hold');
				}
				catch (_:Dynamic)
				{
				}
			}
			for (i in 0...dirs.length)
				if (noteData == i)
				{
					_applyNoteAnim(dirs[i] + 'holdend');
					break;
				}
		}
		setGraphicSize(Std.int(width * _noteScale));
		updateHitbox();
	}

	// ==================== UTILIDADES ====================

	/**
	 * Plays an animation de nota appliesndo el offset de skin correspondiente.
	 * Equivalente a StrumNote.playAnim() pero para notas scroll/hold/holdend.
	 *
	 * Flujo: animation.play() → centerOffsets() → offset.x += noteOffsetX, offset.y += noteOffsetY
	 * If the animation no exists is ignora silenciosamente (without WARNING).
	 */
	private function _applyNoteAnim(animName:String, force:Bool = false):Void
	{
		if (animation == null || !animation.exists(animName))
			return;
		animation.play(animName, force);
		centerOffsets();
		offset.x += noteOffsetX;
		offset.y += noteOffsetY;
	}

	/** Calcula the position X base according to mustPress and middlescroll. */
	inline function _calcBaseX(mustHitNote:Bool):Float
	{
		if (FlxG.save.data.middlescroll)
			return mustHitNote ? (FlxG.width / 2 - swagWidth * 2) : -275;
		else
			return mustHitNote ? (FlxG.width / 2 + 100) : 100;
	}

	// ==================== UPDATE ====================

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (Math.abs(Conductor.songPosition - _lastSongPos) > 10)
		{
			_lastSongPos = Conductor.songPosition;

			if (mustPress)
			{
				canBeHit = (strumTime > Conductor.songPosition - _hitWindowCache
					&& strumTime < Conductor.songPosition + (_hitWindowCache / 2.7));
			}
			else
			{
				canBeHit = false;
				if (strumTime <= Conductor.songPosition)
					wasGoodHit = true;
			}
		}

		if (tooLate && alpha > 0.3)
			alpha = 0.3;

		// ── Glow de proximidad ────────────────────────────────────────────────
		// Cuanto more cerca is the note of the strum, more brilla.
		// Only in notes of player that still no have sido golpeadas.
		if (_glowShader != null && mustPress && !wasGoodHit && !tooLate)
		{
			final dist:Float = strumTime - Conductor.songPosition;

			if (dist > 0 && dist < GLOW_START_MS)
			{
				// t = 0 lejos, t = 1 justo en el strum
				final t:Float = 1.0 - (dist / GLOW_START_MS);
				// Quadratic curve: rises slowly and accelerates near the strum
				final curved:Float = t * t;
				_glowShader.intensity = curved * 0.75;
				_glowShader.pulse     = (dist < GLOW_PEAK_MS) ? 1.0 : curved;
			}
			else
			{
				_glowShader.intensity = 0.0;
				_glowShader.pulse     = 0.0;
			}
		}
		else if (_glowShader != null && (wasGoodHit || tooLate))
		{
			// Apagar glow una vez golpeada o perdida
			_glowShader.intensity = 0.0;
			_glowShader.pulse     = 0.0;
		}
	}
}
