package funkin.system;

#if cpp
import cpp.vm.Gc;
#elseif hl
import hl.Gc;
#end
import openfl.system.System;

/**
 * MemoryUtil — control del GC y consultas de memoria.
 *
 * ─── Design ──────────────────────────────────────────────────────────────────
 * Inspirado in Codename Engine but integrado with the system of modules of
 * Cool Engine.  Use a contador of "solicitudes of desactivación" (disableCount)
 * in vez of a bool simple, for that multiple systems puedan pedir that the GC
 * is inactive independently and reactivates only when all of them have
 * liberado.
 *
 * ─── Typical usage ──────────────────────────────────────────────────────────────
 *   // Antes de cargar assets pesados (bloquea GC durante la carga):
 *   MemoryUtil.pauseGC();
 *   loadHeavyStuff();
 *   MemoryUtil.resumeGC();
 *   MemoryUtil.collectMajor();   // force ciclo after of the load
 *
 * @author  Cool Engine Team
 * @since   0.5.1
 */
class MemoryUtil
{
	// ── Estado del GC ─────────────────────────────────────────────────────────

	/** Number of calldas to pauseGC() without its correspondiente resumeGC(). */
	public static var disableCount(default, null):Int = 0;

	// ── GC control ───────────────────────────────────────────────────────────

	/**
	 * Solicita pause the GC.  The GC is desactiva only when disableCount > 0.
	 * Always acompañar with `resumeGC()` in a bloque try/finally.
	 */
	public static function pauseGC():Void
	{
		disableCount++;
		if (disableCount > 0) _disableGC();
	}

	/**
	 * Libera una pausa del GC.
	 * El GC se reactiva cuando disableCount vuelve a 0.
	 */
	public static function resumeGC():Void
	{
		if (disableCount > 0) disableCount--;
		if (disableCount == 0) _enableGC();
	}

	/**
	 * Forces a ciclo menor of the GC (fast, only generación joven).
	 * Llamar entre canciones o al cambiar de estado.
	 */
	public static function collectMinor():Void
	{
		#if (cpp || hl)
		Gc.run(false);
		#end
	}

	/**
	 * Forces a ciclo complete of the GC + compactación of the heap.
	 * Callr to the volver to the menu main or after of a load heavy.
	 * Evitar durante gameplay — provoca un stutter visible.
	 */
	public static function collectMajor():Void
	{
		#if cpp
		Gc.run(true);
		Gc.compact();
		#elseif hl
		Gc.major();
		#end
	}

	// ── Consultas de memoria ─────────────────────────────────────────────────

	/** Memoria RAM usada por el proceso en bytes. */
	public static inline function usedBytes():Float
		return System.totalMemory;

	/** Memoria RAM usada en MB (redondeado). */
	public static inline function usedMB():Int
		return Math.round(System.totalMemory / (1024 * 1024));

	/**
	 * Formatea bytes en una string legible: "152 MB" / "1.2 GB".
	 * @param bytes  Cantidad en bytes.
	 */
	public static function formatBytes(bytes:Float):String
	{
		if (bytes < 0) return "0 B";
		if (bytes < 1024) return Std.int(bytes) + " B";
		if (bytes < 1024 * 1024) return Std.int(bytes / 1024) + " KB";
		if (bytes < 1024 * 1024 * 1024)
			return Std.int(bytes / (1024 * 1024)) + " MB";
		var gb:Float = bytes / (1024 * 1024 * 1024);
		return (Math.round(gb * 10) / 10) + " GB";
	}

	// ── Internals ─────────────────────────────────────────────────────────────

	static function _enableGC():Void
	{
		#if cpp Gc.enable(true);  #end
		// HashLink: enable no-op — Gc.major() it reactiva implicitly
	}

	static function _disableGC():Void
	{
		#if cpp Gc.enable(false); #end
		// HashLink no expone disable — la pausa se simula no llamando a Gc.major()
	}
}
