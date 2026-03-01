package funkin.data;

import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import mods.ModManager;

/**
 * GlobalConfig — Configuración global de UI y noteskin.
 *
 * Archivo: assets/data/config/global.json  (base)
 *          mods/{activeMod}/data/config/global.json  (override por mod)
 *
 * Ejemplo de global.json:
 * {
 *   "ui":          "default",
 *   "noteSkin":    "arrows",
 *   "noteSplash":  "Default"
 * }
 *
 * Jerarquía de prioridad al resolver:
 *   meta.json de song  >  global.json del mod activo  >  global.json base  >  hardcoded
 *
 * AUTO-INVALIDACIÓN:
 *   El singleton detecta automáticamente cuando el mod activo cambia y se
 *   recarga solo. Se engancha a ModManager.onModChanged para re-inicializar
 *   NoteSkinSystem y aplicar el noteSkin/noteSplash del nuevo mod.
 */
class GlobalConfig
{
	// ─── Singleton ──────────────────────────────────────────────────────────────
	public static var instance(get, null):GlobalConfig;
	private static var _instance:GlobalConfig;

	/**
	 * Mod con el que se cargó la instancia actual.
	 * Centinela '__NONE__' = cargado sin mod activo.
	 * null = nunca cargado.
	 */
	private static var _loadedForMod:String = null;

	/** Evita registrar el hook más de una vez. */
	private static var _hooked:Bool = false;

	static function get_instance():GlobalConfig
	{
		_ensureHooked();

		final curMod:String = ModManager.activeMod != null ? ModManager.activeMod : '__NONE__';

		// Auto-recargar si el mod cambió desde la última carga
		if (_instance == null || _loadedForMod != curMod)
		{
			if (_instance != null)
				trace('[GlobalConfig] Mod cambió ("$_loadedForMod" → "$curMod"), recargando...');
			_instance     = _load(curMod);
			_loadedForMod = curMod;
		}

		return _instance;
	}

	/**
	 * Aplica los valores del GlobalConfig actual a NoteSkinSystem.
	 * Llamar después de NoteSkinSystem.init() para setear _modDefaultSkin/Splash
	 * sin releer el archivo de disco.
	 */
	public static function applyToSkinSystem():Void
	{
		if (_instance != null)
			_applyToSkinSystem(_instance);
		else
			_applyToSkinSystem(instance); // fuerza carga si aún no hay instancia
	}

	/**
	 * Fuerza una recarga desde disco y re-aplica skin/splash a NoteSkinSystem.
	 * Llamar tras guardar cambios en el editor de GlobalConfig.
	 */
	public static function reload():Void
	{
		final curMod:String = ModManager.activeMod != null ? ModManager.activeMod : '__NONE__';
		_instance     = _load(curMod);
		_loadedForMod = curMod;
		_applyToSkinSystem(_instance);
	}

	// ─── Propiedades ────────────────────────────────────────────────────────────

	/** Nombre del script de UI en assets/ui/{ui}/script.hx */
	public var ui:String = 'default';

	/** Nombre del noteskin en assets/skins/{noteSkin}/skin.json */
	public var noteSkin:String = 'default';

	/** Nombre del splash en assets/splashes/{noteSplash}/splash.json */
	public var noteSplash:String = 'Default';

	// ─── Carga interna ───────────────────────────────────────────────────────────

	function new() {}

	static function _load(curMod:String):GlobalConfig
	{
		var cfg      = new GlobalConfig();
		var path:String  = null;
		var fromMod:Bool = false;

		// ── Resolver path: mod activo → assets base ──────────────────────────
		#if sys
		final modPath = ModManager.resolveInMod('data/config/global.json');
		if (modPath != null)
		{
			path    = modPath;
			fromMod = true;
		}
		if (path == null)
		{
			final basePath = 'assets/data/config/global.json';
			if (FileSystem.exists(basePath)) path = basePath;
		}
		#else
		path = 'assets/data/config/global.json';
		#end

		if (path == null)
		{
			trace('[GlobalConfig] No existe global.json (mod=$curMod), usando defaults');
			return cfg;
		}

		try
		{
			var raw:Dynamic = Json.parse(File.getContent(path));

			if (raw.ui         != null) cfg.ui         = Std.string(raw.ui);
			if (raw.noteSkin   != null) cfg.noteSkin   = Std.string(raw.noteSkin);
			if (raw.noteSplash != null) cfg.noteSplash = Std.string(raw.noteSplash);

			final src = fromMod ? 'mod:${ModManager.activeMod}' : 'base';
			trace('[GlobalConfig] Cargado ($src) — ui="${cfg.ui}" skin="${cfg.noteSkin}" splash="${cfg.noteSplash}"');
		}
		catch (e)
		{
			trace('[GlobalConfig] Error al parsear $path: $e');
		}

		// Propagar al sistema de notas tras cada carga
		_applyToSkinSystem(cfg);

		return cfg;
	}

	// ─── Aplicar a NoteSkinSystem ────────────────────────────────────────────────

	/**
	 * Propaga noteSkin y noteSplash del GlobalConfig a NoteSkinSystem como
	 * valores "por defecto del mod activo", sin tocar el save del jugador.
	 *
	 * Usa setModDefaultSkin/setModDefaultSplash para que:
	 *   - El jugador pueda sobreescribirlos desde Opciones.
	 *   - Al cambiar de mod, el sistema vuelva al valor correcto.
	 *   - Las canciones con meta.json propio sigan teniendo prioridad máxima.
	 *   - applySkinForStage() → restoreGlobalSkin() respete el global.json del mod.
	 */
	private static function _applyToSkinSystem(cfg:GlobalConfig):Void
	{
		try
		{
			final skinSystem = funkin.gameplay.notes.NoteSkinSystem;

			if (cfg.noteSkin != null && cfg.noteSkin.toLowerCase() != 'default')
			{
				skinSystem.setModDefaultSkin(cfg.noteSkin);
				trace('[GlobalConfig → NoteSkinSystem] skin mod-default: "${cfg.noteSkin}"');
			}
			else
			{
				skinSystem.setModDefaultSkin(null);
			}

			if (cfg.noteSplash != null && cfg.noteSplash.toLowerCase() != 'default')
			{
				skinSystem.setModDefaultSplash(cfg.noteSplash);
				trace('[GlobalConfig → NoteSkinSystem] splash mod-default: "${cfg.noteSplash}"');
			}
			else
			{
				skinSystem.setModDefaultSplash(null);
			}
		}
		catch (e)
		{
			// Puede fallar si NoteSkinSystem no está inicializado aún (primeros frames)
			trace('[GlobalConfig] _applyToSkinSystem falló (posiblemente demasiado temprano): $e');
		}
	}

	// ─── Hook a ModManager ───────────────────────────────────────────────────────

	/**
	 * Registra el listener en ModManager.onModChanged la primera vez que se
	 * accede al singleton.
	 *
	 * Al cambiar de mod:
	 *   1. Invalida el singleton de GlobalConfig.
	 *   2. Recarga inmediatamente con el global.json del nuevo mod (o base).
	 *   3. Fuerza re-init de NoteSkinSystem para descubrir las skins del nuevo mod.
	 *   4. Aplica la skin/splash del nuevo GlobalConfig a NoteSkinSystem.
	 */
	private static function _ensureHooked():Void
	{
		if (_hooked) return;
		_hooked = true;

		final prevCallback = ModManager.onModChanged;
		ModManager.onModChanged = function(newMod:Null<String>):Void
		{
			// Propagar al callback anterior si existía
			if (prevCallback != null) prevCallback(newMod);

			final label = newMod != null ? '"$newMod"' : '(ninguno)';
			trace('[GlobalConfig] Mod cambió a $label — invalidando singleton...');

			// Invalidar y recargar inmediatamente
			final curMod  = newMod != null ? newMod : '__NONE__';
			_instance     = null;
			_loadedForMod = null;
			_instance     = _load(curMod);
			_loadedForMod = curMod;

			// Forzar re-init de NoteSkinSystem para descubrir las skins del nuevo mod
			funkin.gameplay.notes.NoteSkinSystem.forceReinit();
			funkin.gameplay.notes.NoteSkinSystem.init();
		};
	}

	// ─── Save ────────────────────────────────────────────────────────────────────

	/**
	 * Guarda la configuración actual a disco.
	 *
	 * Destino según contexto:
	 *   - Mod activo → mods/{activeMod}/data/config/global.json
	 *   - Sin mod    → assets/data/config/global.json
	 *
	 * Nunca sobreescribe el global base cuando hay un mod activo.
	 */
	public function save():Void
	{
		#if sys
		var savePath:String;
		final modRoot = ModManager.modRoot();

		if (modRoot != null)
		{
			final dir = '$modRoot/data/config';
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			savePath = '$dir/global.json';
		}
		else
		{
			final dir = 'assets/data/config';
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			savePath = '$dir/global.json';
		}

		try
		{
			final data = { ui: ui, noteSkin: noteSkin, noteSplash: noteSplash };
			File.saveContent(savePath, Json.stringify(data, null, '\t'));
			trace('[GlobalConfig] Guardado en $savePath');
		}
		catch (e)
		{
			trace('[GlobalConfig] Error al guardar en $savePath: $e');
		}
		#else
		trace('[GlobalConfig] save() no disponible en esta plataforma');
		#end
	}
}
