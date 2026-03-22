package funkin.gameplay.notes;

import flixel.FlxSprite;
import flixel.FlxG;
import flixel.graphics.frames.FlxAtlasFrames;
import funkin.gameplay.notes.NoteSkinSystem;

using StringTools;
/**
 * NoteHoldCover — Animation visual that is muestra mientras the jugador sostiene a note larga.
 *
 * ─── CICLO DE VIDA ───────────────────────────────────────────────────────────
 *
 *   IDLE ──playStart()──→ START ──(fin)──→ LOOP
 *                                           │
 *                              playEnd() ───┤
 *                                           ▼
 *                                          END ──(fin)──→ IDLE (kill)
 *
 *   Si playEnd() se llama durante START → END_PENDING:
 *   cuando START termina pasa a END directamente sin pasar por LOOP.
 *
 * ─── POSICIONAMIENTO ─────────────────────────────────────────────────────────
 *
 *   setup() recibe el CENTRO del strum (strumCenterX, strumCenterY).
 *   NoteManager debe pasar strum.x + strum.width/2 y strum.y + strum.height/2.
 *   The cover is centra over that punto more the offset configurado in splash.json.
 *
 * ─── COMPATIBILIDAD CON MODS ─────────────────────────────────────────────────
 *
 *   All the resolution of assets pasa by NoteSkinSystem.getHoldCoverTexture()
 *   y NoteSkinSystem.getHoldCoverData(), que buscan primero en el mod activo
 *   and hacen fallback to the assets base automatically.
 */
class NoteHoldCover extends FlxSprite
{
	// ─── Estados ──────────────────────────────────────────────────────────────
	static inline var STATE_IDLE        = 0;
	static inline var STATE_START       = 1;
	static inline var STATE_LOOP        = 2;
	static inline var STATE_END         = 3;
	static inline var STATE_END_PENDING = 4;

	var _state:Int = STATE_IDLE;

	// ─── Skin cargada ─────────────────────────────────────────────────────────
	var _hcData:NoteSkinSystem.NoteHoldCoverData = null;
	var _color:String        = 'Purple';
	var _loadedSplash:String = '';
	var _loadedColor:String  = '';

	/** Prefijos of animation activos (with suffix of color if perColorTextures=true). */
	var _startAnim:String = '';
	var _loopAnim:String  = '';
	var _endAnim:String   = '';

	/** Centro del strum guardado para re-centrar tras cambio de skin. */
	var _strumCenterX:Float = 0;
	var _strumCenterY:Float = 0;

	// ─── Propiedad public ────────────────────────────────────────────────────

	/**
	 * true while the cover is in uso (START / LOOP / END / END_PENDING).
	 * NoteRenderer lo comprueba para decidir si puede reutilizar este cover del pool.
	 */
	public var inUse(get, never):Bool;
	inline function get_inUse():Bool return _state != STATE_IDLE && alive;

	public function new()
	{
		super(0, 0);
		visible = false;
		active  = false;
		alive   = false;
	}

	// ─── API public ──────────────────────────────────────────────────────────

	/**
	 * Prepara el cover para ser usado.
	 * Load the skin from NoteSkinSystem (with cache — no recarga if already is the misma),
	 * centra el sprite sobre el strum y lo pone listo para playStart().
	 *
	 * @param strumCenterX  Centro-X del strum  (strum.x + strum.width  / 2).
	 * @param strumCenterY  Centro-Y del strum  (strum.y + strum.height / 2).
	 * @param noteData      Direction 0-3 → determina the color (Purple/Blue/Green/Red).
	 * @param splashName    Override de splash (null = splash activo del sistema).
	 */
	public function setup(strumCenterX:Float, strumCenterY:Float, noteData:Int, ?splashName:String):Void
	{
		_state = STATE_IDLE;
		_strumCenterX = strumCenterX;
		_strumCenterY = strumCenterY;

		final colors = ['Purple', 'Blue', 'Green', 'Red'];
		_color = (noteData >= 0 && noteData < colors.length) ? colors[noteData] : 'Purple';

		final resolvedSplash = (splashName != null && splashName != '')
			? splashName
			: NoteSkinSystem.currentSplash;

		// ── Load frames only if changed splash or color ───────────────────
		if (resolvedSplash != _loadedSplash || _color != _loadedColor || frames == null)
		{
			_hcData = NoteSkinSystem.getHoldCoverData(resolvedSplash);

			var atlasFrames:FlxAtlasFrames = null;
			try { atlasFrames = NoteSkinSystem.getHoldCoverTexture(_color, resolvedSplash); }
			catch (e:Dynamic) { trace('[NoteHoldCover] Error cargando textura $_color/$resolvedSplash: $e'); }

			// Fallback a Default si el splash no tiene holdCover
			if (atlasFrames == null && resolvedSplash != 'Default')
			{
				try { atlasFrames = NoteSkinSystem.getHoldCoverTexture(_color, 'Default'); }
				catch (e:Dynamic) {}
				if (atlasFrames != null)
				{
					_hcData = NoteSkinSystem.getHoldCoverData('Default');
					trace('[NoteHoldCover] "$resolvedSplash" sin holdCover → usando Default para $_color');
				}
			}

			if (atlasFrames != null)
			{
				frames = atlasFrames;

				// Prefijos con sufijo de color si perColorTextures=true
				final perColor    = (_hcData.perColorTextures == true);
				final colorSuffix = perColor ? _color : '';
				_startAnim = (_hcData.startPrefix != null ? _hcData.startPrefix : 'holdCoverStart') + colorSuffix;
				_loopAnim  = (_hcData.loopPrefix  != null ? _hcData.loopPrefix  : 'holdCover')      + colorSuffix;
				_endAnim   = (_hcData.endPrefix   != null ? _hcData.endPrefix   : 'holdCoverEnd')   + colorSuffix;

				_setupAnimations();

				antialiasing = (_hcData.antialiasing == true);
				final s:Float = (_hcData.scale != null && _hcData.scale > 0) ? _hcData.scale : 1.0;
				scale.set(s, s);
				updateHitbox();

				_loadedSplash = resolvedSplash;
				_loadedColor  = _color;
			}
			else
			{
				trace('[NoteHoldCover] WARN: sin frames para $_color/$resolvedSplash → cover invisible');
				makeGraphic(1, 1, 0x00000000);
				_loadedSplash = '';
				_loadedColor  = '';
				_startAnim = _loopAnim = _endAnim = '';
			}
		}

		// ── Centrar el cover sobre el strum ───────────────────────────────
		_applyPosition();

		revive();
		visible = false;
		active  = true;
	}

	/**
	 * Arranca the animation of START.
	 * When termina pasa automatically to LOOP (or END if playEnd() was calldo before).
	 *
	 * FIX: if startPrefix == loopPrefix (mismo nombre of animation), saltamos
	 * directamente to LOOP. Of it contrario the animation is registra only a vez
	 * como looped=true (la segunda addByPrefix sobreescribe la primera) y
	 * animation.finished never would be true → the state machine is atasca in START.
	 */
	public function playStart():Void
	{
		if (!alive) return;

		final hasUniqueStart = (_startAnim != '' && _startAnim != _loopAnim
			&& animation.getByName(_startAnim) != null);

		if (hasUniqueStart)
		{
			_state = STATE_START;
			visible = true;
			animation.play(_startAnim, true);
		}
		else
		{
			// Without animation of start propia → ir directo to the loop
			_state = STATE_START;
			_playLoop();
		}
	}

	/**
	 * Arranca END (or marca END_PENDING if START still no ended).
	 * @return true if END is inició directly; false if quedó pending.
	 */
	public function playEnd():Bool
	{
		switch (_state)
		{
			case STATE_LOOP:
				_playEnd();
				return true;

			case STATE_START:
				_state = STATE_END_PENDING;
				return false;

			case STATE_END, STATE_END_PENDING:
				return true; // already is saliendo

			default:
				_killSelf();
				return true;
		}
	}

	// ─── UPDATE ───────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (!alive) return;

		switch (_state)
		{
			case STATE_START:
				// START → LOOP when the animation termina
				if (animation.name == _startAnim && animation.finished)
					_playLoop();

			case STATE_END_PENDING:
				// START ended while we waited for end → now play END
				// When startAnim == loopAnim no there is animation of start separada;
				// in that case END_PENDING no debería ocurrir (playStart va directo to LOOP).
				// Por seguridad: si estamos en loop y animation.finished=false simplemente
				// esperamos a que playEnd() sea llamado de nuevo desde el exterior.
				if (_startAnim != _loopAnim && animation.name == _startAnim && animation.finished)
					_playEnd();

			case STATE_END:
				// AUTO-KILL cuando el end termina
				if (animation.name == _endAnim && animation.finished)
					_killSelf();

			case STATE_LOOP:
				// looped=true is encarga only — nada that do here

			default:
		}
	}

	// ─── PRIVADAS ─────────────────────────────────────────────────────────────

	function _setupAnimations():Void
	{
		if (_hcData == null || frames == null) return;

		final fps:Int     = (_hcData.framerate     != null && _hcData.framerate     > 0) ? _hcData.framerate     : 24;
		final loopFps:Int = (_hcData.loopFramerate != null && _hcData.loopFramerate > 0) ? _hcData.loopFramerate : 48;

		_addPrefixAnim(_startAnim, fps,     false);
		_addPrefixAnim(_loopAnim,  loopFps, true);
		_addPrefixAnim(_endAnim,   fps,     false);
	}

	inline function _addPrefixAnim(prefix:String, fps:Int, looped:Bool):Void
	{
		if (prefix == '' || frames == null) return;
		var found = false;
		for (f in frames.frames)
			if (f.name != null && f.name.startsWith(prefix)) { found = true; break; }
		if (found)
			animation.addByPrefix(prefix, prefix, fps, looped);
	}

	/**
	 * Centra el cover sobre _strumCenterX / _strumCenterY (centro VISUAL del strum).
	 *
	 * FIX: usar width/height (ya incluyen scale) en lugar de frameWidth/frameHeight
	 * que son las dimensiones del frame SIN escalar. Con scale=4 y frameWidth=200,
	 * width=800 — usar frameWidth desplazaba el cover ~300px a la derecha.
	 *
	 * El offset del splash.json permite ajuste fino por skin.
	 */
	function _applyPosition():Void
	{
		// width/height ya incorporan scale → correcto para cualquier escala
		final fw:Float = (width  > 0) ? width  : frameWidth;
		final fh:Float = (height > 0) ? height : frameHeight;

		x = _strumCenterX - fw * 0.5 - 20;
		y = _strumCenterY - fh * 0.5 + 40;

		// Ajuste fino desde splash.json
		if (_hcData != null && _hcData.offset != null && _hcData.offset.length >= 2)
		{
			x += _hcData.offset[0];
			y += _hcData.offset[1];
		}
	}

	function _playLoop():Void
	{
		_state = STATE_LOOP;
		visible = true;
		if (_loopAnim != '' && animation.getByName(_loopAnim) != null)
			animation.play(_loopAnim, true);
	}

	function _playEnd():Void
	{
		_state = STATE_END;
		visible = true;
		if (_endAnim != '' && animation.getByName(_endAnim) != null)
			animation.play(_endAnim, true);
		else
			_killSelf(); // without animation of fin → desaparecer
	}

	function _killSelf():Void
	{
		_state  = STATE_IDLE;
		visible = false;
		active  = false;
		kill();
	}
}
