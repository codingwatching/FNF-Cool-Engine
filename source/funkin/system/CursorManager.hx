package funkin.system;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import haxe.Json;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.display.Sprite as OflSprite;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;

#if sys
import sys.FileSystem;
import sys.io.File;
#else
import openfl.Assets as OpenFlAssets;
#end

using StringTools;

/**
 * CursorManager v3 — cursor personalizable para Cool Engine.
 *
 * ─── Arquitectura (reescrita) ─────────────────────────────────────────────────
 *
 *  Usa puro OpenFL sin FlxCamera ni FlxSprite para renderizar.
 *  El OflSprite contenedor se posiciona en stage.mouseX/Y cada tick,
 *  y dentro hay un Bitmap con el frame actual del cursor.
 *
 *  Animación: carga el atlas Sparrow una vez, extrae los BitmapData de cada
 *  frame y los cicla con un simple timer. Sin FlxCamera → sin problemas de
 *  coordenadas, zoom, letterbox ni state-switch.
 *
 *  Sobrevive entre estados vía FlxG.signals.preUpdate (mismo patrón que SoundTray).
 *
 * ─── Uso ──────────────────────────────────────────────────────────────────────
 *
 *   // Main.hx — una sola vez, tras initializeFunkin():
 *   CursorManager.init();
 *   CursorManager.loadSkinPreference();
 *
 *   // PlayState.create()  → ocultar en gameplay:
 *   CursorManager.pushHidden();
 *
 *   // PlayState.destroy() → restaurar:
 *   CursorManager.popHidden();
 *
 *   // Cambiar estado manualmente:
 *   CursorManager.setState(CursorState.HOVER);
 *
 * ─── cursor.json ──────────────────────────────────────────────────────────────
 *
 *  assets/data/config/cursor.json
 *  {
 *    "scale": 1.0,
 *    "states": {
 *      "default":  { "atlas": "menu/cursor/cursor-default", "anim": "idle", "fps": 12, "hotspotX": 0, "hotspotY": 0 },
 *      "hover":    { "atlas": "menu/cursor/cursor-hover",   "anim": "idle", "fps": 12 },
 *      "click":    { "atlas": "menu/cursor/cursor-click",   "anim": "press","fps": 24 }
 *    }
 *  }
 *
 * @author  Cool Engine Team
 * @version 3.0.0
 */

// ── Tipos ─────────────────────────────────────────────────────────────────────

enum abstract CursorState(String) to String
{
	var DEFAULT   = "default";
	var HOVER     = "hover";
	var CLICK     = "click";
	var DRAG      = "drag";
	var TEXT      = "text";
	var CROSSHAIR = "crosshair";
	var WAIT      = "wait";
	var HIDDEN    = "hidden";
}

typedef CursorStateData =
{
	@:optional var atlas    : String;
	@:optional var anim     : String;
	@:optional var fps      : Int;
	@:optional var loop     : Bool;
	@:optional var hotspotX : Float;
	@:optional var hotspotY : Float;
}

typedef CursorConfig =
{
	@:optional var skin   : String;
	@:optional var scale  : Float;
	@:optional var alpha  : Float;
	@:optional var tint   : String;
	@:optional var trail  : Bool;
	@:optional var ripple : Bool;
	@:optional var states : Dynamic;
}

// ─────────────────────────────────────────────────────────────────────────────
// CursorManager — singleton estático
// ─────────────────────────────────────────────────────────────────────────────

class CursorManager
{
	static var _container   : CursorContainer = null;
	static var _initialized : Bool = false;
	static var _config      : CursorConfig = null;

	public static var state(default, null) : CursorState = DEFAULT;
	static var _hiddenStack  : Int = 0;
	/** Visibilidad del cursor — usar show()/hide() o FlxG.mouse.visible. */
	static var _visible      : Bool = false;
	/** Carga diferida — se activa en init y se resuelve en el primer tick. */
	static var _needsLoad    : Bool = false;
	static var _hoverTargets : Array<FlxSprite> = [];

	public static var scale(get, set) : Float;
	static var _scale : Float = 1.0;

	public static var alpha(get, set) : Float;

	static inline final CONFIG_PATH : String = 'assets/data/config/cursor.json';
	static inline final SKINS_DIR   : String = 'assets/data/config/cursors/';

	// ── Init ─────────────────────────────────────────────────────────────────

	public static function init():Void
	{
		if (_initialized) return;

		// Ocultar cursor nativo a todos los niveles
		openfl.ui.Mouse.hide();
		FlxG.mouse.useSystemCursor = false;
		FlxG.mouse.visible = false;

		_config = _loadConfig(CONFIG_PATH);

		_container = new CursorContainer();
		_container.insert();

		_applyConfig(_config);
		// loadState se hace en el primer tick para que los assets estén listos
		_needsLoad = true;

		_initialized = true;
		trace('[CursorManager] Init OK.');
	}

	// ── Estado ───────────────────────────────────────────────────────────────

	public static function setState(s:CursorState, force:Bool = false):Void
	{
		if (!_initialized || _container == null) return;
		if (state == s && !force) return;
		state = s;

		if (s == HIDDEN)
		{
			_container.visible = false;
			return;
		}
		// Visibilidad manejada en _tick según _hiddenStack
		_container.loadState(s, _config);
	}

	public static function pushHidden():Void
	{
		_hiddenStack++;
		FlxG.mouse.visible = false;
		if (_container != null) _container.visible = false;
	}

	public static function popHidden():Void
	{
		_hiddenStack = Std.int(Math.max(0, _hiddenStack - 1));
	}

	/** Muestra el cursor personalizado. Equivale a FlxG.mouse.visible = true. */
	public static function show():Void  { _visible = true; }

	/** Oculta el cursor personalizado. Equivale a FlxG.mouse.visible = false. */
	public static function hide():Void
	{
		_visible = false;
		if (_container != null) _container.visible = false;
	}

	// ── Skins ─────────────────────────────────────────────────────────────────

	public static function loadSkin(skinName:String):Void
	{
		if (!_initialized) return;
		var path = '${SKINS_DIR}${skinName}.json';
		#if sys
		if (mods.ModManager.isActive())
		{
			var mp = '${mods.ModManager.modRoot()}/data/config/cursors/${skinName}.json';
			if (FileSystem.exists(mp)) path = mp;
		}
		if (!FileSystem.exists(path)) { trace('[CursorManager] Skin "$skinName" no encontrado.'); return; }
		#end
		_config = _loadConfig(path);
		_applyConfig(_config);
		setState(state, true);
	}

	public static function getAvailableSkins():Array<String>
	{
		var skins:Array<String> = ['default'];
		#if sys
		if (FileSystem.exists(SKINS_DIR) && FileSystem.isDirectory(SKINS_DIR))
			for (f in FileSystem.readDirectory(SKINS_DIR))
				if (f.endsWith('.json')) skins.push(f.substr(0, f.length - 5));
		if (mods.ModManager.isActive())
		{
			var d = '${mods.ModManager.modRoot()}/data/config/cursors/';
			if (FileSystem.exists(d) && FileSystem.isDirectory(d))
				for (f in FileSystem.readDirectory(d))
					if (f.endsWith('.json') && !skins.contains(f.substr(0, f.length - 5)))
						skins.push(f.substr(0, f.length - 5));
		}
		#end
		return skins;
	}

	// ── Auto-hover ────────────────────────────────────────────────────────────

	public static function registerHoverTarget(s:FlxSprite):Void
		{ if (!_hoverTargets.contains(s)) _hoverTargets.push(s); }

	public static function unregisterHoverTarget(s:FlxSprite):Void
		_hoverTargets.remove(s);

	public static function clearHoverTargets():Void
		_hoverTargets = [];

	// ── Propiedades ───────────────────────────────────────────────────────────

	public static function set_scale(v:Float):Float
	{
		_scale = v;
		if (_container != null) _container.setScale(v);
		return v;
	}
	public static function get_scale():Float return _scale;

	public static function set_alpha(v:Float):Float
	{
		if (_container != null) _container.alpha = v;
		return v;
	}
	public static function get_alpha():Float
		return (_container != null) ? _container.alpha : 1.0;

	// ── Tick interno ─────────────────────────────────────────────────────────

	@:allow(funkin.system.CursorContainer)
	static function _tick():Void
	{
		if (!_initialized || _container == null) return;

		// Carga diferida: ahora sí los assets están disponibles
		if (_needsLoad)
		{
			_needsLoad = false;
			_container.loadState(DEFAULT, _config);
			// visible se aplica en la sección de visibilidad de abajo
			state = DEFAULT;
		}

		// Bloquear SIEMPRE el cursor nativo — no leerlo, solo escribirlo.
		FlxG.mouse.visible = false;
		openfl.ui.Mouse.hide();
		// _visible es la única fuente de verdad — se controla con show()/hide()
		_container.visible = _visible && (_hiddenStack == 0) && (state != HIDDEN);

		// Auto-estado
		var onTarget = _checkHoverTargets();

		if (FlxG.mouse.justPressed && state != CLICK)
		{
			setState(CLICK);
			if (_config != null && _config.ripple != false)
				_container.spawnRipple();

			new FlxTimer().start(0.15, function(_)
			{
				if (state == CLICK) setState(onTarget ? HOVER : DEFAULT);
			});
		}
		else if (!FlxG.mouse.pressed && state == CLICK)
			setState(onTarget ? HOVER : DEFAULT);
		else if (state != CLICK)
			setState(onTarget ? HOVER : DEFAULT);

		if (_config != null && _config.trail == true)
			_container.spawnTrail();
	}

	static function _checkHoverTargets():Bool
	{
		for (t in _hoverTargets)
		{
			if (t == null || !t.alive || !t.visible) continue;
			var cam = (t.cameras != null && t.cameras.length > 0) ? t.cameras[0] : FlxG.camera;
			if (t.overlapsPoint(FlxG.mouse.getWorldPosition(cam))) return true;
		}
		return false;
	}

	// ── Config ────────────────────────────────────────────────────────────────

	static function _loadConfig(path:String):CursorConfig
	{
		var raw:String = null;
		#if sys
		if (FileSystem.exists(path)) try { raw = File.getContent(path); } catch (_) {}
		#else
		if (OpenFlAssets.exists(path)) try { raw = OpenFlAssets.getText(path); } catch (_) {}
		#end
		if (raw == null) return _defaultConfig();
		try { return cast Json.parse(raw); } catch (_) { return _defaultConfig(); }
	}

	static function _defaultConfig():CursorConfig
	{
		return {
			skin: 'default', scale: 1.0, alpha: 1.0,
			tint: '0xFFFFFFFF', trail: false, ripple: true,
			states: {
				"default": { atlas:'menu/cursor/cursor-default', anim:'idle',  fps:12, loop:true,  hotspotX:0, hotspotY:0 },
				"hover":   { atlas:'menu/cursor/cursor-hover',   anim:'idle',  fps:12, loop:true,  hotspotX:0, hotspotY:0 },
				"click":   { atlas:'menu/cursor/cursor-click',   anim:'press', fps:24, loop:false, hotspotX:0, hotspotY:0 }
			}
		};
	}

	static function _applyConfig(cfg:CursorConfig):Void
	{
		if (cfg == null || _container == null) return;
		_scale = cfg.scale ?? 1.0;
		_container.setScale(_scale);
		_container.alpha = cfg.alpha ?? 1.0;
		if (cfg.tint != null)
			try { _container.setTint(FlxColor.fromInt(Std.parseInt(cfg.tint))); } catch (_) {}
	}

	// ── Persistencia ──────────────────────────────────────────────────────────

	public static function saveSkinPreference(skinName:String):Void
	{
		FlxG.save.data.cursorSkin = skinName;
		FlxG.save.flush();
	}

	public static function loadSkinPreference():Void
	{
		var saved:String = FlxG.save.data.cursorSkin;
		if (saved != null && saved != '' && saved != 'default') loadSkin(saved);
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// CursorContainer — OflSprite puro, sin FlxCamera
//
// Se posiciona en stage.mouseX/Y cada tick.
// Renderiza el cursor con un openfl.display.Bitmap (frame del atlas).
// ─────────────────────────────────────────────────────────────────────────────

class CursorContainer extends OflSprite
{
	// ── Display ───────────────────────────────────────────────────────────────
	var _bmp       : Bitmap;          // el Bitmap visible del cursor
	var _scale     : Float = 1.0;

	// ── Animación ─────────────────────────────────────────────────────────────
	var _frames    : Array<BitmapData> = [];  // frames extraídos del atlas
	var _frameIdx  : Int   = 0;
	var _fps       : Float = 12;
	var _loop      : Bool  = true;
	var _frameTime : Float = 0;
	var _elapsed   : Float = 0;

	// ── Hotspot ───────────────────────────────────────────────────────────────
	var _hotX : Float = 0;
	var _hotY : Float = 0;

	// ── Atlas cache: evitar recargar el mismo atlas ───────────────────────────
	var _currentAtlas : String = '';
	var _currentAnim  : String = '';

	// ── Efectos ───────────────────────────────────────────────────────────────
	var _ripples : Array<RippleEffect> = [];
	var _trail   : Array<TrailEffect>  = [];
	static inline final TRAIL_MAX      : Int   = 8;
	var _trailCooldown : Float = 0;

	var _updateConnected : Bool = false;

	public function new()
	{
		super();
		visible = false;

		_bmp = new Bitmap();
		addChild(_bmp);
	}

	// ── Insert ────────────────────────────────────────────────────────────────

	public function insert():Void
	{
		// Añadir directamente al stage de OpenFL en el índice más alto posible.
		// stage.addChild() lo pone encima de TODO (juego, UI, transiciones).
		var _stage = openfl.Lib.current.stage;
		if (_stage != null)
		{
			// Quitar primero si ya está en el display list (evitar duplicados)
			if (_stage.contains(this)) _stage.removeChild(this);
			_stage.addChild(this);
		}
		visible = true;

		if (!_updateConnected)
		{
			FlxG.signals.preUpdate.add(_tick);
			_updateConnected = true;
		}
	}

	// ── Cargar estado ─────────────────────────────────────────────────────────

	public function loadState(s:CursorState, cfg:CursorConfig):Void
	{
		var sd = _getStateData(s, cfg);
		// Si el estado no tiene config, intentar fallback a default
		if (sd == null) sd = _getStateData(DEFAULT, cfg);
		if (sd == null) return;

		_hotX = sd.hotspotX ?? 0;
		_hotY = sd.hotspotY ?? 0;
		_fps  = sd.fps  ?? 12;
		_loop = sd.loop ?? true;

		var atlasPath = sd.atlas ?? 'menu/cursor/cursor-default';
		var animName  = sd.anim  ?? 'idle';

		// Si es el mismo atlas y anim, solo reiniciar frame counter
		if (atlasPath == _currentAtlas && animName == _currentAnim)
		{
			_frameIdx  = 0;
			_elapsed   = 0;
			return;
		}

		_currentAtlas = atlasPath;
		_currentAnim  = animName;
		_frames       = [];
		_frameIdx     = 0;
		_elapsed      = 0;
		_frameTime    = (_fps > 0) ? (1.0 / _fps) : 0.1;

		// Intentar cargar atlas Sparrow → extraer frames del anim
		var extracted = false;
		try
		{
			var atlas = Paths.getSparrowAtlas(atlasPath);
			if (atlas != null)
			{
				// Filtrar frames cuyo nombre empieza con animName
				for (frame in atlas.frames)
				{
					if (frame.name.startsWith(animName))
					{
						// Extraer BitmapData del frame
						var src    = atlas.parent.bitmap;
						var region = frame.frame;
						var bd     = new BitmapData(
							Std.int(region.width),
							Std.int(region.height),
							true, 0x00000000
						);
						bd.copyPixels(
							src,
							new Rectangle(region.x, region.y, region.width, region.height),
							new Point(0, 0)
						);
						_frames.push(bd);
					}
				}
				extracted = _frames.length > 0;
			}
		}
		catch (_) {}

		// Fallback PNG
		if (!extracted)
		{
			try
			{
				var bd = openfl.Assets.getBitmapData(Paths.image(atlasPath));
				if (bd != null) { _frames.push(bd); extracted = true; }
			}
			catch (_) {}
		}

		// Último fallback: cuadrado magenta 16×16
		if (!extracted)
		{
			var bd = new BitmapData(16, 16, false, 0xFFFF00FF);
			_frames.push(bd);
			trace('[CursorManager] Atlas no encontrado: "$atlasPath"');
		}

		_updateBitmap();
	}

	// ── Tint / escala ─────────────────────────────────────────────────────────

	public function setScale(s:Float):Void
	{
		_scale = s;
		scaleX = scaleY = s;
	}

	public function setTint(col:FlxColor):Void
	{
		// Aplicar color a través de la transform de OflSprite
		// (ColorTransform multiplica cada canal)
		var r = col.redFloat;
		var g = col.greenFloat;
		var b = col.blueFloat;
		transform.colorTransform = new openfl.geom.ColorTransform(r, g, b, 1);
	}

	// ── Ripple ────────────────────────────────────────────────────────────────

	public function spawnRipple():Void
	{
		_ripples.push(new RippleEffect(this));
	}

	// ── Trail ─────────────────────────────────────────────────────────────────

	public function spawnTrail():Void
	{
		_trailCooldown -= FlxG.elapsed;
		if (_trailCooldown > 0 || _trail.length >= TRAIL_MAX) return;
		_trailCooldown = 0.03;
		// Trail particle: pequeño bitmap del frame actual en posición absoluta
		if (_bmp.bitmapData != null)
			_trail.push(new TrailEffect(_bmp.bitmapData, x, y));
	}

	// ── Tick ─────────────────────────────────────────────────────────────────

	function _tick():Void
	{
		// El container vive en el stage de OpenFL directamente, así que
		// necesita coordenadas NATIVAS del stage (no game-space de Flixel).
		var _s = openfl.Lib.current.stage;
		x = _s.mouseX - _hotX * _scale;
		y = _s.mouseY - _hotY * _scale;

		// Delegar lógica de estado al manager (puede cambiar visible)
		CursorManager._tick();

		if (!visible) return;

		var elapsed = FlxG.elapsed;

		// ── Coordenadas de stage ya asignadas arriba ─────────────────────────

		// ── Avanzar animación ────────────────────────────────────────────────
		if (_frames.length > 1)
		{
			_elapsed += elapsed;
			while (_elapsed >= _frameTime && _frameTime > 0)
			{
				_elapsed -= _frameTime;
				_frameIdx++;
				if (_frameIdx >= _frames.length)
				{
					_frameIdx = _loop ? 0 : _frames.length - 1;
				}
			}
			_updateBitmap();
		}

		// ── Ripples ───────────────────────────────────────────────────────────
		var i = _ripples.length;
		while (--i >= 0)
		{
			_ripples[i].update(elapsed, stage);
			if (_ripples[i].finished)
			{
				_ripples[i].destroy(stage);
				_ripples.splice(i, 1);
			}
		}

		// ── Trail ─────────────────────────────────────────────────────────────
		var j = _trail.length;
		while (--j >= 0)
		{
			_trail[j].update(elapsed);
			if (_trail[j].finished)
			{
				_trail[j].destroy();
				_trail.splice(j, 1);
			}
		}
	}

	function _updateBitmap():Void
	{
		if (_frames.length == 0) return;
		var idx = Std.int(Math.min(_frameIdx, _frames.length - 1));
		_bmp.bitmapData = _frames[idx];
	}

	static function _getStateData(s:CursorState, cfg:CursorConfig):Null<CursorStateData>
	{
		if (cfg == null || cfg.states == null) return null;
		return cast Reflect.field(cfg.states, (s : String));
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// RippleEffect — círculo OpenFL que se expande al hacer clic
// ─────────────────────────────────────────────────────────────────────────────

class RippleEffect
{
	public var finished : Bool = false;

	var _shape  : Shape;
	var _timer  : Float = 0;
	var _stage  : openfl.display.Stage;

	static inline final DURATION  : Float = 0.28;
	static inline final MAX_R     : Float = 24.0;

	public function new(parent:OflSprite)
	{
		_stage = openfl.Lib.current.stage;
		_shape = new Shape();
		_stage.addChild(_shape);
		_draw(FlxG.mouse.screenX, FlxG.mouse.screenY, 0);
	}

	public function update(elapsed:Float, stage:openfl.display.Stage):Void
	{
		_timer += elapsed;
		var t   = _timer / DURATION;
		_draw(stage.mouseX, stage.mouseY, t);
		if (_timer >= DURATION) finished = true;
	}

	function _draw(px:Float, py:Float, t:Float):Void
	{
		var r = FlxEase_cubeOut(t) * MAX_R;
		var a = (1.0 - t) * 0.6;
		_shape.graphics.clear();
		_shape.graphics.lineStyle(1.5, 0xFFFFFF, a);
		_shape.graphics.drawCircle(px, py, r);
	}

	public function destroy(stage:openfl.display.Stage):Void
	{
		_shape.graphics.clear();
		if (stage.contains(_shape)) stage.removeChild(_shape);
	}

	// Inline cubeOut para no depender de FlxEase
	static inline function FlxEase_cubeOut(t:Float):Float
	{
		return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// TrailEffect — partícula de estela del cursor
// ─────────────────────────────────────────────────────────────────────────────

class TrailEffect
{
	public var finished : Bool = false;

	var _bmp   : Bitmap;
	var _timer : Float = 0;
	var _ox    : Float;
	var _oy    : Float;

	static inline final DURATION : Float = 0.16;

	public function new(frameBd:BitmapData, px:Float, py:Float)
	{
		_ox = px; _oy = py;
		_bmp = new Bitmap(frameBd);
		_bmp.x = px; _bmp.y = py;
		_bmp.alpha = 0.35;
		openfl.Lib.current.stage.addChild(_bmp);
	}

	public function update(elapsed:Float):Void
	{
		_timer += elapsed;
		var t = _timer / DURATION;
		_bmp.alpha  = (1.0 - t) * 0.35;
		_bmp.scaleX = _bmp.scaleY = 1.0 - t * 0.6;
		if (_timer >= DURATION) finished = true;
	}

	public function destroy():Void
	{
		var s = openfl.Lib.current.stage;
		if (s.contains(_bmp)) s.removeChild(_bmp);
		_bmp.bitmapData = null;
	}
}
