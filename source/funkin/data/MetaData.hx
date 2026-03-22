package funkin.data;

import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import mods.ModManager;

using StringTools;

/**
 * MetaData — Metadata by song.
 *
 * File: assets/songs/{songName}/meta.json
 *
 * Hierarchy of priority: meta.json > global.json > stage override > preference global
 *
 * Example complete meta.json:
 * {
 *   "ui":              "default",
 *   "noteSkin":        "MyPixelSkin",
 *   "noteSplash":      "Default",
 *
 *   "holdCoverEnabled": true,
 *   "holdCoverSkin":    "pixelNoteHoldCover",
 *   "holdCoverFormat":  "sparrow",
 *   "holdCoverFrameW":  36,
 *   "holdCoverFrameH":  32,
 *
 *   "stageSkins": {
 *     "school":     "DefaultPixel",
 *     "schoolEvil": "DefaultPixel",
 *     "stage":      "Default"
 *   },
 *
 *   "hideCombo":    false,
 *   "hideRatings":  false,
 *   "hudVisible":   true,
 *   "introVideo":   "bopeebo-intro",
 *   "outroVideo":   "bopeebo-outro",
 *   "midSongVideo": false
 * }
 *
 * Atlas formats supported in holdCoverFormat:
 *   "sparrow" — TextureAtlas XML (ej: pixelNoteHoldCover.xml). DEFAULT.
 *               PNG + XML with "loop" and "explode" animations.
 *   "packer"  — Starling/Packer TXT. PNG + TXT.
 *   "grid"    — Spritesheet in uniform grid. PNG only.
 *               Requires holdCoverFrameW + holdCoverFrameH.
 *               First N frames = "loop", subsequent N = "explode".
 */
typedef SongMetaData =
{
	@:optional var ui:Null<String>;
	@:optional var noteSkin:Null<String>;
	@:optional var noteSplash:Null<String>;
	@:optional var stageSkins:Null<Dynamic>;

	/**
	 * Overrides by difficulty. The key is the suffix of difficulty without the dash
	 * (ej: "erect", "hard", "nightmare"). The fields present in the object
	 * They have priority over the base values ​​of the meta.json for that difficulty.
	 *
	 * Example:
	 *   "difficultyOverrides": {
	 *     "erect":     { "artist": "NyaWithMe" },
	 *     "nightmare": { "artist": "NyaWithMe" }
	 *   }
	 *
	 * Currently supported fields: artist.
	 * (Easy of extender to other fields in MetaData.load)
	 */
	@:optional var difficultyOverrides:Null<Dynamic>;

	// ── Hold Cover ─────────────────────────────────────────────────────────
	@:optional var holdCoverEnabled:Null<Bool>;
	@:optional var holdCoverSkin:Null<String>;
	@:optional var holdCoverFormat:Null<String>;
	@:optional var holdCoverFrameW:Null<Int>;
	@:optional var holdCoverFrameH:Null<Int>;

	// ── HUD ────────────────────────────────────────────────────────────────
	@:optional var overrideGlobal:Null<Bool>;
	@:optional var hideCombo:Null<Bool>;
	@:optional var hideRatings:Null<Bool>;
	@:optional var hudVisible:Null<Bool>;
	@:optional var introVideo:Null<String>;
	@:optional var outroVideo:Null<String>;
	@:optional var introCutscene:Null<String>;
	@:optional var outroCutscene:Null<String>;
	@:optional var midSongVideo:Null<Bool>;
	@:optional var disableCameraZoom:Null<Bool>;
	@:optional var artist:Null<String>;

	/**
	 * List of suffixes of difficulty that this song expone to the player.
	 * If null or empty → is show all the difficulties detected (behavior legacy).
	 * If is especifica → only is show the diffs whose sufijos are in this list.
	 *
	 * Ejemplo:
	 *   "difficulties": ["-easy", "-hard"]
	 *   → Solo aparecen Easy y Hard aunque exista un chart "-nightmare".
	 *
	 *   "difficulties": ["", "-hard"]
	 *   → Normal (suffix empty) and Hard.
	 */
	@:optional var difficulties:Null<Array<String>>;
}

class MetaData
{
	public var ui:String = 'default';
	public var noteSkin:String = 'default';
	public var noteSplash:Null<String> = null;
	public var stageSkins:Null<Map<String, String>> = null;

	// ── Hold Cover ──────────────────────────────────────────────────────────

	/** null = use GlobalConfig.holdCoverEnabled */
	public var holdCoverEnabled:Null<Bool> = null;

	/** null = use GlobalConfig.holdCoverSkin o el builtin */
	public var holdCoverSkin:Null<String> = null;

	/** "sparrow" | "packer" | "grid" */
	public var holdCoverFormat:String = 'sparrow';

	/** Ancho de frame para formato "grid" */
	public var holdCoverFrameW:Int = 0;

	/** Alto de frame para formato "grid" */
	public var holdCoverFrameH:Int = 0;

	public var hideCombo:Bool = false;
	public var hideRatings:Bool = false;
	public var hudVisible:Bool = true;
	public var introVideo:Null<String> = null;
	public var outroVideo:Null<String> = null;

	/** Sprite cutscene key for the intro (assets/data/cutscenes/{key}.json). */
	public var introCutscene:Null<String> = null;

	/** Sprite cutscene key for the outro. */
	public var outroCutscene:Null<String> = null;

	public var midSongVideo:Bool = false;
	public var disableCameraZoom:Bool = false;
	public var artist:Null<String> = null;

	/**
	 * Suffixes of difficulty that is show for this song.
	 * null = without restriction (show all the detected).
	 * Array empty = equal that null (without restriction).
	 */
	public var allowedDifficulties:Null<Array<String>> = null;

	public var raw:SongMetaData;

	public function new()
	{
	}

	public static function load(songName:String, ?difficulty:String):MetaData
	{
		var meta = new MetaData();
		var global = GlobalConfig.instance;

		var rawData:SongMetaData = null;

		#if sys
		final songKey = songName.toLowerCase();

		// ── Priority 1: meta block of the file .level ───────────────────
		final levelMeta = funkin.data.LevelFile.loadMeta(songKey);
		if (levelMeta != null)
		{
			rawData = levelMeta;
			meta.raw = rawData;
			trace('[MetaData] Cargado desde .level: $songKey');
		}

		// ── Priority 2: meta.json legacy ──────────────────────────────────
		if (rawData == null)
		{
			var path:String = null;
			final modPath = ModManager.resolveInMod('songs/$songKey/meta.json');
			if (modPath != null)
				path = modPath;
			else
			{
				final basePath = 'assets/songs/$songKey/meta.json';
				if (FileSystem.exists(basePath))
					path = basePath;
			}

			if (path != null && FileSystem.exists(path))
			{
				try
				{
					rawData = cast Json.parse(File.getContent(path));
					meta.raw = rawData;
					trace('[MetaData] Loaded meta.json: $path');
				}
				catch (e)
				{
					trace('[MetaData] Error parsing meta.json of "$songName": $e');
				}
			}
			else
			{
				trace('[MetaData]No meta tag for "$songName", using GlobalConfig');
			}
		}
		#else
		final legacyPath = 'assets/songs/${songName.toLowerCase()}/meta.json';
		try
		{
			rawData = cast Json.parse(lime.utils.Assets.getText(legacyPath));
		}
		catch (_)
		{
		}
		#end

		meta.ui = resolveStr(rawData?.ui, global.ui, 'default');
		meta.noteSkin = resolveStr(rawData?.noteSkin, global.noteSkin, 'default');
		meta.noteSplash = (rawData?.noteSplash != null && rawData.noteSplash != '') ? rawData.noteSplash : null;

		if (rawData?.stageSkins != null)
		{
			meta.stageSkins = new Map<String, String>();
			var obj:Dynamic = rawData.stageSkins;
			for (field in Reflect.fields(obj))
			{
				var val = Std.string(Reflect.field(obj, field));
				if (val != null && val != '')
					meta.stageSkins.set(field, val);
			}
			if (!meta.stageSkins.iterator().hasNext())
				meta.stageSkins = null;
		}

		// ── Hold Cover ───────────────────────────────────────────────────────
		// holdCoverEnabled: meta have priority; null = Let GlobalConfig decide
		meta.holdCoverEnabled = (rawData?.holdCoverEnabled != null) ? rawData.holdCoverEnabled : null;

		// holdCoverSkin: meta > global
		if (rawData?.holdCoverSkin != null && rawData.holdCoverSkin != '')
			meta.holdCoverSkin = rawData.holdCoverSkin;
		else if (global.holdCoverSkin != null && global.holdCoverSkin != '')
			meta.holdCoverSkin = global.holdCoverSkin;

		// holdCoverFormat: meta > 'sparrow'
		final fmt = rawData?.holdCoverFormat;
		meta.holdCoverFormat = (fmt != null && fmt != '') ? fmt.toLowerCase() : 'sparrow';

		meta.holdCoverFrameW = (rawData?.holdCoverFrameW != null) ? rawData.holdCoverFrameW : 0;
		meta.holdCoverFrameH = (rawData?.holdCoverFrameH != null) ? rawData.holdCoverFrameH : 0;

		meta.hideCombo = resolveBool(rawData?.hideCombo, false);
		meta.hideRatings = resolveBool(rawData?.hideRatings, false);
		meta.hudVisible = resolveBool(rawData?.hudVisible, true);
		meta.introVideo = rawData?.introVideo ?? null;
		meta.outroVideo = rawData?.outroVideo ?? null;
		meta.introCutscene = rawData?.introCutscene ?? null;
		meta.outroCutscene = rawData?.outroCutscene ?? null;
		meta.midSongVideo = resolveBool(rawData?.midSongVideo, false);
		meta.disableCameraZoom = resolveBool(rawData?.disableCameraZoom, false);
		meta.artist = (rawData?.artist != null && rawData.artist != '') ? rawData.artist : null;

		// ── Difficulties allowed ──────────────────────────────────────────
		// If the meta.json has "difficulties": ["-easy", "-hard"], only those
		// Difficulties are exposed to the player (the rest are hidden even if they exist).
		if (rawData?.difficulties != null && Std.isOfType(rawData.difficulties, Array))
		{
			final arr:Array<Dynamic> = cast rawData.difficulties;
			if (arr.length > 0)
				meta.allowedDifficulties = [for (d in arr) Std.string(d)];
		}

		// ── Difficulty overrides ─────────────────────────────────────────────
		// Normalize difficulty: remove leading dash if comes with it ("-erect" → "erect").
		// The key in the JSON no lleva dash for that sea more legible.
		if (difficulty != null && rawData?.difficultyOverrides != null)
		{
			final diffKey = difficulty.startsWith('-') ? difficulty.substr(1) : difficulty;
			final ov:Dynamic = Reflect.field(rawData.difficultyOverrides, diffKey);
			if (ov != null)
			{
				// artist
				final ovArtist:Null<String> = Reflect.field(ov, 'artist');
				if (ovArtist != null && ovArtist != '')
					meta.artist = ovArtist;

				// Add more fields here in the future following the same pattern:
				// final ovXxx = Reflect.field(ov, 'xxx');
				// if (ovXxx != null) meta.xxx = ovXxx;

				trace('[MetaData] difficultyOverrides["$diffKey"] applied');
			}
		}

		trace('[MetaData] Resolved — noteSkin="${meta.noteSkin}" holdCoverEnabled=${meta.holdCoverEnabled} holdCoverSkin="${meta.holdCoverSkin}" holdCoverFormat="${meta.holdCoverFormat}"');
		return meta;
	}

	/**
	 * Save the values actuales as meta.json in the folder of the song.
	 */
	public static function save(songName:String, ui:String, noteSkin:String, ?noteSplash:String = null, ?stageSkins:Map<String, String> = null,
			?holdCoverEnabled:Null<Bool> = null, ?holdCoverSkin:Null<String> = null, ?holdCoverFormat:String = 'sparrow', ?holdCoverFrameW:Int = 0,
			?holdCoverFrameH:Int = 0, ?hideCombo:Bool = false, ?hideRatings:Bool = false, ?hudVisible:Bool = true):Void
	{
		#if sys
		try
		{
			var dir = 'assets/songs/${songName.toLowerCase()}';
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);

			var stageSkinsObj:Dynamic = null;
			if (stageSkins != null)
			{
				stageSkinsObj = {};
				for (stage in stageSkins.keys())
					Reflect.setField(stageSkinsObj, stage, stageSkins.get(stage));
			}

			var data:SongMetaData = {
				ui: (ui != null && ui != '') ? ui : null,
				noteSkin: (noteSkin != null && noteSkin != '') ? noteSkin : null,
				noteSplash: (noteSplash != null && noteSplash != '') ? noteSplash : null,
				stageSkins: stageSkinsObj,
				holdCoverEnabled: holdCoverEnabled,
				holdCoverSkin: (holdCoverSkin != null && holdCoverSkin != '') ? holdCoverSkin : null,
				holdCoverFormat: (holdCoverFormat != null && holdCoverFormat != 'sparrow') ? holdCoverFormat : null,
				holdCoverFrameW: (holdCoverFrameW > 0) ? holdCoverFrameW : null,
				holdCoverFrameH: (holdCoverFrameH > 0) ? holdCoverFrameH : null,
				hideCombo: hideCombo,
				hideRatings: hideRatings,
				hudVisible: hudVisible
			};

			File.saveContent('$dir/meta.json', Json.stringify(data, null, '\t'));
			trace('[MetaData] Saved: $dir/meta.json');
		}
		catch (e)
		{
			trace('[MetaData] Error to save meta.json: $e');
		}
		#end
	}

	static inline function resolveStr(metaVal:Null<String>, globalVal:Null<String>, fallback:String):String
	{
		if (metaVal != null && metaVal.length > 0)
			return metaVal;
		if (globalVal != null && globalVal.length > 0)
			return globalVal;
		return fallback;
	}

	static inline function resolveBool(metaVal:Null<Bool>, fallback:Bool):Bool
		return (metaVal != null) ? metaVal : fallback;
}
