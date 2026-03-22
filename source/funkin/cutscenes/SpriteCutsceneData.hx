package funkin.cutscenes;

/**
 * SpriteCutsceneData — estructuras de datos para el formato JSON de cutscenes.
 *
 * ─── Formato del JSON ────────────────────────────────────────────────────────
 *
 * {
 *   "sprites": {
 *     "black": { "type": "rect", "color": "0xFF000000", "width": 2, "height": 2, "x": -100, "y": -100 },
 *     "senpai": { "type": "atlas", "image": "weeb/senpaiCrazy", "scale": 6, "center": true,
 *       "animations": [{ "name": "idle", "prefix": "Senpai Pre Explosion", "fps": 24, "loop": false }]
 *     },
 *     "dad_anim": { "type": "animate", "paths": ["characters/dad/main", "characters/dad/extra"], "center": true,
 *       "animations": [{ "name": "idle", "prefix": "Dad Idle Dance", "fps": 24, "loop": true }]
 *     }
 *   },
 *   "steps": [
 *     { "action": "add",       "sprite": "black" },
 *     { "action": "fadeTimer", "sprite": "black", "target": 0,   "step": 0.15, "interval": 0.3 },
 *     { "action": "add",       "sprite": "senpai", "alpha": 0 },
 *     { "action": "fadeTimer", "sprite": "senpai", "target": 1,  "step": 0.15, "interval": 0.3 },
 *     { "action": "playAnim",  "sprite": "senpai", "anim": "idle" },
 *     { "action": "playSound", "key": "sounds/Senpai_Dies", "id": "dies" },
 *     { "action": "wait",      "time": 3.2 },
 *     { "action": "cameraFade","color": "WHITE", "duration": 1.6 },
 *     { "action": "waitSound", "id": "dies" },
 *     { "action": "remove",    "sprite": "senpai" },
 *     { "action": "cameraFade","color": "WHITE", "duration": 0.01, "fadeIn": true },
 *     { "action": "end" }
 *   ]
 * }
 *
 * ─── Tipos de sprite ─────────────────────────────────────────────────────────
 *
 *   "rect"      → makeGraphic (rectangle solid of color)
 *   "image"     → image static (Paths.getGraphic / images/)
 *
 *   "character" → personaje desde characters/images/
 *                 FunkinSprite.loadCharacterSparrow() detecta automatically:
 *                   Multi-Animate (.sheets) → Animate folder → Sparrow → Packer
 *                 Ejemplo: "image": "weeb/senpaiCrazy"
 *
 *   "stage"     → sprite de stage desde stages/
 *                 FunkinSprite.loadStageSparrow()
 *                 Ejemplo: "image": "school/schoolBG"
 *
 *   "atlas"     → asset generic from images/ with auto-detection:
 *   "sparrow"     FunkinSprite.loadAsset() detecta por XML/TXT/Animation.json
 *   "packer"    → mismo que "atlas" (todos usan loadAsset internamente)
 *   "animate"   → ídem, or usar "paths" for multi-atlas explicit
 *   "auto"      → alias de "atlas"
 *
 * ─── Acciones disponibles ────────────────────────────────────────────────────
 *
 *   add         → add sprite to the escena (alpha optional)
 *   remove      → quitar sprite de la escena
 *   setAlpha    → change alpha instantly
 *   setColor    → cambiar color/tinte
 *   setVisible  → mostrar/ocultar
 *   setPosition → mover a (x, y)
 *   screenCenter→ centrar en pantalla (axis: "xy" | "x" | "y")
 *   wait        → esperar N segundos
 *   fadeTimer   → fade step-a-step con FlxTimer (como el original de FNF)
 *   tween       → FlxTween sobre propiedades del sprite
 *   playAnim    → play animation
 *   playSound   → reproducir sonido (id opcional para waitSound)
 *   waitSound   → esperar a que termine un sonido con id
 *   cameraFade   → camera.fade() (fadeIn=true para "from black")
 *   cameraFlash  → camera.flash()
 *   cameraShake  → camera.shake(intensity, duration)
 *   cameraZoom   → tween of the zoom of the camera of the gameplay
 *                  { "action":"cameraZoom", "zoom":1.3, "duration":0.5, "ease":"quadOut", "async":true }
 *   cameraMove   → salta the camera to (camX, camY) instantly
 *                  { "action":"cameraMove", "camX":760, "camY":450 }
 *   cameraPan    → tween of the camera towards (camX, camY)
 *                  { "action":"cameraPan",  "camX":760, "camY":450, "duration":1.0, "ease":"sineInOut", "async":true }
 *   cameraTween  → tween libre over the camera (zoom, x, and in camProps)
 *                  { "action":"cameraTween", "camProps":{"zoom":1.2,"x":400}, "duration":0.8, "ease":"quadOut" }
 *   cameraReset  → restaura zoom to 1.0 and position to the centro of screen (tweeneable)
 *                  { "action":"cameraReset", "duration":0.5, "ease":"quadOut", "async":true }
 *   cameraTarget → centra the camera in a sprite of the cutscene or of the stage
 *                  { "action":"cameraTarget", "camTarget":"senpaiEvil" }
 *                  { "action":"cameraTarget", "camTarget":null }   ← dejar de seguir
 *   setCamVisible → muestra u oculta a camera of the PlayState
 *                  { "action":"setCamVisible", "cam":"hud", "visible":false }
 *                  "cam" acepta: "hud" | "game" | "countdown"
 *                  Is restaura automatically to the terminar/saltar the cutscene.
 *   call          → ejecuta a callback registered via registerCallback() without bloquear
 *                  { "action":"call", "id":"myFn" }
 *   callAsync     → ejecuta un callback que recibe done:Void->Void y bloquea hasta que lo llame
 *                  { "action":"callAsync", "id":"myFn" }
 *   waitBeat      → espera hasta que Conductor llega al beat indicado
 *                  { "action":"waitBeat", "beat":8 }
 *   waitStep      → espera hasta que Conductor llega al step indicado (1 beat = 4 steps)
 *                  { "action":"waitStep", "step":32 }
 *   script       → callr function in the script of the mod (if exists)
 *   end          → terminar la cutscene y llamar al callback
 */

// ── Sprite definition ──────────────────────────────────────────────────────

typedef CutsceneSpriteAnim = {
	var name:String;
	var prefix:String;
	@:optional var fps:Int;
	@:optional var loop:Bool;
	@:optional var indices:Array<Int>;
}

typedef CutsceneSpriteData = {
	/**
	 * Tipo de sprite:
	 *   "rect"      → rectangle of color (makeGraphic)
	 *   "image"     → image static from images/
	 *   "character" → personaje desde characters/images/ (auto-detecta Multi-Animate / Sparrow / Packer)
	 *   "stage"     → sprite de stage desde stages/ (auto-detecta Sparrow / Animate)
	 *   "atlas"     → asset from images/ with auto-detection XML/TXT/Animate (alias: "sparrow","packer","animate","auto")
	 *                 Para multi-atlas usar el campo `paths`.
	 */
	var type:String;

	// ── rect ──
	@:optional var color:String;         // "0xFF000000" o nombre: "BLACK", "WHITE", "RED"...
	/** Multiplicador del ancho de pantalla (1.0 = FlxG.width, 2.0 = x2). Default 1. */
	@:optional var width:Float;
	/** Multiplicador del alto de pantalla. Default 1. */
	@:optional var height:Float;

	// ── image / atlas / packer ──
	@:optional var image:String;         // clave para Paths.image / getSparrowAtlas / carpeta animate single
	@:optional var xml:String;           // clave del XML si difiere de image

	// ── animate (FlxAnimate / Adobe Animate) ──────────────────────────────────
	/**
	 * Array de rutas de carpetas para el tipo "animate".
	 * Permite cargar un personaje que tiene sus texturas repartidas en varias
	 * carpetas (ej. `characters/dad/main` + `characters/dad/hair`), igual que
	 * V-Slice MultiAnimateAtlasCharacter.
	 *
	 *   paths[0] = atlas PRINCIPAL (contiene Animation.json con los frame labels)
	 *   paths[1..] = sub-atlases (carpetas de texturas adicionales)
	 *
	 * Si solo hay una entrada se comporta igual que un single-atlas.
	 * Para sprites con `paths` se ignora el campo `image`.
	 *
	 * Ejemplo:
	 *   "paths": ["characters/dad/main", "characters/dad/extra"]
	 */
	@:optional var paths:Array<String>;

	// ── shared (atlas / packer / animate) ──
	@:optional var animations:Array<CutsceneSpriteAnim>;

	// ── position inicial ──
	@:optional var x:Float;
	@:optional var y:Float;
	@:optional var alpha:Float;
	@:optional var angle:Float;
	@:optional var scale:Float;
	@:optional var scaleX:Float;
	@:optional var scaleY:Float;
	@:optional var flipX:Bool;
	@:optional var flipY:Bool;
	@:optional var scrollFactor:Float;   // 0 = no scroll (default para cutscenes)
	@:optional var antialiasing:Bool;
	@:optional var center:Bool;          // screenCenter() al crear
	@:optional var camera:String;        // "game" | "hud" (default: "game")
}

// ── Step definition ────────────────────────────────────────────────────────

typedef CutsceneStep = {
	/** Name of the action — ver list up. */
	var action:String;

	// ── add / remove / setAlpha / setColor / setVisible / setPosition / screenCenter ──
	@:optional var sprite:String;
	@:optional var alpha:Float;
	@:optional var color:String;
	@:optional var visible:Bool;
	@:optional var x:Float;
	@:optional var y:Float;
	@:optional var axis:String;          // para screenCenter: "xy" | "x" | "y"

	// ── wait ──
	@:optional var time:Float;

	// ── fadeTimer ──
	@:optional var target:Float;         // alpha objetivo
	/** Step de Conductor al que esperar (waitStep). */
	@:optional var step:Float;           // how much changes by tick (ej. 0.15)
	@:optional var interval:Float;       // segundos entre ticks (ej. 0.3)

	// ── tween ──
	@:optional var props:Dynamic;        // { alpha: 1, x: 100, ... }
	@:optional var duration:Float;
	@:optional var ease:String;          // "quadIn", "sineOut", etc.
	@:optional var async:Bool;           // true = no esperar a que termine

	// ── playAnim ──
	@:optional var anim:String;
	@:optional var force:Bool;

	// ── playSound ──
	@:optional var key:String;           // clave del sonido
	@:optional var volume:Float;
	// ── call / callAsync ──
	/** ID del callback registrado con registerCallback(). */
	@:optional var id:String;            // ID para waitSound
	/**
	 * Si true, usa Paths.music() en vez de Paths.sound().
	 * Useful for music of cutscene without moverla to the folder global music/.
	 */
	@:optional var music:Bool;
	/**
	 * Si true, usa Paths.soundStage() — busca en stages/<curStage>/sounds/ o music/.
	 * Combinar with music:true for music of stage:
	 *   { "key":"darnellCanCutscene", "stage":true, "music":true }
	 *     → stages/phillyStreets/music/darnellCanCutscene.ogg
	 *   { "key":"Darnell_Lighter", "stage":true }
	 *     → stages/phillyStreets/sounds/Darnell_Lighter.ogg
	 */
	@:optional var stage:Bool;

	// ── waitSound ──
	// (usa `id` de arriba)

	// ── cameraFade / cameraFlash ──
	// (usa `color`, `duration`)
	@:optional var fadeIn:Bool;          // true = fade FROM the color (in vez of towards it)

	// ── cameraShake ──
	@:optional var intensity:Float;

	// ── cameraZoom ──
	/** Zoom objetivo of the camera. */
	@:optional var zoom:Float;

	// ── cameraMove / cameraPan ──
	/** Position X absoluta to the that move the camera (cameraMove). */
	@:optional var camX:Float;
	/** Position and absoluta to the that move the camera (cameraMove). */
	@:optional var camY:Float;

	// ── cameraTween (zoom + position via FlxTween) ──
	/** Propiedades of camera to tweenear: { zoom, x, and }. */
	@:optional var camProps:Dynamic;

	// ── cameraTarget ──
	/** Sprite (by ID) to the that seguir with the camera. null = dejar of seguir. */
	@:optional var camTarget:String;

	// ── setCamVisible ──
	/** Nombre of the camera of the PlayState to mostrar/ocultar: "hud" | "game" | "countdown". */
	@:optional var cam:String;
	// (use also `visible` definido arriba)

	// ── waitBeat / waitStep ──
	/** Beat de Conductor al que esperar (waitBeat). */
	@:optional var beat:Float;

	// ── script ──
	@:optional var func:String;          // nombre of function to callr in the script
	@:optional var args:Array<Dynamic>;

	// ── stageAnim ──
	/** If true, the cutscene waits to that the animation termine before of continuar. */
	@:optional var wait:Bool;

	// ── subtitle / subtitleHide / subtitleClear / subtitleStyle ──────────────
	//
	//  subtitle:
	//    { "action": "subtitle", "text": "Hello World", "duration": 3.0 }
	//    { "action": "subtitle", "text": "Hello", "duration": 2.0,
	//      "size": 28, "color": "0xFFFF00", "bgColor": "0x000000", "bgAlpha": 0.7,
	//      "align": "center", "bold": true, "font": "vcr.ttf",
	//      "y": 620, "padX": 16, "padY": 10,
	//      "fadeIn": 0.2, "fadeOut": 0.3 }
	//
	//  subtitleHide:
	//    { "action": "subtitleHide" }                  -- fade suave
	//    { "action": "subtitleHide", "instant": true } -- without animation
	//
	//  subtitleClear:
	//    { "action": "subtitleClear" }
	//
	//  subtitleStyle:  (aplica estilo global para futuros subtitles)
	//    { "action": "subtitleStyle", "size": 28, "color": "0xFFFFFF",
	//      "bgAlpha": 0.6, "align": "center" }
	//
	//  subtitleResetStyle:
	//    { "action": "subtitleResetStyle" }

	/** Text of the subtitle (action: subtitle). */
	@:optional var text:String;
	/** Size of font of the subtitle. */
	@:optional var size:Int;
	/** Color del texto como string hex "0xFFFFFF" o nombre "WHITE". */
	@:optional var bgAlpha:Float;
	/** If true, the action subtitleHide no use fade. */
	@:optional var instant:Bool;
	// color, duration, align, bold, font, y, padX, padY, fadeIn, fadeOut
	// se reutilizan de los campos ya definidos arriba:
	//   @:optional var color:String   (ya declarado para cameraFade/setColor)
	//   @:optional var duration:Float (ya declarado para tween/cameraFade)
	//   @:optional var ease:String    (already declarado — no is use in subtitles)
	//   @:optional var align:String   → usar field axis (already exists) or add:
	/** Alineación of the text: "center" | "left" | "right" (action: subtitle). */
	@:optional var align:String;
	/** Negrita (action: subtitle). */
	@:optional var bold:Bool;
	/** Nombre del font en assets/fonts/ (action: subtitle). */
	@:optional var font:String;
	/** Position and of the subtitle in px; -1 = automatic (action: subtitle). */
	@:optional var padX:Float;
	/** Padding vertical del fondo (action: subtitle). */
	@:optional var padY:Float;
}

// ── Documento completo ────────────────────────────────────────────────────────

typedef CutsceneDocument = {
	/** Mapa de sprites por ID. */
	@:optional var sprites:Dynamic;       // Map<String, CutsceneSpriteData> as object anónimo
	/** Secuencia de pasos a ejecutar. */
	var steps:Array<CutsceneStep>;
	/** Skippable con ESCAPE (default true). */
	@:optional var skippable:Bool;
}
