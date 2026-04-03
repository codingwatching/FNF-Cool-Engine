package funkin.gameplay.notes;

import flixel.FlxSprite;
import flixel.FlxG;
import flixel.graphics.frames.FlxAtlasFrames;
import funkin.gameplay.notes.NoteSkinSystem;

using StringTools;
/**
 * NoteHoldCover — Animación visual que se muestra mientras el jugador sostiene una nota larga.
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
 *   El cover se centra sobre ese punto más el offset configurado en splash.json.
 *
 * ─── COMPATIBILIDAD CON MODS ─────────────────────────────────────────────────
 *
 *   Toda la resolución de assets pasa por NoteSkinSystem.getHoldCoverTexture()
 *   y NoteSkinSystem.getHoldCoverData(), que buscan primero en el mod activo
 *   y hacen fallback a los assets base automáticamente.
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

	/** Prefijos de animación activos (con sufijo de color si perColorTextures=true). */
	var _startAnim:String = '';
	var _loopAnim:String  = '';
	var _endAnim:String   = '';

	/** Centro del strum guardado para re-centrar tras cambio de skin. */
	var _strumCenterX:Float = 0;
	var _strumCenterY:Float = 0;

	/** GC FIX: shader HSV reutilizado entre activaciones del pool (fallback colorHSV). */
	var _colorSwapShader:funkin.shaders.NoteColorSwapShader = null;
	/** GC FIX: shader RGB por paleta reutilizado entre activaciones del pool (colorDirections). Mismo enfoque que NightmareVision. */
	var _rgbShader:funkin.shaders.NoteRGBPaletteShader = null;
	/** Dirección del último shader aplicado, para detectar cambios. */
	var _lastShaderDir:Int = -1;

	/**
	 * Cache animList: animName → [offsetX, offsetY, flipX:0|1, flipY:0|1].
	 * Construido por _setupAnimations() cuando _hcData.animList != null.
	 * Permite offsets y flipX por animación al estilo personaje.
	 */
	var _animListData:Map<String, Array<Float>> = null;

	/** flipX base del sprite (antes de aplicar per-anim flipX del animList). */
	var _baseFlipX:Bool = false;

	/**
	 * Per-animation positional offsets read from animList (offsetX / offsetY).
	 * Set by _applyAnimListExtras() and consumed by _applyPosition() so that
	 * each animation can shift the cover independently of the global skin offset.
	 */
	var _animOffsetX:Float = 0.0;
	var _animOffsetY:Float = 0.0;

	/**
	 * BUG FIX: dimensiones cacheadas al hacer setup().
	 * width/height cambian frame a frame cuando la animación está en loop
	 * (cada frame puede tener distinto tamaño de hitbox), haciendo que
	 * _applyPosition() calcule una X/Y diferente cada vez que
	 * _updateHoldCoverPositions() la llama → el cover "baila" aunque el
	 * strum esté completamente quieto.
	 * Cacheamos las dimensiones UNA SOLA VEZ al iniciar el cover y las
	 * usamos como referencia fija para todo el ciclo de vida del cover.
	 */
	var _cachedW:Float = 0;
	var _cachedH:Float = 0;

	// ─── Propiedad pública ────────────────────────────────────────────────────

	/**
	 * true mientras el cover esté en uso (START / LOOP / END / END_PENDING).
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

	// ─── API PÚBLICA ──────────────────────────────────────────────────────────

	/**
	 * Prepara el cover para ser usado.
	 * Carga la skin desde NoteSkinSystem (con caché — no recarga si ya es la misma),
	 * centra el sprite sobre el strum y lo pone listo para playStart().
	 *
	 * @param strumCenterX  Centro-X del strum  (strum.x + strum.width  / 2).
	 * @param strumCenterY  Centro-Y del strum  (strum.y + strum.height / 2).
	 * @param noteData      Dirección 0-3 → determina el color (Purple/Blue/Green/Red).
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

		// ── Cargar frames solo si cambió splash o color ───────────────────
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

				_cachedW = width  > 0 ? width  : frameWidth;
				_cachedH = height > 0 ? height : frameHeight;

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

		// ── Shader de colorización automática ──────────────────────────────
		final _hcSplashData = NoteSkinSystem.getSplashData(resolvedSplash);
		// FIX: heredar colorAuto/colorMult/colorDirections del note skin activo
		// cuando el splash.json no los define explícitamente (null).
		// Permite que colorAuto:true en skin.json colorice también los hold covers
		// sin necesitar un splash.json separado.
		final effectiveColorAuto = (_hcSplashData != null && _hcSplashData.colorAuto != null)
			? _hcSplashData.colorAuto
			: (NoteSkinSystem.getCurrentSkinData()?.colorAuto == true);
		final effectiveColorMult = (_hcSplashData != null && _hcSplashData.colorMult != null)
			? _hcSplashData.colorMult
			: (NoteSkinSystem.getCurrentSkinData()?.colorMult ?? 1.0);
		final effectiveColorDirs = (_hcSplashData != null && _hcSplashData.colorDirections != null)
			? _hcSplashData.colorDirections
			: NoteSkinSystem.getCurrentSkinData()?.colorDirections;
		final effectiveColorHSV = (_hcSplashData != null && _hcSplashData.colorHSV != null)
			? _hcSplashData.colorHSV
			: NoteSkinSystem.getCurrentSkinData()?.colorHSV;

		if (effectiveColorAuto == true)
		{
			final _noteDir = ['Purple', 'Blue', 'Green', 'Red'].indexOf(_color);
			final dir      = _noteDir >= 0 ? _noteDir : 0;

			// PRIORIDAD 1: colorDirections → RGB palette shader (mismo enfoque que NightmareVision).
			// Reemplaza los canales R/G/B de la textura con colores reales por dirección.
			if (effectiveColorDirs != null && dir < effectiveColorDirs.length)
			{
				final cd = effectiveColorDirs[dir];
				// GC FIX: reutilizar shader entre activaciones del pool.
				if (_rgbShader == null)
					_rgbShader = new funkin.shaders.NoteRGBPaletteShader();
				if (_lastShaderDir != dir)
					_rgbShader.setColors(cd.r, cd.g, cd.b);
				_colorSwapShader = null;
				_lastShaderDir = dir;
				shader = _rgbShader;
			}
			else
			{
				// PRIORIDAD 2: colorHSV → HSV shift (fallback cuando no hay colorDirections).
				final mult = effectiveColorMult;
				// GC FIX: reutilizar el shader existente.
				if (_colorSwapShader == null)
					_colorSwapShader = new funkin.shaders.NoteColorSwapShader(dir % 4, mult, null);
				else if (_lastShaderDir != dir)
				{
					_colorSwapShader.setDirection(dir % 4, null);
					_colorSwapShader.intensity = mult;
				}
				_rgbShader = null;
				_lastShaderDir = dir;
				shader = _colorSwapShader;
			}
		}
		else
		{
			_lastShaderDir = -1;
			_colorSwapShader = null;
			_rgbShader = null;
			shader = null;
		}

		revive();
		visible = false;
		active  = true;
	}

	/**
	 * Arranca la animación de START.
	 * Cuando termina pasa automáticamente a LOOP (o END si playEnd() fue llamado antes).
	 *
	 * FIX: si startPrefix == loopPrefix (mismo nombre de animación), saltamos
	 * directamente a LOOP. De lo contrario la animación se registra solo una vez
	 * como looped=true (la segunda addByPrefix sobreescribe la primera) y
	 * animation.finished nunca sería true → el state machine se atasca en START.
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
			_applyAnimListExtras(_startAnim);
		}
		else
		{
			// Sin animación de inicio propia → ir directo al loop
			_state = STATE_START;
			_playLoop();
		}
	}

	/**
	 * Arranca END (o marca END_PENDING si START aún no terminó).
	 * @return true si END se inició directamente; false si quedó pendiente.
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
				return true; // ya está saliendo

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
				// START → LOOP cuando la animación termina
				if (animation.name == _startAnim && animation.finished)
					_playLoop();

			case STATE_END_PENDING:
				// START terminó mientras esperábamos el end → ahora reproducir END
				// Cuando startAnim == loopAnim no hay animación de start separada;
				// en ese caso END_PENDING no debería ocurrir (playStart va directo a LOOP).
				// Por seguridad: si estamos en loop y animation.finished=false simplemente
				// esperamos a que playEnd() sea llamado de nuevo desde el exterior.
				if (_startAnim != _loopAnim && animation.name == _startAnim && animation.finished)
					_playEnd();

			case STATE_END:
				// AUTO-KILL cuando el end termina
				if (animation.name == _endAnim && animation.finished)
					_killSelf();

			case STATE_LOOP:
				// looped=true se encarga solo — nada que hacer aquí

			default:
		}
	}

	// ─── PRIVADAS ─────────────────────────────────────────────────────────────

	function _setupAnimations():Void
	{
		if (_hcData == null || frames == null) return;

		_animListData = null;
		_baseFlipX = this.flipX;

		if (_hcData.animList != null && _hcData.animList.length > 0)
		{
			// ── Sistema animList (estilo personaje) ─────────────────────────────
			// Registrar TODAS las entradas del animList.
			// _startAnim/_loopAnim/_endAnim (con sufijo de color) se buscan
			// en la lista por nombre, así que deben coincidir exactamente.
			_animListData = new Map();
			for (entry in _hcData.animList)
			{
				if (entry == null || entry.name == null || entry.prefix == null) continue;

				var fps:Int   = entry.fps      != null ? entry.fps
				              : entry.framerate != null ? Std.int(entry.framerate) : 24;
				var loop:Bool = entry.loop   != null ? entry.loop
				              : entry.looped != null ? entry.looped : false;
				// El loop del animList se respeta; solo override para el loopAnim si no está explícito
				if (entry.name == _loopAnim && entry.loop == null && entry.looped == null)
					loop = true;

				if (entry.indices != null && entry.indices.length > 0)
					animation.add(entry.name, entry.indices, fps, loop);
				else
					animation.addByPrefix(entry.name, entry.prefix, fps, loop);

				var ox:Float = (entry.offsets != null && entry.offsets.length > 0) ? entry.offsets[0] : 0.0;
				var oy:Float = (entry.offsets != null && entry.offsets.length > 1) ? entry.offsets[1] : 0.0;
				var fx:Float = entry.flipX == true ? 1.0 : 0.0;
				var fy:Float = entry.flipY == true ? 1.0 : 0.0;
				_animListData.set(entry.name, [ox, oy, fx, fy]);
			}
		}
		else
		{
			// ── Sistema legacy ───────────────────────────────────────────────────
			final fps:Int     = (_hcData.framerate     != null && _hcData.framerate     > 0) ? _hcData.framerate     : 24;
			final loopFps:Int = (_hcData.loopFramerate != null && _hcData.loopFramerate > 0) ? _hcData.loopFramerate : 48;

			_addPrefixAnim(_startAnim, fps,     false);
			_addPrefixAnim(_loopAnim,  loopFps, true);
			_addPrefixAnim(_endAnim,   fps,     false);
		}
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
		// BUG FIX #1: usar _cachedW/_cachedH (fijados en setup()) en lugar de
		// width/height que varían con cada frame de animación → cover quieto.
		final fw:Float = (_cachedW > 0) ? _cachedW : (width  > 0 ? width  : frameWidth);
		final fh:Float = (_cachedH > 0) ? _cachedH : (height > 0 ? height : frameHeight);

		x = _strumCenterX - fw * 0.5;
		y = _strumCenterY - fh * 0.5;

		// Ajuste fino desde splash.json — convención estándar Flixel:
		//   offset[0] positivo → cover se mueve a la DERECHA  ✓
		//   offset[1] positivo → cover se mueve HACIA ABAJO   ✓
		if (_hcData != null && _hcData.offset != null && _hcData.offset.length >= 2)
		{
			x += _hcData.offset[0];
			y += _hcData.offset[1];
		}

		// Per-animation offsets from animList (set by _applyAnimListExtras).
		x += _animOffsetX;
		y += _animOffsetY;
	}

	function _playLoop():Void
	{
		_state = STATE_LOOP;
		visible = true;
		if (_loopAnim != '' && animation.getByName(_loopAnim) != null)
		{
			animation.play(_loopAnim, true);
			_applyAnimListExtras(_loopAnim);
		}
	}

	function _playEnd():Void
	{
		_state = STATE_END;
		visible = true;
		if (_endAnim != '' && animation.getByName(_endAnim) != null)
		{
			animation.play(_endAnim, true);
			_applyAnimListExtras(_endAnim);
		}
		else
			_killSelf(); // sin animación de fin → desaparecer
	}

	/**
	 * Aplica flipX/flipY del animList para la animación dada (si existe en la cache).
	 * El flipX sigue el patrón XOR de Character.hx: base XOR per-anim.
	 * También almacena los offsets por animación y llama a _applyPosition() para
	 * que el cover se desplace correctamente según el animList.
	 */
	inline function _applyAnimListExtras(animName:String):Void
	{
		if (_animListData == null) return;
		var data = _animListData.get(animName);
		if (data == null)
		{
			// No entry for this anim — clear any previously stored per-anim offset
			// so leftover values from the previous animation don't bleed through.
			_animOffsetX = 0.0;
			_animOffsetY = 0.0;
			_applyPosition();
			return;
		}
		var animFlipX:Bool = data[2] > 0.5;
		this.flipX = _baseFlipX != animFlipX;
		if (data[3] > 0.5) this.flipY = !this.flipY;
		// Store per-anim offsets so _applyPosition() can read them.
		_animOffsetX = data[0];
		_animOffsetY = data[1];
		_applyPosition();
	}

	function _killSelf():Void
	{
		_state  = STATE_IDLE;
		visible = false;
		active  = false;
		kill();
	}

	/**
	 * Mata el cover instantáneamente sin reproducir la animación de end.
	 * Usado para el CPU (igual que V-Slice), donde el end del hold splash es invisible.
	 */
	public function killInstant():Void
	{
		_killSelf();
	}

	// ─── LIVE STRUM TRACKING ──────────────────────────────────────────────────

	/**
	 * Update the cover's world position to match the strum's CURRENT center.
	 *
	 * WHY THIS IS NEEDED:
	 *   setup() captures the strum center once when the hold begins.
	 *   When strums move mid-song (modcharts, stage events, scripted offsets)
	 *   the cover drifts out of sync — it stays at the old position while the
	 *   strum moves underneath it.  NoteManager calls this every frame while
	 *   the cover is active so it tracks the strum in real time.
	 *
	 * @param strumCenterX  Current horizontal center of the strum sprite.
	 * @param strumCenterY  Current vertical center of the strum sprite.
	 */
	public function updatePosition(strumCenterX:Float, strumCenterY:Float):Void
	{
		if (!alive) return;

		_strumCenterX = strumCenterX;
		_strumCenterY = strumCenterY;
		_applyPosition();
	}
}
