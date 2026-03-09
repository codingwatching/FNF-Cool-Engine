
// ════════════════════════════════════════════════════════════════
//  modchart.hx — COMPLETE OVERHAUL
//  BPM: 150  |  64 secciones × 4 beats  |  256 beats totales
//
//  FASES (mapeadas del JSON):
//  0-31    Intro vacío        → cinematográfico, strums "despiertan"
//  32-39   Primeras notas     → caída del cielo + micro-swing
//  40-63   Dobles + holds     → ola sinusoidal en cascada
//  64-79   Simultáneas        → push/pull entre grupos
//  80-111  Corcheas rápidas   → ola viajera strum a strum + acordeón
//  112-127 Cadena de holds    → péndulo + cuenta regresiva al DROP
//  128-151 ¡¡8-KEY DROP!!     → impacto máximo + ola creciente
//  152-175 8-key loco         → V-shape + roulette de tilts
//  176-191 SWAP               → intercambio de posiciones
//  192-215 Ultra-densidad     → ola controlada, tilt alternado
//  216-247 Gran finale        → tremor, convergencia, alpha flash
//  248-255 Outro vacío        → fade cinematográfico
//
//  LÍMITES DE PANTALLA SEGUROS:
//  Player MOVE_X  : [-160, +80]   (base 740, 4 strums × ~108 = 432px)
//  CPU    MOVE_X  : [-10,  +120]  (base 100)
//  MOVE_Y durante notas: [-25, +35]  (off-screen sólo en transiciones)
//  SCALE durante notas:  máx 1.25   (visual, sin afectar hitbox)
//  Sin SPIN durante gameplay — confunde la lectura de notas
// ════════════════════════════════════════════════════════════════

var BASE_PLAYER_X = 740;
var BASE_CPU_X    = 100;
var beatCount     = 0;

function sin(deg) { return Math.sin(deg * Math.PI / 180.0); }
function cos(deg) { return Math.cos(deg * Math.PI / 180.0); }

// ─────────────────────────────────────────────────────────────
//  onCreate
// ─────────────────────────────────────────────────────────────
function onCreate() {

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 1 (0-31): INTRO CINEMATOGRÁFICO        ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(0, "all", -1, ALPHA, 0.0, 0, INSTANT);
    modChart.addEventSimple(0, "all", -1, SCALE, 0.1, 0, INSTANT);

    // CPU aparece primero (latido lento)
    modChart.addEventSimple(4,  "cpu",    -1, ALPHA, 0.45, 3.0, QUAD_OUT);
    modChart.addEventSimple(4,  "cpu",    -1, SCALE, 0.7,  2.0, BACK_OUT);

    // Player aparece con retardo (revelación)
    modChart.addEventSimple(12, "player", -1, ALPHA, 0.45, 3.0, QUAD_OUT);
    modChart.addEventSimple(12, "player", -1, SCALE, 0.7,  2.0, BACK_OUT);

    // Beat 24: ambos al máximo antes de las primeras notas
    modChart.addEventSimple(24, "all", -1, ALPHA, 1.0, 2.0, QUAD_OUT);
    modChart.addEventSimple(24, "all", -1, SCALE, 1.0, 2.0, ELASTIC_OUT);

    // Beat 28-31: pulso de anticipación creciente
    for (b in 0...4) {
        var beat      = 28 + b;
        var intensity = 1.0 + b * 0.04;
        modChart.addEventSimple(beat,       "all", -1, SCALE, intensity, 0.10, QUAD_OUT);
        modChart.addEventSimple(beat + 0.3, "all", -1, SCALE, 0.7,       0.30, QUAD_IN);
    }

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 2 (32-39): PRIMERA IMPACTO             ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(32, "all", -1, RESET,  0, 0, INSTANT);
    modChart.addEventSimple(32, "all", -1, ALPHA,  0.0, 0, INSTANT);
    modChart.addEventSimple(32, "all", -1, MOVE_Y, -200, 0, INSTANT);
    modChart.addEventSimple(32, "all", -1, SCALE,  1.6, 0, INSTANT);

    modChart.addEventSimple(32,   "cpu",    -1, ALPHA,  1.0, 0, INSTANT);
    modChart.addEventSimple(32,   "cpu",    -1, MOVE_Y, 0, 0.55, BOUNCE_OUT);
    modChart.addEventSimple(32,   "cpu",    -1, SCALE,  0.7, 0.50, ELASTIC_OUT);
    modChart.addEventSimple(32.5, "player", -1, ALPHA,  1.0, 0, INSTANT);
    modChart.addEventSimple(32.5, "player", -1, MOVE_Y, 0, 0.55, BOUNCE_OUT);
    modChart.addEventSimple(32.5, "player", -1, SCALE,  0.7, 0.50, ELASTIC_OUT);

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 3 (40-63): OLA SINUSOIDAL              ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(40, "all", -1, RESET, 0, 0, INSTANT);

    for (b in 0...24) {
        var beat = 40 + b;
        for (i in 0...4) {
            var phase = i * 90.0;
            var wy = sin(beat * 90.0 + phase) * 20.0;
            var wa = sin(beat * 90.0 + phase + 45.0) * 5.0;
            modChart.addEventSimple(beat, "player", i, MOVE_Y,  wy,  0.32, SINE_IN_OUT);
            modChart.addEventSimple(beat, "cpu",    i, MOVE_Y, -wy,  0.32, SINE_IN_OUT);
            modChart.addEventSimple(beat, "player", i, ANGLE,   wa,  0.32, SINE_IN_OUT);
            modChart.addEventSimple(beat, "cpu",    i, ANGLE,  -wa,  0.32, SINE_IN_OUT);
        }
    }

    // Swing lateral suave beat 52-63 (sección de holds)
    for (b in 0...3) {
        var beat = 52 + b * 4;
        var dir  = (b % 2 == 0) ? 1.0 : -1.0;
        modChart.addEventSimple(beat,     "player", -1, MOVE_X,  35.0 * dir, 1.0, SINE_IN_OUT);
        modChart.addEventSimple(beat + 2, "player", -1, MOVE_X,  0, 1.0, SINE_IN_OUT);
        modChart.addEventSimple(beat,     "cpu",    -1, MOVE_X, -22.0 * dir, 1.0, SINE_IN_OUT);
        modChart.addEventSimple(beat + 2, "cpu",    -1, MOVE_X,  0, 1.0, SINE_IN_OUT);
    }

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 4 (64-79): SIMULTANEAS EXPLOSIVAS      ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(64, "all", -1, RESET,  0, 0, INSTANT);
    modChart.addEventSimple(64, "all", -1, ALPHA,  0.0, 0, INSTANT);
    modChart.addEventSimple(64, "all", -1, SCALE,  1.7, 0, INSTANT);
    modChart.addEventSimple(64, "all", -1, ALPHA,  1.0, 0.35, QUAD_OUT);
    modChart.addEventSimple(64, "all", -1, SCALE,  0.7, 0.50, ELASTIC_OUT);

    for (b in 0...8) {
        var beat = 64 + b * 2;
        modChart.addEventSimple(beat,       "player", -1, MOVE_X,  32, 0.25, BACK_OUT);
        modChart.addEventSimple(beat + 0.9, "player", -1, MOVE_X,   0, 0.40, SINE_IN_OUT);
        modChart.addEventSimple(beat,       "cpu",    -1, MOVE_X, -20, 0.25, BACK_OUT);
        modChart.addEventSimple(beat + 0.9, "cpu",    -1, MOVE_X,   0, 0.40, SINE_IN_OUT);
    }

    for (b in 0...8) {
        var beat = 64 + b;
        var i0   = (b % 2) * 2;
        var i1   = i0 + 1;
        modChart.addEventSimple(beat,       "cpu", i0, ANGLE,  11, 0.10, QUAD_OUT);
        modChart.addEventSimple(beat,       "cpu", i1, ANGLE, -11, 0.10, QUAD_OUT);
        modChart.addEventSimple(beat + 0.2, "cpu", i0, ANGLE,   0, 0.20, ELASTIC_OUT);
        modChart.addEventSimple(beat + 0.2, "cpu", i1, ANGLE,   0, 0.20, ELASTIC_OUT);
    }

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 5 (80-111): TORMENTA DE CORCHEAS       ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(80, "all",    -1, RESET,  0, 0, INSTANT);
    modChart.addEventSimple(80, "player", -1, MOVE_X, -70, 0, INSTANT);
    modChart.addEventSimple(80, "player", -1, MOVE_X,   0, 0.75, BACK_OUT);
    modChart.addEventSimple(80, "cpu",    -1, MOVE_X,  55, 0, INSTANT);
    modChart.addEventSimple(80, "cpu",    -1, MOVE_X,   0, 0.75, BACK_OUT);

    for (b in 0...32) {
        var beat    = 80 + b;
        var sIdx    = b % 4;
        var yAmp    = 14.0 + (b > 16 ? 7.0 : 0.0);
        modChart.addEventSimple(beat,        "player", sIdx, MOVE_Y, -yAmp, 0.07, QUAD_OUT);
        modChart.addEventSimple(beat + 0.12, "player", sIdx, MOVE_Y,  0,    0.22, BOUNCE_OUT);
        modChart.addEventSimple(beat,        "player", sIdx, SCALE,   1.18, 0.07, QUAD_OUT);
        modChart.addEventSimple(beat + 0.18, "player", sIdx, SCALE,   0.7,  0.22, QUAD_IN);
        var cpuM = (sIdx + 2) % 4;
        modChart.addEventSimple(beat + 0.25, "cpu", cpuM, MOVE_Y, -9, 0.08, QUAD_OUT);
        modChart.addEventSimple(beat + 0.38, "cpu", cpuM, MOVE_Y,  0, 0.20, BOUNCE_OUT);
    }

    for (b in 0...4) {
        var beat = 96 + b * 4;
        modChart.addEventSimple(beat,     "player", 0, MOVE_X, -20, 0.22, BACK_OUT);
        modChart.addEventSimple(beat,     "player", 3, MOVE_X,  20, 0.22, BACK_OUT);
        modChart.addEventSimple(beat,     "cpu",    0, MOVE_X, -13, 0.22, BACK_OUT);
        modChart.addEventSimple(beat,     "cpu",    3, MOVE_X,  13, 0.22, BACK_OUT);
        modChart.addEventSimple(beat + 2, "player", 0, MOVE_X,   0, 0.35, ELASTIC_OUT);
        modChart.addEventSimple(beat + 2, "player", 3, MOVE_X,   0, 0.35, ELASTIC_OUT);
        modChart.addEventSimple(beat + 2, "cpu",    0, MOVE_X,   0, 0.35, ELASTIC_OUT);
        modChart.addEventSimple(beat + 2, "cpu",    3, MOVE_X,   0, 0.35, ELASTIC_OUT);
    }

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 6 (112-127): CADENA DE HOLDS + BUILD   ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(112, "all", -1, RESET, 0, 0, INSTANT);

    var swingT = [112, 114, 116, 118];
    var swingD = [1.0, -1.0, 1.0, -1.0];
    for (i in 0...4) {
        var bt = swingT[i];
        var d  = swingD[i];
        modChart.addEventSimple(bt, "player", -1, MOVE_X,  25.0 * d, 2.0, SINE_IN_OUT);
        modChart.addEventSimple(bt, "cpu",    -1, MOVE_X, -15.0 * d, 2.0, SINE_IN_OUT);
        modChart.addEventSimple(bt, "player", -1, ANGLE,   8.0 * d,  2.0, SINE_IN_OUT);
        modChart.addEventSimple(bt, "cpu",    -1, ANGLE,  -6.0 * d,  2.0, SINE_IN_OUT);
    }
    modChart.addEventSimple(120, "player", -1, MOVE_X, 0, 1.2, SINE_IN_OUT);
    modChart.addEventSimple(120, "cpu",    -1, MOVE_X, 0, 1.2, SINE_IN_OUT);
    modChart.addEventSimple(120, "all",    -1, ANGLE,  0, 1.5, ELASTIC_OUT);

    // Cuenta regresiva al DROP
    modChart.addEventSimple(122, "all", -1, ALPHA, 0.55, 1.5, QUAD_IN);
    modChart.addEventSimple(124, "all", -1, ALPHA, 0.20, 1.0, QUAD_IN);
    modChart.addEventSimple(126, "all", -1, ALPHA, 0.0,  0.4, QUAD_IN);
    modChart.addEventSimple(124, "all", -1, SCALE, 0.5,  1.5, QUAD_IN);
    modChart.addEventSimple(126, "all", -1, ANGLE,  0,   0,   INSTANT);
    modChart.addEventSimple(126, "all", -1, MOVE_X, 0,   0,   INSTANT);

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 7 (128-151): ¡¡EL DROP DE 8 KEYS!!    ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(128, "all", -1, RESET,  0, 0, INSTANT);
    modChart.addEventSimple(128, "all", -1, ALPHA,  1.0, 0, INSTANT);
    modChart.addEventSimple(128, "all", -1, SCALE,  2.4, 0, INSTANT);
    modChart.addEventSimple(128, "all", -1, MOVE_Y, -130, 0, INSTANT);

    modChart.addEventSimple(128,   "cpu",    -1, MOVE_Y, 0, 0.60, BOUNCE_OUT);
    modChart.addEventSimple(128,   "cpu",    -1, SCALE,  0.7, 0.55, ELASTIC_OUT);
    modChart.addEventSimple(128.3, "player", -1, MOVE_Y, 0, 0.60, BOUNCE_OUT);
    modChart.addEventSimple(128.3, "player", -1, SCALE,  0.7, 0.55, ELASTIC_OUT);

    // Triple glitch de alpha
    modChart.addEventSimple(128.06,"all", -1, ALPHA, 0.0, 0, INSTANT);
    modChart.addEventSimple(128.12,"all", -1, ALPHA, 1.0, 0, INSTANT);
    modChart.addEventSimple(128.20,"all", -1, ALPHA, 0.3, 0, INSTANT);
    modChart.addEventSimple(128.28,"all", -1, ALPHA, 1.0, 0.2, QUAD_OUT);

    // Beat 128-135: tilt alternado (jugable, sin spin)
    for (b in 0...8) {
        var beat = 128 + b;
        var tilt = (b % 2 == 0) ? 12.0 : -12.0;
        modChart.addEventSimple(beat,       "player", -1, ANGLE, tilt,  0.12, QUAD_OUT);
        modChart.addEventSimple(beat + 0.3, "player", -1, ANGLE, 0,     0.20, ELASTIC_OUT);
        modChart.addEventSimple(beat,       "cpu",    -1, ANGLE, -tilt, 0.12, QUAD_OUT);
        modChart.addEventSimple(beat + 0.3, "cpu",    -1, ANGLE, 0,     0.20, ELASTIC_OUT);
    }

    // Beat 136-143: ola Y creciente strum a strum
    for (b in 0...8) {
        var beat = 136 + b;
        var amp  = 12.0 + b * 2.5;
        for (i in 0...4) {
            var phase = i * 90.0;
            var wy = sin(beat * 90.0 + phase) * amp;
            modChart.addEventSimple(beat, "player", i, MOVE_Y, wy,          0.28, SINE_IN_OUT);
            modChart.addEventSimple(beat, "cpu",    i, MOVE_Y, -wy * 0.55,  0.28, SINE_IN_OUT);
        }
    }

    // Beat 144-151: acordeón diagonal
    for (b in 0...4) {
        var beat = 144 + b * 2;
        modChart.addEventSimple(beat,     "player", 0, MOVE_X, -18, 0.20, BACK_OUT);
        modChart.addEventSimple(beat,     "player", 0, MOVE_Y, -14, 0.20, BACK_OUT);
        modChart.addEventSimple(beat,     "player", 3, MOVE_X,  18, 0.20, BACK_OUT);
        modChart.addEventSimple(beat,     "player", 3, MOVE_Y,  14, 0.20, BACK_OUT);
        modChart.addEventSimple(beat + 1, "player", -1, MOVE_X, 0, 0.35, ELASTIC_OUT);
        modChart.addEventSimple(beat + 1, "player", -1, MOVE_Y, 0, 0.35, ELASTIC_OUT);
        modChart.addEventSimple(beat,     "cpu",    0, MOVE_X, -12, 0.20, BACK_OUT);
        modChart.addEventSimple(beat,     "cpu",    3, MOVE_X,  12, 0.20, BACK_OUT);
        modChart.addEventSimple(beat + 1, "cpu",    -1, MOVE_X, 0, 0.35, ELASTIC_OUT);
    }

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 8 (152-175): 8-KEY LOCO               ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(152, "all", -1, RESET, 0, 0, INSTANT);
    modChart.addEventSimple(152, "all", -1, ALPHA, 0.0, 0, INSTANT);
    modChart.addEventSimple(152, "all", -1, SCALE, 1.5, 0, INSTANT);
    modChart.addEventSimple(152, "all", -1, ALPHA, 1.0, 0.40, QUAD_OUT);
    modChart.addEventSimple(152, "all", -1, SCALE, 0.7, 0.50, ELASTIC_OUT);
    modChart.addEventSimple(152, "player", -1, ANGLE,  10, 0.5, ELASTIC_OUT);
    modChart.addEventSimple(152, "cpu",    -1, ANGLE, -10, 0.5, ELASTIC_OUT);
    modChart.addEventSimple(156, "all",    -1, ANGLE,   0, 1.0, ELASTIC_OUT);

    // V-shape dinámica
    for (b in 0...8) {
        var beat = 152 + b * 3;
        if (beat >= 176) break;
        var vDir = (b % 2 == 0) ? 1.0 : -1.0;
        modChart.addEventSimple(beat, "player", 0, MOVE_Y, -20.0 * vDir, 0.4, SINE_OUT);
        modChart.addEventSimple(beat, "player", 3, MOVE_Y, -20.0 * vDir, 0.4, SINE_OUT);
        modChart.addEventSimple(beat, "player", 1, MOVE_Y,  15.0 * vDir, 0.4, SINE_OUT);
        modChart.addEventSimple(beat, "player", 2, MOVE_Y,  15.0 * vDir, 0.4, SINE_OUT);
    }

    // Roulette de tilts en CPU
    var roulette = [0, 2, 1, 3, 2, 0, 3, 1, 1, 3, 0, 2];
    for (i in 0...12) {
        var beat = 152 + i;
        if (beat >= 164) break;
        var si = roulette[i];
        modChart.addEventSimple(beat,        "cpu", si, SCALE, 1.22, 0.09, ELASTIC_OUT);
        modChart.addEventSimple(beat + 0.30, "cpu", si, SCALE,  0.7, 0.28, QUAD_IN);
        modChart.addEventSimple(beat,        "cpu", si, ANGLE,  14,  0.09, QUAD_OUT);
        modChart.addEventSimple(beat + 0.22, "cpu", si, ANGLE,   0,  0.18, ELASTIC_OUT);
    }

    // Ola horizontal X en player beat 164-175
    for (b in 0...12) {
        var beat = 164 + b;
        for (i in 0...4) {
            var phase = i * 90.0;
            var ox = sin(beat * 60.0 + phase) * 17.0;
            modChart.addEventSimple(beat, "player", i, MOVE_X, ox, 0.30, SINE_IN_OUT);
        }
    }

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 9 (176-191): SWAP DE POSICIONES        ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(176, "all", -1, RESET,  0, 0, INSTANT);
    modChart.addEventSimple(176, "all", -1, SCALE,  1.6, 0, INSTANT);
    modChart.addEventSimple(176, "all", -1, ALPHA,  0.0, 0, INSTANT);
    modChart.addEventSimple(176, "all", -1, SCALE,  0.7, 0.5, ELASTIC_OUT);
    modChart.addEventSimple(176, "all", -1, ALPHA,  1.0, 0.3, QUAD_OUT);

    modChart.addEventSimple(176, "player", -1, SET_ABS_X, BASE_CPU_X,    2.0, QUAD_IN_OUT);
    modChart.addEventSimple(176, "cpu",    -1, SET_ABS_X, BASE_PLAYER_X, 2.0, QUAD_IN_OUT);

    modChart.addEventSimple(176, "player", -1, ANGLE, -14, 1.0, SINE_IN_OUT);
    modChart.addEventSimple(178, "player", -1, ANGLE,  12, 1.5, SINE_IN_OUT);
    modChart.addEventSimple(180, "player", -1, ANGLE,   0, 1.0, ELASTIC_OUT);
    modChart.addEventSimple(176, "cpu",    -1, ANGLE,  14, 1.0, SINE_IN_OUT);
    modChart.addEventSimple(178, "cpu",    -1, ANGLE, -12, 1.5, SINE_IN_OUT);
    modChart.addEventSimple(180, "cpu",    -1, ANGLE,   0, 1.0, ELASTIC_OUT);

    modChart.addEventSimple(183, "player", -1, SET_ABS_X, BASE_PLAYER_X, 2.0, BACK_OUT);
    modChart.addEventSimple(183, "cpu",    -1, SET_ABS_X, BASE_CPU_X,    2.0, BACK_OUT);

    // Build hacia ultra-densidad
    modChart.addEventSimple(187, "all", -1, ALPHA, 0.5, 1.5, QUAD_IN);
    modChart.addEventSimple(189, "all", -1, ALPHA, 0.0, 0.9, QUAD_IN);
    modChart.addEventSimple(189, "all", -1, SCALE, 0.4, 0.9, QUAD_IN);
    modChart.addEventSimple(189, "all", -1, ANGLE, 0,   0,   INSTANT);

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 10 (192-215): ULTRA-DENSIDAD           ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(192, "all", -1, RESET,  0, 0, INSTANT);
    modChart.addEventSimple(192, "all", -1, ALPHA,  1.0, 0, INSTANT);
    modChart.addEventSimple(192, "all", -1, SCALE,  2.6, 0, INSTANT);
    modChart.addEventSimple(192, "all", -1, MOVE_Y, -110, 0, INSTANT);

    modChart.addEventSimple(192,   "cpu",    -1, MOVE_Y, 0, 0.58, BOUNCE_OUT);
    modChart.addEventSimple(192,   "cpu",    -1, SCALE,  0.7, 0.52, ELASTIC_OUT);
    modChart.addEventSimple(192.4, "player", -1, MOVE_Y, 0, 0.58, BOUNCE_OUT);
    modChart.addEventSimple(192.4, "player", -1, SCALE,  0.7, 0.52, ELASTIC_OUT);

    modChart.addEventSimple(192.06,"all", -1, ALPHA, 0.0, 0, INSTANT);
    modChart.addEventSimple(192.12,"all", -1, ALPHA, 1.0, 0, INSTANT);
    modChart.addEventSimple(192.20,"all", -1, ALPHA, 0.2, 0, INSTANT);
    modChart.addEventSimple(192.28,"all", -1, ALPHA, 1.0, 0.2, QUAD_OUT);

    for (b in 0...12) {
        var beat = 192 + b;
        var ta   = (b % 2 == 0) ? 7.0 : -7.0;
        modChart.addEventSimple(beat,       "player", -1, ANGLE,  ta, 0.12, QUAD_OUT);
        modChart.addEventSimple(beat + 0.3, "player", -1, ANGLE,   0, 0.18, ELASTIC_OUT);
        modChart.addEventSimple(beat,       "cpu",    -1, ANGLE, -ta, 0.12, QUAD_OUT);
        modChart.addEventSimple(beat + 0.3, "cpu",    -1, ANGLE,   0, 0.18, ELASTIC_OUT);
    }

    for (b in 0...12) {
        var beat = 196 + b;
        for (i in 0...4) {
            var phase = i * 90.0;
            var wy = sin(beat * 45.0 + phase) * 15.0;
            modChart.addEventSimple(beat, "player", i, MOVE_Y,  wy,       0.22, SINE_IN_OUT);
            modChart.addEventSimple(beat, "cpu",    i, MOVE_Y, -wy * 0.65, 0.22, SINE_IN_OUT);
        }
    }

    for (b in 0...8) {
        var beat   = 208 + b;
        var xShift = (b % 2 == 0) ? 9.0 : -9.0;
        modChart.addEventSimple(beat,        "player", -1, MOVE_X,  xShift, 0.09, QUAD_OUT);
        modChart.addEventSimple(beat + 0.28, "player", -1, MOVE_X,  0, 0.18, SINE_IN_OUT);
        modChart.addEventSimple(beat,        "cpu",    -1, MOVE_X, -xShift, 0.09, QUAD_OUT);
        modChart.addEventSimple(beat + 0.28, "cpu",    -1, MOVE_X,  0, 0.18, SINE_IN_OUT);
    }

    // ╔═══════════════════════════════════════════════╗
    // ║  FASE 11 (216-247): GRAN FINALE              ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(216, "all",    -1, RESET,  0, 0, INSTANT);
    modChart.addEventSimple(216, "all",    -1, SCALE,  0.1, 0, INSTANT);
    modChart.addEventSimple(216, "all",    -1, ALPHA,  1.0, 0, INSTANT);
    modChart.addEventSimple(216, "all",    -1, SCALE,  0.7, 0.85, ELASTIC_OUT);
    modChart.addEventSimple(216, "player", -1, MOVE_X, -140, 0, INSTANT);
    modChart.addEventSimple(216, "player", -1, MOVE_X,    0, 1.1, BACK_OUT);
    modChart.addEventSimple(216, "cpu",    -1, MOVE_X,  110, 0, INSTANT);
    modChart.addEventSimple(216, "cpu",    -1, MOVE_X,    0, 1.1, BACK_OUT);

    var tiltSeq = [10.0, -10.0, 12.0, -12.0, 8.0, -8.0, 10.0, -10.0,
                   12.0,  -8.0,-10.0,  10.0,-12.0,  8.0, 11.0, -11.0];
    for (i in 0...16) {
        var beat    = 216 + i;
        var si      = i % 4;
        var tiltAmt = tiltSeq[i];
        modChart.addEventSimple(beat,        "player", si,   ANGLE,  tiltAmt, 0.08, QUAD_OUT);
        modChart.addEventSimple(beat + 0.22, "player", si,   ANGLE,  0,       0.20, ELASTIC_OUT);
        modChart.addEventSimple(beat,        "cpu",    3-si, ANGLE, -tiltAmt, 0.08, QUAD_OUT);
        modChart.addEventSimple(beat + 0.22, "cpu",    3-si, ANGLE,  0,       0.20, ELASTIC_OUT);
    }

    // Convergencia al centro
    modChart.addEventSimple(232, "player", -1, MOVE_X, -110, 1.5, QUAD_IN_OUT);
    modChart.addEventSimple(232, "cpu",    -1, MOVE_X,   75, 1.5, QUAD_IN_OUT);
    modChart.addEventSimple(232, "player", -1, MOVE_Y,  -28, 1.2, SINE_IN_OUT);
    modChart.addEventSimple(232, "cpu",    -1, MOVE_Y,   28, 1.2, SINE_IN_OUT);

    // Separación explosiva beat 235
    modChart.addEventSimple(235, "player", -1, MOVE_X,  28, 1.2, BACK_OUT);
    modChart.addEventSimple(235, "cpu",    -1, MOVE_X,  -8, 1.2, BACK_OUT);
    modChart.addEventSimple(235, "all",    -1, MOVE_Y,   0, 1.0, BOUNCE_OUT);
    modChart.addEventSimple(235, "all",    -1, SCALE,   1.2, 0.10, QUAD_OUT);
    modChart.addEventSimple(235, "all",    -1, SCALE,   0.7, 0.50, ELASTIC_OUT);

    // Tremor + alpha flash beat 240-247 (la parte más hype)
    for (b in 0...8) {
        var beat = 240 + b;
        var jx   = (b % 2 == 0) ? 8.0 : -8.0;
        var alp  = (b % 2 == 0) ? 0.45 : 1.0;
        modChart.addEventSimple(beat,        "player", -1, MOVE_X,  jx, 0.05, INSTANT);
        modChart.addEventSimple(beat,        "cpu",    -1, MOVE_X, -jx, 0.05, INSTANT);
        modChart.addEventSimple(beat + 0.10, "player", -1, MOVE_X,   0, 0.12, QUAD_OUT);
        modChart.addEventSimple(beat + 0.10, "cpu",    -1, MOVE_X,   0, 0.12, QUAD_OUT);
        modChart.addEventSimple(beat,        "all",    -1, ALPHA,  alp, 0.10, QUAD_IN);
        modChart.addEventSimple(beat + 0.32, "all",    -1, ALPHA,  1.0, 0.14, QUAD_OUT);
    }

    // ╔═══════════════════════════════════════════════╗
    // ║  OUTRO (248-255): FADE CINEMATOGRÁFICO       ║
    // ╚═══════════════════════════════════════════════╝

    modChart.addEventSimple(248, "all", -1, ANGLE, 0, 0, INSTANT);
    modChart.addEventSimple(248, "all", -1, RESET, 0, 3.0, SINE_IN_OUT);
    modChart.addEventSimple(250, "all", -1, ALPHA, 0.6, 2.0, QUAD_IN);
    modChart.addEventSimple(253, "all", -1, ALPHA, 0.0, 1.0, QUAD_IN);
    modChart.addEventSimple(255, "all", -1, RESET, 0, 0, INSTANT);
    modChart.addEventSimple(255, "all", -1, ALPHA, 1.0, 0, INSTANT);
}

// ─────────────────────────────────────────────────────────────
//  onBeatHit — efectos dinámicos por beat
// ─────────────────────────────────────────────────────────────
function onBeatHit(beat) {
    beatCount = beat;

    // ── Pulso de escala universal ───────────────────────────────
    if (beat >= 32 && beat < 248) {
        var intense;
        if      (beat >= 216) intense = 1.14;
        else if (beat >= 192) intense = 1.12;
        else if (beat >= 128) intense = 1.09;
        else if (beat >= 64)  intense = 1.06;
        else                  intense = 1.04;
        modChart.addEventSimple(beat,       "all", -1, SCALE, intense, 0.07, QUAD_OUT);
        modChart.addEventSimple(beat + 0.2, "all", -1, SCALE,    0.7,  0.25, QUAD_IN);
    }

    // ── Kick de pantalla cada 4 beats (desde beat 40) ──────────
    if (beat >= 40 && beat % 4 == 0) {
        var kickAmp = (beat >= 192) ? 20.0 : ((beat >= 128) ? 15.0 : 10.0);
        modChart.addEventSimple(beat,        "all", -1, MOVE_Y, -kickAmp, 0.09, QUAD_OUT);
        modChart.addEventSimple(beat + 0.17, "all", -1, MOVE_Y, 0, 0.35, BOUNCE_OUT);
    }

    // ── Strum highlight secuencial ──────────────────────────────
    if (beat >= 40 && beat < 192) {
        var sIdx = beat % 4;
        modChart.addEventSimple(beat,       "player", sIdx,   SCALE, 1.20, 0.08, ELASTIC_OUT);
        modChart.addEventSimple(beat + 0.3, "player", sIdx,   SCALE,  0.7, 0.28, QUAD_IN);
        modChart.addEventSimple(beat,       "cpu",    3-sIdx, SCALE, 1.14, 0.08, ELASTIC_OUT);
        modChart.addEventSimple(beat + 0.3, "cpu",    3-sIdx, SCALE,  0.7, 0.28, QUAD_IN);
    }

    // ── Snare visual cada 2 beats (fases 7-11) ─────────────────
    if (beat >= 128 && beat < 248 && beat % 2 == 0) {
        var snIdx = Std.int((beat / 2) % 4);
        modChart.addEventSimple(beat,        "cpu", snIdx, ANGLE,  13, 0.07, QUAD_OUT);
        modChart.addEventSimple(beat + 0.13, "cpu", snIdx, ANGLE, -13, 0.14, SINE_IN_OUT);
        modChart.addEventSimple(beat + 0.30, "cpu", snIdx, ANGLE,   0, 0.14, ELASTIC_OUT);
    }

    // ── Ola sinusoidal de X en ultra-densidad (192-215) ────────
    if (beat >= 192 && beat < 216) {
        for (i in 0...4) {
            var phase = i * 90.0;
            var ox = sin(beat * 45.0 + phase) * 19.0;
            modChart.addEventSimple(beat, "player", i, MOVE_X, ox, 0.36, SINE_IN_OUT);
        }
    }

    // ── Tremor agresivo en finale (240-247) ─────────────────────
    if (beat >= 240 && beat < 248) {
        var fx = (beat % 2 == 0) ? 8.0 : -8.0;
        for (i in 0...4) {
            modChart.addEventSimple(beat,        "all", i, MOVE_X,  fx, 0.05, INSTANT);
            modChart.addEventSimple(beat + 0.10, "all", i, MOVE_X, -fx, 0.05, INSTANT);
            modChart.addEventSimple(beat + 0.20, "all", i, MOVE_X,  0,  0.10, QUAD_OUT);
        }
    }

    // ── Micro-swing en intro (32-39) ────────────────────────────
    if (beat >= 32 && beat < 40) {
        var lrDir = (beat % 2 == 0) ? 11.0 : -11.0;
        modChart.addEventSimple(beat,       "player", -1, MOVE_X,  lrDir,        0.12, QUAD_OUT);
        modChart.addEventSimple(beat + 0.4, "player", -1, MOVE_X,  0, 0.30, SINE_IN_OUT);
        modChart.addEventSimple(beat,       "cpu",    -1, MOVE_X, -lrDir * 0.55, 0.12, QUAD_OUT);
        modChart.addEventSimple(beat + 0.4, "cpu",    -1, MOVE_X,  0, 0.30, SINE_IN_OUT);
    }

    // ── Pulso extra durante SWAP (176-189) ──────────────────────
    if (beat >= 176 && beat < 190) {
        modChart.addEventSimple(beat,       "all", -1, SCALE, 1.09, 0.07, QUAD_OUT);
        modChart.addEventSimple(beat + 0.2, "all", -1, SCALE,  0.7, 0.25, QUAD_IN);
    }
}

// ─────────────────────────────────────────────────────────────
//  onStepHit — efectos granulares por step (4 steps = 1 beat)
// ─────────────────────────────────────────────────────────────
function onStepHit(step) {
    // ── Ola Y granular en sección de corcheas (beat 80-128) ────
    if (step >= 320 && step < 512) {
        var sIdx = step % 4;
        var wy   = sin(step * 45.0) * 11.0;
        modChart.addEventSimple(step / 4.0, "player", sIdx, MOVE_Y,  wy,       0.14, SINE_IN_OUT);
        modChart.addEventSimple(step / 4.0, "cpu",    sIdx, MOVE_Y, -wy * 0.5, 0.14, SINE_IN_OUT);
    }

    // ── Mini-tilt por step en finale (beat 216-248) ─────────────
    if (step >= 864 && step < 992 && step % 3 == 0) {
        var ta = sin(step * 90.0) * 6.0;
        modChart.addEventSimple(step / 4.0,        "player", -1, ANGLE, ta, 0.07, QUAD_OUT);
        modChart.addEventSimple(step / 4.0 + 0.10, "player", -1, ANGLE, 0,  0.14, ELASTIC_OUT);
    }

    // ── Respiración suave en el intro (beat 0-32) ───────────────
    if (step < 128 && step % 8 == 0) {
        var by = sin(step * 45.0) * 3.5;
        modChart.addEventSimple(step / 4.0, "all", -1, MOVE_Y, by, 0.55, SINE_IN_OUT);
    }
}
