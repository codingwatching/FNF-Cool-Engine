package funkin.debug.charting;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.group.FlxGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.addons.ui.*;
import funkin.data.Song.SwagSong;
import funkin.data.Song.CharacterSlotData;
import funkin.data.Song.StrumsGroupData;
import funkin.gameplay.objects.character.HealthIcon;
import funkin.gameplay.objects.character.CharacterList;

using StringTools;

// ============================================================================
//  CharacterIconRow — fila de iconos encima del grid
//  Click en un icono → abre CharacterPickerMenu (estilo V-Slice)
//  Button "+" → modal for add character new
// ============================================================================
class CharacterIconRow extends FlxGroup
{
	var parent:ChartingState;
	var _song:SwagSong;
	var camHUD:FlxCamera;

	var iconSprites:FlxTypedGroup<FlxSprite>;
	var iconLabels:FlxTypedGroup<FlxText>;
	var iconHitboxes:Array<{x:Float, y:Float, w:Float, h:Float, index:Int}>;

	var addCharBtn:FlxSprite;
	var addCharBtnText:FlxText;

	var rowY:Float     = 30;
	var iconSize:Int   = 38;
	var iconSpacing:Int = 66;
	var gridX:Float;

	var _rowScrollX:Float   = 0;
	var _rowMaxScroll:Float = 0;
	var _rowAreaW:Float     = 0;

	// V-Slice style character picker
	public var charPickerMenu:CharacterPickerMenu;
	// Properties panel (pos/scale/flip/strumsGroup)
	public var charPropsPanel:CharacterPropertiesPanel;

	public var addCharModalOpen:Bool = false;

	static inline var ACCENT_GREEN:Int = 0xFF00FF88;
	static inline var ACCENT_CYAN:Int  = 0xFF00D9FF;
	static inline var TEXT_GRAY:Int    = 0xFFAAAAAA;

	public static var CHAR_TYPES:Array<String> = ["Opponent", "Player", "Girlfriend", "Other"];

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new(parent:ChartingState, song:SwagSong, camHUD:FlxCamera, gridX:Float)
	{
		super();
		this.parent  = parent;
		this._song   = song;
		this.camHUD  = camHUD;
		this.gridX   = gridX;
		iconHitboxes = [];

		iconSprites = new FlxTypedGroup<FlxSprite>();
		iconLabels  = new FlxTypedGroup<FlxText>();
		add(iconSprites);
		add(iconLabels);

		charPickerMenu = new CharacterPickerMenu(parent, song, camHUD, this);
		add(charPickerMenu);

		charPropsPanel = new CharacterPropertiesPanel(parent, song, camHUD, this);
		add(charPropsPanel);

		// "+" button
		addCharBtn = new FlxSprite(0, rowY).makeGraphic(28, 28, 0xFF1A3A2A);
		addCharBtn.scrollFactor.set(); addCharBtn.cameras = [camHUD]; add(addCharBtn);

		addCharBtnText = new FlxText(0, rowY + 2, 28, "+", 16);
		addCharBtnText.setFormat(Paths.font("vcr.ttf"), 16, ACCENT_GREEN, CENTER);
		addCharBtnText.scrollFactor.set(); addCharBtnText.cameras = [camHUD]; add(addCharBtnText);

		refreshIcons();
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	public function isAnyModalOpen():Bool
		return addCharModalOpen
		    || (charPickerMenu != null && (charPickerMenu.isOpen || charPickerMenu._justClosed))
		    || (charPropsPanel != null && (charPropsPanel.isOpen || charPropsPanel._justClosed));

	// ── Rebuild icon sprites ──────────────────────────────────────────────────

	public function refreshIcons():Void
	{
		iconSprites.clear();
		iconLabels.clear();
		iconHitboxes = [];

		var chars = (_song.characters != null) ? _song.characters : [];
		_rowAreaW   = FlxG.width - 340 - gridX;
		if (_rowAreaW < 100) _rowAreaW = 100;

		var totalRowW:Float = chars.length * iconSpacing + 36;
		_rowMaxScroll = Math.max(0, totalRowW - _rowAreaW);
		_rowScrollX   = Math.min(_rowScrollX, _rowMaxScroll);
		if (_rowScrollX < 0) _rowScrollX = 0;

		var currentX:Float = gridX - _rowScrollX;

		for (i in 0...chars.length)
		{
			var char        = chars[i];
			var typeBg      = _typeColor(char.type);
			var iconScreenX = currentX;
			var inView = (iconScreenX + iconSize >= gridX) && (iconScreenX <= gridX + _rowAreaW);

			if (inView)
			{
				var bg = new FlxSprite(iconScreenX, rowY).makeGraphic(iconSize, iconSize, typeBg);
				bg.alpha = 0.85; bg.scrollFactor.set(); bg.cameras = [camHUD]; iconSprites.add(bg);

				try
				{
					var icon = new HealthIcon(char.name);
					icon.setPosition(iconScreenX + 2, rowY + 2);
					icon.setGraphicSize(iconSize - 4, iconSize - 4);
					icon.updateHitbox(); icon.scrollFactor.set(); icon.cameras = [camHUD];
					iconSprites.add(cast icon);
				}
				catch (_:Dynamic)
				{
					var ph = new FlxSprite(iconScreenX + 6, rowY + 6).makeGraphic(iconSize - 12, iconSize - 12, 0xFF444466);
					ph.scrollFactor.set(); ph.cameras = [camHUD]; iconSprites.add(ph);
				}

				var nameLabel = new FlxText(iconScreenX, rowY + iconSize + 2, iconSize, char.name, 8);
				nameLabel.setFormat(Paths.font("vcr.ttf"), 8, TEXT_GRAY, CENTER);
				nameLabel.scrollFactor.set(); nameLabel.cameras = [camHUD]; iconLabels.add(nameLabel);

				if (char.strumsGroup != null && char.strumsGroup.length > 0)
				{
					var sgLabel = new FlxText(iconScreenX, rowY - 11, iconSize, char.strumsGroup, 7);
					sgLabel.setFormat(Paths.font("vcr.ttf"), 7, ACCENT_CYAN, CENTER);
					sgLabel.scrollFactor.set(); sgLabel.cameras = [camHUD]; iconLabels.add(sgLabel);
				}
			}

			iconHitboxes.push({x: iconScreenX, y: rowY, w: Std.int(iconSize), h: Std.int(iconSize), index: i});
			currentX += iconSpacing;
		}

		addCharBtn.x     = currentX + 4; addCharBtn.y     = rowY + 5;
		addCharBtnText.x = currentX + 4; addCharBtnText.y = rowY + 7;
		var btnInView = (addCharBtn.x >= gridX) && (addCharBtn.x <= gridX + _rowAreaW + 60);
		addCharBtn.visible = btnInView; addCharBtnText.visible = btnInView;
	}

	function _typeColor(type:String):Int
	{
		return switch (type)
		{
			case "Player":     0xFF002233;
			case "Girlfriend": 0xFF220022;
			case "Other":      0xFF222200;
			default:           0xFF220000;
		};
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (charPickerMenu.isOpen || charPropsPanel.isOpen) return;

		var my = FlxG.mouse.y;
		var mx = FlxG.mouse.x;
		var onRow  = (my >= rowY - 14) && (my <= rowY + iconSize + 18);
		var onGrid = (mx >= gridX)     && (mx <= gridX + _rowAreaW);

		if (onRow && onGrid && FlxG.keys.pressed.CONTROL && FlxG.mouse.wheel != 0)
		{
			_rowScrollX -= FlxG.mouse.wheel * iconSpacing;
			_rowScrollX  = Math.max(0, Math.min(_rowScrollX, _rowMaxScroll));
			refreshIcons();
			// ← Marcar que la rueda fue consumida por este componente para que
			//   ChartingState no haga scroll of the grid also.
			parent.wheelConsumed = true;
			return;
		}

		if (!FlxG.mouse.justPressed) return;

		// "+" button
		if (FlxG.mouse.overlaps(addCharBtn, camHUD) && addCharBtn.visible)
		{
			_openAddCharModal(); return;
		}

		// Click on existing icon → V-Slice picker
		for (hb in iconHitboxes)
		{
			if (mx >= hb.x && mx <= hb.x + hb.w && my >= hb.y && my <= hb.y + hb.h)
			{
				charPickerMenu.openForCharacter(hb.index, mx, my);
				return;
			}
		}
	}

	// ── Add character modal ───────────────────────────────────────────────────

	function _openAddCharModal():Void
	{
		addCharModalOpen = true;
		var cx = FlxG.width  / 2 - 200.0;
		var cy = FlxG.height / 2 - 140.0;

		var panelBg = new FlxSprite(cx, cy).makeGraphic(400, 280, 0xFF0D0D1F);
		panelBg.scrollFactor.set(); panelBg.cameras = [camHUD];
		var topBar = new FlxSprite(cx, cy).makeGraphic(400, 3, ACCENT_CYAN);
		topBar.scrollFactor.set(); topBar.cameras = [camHUD];
		var title = new FlxText(cx + 10, cy + 10, 380, "Add Character", 14);
		title.setFormat(Paths.font("vcr.ttf"), 14, ACCENT_CYAN, LEFT);
		title.scrollFactor.set(); title.cameras = [camHUD];

		var nameLabel = new FlxText(cx + 10, cy + 38, 0, "Name:", 10);
		nameLabel.setFormat(Paths.font("vcr.ttf"), 10, TEXT_GRAY, LEFT);
		nameLabel.scrollFactor.set(); nameLabel.cameras = [camHUD];
		var nameInput = new FlxUIInputText(cx + 10, cy + 52, 175, "bf", 12);
		nameInput.scrollFactor.set(); nameInput.cameras = [camHUD];

		var typeLabel = new FlxText(cx + 210, cy + 38, 0, "Type:", 10);
		typeLabel.setFormat(Paths.font("vcr.ttf"), 10, TEXT_GRAY, LEFT);
		typeLabel.scrollFactor.set(); typeLabel.cameras = [camHUD];
		var typeDropDown = new FlxUIDropDownMenu(cx + 210, cy + 52,
			FlxUIDropDownMenu.makeStrIdLabelArray(CHAR_TYPES, true), function(_) {});
		typeDropDown.scrollFactor.set(); typeDropDown.cameras = [camHUD];

		var strumsCheck = new FlxUICheckBox(cx + 10, cy + 95, null, null,
			"Create new StrumsGroup (adds 4 columns to grid)", 360);
		strumsCheck.checked = true; strumsCheck.scrollFactor.set(); strumsCheck.cameras = [camHUD];

		var strumsIdLabel = new FlxText(cx + 10, cy + 120, 0, "StrumsGroup ID:", 10);
		strumsIdLabel.setFormat(Paths.font("vcr.ttf"), 10, TEXT_GRAY, LEFT);
		strumsIdLabel.scrollFactor.set(); strumsIdLabel.cameras = [camHUD];

		var nextId = (_song.strumsGroups != null) ? _song.strumsGroups.length : 2;
		var strumsIdInput = new FlxUIInputText(cx + 10, cy + 134, 180, "strums_" + nextId, 11);
		strumsIdInput.scrollFactor.set(); strumsIdInput.cameras = [camHUD];
		var cpuCheck = new FlxUICheckBox(cx + 210, cy + 134, null, null, "CPU", 100);
		cpuCheck.checked = true; cpuCheck.scrollFactor.set(); cpuCheck.cameras = [camHUD];

		var hint = new FlxText(cx + 10, cy + 158, 380,
			"Notes in this StrumsGroup will trigger this character's sing animation.", 9);
		hint.setFormat(Paths.font("vcr.ttf"), 9, 0xFF445566, LEFT);
		hint.scrollFactor.set(); hint.cameras = [camHUD];

		var allObjs:Array<Dynamic> = [panelBg, topBar, title, nameLabel, nameInput,
			typeLabel, typeDropDown, strumsCheck, strumsIdLabel, strumsIdInput, cpuCheck, hint];
		for (o in allObjs) parent.add(o);

		var cancelBtn:FlxButton  = null;
		var confirmBtn:FlxButton = null;

		function closeModal():Void
		{
			addCharModalOpen = false;
			for (o in allObjs) parent.remove(o);
			parent.remove(cancelBtn); parent.remove(confirmBtn);
		}

		cancelBtn  = new FlxButton(cx + 280, cy + 240, "Cancel", closeModal);
		cancelBtn.scrollFactor.set(); cancelBtn.cameras = [camHUD];

		confirmBtn = new FlxButton(cx + 10, cy + 240, "Add", function()
		{
			var charName = nameInput.text.trim();
			if (charName.length == 0) charName = "bf";

			var typeIdx = Std.parseInt(typeDropDown.selectedId);
			if (typeIdx == null || typeIdx < 0) typeIdx = 0;
			var charType = CHAR_TYPES[typeIdx];

			var groupId:String = strumsCheck.checked ? strumsIdInput.text.trim() : null;
			if (groupId != null && groupId.length == 0) groupId = "strums_" + nextId;

			var newChar:CharacterSlotData = {
				name: charName, x: 0, y: 0, visible: true, scale: 1.0,
				type: charType, strumsGroup: groupId
			};
			if (_song.characters == null) _song.characters = [];
			_song.characters.push(newChar);

			if (strumsCheck.checked && groupId != null)
			{
				if (_song.strumsGroups == null) _song.strumsGroups = [];
				var extraGroupX = 100.0 + (_song.strumsGroups.length * 4 * 120.0);
				var groupVisible = (charType != "Girlfriend");
				var newGroup:StrumsGroupData = {
					id: groupId, x: extraGroupX, y: 50,
					visible: groupVisible, cpu: cpuCheck.checked, spacing: 110
				};
				_song.strumsGroups.push(newGroup);
				parent.rebuildGrid();
				parent.showMessage('✅ "${charName}" [${charType}] + "${groupId}" created', ACCENT_GREEN);
			}
			else
			{
				refreshIcons();
				parent.showMessage('✅ "${charName}" [${charType}] added', ACCENT_GREEN);
			}
			closeModal();
		});
		confirmBtn.scrollFactor.set(); confirmBtn.cameras = [camHUD];

		parent.add(cancelBtn); parent.add(confirmBtn);
	}
}


// ============================================================================
//  CharacterPickerMenu  — V-Slice style scrollable character icon grid
//
//  • Filter tabs: ALL / Player / Opponent / GF
//  • HealthIcon + short name per cell
//  • Hover → full name in bottom label
//  • Click "Properties" → opens CharacterPropertiesPanel
//  • Click outside / ESC → close
//  • Animate in: overlay fade + panel slide-up
// ============================================================================
class CharacterPickerMenu extends FlxGroup
{
	var parent:ChartingState;
	var _song:SwagSong;
	var camHUD:FlxCamera;
	public var iconRow:CharacterIconRow;

	public var isOpen:Bool = false;
	var editingIndex:Int = -1;

	/**
	 * `true` durante the frame inmediatamente posterior to the cierre of the menu.
	 * Avoids that the click that cerró the panel "is filtre" to the grid of fondo.
	 * Se resetea al inicio del siguiente update().
	 */
	public var _justClosed:Bool = false;

	// ── Layout ────────────────────────────────────────────────────────────────
	static inline var MENU_W:Int    = 460;
	static inline var MENU_H:Int    = 380;
	static inline var COLS:Int      = 5;
	static inline var CELL_W:Int    = 76;
	static inline var CELL_H:Int    = 76;
	static inline var HEADER_H:Int  = 60;
	static inline var FOOTER_H:Int  = 36;

	static inline var BG_PANEL:Int      = 0xFF0D0D1F;
	static inline var ACCENT_CYAN:Int   = 0xFF00D9FF;
	static inline var ACCENT_GREEN:Int  = 0xFF00FF88;
	static inline var ACCENT_ERR:Int    = 0xFFFF3366;
	static inline var TEXT_GRAY:Int     = 0xFFAAAAAA;

	// ── Elements ──────────────────────────────────────────────────────────────
	var overlay:FlxSprite;
	var panel:FlxSprite;
	var topBar:FlxSprite;
	var titleText:FlxText;
	var hoverLabel:FlxText;
	var propsBtn:FlxSprite;
	var propsBtnTxt:FlxText;
	var closeXBtn:FlxSprite;
	var closeXTxt:FlxText;

	var tabBtns:Array<{spr:FlxSprite, txt:FlxText, filter:String}> = [];
	var activeFilter:String = "ALL";

	var charIcons:FlxTypedGroup<FlxSprite>;
	var charLabels:FlxTypedGroup<FlxText>;
	var charHitboxes:Array<{x:Float, y:Float, id:String}> = [];

	var gridScrollY:Float    = 0;
	var gridMaxScrollY:Float = 0;
	var gridAreaH:Float      = 0;

	var _panelX:Float  = 0;
	var _panelY:Float  = 0;
	var _currentId:String = "";

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new(parent:ChartingState, song:SwagSong, camHUD:FlxCamera, iconRow:CharacterIconRow)
	{
		super();
		this.parent  = parent;
		this._song   = song;
		this.camHUD  = camHUD;
		this.iconRow = iconRow;

		charIcons  = new FlxTypedGroup<FlxSprite>();
		charLabels = new FlxTypedGroup<FlxText>();

		_buildStaticUI();
		add(charIcons);
		add(charLabels);

		close();
	}

	// ── Static UI ─────────────────────────────────────────────────────────────

	function _buildStaticUI():Void
	{
		overlay = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xAA000000);
		overlay.alpha = 0; overlay.scrollFactor.set(); overlay.cameras = [camHUD]; add(overlay);

		panel = new FlxSprite(0, 0).makeGraphic(MENU_W, MENU_H, BG_PANEL);
		panel.scrollFactor.set(); panel.cameras = [camHUD]; add(panel);

		topBar = new FlxSprite(0, 0).makeGraphic(MENU_W, 3, ACCENT_CYAN);
		topBar.scrollFactor.set(); topBar.cameras = [camHUD]; add(topBar);

		titleText = new FlxText(0, 0, MENU_W - 30, "Select Character", 14);
		titleText.setFormat(Paths.font("vcr.ttf"), 14, ACCENT_CYAN, LEFT);
		titleText.scrollFactor.set(); titleText.cameras = [camHUD]; add(titleText);

		// Tabs: ALL / Player / Opponent / GF
		var filters = ["ALL",       "Player",    "Opponent",  "GF"];
		var tcolors = [ACCENT_CYAN, 0xFF00AAFF,  0xFFFF5555,  0xFFFF99EE];
		for (i in 0...filters.length)
		{
			var tbg = new FlxSprite(0, 0).makeGraphic(80, 22, 0xFF111133);
			tbg.scrollFactor.set(); tbg.cameras = [camHUD]; add(tbg);
			var ttxt = new FlxText(0, 0, 80, filters[i], 10);
			ttxt.setFormat(Paths.font("vcr.ttf"), 10, tcolors[i], CENTER);
			ttxt.scrollFactor.set(); ttxt.cameras = [camHUD]; add(ttxt);
			tabBtns.push({spr: tbg, txt: ttxt, filter: filters[i]});
		}

		// Hover label
		hoverLabel = new FlxText(0, 0, MENU_W - 110, "(hover a character)", 11);
		hoverLabel.setFormat(Paths.font("vcr.ttf"), 11, TEXT_GRAY, LEFT);
		hoverLabel.scrollFactor.set(); hoverLabel.cameras = [camHUD]; add(hoverLabel);

		// "Properties" button
		propsBtn = new FlxSprite(0, 0).makeGraphic(94, 26, 0xFF0A2A1A);
		propsBtn.scrollFactor.set(); propsBtn.cameras = [camHUD]; add(propsBtn);
		propsBtnTxt = new FlxText(0, 0, 94, "⚙ Properties", 10);
		propsBtnTxt.setFormat(Paths.font("vcr.ttf"), 10, ACCENT_GREEN, CENTER);
		propsBtnTxt.scrollFactor.set(); propsBtnTxt.cameras = [camHUD]; add(propsBtnTxt);

		// Close "×"
		closeXBtn = new FlxSprite(0, 0).makeGraphic(24, 24, 0xFF1A0000);
		closeXBtn.scrollFactor.set(); closeXBtn.cameras = [camHUD]; add(closeXBtn);
		closeXTxt = new FlxText(0, 0, 24, "×", 16);
		closeXTxt.setFormat(Paths.font("vcr.ttf"), 16, ACCENT_ERR, CENTER);
		closeXTxt.scrollFactor.set(); closeXTxt.cameras = [camHUD]; add(closeXTxt);
	}

	// ── Reposition to _panelX/_panelY ─────────────────────────────────────────

	function _reposition():Void
	{
		var px = _panelX;
		var py = _panelY;

		panel.setPosition(px, py);
		topBar.setPosition(px, py);
		titleText.setPosition(px + 10, py + 8);

		for (i in 0...tabBtns.length)
		{
			tabBtns[i].spr.setPosition(px + 10 + i * 86, py + 28);
			tabBtns[i].txt.setPosition(px + 10 + i * 86, py + 32);
		}

		closeXBtn.setPosition(px + MENU_W - 28, py + 5);
		closeXTxt.setPosition(px + MENU_W - 28, py + 5);

		var bottomY = py + MENU_H - FOOTER_H + 4;
		hoverLabel.setPosition(px + 8, bottomY + 4);
		propsBtn.setPosition(px + MENU_W - 102, bottomY);
		propsBtnTxt.setPosition(px + MENU_W - 102, bottomY + 2);

		gridAreaH = MENU_H - HEADER_H - FOOTER_H;
	}

	// ── Character grid ────────────────────────────────────────────────────────

	function _rebuildGrid():Void
	{
		charIcons.clear();
		charLabels.clear();
		charHitboxes = [];

		CharacterList.init();
		var chars:Array<String> = switch (activeFilter)
		{
			case "Player":   CharacterList.boyfriends.copy();
			case "Opponent": CharacterList.opponents.copy();
			case "GF":       CharacterList.girlfriends.copy();
			default:         CharacterList.getAllCharacters();
		};
		chars.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
		chars.insert(0, ""); // "None" option

		var rows       = Math.ceil(chars.length / COLS);
		var totalH     = rows * CELL_H;
		gridMaxScrollY = Math.max(0, totalH - gridAreaH);
		if (gridScrollY > gridMaxScrollY) gridScrollY = gridMaxScrollY;

		var gx0 = _panelX + 10.0;
		var gy0 = _panelY + HEADER_H;
		var gy1 = _panelY + MENU_H - FOOTER_H;

		for (i in 0...chars.length)
		{
			var id   = chars[i];
			var col  = i % COLS;
			var row  = Math.floor(i / COLS);
			var cx   = gx0 + col * CELL_W;
			var cy   = gy0 + row * CELL_H - gridScrollY;

			if (cy + CELL_H < gy0 || cy > gy1) continue; // culled

			var isSelected = (id == _currentId);

			var cellBg = new FlxSprite(cx, cy).makeGraphic(CELL_W - 2, CELL_H - 2,
				isSelected ? 0xFF0A2A3A : 0xFF0A0A1A);
			cellBg.scrollFactor.set(); cellBg.cameras = [camHUD]; charIcons.add(cellBg);

			if (isSelected)
			{
				var topAccent = new FlxSprite(cx, cy).makeGraphic(CELL_W - 2, 2, ACCENT_CYAN);
				topAccent.scrollFactor.set(); topAccent.cameras = [camHUD]; charIcons.add(topAccent);
			}

			if (id != "")
			{
				try
				{
					var icon = new HealthIcon(id);
					icon.setPosition(cx + (CELL_W - 2 - 44) / 2, cy + 6);
					icon.setGraphicSize(44, 44); icon.updateHitbox();
					icon.scrollFactor.set(); icon.cameras = [camHUD];
					charIcons.add(cast icon);
				}
				catch (_:Dynamic)
				{
					var ph = new FlxSprite(cx + 18, cy + 10).makeGraphic(36, 36, 0xFF333355);
					ph.scrollFactor.set(); ph.cameras = [camHUD]; charIcons.add(ph);
				}
			}
			else
			{
				// "None" placeholder
				var noneTxt = new FlxText(cx, cy + 20, CELL_W - 2, "None", 11);
				noneTxt.setFormat(Paths.font("vcr.ttf"), 11, 0xFF555566, CENTER);
				noneTxt.scrollFactor.set(); noneTxt.cameras = [camHUD]; charLabels.add(noneTxt);
			}

			var shortId   = id != "" ? (id.length > 7 ? id.substr(0, 6) + "." : id) : "";
			var nameLbl   = new FlxText(cx, cy + CELL_H - 17, CELL_W - 2, shortId, 8);
			nameLbl.setFormat(Paths.font("vcr.ttf"), 8, isSelected ? ACCENT_CYAN : TEXT_GRAY, CENTER);
			nameLbl.scrollFactor.set(); nameLbl.cameras = [camHUD]; charLabels.add(nameLbl);

			charHitboxes.push({x: cx, y: cy, id: id});
		}
	}

	// ── Open / Close ──────────────────────────────────────────────────────────

	public function openForCharacter(index:Int, clickX:Float, clickY:Float):Void
	{
		if (_song.characters == null || index < 0 || index >= _song.characters.length) return;

		editingIndex = index;
		_currentId   = _song.characters[index].name ?? "";
		activeFilter = "ALL";
		gridScrollY  = 0;

		// Position near click, clamped to screen
		_panelX = Math.max(4, Math.min(clickX, FlxG.width  - MENU_W - 4));
		_panelY = Math.max(4, Math.min(clickY + 24, FlxG.height - MENU_H - 4));

		_reposition();
		_rebuildGrid();
		_refreshTabHighlights();

		titleText.text = 'Character #${index + 1}  ← ${_currentId != "" ? _currentId : "None"}';

		isOpen = visible = active = true;

		// Animate in
		overlay.alpha = 0;
		panel.alpha   = 0;
		FlxTween.cancelTweensOf(overlay);
		FlxTween.cancelTweensOf(panel);
		FlxTween.tween(overlay, {alpha: 0.55}, 0.14, {ease: FlxEase.quadOut});
		panel.y = _panelY + 18;
		FlxTween.tween(panel, {alpha: 1, y: _panelY}, 0.22, {ease: FlxEase.backOut});

		var els:Array<flixel.FlxBasic> = [topBar, titleText, hoverLabel, propsBtn, propsBtnTxt, closeXBtn, closeXTxt];
		for (t in tabBtns) { els.push(t.spr); els.push(t.txt); }
		for (el in els) (cast el : FlxSprite).alpha = 0;

		new flixel.util.FlxTimer().start(0.1, function(_)
		{
			for (el in els)
				FlxTween.tween(cast el, {alpha: 1}, 0.14, {ease: FlxEase.quadOut});
		});
	}

	public function close():Void
	{
		// FIX: no poner active=false here.
		// Si active=false, Flixel no llama update() → _justClosed nunca se resetea
		// → isAnyModalOpen() devuelve true para siempre → grid bloqueado permanentemente.
		// Dejamos active=true 1 frame more for that update() pueda clear _justClosed.
		isOpen   = false;
		visible  = false;
		// active queda true deliberadamente
		editingIndex = -1;
		_justClosed  = true;
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		if (_justClosed) { _justClosed = false; active = false; return; }
		if (!isOpen) { active = false; return; }
		super.update(elapsed);

		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		var gy0 = _panelY + HEADER_H;
		var gy1 = _panelY + MENU_H - FOOTER_H;

		// Scroll wheel — consumir el evento para que el grid de fondo NO lo procese
		if (mx >= _panelX && mx <= _panelX + MENU_W && my >= gy0 && my <= gy1 && FlxG.mouse.wheel != 0)
		{
			gridScrollY -= FlxG.mouse.wheel * 24;
			gridScrollY  = Math.max(0, Math.min(gridScrollY, gridMaxScrollY));
			_rebuildGrid();
			parent.wheelConsumed = true; // ← no filtrar al grid principal
		}

		// Hover label
		var hovering = false;
		for (hb in charHitboxes)
		{
			if (mx >= hb.x && mx <= hb.x + CELL_W - 2 && my >= hb.y && my <= hb.y + CELL_H - 2)
			{
				hoverLabel.text = hb.id != ""
					? '${CharacterList.getCharacterName(hb.id)} [${hb.id}]'
					: "None";
				hovering = true; break;
			}
		}
		if (!hovering)
		{
			hoverLabel.text = _currentId != ""
				? '${CharacterList.getCharacterName(_currentId)} [${_currentId}]'
				: "None";
		}

		if (!FlxG.mouse.justPressed) return;

		// ESC closes
		if (FlxG.keys.justPressed.ESCAPE) { close(); return; }

		// Close "×"
		if (mx >= closeXBtn.x && mx <= closeXBtn.x + 24 && my >= closeXBtn.y && my <= closeXBtn.y + 24)
		{
			close(); return;
		}

		// Properties button
		if (mx >= propsBtn.x && mx <= propsBtn.x + 94 && my >= propsBtn.y && my <= propsBtn.y + 26)
		{
			close();
			iconRow.charPropsPanel.openForCharacter(editingIndex);
			return;
		}

		// Tab buttons
		for (t in tabBtns)
		{
			if (mx >= t.spr.x && mx <= t.spr.x + 80 && my >= t.spr.y && my <= t.spr.y + 22)
			{
				activeFilter = t.filter;
				gridScrollY  = 0;
				_rebuildGrid();
				_refreshTabHighlights();
				return;
			}
		}

		// Click outside panel → close
		if (mx < _panelX || mx > _panelX + MENU_W || my < _panelY || my > _panelY + MENU_H)
		{
			close(); return;
		}

		// Click character cell
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
		if (editingIndex < 0 || _song.characters == null || editingIndex >= _song.characters.length) return;
		_song.characters[editingIndex].name = charId;
		_currentId = charId;
		titleText.text = 'Character #${editingIndex + 1}  ← ${charId != "" ? charId : "None"}';
		_rebuildGrid();

		var displayName = charId != "" ? CharacterList.getCharacterName(charId) : "None";
		parent.showMessage('✅ Character #${editingIndex + 1} → "$displayName"', ACCENT_CYAN);
		iconRow.refreshIcons();
	}

	function _refreshTabHighlights():Void
	{
		for (t in tabBtns)
		{
			var active = (t.filter == activeFilter);
			t.spr.color = active ? 0xFF1A3A5A : FlxColor.WHITE;
			t.spr.alpha  = active ? 1.0 : 0.5;
		}
	}
}


// ============================================================================
//  CharacterPropertiesPanel
//  Smaller floating panel for editing pos/scale/flip/visible/strumsGroup.
// ============================================================================
class CharacterPropertiesPanel extends FlxGroup
{
	var parent:ChartingState;
	var _song:SwagSong;
	var camHUD:FlxCamera;
	var iconRow:CharacterIconRow;

	public var isOpen:Bool = false;
	var editingIndex:Int = -1;
	/** Igual that in CharacterPickerMenu — avoids propagación of clicks to the grid. */
	public var _justClosed:Bool = false;

	static inline var PANEL_W:Int    = 420;
	static inline var PANEL_H:Int    = 310;
	static inline var BG_PANEL:Int   = 0xFF0D0D1F;
	static inline var ACCENT_CYAN:Int = 0xFF00D9FF;
	static inline var ACCENT_ERR:Int  = 0xFFFF3366;
	static inline var TEXT_GRAY:Int   = 0xFFAAAAAA;

	var overlay:FlxSprite;
	var panel:FlxSprite;
	var titleText:FlxText;
	var nameInput:FlxUIInputText;
	var typeDropDown:FlxUIDropDownMenu;
	var posXStepper:FlxUINumericStepper;
	var posYStepper:FlxUINumericStepper;
	var scaleStepper:FlxUINumericStepper;
	var visibleCheck:FlxUICheckBox;
	var flipCheck:FlxUICheckBox;
	var strumsGroupInput:FlxUIInputText;
	var applyBtn:FlxButton;
	var deleteBtn:FlxButton;
	var closeBtn:FlxButton;

	public function new(parent:ChartingState, song:SwagSong, camHUD:FlxCamera, iconRow:CharacterIconRow)
	{
		super();
		this.parent  = parent;
		this._song   = song;
		this.camHUD  = camHUD;
		this.iconRow = iconRow;
		_buildUI();
		close();
	}

	function _lbl(x:Float, y:Float, text:String):Void
	{
		var t = new FlxText(x, y, 0, text, 10);
		t.setFormat(Paths.font("vcr.ttf"), 10, TEXT_GRAY, LEFT);
		t.scrollFactor.set(); t.cameras = [camHUD]; add(t);
	}

	function _buildUI():Void
	{
		var cx = (FlxG.width  - PANEL_W) / 2.0;
		var cy = (FlxG.height - PANEL_H) / 2.0;

		overlay = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xAA000000);
		overlay.scrollFactor.set(); overlay.cameras = [camHUD]; add(overlay);

		panel = new FlxSprite(cx, cy).makeGraphic(PANEL_W, PANEL_H, BG_PANEL);
		panel.scrollFactor.set(); panel.cameras = [camHUD]; add(panel);

		var tbar = new FlxSprite(cx, cy).makeGraphic(PANEL_W, 4, ACCENT_CYAN);
		tbar.scrollFactor.set(); tbar.cameras = [camHUD]; add(tbar);

		titleText = new FlxText(cx + 15, cy + 12, PANEL_W, "Character Properties", 16);
		titleText.setFormat(Paths.font("vcr.ttf"), 16, ACCENT_CYAN, LEFT);
		titleText.scrollFactor.set(); titleText.cameras = [camHUD]; add(titleText);

		_lbl(cx + 15, cy + 44, "Name:");
		nameInput = new FlxUIInputText(cx + 15, cy + 58, 160, "bf", 12);
		nameInput.scrollFactor.set(); nameInput.cameras = [camHUD]; add(nameInput);

		_lbl(cx + 210, cy + 44, "Type:");
		typeDropDown = new FlxUIDropDownMenu(cx + 210, cy + 58,
			FlxUIDropDownMenu.makeStrIdLabelArray(CharacterIconRow.CHAR_TYPES, true), function(_) {});
		typeDropDown.scrollFactor.set(); typeDropDown.cameras = [camHUD];

		_lbl(cx + 15, cy + 96, "Strums Group ID:");
		strumsGroupInput = new FlxUIInputText(cx + 15, cy + 110, 200, "", 12);
		strumsGroupInput.scrollFactor.set(); strumsGroupInput.cameras = [camHUD]; add(strumsGroupInput);

		var hint = new FlxText(cx + 15, cy + 130, PANEL_W - 30,
			"Notes in this StrumsGroup make the character sing.", 9);
		hint.setFormat(Paths.font("vcr.ttf"), 9, 0xFF445566, LEFT);
		hint.scrollFactor.set(); hint.cameras = [camHUD]; add(hint);

		add(typeDropDown);

		_lbl(cx + 15,  cy + 154, "Pos X:");
		posXStepper = new FlxUINumericStepper(cx + 15,  cy + 168, 10, 0, -3000, 3000, 0);
		posXStepper.scrollFactor.set(); posXStepper.cameras = [camHUD]; add(posXStepper);

		_lbl(cx + 150, cy + 154, "Pos Y:");
		posYStepper = new FlxUINumericStepper(cx + 150, cy + 168, 10, 0, -3000, 3000, 0);
		posYStepper.scrollFactor.set(); posYStepper.cameras = [camHUD]; add(posYStepper);

		_lbl(cx + 285, cy + 154, "Scale:");
		scaleStepper = new FlxUINumericStepper(cx + 285, cy + 168, 0.1, 1.0, 0.1, 5.0, 1);
		scaleStepper.scrollFactor.set(); scaleStepper.cameras = [camHUD]; add(scaleStepper);

		visibleCheck = new FlxUICheckBox(cx + 15,  cy + 212, null, null, "Visible", 100);
		visibleCheck.checked = true;
		visibleCheck.scrollFactor.set(); visibleCheck.cameras = [camHUD]; add(visibleCheck);

		flipCheck = new FlxUICheckBox(cx + 120, cy + 212, null, null, "Flip X", 100);
		flipCheck.checked = false;
		flipCheck.scrollFactor.set(); flipCheck.cameras = [camHUD]; add(flipCheck);

		applyBtn  = new FlxButton(cx + 15,        cy + PANEL_H - 40, "Apply",  _applyChanges);
		deleteBtn = new FlxButton(cx + 115,        cy + PANEL_H - 40, "Delete", function() { _deleteCharacter(); close(); });
		closeBtn  = new FlxButton(cx + PANEL_W - 100, cy + PANEL_H - 40, "OK", function() { _applyChanges(); close(); });
		for (b in [applyBtn, deleteBtn, closeBtn])
		{
			b.scrollFactor.set(); b.cameras = [camHUD]; add(b);
		}
	}

	public function openForCharacter(index:Int):Void
	{
		if (_song.characters == null || index < 0 || index >= _song.characters.length) return;
		editingIndex = index;
		var char = _song.characters[index];

		if (nameInput        != null) nameInput.text        = char.name           ?? "bf";
		if (strumsGroupInput != null) strumsGroupInput.text = char.strumsGroup     ?? "";
		if (posXStepper      != null) posXStepper.value     = char.x              ?? 0;
		if (posYStepper      != null) posYStepper.value     = char.y              ?? 0;
		if (scaleStepper     != null) scaleStepper.value    = char.scale          ?? 1.0;
		if (visibleCheck     != null) visibleCheck.checked  = char.visible        ?? true;
		if (flipCheck        != null) flipCheck.checked     = char.flip           ?? false;

		if (typeDropDown != null)
		{
			var idx = CharacterIconRow.CHAR_TYPES.indexOf(char.type ?? "Opponent");
			if (idx < 0) idx = 0;
			typeDropDown.selectedId    = '$idx';
			typeDropDown.selectedLabel = CharacterIconRow.CHAR_TYPES[idx];
		}

		titleText.text = 'Properties — #${index + 1}: ${char.name}';

		isOpen = visible = active = true;

		overlay.alpha = 0;
		panel.alpha   = 0;
		var cy = (FlxG.height - PANEL_H) / 2.0;
		panel.y = cy + 20;
		FlxTween.tween(overlay, {alpha: 0.6},        0.16, {ease: FlxEase.quadOut});
		FlxTween.tween(panel,   {alpha: 1, y: cy},   0.22, {ease: FlxEase.backOut});
	}

	function _applyChanges():Void
	{
		if (editingIndex < 0 || _song.characters == null || editingIndex >= _song.characters.length) return;
		var char = _song.characters[editingIndex];

		if (nameInput != null && nameInput.text.length > 0) char.name = nameInput.text.trim();
		if (typeDropDown != null)
		{
			var idx = Std.parseInt(typeDropDown.selectedId);
			if (idx != null && idx >= 0) char.type = CharacterIconRow.CHAR_TYPES[idx];
		}
		if (strumsGroupInput != null)
		{
			var sg = strumsGroupInput.text.trim();
			char.strumsGroup = sg.length > 0 ? sg : null;
		}
		if (posXStepper  != null) char.x       = posXStepper.value;
		if (posYStepper  != null) char.y       = posYStepper.value;
		if (scaleStepper != null) char.scale   = scaleStepper.value;
		if (visibleCheck != null) char.visible = visibleCheck.checked;
		if (flipCheck    != null) char.flip    = flipCheck.checked;

		parent.showMessage('✅ Character #${editingIndex + 1} updated: ${char.name}', ACCENT_CYAN);
		if (iconRow != null) iconRow.refreshIcons();
	}

	function _deleteCharacter():Void
	{
		if (_song.characters == null || editingIndex < 0 || editingIndex >= _song.characters.length) return;
		var charData = _song.characters[editingIndex];
		var name = charData.name;
		var sgId = charData.strumsGroup;

		_song.characters.splice(editingIndex, 1);
		editingIndex = -1;

		var sgStillUsed = false;
		if (sgId != null && _song.characters != null)
			for (c in _song.characters) if (c.strumsGroup == sgId) { sgStillUsed = true; break; }

		if (!sgStillUsed && sgId != null && sgId.length > 0 && _song.strumsGroups != null)
		{
			for (i in 0..._song.strumsGroups.length)
			{
				if (_song.strumsGroups[i].id == sgId) { _song.strumsGroups.splice(i, 1); break; }
			}
			parent.rebuildGrid();
			parent.showMessage('🗑 "${name}" + StrumsGroup "${sgId}" deleted', ACCENT_ERR);
		}
		else
		{
			parent.showMessage('🗑 Character "${name}" deleted', ACCENT_ERR);
		}
		if (iconRow != null) iconRow.refreshIcons();
	}

	public function close():Void
	{
		// FIX: mismo que CharPickerMenu — no poner active=false hasta que
		// update() haya reseteado _justClosed.
		isOpen   = false;
		visible  = false;
		editingIndex = -1;
		_justClosed  = true;
	}

	override public function update(elapsed:Float):Void
	{
		if (_justClosed) { _justClosed = false; active = false; return; }
		if (!isOpen) { active = false; return; }
		super.update(elapsed);
		if (FlxG.keys.justPressed.ESCAPE) { _applyChanges(); close(); }
	}
}
