package funkin.scripting.events;

/**
 * EventDefinition — Definición completa de un evento del engine.
 *
 * Cada evento tiene:
 *  • Metadatos (nombre, descripción, color, contextos, aliases)
 *  • Parámetros para el editor (lista de EventParamDef)
 *  • Rutas a sus handlers de script (HScript/Lua), si los tiene
 *
 * ─── Estructura de carpetas ──────────────────────────────────────────────────
 *
 *  Formato A — archivos planos en la carpeta de contexto:
 *    data/events/chart/Camera Follow.json    ← definición UI
 *    data/events/chart/Camera Follow.hx      ← handler HScript
 *    data/events/chart/Camera Follow.lua     ← handler Lua
 *
 *  Formato B — carpeta por evento:
 *    data/events/chart/Camera Follow/
 *      event.json      ← (o config.json)
 *      handler.hx      ← (o Camera Follow.hx)
 *      handler.lua     ← (o Camera Follow.lua)
 *
 *  Ambos formatos pueden coexistir en la misma carpeta de contexto.
 *
 * ─── Formato del JSON ────────────────────────────────────────────────────────
 *
 *  {
 *    "name":        "Camera Follow",
 *    "description": "Mueve la cámara hacia un personaje.",
 *    "color":       "#88CCFF",
 *    "context":     ["chart"],
 *    "aliases":     ["Camera", "Follow Camera"],
 *    "params": [
 *      {
 *        "name":         "Target",
 *        "type":         "DropDown(bf,dad,gf,both)",
 *        "defaultValue": "bf",
 *        "description":  "Personaje al que seguir"
 *      },
 *      {
 *        "name":         "Lerp Speed",
 *        "type":         "Float(0,1)",
 *        "defaultValue": "0.04",
 *        "description":  "Velocidad de seguimiento"
 *      }
 *    ]
 *  }
 *
 * ─── API del handler script ──────────────────────────────────────────────────
 *
 *  HScript (Camera Follow.hx):
 *    // Variables disponibles: v1, v2, time, game
 *    // Retornar true = no ejecutar el handler built-in
 *    function onTrigger(v1, v2, time) {
 *      if (game != null) game.cameraController.setTarget(v1);
 *      return false; // dejar que el built-in también corra
 *    }
 *
 *  Lua (Camera Follow.lua):
 *    function onTrigger(v1, v2, time)
 *      -- v1, v2, time están disponibles como args
 *      trace("Camera Follow: " .. v1)
 *      return false
 *    end
 *
 * ─── Contextos disponibles ───────────────────────────────────────────────────
 *
 *   "chart"      → eventos visibles en el Chart Editor; se disparan en gameplay
 *   "cutscene"   → eventos para SpriteCutscene
 *   "playstate"  → eventos para el PlayState Editor
 *   "modchart"   → eventos para el Modchart Editor
 *   "global"     → visible en TODOS los editores
 */

// Importar tipos de EventInfoSystem para reusar EventParamDef
import funkin.scripting.events.EventInfoSystem.EventParamDef;
import funkin.scripting.events.EventInfoSystem.EventParamType;

typedef EventDefinition =
{
	/** Nombre canónico del evento. */
	var name:String;

	/** Descripción breve para tooltips del editor. */
	var ?description:String;

	/** Color ARGB para el sidebar del editor (ej. 0xFF88CCFF). */
	var color:Int;

	/**
	 * Contextos en los que este evento está disponible.
	 * Valores: "chart" | "cutscene" | "playstate" | "modchart" | "global"
	 * Un evento con contexto "global" aparece en todos los editores.
	 */
	var contexts:Array<String>;

	/**
	 * Nombres alternativos que disparan este mismo handler.
	 * Útil para compatibilidad con otros formatos (Psych Engine, V-Slice, etc.)
	 */
	var aliases:Array<String>;

	/** Lista de parámetros para la UI del editor. */
	var params:Array<EventParamDef>;

	// ── Rutas a los scripts handler (null = solo built-in) ──────────────────

	/** Ruta al archivo HScript handler (.hx / .hscript). Null si no existe. */
	var ?hscriptPath:String;

	/** Ruta al archivo Lua handler (.lua). Null si no existe. */
	var ?luaPath:String;

	/** Carpeta de origen (para recargas hot-reload). */
	var ?sourceDir:String;
}
