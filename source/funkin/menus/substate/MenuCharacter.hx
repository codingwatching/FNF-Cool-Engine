package funkin.menus.substate;

import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.graphics.frames.FlxAtlasFrames;
import haxe.Json;

#if sys
import sys.FileSystem;
import sys.io.File;
#else
import openfl.Assets as OpenFlAssets;
#end

// ── Typedef del JSON ──────────────────────────────────────────────────────────

typedef MenuCharacterAnimData =
{
	var name:String;        // nombre internal of the animation (ej: "idle")
	var prefix:String;      // prefijo del atlas (ej: "M BF Idle")
	var fps:Int;            // fotogramas por segundo
	var looped:Bool;        // is repite?
}

typedef MenuCharacterData =
{
	@:optional var offsetX:Float;          // offset X del sprite
	@:optional var offsetY:Float;          // offset Y del sprite
	@:optional var scale:Float;            // escala uniforme (1.0 = normal)
	@:optional var antialiasing:Bool;      // suavizado
	@:optional var flipX:Bool;             // voltear horizontalmente
	@:optional var animations:Array<MenuCharacterAnimData>;
}

// ── Clase principal ───────────────────────────────────────────────────────────

/**
 * Sprite de personaje del Story Menu.
 * Los offsets, escala y animaciones se cargan desde:
 *   assets/data/storymenu/chars/<nombre>.json
 *
 * Si el JSON no existe, usa defaults seguros (visible=false).
 * For add a character new no hace falta tocar the code:
 * solo crea el atlas en  assets/images/menu/storymenu/props/<nombre>.png/.xml
 * y su JSON en          assets/data/storymenu/chars/<nombre>.json
 */
class MenuCharacter extends FlxSprite
{
	public var character:String;

	// Ruta base de los JSONs de personajes del story menu
	private static inline final DATA_PATH:String = 'storymenu/chars/';

	public function new(x:Float, character:String = 'bf')
	{
		super(x);
		// Graphic inicial valid — guarantees that _frame never is null
		// antes de que el primer changeCharacter corra.
		makeGraphic(1, 1, 0x00000000);
		this.character = null;
		changeCharacter(character);
	}

	/**
	 * Intercepta el pipeline de render ANTES de que llegue a FlxDrawQuadsItem.
	 * If graphic or bitmap are invalid, simply no dibujamos.
	 */
	override function draw():Void
	{
		if (graphic == null || graphic.bitmap == null) return;
		super.draw();
	}

	public function changeCharacter(?character:String = 'bf'):Void
	{
		if (character == this.character) return;
		this.character = character;

		// Slot empty — ocultar without tocar frames (avoids useCount-- → cache corrupta)
		if (character == null || character == '')
		{
			visible = false;
			return;
		}

		// ── 1. Cargar atlas ───────────────────────────────────────────────────
		var atlas = Paths.getSparrowAtlas('menu/storymenu/props/' + character);
		if (atlas == null)
		{
			trace('[MenuCharacter] Atlas not found para: $character');
			visible = false;
			return;
		}
		frames = atlas;

		// Guard post-assignment
		if (graphic == null || graphic.bitmap == null)
		{
			visible = false;
			return;
		}

		// ── 2. Cargar datos desde JSON ────────────────────────────────────────
		var data:MenuCharacterData = loadData(character);

		// ── 3. Aplicar escala ─────────────────────────────────────────────────
		var sc:Float = (data.scale != null && data.scale > 0) ? data.scale : 1.0;
		if (sc != 1.0)
		{
			scale.set(sc, sc);
			setGraphicSize(Std.int(width * sc));
		}

		// ── 4. Registrar animaciones ──────────────────────────────────────────
		if (data.animations != null && data.animations.length > 0)
		{
			for (anim in data.animations)
			{
				animation.addByPrefix(anim.name, anim.prefix, anim.fps, anim.looped);
			}
		}
		else
		{
			// Fallback minimum if the JSON no tiene animations
			animation.addByPrefix('idle', 'idle', 24, true);
		}

		// ── 5. Propiedades visuales ───────────────────────────────────────────
		antialiasing = (data.antialiasing != null) ? data.antialiasing : true;
		flipX        = (data.flipX != null) ? data.flipX : false;

		// ── 6. Play idle + hitbox ─────────────────────────────────────────────
		animation.play('idle');
		updateHitbox();

		// ── 7. Aplicar offset ─────────────────────────────────────────────────
		var ox:Float = (data.offsetX != null) ? data.offsetX : 0;
		var oy:Float = (data.offsetY != null) ? data.offsetY : 0;
		offset.set(ox, oy);

		visible = true;
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	/**
	 * Carga el JSON del personaje.
	 * First busca in the mod active (to través of Paths.json),
	 * luego in assets base. If no exists returns a object empty
	 * for that the defaults of the code sean appliesdos without crashear.
	 */
	private static function loadData(character:String):MenuCharacterData
	{
		var jsonPath:String = Paths.json(DATA_PATH + character);

		var raw:String = null;

		#if sys
		if (FileSystem.exists(jsonPath))
		{
			try { raw = File.getContent(jsonPath); }
			catch (e:Dynamic) { trace('[MenuCharacter] Error leyendo JSON $character: $e'); }
		}
		#else
		if (OpenFlAssets.exists(jsonPath))
		{
			try { raw = OpenFlAssets.getText(jsonPath); }
			catch (e:Dynamic) { trace('[MenuCharacter] Error leyendo JSON $character: $e'); }
		}
		#end

		if (raw == null)
		{
			trace('[MenuCharacter] JSON not found para "$character", usando defaults.');
			return {};
		}

		try
		{
			return cast Json.parse(raw);
		}
		catch (e:Dynamic)
		{
			trace('[MenuCharacter] JSON malformado para "$character": $e');
			return {};
		}
	}
}
