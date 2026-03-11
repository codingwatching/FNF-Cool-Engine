package funkin.graphics.shaders;

import flixel.FlxCamera;
import funkin.data.CameraUtil;
import openfl.filters.ShaderFilter;

/**
 * FunkinShaderFilter — Wrapper de ShaderFilter al estilo V-Slice.
 *
 * Facilita aplicar un `FunkinRuntimeShader` a una cámara de forma segura,
 * con un API limpia para añadir/quitar el efecto.
 *
 * Inspirado en el patrón usado en FunkinCrew/Funkin (V-Slice):
 *   • El ShaderFilter envuelve al shader y se aplica a `camera.filters`
 *   • Se puede activar/desactivar sin recrear el shader
 *   • Compatible con el sistema de filtros de FlxCamera en todas las versiones
 *
 * Uso:
 * ```haxe
 * // Crear efecto:
 * var fx = new FunkinShaderFilter(myShader);
 *
 * // Aplicar a cámara:
 * fx.applyTo(FlxG.camera);
 * fx.applyTo(hudCamera);
 *
 * // Actualizar uniforms (desde el update loop):
 * fx.shader.setFloat('uTime', totalElapsed);
 *
 * // Quitar de todas las cámaras:
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

	/** Cámaras a las que está aplicado actualmente. */
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
	 * Aplica el efecto a una cámara añadiendo el filter a su lista.
	 * Si ya está aplicado a esa cámara, no lo añade de nuevo.
	 *
	 * @param cam  Cámara destino. null = FlxG.camera.
	 */
	public function applyTo(?cam:FlxCamera):Void
	{
		if (cam == null) cam = flixel.FlxG.camera;
		if (_cameras.contains(cam)) return;
		CameraUtil.addFilter(filter, cam);
		_cameras.push(cam);
	}

	/**
	 * Quita el efecto de una cámara específica.
	 *
	 * @param cam  Cámara de la que quitar el efecto. null = FlxG.camera.
	 * @return     true si se eliminó con éxito.
	 */
	public function removeFrom(?cam:FlxCamera):Bool
	{
		if (cam == null) cam = flixel.FlxG.camera;
		final removed = CameraUtil.removeFilter(filter, cam);
		_cameras.remove(cam);
		return removed;
	}

	/**
	 * Quita el efecto de TODAS las cámaras a las que está aplicado.
	 */
	public function removeAll():Void
	{
		for (cam in _cameras.copy())
			removeFrom(cam);
		_cameras.resize(0);
	}

	/** Devuelve true si el efecto está actualmente aplicado a alguna cámara. */
	public var isApplied(get, never):Bool;
	inline function get_isApplied():Bool return _cameras.length > 0;

	function set_enabled(v:Bool):Bool
	{
		enabled = v;
		// Cambiar la opacidad del filter para activar/desactivar sin quitar el filter
		// (quitar y re-añadir puede cambiar el orden de los filters)
		// ShaderFilter no tiene un flag "enabled", así que usamos alpha en el shader si existe.
		// Por ahora simplemente gestionamos el flag para que el código externo lo consulte.
		return v;
	}

	/**
	 * Libera los recursos y quita el efecto de todas las cámaras.
	 */
	public function destroy():Void
	{
		removeAll();
	}
}
