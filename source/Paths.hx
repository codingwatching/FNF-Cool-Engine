package;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import openfl.display.BitmapData as Bitmap;
import openfl.media.Sound;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import animationdata.FunkinSprite;
import mods.ModManager;
import funkin.cache.PathsCache;
import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * Paths — system centralizado of resolution of rutas with cache avanzado.
 *
 * ─── Arquitectura of the cache ───────────────────────────────────────────────────
 *
 *  ANTES (Paths viejo):
 *    bitmapCache:Map<String, BitmapData>   — cacheaba el bitmap en RAM
 *    atlasCache: Map<String, FlxAtlasFrames> — cacheaba los frames
 *    The texture was always in RAM even after being uploaded to the GPU!
 *
 *  AHORA (Paths + PathsCache):
 *    PathsCache.currentTrackedGraphics    — FlxGraphic con GPU caching opcional
 *    PathsCache.currentTrackedSounds      — Sound cacheados
 *    atlasCache: Map<String, FlxAtlasFrames> — only the frames (ligeros)
 *
 *  El FlxGraphic que construye PathsCache integra con FlxG.bitmap nativo de
 *  Flixel (FlxSprite.loadGraphic() it encuentra automatically). When
 *  gpuCaching=true the BitmapData in RAM is libera after of the upload → ahorra
 *  ~4 MB por textura 1024×1024.
 *
 * ─── Ciclo of vida of the cache ──────────────────────────────────────────────────
 *
 *   // Al inicio de un estado que carga assets pesados (p.ej. PlayState):
 *   Paths.beginSession();
 *
 *   // Durante the load — is call automatically by getGraphic / getSound
 *
 *   // Al destruir el estado:
 *   Paths.clearStoredMemory();   // sounds outside of uso + marcar graphics
 *   Paths.clearUnusedMemory();   // destroy graphics marcados + GC
 *
 * @author Cool Engine Team
 * @version 0.6.0
 */
class Paths
{
	public static inline var SOUND_EXT = #if web "mp3" #else "ogg" #end;

	// ── Acceso to the cache main ─────────────────────────────────────────────

	/** Instancia global de PathsCache. Nunca null. */
	public static var cache(get, never):PathsCache;

	static inline function get_cache():PathsCache
		return PathsCache.instance;

	// ── Cache of atlas (only frames, the bitmaps are in PathsCache) ─────────
	//
	// FlxAtlasFrames is lightweight: only contains a array of FlxRect + referencia
	// to the FlxGraphic. No tiene datos of pixels propios.
	// The bitmap actual vive in PathsCache (GPU or RAM according to gpuCaching).
	// LRU eliminado: FNF nunca necesita evictar atlases durante gameplay.
	// Los frames se liberan con clearPreviousSession(), no por eviction.
	static var atlasCache:Map<String, FlxAtlasFrames> = [];
	static var atlasCount:Int = 0;

	/**
	 * Limit of atlases in cache.
	 * 50 cubre todo lo necesario para gameplay: 3 personajes + stage + notas + UI.
	 * El valor anterior (200) acumulaba atlas de assets ya sin usar entre canciones
	 * keeping its BitmapData in RAM — direct contribution to the ~1 GB observed.
	 * With LRU (eviction to the superar the limit) is seguro bajar this value.
	 */
	public static var maxAtlasCache:Int = 50;

	/** If false, all accesses go to disk (useful for debugging). */
	public static var cacheEnabled:Bool = true;

	// ── Stage actual ──────────────────────────────────────────────────────────

	/** Actualizado por PlayState al cambiar de stage. */
	public static var currentStage:String = 'stage_week1';

	// ── Opciones de GPU ───────────────────────────────────────────────────────

	/**
	 * Alias de PathsCache.gpuCaching para compatibilidad con opciones guardadas.
	 * Change here also changes the comportamiento of PathsCache.
	 */
	public static var gpuCaching(get, set):Bool;

	static inline function get_gpuCaching():Bool
		return PathsCache.gpuCaching;

	static inline function set_gpuCaching(v:Bool):Bool
	{
		PathsCache.gpuCaching = v;
		return v;
	}

	// ── Management of session (delegados to PathsCache) ────────────────────────────

	/**
	 * Starts a new session of cache.
	 * Resetea localTrackedAssets sin borrar nada.
	 * Llamar al inicio de create() en cada estado pesado.
	 */
	public static inline function beginSession():Void
		cache.beginSession();

	/**
	 * Destroys the assets of the previous session that no fueron rescatados.
	 * Callr to the FINAL of create() of a state heavy, after of load
	 * todos los assets — esto da tiempo a que los assets compartidos sean
	 * rescatados de _previousGraphics a _currentGraphics durante la carga.
	 */
	public static inline function clearPreviousSession():Void
	{
		cache.clearPreviousSession();
		_pruneInvalidAtlases();
	}

	/**
	 * Adds a key to the exclusiones permanentes (never is evicta).
	 * Ejemplo: Paths.addExclusion(Paths.music('freakyMenu'));
	 */
	public static inline function addExclusion(key:String):Void
		cache.addExclusion(key);

	/**
	 * Libera assets of sound + graphics no marcados (outside of localTrackedAssets).
	 * Llamar al salir de un estado pesado ANTES de clearUnusedMemory().
	 */
	public static inline function clearStoredMemory():Void
	{
		cache.clearStoredMemory();
		// Clear also atlases cuya graphic already no is in PathsCache
		_pruneInvalidAtlases();
	}

	/**
	 * Destroys the graphics marcados by clearStoredMemory() + forces GC.
	 * Callr after of clearStoredMemory().
	 */
	public static inline function clearUnusedMemory():Void
		cache.clearUnusedMemory();

	// ── Core: resolve ─────────────────────────────────────────────────────────

	/**
	 * Resuelve a file to the path physical correct.
	 * Orden: mods/{activeMod}/{file} → assets/{file}
	 */
	public static function resolve(file:String, ?type:AssetType):String
	{
		final modPath = ModManager.resolveInMod(file);
		if (modPath != null)
			return modPath;
		return 'assets/$file';
	}

	/**
	 * Resolve a path for WRITING (saving files).
	 * Unlike resolve(), this does NOT check if the file exists —
	 * it always returns the mod path if a mod is active.
	 * Use this whenever you need to save/create a file.
	 *
	 * Examples:
	 *   resolveWrite('characters/bf.json') → 'mods/myMod/characters/bf.json'  (mod active)
	 *   resolveWrite('characters/bf.json') → 'assets/characters/bf.json'      (no mod)
	 */
	public static function resolveWrite(file:String):String
	{
		#if sys
		if (ModManager.isActive())
			return '${ModManager.modRoot()}/$file';
		#end
		return 'assets/$file';
	}

	/**
	 * Ensure the directory for a file path exists, then return the path.
	 * Convenience wrapper for write operations.
	 */
	public static function ensureDir(filePath:String):String
	{
		#if sys
		final dir = haxe.io.Path.directory(filePath);
		if (dir != '' && !sys.FileSystem.exists(dir))
			sys.FileSystem.createDirectory(dir);
		#end
		return filePath;
	}

	public static function resolveAny(candidates:Array<String>):String
	{
		for (c in candidates)
		{
			if (c == null || c == '')
				continue;
			#if sys
			if (FileSystem.exists(c))
				return c;
			#else
			if (OpenFlAssets.exists(c))
				return c;
			#end
		}
		return candidates.filter(s -> s != null && s != '')[0] ?? '';
	}

	/** Does the file exist (in mod or in assets)? */
	public static function exists(file:String, ?type:AssetType):Bool
	{
		final path = resolve(file, type);
		#if sys
		return FileSystem.exists(path);
		#else
		return OpenFlAssets.exists(path, type);
		#end
	}

	/** Lee texto desde file (en mod o en assets). */
	public static function getText(file:String):String
	{
		final path = resolve(file, TEXT);
		#if sys
		if (FileSystem.exists(path))
			return File.getContent(path);
		#end
		return OpenFlAssets.getText(path);
	}

	// ── Paths tipados ─────────────────────────────────────────────────────────

	public static inline function file(file:String, type:AssetType = TEXT):String
		return resolve(file, type);

	public static inline function txt(key:String):String
		return resolve('data/$key.txt', TEXT);

	public static inline function xml(key:String):String
		return resolve('data/$key.xml', TEXT);

	public static inline function json(key:String):String
		return resolve('data/$key.json', TEXT);

	public static function jsonSong(key:String):String
		return resolveAny([ModManager.resolveInMod('songs/$key.json') ?? '', 'assets/songs/$key.json']);

	public static function songsTxt(key:String):String
		return resolve('songs/$key.txt', TEXT);

	public static function characterJSON(key:String):String
		return resolveAny([
			ModManager.resolveInMod('characters/$key.json') ?? '',
			'assets/characters/$key.json'
		]);

	public static function stageJSON(key:String):String
		return resolveAny([ModManager.resolveInMod('stages/$key.json') ?? '', 'stages/$key.json']);

	public static function image(key:String):String
	{
		final path = resolve('images/$key.png', IMAGE);
		#if sys
		// Si el archivo existe en disco pero NO en el manifest de OpenFL
		// (ocurre con mods no recompilados), lo registramos en el cache de
		// OpenFL para que loadGraphic() / getSparrowAtlas() lo encuentren.
		if (FileSystem.exists(path) && !OpenFlAssets.exists(path, IMAGE))
		{
			try
			{
				final bmp = _loadBitmapFromDisk(path);
				if (bmp != null)
					openfl.utils.Assets.cache.setBitmapData(path, bmp);
			}
			catch (e:Dynamic) { trace('[Paths] image() cache register failed for "$path": $e'); }
		}
		#end
		return path;
	}

	public static inline function imageCutscene(key:String):String
		return resolve('$key.png', IMAGE);

	public static inline function characterimage(key:String):String
		return resolve('characters/images/$key.png', IMAGE);

	public static function characterFolder(key:String):String
		return resolve('characters/images/$key/');

	public static function sound(key:String):String
	{
		final path = resolve('sounds/$key.$SOUND_EXT', SOUND);
		#if sys
		if (FileSystem.exists(path))
		{
			// Register in the cache of OpenFL if no is already (mods without recompiling)
			if (!OpenFlAssets.exists(path, SOUND) && !OpenFlAssets.exists(path, MUSIC))
			{
				try
				{
					final snd = openfl.media.Sound.fromFile(path);
					if (snd != null) openfl.utils.Assets.cache.setSound(path, snd);
				}
				catch (e:Dynamic) {}
			}
			return path;
		}
		// Fallback: buscar directamente en assets/ para builds sin recompilar
		final direct = 'assets/sounds/$key.$SOUND_EXT';
		if (FileSystem.exists(direct))
			return direct;
		#end
		return path;
	}

	public static function soundStage(key:String):String
	{
		final path = resolveWrite('stages/$key.$SOUND_EXT');
		#if sys
		// Return the path if exists in disco although no is in the manifest of OpenFL
		if (FileSystem.exists(path))
			return path;
		#end
		return path;
	}

	public static inline function soundRandom(key:String, min:Int, max:Int):String
		return sound(key + FlxG.random.int(min, max));

	public static inline function soundRandomStage(key:String, min:Int, max:Int):String
		return soundStage('${funkin.gameplay.PlayState.curStage}/sounds/' + key + FlxG.random.int(min, max));

	public static function music(key:String):String
	{
		final path = resolve('music/$key.$SOUND_EXT', MUSIC);
		#if sys
		if (FileSystem.exists(path))
		{
			// Register in the cache of OpenFL if no is already (mods without recompiling)
			if (!OpenFlAssets.exists(path, SOUND) && !OpenFlAssets.exists(path, MUSIC))
			{
				try
				{
					final snd = openfl.media.Sound.fromFile(path);
					if (snd != null) openfl.utils.Assets.cache.setSound(path, snd);
				}
				catch (e:Dynamic) {}
			}
			return path;
		}
		// Fallback: assets/ base
		final direct = 'assets/music/$key.$SOUND_EXT';
		if (FileSystem.exists(direct))
			return direct;
		#end
		return path;
	}

	public static inline function font(key:String):String
		return resolve('fonts/$key');

	public static function video(key:String):String
	{
		final k = key.endsWith('.mp4') ? key.substr(0, key.length - 4) : key;
		return resolveAny([
			ModManager.resolveInMod('videos/$k.mp4') ?? '',
			ModManager.resolveInMod('cutscenes/videos/$k.mp4') ?? '',
			'assets/videos/$k.mp4',
			'assets/cutscenes/videos/$k.mp4'
		]);
	}

	public static function stageScripts(stageName:String):String
		return resolveAny([
			ModManager.resolveInMod('stages/$stageName/scripts') ?? '',
			'assets/stages/$stageName/scripts'
		]);

	// ── Load of graphics ─────────────────────────────────────────────────────

	/**
	 * Carga un BitmapData desde disco o assets embebidos.
	 * Internamente pasa por PathsCache → si gpuCaching=true, la imagen en RAM
	 * is libera after of the upload and is returns FlxGraphic.bitmap (that puede
	 * be in modo "GPU only"; the pixels no are accesibles from CPU).
	 *
	 * For effects that necesiten leer pixels from CPU (tintado dynamic, etc.)
	 * usar getGraphic() con allowGPU=false.
	 *
	 * @deprecated Prefer getGraphic() for full Flixel integration.
	 */
	public static function getBitmap(key:String, allowGPU:Bool = true):Null<Bitmap>
	{
		final g = getGraphic(key, allowGPU);
		return g?.bitmap;
	}

	/**
	 * Carga y cachea un FlxGraphic para la clave dada.
	 *
	 * • Busca primero en PathsCache (cache hit → O(1), sin I/O).
	 * • En miss: carga desde disco via Lime → crea FlxGraphic → sube a GPU si
	 *   gpuCaching=true → libera imagen en RAM → cachea en PathsCache.
	 * • El FlxGraphic resultante tiene persist=true + destroyOnNoUse=false.
	 *
	 * @param key       Key logic of the asset (without prefix "images/", without ".png").
	 * @param allowGPU  Si false, deshabilita GPU caching para este asset.
	 */
	public static function getGraphic(key:String, allowGPU:Bool = true):Null<FlxGraphic>
	{
		// Resolve path physical
		final path = image(key);
		// Key of PathsCache = path physical (unique and estable between calldas)
		final cacheKey = path;

		// Cache hit en PathsCache
		if (cacheEnabled && cache.hasValidGraphic(cacheKey))
			return cache.peekGraphic(cacheKey);

		// Cache miss → cargar desde disco
		final bmp = _loadBitmapFromDisk(path);
		if (bmp == null)
		{
			trace('[Paths] getGraphic: not found "$key" (path="$path")');
			return null;
		}

		return cacheEnabled ? cache.getGraphic(cacheKey, bmp, allowGPU) : FlxGraphic.fromBitmapData(bmp, false, cacheKey, false);
	}

	// ── Imagen del stage (path especial) ──────────────────────────────────────

	/**
	 * Carga la imagen de un asset de stage.
	 * @param fromStage  Si se especifica, busca en la carpeta de OTRO stage en
	 *                   lugar de currentStage.  Permite compartir assets entre stages.
	 */
	public static function imageStage(key:String, ?fromStage:String):Null<Bitmap>
	{
		final path = _resolveStageImagePath(key, fromStage);
		if (path == null)
			return null;

		// Intentar desde PathsCache primero
		if (cacheEnabled && cache.hasValidGraphic(path))
			return cache.peekGraphic(path)?.bitmap;

		final bmp = _loadBitmapFromDisk(path);
		if (bmp == null)
			return null;

		// BUGFIX: purgar entry muerta of FlxG.bitmap before of create the graphic new.
		@:privateAccess
		{
			final deadEntry = FlxG.bitmap.get(path);
			if (deadEntry != null && deadEntry.bitmap == null)
			{
				FlxG.bitmap.removeKey(path);
				trace('[Paths] imageStage: purgada entrada muerta de FlxG.bitmap para "$path"');
			}
		}

		if (cacheEnabled)
			cache.getGraphic(path, bmp);
		return bmp;
	}

	// ── Carga de sonidos ─────────────────────────────────────────────────────

	/**
	 * Carga un sonido desde disco y lo cachea en PathsCache.
	 * Reutiliza la instancia Sound si ya estaba cacheada (sin I/O).
	 *
	 * @param path    Path physical of the sound (result of Paths.sound(), .music(), etc.)
	 * @param safety  Si true y no se encuentra, devuelve un beep de fallback.
	 */
	public static function getSound(path:String, safety:Bool = false):Null<Sound>
	{
		// Cache hit
		if (cacheEnabled && cache.hasSound(path))
			return cache.getSound(path, null, safety);

		// Cache miss → cargar
		var snd:Sound = null;
		try
		{
			#if sys
			if (FileSystem.exists(path))
			{
				snd = Sound.fromFile(path);
			}
			else
			#end
			if (OpenFlAssets.exists(path, SOUND))
				snd = OpenFlAssets.getSound(path);
			else if (OpenFlAssets.exists(path, MUSIC))
				snd = OpenFlAssets.getSound(path);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] getSound "$path": $e');
		}

		return cacheEnabled ? cache.getSound(path, snd, safety) : snd;
	}

	/**
	 * Load music of forma segura from the filesystem or assets embebidos.
	 * Use it instead of FlxG.sound.playMusic(Paths.music(...)) when the path
	 * puede venir of a folder of mods (no is in the manifest of OpenFL).
	 */
	public static function loadMusic(key:String):Null<Sound>
	{
		final path = music(key);
		return getSound(path);
	}

	// ── Load of audio of song (streaming) ─────────────────────────────────

	/** Load the Inst of a song usando streaming. */
	public static function loadInst(song:String, ?diffSuffix:String):flixel.sound.FlxSound
		return _loadStreamingSound(inst(song, diffSuffix));

	/** Load the Voices of a song usando streaming. */
	public static function loadVoices(song:String, ?diffSuffix:String):flixel.sound.FlxSound
		return _loadStreamingSound(voices(song, diffSuffix));

	/**
	 * Carga un FlxSound en modo streaming.
	 * Las canciones NUNCA se meten en PathsCache (son demasiado grandes y
	 * se usan una sola vez). Se cargan directamente como stream desde disco.
	 *
	 * WHY STREAMING:
	 *   loadEmbedded() decodifica el OGG completo a PCM en RAM al cargar.
	 *   3 min × 44.1 kHz × 16-bit × 2 canales = ~32 MB por pista.
	 *   Inst + Voices = 64–120 MB. With streaming → only a buffer of segundos.
	 */
	/**
	 * Carga un FlxSound en modo streaming.
	 *
	 * IMPORTANTE: loadStream() registra un SampleDataEvent listener en el
	 * openfl.media.Sound subyacente, lo que DEBE ocurrir en el main thread.
	 * Si se llama desde un thread secundario OpenFL lanza:
	 *   "SampleDataEvent listener has to provide between 2048 and 8192 samples"
	 * By that this function always is synchronous in the main thread.
	 * El threading de la precarga lo gestiona el llamador (FreeplayState).
	 */
	static function _loadStreamingSound(path:String):flixel.sound.FlxSound
	{
		final snd = new flixel.sound.FlxSound();
		try
		{
			#if sys
			if (FileSystem.exists(path))
			{
				snd.loadStream(path);
				FlxG.sound.list.add(snd);
				return snd;
			}

			// Asset embebido → volcar a tmp para hacer stream
			final bytes = lime.utils.Assets.getBytes(path);
			if (bytes != null)
			{
				final tmpDir = Sys.getEnv('TEMP') ?? Sys.getEnv('TMPDIR') ?? '/tmp';
				final tmpFile = '$tmpDir/funkin_stream_${path.split('/').pop() ?? "audio"}';
				if (!FileSystem.exists(tmpFile))
					File.saveBytes(tmpFile, bytes);
				snd.loadStream(tmpFile);
				FlxG.sound.list.add(snd);
				return snd;
			}
			#end
			snd.loadEmbedded(path, false, false);
			FlxG.sound.list.add(snd);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _loadStreamingSound "$path": $e');
		}
		return snd;
	}

	// ── Song paths ────────────────────────────────────────────────────────────

	public static function inst(song:String, ?diffSuffix:String):String
	{
		final folder = _resolveSongFolder(song);
		#if sys
		// Primero intentar con sufijo de dificultad (ej: "Inst-nightmare.ogg")
		if (diffSuffix != null && diffSuffix != '')
		{
			// The suffix comes as "-nightmare", we remove the leading dash
			final diffName = diffSuffix.startsWith('-') ? diffSuffix.substr(1) : diffSuffix;
			for (subdir in ['song/', ''])
			{
				final p = '$folder/${subdir}Inst-$diffName.$SOUND_EXT';
				if (FileSystem.exists(p))
					return p;
			}
		}
		final withSub = '$folder/song/Inst.$SOUND_EXT';
		if (FileSystem.exists(withSub))
			return withSub;
		final flat = '$folder/Inst.$SOUND_EXT';
		if (FileSystem.exists(flat))
			return flat;
		#end
		return '$folder/song/Inst.$SOUND_EXT';
	}

	public static function voices(song:String, ?diffSuffix:String):String
	{
		final folder = _resolveSongFolder(song);
		#if sys
		// Primero intentar con sufijo de dificultad (ej: "Voices-nightmare.ogg")
		if (diffSuffix != null && diffSuffix != '')
		{
			final diffName = diffSuffix.startsWith('-') ? diffSuffix.substr(1) : diffSuffix;
			for (subdir in ['song/', ''])
			{
				final p = '$folder/${subdir}Voices-$diffName.$SOUND_EXT';
				if (FileSystem.exists(p))
					return p;
			}
		}
		final withSub = '$folder/song/Voices.$SOUND_EXT';
		if (FileSystem.exists(withSub))
			return withSub;
		final flat = '$folder/Voices.$SOUND_EXT';
		if (FileSystem.exists(flat))
			return flat;
		#end
		return '$folder/song/Voices.$SOUND_EXT';
	}

	/**
	 * Resuelve the ruta of vocals for a character specific.
	 * Prioridad: Voices-charName-diff → Voices-charName → Voices-diff → Voices
	 * Returns null if no exists no file of vocals for that character.
	 */
	public static function voicesForChar(song:String, charName:String, ?diffSuffix:String):Null<String>
	{
		if (charName == null || charName == '')
			return null;
		final folder = _resolveSongFolder(song);
		#if sys
		final diffName = (diffSuffix != null && diffSuffix != '') ? (diffSuffix.startsWith('-') ? diffSuffix.substr(1) : diffSuffix) : null;

		// 1. Voices-charName-diff.ogg
		if (diffName != null)
		{
			for (subdir in ['song/', ''])
			{
				final p = '$folder/${subdir}Voices-$charName-$diffName.$SOUND_EXT';
				if (FileSystem.exists(p))
					return p;
			}
		}
		// 2. Voices-charName.ogg
		for (subdir in ['song/', ''])
		{
			final p = '$folder/${subdir}Voices-$charName.$SOUND_EXT';
			if (FileSystem.exists(p))
				return p;
		}
		#end
		return null; // no exists file specific for this character
	}

	/** Load character-specific vocals as FlxSound in streaming. */
	public static function loadVoicesForChar(song:String, charName:String, ?diffSuffix:String):Null<flixel.sound.FlxSound>
	{
		final path = voicesForChar(song, charName, diffSuffix);
		if (path == null)
			return null;
		return _loadStreamingSound(path);
	}

	/** true if character-specific vocals exist (with or without diff). */
	public static function hasVoicesForChar(song:String, charName:String, ?diffSuffix:String):Bool
		return voicesForChar(song, charName, diffSuffix) != null;

	// ── FunkinSprite helpers ─────────────────────────────────────────────────

	public static function animateAtlas(key:String):String
		return resolve(key);

	public static function characterAnimateAtlas(key:String):String
		return resolve('characters/images/$key');

	public static function hasAnimateAtlas(key:String):Bool
		return FunkinSprite.folderHasAnimateAtlas(resolve(key));

	public static function characterHasAnimateAtlas(key:String):Bool
		return FunkinSprite.folderHasAnimateAtlas(resolve('characters/images/$key'));

	public static inline function getFunkinSprite(x:Float, y:Float, key:String):FunkinSprite
		return FunkinSprite.create(x, y, key);

	public static inline function getCharacterSprite(x:Float, y:Float, key:String):FunkinSprite
		return FunkinSprite.createCharacter(x, y, key);

	// ── Atlas Sparrow with cache ───────────────────────────────────────────────

	/**
	 * Carga un atlas Sparrow (PNG + XML).
	 *
	 * El FlxGraphic del PNG pasa por PathsCache (GPU caching).
	 * The FlxAtlasFrames is cachea separadamente (is only metadata of frames).
	 */
	public static function getSparrowAtlas(key:String):FlxAtlasFrames
		return _cachedAtlas(key, () -> _sparrow(image(key), resolve('images/$key.xml')));

	public static function characterSprite(key:String):FlxAtlasFrames
		return _cachedAtlas('char_$key', () -> _loadCharacterSpriteAtlas(key));

	/**
	 * Load the atlas of a character soportando multiple hojas of sprites.
	 *
	 * Si existe `characters/images/charName.sheets` (JSON array de strings),
	 * cada entrada puede ser:
	 *
	 *   • Una KEY Sparrow (PNG+XML):
	 *       ["tankman_basic", "tankman_bloody"]
	 *
	 *   • Una CARPETA de Adobe Animate (con Animation.json):
	 *       ["tankman/basic", "tankman/bloody", "tankman/extra-animations"]
	 *
	 *   • O subcarpetas directas del personaje:
	 *       ["basic", "bloody", "extra-animations"]
	 *       → se resuelven como characters/images/charName/basic, etc.
	 *
	 * The entradas Animate is fusionan via FunkinSprite.loadMultiAnimateAtlas()
	 * (que escribe un directorio temporal con el atlas unificado).
	 * Las entradas Sparrow se fusionan con FlxAtlasFramesExt.mergeAtlases().
	 *
	 * Si el .sheets mezcla tipos, las entradas Animate tienen prioridad y las
	 * Sparrow se ignoran (imprime un warning).
	 *
	 * Without .sheets: hoja single standard (Sparrow or Animate).
	 */
	static function _loadCharacterSpriteAtlas(key:String):FlxAtlasFrames
	{
		// 1. Buscar archivo .sheets para multi-sheet
		final sheetsPath = _resolveCharacterSheets(key);
		#if sys
		if (sheetsPath != null && sys.FileSystem.exists(sheetsPath))
		{
			try
			{
				final sheetKeys:Array<String> = haxe.Json.parse(sys.io.File.getContent(sheetsPath));
				if (sheetKeys != null && sheetKeys.length > 0)
				{
					// ── Detectar si las entradas son carpetas Animate ────────
					final animateFolders:Array<String> = [];
					final sparrowKeys:Array<String> = [];

					for (sheetKey in sheetKeys)
					{
						if (sheetKey == null || sheetKey.trim() == '')
							continue;
						final folder = _resolveCharacterAnimateFolder(key, sheetKey);
						if (folder != null)
							animateFolders.push(folder);
						else
							sparrowKeys.push(sheetKey);
					}

					// ── Rama Animate ─────────────────────────────────────────
					if (animateFolders.length > 0)
					{
						if (sparrowKeys.length > 0)
							trace('[Paths] characterSprite "$key": .sheets mixes Animate and Sparrow — only Animate folders are used.');

						// The actual merge happens in FunkinSprite.loadMultiAnimateAtlas.
						// Paths no puede devolver un FlxAtlasFrames para Animate —
						// devolvemos null para que el caller (loadCharacterSparrow)
						// uses the Animate path directly.
						//
						// NOTA: este caso ya es interceptado en FunkinSprite.loadCharacterSparrow()
						// via resolveMultiAnimateFolders(). If we get here it's because someone
						// llama Paths.characterSprite() directamente (raro). En ese caso no podemos
						// do nothing useful, so we log and return null.
						trace('[Paths] characterSprite "$key": multi-Animate detectado — usar FunkinSprite.loadCharacterSparrow() en su lugar.');
						return null;
					}

					// ── Rama Sparrow ──────────────────────────────────────────
					if (sparrowKeys.length > 0)
					{
						final atlases:Array<FlxAtlasFrames> = [];
						for (sheetKey in sparrowKeys)
						{
							final png = _resolveCharacterPng(sheetKey);
							final xml = _resolveCharacterXml(sheetKey);
							final atlas = _sparrow(png, xml);
							if (atlas != null)
								atlases.push(atlas);
						}
						if (atlases.length > 0)
						{
							final merged = extensions.FlxAtlasFramesExt.mergeAtlases(atlases);
							if (merged != null)
							{
								trace('[Paths] characterSprite "$key": multi-sheet Sparrow (${atlases.length} hojas fusionadas)');
								return merged;
							}
						}
					}
				}
			}
			catch (e:Dynamic)
			{
				trace('[Paths] characterSprite "$key": error leyendo .sheets — $e');
			}
		}
		#end
		// 2. Fallback: hoja single standard
		return _sparrow(_resolveCharacterPng(key), _resolveCharacterXml(key));
	}

	/**
	 * Dado un key de .sheets, intenta resolverlo como carpeta Adobe Animate.
	 * Busca en: subcarpeta del char, characters/images/, images/characters/, assets/.
	 * Devuelve el path si tiene Animation.json, null si no es Animate.
	 */
	static function _resolveCharacterAnimateFolder(charKey:String, sheetKey:String):Null<String>
	{
		#if sys
		final isSubKey = !sheetKey.contains('/');
		final candidates:Array<String> = [];

		// Como subcarpeta directa del personaje
		if (isSubKey)
		{
			if (ModManager.activeMod != null)
			{
				final base = '${ModManager.MODS_FOLDER}/${ModManager.activeMod}';
				candidates.push('$base/characters/images/$charKey/$sheetKey');
				candidates.push('$base/images/characters/$charKey/$sheetKey');
			}
			candidates.push('assets/characters/images/$charKey/$sheetKey');
		}

		// Como ruta relativa a characters/images/
		if (ModManager.activeMod != null)
		{
			final base = '${ModManager.MODS_FOLDER}/${ModManager.activeMod}';
			candidates.push('$base/characters/images/$sheetKey');
			candidates.push('$base/images/characters/$sheetKey');
		}
		candidates.push('assets/characters/images/$sheetKey');

		for (p in candidates)
			if (p != null && animationdata.FunkinSprite.folderHasAnimateAtlas(p))
				return p;
		#end
		return null;
	}

	static function _resolveCharacterSheets(key:String):Null<String>
	{
		#if sys
		return resolveAny([
			ModManager.resolveInMod('characters/images/$key.sheets') ?? '',
			ModManager.resolveInMod('images/characters/$key.sheets') ?? '',
			'assets/characters/images/$key.sheets'
		]);
		#else
		return null;
		#end
	}

	/**
	 * Carga un atlas Sparrow de un stage.
	 * @param fromStage  Si se especifica, busca los assets en ese stage en lugar
	 *                   de currentStage — permite reutilizar assets entre stages.
	 */
	public static function stageSprite(key:String, ?fromStage:String):FlxAtlasFrames
	{
		final lib = fromStage ?? currentStage;
		return _cachedAtlas('stage_${lib}_$key', () ->
		{
			final pngPath = resolveAny([
				ModManager.resolveInMod('stages/$lib/images/$key.png') ?? '',
				ModManager.resolveInMod('images/stages/$key.png') ?? '',
				ModManager.resolveInMod('images/$key.png') ?? '',
				'assets/stages/$lib/images/$key.png'
			]);
			final xmlPath = resolveAny([
				ModManager.resolveInMod('stages/$lib/images/$key.xml') ?? '',
				ModManager.resolveInMod('images/stages/$key.xml') ?? '',
				ModManager.resolveInMod('images/$key.xml') ?? '',
				'assets/stages/$lib/images/$key.xml'
			]);
			final stageBmp = _resolveStageImagePath(key, lib);
			if (stageBmp == null)
				return null;
			return _sparrowFromPath(stageBmp, xmlPath);
		});
	}

	public static function skinSprite(key:String):FlxAtlasFrames
		return _cachedAtlas('skin_$key', () -> _sparrow(resolve('notes/skins/$key.png', IMAGE), resolve('notes/skins/$key.xml', TEXT)));

	public static function splashSprite(key:String):FlxAtlasFrames
		return _cachedAtlas('splash_$key', () -> _sparrow(resolve('notes/splashes/$key.png', IMAGE), resolve('notes/splashes/$key.xml', TEXT)));

	public static function getSparrowAtlasCutscene(key:String):FlxAtlasFrames
		return _cachedAtlas('cutscene_$key', () -> FlxAtlasFrames.fromSparrow('$key.png', '$key.xml'));

	// ── Atlas Packer with cache ────────────────────────────────────────────────

	public static function getPackerAtlas(key:String):FlxAtlasFrames
		return _cachedAtlas('packer_$key', () -> _packer(image(key), resolve('images/$key.txt')));

	public static function characterSpriteTxt(key:String):FlxAtlasFrames
		return _cachedAtlas('char_txt_$key', () -> _packer(_resolveCharacterPng(key), _resolveCharacterTxt(key)));

	/** Packer (TXT) atlas from a stage. Accepts optional @fromStage override. */
	public static function stageSpriteTxt(key:String, ?fromStage:String):FlxAtlasFrames
	{
		final lib = fromStage ?? currentStage;
		return _cachedAtlas('stage_txt_${lib}_$key', () ->
		{
			final pngPath = resolveAny([
				ModManager.resolveInMod('stages/$lib/images/$key.png') ?? '',
				ModManager.resolveInMod('images/stages/$key.png') ?? '',
				'assets/stages/$lib/images/$key.png'
			]);
			final txtPath = resolveAny([
				ModManager.resolveInMod('stages/$lib/images/$key.txt') ?? '',
				ModManager.resolveInMod('images/stages/$key.txt') ?? '',
				'assets/stages/$lib/images/$key.txt'
			]);
			return _packer(pngPath, txtPath);
		});
	}

	public static function skinSpriteTxt(key:String):FlxAtlasFrames
		return _cachedAtlas('skin_txt_$key', () -> _packer(resolve('notes/skins/$key.png', IMAGE), resolve('notes/skins/$key.txt', TEXT)));

	// ── Management of the cache of atlas ────────────────────────────────────────────

	/**
	 * Clears the cache of atlas + delega to PathsCache.
	 * Los FlxGraphics del PNG se liberan via PathsCache.
	 */
	public static function clearCache():Void
	{
		for (atlas in atlasCache)
		{
			if (atlas?.parent != null)
			{
				atlas.parent.destroyOnNoUse = true;
				if (atlas.parent.useCount <= 0)
					atlas.parent.destroy();
			}
		}
		atlasCache.clear();
		atlasCount = 0;
		trace('[Paths] Atlas cache limpiado.');
	}

	/**
	 * Limpia entradas del atlasCache cuyo FlxGraphic ya fue dispuesto.
	 * Callr after of GC/compact for that atlas invalidados sean detectados.
	 * So the next acceso forces a recarga clears from disco.
	 */
	public static inline function pruneAtlasCache():Void
	{
		_pruneInvalidAtlases();
	}

	public static function clearFlxBitmapCache():Void
	{
		FlxG.bitmap.clearCache();
		try
		{
			openfl.utils.Assets.cache.clear();
		}
		catch (_:Dynamic)
		{
		}
		#if cpp cpp.vm.Gc.run(true); #end
		#if hl hl.Gc.major(); #end
		trace('[Paths] FlxG.bitmap + OpenFL cache limpiados.');
	}

	/**
	 * Limpia TODO: atlas + PathsCache.forceFullClear() + Flixel.
	 * Only for cambio of mod or reinicio.
	 */
	public static function clearAllCaches():Void
	{
		clearCache();
		cache.forceFullClear();
		clearFlxBitmapCache();
	}

	/**
	 * @deprecated Alias de clearAllCaches() para compatibilidad.
	 */
	public static inline function forceClearCache():Void
		clearAllCaches();

	/** Clears only assets of gameplay without tocar UI/menus. */
	public static function clearGameplayCache():Void
	{
		// Limpiar atlases con prefijos de gameplay
		final prefixes = ["char_", "stage_", "skin_"];
		final toRemove:Array<String> = [];
		for (key in atlasCache.keys())
			for (p in prefixes)
				if (key.startsWith(p))
				{
					toRemove.push(key);
					break;
				}

		for (key in toRemove)
		{
			final atlas = atlasCache.get(key);
			atlasCache.remove(key);
			atlasCount--;
			if (atlas?.parent != null)
			{
				atlas.parent.destroyOnNoUse = true;
				if (atlas.parent.useCount <= 0)
					atlas.parent.destroy();
			}
		}

		// Delegar the graphics to PathsCache
		cache.clearGameplayAssets();

		if (toRemove.length > 0)
			trace('[Paths] clearGameplayCache: ${toRemove.length} atlas(es) + gameplay graphics freed.');
	}

	public static function setCacheEnabled(enabled:Bool):Void
	{
		cacheEnabled = enabled;
		if (!enabled)
			clearCache();
	}

	// ── Stats ─────────────────────────────────────────────────────────────────

	/** String compacto para el debug overlay. */
	public static function cacheDebugString():String
		return 'Atlas: $atlasCount/$maxAtlasCache  ' + cache.debugString();

	/** Stats completos. */
	public static function getCacheStats():String
		return '[Paths] Atlas=$atlasCount/$maxAtlasCache\n' + cache.fullStats();

	// ── Internos: carga de bitmaps ────────────────────────────────────────────

	/**
	 * Carga un BitmapData desde disco (via Lime) o desde assets embebidos.
	 * no cachea nada — is the nivel more under of load.
	 */
	static function _loadBitmapFromDisk(path:String):Null<Bitmap>
	{
		try
		{
			#if sys
			if (FileSystem.exists(path))
			{
				final img = lime.graphics.Image.fromFile(path);
				if (img != null)
					return Bitmap.fromImage(img);
			}
			#end
			if (!path.startsWith('mods/') && !path.startsWith('/') && OpenFlAssets.exists(path, IMAGE))
				return OpenFlAssets.getBitmapData(path);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _loadBitmapFromDisk "$path": $e');
		}
		return null;
	}

	// ── Internos: atlas ───────────────────────────────────────────────────────

	/**
	 * Pattern of cache unificado for FlxAtlasFrames.
	 * Valida el atlas antes de devolverlo: si el bitmap fue dispuesto,
	 * elimina la entrada y recarga.
	 */
	static function _cachedAtlas(key:String, loader:() -> FlxAtlasFrames):FlxAtlasFrames
	{
		if (cacheEnabled && atlasCache.exists(key))
		{
			final cached = atlasCache.get(key);
			if (_atlasValid(cached))
			{
				// Rescue: if the FlxGraphic of the atlas is in _previousGraphics,
				// moverlo to _currentGraphics for that sobreviva this session.
				if (cached.parent != null)
					cache.rescueFromPrevious(cached.parent.key, cached.parent);
				return cached;
			}
			// Invalid → clear and recargar
			atlasCache.remove(key);
			atlasCount--;
		}

		final atlas = loader();
		if (cacheEnabled && atlas != null)
			_storeAtlas(key, atlas);
		return atlas;
	}

	/**
	 * Carga Sparrow: obtiene el FlxGraphic de PathsCache (con GPU upload) y
	 * construye el FlxAtlasFrames desde el FlxGraphic + contenido del XML.
	 *
	 * Pasar FlxGraphic en vez de BitmapData a fromSparrow() garantiza que
	 * Flixel use el MISMO objeto de textura que PathsCache, sin duplicarlo.
	 */
	static function _sparrow(pngPath:String, xmlPath:String):FlxAtlasFrames
	{
		try
		{
			// Obtener o crear el FlxGraphic via PathsCache
			final graphic = _getGraphicForPath(pngPath);
			if (graphic == null)
			{
				trace('[Paths] _sparrow: PNG not found "$pngPath"');
				return null;
			}

			// Leer el XML
			final xmlContent = _readXml(xmlPath);
			if (xmlContent == null)
			{
				trace('[Paths] _sparrow: XML not found "$xmlPath"');
				return null;
			}

			// fromSparrow acepta FlxGraphic directamente — sin duplicar textura
			return FlxAtlasFrames.fromSparrow(graphic, xmlContent);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _sparrow "$pngPath": $e');
			return null;
		}
	}

	/** Variante of _sparrow that receives the path physical directly (no image()). */
	static function _sparrowFromPath(pngPath:String, xmlPath:String):FlxAtlasFrames
	{
		try
		{
			final graphic = _getGraphicForPath(pngPath);
			if (graphic == null)
				return null;
			final xmlContent = _readXml(xmlPath);
			if (xmlContent == null)
				return null;
			return FlxAtlasFrames.fromSparrow(graphic, xmlContent);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _sparrowFromPath "$pngPath": $e');
			return null;
		}
	}

	/** Carga Packer: igual que _sparrow pero para txt. */
	static function _packer(pngPath:String, txtPath:String):FlxAtlasFrames
	{
		try
		{
			final graphic = _getGraphicForPath(pngPath);
			if (graphic == null)
				return null;

			final txtContent = _readXml(txtPath); // reutilizar el mismo helper
			if (txtContent == null)
				return null;

			return FlxAtlasFrames.fromSpriteSheetPacker(graphic, txtContent);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _packer "$pngPath": $e');
			return null;
		}
	}

	/**
	 * Gets or creates a FlxGraphic for a path physical.
	 * Use PathsCache with the path physical as key.
	 */
	static function _getGraphicForPath(pngPath:String):Null<FlxGraphic>
	{
		// Hit fast in PathsCache
		if (cacheEnabled && cache.hasValidGraphic(pngPath))
			return cache.peekGraphic(pngPath);

		// Cargar bitmap y registrar en PathsCache
		final bmp = _loadBitmapFromDisk(pngPath);
		if (bmp == null)
			return null;

		return cacheEnabled ? cache.getGraphic(pngPath, bmp) : FlxGraphic.fromBitmapData(bmp, false, pngPath, false);
	}

	/** Lee contenido XML/TXT desde disco o assets embebidos. */
	static function _readXml(xmlPath:String):Null<String>
	{
		try
		{
			#if sys
			if (FileSystem.exists(xmlPath))
				return File.getContent(xmlPath);
			#end
			if (OpenFlAssets.exists(xmlPath, TEXT))
				return OpenFlAssets.getText(xmlPath);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _readXml "$xmlPath": $e');
		}
		return null;
	}

	static function _storeAtlas(key:String, atlas:FlxAtlasFrames):Void
	{
		// Sin eviction durante gameplay — clearPreviousSession() libera en bloque.
		if (atlas?.parent != null)
			atlas.parent.destroyOnNoUse = false; // PathsCache gestiona el ciclo de vida
		atlasCache.set(key, atlas);
		atlasCount++;
	}

	static inline function _atlasValid(atlas:FlxAtlasFrames):Bool
	{
		try
		{
			return atlas != null && atlas.parent != null && atlas.parent.bitmap != null;
		}
		catch (_:Dynamic)
		{
			return false;
		}
	}

	/** Elimina of the cache of atlas any entry cuyo FlxGraphic already no is in PathsCache. */
	static function _pruneInvalidAtlases():Void
	{
		final toRemove:Array<String> = [];
		for (key in atlasCache.keys())
			if (!_atlasValid(atlasCache.get(key)))
				toRemove.push(key);
		for (key in toRemove)
		{
			atlasCache.remove(key);
			atlasCount--;
		}
	}

	// ── Resolve helpers privados ──────────────────────────────────────────────

	/**
	 * Resuelve the path physical of the image of a stage asset.
	 * @param fromStage  Si se especifica, usa ESA carpeta de stage en lugar de currentStage.
	 */
	static function _resolveStageImagePath(key:String, ?fromStage:String):Null<String>
	{
		final lib = fromStage ?? currentStage;
		final candidates = [
			ModManager.resolveInMod('stages/$lib/images/$key.png'),
			ModManager.resolveInMod('images/stages/$key.png'),
			ModManager.resolveInMod('images/$key.png'),
		].filter(p -> p != null);

		#if sys
		for (p in candidates)
			if (FileSystem.exists(p))
				return p;
		final base = 'assets/stages/$lib/images/$key.png';
		if (FileSystem.exists(base))
			return base;
		#end
		final base = 'assets/stages/$lib/images/$key.png';
		if (OpenFlAssets.exists(base, IMAGE))
			return base;
		return null;
	}

	static function _resolveCharacterPng(key:String):String
		return resolveAny([
			ModManager.resolveInMod('characters/images/$key.png') ?? '',
			ModManager.resolveInMod('images/characters/$key.png') ?? '',
			'assets/characters/images/$key.png'
		]);

	static function _resolveCharacterXml(key:String):String
		return resolveAny([
			ModManager.resolveInMod('characters/images/$key.xml') ?? '',
			ModManager.resolveInMod('images/characters/$key.xml') ?? '',
			'assets/characters/images/$key.xml'
		]);

	static function _resolveCharacterTxt(key:String):String
		return resolveAny([
			ModManager.resolveInMod('characters/images/$key.txt') ?? '',
			ModManager.resolveInMod('images/characters/$key.txt') ?? '',
			'assets/characters/images/$key.txt'
		]);

	static function _songFolderVariants(name:String):Array<String>
	{
		final s = name.toLowerCase();
		final v:Array<String> = [];
		function add(x:String)
		{
			x = x.trim();
			if (x != '' && !v.contains(x))
				v.push(x);
		}
		add(s);
		add(s.replace(' ', '-'));
		add(s.replace('-', ' '));
		add(s.replace('!', ''));
		add(s.replace(' ', '-').replace('!', ''));
		return v;
	}

	static function _resolveSongFolder(song:String):String
	{
		#if sys
		// BUGFIX: igual que findChart(), buscar en TODOS los mods habilitados y no
		// solo en el mod activo. Sin este fix, si los archivos de audio (Inst.ogg,
		// Voices.ogg) estaban en un mod habilitado pero no activo (ej: base_game),
		// Lime tiraba error "file not found" al hacer loadStream().
		// Mod activo primero (mayor prioridad)
		if (ModManager.isActive())
		{
			final modRoot = ModManager.modRoot();
			for (v in _songFolderVariants(song))
				for (base in ['$modRoot/songs', '$modRoot/assets/songs'])
					if (sys.FileSystem.isDirectory('$base/$v'))
						return '$base/$v';
		}
		// Todos los mods instalados y habilitados
		for (mod in ModManager.installedMods)
		{
			if (!ModManager.isEnabled(mod.id)) continue;
			final modRoot = '${ModManager.MODS_FOLDER}/${mod.id}';
			for (v in _songFolderVariants(song))
				for (base in ['$modRoot/songs', '$modRoot/assets/songs'])
					if (sys.FileSystem.isDirectory('$base/$v'))
						return '$base/$v';
		}
		for (v in _songFolderVariants(song))
			if (sys.FileSystem.isDirectory('assets/songs/$v'))
				return 'assets/songs/$v';
		#end
		return 'assets/songs/${song.toLowerCase()}';
	}
}
