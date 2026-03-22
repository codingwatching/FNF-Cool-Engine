package funkin.scripting;

import flixel.FlxG;
import flixel.FlxState;
import haxe.Exception;
import sys.FileSystem;
import sys.io.File;

#if HSCRIPT_ALLOWED
import hscript.Interp;
#end

using StringTools;

/**
 * StateScriptHandler v2 — sistema de scripts para FlxStates y menus.
 *
 * Novedades respecto a v1:
 *   ┌─────────────────────────────────────────────────────────────────────┐
 *   │ ELEMENTOS                                                           │
 *   │  exposeElement(name, obj)  → expone cualquier objeto al script      │
 *   │  getElement(name)          → lee desde fuera                        │
 *   │  exposeAll(map)            → bulk                                   │
 *   ├─────────────────────────────────────────────────────────────────────┤
 *   │ HOOKS CUSTOM                                                        │
 *   │  registerHook(name, fn)    → engancha logic Haxe nativa           │
 *   │  callHook(name, args)      → llama hook + scripts                  │
 *   │  fireRaw(name, args)       → solo scripts, sin hooks Haxe          │
 *   ├─────────────────────────────────────────────────────────────────────┤
 *   │ DATOS COMPARTIDOS entre scripts del mismo state                    │
 *   │  setShared(key, value)                                              │
 *   │  getShared(key)                                                     │
 *   ├─────────────────────────────────────────────────────────────────────┤
 *   │ BROADCAST (entre TODOS los scripts del engine)                     │
 *   │  broadcast(event, args)    → llama a todos (state + gameplay)      │
 *   ├─────────────────────────────────────────────────────────────────────┤
 *   │ OTROS                                                               │
 *   │  hotReloadAll()            → recarga todos los scripts del state   │
 *   │  getByTag(tag)             → obtiene scripts por tag               │
 *   │  callOnBool(fn, args)      → version cancelable                    │
 *   └─────────────────────────────────────────────────────────────────────┘
 *
 * ─── Basic usage ──────────────────────────────────────────────────────────────
 *   StateScriptHandler.init();
 *   StateScriptHandler.loadStateScripts('MainMenuState', this);
 *   StateScriptHandler.exposeElement('menuItems', menuItemGroup);
 *   var cancelled = StateScriptHandler.callOnScripts('onBack', []);
 *   StateScriptHandler.clearStateScripts();
 *
 * ─── Estructura de carpetas ──────────────────────────────────────────────────
 *   assets/states/{statename}/       → scripts .hx / .hscript
 *   mods/{mod}/states/{statename}/   → sobrescribe / complementa
 */
class StateScriptHandler
{
	public static var scripts   : Map<String, HScriptInstance> = [];
	public static var overrides : Map<String, FunctionOverride> = [];

	#if (LUA_ALLOWED && linc_luajit)
	/** Native Lua scripts for this state. */
	public static var luaScripts : Array<LuaScriptInstance> = [];
	#end

	/** Datos compartidos entre scripts del mismo state. */
	public static var sharedData : Map<String, Dynamic> = [];

	/** Hooks Haxe nativos registrados por el state. */
	static var _hooks    : Map<String, Array<Dynamic->Void>> = [];

	static var _sortedCache : Array<HScriptInstance> = [];
	static var _cacheDirty  : Bool = true;

	// ─── Init ─────────────────────────────────────────────────────────────────

	public static function init():Void
	{
		sharedData.clear();
		_hooks.clear();
		trace('[StateScriptHandler] Done.');
	}

	// ─── Carga ────────────────────────────────────────────────────────────────

	public static function loadStateScripts(stateName:String, state:FlxState,
		?extraVars:Map<String, Dynamic>):Array<HScriptInstance>
	{
		clearStateScripts();

		var loaded:Array<HScriptInstance> = [];

		#if sys
		if (mods.ModManager.isActive())
		{
			final modRoot = mods.ModManager.modRoot();
			final sn = stateName.toLowerCase();
			for (folder in ['$modRoot/states/$sn', '$modRoot/assets/states/$sn'])
				for (s in _loadFolder(folder, state, extraVars))
					loaded.push(s);
		}
		#end

		for (s in _loadFolder('assets/states/${stateName.toLowerCase()}', state, extraVars))
			loaded.push(s);

		trace('[StateScriptHandler] ${loaded.length} scripts for $stateName.');
		return loaded;
	}

	public static function loadScript(scriptPath:String, state:FlxState,
		priority:Int = 0, ?extraVars:Map<String, Dynamic>):HScriptInstance
	{
		#if HSCRIPT_ALLOWED
		if (!FileSystem.exists(scriptPath))
		{
			trace('[StateScriptHandler] not found: $scriptPath');
			return null;
		}

		final name    = ScriptHandler.extractName(scriptPath);
		final content = File.getContent(scriptPath);
		final script  = new HScriptInstance(name, scriptPath, priority);

		// Asignar callback de error global
		script.onError = (sn, ctx, err) ->
			trace('[STATE SCRIPT ERROR] $sn::$ctx → ${Std.string(err)}');

		try
		{
			@:privateAccess script._source = content;
			script.program = ScriptHandler.parser.parseString(content, scriptPath);
			script.interp  = new Interp();

			ScriptAPI.expose(script.interp);
			_exposeStateAPI(script.interp, state, script);

			// Variables extra opcionales
			if (extraVars != null)
				script.setAll(extraVars);

			script.interp.execute(script.program);
			script.call('onCreate');

			scripts.set(name, script);
			_cacheDirty = true;

			trace('[StateScriptHandler] Loaded: $name (prio $priority)');
			return script;
		}
		catch (e:Exception)
		{
			trace('[StateScriptHandler] Error "$name": ${e.message}');
			return null;
		}
		#else
		return null;
		#end
	}

	static function _loadFolder(folderPath:String, state:FlxState,
		?extraVars:Map<String, Dynamic>):Array<HScriptInstance>
	{
		final loaded:Array<HScriptInstance> = [];

		if (!FileSystem.exists(folderPath) || !FileSystem.isDirectory(folderPath))
			return loaded;

		for (file in FileSystem.readDirectory(folderPath))
		{
			#if (LUA_ALLOWED && linc_luajit)
			if (file.endsWith('.lua'))
			{
				loadLuaScript('$folderPath/$file', state, extraVars);
				continue;
			}
			#end
			if (!file.endsWith('.hx') && !file.endsWith('.hscript')) continue;
			final s = loadScript('$folderPath/$file', state, 0, extraVars);
			if (s != null) loaded.push(s);
		}

		return loaded;
	}

	// ─── Elementos expuestos ──────────────────────────────────────────────────

	/**
	 * Expone un elemento del state a TODOS los scripts activos.
	 *
	 *   StateScriptHandler.exposeElement('rankSprite', rankSprite);
	 *
	 * En el script:
	 *   rankSprite.alpha = 0.5;
	 */
	public static function exposeElement(name:String, value:Dynamic):Void
		setOnScripts(name, value);

	/** Expone varios elementos de una vez. */
	public static function exposeAll(map:Map<String, Dynamic>):Void
	{
		for (k => v in map)
			setOnScripts(k, v);
	}

	// ─── Hooks nativos ────────────────────────────────────────────────────────

	/**
	 * Registra un hook Haxe para `hookName`.
	 * Cuando `callHook(hookName, args)` se llame, primero ejecuta el callback
	 * nativo y luego propaga a los scripts.
	 *
	 *   StateScriptHandler.registerHook('onExit', function(args) {
	 *       // logic Haxe nativa before of that the scripts it vean
	 *   });
	 */
	public static function registerHook(hookName:String, callback:Dynamic->Void):Void
	{
		if (!_hooks.exists(hookName))
			_hooks.set(hookName, []);
		_hooks.get(hookName).push(callback);
		trace('[StateScriptHandler] Hook "$hookName" registred.');
	}

	/** Elimina todos los hooks nativos para `hookName`. */
	public static function removeHook(hookName:String):Void
	{
		_hooks.remove(hookName);
	}

	/**
	 * Llama hooks nativos + scripts.
	 * @return true if some script canceló the event.
	 */
	public static function callHook(hookName:String, args:Array<Dynamic> = null):Bool
	{
		if (args == null) args = [];

		// 1) Hooks Haxe nativos
		final hooks = _hooks.get(hookName);
		if (hooks != null)
			for (h in hooks)
				try { h(args); } catch (e:Dynamic) { trace('[Hook Error] $hookName: $e'); }

		// 2) Scripts
		return callOnScripts(hookName, args);
	}

	/**
	 * Llama solo en scripts (sin hooks nativos), y NO cancela.
	 * For events of "notification pura".
	 */
	public static function fireRaw(hookName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		for (script in getSorted())
			script.call(hookName, args);
	}

	// ─── Datos compartidos ────────────────────────────────────────────────────

	public static function setShared(key:String, value:Dynamic):Void
		sharedData.set(key, value);

	public static function getShared(key:String, ?defaultVal:Dynamic):Dynamic
	{
		if (sharedData.exists(key)) return sharedData.get(key);
		return defaultVal;
	}

	public static function deleteShared(key:String):Void
		sharedData.remove(key);

	// ─── Broadcast global ─────────────────────────────────────────────────────

	/**
	 * Lanza un evento a TODOS los sistemas de scripts (state + gameplay).
	 * Useful for comunicación inter-system (ej. a menu le dice to the gameplay algo).
	 */
	public static function broadcast(eventName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		callOnScripts(eventName, args);
		ScriptHandler.callOnScripts(eventName, args);
	}

	// ─── Hot-Reload ───────────────────────────────────────────────────────────

	/** Recarga todos los scripts del state sin perder sus variables. */
	public static function hotReloadAll():Void
	{
		for (s in scripts)
			s.hotReload();
	
		#if (LUA_ALLOWED && linc_luajit)
		for (lua in luaScripts)
			lua.hotReload();
		#end
	}

	/** Recarga un script concreto por nombre. */
	public static function hotReload(scriptName:String):Bool
	{
		final s = scripts.get(scriptName);
		return s != null && s.hotReload();
	}

	/**
	 * Re-sincroniza TODOS los campos del state hacia los scripts activos.
	 * Useful when the state creates objects after of load the scripts
	 * (ej: TitleState crea logoBl en startIntro(), no en create()).
	 * Llamar justo antes de 'postCreate' en esos casos.
	 *
	 * IMPORTANTE: a diferencia de _reflectStateFields (que respeta variables ya
	 * existentes for no sobreescribir the API of the engine), this function itself
	 * actualiza todos los campos del state — excepto las variables fijas del API.
	 */
	public static function refreshStateFields(state:FlxState):Void
	{
		#if HSCRIPT_ALLOWED
		for (script in scripts)
			if (script.interp != null)
				_reflectStateFields(script.interp, state, true); // true = modo refresh
		#end
	}

	// ─── Llamadas ─────────────────────────────────────────────────────────────

	/**
	 * Llama `funcName` en orden de prioridad.
	 * If some script returns `true` → cancela (returns true).
	 */
	public static function callOnScripts(funcName:String, args:Array<Dynamic> = null):Bool
	{
		if (args == null) args = [];

		final ovr = overrides.get(funcName);
		if (ovr != null && ovr.enabled)
		{
			ovr.call(args);
			// Lua scripts still receive the call even when overridden
			#if (LUA_ALLOWED && linc_luajit)
			for (lua in luaScripts)
				if (lua.active) lua.call(funcName, args);
			#end
			return true;
		}

		for (script in getSorted())
			if (script.callBool(funcName, args))
			{
				trace('[StateScriptHandler] "$funcName" canceled por ${script.name}');
				#if (LUA_ALLOWED && linc_luajit)
				for (lua in luaScripts)
					if (lua.active) lua.call(funcName, args);
				#end
				return true;
			}

		#if (LUA_ALLOWED && linc_luajit)
		for (lua in luaScripts)
			if (lua.active) lua.call(funcName, args);
		#end
		return false;
	}

	/** Devuelve el primer resultado no-null. */
	public static function callOnScriptsReturn(funcName:String, args:Array<Dynamic> = null,
		defaultValue:Dynamic = null):Dynamic
	{
		if (args == null) args = [];

		final ovr = overrides.get(funcName);
		if (ovr != null && ovr.enabled) return ovr.call(args);

		for (script in getSorted())
		{
			final r = script.call(funcName, args);
			if (r != null) return r;
		}

		return defaultValue;
	}

	/** Call in all without cancelación (always continúa). */
	public static function callOnAll(funcName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		for (s in getSorted()) s.call(funcName, args);
	}

	// ─── Variables ────────────────────────────────────────────────────────────

	public static function setOnScripts(varName:String, value:Dynamic):Void
	{
		for (s in scripts) s.set(varName, value);
		#if (LUA_ALLOWED && linc_luajit)
		for (lua in luaScripts)
			if (lua.active) lua.set(varName, value);
		#end
	}

	public static function getFromScripts(varName:String):Dynamic
	{
		for (s in getSorted())
			if (s.exists(varName)) return s.get(varName);
		return null;
	}

	// ─── Por tag ──────────────────────────────────────────────────────────────

	/** Obtiene un script por su nombre. */
	public static function getByName(name:String):HScriptInstance
		return scripts.get(name);

	/** Obtiene todos los scripts con un tag dado. */
	public static function getByTag(tag:String):Array<HScriptInstance>
		return [for (s in scripts) if (s.tag == tag) s];

	// ─── Overrides ────────────────────────────────────────────────────────────

	public static function registerOverride(funcName:String, script:HScriptInstance, func:Dynamic):Void
	{
		overrides.set(funcName, new FunctionOverride(funcName, script, func));
		trace('[StateScriptHandler] Override "$funcName" by ${script.name}');
	}

	public static function unregisterOverride(funcName:String):Void
		overrides.remove(funcName);

	public static function toggleOverride(funcName:String, enabled:Bool):Void
	{
		final ovr = overrides.get(funcName);
		if (ovr != null) ovr.enabled = enabled;
	}

	public static function hasOverride(funcName:String):Bool
	{
		final ovr = overrides.get(funcName);
		return ovr != null && ovr.enabled;
	}

	// ─── Colecciones ──────────────────────────────────────────────────────────

	public static function collectArrays(funcName:String):Array<Dynamic>
	{
		final all:Array<Dynamic> = [];
		for (s in scripts)
		{
			final r = s.call(funcName);
			if (r != null && Std.isOfType(r, Array))
				for (item in (cast r:Array<Dynamic>)) all.push(item);
		}
		return all;
	}

	public static function collectUniqueStrings(funcName:String):Array<String>
	{
		final all:Array<String> = [];
		for (s in scripts)
		{
			final r = s.call(funcName);
			if (r == null || !Std.isOfType(r, Array)) continue;
			for (item in (cast r:Array<String>))
				if (!all.contains(item)) all.push(item);
		}
		return all;
	}

	// ─── Compatibilidad OptionsMenuState ─────────────────────────────────────

	public static function getCustomOptions():Array<Dynamic>     return collectArrays('getCustomOptions');
	public static function getCustomCategories():Array<String>   return collectUniqueStrings('getCustomCategories');

	// ─── Limpiar ──────────────────────────────────────────────────────────────

	public static function clearStateScripts():Void
	{
		for (s in scripts) s.destroy();
		scripts.clear();
		overrides.clear();
		sharedData.clear();
		_hooks.clear();
		_sortedCache = [];
		_cacheDirty  = false;
		#if (LUA_ALLOWED && linc_luajit)
		for (lua in luaScripts)
		{
			try lua.call('onDestroy') catch(_) {};
			try lua.destroy()        catch(_) {};
		}
		luaScripts = [];
		#end
	}

	// ─── Lua scripts para states ──────────────────────────────────────────────

	/**
	 * Loads a .lua file as a native LuaScriptInstance for a state/menu.
	 * Supports the same hooks and ui API as HScript state scripts.
	 *
	 * Hooks:  onCreate, postCreate, onUpdate, onUpdatePost,
	 *         onBeatHit, onStepHit, onDestroy, onKeyJustPressed
	 * API:    ui.add/remove/text/solidSprite/tween/center/zoom/playSound/switchState
	 */
	#if (LUA_ALLOWED && linc_luajit)
	public static function loadLuaScript(scriptPath:String, state:Dynamic,
		?extraVars:Map<String, Dynamic>):Null<LuaScriptInstance>
	{
		if (!FileSystem.exists(scriptPath)) return null;

		final name   = ScriptHandler.extractName(scriptPath);
		final script = new LuaScriptInstance(name, scriptPath);

		// Inject the state ui-helper API
		_exposeLuaStateAPI(script, state);

		// Extra caller-provided vars
		if (extraVars != null)
			for (k => v in extraVars) script.set(k, v);

		// Hot-reload self-reference
		script.set('hotReload', function():Bool return script.hotReload());
		script.set('log', function(msg:Dynamic):Void trace('[Lua:$name] $msg'));

		script.loadFile(scriptPath);

		if (!script.active)
		{
			trace('[StateScriptHandler] Lua error in: $scriptPath');
			script.destroy();
			return null;
		}

		luaScripts.push(script);
		script.call('onCreate');
		script.call('postCreate');
		trace('[StateScriptHandler] Lua loaded: $name');
		return script;
	}

	/**
	 * Exposes the standard state ui API to a Lua script.
	 * Mirrors _exposeStateAPI (HScript version) but uses lua.set().
	 */
	static function _exposeLuaStateAPI(script:LuaScriptInstance, state:Dynamic):Void
	{
		script.set('FlxG',  flixel.FlxG);
		script.set('Math',  Math);
		script.set('Std',   Std);
		script.set('self',  state);

		// Build ui helper object matching ScriptBridge.buildUIHelper output
		final uiHelper:Dynamic =
			(state != null && Std.isOfType(state, flixel.FlxState))
			? funkin.scripting.ScriptBridge.buildUIHelper(cast state)
			: funkin.scripting.ScriptBridge.buildUIHelper(flixel.FlxG.state);

		script.set('ui', uiHelper);

		// PlayState reference if available
		var ps = funkin.gameplay.PlayState.instance;
		if (ps != null) script.set('game', ps);
	}
	#end


	// ─── Helpers internos ─────────────────────────────────────────────────────

	static function getSorted():Array<HScriptInstance>
	{
		if (_cacheDirty)
		{
			_sortedCache = [for (s in scripts) s];
			_sortedCache.sort((a, b) -> b.priority - a.priority);
			_cacheDirty = false;
		}
		return _sortedCache;
	}

	#if HSCRIPT_ALLOWED
	/**
	 * Expone automatically all the fields of instance of the state to the script,
	 * igual que hace Codename Engine — sin necesidad de llamar exposeElement()
	 * manualmente para cada sprite/variable.
	 *
	 * Funcionamiento:
	 *  • Type.getInstanceFields() recorre all the jerarquía of classes of the state
	 *    y devuelve los nombres de todos los campos de instancia.
	 *  • Reflect.getProperty() lee el valor actual de cada campo.
	 *  • Los objetos (FlxSprite, FlxGroup…) se pasan por referencia — el script
	 *    puede modificarlos directamente (logoBl.visible = false; etc.).
	 *  • Los primitivos (Bool, Int, Float, String) se pasan por valor.
	 *    Para escribirlos de vuelta desde el script usa setField(nombre, valor).
	 *
	 * Ejemplo en script:
	 *   logoBl.visible = false;          // funciona — es referencia al sprite
	 *   setField('transitioning', true); // escribe un Bool del state
	 *   var v = getField('curBeat');     // lee cualquier campo
	 */
	static function _exposeStateAPI(interp:Interp, state:FlxState, script:HScriptInstance):Void
	{
		// ── 1. AUTO-REFLECT: exponer TODOS los campos de instancia del state ──
		_reflectStateFields(interp, state);

		// ── 2. Referencia principal al state ──────────────────────────────────
		interp.variables.set('state', state);
		interp.variables.set('save',  FlxG.save.data);

		// ── 3. Leer/escribir campos primitivos del state desde el script ──────
		//    Para objetos no hace falta porque son referencias, pero para
		//    Bool/Int/Float/String the assignment directa no escribe of vuelta.
		interp.variables.set('getField', (name:String) -> {
			try   { return Reflect.getProperty(state, name); }
			catch (e:Dynamic) { trace('[StateScript] getField("$name") failed: $e'); return null; }
		});
		interp.variables.set('setField', (name:String, value:Dynamic) -> {
			try   { Reflect.setProperty(state, name, value); }
			catch (e:Dynamic) { trace('[StateScript] setField("$name") failed: $e'); }
		});

		// ── 4. Callr methods of the state by nombre ────────────────────────────
		//    callMethod('skipIntro')  →  state.skipIntro()
		interp.variables.set('callMethod', (name:String, ?args:Array<Dynamic>) -> {
			try
			{
				final fn = Reflect.getProperty(state, name);
				if (fn != null && Reflect.isFunction(fn))
					return Reflect.callMethod(state, fn, args ?? []);
			}
			catch (e:Dynamic) { trace('[StateScript] callMethod("$name") failed: $e'); }
			return null;
		});

		// ── 5. Re-sincronizar campos del state HACIA el script ─────────────────
		//    Useful for refrescar values primitivos that cambiaron from Haxe.
		//    Llamar desde el script cuando sea necesario: refreshFields()
		interp.variables.set('refreshFields', () -> _reflectStateFields(interp, state, true));

		// ── 6. Control of cancelación ─────────────────────────────────────────
		interp.variables.set('cancelEvent',   () -> true);
		interp.variables.set('continueEvent', () -> false);

		// ── 7. Prioridad dynamic ─────────────────────────────────────────────
		interp.variables.set('setPriority', (p:Int) -> {
			script.priority = p;
			_cacheDirty = true;
		});

		// ── 8. Tag del script ─────────────────────────────────────────────────
		interp.variables.set('setTag', (t:String) -> { script.tag = t; });
		interp.variables.set('getTag', () -> script.tag);

		// ── 9. Overrides de funciones ─────────────────────────────────────────
		interp.variables.set('overrideFunction', (name:String, fn:Dynamic) ->
			registerOverride(name, script, fn));
		interp.variables.set('removeOverride',   (name:String) -> unregisterOverride(name));
		interp.variables.set('toggleOverride',   (name:String, en:Bool) -> toggleOverride(name, en));
		interp.variables.set('hasOverride',       (name:String) -> hasOverride(name));

		// ── 10. Datos compartidos ─────────────────────────────────────────────
		interp.variables.set('setShared',    (k:String, v:Dynamic)    -> setShared(k, v));
		interp.variables.set('getShared',    (k:String, ?def:Dynamic) -> getShared(k, def));
		interp.variables.set('deleteShared', (k:String)               -> deleteShared(k));

		// ── 11. Hooks, broadcast, hot-reload, require ─────────────────────────
		interp.variables.set('registerHook', (name:String, fn:Dynamic->Void) ->
			registerHook(name, fn));
		interp.variables.set('broadcast', (ev:String, ?args:Array<Dynamic>) ->
			broadcast(ev, args ?? []));
		interp.variables.set('hotReload', () -> script.hotReload());
		interp.variables.set('require',   (path:String) -> script.require(path));

		// ── 12. Acceso a otros scripts del mismo state ────────────────────────
		interp.variables.set('getScript',    (name:String) -> getByName(name));
		interp.variables.set('getScriptTag', (tag:String)  -> getByTag(tag));

		// ── 13. Helper create options of menu ─────────────────────────────────
		interp.variables.set('createOption',
			(name:String, getValue:Void->String, onPress:Void->Bool) -> ({
				name:     name,
				getValue: getValue,
				onPress:  onPress
			})
		);

		// ── 14. Builder de elementos UI ───────────────────────────────────────
		interp.variables.set('ui', ScriptBridge.buildUIHelper(state));

		// ── 15. Funciones de stage directas (add/remove) ──────────────────────
		// IMPORTANTE: add() viene de FlxGroup (padre de FlxState) y NO se refleja
		// automatically by _reflectStateFields porque the bucle for in FlxState.
		// Is exponen here explicitly for that the scripts puedan callr
		// add(sprite) y remove(sprite) igual que en Codename Engine.
		if (!interp.variables.exists('add'))
			interp.variables.set('add', function(obj:Dynamic) { state.add(obj); return obj; });
		if (!interp.variables.exists('remove'))
			interp.variables.set('remove', function(obj:Dynamic, splice:Bool = false) { return state.remove(obj, splice); });

		// ── 16. Referencia al propio script ───────────────────────────────────
		interp.variables.set('self', script);
	}

	/**
	 * Itera TODOS los campos de instancia del state (y sus superclases)
	 * and the inyecta in the interpreter of the script by reflection.
	 *
	 * @param refresh  Si true (modo refresh), sobreescribe campos existentes del
	 *                 state EXCEPTO las variables fijas del API del engine.
	 *                 Si false (modo init, default), no sobreescribe nada que ya
	 *                 exista — el API tiene prioridad.
	 *
	 * Uso:
	 *   • Modo init   → llamado desde _exposeStateAPI al cargar el script por primera vez.
	 *   • Modo refresh → llamado desde refreshStateFields() / refreshFields()
	 *                    when the state creates objects after of load the scripts.
	 */
	static final _API_VARS:Array<String> = [
		'state','save','getField','setField','callMethod','refreshFields',
		'cancelEvent','continueEvent','setPriority','setTag','getTag',
		'overrideFunction','removeOverride','toggleOverride','hasOverride',
		'setShared','getShared','deleteShared','registerHook','broadcast',
		'hotReload','require','getScript','getScriptTag','createOption','ui','self',
		'add','remove'
	];

	static function _reflectStateFields(interp:Interp, state:FlxState, refresh:Bool = false):Void
	{
		// Get all the fields of instance recorriendo the jerarquía complete.
		// Type.getSuperClass() returns Class<Dynamic>, no Class<FlxState>, so that
		// usamos Dynamic for the variable of iteration and evitamos the error of types.
		var fields:Array<String> = [];
		var cls:Dynamic = Type.getClass(state);
		while (cls != null)
		{
			for (f in Type.getInstanceFields(cls))
				if (!fields.contains(f))
					fields.push(f);
			cls = Type.getSuperClass(cls);
			// Parar en FlxState para no exponer internos de Flixel/OpenFL
			if (cls != null && Type.getClassName(cls) == 'flixel.FlxState')
				break;
		}

		for (fieldName in fields)
		{
			// En modo init: no sobreescribir NADA que ya exista (API tiene prioridad).
			// En modo refresh: actualizar campos del state SALVO las vars fijas del API.
			if (!refresh && interp.variables.exists(fieldName)) continue;
			if (refresh && _API_VARS.contains(fieldName)) continue;

			try
			{
				final value = Reflect.getProperty(state, fieldName);
				interp.variables.set(fieldName, value);
			}
			catch (e:Dynamic)
			{
				// Campo write-only o inaccesible — ignorar silenciosamente
			}
		}
	}
	#end
}

// ─────────────────────────────────────────────────────────────────────────────

class FunctionOverride
{
	public var funcName : String;
	public var script   : HScriptInstance;
	public var func     : Dynamic;
	public var enabled  : Bool = true;

	public function new(funcName, script, func)
	{
		this.funcName = funcName;
		this.script   = script;
		this.func     = func;
	}

	public function call(args:Array<Dynamic>):Dynamic
	{
		if (!enabled || !script.active) return null;

		try
		{
			if (Reflect.isFunction(func))
				return Reflect.callMethod(null, func, args);
		}
		catch (e:Exception)
		{
			trace('[FunctionOverride] Error "$funcName": ${e.message}');
		}

		return null;
	}
}
