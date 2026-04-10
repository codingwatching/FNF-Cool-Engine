package funkin.debug.editors;

/**
 * SpriteEditorState — Sprite Sheet & XML Atlas Editor
 * ─────────────────────────────────────────────────────────────────────────────
 * A full-featured editor for Sparrow-format sprite atlases (PNG + XML).
 *
 * FEATURES
 *   • Load any PNG sprite sheet and its paired XML atlas
 *   • Visual canvas: pan (middle-mouse / hold space + drag), zoom (scroll wheel)
 *   • Transparent or solid background — colour and alpha fully adjustable
 *   • Frame outlines drawn for every SubTexture in the atlas
 *   • Click a frame on the canvas to select it; or pick from the list panel
 *   • Per-frame hitbox overlay (shows frameWidth × frameHeight logical bounds)
 *   • Toggle hitboxes globally or hide them for an individual frame
 *   • Editable frame fields: name, x/y/w/h on atlas, frameX/Y, frameW/H
 *   • Add new frames manually; delete existing ones
 *   • Export: save modified XML back to disk (or Save As to a new path)
 *   • Create XML from scratch for a sheet with no atlas
 *   • Theme-aware UI via EditorTheme
 *
 * CAMERA LAYOUT  (same pattern as AnimationDebug)
 *   camUI   → cameras[0], zoom 1, invisible — stable mouse coords
 *   camGame → canvas with the sprite sheet
 *   camHUD  → all UI panels / text
 *
 * NAVIGATION
 *   Middle-click drag / Space+drag  → pan canvas
 *   Scroll wheel                    → zoom canvas
 *   Click frame on canvas           → select frame
 *   ESC                             → back to EditorHubState
 *   Ctrl+S                          → quick-save XML
 *
 * ADDING TO EditorHubState
 *   1. Add "Sprite Editor" to EDITOR_NAMES, an icon to EDITOR_ICONS,
 *      0xFFFFAA00 to EDITOR_ACCENTS, and a description to EDITOR_DESCS.
 *   2. In _openEditor(), add a new case that calls:
 *        StateTransition.switchState(new funkin.debug.editors.SpriteEditorState());
 */

import coolui.CoolInputText;
import funkin.debug.EditorDialogs.UnsavedChangesDialog;
import coolui.CoolNumericStepper;
import coolui.CoolCheckBox;
import coolui.CoolTabMenu;
import coolui.CoolUIGroup;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import coolui.CoolButton;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;

import funkin.debug.themes.EditorTheme;
import funkin.states.MusicBeatState;
import funkin.transitions.StateTransition;

import haxe.Json;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

#if sys
import sys.FileSystem;
import sys.io.File;
import lime.ui.FileDialog;
#end

using StringTools;

// ─────────────────────────────────────────────────────────────────────────────
// Data types
// ─────────────────────────────────────────────────────────────────────────────

/** One SubTexture entry from a Sparrow XML atlas. */
typedef FrameData =
{
    var name:String;
    /** X position of this frame inside the sprite sheet image. */
    var x:Int;
    /** Y position of this frame inside the sprite sheet image. */
    var y:Int;
    /** Width of this frame inside the sprite sheet image. */
    var width:Int;
    /** Height of this frame inside the sprite sheet image. */
    var height:Int;
    /**
     * Horizontal offset applied when rendering (trim compensation).
     * Negative = the sprite was trimmed on the left by this many pixels.
     */
    @:optional var frameX:Int;
    /**
     * Vertical offset applied when rendering (trim compensation).
     * Negative = the sprite was trimmed on the top by this many pixels.
     */
    @:optional var frameY:Int;
    /** Original (un-trimmed) frame width.  0 means equal to `width`. */
    @:optional var frameWidth:Int;
    /** Original (un-trimmed) frame height. 0 means equal to `height`. */
    @:optional var frameHeight:Int;
    /** Whether this frame is stored rotated 90° clockwise in the sheet. */
    @:optional var rotated:Bool;
    /** Per-frame hitbox visibility override.  null = follow global toggle. */
    @:optional var hideHitbox:Bool;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main state
// ─────────────────────────────────────────────────────────────────────────────

class SpriteEditorState extends MusicBeatState
{
    // ── Cameras ───────────────────────────────────────────────────────────────
    var camUI:FlxCamera;
    var camGame:FlxCamera;
    var camHUD:FlxCamera;

    // ── Canvas state ──────────────────────────────────────────────────────────
    /** Checkerboard / solid background sprite rendered behind the sheet. */
    var _canvasBg:FlxSprite;
    /** The loaded sprite sheet image. */
    var _sheetSprite:FlxSprite;
    /** Outline sprites drawn over every frame rect (one per frame). */
    var _frameOutlines:FlxTypedGroup<FlxSprite>;
    /** Hitbox rectangle for every frame (frameWidth × frameHeight logical box). */
    var _hitboxes:FlxTypedGroup<FlxSprite>;
    /** Accent-coloured highlight drawn over the currently-selected frame. */
    var _selHighlight:FlxSprite;

    // Canvas transform
    var _zoom:Float       = 1.0;
    var _panX:Float       = 0.0;
    var _panY:Float       = 0.0;
    var _isPanning:Bool   = false;
    var _panStartMouseX:Float = 0;
    var _panStartMouseY:Float = 0;
    var _panStartPanX:Float   = 0;
    var _panStartPanY:Float   = 0;

    // ── Atlas data ────────────────────────────────────────────────────────────
    /** All frames currently loaded / edited. */
    var _frames:Array<FrameData> = [];
    /** Path to the loaded PNG file on disk. */
    var _pngPath:String  = "";
    /** Path to the loaded (or target) XML file on disk. */
    var _xmlPath:String  = "";
    /** imagePath attribute from the root <TextureAtlas> node. */
    var _atlasImagePath:String = "";
    /** Whether the atlas has unsaved changes. */
    var _dirty:Bool = false;
    var _unsavedDlg:UnsavedChangesDialog = null;
    var _windowCloseFn:Void->Void = null;

    // ── Selection ─────────────────────────────────────────────────────────────
    var _selIdx:Int  = -1;   // -1 = nothing selected

    // ── Background colour ─────────────────────────────────────────────────────
    var _bgColor:FlxColor  = FlxColor.TRANSPARENT;
    var _bgAlpha:Float     = 0.0;       // 0 = fully transparent (checkerboard visible)

    // ── Display toggles ───────────────────────────────────────────────────────
    var _showOutlines:Bool = true;
    var _showHitboxes:Bool = true;

    // ── HUD / UI ──────────────────────────────────────────────────────────────
    var _statusBar:FlxSprite;
    var _statusText:FlxText;
    var _headerText:FlxText;
    var _tabMenu:CoolTabMenu;
    var _tabPanelBg:FlxSprite;

    // Frames-list panel (left side)
    static inline final LIST_W:Int = 220;
    var _listPanel:FlxSprite;
    var _listItems:flixel.group.FlxGroup;
    var _listHighlight:FlxSprite;
    var _listScroll:Int = 0;
    static inline final LIST_ROW_H:Int = 20;
    static inline final LIST_VISIBLE:Int = 26;

    // Frame-info panel (bottom of left side)
    var _infoPanel:FlxSprite;
    var _infoLines:Array<FlxText> = [];

    // Right-tab UI references
    var _fNameInput:CoolInputText;
    var _fXStepper:CoolNumericStepper;
    var _fYStepper:CoolNumericStepper;
    var _fWStepper:CoolNumericStepper;
    var _fHStepper:CoolNumericStepper;
    var _fFXStepper:CoolNumericStepper;
    var _fFYStepper:CoolNumericStepper;
    var _fFWStepper:CoolNumericStepper;
    var _fFHStepper:CoolNumericStepper;
    var _fRotatedCheck:CoolCheckBox;
    var _fHideHitboxCheck:CoolCheckBox;

    var _bgColorInput:CoolInputText;
    var _bgAlphaStepper:CoolNumericStepper;
    var _bgPreview:FlxSprite;

    var _exportXmlInput:CoolInputText;
    var _exportImageInput:CoolInputText;

    // ── Checkerboard ──────────────────────────────────────────────────────────
    static inline final CHECKER_SIZE:Int = 12;

    // ── Constants ─────────────────────────────────────────────────────────────
    static inline final ZOOM_MIN:Float = 0.1;
    static inline final ZOOM_MAX:Float = 8.0;
    static inline final ZOOM_STEP:Float = 0.15;
    /** Width of the right-side tab panel. */
    static inline final TAB_W:Int = 310;
    static inline final STATUS_H:Int = 24;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    public function new()
    {
        super();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // create()
    // ─────────────────────────────────────────────────────────────────────────

    override function create():Void
    {
        EditorTheme.load();
        funkin.system.CursorManager.show();
        funkin.audio.MusicManager.play('configurator', 0.6);

        // ── Camera setup (same pattern as AnimationDebug) ─────────────────────
        camUI   = new FlxCamera(); camUI.bgColor.alpha = 0;
        camGame = new FlxCamera(); camGame.bgColor.alpha = 0;
        camHUD  = new FlxCamera(); camHUD.bgColor.alpha = 0;

        // camUI is cameras[0] so FlxG.mouse uses it for stable screen coordinates
        FlxG.cameras.reset(camUI);
        FlxG.cameras.add(camGame, false);
        FlxG.cameras.add(camHUD,  false);

        // ── Canvas background (checkerboard) ──────────────────────────────────
        _buildCheckerBg();

        // ── Frame display groups ──────────────────────────────────────────────
        _frameOutlines = new FlxTypedGroup<FlxSprite>();
        _frameOutlines.cameras = [camGame];
        add(_frameOutlines);

        _hitboxes = new FlxTypedGroup<FlxSprite>();
        _hitboxes.cameras = [camGame];
        add(_hitboxes);

        _selHighlight = new FlxSprite();
        _selHighlight.makeGraphic(4, 4, FlxColor.TRANSPARENT);
        _selHighlight.cameras = [camGame];
        _selHighlight.visible = false;
        add(_selHighlight);

        // ── HUD layer ─────────────────────────────────────────────────────────
        _buildLeftPanel();
        _buildStatusBar();
        _buildHeader();
        _buildTabPanel();

        // ── Initial welcome message ───────────────────────────────────────────
        _setStatus("Welcome to Sprite Editor  ·  Import Tab → Load PNG+XML to begin", EditorTheme.current.accent);

        // Window-close guard
        #if sys
        _windowCloseFn = function()
        {
            if (_dirty)
                try { _saveXml(false); } catch (_) {}
        };
        lime.app.Application.current.window.onClose.add(_windowCloseFn);
        #end

        super.create();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Background builders
    // ─────────────────────────────────────────────────────────────────────────

    function _buildCheckerBg():Void
    {
        var t = EditorTheme.current;

        // Solid colour fill (sits under the checker, alpha-controlled)
        _canvasBg = new FlxSprite(0, 0);
        _canvasBg.makeGraphic(FlxG.width, FlxG.height, FlxColor.fromRGB(40, 40, 50));
        _canvasBg.scrollFactor.set();
        _canvasBg.cameras = [camGame];
        add(_canvasBg);

        // Checkerboard overlay that represents transparency
        var checker = new FlxSprite(0, 0);
        var cw = FlxG.width;
        var ch = FlxG.height;
        checker.makeGraphic(cw, ch, FlxColor.TRANSPARENT, true);
        var dark:FlxColor  = FlxColor.fromRGB(80, 80, 90);
        var light:FlxColor = FlxColor.fromRGB(110, 110, 120);
        var cols = Math.ceil(cw / CHECKER_SIZE);
        var rows = Math.ceil(ch / CHECKER_SIZE);
        for (row in 0...rows)
        {
            for (col in 0...cols)
            {
                var c = ((row + col) % 2 == 0) ? dark : light;
                checker.pixels.fillRect(
                    new openfl.geom.Rectangle(col * CHECKER_SIZE, row * CHECKER_SIZE, CHECKER_SIZE, CHECKER_SIZE), c);
            }
        }
        checker.pixels.unlock();
        checker.scrollFactor.set();
        checker.cameras = [camGame];
        add(checker);

        _applyBgColor();
    }

    /** Re-applies _bgColor / _bgAlpha to _canvasBg. */
    function _applyBgColor():Void
    {
        if (_canvasBg == null) return;
        if (_bgAlpha <= 0.005)
        {
            _canvasBg.alpha = 0.0;
            return;
        }
        var c:FlxColor = _bgColor;
        c.alphaFloat   = _bgAlpha;
        _canvasBg.color = c;
        _canvasBg.alpha = _bgAlpha;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Left panel — frame list + info
    // ─────────────────────────────────────────────────────────────────────────

    function _buildLeftPanel():Void
    {
        var t = EditorTheme.current;

        // Panel background
        _listPanel = new FlxSprite(0, 24);
        _listPanel.makeGraphic(LIST_W, FlxG.height - 24 - STATUS_H, t.bgPanel);
        _listPanel.scrollFactor.set();
        _listPanel.cameras = [camHUD];
        add(_listPanel);

        // Right border line
        var border = new FlxSprite(LIST_W, 24);
        border.makeGraphic(2, FlxG.height - 24 - STATUS_H, t.accent);
        border.alpha = 0.25;
        border.scrollFactor.set();
        border.cameras = [camHUD];
        add(border);

        // Column header
        var hdr = new FlxSprite(0, 24);
        hdr.makeGraphic(LIST_W, 18, (t.accent & 0x00FFFFFF) | 0x33000000);
        hdr.scrollFactor.set();
        hdr.cameras = [camHUD];
        add(hdr);

        var hdrTxt = new FlxText(6, 26, LIST_W - 10, "FRAMES  (0)", 9);
        hdrTxt.color = t.accent;
        hdrTxt.scrollFactor.set();
        hdrTxt.cameras = [camHUD];
        add(hdrTxt);
        // save ref so we can update the count later
        _infoLines.push(hdrTxt); // index 0 = header label

        // Row highlight sprite
        _listHighlight = new FlxSprite(0, 42);
        _listHighlight.makeGraphic(LIST_W - 2, LIST_ROW_H, (t.accent & 0x00FFFFFF) | 0x44000000);
        _listHighlight.scrollFactor.set();
        _listHighlight.cameras = [camHUD];
        _listHighlight.visible = false;
        add(_listHighlight);

        // Frame rows (text objects, reused via _rebuildList)
        _listItems = new flixel.group.FlxGroup();
        _listItems.cameras = [camHUD];
        add(_listItems);

        // ── Info sub-panel (bottom of left column) ────────────────────────────
        var infoTop = 24 + 18 + LIST_VISIBLE * LIST_ROW_H + 4;
        _infoPanel = new FlxSprite(0, infoTop);
        _infoPanel.makeGraphic(LIST_W, FlxG.height - infoTop - STATUS_H, (t.bgPanelAlt & 0x00FFFFFF) | 0xDD000000);
        _infoPanel.scrollFactor.set();
        _infoPanel.cameras = [camHUD];
        add(_infoPanel);

        var infoHdr = new FlxSprite(0, infoTop);
        infoHdr.makeGraphic(LIST_W, 16, (t.accent & 0x00FFFFFF) | 0x22000000);
        infoHdr.scrollFactor.set();
        infoHdr.cameras = [camHUD];
        add(infoHdr);

        var infoLbl = new FlxText(6, infoTop + 2, LIST_W - 10, "FRAME INFO", 9);
        infoLbl.color = t.accent;
        infoLbl.scrollFactor.set();
        infoLbl.cameras = [camHUD];
        add(infoLbl);

        // Info value lines (indices 1..12 in _infoLines)
        var fields = ["Name", "Atlas X", "Atlas Y", "Atlas W", "Atlas H",
                      "Frame X", "Frame Y", "Frame W", "Frame H", "Rotated", "Hitbox hidden"];
        for (i in 0...fields.length)
        {
            var lbl = new FlxText(6, infoTop + 18 + i * 14, LIST_W - 8, fields[i] + ": —", 9);
            lbl.color = FlxColor.fromRGB(180, 190, 210);
            lbl.scrollFactor.set();
            lbl.cameras = [camHUD];
            add(lbl);
            _infoLines.push(lbl); // indices 1..11
        }
    }

    /** Rebuilds the scrollable frame list from _frames. */
    function _rebuildList():Void
    {
        _listItems.clear();

        // Update header count
        if (_infoLines.length > 0)
            _infoLines[0].text = 'FRAMES  (${_frames.length})';

        var t  = EditorTheme.current;
        var y0 = 42; // first row y

        var end = Std.int(Math.min(_listScroll + LIST_VISIBLE, _frames.length));
        for (i in _listScroll...end)
        {
            var row  = i - _listScroll;
            var rowY = y0 + row * LIST_ROW_H;
            var bg   = (row % 2 == 0) ? 0x0AFFFFFF : 0x04FFFFFF;
            var rowBg = new FlxSprite(0, rowY);
            rowBg.makeGraphic(LIST_W - 2, LIST_ROW_H, bg);
            rowBg.scrollFactor.set();
            rowBg.cameras = [camHUD];
            _listItems.add(rowBg);

            var label = new FlxText(6, rowY + 3, LIST_W - 20, _frames[i].name, 9);
            label.color = (i == _selIdx) ? t.accent : FlxColor.fromRGB(200, 210, 230);
            label.scrollFactor.set();
            label.cameras = [camHUD];
            _listItems.add(label);
        }

        _updateListHighlight();
    }

    function _updateListHighlight():Void
    {
        if (_selIdx < 0 || _selIdx < _listScroll || _selIdx >= _listScroll + LIST_VISIBLE)
        {
            _listHighlight.visible = false;
            return;
        }
        _listHighlight.visible = true;
        _listHighlight.y = 42 + (_selIdx - _listScroll) * LIST_ROW_H;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Status bar + header
    // ─────────────────────────────────────────────────────────────────────────

    function _buildStatusBar():Void
    {
        var t = EditorTheme.current;
        _statusBar = new FlxSprite(0, FlxG.height - STATUS_H);
        _statusBar.makeGraphic(FlxG.width, STATUS_H, (t.bgDark & 0x00FFFFFF) | 0xEE000000);
        _statusBar.scrollFactor.set();
        _statusBar.cameras = [camHUD];
        add(_statusBar);

        _statusText = new FlxText(8, FlxG.height - STATUS_H + 5, FlxG.width - 20, "", 11);
        _statusText.color = t.accent;
        _statusText.font = Paths.font("vcr.ttf");
        _statusText.scrollFactor.set();
        _statusText.cameras = [camHUD];
        add(_statusText);

        // Right-side shortcut hints in status bar
        var hints = new FlxText(0, FlxG.height - STATUS_H + 5, FlxG.width - 10, "Ctrl+S Save  ·  Scroll Zoom  ·  Space+Drag Pan  ·  ESC Back", 9);
        hints.color = FlxColor.fromRGB(100, 115, 140);
        hints.alignment = RIGHT;
        hints.scrollFactor.set();
        hints.cameras = [camHUD];
        add(hints);
    }

    function _buildHeader():Void
    {
        var t = EditorTheme.current;
        var hdr = new FlxSprite(0, 0);
        hdr.makeGraphic(FlxG.width, 24, t.accent);
        hdr.scrollFactor.set();
        hdr.cameras = [camHUD];
        add(hdr);

        _headerText = new FlxText(8, 4, FlxG.width - 200, "SPRITE EDITOR  ·  No file loaded", 13);
        _headerText.color = t.bgDark;
        _headerText.font = Paths.font("vcr.ttf");
        _headerText.scrollFactor.set();
        _headerText.cameras = [camHUD];
        add(_headerText);

        // Theme button in header
        var themeBtn = new CoolButton(FlxG.width - 90, 2, "✨ Theme", function()
        {
            openSubState(new funkin.debug.themes.ThemePickerSubState());
        });
        themeBtn.scrollFactor.set();
        themeBtn.cameras = [camHUD];
        add(themeBtn);
    }

    function _setStatus(msg:String, ?col:FlxColor):Void
    {
        if (_statusText == null) return;
        _statusText.text  = msg;
        _statusText.color = (col != null) ? col : EditorTheme.current.textPrimary;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Right-side Tab Panel
    // ─────────────────────────────────────────────────────────────────────────

    function _buildTabPanel():Void
    {
        var t   = EditorTheme.current;
        var tabs = [
            {name: "Atlas",  label: "Atlas"},
            {name: "Frame",  label: "Frame"},
            {name: "View",   label: "View"},
            {name: "Export", label: "Export"},
        ];

        _tabMenu = new CoolTabMenu(null, tabs, true);
        _tabMenu.cameras = [camHUD];
        _tabMenu.resize(TAB_W, FlxG.height - 24 - STATUS_H - 10);
        _tabMenu.x = FlxG.width - TAB_W - 10;
        _tabMenu.y = 30;

        _tabPanelBg = new FlxSprite(_tabMenu.x - 4, _tabMenu.y - 4);
        _tabPanelBg.makeGraphic(TAB_W + 8, Std.int(_tabMenu.height) + 8,
            (t.bgPanel & 0x00FFFFFF) | 0xDD000000);
        _tabPanelBg.scrollFactor.set();
        _tabPanelBg.cameras = [camHUD];
        add(_tabPanelBg);

        add(_tabMenu);

        _addAtlasTab();
        _addFrameTab();
        _addViewTab();
        _addExportTab();
    }

    // ── Atlas Tab ─────────────────────────────────────────────────────────────

    function _addAtlasTab():Void
    {
        var tab = new CoolUIGroup();
        tab.name = "Atlas";
        var y = 10;

        _addTabHeader(tab, y, "Load / Create Atlas"); y += 28;

        tab.add(_makeLabel(10, y, "Load existing PNG + XML:")); y += 16;
        tab.add(new CoolButton(10, y, "Import Sprite Sheet", _importSpriteSheet));
        tab.add(_makeHint(10, y + 22, "Picks a PNG — auto-finds its .xml sibling"));
        y += 50;

        tab.add(_makeSep(tab, y, "Create new XML")); y += 14;
        tab.add(_makeLabel(10, y, "Load PNG only (build XML from scratch):")); y += 16;
        tab.add(new CoolButton(10, y, "Import PNG Only", _importPngOnly));
        tab.add(_makeHint(10, y + 22, "No XML required — you'll create frames manually"));
        y += 50;

        tab.add(_makeSep(tab, y, "Quick Add Frame")); y += 14;
        tab.add(_makeLabel(10, y, "Adds a new blank frame at (0,0,64,64):")); y += 16;
        tab.add(new CoolButton(10, y, "+ Add Frame", function()
        {
            _addBlankFrame();
        }));
        y += 34;

        tab.add(new CoolButton(10, y, "✕ Delete Selected", function()
        {
            _deleteSelected();
        }));
        y += 34;

        tab.add(_makeSep(tab, y, "Auto-Detect from Grid")); y += 14;
        tab.add(_makeLabel(10, y, "Frame width × height:")); y += 16;

        var gridWStepper = new CoolNumericStepper(10,  y, 8, 64, 1, 1024, 0);
        var gridHStepper = new CoolNumericStepper(108, y, 8, 64, 1, 1024, 0);
        tab.add(gridWStepper);
        tab.add(gridHStepper);
        tab.add(_makeHint(10, y + 22, "W px             H px"));
        y += 46;

        var baseName = new CoolInputText(10, y, TAB_W - 20, "frame", 10);
        tab.add(baseName);
        tab.add(_makeHint(10, y + 18, "Base name prefix (e.g. 'idle', 'sing')"));
        y += 38;

        tab.add(new CoolButton(10, y, "Auto-Grid Slice", function()
        {
            if (_sheetSprite == null || _sheetSprite.graphic == null)
            {
                _setStatus("✗ Load a PNG first", EditorTheme.current.error);
                return;
            }
            _autoSliceGrid(
                Std.int(gridWStepper.value),
                Std.int(gridHStepper.value),
                (baseName.text != null && baseName.text.trim() != "") ? baseName.text.trim() : "frame"
            );
        }));

        _tabMenu.addGroup(tab);
    }

    // ── Frame Tab ─────────────────────────────────────────────────────────────

    function _addFrameTab():Void
    {
        var tab = new CoolUIGroup();
        tab.name = "Frame";
        var y = 10;

        _addTabHeader(tab, y, "Selected Frame"); y += 28;

        tab.add(_makeLabel(10, y, "Name:")); y += 16;
        _fNameInput = new CoolInputText(10, y, TAB_W - 20, "", 10);
        tab.add(_fNameInput);
        y += 28;

        tab.add(_makeSep(tab, y, "Atlas Position")); y += 14;
        tab.add(_makeLabel(10, y, "X:"));
        tab.add(_makeLabel(90, y, "Y:"));
        _fXStepper = new CoolNumericStepper(10,  y + 14, 5, 0, 0, 8192, 0);
        _fYStepper = new CoolNumericStepper(90,  y + 14, 5, 0, 0, 8192, 0);
        tab.add(_fXStepper); tab.add(_fYStepper);
        tab.add(_makeLabel(170, y, "W:"));
        tab.add(_makeLabel(240, y, "H:"));
        _fWStepper = new CoolNumericStepper(170, y + 14, 5, 64, 1, 4096, 0);
        _fHStepper = new CoolNumericStepper(240, y + 14, 5, 64, 1, 4096, 0);
        tab.add(_fWStepper); tab.add(_fHStepper);
        y += 46;

        tab.add(_makeSep(tab, y, "Frame Offset (trim compensation)")); y += 14;
        tab.add(_makeLabel(10, y, "frameX:"));
        tab.add(_makeLabel(90, y, "frameY:"));
        _fFXStepper = new CoolNumericStepper(10,  y + 14, 5, 0, -4096, 4096, 0);
        _fFYStepper = new CoolNumericStepper(90,  y + 14, 5, 0, -4096, 4096, 0);
        tab.add(_fFXStepper); tab.add(_fFYStepper);
        tab.add(_makeLabel(170, y, "frameW:"));
        tab.add(_makeLabel(240, y, "frameH:"));
        _fFWStepper = new CoolNumericStepper(170, y + 14, 5, 0, 0, 4096, 0);
        _fFHStepper = new CoolNumericStepper(240, y + 14, 5, 0, 0, 4096, 0);
        tab.add(_fFWStepper); tab.add(_fFHStepper);
        tab.add(_makeHint(10, y + 36, "0 = not set  ·  Negative frameX/Y = left/top trim"));
        y += 60;

        _fRotatedCheck    = new CoolCheckBox(10, y,    "Rotated 90° CW");
        _fHideHitboxCheck = new CoolCheckBox(10, y+20, "Hide hitbox for this frame");
        tab.add(_fRotatedCheck);
        tab.add(_fHideHitboxCheck);
        y += 50;

        tab.add(new CoolButton(10, y, "Apply Changes", _applyFrameEdits));
        tab.add(new CoolButton(120, y, "Duplicate Frame", function()
        {
            if (_selIdx < 0 || _selIdx >= _frames.length) return;
            var src = _frames[_selIdx];
            var copy:FrameData = {
                name: src.name + "_copy",
                x: src.x, y: src.y, width: src.width, height: src.height,
                frameX: src.frameX, frameY: src.frameY,
                frameWidth: src.frameWidth, frameHeight: src.frameHeight,
                rotated: src.rotated
            };
            _frames.insert(_selIdx + 1, copy);
            _dirty = true;
            _rebuildVisuals();
            _selectFrame(_selIdx + 1);
            _setStatus("✓ Frame duplicated: " + copy.name, EditorTheme.current.success);
        }));

        _tabMenu.addGroup(tab);
    }

    // ── View Tab ──────────────────────────────────────────────────────────────

    function _addViewTab():Void
    {
        var tab = new CoolUIGroup();
        tab.name = "View";
        var y = 10;

        _addTabHeader(tab, y, "Canvas & Display"); y += 28;

        // Outline / hitbox toggles
        var showOutlinesChk = new CoolCheckBox(10, y, "Show frame outlines");
        showOutlinesChk.checked = true;
        showOutlinesChk.callback = function(v) { _showOutlines = v; _rebuildVisuals(); };
        tab.add(showOutlinesChk); y += 24;

        var showHitboxChk = new CoolCheckBox(10, y, "Show hitboxes (frameW×frameH)");
        showHitboxChk.checked = true;
        showHitboxChk.callback = function(v) { _showHitboxes = v; _rebuildVisuals(); };
        tab.add(showHitboxChk); y += 28;

        tab.add(_makeSep(tab, y, "Background Colour")); y += 14;

        tab.add(_makeLabel(10, y, "Hex colour (#RRGGBB or name):")); y += 16;
        _bgColorInput = new CoolInputText(10, y, 160, "#282830", 10);
        tab.add(_bgColorInput);
        y += 28;

        tab.add(_makeLabel(10, y, "Opacity  (0.0 = transparent):"));
        y += 16;
        _bgAlphaStepper = new CoolNumericStepper(10, y, 0.05, 0.0, 0.0, 1.0, 2);
        tab.add(_bgAlphaStepper);
        y += 28;

        // BG preview swatch
        _bgPreview = new FlxSprite(10, y);
        _bgPreview.makeGraphic(TAB_W - 20, 24, FlxColor.fromRGB(40, 40, 50));
        _bgPreview.scrollFactor.set();
        tab.add(_bgPreview);
        y += 34;

        tab.add(new CoolButton(10, y, "Apply BG", function()
        {
            _applyBgFromUI();
        }));
        y += 34;

        tab.add(_makeSep(tab, y, "Zoom")); y += 14;
        tab.add(new CoolButton(10, y, "Reset View (1:1)", function()
        {
            _zoom = 1.0; _panX = 0; _panY = 0; _applyTransform();
        }));
        tab.add(new CoolButton(130, y, "Fit to Screen", function()
        {
            _fitToScreen();
        }));

        _tabMenu.addGroup(tab);
    }

    // ── Export Tab ────────────────────────────────────────────────────────────

    function _addExportTab():Void
    {
        var tab = new CoolUIGroup();
        tab.name = "Export";
        var y = 10;

        _addTabHeader(tab, y, "Save & Export"); y += 28;

        tab.add(_makeLabel(10, y, "XML output path:")); y += 16;
        _exportXmlInput = new CoolInputText(10, y, TAB_W - 20, "", 9);
        tab.add(_exportXmlInput); y += 28;

        tab.add(_makeLabel(10, y, "imagePath attribute (in <TextureAtlas>):")); y += 16;
        _exportImageInput = new CoolInputText(10, y, TAB_W - 20, "", 9);
        tab.add(_exportImageInput); y += 30;

        tab.add(new CoolButton(10, y, "💾 Save XML", function()
        {
            _saveXml(false);
        }));
        tab.add(new CoolButton(110, y, "Save As…", function()
        {
            _saveXml(true);
        }));
        y += 34;

        tab.add(_makeSep(tab, y, "Clipboard")); y += 14;
        tab.add(new CoolButton(10, y, "Copy XML to Clipboard", function()
        {
            var xml = _buildXmlString();
            #if sys
            // Lime doesn't expose clipboard directly on all targets;
            // write to a temp file as fallback
            try { File.saveContent("_sprite_editor_clipboard.xml", xml); } catch (_:Dynamic) {}
            #end
            _setStatus("✓ XML written to _sprite_editor_clipboard.xml", EditorTheme.current.success);
        }));
        y += 34;

        tab.add(_makeSep(tab, y, "Summary")); y += 14;
        tab.add(new CoolButton(10, y, "Print Frame Stats", function()
        {
            trace("═══ Sprite Editor Frame Stats ═══");
            trace("  Atlas image : " + (_atlasImagePath != "" ? _atlasImagePath : "(none)"));
            trace("  Total frames: " + _frames.length);
            for (f in _frames)
                trace('    [${f.name}]  x=${f.x} y=${f.y} w=${f.width} h=${f.height}'
                    + (f.frameX != null && f.frameX != 0 ? '  fX=${f.frameX}' : '')
                    + (f.frameY != null && f.frameY != 0 ? '  fY=${f.frameY}' : '')
                    + (f.rotated == true ? '  ROT' : ''));
            _setStatus("✓ Frame stats printed to console", EditorTheme.current.success);
        }));

        _tabMenu.addGroup(tab);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UI helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _addTabHeader(tab:CoolUIGroup, y:Float, title:String):Void
    {
        var lbl = new FlxText(10, y, TAB_W - 20, title, 13);
        lbl.setBorderStyle(OUTLINE, FlxColor.fromRGB(0, 0, 0), 1);
        tab.add(lbl);
    }

    function _makeLabel(x:Float, y:Float, text:String):FlxText
    {
        var t = new FlxText(x, y, 0, text, 10);
        t.color = EditorTheme.current.textSecondary;
        return t;
    }

    function _makeHint(x:Float, y:Float, text:String):FlxText
    {
        var t = new FlxText(x, y, TAB_W - 20, text, 8);
        t.color = EditorTheme.current.textDim;
        return t;
    }

    function _makeSep(tab:CoolUIGroup, y:Float, label:String):FlxSprite
    {
        var line = new FlxSprite(10, y + 5);
        line.makeGraphic(TAB_W - 20, 1, EditorTheme.current.accent);
        line.alpha = 0.35;
        var lbl = new FlxText(14, y - 1, 0, "─ " + label, 8);
        lbl.color = EditorTheme.current.accent;
        tab.add(lbl);
        return line;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // update()
    // ─────────────────────────────────────────────────────────────────────────

    override function update(elapsed:Float):Void
    {
        super.update(elapsed);

        _handleZoom();
        _handlePan(elapsed);
        _handleCanvasClick();
        _handleListClick();
        _handleKeyboard();
    }

    function _handleZoom():Void
    {
        if (FlxG.mouse.wheel == 0) return;
        var factor = FlxG.mouse.wheel > 0 ? (1.0 + ZOOM_STEP) : (1.0 - ZOOM_STEP);
        _zoom = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, _zoom * factor));
        _applyTransform();
    }

    function _handlePan(elapsed:Float):Void
    {
        var space   = FlxG.keys.pressed.SPACE;
        var mMid    = FlxG.mouse.pressedMiddle;

        if ((space || mMid) && FlxG.mouse.justPressed)
        {
            _isPanning      = true;
            _panStartMouseX = FlxG.mouse.screenX;
            _panStartMouseY = FlxG.mouse.screenY;
            _panStartPanX   = _panX;
            _panStartPanY   = _panY;
        }
        if (!FlxG.mouse.pressed && !mMid)
            _isPanning = false;

        if (_isPanning)
        {
            var dx = FlxG.mouse.screenX - _panStartMouseX;
            var dy = FlxG.mouse.screenY - _panStartMouseY;
            _panX  = _panStartPanX + dx;
            _panY  = _panStartPanY + dy;
            _applyTransform();
        }
    }

    function _handleCanvasClick():Void
    {
        if (!FlxG.mouse.justPressed) return;
        if (_isPanning)               return;
        if (_sheetSprite == null || _frames.length == 0) return;

        // Map screen coords to sheet-local coords
        var mx = (FlxG.mouse.screenX - LIST_W - _panX) / _zoom;
        var my = (FlxG.mouse.screenY - 24      - _panY) / _zoom;

        // Check which frame the click landed in (iterate in reverse so topmost wins)
        var hit = -1;
        var i   = _frames.length - 1;
        while (i >= 0)
        {
            var f = _frames[i];
            if (mx >= f.x && mx < f.x + f.width && my >= f.y && my < f.y + f.height)
            {
                hit = i;
                break;
            }
            i--;
        }
        if (hit >= 0)
            _selectFrame(hit);
    }

    function _handleListClick():Void
    {
        var mx = FlxG.mouse.screenX;
        var my = FlxG.mouse.screenY;

        // Scroll wheel over the list panel — handled independently of clicks
        if (FlxG.mouse.wheel != 0 && mx >= 0 && mx <= LIST_W)
        {
            _listScroll = Std.int(Math.max(0, Math.min(
                Std.int(Math.max(0, _frames.length - LIST_VISIBLE)),
                _listScroll - FlxG.mouse.wheel)));
            _rebuildList();
        }

        // Row click
        if (!FlxG.mouse.justPressed) return;
        if (mx < 0 || mx > LIST_W) return;

        var row = Std.int((my - 42) / LIST_ROW_H);
        var idx = _listScroll + row;
        if (idx >= 0 && idx < _frames.length)
            _selectFrame(idx);
    }

    function _handleKeyboard():Void
    {
        // ESC → back (with unsaved-changes guard)
        if (FlxG.keys.justPressed.ESCAPE)
        {
            if (_unsavedDlg != null) return;
            if (_dirty)
            {
                _unsavedDlg = new UnsavedChangesDialog([camHUD]);
                _unsavedDlg.onSaveAndExit = () -> { _saveXml(false); StateTransition.switchState(new funkin.debug.EditorHubState()); };
                _unsavedDlg.onSave        = () -> { _saveXml(false); remove(_unsavedDlg); _unsavedDlg = null; };
                _unsavedDlg.onExit        = () -> { StateTransition.switchState(new funkin.debug.EditorHubState()); };
                add(_unsavedDlg);
            }
            else
            {
                StateTransition.switchState(new funkin.debug.EditorHubState());
            }
            return;
        }

        // Ctrl+S → save
        if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S)
        {
            _saveXml(false);
            return;
        }

        // Arrow keys scroll the frame list
        if (FlxG.keys.justPressed.DOWN && _selIdx < _frames.length - 1)
            _selectFrame(_selIdx + 1);
        if (FlxG.keys.justPressed.UP && _selIdx > 0)
            _selectFrame(_selIdx - 1);

        // Delete key → remove selected frame
        if (FlxG.keys.justPressed.DELETE)
            _deleteSelected();

        // H → toggle hitboxes
        if (FlxG.keys.justPressed.H)
        {
            _showHitboxes = !_showHitboxes;
            _rebuildVisuals();
            _setStatus("Hitboxes: " + (_showHitboxes ? "visible" : "hidden"), EditorTheme.current.accent);
        }

        // G → toggle outlines
        if (FlxG.keys.justPressed.G)
        {
            _showOutlines = !_showOutlines;
            _rebuildVisuals();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Import
    // ─────────────────────────────────────────────────────────────────────────

    function _importSpriteSheet():Void
    {
        #if sys
        var fd = new FileDialog();
        fd.onSelect.add(function(pngPath:String)
        {
            _loadPng(pngPath);

            // Try to find paired XML automatically
            var base   = haxe.io.Path.withoutExtension(pngPath);
            var xmlTry = base + ".xml";
            if (FileSystem.exists(xmlTry))
            {
                _xmlPath = xmlTry;
                _parseXml(File.getContent(xmlTry));
                _setStatus("✓ Loaded: " + haxe.io.Path.withoutDirectory(pngPath) + " + XML  (" + _frames.length + " frames)", EditorTheme.current.success);
            }
            else
            {
                _setStatus("✓ PNG loaded — no XML found. Use Atlas tab to create frames.", EditorTheme.current.warning);
            }

            if (_exportXmlInput != null && _xmlPath != "")
                _exportXmlInput.text = _xmlPath;
        });
        fd.browse(OPEN, "png", null, "Select Sprite Sheet PNG");
        #end
    }

    function _importPngOnly():Void
    {
        #if sys
        var fd = new FileDialog();
        fd.onSelect.add(function(pngPath:String)
        {
            _loadPng(pngPath);
            _frames = [];
            _xmlPath = haxe.io.Path.withoutExtension(pngPath) + ".xml";
            if (_exportXmlInput != null) _exportXmlInput.text = _xmlPath;
            _rebuildVisuals();
            _setStatus("✓ PNG loaded (no XML) — build frames manually or use Auto-Grid Slice", EditorTheme.current.success);
        });
        fd.browse(OPEN, "png", null, "Select PNG (no XML needed)");
        #end
    }

    function _loadPng(pngPath:String):Void
    {
        _pngPath = pngPath;
        var fileName = haxe.io.Path.withoutDirectory(pngPath);

        // Remove previous sheet sprite
        if (_sheetSprite != null) { remove(_sheetSprite); _sheetSprite = null; }

        try
        {
            #if sys
            var bmd = BitmapData.fromFile(pngPath);
            _sheetSprite = new FlxSprite(0, 0);
            _sheetSprite.loadGraphic(bmd);
            _sheetSprite.cameras = [camGame];
            _sheetSprite.scrollFactor.set();
            add(_sheetSprite);

            _atlasImagePath = fileName;
            if (_exportImageInput != null) _exportImageInput.text = fileName;
            _headerText.text = "SPRITE EDITOR  ·  " + fileName;
            _fitToScreen();
            #end
        }
        catch (e:Dynamic)
        {
            _setStatus("✗ Error loading PNG: " + e, EditorTheme.current.error);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // XML parsing
    // ─────────────────────────────────────────────────────────────────────────

    function _parseXml(content:String):Void
    {
        _frames = [];
        try
        {
            var root = Xml.parse(content).firstElement();
            if (root == null) { _setStatus("✗ Empty or invalid XML", EditorTheme.current.error); return; }

            // Read imagePath attribute from root
            if (root.get("imagePath") != null)
            {
                _atlasImagePath = root.get("imagePath");
                if (_exportImageInput != null) _exportImageInput.text = _atlasImagePath;
            }

            for (node in root.elements())
            {
                if (node.nodeName != "SubTexture") continue;

                var fd:FrameData = {
                    name:   node.get("name")   ?? "frame",
                    x:      Std.parseInt(node.get("x")     ?? "0"),
                    y:      Std.parseInt(node.get("y")     ?? "0"),
                    width:  Std.parseInt(node.get("width")  ?? "64"),
                    height: Std.parseInt(node.get("height") ?? "64"),
                };

                var fxStr  = node.get("frameX");
                var fyStr  = node.get("frameY");
                var fwStr  = node.get("frameWidth");
                var fhStr  = node.get("frameHeight");
                var rotStr = node.get("rotated");

                if (fxStr  != null) fd.frameX     = Std.parseInt(fxStr);
                if (fyStr  != null) fd.frameY     = Std.parseInt(fyStr);
                if (fwStr  != null) fd.frameWidth  = Std.parseInt(fwStr);
                if (fhStr  != null) fd.frameHeight = Std.parseInt(fhStr);
                if (rotStr != null) fd.rotated = (rotStr.toLowerCase() == "true");

                _frames.push(fd);
            }

            _rebuildVisuals();
        }
        catch (e:Dynamic)
        {
            _setStatus("✗ XML parse error: " + e, EditorTheme.current.error);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Visual rebuild (outlines, hitboxes, highlights)
    // ─────────────────────────────────────────────────────────────────────────

    function _rebuildVisuals():Void
    {
        var t = EditorTheme.current;

        // Destroy every member before clearing so OpenFL BitmapData is freed.
        for (sp in _frameOutlines.members) if (sp != null) { sp.destroy(); }
        _frameOutlines.clear();
        for (sp in _hitboxes.members) if (sp != null) { sp.destroy(); }
        _hitboxes.clear();

        for (i in 0..._frames.length)
        {
            var f = _frames[i];
            var selected = (i == _selIdx);

            // ── Frame outline (thin border around the atlas crop) ──────────────
            if (_showOutlines)
            {
                var outlineColor:FlxColor = selected
                    ? t.accent
                    : FlxColor.fromRGB(0, 200, 255);

                // Top
                _addLine(f.x, f.y, f.width, 1, outlineColor, selected ? 1.0 : 0.55);
                // Bottom
                _addLine(f.x, f.y + f.height - 1, f.width, 1, outlineColor, selected ? 1.0 : 0.55);
                // Left
                _addLine(f.x, f.y, 1, f.height, outlineColor, selected ? 1.0 : 0.55);
                // Right
                _addLine(f.x + f.width - 1, f.y, 1, f.height, outlineColor, selected ? 1.0 : 0.55);
            }

            // ── Hitbox (logical frame bounds, includes frameX/Y offsets) ────────
            var hide = (f.hideHitbox == true) || !_showHitboxes;
            if (!hide)
            {
                var hbW = (f.frameWidth  != null && f.frameWidth  > 0) ? f.frameWidth  : f.width;
                var hbH = (f.frameHeight != null && f.frameHeight > 0) ? f.frameHeight : f.height;
                var hbX = f.x + (f.frameX != null ? f.frameX : 0);
                var hbY = f.y + (f.frameY != null ? f.frameY : 0);

                // Only draw hitbox if it differs from the crop rect
                if (hbW != f.width || hbH != f.height || hbX != f.x || hbY != f.y)
                {
                    var hbColor:FlxColor = FlxColor.fromRGB(255, 80, 80);
                    // Top
                    _addHitboxLine(hbX, hbY, hbW, 1, hbColor, 0.7);
                    // Bottom
                    _addHitboxLine(hbX, hbY + hbH - 1, hbW, 1, hbColor, 0.7);
                    // Left
                    _addHitboxLine(hbX, hbY, 1, hbH, hbColor, 0.7);
                    // Right
                    _addHitboxLine(hbX + hbW - 1, hbY, 1, hbH, hbColor, 0.7);
                }
            }
        }

        // ── Selected frame fill ───────────────────────────────────────────────
        if (_selIdx >= 0 && _selIdx < _frames.length)
        {
            var f   = _frames[_selIdx];
            var fill = new FlxSprite(f.x, f.y);
            fill.makeGraphic(f.width, f.height, (t.accent & 0x00FFFFFF) | 0x22000000);
            fill.cameras = [camGame];
            _frameOutlines.add(fill);
        }

        _rebuildList();
        _applyTransform();
    }

    function _addLine(x:Int, y:Int, w:Int, h:Int, col:FlxColor, alpha:Float):Void
    {
        var sp = new FlxSprite(x, y);
        sp.makeGraphic(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), col);
        sp.alpha = alpha;
        sp.cameras = [camGame];
        _frameOutlines.add(sp);
    }

    function _addHitboxLine(x:Int, y:Int, w:Int, h:Int, col:FlxColor, alpha:Float):Void
    {
        var sp = new FlxSprite(x, y);
        sp.makeGraphic(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), col);
        sp.alpha = alpha;
        sp.cameras = [camGame];
        _hitboxes.add(sp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Camera / transform
    // ─────────────────────────────────────────────────────────────────────────

    function _applyTransform():Void
    {
        // The game camera is positioned so the sheet sits within the canvas area
        // (right of the left panel, below the header).
        camGame.zoom   = _zoom;
        camGame.x      = LIST_W;
        camGame.width  = FlxG.width - LIST_W - TAB_W - 14;
        camGame.y      = 24;
        camGame.height = FlxG.height - 24 - STATUS_H;
        camGame.scroll.set(-_panX / _zoom, -_panY / _zoom);
    }

    function _fitToScreen():Void
    {
        if (_sheetSprite == null) return;
        var availW = FlxG.width  - LIST_W - TAB_W - 24;
        var availH = FlxG.height - 24 - STATUS_H - 20;
        // graphic.width/height = actual pixel dimensions of the loaded bitmap.
        // frameWidth/frameHeight would return a single animation frame size,
        // which equals graphic.width only when no animation frames are defined.
        var imgW = (_sheetSprite.graphic != null) ? _sheetSprite.graphic.width  : _sheetSprite.width;
        var imgH = (_sheetSprite.graphic != null) ? _sheetSprite.graphic.height : _sheetSprite.height;
        var scaleX = availW / imgW;
        var scaleY = availH / imgH;
        _zoom  = Math.min(scaleX, scaleY);
        _panX  = (availW - imgW * _zoom) / 2;
        _panY  = (availH - imgH * _zoom) / 2;
        _applyTransform();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Frame selection
    // ─────────────────────────────────────────────────────────────────────────

    function _selectFrame(idx:Int):Void
    {
        _selIdx = idx;
        _rebuildVisuals();
        _populateFrameTab();
        _updateInfoPanel();

        // Ensure the selected frame is visible in the list
        if (idx >= 0 && idx < _frames.length)
        {
            if (idx < _listScroll)
                _listScroll = idx;
            else if (idx >= _listScroll + LIST_VISIBLE)
                _listScroll = idx - LIST_VISIBLE + 1;
            _rebuildList();
        }
    }

    /** Fills the Frame tab inputs with the currently selected frame's data. */
    function _populateFrameTab():Void
    {
        if (_selIdx < 0 || _selIdx >= _frames.length) return;
        var f = _frames[_selIdx];

        if (_fNameInput  != null) _fNameInput.text  = f.name;
        if (_fXStepper   != null) _fXStepper.value  = f.x;
        if (_fYStepper   != null) _fYStepper.value  = f.y;
        if (_fWStepper   != null) _fWStepper.value  = f.width;
        if (_fHStepper   != null) _fHStepper.value  = f.height;
        if (_fFXStepper  != null) _fFXStepper.value = (f.frameX     != null) ? f.frameX     : 0;
        if (_fFYStepper  != null) _fFYStepper.value = (f.frameY     != null) ? f.frameY     : 0;
        if (_fFWStepper  != null) _fFWStepper.value = (f.frameWidth  != null) ? f.frameWidth  : 0;
        if (_fFHStepper  != null) _fFHStepper.value = (f.frameHeight != null) ? f.frameHeight : 0;
        if (_fRotatedCheck    != null) _fRotatedCheck.checked    = (f.rotated     == true);
        if (_fHideHitboxCheck != null) _fHideHitboxCheck.checked = (f.hideHitbox  == true);
    }

    /** Updates the left info panel with the selected frame's values. */
    function _updateInfoPanel():Void
    {
        if (_selIdx < 0 || _selIdx >= _frames.length)
        {
            for (i in 1..._infoLines.length)
                _infoLines[i].text = _infoLines[i].text.split(":")[0] + ": —";
            return;
        }
        var f   = _frames[_selIdx];
        var vals = [
            f.name,
            "" + f.x,
            "" + f.y,
            "" + f.width,
            "" + f.height,
            (f.frameX     != null) ? "" + f.frameX     : "—",
            (f.frameY     != null) ? "" + f.frameY     : "—",
            (f.frameWidth  != null) ? "" + f.frameWidth  : "—",
            (f.frameHeight != null) ? "" + f.frameHeight : "—",
            (f.rotated    == true) ? "yes"              : "no",
            (f.hideHitbox == true) ? "yes"              : "no",
        ];
        for (i in 0...vals.length)
        {
            if (i + 1 < _infoLines.length)
            {
                var field = _infoLines[i + 1].text.split(":")[0];
                _infoLines[i + 1].text = field + ": " + vals[i];
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Frame editing
    // ─────────────────────────────────────────────────────────────────────────

    function _applyFrameEdits():Void
    {
        if (_selIdx < 0 || _selIdx >= _frames.length)
        {
            _setStatus("✗ No frame selected", EditorTheme.current.error);
            return;
        }

        var f    = _frames[_selIdx];
        var name = (_fNameInput != null) ? StringTools.trim(_fNameInput.text) : f.name;
        if (name == "") name = f.name;

        f.name   = name;
        f.x      = (_fXStepper  != null) ? Std.int(_fXStepper.value)  : f.x;
        f.y      = (_fYStepper  != null) ? Std.int(_fYStepper.value)  : f.y;
        f.width  = (_fWStepper  != null) ? Std.int(_fWStepper.value)  : f.width;
        f.height = (_fHStepper  != null) ? Std.int(_fHStepper.value)  : f.height;

        var fxVal = (_fFXStepper != null) ? Std.int(_fFXStepper.value) : 0;
        var fyVal = (_fFYStepper != null) ? Std.int(_fFYStepper.value) : 0;
        var fwVal = (_fFWStepper != null) ? Std.int(_fFWStepper.value) : 0;
        var fhVal = (_fFHStepper != null) ? Std.int(_fFHStepper.value) : 0;

        if (fxVal != 0) f.frameX = fxVal; else Reflect.deleteField(f, "frameX");
        if (fyVal != 0) f.frameY = fyVal; else Reflect.deleteField(f, "frameY");
        if (fwVal != 0) f.frameWidth  = fwVal; else Reflect.deleteField(f, "frameWidth");
        if (fhVal != 0) f.frameHeight = fhVal; else Reflect.deleteField(f, "frameHeight");

        f.rotated    = (_fRotatedCheck    != null && _fRotatedCheck.checked)    ? true : null;
        f.hideHitbox = (_fHideHitboxCheck != null && _fHideHitboxCheck.checked) ? true : null;

        _frames[_selIdx] = f;
        _dirty = true;
        _rebuildVisuals();
        _updateInfoPanel();
        _setStatus("✓ Frame updated: " + f.name, EditorTheme.current.success);
    }

    function _addBlankFrame():Void
    {
        var fd:FrameData = { name: "frame" + _frames.length, x: 0, y: 0, width: 64, height: 64 };
        _frames.push(fd);
        _dirty = true;
        _rebuildVisuals();
        _selectFrame(_frames.length - 1);
        _setStatus("✓ Added blank frame — edit in Frame tab", EditorTheme.current.success);
    }

    function _deleteSelected():Void
    {
        if (_selIdx < 0 || _selIdx >= _frames.length) return;
        var name = _frames[_selIdx].name;
        _frames.splice(_selIdx, 1);
        _dirty   = true;
        _selIdx  = Std.int(Math.max(0, _selIdx - 1));
        if (_frames.length == 0) _selIdx = -1;
        _rebuildVisuals();
        _setStatus("✓ Deleted frame: " + name, EditorTheme.current.warning);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Auto-slice
    // ─────────────────────────────────────────────────────────────────────────

    function _autoSliceGrid(fw:Int, fh:Int, baseName:String):Void
    {
        if (fw <= 0 || fh <= 0) return;
        if (_sheetSprite == null) return;

        var sw = _sheetSprite.frameWidth;
        var sh = _sheetSprite.frameHeight;
        var cols = Std.int(sw / fw);
        var rows = Std.int(sh / fh);

        _frames = [];
        var idx = 1;
        for (row in 0...rows)
        {
            for (col in 0...cols)
            {
                _frames.push({
                    name:   baseName + StringTools.lpad("" + idx, "0", 4),
                    x:      col * fw,
                    y:      row * fh,
                    width:  fw,
                    height: fh
                });
                idx++;
            }
        }
        _dirty = true;
        _rebuildVisuals();
        _selectFrame(0);
        _setStatus("✓ Auto-sliced into " + _frames.length + " frames (" + cols + "×" + rows + ")", EditorTheme.current.success);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Background from UI
    // ─────────────────────────────────────────────────────────────────────────

    function _applyBgFromUI():Void
    {
        if (_bgColorInput != null)
        {
            var raw = StringTools.trim(_bgColorInput.text);
            try
            {
                _bgColor = FlxColor.fromString(raw.startsWith("#") ? raw : "#" + raw);
            }
            catch (_:Dynamic)
            {
                _setStatus("⚠ Invalid colour — using #282830", EditorTheme.current.warning);
                _bgColor = FlxColor.fromRGB(40, 40, 48);
            }
        }
        if (_bgAlphaStepper != null)
            _bgAlpha = _bgAlphaStepper.value;

        _applyBgColor();

        // Update swatch
        if (_bgPreview != null)
        {
            var c:FlxColor = _bgColor; c.alphaFloat = Math.max(0.1, _bgAlpha);
            _bgPreview.makeGraphic(TAB_W - 20, 24, c);
        }
        _setStatus("✓ Background updated", EditorTheme.current.success);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // XML generation & save
    // ─────────────────────────────────────────────────────────────────────────

    function _buildXmlString():String
    {
        var imgPath = (_exportImageInput != null && _exportImageInput.text.trim() != "")
            ? _exportImageInput.text.trim()
            : _atlasImagePath;

        var sb = new StringBuf();
        sb.add('<?xml version="1.0" encoding="utf-8"?>\n');
        sb.add('<TextureAtlas imagePath="' + _escAttr(imgPath) + '">\n');

        for (f in _frames)
        {
            sb.add('\t<SubTexture');
            sb.add(' name="'   + _escAttr(f.name)   + '"');
            sb.add(' x="'      + f.x                + '"');
            sb.add(' y="'      + f.y                + '"');
            sb.add(' width="'  + f.width             + '"');
            sb.add(' height="' + f.height            + '"');
            if (f.frameX     != null && f.frameX     != 0) sb.add(' frameX="'     + f.frameX     + '"');
            if (f.frameY     != null && f.frameY     != 0) sb.add(' frameY="'     + f.frameY     + '"');
            if (f.frameWidth  != null && f.frameWidth  > 0) sb.add(' frameWidth="'  + f.frameWidth  + '"');
            if (f.frameHeight != null && f.frameHeight > 0) sb.add(' frameHeight="' + f.frameHeight + '"');
            if (f.rotated    == true)                        sb.add(' rotated="true"');
            sb.add('/>\n');
        }

        sb.add('</TextureAtlas>\n');
        return sb.toString();
    }

    /** Escapes characters that would break XML attribute values. */
    function _escAttr(s:String):String
    {
        return s.replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;").replace(">", "&gt;");
    }

    function _saveXml(saveAs:Bool):Void
    {
        #if sys
        var path = (_exportXmlInput != null && _exportXmlInput.text.trim() != "")
            ? _exportXmlInput.text.trim()
            : _xmlPath;

        if (saveAs || path == "")
        {
            var fd = new FileDialog();
            fd.onSelect.add(function(chosen:String)
            {
                _xmlPath = chosen;
                if (_exportXmlInput != null) _exportXmlInput.text = chosen;
                _doWrite(chosen);
            });
            fd.browse(SAVE, "xml", null, "Save Atlas XML");
            return;
        }
        _doWrite(path);
        #else
        _setStatus("⚠ File saving only available on desktop", EditorTheme.current.warning);
        #end
    }

    function _doWrite(path:String):Void
    {
        #if sys
        try
        {
            Paths.ensureDir(path);
            File.saveContent(path, _buildXmlString());
            _dirty = false;
            _setStatus("✓ Saved → " + path + "  (" + _frames.length + " frames)", EditorTheme.current.success);
        }
        catch (e:Dynamic)
        {
            _setStatus("✗ Save error: " + e, EditorTheme.current.error);
        }
        #end
    }

    override function destroy():Void
    {
        #if sys
        if (_windowCloseFn != null)
        {
            try { lime.app.Application.current.window.onClose.remove(_windowCloseFn); } catch (_) {}
            _windowCloseFn = null;
        }
        #end
        super.destroy();
    }
}
