package funkin.debug.charting;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import flixel.addons.ui.*;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import funkin.data.Song.SwagSong;
import funkin.gameplay.objects.character.CharacterList;
import funkin.gameplay.objects.character.HealthIcon;

using StringTools;

/**
 * MetaPopup — expanded V-Slice-style metadata editor.
 *
 * Fields:
 *   Song       — title (display name), artist, charter
 *   Audio      — BPM (primary), Speed, needsVoices
 *   Stage      — dropdown from CharacterList.stages
 *   Characters — Player / Opponent / GF buttons with health icons
 *                Clicking a character button opens CharacterPickerMenu (V-Slice style)
 *   NoteStyle  — text input
 *   BPM Changes— simplified list: add/remove rows
 *
 * Opens via the [Meta] button in the toolbar.
 * Closed by clicking outside the panel or pressing ESC.
 */
class MetaPopup extends FlxGroup
{
	var parent:ChartingState;
	var _song:SwagSong;
	var camHUD:FlxCamera;

	// ── Layout ────────────────────────────────────────────────────────────────
	static inline var POPUP_W:Int = 580;
	static inline var POPUP_H:Int = 520;

	static inline var BG_PANEL:Int     = 0xFF0D0D1F;
	static inline var ACCENT_CYAN:Int  = 0xFF00D9FF;
	static inline var ACCENT_GREEN:Int = 0xFF00FF88;
	static inline var ACCENT_PINK:Int  = 0xFFFF00E5;
	static inline var TEXT_WHITE:Int   = 0xFFFFFFFF;
	static inline var TEXT_GRAY:Int    = 0xFFAAAAAA;

	// ── State ─────────────────────────────────────────────────────────────────
	public var isOpen:Bool = false;

	// ── Static UI elements ────────────────────────────────────────────────────
	var overlay:FlxSprite;
	var panel:FlxSprite;

	// Song section
	var titleInput:FlxUIInputText;
	var artistInput:FlxUIInputText;
	var charterInput:FlxUIInputText;

	// Audio section
	var bpmStepper:FlxUINumericStepper;
	var speedStepper:FlxUINumericStepper;
	var needsVoicesCheck:FlxUICheckBox;

	// Stage section
	var stageDropDown:FlxUIDropDownMenu;

	// Note style section
	var noteStyleInput:FlxUIInputText;

	// Character buttons (V-Slice style)
	var charBtnBF:FlxSprite;
	var charBtnDad:FlxSprite;
	var charBtnGF:FlxSprite;
	var charIconBF:FlxSprite;
	var charIconDad:FlxSprite;
	var charIconGF:FlxSprite;
	var charLabelBF:FlxText;
	var charLabelDad:FlxText;
	var charLabelGF:FlxText;

	// BPM changes simplified (just list display + add/remove)
	var bpmChangesList:FlxTypedGroup<FlxText>;
	var bpmChangesData:Array<{time:Float, bpm:Float}> = [];
	var bpmChangeScrollY:Int = 0;

	// Action buttons
	var applyBtn:FlxButton;
	var closeBtn:FlxButton;

	// V-Slice character picker sub-popup
	var _inlineCharPicker:InlineCharacterPicker;
	var _pickerTargetField:String = "player1"; // which field to update

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new(parent:ChartingState, song:SwagSong, camHUD:FlxCamera)
	{
		super();
		this.parent  = parent;
		this._song   = song;
		this.camHUD  = camHUD;

		_buildUI();
		_inlineCharPicker = new InlineCharacterPicker(parent, song, camHUD, this);
		add(_inlineCharPicker);

		visible = false;
		close();
	}

	// ── UI Builder ────────────────────────────────────────────────────────────

	function _lbl(x:Float, y:Float, text:String, ?size:Int = 10, ?color:Int = 0):Void
	{
		if (color == 0) color = TEXT_GRAY;
		var t = new FlxText(x, y, 0, text, size);
		t.setFormat(Paths.font("vcr.ttf"), size, color, LEFT);
		t.scrollFactor.set(); t.cameras = [camHUD]; add(t);
	}

	function _section(x:Float, y:Float, text:String):Void
	{
		var line = new FlxSprite(x, y).makeGraphic(Std.int(POPUP_W - x * 2), 1, ACCENT_CYAN);
		line.alpha = 0.4; line.scrollFactor.set(); line.cameras = [camHUD]; add(line);
		var t = new FlxText(x, y - 14, 0, text, 11);
		t.setFormat(Paths.font("vcr.ttf"), 11, ACCENT_CYAN, LEFT);
		t.scrollFactor.set(); t.cameras = [camHUD]; add(t);
	}

	function _buildUI():Void
	{
		var cx = (FlxG.width  - POPUP_W) / 2.0;
		var cy = (FlxG.height - POPUP_H) / 2.0;

		// Overlay + Panel
		overlay = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xAA000000);
		overlay.scrollFactor.set(); overlay.cameras = [camHUD]; add(overlay);

		panel = new FlxSprite(cx, cy).makeGraphic(POPUP_W, POPUP_H, BG_PANEL);
		panel.scrollFactor.set(); panel.cameras = [camHUD]; add(panel);

		// Top accent bar
		var tbar = new FlxSprite(cx, cy).makeGraphic(POPUP_W, 4, ACCENT_CYAN);
		tbar.scrollFactor.set(); tbar.cameras = [camHUD]; add(tbar);

		// Title
		var title = new FlxText(cx + 16, cy + 10, POPUP_W - 32, "SONG METADATA", 18);
		title.setFormat(Paths.font("vcr.ttf"), 18, ACCENT_CYAN, LEFT);
		title.scrollFactor.set(); title.cameras = [camHUD]; add(title);

		// Left column X
		var lx = cx + 16.0;
		var y  = cy + 38.0;

		// ── SONG ─────────────────────────────────────────────────────────────
		_section(lx, y, "SONG"); y += 10;

		_lbl(lx, y, "Title:"); y += 14;
		titleInput = new FlxUIInputText(lx, y, 250, _song.song ?? "", 12);
		titleInput.scrollFactor.set(); titleInput.cameras = [camHUD]; add(titleInput); y += 26;

		_lbl(lx, y, "Artist:");
		_lbl(lx + 165, y, "Charter:");
		y += 14;
		artistInput = new FlxUIInputText(lx, y, 155, _song.artist ?? "", 12);
		artistInput.scrollFactor.set(); artistInput.cameras = [camHUD]; add(artistInput);
		charterInput = new FlxUIInputText(lx + 165, y, 155, "", 12);
		charterInput.scrollFactor.set(); charterInput.cameras = [camHUD]; add(charterInput);
		y += 30;

		// ── AUDIO ─────────────────────────────────────────────────────────────
		_section(lx, y, "AUDIO"); y += 10;

		_lbl(lx, y, "BPM:");
		_lbl(lx + 110, y, "Speed:");
		y += 14;
		bpmStepper = new FlxUINumericStepper(lx, y, 1, _song.bpm > 0 ? _song.bpm : 120, 1, 999, 0);
		bpmStepper.scrollFactor.set(); bpmStepper.cameras = [camHUD]; add(bpmStepper);
		speedStepper = new FlxUINumericStepper(lx + 110, y, 0.1, _song.speed > 0 ? _song.speed : 1.0, 0.1, 10.0, 1);
		speedStepper.scrollFactor.set(); speedStepper.cameras = [camHUD]; add(speedStepper);
		y += 30;

		needsVoicesCheck = new FlxUICheckBox(lx, y, null, null, "Needs Voices (load vocals track)", 250);
		needsVoicesCheck.checked = _song.needsVoices;
		needsVoicesCheck.scrollFactor.set(); needsVoicesCheck.cameras = [camHUD]; add(needsVoicesCheck);
		y += 28;

		// ── STAGE + NOTE STYLE ───────────────────────────────────────────────
		_section(lx, y, "STAGE & STYLE"); y += 10;

		_lbl(lx, y, "Stage:");
		_lbl(lx + 210, y, "Note Style:");
		y += 14;

		CharacterList.init();
		var stageNames:Array<String> = CharacterList.stages.length > 0 ? CharacterList.stages : ["stage_week1"];
		var stageLabels:Array<String> = stageNames.map(function(s) return CharacterList.getStageName(s) + ' [$s]');
		stageDropDown = new FlxUIDropDownMenu(lx, y, FlxUIDropDownMenu.makeStrIdLabelArray(stageLabels, true), function(id:String)
		{
			var idx = Std.parseInt(id);
			if (idx != null && idx >= 0 && idx < stageNames.length)
				_song.stage = stageNames[idx];
		});
		// Select current stage
		var currentStageIdx = stageNames.indexOf(_song.stage ?? "");
		if (currentStageIdx >= 0)
		{
			stageDropDown.selectedId    = '$currentStageIdx';
			stageDropDown.selectedLabel = stageLabels[currentStageIdx];
		}
		stageDropDown.scrollFactor.set(); stageDropDown.cameras = [camHUD]; add(stageDropDown);

		noteStyleInput = new FlxUIInputText(lx + 210, y, 150, "", 12);
		noteStyleInput.scrollFactor.set(); noteStyleInput.cameras = [camHUD]; add(noteStyleInput);
		y += 30;

		// ── CHARACTERS (V-SLICE STYLE) ────────────────────────────────────────
		_section(lx, y, "CHARACTERS"); y += 10;

		var charHint = new FlxText(lx, y, POPUP_W - 32,
			"Click a character to change it using the V-Slice picker.", 9);
		charHint.setFormat(Paths.font("vcr.ttf"), 9, 0xFF445566, LEFT);
		charHint.scrollFactor.set(); charHint.cameras = [camHUD]; add(charHint);
		y += 14;

		// Three character buttons
		var charBtnW:Int = 110;
		var charBtnH:Int = 66;
		var charSlots = [
			{label: "OPPONENT", field: "player2",   x: lx,             color: 0xFF220000},
			{label: "PLAYER",   field: "player1",   x: lx + 125.0,    color: 0xFF002233},
			{label: "GF",       field: "gfVersion", x: lx + 250.0,    color: 0xFF220022}
		];

		// Build character buttons (BG + icon + name label + type label)
		charBtnDad  = _makeCharBtn(charSlots[0].x, y, charBtnW, charBtnH, charSlots[0].color, charSlots[0].label);
		charBtnBF   = _makeCharBtn(charSlots[1].x, y, charBtnW, charBtnH, charSlots[1].color, charSlots[1].label);
		charBtnGF   = _makeCharBtn(charSlots[2].x, y, charBtnW, charBtnH, charSlots[2].color, charSlots[2].label);

		charIconDad = _makeCharIcon(charSlots[0].x + 4, y + 18, _song.player2 ?? "dad");
		charIconBF  = _makeCharIcon(charSlots[1].x + 4, y + 18, _song.player1 ?? "bf");
		charIconGF  = _makeCharIcon(charSlots[2].x + 4, y + 18, _song.gfVersion ?? "gf");

		charLabelDad = _makeCharLabel(charSlots[0].x, y + charBtnH - 16, charBtnW, _song.player2 ?? "dad");
		charLabelBF  = _makeCharLabel(charSlots[1].x, y + charBtnH - 16, charBtnW, _song.player1 ?? "bf");
		charLabelGF  = _makeCharLabel(charSlots[2].x, y + charBtnH - 16, charBtnW, _song.gfVersion ?? "gf");

		y += charBtnH + 14;

		// ── BPM CHANGES (simplified) ──────────────────────────────────────────
		_section(lx, y, "BPM CHANGES"); y += 10;

		var bpmHint = new FlxText(lx, y, POPUP_W - 32,
			"Scroll: ↑/↓ or wheel over list. These changes apply at specific song times.", 9);
		bpmHint.setFormat(Paths.font("vcr.ttf"), 9, 0xFF445566, LEFT);
		bpmHint.scrollFactor.set(); bpmHint.cameras = [camHUD]; add(bpmHint);
		y += 14;

		bpmChangesList = new FlxTypedGroup<FlxText>();
		add(bpmChangesList);

		// Add / Remove buttons
		var addBpmBtn = new FlxButton(lx, y + 60, "+ Add BPM Change", function()
		{
			bpmChangesData.push({time: 0, bpm: bpmStepper.value});
			_rebuildBpmChangeList(lx, cy + 370);
		});
		addBpmBtn.scrollFactor.set(); addBpmBtn.cameras = [camHUD]; add(addBpmBtn);

		var removeBpmBtn = new FlxButton(lx + 125, y + 60, "- Remove Last", function()
		{
			if (bpmChangesData.length > 1)
			{
				bpmChangesData.pop();
				_rebuildBpmChangeList(lx, cy + 370);
			}
		});
		removeBpmBtn.scrollFactor.set(); removeBpmBtn.cameras = [camHUD]; add(removeBpmBtn);

		// ── ACTION BUTTONS ────────────────────────────────────────────────────
		applyBtn = new FlxButton(cx + 16, cy + POPUP_H - 42, "Apply", function()
		{
			_applyChanges();
		});
		applyBtn.scrollFactor.set(); applyBtn.cameras = [camHUD]; add(applyBtn);

		closeBtn = new FlxButton(cx + POPUP_W - 100, cy + POPUP_H - 42, "Close", function()
		{
			_applyChanges(); close();
		});
		closeBtn.scrollFactor.set(); closeBtn.cameras = [camHUD]; add(closeBtn);
	}

	function _makeCharBtn(x:Float, y:Float, w:Int, h:Int, color:Int, label:String):FlxSprite
	{
		var bg = new FlxSprite(x, y).makeGraphic(w, h, color);
		bg.alpha = 0.85; bg.scrollFactor.set(); bg.cameras = [camHUD]; add(bg);

		var lbl = new FlxText(x, y + 2, w, label, 8);
		lbl.setFormat(Paths.font("vcr.ttf"), 8, TEXT_GRAY, CENTER);
		lbl.scrollFactor.set(); lbl.cameras = [camHUD]; add(lbl);

		return bg;
	}

	function _makeCharIcon(x:Float, y:Float, charId:String):FlxSprite
	{
		try
		{
			var icon = new HealthIcon(charId);
			icon.setPosition(x, y);
			icon.setGraphicSize(42, 42); icon.updateHitbox();
			icon.scrollFactor.set(); icon.cameras = [camHUD]; add(cast icon);
			return cast icon;
		}
		catch (_:Dynamic)
		{
			var ph = new FlxSprite(x, y).makeGraphic(42, 42, 0xFF333355);
			ph.scrollFactor.set(); ph.cameras = [camHUD]; add(ph);
			return ph;
		}
	}

	function _makeCharLabel(x:Float, y:Float, w:Int, charId:String):FlxText
	{
		var short = charId.length > 9 ? charId.substr(0, 8) + "." : charId;
		var t = new FlxText(x, y, w, short, 9);
		t.setFormat(Paths.font("vcr.ttf"), 9, ACCENT_CYAN, CENTER);
		t.scrollFactor.set(); t.cameras = [camHUD]; add(t);
		return t;
	}

	function _rebuildBpmChangeList(lx:Float, startY:Float):Void
	{
		bpmChangesList.clear();
		var maxVisible = 3;
		var start = bpmChangeScrollY;
		var end   = Math.min(start + maxVisible, bpmChangesData.length);

		for (i in start...Std.int(end))
		{
			var change = bpmChangesData[i];
			var rowY   = startY + (i - start) * 18;
			var row    = new FlxText(lx, rowY, 300,
				'#${i + 1}  @${Std.int(change.time)}ms  →  ${change.bpm} BPM', 10);
			row.setFormat(Paths.font("vcr.ttf"), 10, TEXT_GRAY, LEFT);
			row.scrollFactor.set(); row.cameras = [camHUD];
			bpmChangesList.add(row);
		}
	}

	// ── Apply all changes ──────────────────────────────────────────────────────

	function _applyChanges():Void
	{
		if (titleInput   != null && titleInput.text.length   > 0) _song.song   = titleInput.text.trim();
		if (artistInput  != null)                                  _song.artist = artistInput.text.trim();
		if (bpmStepper   != null && bpmStepper.value > 0)         _song.bpm    = bpmStepper.value;
		if (speedStepper != null && speedStepper.value > 0)       _song.speed  = speedStepper.value;
		if (needsVoicesCheck != null)                              _song.needsVoices = needsVoicesCheck.checked;

		parent.showMessage('✅ Metadata saved', ACCENT_GREEN);
	}

	// ── Refresh character icons after picker selection ─────────────────────────

	public function refreshCharacterButtons():Void
	{
		_refreshCharIcon(charIconDad,  charLabelDad,  _song.player2   ?? "dad");
		_refreshCharIcon(charIconBF,   charLabelBF,   _song.player1   ?? "bf");
		_refreshCharIcon(charIconGF,   charLabelGF,   _song.gfVersion ?? "gf");
	}

	function _refreshCharIcon(iconSpr:FlxSprite, label:FlxText, charId:String):Void
	{
		try
		{
			var newIcon = new HealthIcon(charId);
			newIcon.setPosition(iconSpr.x, iconSpr.y);
			newIcon.setGraphicSize(42, 42); newIcon.updateHitbox();
			newIcon.scrollFactor.set(); newIcon.cameras = [camHUD];
			// Replace in group
			remove(iconSpr);
			add(cast newIcon);
		}
		catch (_:Dynamic) {}

		if (label != null)
		{
			var short = charId.length > 9 ? charId.substr(0, 8) + "." : charId;
			label.text = short;
		}
	}

	// ── Open / Close ─────────────────────────────────────────────────────────

	public function open():Void
	{
		isOpen  = true;
		visible = true;
		active  = true;

		// Refresh values from song
		if (titleInput   != null) titleInput.text   = _song.song    ?? "";
		if (artistInput  != null) artistInput.text  = _song.artist  ?? "";
		if (bpmStepper   != null) bpmStepper.value  = _song.bpm > 0 ? _song.bpm : 120;
		if (speedStepper != null) speedStepper.value = _song.speed > 0 ? _song.speed : 1.0;
		if (needsVoicesCheck != null) needsVoicesCheck.checked = _song.needsVoices;

		refreshCharacterButtons();

		// Seed BPM changes from song if empty
		if (bpmChangesData.length == 0)
			bpmChangesData = [{time: 0, bpm: _song.bpm > 0 ? _song.bpm : 120}];

		var cx = (FlxG.width  - POPUP_W) / 2.0;
		var cy = (FlxG.height - POPUP_H) / 2.0;
		_rebuildBpmChangeList(cx + 16, cy + 372);

		// Animate in
		overlay.alpha = 0;
		panel.alpha   = 0;
		FlxTween.cancelTweensOf(overlay);
		FlxTween.cancelTweensOf(panel);
		FlxTween.tween(overlay, {alpha: 0.65}, 0.18, {ease: FlxEase.quadOut});
		panel.y = cy + 24;
		FlxTween.tween(panel, {alpha: 1, y: cy}, 0.22, {ease: FlxEase.backOut});
	}

	public function close():Void
	{
		if (!isOpen && !visible) return;

		isOpen  = false;
		active  = false;

		if (!visible) { visible = false; return; }

		FlxTween.cancelTweensOf(overlay);
		FlxTween.cancelTweensOf(panel);
		FlxTween.tween(overlay, {alpha: 0}, 0.15, {ease: FlxEase.quadIn});
		var cy = (FlxG.height - POPUP_H) / 2.0;
		FlxTween.tween(panel, {alpha: 0, y: cy + 18}, 0.18, {
			ease: FlxEase.quadIn,
			onComplete: function(_) { visible = false; }
		});
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		if (!isOpen) return;
		super.update(elapsed);

		if (_inlineCharPicker.isOpen) return;

		if (FlxG.keys.justPressed.ESCAPE) { _applyChanges(); close(); return; }

		var cx = (FlxG.width  - POPUP_W) / 2.0;
		var cy = (FlxG.height - POPUP_H) / 2.0;
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		// Close on click outside
		if (FlxG.mouse.justPressed)
		{
			if (mx < cx || mx > cx + POPUP_W || my < cy || my > cy + POPUP_H)
			{
				_applyChanges(); close(); return;
			}

			// Character button clicks (V-Slice style: open inline picker)
			var lx = cx + 16.0;
			var charBtnY = cy + 290.0; // approximate Y of character buttons
			var charBtnH = 66;

			var charSlots = [
				{field: "player2",   bx: lx,           charBtnW: 110},
				{field: "player1",   bx: lx + 125.0,   charBtnW: 110},
				{field: "gfVersion", bx: lx + 250.0,   charBtnW: 110}
			];
			for (slot in charSlots)
			{
				if (mx >= slot.bx && mx <= slot.bx + slot.charBtnW
				 && my >= charBtnY && my <= charBtnY + charBtnH)
				{
					_pickerTargetField = slot.field;
					var currentId = switch (slot.field)
					{
						case "player1":   _song.player1   ?? "bf";
						case "gfVersion": _song.gfVersion ?? "gf";
						default:          _song.player2   ?? "dad";
					};
					_inlineCharPicker.openAt(slot.bx + slot.charBtnW / 2, charBtnY + charBtnH, currentId, slot.field);
					return;
				}
			}
		}

		// BPM changes list scroll
		var bpmListY0 = cy + 368;
		var bpmListY1 = bpmListY0 + 54;
		if (FlxG.mouse.wheel != 0 && mx >= cx + 16 && mx <= cx + 16 + 300
		 && my >= bpmListY0 && my <= bpmListY1)
		{
			bpmChangeScrollY -= FlxG.mouse.wheel;
			bpmChangeScrollY  = Std.int(Math.max(0, Math.min(bpmChangeScrollY, bpmChangesData.length - 1)));
			_rebuildBpmChangeList(cx + 16, bpmListY0);
		}
	}
}


// ============================================================================
//  InlineCharacterPicker
//  Minimal floating picker triggered from within MetaPopup's character buttons.
//  Updates player1 / player2 / gfVersion fields directly.
// ============================================================================
class InlineCharacterPicker extends FlxGroup
{
	var parent:ChartingState;
	var _song:SwagSong;
	var camHUD:FlxCamera;
	var metaPopup:MetaPopup;

	public var isOpen:Bool = false;
	var _targetField:String = "player1";
	var _currentId:String   = "";

	static inline var MENU_W:Int   = 420;
	static inline var MENU_H:Int   = 320;
	static inline var COLS:Int     = 5;
	static inline var CELL_W:Int   = 70;
	static inline var CELL_H:Int   = 70;
	static inline var HEADER_H:Int = 52;
	static inline var FOOTER_H:Int = 30;

	static inline var BG_PANEL:Int    = 0xFF0D0D1F;
	static inline var ACCENT_CYAN:Int = 0xFF00D9FF;
	static inline var ACCENT_ERR:Int  = 0xFFFF3366;
	static inline var TEXT_GRAY:Int   = 0xFFAAAAAA;

	var overlay:FlxSprite;
	var panel:FlxSprite;
	var titleText:FlxText;
	var hoverLabel:FlxText;
	var closeXSpr:FlxSprite;
	var closeXTxt:FlxText;

	var tabBtns:Array<{spr:FlxSprite, txt:FlxText, filter:String}> = [];
	var activeFilter:String = "ALL";

	var charIcons:FlxTypedGroup<FlxSprite>;
	var charLabels:FlxTypedGroup<FlxText>;
	var charHitboxes:Array<{x:Float, y:Float, id:String}> = [];

	var gridScrollY:Float    = 0;
	var gridMaxScrollY:Float = 0;
	var gridAreaH:Float      = MENU_H - HEADER_H - FOOTER_H;

	var _panelX:Float = 0;
	var _panelY:Float = 0;

	public function new(parent:ChartingState, song:SwagSong, camHUD:FlxCamera, metaPopup:MetaPopup)
	{
		super();
		this.parent    = parent;
		this._song     = song;
		this.camHUD    = camHUD;
		this.metaPopup = metaPopup;

		charIcons  = new FlxTypedGroup<FlxSprite>();
		charLabels = new FlxTypedGroup<FlxText>();

		_buildStaticUI();
		add(charIcons);
		add(charLabels);
		close();
	}

	function _buildStaticUI():Void
	{
		overlay = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0x88000000);
		overlay.alpha = 0; overlay.scrollFactor.set(); overlay.cameras = [camHUD]; add(overlay);

		panel = new FlxSprite(0, 0).makeGraphic(MENU_W, MENU_H, BG_PANEL);
		panel.scrollFactor.set(); panel.cameras = [camHUD]; add(panel);

		var tbar = new FlxSprite(0, 0).makeGraphic(MENU_W, 3, ACCENT_CYAN);
		tbar.scrollFactor.set(); tbar.cameras = [camHUD]; add(tbar);

		titleText = new FlxText(0, 0, MENU_W - 30, "Select Character", 13);
		titleText.setFormat(Paths.font("vcr.ttf"), 13, ACCENT_CYAN, LEFT);
		titleText.scrollFactor.set(); titleText.cameras = [camHUD]; add(titleText);

		var filters = ["ALL",    "Player",  "Opponent",  "GF"];
		var tcolors = [0xFF00D9FF, 0xFF00AAFF, 0xFFFF5555, 0xFFFF99EE];
		for (i in 0...filters.length)
		{
			var tbg = new FlxSprite(0, 0).makeGraphic(74, 20, 0xFF111133);
			tbg.scrollFactor.set(); tbg.cameras = [camHUD]; add(tbg);
			var ttxt = new FlxText(0, 0, 74, filters[i], 9);
			ttxt.setFormat(Paths.font("vcr.ttf"), 9, tcolors[i], CENTER);
			ttxt.scrollFactor.set(); ttxt.cameras = [camHUD]; add(ttxt);
			tabBtns.push({spr: tbg, txt: ttxt, filter: filters[i]});
		}

		hoverLabel = new FlxText(0, 0, MENU_W - 30, "(hover)", 10);
		hoverLabel.setFormat(Paths.font("vcr.ttf"), 10, TEXT_GRAY, LEFT);
		hoverLabel.scrollFactor.set(); hoverLabel.cameras = [camHUD]; add(hoverLabel);

		closeXSpr = new FlxSprite(0, 0).makeGraphic(22, 22, 0xFF1A0000);
		closeXSpr.scrollFactor.set(); closeXSpr.cameras = [camHUD]; add(closeXSpr);
		closeXTxt = new FlxText(0, 0, 22, "×", 15);
		closeXTxt.setFormat(Paths.font("vcr.ttf"), 15, ACCENT_ERR, CENTER);
		closeXTxt.scrollFactor.set(); closeXTxt.cameras = [camHUD]; add(closeXTxt);
	}

	function _reposition():Void
	{
		var px = _panelX; var py = _panelY;
		panel.setPosition(px, py);
		var tbarSpr:FlxSprite = cast members[2]; tbarSpr.setPosition(px, py);
		titleText.setPosition(px + 10, py + 6);
		for (i in 0...tabBtns.length)
		{
			tabBtns[i].spr.setPosition(px + 8 + i * 78, py + 28);
			tabBtns[i].txt.setPosition(px + 8 + i * 78, py + 32);
		}
		closeXSpr.setPosition(px + MENU_W - 26, py + 4);
		closeXTxt.setPosition(px + MENU_W - 26, py + 4);
		hoverLabel.setPosition(px + 8, py + MENU_H - FOOTER_H + 6);
		gridAreaH = MENU_H - HEADER_H - FOOTER_H;
	}

	function _rebuildGrid():Void
	{
		charIcons.clear(); charLabels.clear(); charHitboxes = [];
		CharacterList.init();

		var chars:Array<String> = switch (activeFilter)
		{
			case "Player":   CharacterList.boyfriends.copy();
			case "Opponent": CharacterList.opponents.copy();
			case "GF":       CharacterList.girlfriends.copy();
			default:         CharacterList.getAllCharacters();
		};
		chars.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
		chars.insert(0, "");

		var rows = Math.ceil(chars.length / COLS);
		gridMaxScrollY = Math.max(0, rows * CELL_H - gridAreaH);
		if (gridScrollY > gridMaxScrollY) gridScrollY = gridMaxScrollY;

		var gx0 = _panelX + 6.0;
		var gy0 = _panelY + HEADER_H;
		var gy1 = _panelY + MENU_H - FOOTER_H;

		for (i in 0...chars.length)
		{
			var id  = chars[i];
			var col = i % COLS;
			var row = Math.floor(i / COLS);
			var cx  = gx0 + col * CELL_W;
			var cy  = gy0 + row * CELL_H - gridScrollY;

			if (cy + CELL_H < gy0 || cy > gy1) continue;

			var isSel = (id == _currentId);
			var bg = new FlxSprite(cx, cy).makeGraphic(CELL_W - 2, CELL_H - 2, isSel ? 0xFF0A2A3A : 0xFF0A0A1A);
			bg.scrollFactor.set(); bg.cameras = [camHUD]; charIcons.add(bg);

			if (isSel)
			{
				var accent = new FlxSprite(cx, cy).makeGraphic(CELL_W - 2, 2, ACCENT_CYAN);
				accent.scrollFactor.set(); accent.cameras = [camHUD]; charIcons.add(accent);
			}

			if (id != "")
			{
				try
				{
					var icon = new HealthIcon(id);
					icon.setPosition(cx + (CELL_W - 2 - 40) / 2, cy + 4);
					icon.setGraphicSize(40, 40); icon.updateHitbox();
					icon.scrollFactor.set(); icon.cameras = [camHUD]; charIcons.add(cast icon);
				}
				catch (_:Dynamic) {}
			}

			var short = id != "" ? (id.length > 7 ? id.substr(0, 6) + "." : id) : "None";
			var lbl = new FlxText(cx, cy + CELL_H - 16, CELL_W - 2, short, 8);
			lbl.setFormat(Paths.font("vcr.ttf"), 8, isSel ? ACCENT_CYAN : TEXT_GRAY, CENTER);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD]; charLabels.add(lbl);

			charHitboxes.push({x: cx, y: cy, id: id});
		}
	}

	function _refreshTabHighlights():Void
	{
		for (t in tabBtns)
		{
			var active = (t.filter == activeFilter);
			t.spr.color = active ? 0xFF1A3A5A : FlxColor.WHITE;
			t.spr.alpha  = active ? 1.0 : 0.45;
		}
	}

	public function openAt(anchorX:Float, anchorY:Float, currentId:String, field:String):Void
	{
		_currentId   = currentId;
		_targetField = field;
		activeFilter = "ALL";
		gridScrollY  = 0;

		_panelX = Math.max(4, Math.min(anchorX - MENU_W / 2, FlxG.width  - MENU_W - 4));
		_panelY = Math.max(4, Math.min(anchorY + 4,           FlxG.height - MENU_H - 4));

		_reposition();
		_rebuildGrid();
		_refreshTabHighlights();

		var fieldName = switch (field)
		{
			case "player1": "Player (BF)"; case "gfVersion": "Girlfriend (GF)"; default: "Opponent (Dad)";
		};
		titleText.text = 'Select $fieldName';

		isOpen = visible = active = true;

		overlay.alpha = 0;
		panel.alpha   = 0;
		FlxTween.cancelTweensOf(overlay);
		FlxTween.cancelTweensOf(panel);
		FlxTween.tween(overlay, {alpha: 0.4}, 0.12, {ease: FlxEase.quadOut});
		panel.y = _panelY + 14;
		FlxTween.tween(panel, {alpha: 1, y: _panelY}, 0.18, {ease: FlxEase.backOut});
	}

	public function close():Void { isOpen = visible = active = false; }

	override public function update(elapsed:Float):Void
	{
		if (!isOpen) return;
		super.update(elapsed);

		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		if (FlxG.mouse.wheel != 0 && mx >= _panelX && mx <= _panelX + MENU_W)
		{
			gridScrollY -= FlxG.mouse.wheel * 22;
			gridScrollY  = Math.max(0, Math.min(gridScrollY, gridMaxScrollY));
			_rebuildGrid();
		}

		var hovering = false;
		for (hb in charHitboxes)
		{
			if (mx >= hb.x && mx <= hb.x + CELL_W - 2 && my >= hb.y && my <= hb.y + CELL_H - 2)
			{
				hoverLabel.text = hb.id != "" ? '${CharacterList.getCharacterName(hb.id)} [${hb.id}]' : "None";
				hovering = true; break;
			}
		}
		if (!hovering) hoverLabel.text = _currentId != "" ? '${CharacterList.getCharacterName(_currentId)} [${_currentId}]' : "None";

		if (!FlxG.mouse.justPressed) return;

		if (FlxG.keys.justPressed.ESCAPE) { close(); return; }

		if (mx >= closeXSpr.x && mx <= closeXSpr.x + 22 && my >= closeXSpr.y && my <= closeXSpr.y + 22)
		{
			close(); return;
		}

		// Tabs
		for (t in tabBtns)
		{
			if (mx >= t.spr.x && mx <= t.spr.x + 74 && my >= t.spr.y && my <= t.spr.y + 20)
			{
				activeFilter = t.filter; gridScrollY = 0;
				_rebuildGrid(); _refreshTabHighlights(); return;
			}
		}

		// Click outside
		if (mx < _panelX || mx > _panelX + MENU_W || my < _panelY || my > _panelY + MENU_H)
		{
			close(); return;
		}

		// Character cell
		for (hb in charHitboxes)
		{
			if (mx >= hb.x && mx <= hb.x + CELL_W - 2 && my >= hb.y && my <= hb.y + CELL_H - 2)
			{
				_selectChar(hb.id); return;
			}
		}
	}

	function _selectChar(charId:String):Void
	{
		switch (_targetField)
		{
			case "player1":   _song.player1   = charId;
			case "gfVersion": _song.gfVersion = charId;
			default:          _song.player2   = charId;
		}
		_currentId = charId;
		_rebuildGrid();
		metaPopup.refreshCharacterButtons();
		var name = charId != "" ? CharacterList.getCharacterName(charId) : "None";
		parent.showMessage('✅ ${_targetField} → "$name"', ACCENT_CYAN);
	}
}
