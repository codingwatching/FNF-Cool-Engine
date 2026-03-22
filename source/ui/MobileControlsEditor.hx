package ui;

#if mobileC
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import flixel.math.FlxPoint;

/**
 * MobileControlsEditor — Editor drag-and-drop para el layout personalizado del VirtualPad.
 *
 * Load the layout saved in FlxG.save.data.mobilePadLayout (Array of {x,and} by button).
 * The jugador puede arrastrar each button to cualquier position of the screen.
 * To the salir with the button Save, save the positions. Discard descarta the cambios.
 *
 * Orden de los botones: LEFT, DOWN, UP, RIGHT (mismo que FlxVirtualPad en modo FULL).
 */
class MobileControlsEditor extends FlxSubState
{
	// ── Buttons of the pad (the 4 of direction) ─────────────────────────────
	private var _buttons:Array<DragButton> = [];
	private static final BUTTON_LABELS:Array<String>  = ["L", "D", "U", "R"];
	private static final BUTTON_COLORS:Array<FlxColor> = [
		FlxColor.fromRGB(195, 52, 154),  // left  — magenta
		FlxColor.fromRGB(0,   255, 255), // down  — cyan
		FlxColor.fromRGB(18,  251, 6),   // up    — green
		FlxColor.fromRGB(249, 57,  63)   // right — red
	];

	// Default positions (centro of the button) if no there is layout saved
	// Columna derecha a la altura media-baja de la pantalla, igual que VirtualPad FULL
	private static final DEFAULT_X:Array<Float> = [
		FlxG.width - 390,  // LEFT
		FlxG.width - 220,  // DOWN
		FlxG.width - 300,  // UP
		FlxG.width - 130   // RIGHT
	];
	private static final DEFAULT_Y:Array<Float> = [
		FlxG.height - 180, // LEFT
		FlxG.height - 150, // DOWN
		FlxG.height - 280, // UP
		FlxG.height - 150  // RIGHT
	];

	// ── Drag state ────────────────────────────────────────────────────────
	private var _dragging:DragButton = null;
	private var _dragOffX:Float = 0;
	private var _dragOffY:Float = 0;

	// ── UI ────────────────────────────────────────────────────────────────
	private var _saveBtn:FlxSprite;
	private var _discardBtn:FlxSprite;
	private var _saveTxt:FlxText;
	private var _discardTxt:FlxText;
	private var _helpTxt:FlxText;
	private var _titleTxt:FlxText;

	/** true si hay cambios sin guardar */
	private var _dirty:Bool = false;

	// ── Currently "highlighted" pad button (touch feedback) ──────────
	private var _prevHighlight:Int = -1;

	override function create():Void
	{
		super.create();

		// Fondo semitransparente
		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.6;
		bg.scrollFactor.set();
		add(bg);

		// Title
		_titleTxt = new FlxText(0, 10, FlxG.width, "CUSTOM PAD LAYOUT", 32);
		_titleTxt.setFormat("assets/fonts/Funkin.otf", 32, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		_titleTxt.borderSize = 2;
		_titleTxt.scrollFactor.set();
		add(_titleTxt);

		// Texto de ayuda
		_helpTxt = new FlxText(0, FlxG.height - 50, FlxG.width,
			"Drag buttons • SAVE = confirm • DISCARD = cancel", 20);
		_helpTxt.setFormat("assets/fonts/Funkin.otf", 20, FlxColor.GRAY, CENTER, NONE);
		_helpTxt.scrollFactor.set();
		add(_helpTxt);

		// Cargar posiciones guardadas (o usar defaults)
		var savedLayout:Array<Dynamic> = FlxG.save.data.mobilePadLayout;

		for (i in 0...4)
		{
			var bx:Float = DEFAULT_X[i];
			var by:Float = DEFAULT_Y[i];

			if (savedLayout != null && i < savedLayout.length && savedLayout[i] != null)
			{
				bx = savedLayout[i].x;
				by = savedLayout[i].y;
			}

			var btn = new DragButton(bx, by, BUTTON_LABELS[i], BUTTON_COLORS[i]);
			btn.ID = i;
			btn.scrollFactor.set();
			_buttons.push(btn);
			add(btn);
		}

		// ── Botones Save / Discard ──────────────────────────────────────────
		_saveBtn = new FlxSprite(FlxG.width - 220, 10).makeGraphic(100, 50, FlxColor.fromRGB(30, 160, 30));
		_saveBtn.scrollFactor.set();
		add(_saveBtn);

		_saveTxt = new FlxText(_saveBtn.x, _saveBtn.y + 12, 100, "SAVE", 22);
		_saveTxt.setFormat("assets/fonts/Funkin.otf", 22, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		_saveTxt.borderSize = 2;
		_saveTxt.scrollFactor.set();
		add(_saveTxt);

		_discardBtn = new FlxSprite(FlxG.width - 110, 10).makeGraphic(100, 50, FlxColor.fromRGB(160, 30, 30));
		_discardBtn.scrollFactor.set();
		add(_discardBtn);

		_discardTxt = new FlxText(_discardBtn.x, _discardBtn.y + 12, 100, "DISCARD", 22);
		_discardTxt.setFormat("assets/fonts/Funkin.otf", 22, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		_discardTxt.borderSize = 2;
		_discardTxt.scrollFactor.set();
		add(_discardTxt);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		_handleTouch();
		_handleKeyboard();
	}

	// ── Touch input handling ────────────────────────────────────────────

	private function _handleTouch():Void
	{
		#if FLX_TOUCH
		var touches = FlxG.touches.list;

		if (touches.length == 0)
		{
			// Without dedos: soltar the button that is arrastraba
			if (_dragging != null)
			{
				_dragging.isHeld = false;
				_dragging = null;
			}
			return;
		}

		// Usar el primer dedo activo
		var touch = touches[0];

		if (touch.justPressed)
		{
			// Revisar si toca Save/Discard
			if (_touchOverlaps(_saveBtn, touch.screenX, touch.screenY))
			{
				_saveLayout();
				return;
			}
			if (_touchOverlaps(_discardBtn, touch.screenX, touch.screenY))
			{
				_discard();
				return;
			}

			// Revisar buttons of the pad (of back towards adelante for priorizar the of above)
			var i = _buttons.length - 1;
			while (i >= 0)
			{
				var btn = _buttons[i];
				if (_touchOverlaps(btn, touch.screenX, touch.screenY))
				{
					_dragging  = btn;
					_dragOffX  = touch.screenX - btn.x;
					_dragOffY  = touch.screenY - btn.y;
					btn.isHeld = true;
					// Llevar al frente (re-add al final del grupo)
					remove(btn, true);
					add(btn);
					_dirty = true;
					break;
				}
				i--;
			}
		}
		else if (touch.pressed && _dragging != null)
		{
			// Arrastrar — clampear to the area visible
			var newX = touch.screenX - _dragOffX;
			var newY = touch.screenY - _dragOffY;
			newX = Math.max(0, Math.min(FlxG.width  - _dragging.width,  newX));
			newY = Math.max(60, Math.min(FlxG.height - _dragging.height - 60, newY));
			_dragging.x = newX;
			_dragging.y = newY;
		}
		else if (touch.justReleased && _dragging != null)
		{
			_dragging.isHeld = false;
			_dragging = null;
		}
		#else
		// Fallback: mouse (useful for debug in desktop with -Dmobile)
		var mx = FlxG.mouse.screenX;
		var my = FlxG.mouse.screenY;

		if (FlxG.mouse.justPressed)
		{
			if (_touchOverlaps(_saveBtn, mx, my))    { _saveLayout(); return; }
			if (_touchOverlaps(_discardBtn, mx, my)) { _discard();    return; }

			var i = _buttons.length - 1;
			while (i >= 0)
			{
				var btn = _buttons[i];
				if (_touchOverlaps(btn, mx, my))
				{
					_dragging = btn;
					_dragOffX = mx - btn.x;
					_dragOffY = my - btn.y;
					btn.isHeld = true;
					remove(btn, true);
					add(btn);
					_dirty = true;
					break;
				}
				i--;
			}
		}
		else if (FlxG.mouse.pressed && _dragging != null)
		{
			var newX = mx - _dragOffX;
			var newY = my - _dragOffY;
			newX = Math.max(0, Math.min(FlxG.width  - _dragging.width,  newX));
			newY = Math.max(60, Math.min(FlxG.height - _dragging.height - 60, newY));
			_dragging.x = newX;
			_dragging.y = newY;
		}
		else if (FlxG.mouse.justReleased && _dragging != null)
		{
			_dragging.isHeld = false;
			_dragging = null;
		}
		#end
	}

	// ── Teclado (ESC = discard, ENTER = save) ────────────────────────────

	private function _handleKeyboard():Void
	{
		if (FlxG.keys.justPressed.ESCAPE)
			_discard();
		if (FlxG.keys.justPressed.ENTER)
			_saveLayout();
	}

	// ── Helpers ──────────────────────────────────────────────────────────

	private inline function _touchOverlaps(spr:FlxSprite, tx:Float, ty:Float):Bool
		return tx >= spr.x && tx <= spr.x + spr.width
			&& ty >= spr.y && ty <= spr.y + spr.height;

	private function _saveLayout():Void
	{
		// Guardar las posiciones en el FlxSave global
		var layout:Array<{x:Float, y:Float}> = [];
		for (btn in _buttons)
			layout.push({x: btn.x, y: btn.y});

		FlxG.save.data.mobilePadLayout = layout;
		FlxG.save.flush();

		// Also save in Config for that Mobilecontrols.hx it use
		var cfg = new data.Config();
		cfg.setcontrolmode(3); // Asegurar que el modo quede en VIRTUALPAD_CUSTOM

		FlxTween.tween(_titleTxt, {alpha: 0}, 0.15, {
			onComplete: function(_) {
				_titleTxt.text = "Saved!";
				_titleTxt.color = FlxColor.LIME;
				FlxTween.tween(_titleTxt, {alpha: 1}, 0.15, {
					onComplete: function(_) {
						new flixel.util.FlxTimer().start(0.5, function(_) close());
					}
				});
			}
		});
	}

	private function _discard():Void
	{
		close();
	}
}

/**
 * DragButton — button circular arrastrable with label of text central.
 * Changes of color when is siendo arrastrado.
 */
class DragButton extends FlxSpriteGroup
{
	public var isHeld(default, set):Bool = false;

	private var _bg:FlxSprite;
	private var _label:FlxText;
	private var _color:FlxColor;

	private static inline final SIZE:Int = 90;
	private static inline final HELD_SCALE:Float = 1.18;

	public function new(x:Float, y:Float, label:String, color:FlxColor)
	{
		super(x, y);

		_color = color;

		_bg = new FlxSprite(0, 0).makeGraphic(SIZE, SIZE, color);
		_bg.alpha = 0.82;
		add(_bg);

		_label = new FlxText(0, SIZE / 2 - 14, SIZE, label, 28);
		_label.setFormat("assets/fonts/Funkin.otf", 28, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		_label.borderSize = 2;
		add(_label);

		scrollFactor.set();
	}

	// Feedback visual al arrastrar
	@:noCompletion
	function set_isHeld(v:Bool):Bool
	{
		isHeld = v;
		if (v)
		{
			FlxTween.cancelTweensOf(scale);
			FlxTween.tween(scale, {x: HELD_SCALE, y: HELD_SCALE}, 0.08, {ease: FlxEase.quadOut});
			_bg.color = FlxColor.WHITE;
			_bg.alpha = 1.0;
		}
		else
		{
			FlxTween.cancelTweensOf(scale);
			FlxTween.tween(scale, {x: 1.0, y: 1.0}, 0.12, {ease: FlxEase.quadOut});
			_bg.color = _color;
			_bg.alpha = 0.82;
		}
		return v;
	}
}
#end
