package funkin.states;

import lime.app.Promise;
import lime.app.Future;
import flixel.FlxG;
import flixel.FlxState;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.math.FlxMath;
import flixel.math.FlxRect;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import funkin.gameplay.PlayState;
import funkin.transitions.StateTransition;

import openfl.utils.Assets;
import lime.utils.Assets as LimeAssets;
import lime.utils.AssetLibrary;
import lime.utils.AssetManifest;
import haxe.io.Path;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

// Management of cache
import Paths;

class LoadingState extends funkin.states.MusicBeatState
{
	// ── Tiempo minimum in screen ────────────────────────────────────────────
	inline static var MIN_TIME:Float = 1.0;

	// ── Position of the slot of the barra dentro of menuLoadChar.png ─────────────
	// The rectangle oscuro ("pila") that there is behind of the text "Loading..."
	// Valores en porcentaje sobre las dimensiones del sprite ya escalado.
	// If the barra no encaja exactamente, ajusta here.
	inline static var BAR_X_PCT:Float  = 0.496; // borde izquierdo del slot
	inline static var BAR_Y_PCT:Float  = 0.528; // borde superior del slot
	inline static var BAR_W_PCT:Float  = 0.434; // ancho del slot
	inline static var BAR_H_PCT:Float  = 0.098; // alto del slot
	// Padding interno para que el fill no toque los bordes del hueco
	inline static var BAR_PADDING:Float = 4;

	// ── Colores de la barra (gradiente conforme avanza el progreso) ──────────
	inline static var COLOR_START:Int = 0xFFAF66CE; // morado  (0%)
	inline static var COLOR_MID:Int   = 0xFFFF78BF; // rosa    (50%)
	inline static var COLOR_END:Int   = 0xFF00FF99; // verde   (100%)

	// ─────────────────────────────────────────────────────────────────────────

	var target:FlxState;
	var stopMusic:Bool;
	var callbacks:MultiCallback;

	// Sprites
	var bgArt:FlxSprite;     // menuLoading.png  — fondo artístico
	var barBg:FlxSprite;     // fondo solid of the slot of the bar
	var barFill:FlxSprite;   // filled of progreso  (behind of charImage)
	var charImage:FlxSprite; // menuLoadChar.png — personajes + "Loading..." (ENCIMA)

	// Estado
	var loadProgress:Float   = 0.0; // 0..1 real
	var visualProgress:Float = 0.0; // 0..1 suavizado
	var totalTime:Float      = 0.0;
	var barFullWidth:Float   = 0.0; // ancho del fill en px (cacheado)

	// v2: rect reutilizable — evita new FlxRect() en cada frame del update
	var _barClipRect:flixel.math.FlxRect = new flixel.math.FlxRect();

	// ─────────────────────────────────────────────────────────────────────────

	function new(target:FlxState, stopMusic:Bool)
	{
		super();
		this.target    = target;
		this.stopMusic = stopMusic;
	}

	override function create()
	{
		// note: PathsCache.beginSession() is calldo automatically by the signal
		// preStateSwitch in FunkinCache.init(). Callrlo here of new causa that the
		// assets of the state previous queden orphaned (ni rescatables ni destruibles).

		super.create();
		FlxG.camera.bgColor = FlxColor.BLACK;

		// ── Dimensiones del juego ────────────────────────────────────────────
		final GW:Float = FlxG.width;
		final GH:Float = FlxG.height;

		// ── 1. Fondo artístico ───────────────────────────────────────────────
		bgArt = new FlxSprite();
		bgArt.loadGraphic(Paths.image('menuLoading'));
		bgArt.setGraphicSize(Std.int(GW), Std.int(GH));
		bgArt.updateHitbox();
		bgArt.scrollFactor.set();
		bgArt.antialiasing = true;
		bgArt.alpha = 0;
		add(bgArt);

		// ── 2. Calculate size/position of menuLoadChar (fit height) ─────────
		// La imagen original es 1270×952.
		// Escalamos para que la altura ocupe toda la pantalla y centramos X.
		final SRC_W:Float = 1270;
		final SRC_H:Float = 952;
		final imgScale:Float = GH / SRC_H;
		final dispW:Float    = SRC_W * imgScale;   // ≈ 960  a 720p
		final dispH:Float    = GH;                  // = 720
		final imgX:Float     = (GW - dispW) / 2;    // ≈ 160  centrado
		final imgY:Float     = 0;

		// ── 3. Coordenadas del slot de la barra en pantalla ──────────────────
		final slotX:Float = imgX + BAR_X_PCT * dispW;
		final slotY:Float = imgY + BAR_Y_PCT * dispH;
		final slotW:Float = BAR_W_PCT * dispW;
		final slotH:Float = BAR_H_PCT * dispH;

		// ── 4. Fondo of the slot (va behind of the fill and of the charImage) ───────────
		barBg = new FlxSprite(slotX, slotY);
		barBg.makeGraphic(Std.int(slotW), Std.int(slotH), 0xFF0A0A0A);
		barBg.scrollFactor.set();
		barBg.alpha = 0;
		add(barBg);

		// ── 5. Fill de progreso ───────────────────────────────────────────────
		// Empieza to the size complete and it recortamos with clipRect.
		barFullWidth = slotW - BAR_PADDING * 2;
		barFill = new FlxSprite(slotX + BAR_PADDING, slotY + BAR_PADDING);
		barFill.makeGraphic(Std.int(barFullWidth), Std.int(slotH - BAR_PADDING * 2), COLOR_START);
		barFill.scrollFactor.set();
		barFill.clipRect = new FlxRect(0, 0, 0, slotH - BAR_PADDING * 2); // empieza empty
		barFill.alpha = 0;
		add(barFill);

		// ── 6. Imagen de personajes (ENCIMA del fill, DEBAJO de nada) ────────
		charImage = new FlxSprite(imgX, imgY);
		charImage.loadGraphic(Paths.image('menuLoadChar'));
		charImage.setGraphicSize(Std.int(dispW), Std.int(dispH));
		charImage.updateHitbox();
		charImage.scrollFactor.set();
		charImage.antialiasing = true;
		charImage.alpha = 0;
		add(charImage);

		// ── 7. Fade in escalonado ─────────────────────────────────────────────
		FlxTween.tween(bgArt,    {alpha: 0.55}, 0.6, {ease: FlxEase.quadOut});
		FlxTween.tween(barBg,    {alpha: 1.0},  0.5, {ease: FlxEase.quadOut, startDelay: 0.15});
		FlxTween.tween(barFill,  {alpha: 1.0},  0.5, {ease: FlxEase.quadOut, startDelay: 0.2});
		FlxTween.tween(charImage,{alpha: 1.0},  0.5, {ease: FlxEase.quadOut, startDelay: 0.1});

		// ── 8. Arrancar carga ─────────────────────────────────────────────────
		initSongsManifest().onComplete(function(lib)
		{
			callbacks = new MultiCallback(onLoad);
			var introComplete = callbacks.add("introComplete");

			checkLoadSong(getSongPath());
			if (PlayState.SONG.needsVoices)
				checkLoadSong(getVocalPath());
			// ── no load libraries "characters" and "stages" completas ──────────
			// Codename Engine NO hace Assets.loadLibrary("characters/stages").
			// Load those libraries sube all the characters and stages to RAM of
			// golpe (~100-150 MB). Los assets de personajes/stage se cargan
			// on-demand por FunkinSprite/Stage cuando los sprites los piden.

			// Fade from negro + tiempo minimum
			var fadeTime:Float = 0.4;
			FlxG.camera.fade(FlxG.camera.bgColor, fadeTime, true);
			new FlxTimer().start(fadeTime + MIN_TIME, function(_) introComplete());
		});
	}

	// ─────────────────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		totalTime += elapsed;

		// ── Actualizar progreso real ─────────────────────────────────────────
		if (callbacks != null && callbacks.length > 0)
			loadProgress = (callbacks.length - callbacks.numRemaining) / callbacks.length;

		// ── Suavizar progreso visual (lerp fast) ───────────────────────────
		visualProgress = FlxMath.lerp(visualProgress, loadProgress, Math.min(elapsed * 9.0, 1.0));
		if (Math.abs(visualProgress - loadProgress) < 0.001)
			visualProgress = loadProgress;

		// ── Aplicar clipRect al fill (recortar desde la derecha) ─────────────
		// v2: reutilizar _barClipRect — antes era new FlxRect() cada frame
		if (barFill.clipRect != null)
		{
			var clipW:Float = barFullWidth * visualProgress;
			_barClipRect.set(0, 0, clipW, barFill.clipRect.height);
			barFill.clipRect = _barClipRect;
		}

		// ── Color dynamic of the barra ────────────────────────────────────────
		barFill.color = _barColor(visualProgress);

		// ── Small "respiro" in charImage ───────────────────────────────────
		var pulse:Float = 1.0 + Math.sin(totalTime * 2.8) * 0.004;
		charImage.scale.set(pulse, pulse);
		charImage.updateHitbox();
		// Recentrar tras escalar
		charImage.screenCenter();
		charImage.y = 0; // fit-height, top-aligned

		#if debug
		if (FlxG.keys.justPressed.SPACE)
			trace('fired: ' + callbacks.getFired() + " unfired:" + callbacks.getUnfired());
		#end
	}

	// ── Gradiente de color de la barra (morado → rosa → verde) ──────────────
	inline function _barColor(t:Float):FlxColor
	{
		if (t <= 0.5)
			return FlxColor.interpolate(COLOR_START, COLOR_MID, t * 2.0);
		else
			return FlxColor.interpolate(COLOR_MID, COLOR_END, (t - 0.5) * 2.0);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  FILESYSTEM SCANNING  (solo en plataformas #if sys)
	//
	//  Allows load assets added to the directorio of the build after of
	//  compilar: nuevas canciones, personajes, stages, etc.
	// ─────────────────────────────────────────────────────────────────────────

	#if sys

	/**
	 * Returns the directorio of filesystem that corresponde to a library.
	 * Prueba the convenciones of layout more comunes.
	 */
	// Cache of directorios of libraries — avoids multiple FileSystem.exists()
	// by the same libraryId in a session of load.
	// PERF FIX: getLibraryDir() era llamado N veces (una por cada pista de audio)
	// haciendo FileSystem.exists() repetido para el mismo directorio.
	static var _libraryDirCache:Map<String, String> = new Map();

	static function getLibraryDir(library:String):String
	{
		var cached = _libraryDirCache.get(library);
		if (cached != null) return cached;

		var candidates = [
			Paths.resolve('$library/'),
			Paths.resolve('data/$library/'),
			Paths.resolve('images/$library/'),
		];
		for (c in candidates)
			if (FileSystem.exists(c) && FileSystem.isDirectory(c))
			{
				_libraryDirCache.set(library, c);
				return c;
			}
		var fallback = Paths.resolve('$library/'); // fallback aunque no exista
		_libraryDirCache.set(library, fallback);
		return fallback;
	}

	/**
	 * Recorre `currentDir` recursivamente and adds to `out` a entry of
	 * manifiesto by each file encontrado cuyo ID no is already in `known`.
	 * `rootDir` se usa para calcular rutas relativas.
	 */
	static function scanDirForEntries(
		rootDir:String,
		currentDir:String,
		known:Map<String, Bool>,
		out:Array<Dynamic>):Void
	{
		if (!FileSystem.exists(currentDir) || !FileSystem.isDirectory(currentDir))
			return;

		for (entry in FileSystem.readDirectory(currentDir))
		{
			var fullPath = currentDir + entry;
			if (FileSystem.isDirectory(fullPath))
			{
				scanDirForEntries(rootDir, fullPath + "/", known, out);
				continue;
			}

			var relativePath = fullPath.substring(rootDir.length);
			var assetId      = Path.withoutExtension(relativePath);

			if (known.exists(assetId)) continue; // already is in the manifiesto

			var ext       = Path.extension(entry).toLowerCase();
			var assetType = switch (ext)
			{
				case "ogg" | "mp3":              cast lime.utils.AssetType.MUSIC;
				case "wav":                      cast lime.utils.AssetType.SOUND;
				case "png":                      cast lime.utils.AssetType.IMAGE;
				case "jpg" | "jpeg":             cast lime.utils.AssetType.IMAGE;
				case "json" | "xml" | "txt" |
				     "csv"  | "hx":              cast lime.utils.AssetType.TEXT;
				case "ttf"  | "otf":             cast lime.utils.AssetType.FONT;
				case _:                          cast lime.utils.AssetType.BINARY;
			};

			out.push({ id: assetId, path: relativePath, type: assetType });
		}
	}

	/**
	 * Construye una AssetLibrary leyendo todos los archivos del directorio
	 * `dir` y la registra en LimeAssets bajo `libraryId`.
	 * Returns true if succeeded.
	 */
	static function buildAndRegisterLibraryFromFs(libraryId:String, dir:String):Bool
	{
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir))
			return false;

		var entries:Array<Dynamic> = [];
		scanDirForEntries(dir, dir, new Map<String, Bool>(), entries);

		if (entries.length == 0)
			return false;

		var manifest      = new AssetManifest();
		manifest.name     = libraryId;
		manifest.rootPath = dir;
		// assets es (default, null), pero podemos mutar el array
		for (e in entries)
			manifest.assets.push(e);

		var lib = AssetLibrary.fromManifest(manifest);
		if (lib == null)
			return false;

		@:privateAccess
		LimeAssets.libraries.set(libraryId, lib);
		lib.onChange.add(LimeAssets.onChange.dispatch);

		trace('[LoadingState] Library "$libraryId" construida of the filesystem: '
		      + dir + ' (${entries.length} assets)');
		return true;
	}

	/**
	 * Dado un asset ID del sistema (ej: "songs:mySong/Inst"),
	 * intenta localizar el archivo en el filesystem probando extensiones
	 * de audio comunes. Devuelve la ruta absoluta o null si no la encuentra.
	 */
	static function resolveSoundFsPath(assetId:String):Null<String>
	{
		var libId    = "songs";
		var relative = assetId;

		if (assetId.contains(":"))
		{
			var sep  = assetId.indexOf(":");
			libId    = assetId.substring(0, sep);
			relative = assetId.substring(sep + 1);
		}

		var dir = getLibraryDir(libId);

		for (ext in ["ogg", "mp3", "wav"])
		{
			var candidate = dir + relative + "." + ext;
			if (FileSystem.exists(candidate))
				return candidate;
		}
		return null;
	}

	#end // sys

	// ─────────────────────────────────────────────────────────────────────────
	//  CARGA DE ASSETS
	// ─────────────────────────────────────────────────────────────────────────

	function checkLoadSong(path:String)
	{
		if (!Assets.cache.hasSound(path))
		{
			var callback = callbacks.add("song:" + path);

			#if sys
			// ── Fallback filesystem (hilo separado) ──────────────────────────
			// Si el audio no figura en el manifiesto compilado pero existe
			// in disco (song added post-compilation), it load in a
			// hilo de fondo para NO bloquear el hilo principal.
			// PERF FIX: Sound.fromFile() en el hilo principal bloqueaba la barra
			// de carga varios segundos en canciones de mods grandes (>10 MB).
			var fsPath = resolveSoundFsPath(path);
			if (fsPath != null)
			{
				#if (cpp || hl)
				// Usar hilo de sistema cuando el target lo soporta.
				// PERF FIX: Sound.fromFile() bloqueaba el hilo principal varios segundos
				// en canciones de mods grandes. Se ejecuta en background y el callback
				// se despacha al hilo principal via un ENTER_FRAME one-shot en el stage.
				sys.thread.Thread.create(function()
				{
					var sound:openfl.media.Sound = null;
					try { sound = openfl.media.Sound.fromFile(fsPath); }
					catch (and:Dynamic) { trace('[LoadingState] Async load failed ($fsPath): $and'); }

					// Volver al hilo principal via ENTER_FRAME one-shot.
					var stage = openfl.Lib.current.stage;
					var listener:openfl.events.Event->Void = null;
					listener = function(_)
					{
						stage.removeEventListener(openfl.events.Event.ENTER_FRAME, listener);
						if (sound != null)
						{
							Assets.cache.setSound(path, sound);
							trace('[LoadingState] Audio de mod cargado async: $fsPath → $path');
						}
						callback();
					};
					stage.addEventListener(openfl.events.Event.ENTER_FRAME, listener);
				});
				return;
				#else
				// On targets without threads, synchronous load
				try
				{
					var sound = openfl.media.Sound.fromFile(fsPath);
					if (sound != null)
					{
						Assets.cache.setSound(path, sound);
						trace('[LoadingState] Audio cargado del filesystem: $fsPath → $path');
						callback();
						return;
					}
				}
				catch (e:Dynamic)
				{
					trace('[LoadingState] Direct load failed ($fsPath): $and');
				}
				#end
			}
			#end

			Assets.loadSound(path).onComplete(function(_) { callback(); });
		}
	}

	function checkLibrary(library:String)
	{
		trace(Assets.hasLibrary(library));
		if (Assets.getLibrary(library) == null)
		{
			@:privateAccess
			var inPaths = LimeAssets.libraryPaths.exists(library);

			if (!inPaths)
			{
				#if sys
				// ── Fallback filesystem ──────────────────────────────────────
				// The library no is in the paths compilados — the construimos
				// escaneando el directorio correspondiente en disco.
				var dir = getLibraryDir(library);
				if (buildAndRegisterLibraryFromFs(library, dir))
					return; // ya registrada, no hace falta loadLibrary()
				#end
				throw "Missing library: " + library;
			}

			var callback = callbacks.add("library:" + library);
			Assets.loadLibrary(library).onComplete(function(_) { callback(); });
		}
	}

	function onLoad()
	{
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Completar barra visualmente antes de cambiar de estado
		loadProgress   = 1.0;
		visualProgress = 1.0;
		if (barFill.clipRect != null)
			barFill.clipRect = new FlxRect(0, 0, barFullWidth, barFill.clipRect.height);
		barFill.color = COLOR_END;

		new FlxTimer().start(0.15, function(_) StateTransition.switchState(target));
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  API static (no changes respecto to the original)
	// ─────────────────────────────────────────────────────────────────────────

	static function getSongPath()  return Paths.inst(PlayState.SONG.song);
	static function getVocalPath() return Paths.voices(PlayState.SONG.song);

	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false)
	{
		StateTransition.switchState(getNextState(target, stopMusic));
	}

	static function getNextState(target:FlxState, stopMusic = false):FlxState
	{
		#if NO_PRELOAD_ALL
		var loaded = isSoundLoaded(getSongPath())
			&& (!PlayState.SONG.needsVoices || isSoundLoaded(getVocalPath()))

		if (!loaded)
			return new LoadingState(target, stopMusic);
		#end
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		return target;
	}

	#if NO_PRELOAD_ALL
	static function isSoundLoaded(path:String):Bool
		return Assets.cache.hasSound(path);

	static function isLibraryLoaded(library:String):Bool
		return Assets.getLibrary(library) != null;
	#end

	override function destroy()
	{
		// Liberar assets de LoadingState que no pasen a PlayState
		Paths.clearUnusedMemory();
		// Clear cache of directorios of libraries
		_libraryDirCache.clear();
		super.destroy();
		callbacks = null;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  initSongsManifest (sin cambios)
	// ─────────────────────────────────────────────────────────────────────────

	static function initSongsManifest()
	{
		var id = "songs";
		var promise = new Promise<AssetLibrary>();

		var library = LimeAssets.getLibrary(id);
		if (library != null)
			return Future.withValue(library);

		var path = id;
		var rootPath = null;

		@:privateAccess
		var libraryPaths = LimeAssets.libraryPaths;
		if (libraryPaths.exists(id))
		{
			path = libraryPaths[id];
			rootPath = Path.directory(path);
		}
		else
		{
			if (StringTools.endsWith(path, ".bundle"))
			{
				rootPath = path;
				path += "/library.json";
			}
			else
			{
				rootPath = Path.directory(path);
			}
			@:privateAccess
			path = LimeAssets.__cacheBreak(path);
		}

		AssetManifest.loadFromFile(path, rootPath).onComplete(function(manifest)
		{
			if (manifest == null)
			{
				promise.error("Cannot parse asset manifest for library \"" + id + "\"");
				return;
			}

			#if sys
			// ── Mezclar archivos nuevos del filesystem en el manifiesto ────────
			// Any file that is in assets/songs/ but no in
			// library.json (added after of compile) is agrega here.
			// `manifest.assets` es readable externally; push() funciona sin
			// @:privateAccess porque no reemplazamos la referencia.
			var songsDir = (rootPath != null && rootPath != "")
				? (StringTools.endsWith(rootPath, "/") ? rootPath : rootPath + "/")
				: Paths.resolve("songs/");

			// Index of IDs already conocidos for avoid duplicados
			var knownIds = new Map<String, Bool>();
			for (a in manifest.assets)
			{
				var aid:String = Std.string(Reflect.field(a, "id"));
				if (aid != null) knownIds.set(aid, true);
			}

			var newEntries:Array<Dynamic> = [];
			scanDirForEntries(songsDir, songsDir, knownIds, newEntries);

			if (newEntries.length > 0)
			{
				for (e in newEntries)
					manifest.assets.push(e);
				trace('[LoadingState] ${newEntries.length} archivo(s) nuevo(s) del filesystem '
				      + 'mezclados en el manifiesto "songs".');
			}
			#end

			var library = AssetLibrary.fromManifest(manifest);
			if (library == null)
				promise.error("Cannot open library \"" + id + "\"");
			else
			{
				@:privateAccess
				LimeAssets.libraries.set(id, library);
				library.onChange.add(LimeAssets.onChange.dispatch);
				promise.completeWith(Future.withValue(library));
			}
		}).onError(function(_)
		{
			promise.error("There is no asset library with an ID of \"" + id + "\"");
		});

		return promise.future;
	}
}

// ═════════════════════════════════════════════════════════════════════════════
//  MultiCallback — sin cambios respecto al original
// ═════════════════════════════════════════════════════════════════════════════

class MultiCallback
{
	public var callback:Void->Void;
	public var logId:String = null;
	public var length(default, null) = 0;
	public var numRemaining(default, null) = 0;

	var unfired = new Map<String, Void->Void>();
	var fired   = new Array<String>();

	public function new(callback:Void->Void, logId:String = null)
	{
		this.callback = callback;
		this.logId    = logId;
	}

	public function add(id = "untitled")
	{
		id = '$length:$id';
		length++;
		numRemaining++;
		var func:Void->Void = null;
		func = function()
		{
			if (unfired.exists(id))
			{
				unfired.remove(id);
				fired.push(id);
				numRemaining--;

				if (logId != null) log('fired $id, $numRemaining remaining');

				if (numRemaining == 0)
				{
					if (logId != null) log('all callbacks fired');
					callback();
				}
			}
			else
				log('already fired $id');
		};
		unfired[id] = func;
		return func;
	}

	inline function log(msg):Void
	{
		if (logId != null) trace('$logId: $msg');
	}

	public function getFired()   return fired.copy();
	public function getUnfired() return [for (id in unfired.keys()) id];
}