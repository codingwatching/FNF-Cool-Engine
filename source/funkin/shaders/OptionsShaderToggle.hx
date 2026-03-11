package funkin.shaders;

/**
 * OptionsShaderToggle — Fragmento de código listo para pegar en tu OptionsState.
 *
 * ─── INSTRUCCIONES ───────────────────────────────────────────────────────────
 *
 * Este archivo NO es una clase que debas instanciar.
 * Es una guía de integración. Copia los fragmentos indicados en tu OptionsState.
 *
 * ─── PASO 1: Import ──────────────────────────────────────────────────────────
 *
 *   import funkin.shaders.ShaderManager;
 *
 * ─── PASO 2: Añadir la opción en tu lista de opciones ─────────────────────────
 *
 *   // Dentro de donde construyes el array/lista de opciones de tu menú:
 *   options.push("Shaders: " + (ShaderManager.enabled ? "ON" : "OFF"));
 *
 * ─── PASO 3: Manejar la selección ────────────────────────────────────────────
 *
 *   // Dentro del switch/if que procesa qué opción eligió el jugador:
 *   case "shaders":   // o el índice que uses en tu menú
 *       ShaderManager.setEnabled(!ShaderManager.enabled);
 *       // Actualizar el texto del item en pantalla:
 *       updateOptionText(index, "Shaders: " + (ShaderManager.enabled ? "ON" : "OFF"));
 *
 * ─── EJEMPLO COMPLETO (CheckboxOption) ───────────────────────────────────────
 *
 *   // Si tu engine usa un sistema de CheckboxOption o similar:
 *
 *   var shadersOption = new CheckboxOption(
 *       "Shaders",
 *       "Activa efectos visuales de post-procesado y brillo en las flechas.",
 *       ShaderManager.enabled,           // valor inicial
 *       function(value:Bool) {
 *           ShaderManager.setEnabled(value);
 *       }
 *   );
 *   optionsList.add(shadersOption);
 *
 * ─── LEER EL ESTADO ACTUAL ───────────────────────────────────────────────────
 *
 *   // Para saber si los shaders están ON u OFF en cualquier momento:
 *   if (ShaderManager.enabled) { ... }
 *
 * ─── PARA LAS FLECHAS (en tu clase de nota/receptor) ─────────────────────────
 *
 *   // Al crear o reciclar una flecha, añadir una línea:
 *   ShaderManager.applyToNote(this, noteData % 4);
 *       // noteData % 4 → 0=LEFT 1=DOWN 2=UP 3=RIGHT
 *
 *   // Si los shaders están OFF, applyToNote() pone shader=null automáticamente.
 *
 * ─── ANIMACIÓN (en MusicBeatState o PlayState) ───────────────────────────────
 *
 *   // En tu update() de la clase base MusicBeatState:
 *   override function update(elapsed:Float) {
 *       super.update(elapsed);
 *       ShaderManager.update(elapsed);   // anima el film grain
 *   }
 *
 * ─── EFECTO DE GOLPE (miss / death) ──────────────────────────────────────────
 *
 *   // Al anotar un miss:
 *   ShaderManager.pulseCA(0.012);
 *
 *   // Al morir:
 *   ShaderManager.pulseCA(0.025, 12);
 *
 */
class OptionsShaderToggle {}
