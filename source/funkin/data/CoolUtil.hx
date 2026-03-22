package funkin.data;

using StringTools;

/**
 * CoolUtil — utilidades generales de uso frecuente.
 *
 * All the methods of load of files buscan in mods first (via Paths),
 * por lo que los mods pueden sobreescribir archivos de datos como listas de canciones.
 */
class CoolUtil
{
	/** Lista de nombres de dificultad para mostrar en UI. */
	public static var difficultyArray:Array<String> = ['EASY', 'NORMAL', 'HARD'];

	/** Sufijos de dificultad para construir paths de chart. */
	public static var difficultyPath:Array<String> = ['-easy', '', '-hard'];

	// ─── Dificultad ───────────────────────────────────────────────────────────

	/** Name of the difficulty current in uppercases. */
	public static function difficultyString():String
	{
		final diff = funkin.gameplay.PlayState.storyDifficulty;
		final diffs = funkin.menus.FreeplayState.difficultyStuff;
		if (diff >= 0 && diff < diffs.length)
			return diffs[diff][0].toUpperCase();
		if (diff >= 0 && diff < difficultyArray.length)
			return difficultyArray[diff];
		return 'NORMAL';
	}

	/**
	 * Devuelve el sufijo de dificultad actual (ej: "-hard", "-nightmare", "").
	 * Useful for load charts and audio in PlayState.
	 */
	public static function difficultySuffix():String
	{
		final diff = funkin.gameplay.PlayState.storyDifficulty;
		final diffs = funkin.menus.FreeplayState.difficultyStuff;
		if (diff >= 0 && diff < diffs.length)
			return diffs[diff][1];
		if (diff >= 0 && diff < difficultyPath.length)
			return difficultyPath[diff];
		return '';
	}

	// ─── Lectura de archivos ──────────────────────────────────────────────────

	/**
	 * Lee a file of text and returns its lines without espacios extra.
	 * Busca in the mod active first (via Paths.getText).
	 */
	public static function coolTextFile(path:String):Array<String>
		return splitTrimmed(Paths.getText(path));

	/**
	 * Divide a string in lines and elimina espacios extra of each a.
	 * Version without I/or — useful when already tienes the contenido in memory.
	 */
	public static function coolStringFile(content:String):Array<String>
		return splitTrimmed(content);

	// ─── Arrays ───────────────────────────────────────────────────────────────

	/**
	 * Crea un array de enteros [min, min+1, … max-1].
	 * Equivalente a Python `range(min, max)`.
	 */
	public static function numberArray(max:Int, min:Int = 0):Array<Int>
	{
		final arr = new Array<Int>();
		arr.resize(max - min); // reserva capacidad de una vez
		for (i in 0...(max - min))
			arr[i] = min + i;
		return arr;
	}

	// ─── Strings ──────────────────────────────────────────────────────────────

	/** Capitaliza la primera letra de un string. */
	public static inline function capitalize(s:String):String
		return s.length == 0 ? s : s.charAt(0).toUpperCase() + s.substr(1);

	/** Trunca `s` to `maxLen` caracteres, adding '…' if is truncó. */
	public static inline function truncate(s:String, maxLen:Int):String
		return s.length <= maxLen ? s : s.substr(0, maxLen - 1) + '…';

	// ─── Helpers internos ─────────────────────────────────────────────────────

	/** Divide by '\n', hace trim of each line and elimina lines vacías. */
	static function splitTrimmed(raw:String):Array<String>
	{
		final lines = raw.trim().split('\n');
		// trim in-place, sin array intermedio
		var write = 0;
		for (i in 0...lines.length)
		{
			final l = lines[i].trim();
			if (l.length > 0)
				lines[write++] = l;
		}
		lines.resize(write);
		return lines;
	}
}
