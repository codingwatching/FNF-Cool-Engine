package funkin.gameplay;

/**
 * Datos de un rating individual.
 * Todos los campos son primitivas para minimizar allocations.
 */
typedef RatingData = {
	var name:String;
	/** Ventana de timing superior (ms, exclusiva). */
	var window:Float;
	/** Puntos que otorga. */
	var score:Int;
	/** Contribución to the accuracy (0.0–1.0). */
	var accuracyWeight:Float;
	/** Modificador de salud. */
	var health:Float;
	/** Si true, resetea el combo. */
	var breakCombo:Bool;
	/** If false, no muestra popup of rating (useful for "perfect" silencioso, etc.). */
	var ?showPopup:Bool;

	// ── Display config por rating ─────────────────────────────────────────────
	/** Offset X adicional para el sprite de rating (sumado al base global). */
	var ?displayOffsetX:Float;
	/** Offset Y adicional para el sprite de rating (sumado al base global). */
	var ?displayOffsetY:Float;
	/** Escala del sprite de rating (null = usa el valor global). */
	var ?displayScale:Float;
	/**
	 * Ruta del sprite custom para este rating (null = usa "UI/normal/score/{name}" o el prefijo global).
	 * Ejemplo: "UI/pixel/score/sick" para usar un sprite de pixel art.
	 */
	var ?spritePath:Null<String>;
	/** If false, no muestra the numbers of combo with this rating. Null = usar value global. */
	var ?showCombo:Null<Bool>;
	/** Offset X adicional for the numbers of combo of this rating. */
	var ?comboOffsetX:Float;
	/** Offset and adicional for the numbers of combo of this rating. */
	var ?comboOffsetY:Float;
}

/**
 * Configuration of display of the popup of ratings.
 * Se carga desde `ratings_display.json` (en paralelo a `ratings.json`).
 *
 * Estructura del JSON:
 * {
 *   "baseX": 0,               // X base de todos los ratings (relativo al centro de pantalla)
 *   "baseY": -60,             // Y base
 *   "comboBaseX": 0,          // X base of the numbers of combo
 *   "comboBaseY": 80,         // and base of the numbers of combo
 *   "ratingScale": 0.785,     // Escala global de sprites de rating
 *   "comboScale": 0.6,        // Scales global of numbers of combo
 *   "spritePrefix": "",       // Prefijo para las rutas de sprite (e.g. "pixel/")
 *   "spriteSuffix": "",       // Sufijo (e.g. "-hd")
 *   "numPrefix": "num",       // Prefix of the numbers of combo
 *   "numSuffix": "",          // Suffix of the numbers of combo
 *   "antialiasing": true,     // Antialiasing global (false para pixel art)
 *   "showCombo": true,        // Show numbers of combo by default
 *   "animDuration": 0.2,      // Duration of the fade-out of the sprites
 *   "characters": {           // Overrides por personaje (por nombre de personaje)
 *     "bf-pixel": {
 *       "baseX": 5, "baseY": -55,
 *       "spritePrefix": "pixel/", "antialiasing": false
 *     }
 *   }
 * }
 */
typedef RatingDisplayConfig = {
	/** X base de todos los sprites de rating (relativo al centro de pantalla). */
	var ?baseX:Float;
	/** Y base. */
	var ?baseY:Float;
	/** X base of the numbers of combo. */
	var ?comboBaseX:Float;
	/** and base of the numbers of combo. */
	var ?comboBaseY:Float;
	/** Escala global de sprites de rating. */
	var ?ratingScale:Float;
	/** Scales global of numbers of combo. */
	var ?comboScale:Float;
	/** Prefijo global para rutas de sprite. E.g. "pixel/" para usar sprites de pixel art. */
	var ?spritePrefix:String;
	/** Sufijo global para rutas de sprite. E.g. "-hd". */
	var ?spriteSuffix:String;
	/** Prefix of the numbers of combo. Default: "num". */
	var ?numPrefix:String;
	/** Suffix of the numbers of combo. Default: "". */
	var ?numSuffix:String;
	/** Antialiasing global. false = pixel art. */
	var ?antialiasing:Bool;
	/** Show numbers of combo by default. */
	var ?showCombo:Bool;
	/** Duration of the tween of desvanecimiento (segundos). */
	var ?animDuration:Float;
	/**
	 * Overrides por nombre de personaje.
	 * La clave es el nombre del personaje (e.g. "bf", "bf-pixel", "gf").
	 * Los campos coinciden con los de RatingDisplayConfig (sin este campo).
	 */
	var ?characters:Dynamic;
}

/**
 * RatingManager — Sistema de ratings y display completamente softcodeado.
 *
 * ═══════════════════════════════════════════════════════════════
 *  RATINGS (ventanas de timing, puntos, health)
 * ═══════════════════════════════════════════════════════════════
 * Jerarquía of load (first encontrada gana):
 *   1. mods/{mod}/data/songs/{song}/ratings.json
 *   2. mods/{mod}/data/ratings.json
 *   3. assets/data/songs/{song}/ratings.json
 *   4. assets/data/ratings.json
 *   5. Defaults hardcoded (FNF vanilla)
 *
 * ═══════════════════════════════════════════════════════════════
 *  DISPLAY CONFIG (offsets, escala, sprites, personajes)
 * ═══════════════════════════════════════════════════════════════
 * Jerarquía of load:
 *   1. mods/{mod}/data/songs/{song}/ratings_display.json
 *   2. mods/{mod}/data/ratings_display.json
 *   3. assets/data/songs/{song}/ratings_display.json
 *   4. assets/data/ratings_display.json
 *   5. Defaults internos
 *
 * For a character specific: add in "characters" of the JSON with the nombre exacto
 * del personaje (e.g. "bf-pixel", "pico"). Los campos del override se fusionan
 * encima de la config global.
 *
 * Los scripts de HUD pueden acceder a la config via:
 *   var cfg = RatingManager.getDisplayConfig();
 *   var cfgForChar = RatingManager.getDisplayConfigForChar("bf-pixel");
 */
class RatingManager
{
	// ── Defaults (FNF vanilla) ────────────────────────────────────────────────
	static final DEFAULTS:Array<RatingData> = [
		{ name: 'sick',  window: 45.0,  score: 350, accuracyWeight: 1.00, health:  0.10, breakCombo: false, showPopup: true },
		{ name: 'good',  window: 90.0,  score: 200, accuracyWeight: 0.75, health:  0.05, breakCombo: false, showPopup: true },
		{ name: 'bad',   window: 135.0, score: 100, accuracyWeight: 0.50, health: -0.03, breakCombo: false, showPopup: true },
		{ name: 'shit',  window: 166.0, score:  50, accuracyWeight: 0.25, health: -0.03, breakCombo: true,  showPopup: true },
	];

	/** Display config por defecto (usada si no hay JSON). */
	static final DEFAULT_DISPLAY:RatingDisplayConfig = {
		baseX:        0.0,
		baseY:        -60.0,
		comboBaseX:   0.0,
		comboBaseY:   80.0,
		ratingScale:  0.785,
		comboScale:   0.6,
		spritePrefix: '',
		spriteSuffix: '',
		numPrefix:    'num',
		numSuffix:    '',
		antialiasing: true,
		showCombo:    true,
		animDuration: 0.2,
		characters:   null,
	};

	/** Lista activa de ratings, ordenada por window ascendente. */
	public static var ratings:Array<RatingData> = [];

	/** Nombre del rating "top" (menor window). Cacheado para isSickMode(). */
	public static var topRatingName:String = 'sick';

	/** Window maximum valid. Notes with diff > this are miss. */
	public static var missWindow:Float = 166.0;

	/** Lookup O(1) por nombre. */
	static var _byName:Map<String, RatingData> = new Map();

	static var _initialized:Bool = false;

	/** Config de display cargada (mezcla global + defaults). */
	static var _displayConfig:Null<RatingDisplayConfig> = null;

	// ────────────────────────────────────────────────────────────────────────

	/** Inicializar con defaults. Ignorado si ya fue llamado. */
	public static inline function init():Void
		if (!_initialized) { _load(null); _initialized = true; }

	/**
	 * Recargar ratings for a song specific.
	 * Callr in PlayState.create() pasando the nombre of the song.
	 */
	public static function reload(?songName:String):Void
	{
		_initialized = false;
		_load(songName != null ? songName.toLowerCase() : null);
		_initialized = true;
	}

	/** Limpiar al destruir PlayState. */
	public static function destroy():Void
	{
		ratings = [];
		_byName.clear();
		_displayConfig = null;
		_initialized = false;
	}

	// ── Lookup ────────────────────────────────────────────────────────────────

	/**
	 * Devuelve el RatingData para una diferencia de timing dada.
	 * Retorna null si noteDiff > missWindow (= miss, manejar externamente).
	 */
	public static function getRating(noteDiff:Float):Null<RatingData>
	{
		for (r in ratings)
			if (noteDiff <= r.window)
				return r;
		return null;
	}

	/** Lookup O(1) por nombre. */
	public static inline function getByName(name:String):Null<RatingData>
		return _byName.get(name);

	/** true if the rating muestra popup (default true if the field no is definido). */
	public static inline function showsPopup(r:RatingData):Bool
		return r.showPopup != false;

	// ── Display Config API ────────────────────────────────────────────────────

	/**
	 * Devuelve la config de display global (con defaults aplicados).
	 * Los scripts de HUD deben usar esto para posicionar los sprites.
	 */
	public static function getDisplayConfig():RatingDisplayConfig
	{
		if (_displayConfig == null)
			return DEFAULT_DISPLAY;
		return _displayConfig;
	}

	/**
	 * Returns the config of display fusionada for a character specific.
	 * Si el personaje no tiene override, devuelve la config global.
	 *
	 * Ejemplo de uso en HUD script:
	 *   var cfg = RatingManager.getDisplayConfigForChar(PlayState.SONG.player1);
	 *   rating.x = FlxG.width * 0.35 + cfg.baseX;
	 *   rating.y = FlxG.height * 0.5 + cfg.baseY;
	 */
	public static function getDisplayConfigForChar(?charName:String):RatingDisplayConfig
	{
		var base = getDisplayConfig();
		if (charName == null || base.characters == null)
			return base;

		var overrideState:Dynamic = Reflect.field(base.characters, charName);
		if (overrideState == null)
			return base;

		// Fusionar override encima de la base
		return _mergeDisplayConfig(base, overrideState);
	}

	/**
	 * Devuelve la ruta de sprite para un rating dado el config activo.
	 * Respeta `ratingData.spritePath` if is definido, sino construye
	 * con el prefijo/sufijo del displayConfig.
	 *
	 * Ejemplo: si spritePrefix="pixel/" y name="sick" → "pixel/sick"
	 */
	public static function getSpritePathForRating(r:RatingData, ?charName:String):String
	{
		// The rating tiene a path custom explicit
		if (r.spritePath != null && r.spritePath.length > 0)
			return r.spritePath;

		var cfg = getDisplayConfigForChar(charName);
		var prefix = (cfg.spritePrefix != null) ? cfg.spritePrefix : '';
		var suffix = (cfg.spriteSuffix != null) ? cfg.spriteSuffix : '';
		return '${prefix}${r.name}${suffix}';
	}

	/**
	 * Returns the path of sprite for a number of combo dado the config active.
	 * Ejemplo: numPrefix="num", numSuffix="" y digit=5 → "num5"
	 */
	public static function getNumSpritePath(digit:Int, ?charName:String):String
	{
		var cfg = getDisplayConfigForChar(charName);
		var prefix = (cfg.numPrefix != null) ? cfg.numPrefix : 'num';
		var suffix = (cfg.numSuffix != null) ? cfg.numSuffix : '';
		return '${prefix}${digit}${suffix}';
	}

	// ── Carga interna ─────────────────────────────────────────────────────────

	static function _load(?songName:String):Void
	{
		ratings = [];
		_byName.clear();
		_displayConfig = null;

		var raw:Null<String>     = null;
		var rawDisplay:Null<String> = null;

		#if sys
		var candidates:Array<String> = [];
		var candidatesDisplay:Array<String> = [];

		if (mods.ModManager.isActive())
		{
			var modRoot = mods.ModManager.modRoot();
			if (songName != null)
			{
				candidates.push('$modRoot/data/songs/$songName/ratings.json');
				candidatesDisplay.push('$modRoot/data/songs/$songName/ratings_display.json');
			}
			candidates.push('$modRoot/data/ratings.json');
			candidatesDisplay.push('$modRoot/data/ratings_display.json');
		}
		if (songName != null)
		{
			candidates.push('assets/data/songs/$songName/ratings.json');
			candidatesDisplay.push('assets/data/songs/$songName/ratings_display.json');
		}
		candidates.push('assets/data/ratings.json');
		candidatesDisplay.push('assets/data/ratings_display.json');

		// Cargar ratings.json
		for (path in candidates)
		{
			if (sys.FileSystem.exists(path))
			{
				try   { raw = sys.io.File.getContent(path); trace('[RatingManager] Cargando $path'); break; }
				catch (e:Dynamic) { trace('[RatingManager] Error leyendo $path: $e'); }
			}
		}

		// Cargar ratings_display.json
		for (path in candidatesDisplay)
		{
			if (sys.FileSystem.exists(path))
			{
				try   { rawDisplay = sys.io.File.getContent(path); trace('[RatingManager] Display config: $path'); break; }
				catch (e:Dynamic) { trace('[RatingManager] Error leyendo $path: $e'); }
			}
		}
		#end

		// ── Parsear ratings ───────────────────────────────────────────────
		if (raw != null)
		{
			try
			{
				var parsed:Array<Dynamic> = haxe.Json.parse(raw);
				for (r in parsed)
				{
					if (r.name == null || r.window == null) continue;
					ratings.push({
						name:           Std.string(r.name),
						window:         r.window,
						score:          r.score   != null ? Std.int(r.score)   : 0,
						accuracyWeight: r.accuracyWeight != null ? r.accuracyWeight : 1.0,
						health:         r.health  != null ? r.health  : 0.0,
						breakCombo:     r.breakCombo == true,
						showPopup:      r.showPopup  != false,
						// Display fields
						displayOffsetX: r.displayOffsetX != null ? r.displayOffsetX : 0.0,
						displayOffsetY: r.displayOffsetY != null ? r.displayOffsetY : 0.0,
						displayScale:   r.displayScale,
						spritePath:     r.spritePath,
						showCombo:      r.showCombo,
						comboOffsetX:   r.comboOffsetX != null ? r.comboOffsetX : 0.0,
						comboOffsetY:   r.comboOffsetY != null ? r.comboOffsetY : 0.0,
					});
				}
				trace('[RatingManager] ${ratings.length} ratings cargados desde JSON');
			}
			catch (e:Dynamic)
			{
				trace('[RatingManager] Invalid JSON: $e — usando defaults');
				ratings = [];
			}
		}

		// Fallback to defaults if no is cargó nothing
		if (ratings.length == 0)
		{
			for (r in DEFAULTS) ratings.push(r);
			trace('[RatingManager] Usando ${ratings.length} ratings por defecto');
		}

		// Ordenar ascendente por window
		ratings.sort((a, b) -> {
			if (a.window < b.window) return -1;
			if (a.window > b.window) return  1;
			return 0;
		});

		for (r in ratings)
			_byName.set(r.name, r);

		topRatingName = ratings.length > 0 ? ratings[0].name : 'sick';
		missWindow    = ratings.length > 0 ? ratings[ratings.length - 1].window : 166.0;

		// ── Parsear display config ────────────────────────────────────────
		if (rawDisplay != null)
		{
			try
			{
				var parsed:Dynamic = haxe.Json.parse(rawDisplay);
				// Fusionar con los defaults internos
				_displayConfig = _mergeDisplayConfig(DEFAULT_DISPLAY, parsed);
				trace('[RatingManager] Display config cargada desde JSON');
			}
			catch (e:Dynamic)
			{
				trace('[RatingManager] JSON of display invalid: $and — usando defaults');
				_displayConfig = DEFAULT_DISPLAY;
			}
		}
		else
		{
			_displayConfig = DEFAULT_DISPLAY;
		}
	}

	/**
	 * Fusiona los campos de `override` encima de `base`.
	 * Solo sobreescribe campos presentes y no-null en `override`.
	 */
	static function _mergeDisplayConfig(base:RatingDisplayConfig, overrideState:Dynamic):RatingDisplayConfig
	{
		// Usamos Dynamic para leer campos opcionales del override
		inline function _f(field:String, fallback:Float):Float
		{
			var v = Reflect.field(overrideState, field);
			return (v != null) ? v : Reflect.field(base, field) ?? fallback;
		}
		inline function _b(field:String, fallback:Bool):Bool
		{
			var v = Reflect.field(overrideState, field);
			return (v != null) ? v : Reflect.field(base, field) ?? fallback;
		}
		inline function _s(field:String, fallback:String):String
		{
			var v = Reflect.field(overrideState, field);
			return (v != null) ? Std.string(v) : (Reflect.field(base, field) ?? fallback);
		}

		// El campo "characters" del resultado es siempre el del base global
		// (no se anidan overrides de personaje dentro de overrides de personaje)
		var chars = base.characters;

		return {
			baseX:        _f('baseX',        0.0),
			baseY:        _f('baseY',        -60.0),
			comboBaseX:   _f('comboBaseX',   0.0),
			comboBaseY:   _f('comboBaseY',   80.0),
			ratingScale:  _f('ratingScale',  0.785),
			comboScale:   _f('comboScale',   0.6),
			spritePrefix: _s('spritePrefix', ''),
			spriteSuffix: _s('spriteSuffix', ''),
			numPrefix:    _s('numPrefix',    'num'),
			numSuffix:    _s('numSuffix',    ''),
			antialiasing: _b('antialiasing', true),
			showCombo:    _b('showCombo',    true),
			animDuration: _f('animDuration', 0.2),
			characters:   chars,
		};
	}
}
