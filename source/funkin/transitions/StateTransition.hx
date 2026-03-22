package funkin.transitions;

import flixel.FlxG;
import flixel.FlxState;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.geom.Matrix;

using StringTools;

/**
	* StateTransition — Smooth, scriptable transitions between FlxStates.
	*
	* ─── Features ─────────────────────────────────────────────────────────
	* • Does not interfere with StickerTransition (uses a separate OpenFL layer, lower z-slot).

	* • Configurable via a switch or globally from HScript scripts.

	* • Types: FADE, FADE_WHITE, SLIDE_LEFT, SLIDE_RIGHT, SLIDE_UP, SLIDE_DOWN,

	* CIRCLE_WIPE, NONE, CUSTOM.

	* Fluent API: switchState() + setNext() + setGlobal().

	* The "intro" (discovery) is automatically triggered in MusicBeatState.create().
	* 
	* ─── Use in HScript ──────────────────────────── ───────────────────────────── 
	* StateTransition.setNext("slide_left", 0.4); // next switch 
	* StateTransition.switchState(new MainMenuState()); // switch + transition

	*
	* StateTransition.setGlobal("fade", 0.35, 0xFF000000); // all transitions

	* StateTransition.setCustomIn(function() { ... }); // custom entrance animation

	* StateTransition.setCustomOut(function(done) { done(); }); // custom exit
*/

class StateTransition
{
	// ─── Config global ────────────────────────────────────────────────────────
	public static var globalType:TransitionType = FADE;
	public static var globalDuration:Float = 0.35;
	public static var globalColor:Int = 0xFF000000;
	public static var globalEaseIn:EaseFunction = null; // null = cubeInOut
	public static var globalEaseOut:EaseFunction = null;

	/** If false, no is hace none transition (useful for debug). */
	public static var enabled:Bool = true;

	// ─── Override for the next switch (is consume a vez) ─────────────────
	private static var _nextType:Null<TransitionType> = null;
	private static var _nextDuration:Null<Float> = null;
	private static var _nextColor:Null<Int> = null;
	private static var _nextEaseIn:Null<EaseFunction> = null;
	private static var _nextEaseOut:Null<EaseFunction> = null;

	// ─── Custom callbacks (scripts) ───────────────────────────────────────────

	/** Function of output custom: receives callback `done` that debe callrse to the terminar. */
	public static var customOut:Null<(Void->Void)->Void> = null;

	/** Function of entry custom: is call when the new state already is creado. */
	public static var customIn:Null<Void->Void> = null;

	// ─── Estado interno ───────────────────────────────────────────────────────
	private static var _overlay:TransitionOverlay = null;
	private static var _pendingIntro:Bool = false;
	private static var _pendingType:TransitionType = FADE;
	private static var _pendingDuration:Float = 0.35;
	private static var _pendingColor:Int = 0xFF000000;
	private static var _pendingEaseIn:EaseFunction = null;
	private static var _pendingEaseOut:EaseFunction = null;

	private static var _active:Bool = false;

	// ═════════════════════════════════════════════════════════════════════════
	//  API public
	// ═════════════════════════════════════════════════════════════════════════

	/**
	 * Configures the transition for the next switchState solamente.
	 * Se descarta tras usarse (no afecta transiciones posteriores).
	 *
	 * @param type     Type of transition (String or TransitionType)
	 * @param duration Duration total in segundos
	 * @param color    Color del overlay (ARGB)
	 */
	public static function setNext(?type:Dynamic, ?duration:Float, ?color:Int, ?easeIn:EaseFunction, ?easeOut:EaseFunction):Void
	{
		_nextType = type != null ? parseType(type) : null;
		_nextDuration = duration != null ? duration : null;
		_nextColor = color != null ? color : null;
		_nextEaseIn = easeIn;
		_nextEaseOut = easeOut;
	}

	/**
	 * Changes the configuration global (afecta all the switches siguientes).
	 */
	public static function setGlobal(?type:Dynamic, ?duration:Float, ?color:Int, ?easeIn:EaseFunction, ?easeOut:EaseFunction):Void
	{
		if (type != null)
			globalType = parseType(type);
		if (duration != null)
			globalDuration = duration;
		if (color != null)
			globalColor = color;
		if (easeIn != null)
			globalEaseIn = easeIn;
		if (easeOut != null)
			globalEaseOut = easeOut;
	}

	/**
	 * Registra a function of output custom for the next switch.
	 * The function receives a callback `done:Void->Void` that DEBE callrse
	 * when the animation of output termina.
	 *
	 * Ejemplo HScript:
	 *   StateTransition.setCustomOut(function(done) {
	 *     FlxTween.tween(mySprite, {alpha: 0}, 0.4, {onComplete: function(_) done()});
	 *   });
	 */
	public static function setCustomOut(fn:(Void->Void)->Void):Void
	{
		customOut = fn;
		_nextType = CUSTOM;
	}

	/** Registra a function of entry custom (is call in the new state). */
	public static function setCustomIn(fn:Void->Void):Void
	{
		customIn = fn;
	}

	/**
	 * Hace a switchState with transition suave.
	 * Compatible with StickerTransition: if the stickers are activos,
	 * simplemente hace el switch sin overlay para no pelear con ellos.
	 */
	public static function switchState(target:FlxState, ?type:Dynamic, ?duration:Float, ?color:Int):Void
	{
		if (type != null || duration != null || color != null)
			setNext(type, duration, color);

		// If StickerTransition is corriendo, no meter a overlay above.
		if (StickerTransition.isActive())
		{
			_consumeNext(); // descartar override sin usar
			FlxG.switchState(target);
			return;
		}

		if (!enabled)
		{
			_consumeNext();
			FlxG.switchState(target);
			return;
		}

		_performSwitch(target);
	}

	/**
	 * Calldo automatically by MusicBeatState.create() for play
	 * the animation of entry ("intro") in the new state.
	 * No llamar manualmente salvo en estados custom que no extiendan MusicBeatState.
	 */
	public static function onStateCreated():Void
	{
		if (!_pendingIntro)
			return;

		_pendingIntro = false;

		if (_overlay == null || !_overlay.visible)
			return;

		var easeIn = _pendingEaseIn ?? globalEaseIn ?? FlxEase.cubeInOut;
		var halfDur = _pendingDuration * 0.5;

		if (_pendingType == CUSTOM && customIn != null)
		{
			// Esconder overlay primero, luego correr custom
			_overlay.hideInstant();
			_overlay.detach();
			customIn();
			customIn = null;
			return;
		}

		// Animar salida del overlay (revelar nuevo state)
		_overlay.animateOut(_pendingType, halfDur, easeIn, function()
		{
			_overlay.detach();
			_active = false;
		});
	}

	/** Returns true if there is a transition in curso. */
	public static inline function isActive():Bool
		return _active;

	/** Resetea todos los overrides y callbacks custom. */
	public static function reset():Void
	{
		_consumeNext();
		customOut = null;
		customIn = null;
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  INTERNOS
	// ═════════════════════════════════════════════════════════════════════════

	static function _performSwitch(target:FlxState):Void
	{
		// Resolve parameters (override of next switch > global)
		var type = _nextType ?? globalType;
		var duration = _nextDuration ?? globalDuration;
		var color = _nextColor ?? globalColor;
		var easeOut = _nextEaseOut ?? globalEaseOut ?? FlxEase.cubeInOut;
		var easeIn = _nextEaseIn ?? globalEaseIn ?? FlxEase.cubeInOut;
		_consumeNext();

		// Save parameters for the intro of the new state
		_pendingType = type;
		_pendingDuration = duration;
		_pendingColor = color;
		_pendingEaseIn = easeIn;
		_pendingEaseOut = easeOut;
		_pendingIntro = true;
		_active = true;

		if (type == NONE)
		{
			_pendingIntro = false;
			_active = false;
			FlxG.switchState(target);
			return;
		}

		// Crear overlay si no existe
		_ensureOverlay();

		var halfDur = duration * 0.5;

		if (type == CUSTOM && customOut != null)
		{
			customOut(function()
			{
				FlxG.switchState(target);
				customOut = null;
			});
			return;
		}

		// Animation of "output" (cubrir screen)
		_overlay.setup(type, color);
		_overlay.attach();
		_overlay.animateOut_reverse(type, halfDur, easeOut, function()
		{
			// Pantalla cubierta — cambiar state
			FlxG.switchState(target);
			// El intro se dispara en MusicBeatState.create()
		});
	}

	static function _ensureOverlay():Void
	{
		if (_overlay == null)
			_overlay = new TransitionOverlay();
	}

	static function _consumeNext():Void
	{
		_nextType = null;
		_nextDuration = null;
		_nextColor = null;
		_nextEaseIn = null;
		_nextEaseOut = null;
	}

	/** Parsea un tipo desde String o TransitionType. */
	static function parseType(v:Dynamic):TransitionType
	{
		if (Std.isOfType(v, String))
		{
			return switch (Std.string(v).toLowerCase().replace('-', '_'))
			{
				case 'fade': FADE;
				case 'fade_white': FADE_WHITE;
				case 'slide_left': SLIDE_LEFT;
				case 'slide_right': SLIDE_RIGHT;
				case 'slide_up': SLIDE_UP;
				case 'slide_down': SLIDE_DOWN;
				case 'circle_wipe': CIRCLE_WIPE;
				case 'none': NONE;
				case 'custom': CUSTOM;
				default: FADE;
			};
		}
		return cast v;
	}
}

// ═════════════════════════════════════════════════════════════════════════════
//  TransitionOverlay — capa OpenFL que dibuja el efecto
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Sprite OpenFL that draws the overlay of transition.
 * Z-order: debajo of StickerTransition (that use 9999), here usamos 9998.
 */
class TransitionOverlay extends Sprite
{
	private var _shape:Shape;
	private var _activeTween:FlxTween = null;

	private var _color:Int;
	private var _type:TransitionType;
	private var _currentProgress:Float = 1.0; // progreso current of the animation (0-1)

	public function new()
	{
		super();
		_shape = new Shape();
		addChild(_shape);
		visible = false;
	}

	// ── Setup ─────────────────────────────────────────────────────────────────

	public function setup(type:TransitionType, color:Int):Void
	{
		_type = type;
		_color = color;
		_currentProgress = 0.0;
		_redraw(type, 0.0);
		alpha = 0;
		visible = true;
	}

	/** Inserta en OpenFL debajo de stickers. */
	public function attach():Void
	{
		// Usar 9998 para estar debajo de StickerTransition (9999)
		FlxG.addChildBelowMouse(this, 9998);
		_resize();
		// FIX: escuchar cambios of size of window for that the overlay
		// always cubra all the screen aunque is redimensione durante the transition.
		FlxG.stage.addEventListener(openfl.events.Event.RESIZE, _onStageResize);
	}

	public function detach():Void
	{
		if (_activeTween != null)
		{
			_activeTween.cancel();
			_activeTween = null;
		}
		FlxG.stage.removeEventListener(openfl.events.Event.RESIZE, _onStageResize);
		FlxG.removeChild(this);
		visible = false;
		alpha = 0;
	}

	public function hideInstant():Void
	{
		alpha = 0;
		visible = false;
	}

	// ── Animaciones ───────────────────────────────────────────────────────────

	/**
	 * Anima cubriendo la pantalla (para la SALIDA del state actual).
	 * Al terminar llama `onDone`.
	 */
	public function animateOut_reverse(type:TransitionType, duration:Float, ease:EaseFunction, onDone:Void->Void):Void
	{
		_cancelTween();

		switch (type)
		{
			case FADE, FADE_WHITE:
				alpha = 0;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null; // BUGFIX: limpiar antes de que el tween vuelva al pool
						alpha = 1;
						onDone();
					}
				}, function(v:Float)
				{
					alpha = v;
				});

			case SLIDE_LEFT:
				x = -_gw();
				alpha = 1;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						x = 0;
						onDone();
					}
				}, function(v:Float)
				{
					_currentProgress = v;
					x = -_gw() * (1.0 - v);
				});

			case SLIDE_RIGHT:
				x = _gw();
				alpha = 1;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						x = 0;
						onDone();
					}
				}, function(v:Float)
				{
					_currentProgress = v;
					x = _gw() * (1.0 - v);
				});

			case SLIDE_UP:
				y = -_gh();
				alpha = 1;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						y = 0;
						onDone();
					}
				}, function(v:Float)
				{
					_currentProgress = v;
					y = -_gh() * (1.0 - v);
				});

			case SLIDE_DOWN:
				y = _gh();
				alpha = 1;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						y = 0;
						onDone();
					}
				}, function(v:Float)
				{
					_currentProgress = v;
					y = _gh() * (1.0 - v);
				});

			case CIRCLE_WIPE:
				alpha = 1;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						_redraw(CIRCLE_WIPE, 1);
						onDone();
					}
				}, function(v:Float)
				{
					_redraw(CIRCLE_WIPE, v);
				});

			default:
				// NONE / CUSTOM — no animar
				alpha = 1;
				onDone();
		}
	}

	/**
	 * Anima descubriendo la pantalla (para la ENTRADA del nuevo state).
	 */
	public function animateOut(type:TransitionType, duration:Float, ease:EaseFunction, onDone:Void->Void):Void
	{
		_cancelTween();

		switch (type)
		{
			case FADE, FADE_WHITE:
				alpha = 1;
				_activeTween = FlxTween.num(1, 0, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						onDone();
					}
				}, function(v:Float)
				{
					alpha = v;
				});

			case SLIDE_LEFT:
				x = 0;
				alpha = 1;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						onDone();
					}
				}, function(v:Float)
				{
					_currentProgress = 1.0 - v;
					x = _gw() * v;
				});

			case SLIDE_RIGHT:
				x = 0;
				alpha = 1;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						onDone();
					}
				}, function(v:Float)
				{
					_currentProgress = 1.0 - v;
					x = -_gw() * v;
				});

			case SLIDE_UP:
				y = 0;
				alpha = 1;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						onDone();
					}
				}, function(v:Float)
				{
					_currentProgress = 1.0 - v;
					y = _gh() * v;
				});

			case SLIDE_DOWN:
				y = 0;
				alpha = 1;
				_activeTween = FlxTween.num(0, 1, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						onDone();
					}
				}, function(v:Float)
				{
					_currentProgress = 1.0 - v;
					y = -_gh() * v;
				});

			case CIRCLE_WIPE:
				_activeTween = FlxTween.num(1, 0, duration, {
					ease: ease,
					onComplete: function(_)
					{
						_activeTween = null;
						_redraw(CIRCLE_WIPE, 0);
						onDone();
					}
				}, function(v:Float)
				{
					_redraw(CIRCLE_WIPE, v);
				});

			default:
				onDone();
		}
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	private function _cancelTween():Void
	{
		if (_activeTween != null)
		{
			_activeTween.cancel();
			_activeTween = null;
		}
	}

	/** Width actual of the stage OpenFL (no the resolution logic of Flixel). */
	private inline function _gw():Float
		return FlxG.stage.stageWidth > 0 ? FlxG.stage.stageWidth : FlxG.width;

	/** Alto real del stage OpenFL. */
	private inline function _gh():Float
		return FlxG.stage.stageHeight > 0 ? FlxG.stage.stageHeight : FlxG.height;

	/** Calldo to the redimensionar the window — updates shape and position for slides. */
	private function _onStageResize(_:openfl.events.Event):Void
	{
		_resize();
	}

	private function _resize():Void
	{
		_shape.x = 0;
		_shape.y = 0;

		// Redibujar the shape to the new size with the progreso current
		_redraw(_type, _currentProgress);

		// For slides, the position X/and of the overlay depende of the size of window.
		// If there is a tween active, reposicionar according to the progreso current.
		// _currentProgress va de 0 (oculto) a 1 (cubriendo pantalla).
		switch (_type)
		{
			case SLIDE_LEFT:
				// animateOut_reverse: x va de -gw→0; animateOut: x va de 0→gw
				// We can't know what phase we're in here, but the tween
				// actualiza x en su callback. Solo nos aseguramos de que la
				// shape is redibuja to the size correct (already hecho arriba).
			case SLIDE_RIGHT:
				// ídem
			case SLIDE_UP:
				// ídem
			case SLIDE_DOWN:
				// ídem
			default:
				// FADE and CIRCLE_WIPE no tienen position — nada more that do
		}
	}

	/**
	 * Redibujar the Shape according to the type and progreso (0=empty, 1=full).
	 */
	private function _redraw(type:TransitionType, progress:Float):Void
	{
		_currentProgress = progress; // FIX: guardar progreso para redibujado en resize
		var gfx = _shape.graphics;
		gfx.clear();

		gfx.beginFill(_color & 0x00FFFFFF, 1);

		switch (type)
		{
			case CIRCLE_WIPE:
				var cx = _gw() * 0.5;
				var cy = _gh() * 0.5;
				var maxR = Math.sqrt(cx * cx + cy * cy) + 10;
				gfx.drawCircle(cx, cy, maxR * progress);
			default:
				gfx.drawRect(0, 0, _gw() + 2, _gh() + 2);
		}

		gfx.endFill();
	}
}

// ═════════════════════════════════════════════════════════════════════════════
//  Tipos
// ═════════════════════════════════════════════════════════════════════════════

enum TransitionType
{
	FADE;
	FADE_WHITE;
	SLIDE_LEFT;
	SLIDE_RIGHT;
	SLIDE_UP;
	SLIDE_DOWN;
	CIRCLE_WIPE;
	NONE;
	CUSTOM;
}

typedef EaseFunction = Float->Float;
