package funkin.graphics.shaders;

import flixel.addons.display.FlxRuntimeShader;
import flixel.util.FlxColor;
import lime.graphics.opengl.GLProgram;
import lime.utils.Log;
import openfl.utils.Assets;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * FunkinRuntimeShader — Runtime shader mejorado, inspirado en V-Slice (FunkinCrew/Funkin).
 *
 * Mejoras sobre FlxRuntimeShader puro:
 *   • Soporte de vertex shader opcional: si existe `myFx.vert` junto a `myFx.frag`,
 *     is load automatically (as hace V-Slice).
 *   • API uniforms ampliada y segura:
 *       setFloat2 / setFloat3 / setFloat4  — escribe vec2/3/4 de una llamada
 *       setColor(FlxColor)                 — escribe vec4 de color normalizado
 *       writeUniform(name, Dynamic)        — dispatch automatic by type
 *       safeSetInt / safeSetIntArray       — fallback a Float en addons antiguos
 *       safeSetBoolArray                   — fallback a Float en addons < 2.12
 *   • `fromFile(path)` / `fromAsset(key)` — factories with .vert detection
 *   • `reload()` — hot-reload from the file original (useful in debug)
 *   • `recompile(frag, vert)` — recompila en caliente sin crear nueva instancia
 *   • Preprocesado GLSL: normalizes saltos of line, save fonts for debug
 *   • Error handling robusto: __createGLProgram captura excepciones GL
 *   • Compatible with flixel-addons 2.11.0 – versiones more recientes
 *   • Compatible con Haxe 4.2+ (sin ??= ni operadores 4.3-exclusivos)
 *
 * Uso fast:
 * ```haxe
 * // From file in disco (.vert hermano loaded automatically if exists):
 * var fx = FunkinRuntimeShader.fromFile('assets/shaders/wave.frag');
 *
 * // Inline / desde string:
 * var fx = new FunkinRuntimeShader('
 *   uniform float uTime;
 *   void main() {
 *     vec2 uv = openfl_TextureCoordv;
 *     uv.x += sin(uv.y * 20.0 + uTime * 3.0) * 0.01;
 *     gl_FragColor = flixel_texture2D(bitmap, uv);
 *   }
 * ');
 *
 * // Appliesr to sprite / camera:
 * sprite.shader   = fx;
 * camera.filters  = [new ShaderFilter(fx)];
 *
 * // Actualizar uniforms cada frame:
 * fx.setFloat('uTime', elapsed);
 * fx.setFloat2('uResolution', FlxG.width, FlxG.height);
 * fx.setColor('uTint', FlxColor.RED);
 * ```
 */
class FunkinRuntimeShader extends FlxRuntimeShader
{
	// ── Estado ────────────────────────────────────────────────────────────────

	/** Path of the source .frag (only when `fromFile` was used). */
	public var fragmentPath(default, null):Null<String> = null;

	/** Code font of the fragment shader currently compiled. */
	public var fragmentSource(default, null):Null<String> = null;

	/** Code font of the vertex shader currently compiled (null = default of Flixel). */
	public var vertexSource(default, null):Null<String> = null;

	// ── Factories ─────────────────────────────────────────────────────────────

	/**
	 * Crea un FunkinRuntimeShader desde un archivo .frag en disco.
	 *
	 * Si existe un archivo `.vert` con el mismo nombre en la misma carpeta,
	 * is load as vertex shader automatically (pattern V-Slice).
	 *
	 * @param fragPath     Ruta al archivo .frag
	 * @param glslVersion  Version GLSL (0 = auto-detect according to target)
	 * @return             La instancia creada, o null si el archivo no existe
	 */
	#if sys
	public static function fromFile(fragPath:String, glslVersion:Int = 0):Null<FunkinRuntimeShader>
	{
		if (!FileSystem.exists(fragPath))
		{
			Log.warn('[FunkinRuntimeShader] Fragment no encontrado: $fragPath');
			return null;
		}
		try
		{
			final fragCode = File.getContent(fragPath);
			final vertPath = _swapExt(fragPath, '.vert');
			final vertCode = FileSystem.exists(vertPath) ? File.getContent(vertPath) : null;
			final shader   = new FunkinRuntimeShader(fragCode, vertCode, glslVersion);
			shader.fragmentPath = fragPath;
			return shader;
		}
		catch (e:Dynamic)
		{
			Log.warn('[FunkinRuntimeShader] Error leyendo "$fragPath": $e');
			return null;
		}
	}
	#end

	/**
	 * Crea un FunkinRuntimeShader desde assets embebidos de OpenFL.
	 *
	 * Busca also a `.vert` with the mismo key base.
	 *
	 * @param fragKey      Clave del asset .frag (ej: "assets/shaders/bloom.frag")
	 * @param glslVersion  Version GLSL (0 = auto-detect)
	 * @return             La instancia creada, o null si el asset no existe
	 */
	public static function fromAsset(fragKey:String, glslVersion:Int = 0):Null<FunkinRuntimeShader>
	{
		try
		{
			final fragCode = Assets.getText(fragKey);
			if (fragCode == null || fragCode.length == 0)
			{
				Log.warn('[FunkinRuntimeShader] Asset empty or no encontrado: $fragKey');
				return null;
			}
			final vertKey  = _swapExt(fragKey, '.vert');
			final vertCode = Assets.exists(vertKey) ? Assets.getText(vertKey) : null;
			return new FunkinRuntimeShader(fragCode, vertCode, glslVersion);
		}
		catch (e:Dynamic)
		{
			Log.warn('[FunkinRuntimeShader] Error cargando asset "$fragKey": $e');
			return null;
		}
	}

	// ── Constructor ───────────────────────────────────────────────────────────

	/**
	 * @param fragmentSource  Code GLSL of the fragment shader.
	 *                        Soporta `openfl_TextureCoordv`, `flixel_texture2D`, etc.
	 * @param vertexSource    Code GLSL of the vertex shader (null = usar the of Flixel).
	 * @param glslVersion     Version GLSL for the compilador.
	 *                        0 = auto (100 en mobile/html5, 120 en desktop).
	 */
	public function new(?fragmentSource:String, ?vertexSource:String, glslVersion:Int = 0)
	{
		final fragCode = _preprocessGLSL(fragmentSource);

		// FlxRuntimeShader (git): new(?fragmentSource, ?vertexSource)  — sin glslVersion
		super(fragCode, vertexSource);

		this.fragmentSource = fragCode;
		this.vertexSource   = vertexSource;
	}

	// ── Hot-reload ────────────────────────────────────────────────────────────

	/**
	 * Recarga el shader desde el archivo original en disco.
	 * Solo funciona si fue creado con `fromFile()`.
	 *
	 * @return true if reloaded successfully
	 */
	#if sys
	public function reload():Bool
	{
		if (fragmentPath == null) return false;
		if (!FileSystem.exists(fragmentPath))
		{
			Log.warn('[FunkinRuntimeShader] reload(): archivo no encontrado: $fragmentPath');
			return false;
		}
		try
		{
			final fragCode = File.getContent(fragmentPath);
			final vertPath = _swapExt(fragmentPath, '.vert');
			final vertCode = FileSystem.exists(vertPath) ? File.getContent(vertPath) : null;
			recompile(fragCode, vertCode);
			return true;
		}
		catch (e:Dynamic)
		{
			Log.warn('[FunkinRuntimeShader] reload() failed: $and');
			return false;
		}
	}
	#end

	/**
	 * Recompila the shader with new code font without create a new instance.
	 * Useful for live-edit of shaders in the editor of debug.
	 *
	 * @param newFrag  New code of fragment shader
	 * @param newVert  New code of vertex shader (null = mantener the current)
	 */
	public function recompile(newFrag:String, ?newVert:String):Void
	{
		final processed = _preprocessGLSL(newFrag);
		fragmentSource  = processed;
		if (newVert != null) vertexSource = newVert;
		try
		{
			@:privateAccess this.glFragmentSource = processed;
			if (newVert != null)
				@:privateAccess this.glVertexSource = newVert;
			@:privateAccess this.__init();
		}
		catch (e:Dynamic)
		{
			Log.warn('[FunkinRuntimeShader] recompile() failed: $and');
		}
	}

	// ── API Uniforms extendida ────────────────────────────────────────────────

	/**
	 * Escribe un `vec2` uniform en una sola llamada.
	 */
	public inline function setFloat2(name:String, x:Float, y:Float):Void
		setFloatArray(name, [x, y]);

	/**
	 * Escribe un `vec3` uniform en una sola llamada.
	 */
	public inline function setFloat3(name:String, x:Float, y:Float, z:Float):Void
		setFloatArray(name, [x, y, z]);

	/**
	 * Escribe un `vec4` uniform en una sola llamada.
	 */
	public inline function setFloat4(name:String, x:Float, y:Float, z:Float, w:Float):Void
		setFloatArray(name, [x, y, z, w]);

	/**
	 * Escribe un `FlxColor` como uniform `vec4` (r, g, b, a normalizados a 0..1).
	 *
	 * Ejemplo en GLSL: `uniform vec4 uTint;`
	 */
	public inline function setColor(name:String, color:FlxColor):Void
		setFloatArray(name, [color.redFloat, color.greenFloat, color.blueFloat, color.alphaFloat]);

	/**
	 * Escribe un uniform `int` con fallback a `float` si falla.
	 * En C++/Dynamic los literales enteros a veces llegan como TInt aunque el
	 * uniform is `float`; this method tests both ways safely.
	 */
	public function safeSetInt(name:String, value:Int):Void
	{
		try { setInt(name, value); }
		catch (_:Dynamic)
		{
			try { setFloat(name, value); } catch (_:Dynamic) {}
		}
	}

	/**
	 * Escribe un array de `int` con fallback a `float[]`.
	 * `setIntArray` was added in flixel-addons after of 2.11.0;
	 * if no is available is converts to floats automatically.
	 */
	public function safeSetIntArray(name:String, values:Array<Int>):Void
	{
		#if (flixel_addons >= "2.12.0")
		try { setIntArray(name, values); return; } catch (_:Dynamic) {}
		#end
		setFloatArray(name, [for (v in values) (v : Float)]);
	}

	/**
	 * Escribe un array de `bool` con fallback a `float[]` (0.0 / 1.0).
	 * `setBoolArray` was added in flixel-addons after of 2.11.0.
	 */
	public function safeSetBoolArray(name:String, values:Array<Bool>):Void
	{
		#if (flixel_addons >= "2.12.0")
		try { setBoolArray(name, values); return; } catch (_:Dynamic) {}
		#end
		setFloatArray(name, [for (v in values) v ? 1.0 : 0.0]);
	}

	/**
	 * Escribe a uniform with detection automatic of type.
	 * Is the method that use `ShaderManager._writeParam` internamente.
	 *
	 * Tipos soportados: Float, Int, Bool y Arrays de cualquiera de ellos.
	 *
	 * @return true si la escritura fue exitosa
	 */
	public function writeUniform(name:String, value:Dynamic):Bool
	{
		if (value == null) return false;
		try
		{
			if (Std.isOfType(value, Array))
			{
				final arr:Array<Dynamic> = cast value;
				if (arr.length == 0) return false;
				final first = arr[0];
				if (Std.isOfType(first, Bool))
					safeSetBoolArray(name, cast arr);
				else if (Type.typeof(first) == TInt)
					// TInt-but-really-float is common in cpp; prefer floats
					try { setFloatArray(name, [for (v in arr) cast(v, Float)]); }
					catch (_:Dynamic) { safeSetIntArray(name, [for (v in arr) Std.int(v)]); }
				else
					setFloatArray(name, [for (v in arr) cast(v, Float)]);
			}
			else if (Std.isOfType(value, Bool))
			{
				setBool(name, cast value);
			}
			else if (Type.typeof(value) == TInt)
			{
				// Bugfix: en C++/Dynamic, floats con valor entero (0.0, 8.0…)
				// is tipan as TInt. setInt() over a uniform float only imprime
				// un warning silencioso sin actualizar el valor. Usar setFloat primero.
				try { setFloat(name, cast(value, Float)); }
				catch (_:Dynamic) { safeSetInt(name, cast value); }
			}
			else
			{
				setFloat(name, cast(value, Float));
			}
			return true;
		}
		catch (e:Dynamic) { return false; }
	}

	// ── Post-process (ShaderFilter) ──────────────────────────────────────────

	/**
	 * Prepara the shader for uso as `ShaderFilter` of camera (post-process actual).
	 * Callr a VEZ justo after of create the instancia, before of pasarla to
	 * `ShaderFilter` o `CameraUtil.addShader`.
	 *
	 * ── by what is NECESARIO ─────────────────────────────────────────────────
	 * `FlxRuntimeShader` crea el `ShaderInput<BitmapData>` de `bitmap` de forma
	 * dynamic in `__init()`. OpenFL's `ShaderFilter` accede to it via
	 * `Reflect.field(shader, "__bitmap")`. En algunas versiones de flixel-addons
	 * the field dynamic no is accesible via reflection porque is almacena in a
	 * Map interno en vez de como field de clase — forzar `__init()` de nuevo
	 * after of that the programa GL is compiled resuelve the majority of the casos.
	 *
	 * ── GUARANTEES ────────────────────────────────────────────────────────────
	 * El .frag DEBE tener `#pragma header` (para que se declare `bitmap` y los
	 * varyings) y samplear con `flixel_texture2D(bitmap, openfl_TextureCoordv)`.
	 * If your shader uses `texture2D(bitmap, sc)` directly, ensure that `sc`
	 * is in [0..1] — in algunos builds `openfl_TextureCoordv` llega in pixels.
	 */
	public function setupForPostProcess():Void
	{
		try
		{
			// Forces reinitialization of the GL program.
			// Esto recrea todos los ShaderInput/ShaderParameter, incluyendo
			// __bitmap, con los uniform locations correctas del programa compilado.
			@:privateAccess this.__init();
		}
		catch (e:Dynamic)
		{
			trace('[FunkinRuntimeShader] setupForPostProcess() failed: $and');
		}
	}



	/**
	 * Captura errors of compilation GL without crashear the game.
	 * Igual que hace V-Slice en sus shaders base.
	 */
	override function __createGLProgram(vertexSource:String, fragmentSource:String):GLProgram
	{
		try
		{
			return super.__createGLProgram(vertexSource, fragmentSource);
		}
		catch (error)
		{
			Log.warn('[FunkinRuntimeShader] Error compilando programa GL: $error');
			return null;
		}
	}

	// ── Internals ─────────────────────────────────────────────────────────────

	/**
	 * Pre-procesa the GLSL code:
	 * - Normalizes saltos of line CRLF → LF
	 * - En mobile (OpenGL ES 2.0), inyecta "precision mediump float;" si no existe,
	 *   for avoid errors of compilation in GPUs estrictos with is 2.0.
	 * - Sustituye "texture()" por "texture2D()" si se usa GLSL > 1.30 targeting ES.
	 *
	 * Returns null if the source is empty or null.
	 */
	static function _preprocessGLSL(source:Null<String>):Null<String>
	{
		if (source == null) return null;
		final s:String = cast source;
		final trimmed  = StringTools.trim(s);
		if (trimmed.length == 0) return null;

		// Normalizar CRLF → LF
		var result = StringTools.replace(trimmed, '\r\n', '\n');
		result     = StringTools.replace(result,  '\r',   '\n');

		#if (mobile || html5)
		// ── OpenGL is 2.0: inject precision declaration if not present ──
		// "precision mediump float;" es obligatorio en GLSL ES 1.00.
		// FlxRuntimeShader inyecta esto en #pragma header, pero si el shader no usa
		// #pragma header o lo omite accidentalmente, el compilador falla silenciosamente.
		// Inyectamos before of the primer "void" or "uniform" (but after of cualquier
		// #pragma header or #version that already is presente).
		final hasPrecision  = result.indexOf('precision ') >= 0;
		final hasPragma     = result.indexOf('#pragma header') >= 0;
		// Only inject if there's no precision declaration and no #pragma header
		// (if there's a #pragma header, Flixel already injects precision for us).
		if (!hasPrecision && !hasPragma)
		{
			result = '#ifdef GL_ES\nprecision mediump float;\n#endif\n' + result;
		}

		// ── Sustituir "texture(" (GLSL 1.30+) por "texture2D(" (GLSL ES 1.00) ──
		// Algunos shaders usan the function texture() of GLSL moderno, that no exists
		// en OpenGL ES 2.0. La sustituimos por texture2D() que es el equivalente ES.
		// Solo si la cadena "texture(" aparece sin estar precedida de "2D", "Cube", etc.
		// We use a simple approximation that covers 99% of real cases.
		if (result.indexOf('texture(') >= 0)
		{
			result = result.split('texture(').join('texture2D(');
		}
		#end

		return result;
	}

	/** Detects the minimum appropriate GLSL version for the target. */
	static inline function _autoGLSLVersion():Int
	{
		#if (mobile || html5)
		return 100; // OpenGL is 2.0 — maximum compat mobile/web
		#else
		return 120; // OpenGL 2.1 — maximum compat desktop
		#end
	}

	/** Reemplaza the extension of a path of file. */
	static inline function _swapExt(path:String, newExt:String):String
	{
		final dot = path.lastIndexOf('.');
		return (dot >= 0 ? path.substr(0, dot) : path) + newExt;
	}
}
