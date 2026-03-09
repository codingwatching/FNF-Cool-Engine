/**
 * ABotVis.hx — Visualizador de barras de audio del A-Bot.
 *
 * Uso desde otro script:
 *   var vizMod = require('characters/nene/scripts/ABotVis.hx');
 *   var viz    = vizMod.get('create')(baseX, baseY);
 *   viz.initAnalyzer();
 *   viz.update(elapsed);
 *   viz.dumpSound();
 *   viz.destroy();
 */

var NUM_BARS:Int    = 9;
var BAR_W:Int       = 9;
var BAR_GAP:Int     = 4;
var BAR_MIN_H:Float = 4.0;
var BAR_MAX_H:Float = 48.0;

var COLORS:Array<Dynamic> = [
    0xFF1A6B9E, 0xFF1E7AB5, 0xFF2289CC, 0xFF29A0D4,
    0xFF30B8DC, 0xFF38CEE4, 0xFF44DEED, 0xFF56EEF4, 0xFF76F8F8
];

var ATTACK:Array<Float>      = [0.25, 0.30, 0.38, 0.45, 0.52, 0.60, 0.68, 0.76, 0.85];
var RELEASE:Array<Float>     = [0.06, 0.08, 0.10, 0.13, 0.17, 0.21, 0.26, 0.32, 0.40];
var SENSITIVITY:Array<Float> = [1.60, 1.50, 1.30, 1.10, 1.00, 0.95, 0.90, 0.85, 0.80];
var PHASE:Array<Int>         = [0, 1, 1, 2, 3, 4, 4, 5, 6];
var HISTORY_SIZE:Int         = 12;

/**
 * Factory: crea el visualizador en (baseX, baseY) y devuelve un objeto
 * con los métodos: initAnalyzer, dumpSound, update, setAlpha, setShader, destroy.
 */
function create(baseX:Float, baseY:Float):Dynamic
{
    // ── Estado interno ────────────────────────────────────────────────────
    var bars:Array<FlxSprite>  = [];
    var levels:Array<Float>    = [];
    var history:Array<Float>   = [];
    var histIdx:Int            = 0;
    var active:Bool            = false;

    for (i in 0...NUM_BARS)    levels.push(0.0);
    for (i in 0...HISTORY_SIZE) history.push(0.0);

    // ── Construir barras ──────────────────────────────────────────────────
    for (i in 0...NUM_BARS)
    {
        var bar = new FlxSprite();
        bar.makeGraphic(BAR_W, Std.int(BAR_MAX_H), COLORS[i]);
        bar.x = baseX + i * (BAR_W + BAR_GAP);
        bar.y = baseY;
        bar.alpha = 0.0;
        bar.antialiasing = false;
        bars.push(bar);
    }

    // ── API pública expuesta como objeto ──────────────────────────────────
    return {
        bars: bars,

        initAnalyzer: function()
        {
            active  = true;
            histIdx = 0;
            for (i in 0...HISTORY_SIZE) history[i] = 0.0;
            for (i in 0...NUM_BARS)     levels[i]  = 0.0;
            for (i in 0...bars.length)
                FlxTween.tween(bars[i], { alpha: 1.0 }, 0.3);
        },

        dumpSound: function()
        {
            active = false;
            for (i in 0...bars.length)
                FlxTween.tween(bars[i], { alpha: 0.0 }, 0.4);
        },

        update: function(elapsed:Float)
        {
            var rawAmp:Float = 0.0;
            if (FlxG.sound.music != null && FlxG.sound.music.playing)
                rawAmp = FlxG.sound.music.amplitude;
            rawAmp = Math.min(1.0, rawAmp * 3.5);

            history[histIdx] = rawAmp;
            histIdx = (histIdx + 1) % HISTORY_SIZE;

            for (i in 0...NUM_BARS)
            {
                var bar = bars[i];
                if (bar == null) continue;

                if (!active)
                {
                    levels[i] *= (1.0 - RELEASE[i] * 2.0);
                }
                else
                {
                    var delay:Int   = PHASE[i];
                    var pos:Int     = ((histIdx - 1 - delay) + HISTORY_SIZE * 2) % HISTORY_SIZE;
                    var target:Float = Math.min(1.0, history[pos] * SENSITIVITY[i]);
                    var alpha:Float  = (target > levels[i]) ? ATTACK[i] : RELEASE[i];
                    levels[i] += (target - levels[i]) * alpha;
                }

                var h:Float = BAR_MIN_H + levels[i] * (BAR_MAX_H - BAR_MIN_H);
                bar.scale.y = h / BAR_MAX_H;
                // FIX: el pivot/origin de FlxSprite está en el CENTRO por defecto,
                // no en el borde superior. Al escalar, el sprite se encoge hacia
                // el centro, así que hay que compensar con la mitad del desplazamiento.
                // Fórmula correcta: baseY + (BAR_MAX_H - h) * 0.5
                // (antes era baseY + (BAR_MAX_H - h), que asumía pivot en top y
                //  desplazaba las barras el doble hacia abajo)
                bar.y = baseY + (BAR_MAX_H - h) * 0.5;
            }
        },

        setVisible: function(v:Bool)
        {
            for (i in 0...bars.length) bars[i].visible = v;
        },

        setShader: function(sh:Dynamic)
        {
            for (i in 0...bars.length) bars[i].shader = sh;
        },

        destroy: function()
        {
            active = false;
            for (i in 0...bars.length) if (bars[i] != null) bars[i].destroy();
            bars = [];
        }
    };
}
