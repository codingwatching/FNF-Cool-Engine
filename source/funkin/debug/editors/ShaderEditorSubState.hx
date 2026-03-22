package funkin.debug.editors;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import openfl.display.Shape;
import openfl.geom.Rectangle;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

// ─────────────────────────────────────────────────────────────────────────────
//  TYPEDEFS
// ─────────────────────────────────────────────────────────────────────────────
typedef SPortDef =
{
	n:String,
	t:String
};

typedef SNodeDef =
{
	label:String,
	color:Int,
	cat:String,
	inputs:Array<SPortDef>,
	outputs:Array<SPortDef>
};

typedef SNodeData =
{
	id:Int,
	type:String,
	wx:Float,
	wy:Float,
	params:Map<String, Dynamic>
};

typedef SConnData =
{
	fromId:Int,
	fromPort:Int,
	toId:Int,
	toPort:Int
};

typedef SNViewIt =
{
	s:FlxSprite,
	ox:Float,
	oy:Float
};

typedef SNViewTx =
{
	t:FlxText,
	ox:Float,
	oy:Float
};

typedef SNodeView =
{
	sprs:Array<SNViewIt>,
	txts:Array<SNViewTx>,
	nodeH:Int
};

/**
 * ShaderEditorSubState v3 — Visual node-based shader editor.
 *
 *  Inspirado en Blender Node Editor y Amplify Shader Editor.
 *  Funcionalidades:
 *   · Grafo de nodos arrastrables con cables bezier a color
 *   · 18 tipos de nodo: Texture, Color, Float, Time, UV, Math, FX, etc.
 *   · Generación automática de GLSL desde el grafo
 *   · Preview en vivo del shader (aplica el shader a un sprite)
 *   · Zoom (rueda) y pan (clic derecho)
 *   · Menú "Add Node" por categoría (tecla A o botón)
 *   · Guardar shader en disco  (Ctrl+S)
 *   · Borrar nodo seleccionado (Delete)
 *   · Panel de propiedades del nodo seleccionado
 */
class ShaderEditorSubState extends flixel.FlxSubState
{
	// ── Layout ────────────────────────────────────────────────────────────────
	static inline final PANEL_W:Int = 250;
	static inline final TOOLBAR_H:Int = 42;
	static inline final PREV_SZ:Int = 180;

	// ── Node visuals ──────────────────────────────────────────────────────────
	static inline final NODE_W:Int = 165;
	static inline final NODE_TITL:Int = 22;
	static inline final PORT_H:Int = 18;
	static inline final PORT_R:Float = 5.5;

	// ── Canvas ────────────────────────────────────────────────────────────────
	static inline final CANVAS_W:Int = 2400;
	static inline final CANVAS_H:Int = 1800;

	// ── Colors ────────────────────────────────────────────────────────────────
	static inline final C_BG:Int = 0xFF11111E;
	static inline final C_PANEL:Int = 0xFF191927;
	static inline final C_TITBAR:Int = 0xFF0C0C1A;
	static inline final C_ACCENT:Int = 0xFF00D9FF;
	static inline final C_GREEN:Int = 0xFF00E676;
	static inline final C_YELLOW:Int = 0xFFFFD600;
	static inline final C_RED:Int = 0xFFFF4060;
	static inline final C_GRAY:Int = 0xFF6A6A80;
	static inline final C_WHITE:Int = 0xFFDDDDEE;
	static inline final C_NODEBG:Int = 0xFF1C1C2C;
	static inline final C_NODESEL:Int = 0xFF00D9FF;

	// Port type colors (RGB for openfl graphics, no alpha)
	static inline final PC_VEC4:Int = 0xFFD600; // gold  – color/vec4
	static inline final PC_VEC2:Int = 0x69FF47; // lime  – uv/vec2
	static inline final PC_FLOAT:Int = 0x80DEEA; // cyan  – float
	static inline final PC_ANY:Int = 0xC0C0D0; // gray  – any

	// ── Static node definitions ───────────────────────────────────────────────
	static var DEFS:Map<String, SNodeDef>;

	static function __init__():Void
	{
		DEFS = [
			// ── Output ────────────────────────────────────────────────────────────
			"output" => {
				label: "Output",
				color: 0xFF1B5E20,
				cat: "Output",
				inputs: [{n: "Color", t: "vec4"}, {n: "Alpha", t: "float"}],
				outputs: []
			},
			// ── Texture & UV ─────────────────────────────────────────────────────
			"texture" => {
				label: "Texture Sample",
				color: 0xFF0D47A1,
				cat: "Texture",
				inputs: [{n: "UV", t: "vec2"}],
				outputs: [
					{n: "RGBA", t: "vec4"},
					{n: "R", t: "float"},
					{n: "G", t: "float"},
					{n: "B", t: "float"},
					{n: "A", t: "float"}
				]
			},
			"uv" => {
				label: "UV Coords",
				color: 0xFF33691E,
				cat: "Coords",
				inputs: [],
				outputs: [{n: "UV", t: "vec2"}, {n: "U", t: "float"}, {n: "V", t: "float"}]
			},
			"screen_uv" => {
				label: "Screen UV",
				color: 0xFF33691E,
				cat: "Coords",
				inputs: [],
				outputs: [{n: "UV", t: "vec2"}]
			},
			// ── Constants ─────────────────────────────────────────────────────────
			"color" => {
				label: "Color",
				color: 0xFF4A148C,
				cat: "Value",
				inputs: [],
				outputs: [{n: "RGBA", t: "vec4"}]
			},
			"float_val" => {
				label: "Float",
				color: 0xFF263238,
				cat: "Value",
				inputs: [],
				outputs: [{n: "Value", t: "float"}]
			},
			"time" => {
				label: "Time",
				color: 0xFF00695C,
				cat: "Value",
				inputs: [],
				outputs: [{n: "Time", t: "float"}]
			},
			// ── Math ──────────────────────────────────────────────────────────────
			"add" => {
				label: "Add  A+B",
				color: 0xFF3E2723,
				cat: "Math",
				inputs: [{n: "A", t: "any"}, {n: "B", t: "any"}],
				outputs: [{n: "Result", t: "any"}]
			},
			"multiply" => {
				label: "Multiply  A×B",
				color: 0xFF3E2723,
				cat: "Math",
				inputs: [{n: "A", t: "any"}, {n: "B", t: "any"}],
				outputs: [{n: "Result", t: "any"}]
			},
			"mix" => {
				label: "Mix / Lerp",
				color: 0xFF3E2723,
				cat: "Math",
				inputs: [{n: "A", t: "any"}, {n: "B", t: "any"}, {n: "T", t: "float"}],
				outputs: [{n: "Result", t: "any"}]
			},
			"sine" => {
				label: "Sine",
				color: 0xFF880E4F,
				cat: "Math",
				inputs: [{n: "X", t: "float"}],
				outputs: [{n: "Sin", t: "float"}]
			},
			"pow_node" => {
				label: "Power",
				color: 0xFF880E4F,
				cat: "Math",
				inputs: [{n: "Base", t: "float"}, {n: "Exp", t: "float"}],
				outputs: [{n: "Result", t: "float"}]
			},
			"clamp_node" => {
				label: "Clamp",
				color: 0xFF880E4F,
				cat: "Math",
				inputs: [{n: "Value", t: "float"}, {n: "Min", t: "float"}, {n: "Max", t: "float"}],
				outputs: [{n: "Result", t: "float"}]
			},
			// ── Color ops ─────────────────────────────────────────────────────────
			"grayscale" => {
				label: "Grayscale",
				color: 0xFF37474F,
				cat: "Color",
				inputs: [{n: "Color", t: "vec4"}],
				outputs: [{n: "Gray", t: "float"}, {n: "RGBA", t: "vec4"}]
			},
			"invert" => {
				label: "Invert",
				color: 0xFF37474F,
				cat: "Color",
				inputs: [{n: "Color", t: "vec4"}],
				outputs: [{n: "Color", t: "vec4"}]
			},
			"split" => {
				label: "Split RGBA",
				color: 0xFF1B5E20,
				cat: "Color",
				inputs: [{n: "Color", t: "vec4"}],
				outputs: [
					{n: "R", t: "float"},
					{n: "G", t: "float"},
					{n: "B", t: "float"},
					{n: "A", t: "float"}
				]
			},
			"combine" => {
				label: "Combine RGBA",
				color: 0xFF1B5E20,
				cat: "Color",
				inputs: [
					{n: "R", t: "float"},
					{n: "G", t: "float"},
					{n: "B", t: "float"},
					{n: "A", t: "float"}
				],
				outputs: [{n: "Color", t: "vec4"}]
			},
			// ── Effects ───────────────────────────────────────────────────────────
			"fresnel" => {
				label: "Fresnel",
				color: 0xFF0D47A1,
				cat: "FX",
				inputs: [{n: "Power", t: "float"}],
				outputs: [{n: "Value", t: "float"}]
			},
			"wave_uv" => {
				label: "Wave UV",
				color: 0xFF4A148C,
				cat: "FX",
				inputs: [{n: "UV", t: "vec2"}, {n: "Speed", t: "float"}, {n: "Amp", t: "float"}],
				outputs: [{n: "UV", t: "vec2"}]
			},
			"chromatic" => {
				label: "Chromatic Ab.",
				color: 0xFF4A148C,
				cat: "FX",
				inputs: [{n: "UV", t: "vec2"}, {n: "Shift", t: "float"}],
				outputs: [{n: "Color", t: "vec4"}]
			},
			// ── Raw GLSL (imported from file) ─────────────────────────────────────
			"raw_glsl" => {
				label: "Raw GLSL",
				color: 0xFF37474F,
				cat: "Raw",
				inputs: [],
				outputs: [{n: "Output", t: "vec4"}]
			},
		];
	}

	// ── State ─────────────────────────────────────────────────────────────────
	var _name:String;
	var _onSave:String->String->Void;
	var _nodeCam:FlxCamera;
	var _hudCam:FlxCamera;

	// Canvas / world
	var _canvasBg:FlxSprite;
	var _nodeGroup:FlxTypedGroup<FlxSprite>;

	// openfl shapes (added directly to stage)
	var _gridShape:openfl.display.Shape;
	var _wireShape:openfl.display.Shape;

	// HUD
	var _propLines:Array<FlxText> = [];
	var _codeText:FlxText;
	var _statusText:FlxText;

	// Graph data
	var _nodes:Array<SNodeData> = [];
	var _conns:Array<SConnData> = [];
	var _nextId:Int = 1;
	var _views:Map<Int, SNodeView> = new Map();

	// Interaction
	var _selectedId:Int = -1;
	var _draggingId:Int = -1;
	var _dragOffX:Float = 0;
	var _dragOffY:Float = 0;
	var _isPanning:Bool = false;
	var _panStartX:Float = 0;
	var _panStartY:Float = 0;
	var _panCamX:Float = 0;
	var _panCamY:Float = 0;
	var _camZoom:Float = 1.0;
	var _mouseWX:Float = 0;
	var _mouseWY:Float = 0;

	// Wire dragging
	var _pending:Null<{nodeId:Int, portIdx:Int, isOut:Bool}> = null;

	// Add-node popup
	var _addMenuOpen:Bool = false;
	var _addMenuSprArr:Array<FlxSprite> = [];
	var _addMenuTxtArr:Array<FlxText> = [];
	var _addMenuWX:Float = 500;
	var _addMenuWY:Float = 300;
	var _addMenuBtns:Array<{
		id:String,
		x:Float,
		y:Float,
		w:Float,
		h:Float
	}> = [];

	// HUD buttons
	var _hudBtns:Array<{
		id:String,
		x:Float,
		y:Float,
		w:Float,
		h:Float
	}> = [];

	var _statusTimer:Float = 0;
	var _keyDownFn:KeyboardEvent->Void;

	// ── Shader browser ────────────────────────────────────────────────────────
	var _browserOpen:Bool = false;
	var _browserSprs:Array<FlxSprite> = [];
	var _browserTxts:Array<FlxText> = [];
	var _browserBtns:Array<{
		id:String,
		x:Float,
		y:Float,
		w:Float,
		h:Float
	}> = [];
	var _browserScrollY:Int = 0;
	var _browserList:Array<String> = [];
	var _browserHoverIdx:Int = -1;

	/** Loaded-from-disk GLSL (raw mode), null = graph mode */
	var _rawFragCode:Null<String> = null;

	var _rawShaderName:String = "";

	// ── Constructor ───────────────────────────────────────────────────────────
	public function new(name:String, ?frag:String, ?vert:String, ?spr:FlxSprite, ?cam:FlxCamera, onSave:String->String->Void)
	{
		super();
		_name = name;
		_onSave = onSave;
	}

	// ── create ────────────────────────────────────────────────────────────────
	override function create():Void
	{
		super.create();
		funkin.system.CursorManager.show();

		// Cameras
		_nodeCam = new FlxCamera();
		_nodeCam.bgColor = C_BG;
		_nodeCam.x = 0;
		_nodeCam.y = TOOLBAR_H;
		_nodeCam.width = FlxG.width - PANEL_W;
		_nodeCam.height = FlxG.height - TOOLBAR_H;

		_hudCam = new FlxCamera();
		_hudCam.bgColor.alpha = 0;

		FlxG.cameras.reset(_nodeCam);
		FlxG.cameras.add(_hudCam, false);
		@:privateAccess FlxCamera._defaultCameras = [_nodeCam];

		// Canvas BG (solid — grid drawn via openfl Shape)
		_canvasBg = new FlxSprite(0, 0);
		_canvasBg.makeGraphic(CANVAS_W, CANVAS_H, C_BG);
		add(_canvasBg);

		// openfl shapes: grid + wires (added to stage, above HaxeFlixel bitmaps)
		_gridShape = new openfl.display.Shape();
		_wireShape = new openfl.display.Shape();
		FlxG.stage.addChild(_gridShape);
		FlxG.stage.addChild(_wireShape);

		// Node group
		_nodeGroup = new FlxTypedGroup<FlxSprite>();
		add(_nodeGroup);

		// Build HUD
		_buildHUD();

		// Default graph
		_buildDefaultGraph();

		// Camera start
		_nodeCam.scroll.set(300, 200);

		// Input
		_keyDownFn = _onKeyDown;
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _keyDownFn);
	}

	// ── Default graph ─────────────────────────────────────────────────────────
	function _buildDefaultGraph():Void
	{
		var uvId = _addNode("uv", 400, 350);
		var texId = _addNode("texture", 620, 320);
		var outId = _addNode("output", 860, 350);
		_connectPorts(uvId, 0, texId, 0);
		_connectPorts(texId, 0, outId, 0);
	}

	// ── HUD ───────────────────────────────────────────────────────────────────
	function _buildHUD():Void
	{
		// Toolbar
		var tb = _hud(new FlxSprite(0, 0).makeGraphic(FlxG.width, TOOLBAR_H, C_TITBAR));
		_drawLineH(tb, 0, TOOLBAR_H - 2, FlxG.width, 2, C_ACCENT);

		_hudTxt("⬡ SHADER NODE EDITOR", 10, 10, 0, 12, C_ACCENT, LEFT);
		_mkHudBtn(190, 5, 115, 28, "  Add Node  [A]", C_GREEN, "add_node");
		_mkHudBtn(315, 5, 120, 28, "  Load Shader [L]", 0xFFFF8F00, "load_shader");
		_mkHudBtn(445, 5, 95, 28, "  Apply  [F5]", 0xFF00897B, "apply");
		_mkHudBtn(550, 5, 110, 28, "  Save  [Ctrl+S]", C_ACCENT, "save");
		_mkHudBtn(FlxG.width - 36, 5, 30, 28, "✕", C_RED, "close");

		_statusText = _hudTxt("", FlxG.width - PANEL_W - 130, 12, 120, 12, C_GRAY, RIGHT);

		// Right panel
		var px = FlxG.width - PANEL_W;
		var panelBg = _hud(new FlxSprite(px, 0).makeGraphic(PANEL_W, FlxG.height, C_PANEL));
		_drawLineV(panelBg, 0, 0, FlxG.height, 2, C_ACCENT);

		// Section: PREVIEW
		_hudTxt("PREVIEW", px + 8, TOOLBAR_H + 8, 0, 12, C_ACCENT, LEFT);
		var sepLine1 = _hud(new FlxSprite(px + 4, TOOLBAR_H + 22).makeGraphic(PANEL_W - 8, 1, C_ACCENT));
		sepLine1.alpha = 0.25;

		// Checkerboard bg for preview
		var prevBg = new FlxSprite(px + (PANEL_W - PREV_SZ) / 2, TOOLBAR_H + 28);
		_drawCheckerboard(prevBg, PREV_SZ, PREV_SZ);
		_hud(prevBg);

		// The preview sprite (shader is applied here)
		var prevSpr = new FlxSprite(px + (PANEL_W - PREV_SZ) / 2, TOOLBAR_H + 28);
		prevSpr.makeGraphic(PREV_SZ, PREV_SZ, 0xFFFFFFFF);
		_hud(prevSpr);
		_propLines.push(null); // [0] = prevSpr placeholder (stored separately)
		// Store for shader updates
		_previewSpr = prevSpr;

		// Section: PROPERTIES
		var propY = TOOLBAR_H + 28 + PREV_SZ + 14;
		_hudTxt("PROPERTIES", px + 8, propY, 0, 12, C_ACCENT, LEFT);
		var sepLine2 = _hud(new FlxSprite(px + 4, propY + 14).makeGraphic(PANEL_W - 8, 1, C_ACCENT));
		sepLine2.alpha = 0.25;

		propY += 20;
		for (i in 0...8)
		{
			var t = _hudTxt("", px + 8, propY + i * 17, PANEL_W - 16, 11, C_WHITE, LEFT);
			_propLines.push(t);
		}

		// Section: GENERATED CODE
		var codeY = FlxG.height - 105;
		_hudTxt("GENERATED GLSL", px + 8, codeY - 16, 0, 12, C_GRAY, LEFT);
		var codeBg = _hud(new FlxSprite(px + 4, codeY).makeGraphic(PANEL_W - 8, 98, 0xFF0A0A14));
		_codeText = _hudTxt("", px + 8, codeY + 3, PANEL_W - 16, 10, 0xFF77DD77, LEFT);
		_codeText.fieldHeight = 92;
	}

	var _previewSpr:FlxSprite;

	// ── Node management ───────────────────────────────────────────────────────
	function _addNode(type:String, wx:Float, wy:Float):Int
	{
		var id = _nextId++;
		var def = DEFS.get(type);
		if (def == null)
			return -1;

		var params:Map<String, Dynamic> = new Map();
		switch (type)
		{
			case "color":
				params.set("r", 1.0);
				params.set("g", 0.5);
				params.set("b", 0.0);
				params.set("a", 1.0);
			case "float_val":
				params.set("value", 0.5);
			case "pow_node":
				params.set("exp", 2.0);
			case "clamp_node":
				params.set("min", 0.0);
				params.set("max", 1.0);
		}

		_nodes.push({
			id: id,
			type: type,
			wx: wx,
			wy: wy,
			params: params
		});
		_buildNodeView(id);
		return id;
	}

	function _removeNode(id:Int):Void
	{
		if (_getNode(id) != null && _getNode(id).type == "output")
			return; // can't delete Output
		_conns = _conns.filter(c -> c.fromId != id && c.toId != id);
		_nodes = _nodes.filter(n -> n.id != id);
		_deleteView(id);
		if (_selectedId == id)
		{
			_selectedId = -1;
			_updateProps();
		}
		_updatePreview();
	}

	function _connectPorts(fId:Int, fP:Int, tId:Int, tP:Int):Void
	{
		// Remove existing connection to this input port
		_conns = _conns.filter(c -> !(c.toId == tId && c.toPort == tP));
		_conns.push({
			fromId: fId,
			fromPort: fP,
			toId: tId,
			toPort: tP
		});
	}

	function _getNode(id:Int):Null<SNodeData>
	{
		for (n in _nodes)
			if (n.id == id)
				return n;
		return null;
	}

	// ── Node view ─────────────────────────────────────────────────────────────
	function _buildNodeView(id:Int):Void
	{
		var node = _getNode(id);
		if (node == null)
			return;
		var def = DEFS.get(node.type);
		if (def == null)
			return;

		var nPorts = Std.int(Math.max(def.inputs.length, def.outputs.length));
		var nodeH = NODE_TITL + nPorts * PORT_H + 8;

		var sprs:Array<SNViewIt> = [];
		var txts:Array<SNViewTx> = [];

		function addS(s:FlxSprite, ox:Float, oy:Float)
		{
			s.x = node.wx + ox;
			s.y = node.wy + oy;
			s.cameras = [_nodeCam];
			_nodeGroup.add(s);
			sprs.push({s: s, ox: ox, oy: oy});
		}
		function addT(t:FlxText, ox:Float, oy:Float)
		{
			t.x = node.wx + ox;
			t.y = node.wy + oy;
			t.cameras = [_nodeCam];
			add(t);
			txts.push({t: t, ox: ox, oy: oy});
		}

		// Shadow
		var shadow = new FlxSprite();
		shadow.makeGraphic(NODE_W + 4, nodeH + 4, 0x66000000);
		addS(shadow, 3, 3);

		// Body
		var body = new FlxSprite();
		body.makeGraphic(NODE_W, nodeH, C_NODEBG);
		addS(body, 0, 0);

		// Title bar
		var titleBg = new FlxSprite();
		titleBg.makeGraphic(NODE_W, NODE_TITL, def.color);
		addS(titleBg, 0, 0);

		// Title text
		var titleT = new FlxText(0, 0, NODE_W - 8, def.label, 11);
		titleT.setFormat(Paths.font('vcr.ttf'), 9, 0xFFFFFFFF, LEFT);
		addT(titleT, 5, 4);

		// Input ports
		for (i in 0...def.inputs.length)
		{
			var py = NODE_TITL + i * PORT_H + PORT_H / 2;
			var col = _pcol(def.inputs[i].t);

			var dot = new FlxSprite();
			dot.makeGraphic(Std.int(PORT_R * 2), Std.int(PORT_R * 2), 0xFF000000 | col);
			addS(dot, -PORT_R, py - PORT_R);

			var lbl = new FlxText(0, 0, Std.int(NODE_W / 2) - 4, def.inputs[i].n, 9);
			lbl.setFormat(Paths.font('vcr.ttf'), 7, C_GRAY, LEFT);
			addT(lbl, Std.int(PORT_R) + 4, py - 6);
		}

		// Output ports
		for (i in 0...def.outputs.length)
		{
			var py = NODE_TITL + i * PORT_H + PORT_H / 2;
			var col = _pcol(def.outputs[i].t);

			var dot = new FlxSprite();
			dot.makeGraphic(Std.int(PORT_R * 2), Std.int(PORT_R * 2), 0xFF000000 | col);
			addS(dot, NODE_W - PORT_R, py - PORT_R);

			var lbl = new FlxText(0, 0, Std.int(NODE_W / 2) - 4, def.outputs[i].n, 9);
			lbl.setFormat(Paths.font('vcr.ttf'), 7, C_GRAY, RIGHT);
			addT(lbl, Std.int(NODE_W / 2) + 2, py - 6);
		}

		// Selection border
		var border = new FlxSprite();
		border.makeGraphic(NODE_W, nodeH, 0x00000000, true);
		_nodeBorder(border, NODE_W, nodeH, id == _selectedId ? C_NODESEL : 0x44AAAACC);
		addS(border, 0, 0);

		_views.set(id, {sprs: sprs, txts: txts, nodeH: nodeH});
	}

	function _moveView(id:Int):Void
	{
		var node = _getNode(id);
		if (node == null)
			return;
		var view = _views.get(id);
		if (view == null)
			return;
		for (it in view.sprs)
		{
			it.s.x = node.wx + it.ox;
			it.s.y = node.wy + it.oy;
		}
		for (it in view.txts)
		{
			it.t.x = node.wx + it.ox;
			it.t.y = node.wy + it.oy;
		}
	}

	function _refreshBorder(id:Int):Void
	{
		var view = _views.get(id);
		if (view == null)
			return;
		var node = _getNode(id);
		if (node == null)
			return;
		var def = DEFS.get(node.type);
		if (def == null)
			return;
		var nPorts = Std.int(Math.max(def.inputs.length, def.outputs.length));
		var nodeH = NODE_TITL + nPorts * PORT_H + 8;
		// The border is the last sprite in sprs
		var border = view.sprs[view.sprs.length - 1].s;
		border.pixels.fillRect(new Rectangle(0, 0, NODE_W, nodeH), 0x00000000);
		_nodeBorder(border, NODE_W, nodeH, id == _selectedId ? C_NODESEL : 0x44AAAACC);
		border.dirty = true;
	}

	function _deleteView(id:Int):Void
	{
		var view = _views.get(id);
		if (view == null)
			return;
		for (it in view.sprs)
		{
			_nodeGroup.remove(it.s, true);
			it.s.destroy();
		}
		for (it in view.txts)
		{
			remove(it.t, true);
			it.t.destroy();
		}
		_views.remove(id);
	}

	// ── Port positions ────────────────────────────────────────────────────────
	function _portWPos(nodeId:Int, portIdx:Int, isOut:Bool):FlxPoint
	{
		var node = _getNode(nodeId);
		if (node == null)
			return null;
		var py = node.wy + NODE_TITL + portIdx * PORT_H + PORT_H / 2;
		var px = isOut ? (node.wx + NODE_W) : node.wx;
		return FlxPoint.get(px, py);
	}

	// ── Hit testing ───────────────────────────────────────────────────────────
	function _hitPort(wx:Float, wy:Float):{nodeId:Int, portIdx:Int, isOut:Bool}
	{
		var R2 = (PORT_R + 5) * (PORT_R + 5);
		for (node in _nodes)
		{
			var def = DEFS.get(node.type);
			if (def == null)
				continue;
			// Inputs (left edge)
			for (i in 0...def.inputs.length)
			{
				var py = node.wy + NODE_TITL + i * PORT_H + PORT_H / 2;
				var dx = wx - node.wx;
				var dy = wy - py;
				if (dx * dx + dy * dy < R2)
					return {nodeId: node.id, portIdx: i, isOut: false};
			}
			// Outputs (right edge)
			for (i in 0...def.outputs.length)
			{
				var py = node.wy + NODE_TITL + i * PORT_H + PORT_H / 2;
				var dx = wx - (node.wx + NODE_W);
				var dy = wy - py;
				if (dx * dx + dy * dy < R2)
					return {nodeId: node.id, portIdx: i, isOut: true};
			}
		}
		return null;
	}

	function _hitNode(wx:Float, wy:Float):Int
	{
		var i = _nodes.length - 1;
		while (i >= 0)
		{
			var node = _nodes[i];
			var view = _views.get(node.id);
			if (view != null)
			{
				if (wx >= node.wx && wx <= node.wx + NODE_W && wy >= node.wy && wy <= node.wy + view.nodeH)
					return node.id;
			}
			i--;
		}
		return -1;
	}

	// ── Wire drawing ──────────────────────────────────────────────────────────

	/**
	 * Redraws all wires on _wireShape (openfl Shape, on stage).
	 * Called every frame since camera pan/zoom changes the transform.
	 */
	function _redrawWires():Void
	{
		// Sync transform to nodeCam
		_wireShape.x = _nodeCam.x - _nodeCam.scroll.x * _camZoom;
		_wireShape.y = _nodeCam.y - _nodeCam.scroll.y * _camZoom;
		_wireShape.scaleX = _camZoom;
		_wireShape.scaleY = _camZoom;

		var g = _wireShape.graphics;
		g.clear();

		// Established connections
		for (c in _conns)
		{
			var from = _portWPos(c.fromId, c.fromPort, true);
			var to = _portWPos(c.toId, c.toPort, false);
			if (from == null || to == null)
			{
				from?.put();
				to?.put();
				continue;
			}

			var srcNode = _getNode(c.fromId);
			var def = srcNode != null ? DEFS.get(srcNode.type) : null;
			var col = (def != null && c.fromPort < def.outputs.length) ? _pcol(def.outputs[c.fromPort].t) : PC_ANY;

			// Glow (thick transparent under)
			g.lineStyle(5, col, 0.15);
			_bezier(g, from.x, from.y, to.x, to.y);
			// Main wire
			g.lineStyle(2, col, 1.0);
			_bezier(g, from.x, from.y, to.x, to.y);
			// Bright highlight center
			g.lineStyle(1, 0xFFFFFF, 0.2);
			_bezier(g, from.x, from.y, to.x, to.y);

			from.put();
			to.put();
		}

		// Pending wire (dragging from port)
		if (_pending != null)
		{
			var fp = _pending.isOut ? _portWPos(_pending.nodeId, _pending.portIdx, true) : _portWPos(_pending.nodeId, _pending.portIdx, false);
			if (fp != null)
			{
				g.lineStyle(1.5, C_ACCENT, 0.75);
				if (_pending.isOut)
					_bezier(g, fp.x, fp.y, _mouseWX, _mouseWY);
				else
					_bezier(g, _mouseWX, _mouseWY, fp.x, fp.y);
				fp.put();
			}
		}
	}

	function _bezier(g:openfl.display.Graphics, x1:Float, y1:Float, x2:Float, y2:Float):Void
	{
		var dx = Math.max(Math.abs(x2 - x1) * 0.45, 60.0);
		g.moveTo(x1, y1);
		g.cubicCurveTo(x1 + dx, y1, x2 - dx, y2, x2, y2);
	}

	// ── Grid drawing ──────────────────────────────────────────────────────────
	function _redrawGrid():Void
	{
		_gridShape.x = _nodeCam.x - _nodeCam.scroll.x * _camZoom;
		_gridShape.y = _nodeCam.y - _nodeCam.scroll.y * _camZoom;
		_gridShape.scaleX = _camZoom;
		_gridShape.scaleY = _camZoom;

		var g = _gridShape.graphics;
		g.clear();

		var step = 20;
		var major = 100;
		var camW = _nodeCam.width / _camZoom;
		var camH = _nodeCam.height / _camZoom;
		var sx = Math.floor(_nodeCam.scroll.x / step) * step - step;
		var sy = Math.floor(_nodeCam.scroll.y / step) * step - step;
		var ex = sx + camW + step * 2;
		var ey = sy + camH + step * 2;

		var x = sx;
		while (x <= ex)
		{
			var isMajX = Std.int(x) % major == 0;
			var y = sy;
			while (y <= ey)
			{
				var isMajY = Std.int(y) % major == 0;
				if (isMajX && isMajY)
				{
					g.beginFill(0x3A3A60, 1);
					g.drawRect(x - 1.5, y - 1.5, 3, 3);
					g.endFill();
				}
				else
				{
					g.beginFill(0x222238, 1);
					g.drawRect(x - 0.5, y - 0.5, 1, 1);
					g.endFill();
				}
				y += step;
			}
			x += step;
		}
	}

	// ── GLSL Generation ───────────────────────────────────────────────────────
	function _generateGLSL():String
	{
		var outNode:SNodeData = null;
		for (n in _nodes)
			if (n.type == "output")
			{
				outNode = n;
				break;
			}
		if (outNode == null)
			return "#pragma header\nvoid main(){gl_FragColor=vec4(1.0);}";

		// Topological sort (DFS from output backwards)
		var sorted:Array<Int> = [];
		var vis:Map<Int, Bool> = new Map();
		function visit(id:Int):Void
		{
			if (vis.get(id) == true)
				return;
			vis.set(id, true);
			for (c in _conns)
				if (c.toId == id)
					visit(c.fromId);
			sorted.push(id);
		}
		visit(outNode.id);

		var needTime = false;
		for (n in _nodes)
			if (n.type == "time" || n.type == "wave_uv" || n.type == "chromatic")
			{
				needTime = true;
				break;
			}

		var sb = new StringBuf();
		sb.add("#pragma header\n");
		if (needTime)
			sb.add("uniform float time;\n");
		sb.add("\nvoid main() {\n");

		for (nodeId in sorted)
		{
			var node = _getNode(nodeId);
			if (node == null || node.type == "output")
				continue;
			var snip = _nodeSnippet(node);
			if (snip != null)
				sb.add(snip);
		}

		// Final color
		var finalCol = _inVar(outNode.id, 0, "flixel_texture2D(bitmap, openfl_TextureCoordv)");
		sb.add('  gl_FragColor = $finalCol;\n');
		sb.add("}\n");
		return sb.toString();
	}

	function _nodeSnippet(node:SNodeData):Null<String>
	{
		var vn = 'v_${node.id}'; // primary output variable
		return switch (node.type)
		{
			case "texture":
				var uv = _inVar(node.id, 0, "openfl_TextureCoordv");
				'  vec4 $vn = flixel_texture2D(bitmap, $uv);\n';
			case "color":
				var r = _pf(node.params.get("r"));
				var g = _pf(node.params.get("g"));
				var b = _pf(node.params.get("b"));
				var a = _pf(node.params.get("a"));
				'  vec4 $vn = vec4($r, $g, $b, $a);\n';
			case "float_val":
				var v = _pf(node.params.get("value"));
				'  float $vn = $v;\n';
			case "time":
				'  float $vn = time;\n';
			case "uv":
				'  vec2 $vn = openfl_TextureCoordv;\n';
			case "screen_uv":
				'  vec2 $vn = gl_FragCoord.xy / vec2(float(${FlxG.width}), float(${FlxG.height}));\n';
			case "add":
				var a = _inVar(node.id, 0, "0.0");
				var b = _inVar(node.id, 1, "0.0");
				'  vec4 $vn = vec4($a) + vec4($b);\n';
			case "multiply":
				var a = _inVar(node.id, 0, "1.0");
				var b = _inVar(node.id, 1, "1.0");
				'  vec4 $vn = vec4($a) * vec4($b);\n';
			case "mix":
				var a = _inVar(node.id, 0, "0.0");
				var b = _inVar(node.id, 1, "1.0");
				var t = _inVar(node.id, 2, "0.5");
				'  vec4 $vn = mix(vec4($a), vec4($b), $t);\n';
			case "sine":
				var x = _inVar(node.id, 0, "0.0");
				'  float $vn = sin($x);\n';
			case "pow_node":
				var base = _inVar(node.id, 0, "1.0");
				var exp = _pf(node.params.get("exp"));
				'  float $vn = pow(max($base, 0.0001), $exp);\n';
			case "clamp_node":
				var val = _inVar(node.id, 0, "0.0");
				var mn = _pf(node.params.get("min"));
				var mx = _pf(node.params.get("max"));
				'  float $vn = clamp($val, $mn, $mx);\n';
			case "grayscale":
				var c = _inVar(node.id, 0, "flixel_texture2D(bitmap,openfl_TextureCoordv)");
				'  float ${vn}_g = dot(($c).rgb, vec3(0.299,0.587,0.114));\n  vec4 $vn = vec4(${vn}_g,${vn}_g,${vn}_g,($c).a);\n';
			case "invert":
				var c = _inVar(node.id, 0, "flixel_texture2D(bitmap,openfl_TextureCoordv)");
				'  vec4 $vn = vec4(1.0 - ($c).rgb, ($c).a);\n';
			case "split":
				var c = _inVar(node.id, 0, "flixel_texture2D(bitmap,openfl_TextureCoordv)");
				'  vec4 $vn = $c;\n';
			case "combine":
				var r = _inVar(node.id, 0, "0.0");
				var g = _inVar(node.id, 1, "0.0");
				var b = _inVar(node.id, 2, "0.0");
				var a = _inVar(node.id, 3, "1.0");
				'  vec4 $vn = vec4($r,$g,$b,$a);\n';
			case "fresnel":
				var pw = _inVar(node.id, 0, "2.0");
				'  float $vn = pow(abs(dot(vec3(0.0,0.0,1.0), normalize(vec3(openfl_TextureCoordv*2.0-1.0,1.0)))), $pw);\n';
			case "wave_uv":
				var uv = _inVar(node.id, 0, "openfl_TextureCoordv");
				var spd = _inVar(node.id, 1, "1.0");
				var amp = _inVar(node.id, 2, "0.05");
				'  vec2 $vn = ($uv) + vec2(sin(($uv).y*10.0 + time*$spd)*$amp, 0.0);\n';
			case "chromatic":
				var uv = _inVar(node.id, 0, "openfl_TextureCoordv");
				var sh = _inVar(node.id, 1, "0.005");
				'  vec4 $vn = vec4(\n    flixel_texture2D(bitmap,$uv+vec2($sh,0.0)).r,\n    flixel_texture2D(bitmap,$uv).g,\n    flixel_texture2D(bitmap,$uv-vec2($sh,0.0)).b,\n    flixel_texture2D(bitmap,$uv).a);\n';
			case "raw_glsl":
				// Inline the entire raw shader body into a helper function,
				// then call it and store the result in vn.
				var rawCode:String = node.params.exists("code") ? node.params.get("code") : "";
				// Strip #pragma header and void main(){...} wrapper, keep inner body
				var inner = _extractGLSLBody(rawCode);
				'  // Raw GLSL: ${node.params.exists("label") ? node.params.get("label") : "shader"}\n$inner  vec4 $vn = gl_FragColor; // captured from raw body\n';
			default: null;
		};
	}

	/** Returns the GLSL expression for output port [portIdx] of [nodeId]. */
	function _outExpr(nodeId:Int, portIdx:Int):String
	{
		var node = _getNode(nodeId);
		if (node == null)
			return "0.0";
		var vn = 'v_$nodeId';
		return switch (node.type + ":" + portIdx)
		{
			case "texture:0": vn;
			case "texture:1": '$vn.r';
			case "texture:2": '$vn.g';
			case "texture:3": '$vn.b';
			case "texture:4": '$vn.a';
			case "color:0": vn;
			case "float_val:0": vn;
			case "time:0": vn;
			case "uv:0": vn;
			case "uv:1": '$vn.x';
			case "uv:2": '$vn.y';
			case "screen_uv:0": vn;
			case "add:0": vn;
			case "multiply:0": vn;
			case "mix:0": vn;
			case "sine:0": vn;
			case "pow_node:0": vn;
			case "clamp_node:0": vn;
			case "grayscale:0": '${vn}_g';
			case "grayscale:1": vn;
			case "invert:0": vn;
			case "split:0": '$vn.r';
			case "split:1": '$vn.g';
			case "split:2": '$vn.b';
			case "split:3": '$vn.a';
			case "combine:0": vn;
			case "fresnel:0": vn;
			case "wave_uv:0": vn;
			case "chromatic:0": vn;
			case "raw_glsl:0": vn;
			default: vn;
		};
	}

	/** Returns the GLSL expression for input [portIdx] of [nodeId], or [def] if unconnected. */
	function _inVar(nodeId:Int, portIdx:Int, def:String):String
	{
		for (c in _conns)
		{
			if (c.toId == nodeId && c.toPort == portIdx)
				return _outExpr(c.fromId, c.fromPort);
		}
		return def;
	}

	/** Extracts the body lines of a raw GLSL main() for inlining in the graph. */
	function _extractGLSLBody(code:String):String
	{
		if (code == null || code.trim() == "")
			return "";
		// Find void main() { ... } and extract the inner lines
		var mainIdx = code.indexOf("void main");
		if (mainIdx < 0)
			return "  // (no main found in raw shader)\n";
		var open = code.indexOf("{", mainIdx);
		var close = code.lastIndexOf("}");
		if (open < 0 || close < open)
			return "  // (malformed raw shader)\n";
		var body = code.substr(open + 1, close - open - 1).trim();
		// Indent each line by 2 spaces
		return body.split('\n').map(l -> "  " + l).join('\n') + "\n";
	}

	inline function _pf(v:Dynamic):String
	{
		if (v == null)
			return "0.0";
		var f:Float = Std.parseFloat(Std.string(v));
		return (f == Math.ffloor(f)) ? '${Std.int(f)}.0' : Std.string(f);
	}

	// ── Preview ───────────────────────────────────────────────────────────────
	function _updatePreview():Void
	{
		var glsl = _rawFragCode != null ? _rawFragCode : _generateGLSL();

		// Show first 12 lines in code panel
		var lines = glsl.split('\n');
		_codeText.text = lines.slice(0, Std.int(Math.min(12, lines.length))).join('\n');

		try
		{
			_previewSpr.shader = new flixel.addons.display.FlxRuntimeShader(glsl, null);
		}
		catch (e:Dynamic)
		{
			_previewSpr.shader = null;
			_setStatus('⚠ GLSL error — check shader/connections');
			trace('[ShaderNodeEditor] $e');
		}
	}

	// ── Properties panel ─────────────────────────────────────────────────────
	function _updateProps():Void
	{
		// Clear all prop lines
		for (i in 1..._propLines.length)
			if (_propLines[i] != null)
				_propLines[i].text = "";

		if (_selectedId < 0)
		{
			if (_propLines.length > 1 && _propLines[1] != null)
				_propLines[1].text = "(no node selected)";
			return;
		}
		var node = _getNode(_selectedId);
		if (node == null)
			return;
		var def = DEFS.get(node.type);
		if (def == null)
			return;

		var lines:Array<{txt:String, col:Int}> = [
			{txt: def.label, col: def.color | 0xFF000000},
			{txt: 'Cat: ${def.cat} | ID: ${node.id}', col: C_GRAY},
			{txt: 'In: ${def.inputs.length}  Out: ${def.outputs.length}', col: C_GRAY},
		];

		// Ports list
		for (p in def.inputs)
			lines.push({txt: '← ${p.n}  [${p.t}]', col: 0xFFAABBFF});
		for (p in def.outputs)
			lines.push({txt: '→ ${p.n}  [${p.t}]', col: 0xFFAAFFBB});

		// Params
		for (k in node.params.keys())
			lines.push({txt: '  $k = ${node.params.get(k)}', col: C_YELLOW});

		for (i in 0...lines.length)
		{
			var idx = i + 1;
			if (idx >= _propLines.length || _propLines[idx] == null)
				break;
			_propLines[idx].text = lines[i].txt;
			_propLines[idx].color = lines[i].col;
		}
	}

	// ── Add-node menu ─────────────────────────────────────────────────────────
	function _showAddMenu(scrX:Float, scrY:Float, wX:Float, wY:Float):Void
	{
		_hideAddMenu();
		_addMenuOpen = true;
		_addMenuWX = wX;
		_addMenuWY = wY;
		_addMenuBtns = [];

		// Gather by category
		var cats:Array<String> = [];
		var bycat:Map<String, Array<String>> = new Map();
		for (type in DEFS.keys())
		{
			var cat = DEFS.get(type).cat;
			if (!bycat.exists(cat))
			{
				bycat.set(cat, []);
				cats.push(cat);
			}
			bycat.get(cat).push(type);
		}
		cats.sort((a, b) -> a < b ? -1 : 1);
		for (cat in cats)
			bycat.get(cat).sort((a, b) -> a < b ? -1 : 1);

		var mW = 180;
		var mH = 22;
		for (cat in cats)
			mH += 14 + bycat.get(cat).length * 18;

		var mX = scrX;
		if (mX + mW > FlxG.width - PANEL_W)
			mX = scrX - mW;
		var mY = scrY;
		if (mY + mH > FlxG.height)
			mY = scrY - mH;

		// Background
		var bg = new FlxSprite(mX, mY);
		bg.makeGraphic(mW, mH, 0xFF0E0E1E);
		_hud(bg);
		_addMenuSprArr.push(bg);
		var bdr = new FlxSprite(mX, mY);
		bdr.makeGraphic(mW, mH, 0x00000000, true);
		_nodeBorder(bdr, mW, mH, C_ACCENT);
		_hud(bdr);
		_addMenuSprArr.push(bdr);

		var py = mY + 5;
		var hdr = _hudTxt("ADD NODE", mX + 6, py, mW - 8, 12, C_ACCENT, LEFT);
		_addMenuTxtArr.push(hdr);
		py += 16;

		for (cat in cats)
		{
			var catLbl = _hudTxt(cat.toUpperCase(), mX + 6, py, mW - 8, 10, C_GRAY, LEFT);
			_addMenuTxtArr.push(catLbl);
			py += 12;

			for (type in bycat.get(cat))
			{
				var def = DEFS.get(type);
				var itBg = new FlxSprite(mX + 2, py);
				itBg.makeGraphic(mW - 4, 17, 0xFF151525);
				_hud(itBg);
				_addMenuSprArr.push(itBg);

				// Color strip on left
				var strip = new FlxSprite(mX + 2, py);
				strip.makeGraphic(3, 17, def.color);
				_hud(strip);
				_addMenuSprArr.push(strip);

				var itLbl = _hudTxt(def.label, mX + 10, py + 3, mW - 14, 11, C_WHITE, LEFT);
				_addMenuTxtArr.push(itLbl);

				final t = type;
				_addMenuBtns.push({
					id: "addnode:" + t,
					x: mX + 2,
					y: py,
					w: mW - 4,
					h: 17
				});
				py += 18;
			}
			py += 2;
		}
	}

	function _hideAddMenu():Void
	{
		_addMenuOpen = false;
		for (s in _addMenuSprArr)
		{
			remove(s, true);
			s.destroy();
		}
		for (t in _addMenuTxtArr)
		{
			remove(t, true);
			t.destroy();
		}
		_addMenuSprArr = [];
		_addMenuTxtArr = [];
		_addMenuBtns = [];
	}

	// ── Save ──────────────────────────────────────────────────────────────────
	function _saveShader():Void
	{
		var glsl = _generateGLSL();
		var name = _name.trim();
		if (name.endsWith('.frag'))
			name = name.substr(0, name.length - 5);
		if (name == "")
			name = "node_shader";

		#if sys
		var dir = mods.ModManager.isActive() ? '${mods.ModManager.modRoot()}/shaders' : 'assets/shaders';
		try
		{
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			File.saveContent('$dir/$name.frag', glsl);
		}
		catch (ex:Dynamic)
		{
			_setStatus('Write error: $ex');
			return;
		}
		funkin.graphics.shaders.ShaderManager.shaders.remove(name);
		funkin.graphics.shaders.ShaderManager.scanShaders();
		if (_onSave != null)
			_onSave(name, glsl);
		_setStatus('Saved: $name.frag ✓');
		close();
		#else
		_setStatus('Sys not available');
		#end
	}

	// ── Shader browser ────────────────────────────────────────────────────────

	function _showShaderBrowser():Void
	{
		_hideBrowser();
		_browserOpen = true;

		// Refresh list from ShaderManager
		funkin.graphics.shaders.ShaderManager.scanShaders();
		_browserList = funkin.graphics.shaders.ShaderManager.getAvailableShaders();

		var bW = 340;
		var bH = Std.int(Math.min(FlxG.height - 80, 500));
		var bX = Std.int((FlxG.width - bW) / 2);
		var bY = Std.int((FlxG.height - bH) / 2);

		// Dim overlay
		var ov = new FlxSprite(0, 0);
		ov.makeGraphic(FlxG.width, FlxG.height, 0xBB000000);
		_hud(ov);
		_browserSprs.push(ov);

		// Panel bg + border
		var bg = new FlxSprite(bX, bY);
		bg.makeGraphic(bW, bH, 0xFF0F0F1E);
		_hud(bg);
		_browserSprs.push(bg);
		var bdr = new FlxSprite(bX, bY);
		bdr.makeGraphic(bW, bH, 0x00000000, true);
		_nodeBorder(bdr, bW, bH, C_ACCENT);
		_hud(bdr);
		_browserSprs.push(bdr);

		// Title bar
		var titleH = 34;
		var tbg = new FlxSprite(bX, bY);
		tbg.makeGraphic(bW, titleH, C_TITBAR);
		_hud(tbg);
		_browserSprs.push(tbg);
		var tline = new FlxSprite(bX, bY + titleH - 2);
		tline.makeGraphic(bW, 2, C_ACCENT);
		tline.alpha = 0.5;
		_hud(tline);
		_browserSprs.push(tline);

		var hdr = _hudTxt("  📁  LOAD SHADER", bX + 8, bY + 9, bW - 60, 12, C_ACCENT, LEFT);
		_browserTxts.push(hdr);

		// Close button
		var closeBg = new FlxSprite(bX + bW - 30, bY + 4);
		closeBg.makeGraphic(26, 26, 0xFF2A0808);
		_hud(closeBg);
		_browserSprs.push(closeBg);
		var closeTxt = _hudTxt("✕", bX + bW - 30, bY + 8, 26, 11, C_RED, CENTER);
		_browserTxts.push(closeTxt);
		_browserBtns.push({
			id: "browser_close",
			x: bX + bW - 30,
			y: bY + 4,
			w: 26,
			h: 26
		});

		// Search hint
		var hint = _hudTxt(_browserList.length == 0 ? "No shaders found in assets/shaders/" : '${_browserList.length} shader(s) found — click to preview · Ctrl+click to import as node',
			bX
			+ 8, bY
			+ titleH
			+ 6, bW
			- 16, 11, C_GRAY, LEFT);
		_browserTxts.push(hint);

		// Currently loaded indicator
		if (_rawFragCode != null)
		{
			var curT = _hudTxt('▶ Currently loaded: $_rawShaderName', bX + 8, bY + titleH + 18, bW - 16, 11, 0xFFFF8F00, LEFT);
			_browserTxts.push(curT);
		}

		// List area
		var listY = bY + titleH + 32;
		var itemH = 26;
		var maxItems = Std.int((bH - titleH - 40) / itemH);
		_browserScrollY = Std.int(Math.max(0, Math.min(_browserScrollY, _browserList.length - maxItems)));

		for (i in 0...maxItems)
		{
			var idx = i + _browserScrollY;
			if (idx >= _browserList.length)
				break;

			var name = _browserList[idx];
			var isLoaded = _rawShaderName == name && _rawFragCode != null;

			var iy = listY + i * itemH;

			// Row bg (alternate + highlight loaded)
			var rowCol = isLoaded ? 0xFF1A2A10 : (i % 2 == 0 ? 0xFF141424 : 0xFF111120);
			var rowBg = new FlxSprite(bX + 4, iy);
			rowBg.makeGraphic(bW - 8, itemH - 2, rowCol);
			_hud(rowBg);
			_browserSprs.push(rowBg);

			// Left accent bar (color by loaded state)
			var barCol = isLoaded ? C_GREEN : C_ACCENT;
			var bar = new FlxSprite(bX + 4, iy);
			bar.makeGraphic(3, itemH - 2, barCol);
			_hud(bar);
			_browserSprs.push(bar);

			// Icon + name
			var icon = isLoaded ? "✓ " : "⬡ ";
			var nameT = _hudTxt('$icon$name', bX + 12, iy + 6, bW - 80, 12, isLoaded ? C_GREEN : C_WHITE, LEFT);
			_browserTxts.push(nameT);

			// Preview button
			var prevBtn = new FlxSprite(bX + bW - 70, iy + 3);
			prevBtn.makeGraphic(62, itemH - 7, 0xFF082028);
			_hud(prevBtn);
			_browserSprs.push(prevBtn);
			var prevT = _hudTxt("▶ Preview", bX + bW - 70, iy + 6, 62, 11, C_ACCENT, CENTER);
			_browserTxts.push(prevT);

			final n = name;
			_browserBtns.push({
				id: 'browser_preview:$n',
				x: bX + 4,
				y: iy,
				w: bW - 80,
				h: itemH - 2
			});
			_browserBtns.push({
				id: 'browser_load:$n',
				x: bX + bW - 70,
				y: iy,
				w: 62,
				h: itemH - 2
			});
		}

		// Scroll arrows
		if (_browserScrollY > 0)
		{
			var upT = _hudTxt("▲ scroll", bX + 8, bY + bH - 18, 80, 11, C_GRAY, LEFT);
			_browserTxts.push(upT);
			_browserBtns.push({
				id: "browser_up",
				x: bX + 4,
				y: bY + bH - 22,
				w: 80,
				h: 18
			});
		}
		if (_browserScrollY + maxItems < _browserList.length)
		{
			var dnT = _hudTxt("▼ scroll", bX + bW - 90, bY + bH - 18, 80, 11, C_GRAY, RIGHT);
			_browserTxts.push(dnT);
			_browserBtns.push({
				id: "browser_down",
				x: bX + bW - 90,
				y: bY + bH - 22,
				w: 80,
				h: 18
			});
		}

		// "Back to graph mode" if in raw mode
		if (_rawFragCode != null)
		{
			var clearBtn = new FlxSprite(bX + 8, bY + bH - 20);
			clearBtn.makeGraphic(bW - 16, 16, 0xFF2A1010);
			_hud(clearBtn);
			_browserSprs.push(clearBtn);
			var clearT = _hudTxt("⟲  Return to Node Graph mode (discard loaded shader)", bX + 8, bY + bH - 19, bW - 16, 11, C_RED, CENTER);
			_browserTxts.push(clearT);
			_browserBtns.push({
				id: "browser_clear_raw",
				x: bX + 8,
				y: bY + bH - 20,
				w: bW - 16,
				h: 16
			});
		}
	}

	function _hideBrowser():Void
	{
		_browserOpen = false;
		for (s in _browserSprs)
		{
			remove(s, true);
			s.destroy();
		}
		for (t in _browserTxts)
		{
			remove(t, true);
			t.destroy();
		}
		_browserSprs = [];
		_browserTxts = [];
		_browserBtns = [];
	}

	/**
	 * Preview a shader from disk without importing it into the graph.
	 * Applies the raw GLSL directly to the preview sprite.
	 */
	function _previewShaderFromDisk(name:String):Void
	{
		#if sys
		funkin.graphics.shaders.ShaderManager.scanShaders();
		var paths = funkin.graphics.shaders.ShaderManager.shaderPaths;
		if (!paths.exists(name))
		{
			_setStatus('Shader "$name" not found on disk');
			return;
		}
		try
		{
			var code = sys.io.File.getContent(paths.get(name));
			_rawFragCode = code;
			_rawShaderName = name;
			_updatePreview();
			_setStatus('👁  Previewing: $name  (not imported to graph)');
		}
		catch (ex:Dynamic)
		{
			_setStatus('Load error: $ex');
		}
		#else
		_setStatus('File system not available');
		#end
	}

	/**
	 * Load shader from disk and import it into the graph as a "Raw GLSL" node.
	 */
	function _loadShaderAsNode(name:String):Void
	{
		#if sys
		funkin.graphics.shaders.ShaderManager.scanShaders();
		var paths = funkin.graphics.shaders.ShaderManager.shaderPaths;
		if (!paths.exists(name))
		{
			_setStatus('Shader "$name" not found');
			return;
		}
		try
		{
			var code = sys.io.File.getContent(paths.get(name));
			// Add a RawGLSL node at current scroll center
			var cx = _nodeCam.scroll.x + (_nodeCam.width / _camZoom) / 2 - NODE_W / 2;
			var cy = _nodeCam.scroll.y + (_nodeCam.height / _camZoom) / 2;
			var nid = _addNode("raw_glsl", cx, cy);
			var node = _getNode(nid);
			if (node != null)
			{
				node.params.set("code", code);
				node.params.set("label", name);
			}
			_rawFragCode = null; // back to graph mode
			_rawShaderName = "";
			_updatePreview();
			_setStatus('✓ Imported "$name" as Raw GLSL node');
		}
		catch (ex:Dynamic)
		{
			_setStatus('Import error: $ex');
		}
		#else
		_setStatus('File system not available');
		#end
	}

	function _setStatus(msg:String):Void
	{
		_statusTimer = 3.0;
		if (_statusText != null)
			_statusText.text = msg;
	}

	// ── update ────────────────────────────────────────────────────────────────
	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Keep nodeCam sized to current window (handles resize)
		_nodeCam.width = FlxG.width - PANEL_W;
		_nodeCam.height = FlxG.height - TOOLBAR_H;

		// World mouse pos (nodeCam space - node/port interaction)
		var wm = FlxG.mouse.getWorldPosition(_nodeCam);
		_mouseWX = wm.x;
		_mouseWY = wm.y;
		wm.put();

		// Screen mouse pos - raw pixels matching HUD element positions.
		// FlxG.mouse.x/y is transformed by defaultCameras=[_nodeCam] and
		// CANNOT be used for HUD hit-testing.
		var sx:Float = FlxG.mouse.screenX;
		var sy:Float = FlxG.mouse.screenY;

		// Status timer
		if (_statusTimer > 0)
		{
			_statusTimer -= elapsed;
			if (_statusTimer <= 0 && _statusText != null)
				_statusText.text = 'Zoom: ${Std.int(_camZoom * 100)}%  ·  ${_nodes.length} nodes';
		}

		// Redraw wires + grid every frame (handles pan/zoom continuously)
		_redrawWires();
		_redrawGrid();

		// Scroll zoom (only over canvas area)
		if (FlxG.mouse.wheel != 0 && !_inHUD(sx, sy))
		{
			if (_browserOpen)
			{
				_browserScrollY = Std.int(Math.max(0, _browserScrollY - FlxG.mouse.wheel));
				_hideBrowser();
				_showShaderBrowser();
			}
			else
			{
				var dz = FlxG.mouse.wheel > 0 ? 0.12 : -0.12;
				_camZoom = Math.max(0.25, Math.min(2.5, _camZoom + dz));
				_nodeCam.zoom = _camZoom;
			}
		}

		// Right-click pan - use screen coords so delta is in actual pixels
		if (FlxG.mouse.justPressedRight && !_inHUD(sx, sy))
		{
			_isPanning = true;
			_panStartX = sx;
			_panStartY = sy;
			_panCamX = _nodeCam.scroll.x;
			_panCamY = _nodeCam.scroll.y;
		}
		if (_isPanning)
		{
			if (FlxG.mouse.releasedRight)
			{
				_isPanning = false;
			}
			else
			{
				var dx = (sx - _panStartX) / _camZoom;
				var dy = (sy - _panStartY) / _camZoom;
				_nodeCam.scroll.x = _panCamX - dx;
				_nodeCam.scroll.y = _panCamY - dy;
			}
		}

		// Left click
		if (FlxG.mouse.justPressed)
		{
			// Use sx/sy (screen coords) for HUD, _mouseWX/_mouseWY (world) for nodes

			// Browser overlay (handles all clicks when open)
			if (_browserOpen)
			{
				for (b in _browserBtns)
					if (sx >= b.x && sx <= b.x + b.w && sy >= b.y && sy <= b.y + b.h)
					{
						_onHudBtn(b.id);
						return;
					}
				_hideBrowser();
				return;
			}

			// Toolbar buttons
			if (sy < TOOLBAR_H)
			{
				for (b in _hudBtns)
					if (sx >= b.x && sx <= b.x + b.w && sy >= b.y && sy <= b.y + b.h)
					{
						_onHudBtn(b.id);
						return;
					}
				return;
			}

			// Right panel
			if (_inHUD(sx, sy))
			{
				if (_addMenuOpen)
					_hideAddMenu();
				return;
			}

			// Add-menu items (screen space)
			if (_addMenuOpen)
			{
				var handled = false;
				for (b in _addMenuBtns)
					if (sx >= b.x && sx <= b.x + b.w && sy >= b.y && sy <= b.y + b.h)
					{
						_onHudBtn(b.id);
						handled = true;
						break;
					}
				_hideAddMenu();
				if (handled)
					return;
			}

			// Port hit?
			var pH = _hitPort(_mouseWX, _mouseWY);
			if (pH != null)
			{
				if (_pending != null)
				{
					// Complete connection
					if (_pending.isOut != pH.isOut)
					{
						var fId:Int;
						var fP:Int;
						var tId:Int;
						var tP:Int;
						if (_pending.isOut)
						{
							fId = _pending.nodeId;
							fP = _pending.portIdx;
							tId = pH.nodeId;
							tP = pH.portIdx;
						}
						else
						{
							fId = pH.nodeId;
							fP = pH.portIdx;
							tId = _pending.nodeId;
							tP = _pending.portIdx;
						}
						_connectPorts(fId, fP, tId, tP);
						_updatePreview();
					}
					_pending = null;
				}
				else
				{
					_pending = pH;
				}
				return;
			}

			// Cancel pending connection
			if (_pending != null)
			{
				_pending = null;
				return;
			}

			// Node hit
			var nId = _hitNode(_mouseWX, _mouseWY);
			var prevSel = _selectedId;
			if (nId >= 0)
			{
				var node = _getNode(nId);
				if (node != null)
				{
					// Drag only when clicking title bar
					if (_mouseWY >= node.wy && _mouseWY <= node.wy + NODE_TITL)
					{
						_draggingId = nId;
						_dragOffX = _mouseWX - node.wx;
						_dragOffY = _mouseWY - node.wy;
					}
					_selectedId = nId;
				}
			}
			else
			{
				_selectedId = -1;
			}
			if (_selectedId != prevSel)
			{
				if (prevSel >= 0)
					_refreshBorder(prevSel);
				if (_selectedId >= 0)
					_refreshBorder(_selectedId);
				_updateProps();
			}
		}

		// Release drag
		if (FlxG.mouse.released && _draggingId >= 0)
			_draggingId = -1;

		// Move dragging node
		if (_draggingId >= 0 && FlxG.mouse.pressed)
		{
			var node = _getNode(_draggingId);
			if (node != null)
			{
				// Snap to 10px grid
				node.wx = Math.round((_mouseWX - _dragOffX) / 10) * 10;
				node.wy = Math.round((_mouseWY - _dragOffY) / 10) * 10;
				_moveView(_draggingId);
			}
		}
	}

	function _onHudBtn(id:String):Void
	{
		if (id.startsWith("addnode:"))
		{
			var type = id.substr(8);
			var newId = _addNode(type, _addMenuWX, _addMenuWY);
			_updatePreview();
			_hideAddMenu();
			return;
		}
		if (id.startsWith("browser_preview:"))
		{
			var name = id.substr(16);
			_previewShaderFromDisk(name);
			_hideBrowser();
			_showShaderBrowser(); // refresh with loaded indicator
			return;
		}
		if (id.startsWith("browser_load:"))
		{
			var name = id.substr(13);
			_loadShaderAsNode(name);
			_hideBrowser();
			return;
		}
		switch (id)
		{
			case "browser_close":
				_hideBrowser();
			case "browser_up":
				_browserScrollY = Std.int(Math.max(0, _browserScrollY - 5));
				_hideBrowser();
				_showShaderBrowser();
			case "browser_down":
				_browserScrollY += 5;
				_hideBrowser();
				_showShaderBrowser();
			case "browser_clear_raw":
				_rawFragCode = null;
				_rawShaderName = "";
				_updatePreview();
				_hideBrowser();
				_setStatus('⟲ Returned to Node Graph mode');
			case "add_node":
				_showAddMenu(195, TOOLBAR_H + 4, _mouseWX, _mouseWY);
			case "load_shader":
				_showShaderBrowser();
			case "apply":
				_updatePreview();
			case "save":
				_saveShader();
			case "close":
				close();
		}
	}

	function _onKeyDown(e:KeyboardEvent):Void
	{
		switch (e.keyCode)
		{
			case Keyboard.ESCAPE:
				if (_browserOpen)
				{
					_hideBrowser();
					return;
				}
				if (_addMenuOpen)
				{
					_hideAddMenu();
					return;
				}
				else if (_pending != null)
					_pending = null;
				else
					close();
			case Keyboard.S:
				if (e.ctrlKey)
					_saveShader();
			case Keyboard.F5:
				_updatePreview();
			case Keyboard.A:
				if (!e.ctrlKey && !_addMenuOpen && !_browserOpen)
					_showAddMenu(210, TOOLBAR_H + 10, _mouseWX, _mouseWY);
			case Keyboard.L:
				if (!_browserOpen)
					_showShaderBrowser();
			case Keyboard.DELETE, Keyboard.BACKSPACE:
				if (!_browserOpen && _selectedId > 0)
					_removeNode(_selectedId);
			case Keyboard.F:
				if (_selectedId >= 0)
				{
					var n = _getNode(_selectedId);
					if (n != null)
					{
						_nodeCam.scroll.x = n.wx - (_nodeCam.width / _camZoom) / 2 + NODE_W / 2;
						_nodeCam.scroll.y = n.wy - (_nodeCam.height / _camZoom) / 2;
					}
				}
		}
	}

	// ── Helpers ───────────────────────────────────────────────────────────────
	inline function _inHUD(mx:Float, my:Float):Bool
		return mx >= FlxG.width - PANEL_W;

	inline function _pcol(t:String):Int
		return switch (t)
		{
			case "vec4": PC_VEC4;
			case "vec2": PC_VEC2;
			case "float": PC_FLOAT;
			default: PC_ANY;
		};

	function _hud<T:FlxSprite>(s:T):T
	{
		s.scrollFactor.set();
		s.cameras = [_hudCam];
		add(s);
		return s;
	}

	function _hudTxt(txt:String, x:Float, y:Float, w:Float, sz:Int, col:Int, align:flixel.text.FlxTextAlign):FlxText
	{
		var t = new FlxText(x, y, Std.int(w), txt, sz);
		t.setFormat(Paths.font('vcr.ttf'), sz, col, align);
		t.scrollFactor.set();
		t.cameras = [_hudCam];
		add(t);
		return t;
	}

	function _mkHudBtn(bx:Float, by:Float, bw:Float, bh:Float, lbl:String, col:Int, id:String):Void
	{
		var r = (col >> 16) & 0xFF;
		var g = (col >> 8) & 0xFF;
		var b = col & 0xFF;
		var dim:Int = (0xFF << 24) | (Std.int(r * 0.2) << 16) | (Std.int(g * 0.2) << 8) | Std.int(b * 0.2);
		var bg = new FlxSprite(bx, by);
		bg.makeGraphic(Std.int(bw), Std.int(bh), dim);
		_hud(bg);
		// Left accent strip
		var strip = new FlxSprite(bx, by);
		strip.makeGraphic(2, Std.int(bh), col);
		_hud(strip);
		var t = _hudTxt(lbl, bx + 5, by + (bh - 9) / 2, bw - 7, 12, col, LEFT);
		_hudBtns.push({
			id: id,
			x: bx,
			y: by,
			w: bw,
			h: bh
		});
	}

	function _nodeBorder(spr:FlxSprite, w:Int, h:Int, col:Int):Void
	{
		FlxSpriteUtil.drawRect(spr, 0, 0, w, 1, col);
		FlxSpriteUtil.drawRect(spr, 0, h - 1, w, 1, col);
		FlxSpriteUtil.drawRect(spr, 0, 0, 1, h, col);
		FlxSpriteUtil.drawRect(spr, w - 1, 0, 1, h, col);
	}

	function _drawLineH(spr:FlxSprite, x:Float, y:Float, w:Float, h:Float, col:Int):Void
		FlxSpriteUtil.drawRect(spr, x, y, w, h, col);

	function _drawLineV(spr:FlxSprite, x:Float, y:Float, h:Float, w:Float, col:Int):Void
		FlxSpriteUtil.drawRect(spr, x, y, w, h, col);

	function _drawCheckerboard(spr:FlxSprite, w:Int, h:Int):Void
	{
		spr.makeGraphic(w, h, 0xFF444444);
		var bd = spr.pixels;
		var sz = 10;
		for (cx in 0...Std.int(w / sz))
			for (cy in 0...Std.int(h / sz))
				if ((cx + cy) % 2 == 1)
					bd.fillRect(new Rectangle(cx * sz, cy * sz, sz, sz), 0xFF555568);
		spr.dirty = true;
	}

	// ── close ─────────────────────────────────────────────────────────────────
	override function close():Void
	{
		if (_keyDownFn != null)
		{
			FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, _keyDownFn);
			_keyDownFn = null;
		}
		_hideBrowser();
		_hideAddMenu();
		// Remove stage shapes
		if (_gridShape != null && FlxG.stage.contains(_gridShape))
			FlxG.stage.removeChild(_gridShape);
		if (_wireShape != null && FlxG.stage.contains(_wireShape))
			FlxG.stage.removeChild(_wireShape);
		if (_nodeCam != null)
		{
			FlxG.cameras.remove(_nodeCam, true);
			_nodeCam = null;
		}
		if (_hudCam != null)
		{
			FlxG.cameras.remove(_hudCam, true);
			_hudCam = null;
		}
		super.close();
	}
}
