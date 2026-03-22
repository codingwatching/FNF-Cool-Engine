package shaders.compat;

import flixel.addons.display.FlxRuntimeShader;
import funkin.graphics.shaders.FunkinRuntimeShader;

/**
 * ShaderCompat — Capa de compatibilidad centralizada para la API de shaders.
 *
 * Abstrae las diferencias entre versiones de flixel-addons, OpenFL y Lime
 * para que el resto del engine pueda llamar siempre a la misma API.
 *
 * ## Versiones cubiertas
 *
 * | flixel-addons | FlxRuntimeShader |  setIntArray/setBoolArray  |
 * |---------------|------------------|---------------------------|
 * | 2.11.0        | ✔ (introducido)  | ✘ (no disponible)         |
 * | 2.11.x+       | ✔                | ✔ (added later)         |
 * | 2.12.0+       | ✔                | ✔ (garantizado)           |
 *
 * | Haxe | ??= operator |
 * |------|--------------|
 * | 4.2  | ✘            |
 * | 4.3+ | ✔            |
 *
 * | OpenFL | openfl_TextureCoordv | flixel_texture2D |
 * |--------|---------------------|-----------------|
 * | 8.x    | ✔ (via pragma)      | ✔ (via pragma)  |
 * | 9.x    | ✔                   | ✔               |
 *
 * ## GLSL helper macros
 *
 * The prelude of Flixel (`#pragma header`) defines automatically:
 *   • `openfl_TextureCoordv` — coordenada UV del fragmento actual
 *   • `flixel_texture2D(sampler, uv)` — muestreo de textura con alpha premultiplicado
 *   • `openfl_TextureSize` — resolution of the texture in pixels
 *   • `bitmap` — sampler2D de la textura principal
 *
 * **No** uses `texture2D(bitmap, uv)` directamente en shaders de FlxShader:
 * usa siempre `flixel_texture2D(bitmap, uv)` para compatibilidad con
 * premultiply-alpha en todas las versiones.
 */
class ShaderCompat
{
	// ── Detection of runtime ──────────────────────────────────────────────────

	/**
	 * Returns true if the version instalada of flixel-addons tiene `setIntArray`.
	 * Se detecta en runtime via Reflect para no romper en versiones antiguas.
	 */
	public static var hasSetIntArray(get, never):Bool;
	static var _hasSetIntArray:Null<Bool> = null;

	static function get_hasSetIntArray():Bool
	{
		if (_hasSetIntArray != null) return _hasSetIntArray;
		// Create a minimal temporary instance to inspect its API
		try
		{
			final probe = new FlxRuntimeShader(null);
			_hasSetIntArray = Reflect.hasField(probe, 'setIntArray');
		}
		catch (_:Dynamic) { _hasSetIntArray = false; }
		return _hasSetIntArray;
	}

	/**
	 * Returns true if the version instalada of flixel-addons tiene `setBoolArray`.
	 */
	public static var hasSetBoolArray(get, never):Bool;
	static var _hasSetBoolArray:Null<Bool> = null;

	static function get_hasSetBoolArray():Bool
	{
		if (_hasSetBoolArray != null) return _hasSetBoolArray;
		try
		{
			final probe = new FlxRuntimeShader(null);
			_hasSetBoolArray = Reflect.hasField(probe, 'setBoolArray');
		}
		catch (_:Dynamic) { _hasSetBoolArray = false; }
		return _hasSetBoolArray;
	}

	// ── Escritura segura de uniforms ──────────────────────────────────────────

	/**
	 * Escribe un uniform en un FlxRuntimeShader de forma segura,
	 * detectando automatically the type and appliesndo the fallbacks necesarios.
	 *
	 * Is the entry point unique for modificar uniforms from code external
	 * (HScript, ScriptAPI, ShaderManager, etc.).
	 *
	 * @param shader     Shader destino
	 * @param name       Nombre del uniform GLSL
	 * @param value      Valor: Float, Int, Bool, o Array de cualquiera de ellos
	 * @return           true if the write succeeded
	 */
	public static function writeUniform(shader:FlxRuntimeShader, name:String, value:Dynamic):Bool
	{
		if (shader == null || value == null) return false;

		// Redirigir a FunkinRuntimeShader.writeUniform si es posible
		if (Std.isOfType(shader, FunkinRuntimeShader))
			return (cast shader:FunkinRuntimeShader).writeUniform(name, value);

		// Fallback for FlxRuntimeShader generic
		return _writeDynamic(shader, name, value);
	}

	/**
	 * Escribe multiple uniforms of a vez from a Map.
	 *
	 * @param shader   Shader destino
	 * @param params   Map de nombre → valor
	 * @return         Number of uniforms successfully written
	 */
	public static function writeUniforms(shader:FlxRuntimeShader, params:Map<String, Dynamic>):Int
	{
		var written = 0;
		for (name => value in params)
			if (writeUniform(shader, name, value)) written++;
		return written;
	}

	// ── Helpers internos ──────────────────────────────────────────────────────

	static function _writeDynamic(shader:FlxRuntimeShader, name:String, value:Dynamic):Bool
	{
		try
		{
			if (Std.isOfType(value, Array))
			{
				final arr:Array<Dynamic> = cast value;
				if (arr.length == 0) return false;
				final first = arr[0];
				if (Std.isOfType(first, Bool))
				{
					if (hasSetBoolArray)
						try { shader.setBoolArray(name, cast arr); return true; } catch (_:Dynamic) {}
					shader.setFloatArray(name, [for (v in arr) (v : Bool) ? 1.0 : 0.0]);
				}
				else if (Type.typeof(first) == TInt)
				{
					try { shader.setFloatArray(name, [for (v in arr) cast(v, Float)]); }
					catch (_:Dynamic)
					{
						if (hasSetIntArray)
							try { shader.setIntArray(name, [for (v in arr) Std.int(v)]); return true; }
							catch (_:Dynamic) {}
					}
				}
				else
				{
					shader.setFloatArray(name, [for (v in arr) cast(v, Float)]);
				}
			}
			else if (Std.isOfType(value, Bool))
			{
				shader.setBool(name, cast value);
			}
			else if (Type.typeof(value) == TInt)
			{
				try { shader.setFloat(name, cast(value, Float)); }
				catch (_:Dynamic) { shader.setInt(name, cast value); }
			}
			else
			{
				shader.setFloat(name, cast(value, Float));
			}
			return true;
		}
		catch (e:Dynamic) { return false; }
	}
}
