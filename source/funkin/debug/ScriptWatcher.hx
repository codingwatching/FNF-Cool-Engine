package funkin.debug;

#if (sys)

import sys.FileSystem;

using StringTools;
import sys.io.File;
import funkin.scripting.ScriptHandler;
import funkin.scripting.StateScriptHandler;
import funkin.scripting.HScriptInstance;

/**
 * ScriptWatcher — Live reload de scripts .hx / .hscript / .lua en tiempo real.
 *
 * ─── ¿Qué hace? ───────────────────────────────────────────────────────────────
 *
 *  Mientras el juego corre, escanea cada POLL_INTERVAL segundos los archivos
 *  registrados (y sus carpetas). Si detecta que un archivo fue modificado en
 *  disco (mtime cambió) lo recarga al instante SIN reiniciar el state:
 *
 *   • .hx / .hscript  → HScriptInstance.hotReload() → reejecutar el script
 *                        con el intérprete existente. Las variables del state
 *                        (bf, dad, stage, etc.) se re-inyectan automáticamente.
 *
 *   • .lua             → LuaScriptInstance.hotReload() si LUA_ALLOWED.
 *
 *  Además, si aparece un archivo NUEVO en una carpeta vigilada, lo carga
 *  dinámicamente con el scriptType correspondiente.
 *
 * ─── Integración ──────────────────────────────────────────────────────────────
 *
 *  MusicBeatState.update() llama ScriptWatcher.poll(elapsed) exactamente
 *  igual que hace con JsonWatcher. No necesitas hacer nada más.
 *
 *  Para forzar un hot-reload manual desde teclado: F7 (en developerMode).
 *
 * ─── Flujo de recarga ──────────────────────────────────────────────────────────
 *
 *  1. ScriptWatcher detecta que script.path fue modificado.
 *  2. Llama script.hotReload() → re-parsea el archivo, re-expone ScriptAPI,
 *     invalida el caché de funciones, re-ejecuta el programa (re-define funciones),
 *     llama onCreate() + postCreate().
 *  3. Re-inyecta las variables del state actual (refreshStateFields) para que
 *     los nuevos objetos que el script añada tengan acceso a bf, dad, stage, etc.
 *  4. Llama onReload(scriptName) en TODOS los scripts — útil para que otros
 *     scripts reaccionen al cambio.
 *  5. Loguea en GameDevConsole con color verde.
 *
 * ─── API desde scripts ────────────────────────────────────────────────────────
 *
 *  Dentro de tu .hx / .lua puedes definir:
 *
 *    function onReload(who) {
 *        // Se llama cuando CUALQUIER script (incluyendo este) fue recargado.
 *        // 'who' = nombre del script que se recargó.
 *        trace('Script recargado: ' + who);
 *    }
 *
 * ─── Teclas de debug ──────────────────────────────────────────────────────────
 *
 *  F7  → Hot-reload inmediato de TODOS los scripts (sin esperar al poll)
 *
 * @author Cool Engine Team
 * @version 1.0.0
 */
class ScriptWatcher
{
	// ── Configuración ─────────────────────────────────────────────────────────

	/** Intervalo entre scans en segundos. 0.5 = 2 veces por segundo. */
	public static inline var POLL_INTERVAL:Float = 0.5;

	// ── Estado interno ────────────────────────────────────────────────────────

	/** Archivos de script activos → su mtime en el último check. */
	static var _fileMtimes:Map<String, Float> = [];

	/** Carpetas vigiladas para detectar archivos nuevos. */
	static var _watchedFolders:Array<WatchedFolder> = [];

	/** Referencia al state actual (para re-inyectar vars tras reload). */
	static var _currentState:flixel.FlxState = null;

	/** Acumulador de tiempo para throttle. */
	static var _timer:Float = 0.0;

	/** Si false, el watcher está pausado (ej: durante una transición). */
	public static var enabled:Bool = true;

	// ── Init / Clear ──────────────────────────────────────────────────────────

	/**
	 * Registra el state actual y re-escanea todos los scripts cargados.
	 * Llamar desde MusicBeatState.create() después de cargar los scripts.
	 */
	public static function init(state:flixel.FlxState):Void
	{
		_currentState = state;
		_fileMtimes.clear();
		_watchedFolders = [];
		_timer = 0.0;

		// Registrar todos los scripts ya cargados en ScriptHandler
		_indexLayer(ScriptHandler.globalScripts);
		_indexLayer(ScriptHandler.stageScripts);
		_indexLayer(ScriptHandler.songScripts);
		_indexLayer(ScriptHandler.uiScripts);
		_indexLayer(ScriptHandler.menuScripts);
		_indexLayer(ScriptHandler.charScripts);

		// Registrar scripts del StateScriptHandler
		for (s in StateScriptHandler.scripts)
			_indexScript(s);

		#if (LUA_ALLOWED && linc_luajit)
		_indexLuaLayer(ScriptHandler.globalLuaScripts);
		_indexLuaLayer(ScriptHandler.stageLuaScripts);
		_indexLuaLayer(ScriptHandler.songLuaScripts);
		_indexLuaLayer(ScriptHandler.uiLuaScripts);
		_indexLuaLayer(ScriptHandler.menuLuaScripts);
		_indexLuaLayer(ScriptHandler.charLuaScripts);
		for (lua in StateScriptHandler.luaScripts)
			if (lua.filePath != null && lua.filePath != '') _fileMtimes.set(lua.filePath, _mtime(lua.filePath));
		#end

		trace('[ScriptWatcher] Inicializado. ${Lambda.count(_fileMtimes)} archivos vigilados.');
	}

	/** Limpia todo al cambiar de state. */
	public static function clear():Void
	{
		_fileMtimes.clear();
		_watchedFolders = [];
		_currentState = null;
		_timer = 0.0;
	}

	/**
	 * Vigila una carpeta entera. Si aparece un .hx/.lua nuevo, se carga
	 * automáticamente con el scriptType indicado.
	 *
	 * @param folderPath  Ruta absoluta o relativa a la carpeta.
	 * @param scriptType  'song' | 'stage' | 'menu' | 'global' | 'ui' | 'char'
	 */
	public static function watchFolder(folderPath:String, scriptType:String):Void
	{
		if (!FileSystem.exists(folderPath) || !FileSystem.isDirectory(folderPath)) return;

		// Snapshot de los archivos que ya existen (no los cargamos de nuevo)
		var known:Map<String, Bool> = [];
		for (f in FileSystem.readDirectory(folderPath))
			if (_isScript(f)) known.set(f, true);

		_watchedFolders.push({ path: folderPath, type: scriptType, known: known });
		trace('[ScriptWatcher] Carpeta vigilada [$scriptType]: $folderPath');
	}

	/**
	 * Registra los scripts de un personaje ya cargados para vigilancia.
	 * Llamar desde PlayState después de ScriptHandler.loadCharacterScripts().
	 *
	 * @param charName  Nombre del personaje (ej: 'bf', 'dad')
	 */
	public static function watchCharacterScripts(charName:String):Void
	{
		// Index scripts already loaded for this character
		final list = ScriptHandler.charScriptsByName.get(charName);
		if (list != null) for (s in list) _indexScript(s);

		// Watch the character script folders for new files
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			watchFolder('$r/characters/scripts/$charName', 'char');
			watchFolder('$r/characters/$charName/scripts', 'char');
		}
		watchFolder('assets/characters/scripts/$charName', 'char');
		watchFolder('assets/characters/$charName/scripts', 'char');
	}

	/**
	 * Registra los scripts de un stage ya cargados para vigilancia.
	 * Llamar desde PlayState/Stage después de ScriptHandler.loadStageScripts().
	 *
	 * @param stageName  Nombre del stage (ej: 'stage_week1')
	 */
	public static function watchStageScripts(stageName:String):Void
	{
		// Index scripts already loaded for this stage
		for (s in ScriptHandler.stageScripts) _indexScript(s);

		// Watch the stage script folders for new files
		final sn = stageName.toLowerCase();
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			watchFolder('$r/stages/$sn/scripts',        'stage');
			watchFolder('$r/assets/stages/$sn/scripts', 'stage');
		}
		watchFolder('assets/stages/$sn/scripts',       'stage');
		watchFolder('assets/data/stages/$sn/scripts',  'stage');
	}

	/**
	 * Registra los scripts de la canción actual para vigilancia.
	 * Llamar desde PlayState después de ScriptHandler.loadSongScripts().
	 *
	 * @param songName  Nombre de la canción en minúsculas (ej: 'bopeebo')
	 */
	public static function watchSongScripts(songName:String):Void
	{
		for (s in ScriptHandler.songScripts) _indexScript(s);

		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			watchFolder('$r/songs/$songName/scripts', 'song');
			watchFolder('$r/songs/$songName/events',  'song');
			watchFolder('$r/data/$songName',          'song');
		}
		watchFolder('assets/songs/$songName/scripts', 'song');
		watchFolder('assets/songs/$songName/events',  'song');
	}

	// ── Poll ──────────────────────────────────────────────────────────────────

	/**
	 * Llamar cada frame desde MusicBeatState.update().
	 * Hace el trabajo real solo cada POLL_INTERVAL segundos.
	 */
	public static function poll(elapsed:Float):Void
	{
		if (!enabled) return;

		_timer += elapsed;
		if (_timer < POLL_INTERVAL) return;
		_timer = 0.0;

		_checkFiles();
		_checkFolders();
	}

	/**
	 * Fuerza un reload inmediato de todos los scripts sin esperar al poll.
	 * Equivalente a pulsar F7.
	 */
	public static function forceReloadAll():Void
	{
		ScriptHandler.hotReloadAll();
		StateScriptHandler.hotReloadAll();

		_notifyReload('*');
		_refreshStateVars();

		final msg = '[ScriptWatcher] Reload forzado — todos los scripts.';
		trace(msg);
		_log(msg, 0xFF69F0AE);
	}

	// ── Indexado ──────────────────────────────────────────────────────────────

	/**
	 * Añade un script individual al índice de vigilancia.
	 * Llamar desde fuera si se carga un script en tiempo de ejecución
	 * DESPUÉS de ScriptWatcher.init().
	 */
	public static function indexScript(script:HScriptInstance):Void
		_indexScript(script);

	// ── Internos ──────────────────────────────────────────────────────────────

	static function _indexLayer(layer:Map<String, HScriptInstance>):Void
		for (s in layer) _indexScript(s);

	static function _indexScript(s:HScriptInstance):Void
	{
		if (s == null || s.path == null || s.path == '') return;
		if (!FileSystem.exists(s.path)) return;
		_fileMtimes.set(s.path, _mtime(s.path));
	}

	#if (LUA_ALLOWED && linc_luajit)
	static function _indexLuaLayer(layer:Array<funkin.scripting.LuaScriptInstance>):Void
		for (lua in layer)
			if (lua.filePath != null && lua.filePath != '' && FileSystem.exists(lua.filePath))
				_fileMtimes.set(lua.filePath, _mtime(lua.filePath));
	#end

	/** Comprueba si algún archivo registrado fue modificado. */
	static function _checkFiles():Void
	{
		for (path => oldMtime in _fileMtimes)
		{
			if (!FileSystem.exists(path)) continue;
			final newMtime = _mtime(path);
			if (newMtime == oldMtime) continue;

			_fileMtimes.set(path, newMtime);
			_reloadFile(path);
		}
	}

	/** Comprueba si aparecieron archivos nuevos en carpetas vigiladas. */
	static function _checkFolders():Void
	{
		for (folder in _watchedFolders)
		{
			if (!FileSystem.exists(folder.path)) continue;
			for (file in FileSystem.readDirectory(folder.path))
			{
				if (!_isScript(file)) continue;
				if (folder.known.exists(file)) continue;

				// ¡Archivo nuevo! Registrarlo y cargarlo.
				folder.known.set(file, true);
				final fullPath = '${folder.path}/$file';
				_fileMtimes.set(fullPath, _mtime(fullPath));

				final s = ScriptHandler.loadScript(fullPath, folder.type);
				if (s != null)
				{
					_injectStateVarsInto(s);
					final msg = '[ScriptWatcher] NUEVO script detectado y cargado: $file';
					trace(msg);
					_log(msg, 0xFF69F0AE);
					_notifyReload(s.name);
				}
			}
		}
	}

	/** Recarga el script cuyo archivo es `path`. */
	static function _reloadFile(path:String):Void
	{
		var reloadedName:String = null;

		// ── 1. Buscar en ScriptHandler (todas las capas) ──────────────────────
		#if HSCRIPT_ALLOWED
		final allLayers = [
			ScriptHandler.globalScripts, ScriptHandler.stageScripts,
			ScriptHandler.songScripts,   ScriptHandler.uiScripts,
			ScriptHandler.menuScripts,   ScriptHandler.charScripts
		];
		for (layer in allLayers)
		{
			for (s in layer)
			{
				if (s.path != path) continue;
				final ok = s.hotReload();
				if (ok)
				{
					reloadedName = s.name;
					_injectStateVarsInto(s);
				}
				break;
			}
			if (reloadedName != null) break;
		}

		// ── 2. Buscar en StateScriptHandler ───────────────────────────────────
		if (reloadedName == null)
		{
			for (s in StateScriptHandler.scripts)
			{
				if (s.path != path) continue;
				final ok = s.hotReload();
				if (ok)
				{
					reloadedName = s.name;
					// Re-inyectar campos del state (objetos que el script podría necesitar)
					if (_currentState != null)
						StateScriptHandler.refreshStateFields(_currentState);
				}
				break;
			}
		}
		#end

		#if (LUA_ALLOWED && linc_luajit)
		// ── 3. Buscar en capas Lua de ScriptHandler ───────────────────────────
		if (reloadedName == null)
		{
			final luaLayers = [
				ScriptHandler.globalLuaScripts, ScriptHandler.stageLuaScripts,
				ScriptHandler.songLuaScripts,   ScriptHandler.uiLuaScripts,
				ScriptHandler.menuLuaScripts,   ScriptHandler.charLuaScripts
			];
			for (layer in luaLayers)
			{
				for (lua in layer)
				{
					if (lua.filePath != path) continue;
					lua.hotReload();
					reloadedName = lua.id;
					break;
				}
				if (reloadedName != null) break;
			}
		}

		// ── 4. Buscar en Lua de StateScriptHandler ────────────────────────────
		if (reloadedName == null)
		{
			for (lua in StateScriptHandler.luaScripts)
			{
				if (lua.filePath != path) continue;
				lua.hotReload();
				reloadedName = lua.id;
				break;
			}
		}
		#end

		if (reloadedName != null)
		{
			final fileName = path.split('/').pop();
			final msg = '[ScriptWatcher] ♻ Recargado: $fileName';
			trace(msg);
			_log(msg, 0xFF69F0AE);
			_notifyReload(reloadedName);
		}
	}

	/**
	 * Re-inyecta las variables del state actual en un script recién recargado.
	 * Esto garantiza que el script vea los objetos actuales (bf, dad, stage…)
	 * incluso si se recarga después de que el state terminó su create().
	 */
	static function _injectStateVarsInto(script:HScriptInstance):Void
	{
		#if HSCRIPT_ALLOWED
		if (script == null || script.interp == null || _currentState == null) return;

		// Inyectar todos los campos del state por reflexión
		var cls:Dynamic = Type.getClass(_currentState);
		while (cls != null)
		{
			for (field in Type.getInstanceFields(cls))
			{
				try
				{
					final value = Reflect.getProperty(_currentState, field);
					script.interp.variables.set(field, value);
				}
				catch (_) {}
			}
			cls = Type.getSuperClass(cls);
			if (cls != null && Type.getClassName(cls) == 'flixel.FlxState') break;
		}

		// Variables especiales explícitas
		script.interp.variables.set('state', _currentState);

		// PlayState si aplica
		final ps = funkin.gameplay.PlayState.instance;
		if (ps != null)
		{
			script.interp.variables.set('game',      ps);
			script.interp.variables.set('bf',        ps.boyfriend);
			script.interp.variables.set('dad',       ps.dad);
			script.interp.variables.set('gf',        ps.gf);
			script.interp.variables.set('stage',     ps.currentStage);
			script.interp.variables.set('conductor', funkin.data.Conductor);
		}
		#end
	}

	/** Refresca variables del state en TODOS los scripts. */
	static function _refreshStateVars():Void
	{
		if (_currentState == null) return;

		#if HSCRIPT_ALLOWED
		final allLayers = [
			ScriptHandler.globalScripts, ScriptHandler.stageScripts,
			ScriptHandler.songScripts,   ScriptHandler.uiScripts,
			ScriptHandler.menuScripts,   ScriptHandler.charScripts
		];
		for (layer in allLayers)
			for (s in layer) _injectStateVarsInto(s);
		for (s in StateScriptHandler.scripts)
			_injectStateVarsInto(s);
		StateScriptHandler.refreshStateFields(_currentState);
		#end
	}

	/** Notifica a todos los scripts con onReload(who). */
	static function _notifyReload(who:String):Void
	{
		ScriptHandler.callOnScripts('onReload', [who]);
		StateScriptHandler.callOnAll('onReload', [who]);
	}

	static inline function _mtime(path:String):Float
	{
		try { return FileSystem.stat(path).mtime.getTime(); }
		catch (_) { return 0.0; }
	}

	static inline function _isScript(name:String):Bool
		return name.endsWith('.hx') || name.endsWith('.hscript') || name.endsWith('.lua');

	static function _log(msg:String, color:Int = 0xFFFFFFFF):Void
	{
		#if debug
		try { funkin.debug.GameDevConsole.log(msg, color); } catch (_) {}
		#end
	}
}

// ─────────────────────────────────────────────────────────────────────────────

private typedef WatchedFolder =
{
	path  : String,
	type  : String,
	known : Map<String, Bool>
}

#end // sys && debug
