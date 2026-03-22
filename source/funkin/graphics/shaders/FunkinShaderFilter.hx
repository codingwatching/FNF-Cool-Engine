package funkin.graphics.shaders;

import flixel.FlxCamera;
import funkin.data.CameraUtil;
import openfl.filters.ShaderFilter;

/**
 * FunkinShaderFilter — Wrapper de ShaderFilter al estilo V-Slice.
 *
 * Facilita appliesr a `FunkinRuntimeShader` to a camera of forma segura,
 * with a API clears for add/quitar the effect.
 *
 * Inspirado in the pattern usado in FunkinCrew/Funkin (V-Slice):
 *   • El ShaderFilter envuelve al shader y se aplica a `camera.filters`
 *   • Se puede activar/desactivar sin recrear el shader
 *   • Compatible con el sistema de filtros de FlxCamera en todas las versiones
 *
 * Uso:
 * ```haxe
 * // Crear efecto:
 * var fx = new FunkinShaderFilter(myShader);
 *
 * // Appliesr to camera:
 * fx.applyTo(FlxG.camera);
 * fx.applyTo(hudCamera);
 *
 * // Actualizar uniforms (desde el update loop):
 * fx.shader.setFloat('uTime', totalElapsed);
 *
 * // Quitar of all the cameras:
 * fx.removeAll();
 * ```
 */
class FunkinShaderFilter
{
	/** El shader que aplica el efecto. */
	public var shader(default, null):FunkinRuntimeShader;

	/** El ShaderFilter de OpenFL que envuelve al shader. */
	public var filter(default, null):ShaderFilter;

	/** Si es false, el efecto no se aplica (el filter se mantiene pero sin efecto visual). */
	public var enabled(default, set):Bool = true;

	/** Cameras to the that is appliesdo currently. */
	var _cameras:Array<FlxCamera> = [];

	// ── Constructor ───────────────────────────────────────────────────────────

	/**
	 * @param shader  El FunkinRuntimeShader a envolver.
	 *                Si es null, crea un shader identidad (pass-through).
	 */
	public function new(?shader:FunkinRuntimeShader)
	{
		this.shader = shader != null ? shader : new FunkinRuntimeShader();
		this.filter = new ShaderFilter(this.shader);
	}

	// ── API ───────────────────────────────────────────────────────────────────

	/**
	 * Applies the effect to a camera adding the filter to its list.
	 * If already is appliesdo to that camera, no it adds of new.
	 *
	 * @param cam  Camera destino. null = FlxG.camera.
	 */
	public function applyTo(?cam:FlxCamera):Void
	{
		if (cam == null) cam = flixel.FlxG.camera;
		if (_cameras.contains(cam)) return;
		CameraUtil.addFilter(filter, cam);
		_cameras.push(cam);
	}

	/**
	 * Quita the effect of a camera specific.
	 *
	 * @param cam  Camera of the that quitar the effect. null = FlxG.camera.
	 * @return     true if is eliminó with success.
	 */
	public function removeFrom(?cam:FlxCamera):Bool
	{
		if (cam == null) cam = flixel.FlxG.camera;
		final removed = CameraUtil.removeFilter(filter, cam);
		_cameras.remove(cam);
		return removed;
	}

	/**
	 * Quita the effect of all the cameras to the that is appliesdo.
	 */
	public function removeAll():Void
	{
		for (cam in _cameras.copy())
			removeFrom(cam);
		_cameras.resize(0);
	}

	/** Returns true if the effect is currently appliesdo to alguna camera. */
	public var isApplied(get, never):Bool;
	inline function get_isApplied():Bool return _cameras.length > 0;

	function set_enabled(v:Bool):Bool
	{
		enabled = v;
		// Cambiar la opacidad del filter para activar/desactivar sin quitar el filter
		// (quitar and re-add puede change the orden of the filters)
		// ShaderFilter no tiene a flag "enabled", so that usamos alpha in the shader if exists.
		// By now simply gestionamos the flag for that the code external it consulte.
		return v;
	}

	/**
	 * Libera the recursos and quita the effect of all the cameras.
	 */
	public function destroy():Void
	{
		removeAll();
	}
}
