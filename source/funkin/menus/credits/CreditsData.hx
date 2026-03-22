package funkin.menus.credits;

/**
 * Structure root of the JSON of credits.
 * Compatible con el formato de v-slice (entries con header + body).
 *
 * Formato JSON de ejemplo (assets/data/credits.json):
 * {
 *   "entries": [
 *     {
 *       "header": "Directores",
 *       "body": [
 *         { "line": "ninjamuffin99 — Programming" },
 *         { "line": "PhantomArcade — Animation" }
 *       ]
 *     }
 *   ]
 * }
 *
 * Para mods, colocar en: mods/<mod>/data/credits.json
 * The entries of the mod is añaden to the end of the entries base.
 */
typedef CreditsData =
{
	var entries:Array<CreditsEntry>;
}

/**
 * A section of the credits (rol, category, etc.).
 */
typedef CreditsEntry =
{
	/**
	 * Title of the section in bold (p.ej. "Directores", "Arte").
	 * Opcional: si es null, no se muestra cabecera.
	 */
	@:optional
	var header:Null<String>;

	/**
	 * Lines of text under the header.
	 */
	@:optional
	var body:Array<CreditsLine>;

	/**
	 * Color del header en formato hex sin # (p.ej. "FFFFFF").
	 * Por defecto blanco.
	 */
	@:optional
	var headerColor:Null<String>;

	/**
	 * Color del body en formato hex sin # (p.ej. "CCCCCC").
	 * Por defecto gris claro.
	 */
	@:optional
	var bodyColor:Null<String>;
}

/**
 * A line of text in the body of a entry.
 */
typedef CreditsLine =
{
	var line:String;
}
