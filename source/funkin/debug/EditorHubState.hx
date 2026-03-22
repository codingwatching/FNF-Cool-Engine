package funkin.debug;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.transitions.StateTransition;
import funkin.states.MusicBeatState;

/**
 * EditorHubState — Menú central de editores del engine.
 *
 * Acceso desde MainMenuState pulsando [3] en Developer Mode.
 *
 * Editores disponibles:
 *   • Animation Debug  — editor de personajes y offsets de animación
 *   • Story Menu       — editor visual de semanas del Story Mode
 *   • Menu Editor      — editor de menús personalizados
 *   • Stage Editor     — editor de stages
 *   • Chart Editor     — editor de notas / charting
 *   • Dialogue Editor  — editor de diálogos/cutscenes
 */
class EditorHubState extends MusicBeatState
{
	// ── Paleta ───────────────────────────────────────────────────────────────
	static inline var C_BG:Int = 0xFF080810;
	static inline var C_PANEL:Int = 0xFF0F0F1E;
	static inline var C_CARD:Int = 0xFF141426;
	static inline var C_CARD_HOV:Int = 0xFF1C1C38;
	static inline var C_ACCENT:Int = 0xFF00D9FF;
	static inline var C_ACCENT2:Int = 0xFFFF3399;
	static inline var C_TEXT:Int = 0xFFE0E0FF;
	static inline var C_SUBTEXT:Int = 0xFF8888AA;
	static inline var C_WHITE:Int = 0xFFFFFFFF;

	// Accentos por editor (para el borde de color de cada card)
	static var EDITOR_ACCENTS:Array<Int> = [
		0xFF00D9FF, // Anim Debug    — cyan
		0xFFFF3399, // Story Menu    — rosa
		0xFFFFCC00, // Menu Editor   — amarillo
		0xFF44FF88, // Stage Editor  — verde
		0xFFFF6644, // Chart Editor  — naranja
		0xFF9966FF, // Dialogue      — morado
	];

	static var EDITOR_ICONS:Array<String> = ["✦", "☰", "⊞", "⬡", "♩", "✎"];

	static var EDITOR_NAMES:Array<String> = ["Character Editor", "Story Menu Editor", "Menu Editor"];

	static var EDITOR_DESCS:Array<String> = [
		"Edit characters, animations, and offsets",
		"Create and edit\nStory Mode weeks with visual preview",
		"Design custom menus\nwith objects and scripts"
	];

	// ── Estado interno ───────────────────────────────────────────────────────
	var _cards:Array<EditorCard> = [];
	var _curSel:Int = 0;
	var _title:FlxText;
	var _hint:FlxText;
	var _scanline:FlxSprite;
	var _glow:FlxSprite;

	override public function create():Void
	{
		super.create();

		// ── Fondo
		var bg = new FlxSprite(0, 0);
		bg.makeGraphic(FlxG.width, FlxG.height, C_BG);
		bg.scrollFactor.set();
		add(bg);

		// Líneas de cuadrícula decorativas
		_buildGrid();

		// Glow central
		_glow = new FlxSprite(0, 0);
		_glow.makeGraphic(800, 800, FlxColor.TRANSPARENT);
		// Efecto radial manual con círculos concéntricos
		for (r in [400, 300, 200, 100])
		{
			var c:FlxColor = FlxColor.fromInt(C_ACCENT);
			c.alphaFloat = 0.008 * (400 - r) / 100;
			var dot = new FlxSprite(FlxG.width * 0.5 - r, FlxG.height * 0.5 - r);
			dot.makeGraphic(r * 2, r * 2, c);
			dot.scrollFactor.set();
			add(dot);
		}

		// ── Título
		_title = new FlxText(0, 28, FlxG.width, "EDITOR HUB", 32);
		_title.alignment = CENTER;
		_title.color = C_ACCENT;
		_title.font = Paths.font("vcr.ttf");
		_title.scrollFactor.set();
		add(_title);

		var sub = new FlxText(0, _title.y + _title.height + 4, FlxG.width, "Select a editor  •  [ENTER] Open  •  [ESC] Back", 11);
		sub.alignment = CENTER;
		sub.color = C_SUBTEXT;
		sub.font = Paths.font("vcr.ttf");
		sub.scrollFactor.set();
		add(sub);

		// Línea accent bajo el título
		var line = new FlxSprite(0, sub.y + sub.height + 10);
		line.makeGraphic(FlxG.width, 1, C_ACCENT);
		line.alpha = 0.18;
		line.scrollFactor.set();
		add(line);

		// ── Cards de editores (2 columnas × 3 filas)
		_buildCards();

		// ── Hints de navegación
		_hint = new FlxText(0, FlxG.height - 28, FlxG.width, "UP/DOWN/LEFT/RIGHT Browse   ENTER Open   ESC Main Menu", 11);
		_hint.alignment = CENTER;
		_hint.color = C_SUBTEXT;
		_hint.font = Paths.font("vcr.ttf");
		_hint.scrollFactor.set();
		add(_hint);

		// Scanline overlay sutil
		_scanline = new FlxSprite(0, 0);
		_scanline.makeGraphic(FlxG.width, FlxG.height, FlxColor.TRANSPARENT);
		for (y in 0...Std.int(FlxG.height / 4))
		{
			var sl = new FlxSprite(0, y * 4);
			sl.makeGraphic(FlxG.width, 1, 0x04FFFFFF);
			sl.scrollFactor.set();
			add(sl);
		}

		// Entrada inicial
		_updateSelection(0, true);

		// Fade-in
		FlxG.camera.fade(FlxColor.BLACK, 0.25, true);
	}

	// ── Construcción de grid decorativo ──────────────────────────────────────

	function _buildGrid():Void
	{
		var cols = 20;
		var rows = 12;
		var cw = FlxG.width / cols;
		var rh = FlxG.height / rows;
		for (c in 0...cols)
		{
			var vline = new FlxSprite(Std.int(c * cw), 0);
			vline.makeGraphic(1, FlxG.height, 0x06FFFFFF);
			vline.scrollFactor.set();
			add(vline);
		}
		for (r in 0...rows)
		{
			var hline = new FlxSprite(0, Std.int(r * rh));
			hline.makeGraphic(FlxG.width, 1, 0x06FFFFFF);
			hline.scrollFactor.set();
			add(hline);
		}
	}

	// ── Construcción de cards ─────────────────────────────────────────────────

	function _buildCards():Void
	{
		var cols = 3;
		var cardW = 300;
		var cardH = 140;
		var gapX = 30;
		var gapY = 22;
		var totalW = cols * cardW + (cols - 1) * gapX;
		var startX = Std.int((FlxG.width - totalW) / 2);
		var startY = 120;

		for (i in 0...EDITOR_NAMES.length)
		{
			var col = i % cols;
			var row = Std.int(i / cols);
			var cx = startX + col * (cardW + gapX);
			var cy = startY + row * (cardH + gapY);

			var card = new EditorCard(cx, cy, cardW, cardH, EDITOR_NAMES[i], EDITOR_DESCS[i], EDITOR_ICONS[i], EDITOR_ACCENTS[i]);
			card.scrollFactor.set();
			add(card);
			_cards.push(card);

			// Stagger de entrada
			card.alpha = 0;
			var delay = i * 0.05;
			FlxTween.tween(card, {alpha: 1.0, y: cy}, 0.35, {
				startDelay: delay,
				ease: FlxEase.quartOut,
				onStart: function(_)
				{
					card.y = cy + 18;
				}
			});
		}
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		var cols = 3;
		var prev = _curSel;

		if (controls.LEFT_P && _curSel % cols > 0)
			_curSel--;
		if (controls.RIGHT_P && _curSel % cols < cols - 1)
			_curSel++;
		if (controls.UP_P && _curSel >= cols)
			_curSel -= cols;
		if (controls.DOWN_P && _curSel < _cards.length - cols)
			_curSel += cols;

		if (_curSel != prev)
		{
			FlxG.sound.play(Paths.sound('menus/scrollMenu'));
			_updateSelection(_curSel);
		}

		if (controls.ACCEPT)
		{
			FlxG.sound.play(Paths.sound('menus/confirmMenu'));
			_cards[_curSel].pulse(() -> _openEditor(_curSel));
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			StateTransition.switchState(new funkin.menus.MainMenuState());
		}
	}

	// ── Selección visual ──────────────────────────────────────────────────────

	function _updateSelection(idx:Int, instant:Bool = false):Void
	{
		for (i in 0..._cards.length)
			_cards[i].setSelected(i == idx, instant);
		_curSel = idx;
	}

	// ── Apertura de editor ────────────────────────────────────────────────────

	function _openEditor(idx:Int):Void
	{
		FlxG.camera.fade(FlxColor.BLACK, 0.22, false, function()
		{
			switch (idx)
			{
				case 0:
					StateTransition.switchState(new funkin.menus.CharacterSelectorState());
				case 1:
					StateTransition.switchState(new funkin.debug.editors.StoryMenuEditor());
				case 2:
					StateTransition.switchState(new funkin.debug.editors.MenuEditor());
				/*
					case 3: StateTransition.switchState(new StageEditor());
					case 4: StateTransition.switchState(new charting.ChartingState());
					case 5: StateTransition.switchState(new DialogueEditor()); */
				default:
					StateTransition.switchState(new funkin.menus.MainMenuState());
			}
		});
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// EditorCard
// ─────────────────────────────────────────────────────────────────────────────

class EditorCard extends flixel.group.FlxSpriteGroup
{
	var _bg:FlxSprite;
	var _border:FlxSprite;
	var _icon:FlxText;
	var _name:FlxText;
	var _desc:FlxText;
	var _accent:Int;
	var _cw:Int;
	var _ch:Int;
	var _selected:Bool = false;

	public function new(cx:Float, cy:Float, cw:Int, ch:Int, name:String, desc:String, icon:String, accent:Int)
	{
		super(cx, cy);
		_accent = accent;
		_cw = cw;
		_ch = ch;

		// Fondo
		_bg = new FlxSprite(0, 0);
		_bg.makeGraphic(cw, ch, 0xFF141426);
		add(_bg);

		// Borde izquierdo de color
		_border = new FlxSprite(0, 0);
		_border.makeGraphic(3, ch, accent);
		add(_border);

		// Ícono
		_icon = new FlxText(14, 12, 0, icon, 28);
		_icon.color = FlxColor.fromInt(accent);
		_icon.font = Paths.font("vcr.ttf");
		add(_icon);

		// Nombre
		_name = new FlxText(14, _icon.y + _icon.height + 6, cw - 18, name, 14);
		_name.color = 0xFFE0E0FF;
		_name.font = Paths.font("vcr.ttf");
		add(_name);

		// Descripción
		_desc = new FlxText(14, _name.y + _name.height + 5, cw - 20, desc, 10);
		_desc.color = 0xFF8888AA;
		_desc.font = Paths.font("vcr.ttf");
		add(_desc);
	}

	public function setSelected(sel:Bool, instant:Bool = false):Void
	{
		if (_selected == sel && !instant)
			return;
		_selected = sel;

		var targetBg:Int = sel ? 0xFF1C1C38 : 0xFF141426;
		var targetA:Float = sel ? 1.0 : 0.6;

		if (instant)
		{
			_bg.makeGraphic(_cw, _ch, targetBg);
			_icon.alpha = _name.alpha = targetA;
		}
		else
		{
			FlxTween.color(_bg, 0.12, FlxColor.fromInt(_bg.color), FlxColor.fromInt(targetBg));
			FlxTween.tween(_icon, {alpha: targetA}, 0.12);
			FlxTween.tween(_name, {alpha: targetA}, 0.12);
		}

		// Escalar ligeramente al seleccionar
		var sc = sel ? 1.02 : 1.0;
		if (!instant)
			FlxTween.tween(this.scale, {x: sc, y: sc}, 0.14, {ease: FlxEase.quartOut});
		else
		{
			scale.x = sc;
			scale.y = sc;
		}
	}

	public function pulse(onDone:Void->Void):Void
	{
		FlxTween.tween(this.scale, {x: 0.96, y: 0.96}, 0.07, {
			ease: FlxEase.quartIn,
			onComplete: function(_)
			{
				FlxTween.tween(this.scale, {x: 1.06, y: 1.06}, 0.1, {
					ease: FlxEase.quartOut,
					onComplete: function(_)
					{
						if (onDone != null)
							onDone();
					}
				});
			}
		});
	}
}
