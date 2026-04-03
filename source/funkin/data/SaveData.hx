package funkin.data;

import flixel.FlxG;

/**
	* SaveData — A typed layer on top of FlxG.save.data.
	*
	* ─── Why it exists ──────────────────────────── ──────────────────────────────
	*
	* FlxG.save.data is a dynamic object: any field can be written to without

	* the compiler notifying you. These types of problems:
	*
	* 1. Silent typos: `FlxG.save.data.antialiasing = true` compiles and saves
	* 	to a field that is never read, while `antialiasing` remains null.
	*
	* 2. Scattered migrations: each refactor renames a field and leaves migration code scattered throughout the project (see FPSCap → fpsTarget).
	* 	This class solves both:

	* • `SaveData.data` returns FlxG.save.data cast to the typedef `SaveDataFields`,

	* resulting in autocompletion and compile-time type errors.

	* • `SaveData.migrate()` centralizes ALL migrations in one place.

	* Call it once at startup (in Main, after FlxG.save.bind). *
	* ─── Usage ────────────────────────────────── ──────────────────────────────────
	*
	* Read: var fps = SaveData.data.fpsTarget ?? 60;
	* Write: SaveData.data.antialiasing = true; SaveData.flush();

	* Flush: SaveData.flush(); // equivalent to FlxG.save.flush()
	*
	* ─── Adding a New Field ───────────────────────── ─────────────────────────
	*
	* 1. Declare the field in `SaveDataFields` with `@:optional` and the correct type.

	* 2. If renaming an existing field, add a rule in `migrate()`.
	* 3. Do not directly edit FlxG.save.data — always use SaveData.data.
	*
	* @author  Cool Engine Team
	* @since   0.6.1
 */
// ─── Typedef typing ──────────────────────────────────────────────────────────

/**
	* All fields that the engine saves in FlxG.save.data.
	* Each field is optional (Null<T>) because it may not exist in older saves.

	* Naming convention:
	* • Strict camelCase.
	* • Deprecated fields are marked with the comment "@deprecated" and the new name.
 */
typedef SaveDataFields =
{
	// ── Video / performance ──────────────────────────────────────────────────

	/** FPS limit. 0 = no limit. Replaces the obsolete FPSCap field. */
	@:optional var fpsTarget:Null<Int>;

	/** @deprecated — Use fpsTarget. Retained for migration purposes only. */
	@:optional var FPSCap:Null<Int>;

	/** Sync vertical. */
	@:optional var vsync:Null<Bool>;

	/** Antialiasing global. */
	@:optional var antialiasing:Null<Bool>;

	/** Screen scaling mode (e.g. "letterbox", "stretch"). */
	@:optional var scaleMode:Null<String>;

	/** Internal render resolution (e.g. "720p", "1080p"). */
	@:optional var renderResolution:Null<String>;

	/** Shader effects enabled. */
	@:optional var shadersEnabled:Null<Bool>;

	/** @deprecated — use shadersEnabled. */
	@:optional var shaders:Null<Bool>;

	/** Special visual effects (particles, etc.). */
	@:optional var specialVisualEffects:Null<Bool>;

	/** GPU texture cache. */
	@:optional var gpuCaching:Null<Bool>;

	/** Low memory power mode. */
	@:optional var lowMemoryMode:Null<Bool>;

	/** Streaming music instead of full upload. */
	@:optional var streamedMusic:Null<Bool>;

	// ── Gameplay ─────────────────────────────────────────────────────────────

	/** Downscroll enabled. */
	@:optional var downscroll:Null<Bool>;

	/** Middlescroll enabled. */
	@:optional var middlescroll:Null<Bool>;

	/** Ghost tap (does not penalize taps without a note). */
	@:optional var ghosttap:Null<Bool>;

	/** Sick Mode (Strict FC). */
	@:optional var sickmode:Null<Bool>;

	/** Global audio/input offset in ms. */
	@:optional var offset:Null<Float>;

	/** Hide HUD toggle. */
	@:optional var HUD:Null<Bool>;

	/** Hitsounds activated. */
	@:optional var hitsounds:Null<Bool>;

	/** Accuracy display enabled. */
	@:optional var accuracyDisplay:Null<Bool>;

	/** Notesplashes activated. */
	@:optional var notesplashes:Null<Bool>;

	// ── Appearance ───────────────────────────────────────────────────────────

	/** Selected Noteskin. */
	@:optional var noteSkin:Null<String>;

	/** Selected Splash. */
	@:optional var noteSplash:Null<String>;

	/** Note lane alpha (0.0–1.0). */
	@:optional var laneAlpha:Null<Float>;

	/** Cursor Skin. */
	@:optional var cursorSkin:Null<String>;

	/** Offset X of the rating text. */
	@:optional var ratingOffsetX:Null<Float>;

	/** Offset and rating text. */
	@:optional var ratingOffsetY:Null<Float>;

	/** Song ratings per key (serialized Map<String,Float>). */
	@:optional var songRating:Null<Dynamic>;

	/** Flash effects in transitions. */
	@:optional var flashing:Null<Bool>;

	// ── Audio ────────────────────────────────────────────────────────────────

	/** Master volume (0.0–1.0). */
	@:optional var volume:Null<Float>;

	/** Silenced master. */
	@:optional var muted:Null<Bool>;

	/** Core audio volume. */
	@:optional var coreVolume:Null<Float>;

	/** Core audio muted. */
	@:optional var coreMuted:Null<Bool>;

	// ── Subtitles ───────────────────────────────────────────────────────────
	@:optional var subtitlesEnabled:Null<Bool>;
	@:optional var subtitleFont:Null<String>;
	@:optional var subtitleSize:Null<Int>;
	@:optional var subtitleColor:Null<Int>;
	@:optional var subtitleBold:Null<Bool>;
	@:optional var subtitleFadeIn:Null<Float>;
	@:optional var subtitlePosition:Null<String>;
	@:optional var subtitleBgAlpha:Null<Float>;
	@:optional var subtitleTranslateLang:Null<String>;

	// ── Controls ────────────────────────────────────────────────────────────
	@:optional var upBind:Null<String>;
	@:optional var downBind:Null<String>;
	@:optional var leftBind:Null<String>;
	@:optional var rightBind:Null<String>;
	@:optional var killBind:Null<String>;
	@:optional var acceptBind:Null<String>;
	@:optional var backBind:Null<String>;
	@:optional var pauseBind:Null<String>;
	@:optional var screenshotBind:Null<String>;
	@:optional var cheatBind:Null<String>;

	// ── Mobile ───────────────────────────────────────────────────────────────
	@:optional var mobileAlpha:Null<Float>;
	@:optional var mobilePadLayout:Null<String>;
	@:optional var touchIndicator:Null<Bool>;

	// ── Game progress ────────────────────────────────────────────────────

	/** Unlocked Weeks (Serialized Array<Bool>). */
	@:optional var weekUnlocked:Null<Dynamic>;

	/** Scores per song (Serialized Map). */
	@:optional var songScores:Null<Dynamic>;

	// ── Modchart / scripting ─────────────────────────────────────────────────
	@:optional var modchart_last:Null<String>;
	@:optional var modchart_script:Null<String>;
	@:optional var ruleScriptData:Null<Dynamic>;
}

// ─── Manager ─────────────────────────────────────────────────────────────────

class SaveData
{
	// ── Typed Access ──────────────────────────────────────────────────────

	/**
	 * Typed access to FlxG.save.data.
	 *
	 * Reads and writes directly to the same object as FlxG.save.data:
	 * The cast is only for compiler information; there is no data copying.
	 * 
	 * SaveData.data.antialiasing = true; 
	 * SaveData.flush();
	 */
	public static var data(get, never):SaveDataFields;

	static inline function get_data():SaveDataFields
		return (cast FlxG.save.data : SaveDataFields);

	// ── Persistence ────────────────────────────────────────────────────────

	/** The save persists on disk. Equivalent to FlxG.save.flush(). */
	public static inline function flush():Void
		FlxG.save.flush();

	// ── Centralized migration ───────────────────────────────────────────────

	/**
		* Migrate obsolete fields to the current name and clean up any leftover data.

		* Must be called ONLY ONCE at application startup, after

		 `FlxG.save.bind(...)`.
		* *
		* ─── Migration History ──────────────────────────────────────────

		* 0.6.1 FPSCap → fpsTarget (field renamed)
		* 0.6.1 shaders → shadersEnabled (field renamed)

		* ─────────────────────────────────────────────────────────────────────────
		*
		* To add a future migration, add an `if` block following the
		  same pattern: check the old field, copy The new one nullifies the old one.
	 */
	public static function migrate():Void
	{
		var dirty = false;

		// ── v0.6.1: FPSCap → fpsTarget ──────────────────────────────────────
		if (data.FPSCap != null && data.fpsTarget == null)
		{
			trace('[SaveData] migrate: FPSCap(${data.FPSCap}) → fpsTarget');
			data.fpsTarget = data.FPSCap;
			data.FPSCap = null;
			dirty = true;
		}

		// ── v0.6.1: shaders → shadersEnabled ────────────────────────────────
		if (data.shaders != null && data.shadersEnabled == null)
		{
			trace('[SaveData] migrate: shaders(${data.shaders}) → shadersEnabled');
			data.shadersEnabled = data.shaders;
			data.shaders = null;
			dirty = true;
		}

		// ── Add future migrations here ───────────────────────────────
		// Pattern:
		//   if (data.oldField != null && data.oldField == null)
		//   {
		//       trace('[SaveData] migrate: oldField → newField');
		//       data.newField = data.oldField;
		//       data.oldField = null;
		//       dirty = true;
		//   }

		if (dirty)
		{
			flush();
			trace('[SaveData] migrate: save actualizado y persistido.');
		}
		else
		{
			trace('[SaveData] migrate: sin cambios necesarios.');
		}
	}
}
