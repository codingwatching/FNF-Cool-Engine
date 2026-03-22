package funkin.scripting;

/**
 * IScript — interface common for any instance of script of the engine.
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
 *   • active         — true if the script is loaded and puede receive calls
 *   • errored        — true si hubo un error irrecuperable
 *   • lastError      — mensaje of the last error, or null
 *   • call()         — invocar a function of the script by nombre
 *   • set() / get()  — leer/escribir variables globales del script
 *   • hasFunction()  — check if a function exists
 *   • destroy()      — liberar todos los recursos del script
 */
interface IScript
{
	/** Identificador unique of the script (normalmente nombre of file without ext). */
	public var id        : String;
	/** Path to the file font, or null if is cargó from string. */
	public var filePath  (default, null) : Null<String>;
	/** true if the script is active and puede receive calldas. */
	public var active    : Bool;
	/** true if ocurrió a error irrecuperable that desactivó the script. */
	public var errored   : Bool;
	/** Text of the last error, or null. */
	public var lastError : Null<String>;

	/**
	 * Call to the function `fn` of the script with the argumentos dados.
	 * If the function no exists or the script no is active, returns null.
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
	 * Returns true if the function global `name` is definida in the script.
	 */
	public function hasFunction(name:String):Bool;

	/**
	 * Libera all the recursos of the script (state Lua, interpreter, etc.).
	 * Tras llamar a destroy(), active = false y el script no puede reutilizarse.
	 */
	public function destroy():Void;
}
