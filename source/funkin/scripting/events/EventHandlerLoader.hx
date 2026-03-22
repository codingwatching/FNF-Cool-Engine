package funkin.scripting.events;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

import funkin.scripting.events.EventDefinition;
import funkin.scripting.events.EventInfoSystem.EventParamDef;

using StringTools;

/**
 * EventHandlerLoader — Carga y despacha scripts handler por evento.
 *
 * Cada evento puede tener un script propio (.hx y/o .lua) que se carga UNA VEZ
 * y se llama cada vez que el evento se dispara. Los scripts conviven con el
 * sistema built-in de EventManager: si el handler devuelve `true`, se cancela
 * el comportamiento built-in; si devuelve `false` o nada, ambos corren.
 *
 * ─── Ciclo de vida ───────────────────────────────────────────────────────────
 *
 *   1. EventRegistry.reload() → descubre definiciones + rutas de handlers
 *   2. EventHandlerLoader.loadContext("chart") → carga scripts del contexto
 *   3. PlayState (update) → EventManager.triggerEvent(e)
 *      → EventHandlerLoader.dispatch(name, v1, v2, time)
 *      → Si retorna true: skip built-in
 *      → Si retorna false/null: EventManager._handleBuiltin()
 *   4. PlayState.destroy() → EventHandlerLoader.clearContext("chart")
 *
 * ─── API del script handler ──────────────────────────────────────────────────
 *
 *   HScript (Camera Follow.hx):
 *     // Variables globales: v1, v2, time, game
 *     function onTrigger(v1, v2, time) {
 *       if (game != null) game.cameraController.setTarget(v1);
 *       return false; // false = also corre the built-in
 *     }
 *
 *   Lua (Camera Follow.lua):
 *     function onTrigger(v1, v2, time)
 *       return false
 *     end
 *
 *   Also is aceptan the functions of compatibility:
 *     onEvent(name, v1, v2, time)   -- igual que en scripts globales
 *     onCreate()                     -- al cargar el handler
 *     onDestroy()                    -- al descargar el handler
 */
class EventHandlerLoader
{
	// ── Maps de handlers cargados por nombre de evento ─────────────────────────

	/** HScript handlers indexados by name canónico of event. */
	static var _hx:Map<String, HScriptInstance> = new Map();

	/** Lua handlers indexados by name canónico of event. */
	#if (LUA_ALLOWED && linc_luajit)
	static var _lua:Map<String, LuaScriptInstance> = new Map();
	#end

	/** Contextos ya cargados (para evitar doble-carga). */
	static var _loadedContexts:Array<String> = [];

	// ── Carga ─────────────────────────────────────────────────────────────────

	/**
	 * Carga todos los handlers del contexto indicado.
	 * Llamar cuando se entra en el contexto (p.ej. al iniciar PlayState para "chart").
	 *
	 * @param context  "chart" | "cutscene" | "playstate" | "modchart" | "global"
	 */
	public static function loadContext(context:String):Void
	{
		if (_loadedContexts.contains(context)) return;
		_loadedContexts.push(context);

		final defs = EventRegistry.getByContext(context);
		for (def in defs) _loadDef(def);

		trace('[EventHandlerLoader] Contexto "$context": ${defs.length} eventos, '
			+ '${_hx.keys().hasNext() ? Lambda.count(_hx) : 0} HScript handlers cargados.');
	}

	/**
	 * Descarga todos los handlers de un contexto.
	 * Llamar al salir del contexto (p.ej. al destruir PlayState).
	 */
	public static function clearContext(context:String):Void
	{
		_loadedContexts.remove(context);
		final defs = EventRegistry.getByContext(context);
		for (def in defs)
		{
			final name = def.name;
			if (_hx.exists(name))
			{
				try _hx.get(name).call('onDestroy', []) catch(_) {}
				try _hx.get(name).dispose() catch(_) {}
				_hx.remove(name);
			}
			#if (LUA_ALLOWED && linc_luajit)
			if (_lua.exists(name))
			{
				try _lua.get(name).call('onDestroy', []) catch(_) {}
				try _lua.get(name).destroy() catch(_) {}
				_lua.remove(name);
			}
			#end
		}
	}

	/** Descarga TODOS los handlers de todos los contextos. */
	public static function clearAll():Void
	{
		_loadedContexts = [];
		for (s in _hx) { try s.call('onDestroy', []) catch(_) {}; try s.dispose() catch(_) {}; }
		_hx.clear();
		#if (LUA_ALLOWED && linc_luajit)
		for (s in _lua) { try s.call('onDestroy', []) catch(_) {}; try s.destroy() catch(_) {}; }
		_lua.clear();
		#end
	}

	// ── Dispatch ──────────────────────────────────────────────────────────────

	/**
	 * Llama al handler del evento si existe.
	 *
	 * @param name  Nombre del evento.
	 * @param v1    Valor 1.
	 * @param v2    Valor 2.
	 * @param time  Tiempo en ms.
	 * @return      true if the handler pidió cancelar the built-in.
	 */
	public static function dispatch(name:String, v1:String, v2:String, time:Float):Bool
	{
		// Resolve alias to the name canónico
		final canonical = EventRegistry.resolveAlias(name) ?? name;
		var cancelled = false;

		// ── HScript handler ───────────────────────────────────────────────────
		#if HSCRIPT_ALLOWED
		final hx = _hx.get(canonical);
		if (hx != null && hx.active)
		{
			try
			{
				hx.set('v1', v1);
				hx.set('v2', v2);
				hx.set('time', time);
				hx.set('game', funkin.gameplay.PlayState.instance);
				final result = hx.call('onTrigger', [v1, v2, time]);
				if (result == true) cancelled = true;
				// Also probar onEvent for compat with scripts globales
				if (!cancelled)
				{
					final r2 = hx.call('onEvent', [canonical, v1, v2, time]);
					if (r2 == true) cancelled = true;
				}
			}
			catch (e:Dynamic) trace('[EventHandlerLoader] Error en HScript "$canonical": $e');
		}
		#end

		// ── Lua handler ───────────────────────────────────────────────────────
		#if (LUA_ALLOWED && linc_luajit)
		final lua = _lua.get(canonical);
		if (lua != null && lua.active && !cancelled)
		{
			try
			{
				lua.set('v1', v1);
				lua.set('v2', v2);
				lua.set('time', time);
				final result = lua.call('onTrigger', [v1, v2, time]);
				if (result == true) cancelled = true;
				if (!cancelled)
				{
					final r2 = lua.call('onEvent', [canonical, v1, v2, time]);
					if (r2 == true) cancelled = true;
				}
			}
			catch (e:Dynamic) trace('[EventHandlerLoader] Error en Lua "$canonical": $e');
		}
		#end

		return cancelled;
	}

	/**
	 * Returns true if there is some handler (HScript or Lua) for the event.
	 */
	public static function hasHandler(name:String):Bool
	{
		final canonical = EventRegistry.resolveAlias(name) ?? name;
		#if (LUA_ALLOWED && linc_luajit)
		if (_lua.exists(canonical)) return true;
		#end
		return _hx.exists(canonical);
	}

	// ── Internals ─────────────────────────────────────────────────────────────

	static function _loadDef(def:EventDefinition):Void
	{
		final name = def.name;

		// ── HScript ──────────────────────────────────────────────────────────
		#if HSCRIPT_ALLOWED
		if (def.hscriptPath != null && !_hx.exists(name))
		{
			#if sys
			if (sys.FileSystem.exists(def.hscriptPath))
			{
				try
				{
					final script = new HScriptInstance(name, def.hscriptPath);
					script.set('game', funkin.gameplay.PlayState.instance);
					script.call('onCreate', []);
					_hx.set(name, script);
					trace('[EventHandlerLoader] HScript cargado: "${name}" ← ${def.hscriptPath}');
				}
				catch (e:Dynamic) trace('[EventHandlerLoader] Error cargando HScript "$name": $e');
			}
			#end
		}
		#end

		// ── Lua ──────────────────────────────────────────────────────────────
		#if (LUA_ALLOWED && linc_luajit)
		if (def.luaPath != null && !_lua.exists(name))
		{
			#if sys
			if (sys.FileSystem.exists(def.luaPath))
			{
				try
				{
					final lua = new LuaScriptInstance(name, def.luaPath);
					lua.call('onCreate', []);
					_lua.set(name, lua);
					trace('[EventHandlerLoader] Lua cargado: "${name}" ← ${def.luaPath}');
				}
				catch (e:Dynamic) trace('[EventHandlerLoader] Error cargando Lua "$name": $e');
			}
			#end
		}
		#end
	}
}
