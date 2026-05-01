package mods.compat;

using StringTools;

import haxe.Json;
import funkin.data.Song;
import funkin.data.Section;

/**
 * CodenameConverter
 * ─────────────────────────────────────────────────────────────────────────────
 * Translates Codename Engine (CNE) data formats into Cool Engine's native
 * SwagSong / CharacterData structures.
 *
 * ── Codename chart structure (reference) ─────────────────────────────────────
 * {
 *   "song": {
 *     "song": "Bopeebo",
 *     "bpm": 100,  "speed": 1,  "needsVoices": true,
 *     "player":   "bf",
 *     "opponent": "dad",
 *     "gf":       "gf",
 *     "stage":    "stage",
 *     "notes": {
 *       "easy":   [ ...sections ],
 *       "normal": [ ...sections ],
 *       "hard":   [ ...sections ]
 *     },
 *     "events": [
 *       { "time": 1234, "name": "Camera Move", "params": ["dad"] }
 *     ]
 *   }
 * }
 *
 * CNE sections are identical in structure to base-game sections.
 *
 * ── Codename character structure (reference) ─────────────────────────────────
 * {
 *   "asset":      "characters/bf",
 *   "animations": [
 *     { "name": "idle",  "anim": "BF idle dance",
 *       "fps": 24,  "loop": false,  "offset": [0, 0] }
 *   ],
 *   "antialiasing": true,
 *   "scale":        1,
 *   "icon":         "bf",
 *   "color":        [49, 176, 209],
 *   "flipX":        false,
 *   "position":     [0, 0],
 *   "cameraOffset": [0, 0],
 *   "isPlayer":     false
 * }
 */
class CodenameConverter
{
	// ─── Chart ────────────────────────────────────────────────────────────────

	/**
	 * Converts a raw Codename Engine chart JSON string into a Cool Engine SwagSong.
	 *
	 * @param rawJson     Full content of the CNE chart JSON.
	 * @param difficulty  Which difficulty key to extract from `notes` object.
	 *                    Defaults to "hard", falls back to first available key.
	 */
	public static function convertChart(rawJson:String, ?difficulty:String = 'hard',
	                                    ?chartFilePath:String = null):SwagSong
	{
		trace('[CodenameConverter] Converting chart (difficulty=$difficulty)...');

		final root:Dynamic = Json.parse(rawJson);
		final cs:Dynamic   = root.song ?? root;

		// ── Song name ─────────────────────────────────────────────────────────
		// CNE 1.6 charts do not have a top-level "song" field — derive the name
		// from the file path (e.g. "songs/rebellion/charts/hard.json" → "rebellion").
		var songName:String = _str(cs.song, null);
		if (songName == null && chartFilePath != null)
		{
			final parts = chartFilePath.replace('\\', '/').split('/');
			// Find "charts" folder segment or a .json file; the parent folder is the song id.
			var found = false;
			for (i in 1...parts.length)
			{
				if (parts[i] == 'charts' || parts[i].endsWith('.json'))
				{
					songName = parts[i - 1];
					found = true;
					break;
				}
			}
			if (!found && parts.length >= 2)
				songName = parts[parts.length - 2];
		}
		if (songName == null) songName = 'unknown';

		// ── CNE 1.6: BPM from events (no top-level bpm field) ─────────────────
		var resolvedBpm:Float = _float(cs.bpm, 0);
		final cneEventsEarly:Array<Dynamic> = (cs.events != null && Std.isOfType(cs.events, Array))
			? cast cs.events : [];
		if (resolvedBpm <= 0)
		{
			for (ev in cneEventsEarly)
			{
				if (_str(ev.name, '') == 'BPM Change')
				{
					final params:Array<Dynamic> = (ev.params != null && Std.isOfType(ev.params, Array))
						? cast ev.params : [];
					if (params.length > 0)
					{
						final b = _float(params[0], 0);
						if (b > 0) { resolvedBpm = b; break; }
					}
				}
			}
		}
		if (resolvedBpm <= 0) resolvedBpm = 100;

		// ── Basic fields ─────────────────────────────────────────────────────
		final song:SwagSong = {
			song:        songName,
			bpm:         resolvedBpm,
			// CNE 1.6 uses "scrollSpeed", legacy uses "speed"
			speed:       _float(cs.speed ?? cs.scrollSpeed, 1),
			needsVoices: _bool(cs.needsVoices, true),
			stage:       _str(cs.stage, 'stage'),
			validScore:  true,
			notes:       [],
			// Legacy fields — populated from strumLines if available
			player1:     _str(cs.player   ?? cs.player1, 'bf'),
			player2:     _str(cs.opponent ?? cs.player2, 'dad'),
			gfVersion:   _str(cs.gf       ?? cs.gfVersion ?? cs.player3, 'gf'),
			characters:  null,
			strumsGroups: null,
			events:      []
		};

		// ── Notes ─────────────────────────────────────────────────────────────
		// CNE can store notes either as:
		//   a) An Object with difficulty keys: { "easy": [...], "hard": [...] }
		//   b) A plain Array (same as base-game / legacy)
		final notesField = cs.notes;
		var sections:Array<Dynamic> = [];

		if (notesField != null)
		{
			if (Std.isOfType(notesField, Array))
			{
				// Already a flat array — treat as base-game format
				sections = cast notesField;
			}
			else
			{
				// Object with difficulty keys — pick requested diff or first available
				var picked:Array<Dynamic> = null;
				final tryDiffs = [difficulty, 'hard', 'normal', 'easy'];
				for (d in tryDiffs)
				{
					final v = Reflect.field(notesField, d);
					if (v != null && Std.isOfType(v, Array))
					{
						picked = cast v;
						trace('[CodenameConverter] Using difficulty key "$d"');
						break;
					}
				}
				if (picked == null)
				{
					// Grab whatever first field is there
					final fields = Reflect.fields(notesField);
					if (fields.length > 0)
					{
						final v = Reflect.field(notesField, fields[0]);
						if (Std.isOfType(v, Array)) picked = cast v;
					}
				}
				sections = picked ?? [];
			}
		}

		// ── CNE 1.6: strumLines-based notes (no "notes" field) ────────────────
		// When the chart uses the new strumLines format, extract notes directly
		// and build legacy SwagSection objects the engine can consume.
		if (sections.length == 0 && cs.strumLines != null && Std.isOfType(cs.strumLines, Array))
		{
			final strumLines:Array<Dynamic> = cast cs.strumLines;

			// Read characters from strumLines
			for (sl in strumLines)
			{
				final slType = Std.int(_float(sl.type, -1));
				final chars:Array<Dynamic> = (sl.characters != null && Std.isOfType(sl.characters, Array))
					? cast sl.characters : [];
				if (chars.length == 0) continue;
				final name = Std.string(chars[0]);
				switch (slType)
				{
					case 1: song.player1 = name;
					case 0: song.player2 = name;
					case 2: song.gfVersion = name;
					default:
				}
			}

			// Collect all notes into one flat SwagSection per 16 steps
			// (avoids empty-section issues when note times are spread across the song)
			final allNotes:Array<Dynamic> = [];
			var maxTimeMs:Float = 0;

			for (sl in strumLines)
			{
				final slType = Std.int(_float(sl.type, -1));
				if (slType == 2) continue;               // spectator — no playable notes
				final mustHit = (slType == 1);           // type 1 = player → mustHitSection
				final colOffset = mustHit ? 0 : 4;      // type 0 = opponent → cols 4-7

				final rawNotes:Array<Dynamic> = (sl.notes != null && Std.isOfType(sl.notes, Array))
					? cast sl.notes : [];

				for (n in rawNotes)
				{
					final t   = _float(n.time, 0);
					final id  = Std.int(_float(n.id, 0)) % 4;
					final len = _float(n.sLen, 0);
					if (t > maxTimeMs) maxTimeMs = t;
					allNotes.push({ time: t, data: colOffset + id, length: len, mustHit: mustHit });
				}
			}

			// Sort by time and distribute into sections (one section = 16 steps @ current bpm)
			allNotes.sort((a, b) -> Std.int(a.time - b.time));

			final msPerStep = (60000 / song.bpm) / 4;
			final stepsPerSection = 16;
			final msPerSection = msPerStep * stepsPerSection;
			final sectionCount = Math.max(1, Math.ceil((maxTimeMs + msPerSection) / msPerSection));

			// Pre-build sections
			final sectionsArr:Array<SwagSection> = [];
			for (i in 0...Std.int(sectionCount))
			{
				sectionsArr.push({
					sectionNotes: [],
					lengthInSteps: stepsPerSection,
					typeOfSection: 0,
					mustHitSection: true,
					bpm: song.bpm,
					changeBPM: false,
					altAnim: false
				});
			}

			for (n in allNotes)
			{
				final secIndex = Std.int(n.time / msPerSection);
				if (secIndex < 0 || secIndex >= sectionsArr.length) continue;
				sectionsArr[secIndex].sectionNotes.push([n.time, n.data, n.length]);
				// If any note in this section is opponent-side, track mustHit accordingly
				if (!n.mustHit) sectionsArr[secIndex].mustHitSection = false;
			}

			for (sec in sectionsArr)
				song.notes.push(sec);
		}
		else
		{
			// Legacy CNE/Cool format: convert existing sections
			for (sec in sections)
				song.notes.push(_convertSection(sec, song.bpm));
		}

		// ── Events ────────────────────────────────────────────────────────────
		// CNE events: Array<{ time:Float, name:String, params:Array<Dynamic> }>
		final cneEvents:Array<Dynamic> = (cs.events != null && Std.isOfType(cs.events, Array))
			? cast cs.events : [];

		for (ev in cneEvents)
		{
			final timeMs:Float          = _float(ev.time, 0);
			final stepTime:Float        = _msToStep(timeMs, song.bpm);
			final params:Array<Dynamic> = (ev.params != null && Std.isOfType(ev.params, Array))
				? cast ev.params : [];

			final coolType  = _mapEventType(_str(ev.name, ''));
			final coolValue = _mapEventValue(_str(ev.name, ''), params);

			song.events.push({
				stepTime: stepTime,
				type:     coolType,
				value:    coolValue
			});
		}

		// ── Characters & strums ───────────────────────────────────────────────
		_buildCharactersFromLegacy(song);

		trace('[CodenameConverter] Done. Sections: ${song.notes.length}, Events: ${song.events.length}');
		return song;
	}

	// ─── Character ────────────────────────────────────────────────────────────

	/**
	 * Converts a raw Codename Engine character JSON string into a Cool Engine
	 * CharacterData-compatible Dynamic object.
	 */
	public static function convertCharacter(rawJson:String, charName:String):Dynamic
	{
		trace('[CodenameConverter] Converting character "$charName"...');

		final c:Dynamic = Json.parse(rawJson);

		// ── Animations ────────────────────────────────────────────────────────
		// CNE: { name, anim, fps, loop, offset:[x,y] }
		// Cool: { name, prefix, framerate, looped, offsetX, offsetY, indices }
		final anims:Array<Dynamic> = [];
		if (c.animations != null && Std.isOfType(c.animations, Array))
		{
			final cneAnims:Array<Dynamic> = cast c.animations;
			for (ca in cneAnims)
			{
				final offset:Array<Dynamic> = (ca.offset != null && Std.isOfType(ca.offset, Array))
					? cast ca.offset : [0, 0];

				final indices:Array<Int> = (ca.indices != null && Std.isOfType(ca.indices, Array)
					&& (cast ca.indices:Array<Dynamic>).length > 0)
					? cast ca.indices : null;

				anims.push({
					// CNE "name" = internal anim name, "anim" = XML prefix
					name:      _str(ca.name,  'idle'),
					prefix:    _str(ca.anim ?? ca.prefix, 'idle'),
					framerate: _float(ca.fps, 24),
					looped:    _bool(ca.loop ?? ca.looped, false),
					offsetX:   offset.length > 0 ? _float(offset[0], 0) : 0.0,
					offsetY:   offset.length > 1 ? _float(offset[1], 0) : 0.0,
					indices:   indices
				});
			}
		}

		// ── Color [R,G,B] → "#RRGGBB" ─────────────────────────────────────────
		var healthBarColor:String = '#31B0D1';
		if (c.color != null && Std.isOfType(c.color, Array))
		{
			final rgb:Array<Dynamic> = cast c.color;
			if (rgb.length >= 3)
			{
				final r = Std.int(_float(rgb[0], 49));
				final g = Std.int(_float(rgb[1], 176));
				final b = Std.int(_float(rgb[2], 209));
				healthBarColor = '#' + _hex2(r) + _hex2(g) + _hex2(b);
			}
		}

		// ── Camera offset ─────────────────────────────────────────────────────
		var camOffset:Array<Float> = [0.0, 0.0];
		if (c.cameraOffset != null && Std.isOfType(c.cameraOffset, Array))
		{
			final co:Array<Dynamic> = cast c.cameraOffset;
			camOffset = [_float(co[0], 0), _float(co[1], 0)];
		}

		// ── Build Cool Engine CharacterData ───────────────────────────────────
		final coolChar:Dynamic = {
			// CNE uses "asset", e.g. "characters/bf"  →  strip prefix
			path:           _normalizePath(_str(c.asset ?? c.image, 'characters/$charName')),
			animations:     anims,
			isPlayer:       _bool(c.isPlayer, false),
			antialiasing:   _bool(c.antialiasing, true),
			scale:          _float(c.scale, 1),
			flipX:          _bool(c.flipX ?? c.flip_x, false),
			healthIcon:     _str(c.icon ?? c.healthicon, charName),
			healthBarColor: healthBarColor,
			cameraOffset:   camOffset
		};

		trace('[CodenameConverter] Character "$charName" done. Anims: ${anims.length}');
		return coolChar;
	}

	// ─── Helpers ─────────────────────────────────────────────────────────────

	static function _convertSection(sec:Dynamic, defaultBpm:Float):SwagSection
	{
		// CNE sections have essentially the same structure as base-game sections
		return {
			sectionNotes:   _convertNotes(sec.sectionNotes),
			lengthInSteps:  Std.int(_float(sec.lengthInSteps, 16)),
			typeOfSection:  0,
			mustHitSection: _bool(sec.mustHitSection, true),
			bpm:            _float(sec.bpm, defaultBpm),
			changeBPM:      _bool(sec.changeBPM, false),
			altAnim:        _bool(sec.altAnim, false),
			gfSing:         _bool(sec.gfSection ?? sec.gfSing, false)
		};
	}

	static function _convertNotes(raw:Dynamic):Array<Dynamic>
	{
		final out:Array<Dynamic> = [];
		if (raw == null || !Std.isOfType(raw, Array)) return out;
		final arr:Array<Dynamic> = cast raw;
		for (n in arr)
		{
			if (!Std.isOfType(n, Array)) continue;
			final note:Array<Dynamic> = cast n;
			out.push([
				_float(note[0], 0),
				Std.int(_float(note[1], 0)),
				_float(note[2], 0)
			]);
		}
		return out;
	}

	/** Maps CNE event names → Cool Engine types. */
	static function _mapEventType(cneName:String):String
	{
		return switch (cneName.toLowerCase())
		{
			case 'camera move', 'focus on', 'camera follow':
				'Camera';
			case 'change bpm', 'bpm change':
				'BPM Change';
			case 'play animation', 'play anim':
				'Play Anim';
			case 'alt anim', 'alt animation':
				'Alt Anim';
			case 'camera zoom', 'zoom camera':
				'Camera Zoom';
			default:
				cneName;
		};
	}

	static function _mapEventValue(cneName:String, params:Array<Dynamic>):String
	{
		final p0 = params.length > 0 ? _str(params[0], '') : '';
		final p1 = params.length > 1 ? _str(params[1], '') : '';

		return switch (cneName.toLowerCase())
		{
			case 'camera move', 'focus on', 'camera follow':
				// CNE usually passes "dad", "bf", "gf"
				p0.toLowerCase();
			default:
				p0 != '' ? p0 : p1;
		};
	}

	static function _buildCharactersFromLegacy(song:SwagSong):Void
	{
		if (song.characters != null && song.characters.length > 0) return;

		song.characters = [
			{ name: song.gfVersion ?? 'gf',  x: 0.0, y: 0.0, visible: true, type: 'Girlfriend' },
			{ name: song.player2   ?? 'dad', x: 0.0, y: 0.0, visible: true, type: 'Opponent'   },
			{ name: song.player1   ?? 'bf',  x: 0.0, y: 0.0, visible: true, type: 'Player'     }
		];

		song.strumsGroups = [
			{ id: 'cpu_strums_0',    x: 100.0, y: 50.0, visible: true, cpu: true,  spacing: 110.0 },
			{ id: 'player_strums_0', x: 740.0, y: 50.0, visible: true, cpu: false, spacing: 110.0 }
		];
	}

	static inline function _msToStep(ms:Float, bpm:Float):Float
		return (ms / 1000) * (bpm / 60) * 4;

	static function _normalizePath(path:String):String
	{
		if (path.startsWith('characters/')) return path.substr('characters/'.length);
		if (path.startsWith('chars/'))      return path.substr('chars/'.length);
		return path;
	}

	static inline function _str(v:Dynamic, def:String):String
		return (v != null) ? Std.string(v) : def;

	static inline function _float(v:Dynamic, def:Float):Float
	{
		if (v == null) return def;
		final f = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? def : f;
	}

	static inline function _bool(v:Dynamic, def:Bool):Bool
		return (v != null) ? (v == true) : def;

	static function _hex2(n:Int):String
	{
		final h = StringTools.hex(n & 0xFF, 2);
		return h.length < 2 ? '0$h' : h;
	}
}
