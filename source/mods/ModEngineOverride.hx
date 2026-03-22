package mods;

import flixel.FlxG;
import flixel.FlxState;
import haxe.ds.StringMap;
import haxe.Constraints.Function;

#if sys
import sys.FileSystem;
import sys.io.File;
import haxe.Json;
#end

/**
 * ModEngineOverride — Reemplaza o extiende CUALQUIER componente del engine desde mods.
 *
 * ─── What can be changed from a mod? ─────────────────────────────────────
 *
 *  ESTADOS (States)
 *    • Sustituir MainMenuState, FreeplayState, PlayState, etc. por clases propias del mod.
 *    • Inyectar hooks "before/after create(), update(), destroy()" sin reemplazar el state.
 *
 *  HUD
 *    • Register an alternative HUD class that the engine will instantiate in PlayState.
 *
 *  GAMEPLAY
 *    • Hook en onNoteHit, onNoteMiss, onSongStart, onSongEnd, onCountdown…
 *    • Override of the logic of rating/scoring complete.
 *    • Override de scroll speed, botones, receptor positions.
 *
 *  RENDERIZADO
 *    • Override of how a character is loaded and drawn.
 *    • Override of how a stage is loaded.
 *    • Override del noteskin pipeline.
 *
 *  AUDIO
 *    • Override of the conductor (BPM / offset) by song.
 *    • Override del volumen de voces/instrumentales.
 *
 *  UI GLOBAL
 *    • Override of fonts, colores, layout of menus.
 *    • Override del transition shader entre estados.
 *
 * ─── Uso desde un script de mod (script.hx) ──────────────────────────────────
 *
 *  // Reemplazar the menu main by uno propio:
 *  ModEngineOverride.replaceState("MainMenuState", MyCustomMenu);
 *
 *  // Inyectar hook en cada nota acertada sin reemplazar PlayState:
 *  ModEngineOverride.onGameplayEvent("onNoteHit", function(note) {
 *    trace("Note hit! " + note.noteType);
 *  });
 *
 *  // Change all the logic of scoring:
 *  ModEngineOverride.replaceScoring(MyCustomScoringClass);
 *
 *  // Reemplazar el HUD completo:
 *  ModEngineOverride.replaceHUD(MyHUD);
 *
 *  // Reemplazar el sistema de notas:
 *  ModEngineOverride.replaceNoteSystem(MyNoteSystem);
 *
 *  // Descargar todos los overrides al cambiar de mod:
 *  ModEngineOverride.clear();
 *
 * ─── Auto-load from mod.json ─────────────────────────────────────────
 *
 *  Si el mod incluye "engineOverrides": { ... } en su mod.json, se aplican
 *  automatically to the activar the mod. Ejemplo:
 *
 *  "engineOverrides": {
 *    "states": {
 *      "MainMenuState":  "mymod.MyMenu",
 *      "FreeplayState":  "mymod.MyFreeplay"
 *    },
 *    "hud":     "mymod.MyHUD",
 *    "scoring": "mymod.MyScoring",
 *    "notes":   "mymod.MyNoteSystem",
 *    "transition": "mymod.MyTransition"
 *  }
 *
 * @author Cool Engine Team
 * @version 2.0.0
 */
class ModEngineOverride
{
	// ── Singleton ──────────────────────────────────────────────────────────────
	public static var instance(get, null):ModEngineOverride;
	static function get_instance():ModEngineOverride
	{
		if (instance == null) instance = new ModEngineOverride();
		return instance;
	}

	// ── Registro de overrides ──────────────────────────────────────────────────

	/** Mapa de nombre de State → clase de reemplazo (o factory). */
	var _stateOverrides : StringMap<StateFactory>          = new StringMap();

	/** Hooks de eventos de gameplay: nombre → lista de callbacks. */
	var _gameplayHooks  : StringMap<Array<GameplayHook>>   = new StringMap();

	/** Clase HUD de reemplazo (null = usar el default del engine). */
	var _hudClass       : Null<Class<Dynamic>>             = null;

	/** Clase de scoring de reemplazo. */
	var _scoringClass   : Null<Class<Dynamic>>             = null;

	/** Clase de sistema de notas de reemplazo. */
	var _noteSystemClass : Null<Class<Dynamic>>            = null;

	/** Class of transition of reemplazo. */
	var _transitionClass : Null<Class<Dynamic>>            = null;

	/** Metadatos extra que el mod puede adjuntar (para scripts avanzados). */
	var _metadata       : StringMap<Dynamic>               = new StringMap();

	/** Lista de mods que tienen overrides activos (para multi-mod). */
	var _activeMods     : Array<String>                    = [];

	// ── Constructor ────────────────────────────────────────────────────────────
	function new() {}

	// ══════════════════════════════════════════════════════════════════════════
	// OVERRIDE DE ESTADOS
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Registra una clase de State como reemplazo para un estado del engine.
	 *
	 * @param stateName  Nombre del estado a reemplazar (ej: "MainMenuState").
	 * @param cls        Clase Haxe que extiende FlxState (o compatible).
	 * @param args       Argumentos opcionales para el constructor.
	 *
	 * @example
	 *   ModEngineOverride.replaceState("MainMenuState", MyMenu);
	 */
	public static function replaceState(stateName:String, cls:Class<Dynamic>, ?args:Array<Dynamic>):Void
	{
		instance._stateOverrides.set(stateName, { cls: cls, args: args ?? [] });
		trace('[ModEngineOverride] Estado reemplazado: "$stateName" → ${Type.getClassName(cls)}');
	}

	/**
	 * Elimina the override of a state specific.
	 */
	public static function removeStateOverride(stateName:String):Void
		instance._stateOverrides.remove(stateName);

	/**
	 * Devuelve una nueva instancia del estado reemplazado, o null si no hay override.
	 * El engine llama esto antes de instanciar cualquier state.
	 *
	 * @param stateName  El nombre del state que el engine va a crear.
	 * @return           La instancia del state de reemplazo, o null si no hay override.
	 */
	public static function resolveState(stateName:String):Null<FlxState>
	{
		final factory = instance._stateOverrides.get(stateName);
		if (factory == null) return null;
		try
		{
			final inst = Type.createInstance(factory.cls, factory.args);
			trace('[ModEngineOverride] State resuelto: "$stateName" → ${Type.getClassName(factory.cls)}');
			return cast inst;
		}
		catch (e:Dynamic)
		{
			trace('[ModEngineOverride] ERROR creando state "$stateName": $e');
			return null;
		}
	}

	/** true si hay un override activo para el estado dado. */
	public static function hasStateOverride(stateName:String):Bool
		return instance._stateOverrides.exists(stateName);

	// ══════════════════════════════════════════════════════════════════════════
	// OVERRIDE DE HUD
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Registra una clase HUD personalizada.
	 * The engine will instantiate this class instead of the default HUD in PlayState.
	 *
	 * @param cls  Clase del HUD. Debe ser compatible con el HUD base del engine.
	 */
	public static function replaceHUD(cls:Class<Dynamic>):Void
	{
		instance._hudClass = cls;
		trace('[ModEngineOverride] HUD reemplazado → ${Type.getClassName(cls)}');
	}

	public static function removeHUDOverride():Void    instance._hudClass = null;
	public static function hasHUDOverride():Bool        return instance._hudClass != null;

	/**
	 * Crea el HUD con la clase registrada, o null si no hay override.
	 * PlayState llama esto en su create().
	 */
	public static function resolveHUD(?args:Array<Dynamic>):Null<Dynamic>
	{
		if (instance._hudClass == null) return null;
		try   { return Type.createInstance(instance._hudClass, args ?? []); }
		catch (e:Dynamic) { trace('[ModEngineOverride] ERROR creando HUD: $e'); return null; }
	}

	// ══════════════════════════════════════════════════════════════════════════
	// OVERRIDE DE SCORING
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Reemplaza el sistema de scoring (rating, puntos, combos).
	 * The class debe implementar the methods of the IScoringSystem of the engine.
	 */
	public static function replaceScoring(cls:Class<Dynamic>):Void
	{
		instance._scoringClass = cls;
		trace('[ModEngineOverride] Scoring reemplazado → ${Type.getClassName(cls)}');
	}

	public static function removeScoringOverride():Void instance._scoringClass = null;
	public static function hasScoringOverride():Bool     return instance._scoringClass != null;

	public static function resolveScoring(?args:Array<Dynamic>):Null<Dynamic>
	{
		if (instance._scoringClass == null) return null;
		try   { return Type.createInstance(instance._scoringClass, args ?? []); }
		catch (e:Dynamic) { trace('[ModEngineOverride] ERROR creando Scoring: $e'); return null; }
	}

	// ══════════════════════════════════════════════════════════════════════════
	// OVERRIDE DE SISTEMA DE NOTAS
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Replaces the note system (spawning, timing windows, mechanics).
	 */
	public static function replaceNoteSystem(cls:Class<Dynamic>):Void
	{
		instance._noteSystemClass = cls;
		trace('[ModEngineOverride] NoteSystem reemplazado → ${Type.getClassName(cls)}');
	}

	public static function removeNoteSystemOverride():Void instance._noteSystemClass = null;
	public static function hasNoteSystemOverride():Bool     return instance._noteSystemClass != null;

	public static function resolveNoteSystem(?args:Array<Dynamic>):Null<Dynamic>
	{
		if (instance._noteSystemClass == null) return null;
		try   { return Type.createInstance(instance._noteSystemClass, args ?? []); }
		catch (e:Dynamic) { trace('[ModEngineOverride] ERROR creando NoteSystem: $e'); return null; }
	}

	// ══════════════════════════════════════════════════════════════════════════
	// OVERRIDE of transition
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Reemplaza the shader/effect of transition between states.
	 */
	public static function replaceTransition(cls:Class<Dynamic>):Void
	{
		instance._transitionClass = cls;
		trace('[ModEngineOverride] Transition reemplazado → ${Type.getClassName(cls)}');
	}

	public static function removeTransitionOverride():Void instance._transitionClass = null;
	public static function hasTransitionOverride():Bool     return instance._transitionClass != null;

	public static function resolveTransition(?args:Array<Dynamic>):Null<Dynamic>
	{
		if (instance._transitionClass == null) return null;
		try   { return Type.createInstance(instance._transitionClass, args ?? []); }
		catch (e:Dynamic) { trace('[ModEngineOverride] ERROR creando Transition: $e'); return null; }
	}

	// ══════════════════════════════════════════════════════════════════════════
	// HOOKS DE GAMEPLAY
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Registra un callback para un evento de gameplay.
	 *
	 * Eventos disponibles (expandibles por mods):
	 *   "onNoteHit"      — (note:Dynamic) → Void
	 *   "onNoteMiss"     — (note:Dynamic) → Void
	 *   "onNoteSpawn"    — (note:Dynamic) → Void
	 *   "onSongStart"    — () → Void
	 *   "onSongEnd"      — () → Void
	 *   "onCountdown"    — (step:Int) → Void
	 *   "onCameraMove"   — (x:Float, y:Float) → Void
	 *   "onBeat"         — (beat:Int) → Void
	 *   "onStep"         — (step:Int) → Void
	 *   "onSection"      — (section:Int) → Void
	 *   "onHealthChange" — (delta:Float, newHealth:Float) → Void
	 *   "onGameOver"     — () → Void
	 *   "onPause"        — () → Void
	 *   "onResume"       — () → Void
	 *
	 * Puedes registrar cuantos callbacks quieras para el mismo evento.
	 * Se ejecutan en orden de registro.
	 *
	 * @param event     Nombre del evento.
	 * @param callback  Function to callr. Use Dynamic for compatibility of firma.
	 * @param priority  Mayor number = is ejecuta before. Default = 0.
	 *
	 * @example
	 *   ModEngineOverride.onGameplayEvent("onNoteHit", function(note) {
	 *     FlxG.log.add("Hit! noteType=" + note.noteType);
	 *   });
	 */
	public static function onGameplayEvent(event:String, callback:Dynamic, priority:Int = 0):Void
	{
		var hooks = instance._gameplayHooks.get(event);
		if (hooks == null)
		{
			hooks = [];
			instance._gameplayHooks.set(event, hooks);
		}
		hooks.push({ fn: callback, priority: priority });
		// Ordenar por prioridad descendente (mayor prioridad primero)
		haxe.ds.ArraySort.sort(hooks, (a, b) -> b.priority - a.priority);
		trace('[ModEngineOverride] Hook registrado: "$event" (priority=$priority)');
	}

	/**
	 * Elimina a callback specific of a event.
	 */
	public static function removeGameplayHook(event:String, callback:Dynamic):Void
	{
		var hooks = instance._gameplayHooks.get(event);
		if (hooks == null) return;
		hooks = [for (h in hooks) if (h.fn != callback) h];
		instance._gameplayHooks.set(event, hooks);
	}

	/**
	 * Ejecuta todos los hooks registrados para un evento.
	 * El engine llama esto en los puntos relevantes de PlayState.
	 *
	 * @param event  Nombre del evento.
	 * @param args   Argumentos a pasar a cada callback.
	 */
	public static function fireEvent(event:String, ?args:Array<Dynamic>):Void
	{
		final hooks = instance._gameplayHooks.get(event);
		if (hooks == null || hooks.length == 0) return;
		final safeArgs = args ?? [];
		for (h in hooks)
		{
			try   { Reflect.callMethod(null, h.fn, safeArgs); }
			catch (e:Dynamic) { trace('[ModEngineOverride] ERROR en hook "$event": $e'); }
		}
	}

	/**
	 * Version with retorno: ejecuta hooks until that uno returns non-null.
	 * Useful for overrides that producen a value (ej: rating, scoring).
	 *
	 * @return The first non-null value returned, or null if no hook respondsd.
	 */
	public static function fireEventWithResult(event:String, ?args:Array<Dynamic>):Null<Dynamic>
	{
		final hooks = instance._gameplayHooks.get(event);
		if (hooks == null) return null;
		final safeArgs = args ?? [];
		for (h in hooks)
		{
			try
			{
				final result = Reflect.callMethod(null, h.fn, safeArgs);
				if (result != null) return result;
			}
			catch (e:Dynamic) { trace('[ModEngineOverride] ERROR en hook "$event" (result): $e'); }
		}
		return null;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// METADATA DE MOD
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Almacena un valor arbitrario con el override (para scripts avanzados).
	 * The scripts of mod pueden usarlo for pasar configuration to the engine.
	 */
	public static function setMeta(key:String, value:Dynamic):Void
		instance._metadata.set(key, value);

	public static function getMeta(key:String, ?defaultValue:Dynamic):Dynamic
	{
		final v = instance._metadata.get(key);
		return v != null ? v : defaultValue;
	}

	public static function hasMeta(key:String):Bool
		return instance._metadata.exists(key);

	// ══════════════════════════════════════════════════════════════════════════
	// CARGA DESDE mod.json
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Lee the section "engineOverrides" of mod.json and applies the overrides.
	 *
	 * Formato en mod.json:
	 * {
	 *   "engineOverrides": {
	 *     "states": {
	 *       "MainMenuState": "mymod.MyMenu",
	 *       "FreeplayState": "mymod.MyFreeplay"
	 *     },
	 *     "hud":        "mymod.MyHUD",
	 *     "scoring":    "mymod.MyScoring",
	 *     "notes":      "mymod.MyNoteSystem",
	 *     "transition": "mymod.MyTransition"
	 *   }
	 * }
	 */
	/**
	 * Lee el mod.json desde disco y aplica los engineOverrides.
	 * If ModManager already parsed the JSON (in _loadModInfo), use applyFromRaw
	 * directamente para evitar el doble parse.
	 */
	public static function loadFromModJson(modJsonPath:String, modId:String):Void
	{
		#if sys
		if (!FileSystem.exists(modJsonPath)) return;
		try
		{
			final raw:Dynamic = Json.parse(File.getContent(modJsonPath));
			if (raw.engineOverrides != null)
				applyFromRaw(raw.engineOverrides, modId);
		}
		catch (e:Dynamic) { trace('[ModEngineOverride] Error parseando mod.json de "$modId": $e'); }
		#end
	}

	/**
	 * Aplica los engineOverrides desde un objeto Dynamic ya parseado.
	 * Llamado por ModManager._loadModInfo (cuando el mod es activado durante
	 * el escaneo) y por loadFromModJson (resto de casos).
	 *
	 * @param overrides  El objeto raw.engineOverrides del mod.json ya parseado.
	 * @param modId      ID del mod (para logs y tracking).
	 */
	public static function applyFromRaw(overrides:Dynamic, modId:String):Void
	{
		if (overrides == null) return;

		// ── Estados ───────────────────────────────────────────────────────────
		if (overrides.states != null)
		{
			for (stateName in Reflect.fields(overrides.states))
			{
				final className:String = Reflect.field(overrides.states, stateName);
				final cls = Type.resolveClass(className);
				if (cls != null)
					replaceState(stateName, cls);
				else
					trace('[ModEngineOverride] Clase no encontrada: "$className" (state "$stateName")');
			}
		}

		// ── HUD ───────────────────────────────────────────────────────────────
		if (overrides.hud != null)
		{
			final cls = Type.resolveClass(Std.string(overrides.hud));
			if (cls != null) replaceHUD(cls);
			else trace('[ModEngineOverride] Clase HUD no encontrada: "${overrides.hud}"');
		}

		// ── Scoring ───────────────────────────────────────────────────────────
		if (overrides.scoring != null)
		{
			final cls = Type.resolveClass(Std.string(overrides.scoring));
			if (cls != null) replaceScoring(cls);
		}

		// ── Notes ─────────────────────────────────────────────────────────────
		if (overrides.notes != null)
		{
			final cls = Type.resolveClass(Std.string(overrides.notes));
			if (cls != null) replaceNoteSystem(cls);
		}

		// ── Transition ────────────────────────────────────────────────────────
		if (overrides.transition != null)
		{
			final cls = Type.resolveClass(Std.string(overrides.transition));
			if (cls != null) replaceTransition(cls);
		}

		// ── Metadata extra ────────────────────────────────────────────────────
		if (overrides.meta != null)
		{
			for (key in Reflect.fields(overrides.meta))
				setMeta(key, Reflect.field(overrides.meta, key));
		}

		if (!instance._activeMods.contains(modId))
			instance._activeMods.push(modId);

		trace('[ModEngineOverride] Overrides aplicados para "$modId"');
	}

	// ══════════════════════════════════════════════════════════════════════════
	// LIMPIAR / RESET
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Elimina TODOS los overrides registrados.
	 * Llamar al desactivar un mod o al volver al engine base.
	 */
	public static function clear():Void
	{
		instance._stateOverrides  = new StringMap();
		instance._gameplayHooks   = new StringMap();
		instance._hudClass        = null;
		instance._scoringClass    = null;
		instance._noteSystemClass = null;
		instance._transitionClass = null;
		instance._metadata        = new StringMap();
		instance._activeMods      = [];
		trace('[ModEngineOverride] Todos los overrides eliminados.');
	}

	/**
	 * Elimina only the overrides of a mod specific
	 * (para sistemas multi-mod donde se activa/desactiva uno a la vez).
	 */
	public static function clearForMod(modId:String):Void
	{
		instance._activeMods.remove(modId);
		// Si ya no hay mods con overrides, limpiar todo
		if (instance._activeMods.length == 0) clear();
		else trace('[ModEngineOverride] Overrides de "$modId" eliminados.');
	}

	// ══════════════════════════════════════════════════════════════════════════
	// DEBUG / STATS
	// ══════════════════════════════════════════════════════════════════════════

	/** Resumen de los overrides activos para debug. */
	public static function debugInfo():String
	{
		final sb = new StringBuf();
		sb.add('[ModEngineOverride] ──────────────────────────\n');
		sb.add('  Mods activos: ${instance._activeMods.join(", ")}\n');

		// States
		var stateCount = 0;
		for (k in instance._stateOverrides.keys()) stateCount++;
		sb.add('  States override: $stateCount\n');
		for (k => v in instance._stateOverrides)
			sb.add('    • $k → ${Type.getClassName(v.cls)}\n');

		// HUD / Scoring / Notes / Transition
		sb.add('  HUD:        ${instance._hudClass        != null ? Type.getClassName(instance._hudClass)        : "(default)"}\n');
		sb.add('  Scoring:    ${instance._scoringClass    != null ? Type.getClassName(instance._scoringClass)    : "(default)"}\n');
		sb.add('  NoteSystem: ${instance._noteSystemClass != null ? Type.getClassName(instance._noteSystemClass) : "(default)"}\n');
		sb.add('  Transition: ${instance._transitionClass != null ? Type.getClassName(instance._transitionClass) : "(default)"}\n');

		// Hooks
		var hookCount = 0;
		for (k in instance._gameplayHooks.keys())
		{
			final arr = instance._gameplayHooks.get(k);
			sb.add('  Hook "$k": ${arr?.length ?? 0} callbacks\n');
			hookCount++;
		}
		sb.add('  Total hooks: $hookCount eventos\n');
		sb.add('──────────────────────────────────────────────');
		return sb.toString();
	}
}

// ── Tipos auxiliares ─────────────────────────────────────────────────────────

/** Factory para crear instancias de states. */
private typedef StateFactory = {
	cls  : Class<Dynamic>,
	args : Array<Dynamic>
}

/** Entrada de hook con prioridad. */
private typedef GameplayHook = {
	fn       : Dynamic,
	priority : Int
}
