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
 * ScriptHandler v3 — sistema central de scripts para gameplay y mods.
 *
 * ─── Capas de script ─────────────────────────────────────────────────────────
 *
 *   global   → siempre activos (toda la sesión de juego)
 *   stage    → activos durante el stage actual
 *   song     → activos durante la canción actual
 *   ui       → scripts del HUD / UIScriptedManager
 *   menu     → scripts de estados y menús (FreeplayState, TitleState, etc.)
 *   char     → scripts de personaje específico
 *
 * ─── Estructura de carpetas MÁS COMPLETA ────────────────────────────────────
 *
 *   BASE GAME:
 *   assets/data/scripts/global/          → scripts globales base
 *   assets/data/scripts/events/          → handlers de eventos personalizados
 *   assets/songs/{song}/scripts/         → scripts de canción
 *   assets/songs/{song}/events/          → eventos custom de canción
 *   assets/stages/{stage}/scripts/       → scripts de stage
 *   assets/characters/{char}/scripts/    → scripts de personaje
 *   assets/states/{state}/              → scripts de estado / menú
 *
 *   MODS:
 *   mods/{mod}/scripts/global/           → equivalente base
 *   mods/{mod}/scripts/events/
 *   mods/{mod}/songs/{song}/scripts/
 *   mods/{mod}/songs/{song}/events/
 *   mods/{mod}/stages/{stage}/scripts/
 *   mods/{mod}/characters/{char}/scripts/
 *   mods/{mod}/states/{state}/
 *   mods/{mod}/data/scripts/             → alias adicional
 *
 *   PSYCH-COMPAT (rutas adicionales reconocidas):
 *   mods/{mod}/custom_events/{event}.hx
 *   mods/{mod}/custom_notetypes/{type}.hx
 *
 * ─── Compatibilidad de librerías ─────────────────────────────────────────────
 *  hscript 2.4.x y 2.5.x — mismo Parser/Interp API
 *  hscript anterior a allowMetadata: compilación condicional
 *
 * @author Cool Engine Team
 * @version 3.0.0
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
	public static var globalLuaScripts : Array<LuaScriptInstance> = [];
	public static var stageLuaScripts  : Array<LuaScriptInstance> = [];
	public static var songLuaScripts   : Array<LuaScriptInstance> = [];
	public static var uiLuaScripts     : Array<LuaScriptInstance> = [];
	public static var menuLuaScripts   : Array<LuaScriptInstance> = [];
	public static var charLuaScripts   : Array<LuaScriptInstance> = [];
	#end

	/**
	 * Índice de scripts de personaje agrupados por nombre.
	 * Permite callOnCharacterScripts en O(1) en vez de iterar todo charScripts.
	 * Se rellena en loadCharacterScripts y se limpia en destroy().
	 */
	public static var charScriptsByName : Map<String, Array<HScriptInstance>> = [];

	// ── Arrays reutilizables para el hot-path (evitan new Array cada frame) ──
	// Cada función de callback del gameplay (onUpdate, onBeatHit, onStepHit,
	// onNoteHit, onMiss…) pasa sus args a través de estos arrays estáticos en
	// lugar de crear un new Array<Dynamic> en cada llamada.
	// IMPORTANTE: Estos arrays son de uso temporal — solo válidos durante la
	// llamada a callOnScripts. No guardarlos por referencia en los scripts.

	/** Para onUpdate(elapsed:Float) */
	public static final _argsUpdate   : Array<Dynamic> = [0.0];
	/** Para onUpdatePost(elapsed:Float) */
	public static final _argsUpdatePost: Array<Dynamic> = [0.0];
	/** Para onBeatHit(beat:Int) */
	public static final _argsBeat     : Array<Dynamic> = [0];
	/** Para onStepHit(step:Int) */
	public static final _argsStep     : Array<Dynamic> = [0];
	/** Para onNoteHit / onMiss — [note, extra] */
	public static final _argsNote     : Array<Dynamic> = [null, null];
	/** Para eventos con un solo arg genérico */
	public static final _argsOne      : Array<Dynamic> = [null];
	/** Array vacío reutilizable — para callbacks sin argumentos */
	public static final _argsEmpty    : Array<Dynamic> = [];
	/** Para onAnimStart/onSingStart/onSingEnd en scripts de personaje — [arg0, arg1] */
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
		trace('[ScriptHandler v3] Listo.');
	}

	/**
	 * Carga todos los scripts globales: base + mods + custom_events (Psych compat).
	 */
	public static function loadGlobalScripts():Void
	{
		// Limpiar scripts globales anteriores para evitar duplicados en la 2ª partida
		_destroyLayer(globalScripts);
		globalScripts.clear();

		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			// Rutas estándar del mod
			_loadFolder('$r/scripts/global',   'global');
			_loadFolder('$r/scripts/events',   'global');
			_loadFolder('$r/data/scripts',     'global');
			_loadFolder('$r/data/config', 'global');
			// Rutas Psych-compat
			_loadFolder('$r/custom_events',    'global');
			_loadFolder('$r/custom_notetypes', 'global');
		}
		#end
		_loadFolder('assets/data/scripts/global', 'global');
		_loadFolder('assets/data/scripts/events', 'global');
		trace('[ScriptHandler v3] Scripts globales cargados.');
	}

	// ── Carga por contexto ────────────────────────────────────────────────────

	/** Carga scripts de la canción `songName` desde base + mod. */
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

	/** Carga scripts del stage `stageName` desde base + mod. */
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

	/** Carga scripts de personaje `charName` desde base + mod.
	 *  Los scripts quedan taggeados con `charName` para poder filtrarlos después.
	 *  Retorna la lista de scripts cargados para poder inyectarles variables.
	 *
	 *  ── Rutas (en orden de prioridad) ───────────────────────────────────────
	 *
	 *   NUEVA ruta canónica (recomendada):
	 *     assets/characters/scripts/{char}/scripts.hx    ← coloca aquí tu script
	 *     mods/{mod}/characters/scripts/{char}/scripts.hx
	 *
	 *   Rutas heredadas (siguen funcionando para compat):
	 *     assets/characters/{char}/scripts/              ← carpeta con varios .hx
	 *     mods/{mod}/characters/{char}/scripts/
	 *     mods/{mod}/characters/{char}/                  ← .hx sueltos (legacy)
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
	 * Llama `func` en los scripts del personaje `charName`.
	 * Usa charScriptsByName para lookup O(1) — no itera todos los charScripts.
	 */
	public static function callOnCharacterScripts(charName:String, func:String, args:Array<Dynamic>):Void
	{
		#if HSCRIPT_ALLOWED
		final list = charScriptsByName.get(charName);
		if (list == null) return; // guard rápido: sin scripts para este personaje
		for (script in list)
			if (script.active) script.call(func, args);
		#end
	}

	/**
	 * Igual que callOnCharacterScripts pero retorna true si algún script devuelve true.
	 * (Para cancelar comportamiento por defecto: return true en overrideDance, etc.)
	 */
	public static function callOnCharacterScriptsReturn(charName:String, func:String, args:Array<Dynamic>):Bool
	{
		#if HSCRIPT_ALLOWED
		final list = charScriptsByName.get(charName);
		if (list == null) return false; // guard rápido
		var result = false;
		for (script in list)
			if (script.active && script.call(func, args) == true) result = true;
		return result;
		#else
		return false;
		#end
	}

	/**
	 * Inyecta variables en los scripts de un personaje específico.
	 * Usa charScriptsByName para lookup O(1).
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
	 * Carga scripts de un estado/menú `stateName`.
	 * Busca en `assets/states/{stateName}/` y `mods/{mod}/states/{stateName}/`.
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

	// ── Carga de un script individual ─────────────────────────────────────────

	/**
	 * Carga un script desde `scriptPath`.
	 * Soporta .hx / .hscript nativos y .lua (transpilación Psych-compat).
	 *
	 * @param presetVars  Variables inyectadas ANTES de execute() (top-level code las ve).
	 * @param stage       Stage reference para el API shim de Psych Lua.
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

		if (isLua) trace('[ScriptHandler] Transpilando Lua: $scriptPath');

		final scriptName = _extractName(scriptPath);
		final script     = new HScriptInstance(scriptName, scriptPath);

		try
		{
			script.program = parser.parseString(content, scriptPath);
			script.interp  = new Interp();

			ScriptAPI.expose(script.interp);

			// ── require() y log() por instancia ──────────────────────────────
			// require() necesita la instancia concreta para resolver la ruta
			// relativa al script que hace la llamada. ScriptAPI.expose() no
			// tiene acceso a la instancia, así que lo inyectamos aquí.
			// BUG FIX: sin esto, require('ABotVis.hx') en nene.hx devuelve null
			// porque el intérprete no conoce 'require' → viz = null → barras invisibles.
			script.interp.variables.set('require', function(path:String):Dynamic return script.require(path));
			// log() como función top-level (el API solo expone debug.log()).
			// BUG FIX: scripts que llaman log('msg') obtenían "Variable log not found".
			script.interp.variables.set('log', function(msg:Dynamic):Void trace('[Script:$scriptName] $msg'));

			if (presetVars != null)
				for (k => v in presetVars)
					script.interp.variables.set(k, v);

			// ── Psych Lua API shims ───────────────────────────────────────────
			// Always expose the gameplay API for Lua scripts (getProperty,
			// setProperty, makeLuaText, callMethod, etc.).
			// The stage-specific API is layered on top when a Stage is provided.
			if (isLua)
				mods.compat.PsychLuaGameplayAPI.expose(script.interp);

			if (isLua && stage != null)
				mods.compat.PsychLuaStageAPI.expose(script.interp, stage);

			// ── HScript: pre-procesar imports antes de ejecutar ─────────────────
			// Permite escribir `import flixel.util.FlxColor;` en scripts .hx/.hscript.
			// Los imports se resuelven y comentan; la clase queda en interp.variables.
			#if HSCRIPT_ALLOWED
			if (!isLua)
			{
				final processedContent = processImports(content, script.interp);
				if (processedContent != content)
					script.program = parser.parseString(processedContent, scriptPath);
			}
			#end

			script.interp.execute(script.program);

			// Set up Psych callback aliases AFTER the script has defined its
			// functions (goodNoteHit → onNoteHit, onCreatePost → postCreate, etc.)
			if (isLua)
				mods.compat.PsychLuaGameplayAPI.setupCallbackAliases(script);

			script.call('onCreate');
			script.call('postCreate');

			_registerScript(script, scriptType);
			trace('[ScriptHandler] Cargado [$scriptType]: $scriptName${isLua ? " (Lua)" : ""}');
			return script;
		}
		catch (e:Dynamic)
		{
			trace('[ScriptHandler] ¡Error en "$scriptName"!');
			trace('  → ${Std.string(e)}');
			if (isLua) trace('[ScriptHandler] Código transpilado:\n$content');
			return null;
		}

		#else
		trace('[ScriptHandler] HSCRIPT_ALLOWED no definido en Project.xml — scripts desactivados.');
		return null;
		#end
	}

	/**
	 * Igual que loadScript() pero NO llama onCreate/postCreate automáticamente.
	 * Usar cuando el llamador necesita inyectar APIs adicionales ANTES del primer onCreate.
	 * El script queda parseado, con ScriptAPI expuesto y el programa ejecutado (funciones definidas).
	 * El llamador es responsable de llamar script.call('onCreate') cuando esté listo.
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

		try
		{
			script.program = parser.parseString(rawContent, scriptPath);
			script.interp  = new Interp();

			ScriptAPI.expose(script.interp);

			// ── require() y log() por instancia (ver loadScript() para explicación) ─
			script.interp.variables.set('require', function(path:String):Dynamic return script.require(path));
			script.interp.variables.set('log', function(msg:Dynamic):Void trace('[Script:$scriptName] $msg'));

			if (presetVars != null)
				for (k => v in presetVars)
					script.interp.variables.set(k, v);

			if (isLuaNoInit)
				mods.compat.PsychLuaGameplayAPI.expose(script.interp);

			// ── HScript: pre-procesar imports antes de ejecutar ─────────────────
			#if HSCRIPT_ALLOWED
			if (!isLuaNoInit)
			{
				final processedRaw = processImports(rawContent, script.interp);
				if (processedRaw != rawContent)
					script.program = parser.parseString(processedRaw, scriptPath);
			}
			#end

			// Ejecutar el programa define funciones en interp.variables — sin llamar onCreate aún.
			script.interp.execute(script.program);

			if (isLuaNoInit)
				mods.compat.PsychLuaGameplayAPI.setupCallbackAliases(script);

			_registerScript(script, scriptType);
			trace('[ScriptHandler] Cargado sin init [$scriptType]: $scriptName');
			return script;
		}
		catch (e:Dynamic)
		{
			trace('[ScriptHandler] ¡Error parseando "$scriptName"!');
			trace('  → ${Std.string(e)}');
			return null;
		}

		#else
		trace('[ScriptHandler] HSCRIPT_ALLOWED no definido — scripts desactivados.');
		return null;
		#end
	}

	/** Carga todos los `.hx` / `.hscript` / `.lua` de una carpeta. */
	public static function loadScriptsFromFolder(folderPath:String, scriptType:String = 'song'):Array<HScriptInstance>
	{
		return _loadFolder(folderPath, scriptType);
	}

	/** Carga scripts desde una lista explícita de paths. */
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

	// ── Llamadas ──────────────────────────────────────────────────────────────

	/**
	 * Llama `funcName(args)` en TODOS los scripts de TODAS las capas.
	 * El orden es: global → stage → song → ui → menu → char.
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
	 * Como callOnScripts pero devuelve el primer valor no-nulo / no-defaultValue.
	 * Si algún script devuelve `true` (cancelar), se detiene la propagación.
	 * Sin alloc de array intermedio — itera las capas directamente.
	 */
	public static function callOnScriptsReturn(funcName:String, args:Array<Dynamic> = null, defaultValue:Dynamic = null):Dynamic
	{
		if (args == null) args = _argsEmpty;
		// Iterar capas directamente sin crear Array "layers" cada llamada
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

	/** Inyecta una variable en todos los scripts activos. */
	public static function setOnScripts(varName:String, value:Dynamic):Void
	{
		// Sin Array "layers" intermedio
		inline function _setLayer(layer:Map<String, HScriptInstance>):Void
			for (script in layer) if (script.active) script.set(varName, value);
		_setLayer(globalScripts);
		_setLayer(stageScripts);
		_setLayer(songScripts);
		_setLayer(uiScripts);
		_setLayer(menuScripts);
		_setLayer(charScripts);
	
		#if (LUA_ALLOWED && linc_luajit)
		inline function _setLua(layer:Array<LuaScriptInstance>):Void
			for (lua in layer) if (lua.active) lua.set(varName, value);
		_setLua(globalLuaScripts); _setLua(stageLuaScripts); _setLua(songLuaScripts);
		_setLua(uiLuaScripts);     _setLua(menuLuaScripts);  _setLua(charLuaScripts);
		#end
	}

	/** Inyecta una variable solo en los scripts de stage. */
	public static function setOnStageScripts(varName:String, value:Dynamic):Void
	{
		for (script in stageScripts)
			if (script.active) script.set(varName, value);
	}

	/** Llama una función solo en los scripts de stage. */
	public static function callOnStageScripts(funcName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		_callLayer(stageScripts, funcName, args);
	}

	/**
	 * Llama una función en todos los layers EXCEPTO stageScripts.
	 * Usar cuando los stage scripts ya dispararon el evento en loadStageScripts()
	 * y no queremos una segunda ejecucion que pise el estado correcto.
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

	/** Obtiene el valor de una variable de los scripts activos (primer resultado no-nulo). */
	public static function getFromScripts(varName:String, defaultValue:Dynamic = null):Dynamic
	{
		final layers = [globalScripts, stageScripts, songScripts, uiScripts, menuScripts, charScripts];
		for (layer in layers)
			for (script in layer)
				if (script.active) {
					final v = script.get(varName);
					if (v != null) return v;
				}
		return defaultValue;
	}

	// ── Limpieza ──────────────────────────────────────────────────────────────

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
		charScriptsByName.clear(); // limpiar índice también
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

	/** Recarga un script por nombre (sin reiniciar el intérprete). */
	public static function hotReload(name:String):Bool
	{
		final layers = [globalScripts, stageScripts, songScripts, uiScripts, menuScripts, charScripts];
		for (layer in layers)
		{
			if (layer.exists(name))
			{
				layer.get(name).hotReload();
				trace('[ScriptHandler] Hot-reload: $name');
				return true;
			}
		}
		trace('[ScriptHandler] hotReload: "$name" not found.');
		return false;
	}

	/** Recarga todos los scripts de todas las capas. */
	public static function hotReloadAll():Void
	{
		final layers = [globalScripts, stageScripts, songScripts, uiScripts, menuScripts, charScripts];
		for (layer in layers) for (s in layer) s.hotReload();
		trace('[ScriptHandler] Hot-reload completo.');
	
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
		// Nombres duplicados → sufijo numérico
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
		// BUGFIX: NO llamar onDestroy aquí.
		// PlayState.destroy() ya llama callOnScripts('onDestroy') antes de
		// clearSongScripts() / clearStageScripts() / clearCharScripts(), lo que
		// a su vez llamaba a _destroyLayer() → onDestroy se ejecutaba DOS VECES.
		// La segunda ejecución ocurría con el estado parcialmente destruido
		// (stage elements, camGame, etc. ya nulleados) → crash.
		// Esta función ahora solo libera el intérprete de cada script.
		for (script in layer)
			script.dispose();
	}

	#if (LUA_ALLOWED && linc_luajit)
	static function _callLuaLayer(layer:Array<LuaScriptInstance>, func:String, args:Array<Dynamic>):Void
	{
		for (lua in layer) if (lua.active) lua.call(func, args);
	}

	static function _destroyLuaLayer(layer:Array<LuaScriptInstance>):Void
	{
		for (lua in layer) try lua.destroy() catch (_) {};
		layer.resize(0);
	}

	/**
	 * Loads a .lua file as a native LuaScriptInstance into the correct gameplay layer.
	 * Exposes the full ScriptAPI so it has access to PlayState, FlxG, Conductor, etc.
	 * Called automatically by _loadFolder when a .lua file is found.
	 */
	static function _loadLuaFile(path:String, scriptType:String):Null<LuaScriptInstance>
	{
		if (!FileSystem.exists(path)) return null;
		final name   = _extractName(path);
		final script = new LuaScriptInstance(name, path);

		// Per-script helpers
		script.set('log',       function(msg:Dynamic) trace('[Lua:$name] $msg'));
		script.set('hotReload', function():Bool return script.hotReload());

		// import('com.foo.Bar') → devuelve la clase/enum resuelta como Dynamic.
		// Uso en Lua:
		//   local FlxColor = import('flixel.util.FlxColor')
		//   local col = FlxColor.RED
		// import('com.foo.Bar') → registra como global con nombre corto Y retorna la clase.
		// Uso: import('flixel.util.FlxAxes')  →  FlxAxes disponible globalmente.
		script.set('import', function(className:String):Dynamic {
			var resolved:Dynamic = Type.resolveClass(className);
			if (resolved == null) resolved = Type.resolveEnum(className);
			if (resolved == null) {
				trace('[Lua:$name] import: clase no encontrada: $className');
				return null;
			}
			// Registrar como global con el nombre corto para uso directo
			final shortName = className.split('.').pop();
			script.set(shortName, resolved);
			trace('[Lua:$name] import $className → global $shortName');
			return resolved;
		});

		script.loadFile(path);

		if (!script.active)
		{
			trace('[ScriptHandler] Lua error: $path');
			script.destroy();
			return null;
		}

		var target:Array<LuaScriptInstance> = switch (scriptType.toLowerCase())
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
		trace('[ScriptHandler] Lua cargado [$scriptType]: $name');
		return script;
	}
	#end

	/** Alias público de _extractName para compatibilidad. */
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
	 * Pre-procesa las líneas `import a.b.C;` y `import a.b.C as Alias;`
	 * del código fuente de un HScript.
	 *
	 * Cada import se resuelve con Type.resolveClass / Type.resolveEnum
	 * y se inyecta en `interp.variables` bajo el nombre corto (o alias).
	 * Las líneas de import se sustituyen por comentarios para que el parser
	 * hscript no las rechace (hscript no soporta la sintaxis `import`).
	 *
	 * Uso desde un script .hx:
	 *   import flixel.util.FlxColor;
	 *   import flixel.math.FlxMath as Math;
	 *
	 * @param source   Código fuente original del script.
	 * @param interp   Intérprete en el que se inyectarán las clases.
	 * @return         Código fuente con las líneas de import comentadas.
	 */
	#if HSCRIPT_ALLOWED
	public static function processImports(source:String, interp:Interp):String
	{
		// Regex: import com.foo.Bar; o import com.foo.Bar as B;
		final importReg = ~/^[ \t]*import\s+([\w.]+)(?:\s+as\s+(\w+))?\s*;/gm;
		return importReg.map(source, function(r:EReg):String
		{
			final fullName  = r.matched(1);
			final alias     = r.matched(2);
			final shortName = (alias != null && alias != '') ? alias : fullName.split('.').pop();

			var resolved:Dynamic = Type.resolveClass(fullName);
			if (resolved == null) resolved = Type.resolveEnum(fullName);

			if (resolved != null)
			{
				interp.variables.set(shortName, resolved);
				trace('[ScriptHandler] import $fullName → $shortName');
			}
			else
			{
				trace('[ScriptHandler] import no resuelta: $fullName (¿falta en el build?)');
			}
			// Comentar la línea para que hscript no la vea
			return '// [import] $fullName';
		});
	}
	#end
}
