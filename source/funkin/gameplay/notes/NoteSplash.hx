package funkin.gameplay.notes;

import flixel.FlxG;
import flixel.FlxSprite;
import funkin.gameplay.notes.NoteSkinSystem;
import funkin.gameplay.notes.NoteSkinSystem.NoteSplashData;

/**
 * Splash visual que aparece al golpear una nota normal.
 *
 * Basado en el patrón limpio de v-slice (NoteSplash.hx):
 * - Responsabilidad única: splashes de hit, sin ningún código de hold
 * - Object pooling con kill()/revive()
 * - Animaciones registradas una sola vez; se reaprovechan entre reciclajes
 * - Skin soportada vía NoteSkinSystem
 *
 * Para splashes de hold notes, ver NoteHoldCover.hx
 */
class NoteSplash extends FlxSprite
{
	/** Dirección de la nota (0=left 1=down 2=up 3=right). */
	public var noteData:Int = 0;

	/** true mientras el splash está en uso (no en el pool). */
	public var inUse:Bool = false;

	/** Nombre del splash skin con el que se cargaron los frames actuales. */
	private var _loadedSplash:String = "";

	/** Offset del JSON del splash, re-aplicado en cada setup(). */
	private var _splashOffsetX:Float = 0.0;

	private var _splashOffsetY:Float = 0.0;

	/** Shader HSV reutilizado entre activaciones del pool (fallback colorHSV). */
	private var _colorSwapShader:funkin.shaders.NoteColorSwapShader = null;

	/** Shader RGB por paleta reutilizado entre activaciones del pool (colorDirections). Mismo enfoque que NightmareVision. */
	private var _rgbShader:funkin.shaders.NoteRGBPaletteShader = null;

	/** Dirección de la última activación, para detectar si hay que actualizar el shader. */
	private var _lastShaderDir:Int = -1;

	/**
	 * Cache animList: animName → [offsetX, offsetY, flipX:0|1, flipY:0|1].
	 * Construido por _loadFrames() cuando splashData.animList != null.
	 * Usado en _playRandomAnim() para aplicar offsets y flipX al estilo personaje.
	 */
	private var _animListData:Map<String, Array<Float>> = null;

	/** flipX base del sprite (antes de aplicar per-anim flipX del animList). */
	private var _baseFlipX:Bool = false;

	// ─────────────────────────────────────────────────────────────────────────

	public function new()
	{
		super(0, 0);
		kill();
	}

	// ─────────────── API pública ──────────────────────────────────────────────

	/**
	 * Inicializar/reciclar el splash para una nota.
	 *
	 * @param x          Posición X
	 * @param y          Posición Y
	 * @param noteData   Columna de la nota (0-3)
	 * @param splashName Skin de splash (null = currentSplash)
	 */
	public function setup(x:Float, y:Float, noteData:Int = 0, ?splashName:String):Void
	{
		this.noteData = noteData;
		// El offset se aplica después de cargar frames (ver _loadFrames).
		// Guardado en _splashOffsetX/Y y re-aplicado aquí en cada reuse.
		this.x = x + _splashOffsetX;
		this.y = y + _splashOffsetY;
		inUse = true;

		var targetSplash:String = splashName != null ? splashName : NoteSkinSystem.currentSplash;

		// Obtener datos del splash
		var splashData:NoteSplashData = NoteSkinSystem.getSplashData(targetSplash);
		if (splashData == null)
		{
			_fallback();
			return;
		}

		// Solo recargar atlas si el skin cambió o el bitmap fue destruido
		@:privateAccess
		var needsReload = (_loadedSplash != targetSplash) || frames == null || frames.parent == null || frames.parent.bitmap == null;

		if (needsReload)
		{
			// Reset offset antes de cargar — _loadFrames lo recalculará
			_splashOffsetX = 0.0;
			_splashOffsetY = 0.0;
			if (!_loadFrames(splashData, targetSplash))
			{
				_fallback();
				return;
			}
			_loadedSplash = targetSplash;
			// Re-aplicar el offset ahora que _loadFrames lo calculó
			this.x = x + _splashOffsetX;
			this.y = y + _splashOffsetY;
		}

		alpha = 0.7;
		visible = true;
		revive();

		_playRandomAnim(splashData, noteData);

		// ── Shader de colorización automática ───────────────────────────────
		// FIX: si el splash.json no define colorAuto explícitamente (null),
		// heredar el valor del note skin activo. Esto permite que con solo poner
		// colorAuto:true en skin.json los splashes también se coloricen, sin
		// necesitar un splash.json separado con el mismo campo.
		// Un splash.json que ponga colorAuto:false sigue pudiendo forzar "sin color".
		final effectiveColorAuto = splashData.colorAuto != null ? splashData.colorAuto : (NoteSkinSystem.getCurrentSkinData()?.colorAuto == true);
		final effectiveColorDirs = splashData.colorDirections != null ? splashData.colorDirections : NoteSkinSystem.getCurrentSkinData()?.colorDirections;
		final effectiveColorHSV  = splashData.colorHSV        != null ? splashData.colorHSV        : NoteSkinSystem.getCurrentSkinData()?.colorHSV;

		if (effectiveColorAuto == true)
		{
			final dir = noteData % 4;

			// PRIORIDAD 1: colorDirections → RGB palette shader (mismo enfoque que NightmareVision).
			// Reemplaza los canales R/G/B de la textura con colores reales por dirección.
			if (effectiveColorDirs != null && dir < effectiveColorDirs.length)
			{
				final cd = effectiveColorDirs[dir];
				if (_rgbShader == null)
					_rgbShader = new funkin.shaders.NoteRGBPaletteShader();
				_rgbShader.setColors(cd.r, cd.g, cd.b);
				_colorSwapShader = null;
				_lastShaderDir = dir;
				shader = _rgbShader;
			}
			else
			{
				// PRIORIDAD 2: colorHSV → HSV shift (fallback cuando no hay colorDirections).
				final entry = (effectiveColorHSV != null && dir < effectiveColorHSV.length) ? effectiveColorHSV[dir] : {h: 0.0, s: 0.0, b: 0.0};
				if (_colorSwapShader == null)
					_colorSwapShader = new funkin.shaders.NoteColorSwapShader();
				_colorSwapShader.applyEntry(entry);
				_rgbShader = null;
				_lastShaderDir = dir;
				shader = _colorSwapShader;
			}
		}
		else
		{
			_lastShaderDir = -1;
			_rgbShader = null;
			shader = null;
		}
	}

	// ─────────────────────────────────────────────────────────────────────────

	override function kill():Void
	{
		super.kill();
		inUse = false;
		visible = false;
	}

	override function revive():Void
	{
		super.revive();
		visible = true;
	}

	// ─────────────── Internos ────────────────────────────────────────────────

	/**
	 * Cargar el atlas y registrar todas las animaciones.
	 * Solo se llama cuando el skin realmente cambió.
	 */
	private function _loadFrames(splashData:NoteSplashData, splashName:String):Bool
	{
		var loaded = NoteSkinSystem.getSplashTexture(splashName);
		if (loaded == null)
			return false;

		frames = loaded;

		var assets = splashData.assets;
		scale.set(assets.scale != null ? assets.scale : 1.0, assets.scale != null ? assets.scale : 1.0);
		antialiasing = assets.antialiasing != null ? assets.antialiasing : true;

		// Registrar animaciones para las 4 direcciones.
		// Prioridad: animList (estilo personaje) → campo animations (legacy).
		if (animation != null)
			animation.destroyAnimations();
		_animListData = null;

		var dirs = ["left", "down", "up", "right"];

		if (splashData.animList != null && splashData.animList.length > 0)
		{
			// ── Sistema animList ───────────────────────────────────────────────
			// Registrar TODAS las entradas del list tal cual.
			// _playRandomAnim() las resuelve por dirección con resolveSplashNamesFromAnimList().
			_animListData = NoteSkinSystem.loadAnimList(this, splashData.animList);
			_baseFlipX = this.flipX;
		}
		else
		{
			// ── Sistema legacy ─────────────────────────────────────────────────
			var anims = splashData.animations;
			var framerate:Int = (anims != null && anims.framerate != null) ? anims.framerate : 24;

			if (anims != null)
			{
				for (i in 0...4)
				{
					var animList:Array<String> = NoteSkinSystem.resolveSplashList(anims, i);
					if (animList == null)
						continue;
					for (j in 0...animList.length)
						animation.addByPrefix('${dirs[i]}_$j', animList[j], framerate, false);
				}
			}
		}

		animation.finishCallback = _onAnimationFinished;

		updateHitbox();
		offset.set(width * 0.3, height * 0.3);

		if (assets.offset != null && assets.offset.length >= 2)
		{
			_splashOffsetX = assets.offset[0];
			_splashOffsetY = assets.offset[1];
		}

		return true;
	}

	/**
	 * Reproducir una variante aleatoria de la dirección indicada.
	 */
	private function _playRandomAnim(splashData:NoteSplashData, noteData:Int):Void
	{
		var dirs = ["left", "down", "up", "right"];
		var animName:String = '';
		var baseFps:Int = 24;
		var range:Int = 2;

		if (_animListData != null && splashData.animList != null)
		{
			// ── Sistema animList ─────────────────────────────────────────────────
			var variants:Array<String> = NoteSkinSystem.resolveSplashNamesFromAnimList(splashData.animList, noteData);
			if (variants == null || variants.length == 0)
				return;

			animName = variants[FlxG.random.int(0, variants.length - 1)];
			if (!animation.exists(animName))
				return;

			// Resetear flipX al base antes de aplicar per-anim flipX
			this.flipX = _baseFlipX;
			this.flipY = false;

			animation.play(animName, true);

			// Offsets y flipX desde animListData
			// FIX: centerOffsets() centra el gráfico (offset = width/2, height/2).
			// _splashOffsetX/Y ya está en this.x/y desde setup() — NO añadir a offset.x
			// porque Flixel lo RESTA al renderizar (→ positivo iba a la izquierda).
			// Los offsets per-animación también van a this.x/y directamente:
			//   positivo X = derecha ✓   positivo Y = abajo ✓
			var data = _animListData.get(animName);
			centerOffsets(); // centra gráfico sobre hitbox
			if (data != null)
			{
				this.x += data[0]; // positivo → derecha
				this.y += data[1]; // positivo → abajo
				if (data[2] > 0.5)
					this.flipX = !this.flipX;
				if (data[3] > 0.5)
					this.flipY = !this.flipY;
			}

			// FPS aleatorio usando la entrada del animList
			for (entry in splashData.animList)
			{
				if (entry != null && entry.name == animName)
				{
					baseFps = entry.fps != null ? entry.fps : entry.framerate != null ? Std.int(entry.framerate) : 24;
					break;
				}
			}
		}
		else
		{
			// ── Sistema legacy ────────────────────────────────────────────────────
			var animList:Array<String> = NoteSkinSystem.resolveSplashList(splashData.animations, noteData);
			if (animList == null || animList.length == 0)
				return;

			var variant:Int = FlxG.random.int(0, animList.length - 1);
			animName = '${dirs[noteData]}_$variant';
			if (!animation.exists(animName))
				return;

			range = splashData.animations.randomFramerateRange != null ? splashData.animations.randomFramerateRange : 2;
			baseFps = splashData.animations.framerate != null ? splashData.animations.framerate : 24;
		}

		if (animName != '' && animation.exists(animName))
		{
			if (_animListData == null)
				animation.play(animName, true); // legacy ya llamó play arriba si es animList
			if (animation.curAnim != null)
				animation.curAnim.frameRate = baseFps + FlxG.random.int(-range, range);
		}
	}

	private function _onAnimationFinished(name:String):Void
	{
		kill();
	}

	private function _fallback():Void
	{
		makeGraphic(1, 1, 0x00000000);
		inUse = false;
		visible = false;
	}
}
