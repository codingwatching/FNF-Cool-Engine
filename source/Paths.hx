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

class Paths
{
	public static inline var SOUND_EXT = #if web "mp3" #else "ogg" #end;

	// ── Acceso al caché principal ─────────────────────────────────────────────

	/** Instancia global de PathsCache. Nunca null. */
	public static var cache(get, never):PathsCache;

	static inline function get_cache():PathsCache
		return PathsCache.instance;

	static var atlasCache:Map<String, FlxAtlasFrames> = [];
	static var atlasCount:Int = 0;

	public static var maxAtlasCache:Int = 50;

	public static var cacheEnabled:Bool = true;

	// ── Stage actual ──────────────────────────────────────────────────────────
	public static var currentStage:String = 'stage_week1';

	// ── GPU Options ───────────────────────────────────────────────────────
	public static var gpuCaching(get, set):Bool;

	static inline function get_gpuCaching():Bool
		return PathsCache.gpuCaching;

	static inline function set_gpuCaching(v:Bool):Bool
	{
		PathsCache.gpuCaching = v;
		return v;
	}

	// Paths cache delegation
	public static inline function beginSession():Void
		cache.beginSession();

	// Destroyer for assets that are no longer valid (e.g. after a mod reload).
	public static inline function clearPreviousSession():Void
	{
		cache.clearPreviousSession();
		_pruneInvalidAtlases();
	}

	public static inline function addExclusion(key:String):Void
		cache.addExclusion(key);

	// Clean up all cached assets that are no longer valid + force GC.
	public static inline function clearStoredMemory():Void
	{
		cache.clearStoredMemory();
		_pruneInvalidAtlases();
	}

	// Destroy the graphics in clearStoredMemory() that are no longer valid, but keep the rest of the cache entries (e.g. for sounds).
	public static inline function clearUnusedMemory():Void
		cache.clearUnusedMemory();

	// ── Core: resolve ─────────────────────────────────────────────────────────

	public static function resolve(file:String, ?type:AssetType):String
	{
		final modPath = ModManager.resolveInMod(file);
		if (modPath != null)
			return modPath;
		return 'assets/$file';
	}

	/**
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

	public static function exists(file:String, ?type:AssetType):Bool
	{
		final path = resolve(file, type);
		#if sys
		return FileSystem.exists(path);
		#else
		return OpenFlAssets.exists(path, type);
		#end
	}

	public static function getText(file:String):String
	{
		final path = resolve(file, TEXT);
		#if sys
		if (FileSystem.exists(path))
			return File.getContent(path);
		#end
		return OpenFlAssets.getText(path);
	}

	// ── Paths typeds ─────────────────────────────────────────────────────────

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
		return resolve('images/$key.png', IMAGE);
	}

	public static inline function imageCutscene(key:String):String
		return resolve('$key.png', IMAGE);

	public static inline function characterimage(key:String):String
		return resolve('characters/images/$key.png', IMAGE);

	public static function characterFolder(key:String):String
		return resolve('characters/images/$key/');

	public static function sound(key:String):String
	{
		#if sys
		final modPath = ModManager.resolveInMod('sounds/$key.$SOUND_EXT');
		if (modPath != null && FileSystem.exists(modPath))
			return modPath;
		final assetsPath = 'assets/sounds/$key.$SOUND_EXT';
		if (FileSystem.exists(assetsPath))
			return assetsPath;
		#end
		return resolve('sounds/$key.$SOUND_EXT', SOUND);
	}

	public static function soundStage(key:String):String
	{
		#if sys
		if (ModManager.isActive())
		{
			final p = '${ModManager.modRoot()}/stages/$key.$SOUND_EXT';
			if (FileSystem.exists(p))
				return p;
		}
		for (mod in ModManager.installedMods)
		{
			if (!ModManager.isEnabled(mod.id))
				continue;
			final p = '${ModManager.MODS_FOLDER}/${mod.id}/stages/$key.$SOUND_EXT';
			if (FileSystem.exists(p))
				return p;
		}
		final assetsPath = 'assets/stages/$key.$SOUND_EXT';
		if (FileSystem.exists(assetsPath))
			return assetsPath;
		#end
		return 'assets/stages/$key.$SOUND_EXT';
	}

	public static inline function soundRandom(key:String, min:Int, max:Int):Null<Sound>
		return getSound(key + FlxG.random.int(min, max));

	public static inline function soundRandomStage(key:String, min:Int, max:Int):String
		return soundStage('${funkin.gameplay.PlayState.curStage}/sounds/' + key + FlxG.random.int(min, max));

	public static function music(key:String):String
	{
		#if sys
		final modPath = ModManager.resolveInMod('music/$key.$SOUND_EXT');
		if (modPath != null && FileSystem.exists(modPath))
			return modPath;
		final assetsPath = 'assets/music/$key.$SOUND_EXT';
		if (FileSystem.exists(assetsPath))
			return assetsPath;
		#end
		return resolve('music/$key.$SOUND_EXT', MUSIC);
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

	/** ── Graphics Load ─────────────────────────────────────────────────────
		* Loads BitmapData from disk or embedded assets.
		* Internally passes through PathsCache → if gpuCaching=true, the image in RAM
		* is released after upload and FlxGraphic.bitmap is returned (which may
		* be in "GPU only" mode; the pixels are not accessible from the CPU).

		* For effects that need to read pixels from the CPU (dynamic tinting, etc.)
		* use getGraphic() with allowGPU=false.
		* @deprecated Prefer getGraphic() for full integration with Flixel.
	 */
	public static function getBitmap(key:String, allowGPU:Bool = true):Null<Bitmap>
	{
		final g = getGraphic(key, allowGPU);
		return g?.bitmap;
	}

	/**
	 * Loads and caches an FlxGraphic for the given key.
	 *
	 * • First searches PathsCache (cache hit → O(1), no I/O).
	 * • The resulting FlxGraphic has persist=true + destroyOnNoUse=false.
	 *
	 * @param key       Logical key of the asset (without the "images/" prefix, without ".png").
	 * @param allowGPU  If false, disable GPU caching for this asset.
	 */
	public static function getGraphic(key:String, allowGPU:Bool = true):Null<FlxGraphic>
	{
		final path = image(key);
		final cacheKey = path;

		if (cacheEnabled && cache.hasValidGraphic(cacheKey))
			return cache.peekGraphic(cacheKey);

		final bmp = _loadBitmapFromDisk(path);
		if (bmp == null)
		{
			trace('[Paths] getGraphic: not found "$key" (path="$path")');
			return null;
		}

		return cacheEnabled ? cache.getGraphic(cacheKey, bmp, allowGPU) : FlxGraphic.fromBitmapData(bmp, false, cacheKey, false);
	}

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

		@:privateAccess
		{
			final deadEntry = FlxG.bitmap.get(path);
			if (deadEntry != null && deadEntry.bitmap == null)
			{
				FlxG.bitmap.removeKey(path);
				trace('[Paths] imageStage: purged dead entry of FlxG.bitmap for "$path"');
			}
		}

		if (cacheEnabled)
			cache.getGraphic(path, bmp);
		return bmp;
	}

	public static function getSound(path:String, safety:Bool = false):Null<Sound>
	{
		// Cache hit
		if (cacheEnabled && cache.hasSound(path))
			return cache.getSound(path, null, safety);

		var snd:Sound = null;
		try
		{
			#if sys
			if (FileSystem.exists(path))
			{
				snd = Sound.fromFile(path);
			}
			#end
			if (snd == null)
			{
				if (OpenFlAssets.exists(path, SOUND))
					snd = OpenFlAssets.getSound(path);
				else if (OpenFlAssets.exists(path, MUSIC))
					snd = OpenFlAssets.getSound(path);
			}
		}
		catch (e:Dynamic)
		{
			trace('[Paths] getSound "$path": $e');
		}

		return cacheEnabled ? cache.getSound(path, snd, safety) : snd;
	}

	public static function loadMusic(key:String):Null<Sound>
	{
		final path = music(key);
		return getSound(path);
	}

	// ── Audio Load for songs (streaming) ─────────────────────────────────

	public static function loadInst(song:String, ?diffSuffix:String):flixel.sound.FlxSound
		return _loadStreamingSound(inst(song, diffSuffix));

	public static function loadVoices(song:String, ?diffSuffix:String):flixel.sound.FlxSound
		return _loadStreamingSound(voices(song, diffSuffix));

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
		if (diffSuffix != null && diffSuffix != '')
		{
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
		return null;
	}

	public static function loadVoicesForChar(song:String, charName:String, ?diffSuffix:String):Null<flixel.sound.FlxSound>
	{
		final path = voicesForChar(song, charName, diffSuffix);
		if (path == null)
			return null;
		return _loadStreamingSound(path);
	}

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

	// ── Cache Atlas Sparrow ───────────────────────────────────────────────

	public static function getSparrowAtlas(key:String):FlxAtlasFrames
	{
		final path:String = image(key);
		return _cachedAtlas(path, () -> _sparrow(path, resolve('images/$key.xml')));
	}

	public static function characterSprite(key:String):FlxAtlasFrames
		return _cachedAtlas('char_$key', () -> _loadCharacterSpriteAtlas(key));

	static function _loadCharacterSpriteAtlas(key:String):FlxAtlasFrames
	{
		final sheetsPath = _resolveCharacterSheets(key);
		#if sys
		if (sheetsPath != null && sys.FileSystem.exists(sheetsPath))
		{
			try
			{
				final sheetKeys:Array<String> = haxe.Json.parse(sys.io.File.getContent(sheetsPath));
				if (sheetKeys != null && sheetKeys.length > 0)
				{
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

					if (animateFolders.length > 0)
					{
						if (sparrowKeys.length > 0)
							trace('[Paths] characterSprite "$key": .sheets mixes Animate and Sparrow — only the Animate folders are used.');

						trace('[Paths] characterSprite "$key": multi-Animate Detected — use FunkinSprite.loadCharacterSparrow() instead.');
						return null;
					}

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
								trace('[Paths] characterSprite "$key": multi-sheet Sparrow (${atlases.length} fused spritesheets)');
								return merged;
							}
						}
					}
				}
			}
			catch (e:Dynamic)
			{
				trace('[Paths] characterSprite "$key": error reading .sheets — $e');
			}
		}
		#end
		return _sparrow(_resolveCharacterPng(key), _resolveCharacterXml(key));
	}

	static function _resolveCharacterAnimateFolder(charKey:String, sheetKey:String):Null<String>
	{
		#if sys
		final isSubKey = !sheetKey.contains('/');
		final candidates:Array<String> = [];

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
	{
		final pngPath = resolve('$key.png', IMAGE);
		final xmlPath = resolve('$key.xml', TEXT);
		return _cachedAtlas('cutscene_$key', () -> _sparrowFromPath(pngPath, xmlPath));
	}

	// ── Cache Atlas Packer ────────────────────────────────────────────────

	public static function getPackerAtlas(key:String):FlxAtlasFrames
		return _cachedAtlas('packer_$key', () -> _packer(image(key), resolve('images/$key.txt')));

	public static function characterSpriteTxt(key:String):FlxAtlasFrames
		return _cachedAtlas('char_txt_$key', () -> _packer(_resolveCharacterPng(key), _resolveCharacterTxt(key)));

	// Packer (TXT) atlas from a stage. Accepts optional @fromStage override.
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

	// ── Management Cache Atlas ────────────────────────────────────────────
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
		trace('[Paths] Atlas cache cleaned.');
	}

	// GC/Memory Call
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
		trace('[Paths] FlxG.bitmap + OpenFL cache cleaned.');
	}

	public static function clearAllCaches():Void
	{
		clearCache();
		cache.forceFullClear();
		try
		{
			final oflCache:openfl.utils.AssetCache = cast openfl.utils.Assets.cache;
			@:privateAccess
			{
				if (oflCache.bitmapData != null)
				{
					final bmpKeys = [for (k in oflCache.bitmapData.keys()) k];
					for (k in bmpKeys) oflCache.removeBitmapData(k);
				}
				if (oflCache.sound != null)
				{
					final sndKeys = [for (k in oflCache.sound.keys()) k];
					for (k in sndKeys) oflCache.removeSound(k);
				}
			}
			oflCache.clear();
		}
		catch (_:Dynamic) {}

		clearFlxBitmapCache();
		cache.clearModPathCache();
	}

	public static inline function forceClearCache():Void
		clearAllCaches();

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

		cache.clearGameplayAssets();

		if (toRemove.length > 0)
			trace('[Paths] clearGameplayCache: ${toRemove.length} atlas(es) + gameplay graphics released.');
	}

	public static function setCacheEnabled(enabled:Bool):Void
	{
		cacheEnabled = enabled;
		if (!enabled)
			clearCache();
	}

	// ── Stats ─────────────────────────────────────────────────────────────────

	public static function cacheDebugString():String
		return 'Atlas: $atlasCount/$maxAtlasCache  ' + cache.debugString();

	public static function getCacheStats():String
		return '[Paths] Atlas=$atlasCount/$maxAtlasCache\n' + cache.fullStats();

	static function _loadBitmapFromDisk(path:String):Null<Bitmap>
	{
		try
		{
			#if sys
			if (FileSystem.exists(path))
			{
				try
				{
					final bmp = Bitmap.fromFile(path);
					if (bmp != null)
						return bmp;
				}
				catch (innerE:Dynamic)
				{
					trace('[Paths] _loadBitmapFromDisk fromFile failed "$path": $innerE — trying OpenFlAssets fallback');
				}
			}
			#end
			if (!path.startsWith('/') && OpenFlAssets.exists(path, IMAGE))
				return OpenFlAssets.getBitmapData(path);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _loadBitmapFromDisk "$path": $e');
		}
		return null;
	}

	static function _cachedAtlas(key:String, loader:() -> FlxAtlasFrames):FlxAtlasFrames
	{
		if (cacheEnabled && atlasCache.exists(key))
		{
			final cached = atlasCache.get(key);
			final parentOwned = cached?.parent == null || cache.hasValidGraphic(cached.parent.key);
			if (_atlasValid(cached) && parentOwned)
			{
				if (cached.parent != null)
					cache.rescueFromPrevious(cached.parent.key, cached.parent);
				return cached;
			}
			atlasCache.remove(key);
			atlasCount--;
		}

		final atlas = loader();
		if (cacheEnabled && atlas != null)
			_storeAtlas(key, atlas);
		return atlas;
	}

	static function _sparrow(pngPath:String, xmlPath:String):FlxAtlasFrames
	{
		try
		{
			final graphic = _getGraphicForPath(pngPath);
			if (graphic == null)
			{
				trace('[Paths] _sparrow: PNG not found "$pngPath"');
				return null;
			}

			final xmlContent = _readXml(xmlPath);
			if (xmlContent == null)
			{
				trace('[Paths] _sparrow: XML not found "$xmlPath"');
				return null;
			}

			return FlxAtlasFrames.fromSparrow(graphic, xmlContent);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _sparrow "$pngPath": $e');
			return null;
		}
	}

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

	static function _packer(pngPath:String, txtPath:String):FlxAtlasFrames
	{
		try
		{
			final graphic = _getGraphicForPath(pngPath);
			if (graphic == null)
				return null;

			final txtContent = _readXml(txtPath);
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

	static function _getGraphicForPath(pngPath:String):Null<FlxGraphic>
	{
		if (cacheEnabled && cache.hasValidGraphic(pngPath))
			return cache.peekGraphic(pngPath);

		final bmp = _loadBitmapFromDisk(pngPath);
		if (bmp == null)
			return null;

		return cacheEnabled ? cache.getGraphic(pngPath, bmp) : FlxGraphic.fromBitmapData(bmp, false, pngPath, false);
	}

	// Read XML/TXT content from disk or embedded assets.
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
		if (atlasCount >= maxAtlasCache)
		{
			var evictKey:Null<String> = null;
			for (k => a in atlasCache)
			{
				if (!_atlasValid(a)) { evictKey = k; break; }
				if (evictKey == null) evictKey = k; // fallback: primera entrada
			}
			if (evictKey != null)
			{
				final evicted = atlasCache.get(evictKey);
				if (evicted?.parent != null)
					evicted.parent.destroyOnNoUse = true;
				atlasCache.remove(evictKey);
				atlasCount--;
			}
		}
		if (atlas?.parent != null)
			atlas.parent.destroyOnNoUse = false;
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

	/**
	 * Removes any atlas cache entry whose FlxGraphic is no longer valid OR whose
	 * parent graphic has been evicted from PathsCache (zombie entries whose bitmap
	 * pointer is non-null but the graphic is no longer tracked by the session cache).
	 */
	static function _pruneInvalidAtlases():Void
	{
		final toRemove:Array<String> = [];
		for (key in atlasCache.keys())
		{
			final atlas = atlasCache.get(key);
			final parentKey  = atlas?.parent?.key ?? '';
			final isZombie   = parentKey != '' && !cache.hasValidGraphic(parentKey);
			if (!_atlasValid(atlas) || isZombie)
				toRemove.push(key);
		}
		for (key in toRemove)
		{
			atlasCache.remove(key);
			atlasCount--;
		}
	}

	// ── Resolve helpers privated ──────────────────────────────────────────────

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
		if (ModManager.isActive())
		{
			final modRoot = ModManager.modRoot();
			for (v in _songFolderVariants(song))
				for (base in ['$modRoot/songs', '$modRoot/assets/songs'])
					if (sys.FileSystem.isDirectory('$base/$v'))
						return '$base/$v';
		}
		for (mod in ModManager.installedMods)
		{
			if (!ModManager.isEnabled(mod.id))
				continue;
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