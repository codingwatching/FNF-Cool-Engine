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
 *   "rect"      → makeGraphic (rectángulo sólido de color)
 *   "image"     → imagen estática (Paths.getGraphic / images/)
 *
 *   "character" → personaje desde characters/images/
 *                 FunkinSprite.loadCharacterSparrow() detecta automáticamente:
 *                   Multi-Animate (.sheets) → Animate folder → Sparrow → Packer
 *                 Ejemplo: "image": "weeb/senpaiCrazy"
 *
 *   "stage"     → sprite de stage desde stages/
 *                 FunkinSprite.loadStageSparrow()
 *                 Ejemplo: "image": "school/schoolBG"
 *
 *   "atlas"     → asset genérico desde images/ con auto-detección:
 *   "sparrow"     FunkinSprite.loadAsset() detecta por XML/TXT/Animation.json
 *   "packer"    → mismo que "atlas" (todos usan loadAsset internamente)
 *   "animate"   → ídem, o usar "paths" para multi-atlas explícito
 *   "auto"      → alias de "atlas"
 *
 * ─── Acciones disponibles ────────────────────────────────────────────────────
 *
 *   add         → añadir sprite a la escena (alpha opcional)
 *   remove      → quitar sprite de la escena
 *   setAlpha    → cambiar alpha instantáneamente
 *   setColor    → cambiar color/tinte
 *   setVisible  → mostrar/ocultar
 *   setPosition → mover a (x, y)
 *   screenCenter→ centrar en pantalla (axis: "xy" | "x" | "y")
 *   wait        → esperar N segundos
 *   fadeTimer   → fade step-a-step con FlxTimer (como el original de FNF)
 *   tween       → FlxTween sobre propiedades del sprite
 *   playAnim    → reproducir animación
 *   playSound   → reproducir sonido (id opcional para waitSound)
 *   waitSound   → esperar a que termine un sonido con id
 *   cameraFade   → camera.fade() (fadeIn=true para "from black")
 *   cameraFlash  → camera.flash()
 *   cameraShake  → camera.shake(intensity, duration)
 *   cameraZoom   → tween del zoom de la cámara del gameplay
 *                  { "action":"cameraZoom", "zoom":1.3, "duration":0.5, "ease":"quadOut", "async":true }
 *   cameraMove   → salta la cámara a (camX, camY) instantáneamente
 *                  { "action":"cameraMove", "camX":760, "camY":450 }
 *   cameraPan    → tween de la cámara hacia (camX, camY)
 *                  { "action":"cameraPan",  "camX":760, "camY":450, "duration":1.0, "ease":"sineInOut", "async":true }
 *   cameraTween  → tween libre sobre la cámara (zoom, x, y en camProps)
 *                  { "action":"cameraTween", "camProps":{"zoom":1.2,"x":400}, "duration":0.8, "ease":"quadOut" }
 *   cameraReset  → restaura zoom a 1.0 y posición al centro de pantalla (tweeneable)
 *                  { "action":"cameraReset", "duration":0.5, "ease":"quadOut", "async":true }
 *   cameraTarget → centra la cámara en un sprite de la cutscene o del stage
 *                  { "action":"cameraTarget", "camTarget":"senpaiEvil" }
 *                  { "action":"cameraTarget", "camTarget":null }   ← dejar de seguir
 *   setCamVisible → muestra u oculta una cámara del PlayState
 *                  { "action":"setCamVisible", "cam":"hud", "visible":false }
 *                  "cam" acepta: "hud" | "game" | "countdown"
 *                  Se restaura automáticamente al terminar/saltar la cutscene.
 *   call          → ejecuta un callback registrado vía registerCallback() sin bloquear
 *                  { "action":"call", "id":"myFn" }
 *   callAsync     → ejecuta un callback que recibe done:Void->Void y bloquea hasta que lo llame
 *                  { "action":"callAsync", "id":"myFn" }
 *   waitBeat      → espera hasta que Conductor llega al beat indicado
 *                  { "action":"waitBeat", "beat":8 }
 *   waitStep      → espera hasta que Conductor llega al step indicado (1 beat = 4 steps)
 *                  { "action":"waitStep", "step":32 }
 *   script       → llamar función en el script del mod (si existe)
 *   end          → terminar la cutscene y llamar al callback
 */

// ── Definición de sprite ──────────────────────────────────────────────────────

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
	 *   "rect"      → rectángulo de color (makeGraphic)
	 *   "image"     → imagen estática desde images/
	 *   "character" → personaje desde characters/images/ (auto-detecta Multi-Animate / Sparrow / Packer)
	 *   "stage"     → sprite de stage desde stages/ (auto-detecta Sparrow / Animate)
	 *   "atlas"     → asset desde images/ con auto-detección XML/TXT/Animate (alias: "sparrow","packer","animate","auto")
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

	// ── posición inicial ──
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

// ── Definición de paso ────────────────────────────────────────────────────────

typedef CutsceneStep = {
	/** Nombre de la acción — ver lista arriba. */
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
	@:optional var step:Float;           // cuánto cambia por tick (ej. 0.15)
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
	 * Útil para música de cutscene sin moverla a la carpeta global music/.
	 */
	@:optional var music:Bool;
	/**
	 * Si true, usa Paths.soundStage() — busca en stages/<curStage>/sounds/ o music/.
	 * Combinar con music:true para música de stage:
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
	@:optional var fadeIn:Bool;          // true = fade FROM el color (en vez de hacia él)

	// ── cameraShake ──
	@:optional var intensity:Float;

	// ── cameraZoom ──
	/** Zoom objetivo de la cámara. */
	@:optional var zoom:Float;

	// ── cameraMove / cameraPan ──
	/** Posición X absoluta a la que mover la cámara (cameraMove). */
	@:optional var camX:Float;
	/** Posición Y absoluta a la que mover la cámara (cameraMove). */
	@:optional var camY:Float;

	// ── cameraTween (zoom + posición via FlxTween) ──
	/** Propiedades de cámara a tweenear: { zoom, x, y }. */
	@:optional var camProps:Dynamic;

	// ── cameraTarget ──
	/** Sprite (por ID) al que seguir con la cámara. null = dejar de seguir. */
	@:optional var camTarget:String;

	// ── setCamVisible ──
	/** Nombre de la cámara del PlayState a mostrar/ocultar: "hud" | "game" | "countdown". */
	@:optional var cam:String;
	// (usa también `visible` definido arriba)

	// ── waitBeat / waitStep ──
	/** Beat de Conductor al que esperar (waitBeat). */
	@:optional var beat:Float;

	// ── script ──
	@:optional var func:String;          // nombre de función a llamar en el script
	@:optional var args:Array<Dynamic>;

	// ── stageAnim ──
	/** Si true, la cutscene espera a que la animación termine antes de continuar. */
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
	//    { "action": "subtitleHide", "instant": true } -- sin animación
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

	/** Texto del subtítulo (action: subtitle). */
	@:optional var text:String;
	/** Tamaño de fuente del subtítulo. */
	@:optional var size:Int;
	/** Color del texto como string hex "0xFFFFFF" o nombre "WHITE". */
	@:optional var bgAlpha:Float;
	/** Si true, la acción subtitleHide no usa fade. */
	@:optional var instant:Bool;
	// color, duration, align, bold, font, y, padX, padY, fadeIn, fadeOut
	// se reutilizan de los campos ya definidos arriba:
	//   @:optional var color:String   (ya declarado para cameraFade/setColor)
	//   @:optional var duration:Float (ya declarado para tween/cameraFade)
	//   @:optional var ease:String    (ya declarado — no se usa en subtítulos)
	//   @:optional var align:String   → usar campo axis (ya existe) o añadir:
	/** Alineación del texto: "center" | "left" | "right" (action: subtitle). */
	@:optional var align:String;
	/** Negrita (action: subtitle). */
	@:optional var bold:Bool;
	/** Nombre del font en assets/fonts/ (action: subtitle). */
	@:optional var font:String;
	/** Posición Y del subtítulo en px; -1 = automático (action: subtitle). */
	@:optional var padX:Float;
	/** Padding vertical del fondo (action: subtitle). */
	@:optional var padY:Float;
}

// ── Documento completo ────────────────────────────────────────────────────────

typedef CutsceneDocument = {
	/** Mapa de sprites por ID. */
	@:optional var sprites:Dynamic;       // Map<String, CutsceneSpriteData> como objeto anónimo
	/** Secuencia de pasos a ejecutar. */
	var steps:Array<CutsceneStep>;
	/** Skippable con ESCAPE (default true). */
	@:optional var skippable:Bool;
}
