package funkin.graphics.shaders;

import funkin.graphics.shaders.FunkinRuntimeShader;
import funkin.scripting.RuleScriptInstance;
import funkin.scripting.HScriptInstance;
import funkin.scripting.ScriptHandler;

#if HSCRIPT_ALLOWED
import hscript.Interp;
import hscript.Parser;
#end

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;
/**
 * ScriptShader — a GLSL shader defined and animated from a script file.
 *
 * Place a .lua or .hx file in  assets/shaders/  (or  mods/{mod}/shaders/).
 * The script defines the GLSL source and updates uniforms each frame.
 *
 * ─── Lua example  (assets/shaders/wave.lua) ──────────────────────────────────
 *
 *   frag = [[
 *     #pragma header
 *     uniform float uTime;
 *     void main() {
 *       vec2 uv = openfl_TextureCoordv;
 *       uv.x += sin(uv.y * 20.0 + uTime * 3.0) * 0.01;
 *       gl_FragColor = flixel_texture2D(bitmap, uv);
 *     }
 *   ]]
 *
 *   -- vert = [[ ... ]]   -- optional vertex shader
 *
 *   local time = 0.0
 *   function onUpdate(elapsed)
 *       time = time + elapsed
 *       setUniform("uTime", time)
 *   end
 *
 * ─── HScript example  (assets/shaders/wave.hx) ───────────────────────────────
 *
 *   var frag = "
 *     #pragma header
 *     uniform float uTime;
 *     void main() {
 *       vec2 uv = openfl_TextureCoordv;
 *       uv.x += sin(uv.y * 20.0 + uTime * 3.0) * 0.01;
 *       gl_FragColor = flixel_texture2D(bitmap, uv);
 *     }
 *   ";
 *
 *   var time = 0.0;
 *   function onUpdate(elapsed:Float) {
 *     time += elapsed;
 *     setUniform("uTime", time);
 *   }
 *
 * ─── API available inside every shader script ─────────────────────────────────
 *
 *   frag            String — GLSL fragment source (required)
 *   vert            String — GLSL vertex source   (optional)
 *
 *   setUniform(name, value)        — set any uniform (float, int, bool, array)
 *   setFloat(name, v)              — set float uniform
 *   setFloat2(name, x, y)          — set vec2 uniform
 *   setFloat3(name, x, y, z)       — set vec3 uniform
 *   setFloat4(name, x, y, z, w)    — set vec4 uniform
 *   setInt(name, v)                — set int uniform
 *   setBool(name, v)               — set bool uniform
 *   setColor(name, hexColor)       — set vec4 from 0xAARRGGBB color int
 *
 *   recompile()                    — recompile the shader (re-reads frag/vert from script)
 *
 *   width, height                  — FlxG.width / FlxG.height
 *
 * ─── Callbacks ────────────────────────────────────────────────────────────────
 *
 *   onCreate()               called once after the shader is compiled
 *   onUpdate(elapsed)        called every frame while the shader is active
 *   onDestroy()              called when the shader is unloaded
 */
class ScriptShader
{
	/** Shader name (filename without extension). */
	public var name(default, null):String;

	/** Path of the script file that defines this shader. */
	public var scriptPath(default, null):String;

	/** The compiled runtime shader.  null until the script has run. */
	public var shader(default, null):Null<FunkinRuntimeShader>;

	/** Whether the shader compiled and the script is active. */
	public var active(default, null):Bool = false;

	// ── Internal script handles ───────────────────────────────────────────────

	#if (LUA_ALLOWED && linc_luajit)
	var _lua:Null<RuleScriptInstance>;
	#end

	#if HSCRIPT_ALLOWED
	var _hscript:Null<HScriptInstance>;
	#end

	var _isLua:Bool;

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new(name:String, scriptPath:String)
	{
		this.name       = name;
		this.scriptPath = scriptPath;
		this._isLua     = scriptPath.endsWith('.lua');
	}

	// ── Load ──────────────────────────────────────────────────────────────────

	/**
	 * Loads and executes the script, reads frag/vert variables,
	 * compiles the runtime shader, and calls onCreate().
	 */
	public function load():Bool
	{
		#if !sys
		trace('[ScriptShader] sys not available — cannot load $scriptPath');
		return false;
		#else
		if (!FileSystem.exists(scriptPath))
		{
			trace('[ScriptShader] File not found: $scriptPath');
			return false;
		}

		if (_isLua)
			return _loadLua();
		else
			return _loadHScript();
		#end
	}

	// ── Update ────────────────────────────────────────────────────────────────

	/** Call this every frame (e.g. from ShaderManager.update). */
	public function update(elapsed:Float):Void
	{
		if (!active) return;
		_call('onUpdate', [elapsed]);
	}

	// ── Destroy ───────────────────────────────────────────────────────────────

	public function destroy():Void
	{
		_call('onDestroy', []);
		active = false;

		#if (LUA_ALLOWED && linc_luajit)
		if (_lua != null) { _lua.destroy(); _lua = null; }
		#end

		#if HSCRIPT_ALLOWED
		if (_hscript != null) { _hscript.dispose(); _hscript = null; }
		#end

		shader = null;
	}

	// ── Hot-reload ────────────────────────────────────────────────────────────

	/** Reloads the script from disk and recompiles the shader. */
	public function hotReload():Bool
	{
		final prevShader = shader;
		destroy();
		final ok = load();
		if (!ok) shader = prevShader; // restore on failure
		return ok;
	}

	// ── Internals ─────────────────────────────────────────────────────────────

	#if sys
	function _loadLua():Bool
	{
		#if (LUA_ALLOWED && linc_luajit)
		_lua = new RuleScriptInstance(name, scriptPath);

		// Expose shader-writing API BEFORE the script runs so inline code
		// (outside any function) can call setUniform() at top-level.
		_exposeLuaAPI(_lua);

		_lua.loadFile(scriptPath);

		if (!_lua.active)
		{
			trace('[ScriptShader] Lua error in: $scriptPath');
			_lua.destroy();
			_lua = null;
			return false;
		}

		return _compileFromScript();
		#else
		trace('[ScriptShader] LUA_ALLOWED / linc_luajit not enabled.');
		return false;
		#end
	}

	function _loadHScript():Bool
	{
		#if HSCRIPT_ALLOWED
		final src = File.getContent(scriptPath);
		_hscript   = new HScriptInstance(name, scriptPath);

		try
		{
			_hscript.program = ScriptHandler.parser.parseString(src, scriptPath);
			_hscript.interp  = new Interp();

			// Expose shader API
			_exposeHScriptAPI(_hscript.interp);

			_hscript.interp.execute(_hscript.program);
		}
		catch (e:Dynamic)
		{
			trace('[ScriptShader] HScript error in $scriptPath: $e');
			_hscript.dispose();
			_hscript = null;
			return false;
		}

		return _compileFromScript();
		#else
		trace('[ScriptShader] HSCRIPT_ALLOWED not enabled.');
		return false;
		#end
	}

	function _compileFromScript():Bool
	{
		// Read frag and optional vert from the script
		final frag:Null<String> = cast _get('frag');
		final vert:Null<String> = cast _get('vert');

		if (frag == null || StringTools.trim(frag) == '')
		{
			trace('[ScriptShader] "$name" did not define a "frag" variable — skipping.');
			return false;
		}

		try
		{
			shader = new FunkinRuntimeShader(frag, vert);
			active = true;

			// Now that shader is compiled, expose the real uniform-writing functions
			// (they need the shader instance to exist first)
			_exposeUniformAPI();

			// onCreate
			_call('onCreate', []);

			trace('[ScriptShader] "$name" compiled OK${vert != null ? " (with vertex)" : ""}');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[ScriptShader] "$name" shader compile error: $e');
			shader = null;
			active = false;
			return false;
		}
	}
	#end

	// ── Uniform helpers ───────────────────────────────────────────────────────

	/** Exposes uniform-writing stubs BEFORE compilation (so top-level code doesn't crash). */
	#if (LUA_ALLOWED && linc_luajit)
	function _exposeLuaAPI(s:RuleScriptInstance):Void
	{
		// Stubs — replaced by real implementations after shader compiles
		s.set('setUniform',  function(n:String, v:Dynamic) _setUniform(n, v));
		s.set('setFloat',    function(n:String, v:Float)   _setFloat(n, v));
		s.set('setFloat2',   function(n:String, x:Float, y:Float) _setFloat2(n, x, y));
		s.set('setFloat3',   function(n:String, x:Float, y:Float, z:Float) _setFloat3(n, x, y, z));
		s.set('setFloat4',   function(n:String, x:Float, y:Float, z:Float, w:Float) _setFloat4(n, x, y, z, w));
		s.set('setInt',      function(n:String, v:Int)     _setInt(n, v));
		s.set('setBool',     function(n:String, v:Bool)    _setBool(n, v));
		s.set('setColor',    function(n:String, c:Int)     _setColor(n, c));
		s.set('recompile',   function() _recompileFromScript());
		s.set('width',       flixel.FlxG.width);
		s.set('height',      flixel.FlxG.height);
	}
	#end

	#if HSCRIPT_ALLOWED
	function _exposeHScriptAPI(interp:Interp):Void
	{
		interp.variables.set('setUniform',  function(n:String, v:Dynamic) _setUniform(n, v));
		interp.variables.set('setFloat',    function(n:String, v:Float)   _setFloat(n, v));
		interp.variables.set('setFloat2',   function(n:String, x:Float, y:Float) _setFloat2(n, x, y));
		interp.variables.set('setFloat3',   function(n:String, x:Float, y:Float, z:Float) _setFloat3(n, x, y, z));
		interp.variables.set('setFloat4',   function(n:String, x:Float, y:Float, z:Float, w:Float) _setFloat4(n, x, y, z, w));
		interp.variables.set('setInt',      function(n:String, v:Int)     _setInt(n, v));
		interp.variables.set('setBool',     function(n:String, v:Bool)    _setBool(n, v));
		interp.variables.set('setColor',    function(n:String, c:Int)     _setColor(n, c));
		interp.variables.set('recompile',   function() _recompileFromScript());
		interp.variables.set('width',       flixel.FlxG.width);
		interp.variables.set('height',      flixel.FlxG.height);
	}
	#end

	/**
	 * Called after shader compiles. Functions now do real GL writes.
	 * (The closures already close over `this`, so they automatically use
	 * the newly assigned `shader` field — nothing extra needed here.)
	 */
	function _exposeUniformAPI():Void {} // closures capture `this.shader` via `_setX` methods

	// ── Uniform dispatch ─────────────────────────────────────────────────────

	function _setUniform(name:String, value:Dynamic):Void
	{
		if (shader == null) return;
		shader.writeUniform(name, value);
		ShaderManager.setShaderParam(this.name, name, value);
	}

	function _setFloat(name:String, v:Float):Void
	{
		if (shader == null) return;
		shader.setFloat(name, v);
		ShaderManager.setShaderParam(this.name, name, v);
	}

	function _setFloat2(name:String, x:Float, y:Float):Void
	{
		if (shader == null) return;
		shader.setFloat2(name, x, y);
		ShaderManager.setShaderParam(this.name, name, [x, y]);
	}

	function _setFloat3(name:String, x:Float, y:Float, z:Float):Void
	{
		if (shader == null) return;
		shader.setFloat3(name, x, y, z);
		ShaderManager.setShaderParam(this.name, name, [x, y, z]);
	}

	function _setFloat4(name:String, x:Float, y:Float, z:Float, w:Float):Void
	{
		if (shader == null) return;
		shader.setFloat4(name, x, y, z, w);
		ShaderManager.setShaderParam(this.name, name, [x, y, z, w]);
	}

	function _setInt(name:String, v:Int):Void
	{
		if (shader == null) return;
		shader.safeSetInt(name, v);
		ShaderManager.setShaderParam(this.name, name, v);
	}

	function _setBool(name:String, v:Bool):Void
	{
		if (shader == null) return;
		shader.setBool(name, v);
		ShaderManager.setShaderParam(this.name, name, v);
	}

	function _setColor(name:String, color:Int):Void
	{
		if (shader == null) return;
		shader.setColor(name, flixel.util.FlxColor.fromInt(color));
		ShaderManager.setShaderParam(this.name, name, color);
	}

	function _recompileFromScript():Void
	{
		final frag:Null<String> = cast _get('frag');
		final vert:Null<String> = cast _get('vert');
		if (frag == null || shader == null) return;
		shader.recompile(frag, vert);
		trace('[ScriptShader] "$name" recompiled.');
	}

	// ── Script call / get helpers ─────────────────────────────────────────────

	function _call(fn:String, args:Array<Dynamic>):Dynamic
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (_lua != null && _lua.active) return _lua.call(fn, args);
		#end
		#if HSCRIPT_ALLOWED
		if (_hscript != null && _hscript.active) return _hscript.call(fn, args);
		#end
		return null;
	}

	function _get(varName:String):Dynamic
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (_lua != null && _lua.active) return _lua.get(varName);
		#end
		#if HSCRIPT_ALLOWED
		if (_hscript != null && _hscript.active)
		{
			#if HSCRIPT_ALLOWED
			if (_hscript.interp != null) return _hscript.interp.variables.get(varName);
			#end
		}
		#end
		return null;
	}
}
