package funkin.data;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.system.FlxAssets.FlxShader;
import openfl.filters.BitmapFilter;
import openfl.filters.ShaderFilter;

/**
 * CameraUtil — helpers para manipular FlxCamera de forma segura y consistente.
 *
 * Usa `@:access(flixel.FlxCamera)` a nivel de clase en vez de esparcir
 * `@:privateAccess` by all the code base — pattern tomado of NightmareVision.
 * This also is it that causaba the error of compilation:
 *   "flixel.FlxCamera has no field filters (Suggestion: _filters)"
 * The API public of FlxCamera in Flixel git expone `filters` (already no `_filters`).
 * Esta clase centraliza todos los accesos a ese campo.
 *
 * @author  Cool Engine Team
 * @since   0.5.1
 */
class CameraUtil
{
	// ── Creation ──────────────────────────────────────────────────────────────

	/**
	 * Creates a camera new with bgColor transparente and opcionalmente the adds
	 * al stack de FlxG.cameras.
	 * @param addToStack  If true (default), the adds as camera no-default.
	 */
	public static function create(addToStack:Bool = true):FlxCamera
	{
		var cam:FlxCamera = new FlxCamera();
		cam.bgColor = 0x00000000; // transparente — no gasta fill-rect cada frame
		if (addToStack)
			FlxG.cameras.add(cam, false);
		return cam;
	}

	// ── Filtros / Shaders ─────────────────────────────────────────────────────

	/**
	 * Returns the array of filtros of the camera, creándolo if no exists.
	 * Use the field public `filters` of FlxCamera.
	 */
	public static inline function getFilters(cam:FlxCamera):Array<BitmapFilter>
	{
		if (cam.filters == null) cam.filters = [];
		return cam.filters;
	}

	/**
	 * Reemplaza all the filtros of the camera of a vez.
	 * Pasa null or array empty for quitar all the filtros
	 * (evita el render-pass off-screen innecesario).
	 */
	public static inline function setFilters(cam:FlxCamera, filters:Array<BitmapFilter>):Void
	{
		cam.filters = (filters != null && filters.length > 0) ? filters : null;
	}

	/**
	 * Adds a shader to the camera.
	 * @param shader  Shader a aplicar.
	 * @param cam     Camera destino. Default: FlxG.camera.
	 * @return The ShaderFilter creado (for poder quitarlo after).
	 */
	// NOTE: cam.filters es propiedad con setter en Flixel git.
	// .push() modifica el array SIN llamar al setter → pipeline no se
	// reconstruye → shader no se aplica → pantalla negra.
	// Siempre copiar, modificar, y reasignar para disparar el setter.

	public static function addShader(shader:FlxShader, ?cam:FlxCamera):ShaderFilter
	{
		if (cam == null) cam = FlxG.camera;
		var filter:ShaderFilter = new ShaderFilter(shader);
		var arr = cam.filters != null ? cam.filters.copy() : [];
		arr.push(filter);
		cam.filters = arr;
		return filter;
	}

	public static function addFilter(filter:BitmapFilter, ?cam:FlxCamera):Void
	{
		if (cam == null) cam = FlxG.camera;
		var arr = cam.filters != null ? cam.filters.copy() : [];
		if (!arr.contains(filter))
		{
			arr.push(filter);
			cam.filters = arr;
		}
	}

	public static function removeFilter(filter:BitmapFilter, ?cam:FlxCamera):Bool
	{
		if (cam == null) cam = FlxG.camera;
		if (cam.filters == null) return false;
		var arr = cam.filters.copy();
		var removed = arr.remove(filter);
		cam.filters = arr.length > 0 ? arr : null;
		return removed;
	}

	/**
	 * Elimina all the filtros of the camera.
	 */
	public static inline function clearFilters(?cam:FlxCamera):Void
	{
		if (cam == null) cam = FlxG.camera;
		cam.filters = null;
	}

	/**
	 * Elimina filtros empty or nulos of the array internal.
	 * Useful for clear without quitar filtros activos.
	 */
	public static function pruneEmptyFilters(?cam:FlxCamera):Void
	{
		if (cam == null) cam = FlxG.camera;
		if (cam.filters == null) return;
		cam.filters = cam.filters.filter(f -> f != null);
		if (cam.filters.length == 0) cam.filters = null;
	}

	// ── Optimization ──────────────────────────────────────────────────────────

	/**
	 * Applies configuration of rendering óptima to a camera of gameplay.
	 * - Without filtros empty (avoids the off-screen render pass).
	 * - bgColor transparente (avoids fill-rect if there is otra camera of fondo).
	 *
	 * No callr in the camera main if this is the single — necesita clear.
	 */
	public static function optimizeForGameplay(cam:FlxCamera):Void
	{
		if (cam == null) return;
		pruneEmptyFilters(cam);
	}

	/**
	 * Returns the last camera of the stack (the of the HUD normalmente).
	 */
	public static var lastCamera(get, never):FlxCamera;
	static inline function get_lastCamera():FlxCamera
		return FlxG.cameras.list[FlxG.cameras.list.length - 1];
}
