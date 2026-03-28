package funkin.scripting;

import haxe.Exception;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if HSCRIPT_ALLOWED
import hscript.Parser;
import hscript.Interp;
#end

using StringTools;

/**
 * ScriptHandler v4 — central script management for gameplay and mods.
 *
 * ─── Script layers ───────────────────────────────────────────────────────────
 *
 *   global   → always active (entire game session)
 *   stage    → active during the current stage
 *   song     → active during the current song
 *   ui       → HUD / UIScriptedManager scripts
 *   menu     → state and menu scripts (FreeplayState, TitleState, etc.)
 *   char     → scripts for a specific character
 *
 * ─── Full folder structure ───────────────────────────────────────────────────
 *
 *   BASE GAME:
 *   assets/data/scripts/global/          → base global scripts
 *   assets/data/scripts/events/          → custom event handlers
 *   assets/songs/{song}/scripts/         → song scripts
 *   assets/songs/{song}/events/          → song-specific custom events
 *   assets/stages/{stage}/scripts/       → stage scripts
 *   assets/characters/{char}/scripts/    → character scripts
 *   assets/states/{state}/              → state / menu scripts
 *
 *   MODS:
 *   mods/{mod}/scripts/global/           → mod global scripts
 *   mods/{mod}/scripts/events/
 *   mods/{mod}/songs/{song}/scripts/
 *   mods/{mod}/songs/{song}/events/
 *   mods/{mod}/stages/{stage}/scripts/
 *   mods/{mod}/characters/{char}/scripts/
 *   mods/{mod}/states/{state}/
 *   mods/{mod}/data/scripts/             → extra alias
 *
 *   PSYCH-COMPAT (additional recognised paths):
 *   mods/{mod}/custom_events/{event}.hx
 *   mods/{mod}/custom_notetypes/{type}.hx
 *
 * ─── Script types supported ──────────────────────────────────────────────────
 *  .hx / .hscript  → HScriptInstance  (requires HSCRIPT_ALLOWED)
 *  .lua            → RuleScriptInstance (requires LUA_ALLOWED + linc_luajit)
 *                    Full LuaJIT OOP bridge — import(), overrideMethod(),
 *                    require(), custom classes, direct Haxe field access.
 *
 * @author Cool Engine Team
 * @version 4.0.0
 */
class ScriptHandler
{
	// ── Almacenamiento de scripts por capa ────────────────────────────────────

	public static var globalScripts : Map<String, HScriptInstance> = [];
	public static var stageScripts  : Map<String, HScriptInstance> = [];
	public static var songScripts   : Map<String, HScriptInstance> = [];
	public static var uiScripts     : Map<String, HScriptInstance> = [];
	public static var menuScripts   : Map<String, HScriptInstance> = [];
	public static var charScripts   : Map<String, HScriptInstance> = [];

	#if (LUA_ALLOWED && linc_luajit)
	// RuleScript layers — one array per gameplay context (same structure as HScript layers)
	public static var globalLuaScripts : Array<RuleScriptInstance> = [];
	public static var stageLuaScripts  : Array<RuleScriptInstance> = [];
	public static var songLuaScripts   : Array<RuleScriptInstance> = [];
	public static var uiLuaScripts     : Array<RuleScriptInstance> = [];
	public static var menuLuaScripts   : Array<RuleScriptInstance> = [];
	public static var charLuaScripts   : Array<RuleScriptInstance> = [];
	#end

	/**
	 * Index of character scripts grouped by name.
	 * Allows callOnCharacterScripts in O(1) instead of iterating all charScripts.
	 * Populated by loadCharacterScripts and cleared by destroy().
	 */
	public static var charScriptsByName : Map<String, Array<HScriptInstance>> = [];

	// ── Reusable hot-path arrays (avoid allocating new Array every frame) ────
	// Every gameplay callback (onUpdate, onBeatHit, onStepHit,
	// onNoteHit, onMiss…) passes its args through these static arrays instead
	// of creating a new Array<Dynamic> on each call.
	// IMPORTANT: These arrays are temporary — only valid during the
	// callOnScripts call. Do NOT store references to them in scripts.

	/** For onUpdate(elapsed:Float) */
	public static final _argsUpdate   : Array<Dynamic> = [0.0];
	/** For onUpdatePost(elapsed:Float) */
	public static final _argsUpdatePost: Array<Dynamic> = [0.0];
	/** For onBeatHit(beat:Int) */
	public static final _argsBeat     : Array<Dynamic> = [0];
	/** For onStepHit(step:Int) */
	public static final _argsStep     : Array<Dynamic> = [0];
	/** For onNoteHit / onMiss — [note, extra] */
	public static final _argsNote     : Array<Dynamic> = [null, null];
	/** For events with a single generic argument */
	public static final _argsOne      : Array<Dynamic> = [null];
	/** Reusable empty array — for no-argument callbacks */
	public static final _argsEmpty    : Array<Dynamic> = [];
	/** For onAnimStart/onSingStart/onSingEnd in character scripts — [arg0, arg1] */
	public static final _argsAnim     : Array<Dynamic> = [null, null];

	// ── Parser compartido ─────────────────────────────────────────────────────

	#if HSCRIPT_ALLOWED
	static var _parser:Parser = null;

	public static var parser(get, null):Parser;
	static function get_parser():Parser
	{
		if (_parser == null)
		{
			_parser = new Parser();
			_parser.allowTypes = true;
			_parser.allowJSON  = true;
			// allowMetadata fue añadido en hscript 2.5. Guard seguro:
			try { Reflect.setField(_parser, 'allowMetadata', true); } catch(_) {}
		}
		return _parser;
	}
	#end

	// ── Init ──────────────────────────────────────────────────────────────────

	public static function init():Void
	{
		loadGlobalScripts();
		trace('[ScriptHandler v4] Ready.');
	}

	/**
	 * Loads all global scripts: base + mods + custom_events (Psych compat).
	 */
	public static function loadGlobalScripts():Void
	{
		// Clear previous global scripts to avoid duplicates on the 2nd playthrough
		_destroyLayer(globalScripts);
		globalScripts.clear();

		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			// Standard mod paths
			_loadFolder('$r/scripts/global',   'global');
			_loadFolder('$r/scripts/events',   'global');
			_loadFolder('$r/data/scripts',     'global');
			_loadFolder('$r/data/config', 'global');
			// Psych-compat paths
			_loadFolder('$r/custom_events',    'global');
			_loadFolder('$r/custom_notetypes', 'global');
		}
		#end
		_loadFolder('assets/data/scripts/global', 'global');
		_loadFolder('assets/data/scripts/events', 'global');
		trace('[ScriptHandler v4] Global scripts loaded.');
	}

	// ── Context loading ───────────────────────────────────────────────────────

	/** Loads scripts for song `songName` from base + mod. */
	public static function loadSongScripts(songName:String):Void
	{
		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			_loadFolder('$r/songs/$songName/scripts', 'song');
			_loadFolder('$r/songs/$songName/events',  'song');
			// Psych Engine layout: scripts live in data/{songName}/ alongside the chart
			_loadFolder('$r/data/$songName', 'song');
		}
		#end
		_loadFolder('assets/songs/$songName/scripts', 'song');
		_loadFolder('assets/songs/$songName/events',  'song');
	}

	/** Loads scripts for stage `stageName` from base + mod. */
	public static function loadStageScripts(stageName:String):Void
	{
		final sn = stageName.toLowerCase();
		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			_loadFolder('$r/stages/$sn/scripts',        'stage');
			_loadFolder('$r/assets/stages/$sn/scripts', 'stage');
		}
		#end
		_loadFolder('assets/stages/$sn/scripts',       'stage');
		_loadFolder('assets/data/stages/$sn/scripts',  'stage');
	}

	/**
	 * Loads scripts for character `charName` from base + mod.
	 * Scripts are tagged with `charName` so they can be filtered later.
	 * Returns the list of loaded scripts so the caller can inject variables.
	 *
	 *  ── Search paths (priority order) ───────────────────────────────────────
	 *
	 *   Canonical new path (recommended):
	 *     assets/characters/scripts/{char}/scripts.hx
	 *     mods/{mod}/characters/scripts/{char}/scripts.hx
	 *
	 *   Legacy paths (still work for backward compat):
	 *     assets/characters/{char}/scripts/              ← folder with multiple .hx
	 *     mods/{mod}/characters/{char}/scripts/
	 *     mods/{mod}/characters/{char}/                  ← loose .hx (legacy)
	 */
	public static function loadCharacterScripts(charName:String):Array<HScriptInstance>
	{
		final loaded:Array<HScriptInstance> = [];
		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			// ── Nueva ruta canónica (mod) ────────────────────────────────────
			for (s in _loadFolder('$r/characters/scripts/$charName', 'char')) loaded.push(s);
			// ── Rutas heredadas (mod) — compat con mods anteriores ───────────
			for (s in _loadFolder('$r/characters/$charName/scripts', 'char')) loaded.push(s);
			for (s in _loadFolder('$r/characters/$charName',         'char')) loaded.push(s);
		}
		#end
		// ── Nueva ruta canónica (base game) ─────────────────────────────────
		for (s in _loadFolder('assets/characters/scripts/$charName', 'char')) loaded.push(s);
		// ── Ruta heredada (base game) ────────────────────────────────────────
		for (s in _loadFolder('assets/characters/$charName/scripts', 'char')) loaded.push(s);
		// Taggear y registrar en el índice por nombre
		if (loaded.length > 0)
		{
			for (s in loaded) s.tag = charName;
			if (!charScriptsByName.exists(charName))
				charScriptsByName.set(charName, []);
			for (s in loaded)
				charScriptsByName.get(charName).push(s);
		}
		return loaded;
	}

	/**
	 * Calls `func` on scripts for character `charName`.
	 * Uses charScriptsByName for O(1) lookup — does not iterate all charScripts.
	 */
	public static function callOnCharacterScripts(charName:String, func:String, args:Array<Dynamic>):Void
	{
		#if HSCRIPT_ALLOWED
		final list = charScriptsByName.get(charName);
		if (list == null) return; // fast guard: no scripts for this character
		for (script in list)
			if (script.active) script.call(func, args);
		#end
	}

	/**
	 * Like callOnCharacterScripts but returns true if any script returns true.
	 * (Used to cancel default behaviour: `return true` in overrideDance, etc.)
	 */
	public static function callOnCharacterScriptsReturn(charName:String, func:String, args:Array<Dynamic>):Bool
	{
		#if HSCRIPT_ALLOWED
		final list = charScriptsByName.get(charName);
		if (list == null) return false; // fast guard
		var result = false;
		for (script in list)
			if (script.active && script.call(func, args) == true) result = true;
		return result;
		#else
		return false;
		#end
	}

	/**
	 * Injects variables into scripts for a specific character.
	 * Uses charScriptsByName for O(1) lookup.
	 */
	public static function setOnCharacterScripts(charName:String, varName:String, value:Dynamic):Void
	{
		#if HSCRIPT_ALLOWED
		final list = charScriptsByName.get(charName);
		if (list == null) return;
		for (script in list)
			if (script.interp != null)
				script.interp.variables.set(varName, value);
		#end
	}

	/**
	 * Loads scripts for state/menu `stateName`.
	 * Searches in `assets/states/{stateName}/` and `mods/{mod}/states/{stateName}/`.
	 */
	public static function loadStateScripts(stateName:String):Void
	{
		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			_loadFolder('$r/states/$stateName', 'menu');
		}
		#end
		_loadFolder('assets/states/$stateName', 'menu');
	}

	// ── Individual script loading ─────────────────────────────────────────────

	/**
	 * Loads a script from `scriptPath`.
	 * Supports native .hx / .hscript and .lua (Psych-compat transpilation).
	 *
	 * @param presetVars  Variables injected BEFORE execute() (top-level code sees them).
	 * @param stage       Stage reference for the Psych Lua API shim.
	 */
	public static function loadScript(scriptPath:String, scriptType:String = 'song',
		?presetVars:Map<String, Dynamic>,
		?stage:funkin.gameplay.objects.stages.Stage):Null<HScriptInstance>
	{
		#if HSCRIPT_ALLOWED

		#if sys
		if (!FileSystem.exists(scriptPath))
		{
			trace('[ScriptHandler] not found: $scriptPath');
			return null;
		}
		#end

		final isLua      = scriptPath.endsWith('.lua');
		final rawContent = #if sys File.getContent(scriptPath) #else '' #end;

		final content = isLua
			? mods.compat.LuaStageConverter.convert(rawContent, _extractName(scriptPath))
			: rawContent;

		if (isLua) trace('[ScriptHandler] Transpiling Lua: $scriptPath');

		final scriptName = _extractName(scriptPath);
		final script     = new HScriptInstance(scriptName, scriptPath);
		// Cache the processed source so _handleError can show the exact failing line
		// for runtime errors that occur later during call() invocations.
		script._source   = content;

		try
		{
			script.interp  = new Interp();

			ScriptAPI.expose(script.interp);

			script.interp.variables.set('require', function(path:String):Dynamic return script.require(path));
			script.interp.variables.set('log', function(msg:Dynamic):Void trace('[Script:$scriptName] $msg'));

			if (presetVars != null)
				for (k => v in presetVars)
					script.interp.variables.set(k, v);

			if (isLua)
				mods.compat.PsychLuaGameplayAPI.expose(script.interp);

			if (isLua && stage != null)
				mods.compat.PsychLuaStageAPI.expose(script.interp, stage);

			// ── HScript: pre-process imports BEFORE first parse ──────────────
			// processImports() replaces import lines with comments and injects
			// classes into interp.variables. We do it once here and only parse
			// the (possibly modified) source — avoiding the double-parse that
			// happened before when we parsed rawContent and then parsed again.
			#if HSCRIPT_ALLOWED
			final finalContent = isLua ? content : processImports(content, script.interp);
			if (finalContent != content) script._source = finalContent;
			script.program = parser.parseString(finalContent, scriptPath);
			#else
			script.program = parser.parseString(content, scriptPath);
			#end

			script.interp.execute(script.program);

			if (isLua)
				mods.compat.PsychLuaGameplayAPI.setupCallbackAliases(script);

			script.call('onCreate');
			script.call('postCreate');

			_registerScript(script, scriptType);
			trace('[ScriptHandler] Loaded [$scriptType]: $scriptName${isLua ? " (Lua)" : ""}');
			return script;
		}
		catch (e:Dynamic)
		{
			// Extract line number from the parse/runtime error for a pinpointed message
			var lineInfo = '';
			try
			{
				if (Reflect.hasField(e, 'line'))
				{
					lineInfo = ':${Reflect.field(e, 'line')}';
				}
				else if (Reflect.hasField(e, 'pmin'))
				{
					final pmin:Int = Reflect.field(e, 'pmin');
					// Count newlines up to pmin to get the 1-based line number
					var lineNum = 1;
					final len   = Std.int(Math.min(pmin, content.length));
					for (i in 0...len)
						if (content.charAt(i) == '\n') lineNum++;
					lineInfo = ':$lineNum';
				}
			}
			catch (_e:Dynamic) {}

			trace('[ScriptHandler] Error loading "$scriptName$lineInfo": ${Std.string(e)}');
			if (isLua) trace('[ScriptHandler] Transpiled code:\n$content');
			return null;
		}

		#else
		trace('[ScriptHandler] HSCRIPT_ALLOWED not defined in Project.xml — scripts disabled.');
		return null;
		#end
	}

	/**
	 * Like loadScript() but does NOT call onCreate/postCreate automatically.
	 * Use when the caller needs to inject additional APIs BEFORE the first onCreate.
	 * The script is parsed, ScriptAPI is exposed, and the program is executed (functions defined).
	 * The caller is responsible for calling script.call('onCreate') when ready.
	 */
	public static function loadScriptNoInit(scriptPath:String, scriptType:String = 'song',
		?presetVars:Map<String, Dynamic>):Null<HScriptInstance>
	{
		#if HSCRIPT_ALLOWED

		#if sys
		if (!FileSystem.exists(scriptPath))
		{
			trace('[ScriptHandler] not found: $scriptPath');
			return null;
		}
		#end

		final isLuaNoInit = scriptPath.endsWith('.lua');
		final rawContentNoInit = #if sys File.getContent(scriptPath) #else '' #end;
		final rawContent = isLuaNoInit
			? mods.compat.LuaStageConverter.convert(rawContentNoInit, _extractName(scriptPath))
			: rawContentNoInit;
		final scriptName = _extractName(scriptPath);
		final script     = new HScriptInstance(scriptName, scriptPath);
		// Cache source so _handleError can show the exact failing line on runtime errors
		script._source   = rawContent;

		try
		{
			script.interp  = new Interp();

			ScriptAPI.expose(script.interp);

			script.interp.variables.set('require', function(path:String):Dynamic return script.require(path));
			script.interp.variables.set('log', function(msg:Dynamic):Void trace('[Script:$scriptName] $msg'));

			if (presetVars != null)
				for (k => v in presetVars)
					script.interp.variables.set(k, v);

			if (isLuaNoInit)
				mods.compat.PsychLuaGameplayAPI.expose(script.interp);

			// ── HScript: pre-process imports BEFORE first parse ──────────────
			#if HSCRIPT_ALLOWED
			final finalRaw = isLuaNoInit ? rawContent : processImports(rawContent, script.interp);
			if (finalRaw != rawContent) script._source = finalRaw;
			script.program = parser.parseString(finalRaw, scriptPath);
			#else
			script.program = parser.parseString(rawContent, scriptPath);
			#end

			script.interp.execute(script.program);

			if (isLuaNoInit)
				mods.compat.PsychLuaGameplayAPI.setupCallbackAliases(script);

			_registerScript(script, scriptType);
			trace('[ScriptHandler] Loaded no-init [$scriptType]: $scriptName');
			return script;
		}
		catch (e:Dynamic)
		{
			// Extract line number from the parse/runtime error for a pinpointed message
			var lineInfo = '';
			try
			{
				if (Reflect.hasField(e, 'line'))
				{
					lineInfo = ':${Reflect.field(e, 'line')}';
				}
				else if (Reflect.hasField(e, 'pmin'))
				{
					final pmin:Int = Reflect.field(e, 'pmin');
					var lineNum = 1;
					final len   = Std.int(Math.min(pmin, rawContent.length));
					for (i in 0...len)
						if (rawContent.charAt(i) == '\n') lineNum++;
					lineInfo = ':$lineNum';
				}
			}
			catch (_e:Dynamic) {}

			trace('[ScriptHandler] Error loading "$scriptName$lineInfo": ${Std.string(e)}');
			return null;
		}

		#else
		trace('[ScriptHandler] HSCRIPT_ALLOWED not defined — scripts disabled.');
		return null;
		#end
	}

	/** Loads all `.hx` / `.hscript` / `.lua` files from a folder. */
	public static function loadScriptsFromFolder(folderPath:String, scriptType:String = 'song'):Array<HScriptInstance>
	{
		return _loadFolder(folderPath, scriptType);
	}

	/** Loads scripts from an explicit list of paths. */
	public static function loadScriptsFromArray(paths:Array<String>, scriptType:String = 'stage'):Array<HScriptInstance>
	{
		final out:Array<HScriptInstance> = [];
		for (p in paths)
		{
			final s = loadScript(p, scriptType);
			if (s != null) out.push(s);
		}
		return out;
	}

	// ── Script calls ─────────────────────────────────────────────────────────

	/**
	 * Calls `funcName(args)` on ALL scripts in ALL layers.
	 * Order: global → stage → song → ui → menu → char.
	 */
	public static function callOnScripts(funcName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		_callLayer(globalScripts, funcName, args);
		_callLayer(stageScripts,  funcName, args);
		_callLayer(songScripts,   funcName, args);
		_callLayer(uiScripts,     funcName, args);
		_callLayer(menuScripts,   funcName, args);
		_callLayer(charScripts,   funcName, args);
	
		#if (LUA_ALLOWED && linc_luajit)
		_callLuaLayer(globalLuaScripts, funcName, args);
		_callLuaLayer(stageLuaScripts,  funcName, args);
		_callLuaLayer(songLuaScripts,   funcName, args);
		_callLuaLayer(uiLuaScripts,     funcName, args);
		_callLuaLayer(menuLuaScripts,   funcName, args);
		_callLuaLayer(charLuaScripts,   funcName, args);
		#end
	}

	/**
	 * Like callOnScripts but returns the first non-null / non-defaultValue result.
	 * If any script returns `true` (cancel), propagation stops.
	 * No intermediate array allocation — iterates layers directly.
	 */
	public static function callOnScriptsReturn(funcName:String, args:Array<Dynamic> = null, defaultValue:Dynamic = null):Dynamic
	{
		if (args == null) args = _argsEmpty;
		// Iterate layers directly without creating an Array "layers" each call
		#if HSCRIPT_ALLOWED
		function _checkLayer(layer:Map<String, HScriptInstance>):Dynamic {
			for (script in layer) {
				if (!script.active) continue;
				final r = script.call(funcName, args);
				if (r != null && r != defaultValue) return r;
			}
			return null;
		}
		var r:Dynamic;
		r = _checkLayer(globalScripts); if (r != null) return r;
		r = _checkLayer(stageScripts);  if (r != null) return r;
		r = _checkLayer(songScripts);   if (r != null) return r;
		r = _checkLayer(uiScripts);     if (r != null) return r;
		r = _checkLayer(menuScripts);   if (r != null) return r;
		r = _checkLayer(charScripts);   if (r != null) return r;
		#end
		return defaultValue;
	}

	/** Injects a variable into all active scripts. */
	public static function setOnScripts(varName:String, value:Dynamic):Void
	{
		// No intermediate Array "layers" allocation
		function _setLayer(layer:Map<String, HScriptInstance>):Void
			for (script in layer) if (script.active) script.set(varName, value);
		_setLayer(globalScripts);
		_setLayer(stageScripts);
		_setLayer(songScripts);
		_setLayer(uiScripts);
		_setLayer(menuScripts);
		_setLayer(charScripts);
	
		#if (LUA_ALLOWED && linc_luajit)
		function _setLua(layer:Array<RuleScriptInstance>):Void
			for (lua in layer) if (lua.active) lua.set(varName, value);
		_setLua(globalLuaScripts); _setLua(stageLuaScripts); _setLua(songLuaScripts);
		_setLua(uiLuaScripts);     _setLua(menuLuaScripts);  _setLua(charLuaScripts);
		#end
	}

	/**
	 * Injects all public fields of a PlayState into every active script.
	 *
	 * OPTIMIZACIÓN: en lugar de llamar setOnScripts() una vez por campo
	 * (lo que iteraba los 6 layers N veces, N = nº de campos ≈ 80+),
	 * construimos el mapa de vars una sola vez y hacemos UNA pasada por
	 * todos los scripts, inyectando el batch entero con interp.variables.set().
	 * 80 campos × 6 layers × M scripts → 1 construcción + 1 pasada total.
	 */
	public static function injectPlayState(ps:funkin.gameplay.PlayState):Void
	{
		if (ps == null) return;

		// ── Construir el batch de variables una sola vez ───────────────────
		final vars:Map<String, Dynamic> = [];
		vars.set('game',      ps);
		vars.set('playState', ps);

		for (field in Type.getInstanceFields(funkin.gameplay.PlayState))
		{
			if (field.startsWith('_')) continue;
			try {
				final val = Reflect.getProperty(ps, field);
				if (!Reflect.isFunction(val)) vars.set(field, val);
			} catch (_e:Dynamic) {}
		}
		for (field in Type.getClassFields(funkin.gameplay.PlayState))
		{
			if (field.startsWith('_')) continue;
			try {
				final val = Reflect.getProperty(funkin.gameplay.PlayState, field);
				if (!Reflect.isFunction(val)) vars.set(field, val);
			} catch (_e:Dynamic) {}
		}
		if (ps.boyfriend    != null) vars.set('bf',    ps.boyfriend);
		if (ps.dad          != null) vars.set('dad',   ps.dad);
		if (ps.gf           != null) vars.set('gf',    ps.gf);
		if (ps.currentStage != null) vars.set('stage', ps.currentStage);

		// ── Inyectar el batch en una sola pasada por scripts ──────────────
		function _injectLayer(layer:Map<String, HScriptInstance>):Void {
			for (script in layer)
				if (script.active && script.interp != null)
					for (k => v in vars)
						script.interp.variables.set(k, v);
		}
		_injectLayer(globalScripts);
		_injectLayer(stageScripts);
		_injectLayer(songScripts);
		_injectLayer(uiScripts);
		_injectLayer(menuScripts);
		_injectLayer(charScripts);
	}

	/** Injects a variable only into stage scripts. */
	public static function setOnStageScripts(varName:String, value:Dynamic):Void
	{
		for (script in stageScripts)
			if (script.active) script.set(varName, value);
	}

	/** Calls a function only in stage scripts. */
	public static function callOnStageScripts(funcName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		_callLayer(stageScripts, funcName, args);
	}

	/**
	 * Calls a function on all layers EXCEPT stageScripts.
	 * Use when stage scripts already fired the event in loadStageScripts()
	 * and a second execution would overwrite the correct state.
	 */
	public static function callOnNonStageScripts(funcName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		_callLayer(globalScripts, funcName, args);
		_callLayer(songScripts,   funcName, args);
		_callLayer(uiScripts,     funcName, args);
		_callLayer(menuScripts,   funcName, args);
		_callLayer(charScripts,   funcName, args);
	}

	/** Gets the value of a variable from active scripts (first non-null result). */
	public static function getFromScripts(varName:String, defaultValue:Dynamic = null):Dynamic
	{
		// No alloc: iterate layers directly instead of building an Array each call.
		function _check(layer:Map<String, HScriptInstance>):Dynamic {
			for (script in layer)
				if (script.active) { final v = script.get(varName); if (v != null) return v; }
			return null;
		}
		var v:Dynamic;
		v = _check(globalScripts); if (v != null) return v;
		v = _check(stageScripts);  if (v != null) return v;
		v = _check(songScripts);   if (v != null) return v;
		v = _check(uiScripts);     if (v != null) return v;
		v = _check(menuScripts);   if (v != null) return v;
		v = _check(charScripts);   if (v != null) return v;
		return defaultValue;
	}

	// ── Cleanup ───────────────────────────────────────────────────────────────

	public static function clearSongScripts():Void
	{
		_destroyLayer(songScripts);
		_destroyLayer(uiScripts);
		songScripts.clear();
		uiScripts.clear();
	
		#if (LUA_ALLOWED && linc_luajit)
		_destroyLuaLayer(songLuaScripts);
		_destroyLuaLayer(uiLuaScripts);
		#end
	}

	public static function clearStageScripts():Void
	{
		_destroyLayer(stageScripts);
		stageScripts.clear();
	
		#if (LUA_ALLOWED && linc_luajit)
		_destroyLuaLayer(stageLuaScripts);
		#end
	}

	public static function clearCharScripts():Void
	{
		_destroyLayer(charScripts);
		charScripts.clear();
		charScriptsByName.clear(); // clear index too
	}

	public static function clearMenuScripts():Void
	{
		_destroyLayer(menuScripts);
		menuScripts.clear();
	}

	public static function clearAll():Void
	{
		clearSongScripts();
		clearStageScripts();
		clearCharScripts();
		clearMenuScripts();
		_destroyLayer(globalScripts);
		globalScripts.clear();
	}

	// ── Hot-reload ────────────────────────────────────────────────────────────

	/** Reloads a script by name (without restarting the interpreter). */
	public static function hotReload(name:String):Bool
	{
		// No alloc: check layers directly.
		function _tryReload(layer:Map<String, HScriptInstance>):Bool {
			if (!layer.exists(name)) return false;
			layer.get(name).hotReload();
			trace('[ScriptHandler] Hot-reload: $name');
			return true;
		}
		if (_tryReload(globalScripts)) return true;
		if (_tryReload(stageScripts))  return true;
		if (_tryReload(songScripts))   return true;
		if (_tryReload(uiScripts))     return true;
		if (_tryReload(menuScripts))   return true;
		if (_tryReload(charScripts))   return true;
		trace('[ScriptHandler] hotReload: "$name" not found.');
		return false;
	}

	/** Reloads all scripts in all layers. */
	public static function hotReloadAll():Void
	{
		final layers = [globalScripts, stageScripts, songScripts, uiScripts, menuScripts, charScripts];
		for (layer in layers) for (s in layer) s.hotReload();
		trace('[ScriptHandler] Hot-reload complete.');
	
		#if (LUA_ALLOWED && linc_luajit)
		for (lua in globalLuaScripts) lua.hotReload();
		for (lua in stageLuaScripts)  lua.hotReload();
		for (lua in songLuaScripts)   lua.hotReload();
		for (lua in uiLuaScripts)     lua.hotReload();
		for (lua in menuLuaScripts)   lua.hotReload();
		for (lua in charLuaScripts)   lua.hotReload();
		funkin.scripting.StateScriptHandler.hotReloadAll();
		#end
	}

	// ── Internals ─────────────────────────────────────────────────────────────

	static function _loadFolder(folderPath:String, scriptType:String):Array<HScriptInstance>
	{
		final out:Array<HScriptInstance> = [];
		#if sys
		if (!FileSystem.exists(folderPath) || !FileSystem.isDirectory(folderPath))
			return out;
		for (file in FileSystem.readDirectory(folderPath))
		{
			#if (LUA_ALLOWED && linc_luajit)
			if (file.endsWith('.lua'))
			{
				_loadLuaFile('$folderPath/$file', scriptType);
				continue;
			}
			#end
			if (!file.endsWith('.hx') && !file.endsWith('.hscript'))
				continue;
			final s = loadScript('$folderPath/$file', scriptType);
			if (s != null) out.push(s);
		}
		#end
		return out;
	}

	static function _registerScript(script:HScriptInstance, scriptType:String):Void
	{
		final target = switch (scriptType.toLowerCase())
		{
			case 'global': globalScripts;
			case 'stage':  stageScripts;
			case 'ui':     uiScripts;
			case 'menu':   menuScripts;
			case 'char':   charScripts;
			default:       songScripts;
		};
		// Duplicate names → numeric suffix
		var name = script.name;
		var i    = 1;
		while (target.exists(name)) name = '${script.name}_${i++}';
		script.name = name;
		target.set(name, script);
	}

	static function _callLayer(layer:Map<String, HScriptInstance>, func:String, args:Array<Dynamic>):Void
	{
		for (script in layer)
		{
			if (script.active)
			{
				#if HSCRIPT_ALLOWED
				script.call(func, args);
				#end
			}
		}
	}

	static function _destroyLayer(layer:Map<String, HScriptInstance>):Void
	{
		// BUGFIX: do NOT call onDestroy here.
		// PlayState.destroy() already calls callOnScripts('onDestroy') before
		// clearSongScripts() / clearStageScripts() / clearCharScripts(), which
		// in turn called _destroyLayer() → onDestroy was executed TWICE.
		// The second execution happened with a partially destroyed state
		// (stage elements, camGame, etc. already nulled) → crash.
		// This function now only releases the interpreter for each script.
		for (script in layer)
			script.dispose();
	}

	#if (LUA_ALLOWED && linc_luajit)
	static function _callLuaLayer(layer:Array<RuleScriptInstance>, func:String, args:Array<Dynamic>):Void
	{
		for (lua in layer) if (lua.active) lua.call(func, args);
	}

	static function _destroyLuaLayer(layer:Array<RuleScriptInstance>):Void
	{
		for (lua in layer) try lua.destroy() catch (_e:Dynamic) {};
		layer.resize(0);
	}

	/**
	 * Loads a .lua file as a RuleScriptInstance into the correct gameplay layer.
	 * RuleScript provides a full LuaJIT OOP bridge to all Haxe classes.
	 * Called automatically by _loadFolder when a .lua file is found.
	 */
	static function _loadLuaFile(path:String, scriptType:String):Null<RuleScriptInstance>
	{
		if (!FileSystem.exists(path)) return null;
		final name   = _extractName(path);
		final script = new RuleScriptInstance(name, path);

		script.loadFile(path);

		if (!script.active)
		{
			trace('[ScriptHandler] RuleScript error: $path');
			script.destroy();
			return null;
		}

		var target:Array<RuleScriptInstance> = switch (scriptType.toLowerCase())
		{
			case 'global': globalLuaScripts;
			case 'stage':  stageLuaScripts;
			case 'ui':     uiLuaScripts;
			case 'menu':   menuLuaScripts;
			case 'char':   charLuaScripts;
			default:       songLuaScripts;
		};
		target.push(script);

		script.call('onCreate');
		script.call('postCreate');
		trace('[ScriptHandler] RuleScript loaded [$scriptType]: $name');
		return script;
	}
	#end

	/** Public alias for _extractName for compatibility. */
	public static inline function extractName(path:String):String
		return _extractName(path);

	static inline function _extractName(path:String):String
	{
		var name = path.split('/').pop() ?? path;
		name = name.split('\\').pop();
		if (StringTools.contains(name, '.')) name = name.substring(0, name.lastIndexOf('.'));
		return name;
	}

	// ── Import pre-processor ──────────────────────────────────────────────────

	/**
	 * Pre-processes `import a.b.C;` and `import a.b.C as Alias;` lines
	 * from an HScript source file.
	 *
	 * Each import is resolved via Type.resolveClass / Type.resolveEnum
	 * and injected into `interp.variables` under the short name (or alias).
	 * Import lines are replaced with comments so the hscript parser
	 * does not reject them (hscript does not support the `import` syntax).
	 *
	 * Usage inside a .hx script:
	 *   import flixel.util.FlxColor;
	 *   import flixel.math.FlxMath as Math;
	 *
	 * @param source   Original source code of the script.
	 * @param interp   Interpreter into which classes will be injected.
	 * @return         Source code with import lines commented out.
	 */
	#if HSCRIPT_ALLOWED
	public static function processImports(source:String, interp:Interp):String
	{
		// Regex: import com.foo.Bar; or import com.foo.Bar as B;
		final importReg = ~/^[ \t]*import\s+([\w.]+)(?:\s+as\s+(\w+))?\s*;/gm;
		return importReg.map(source, function(r:EReg):String
		{
			final fullName  = r.matched(1);
			final alias     = r.matched(2);
			final shortName = (alias != null && alias != '') ? alias : fullName.split('.').pop();

			// IMPORTANT: If ScriptAPI.expose() already registered a hand-crafted proxy
			// for this name (e.g. FlxColor → _flxColorProxy, FlxEase → _flxEaseProxy),
			// do NOT overwrite it with the raw Haxe class/abstract resolved via reflection.
			//
			// Abstracts like FlxColor are erased at runtime — Type.resolveClass() may
			// return the underlying @:impl class, whose static fields are NOT accessible
			// via Reflect.field(). That would make FlxColor.BLACK return null in scripts.
			// The proxy exposes them as plain Int values and is always the better choice.
			if (interp.variables.exists(shortName))
			{
				trace('[ScriptHandler] import $fullName → kept existing proxy for "$shortName"');
				return '// [import] $fullName';
			}

			var resolved:Dynamic = Type.resolveClass(fullName);
			if (resolved == null) resolved = Type.resolveEnum(fullName);

			if (resolved != null)
			{
				interp.variables.set(shortName, resolved);
				trace('[ScriptHandler] import $fullName → $shortName');
			}
			else
			{
				trace('[ScriptHandler] unresolved import: $fullName (missing from build?)');
			}
			// Comment out the line so hscript does not see it
			return '// [import] $fullName';
		});
	}
	#end
}
