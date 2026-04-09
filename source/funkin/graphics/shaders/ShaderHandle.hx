package funkin.graphics.shaders;

import flixel.FlxCamera;
import flixel.FlxSprite;
import openfl.filters.ShaderFilter;

/**
 * ShaderHandle — manejador de instancia para un shader nombrado.
 *
 * Permite controlar los uniforms de un shader directamente como propiedades,
 * tanto desde Haxe compilado como desde scripts HScript y Lua.
 *
 * ─── HScript ──────────────────────────────────────────────────────────────────
 *
 *   var wave = new ShaderHandle('wave');
 *   wave.applyTo(mySprite);
 *
 *   // En update() — asignación directa redirige a ShaderManager:
 *   wave.uTime      = elapsed;
 *   wave.uIntensity = 0.5;
 *
 * ─── Lua ──────────────────────────────────────────────────────────────────────
 *
 *   local wave = ShaderHandle.new('wave')
 *   wave:applyTo(mySprite)
 *
 *   -- En update — usar set() (Lua no pasa por Reflect.__set):
 *   wave:set('uTime', elapsed)
 *   wave:setFloat2('uResolution', FlxG.width, FlxG.height)
 *
 * ─── Haxe compilado ───────────────────────────────────────────────────────────
 *
 *   var contrast:ShaderHandle = new ShaderHandle('contrast');
 *   contrast.applyTo(mySprite);
 *   contrast.uAmount = 1.3;   // → ShaderManager.setShaderParam('contrast', 'uAmount', 1.3)
 *
 * ─── Encadenamiento fluent ────────────────────────────────────────────────────
 *
 *   new ShaderHandle('bloom')
 *       .applyToCamera()
 *       .set('uThreshold', 0.6)
 *       .set('uIntensity', 1.2);
 *
 * ─── Cómo funciona __set / resolve ────────────────────────────────────────────
 *
 *  En targets nativos (C++ / HashLink) y en HScript (que usa Reflect.setField):
 *    `handle.foo = bar`  →  `__set("foo", bar)`  →  ShaderManager.setShaderParam
 *    `handle.foo`        →  `resolve("foo")`      →  último valor cacheado
 *
 *  En Lua la asignación de campo no pasa por Reflect, así que usa set() siempre.
 *
 * @see funkin.graphics.shaders.ShaderManager
 */
class ShaderHandle
{
	// ── Identificación ────────────────────────────────────────────────────────

	/** Nombre del shader (coincide con el .frag / .hx / .lua sin extensión). */
	public var shaderName(default, null):String;

	// Cache local de los últimos valores enviados — devueltos por resolve()
	var _params:Map<String, Dynamic> = new Map();

	// ── Constructor ───────────────────────────────────────────────────────────

	/**
	 * @param shaderName  Nombre del shader registrado en ShaderManager
	 *                    (ej: 'wave', 'contrast', 'chromaShift')
	 */
	public function new(shaderName:String)
	{
		this.shaderName = shaderName;
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// APLICAR / QUITAR
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Aplica este shader a un sprite.
	 * @return  `this` para encadenamiento fluent
	 */
	public function applyTo(sprite:FlxSprite, ?camera:FlxCamera):ShaderHandle
	{
		ShaderManager.applyShader(sprite, shaderName, camera);
		return this;
	}

	/**
	 * Aplica este shader como overlay de pantalla completa en una cámara.
	 * Usa un sprite overlay interno — no necesita #pragma header.
	 * @return  `this` para encadenamiento fluent
	 */
	public function applyToCamera(?cam:FlxCamera):ShaderHandle
	{
		ShaderManager.applyShaderToCamera(shaderName, cam);
		return this;
	}

	/**
	 * Aplica como post-proceso real en la cámara (lee los píxeles de la cámara).
	 * El .frag DEBE tener `#pragma header` y usar `flixel_texture2D(bitmap, uv)`.
	 * @return  El ShaderFilter creado (necesario para quitarlo con CameraUtil.removeFilter)
	 */
	public function applyPostProcess(?cam:FlxCamera):ShaderFilter
		return ShaderManager.applyPostProcessToCamera(shaderName, cam);

	/** Quita el shader de un sprite. */
	public function removeFrom(sprite:FlxSprite):ShaderHandle
	{
		ShaderManager.removeShader(sprite);
		return this;
	}

	/** Quita el overlay de cámara creado con applyToCamera(). */
	public function removeFromCamera(?cam:FlxCamera):ShaderHandle
	{
		ShaderManager.removeShaderFromCamera(shaderName, cam);
		return this;
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// UNIFORMS — API EXPLÍCITA (funciona en todos los targets, incluido Lua)
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Envía cualquier uniform al shader.
	 * Acepta Float, Int, Bool, Array<Float> (vec2/3/4), etc.
	 * @return `this` para encadenamiento fluent
	 */
	public function set(paramName:String, value:Dynamic):ShaderHandle
	{
		_params.set(paramName, value);
		ShaderManager.setShaderParam(shaderName, paramName, value);
		return this;
	}

	/** float uniform. */
	public function setFloat(paramName:String, v:Float):ShaderHandle
		return set(paramName, v);

	/** vec2 uniform. */
	public function setFloat2(paramName:String, x:Float, y:Float):ShaderHandle
		return set(paramName, [x, y]);

	/** vec3 uniform. */
	public function setFloat3(paramName:String, x:Float, y:Float, z:Float):ShaderHandle
		return set(paramName, [x, y, z]);

	/** vec4 uniform. */
	public function setFloat4(paramName:String, x:Float, y:Float, z:Float, w:Float):ShaderHandle
		return set(paramName, [x, y, z, w]);

	/** int uniform (usa setInt de FunkinRuntimeShader, más seguro para tipos int GLSL). */
	public function setInt(paramName:String, v:Int):ShaderHandle
	{
		_params.set(paramName, v);
		ShaderManager.setShaderParamInt(shaderName, paramName, v);
		return this;
	}

	/** bool uniform. */
	public function setBool(paramName:String, v:Bool):ShaderHandle
		return set(paramName, v);

	/**
	 * vec4 uniform desde un color 0xAARRGGBB.
	 * Equivalente a setFloat4(name, r/255, g/255, b/255, a/255).
	 */
	public function setColor(paramName:String, color:Int):ShaderHandle
		return set(paramName, color); // FunkinRuntimeShader.writeUniform detecta Int → vec4 color

	/** Devuelve el último valor enviado a un uniform (del cache local). */
	public function get(paramName:String):Dynamic
		return _params.get(paramName);

	// ═══════════════════════════════════════════════════════════════════════════
	// DYNAMIC FIELD INTERCEPTION
	// Targets nativos (C++ / HashLink) + HScript (via Reflect.setField / getField)
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Intercepta `handle.uTime = elapsed` en C++, HashLink y HScript.
	 * Redirige automáticamente a ShaderManager.setShaderParam.
	 *
	 * No interfiere con los campos reales de la clase (shaderName, _params, etc.)
	 * — esos ya los resuelve el compilador antes de llegar aquí.
	 */
	@:noCompletion
	public function __set(name:String, value:Dynamic):Dynamic
	{
		_params.set(name, value);
		ShaderManager.setShaderParam(shaderName, name, value);
		return value;
	}

	/**
	 * Intercepta `handle.uTime` en C++, HashLink y HScript.
	 * Devuelve el último valor cacheado localmente.
	 */
	@:noCompletion
	public function resolve(name:String):Dynamic
		return _params.get(name);

	// ═══════════════════════════════════════════════════════════════════════════
	// UTILIDADES
	// ═══════════════════════════════════════════════════════════════════════════

	/** Recarga el shader desde disco (útil en desarrollo). */
	public function reload():Bool
		return ShaderManager.reloadShader(shaderName);

	/** Limpia el cache local de params (no afecta las instancias GL activas). */
	public function clearCache():Void
		_params.clear();

	public function toString():String
		return 'ShaderHandle($shaderName)';
}
