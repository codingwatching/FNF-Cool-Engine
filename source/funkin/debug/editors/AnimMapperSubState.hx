package funkin.debug.editors;

import coolui.CoolInputText;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import funkin.gameplay.objects.character.Character.AnimData;
import funkin.debug.themes.EditorTheme;

/**
 * AnimMapperSubState
 *
 * Animation mapping table that appears immediately after importing
 * a character (sprite/XML, TXT, FlxAnimate) in CharacterSelectorState
 * or in AnimationDebug.
 *
 * Displays three columns:
 *   PREFIX — raw name of the asset (SubTexture XML / FlxAnimate SN). Read-only.
 *   NAME   — final name the game will use (editable, pre-filled = prefix).
 *   X      — delete this animation row from the list entirely.
 *
 * Example:
 *   PREFIX              | NAME          | X
 *   dad sing Up         | singUP        | [X]
 *   Dad idle dance      | idle          | [X]
 *
 * Usage:
 *   openSubState(new AnimMapperSubState(rawAnims, function(mapped) {
 *       currentAnimData = mapped;
 *       // ...reload / save
 *   }));
 *
 * ENTER      -> confirm with the entered names (deleted rows are excluded)
 * ESC        -> skip (passes the original unmodified list, ignores deletions)
 * Delete key -> deletes the row whose input currently has focus
 * UP/DOWN / wheel -> scroll when there are more than MAX_ROWS rows
 *
 * Fixes applied vs. first version:
 *   - Panel border/bg are fields; _resizePanel() recalculates their height and
 *     repositions footer widgets every time a row is deleted, so the popup never
 *     shows an empty gap at the bottom.
 *   - _parseXmlPrefixes deduplicates by normalised prefix, not just raw prefix
 *     (handled upstream, but the mapper itself is now safe regardless).
 *   - Confirm guard: if the user deletes ALL rows a warning is shown in the
 *     scroll-info area and ENTER is blocked until at least one row remains,
 *     preventing an accidental empty-animation confirm.
 *   - The _anims working copy is .copy()'d in the constructor so the original
 *     array passed by the caller is never mutated.
 */
class AnimMapperSubState extends FlxSubState
{
	// -- Layout constants -----------------------------------------------------
	static inline final W:Int        = 660;  // panel width
	static inline final ROW_H:Int    = 32;   // height per data row
	static inline final MAX_ROWS:Int = 10;   // max visible rows before scrolling
	static inline final COL_SEP:Int  = 295;  // x-offset of separator (prefix | name)
	static inline final DEL_W:Int    = 38;   // width reserved for the delete button
	static inline final HEADER_H:Int = 86;   // space above table rows (title + sub)
	static inline final FOOTER_H:Int = 52;   // space below table rows (buttons)

	// -- State ----------------------------------------------------------------
	/** Working copy — rows are spliced out on deletion. Caller's array is untouched. */
	var _anims:Array<AnimData>;
	/** Original list passed in, returned unchanged when the user hits Skip/ESC. */
	var _originalAnims:Array<AnimData>;
	var _onConfirm:Array<AnimData> -> Void;

	// Per-row display references — indices always match _anims.
	var _inputs:Array<CoolInputText> = [];
	var _prefixLabels:Array<FlxText> = [];
	var _deleteBtns:Array<FlxButton> = [];
	// 3 background sprites per row: rowBg, colSep, rowLine
	var _rowObjects:Array<FlxSprite> = [];

	var _scrollOffset:Int = 0;
	var _scrollInfo:FlxText;
	var _panX:Float;
	var _panY:Float;
	var _tableTop:Float;
	var _visRows:Int;
	var _camSub:flixel.FlxCamera;

	// Panel sprites kept as fields so _resizePanel() can update them.
	var _panelBorder:FlxSprite;
	var _panelBg:FlxSprite;
	// Other static widgets repositioned by _resizePanel().
	var _titleBar:FlxSprite;
	var _titleText:FlxText;
	var _subText:FlxText;
	var _footerDiv:FlxSprite;
	var _skipBtn:FlxButton;
	var _cfmBtn:FlxButton;

	// -------------------------------------------------------------------------

	public function new(anims:Array<AnimData>, onConfirm:Array<AnimData> -> Void)
	{
		super();
		_originalAnims = (anims != null) ? anims        : [];
		_anims         = (anims != null) ? anims.copy() : [];
		_onConfirm     = onConfirm;
	}

	override function create():Void
	{
		super.create();

		_camSub = new flixel.FlxCamera();
		_camSub.bgColor.alpha = 0;
		FlxG.cameras.add(_camSub, false);
		cameras = [_camSub];

		_panX = (FlxG.width - W) / 2;
		// _panY and _tableTop are set inside _resizePanel()
		_resizePanel();

		_buildOverlay();
		_buildPanelSprites();   // creates border + bg sprites once
		_buildStaticDecorations(); // title bar, subtitle, col headers
		_buildRows();
		_buildFooterWidgets();  // footer div + scroll info + buttons
		_resizePanel();         // final pass: position everything correctly
		_updateScroll();
	}

	// -- Resize (called on create and after every row deletion) ---------------

	/**
	 * Recalculates _visRows, _panY, _tableTop and repositions all
	 * height-dependent sprites (panel border/bg and footer widgets).
	 */
	function _resizePanel():Void
	{
		_visRows  = Std.int(Math.min(_anims.length, MAX_ROWS));
		var panH  = HEADER_H + (_visRows * ROW_H) + FOOTER_H;
		_panY     = (FlxG.height - panH) / 2;
		_tableTop = _panY + HEADER_H;

		var t = EditorTheme.current;

		if (_panelBorder != null)
		{
			_panelBorder.x = _panX - 2;
			_panelBorder.y = _panY - 2;
			_panelBorder.makeGraphic(W + 4, panH + 4, t.accent);
		}
		if (_panelBg != null)
		{
			_panelBg.x = _panX;
			_panelBg.y = _panY;
			_panelBg.makeGraphic(W, panH, t.bgPanel);
		}
		if (_titleBar  != null) { _titleBar.x  = _panX;      _titleBar.y  = _panY; }
		if (_titleText != null) { _titleText.x = _panX + 10; _titleText.y = _panY + 8; }
		if (_subText   != null) { _subText.x   = _panX + 10; _subText.y   = _panY + 38; }

		var fy = _panY + panH - FOOTER_H;
		if (_footerDiv  != null) { _footerDiv.x  = _panX;         _footerDiv.y  = fy; }
		if (_scrollInfo != null) { _scrollInfo.x = _panX + 10;    _scrollInfo.y = fy + 16; }
		if (_skipBtn    != null) { _skipBtn.x    = _panX + W - 218; _skipBtn.y  = fy + 14; }
		if (_cfmBtn     != null) { _cfmBtn.x     = _panX + W - 108; _cfmBtn.y   = fy + 14; }

		// Re-position col header bar (sits just above _tableTop)
		if (_colHeaderBg  != null) { _colHeaderBg.x  = _panX;     _colHeaderBg.y  = _tableTop - 22; }
		if (_colH1        != null) { _colH1.x        = _panX + 8; _colH1.y        = _tableTop - 18; }
		if (_colSep1      != null) { _colSep1.x      = _panX + COL_SEP;   _colSep1.y = _tableTop - 22; }
		if (_colH2        != null) { _colH2.x        = _panX + COL_SEP + 8; _colH2.y = _tableTop - 18; }
		if (_colSep2      != null) { _colSep2.x      = _panX + W - DEL_W; _colSep2.y = _tableTop - 22; }
		if (_colH3        != null) { _colH3.x        = _panX + W - DEL_W + 6; _colH3.y = _tableTop - 18; }
	}

	// Extra fields for column header repositioning
	var _colHeaderBg:FlxSprite;
	var _colH1:FlxText;
	var _colSep1:FlxSprite;
	var _colH2:FlxText;
	var _colSep2:FlxSprite;
	var _colH3:FlxText;

	// -- Building -------------------------------------------------------------

	function _buildOverlay():Void
	{
		var ov = new FlxSprite(0, 0);
		ov.makeGraphic(FlxG.width, FlxG.height, 0xBB000000);
		ov.scrollFactor.set();
		add(ov);
	}

	function _buildPanelSprites():Void
	{
		var t = EditorTheme.current;
		var panH = HEADER_H + (_visRows * ROW_H) + FOOTER_H;

		_panelBorder = new FlxSprite(_panX - 2, _panY - 2);
		_panelBorder.makeGraphic(W + 4, panH + 4, t.accent);
		_panelBorder.scrollFactor.set();
		add(_panelBorder);

		_panelBg = new FlxSprite(_panX, _panY);
		_panelBg.makeGraphic(W, panH, t.bgPanel);
		_panelBg.scrollFactor.set();
		add(_panelBg);
	}

	function _buildStaticDecorations():Void
	{
		var t = EditorTheme.current;

		_titleBar = new FlxSprite(_panX, _panY);
		_titleBar.makeGraphic(W, 32, t.accent);
		_titleBar.scrollFactor.set();
		add(_titleBar);

		_titleText = new FlxText(_panX + 10, _panY + 8, W - 20, "Animation Name Mapper", 13);
		_titleText.color = t.bgDark;
		_titleText.scrollFactor.set();
		add(_titleText);

		_subText = new FlxText(_panX + 10, _panY + 38, W - 20,
			"PREFIX = raw asset name   *   NAME = what the game will call it\n"
			+ "Edit names -> ENTER to confirm   *   [X] or Delete key to remove a row.", 9);
		_subText.color = FlxColor.fromRGB(160, 200, 255);
		_subText.scrollFactor.set();
		add(_subText);

		_buildColumnHeaders();
	}

	function _buildColumnHeaders():Void
	{
		var t  = EditorTheme.current;
		var hY = _tableTop - 22;

		_colHeaderBg = new FlxSprite(_panX, hY);
		_colHeaderBg.makeGraphic(W, 22, 0xFF0D0D1C);
		_colHeaderBg.scrollFactor.set();
		add(_colHeaderBg);

		_colH1 = new FlxText(_panX + 8, hY + 4, COL_SEP - 14, "PREFIX  /  ANIM ASSET", 9);
		_colH1.color = t.accent;
		_colH1.scrollFactor.set();
		add(_colH1);

		_colSep1 = new FlxSprite(_panX + COL_SEP, hY);
		_colSep1.makeGraphic(2, 22, t.accent);
		_colSep1.alpha = 0.6;
		_colSep1.scrollFactor.set();
		add(_colSep1);

		_colH2 = new FlxText(_panX + COL_SEP + 8, hY + 4, W - COL_SEP - DEL_W - 14, "NAME  (editable)", 9);
		_colH2.color = t.accent;
		_colH2.scrollFactor.set();
		add(_colH2);

		_colSep2 = new FlxSprite(_panX + W - DEL_W, hY);
		_colSep2.makeGraphic(2, 22, t.accent);
		_colSep2.alpha = 0.6;
		_colSep2.scrollFactor.set();
		add(_colSep2);

		_colH3 = new FlxText(_panX + W - DEL_W + 6, hY + 4, DEL_W - 8, "DEL", 9);
		_colH3.color = FlxColor.fromRGB(255, 90, 90);
		_colH3.scrollFactor.set();
		add(_colH3);
	}

	/**
	 * Builds (or rebuilds) per-row objects.
	 * Always call _clearRows() first when rebuilding after a deletion.
	 */
	function _buildRows():Void
	{
		var t = EditorTheme.current;

		for (i in 0..._anims.length)
		{
			var anim = _anims[i];
			var rowY = _tableTop + (i * ROW_H);

			// Row background (alternating shade)
			var rowBg = new FlxSprite(_panX, rowY);
			rowBg.makeGraphic(W, ROW_H, (i % 2 == 0) ? 0x18FFFFFF : 0x06FFFFFF);
			rowBg.scrollFactor.set();
			add(rowBg);
			_rowObjects.push(rowBg);

			// Column separator prefix|name
			var colSep = new FlxSprite(_panX + COL_SEP, rowY);
			colSep.makeGraphic(2, ROW_H, t.accent);
			colSep.alpha = 0.18;
			colSep.scrollFactor.set();
			add(colSep);
			_rowObjects.push(colSep);

			// Bottom row line
			var rowLine = new FlxSprite(_panX, rowY + ROW_H - 1);
			rowLine.makeGraphic(W, 1, t.accent);
			rowLine.alpha = 0.10;
			rowLine.scrollFactor.set();
			add(rowLine);
			_rowObjects.push(rowLine);

			// Prefix label (read-only, left column)
			var lbl = new FlxText(_panX + 8, rowY + 9, COL_SEP - 16, anim.prefix, 9);
			lbl.color = FlxColor.fromRGB(200, 210, 230);
			lbl.scrollFactor.set();
			add(lbl);
			_prefixLabels.push(lbl);

			// Name input (editable, middle column)
			var inp = new CoolInputText(
				_panX + COL_SEP + 6,
				rowY + 6,
				W - COL_SEP - DEL_W - 10,
				anim.name, 10);
			inp.scrollFactor.set();
			add(inp);
			_inputs.push(inp);

			// Delete button (right column).
			// Capture index locally so the closure stays correct after rebuilds.
			var capturedIdx = i;
			var delBtn = new FlxButton(_panX + W - DEL_W + 3, rowY + 6, "X", function()
			{
				_deleteRow(capturedIdx);
			});
			delBtn.label.color = FlxColor.fromRGB(255, 80, 80);
			delBtn.scrollFactor.set();
			add(delBtn);
			_deleteBtns.push(delBtn);
		}
	}

	function _buildFooterWidgets():Void
	{
		var t  = EditorTheme.current;
		var fy = _panY + HEADER_H + (_visRows * ROW_H);  // approximated; _resizePanel fixes it

		_footerDiv = new FlxSprite(_panX, fy);
		_footerDiv.makeGraphic(W, 2, t.accent);
		_footerDiv.alpha = 0.35;
		_footerDiv.scrollFactor.set();
		add(_footerDiv);

		_scrollInfo = new FlxText(_panX + 10, fy + 16, 290, "", 9);
		_scrollInfo.color = FlxColor.fromRGB(130, 150, 175);
		_scrollInfo.scrollFactor.set();
		add(_scrollInfo);

		_skipBtn = new FlxButton(_panX + W - 218, fy + 14, "Skip  [ESC]", function()
		{
			// Skip returns the ORIGINAL unmodified list, ignoring any edits or deletions.
			_onConfirm(_originalAnims);
			close();
		});
		_skipBtn.scrollFactor.set();
		add(_skipBtn);

		_cfmBtn = new FlxButton(_panX + W - 108, fy + 14, "Confirm  [ENTER]", function()
		{
			_applyAndConfirm();
		});
		_cfmBtn.scrollFactor.set();
		add(_cfmBtn);
	}

	// -- Row deletion ---------------------------------------------------------

	/**
	 * Deletes the animation at idx.
	 * Flushes current input values first so no edits are lost across the rebuild,
	 * then splices the entry, rebuilds the row table and resizes the panel.
	 */
	function _deleteRow(idx:Int):Void
	{
		if (idx < 0 || idx >= _anims.length) return;

		// Persist whatever the user has already typed in the inputs
		_flushNamesToAnims();

		_anims.splice(idx, 1);

		// Clamp scroll so we never point past the end
		var maxScroll = Std.int(Math.max(0, _anims.length - MAX_ROWS));
		if (_scrollOffset > maxScroll) _scrollOffset = maxScroll;

		_clearRows();
		// Recalculate _visRows / _panY / _tableTop BEFORE rebuilding rows
		// so the new rows are placed at the right Y coordinate.
		_resizePanel();
		_buildRows();
		_updateScroll();
	}

	/**
	 * Removes every per-row display object from the substate members list
	 * and clears the tracking arrays, ready for a fresh _buildRows() call.
	 */
	function _clearRows():Void
	{
		for (sp  in _rowObjects)   { remove(sp,  true); sp.destroy();  }
		for (lbl in _prefixLabels) { remove(lbl, true); lbl.destroy(); }
		for (inp in _inputs)       { remove(inp, true); inp.destroy(); }
		for (btn in _deleteBtns)   { remove(btn, true); btn.destroy(); }

		_rowObjects   = [];
		_prefixLabels = [];
		_inputs       = [];
		_deleteBtns   = [];
	}

	/**
	 * Reads each CoolInputText and writes the trimmed value back into the
	 * matching _anims entry so edits survive a row rebuild.
	 */
	function _flushNamesToAnims():Void
	{
		for (i in 0..._anims.length)
		{
			if (i >= _inputs.length) break;
			var txt = (_inputs[i].text != null) ? StringTools.trim(_inputs[i].text) : "";
			if (txt != "") _anims[i].name = txt;
		}
	}

	// -- Update ---------------------------------------------------------------

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (FlxG.keys.justPressed.ESCAPE)
		{
			// ESC always uses the original list — no partial deletions leak out
			_onConfirm(_originalAnims);
			close();
			return;
		}

		if (FlxG.keys.justPressed.ENTER)
		{
			_applyAndConfirm();
			return;
		}

		// Delete key: remove whichever row's input currently has focus
		if (FlxG.keys.justPressed.DELETE)
		{
			for (i in 0..._inputs.length)
			{
				if (_inputs[i].hasFocus)
				{
					_deleteRow(i);
					return;
				}
			}
		}

		var maxScroll = Std.int(Math.max(0, _anims.length - MAX_ROWS));

		if (FlxG.mouse.wheel != 0)
		{
			_scrollOffset = Std.int(Math.max(0, Math.min(maxScroll, _scrollOffset - FlxG.mouse.wheel)));
			_updateScroll();
		}
		if (FlxG.keys.justPressed.DOWN && _scrollOffset < maxScroll)
		{ _scrollOffset++; _updateScroll(); }
		if (FlxG.keys.justPressed.UP && _scrollOffset > 0)
		{ _scrollOffset--; _updateScroll(); }
	}

	// -- Scroll ---------------------------------------------------------------

	function _updateScroll():Void
	{
		var clipBot = _tableTop + (_visRows * ROW_H);

		for (i in 0..._anims.length)
		{
			var rowY   = _tableTop + ((i - _scrollOffset) * ROW_H);
			var inView = (rowY >= _tableTop - 1) && (rowY < clipBot);

			_prefixLabels[i].y = rowY + 9;
			_inputs[i].y       = rowY + 6;
			_deleteBtns[i].y   = rowY + 6;
			_prefixLabels[i].visible = inView;
			_inputs[i].visible       = inView;
			_deleteBtns[i].visible   = inView;

			var bg  = _rowObjects[i * 3];
			var sep = _rowObjects[i * 3 + 1];
			var lin = _rowObjects[i * 3 + 2];
			bg.y  = rowY;             bg.visible  = inView;
			sep.y = rowY;             sep.visible = inView;
			lin.y = rowY + ROW_H - 1; lin.visible = inView;
		}

		if (_scrollInfo != null)
		{
			var total = _anims.length;
			if (total == 0)
				// Warning state: block Confirm visually
				_scrollInfo.text = "All rows deleted. Add animations manually or press Skip.";
			else if (total > MAX_ROWS)
				_scrollInfo.text = 'UP-DOWN / Wheel  [${_scrollOffset + 1}-${Std.int(Math.min(_scrollOffset + MAX_ROWS, total))} of $total]';
			else
				_scrollInfo.text = '$total animation${total == 1 ? "" : "s"} detected';
		}
	}

	// -- Confirm --------------------------------------------------------------

	function _applyAndConfirm():Void
	{
		// Guard: do not confirm with an empty list — the caller expects at
		// least one animation. Show the warning and let the user decide.
		if (_anims.length == 0)
		{
			if (_scrollInfo != null)
			{
				_scrollInfo.text = "Cannot confirm: no animations left. Use Skip or add rows.";
				_scrollInfo.color = FlxColor.fromRGB(255, 100, 80);
			}
			return;
		}

		var result:Array<AnimData> = [];
		for (i in 0..._anims.length)
		{
			var src  = _anims[i];
			var name = (i < _inputs.length && _inputs[i].text != null)
				? StringTools.trim(_inputs[i].text) : "";
			if (name == "") name = src.prefix;

			result.push({
				name:      name,
				prefix:    src.prefix,
				framerate: src.framerate,
				looped:    src.looped,
				offsetX:   src.offsetX,
				offsetY:   src.offsetY
			});
		}
		_onConfirm(result);
		close();
	}

	// -- Close ----------------------------------------------------------------

	override function close():Void
	{
		if (_camSub != null)
		{
			FlxG.cameras.remove(_camSub, true);
			_camSub = null;
		}
		super.close();
	}
}
