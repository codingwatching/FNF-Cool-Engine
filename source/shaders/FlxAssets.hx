package shaders;

import openfl.utils.ByteArray;

@:keep @:bitmap("menu/logo.png")
class GraphicLogo extends openfl.display.BitmapData {}

/**
 * FlxShader typedef de compatibilidad.
 *
 * | Condición de compilación       | Tipo resultante                         |
 * |--------------------------------|-----------------------------------------|
 * | openfl_legacy o nme            | Dynamic (no hay sistema de shaders)     |
 * | FLX_DRAW_QUADS (Flixel 5.x)    | flixel.graphics.tile.FlxGraphicsShader  |
 * | Resto (Flixel 4.x, html5, etc) | openfl.display.Shader                   |
 *
 * NOTA: En Flixel 5.x con FLX_DRAW_QUADS activo, los shaders solo se pueden
 * aplicar a sprites individuales (sprite.shader), NO a FlxCamera via filters.
 * Para efectos de cámara usa siempre openfl.display.Shader / FlxRuntimeShader.
 */
typedef FlxShader =
	#if (openfl_legacy || nme)
	Dynamic;
	#elseif FLX_DRAW_QUADS
	flixel.graphics.tile.FlxGraphicsShader;
	#else
	openfl.display.Shader;
	#end

/**
 * VirtualInputData — datos de entrada virtual para móvil.
 *
 * Usa ByteArrayData en OpenFL 9+ y ByteArray en versiones anteriores.
 * La distinción importa porque `@:bitmap` / `@:file` generan clases distintas.
 */
@:keep @:file("titlestate/virtual-input.txt")
class VirtualInputData extends
	#if (lime >= "8.0.0")
	haxe.io.Bytes
	#elseif (openfl >= "9.0.0")
	openfl.utils.ByteArrayData
	#else
	ByteArray
	#end {}
