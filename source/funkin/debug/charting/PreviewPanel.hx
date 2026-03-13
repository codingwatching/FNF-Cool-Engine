package funkin.debug.charting;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import funkin.data.Song.SwagSong;
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.CharacterController;

using StringTools;

// ============================================================================
//  PreviewPanel v3 — V-Slice style floating character preview windows.
//
//  Fixes vs v2:
//    ① Close (×) button — fully hides the window and releases its camera
//    ② Input isolation — sets parent.clickConsumed when the mouse is over
//       the window, so the charting grid never receives those clicks
//    ③ Correct character positioning — animOffsets are scaled by the preview
//       ratio so the sprite stays centered regardless of its original offsets
//
//  Public API (backward-compatible with v1):
//    onNotePass(direction, groupIndex)
//    refreshAll()
//    selectedGroupIndex   (compat shim)
// ============================================================================
class PreviewPanel extends FlxGroup
{
	var parent   : ChartingState;
	var _song    : SwagSong;
	var camHUD   : FlxCamera;
	var camGame  : FlxCamera;

	public var windows : Array<CharacterPreviewWindow> = [];

	// v1 compat
	public var selectedGroupIndex(get, never) : Int;
	function get_selectedGroupIndex() : Int
		return (windows.length > 0) ? windows[0].groupIndex : 0;

	public function new(parent:ChartingState, song:SwagSong,
	                    camGame:FlxCamera, camHUD:FlxCamera)
	{
		super();
		this.parent  = parent;
		this._song   = song;
		this.camGame = camGame;
		this.camHUD  = camHUD;
		_buildWindows();
	}

	function _buildWindows() : Void
	{
		for (w in windows) { w.closeWindow(); remove(w, true); }
		windows = [];

		// Windows start closed — user opens them from the Tools panel
		var opp = new CharacterPreviewWindow(parent, _song, camHUD,
			0, _charName(0), 30, 155, true);
		add(opp);
		windows.push(opp);

		var plr = new CharacterPreviewWindow(parent, _song, camHUD,
			1, _charName(1), FlxG.width - CharacterPreviewWindow.WIN_W - 30, 155, true);
		add(plr);
		windows.push(plr);
	}

	function _charName(typeIndex:Int) : String
	{
		if (_song.characters != null)
		{
			var typeName = ["Opponent", "Player", "Girlfriend"][typeIndex];
			for (c in _song.characters)
				if (c.type == typeName) return c.name;
		}
		return switch (typeIndex) {
			case 0: _song.player2   ?? "dad";
			case 1: _song.player1   ?? "bf";
			case 2: _song.gfVersion ?? "gf";
			default: "bf";
		};
	}

	public function onNotePass(direction:Int, groupIndex:Int) : Void
	{
		for (w in windows)
			if (!w.isClosed && w.groupIndex == groupIndex && w.isLoaded)
				w.triggerSing(direction % 4);
	}

	public function refreshAll() : Void
	{
		for (w in windows)
		{
			var newName = _charName(w.charType);
			if (newName != w.charName) w.loadChar(newName);
			w.autoDetectGroupIndex();
		}
	}

	override public function destroy() : Void
	{
		for (w in windows) w.closeWindow();
		super.destroy();
	}
}


// ============================================================================
//  CharacterPreviewWindow — one floating, draggable, closeable preview window.
//
//  ┌────────────────────────────────────────┐  ← colored accent line (3 px)
//  │  Opponent Preview — Dad         [−] [×] │  ← title bar
//  ├────────────────────────────────────────┤
//  │                                        │
//  │        [character renders here]        │  ← dedicated FlxCamera
//  │                                        │
//  └────────────────────────────────────────┘
// ============================================================================
class CharacterPreviewWindow extends FlxGroup
{
	// ── Layout ───────────────────────────────────────────────────────────────
	public  static inline var WIN_W  : Int = 316;
	public  static inline var WIN_H  : Int = 390;
	private static inline var BAR_H  : Int = 30;
	private static inline var BORDER : Int = 2;
	private static inline var BTN_W  : Int = 26;

	private static inline var CAM_W : Int = WIN_W - BORDER * 2;
	private static inline var CAM_H : Int = WIN_H - BAR_H - BORDER * 2;

	// ── Colors ───────────────────────────────────────────────────────────────
	private static inline var C_BG        : Int = 0xCC0A0A1A;
	private static inline var C_BAR       : Int = 0xFF0D1223;
	private static inline var C_BORDER    : Int = 0xFF1A2A3A;
	private static inline var C_CHAR_BG   : Int = 0xFF0D0D1A;
	private static inline var C_ACCENT_OPP: Int = 0xFFFF5566;
	private static inline var C_ACCENT_PLR: Int = 0xFF00D9FF;
	private static inline var C_ACCENT_GF : Int = 0xFFFF88EE;
	private static inline var C_TEXT      : Int = 0xFFDDDDDD;
	private static inline var C_SUBTEXT   : Int = 0xFF778899;
	private static inline var C_BTN       : Int = 0xFF111828;
	private static inline var C_BTN_CLOSE_HOVER : Int = 0xFF3A0A0A;

	// ── Data ─────────────────────────────────────────────────────────────────
	var parent   : ChartingState;
	var _song    : SwagSong;
	var camHUD   : FlxCamera;

	public var charType   : Int;
	public var charName   : String;
	public var groupIndex : Int = 0;

	// ── Camera ────────────────────────────────────────────────────────────────
	var camChar : FlxCamera = null;

	// ── Frame sprites ─────────────────────────────────────────────────────────
	var frameBorder  : FlxSprite;
	var frameBody    : FlxSprite;
	var charAreaBg   : FlxSprite;
	var accentLine   : FlxSprite;
	var titleBar     : FlxSprite;
	var titleText    : FlxText;
	var subText      : FlxText;
	var camBorderSpr : FlxSprite;

	// Close [×]
	var closeBtn    : FlxSprite;
	var closeBtnTxt : FlxText;

	// ── Character ─────────────────────────────────────────────────────────────
	var previewChar    : Character           = null;
	var charController : CharacterController = null;
	var _pendingLoad   : String              = null;
	var _charScale     : Float               = 1.0; // preview ratio, kept for _positionChar

	public var isLoaded  : Bool = false;
	public var isClosed  : Bool = false;

	// ── Window position ───────────────────────────────────────────────────────
	var _winX : Float;
	var _winY : Float;

	// ── Drag ─────────────────────────────────────────────────────────────────
	var _dragging : Bool  = false;
	var _dragOffX : Float = 0;
	var _dragOffY : Float = 0;

	// ── Button hover state ────────────────────────────────────────────────────
	var _closeHovered : Bool = false;

	// ── All frame elements (for batch move) ───────────────────────────────────
	var _frameSprites : Array<FlxSprite> = [];
	var _frameTexts   : Array<FlxText>   = [];

	// ── Constructor ───────────────────────────────────────────────────────────
	public function new(parent:ChartingState, song:SwagSong, camHUD:FlxCamera,
	                    charType:Int, charName:String, startX:Float, startY:Float,
	                    startClosed:Bool = false)
	{
		super();
		this.parent   = parent;
		this._song    = song;
		this.camHUD   = camHUD;
		this.charType = charType;
		this.charName = charName;
		this._winX    = startX;
		this._winY    = startY;

		autoDetectGroupIndex();

		if (startClosed)
		{
			isClosed = true;
			// No camera, no frame built — window is dormant
		}
		else
		{
			_setupCamera();
			_buildFrame();
			_scheduleLoad(charName);
			_playEntry();
		}
	}

	// ── Camera ────────────────────────────────────────────────────────────────
	function _setupCamera() : Void
	{
		camChar = new FlxCamera(
			Std.int(_winX + BORDER),
			Std.int(_winY + BAR_H + BORDER),
			CAM_W, CAM_H
		);
		camChar.bgColor = C_CHAR_BG;
		camChar.scroll.set(0, 0);
		FlxG.cameras.add(camChar, false);
	}

	// ── Frame ─────────────────────────────────────────────────────────────────
	function _buildFrame() : Void
	{
		var accent = _accentColor();
		var closeBtnX = _winX + WIN_W - BTN_W - BORDER;

		frameBorder  = _spr(_winX - 1,     _winY - 1,     WIN_W + 2, WIN_H + 2, C_BORDER);
		frameBody    = _spr(_winX,          _winY,         WIN_W,     WIN_H,     C_BG);
		charAreaBg   = _spr(_winX + BORDER, _winY + BAR_H + BORDER, CAM_W, CAM_H, C_CHAR_BG);
		accentLine   = _spr(_winX,          _winY,         WIN_W,     3,         accent);
		titleBar     = _spr(_winX,          _winY + 3,     WIN_W,     BAR_H - 3, C_BAR);
		camBorderSpr = _spr(_winX + BORDER - 1, _winY + BAR_H + BORDER - 1,
		                    CAM_W + 2, CAM_H + 2, 0x22FFFFFF);

		// Close button [X]
		closeBtn    = _spr(closeBtnX, _winY + 4, BTN_W, BAR_H - 8, C_BTN);
		closeBtnTxt = _txt(closeBtnX, _winY + 7, BTN_W, "X", 11);

		// Title text
		titleText = new FlxText(_winX + 10, _winY + 8,
		                        WIN_W - BTN_W - BORDER - 20, '', 10);
		titleText.setFormat(Paths.font("vcr.ttf"), 10, C_TEXT, LEFT);
		titleText.scrollFactor.set();
		titleText.cameras = [camHUD];
		add(titleText);
		_frameTexts.push(titleText);

		// Char name sub-label (inside the char area)
		subText = new FlxText(_winX + 8, _winY + BAR_H + 6, CAM_W - 16, '', 8);
		subText.setFormat(Paths.font("vcr.ttf"), 8, C_SUBTEXT, LEFT);
		subText.scrollFactor.set();
		subText.cameras = [camHUD];
		add(subText);
		_frameTexts.push(subText);

		_refreshLabels();
	}

	function _spr(x:Float, y:Float, w:Int, h:Int, col:Int) : FlxSprite
	{
		var s = new FlxSprite(x, y).makeGraphic(w, h, col);
		s.scrollFactor.set();
		s.cameras = [camHUD];
		add(s);
		_frameSprites.push(s);
		return s;
	}

	function _txt(x:Float, y:Float, w:Int, str:String, size:Int) : FlxText
	{
		var t = new FlxText(x, y, w, str, size);
		t.setFormat(Paths.font("vcr.ttf"), size, C_TEXT, CENTER);
		t.scrollFactor.set();
		t.cameras = [camHUD];
		add(t);
		_frameTexts.push(t);
		return t;
	}

	function _accentColor() : Int
	{
		return switch (charType) { case 0: C_ACCENT_OPP; case 1: C_ACCENT_PLR; default: C_ACCENT_GF; };
	}

	function _refreshLabels() : Void
	{
		var type = ["Opponent Preview", "Player Preview", "GF Preview"][charType];
		titleText.text = '$type  —  $charName';
		subText.text   = charName;
	}

	// ── Entry animation ───────────────────────────────────────────────────────
	function _playEntry() : Void
	{
		var slideFrom = (charType == 0) ? -WIN_W - 20.0 : FlxG.width + 20.0;
		var deltaX    = slideFrom - _winX;

		for (s in _frameSprites) { s.x += deltaX; s.alpha = 0; }
		for (t in _frameTexts)   { t.x += deltaX; t.alpha = 0; }
		camChar.alpha = 0;

		var dur  = 0.30;
		var ease = FlxEase.backOut;

		for (s in _frameSprites)
			FlxTween.tween(s, {x: s.x - deltaX, alpha: 1.0}, dur, {ease: ease, startDelay: 0.04});
		for (t in _frameTexts)
			FlxTween.tween(t, {x: t.x - deltaX, alpha: 1.0}, dur, {ease: ease, startDelay: 0.04});
		FlxTween.tween(camChar, {alpha: 1.0}, dur, {ease: FlxEase.quadOut, startDelay: 0.10});
	}

	// ── Character loading ─────────────────────────────────────────────────────
	function _scheduleLoad(name:String) : Void { _pendingLoad = name; }

	public function loadChar(name:String) : Void { _scheduleLoad(name); }

	function _doLoad(name:String) : Void
	{
		_destroyChar();
		isLoaded    = false;
		this.charName = name;
		_refreshLabels();

		try
		{
			var isPlayer = (charType == 1);
			previewChar = new Character(0, 0, name, isPlayer);
			previewChar.cameras = [camChar];
			previewChar.scrollFactor.set(1, 1);
			add(previewChar);

			charController = switch (charType) {
				case 1:  new CharacterController(previewChar, null, null);
				case 2:  new CharacterController(null, null, previewChar);
				default: new CharacterController(null, previewChar, null);
			};

			// ── Sprite-scale approach (V-Slice style) ────────────────────────
			// Scale the sprite to fit the preview viewport.
			// animOffsets are LEFT UNTOUCHED — they work correctly as-is when
			// combined with the scaled sprite because _positionChar compensates
			// by adding offset to the sprite position (so Flixel's x-offset.x
			// rendering cancels it out).
			previewChar.scale.set(1, 1);
			previewChar.updateHitbox();

			// Play idle BEFORE measuring so frameWidth/Height are stable.
			try { previewChar.dance(); } catch (_:Dynamic) {}

			var fw:Float = previewChar.frameWidth  > 0 ? previewChar.frameWidth  : 200.0;
			var fh:Float = previewChar.frameHeight > 0 ? previewChar.frameHeight : 300.0;

			// Scale: fit character in ~80% of camera height, ~85% of camera width.
			// Smaller margins avoid clipping on characters with large empty frames.
			var ratio:Float = Math.min((CAM_H * 0.80) / fh, (CAM_W * 0.85) / fw);
			ratio = FlxMath.bound(ratio, 0.05, 2.0);
			_charScale = ratio;

			// Reset camera zoom (we scale the sprite, not the camera).
			if (camChar != null)
				camChar.zoom = 1.0;

			previewChar.scale.set(ratio, ratio);
			previewChar.updateHitbox();

			// Re-trigger idle after scale update.
			try { previewChar.dance(); } catch (_:Dynamic) {}

			_positionChar();
			isLoaded = true;

			trace('[PreviewPanel] "$name" loaded — scale=${Math.round(ratio*1000)/1000}');
		}
		catch (e:Dynamic)
		{
			trace('[PreviewPanel] ERROR loading "$name": $e');
			if (previewChar != null) { remove(previewChar, true); previewChar.destroy(); previewChar = null; }
			parent.showMessage('Preview: could not load "$name"', 0xFFFF3366);
		}
	}

	// ── Positioning ───────────────────────────────────────────────────────────
	/**
	 * Sprite-based positioning (camera scroll stays at 0,0).
	 *
	 * The character is scaled by _charScale. We position the sprite so that
	 * its visual frame appears:
	 *   · Centered horizontally in the camera viewport
	 *   · Bottom-anchored (a small margin from the bottom edge)
	 *
	 * Flixel renders a sprite's texture at (x − offset.x, y − offset.y).
	 * To make the texture appear at world position (targetX, targetY) we set:
	 *   sprite.x = targetX + offset.x
	 *   sprite.y = targetY + offset.y
	 *
	 * We reset the character to world origin each frame to prevent position
	 * drift caused by CharacterController, idle-bob effects, etc.
	 */
	function _positionChar() : Void
	{
		if (previewChar == null) return;

		// Scaled visual dimensions of the sprite frame.
		var sw:Float = previewChar.frameWidth  * _charScale;
		var sh:Float = previewChar.frameHeight * _charScale;

		// Where we want the texture top-left to appear in camera world-space.
		var targetX:Float = (CAM_W - sw) / 2.0;
		var targetY:Float = CAM_H - sh - 8.0; // 8 px margin from bottom

		// Sprite world position that results in texture at (targetX, targetY).
		previewChar.x = targetX + previewChar.offset.x;
		previewChar.y = targetY + previewChar.offset.y;
	}

	function _destroyChar() : Void
	{
		isLoaded = false;
		if (charController != null) { charController.destroy(); charController = null; }
		if (previewChar    != null)
		{
			previewChar.exists  = false;
			previewChar.visible = false;
			previewChar.cameras = [];
			remove(previewChar, true);
			previewChar.destroy();
			previewChar = null;
		}
	}

	// ── Group index ───────────────────────────────────────────────────────────
	public function autoDetectGroupIndex() : Void
	{
		if (_song == null) { groupIndex = charType == 1 ? 1 : 0; return; }

		if (_song.characters != null && _song.strumsGroups != null)
		{
			var typeName = ["Opponent", "Player", "Girlfriend"][charType];
			for (c in _song.characters)
			{
				if (c.type != typeName || c.strumsGroup == null) continue;
				for (gi in 0..._song.strumsGroups.length)
					if (_song.strumsGroups[gi].id == c.strumsGroup)
					{ groupIndex = gi; return; }
			}
		}

		if (_song.strumsGroups != null && _song.strumsGroups.length > 0)
		{
			for (gi in 0..._song.strumsGroups.length)
			{
				var cpu = _song.strumsGroups[gi].cpu;
				if (charType == 0 &&  cpu) { groupIndex = gi; return; }
				if (charType == 1 && !cpu) { groupIndex = gi; return; }
			}
		}

		groupIndex = (charType == 1) ? 1 : 0;
	}

	// ── Sing ─────────────────────────────────────────────────────────────────
	public function triggerSing(direction:Int) : Void
	{
		if (previewChar == null || charController == null) return;
		charController.sing(previewChar, direction);
		_positionChar();
	}

	// ── Open / Close ─────────────────────────────────────────────────────────
	public function openWindow() : Void
	{
		if (!isClosed) return;
		isClosed = false;
		_setupCamera();
		_buildFrame();
		_scheduleLoad(charName);
		_playEntry();
	}

	public function closeWindow() : Void
	{
		if (isClosed) return;
		isClosed = true;
		_destroyChar();

		// Fade + slide out then destroy camera
		var slideDir = (charType == 0) ? -1.0 : 1.0;
		var slideAmt = WIN_W + 40.0;

		for (s in _frameSprites)
			FlxTween.tween(s, {x: s.x + slideDir * slideAmt, alpha: 0.0}, 0.22,
			               {ease: FlxEase.quintIn, onComplete: function(_) s.visible = false});
		for (t in _frameTexts)
			FlxTween.tween(t, {x: t.x + slideDir * slideAmt, alpha: 0.0}, 0.22,
			               {ease: FlxEase.quintIn, onComplete: function(_) t.visible = false});
		FlxTween.tween(camChar, {alpha: 0.0}, 0.18, {ease: FlxEase.quintIn,
			onComplete: function(_) {
				if (camChar != null) { FlxG.cameras.remove(camChar); camChar = null; }
				// Clear frame lists so openWindow() starts fresh
				_frameSprites = [];
				_frameTexts   = [];
			}});
	}

	// ── Window movement ───────────────────────────────────────────────────────
	function _moveTo(nx:Float, ny:Float) : Void
	{
		var dx = nx - _winX;
		var dy = ny - _winY;
		_winX = nx; _winY = ny;

		for (s in _frameSprites) { s.x += dx; s.y += dy; }
		for (t in _frameTexts)   { t.x += dx; t.y += dy; }

		if (camChar != null)
		{
			camChar.x = Std.int(_winX + BORDER);
			camChar.y = Std.int(_winY + BAR_H + BORDER);
		}
	}

	// ── Hit-test helpers ──────────────────────────────────────────────────────
	function _mouseOver(x1:Float, y1:Float, w:Float, h:Float) : Bool
	{
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		return mx >= x1 && mx <= x1 + w && my >= y1 && my <= y1 + h;
	}

	function _isMouseOnWindow()   : Bool return _mouseOver(_winX, _winY, WIN_W, WIN_H);
	function _isMouseOnTitleBar() : Bool return _mouseOver(_winX, _winY, WIN_W, BAR_H);
	function _isMouseOnCloseBtn() : Bool
	{
		var bx = _winX + WIN_W - BTN_W - BORDER;
		return _mouseOver(bx, _winY + 4, BTN_W, BAR_H - 8);
	}

	// ── Update ────────────────────────────────────────────────────────────────
	override public function update(elapsed:Float) : Void
	{
		if (isClosed) return;

		// Deferred character load (safe: before super.update iterates children)
		if (_pendingLoad != null)
		{
			var name = _pendingLoad;
			_pendingLoad = null;
			_doLoad(name);
		}

		// Keep camera scroll at (0,0): character is positioned in camera world-space directly.

		super.update(elapsed);

		// Reposition every frame (anim offset can change each frame)
		if (previewChar != null && isLoaded) _positionChar();

		// ── Input block: consume ANY click/wheel on the window ─────────────
		if (_isMouseOnWindow())
		{
			parent.clickConsumed = true;
			parent.wheelConsumed = true;
		}

		// ── Button hover colors ───────────────────────────────────────────
		var onClose = _isMouseOnCloseBtn();
		if (onClose != _closeHovered) { _closeHovered = onClose; closeBtn.color = onClose ? C_BTN_CLOSE_HOVER : C_BTN; }

		// ── Button clicks ─────────────────────────────────────────────────
		if (FlxG.mouse.justPressed)
		{
			if (_isMouseOnCloseBtn()) { closeWindow(); return; }
			if (_isMouseOnTitleBar())
			{
				_dragging  = true;
				_dragOffX  = FlxG.mouse.x - _winX;
				_dragOffY  = FlxG.mouse.y - _winY;
				return;
			}
		}

		// ── Drag ─────────────────────────────────────────────────────────
		if (_dragging)
		{
			if (FlxG.mouse.pressed)
				_moveTo(
					FlxMath.bound(FlxG.mouse.x - _dragOffX, 0, FlxG.width  - WIN_W),
					FlxMath.bound(FlxG.mouse.y - _dragOffY, 0, FlxG.height - BAR_H)
				);
			else _dragging = false;
		}
	}

	// ── Destroy ───────────────────────────────────────────────────────────────
	override public function destroy() : Void
	{
		_destroyChar();
		if (camChar != null) { FlxG.cameras.remove(camChar); camChar = null; }
		super.destroy();
	}
}
