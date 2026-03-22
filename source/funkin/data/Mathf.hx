package extensions;

/**
 * Mathf — functions matemáticas of conveniencia.
 *
 * Todas las funciones son `static inline` — el compilador las elimina
 * y las reemplaza directamente por el cuerpo en el call site.
 */
class Mathf
{
	static inline var DEG_TO_RAD : Float = Math.PI / 180.0;
	static inline var RAD_TO_DEG : Float = 180.0 / Math.PI;

	// ─── Precision ────────────────────────────────────────────────────────────

	/**
	 * Redondea `number` a `decimals` cifras decimales.
	 * Ej: roundTo(3.14159, 2) → 3.14
	 */
	public static inline function roundTo(number:Float, decimals:Float):Float
	{
		final factor = Math.pow(10, decimals);
		return Math.round(number * factor) / factor;
	}

	/**
	 * Calcula el porcentaje de `value` respecto a `total`.
	 * Ej: percent(45, 100) → 45.0
	 */
	public static inline function percent(value:Float, total:Float):Float
		return total == 0 ? 0 : Math.round(value / total * 100);

	// ─── Rango ────────────────────────────────────────────────────────────────

	/** Limita `value` al rango [min, max]. */
	public static inline function clamp(value:Float, min:Float, max:Float):Float
	{
		if (value < min) return min;
		if (value > max) return max;
		return value;
	}

	/** Clamp for enteros — without conversion Float. */
	public static inline function clampInt(value:Int, min:Int, max:Int):Int
	{
		if (value < min) return min;
		if (value > max) return max;
		return value;
	}

	/** Mapea `value` del rango [inMin, inMax] al rango [outMin, outMax]. */
	public static inline function remap(value:Float, inMin:Float, inMax:Float,
	                                     outMin:Float, outMax:Float):Float
		return outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin);

	// ─── Conversion angular ───────────────────────────────────────────────────

	public static inline function toRadians(degrees:Float):Float return degrees * DEG_TO_RAD;
	public static inline function toDegrees(radians:Float):Float return radians * RAD_TO_DEG;

	// ─── Utilidades ───────────────────────────────────────────────────────────

	/** `Math.floor` como Int — evita cast manual repetido. */
	public static inline function floorInt(value:Float):Int return Std.int(Math.floor(value));

	/** `Math.ceil` como Int. */
	public static inline function ceilInt(value:Float):Int  return Std.int(Math.ceil(value));

	/** Value absoluto entero without conversion Float. */
	public static inline function absInt(value:Int):Int return value < 0 ? -value : value;

	/** Interpolation lineal between `to` and `b`. */
	public static inline function lerp(a:Float, b:Float, t:Float):Float
		return a + (b - a) * t;

	/**
	 * Generates a value senoidal continuo for a object specific.
	 *
	 * to diferencia of the version previous (static var sineShit compartida between
	 * all the callers), here the acumulador is external — each object mantiene
	 * el suyo.
	 *
	 * Uso:
	 *   var sineAcc:Float = 0;
	 *   // en update:
	 *   sineAcc  += elapsed;
	 *   sprite.y += Mathf.sine(sineAcc, 2.0) * 5;
	 */
	public static inline function sine(accumulator:Float, speed:Float = 1.0):Float
		return Math.sin(accumulator * speed);
}
