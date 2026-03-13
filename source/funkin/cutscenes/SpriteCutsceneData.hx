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
 *   cameraFade  → camera.fade() (fadeIn=true para "from black")
 *   cameraFlash → camera.flash()
 *   cameraShake → camera.shake()
 *   script      → llamar función en el script del mod (si existe)
 *   end         → terminar la cutscene y llamar al callback
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
	@:optional var key:String;           // clave de Paths.sound / Paths.music
	@:optional var volume:Float;
	@:optional var id:String;            // ID para waitSound

	// ── waitSound ──
	// (usa `id` de arriba)

	// ── cameraFade / cameraFlash ──
	// (usa `color`, `duration`)
	@:optional var fadeIn:Bool;          // true = fade FROM el color (en vez de hacia él)

	// ── cameraShake ──
	@:optional var intensity:Float;

	// ── script ──
	@:optional var func:String;          // nombre de función a llamar en el script
	@:optional var args:Array<Dynamic>;
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
