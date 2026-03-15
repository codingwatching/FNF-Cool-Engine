package funkin.debug;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxUIGroup;
import flixel.addons.ui.FlxUITabMenu;
import funkin.debug.themes.EditorTheme;

/**
 * CoolTabMenu — Reemplazo visual de FlxUITabMenu con la estética del engine.
 *
 * ── Drop-in: cambia 3 líneas por editor ──────────────────────────────────────
 *
 *   // 1. Import
 *   import funkin.debug.CoolTabMenu;          // en vez de FlxUITabMenu
 *
 *   // 2. Tipo de la variable
 *   var rightPanel : CoolTabMenu;             // en vez de FlxUITabMenu
 *
 *   // 3. Constructor
 *   rightPanel = new CoolTabMenu(null, tabs, true);
 *
 *   // Todo lo demás queda igual:
 *   rightPanel.resize(w, h);
 *   rightPanel.addGroup(tab);
 *   rightPanel.selected_tab_id = 'MyTab';
 *
 * ── Diseño visual ────────────────────────────────────────────────────────────
 *
 *   • Barra de tabs (28 px): fondo bgPanelAlt.
 *   • Línea accent de 1 px separa barra de body.
 *   • Tab inactiva: fondo bgHover, texto textSecondary al 75 %.
 *   • Tab activa:   fondo accent×18 % alpha, texto blanco, underline 2 px.
 *   • Hover: texto al 100 % opacity.
 *   • Body: bgPanel puro.
 *   • Fade-in de 80 ms al cambiar de pestaña.
 *   • refresh() para actualizar colores cuando cambia el tema.
 *
 * ── Estrategia de ocultación del chrome nativo ───────────────────────────────
 *
 *   Hacemos snapshot de members.length antes/después de super() para
 *   identificar exactamente qué sprites añadió FlxUITabMenu internamente
 *   y los ocultamos con visible=false. Nuestro chrome va encima.
 *
 * @author Cool Engine Team
 */
@:access(flixel.addons.ui.FlxUITabMenu)
class CoolTabMenu extends FlxUITabMenu
{
	// ── Constantes de diseño ─────────────────────────────────────────────────

	public static inline var TAB_BAR_H  : Int   = 28;
	public static inline var ACCENT_BAR : Int   = 2;
	public static inline var TAB_FONT   : Int   = 10;
	static         inline var FADE_TIME : Float = 0.08;

	// ── Chrome propio ────────────────────────────────────────────────────────

	var _tabBarBg   : FlxSprite;
	var _tabBarLine : FlxSprite;
	var _bodyBg     : FlxSprite;
	var _tabBtns    : Array<CoolTabBtn> = [];
	var _fadeTween  : FlxTween;

	/** Cuántos miembros añadió super() — son el chrome nativo a ocultar. */
	var _nativeCount : Int = 0;

	var _pw      : Int = 300;
	var _ph      : Int = 400;
	var _tabDefs : Array<{name:String, label:String}>;

	// ── Constructor ──────────────────────────────────────────────────────────

	public function new(?back_:FlxSprite, tabs:Array<{name:String, label:String}>, wrap:Bool = true)
	{
		_tabDefs = tabs;
		super(back_, tabs, wrap);

		// Después de super(): todos los miembros son chrome nativo.
		_nativeCount = members.length;
		_hideNativeMembers();
		_buildChrome();
	}

	// ── API pública ──────────────────────────────────────────────────────────

	override public function resize(w:Float, h:Float):Void
	{
		_pw = Std.int(w);
		_ph = Std.int(h);
		super.resize(w, h);
		_hideNativeMembers();
		_buildChrome();
	}

	override public function addGroup(ui:FlxUIGroup):Void
	{
		super.addGroup(ui);
		// addGroup no modifica el chrome visual — no rebuild necesario.
	}

	override public function set_selected_tab_id(id:String):String
	{
		var r = super.set_selected_tab_id(id);
		_updateHighlights();
		_fadeBody();
		return r;
	}

	/** Refresca colores del chrome con el tema activo. */
	public function refresh():Void
	{
		_hideNativeMembers();
		_buildChrome();
	}

	// ── Chrome interno ───────────────────────────────────────────────────────

	function _hideNativeMembers():Void
	{
		for (i in 0..._nativeCount)
			if (members[i] != null) members[i].visible = false;
	}

	function _buildChrome():Void
	{
		var T  = EditorTheme.current;
		_destroyOwnChrome();

		var pw = (_pw > 0) ? _pw : 300;
		var ph = (_ph > 0) ? _ph : 400;

		// Fondo barra de tabs
		_tabBarBg = new FlxSprite(0, 0);
		_tabBarBg.makeGraphic(pw, TAB_BAR_H, T.bgPanelAlt);
		_tabBarBg.scrollFactor.set();
		add(_tabBarBg);

		// Línea accent separadora
		_tabBarLine = new FlxSprite(0, TAB_BAR_H);
		_tabBarLine.makeGraphic(pw, 1, T.accent);
		_tabBarLine.alpha = 0.4;
		_tabBarLine.scrollFactor.set();
		add(_tabBarLine);

		// Body
		var bodyH = ph - TAB_BAR_H - 1;
		_bodyBg = new FlxSprite(0, TAB_BAR_H + 1);
		_bodyBg.makeGraphic(pw, (bodyH > 0) ? bodyH : 1, T.bgPanel);
		_bodyBg.scrollFactor.set();
		add(_bodyBg);

		// Botones de tab
		_buildTabBtns(pw, T);
		_updateHighlights();
	}

	function _buildTabBtns(pw:Int, T:funkin.debug.themes.ThemeData):Void
	{
		for (b in _tabBtns) { remove(b, true); b.destroy(); }
		_tabBtns = [];
		if (_tabDefs == null || _tabDefs.length == 0) return;

		var n    = _tabDefs.length;
		var btnW = Std.int(pw / n);
		var last = pw - btnW * (n - 1);

		for (i in 0...n)
		{
			var bw  = (i == n - 1) ? last : btnW;
			var btn = new CoolTabBtn(btnW * i, 0, bw, TAB_BAR_H,
			                         _tabDefs[i].label, _tabDefs[i].name, T);
			btn.scrollFactor.set();
			btn.onClick = function(name:String) { selected_tab_id = name; };
			_tabBtns.push(btn);
			add(btn);
		}
	}

	function _updateHighlights():Void
	{
		var T = EditorTheme.current;
		for (b in _tabBtns)
			b.setActive(b.tabName == selected_tab_id, T);
	}

	function _fadeBody():Void
	{
		if (_fadeTween != null) _fadeTween.cancel();
		if (_bodyBg == null) return;
		_bodyBg.alpha = 0.55;
		_fadeTween = FlxTween.globalManager.tween(
			_bodyBg, {alpha: 1.0}, FADE_TIME, {ease: FlxEase.quartOut}
		);
	}

	function _destroyOwnChrome():Void
	{
		if (_fadeTween  != null) { _fadeTween.cancel(); _fadeTween = null; }
		for (b in _tabBtns)     { remove(b, true); b.destroy(); }
		_tabBtns = [];
		inline function _kill(s:FlxSprite):Void
			if (s != null) { remove(s, true); s.destroy(); }
		_kill(_bodyBg);     _bodyBg     = null;
		_kill(_tabBarLine); _tabBarLine = null;
		_kill(_tabBarBg);   _tabBarBg   = null;
	}

	override public function destroy():Void
	{
		_destroyOwnChrome();
		super.destroy();
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// CoolTabBtn
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Botón de pestaña individual.
 * FlxSpriteGroup puro: bg + underline + separador + label.
 * No usa FlxButton para evitar el estilo por defecto de flixel-addons.
 */
class CoolTabBtn extends FlxSpriteGroup
{
	public var tabName : String;
	public var onClick : String -> Void;

	var _bg        : FlxSprite;
	var _underline : FlxSprite;
	var _label     : FlxText;

	var _bw       : Int;
	var _bh       : Int;
	var _isActive : Bool = false;
	var _isHover  : Bool = false;

	public function new(bx:Float, by:Float, bw:Int, bh:Int,
	                    labelStr:String, name:String,
	                    T:funkin.debug.themes.ThemeData)
	{
		super(bx, by);
		tabName = name;
		_bw = bw;
		_bh = bh;

		// Fondo
		_bg = new FlxSprite(0, 0);
		_bg.makeGraphic(bw, bh, T.bgHover);
		add(_bg);

		// Underline (activo)
		_underline = new FlxSprite(0, bh - CoolTabMenu.ACCENT_BAR);
		_underline.makeGraphic(bw, CoolTabMenu.ACCENT_BAR, T.accent);
		_underline.visible = false;
		add(_underline);

		// Separador derecho sutil
		var sep = new FlxSprite(bw - 1, 3);
		sep.makeGraphic(1, bh - 6, T.borderColor);
		sep.alpha = 0.2;
		add(sep);

		// Label
		_label = new FlxText(0, 0, bw, labelStr, CoolTabMenu.TAB_FONT);
		_label.alignment = CENTER;
		_label.color     = FlxColor.fromInt(T.textSecondary);
		_label.alpha     = 0.75;
		_label.scrollFactor.set();
		_label.y = Std.int((bh - _label.height) * 0.5) - 1;
		add(_label);
	}

	public function setActive(active:Bool, T:funkin.debug.themes.ThemeData):Void
	{
		_isActive = active;
		if (active)
		{
			var c = FlxColor.fromInt(T.accent);
			c.alphaFloat = 0.18;
			_bg.makeGraphic(_bw, _bh, c);
			_label.color = FlxColor.WHITE;
			_label.alpha = 1.0;
			_underline.makeGraphic(_bw, CoolTabMenu.ACCENT_BAR, T.accent);
			_underline.visible = true;
		}
		else
		{
			_bg.makeGraphic(_bw, _bh, T.bgHover);
			_label.color = FlxColor.fromInt(T.textSecondary);
			_label.alpha = _isHover ? 1.0 : 0.75;
			_underline.visible = false;
		}
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Las coordenadas del grupo en pantalla dependen de si scrollFactor=0
		// y de la posición del padre (CoolTabMenu). Como usamos scrollFactor.set()
		// en el padre y en cada btn, x/y son coordenadas de pantalla directas.
		var hover = (FlxG.mouse.x >= x && FlxG.mouse.x <= x + _bw
		          && FlxG.mouse.y >= y && FlxG.mouse.y <= y + _bh);

		if (hover != _isHover)
		{
			_isHover = hover;
			if (!_isActive)
				_label.alpha = hover ? 1.0 : 0.75;
		}

		if (hover && FlxG.mouse.justPressed && onClick != null)
			onClick(tabName);
	}

	override public function destroy():Void
	{
		onClick = null;
		super.destroy();
	}
}
