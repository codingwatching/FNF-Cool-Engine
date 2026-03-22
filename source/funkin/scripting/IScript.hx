package funkin.scripting;

/**
 * IScript — interfaz común para cualquier instancia de script del engine.
 *
 * Actualmente implementada por:
 *   - LuaScriptInstance  (.lua  — linc_luajit)
 *
 * HScriptInstance NO implementa esta interfaz porque ScriptHandler la
 * gestiona directamente (el handler conoce los detalles de HScript).
 * IScript existe para el sistema Lua nativo, que tiene su propio ciclo
 * de vida independiente del ScriptHandler.
 *
 * ─── Contrato ────────────────────────────────────────────────────────────────
 *
 *   • id / filePath  — identidad del script
 *   • active         — true si el script está cargado y puede recibir calls
 *   • errored        — true si hubo un error irrecuperable
 *   • lastError      — mensaje del último error, o null
 *   • call()         — invocar una función del script por nombre
 *   • set() / get()  — leer/escribir variables globales del script
 *   • hasFunction()  — comprobar si una función existe
 *   • destroy()      — liberar todos los recursos del script
 */
interface IScript
{
	/** Identificador único del script (normalmente nombre de archivo sin ext). */
	public var id        : String;
	/** Ruta al archivo fuente, o null si se cargó desde string. */
	public var filePath  (default, null) : Null<String>;
	/** true si el script está activo y puede recibir llamadas. */
	public var active    : Bool;
	/** true si ocurrió un error irrecuperable que desactivó el script. */
	public var errored   : Bool;
	/** Texto del último error, o null. */
	public var lastError : Null<String>;

	/**
	 * Llama a la función `fn` del script con los argumentos dados.
	 * Si la función no existe o el script no está activo, devuelve null.
	 */
	public function call(fn:String, ?args:Array<Dynamic>):Dynamic;

	/**
	 * Asigna el valor `v` a la variable global `name` en el script.
	 */
	public function set(name:String, v:Dynamic):Void;

	/**
	 * Lee el valor de la variable global `name` del script.
	 * Devuelve null si la variable no existe.
	 */
	public function get(name:String):Dynamic;

	/**
	 * Devuelve true si la función global `name` está definida en el script.
	 */
	public function hasFunction(name:String):Bool;

	/**
	 * Libera todos los recursos del script (estado Lua, intérprete, etc.).
	 * Tras llamar a destroy(), active = false y el script no puede reutilizarse.
	 */
	public function destroy():Void;
}
