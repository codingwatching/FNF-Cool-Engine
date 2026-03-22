package funkin.shaders;

/**
 * OptionsShaderToggle — Fragment of code done for paste in you OptionsState.
 *
 * ─── INSTRUCTIONS ───────────────────────────────────────────────────────────
 *
 * Este archivo NO es una clase que debas instanciar.
 * Is a guide of integration. Copy the fragments indicades in you OptionsState.
 *
 * ─── STEP 1: Import ──────────────────────────────────────────────────────────
 *
 *   import funkin.shaders.ShaderManager;
 *
 * ─── PASO 2: Add the option in tu list of options ─────────────────────────
 *
 *   // Inside of where construyes the array/list of options of tu menu:
 *   options.push("Shaders: " + (ShaderManager.enabled ? "ON" : "OFF"));
 *
 * ─── STEP 3: Handle the selection ────────────────────────────────────────────
 *
 *   // Inside of the switch/if that procesa what option eligió the player:
 *   case "shaders":   // or the index that uses in tu menu
 *       ShaderManager.setEnabled(!ShaderManager.enabled);
 *       // Actualizar el texto del item en pantalla:
 *       updateOptionText(index, "Shaders: " + (ShaderManager.enabled ? "ON" : "OFF"));
 *
 * ─── EXAMPLE COMPLETE (CheckboxOption) ───────────────────────────────────────
 *
 *   // If your engine uses a CheckboxOption system or similar:
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
 *   // For saber if the shaders are ON u OFF in any momento:
 *   if (ShaderManager.enabled) { ... }
 *
 * ─── PARA LAS FLECHAS (en tu clase de nota/receptor) ─────────────────────────
 *
 *   // To the create or reciclar a flecha, add a line:
 *   ShaderManager.applyToNote(this, noteData % 4);
 *       // noteData % 4 → 0=LEFT 1=DOWN 2=UP 3=RIGHT
 *
 *   // If the shaders are OFF, applyToNote() pone shader=null automatically.
 *
 * ─── animation (in MusicBeatState or PlayState) ───────────────────────────────
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
