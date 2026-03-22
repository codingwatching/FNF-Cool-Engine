package funkin.gameplay.notes;

import extensions.FlxAtlasFramesExt;
import lime.utils.Assets;
import funkin.gameplay.PlayState;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import openfl.display.BitmapData;
import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

// ==================== TYPEDEFS ====================

/**
 * Definition of texture of skin.
 *
 * Para type "sparrow": usa path.xml (Sparrow Atlas).
 * Para type "packer":  usa path.txt (TexturePacker).
 * For type "image":   use path.png dividido in frames of frameWidth×frameHeight pixels.
 *                      The number of filas/columnas is calcula automatically.
 */
typedef NoteSkinTexture =
{
	var path:String;
	/**
	 * Tipo de carga de textura:
	 *   "sparrow"      — Sparrow Atlas (.xml)                  [default]
	 *   "packer"       — TexturePacker (.txt)
	 *   "image"        — PNG dividido en frames (frameWidth×frameHeight)
	 *   "funkinsprite" — Adobe Animate Texture Atlas (FunkinSprite / flxanimate)
	 *                    path apunta a la CARPETA que contiene Animation.json
	 */
	var ?type:String;
	var ?frameWidth:Int;  // solo para type "image"
	var ?frameHeight:Int; // solo para type "image"
	var ?scale:Float;         // escala del sprite (default: 1.0)
	var ?antialiasing:Bool;   // default: true (false para pixel)
}

/**
 * Definition of a animation individual.
 *
 * Formatos aceptados en el JSON:
 *   String shorthand:   "purple0"
 *   Objeto prefix:      {"prefix": "purple0"}
 *   Objeto prefix+fps:  {"prefix": "purple0", "framerate": 12}
 *   Objeto indices:     {"indices": [4]}
 *   Objeto multi-frame: {"indices": [12, 16], "framerate": 24}
 *   Objeto con loop:    {"indices": [0, 1, 2], "framerate": 12, "loop": true}
 */
typedef NoteAnimDef =
{
	var ?prefix:String;
	var ?indices:Array<Int>;
	var ?framerate:Int;
	var ?loop:Bool;
	/**
	 * Offset [x, and] appliesdo to the strum when this animation is active.
	 * Solo relevante para animaciones de strum (pressed / confirm).
	 * Optional — if is ausente, is usan the defaults of the engine.
	 *
	 * Ejemplo en skin.json:
	 *   "strumLeftConfirm": { "prefix": "left confirm", "offset": [-13, -13] }
	 *   "strumLeftPress":   { "prefix": "left press",   "offset": [0, -5] }
	 */
	var ?offset:Array<Float>;
}

/**
 * Todas las animaciones de una skin.
 *
 * Los campos son Dynamic para aceptar tanto el String shorthand como el
 * objeto NoteAnimDef completo. El helper addAnimToSprite() maneja ambos.
 *
 * Separation logic:
 *   Notas (Scroll): left, down, up, right
 *   Hold pieces:    leftHold, downHold, upHold, rightHold
 *   Hold tails:     leftHoldEnd, downHoldEnd, upHoldEnd, rightHoldEnd
 *   Strum static:   strumLeft/Down/Up/Right
 *   Strum pressed:  strumLeft/Down/Up/RightPress
 *   Strum confirm:  strumLeft/Down/Up/RightConfirm
 */
typedef NoteSkinAnims =
{
	var ?left:Dynamic;
	var ?down:Dynamic;
	var ?up:Dynamic;
	var ?right:Dynamic;
	var ?leftHold:Dynamic;
	var ?downHold:Dynamic;
	var ?upHold:Dynamic;
	var ?rightHold:Dynamic;
	var ?leftHoldEnd:Dynamic;
	var ?downHoldEnd:Dynamic;
	var ?upHoldEnd:Dynamic;
	var ?rightHoldEnd:Dynamic;
	var ?strumLeft:Dynamic;
	var ?strumDown:Dynamic;
	var ?strumUp:Dynamic;
	var ?strumRight:Dynamic;
	var ?strumLeftPress:Dynamic;
	var ?strumDownPress:Dynamic;
	var ?strumUpPress:Dynamic;
	var ?strumRightPress:Dynamic;
	var ?strumLeftConfirm:Dynamic;
	var ?strumDownConfirm:Dynamic;
	var ?strumUpConfirm:Dynamic;
	var ?strumRightConfirm:Dynamic;
}

// Compatibility alias — code that used NoteAnimations still compiles
typedef NoteAnimations = NoteSkinAnims;

/**
 * Datos completos de una skin de notas.
 *
 * La skin pixel y la skin normal son ENTIDADES COMPLETAMENTE INDEPENDIENTES.
 * No there is none logic hardcodeada of "school → pixel". In its lugar:
 *   - Crea una skin con isPixel:true y sus texturas/animaciones propias
 *   - Registra what stage the use with NoteSkinSystem.registerStageSkin(stage, skinName)
 *   - O llama NoteSkinSystem.setTemporarySkin(skinName) desde tu PlayState/Stage
 *
 * Campos clave:
 *   texture:      textura de notas (cabeza) y strums
 *   holdTexture:  textura de sustain pieces + tails (null → usa texture)
 *   isPixel:      activa modo pixel (antialiasing false por defecto)
 *   confirmOffset: aplica offset -13,-13 al strum confirm (default: true)
 *   sustainOffset: offset X extra para notas sustain (default: 0; pixel usa 30)
 *   holdStretch:  multiplicador de scale.y en hold chain (default: 1.0; pixel usa 1.19)
 *   animations:   todas las anims de notas + strums, usando NoteAnimDef
 */
typedef NoteSkinData =
{
	var name:String;
	var ?author:String;
	var ?description:String;
	var ?folder:String;
	// ── Texturas ────────────────────────────────────────────────────────
	/**
	 * texture      — textura principal (notas normales + strums).
	 *               Usada para notas normales cuando notesTexture es null,
	 *               y para strums cuando strumsTexture es null.
	 * strumsTexture  — textura SOLO para los strums (opcional).
	 *               Si es null, se usa texture.
	 * notesTexture   — textura SOLO para las notas que bajan (cabezas, scroll) (opcional).
	 *               Si es null, se usa texture.
	 * holdTexture    — textura para sustain pieces + tails (opcional).
	 *               Si es null, se usa texture (o notesTexture si se define).
	 *
	 * Soporta type:"funkinsprite" en cualquiera de ellas para usar Adobe Animate Atlas.
	 */
	var texture:NoteSkinTexture;
	var ?strumsTexture:NoteSkinTexture;  // solo strums  (null → usa texture)
	var ?notesTexture:NoteSkinTexture;   // solo notas scroll (null → usa texture)
	var ?holdTexture:NoteSkinTexture;    // sustain pieces + tails (null → usa texture)
	// ── Flags y ajustes ───────────────────────────────────────────────
	var ?isPixel:Bool;
	var ?confirmOffset:Bool; // default: true — aplica offset -13,-13 a todos los confirms si no tienen offset propio
	var ?offsetDefault:Bool; // alias legacy de confirmOffset
	var ?sustainOffset:Float; // default: 0.0
	var ?holdStretch:Float; // default: 1.0
	// ── Animaciones ───────────────────────────────────────────────────
	var animations:NoteSkinAnims;
}

// ── Splash (sistema independiente, no cambia) ─────────────────────────────────

typedef NoteSplashData =
{
	var name:String;
	var author:String;
	var ?description:String;
	var ?folder:String;
	var assets:NoteSplashAssets;
	var animations:SplashAnimations;
	/** Configuration of the hold covers. Null = usar defaults hardcodeados. */
	var ?holdCover:NoteHoldCoverData;
}

typedef NoteSplashAssets =
{
	var path:String;
	var ?type:String;
	var ?scale:Float;
	var ?antialiasing:Bool;
	var ?offset:Array<Float>;
}

typedef SplashAnimations =
{
	var left:Array<String>;
	var down:Array<String>;
	var up:Array<String>;
	var right:Array<String>;
	var ?framerate:Int;
	var ?randomFramerateRange:Int;
}

/**
 * Datos of configuration for the hold covers (animations of splash largo).
 *
 * Viven dentro del splash.json en el campo "holdCover".
 * Todos los campos son opcionales — los valores por defecto reproducen
 * el comportamiento original hardcodeado, manteniendo compatibilidad total.
 *
 * Ejemplo en splash.json:
 * {
 *   "holdCover": {
 *     "texturePrefix": "holdCover",
 *     "perColorTextures": true,
 *     "textureType": "sparrow",
 *     "scale": 1.0,
 *     "antialiasing": true,
 *     "framerate": 24,
 *     "loopFramerate": 48,
 *     "offset": [0, 0],
 *     "startPrefix": "holdCoverStart",
 *     "loopPrefix":  "holdCover",
 *     "endPrefix":   "holdCoverEnd"
 *   }
 * }
 *
 * Con perColorTextures:true (default), se carga {texturePrefix}{Color}.png
 * for each direction (e.g. holdCoverPurple.png, holdCoverBlue.png…).
 * Con perColorTextures:false, se carga {texturePrefix}.png — atlas compartido.
 *
 * The prefijos of animation always reciben the nombre of the color as suffix:
 *   startPrefix="holdCoverStart" → "holdCoverStartPurple", "holdCoverStartBlue"…
 */
typedef NoteHoldCoverData =
{
	/** true (default): a texture by color; false: atlas unique compartido. */
	var ?perColorTextures:Bool;

	/** Prefijo del archivo de textura. Default: "holdCover". */
	var ?texturePrefix:String;

	/** Tipo de atlas. "sparrow" | "packer". Default: "sparrow". */
	var ?textureType:String;

	/** Escala del sprite. Default: 1.0. */
	var ?scale:Float;

	/** Antialiasing. Default: true. */
	var ?antialiasing:Bool;

	/** FPS de las animaciones de start y end. Default: 24. */
	var ?framerate:Int;

	/** FPS of the animation of loop continuo. Default: 48. */
	var ?loopFramerate:Int;

	/**
	 * Offset [x, and] in pixels appliesdo to the sprite.
	 * Null = auto (width*0.3, height*0.3), igual que el comportamiento original.
	 */
	var ?offset:Array<Float>;

	/** Prefix of the animation of start. Default: "holdCoverStart". */
	var ?startPrefix:String;

	/** Prefix of the animation of loop. Default: "holdCover". */
	var ?loopPrefix:String;

	/** Prefix of the animation of fin. Default: "holdCoverEnd". */
	var ?endPrefix:String;
}

// ==================== SISTEMA PRINCIPAL ====================

class NoteSkinSystem
{
	public static var currentSkin:String = "Default";
	public static var currentSplash:String = "Default";

	/**
	 * Splash elegido permanentemente por el jugador.
	 * Solo se modifica con setSplash() (que guarda en disco).
	 * setTemporarySplash() y applySplashForStage() modifican currentSplash
	 * pero NO _globalSplash, por lo que restoreGlobalSplash() siempre
	 * vuelve al valor real del jugador — sin importar si el save.data
	 * fue corrompido por el bug anterior que llamaba setSplash() en cada cancion.
	 */
	private static var _globalSplash:String = "Default";

	/**
	 * Skin/splash por defecto del MOD ACTIVO (desde global.json del mod).
	 * Se usa como fallback en restoreGlobalSkin/Splash() cuando el jugador
	 * no tiene preferencia guardada. Sin esto, applySkinForStage() en PlayState
	 * ignoraba the global.json of the mod and volvía always to "Default".
	 */
	private static var _modDefaultSkin:String = null;
	private static var _modDefaultSplash:String = null;

	public static var availableSkins:Map<String, NoteSkinData> = new Map();
	public static var availableSplashes:Map<String, NoteSplashData> = new Map();

	/**
	 * Mapa stage-name → skin-name.
	 * Defaults registered in init(). Editable via registerStageSkin().
	 */
	private static var stageSkinMap:Map<String, String> = new Map();

	private static var stageSplashMap:Map<String, String> = new Map();

	private static var initialized:Bool = false;

	/** Last mod active durante the init — if changes, forzamos re-init. */
	private static var _lastInitMod:Null<String> = null;

	/** If the skin current applies the offset -13,-13 standard in confirm. */
	public static var offsetDefault:Bool = true;

	// Paths calculados in init() according to the mod active
	private static var SKINS_PATH:String = "assets/notes/skins";
	private static var SPLASHES_PATH:String = "assets/notes/splashes";

	/** Previene re-entry in init() when setTemporarySkin/setModDefault are calldos durante the initialization. */
	private static var _initializing:Bool = false;

	/**
	 * Forces a re-initialization complete of the system in the next acceso.
	 * Úsalo when the mod active changes for that is descubran the skins of the new mod.
	 * More seguro that acceder to `initialized` directamente (is private).
	 */
	public static function forceReinit():Void
	{
		initialized = false;
	}

	// ==================== INIT ====================

	public static function init():Void
	{
		// If the mod active changed from the last init, force re-initialization
		// para que se descubran las skins del nuevo mod.
		final currentMod:Null<String> = mods.ModManager.activeMod;
		if (initialized && currentMod == _lastInitMod)
			return;

		if (initialized)
		{
			// Reiniciar estado para el nuevo mod
			availableSkins = new Map();
			availableSplashes = new Map();
			stageSkinMap = new Map();
			stageSplashMap = new Map();
			_globalSplash = "Default";
			_modDefaultSkin = null;
			_modDefaultSplash = null;
			initialized = false;
		}

		trace("[NoteSkinSystem] Initializing...");

		_initializing = true;

		// Calculate paths in runtime according to the mod active
		// SIEMPRE apuntamos a assets/ como base (los skins de mod se descubren
		// adicionalmente en discoverSkins / discoverSplashes).
		SKINS_PATH = "assets/notes/skins";
		SPLASHES_PATH = "assets/notes/splashes";

		_lastInitMod = currentMod;

		// Skins built-in
		availableSkins.set("Default", getDefaultSkin());
		availableSkins.set("Pixel", getDefaultPixelSkin());

		// Defaults de stage → skin (editables con registerStageSkin)
		stageSkinMap.set("school", "Pixel");
		stageSkinMap.set("schoolEvil", "Pixel");

		// Defaults de stage → splash (editables con registerStageSplash)
		// Se aplican con applySplashForStage() — sin guardar en disco (temporal).
		stageSplashMap.set("school", "PixelSplash");
		stageSplashMap.set("schoolEvil", "PixelSplash");

		discoverSkins();
		discoverSplashes();
		loadSavedSkin();
		loadSavedSplash();

		_initializing = false;
		initialized = true;
		trace('[NoteSkinSystem] Ready — ${Lambda.count(availableSkins)} skins, ${Lambda.count(availableSplashes)} splashes');
	}

	// ==================== STAGE → SKIN MAPPING ====================

	/**
	 * Registra la skin a usar para un stage concreto.
	 * Llama esto desde tu Stage.hx o PlayState al cargar el stage.
	 *
	 *   NoteSkinSystem.registerStageSkin("schoolEvil", "DefaultPixel");
	 *   NoteSkinSystem.registerStageSkin("myCustomStage", "MyFancySkin");
	 */
	public static function registerStageSkin(stageName:String, skinName:String):Void
	{
		stageSkinMap.set(stageName, skinName);
		trace('[NoteSkinSystem] Stage "$stageName" → skin "$skinName"');
	}

	/**
	 * Devuelve el nombre de skin configurado para un stage, o null si no hay override.
	 */
	public static function getSkinNameForStage(stageName:String):String
	{
		return stageSkinMap.exists(stageName) ? stageSkinMap.get(stageName) : null;
	}

	/**
	 * Aplica temporalmente la skin asignada al stage.
	 * Si el stage no tiene skin propia, restaura la skin global del jugador.
	 *
	 * Úsalo in PlayState to the load the stage:
	 *   NoteSkinSystem.applySkinForStage(PlayState.curStage);
	 */
	public static function applySkinForStage(stageName:String):Void
	{
		var skinForStage = getSkinNameForStage(stageName);
		if (skinForStage != null)
			setTemporarySkin(skinForStage);
		else
			restoreGlobalSkin();
	}

	/** Registra el splash a usar para un stage concreto (temporal, sin guardar). */
	public static function registerStageSplash(stageName:String, splashName:String):Void
	{
		stageSplashMap.set(stageName, splashName);
		trace('[NoteSkinSystem] Stage "$stageName" → splash "$splashName"');
	}

	/** Devuelve el nombre de splash configurado para un stage, o null si no hay override. */
	public static function getSplashNameForStage(stageName:String):String
	{
		return stageSplashMap.exists(stageName) ? stageSplashMap.get(stageName) : null;
	}

	/**
	 * Aplica temporalmente el splash asignado al stage.
	 * Si el stage no tiene splash propio, restaura el splash global del jugador.
	 * Llama esto justo despues de applySkinForStage() en PlayState.
	 */
	public static function applySplashForStage(stageName:String):Void
	{
		var splashForStage = getSplashNameForStage(stageName);
		if (splashForStage != null)
			setTemporarySplash(splashForStage);
		else
			restoreGlobalSplash();
	}

	// ==================== DESCUBRIMIENTO ====================

	private static function discoverSkins():Void
	{
		#if sys
		// Descubrir siempre desde assets/skins (base)
		_discoverSkinsInPath(SKINS_PATH);
		// Adicionalmente from the mod active (overrides and added)
		final modRoot = mods.ModManager.modRoot();
		if (modRoot != null)
		{
			final modSkinsPath = '$modRoot/notes/skins';
			if (modSkinsPath != SKINS_PATH)
				_discoverSkinsInPath(modSkinsPath);
		}
		#else
		for (skinPath in Assets.list().filter(p -> p.contains("notes/skins/") && p.endsWith("skin.json")))
		{
			try
			{
				var data:NoteSkinData = Json.parse(Assets.getText(skinPath));
				var m = ~/skins\/([^\/]+)\//;
				if (m.match(skinPath))
					data.folder = m.matched(1);
				availableSkins.set(data.name, data);
			}
			catch (e:Dynamic)
			{
				trace('[NoteSkinSystem] Error loading $skinPath: $e');
			}
		}
		#end
	}

	#if sys
	private static function _discoverSkinsInPath(basePath:String):Void
	{
		if (!FileSystem.exists(basePath) || !FileSystem.isDirectory(basePath))
			return;
		for (skinFolder in FileSystem.readDirectory(basePath))
		{
			var skinPath = '$basePath/$skinFolder';
			if (!FileSystem.isDirectory(skinPath))
				continue;
			var configPath = '$skinPath/skin.json';
			if (FileSystem.exists(configPath))
			{
				try
				{
					var data:NoteSkinData = Json.parse(File.getContent(configPath));
					data.folder = skinFolder;
					availableSkins.set(data.name, data);
					trace('[NoteSkinSystem] Loaded skin "${data.name}" from $basePath/$skinFolder');
				}
				catch (e:Dynamic)
				{
					trace('[NoteSkinSystem] Error loading $configPath: $e');
				}
			}
			else
			{
				var auto = autoDetectSkin(skinPath, skinFolder);
				if (auto != null)
				{
					availableSkins.set(auto.name, auto);
					trace('[NoteSkinSystem] Auto-detected skin "${auto.name}"');
				}
			}
		}
	}
	#end

	private static function discoverSplashes():Void
	{
		availableSplashes.set("Default", getDefaultSplash());
		#if sys
		_discoverSplashesInPath(SPLASHES_PATH);
		// Adicionalmente desde el mod activo
		final modRoot = mods.ModManager.modRoot();
		if (modRoot != null)
		{
			final modSplashesPath = '$modRoot/notes/splashes';
			if (modSplashesPath != SPLASHES_PATH)
				_discoverSplashesInPath(modSplashesPath);
		}
		#else
		for (splashPath in Assets.list().filter(p -> p.contains("splashes/") && p.endsWith("splash.json")))
		{
			try
			{
				var data:NoteSplashData = Json.parse(Assets.getText(splashPath));
				var m = ~/splashes\/([^\/]+)\//;
				if (m.match(splashPath))
					data.folder = m.matched(1);
				availableSplashes.set(data.name, data);
			}
			catch (e:Dynamic)
			{
				trace('[NoteSkinSystem] Error loading $splashPath: $e');
			}
		}
		#end
	}

	#if sys
	private static function _discoverSplashesInPath(basePath:String):Void
	{
		if (!FileSystem.exists(basePath) || !FileSystem.isDirectory(basePath))
			return;
		for (splashFolder in FileSystem.readDirectory(basePath))
		{
			var splashPath = '$basePath/$splashFolder';
			if (!FileSystem.isDirectory(splashPath))
				continue;
			var configPath = '$splashPath/splash.json';
			if (FileSystem.exists(configPath))
			{
				try
				{
					var data:NoteSplashData = Json.parse(File.getContent(configPath));
					data.folder = splashFolder;
					availableSplashes.set(data.name, data);
				}
				catch (e:Dynamic)
				{
					trace('[NoteSkinSystem] Error loading $configPath: $e');
				}
			}
			else
			{
				var auto = autoDetectSplash(splashPath, splashFolder);
				if (auto != null)
					availableSplashes.set(auto.name, auto);
			}
		}
	}
	#end

	// ==================== AUTO-detection ====================
	#if sys
	private static function autoDetectSkin(skinPath:String, folderName:String):NoteSkinData
	{
		var files = FileSystem.readDirectory(skinPath);
		var mainPath = "";
		var mainType = "sparrow";
		var holdPath = "";

		for (file in files)
		{
			var lower = file.toLowerCase();
			if (!lower.endsWith(".png"))
				continue;
			var base = file.substr(0, file.length - 4);
			var hasXml = files.indexOf(base + ".xml") != -1;
			var hasTxt = files.indexOf(base + ".txt") != -1;
			var isHold = lower.contains("hold") || lower.contains("end");

			if (isHold && holdPath == "")
				holdPath = base;
			else if (!isHold && mainPath == "")
			{
				mainPath = base;
				mainType = hasXml ? "sparrow" : (hasTxt ? "packer" : "image");
			}
		}

		if (mainPath == "")
			return null;

		var skin:NoteSkinData = {
			name: folderName,
			author: "Unknown",
			folder: folderName,
			texture: {path: mainPath, type: mainType},
			animations: {}
		};
		if (holdPath != "")
			skin.holdTexture = {path: holdPath, type: "image"};

		return skin;
	}

	private static function autoDetectSplash(splashPath:String, folderName:String):NoteSplashData
	{
		var files = FileSystem.readDirectory(splashPath);
		for (file in files)
		{
			if (!file.toLowerCase().contains("splash") || !file.toLowerCase().endsWith(".png"))
				continue;
			var base = file.substr(0, file.length - 4);
			var hasXml = files.indexOf(base + ".xml") != -1;
			return {
				name: folderName,
				author: "Unknown",
				folder: folderName,
				assets: {path: base, type: hasXml ? "sparrow" : "image"},
				animations: {
					left: ["note impact 1 purple", "note impact 2 purple"],
					down: ["note impact 1 blue", "note impact 2 blue"],
					up: ["note impact 1 green", "note impact 2 green"],
					right: ["note impact 1 red", "note impact 2 red"],
					framerate: 24
				}
			};
		}
		return null;
	}
	#end

	// ==================== DEFAULTS ====================

	/**
	 * Skin normal by default — NOTE_assets.xml, animations sparrow standard FNF.
	 */
	private static function getDefaultSkin():NoteSkinData
	{
		return {
			name: "Default",
			author: "ninjamuffin99",
			description: "Default Friday Night Funkin' notes",
			folder: "Default",
			texture: {
				path: "NOTE_assets",
				type: "sparrow",
				scale: 0.7,
				antialiasing: true
			},
			confirmOffset: true,
			animations: {
				left: "purple0",
				down: "blue0",
				up: "green0",
				right: "red0",
				leftHold: "purple hold piece",
				downHold: "blue hold piece",
				upHold: "green hold piece",
				rightHold: "red hold piece",
				leftHoldEnd: "pruple end hold",
				downHoldEnd: "blue hold end",
				upHoldEnd: "green hold end",
				rightHoldEnd: "red hold end",
				strumLeft: "arrowLEFT",
				strumDown: "arrowDOWN",
				strumUp: "arrowUP",
				strumRight: "arrowRIGHT",
				strumLeftPress: "left press",
				strumDownPress: "down press",
				strumUpPress: "up press",
				strumRightPress: "right press",
				strumLeftConfirm: "left confirm",
				strumDownConfirm: "down confirm",
				strumUpConfirm: "up confirm",
				strumRightConfirm: "right confirm"
			}
		};
	}

	/**
	 * Skin PIXEL by default — arrows-pixels.png + arrowEnds.png, animations by index.
	 *
	 * Layout arrows-pixels.png (frameWidth=17, frameHeight=17):
	 *   fila 0 (frames  0-3):  strums static
	 *   fila 1 (frames  4-7):  notas scroll
	 *   fila 2 (frames  8-11): strums pressed
	 *   fila 3 (frames 12-15): confirm frame 1
	 *   fila 4 (frames 16-19): confirm frame 2
	 *
	 * Layout arrowEnds.png (frameWidth=7, frameHeight=6):
	 *   fila 0 (frames  0-3):  hold pieces
	 *   fila 1 (frames  4-7):  hold tails
	 */
	private static function getDefaultPixelSkin():NoteSkinData
	{
		return {
			name: "Pixel",
			author: "ninjamuffin99",
			description: "Default pixel/week 6 note skin",
			folder: "Default",
			isPixel: true,
			confirmOffset: false,
			sustainOffset: 30.0,
			holdStretch: 1.19,
			texture: {
				path: "arrows-pixels",
				type: "image",
				frameWidth: 17,
				frameHeight: 17,
				scale: 6.0,
				antialiasing: false
			},
			holdTexture: {
				path: "arrowEnds",
				type: "image",
				frameWidth: 7,
				frameHeight: 6,
				scale: 6.0,
				antialiasing: false
			},
			animations: {
				// Notas scroll — fila 1 (frames 4-7)
				left: {indices: [4]},
				down: {indices: [5]},
				up: {indices: [6]},
				right: {indices: [7]},
				// Hold pieces — fila 0 de arrowEnds (frames 0-3)
				leftHold: {indices: [0]},
				downHold: {indices: [1]},
				upHold: {indices: [2]},
				rightHold: {indices: [3]},
				// Hold tails — fila 1 de arrowEnds (frames 4-7)
				leftHoldEnd: {indices: [4]},
				downHoldEnd: {indices: [5]},
				upHoldEnd: {indices: [6]},
				rightHoldEnd: {indices: [7]},
				// Strums static — fila 0 (frames 0-3)
				strumLeft: {indices: [0]},
				strumDown: {indices: [1]},
				strumUp: {indices: [2]},
				strumRight: {indices: [3]},
				// Strums pressed — filas 1+2 (fps 12)
				strumLeftPress: {indices: [4, 8], framerate: 12},
				strumDownPress: {indices: [5, 9], framerate: 12},
				strumUpPress: {indices: [6, 10], framerate: 12},
				strumRightPress: {indices: [7, 11], framerate: 12},
				// Strums confirm — filas 3+4 (fps 24)
				strumLeftConfirm: {indices: [12, 16], framerate: 24},
				strumDownConfirm: {indices: [13, 17], framerate: 24},
				strumUpConfirm: {indices: [14, 18], framerate: 24},
				strumRightConfirm: {indices: [15, 19], framerate: 24}
			}
		};
	}

	private static function getDefaultSplash():NoteSplashData
	{
		return {
			name: "Default",
			author: "FNF Team",
			description: "Default note splash effects",
			folder: "Default",
			assets: {
				path: "noteSplashes",
				type: "sparrow",
				scale: 1.0,
				antialiasing: true,
				offset: [0, 0]
			},
			animations: {
				left: ["note impact 1 purple", "note impact 2 purple"],
				down: ["note impact 1 blue", "note impact 2 blue"],
				up: ["note impact 1 green", "note impact 2 green"],
				right: ["note impact 1 red", "note impact 2 red"],
				framerate: 24,
				randomFramerateRange: 3
			}
		};
	}

	// ==================== CARGA / GUARDADO ====================

	private static function loadSavedSkin():Void
	{
		if (FlxG.save.data.noteSkin != null && availableSkins.exists(FlxG.save.data.noteSkin))
		{
			currentSkin = FlxG.save.data.noteSkin;
		}
		else
		{
			currentSkin = "Default";
			if (FlxG.save.data.noteSkin != "Default")
			{
				FlxG.save.data.noteSkin = "Default";
				FlxG.save.flush(); // solo flush cuando realmente cambia algo
			}
		}
	}

	private static function loadSavedSplash():Void
	{
		// Determinar el splash global del jugador a partir del save.
		// SANITIZACIÓN: if the save tiene a splash that is specific of pixel
		// (e.g. "PixelSplash") almacenado por el bug antiguo que llamaba setSplash()
		// desde PlayState en cada cancion — lo reseteamos a "Default".
		// Un jugador que QUIERA PixelSplash global lo tiene que elegir manualmente
		// in the menu of options (that call setSplash() explicitly).
		// The heuristic: if the save tiene "PixelSplash" but no there is skin Pixel active
		// global, revertir. Mas simple: los splash que contengan "pixel" en el nombre
		// (case-insensitive) no deben ser el splash global por defecto.
		var savedSplash:String = FlxG.save.data.noteSplash;
		var isValidGlobal:Bool = (savedSplash != null
			&& availableSplashes.exists(savedSplash)
			&& savedSplash.toLowerCase().indexOf('pixel') < 0); // no pixel-only splashes as global default

		if (isValidGlobal)
		{
			_globalSplash = savedSplash;
			currentSplash = savedSplash;
		}
		else
		{
			_globalSplash = "Default";
			currentSplash = "Default";
			// Reparar el save si estaba corrompido
			if (FlxG.save.data.noteSplash != "Default")
			{
				FlxG.save.data.noteSplash = "Default";
				FlxG.save.flush();
			}
		}
	}

	// ==================== SETTERS ====================

	public static function setSkin(skinName:String):Bool
	{
		if (!availableSkins.exists(skinName))
		{
			trace('Note skin "$skinName" not found!');
			return false;
		}
		currentSkin = skinName;
		FlxG.save.data.noteSkin = skinName;
		FlxG.save.flush();
		return true;
	}

	public static function setTemporarySkin(skinName:String):Void
	{
		if (!initialized && !_initializing)
			init();
		if (skinName == null || skinName == '' || skinName == 'default')
		{
			currentSkin = FlxG.save.data.noteSkin != null ? FlxG.save.data.noteSkin : 'Default';
			return;
		}
		if (availableSkins.exists(skinName))
		{
			currentSkin = skinName;
			return;
		}
		for (key in availableSkins.keys())
		{
			if (key.toLowerCase() == skinName.toLowerCase())
			{
				currentSkin = key;
				return;
			}
		}
		currentSkin = FlxG.save.data.noteSkin != null ? FlxG.save.data.noteSkin : 'Default';
		trace('[NoteSkinSystem] Skin "$skinName" no encontrada, usando global: $currentSkin');
	}

	/**
	 * Registra la skin del mod activo (llamado desde GlobalConfig).
	 * A diferencia de setTemporarySkin(), este valor se preserva en
	 * restoreGlobalSkin() cuando el jugador no tiene preferencia guardada.
	 */
	public static function setModDefaultSkin(skinName:String):Void
	{
		_modDefaultSkin = (skinName != null && skinName.toLowerCase() != 'default') ? skinName : null;
		setTemporarySkin(skinName);
	}

	public static function restoreGlobalSkin():Void
	{
		var saved = FlxG.save.data.noteSkin;
		// If the player eligió a skin specific in Options, respetarla.
		if (saved != null && saved != 'Default' && availableSkins.exists(saved))
		{
			currentSkin = saved;
			return;
		}
		// Sin preferencia del jugador → usar la skin del mod (global.json) si existe.
		if (_modDefaultSkin != null && availableSkins.exists(_modDefaultSkin))
		{
			currentSkin = _modDefaultSkin;
			return;
		}
		currentSkin = 'Default';
	}

	public static function setSplash(splashName:String):Bool
	{
		if (!availableSplashes.exists(splashName))
		{
			trace('Splash "$splashName" not found!');
			return false;
		}
		// BUGFIX: actualizar _globalSplash ademas de currentSplash y save.data
		// para que restoreGlobalSplash() use siempre el valor correcto.
		_globalSplash = splashName;
		currentSplash = splashName;
		FlxG.save.data.noteSplash = splashName;
		FlxG.save.flush();
		return true;
	}

	/**
	 * Cambia el splash TEMPORALMENTE sin guardar en disco ni tocar _globalSplash.
	 * Usa esto desde PlayState / Stage para sobreescribir el splash por cancion
	 * sin contaminar la preferencia global del jugador.
	 * Llama restoreGlobalSplash() al salir del PlayState.
	 */
	public static function setTemporarySplash(splashName:String):Void
	{
		if (!initialized && !_initializing)
			init();
		if (splashName == null || splashName == '' || splashName == 'default')
		{
			// Splash empty in meta = usar the global of the jugador
			currentSplash = _globalSplash;
			return;
		}
		if (availableSplashes.exists(splashName))
		{
			currentSplash = splashName;
			return;
		}
		for (key in availableSplashes.keys())
		{
			if (key.toLowerCase() == splashName.toLowerCase())
			{
				currentSplash = key;
				return;
			}
		}
		// Fallback al global (sin tocar _globalSplash)
		currentSplash = _globalSplash;
		trace('[NoteSkinSystem] Splash "$splashName" not found, usando global: $currentSplash');
	}

	/**
	 * Registra el splash del mod activo (llamado desde GlobalConfig).
	 * A diferencia de setTemporarySplash(), este valor se preserva en
	 * restoreGlobalSplash() cuando el jugador no tiene preferencia guardada.
	 */
	public static function setModDefaultSplash(splashName:String):Void
	{
		_modDefaultSplash = (splashName != null && splashName.toLowerCase() != 'default') ? splashName : null;
		setTemporarySplash(splashName);
	}

	/**
	 * Restaura currentSplash al valor elegido por el jugador (_globalSplash),
	 * with fallback to the splash of the mod active (global.json) if the player no eligió nothing.
	 */
	public static function restoreGlobalSplash():Void
	{
		// If the player eligió a splash valid and no is pixel-only, respetarlo.
		if (_globalSplash != null && _globalSplash != 'Default' && availableSplashes.exists(_globalSplash))
		{
			currentSplash = _globalSplash;
			return;
		}
		// Sin preferencia del jugador → usar el splash del mod (global.json) si existe.
		if (_modDefaultSplash != null && availableSplashes.exists(_modDefaultSplash))
		{
			currentSplash = _modDefaultSplash;
			return;
		}
		currentSplash = _globalSplash;
	}

	// ==================== GETTERS DE SKIN ====================

	/**
	 * Devuelve el NoteSkinData completo de la skin actual.
	 * Úsalo in Note.hx / StrumNote.hx — contains texture, scales, anims, flags, all.
	 */
	public static function getCurrentSkinData(?skinName:String):NoteSkinData
	{
		if (!initialized)
			init();
		var skin = skinName != null ? skinName : currentSkin;
		var data = availableSkins.get(skin);
		if (data == null)
			data = availableSkins.get("Default");
		return data;
	}

	/**
	 * Carga y devuelve el FlxAtlasFrames de una NoteSkinTexture.
	 * Usa folder de la skin como prefijo de assets.
	 */
	public static function loadSkinFrames(tex:NoteSkinTexture, ?folder:String):FlxAtlasFrames
	{
		return loadAtlas(tex, folder != null ? folder : "Default");
	}

	/**
	 * Devuelve la textura correcta para los STRUMS del skin dado.
	 * Prioridad: strumsTexture > texture
	 */
	public static function getStrumsTexture(?skinName:String):NoteSkinTexture
	{
		var d = getCurrentSkinData(skinName);
		if (d == null) return null;
		return d.strumsTexture != null ? d.strumsTexture : d.texture;
	}

	/**
	 * Construye un mapa animName → [offsetX, offsetY] a partir de los campos
	 * `offset` definidos en cada NoteAnimDef de strum.
	 *
	 * Logic of priority (of mayor to menor):
	 *   1. The field `offset` explicit in the def of the animation of the JSON.
	 *   2. If the animation is a confirm and `confirmOffset:true` in the skin
	 *      (o no se define, que vale true por defecto para skins no-pixel),
	 *      se usa el fallback [-13, -13] — comportamiento original del engine.
	 *   3. Sin offset (sin entrada en el mapa).
	 *
	 * Parameter `noteID`: index of the arrow (0=left, 1=down, 2=up, 3=right).
	 * Only is procesan the defs of the direction correct.
	 *
	 * The mapa resultante tiene as keys the nombres internos of animation
	 * usados por StrumNote: 'static', 'pressed', 'confirm'.
	 */
	public static function buildStrumOffsets(skinData:NoteSkinData, noteID:Int):Map<String, Array<Float>>
	{
		var map:Map<String, Array<Float>> = new Map();
		if (skinData == null || skinData.animations == null) return map;

		var anims = skinData.animations;
		var i = Std.int(Math.abs(noteID)) % 4;

		// Defs para este noteID
		var staticDefs  = [anims.strumLeft,       anims.strumDown,       anims.strumUp,       anims.strumRight];
		var pressDefs   = [anims.strumLeftPress,   anims.strumDownPress,  anims.strumUpPress,  anims.strumRightPress];
		var confirmDefs = [anims.strumLeftConfirm, anims.strumDownConfirm,anims.strumUpConfirm,anims.strumRightConfirm];

		// Helper: extrae offset of a def dynamic (String or NoteAnimDef)
		inline function offsetOf(def:Dynamic):Array<Float>
		{
			if (def == null || Std.isOfType(def, String)) return null;
			var arr:Dynamic = def.offset;
			if (arr == null) return null;
			return [Std.parseFloat(Std.string(arr[0])), Std.parseFloat(Std.string(arr[1]))];
		}

		// static
		var so = offsetOf(staticDefs[i]);
		if (so != null)
			map.set('static', so);

		// pressed
		var po = offsetOf(pressDefs[i]);
		if (po != null)
			map.set('pressed', po);

		// confirm: si la def tiene offset propio, usarlo; si no, fallback a confirmOffset global
		var co = offsetOf(confirmDefs[i]);
		if (co != null)
		{
			map.set('confirm', co);
		}
		else
		{
			// confirmOffset global: true para skins normales (default), false para pixel
			var useDefault = skinData.confirmOffset != null
				? skinData.confirmOffset
				: (skinData.offsetDefault != null ? skinData.offsetDefault : !(skinData.isPixel == true));
			if (useDefault)
				map.set('confirm', [-13.0, -13.0]);
		}

		return map;
	}

	/**
	 * Devuelve la textura correcta para las NOTAS SCROLL del skin dado.
	 * Prioridad: notesTexture > texture
	 * Construye un par [offsetX, offsetY] para las notas scroll/hold de una
	 * direction concreta to partir of the field `offset` of the animations of note.
	 *
	 * Logic of priority (of mayor to menor):
	 *   1. offset of the animation scroll (left/down/up/right) — cabeza of note.
	 *   2. Sin offset (devuelve [0.0, 0.0]).
	 *
	 * Los offsets de hold/holdEnd se resuelven por separado con las defs
	 * leftHold downHold* etc., but if no are definidos usan the same offset
	 * de la cabeza para mantener coherencia visual entre cabeza y cuerpo.
	 *
	 * @param skinData  Datos de la skin activa.
	 * @param noteID    Direction (0=left, 1=down, 2=up, 3=right).
	 * @return  Array [offsetX, offsetY] listo para aplicar; nunca null.
	*/
	public static function buildNoteOffsets(skinData:NoteSkinData, noteID:Int):Array<Float>
	{
		if (skinData == null || skinData.animations == null) return [0.0, 0.0];

		var anims = skinData.animations;
		var i = Std.int(Math.abs(noteID)) % 4;

		// Defs of animation of note scroll by direction
		var scrollDefs:Array<Dynamic> = [anims.left, anims.down, anims.up, anims.right];
		var def:Dynamic = scrollDefs[i];

		// Extraer offset del def (puede ser String shorthand → sin offset)
		if (def != null && !Std.isOfType(def, String))
		{
			var arr:Dynamic = def.offset;
			if (arr != null)
				return [Std.parseFloat(Std.string(arr[0])), Std.parseFloat(Std.string(arr[1]))];
		}

		return [0.0, 0.0];
	}

	/**
	 * Resuelve the offset for notes HOLD/HOLDEND of a direction.
	 * Prioridad: offset de la def hold > offset de la def scroll (coherencia) > [0,0].
	 *
	 * @param skinData  Datos de la skin activa.
	 * @param noteID    Direction (0=left, 1=down, 2=up, 3=right).
	 * @return  Array [offsetX, offsetY] listo para aplicar; nunca null.
	 */
	public static function buildHoldNoteOffsets(skinData:NoteSkinData, noteID:Int):Array<Float>
	{
		if (skinData == null || skinData.animations == null) return [0.0, 0.0];

		var anims = skinData.animations;
		var i = Std.int(Math.abs(noteID)) % 4;

		// Helper inline
		inline function offsetOf(def:Dynamic):Array<Float>
		{
			if (def == null || Std.isOfType(def, String)) return null;
			var arr:Dynamic = def.offset;
			if (arr == null) return null;
			return [Std.parseFloat(Std.string(arr[0])), Std.parseFloat(Std.string(arr[1]))];
		}

		// Defs de hold (piezas) y holdEnd (tail)
		var holdDefs:Array<Dynamic>    = [anims.leftHold,    anims.downHold,    anims.upHold,    anims.rightHold];
		var holdEndDefs:Array<Dynamic> = [anims.leftHoldEnd, anims.downHoldEnd, anims.upHoldEnd, anims.rightHoldEnd];

		// Preferir holdEnd si tiene offset, si no hold, si no fallback al scroll offset
		var off = offsetOf(holdEndDefs[i]);
		if (off != null) return off;
		off = offsetOf(holdDefs[i]);
		if (off != null) return off;

		// Fallback: mismo offset que la cabeza de nota para coherencia visual
		return buildNoteOffsets(skinData, noteID);
	}

	public static function getNotesScrollTexture(?skinName:String):NoteSkinTexture
	{
		var d = getCurrentSkinData(skinName);
		if (d == null) return null;
		return d.notesTexture != null ? d.notesTexture : d.texture;
	}

	/**
	 * Devuelve la textura correcta para los HOLDS del skin dado.
	 * Prioridad: holdTexture > notesTexture > texture
	 */
	public static function getHoldTexture(?skinName:String):NoteSkinTexture
	{
		var d = getCurrentSkinData(skinName);
		if (d == null) return null;
		if (d.holdTexture != null) return d.holdTexture;
		if (d.notesTexture != null) return d.notesTexture;
		return d.texture;
	}

	/**
	 * Devuelve true si la textura dada es de tipo "funkinsprite".
	 * Usado por Note/StrumNote para decidir si usar FunkinSprite en vez de FlxSprite.
	 */
	public static inline function isFunkinSpriteType(tex:NoteSkinTexture):Bool
	{
		return tex != null && tex.type != null && tex.type.toLowerCase() == "funkinsprite";
	}

	// ── Helpers de escala convenientes ───────────────────────────────────

	public static function getNoteScale(?skinName:String):Float
	{
		var d = getCurrentSkinData(skinName);
		return (d != null && d.texture != null && d.texture.scale != null) ? d.texture.scale : 0.7;
	}

	public static function getPixelNoteScale(?skinName:String):Float
	{
		var d = getCurrentSkinData(skinName);
		return (d != null && d.texture != null && d.texture.scale != null) ? d.texture.scale : funkin.gameplay.PlayStateConfig.PIXEL_ZOOM;
	}

	public static function getPixelEndsScale(?skinName:String):Float
	{
		var d = getCurrentSkinData(skinName);
		if (d == null)
			return funkin.gameplay.PlayStateConfig.PIXEL_ZOOM;
		var tex = d.holdTexture != null ? d.holdTexture : d.texture;
		return (tex != null && tex.scale != null) ? tex.scale : funkin.gameplay.PlayStateConfig.PIXEL_ZOOM;
	}

	// ── Getters legacy (siguen working for code external) ──────────

	public static function getNoteSkin(?skinName:String):FlxAtlasFrames
	{
		var d = getCurrentSkinData(skinName);
		return loadAtlas(d.texture, d.folder);
	}

	public static function getPixelNoteSkin(?skinName:String):FlxAtlasFrames
	{
		var d = getCurrentSkinData(skinName);
		return loadAtlas(d.texture, d.folder);
	}

	public static function getPixelNoteEnds(?skinName:String):FlxAtlasFrames
	{
		var d = getCurrentSkinData(skinName);
		var tex = d.holdTexture != null ? d.holdTexture : d.texture;
		return loadAtlas(tex, d.folder);
	}

	public static function getSkinAnimations(?skinName:String):NoteSkinAnims
	{
		var d = getCurrentSkinData(skinName);
		return d != null ? d.animations : null;
	}

	// ==================== HELPER: add animation ====================

	/**
	 * Adds an animation to a FlxSprite from a field of animation of the JSON.
	 *
	 * Acepta:
	 *   String:         "purple0"                     → addByPrefix("purple0")
	 *   Objeto prefix:  {"prefix":"purple0"}           → addByPrefix("purple0")
	 *   Objeto indices: {"indices":[4],"framerate":24} → animation.add([4], 24)
	 *
	 * If def is null no hace nada — the animation simplemente no is registra.
	 *
	 * @param overrideLoop  When non-null, forces the loop flag regardless of what
	 *                      the JSON definition says.  Pass `false` for strum
	 *                      animations (pressed / confirm) so that
	 *                      animation.curAnim.finished works correctly and the
	 *                      auto-reset to 'static' fires as expected.
	 *                      Passing `null` (default) preserves the original
	 *                      behaviour: loop comes from the def object, or defaults
	 *                      to false for indices/prefix objects and false for plain
	 *                      strings (previously defaulted to Flixel's loop=true).
	 */
	public static function addAnimToSprite(sprite:FlxSprite, animName:String, def:Dynamic, ?overrideLoop:Bool):Void
	{
		if (sprite == null || def == null)
			return;

		if (Std.isOfType(def, String))
		{
			// Plain string shorthand — no framerate or loop info in the def.
			// Default to loop=false so strum confirm/pressed finish correctly.
			// overrideLoop takes precedence when explicitly supplied.
			var loop:Bool = overrideLoop != null ? overrideLoop : false;
			sprite.animation.addByPrefix(animName, cast(def, String), 24, loop);
			return;
		}

		var prefix:String = def.prefix;
		var indices:Dynamic = def.indices;
		var fps:Int = def.framerate != null ? Std.int(def.framerate) : 24;
		// overrideLoop wins; fall back to the def's loop field; then false.
		var loop:Bool = overrideLoop != null ? overrideLoop : (def.loop != null ? (def.loop == true) : false);

		if (indices != null)
		{
			var arr:Array<Int> = [];
			for (v in (indices : Array<Dynamic>))
				arr.push(Std.int(v));
			sprite.animation.add(animName, arr, fps, loop);
		}
		else if (prefix != null)
		{
			sprite.animation.addByPrefix(animName, prefix, fps, loop);
		}
		else
		{
			trace('[NoteSkinSystem] addAnimToSprite: "$animName" no tiene prefix ni indices — ignorado');
		}
	}

	// ==================== GETTERS DE SPLASH ====================

	public static function getSplashTexture(?splashName:String):FlxAtlasFrames
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		return loadAtlasSplash(d.assets, d.folder);
	}

	public static function getSplashAnimations(?splashName:String):SplashAnimations
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		return d.animations;
	}

	public static function getSplashData(?splashName:String):NoteSplashData
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		return d;
	}

	// ==================== HOLD COVERS ====================

	/**
	 * Returns the datos of configuration of the hold cover for the splash current.
	 * If the splash.json no tiene section "holdCover", returns the defaults that
	 * reproducen the comportamiento original (perColorTextures=true, prefijos standard).
	 */
	public static function getHoldCoverData(?splashName:String):NoteHoldCoverData
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");

		// Si el splash tiene datos propios, devolverlos completando los nulls con defaults.
		var hc:NoteHoldCoverData = (d != null && d.holdCover != null) ? d.holdCover : {};

		// Rellenar defaults inline para que NoteHoldCover nunca tenga que hacer null-checks.
		if (hc.perColorTextures == null) hc.perColorTextures = true;
		if (hc.texturePrefix    == null) hc.texturePrefix    = "holdCover";
		if (hc.textureType      == null) hc.textureType      = "sparrow";
		if (hc.scale            == null) hc.scale            = 1.0;
		if (hc.antialiasing     == null) hc.antialiasing     = true;
		if (hc.framerate        == null) hc.framerate        = 24;
		if (hc.loopFramerate    == null) hc.loopFramerate    = 48;
		if (hc.startPrefix      == null) hc.startPrefix      = "holdCoverStart";
		if (hc.loopPrefix       == null) hc.loopPrefix       = "holdCover";
		if (hc.endPrefix        == null) hc.endPrefix        = "holdCoverEnd";
		// offset null = auto calculado en NoteHoldCover (width*0.3, height*0.3)

		return hc;
	}

	/**
	 * Comprueba si existen los assets de hold cover para el color y splash dados.
	 * Use the configuration of the splash.json if is available.
	 */
	public static function holdCoverExists(color:String, ?splashName:String):Bool
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		var folder = d != null && d.folder != null ? d.folder : "Default";
		var hc = getHoldCoverData(splashName);

		var texPath = hc.perColorTextures
			? '${hc.texturePrefix}$color'
			: hc.texturePrefix;
		return splashAssetExists(texPath, folder);
	}

	/**
	 * Carga el FlxAtlasFrames del hold cover para el color y splash dados.
	 * Respeta the configuration of texturePrefix, perColorTextures and textureType
	 * del splash.json — sin nada hardcodeado.
	 */
	public static function getHoldCoverTexture(color:String, ?splashName:String):FlxAtlasFrames
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		var folder = d != null && d.folder != null ? d.folder : "Default";
		var hc = getHoldCoverData(splashName);

		// Construir path according to modo (per-color or atlas unique)
		var texPath = hc.perColorTextures
			? '${hc.texturePrefix}$color'
			: hc.texturePrefix;

		if (!splashAssetExists(texPath, folder))
		{
			// Fallback a Default si el splash actual no tiene el asset
			if (folder != "Default" && splashAssetExists(texPath, "Default"))
				folder = "Default";
			else
				return null;
		}

		try
		{
			var fullPath = '$folder/$texPath';
			return switch (hc.textureType.toLowerCase())
			{
				case "packer": FlxAtlasFrames.fromSpriteSheetPacker(
					flixel.FlxG.bitmap.add('assets/notes/splashes/$fullPath.png'),
					'assets/notes/splashes/$fullPath.txt');
				default: Paths.splashSprite(fullPath); // sparrow
			};
		}
		catch (e:Dynamic)
		{
			trace('[NoteSkinSystem] Error cargando holdCover $folder/$texPath: $e');
			return null;
		}
	}

	public static function getCurrentSplashFolder():String
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		return d.folder != null ? d.folder : "Default";
	}

	// ==================== LISTAS ====================

	public static function getSkinList():Array<String>
	{
		if (!initialized)
			init();
		return [for (k in availableSkins.keys()) k];
	}

	public static function getSplashList():Array<String>
	{
		if (!initialized)
			init();
		return [for (k in availableSplashes.keys()) k];
	}

	public static function getSkinInfo(n:String):NoteSkinData
	{
		if (!initialized)
			init();
		return availableSkins.get(n);
	}

	public static function getSplashInfo(n:String):NoteSplashData
	{
		if (!initialized)
			init();
		return availableSplashes.get(n);
	}

	// ==================== CARGA INTERNA DE ATLAS ====================

	private static function loadAtlas(tex:Dynamic, ?folderName:String):FlxAtlasFrames
	{
		if (tex == null || tex.path == null)
		{
			trace('[NoteSkinSystem] loadAtlas: texture invalid, usando Default');
			var fallback = Paths.skinSprite('Default/NOTE_assets');
			if (fallback != null) return fallback;
			return _makeFallbackFrames();
		}

		var path:String = tex.path;
		var type:String = tex.type != null ? tex.type : "sparrow";
		var folder:String = folderName != null ? folderName : "Default";

		if (!assetExists(path, folder))
		{
			trace('[NoteSkinSystem] loadAtlas: "$folder/$path" not found, usando Default');
			var fallback = Paths.skinSprite('Default/NOTE_assets');
			if (fallback != null) return fallback;
			return _makeFallbackFrames();
		}

		try
		{
			var result:FlxAtlasFrames = null;
			switch (type.toLowerCase())
			{
				case "sparrow":
					result = Paths.skinSprite('$folder/$path');

				case "packer":
					result = Paths.skinSpriteTxt('$folder/$path');

				case "funkinsprite":
					// FunkinSprite (Adobe Animate Atlas) — devolvemos null intencionalmente.
					// Note.hx y StrumNote.hx detectan isFunkinSpriteType() ANTES de llamar
					// loadSkinFrames() y crean un FunkinSprite en su lugar.
					// Este case evita el trace de "tipo desconocido" y el fallback a Default.
					return null;

				case "image":
					var graphic = FlxG.bitmap.add('assets/notes/skins/$folder/$path.png');
					if (graphic == null) throw 'PNG not found para image skin: $folder/$path';
					// BUGFIX: FlxG.bitmap.add() deja persist=false y useCount=0.
					// FunkinCache.clearSecondLayer() → clearUnused() destruye cualquier
					// graphic with persist=false + useCount=0 at the end of postStateSwitch,
					// ANTES de que los StrumNotes/Notes hayan dibujado su primer frame.
					// Resultado: frame.parent.bitmap = null → FlxDrawQuadsItem::render crash.
					// Solution: mark persist=true and register in PathsCache so that the
					// cache system manages it correctly between sessions.
					graphic.persist = true;
					graphic.destroyOnNoUse = false;
					funkin.cache.PathsCache.instance.trackGraphic('assets/notes/skins/$folder/$path.png', graphic);
					// Frame dimensions read from JSON — no hardcoding by filename
					var fw:Int = tex.frameWidth != null ? Std.int(tex.frameWidth) : 17;
					var fh:Int = tex.frameHeight != null ? Std.int(tex.frameHeight) : 17;
					trace('[NoteSkinSystem] image atlas $folder/$path — frame: ${fw}×${fh}px');
					result = FlxAtlasFramesExt.fromGraphic(graphic, fw, fh);

				default:
					trace('[NoteSkinSystem] tipo desconocido "$type" en $folder/$path, usando sparrow');
					result = Paths.skinSprite('$folder/$path');
			}

			if (result != null) return result;

			// Resultado null (ej: XML faltante con PNG presente) → fallback Default
			trace('[NoteSkinSystem] loadAtlas: "$folder/$path" devolvió null, probando Default');
			var fallback = Paths.skinSprite('Default/NOTE_assets');
			if (fallback != null) return fallback;
			return _makeFallbackFrames();
		}
		catch (e:Dynamic)
		{
			trace('[NoteSkinSystem] Error cargando $folder/$path: $e');
			var fallback = Paths.skinSprite('Default/NOTE_assets');
			if (fallback != null) return fallback;
			return _makeFallbackFrames();
		}
	}

	/**
	 * Last recurso: creates a FlxAtlasFrames of 1×1 pixel for that the sprites
	 * nunca tengan frames=null. Sin esto, cualquier StrumNote/Note con skin rota
	 * causa FlxDrawQuadsItem::render crash en el primer frame de PlayState.
	 */
	private static function _makeFallbackFrames():FlxAtlasFrames
	{
		trace('[NoteSkinSystem] FALLBACK: usando frames de 1×1 para evitar crash de render');
		var bmp = new openfl.display.BitmapData(1, 1, true, 0x00000000);
		var g = FlxG.bitmap.add(bmp, false, 'note_skin_fallback_${Math.random()}');
		if (g == null)
		{
			// Last last recurso: create FlxGraphic directamente
			g = flixel.graphics.FlxGraphic.fromBitmapData(bmp, false, null, false);
		}
		// fromGraphic con frames 1×1 → atlas de 1 frame, 1×1 px
		return FlxAtlasFramesExt.fromGraphic(g, 1, 1);
	}

	private static function loadAtlasSplash(assets:Dynamic, ?folderName:String):FlxAtlasFrames
	{
		if (assets == null || assets.path == null)
			return Paths.splashSprite('Default/noteSplashes');
		var path = (assets.path : String);
		var type = assets.type != null ? (assets.type : String) : "sparrow";
		var folder = folderName != null ? folderName : "Default";
		if (!splashAssetExists(path, folder))
			return Paths.splashSprite('Default/noteSplashes');
		try
		{
			switch (type.toLowerCase())
			{
				case "sparrow":
					return Paths.splashSprite('$folder/$path');
				case "packer":
					return FlxAtlasFrames.fromSpriteSheetPacker(FlxG.bitmap.add('assets/notes/splashes/$folder/$path.png'), 'assets/notes/splashes/$folder/$path.txt');
				case "image":
					var g = FlxG.bitmap.add('assets/notes/splashes/$folder/$path.png');
					if (g == null) throw 'PNG not found para image splash: $folder/$path';
					// BUGFIX: igual que loadAtlas "image" — persist=true para evitar que
					// clearSecondLayer() → clearUnused() destroys the graphic before the first render.
					g.persist = true;
					g.destroyOnNoUse = false;
					funkin.cache.PathsCache.instance.trackGraphic('assets/notes/splashes/$folder/$path.png', g);
					return FlxAtlasFramesExt.fromGraphic(g, g.width, g.height);
				default:
					return Paths.splashSprite('$folder/$path');
			}
		}
		catch (e:Dynamic)
		{
			return Paths.splashSprite('Default/noteSplashes');
		}
	}

	private static function assetExists(path:String, folder:String):Bool
	{
		#if sys
		// Comprobar primero en el mod activo, luego en assets base.
		// Sin esto, skins en mods/MyMod/notes/skins/ZoneNotes/NOTE_assets.png
		// son ignoradas y el juego cae silenciosamente al Default.
		final modRoot = mods.ModManager.modRoot();
		if (modRoot != null && sys.FileSystem.exists('$modRoot/notes/skins/$folder/$path.png'))
			return true;
		return sys.FileSystem.exists('assets/notes/skins/$folder/$path.png') || sys.FileSystem.exists('$path.png');
		#else
		return openfl.utils.Assets.exists('assets/notes/skins/$folder/$path.png');
		#end
	}

	private static function splashAssetExists(path:String, folder:String):Bool
	{
		#if sys
		// Same logic that assetExists: check mod first.
		final modRoot = mods.ModManager.modRoot();
		if (modRoot != null && sys.FileSystem.exists('$modRoot/notes/splashes/$folder/$path.png'))
			return true;
		return sys.FileSystem.exists('assets/notes/splashes/$folder/$path.png') || sys.FileSystem.exists('$path.png');
		#else
		return openfl.utils.Assets.exists('assets/notes/splashes/$folder/$path.png');
		#end
	}

	// ==================== EXPORT EXAMPLES ====================

	/**
	 * Genera un JSON de ejemplo para una skin normal.
	 * Colócalo in:  assets/notes/skins/MiSkin/skin.json
	 */
	public static function exportSkinExample():String
	{
		return Json.stringify({
			name: "Custom Skin",
			author: "Your Name",
			description: "My custom note skin",
			// texture: textura principal (fallback para todo si no se definen las otras)
			texture: {
				path: "NOTE_assets",
				type: "sparrow", // "sparrow" | "packer" | "image" | "funkinsprite"
				scale: 0.7,
				antialiasing: true
			},
			// strumsTexture: SOLO para los strums (null = usa texture)
			// strumsTexture: { path: "MY_strums", type: "sparrow", scale: 0.7 },
			// notesTexture: SOLO para las notas que bajan (null = usa texture)
			// notesTexture: { path: "MY_notes", type: "sparrow", scale: 0.7 },
			confirmOffset: true,
			animations: {
				left: "purple0",
				down: "blue0",
				up: "green0",
				right: "red0",
				leftHold: "purple hold piece",
				downHold: "blue hold piece",
				upHold: "green hold piece",
				rightHold: "red hold piece",
				leftHoldEnd: "pruple end hold",
				downHoldEnd: "blue hold end",
				upHoldEnd: "green hold end",
				rightHoldEnd: "red hold end",
				strumLeft: "arrowLEFT",
				strumDown: "arrowDOWN",
				strumUp: "arrowUP",
				strumRight: "arrowRIGHT",
				strumLeftPress: "left press",
				strumDownPress: "down press",
				strumUpPress: "up press",
				strumRightPress: "right press",
				strumLeftConfirm: "left confirm",
				strumDownConfirm: "down confirm",
				strumUpConfirm: "up confirm",
				strumRightConfirm: "right confirm"
			}
		}, null, "  ");
	}

	/**
	 * Genera un JSON de ejemplo para una skin PIXEL.
	 * Colócalo in:  assets/notes/skins/MiSkinPixel/skin.json
	 *
	 * Para asociarlo a un stage:
	 *   NoteSkinSystem.registerStageSkin("miStage", "MiSkinPixel");
	 * O desde PlayState:
	 *   NoteSkinSystem.applySkinForStage(PlayState.curStage);
	 */
	public static function exportPixelSkinExample():String
	{
		return Json.stringify({
			name: "Custom Pixel Skin",
			author: "Your Name",
			description: "My pixel note skin",
			isPixel: true,
			confirmOffset: false,
			sustainOffset: 30,
			holdStretch: 1.19,
			texture: {
				path: "arrows-pixels",
				type: "image",
				frameWidth: 17,
				frameHeight: 17,
				scale: 6.0,
				antialiasing: false
			},
			holdTexture: {
				path: "arrowEnds",
				type: "image",
				frameWidth: 7,
				frameHeight: 6,
				scale: 6.0,
				antialiasing: false
			},
			animations: {
				left: {indices: [4]},
				down: {indices: [5]},
				up: {indices: [6]},
				right: {indices: [7]},
				leftHold: {indices: [0]},
				downHold: {indices: [1]},
				upHold: {indices: [2]},
				rightHold: {indices: [3]},
				leftHoldEnd: {indices: [4]},
				downHoldEnd: {indices: [5]},
				upHoldEnd: {indices: [6]},
				rightHoldEnd: {indices: [7]},
				strumLeft: {indices: [0]},
				strumDown: {indices: [1]},
				strumUp: {indices: [2]},
				strumRight: {indices: [3]},
				strumLeftPress: {indices: [4, 8], framerate: 12},
				strumDownPress: {indices: [5, 9], framerate: 12},
				strumUpPress: {indices: [6, 10], framerate: 12},
				strumRightPress: {indices: [7, 11], framerate: 12},
				strumLeftConfirm: {indices: [12, 16], framerate: 24},
				strumDownConfirm: {indices: [13, 17], framerate: 24},
				strumUpConfirm: {indices: [14, 18], framerate: 24},
				strumRightConfirm: {indices: [15, 19], framerate: 24}
			}
		}, null, "  ");
	}

	public static function exportSplashExample():String
	{
		return Json.stringify({
			name: "Custom Splash",
			author: "Your Name",
			description: "My custom splash",
			assets: {
				path: "noteSplashes",
				type: "sparrow",
				scale: 1.0,
				antialiasing: true,
				offset: [0, 0]
			},
			animations: {
				left: ["note impact 1 purple", "note impact 2 purple"],
				down: ["note impact 1 blue", "note impact 2 blue"],
				up: ["note impact 1 green", "note impact 2 green"],
				right: ["note impact 1 red", "note impact 2 red"],
				framerate: 24,
				randomFramerateRange: 3
			},
			// Section holdCover optional — omitirla use the defaults of the engine.
			// Copia y personaliza para modificar el cover visual de notas largas.
			holdCover: {
				perColorTextures: true,
				texturePrefix: "holdCover",
				textureType: "sparrow",
				scale: 1.0,
				antialiasing: true,
				framerate: 24,
				loopFramerate: 48,
				offset: [0, 0],
				startPrefix: "holdCoverStart",
				loopPrefix: "holdCover",
				endPrefix: "holdCoverEnd"
			}
		}, null, "  ");
	}

	/**
	 * Generates a JSON of ejemplo of splash.json with section holdCover personalizada.
	 * Useful as punto of partida for a splash with atlas unique compartido.
	 *
	 * Coloca el JSON en: assets/notes/splashes/MySplash/splash.json
	 * Y los assets en:   assets/notes/splashes/MySplash/holdCoverAll.png  (+ .xml)
	 */
	public static function exportHoldCoverExample():String
	{
		return Json.stringify({
			name: "Custom Hold Cover",
			author: "Your Name",
			description: "Single-atlas hold cover example",
			assets: {
				path: "noteSplashes",
				type: "sparrow",
				scale: 1.0,
				antialiasing: true
			},
			animations: {
				left: ["note impact 1 purple", "note impact 2 purple"],
				down: ["note impact 1 blue", "note impact 2 blue"],
				up: ["note impact 1 green", "note impact 2 green"],
				right: ["note impact 1 red", "note impact 2 red"],
				framerate: 24
			},
			holdCover: {
				// Atlas unique: holdCoverAll.png contains all the colores
				perColorTextures: false,
				texturePrefix: "holdCoverAll",
				textureType: "sparrow",
				scale: 1.0,
				antialiasing: true,
				framerate: 24,
				loopFramerate: 48,
				// offset null = auto (width*0.3, height*0.3)
				// The prefijos of animation reciben the color as suffix:
				// "myStart" → "myStartPurple", "myStartBlue"...
				startPrefix: "holdCoverStart",
				loopPrefix: "holdCover",
				endPrefix: "holdCoverEnd"
			}
		}, null, "  ");
	}
}
