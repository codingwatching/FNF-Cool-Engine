package funkin.debug;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.ui.FlxUIInputText;
import flixel.addons.ui.FlxUINumericStepper;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import funkin.debug.themes.EditorTheme;
import shaders.ShaderManager;

using StringTools;

/**
 * ShaderParamsSubState — reads all `uniform` declarations from a .frag source
 * and renders a live control panel for each one.
 *
 * Supported uniform types → control widget:
 *   float      → FlxUINumericStepper  (step 0.01, range -100..100)
 *   int        → FlxUINumericStepper  (step 1,    range -100..100)
 *   bool       → toggle FlxButton
 *   vec2/vec3/vec4  → N steppers side-by-side
 *
 * Changing any value immediately calls ShaderManager.setShaderParam() for live preview.
 * Clicking "Save" persists the params map to customProperties.shaderParams in the JSON.
 * ESC / Close discards unsaved changes.
 */
class ShaderParamsSubState extends flixel.FlxSubState
{
	static inline final W:Int   = 520;
	static inline final ROW:Int = 28;
	static inline final PAD:Int = 12;

	var _shaderName:String;
	var _fragSrc:String;
	var _existingParams:Dynamic;
	var _sprite:FlxSprite;
	var _camera:FlxCamera;
	var _onSave:Dynamic->Void;

	var _cam:FlxCamera;
	var _params:Map<String, Dynamic> = new Map(); // live param values

	/** Parsed uniform descriptors. */
	var _uniforms:Array<UniformDef> = [];

	var _statusTxt:FlxText;

	public function new(shaderName:String, fragSrc:String, existingParams:Dynamic,
		?sprite:FlxSprite, ?camera:FlxCamera, onSave:Dynamic->Void)
	{
		super();
		_shaderName    = shaderName;
		_fragSrc       = fragSrc;
		_existingParams = existingParams;
		_sprite        = sprite;
		_camera        = camera;
		_onSave        = onSave;
	}

	override function create():Void
	{
		super.create();

		_parseUniforms();

		// Load existing params into _params map
		if (_existingParams != null)
			for (field in Reflect.fields(_existingParams))
				_params.set(field, Reflect.field(_existingParams, field));

		_cam = new flixel.FlxCamera();
		_cam.bgColor.alpha = 0;
		FlxG.cameras.add(_cam, false);
		cameras = [_cam];

		var T = EditorTheme.current;

		var panelH = Std.int(Math.min(FlxG.height - 80, PAD * 3 + ROW * (_uniforms.length + 2) + 60));
		var panX   = (FlxG.width  - W) * 0.5;
		var panY   = (FlxG.height - panelH) * 0.5;

		// Overlay
		var overlay = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xCC000000);
		overlay.scrollFactor.set();
		overlay.cameras = [_cam];
		add(overlay);

		// Panel
		var panel = new FlxSprite(panX, panY).makeGraphic(W, panelH, T.bgPanel);
		panel.scrollFactor.set();
		panel.cameras = [_cam];
		add(panel);

		var topBar = new FlxSprite(panX, panY).makeGraphic(W, 3, T.accentAlt);
		topBar.scrollFactor.set();
		topBar.cameras = [_cam];
		add(topBar);

		// Title
		var title = new FlxText(panX + PAD, panY + 8, W - PAD * 2,
			'\u2728  SHADER PARAMS  \u2014  $_shaderName', 14);
		title.setFormat(Paths.font('vcr.ttf'), 14, T.accentAlt, LEFT);
		title.scrollFactor.set();
		title.cameras = [_cam];
		add(title);

		if (_uniforms.length == 0)
		{
			var noUni = new FlxText(panX + PAD, panY + 38, W - PAD * 2,
				'No float/int/vec uniforms found in shader source.\n\nMake sure the shader uses:\n  uniform float myParam;\n  uniform vec2  myVec;\netc.', 11);
			noUni.color = T.textSecondary;
			noUni.scrollFactor.set();
			noUni.cameras = [_cam];
			add(noUni);
		}

		var ry = panY + 34.0;

		// Column header
		var hdrName = new FlxText(panX + PAD, ry, 150, 'Uniform', 9);
		hdrName.color = T.textDim;
		hdrName.scrollFactor.set(); hdrName.cameras = [_cam]; add(hdrName);
		var hdrType = new FlxText(panX + 160, ry, 60, 'Type', 9);
		hdrType.color = T.textDim;
		hdrType.scrollFactor.set(); hdrType.cameras = [_cam]; add(hdrType);
		var hdrVal = new FlxText(panX + 220, ry, W - 230, 'Value(s)', 9);
		hdrVal.color = T.textDim;
		hdrVal.scrollFactor.set(); hdrVal.cameras = [_cam]; add(hdrVal);
		ry += 16;

		var sep = new FlxSprite(panX + PAD, ry).makeGraphic(W - PAD * 2, 1, T.borderColor);
		sep.scrollFactor.set(); sep.cameras = [_cam]; add(sep);
		ry += 4;

		// One row per uniform
		for (uni in _uniforms)
		{
			var rowBg = new FlxSprite(panX + 2, ry).makeGraphic(W - 4, ROW - 2, T.rowOdd);
			rowBg.scrollFactor.set(); rowBg.cameras = [_cam]; add(rowBg);

			var nameTxt = new FlxText(panX + PAD, ry + 7, 148, uni.name, 10);
			nameTxt.setFormat(Paths.font('vcr.ttf'), 10, T.textPrimary, LEFT);
			nameTxt.scrollFactor.set(); nameTxt.cameras = [_cam]; add(nameTxt);

			var typeTxt = new FlxText(panX + 160, ry + 7, 58, uni.type, 9);
			typeTxt.setFormat(Paths.font('vcr.ttf'), 9, T.textSecondary, LEFT);
			typeTxt.scrollFactor.set(); typeTxt.cameras = [_cam]; add(typeTxt);

			_buildControl(uni, panX + 220, ry + 4, W - 236);
			ry += ROW;
		}

		// Status + buttons
		var bY = panY + panelH - 48;
		_statusTxt = new FlxText(panX + PAD, bY, W - PAD * 2, 'Adjust values — changes apply live.', 9);
		_statusTxt.color = T.textDim;
		_statusTxt.scrollFactor.set(); _statusTxt.cameras = [_cam]; add(_statusTxt);

		bY += 14;
		var saveBtn = new FlxButton(panX + PAD, bY, 'Save to JSON', _save);
		saveBtn.cameras = [_cam];
		add(saveBtn);

		var resetBtn = new FlxButton(panX + 116, bY, 'Reset All', _resetAll);
		resetBtn.cameras = [_cam];
		add(resetBtn);

		var closeBtn = new FlxButton(panX + W - 100, bY, 'Close', close);
		closeBtn.cameras = [_cam];
		add(closeBtn);
	}

	// ── Control builder ────────────────────────────────────────────────────────

	function _buildControl(uni:UniformDef, cx:Float, cy:Float, cw:Float):Void
	{
		var T = EditorTheme.current;
		switch (uni.type)
		{
			case 'float':
				var initVal:Float = _params.exists(uni.name) ? _params.get(uni.name) : 0.0;
				var s = new FlxUINumericStepper(cx, cy, 0.01, initVal, -999, 999, 3);
				s.scrollFactor.set(); s.cameras = [_cam]; add(s);
				uni.steppers = [s];
				s.value = initVal; // ensure displayed

			case 'int':
				var initVal:Int = _params.exists(uni.name) ? Std.int(_params.get(uni.name)) : 0;
				var s = new FlxUINumericStepper(cx, cy, 1, initVal, -999, 999, 0);
				s.scrollFactor.set(); s.cameras = [_cam]; add(s);
				uni.steppers = [s];

			case 'bool':
				var initVal:Bool = _params.exists(uni.name) ? (_params.get(uni.name) == true) : false;
				var btn = new FlxButton(cx, cy, initVal ? 'true' : 'false', function()
				{
					var cur:Bool = _params.exists(uni.name) ? (_params.get(uni.name) == true) : false;
					var next = !cur;
					_params.set(uni.name, next);
					ShaderManager.setShaderParam(_shaderName, uni.name, next);
					if (uni.toggleBtn != null) uni.toggleBtn.text = next ? 'true' : 'false';
					_status('$_shaderName.${uni.name} = $next');
				});
				btn.cameras = [_cam]; add(btn);
				uni.toggleBtn = btn;

			case 'vec2':
				var initArr:Array<Float> = _vecFromParam(uni.name, 2);
				var stepW = Std.int((cw - 4) / 2);
				var sx = [0, stepW + 2];
				uni.steppers = [];
				for (i in 0...2)
				{
					var s = new FlxUINumericStepper(cx + sx[i], cy, 0.01, initArr[i], -999, 999, 3);
					s.scrollFactor.set(); s.cameras = [_cam]; add(s);
					uni.steppers.push(s);
				}

			case 'vec3':
				var initArr = _vecFromParam(uni.name, 3);
				var stepW = Std.int((cw - 4) / 3);
				uni.steppers = [];
				for (i in 0...3)
				{
					var s = new FlxUINumericStepper(cx + i * (stepW + 2), cy, 0.01, initArr[i], -999, 999, 3);
					s.scrollFactor.set(); s.cameras = [_cam]; add(s);
					uni.steppers.push(s);
				}

			case 'vec4':
				var initArr = _vecFromParam(uni.name, 4);
				var stepW = Std.int((cw - 6) / 4);
				uni.steppers = [];
				for (i in 0...4)
				{
					var s = new FlxUINumericStepper(cx + i * (stepW + 2), cy, 0.01, initArr[i], -999, 999, 3);
					s.scrollFactor.set(); s.cameras = [_cam]; add(s);
					uni.steppers.push(s);
				}

			default:
				var txt = new FlxText(cx, cy + 5, cw, '(unsupported: ${uni.type})', 9);
				txt.color = T.textDim;
				txt.scrollFactor.set(); txt.cameras = [_cam]; add(txt);
		}
	}

	function _vecFromParam(name:String, n:Int):Array<Float>
	{
		var out = [for (_ in 0...n) 0.0];
		if (_params.exists(name))
		{
			var v = _params.get(name);
			if (Std.isOfType(v, Array))
			{
				var arr:Array<Dynamic> = cast v;
				for (i in 0...Std.int(Math.min(n, arr.length)))
					out[i] = cast(arr[i], Float);
			}
		}
		return out;
	}

	// ── Update: poll steppers every frame ─────────────────────────────────────

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (FlxG.keys.justPressed.ESCAPE) { close(); return; }

		// Poll steppers for changed values and push live
		for (uni in _uniforms)
		{
			if (uni.steppers == null || uni.steppers.length == 0) continue;

			switch (uni.type)
			{
				case 'float', 'int':
					var v:Dynamic = uni.type == 'int' ? Std.int(uni.steppers[0].value) : uni.steppers[0].value;
					if (!_params.exists(uni.name) || _params.get(uni.name) != v)
					{
						_params.set(uni.name, v);
						ShaderManager.setShaderParam(_shaderName, uni.name, v);
					}

				case 'vec2', 'vec3', 'vec4':
					var arr = [for (s in uni.steppers) s.value];
					var changed = false;
					var existing = _params.exists(uni.name) ? _params.get(uni.name) : null;
					if (existing == null || !Std.isOfType(existing, Array)) changed = true;
					if (!changed)
					{
						var ea:Array<Dynamic> = cast existing;
						for (i in 0...arr.length) if (ea[i] != arr[i]) { changed = true; break; }
					}
					if (changed)
					{
						_params.set(uni.name, arr);
						ShaderManager.setShaderParam(_shaderName, uni.name, arr);
					}

				default:
			}
		}
	}

	// ── Parse uniforms from GLSL source ───────────────────────────────────────

	function _parseUniforms():Void
	{
		_uniforms = [];
		if (_fragSrc == null || _fragSrc == '') return;

		var lines = _fragSrc.split('\n');
		var supportedTypes = ['float', 'int', 'bool', 'vec2', 'vec3', 'vec4'];

		for (line in lines)
		{
			var trimmed = line.trim();
			if (!trimmed.startsWith('uniform ')) continue;

			// strip "uniform ", then split by whitespace
			var parts = trimmed.substr(8).trim().split(' ');
			// Remove empty parts
			parts = parts.filter(p -> p != '');
			if (parts.length < 2) continue;

			var glslType = parts[0].toLowerCase();
			var nameRaw  = parts[1].replace(';', '').trim();

			if (!supportedTypes.contains(glslType)) continue;
			if (nameRaw == '') continue;

			// Skip common built-in flixel uniforms
			if (['bitmap', 'openfl_texturecoordv', 'openfl_matrix', 'openfl_coloroffsets',
				 'openfl_colortransform', 'openfl_alpha'].contains(nameRaw.toLowerCase())) continue;

			_uniforms.push({
				name:      nameRaw,
				type:      glslType,
				steppers:  null,
				toggleBtn: null
			});
		}
	}

	// ── Actions ───────────────────────────────────────────────────────────────

	function _save():Void
	{
		var out:Dynamic = {};
		for (k => v in _params) Reflect.setField(out, k, v);
		if (_onSave != null) _onSave(out);
		_status('Params saved to JSON \u2713');
		close();
	}

	function _resetAll():Void
	{
		_params.clear();
		for (uni in _uniforms)
		{
			if (uni.steppers != null) for (s in uni.steppers) s.value = 0.0;
			if (uni.toggleBtn != null) uni.toggleBtn.text = 'false';
			ShaderManager.setShaderParam(_shaderName, uni.name, 0.0);
		}
		_status('All params reset to 0');
	}

	inline function _status(msg:String):Void
	{
		if (_statusTxt != null) _statusTxt.text = msg;
	}

	override function close():Void
	{
		if (_cam != null) { FlxG.cameras.remove(_cam, true); _cam = null; }
		super.close();
	}
}

// ── Private typedef ────────────────────────────────────────────────────────────

private typedef UniformDef =
{
	var name:String;
	var type:String; // "float" | "int" | "bool" | "vec2" | "vec3" | "vec4"
	var steppers:Array<FlxUINumericStepper>;
	var toggleBtn:FlxButton;
}
