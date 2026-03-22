package funkin.addons;

/**
 * AddonInfo — Metadatos de un addon cargados desde addon.json.
 *
 * ─── Ejemplo de addon.json ────────────────────────────────────────────────────
 * {
 *   "id":          "my-addon",
 *   "name":        "My Addon",
 *   "description": "Añade mecánicas de combo extendidas",
 *   "author":      "NombreAutor",
 *   "version":     "1.0.0",
 *   "priority":    10,
 *   "enabled":     true,
 *
 *   "systems": ["comboSystem", "scoreMultiplier"],
 *
 *   "hooks": {
 *     "onNoteHit":       "scripts/onNoteHit.hx",
 *     "onMissNote":      "scripts/onMiss.hx",
 *     "onSongStart":     "scripts/onSongStart.hx",
 *     "onSongEnd":       "scripts/onSongEnd.hx",
 *     "onBeat":          "scripts/onBeat.hx",
 *     "onStep":          "scripts/onStep.hx",
 *     "onUpdate":        "scripts/onUpdate.hx",
 *     "onCountdown":     "scripts/onCountdown.hx",
 *     "onGameOver":      "scripts/onGameOver.hx",
 *     "onStateCreate":   "scripts/onStateCreate.hx",
 *     "onStateSwitch":   "scripts/onStateSwitch.hx",
 *     "exposeAPI":       "scripts/exposeAPI.hx"
 *   },
 *
 *   "modCompat": ["my-mod", "other-mod"],
 *   "requires":  ["base-addon >= 1.0.0"]
 * }
 */
typedef AddonInfo = {
	/** Identificador único del addon (nombre de carpeta). */
	var id: String;
	/** Nombre visible. */
	var name: String;
	/** Descripción. */
	var ?description: String;
	/** Autor. */
	var ?author: String;
	/** Versión semántica. */
	var ?version: String;
	/** Prioridad de carga (mayor = se carga antes). Default: 0. */
	var ?priority: Int;
	/** Si false, el addon no se carga. Default: true. */
	var ?enabled: Bool;

	/**
	 * Sistemas que este addon registra.
	 * Son identificadores usados por mods para declarar dependencia.
	 * Ejemplo: ["3dScene", "comboExtended", "customNoteTypes"]
	 */
	var ?systems: Array<String>;

	/**
	 * Mapa de hooks a scripts HScript.
	 * Cada clave es el nombre del hook, el valor es la ruta al .hx relativa
	 * a la carpeta del addon.
	 */
	var ?hooks: Dynamic;

	/**
	 * IDs de mods con los que este addon es compatible/diseñado.
	 * Si es null/vacío = compatible con todos.
	 */
	var ?modCompat: Array<String>;

	/**
	 * Addons requeridos (con versión mínima opcional).
	 * Ejemplo: ["base-addon >= 1.0.0"]
	 */
	var ?requires: Array<String>;
}
