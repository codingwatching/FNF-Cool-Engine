package funkin.gameplay.objects.stages;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.math.FlxPoint;
import flixel.sound.FlxSound;
import flixel.util.FlxColor;
import flixel.util.FlxAxes;
import flixel.addons.display.FlxBackdrop;
import haxe.Json;
import lime.utils.Assets;
// FunkinSprite — reemplaza FlxSprite para sprites animados del stage
import animationdata.FunkinSprite;
// Scripting
import funkin.scripting.ScriptHandler;
// 3D
import funkin.graphics.scene3d.Flx3DSprite;
import funkin.graphics.scene3d.Flx3DObject;
import funkin.graphics.scene3d.Flx3DScene;
import funkin.graphics.scene3d.Model3DLoader;

using StringTools;

typedef StageData =
{
	var name:String;
	var defaultZoom:Float;
	var isPixelStage:Bool;
	var elements:Array<StageElement>;
	@:optional var gfVersion:String;
	@:optional var boyfriendPosition:Array<Float>;
	@:optional var dadPosition:Array<Float>;
	@:optional var gfPosition:Array<Float>;
	@:optional var cameraBoyfriend:Array<Float>;
	@:optional var cameraDad:Array<Float>;
	/** Offset of camera for the GF (field camera_girlfriend of Psych). */
	@:optional var cameraGirlfriend:Array<Float>;
	/** Velocidad of the lerp of camera (camera_speed in Psych, multiplicador over the default). */
	@:optional var cameraSpeed:Float;
	@:optional var hideGirlfriend:Bool;
	@:optional var scripts:Array<String>;
	@:optional var customProperties:Dynamic;
	/**
	 * Library of assets by default for all the elementos of this stage.
	 * Si se especifica, todos los elementos que no tengan su propio "assetLibrary"
	 * buscarán its images in the folder of this otro stage.
	 *
	 * Ejemplo: si tienes "spooky_night" que es igual que "spooky" pero de noche,
	 * pon "assetLibrary": "spooky" y reutilizas todos sus assets sin copiarlos.
	 * Only sobreescribe the assets that cambien añadiéndolos in the folder local.
	 */
	@:optional var assetLibrary:String;
}

typedef StageElement =
{
	var type:String; // "sprite", "animated", "group", "sound", "custom_class", "custom_class_group"
	var asset:String;
	var position:Array<Float>;
	@:optional var name:String;
	@:optional var scrollFactor:Array<Float>;
	@:optional var scale:Array<Float>;
	@:optional var antialiasing:Bool;
	@:optional var active:Bool;
	@:optional var alpha:Float;
	@:optional var flipX:Bool;
	@:optional var flipY:Bool;
	@:optional var angle:Float;
	@:optional var color:String;
	@:optional var blend:String;
	@:optional var visible:Bool;
	@:optional var zIndex:Int;

	// For animated sprites
	@:optional var animations:Array<StageAnimation>;
	@:optional var firstAnimation:String;

	// For groups
	@:optional var members:Array<StageMember>;

	// For sounds
	@:optional var volume:Float;
	@:optional var looped:Bool;

	// For custom classes (BackgroundGirls, BackgroundDancer, etc.)
	@:optional var className:String;
	@:optional var customProperties:Dynamic;

	// For custom class groups
	@:optional var instances:Array<CustomClassInstance>;

	/**
	 * Library of assets for this elemento specific.
	 * Tiene prioridad sobre el "assetLibrary" global del stage.
	 *
	 * Also puedes usar the sintaxis corta in the field "asset":
	 *   "asset": "stage_week1:bg"   →  load "bg" from the library of "stage_week1"
	 *
	 * El campo "assetLibrary" en el elemento sirve para el mismo efecto pero
	 * of forma more explicit and without tocar the field "asset".
	 */
	@:optional var assetLibrary:String;

	/**
	 * When true, this element renders ON TOP of characters.
	 * Set this in the stage JSON (or via the Stage Editor) for foreground
	 * layers like light shafts, front cameras, bokeh overlays, etc.
	 * Equivalent to placing a sprite node AFTER <boyfriend> in Codename Engine XML.
	 */
	@:optional var aboveChars:Bool;

	/**
	 * When true, this element cannot be selected, moved or deleted in the Stage Editor.
	 * Useful for large background sprites you don't want to accidentally grab.
	 * Has no effect at runtime — purely an editor hint.
	 */
	@:optional var locked:Bool;

	// ── Modelo 3D (type: "model3d") ───────────────────────────────────────────
	//
	// Ejemplo en el JSON del stage:
	// {
	//   "type": "model3d",
	//   "name": "spinning_cube",
	//   "asset": "cube",
	//   "position": [640, 360],
	//   "modelScale": 100,
	//   "modelRotX": 0, "modelRotY": 0, "modelRotZ": 0,
	//   "modelCamX": 0, "modelCamY": 1, "modelCamZ": 5,
	//   "sceneWidth": 300, "sceneHeight": 300,
	//   "renderEveryFrame": true
	// }
	//
	// The field "asset" is the name of the .obj (without extension).
	// Se busca en stages/{stage}/models/{asset}.obj y stages/models/{asset}.obj.
	// El elemento se registra en stage.elements con su nombre para que scripts
	// puedan acceder to it as Flx3DSprite and animar its objects 3D.
	//
	/** Escala del modelo 3D (unidades del mundo 3D). Default: 1.0. */
	@:optional var modelScale:Float;
	/** Rotation inicial in X (radianes). Default: 0. */
	@:optional var modelRotX:Float;
	/** Rotation inicial in and (radianes). Default: 0. */
	@:optional var modelRotY:Float;
	/** Rotation inicial in Z (radianes). Default: 0. */
	@:optional var modelRotZ:Float;
	/** Position X of the camera 3D internal. Default: 0. */
	@:optional var modelCamX:Float;
	/** Position and of the camera 3D internal. Default: 1. */
	@:optional var modelCamY:Float;
	/** Position Z of the camera 3D internal (alejamiento). Default: 5. */
	@:optional var modelCamZ:Float;
	/** Width of the render 3D in pixels. Default: 256. */
	@:optional var sceneWidth:Int;
	/** Height of the render 3D in pixels. Default: 256. */
	@:optional var sceneHeight:Int;
	/** Si false, el modelo NO se re-renderiza cada frame (ahorra GPU). Default: true. */
	@:optional var renderEveryFrame:Bool;
	/** Direction of the luz X,and,Z (normalizado). Default: [0.5, 1.0, 0.8]. */
	@:optional var lightDir:Array<Float>;
	/** Color de fondo de la escena 3D (hex string, ej "0x000000"). Default: transparente. */
	@:optional var sceneBgColor:String;

	// ── FlxBackdrop (type: "backdrop") ───────────────────────────────────────
	//
	// Fondo infinito que se repite y puede desplazarse. Usa FlxBackdrop de flixel-addons.
	//
	// Ejemplo en el JSON del stage:
	// {
	//   "type": "backdrop",
	//   "name": "clouds",
	//   "asset": "backgrounds/clouds",
	//   "position": [0, 0],
	//   "repeatX": true,
	//   "repeatY": false,
	//   "velocityX": -60,
	//   "velocityY": 0,
	//   "scrollFactor": [0.4, 0.4],
	//   "alpha": 0.8
	// }
	//
	// The field "asset" is the key of image (igual that in sprites static).
	// velocityX/and defines the speed of desplazamiento automatic in px/s.
	// repeatX/Y controla si se repite en cada eje (default: true en ambos).

	/** Si true, el backdrop se repite en el eje X. Default: true. */
	@:optional var repeatX:Bool;
	/** Si true, el backdrop se repite en el eje Y. Default: true. */
	@:optional var repeatY:Bool;
	/** Speed of desplazamiento automatic in X (px/s). Default: 0. */
	@:optional var velocityX:Float;
	/** Speed of desplazamiento automatic in and (px/s). Default: 0. */
	@:optional var velocityY:Float;
}

typedef CustomClassInstance =
{
	var position:Array<Float>;
	@:optional var name:String;
	@:optional var scrollFactor:Array<Float>;
	@:optional var scale:Array<Float>;
	@:optional var alpha:Float;
	@:optional var flipX:Bool;
	@:optional var flipY:Bool;
	@:optional var customProperties:Dynamic;
}

typedef StageAnimation =
{
	var name:String;
	var prefix:String;
	@:optional var framerate:Int;
	@:optional var looped:Bool;
	@:optional var indices:Array<Int>;
}

typedef StageMember =
{
	var asset:String;
	var position:Array<Float>;
	@:optional var scrollFactor:Array<Float>;
	@:optional var scale:Array<Float>;
	@:optional var animations:Array<StageAnimation>;
}

class Stage extends FlxTypedGroup<FlxBasic>
{
	// ══════════════════════════════════════════════════════════════════════════
	//  cache static of DATOS of STAGE
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Cachea el contenido raw del archivo JSON de cada stage.
	 *
	 * key   → nombre del stage (p. ej. "stage_week1", "spooky")
	 * value → contenido del archivo como String (para re-parsear con loadStage)
	 *
	 * By what cachear the String and no the StageData already parsed:
	 *  • StageData contiene Arrays de StageElement, que son objetos mutables.
	 *    Compartir the same instance between multiple Stage causaría bugs.
	 *  • Cachear el String permite hacer Json.parse() cada vez (muy barato,
	 *    <0.5 ms for a JSON típico of 8 KB) without I/or of disco.
	 *  • If the mod recarga the stage, basta invalidar the entry of the cache.
	 */
	static var _dataCache:Map<String, String> = [];

	/** Invalida the cache of datos of a stage specific (recarga of mod). */
	public static function invalidateStageCache(stageName:String):Void
	{
		_dataCache.remove(stageName);
		trace('[Stage] Cache invalidado para: $stageName');
	}

	/** Clears all the cache of datos of stages. */
	public static function clearStageCache():Void
	{
		_dataCache.clear();
		trace('[Stage] All the caches of Stage limpiados.');
	}

	/**
	 * Carga y devuelve solo el StageData de un stage SIN construir sprites.
	 * Use the mismo cache that Stage.new() — I/or of disco ocurre as maximum a vez.
	 * Useful for leer fields as isPixelStage before of that currentStage exista.
	 */
	public static function getStageData(stageName:String):Null<StageData>
	{
		if (stageName == null || stageName == '') return null;
		try
		{
			var file:String = null;
			if (_dataCache.exists(stageName))
				file = _dataCache.get(stageName);
			else
			{
				file = mods.compat.ModCompatLayer.readStageFile(stageName);
				if (file != null) _dataCache.set(stageName, file);
			}
			if (file == null) return null;
			return cast mods.compat.ModCompatLayer.loadStage(file, stageName);
		}
		catch (_:Dynamic) { return null; }
	}

	public var stageData:StageData;
	public var curStage:String;

	/**
	 * Library of assets active for this stage.
	 * Se rellena desde stageData.assetLibrary al cargar el stage.
	 * null → usa curStage (comportamiento original).
	 */
	public var assetLibrary(default, null):Null<String> = null;

	/**
	 * Cuando es true, los sprites con asset no encontrado generan un placeholder
	 * visible en vez de ser omitidos. Activar SOLO en StageEditor, nunca en gameplay.
	 */
	public var isEditorPreview:Bool = false;

	// Los mapas siguen tipados como FlxSprite — FunkinSprite extiende FlxAnimate
	// that to its vez extiende FlxSprite, so that the compatibility is garantizada.
	public var elements:Map<String, FlxSprite> = new Map<String, FlxSprite>();
	public var groups:Map<String, FlxTypedGroup<FlxSprite>> = new Map<String, FlxTypedGroup<FlxSprite>>();
	public var customClasses:Map<String, FlxSprite> = new Map<String, FlxSprite>();
	public var customClassGroups:Map<String, FlxTypedGroup<FlxSprite>> = new Map<String, FlxTypedGroup<FlxSprite>>();
	public var sounds:Map<String, FlxSound> = new Map<String, FlxSound>();

	/**
	 * Elements with aboveChars:true are placed here.
	 * PlayState adds this group AFTER the characters so they render on top.
	 * Destroyed together with the Stage in destroy().
	 */
	public var aboveCharsGroup:FlxTypedGroup<FlxBasic> = new FlxTypedGroup<FlxBasic>();

	public var defaultCamZoom:Float = 1.05;
	public var isPixelStage:Bool = false;

	// Character positions
	public var boyfriendPosition:FlxPoint = new FlxPoint(770, 450);
	public var dadPosition:FlxPoint = new FlxPoint(100, 100);
	public var gfPosition:FlxPoint = new FlxPoint(400, 130);

	// Camera offsets
	public var cameraBoyfriend:FlxPoint = new FlxPoint(0, 0);
	public var cameraDad:FlxPoint = new FlxPoint(0, 0);
	/** Offset of camera for the GF. Equivalente to camera_girlfriend in Psych. */
	public var cameraGirlfriend:FlxPoint = new FlxPoint(0, 0);
	/** Multiplicador of velocidad of the lerp of camera. 1.0 = default. */
	public var cameraSpeed:Float = 1.0;

	public var gfVersion:String = 'gf';
	public var hideGirlfriend:Bool = false;

	// Callbacks for stage-specific logic
	public var onBeatHit:Void->Void = null;
	public var onStepHit:Void->Void = null;
	public var onUpdate:Float->Void = null;

	// Scripting
	public var scripts:Array<String> = [];

	private var scriptsLoaded:Bool = false;

	public function new(stageName:String)
	{
		super();
		curStage = stageName;
		// Skip loading when used internally by fromData()
		if (stageName != '__fromData__')
			loadStage(stageName);
	}
	
	function loadStage(stageName:String):Void
	{
		try
		{
			// ── Cache hit: avoid I/or of disco ────────────────────────────────
			var file:String;
			if (_dataCache.exists(stageName))
			{
				file = _dataCache.get(stageName);
				trace('[Stage] Cache hit para: $stageName');
			}
			else
			{
				file = mods.compat.ModCompatLayer.readStageFile(stageName);
				if (file != null)
				{
					_dataCache.set(stageName, file); // save in cache

					// ── Hot-reload: registrar path en JsonWatcher ─────────────
					#if sys
					if (mods.ModManager.developerMode)
					{
						var _watchPath:String = mods.compat.ModPathResolver.stageFile(stageName);
						if (_watchPath == null)
						{
							final _rel = Paths.stageJSON(stageName);
							if (sys.FileSystem.exists(_rel)) _watchPath = _rel;
						}
						if (_watchPath != null)
							funkin.debug.JsonWatcher.watch(_watchPath, 'stage', stageName);
					}
					#end
				}
			}

			if (file == null)
			{
				loadDefaultStage();
				return;
			}
			stageData = cast mods.compat.ModCompatLayer.loadStage(file, stageName);
			trace('stagefile (cached=${_dataCache.exists(stageName)}): $stageName');

			// NOTE: onStageCreate se dispara en loadStageScripts(), DESPUES de buildStage(),
			// cuando todos los elementos ya existen. No llamarlo aqui.

			if (stageData != null)
			{
				buildStage();
				trace("Loaded stage: " + stageName);
			}
			else
			{
				trace("Stage data is null for: " + stageName);
				loadDefaultStage();
			}
		}
		catch (e:Dynamic)
		{
			trace("Error loading stage " + stageName + ": " + e);
			loadDefaultStage();
		}
	}

	public function buildStage():Void
	{
		// FIX: apuntar Paths.currentStage to the stage current before of load images,
		// of it contrario imageStage() buscará in the folder of the stage previous.
		if (curStage != null && curStage != '__fromData__')
			Paths.currentStage = curStage;
		else if (stageData != null && stageData.name != null)
			Paths.currentStage = stageData.name;

		// Load basic properties
		// Scale the zoom of the stage according to resolution (fix 1080p)
		defaultCamZoom = stageData.defaultZoom;
		isPixelStage = stageData.isPixelStage;

		// Library of assets by default (puede be null → use curStage)
		assetLibrary = (stageData.assetLibrary != null && stageData.assetLibrary.trim() != '')
			? stageData.assetLibrary.trim() : null;
		if (assetLibrary != null)
			trace('[Stage] assetLibrary global: $assetLibrary (the assets without library own vienen of here)');

		if (stageData.gfVersion != null)
			gfVersion = stageData.gfVersion;

		if (stageData.hideGirlfriend != null)
			hideGirlfriend = stageData.hideGirlfriend;

		// Load positions
		if (stageData.boyfriendPosition != null)
			boyfriendPosition.set(stageData.boyfriendPosition[0], stageData.boyfriendPosition[1]);

		if (stageData.dadPosition != null)
			dadPosition.set(stageData.dadPosition[0], stageData.dadPosition[1]);

		if (stageData.gfPosition != null)
			gfPosition.set(stageData.gfPosition[0], stageData.gfPosition[1]);

		if (stageData.cameraBoyfriend != null)
			cameraBoyfriend.set(stageData.cameraBoyfriend[0], stageData.cameraBoyfriend[1]);

		if (stageData.cameraDad != null)
			cameraDad.set(stageData.cameraDad[0], stageData.cameraDad[1]);

		// BUG FIX: cameraGirlfriend y cameraSpeed eran convertidos por PsychStageConverter
		// but Stage never the leía — the fields is perdían silenciosamente.
		if (stageData.cameraGirlfriend != null)
			cameraGirlfriend.set(stageData.cameraGirlfriend[0], stageData.cameraGirlfriend[1]);

		if (stageData.cameraSpeed != null && stageData.cameraSpeed > 0)
			cameraSpeed = stageData.cameraSpeed;

		// Sort elements by zIndex
		if (stageData.elements != null)
		{
			stageData.elements.sort(function(a, b)
			{
				var azIndex = a.zIndex != null ? a.zIndex : 0;
				var bzIndex = b.zIndex != null ? b.zIndex : 0;
				return azIndex - bzIndex;
			});

			for (element in stageData.elements)
			{
				createElement(element);
			}
		}

		if (stageData.scripts != null && stageData.scripts.length > 0)
		{
			trace('[Stage] Loading scripts del stage desde JSON...');
			scripts = stageData.scripts;
			loadStageScripts();
		}
		else
		{
			trace('[Stage] Intentando cargar scripts desde carpeta...');
			#if sys
			// ── Cool Engine: stages/<name>/scripts/*.hx ──────────────────────
			var stagePath = Paths.stageScripts(curStage);
			if (sys.FileSystem.exists(stagePath))
			{
				trace('[Stage] Carpeta de scripts Cool encontrada: $stagePath');
				for (file in sys.FileSystem.readDirectory(stagePath))
				{
					if (file.endsWith('.hx') || file.endsWith('.hscript'))
						scripts.push(file);
				}
			}

			// ── Psych Engine: mods/mod/stages/<name>.lua (no scripts/ subdir) ─
			if (mods.ModManager.isActive())
			{
				final modRoot = mods.ModManager.modRoot();
				// Psych flat: mods/mod/stages/StageName.lua
				final psychLua = '$modRoot/stages/$curStage.lua';
				if (sys.FileSystem.exists(psychLua))
				{
					trace('[Stage] Found Psych Lua script: $psychLua');
					scripts.push(psychLua); // full path — loadStageScripts handles it
				}
				// Also check stages/<name>/scripts/*.lua
				final psychScriptDir = '$modRoot/stages/$curStage/scripts';
				if (sys.FileSystem.exists(psychScriptDir) && sys.FileSystem.isDirectory(psychScriptDir))
				{
					for (file in sys.FileSystem.readDirectory(psychScriptDir))
						if (file.endsWith('.lua') || file.endsWith('.hx') || file.endsWith('.hscript'))
							scripts.push('$psychScriptDir/$file');
				}
			}

			if (scripts.length > 0)
			{
				loadStageScripts();
				trace('[Stage] ${scripts.length} script(s) cargados');
			}
			else
			{
				trace('[Stage] No se encontraron scripts para el stage: $curStage');
			}
			#else
			trace('[Stage] Carga de scripts desde carpeta no disponible en esta plataforma');
			#end
		}
	}

	/**
	 * Resuelve el par (assetKey, libraryStage) para un elemento del stage.
	 *
	 * Prioridad (de mayor a menor):
	 *  1. Sintaxis corta en el campo asset:  "stage_week1:bg"  → lib="stage_week1", key="bg"
	 *  2. Campo element.assetLibrary          → lib=element.assetLibrary, key=asset
	 *  3. Campo global stageData.assetLibrary → lib=assetLibrary, key=asset
	 *  4. Comportamiento original             → lib=null (Paths usa curStage)
	 *
	 * @return  { key: String, lib: Null<String> }
	 */
	function _resolveAssetLib(element:StageElement):{ key:String, lib:Null<String> }
	{
		final raw = element.asset ?? '';

		// 1. Sintaxis corta "other_stage:asset_key"
		final colonIdx = raw.indexOf(':');
		if (colonIdx > 0)
		{
			final lib = raw.substr(0, colonIdx).trim();
			final key = raw.substr(colonIdx + 1).trim();
			if (lib != '' && key != '')
				return { key: key, lib: lib };
		}

		// 2. Per-element assetLibrary
		if (element.assetLibrary != null && element.assetLibrary.trim() != '')
			return { key: raw, lib: element.assetLibrary.trim() };

		// 3. Global assetLibrary del stage
		if (assetLibrary != null)
			return { key: raw, lib: assetLibrary };

		// 4. Sin override → usa currentStage de Paths (comportamiento original)
		return { key: raw, lib: null };
	}

	function createElement(element:StageElement):Void
	{
		switch (element.type.toLowerCase())
		{
			case "sprite":
				createSprite(element);
			case "animated":
				createAnimatedSprite(element);
			case "group":
				createGroup(element);
			case "sound":
				createSound(element);
			case "custom_class":
				createCustomClass(element);
			case "custom_class_group":
				createCustomClassGroup(element);
			// ── Modelo 3D (OBJ) ─────────────────────────────────────────────────
			case "model3d", "model_3d", "3d", "obj":
				createModel3D(element);
			// ── FlxBackdrop — fondo infinito desplazable ──────────────────────────
			// Requiere flixel-addons (flixel.addons.display.FlxBackdrop).
			case "backdrop", "flxbackdrop", "infinite", "scrolling":
				createBackdrop(element);
			default:
				trace("Unknown element type: " + element.type);
		}
	}

	/**
	 * After creating a sprite/group, decides which group it lives in.
	 * Elements with aboveChars:true go into aboveCharsGroup (rendered above characters).
	 * All others stay in the Stage group itself (rendered below characters).
	 */
	inline function _addToGroup(element:StageElement, obj:FlxBasic):Void
	{
		if (element.aboveChars == true)
			aboveCharsGroup.add(obj);
		else
			add(obj);
	}

	// ── Sprite static ───────────────────────────────────────────────────────
	// For images without animation is sigue usando FlxSprite (more lightweight).

	function createSprite(element:StageElement):Void
	{
		// FIX: usar FunkinSprite en vez de FlxSprite puro.
		// FunkinSprite.loadAsset() detecta automatically:
		//   • .xml  → Sparrow atlas   (animaciones por prefix)
		//   • .txt  → Packer atlas    (animations by index)
		//   • Animation.json → Texture Atlas de Adobe Animate / FlxAnimate
		//   • .png only → image static (comportamiento previous)
		// So, elementos of type "sprite" in the JSON also soportan atlases
		// sin necesitar cambiarse a "animated" manualmente.
		final res     = _resolveAssetLib(element);
		final assetKey = res.key.endsWith('.txt') ? res.key.replace('.txt', '') : res.key;

		var sprite:FunkinSprite = new FunkinSprite(element.position[0], element.position[1]);

		// Intentar load with auto-detection of atlas
		var loaded = false;

		// 1. Sparrow (PNG + XML)
		var stageFrames = Paths.stageSprite(assetKey, res.lib);
		if (stageFrames != null)
		{
			sprite.frames = stageFrames;
			loaded = true;
		}

		// 2. Packer (PNG + TXT)
		if (!loaded)
		{
			var packFrames = Paths.stageSpriteTxt(assetKey, res.lib);
			if (packFrames != null)
			{
				sprite.frames = packFrames;
				loaded = true;
			}
		}

		// 3. Animate atlas (carpeta con Animation.json / spritemap)
		if (!loaded)
		{
			// Buscar carpeta de atlas: stages/<lib>/images/<key>/
			var candidates = [];
			if (res.lib != null)
				candidates.push(mods.ModManager.resolveInMod('stages/${res.lib}/images/$assetKey') ?? '');
			candidates.push('assets/stages/${res.lib ?? Paths.currentStage}/images/$assetKey');
			for (folder in candidates)
			{
				#if sys
				if (folder != '' && sys.FileSystem.exists(folder)
					&& (sys.FileSystem.exists('$folder/Animation.json')
					||  sys.FileSystem.exists('$folder/spritemap1.json')))
				{
					sprite.loadAnimateAtlas(folder);
					loaded = true;
					break;
				}
				#end
			}
		}

		// 4. Image static pura (PNG without atlas)
		if (!loaded)
		{
			final bmp = Paths.imageStage(assetKey, res.lib);
			if (bmp != null)
			{
				sprite.loadGraphic(bmp);
				loaded = true;
			}
		}

		if (!loaded)
		{
			if (isEditorPreview)
			{
				trace('[Stage] createSprite: asset no encontrado para "${element.asset}" — placeholder de editor');
				_makePlaceholderGraphic(sprite, element.name ?? element.asset);
			}
			else
			{
				trace('[Stage] createSprite: imagen no encontrada para asset="${element.asset}"${res.lib != null ? ' (lib: ${res.lib})' : ''} — sprite omitido');
				return;
			}
		}

		applyElementProperties(sprite, element);
		_addToGroup(element, sprite);

		if (element.name != null)
			elements.set(element.name, sprite);
	}

	// ── Sprite animado — ahora usa FunkinSprite ───────────────────────────────

	/**
	 * createAnimatedSprite — integración FunkinSprite
	 *
	 * FunkinSprite.loadStageSparrow() detecta automatically Sparrow vs Packer.
	 * FunkinSprite.addAnim()  / playAnim() funcionan igual para ambos formatos.
	 *
	 * El JSON del stage no necesita cambios — los campos "animations" y
	 * "firstAnimation" se siguen usando exactamente igual.
	 */
	function createAnimatedSprite(element:StageElement):Void
	{
		var sprite:FunkinSprite = new FunkinSprite(element.position[0], element.position[1]);

		final res     = _resolveAssetLib(element);
		// Strip .txt extension if present (Packer assets sometimes have it in JSON)
		final assetKey = res.key.endsWith('.txt') ? res.key.replace('.txt', '') : res.key;

		// Intentar XML (Sparrow) primero, con fallback a TXT (Packer)
		var stageFrames = Paths.stageSprite(assetKey, res.lib);
		if (stageFrames == null)
			stageFrames = Paths.stageSpriteTxt(assetKey, res.lib);
		if (stageFrames != null)
			sprite.frames = stageFrames;
		else
		{
			sprite.makeGraphic(1, 1, 0x00000000);
			sprite.visible = false;
		}

		if (!sprite.visible && sprite.width <= 1 && sprite.height <= 1)
		{
			if (isEditorPreview)
			{
				trace('[Stage] createAnimatedSprite: asset no cargado para "${element.asset}"${res.lib != null ? ' (lib: ${res.lib})' : ''} — placeholder de editor');
				_makePlaceholderGraphic(sprite, element.name ?? element.asset);
				sprite.visible = true;
			}
			else
			{
				trace('[Stage] createAnimatedSprite: asset no cargado para "${element.asset}"${res.lib != null ? ' (lib: ${res.lib})' : ''} — sprite omitido');
				return;
			}
		}

		// Add animations with the API unificada
		if (element.animations != null)
		{
			for (anim in element.animations)
			{
				sprite.addAnim(anim.name, anim.prefix, anim.framerate != null ? anim.framerate : 24, anim.looped != null ? anim.looped : false,
					(anim.indices != null && anim.indices.length > 0) ? anim.indices : null);
			}

			// Play the first animation
			if (element.firstAnimation != null)
				sprite.playAnim(element.firstAnimation);
			else if (element.animations.length > 0)
				sprite.playAnim(element.animations[0].name);
		}

		applyElementProperties(sprite, element);
		_addToGroup(element, sprite);

		if (element.name != null)
			elements.set(element.name, sprite);
	}

	// ── Grupo de sprites — miembros animados usan FunkinSprite ───────────────

	function createGroup(element:StageElement):Void
	{
		var group:FlxTypedGroup<FlxSprite> = new FlxTypedGroup<FlxSprite>();

		if (element.members != null)
		{
			for (member in element.members)
			{
				// If the miembro tiene animations, usar FunkinSprite; if no, FlxSprite static
				var hasAnims = member.animations != null && member.animations.length > 0;

				// Member's library: inherits from the parent element (that to its vez hereda the global)
				// The StageMember no tienen assetLibrary own, but itself pueden usar "stage:key" syntax
				var memberLib:Null<String> = null;
				var memberKey:String       = member.asset ?? '';
				final mColonIdx = memberKey.indexOf(':');
				if (mColonIdx > 0)
				{
					memberLib = memberKey.substr(0, mColonIdx).trim();
					memberKey = memberKey.substr(mColonIdx + 1).trim();
				}
				else
				{
					// Hereda del elemento padre
					memberLib = (element.assetLibrary != null && element.assetLibrary.trim() != '')
						? element.assetLibrary.trim() : assetLibrary;
				}

				if (hasAnims)
				{
					var spr:FunkinSprite = new FunkinSprite(member.position[0], member.position[1]);
					var memberFrames = Paths.stageSprite(memberKey, memberLib);
					if (memberFrames == null)
						memberFrames = Paths.stageSpriteTxt(memberKey, memberLib);
					if (memberFrames != null)
						spr.frames = memberFrames;
					else
					{
						trace('[Stage] createGroup member: frames no encontrados para "${member.asset}"${memberLib != null ? ' (lib: $memberLib)' : ''} — miembro omitido');
						continue;
					}

					for (anim in member.animations)
					{
						spr.addAnim(anim.name, anim.prefix, anim.framerate != null ? anim.framerate : 24, anim.looped != null ? anim.looped : false,
							(anim.indices != null && anim.indices.length > 0) ? anim.indices : null);
					}

					// Play the first animation
					if (member.animations.length > 0)
						spr.playAnim(member.animations[0].name);

					if (member.scrollFactor != null)
						spr.scrollFactor.set(member.scrollFactor[0], member.scrollFactor[1]);

					if (member.scale != null)
					{
						spr.scale.set(member.scale[0], member.scale[1]);
						spr.updateHitbox();
					}

					spr.antialiasing = !isPixelStage;
					group.add(spr);
				}
				else
				{
					// No animations → FlxSprite static (more lightweight)
					final _memberBmp = Paths.imageStage(memberKey, memberLib);
					if (_memberBmp == null)
					{
						trace('[Stage] createGroup member: imagen no encontrada para "${member.asset}"${memberLib != null ? ' (lib: $memberLib)' : ''} — miembro omitido');
						continue;
					}
					var spr:FlxSprite = new FlxSprite(member.position[0], member.position[1]);
					spr.loadGraphic(_memberBmp);

					if (member.scrollFactor != null)
						spr.scrollFactor.set(member.scrollFactor[0], member.scrollFactor[1]);

					if (member.scale != null)
					{
						spr.setGraphicSize(Std.int(spr.width * member.scale[0]), Std.int(spr.height * member.scale[1]));
						spr.updateHitbox();
					}

					spr.antialiasing = !isPixelStage;
					group.add(spr);
				}
			}
		}

		_addToGroup(element, group);

		if (element.name != null)
			groups.set(element.name, group);
	}

	// ── Custom classes ────────────────────────────────────────────────────────

	function createCustomClass(element:StageElement):Void
	{
		if (element.className == null)
		{
			trace("Custom class element missing className property");
			return;
		}

		var sprite:FlxSprite = createCustomClassInstance(element.className, element.position[0], element.position[1], element.customProperties);

		if (sprite != null)
		{
			applyElementProperties(sprite, element);
			_addToGroup(element, sprite);

			if (element.name != null)
				customClasses.set(element.name, sprite);

			trace("Created custom class: " + element.className + " at " + element.position[0] + ", " + element.position[1]);
		}
		else
		{
			trace("Failed to create custom class: " + element.className);
		}
	}

	function createCustomClassGroup(element:StageElement):Void
	{
		if (element.className == null)
		{
			trace("Custom class group missing className property");
			return;
		}

		if (element.instances == null || element.instances.length == 0)
		{
			trace("Custom class group has no instances");
			return;
		}

		var group:FlxTypedGroup<FlxSprite> = new FlxTypedGroup<FlxSprite>();

		for (i in 0...element.instances.length)
		{
			var instance = element.instances[i];

			var sprite:FlxSprite = createCustomClassInstance(element.className, instance.position[0], instance.position[1], instance.customProperties);

			if (sprite != null)
			{
				if (instance.scrollFactor != null)
					sprite.scrollFactor.set(instance.scrollFactor[0], instance.scrollFactor[1]);

				if (instance.scale != null)
				{
					sprite.setGraphicSize(Std.int(sprite.width * instance.scale[0]), Std.int(sprite.height * instance.scale[1]));
					sprite.updateHitbox();
				}

				if (instance.alpha != null)
					sprite.alpha = instance.alpha;

				if (instance.flipX != null)
					sprite.flipX = instance.flipX;

				if (instance.flipY != null)
					sprite.flipY = instance.flipY;

				sprite.antialiasing = !isPixelStage;

				group.add(sprite);

				if (instance.name != null)
					customClasses.set(instance.name, sprite);

				trace("Created instance " + i + " of " + element.className);
			}
		}

		if (element.scrollFactor != null)
		{
			for (sprite in group.members)
			{
				if (sprite != null)
					sprite.scrollFactor.set(element.scrollFactor[0], element.scrollFactor[1]);
			}
		}

		_addToGroup(element, group);

		if (element.name != null)
			customClassGroups.set(element.name, group);

		trace("Created custom class group: " + element.className + " with " + group.length + " instances");
	}

	// ── Modelo 3D ─────────────────────────────────────────────────────────────

	/**
	 * createModel3D — Crea un Flx3DSprite con un modelo OBJ cargado.
	 *
	 * The sprite 3D is coloca in the position of the elemento and is registra in
	 * `stage.elements` para que los scripts puedan animarlo en runtime.
	 *
	 * Ejemplo en JSON:
	 * {
	 *   "type": "model3d",
	 *   "name": "my_rock",
	 *   "asset": "rock_formation",
	 *   "position": [800, 400],
	 *   "modelScale": 80,
	 *   "sceneWidth": 256, "sceneHeight": 256,
	 *   "modelCamZ": 4
	 * }
	 *
	 * From HScript puedes entonces acceder to it:
	 *   var spr3d = stage.getElement("my_rock");      // Flx3DSprite
	 *   spr3d.scene.objects[0].rotY += elapsed * 1.5; // animar
	 */
	function createModel3D(element:StageElement):Void
	{
		final modelName  = element.asset ?? '';
		if (modelName == '')
		{
			trace('[Stage] createModel3D: field "asset" empty.');
			return;
		}

		// Dimensiones of the escena 3D (in pixels of the render off-screen)
		final sw = element.sceneWidth  != null ? element.sceneWidth  : 256;
		final sh = element.sceneHeight != null ? element.sceneHeight : 256;

		// Position 2D in the stage
		final px = element.position != null && element.position.length > 0 ? element.position[0] : 0.0;
		final py = element.position != null && element.position.length > 1 ? element.position[1] : 0.0;

		// Create the Flx3DSprite centrado in the position
		final spr3d = new Flx3DSprite(px - sw * 0.5, py - sh * 0.5, sw, sh);

		// Scroll factor
		if (element.scrollFactor != null)
			spr3d.scrollFactor.set(element.scrollFactor[0], element.scrollFactor[1]);
		else
			spr3d.scrollFactor.set(1, 1);

		// Alpha y visibilidad
		if (element.alpha   != null) spr3d.alpha   = element.alpha;
		if (element.visible != null) spr3d.visible = element.visible;

		// Re-render each frame (puede desactivarse for models static)
		spr3d.renderEveryFrame = element.renderEveryFrame != false;

		// Camera 3D internal
		spr3d.scene.camera.position.set(
			element.modelCamX != null ? element.modelCamX : 0.0,
			element.modelCamY != null ? element.modelCamY : 1.0,
			element.modelCamZ != null ? element.modelCamZ : 5.0);
		spr3d.scene.camera.target.set(0, 0, 0);

		// Direction of luz
		if (element.lightDir != null && element.lightDir.length >= 3)
			spr3d.scene.lightDir.set(element.lightDir[0], element.lightDir[1], element.lightDir[2]).normalizeSelf();

		// Fondo transparente por defecto
		spr3d.scene.clearA = 0.0;
		if (element.sceneBgColor != null)
		{
			final c = flixel.util.FlxColor.fromString(element.sceneBgColor);
			spr3d.scene.clearR = c.redFloat;
			spr3d.scene.clearG = c.greenFloat;
			spr3d.scene.clearB = c.blueFloat;
			spr3d.scene.clearA = c.alphaFloat;
		}

		// Scales of the modelo and rotation inicial
		final mscale = element.modelScale != null ? element.modelScale : 1.0;

		// Load the mesh OBJ when the contexto 3D is listo
		final _stageName = stageData != null ? stageData.name : '';
		final _elemName  = element.name ?? modelName;

		spr3d.onReady = function()
		{
			final mesh = Model3DLoader.loadForStage(modelName, _stageName);
			if (mesh == null)
			{
				// Placeholder: cubo de debug si no se encuentra el modelo
				trace('[Stage] createModel3D: modelo "$modelName" no encontrado — usando cubo placeholder.');
				final obj = new Flx3DObject();
				obj.mesh = funkin.graphics.scene3d.Flx3DPrimitives.cube(0.5, 0.5, 0.5, 1, 0, 1, 1); // magenta
				obj.scaleX = mscale; obj.scaleY = mscale; obj.scaleZ = mscale;
				if (element.modelRotX != null) obj.rotX = element.modelRotX;
				if (element.modelRotY != null) obj.rotY = element.modelRotY;
				if (element.modelRotZ != null) obj.rotZ = element.modelRotZ;
				spr3d.scene.add(obj);
			}
			else
			{
				final obj = new Flx3DObject();
				obj.mesh = mesh;
				obj.scaleX = mscale; obj.scaleY = mscale; obj.scaleZ = mscale;
				if (element.modelRotX != null) obj.rotX = element.modelRotX;
				if (element.modelRotY != null) obj.rotY = element.modelRotY;
				if (element.modelRotZ != null) obj.rotZ = element.modelRotZ;
				spr3d.scene.add(obj);
				trace('[Stage] createModel3D: "$_elemName" listo — ${mesh.triangleCount} triangles.');
			}
		};

		_addToGroup(element, spr3d);

		if (element.name != null)
			elements.set(element.name, spr3d);

		trace('[Stage] createModel3D: "$_elemName" creado (${sw}×${sh}px, escala=$mscale).');
	}

	// ── FlxBackdrop ───────────────────────────────────────────────────────────

	/**
	 * createBackdrop — Crea un FlxBackdrop (fondo infinito desplazable).
	 *
	 * Requiere flixel-addons (flixel.addons.display.FlxBackdrop).
	 * If no is available, hace fallback to a sprite static normal.
	 *
	 * Ejemplo en JSON:
	 * {
	 *   "type": "backdrop",
	 *   "name": "cloud_layer",
	 *   "asset": "backgrounds/clouds",
	 *   "position": [0, 0],
	 *   "scrollFactor": [0.3, 0.3],
	 *   "repeatX": true,
	 *   "repeatY": false,
	 *   "velocityX": -80,
	 *   "velocityY": 0,
	 *   "alpha": 0.9
	 * }
	 *
	 * Desde HScript puedes controlarlo en runtime:
	 *   var bd = stage.getElement("cloud_layer"); // FlxBackdrop
	 *   bd.velocity.x = -120;  // acelerar
	 *   bd.alpha = 0.5;
	 */
	function createBackdrop(element:StageElement):Void
	{
		final res      = _resolveAssetLib(element);
		final assetKey = res.key;

		// ── Intentar cargar la textura ────────────────────────────────────────
		var bitmapData:openfl.display.BitmapData = null;

		// Imagen del stage
		final stageImg = Paths.imageStage(assetKey, res.lib);
		if (stageImg != null) bitmapData = stageImg;

		// Image generic if no is in the stage
		if (bitmapData == null)
		{
			try { bitmapData = Paths.getGraphic(assetKey)?.bitmap; } catch(_) {}
		}

		if (bitmapData == null)
		{
			trace('[Stage] createBackdrop: asset no encontrado para "${element.asset}" — backdrop omitido.');
			if (!isEditorPreview) return;
			// Placeholder en el editor
			bitmapData = new openfl.display.BitmapData(64, 64, false, 0xFF884488);
		}

		final px = element.position != null && element.position.length > 0 ? element.position[0] : 0.0;
		final py = element.position != null && element.position.length > 1 ? element.position[1] : 0.0;

		final repX = element.repeatX != false;  // default: true
		final repY = element.repeatY != false;  // default: true
		final velX = element.velocityX != null ? element.velocityX : 0.0;
		final velY = element.velocityY != null ? element.velocityY : 0.0;

		// ── Crear FlxBackdrop (de flixel-addons) ───────────────────────────────
		var backdrop:FlxSprite = null;
		try
		{
			var axes:FlxAxes = (repX && repY) ? FlxAxes.XY : repX ? FlxAxes.X : repY ? FlxAxes.Y : FlxAxes.XY;
			final bd = new FlxBackdrop(bitmapData, axes, 0, 0);
			bd.x = px;
			bd.y = py;
			if (velX != 0 || velY != 0)
			{
				bd.velocity.x = velX;
				bd.velocity.y = velY;
			}
			backdrop = bd;
			trace('[Stage] createBackdrop: FlxBackdrop "${ element.name ?? assetKey }" creado (axes=$axes, vel=$velX/$velY).');
		}
		catch (e:Dynamic)
		{
			trace('[Stage] createBackdrop: error creando FlxBackdrop: $and — usando sprite static.');
			backdrop = null;
		}

		// ── Fallback: FlxSprite static (if flixel-addons no available) ─────
		if (backdrop == null)
		{
			final spr = new FunkinSprite(px, py);
			spr.loadGraphic(bitmapData);
			if (repX || repY)
			{
				// Tile manual con makeGraphic (simple pero funcional)
				final sw = Std.int(FlxG.width  / bitmapData.width  + 2) * bitmapData.width;
				final sh = Std.int(FlxG.height / bitmapData.height + 2) * bitmapData.height;
				final tiled = new openfl.display.BitmapData(sw, sh, true, 0);
				var tx = 0; while (tx < sw) { var ty = 0; while (ty < sh) {
					tiled.copyPixels(bitmapData,
						new openfl.geom.Rectangle(0, 0, bitmapData.width, bitmapData.height),
						new openfl.geom.Point(tx, ty));
					ty += bitmapData.height;
				} tx += bitmapData.width; }
				spr.loadGraphic(tiled);
			}
			backdrop = spr;
			trace('[Stage] createBackdrop: FlxBackdrop no available — sprite static for "${element.name ?? assetKey}".');
		}

		// ── Propiedades comunes ───────────────────────────────────────────────
		applyElementProperties(backdrop, element);
		_addToGroup(element, backdrop);

		if (element.name != null)
			elements.set(element.name, backdrop);
	}

	private function loadStageScripts():Void
	{
		if (scriptsLoaded)
			return;

		// Build presetVars for Lua scripts: songName must be visible at top-level
		final songName = funkin.gameplay.PlayState.SONG != null ? funkin.gameplay.PlayState.SONG.song : '';
		final luaPreset:Map<String, Dynamic> = ['songName' => songName, 'stage' => this];

		for (scriptPath in scripts)
		{
			var fullPath = scriptPath;

			// Busca el script en mod activo, luego en assets
			if (!scriptPath.startsWith('assets/') && !scriptPath.startsWith('mods/') && !scriptPath.startsWith('/'))
			{
				// Also check Psych layout: mods/mod/stages/<name>.lua (no scripts/ subdir)
				final modScriptPath = mods.ModManager.resolveInMod('stages/${curStage}/scripts/$scriptPath')
					?? (scriptPath.endsWith('.lua')
						? mods.ModManager.resolveInMod('stages/$scriptPath')
						: null);
				fullPath = modScriptPath ?? 'assets/stages/${curStage}/scripts/$scriptPath';
			}

			final isLua = fullPath.endsWith('.lua');
			ScriptHandler.loadScript(fullPath, 'stage',
				isLua ? luaPreset : null,
				isLua ? this      : null);
		}

		scriptsLoaded = true;

		ScriptHandler.setOnStageScripts('stage', this);
		ScriptHandler.setOnStageScripts('currentStage', this);
		ScriptHandler.setOnStageScripts('SONG', PlayState.SONG);

		// BUGFIX: inyectar cameras before of onStageCreate.
		// PlayState.setOnScripts('camGame') se llama antes de loadStageAndCharacters(),
		// but in that momento the stage scripts still no existen → no reciben camGame.
		// Sin esto, cualquier acceso a `camGame` en onStageCreate lanza
		// EUnknownVariable in HScript, rompiendo all the function silenciosamente.
		var _ps = funkin.gameplay.PlayState.instance;
		if (_ps != null)
		{
			ScriptHandler.setOnStageScripts('camGame',      _ps.camGame);
			ScriptHandler.setOnStageScripts('camHUD',       _ps.camHUD);
			ScriptHandler.setOnStageScripts('camCountdown', _ps.camCountdown);
			ScriptHandler.setOnStageScripts('game',         _ps);
			ScriptHandler.setOnStageScripts('playState',    _ps);
		}

		ScriptHandler.callOnStageScripts('onStageCreate', []);

		trace('[Stage] Scripts loaded: ${scripts.length}');
	}

	/**
	 * Crea una instancia de una clase personalizada
	 */
	function createCustomClassInstance(className:String, x:Float, y:Float, ?customProps:Dynamic):FlxSprite
	{
		var sprite:FlxSprite = null;

		try
		{
			switch (className)
			{
				default:
					trace("Unknown custom class: " + className);
					return null;
			}
		}
		catch (e:Dynamic)
		{
			trace("Error creating custom class " + className + ": " + e);
			return null;
		}

		return sprite;
	}

	function createSound(element:StageElement):Void
	{
		var sound:FlxSound = new FlxSound().loadEmbedded(Paths.soundStage('$curStage/sounds/' + element.asset));

		if (element.volume != null)
			sound.volume = element.volume;

		if (element.looped != null)
			sound.looped = element.looped;

		FlxG.sound.list.add(sound);

		if (element.name != null)
			sounds.set(element.name, sound);
	}

	function applyElementProperties(sprite:FlxSprite, element:StageElement):Void
	{
		if (element.scrollFactor != null)
			sprite.scrollFactor.set(element.scrollFactor[0], element.scrollFactor[1]);

		if (element.scale != null)
		{
			sprite.setGraphicSize(Std.int(sprite.width * element.scale[0]), Std.int(sprite.height * element.scale[1]));
			sprite.updateHitbox();
		}

		if (element.antialiasing != null)
			sprite.antialiasing = element.antialiasing;
		else
			sprite.antialiasing = !isPixelStage;

		if (element.active != null)
			sprite.active = element.active;
		else if (element.type == 'sprite') // sprites static without animation
			sprite.active = false;         // no necesitan update() cada frame

		if (element.alpha != null)
			sprite.alpha = element.alpha;

		if (element.flipX != null)
			sprite.flipX = element.flipX;

		if (element.flipY != null)
			sprite.flipY = element.flipY;

		if (element.angle != null)
			sprite.angle = element.angle;

		if (element.color != null)
			sprite.color = FlxColor.fromString(element.color);

		if (element.blend != null)
		{
			switch (element.blend.toLowerCase())
			{
				case "add":
					sprite.blend = openfl.display.BlendMode.ADD;
				case "multiply":
					sprite.blend = openfl.display.BlendMode.MULTIPLY;
				case "screen":
					sprite.blend = openfl.display.BlendMode.SCREEN;
				default:
					sprite.blend = openfl.display.BlendMode.NORMAL;
			}
		}

		if (element.visible != null)
			sprite.visible = element.visible;
	}

	/**
	 * Generates a graphic of placeholder for the StageEditor when a asset no is encuentra.
	 * Draws a pattern of cuadros magenta/black for that the elemento sea claramente visible
	 * and seleccionable, with a scales minimal of 64×64 for that no sea invisible.
	 */
	private function _makePlaceholderGraphic(sprite:FlxSprite, label:String):Void
	{
		final SIZE = 64;
		sprite.makeGraphic(SIZE, SIZE, 0xFFFF00FF); // magenta
		// Draw cuadros negros in diagonal for the pattern checker
		final half = SIZE >> 1;
		final tile = new openfl.display.BitmapData(half, half, false, 0xFF000000);
		sprite.pixels.copyPixels(tile, tile.rect, new openfl.geom.Point(0, 0));
		sprite.pixels.copyPixels(tile, tile.rect, new openfl.geom.Point(half, half));
		sprite.dirty = true;
		sprite.updateHitbox();
	}

	function loadDefaultStage():Void
	{
		// El stage por defecto usa los assets de 'stage' (week 1).
		// Si Paths.currentStage apunta a otro stage que no existe,
		// lo redirigimos temporalmente para no romper imageStage().
		final _prevStage = Paths.currentStage;
		Paths.currentStage = 'stage_week1';

		loadStage('stage_week1');

		Paths.currentStage = _prevStage;
	}

	// ── Helper getters ────────────────────────────────────────────────────────

	public function getElement(name:String):FlxSprite
		return elements.get(name);

	public function getGroup(name:String):FlxTypedGroup<FlxSprite>
	{
		if (groups.exists(name))
			return groups.get(name);
		return customClassGroups.get(name);
	}

	public function getCustomClass(name:String):FlxSprite
		return customClasses.get(name);

	public function getCustomClassGroup(name:String):FlxTypedGroup<FlxSprite>
		return customClassGroups.get(name);

	public function getSound(name:String):FlxSound
		return sounds.get(name);

	public function callCustomMethod(elementName:String, methodName:String, ?args:Array<Dynamic>):Dynamic
	{
		var element = customClasses.get(elementName);
		if (element == null)
		{
			trace("Custom class element not found: " + elementName);
			return null;
		}

		var method = Reflect.field(element, methodName);
		if (method == null)
		{
			trace("Method not found: " + methodName);
			return null;
		}

		if (args == null)
			args = [];

		return Reflect.callMethod(element, method, args);
	}

	public function callCustomGroupMethod(groupName:String, methodName:String, ?args:Array<Dynamic>):Void
	{
		var group = customClassGroups.get(groupName);
		if (group == null)
		{
			trace("Custom class group not found: " + groupName);
			return;
		}

		if (args == null)
			args = [];

		for (sprite in group.members)
		{
			if (sprite != null)
			{
				var method = Reflect.field(sprite, methodName);
				if (method != null)
					Reflect.callMethod(sprite, method, args);
			}
		}
	}

	// ── Callbacks ─────────────────────────────────────────────────────────────

	public function beatHit(curBeat:Int):Void
	{
		if (scriptsLoaded)
			ScriptHandler.callOnStageScripts('onBeatHit', [curBeat]);

		if (onBeatHit != null)
			onBeatHit();

		for (name => sprite in customClasses)
		{
			if (Reflect.hasField(sprite, "dance"))
				Reflect.callMethod(sprite, Reflect.field(sprite, "dance"), []);
		}

		for (name => group in customClassGroups)
		{
			for (sprite in group.members)
			{
				if (sprite != null && Reflect.hasField(sprite, "dance"))
					Reflect.callMethod(sprite, Reflect.field(sprite, "dance"), []);
			}
		}
	}

	public function stepHit(curStep:Int):Void
	{
		if (scriptsLoaded)
			ScriptHandler.callOnStageScripts('onStepHit', [curStep]);

		if (onStepHit != null)
			onStepHit();
	}

	override public function update(elapsed:Float):Void
	{
		if (scriptsLoaded)
			ScriptHandler.callOnStageScripts('onUpdate', [elapsed]);

		super.update(elapsed);

		if (onUpdate != null)
			onUpdate(elapsed);

		if (scriptsLoaded)
			ScriptHandler.callOnStageScripts('onUpdatePost', [elapsed]);
	}

	override public function destroy():Void
	{
		if (scriptsLoaded)
		{
			ScriptHandler.callOnStageScripts('onDestroy', []);
			ScriptHandler.clearStageScripts();
			scriptsLoaded = false;
		}

		// Limpiar los Maps de elementos para que el GC pueda liberar las texturas.
		// Codename Engine hace esto explicitamente; sin esto los Maps retienen
		// referencias a FlxSprites aunque ya esten destruidos por super.destroy().
		elements.clear();
		groups.clear();
		customClasses.clear();
		customClassGroups.clear();

		// Destroy the above-characters group (PlayState adds it separately,
		// but Stage is responsible for cleaning it up).
		if (aboveCharsGroup != null)
		{
			aboveCharsGroup.destroy();
			aboveCharsGroup = null;
		}

		super.destroy();
	}
}
