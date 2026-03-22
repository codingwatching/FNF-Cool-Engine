package funkin.gameplay.modchart;

/**
 * ============================================================
 *  ModChartEvent.hx  –  Tipos de datos del sistema ModChart
 * ============================================================
 *
 *  v3 — Nuevos modificadores inspirados en FNF-Modcharting-Tools:
 *       TIPSY, INVERT, ZIGZAG, WAVE, BEAT_SCALE, STEALTH, NOTE_ALPHA
 *       + fix de DRUNK_Y / NOTE_OFFSET_Y / BUMPY en NoteManager
 *
 *  MODIFICADORES DE STRUM:
 *    MOVE_X / MOVE_Y / SET_ABS_X / SET_ABS_Y   posición
 *    ANGLE / SPIN                               rotación del strum
 *    ALPHA / SCALE / SCALE_X / SCALE_Y          apariencia
 *    VISIBLE / RESET
 *
 *  MODIFICADORES PER-NOTA (EXISTENTES):
 *    DRUNK_X / DRUNK_Y  — onda senoidal en X/Y según strumTime de cada nota
 *    DRUNK_FREQ         — frecuencia de las ondas drunk (default 1.0)
 *    TORNADO            — rotación en onda según strumTime (carrusel)
 *    CONFUSION          — rotación plana extra en cada nota
 *    SCROLL_MULT        — multiplicador de scroll speed (1.0 = normal, -1 = invertido)
 *    FLIP_X             — invierte posición X de notas (0=normal, 1=espejo)
 *    NOTE_OFFSET_X/Y    — offset plano para todas las notas
 *    BUMPY              — ola Y global por songPosition
 *    BUMPY_SPEED        — velocidad de bumpy (default 2.0)
 *
 *  MODIFICADORES PER-NOTA (NUEVOS v3):
 *    TIPSY              — ola X global por songPosition (vaivén horizontal)
 *    TIPSY_SPEED        — velocidad de tipsy (default 1.0)
 *    INVERT             — scroll invertido local por strum (sin afectar downscroll global)
 *    ZIGZAG             — patrón X escalonado A/-A/A/-A basado en strumTime
 *    ZIGZAG_FREQ        — frecuencia del zigzag (default 1.0)
 *    WAVE               — ola Y viajante (desfase por strumTime, velocidad por songPos)
 *    WAVE_SPEED         — velocidad de wave (default 1.5)
 *    BEAT_SCALE         — pulso de escala en cada beat
 *    STEALTH            — notas invisibles pero hiteables (1=stealth, 0=visible)
 *    NOTE_ALPHA         — alpha multiplicador per-nota independiente del strum
 *
 *  CONTROL DE CÁMARA:
 *    CAM_ZOOM / CAM_MOVE_X / CAM_MOVE_Y / CAM_ANGLE
 */

enum abstract ModEventType(String) from String to String
{
    // ── Strum – Posición ──────────────────────────────────────────────────
    var MOVE_X        = "moveX";
    var MOVE_Y        = "moveY";
    var SET_ABS_X     = "setAbsX";
    var SET_ABS_Y     = "setAbsY";

    // ── Strum – Rotación / apariencia ─────────────────────────────────────
    var ANGLE         = "angle";
    var SPIN          = "spin";
    var ALPHA         = "alpha";
    var SCALE         = "scale";
    var SCALE_X       = "scaleX";
    var SCALE_Y       = "scaleY";
    var VISIBLE       = "visible";
    var RESET         = "reset";

    // ── Per-nota – Drunk (onda senoidal por strumTime) ────────────────────
    var DRUNK_X       = "drunkX";
    var DRUNK_Y       = "drunkY";
    var DRUNK_FREQ    = "drunkFreq";

    // ── Per-nota – Rotación ───────────────────────────────────────────────
    var TORNADO       = "tornado";
    var CONFUSION     = "confusion";

    // ── Per-nota – Scroll / Posición ──────────────────────────────────────
    var SCROLL_MULT   = "scrollMult";
    var FLIP_X        = "flipX";
    var NOTE_OFFSET_X = "noteOffsetX";
    var NOTE_OFFSET_Y = "noteOffsetY";

    // ── Per-nota – Bumpy (ola Y global por songPosition) ──────────────────
    var BUMPY         = "bumpy";
    var BUMPY_SPEED   = "bumpySpeed";

    // ── Per-nota – Tipsy (ola X global por songPosition) — NUEVO ─────────
    /** Ondulación X sincronizada por songPosition (todas las notas del strum
     *  oscilan juntas en X). Complementario a bumpy.
     *  offsetX += tipsy * sin(songPos * 0.001 * tipsySpeed) */
    var TIPSY         = "tipsy";
    /** Velocidad de la ola tipsy (default 1.0). */
    var TIPSY_SPEED   = "tipsySpeed";

    // ── Per-nota – Invert (scroll invertido local) — NUEVO ────────────────
    /** Invierte el eje de scroll solo para este strum (1=invertido, 0=normal).
     *  Permite tener notas "al revés" sin cambiar el downscroll global. */
    var INVERT        = "invert";

    // ── Per-nota – Zigzag (patrón escalonado en X) — NUEVO ───────────────
    /** Desplaza notas en X alternando +amp/-amp/+amp/-amp según strumTime.
     *  Produce un patrón escalonado tipo "zigzag".
     *  offsetX += zigzag * sign(sin(strumTime * 0.001 * zigzagFreq * PI)) */
    var ZIGZAG        = "zigzag";
    /** Frecuencia del patrón zigzag (default 1.0). */
    var ZIGZAG_FREQ   = "zigzagFreq";

    // ── Per-nota – Wave (ola Y viajante por strumTime) — NUEVO ───────────
    /** Ola Y con desfase por strumTime: ondas "viajan" por la columna de notas.
     *  offsetY += wave * sin(songPos * 0.001 * waveSpeed - strumTime * 0.001) */
    var WAVE          = "wave";
    /** Velocidad de la ola viajante (default 1.5). */
    var WAVE_SPEED    = "waveSpeed";

    // ── Per-nota – Beat Scale (escala pulsante en beat) — NUEVO ──────────
    /** Amplitud del pulso de escala por beat (0 = sin pulso).
     *  Requiere que onBeatHit() se llame en ModChartManager cada beat.
     *  La escala pulsa desde (1+beatScale) hasta 1 con decay suave. */
    var BEAT_SCALE    = "beatScale";

    // ── Per-nota – Stealth / Note Alpha — NUEVO ───────────────────────────
    /** 1 = notas invisibles pero hiteables; 0 = visible normal. */
    var STEALTH       = "stealth";
    /** Multiplicador de alpha per-nota (0-1), independiente del alpha del strum.
     *  Alpha final de la nota = noteAlpha * strum.alpha */
    var NOTE_ALPHA    = "noteAlpha";

    // ── Cámara ────────────────────────────────────────────────────────────
    var CAM_ZOOM      = "camZoom";
    var CAM_MOVE_X    = "camMoveX";
    var CAM_MOVE_Y    = "camMoveY";
    var CAM_ANGLE     = "camAngle";
}

// ─── Easings ─────────────────────────────────────────────────────────────────

enum abstract ModEase(String) from String to String
{
    var LINEAR       = "linear";
    var QUAD_IN      = "quadIn";
    var QUAD_OUT     = "quadOut";
    var QUAD_IN_OUT  = "quadInOut";
    var CUBE_IN      = "cubeIn";
    var CUBE_OUT     = "cubeOut";
    var CUBE_IN_OUT  = "cubeInOut";
    var SINE_IN      = "sineIn";
    var SINE_OUT     = "sineOut";
    var SINE_IN_OUT  = "sineInOut";
    var ELASTIC_IN   = "elasticIn";
    var ELASTIC_OUT  = "elasticOut";
    var BOUNCE_OUT   = "bounceOut";
    var BACK_IN      = "backIn";
    var BACK_OUT     = "backOut";
    var INSTANT      = "instant";
}

// ─── Evento individual ────────────────────────────────────────────────────────

typedef ModChartEvent =
{
    var id        : String;
    var beat      : Float;
    /**
     * "player" | "cpu" | "all" | id-de-grupo específico
     * Para CAM_* este campo se ignora (siempre afecta la cámara global).
     */
    var target    : String;
    /** -1 = todos los strums del grupo, 0-3 = individual. */
    var strumIdx  : Int;
    var type      : ModEventType;
    var value     : Float;
    /** Duración en beats. 0 o negativo = instantáneo. */
    var duration  : Float;
    var ease      : ModEase;
    var label     : String;
    var color     : Int;
}

// ─── Archivo completo de modchart ─────────────────────────────────────────────

typedef ModChartData =
{
    var name    : String;
    var song    : String;
    var version : String;
    var events  : Array<ModChartEvent>;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class ModChartHelpers
{
    static var _uid:Int = 0;

    public static function newId():String
        return "ev_" + (++_uid) + "_" + Std.string(Std.random(9999));

    public static function makeEvent(beat:Float, target:String, strumIdx:Int,
                                     type:ModEventType, value:Float,
                                     duration:Float = 0.0, ease:ModEase = LINEAR):ModChartEvent
    {
        return {
            id       : newId(),
            beat     : beat,
            target   : target,
            strumIdx : strumIdx,
            type     : type,
            value    : value,
            duration : duration,
            ease     : ease,
            label    : type,
            color    : defaultColor(type)
        };
    }

    public static function defaultColor(type:ModEventType):Int
    {
        return switch (type)
        {
            case MOVE_X | SET_ABS_X | NOTE_OFFSET_X | FLIP_X | TIPSY | ZIGZAG : 0xFF4FC3F7;
            case MOVE_Y | SET_ABS_Y | NOTE_OFFSET_Y | BUMPY | WAVE             : 0xFF81C784;
            case ANGLE  | SPIN | TORNADO | CONFUSION                            : 0xFFFFB74D;
            case ALPHA  | NOTE_ALPHA | STEALTH                                  : 0xFFBA68C8;
            case SCALE  | SCALE_X | SCALE_Y | BEAT_SCALE                        : 0xFFFF8A65;
            case DRUNK_X | DRUNK_Y | DRUNK_FREQ                                 : 0xFF26C6DA;
            case SCROLL_MULT | INVERT                                            : 0xFFFFD54F;
            case BUMPY_SPEED | TIPSY_SPEED | ZIGZAG_FREQ | WAVE_SPEED           : 0xFF66BB6A;
            case CAM_ZOOM | CAM_MOVE_X | CAM_MOVE_Y | CAM_ANGLE                 : 0xFFEF9A9A;
            case VISIBLE                                                          : 0xFFE0E0E0;
            case RESET                                                            : 0xFFEF5350;
            default                                                               : 0xFF90CAF9;
        };
    }

    public static function applyEase(ease:ModEase, t:Float):Float
    {
        t = Math.max(0, Math.min(1, t));
        return switch (ease)
        {
            case LINEAR       : t;
            case QUAD_IN      : t * t;
            case QUAD_OUT     : t * (2 - t);
            case QUAD_IN_OUT  : t < .5 ? 2*t*t : -1+(4-2*t)*t;
            case CUBE_IN      : t * t * t;
            case CUBE_OUT     : var t1=t-1; t1*t1*t1+1;
            case CUBE_IN_OUT  : t < .5 ? 4*t*t*t : (t-1)*(2*t-2)*(2*t-2)+1;
            case SINE_IN      : 1 - Math.cos(t * Math.PI / 2);
            case SINE_OUT     : Math.sin(t * Math.PI / 2);
            case SINE_IN_OUT  : -(Math.cos(Math.PI*t)-1)/2;
            case ELASTIC_IN   :
                if (t == 0 || t == 1) t
                else { var p=0.3; -(Math.pow(2,10*(t-1))*Math.sin(((t-1)-p/4)*(2*Math.PI)/p)); }
            case ELASTIC_OUT  :
                if (t == 0 || t == 1) t
                else { var p=0.3; Math.pow(2,-10*t)*Math.sin((t-p/4)*(2*Math.PI)/p)+1; }
            case BOUNCE_OUT   : bounceOut(t);
            case BACK_IN      : t*t*((1.70158+1)*t - 1.70158);
            case BACK_OUT     : var t1=t-1; t1*t1*((1.70158+1)*t1+1.70158)+1;
            case INSTANT      : 1.0;
            default           : t;
        };
    }

    static function bounceOut(t:Float):Float
    {
        if      (t < 1/2.75)    return 7.5625*t*t;
        else if (t < 2/2.75)   { t -= 1.5/2.75;   return 7.5625*t*t + 0.75; }
        else if (t < 2.5/2.75) { t -= 2.25/2.75;  return 7.5625*t*t + 0.9375; }
        else                   { t -= 2.625/2.75;  return 7.5625*t*t + 0.984375; }
    }

    public static final ALL_EASES:Array<ModEase> = [
        LINEAR, QUAD_IN, QUAD_OUT, QUAD_IN_OUT,
        CUBE_IN, CUBE_OUT, CUBE_IN_OUT,
        SINE_IN, SINE_OUT, SINE_IN_OUT,
        ELASTIC_IN, ELASTIC_OUT,
        BOUNCE_OUT, BACK_IN, BACK_OUT, INSTANT
    ];

    public static final ALL_TYPES:Array<ModEventType> = [
        MOVE_X, MOVE_Y, SET_ABS_X, SET_ABS_Y,
        ANGLE, SPIN, ALPHA, SCALE, SCALE_X, SCALE_Y, VISIBLE, RESET,
        DRUNK_X, DRUNK_Y, DRUNK_FREQ,
        TORNADO, CONFUSION,
        SCROLL_MULT, FLIP_X,
        NOTE_OFFSET_X, NOTE_OFFSET_Y,
        BUMPY, BUMPY_SPEED,
        TIPSY, TIPSY_SPEED,
        INVERT,
        ZIGZAG, ZIGZAG_FREQ,
        WAVE, WAVE_SPEED,
        BEAT_SCALE,
        STEALTH, NOTE_ALPHA,
        CAM_ZOOM, CAM_MOVE_X, CAM_MOVE_Y, CAM_ANGLE
    ];

    public static inline function isCameraType(type:ModEventType):Bool
    {
        return switch (type)
        {
            case CAM_ZOOM | CAM_MOVE_X | CAM_MOVE_Y | CAM_ANGLE: true;
            default: false;
        };
    }

    public static function beatsToSteps(beats:Float, stepsPerBeat:Int = 4):Float
        return beats * stepsPerBeat;

    public static function stepsToBeat(steps:Float, stepsPerBeat:Int = 4):Float
        return steps / stepsPerBeat;

    public static function typeLabel(type:ModEventType):String
    {
        return switch (type)
        {
            case MOVE_X        : "Move X (offset)";
            case MOVE_Y        : "Move Y (offset)";
            case SET_ABS_X     : "Set X (absolute)";
            case SET_ABS_Y     : "Set Y (absolute)";
            case ANGLE         : "Angle";
            case ALPHA         : "Alpha (0-1)";
            case SCALE         : "Scale";
            case SCALE_X       : "Scale X";
            case SCALE_Y       : "Scale Y";
            case SPIN          : "Spin (deg/beat)";
            case RESET         : "Reset All";
            case VISIBLE       : "Visible (0/1)";
            case DRUNK_X       : "Drunk X (px amplitude)";
            case DRUNK_Y       : "Drunk Y (px amplitude)";
            case DRUNK_FREQ    : "Drunk Frequency (default 1.0)";
            case TORNADO       : "Tornado (deg amplitude)";
            case CONFUSION     : "Confusion (deg flat)";
            case SCROLL_MULT   : "Scroll Multiplier (default 1.0)";
            case FLIP_X        : "Flip X (0=normal, 1=mirror)";
            case NOTE_OFFSET_X : "Note Offset X (px)";
            case NOTE_OFFSET_Y : "Note Offset Y (px)";
            case BUMPY         : "Bumpy Y (px amplitude, global)";
            case BUMPY_SPEED   : "Bumpy Speed (default 2.0)";
            case TIPSY         : "Tipsy X (px amplitude, global)";
            case TIPSY_SPEED   : "Tipsy Speed (default 1.0)";
            case INVERT        : "Invert Scroll (1=inverted, 0=normal)";
            case ZIGZAG        : "Zigzag X (px amplitude)";
            case ZIGZAG_FREQ   : "Zigzag Frequency (default 1.0)";
            case WAVE          : "Wave Y (px amplitude, traveling)";
            case WAVE_SPEED    : "Wave Speed (default 1.5)";
            case BEAT_SCALE    : "Beat Scale (amplitude 0-1)";
            case STEALTH       : "Stealth (1=invisible hiteable, 0=normal)";
            case NOTE_ALPHA    : "Note Alpha override (0-1)";
            case CAM_ZOOM      : "Camera Zoom (+offset)";
            case CAM_MOVE_X    : "Camera Move X (px)";
            case CAM_MOVE_Y    : "Camera Move Y (px)";
            case CAM_ANGLE     : "Camera Angle (deg)";
            default            : type;
        };
    }
}
