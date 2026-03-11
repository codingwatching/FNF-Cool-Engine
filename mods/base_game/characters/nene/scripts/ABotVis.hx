/**
 * ABotVis.hx — Visualizador de barras del A-Bot.
 * Usa los sprites reales de aBotViz.xml en lugar de rectángulos sólidos.
 *
 * aBotViz.xml tiene 7 barras (viz1–viz7), cada una con 6 niveles de altura:
 *   nivel 0000 = barra llena (máximo)
 *   nivel 0005 = barra mínima
 *
 * ── SISTEMA BEAT-TIMING (igual que script.hx bits) ───────────────────────────
 * Cada beat, onBeatHit() fija un pico (_hitPeak) en cada barra.
 * En update(), el nivel actual decae desde ese pico según:
 *   level = peak * (1.0 - beatProgress * decay) * volume
 * donde beatProgress = (Conductor.songPosition % Conductor.crochet) / Conductor.crochet.
 * Cada barra tiene distinto decay y distinto pico → efecto ecualizador orgánico.
 * El stagger (delay entre barras en onBeatHit) crea la ola visual izquierda→derecha.
 */

var NUM_BARS:Int    = 7;
var NUM_LEVELS:Int  = 6;
var BAR_GAP:Int     = 1;

// Anchos del frame virtual en aBotViz.xml para viz1–viz7
var BAR_WIDTHS:Array<Int> = [68, 58, 58, 57, 62, 67, 71];

// Escala visual de cada barra (aplicada con setGraphicSize tras cargar el sprite)
var BAR_SCALE:Float = 0.91;

// ── Parámetros del beat-timing ────────────────────────────────────────────────
// Pico de cada barra en el golpe de beat (0=min, 1=max).
// Subido: barras exteriores a 1.0, centro a 0.80 → más potencia visible.
var HIT_PEAK:Array<Float> = [1.00, 0.92, 0.82, 0.72, 0.82, 0.92, 1.00];

// Velocidad de caída. 1.0 = llega a 0 exactamente al final del beat.
// Valores mayores → caída más rápida (barras cortas). Menores → caída lenta.
// Barras exteriores caen más despacio → el arco se mantiene más tiempo.
var DECAY:Array<Float> = [0.65, 0.80, 1.00, 1.20, 1.00, 0.80, 0.65];

// Delay de cada barra en el onBeatHit (segundos). Ola izq→der.
// Barras disparan de izquierda a derecha con 12ms entre cada una.
var STAGGER:Array<Float> = [0.000, 0.012, 0.024, 0.036, 0.048, 0.060, 0.072];

/** Rellena con ceros a la izquierda hasta `digits` dígitos. */
function padNum(n:Int, digits:Int):String
{
    var s = Std.string(n);
    while (s.length < digits) s = '0' + s;
    return s;
}

/**
 * Crea el visualizador en (baseX, baseY) y devuelve un objeto
 * con los métodos: initAnalyzer, dumpSound, update, setBase,
 * setVisible, setAlpha, setShader, destroy.
 *
 * baseX / baseY = esquina superior-izquierda del área de barras.
 * Las barras se anclan por abajo gracias al trim del Sparrow,
 * así que su fondo siempre queda en baseY + frameHeight.
 */
function create(baseX:Float, baseY:Float):Dynamic
{
    var bars:Array<FunkinSprite> = [];
    // ── Estado beat-timing ────────────────────────────────────────────────────
    // _levels: nivel actual de cada barra (0.0–1.0), calculado en update()
    // _peaks:  pico fijado en el último onBeatHit (decae desde aquí)
    var _levels:Array<Float>    = [];
    var _peaks:Array<Float>     = [];
    var active:Bool             = false;
    var _baseX:Float            = baseX;
    var _baseY:Float            = baseY;

    // Offsets X acumulados para cada barra
    var xOffsets:Array<Float>   = [];

    for (i in 0...NUM_BARS) { _levels.push(0.0); _peaks.push(0.0); }

    // Precalcular posición X de cada barra (usando ancho escalado)
    var curX:Float = 0.0;
    for (i in 0...NUM_BARS)
    {
        xOffsets.push(curX);
        curX += Math.round(BAR_WIDTHS[i] * BAR_SCALE) + BAR_GAP;
    }

    // Crear sprites de barra usando aBotViz.xml
    for (i in 0...NUM_BARS)
    {
        var bar = new FunkinSprite(0, 0);
        bar.loadCharacterSparrow('abot/aBotViz');
        bar.antialiasing = true;
        // Reducir tamaño de las barras para que quepan bien en el A-Bot
        bar.setScale(BAR_SCALE, BAR_SCALE);

        // Añadir una animación de un frame por cada nivel de altura
        // viz1 → niveles viz10000…viz10005, viz2 → viz20000…viz20005, etc.
        var prefix:String = 'viz' + Std.string(i + 1);
        // BUGFIX: usar bar.addAnim() en lugar de bar.animation.addByPrefix() directamente.
        // addAnim() es la API unificada de FunkinSprite que maneja tanto Sparrow como
        // Animate Atlas. animation.addByPrefix() falla en Atlas (no hay FlxAnimation objects).
        //
        // Nota de nombres: los frames en el Sparrow XML suelen nombrarse con espacio antes
        // del número (e.g. "viz1 0000"). addByPrefix en Sparrow busca frames que EMPIECEN
        // con el prefix dado, por lo que "viz10000" (sin espacio) no matchea "viz1 0000".
        // addAnim() delega a addByFrameLabel en Atlas (que usa el nombre exacto del label)
        // y a addByPrefix en Sparrow (donde el prefix debe coincidir con el inicio del nombre).
        // Si las barras no aparecen, verificar que el XML use "viz10000" sin espacio,
        // o cambiar frameName a 'viz' + (i+1) + ' ' + padNum(lvl, 4) si usa espacio.
        for (lvl in 0...NUM_LEVELS)
        {
            var frameName:String = prefix + padNum(lvl, 4);
            bar.addAnim('lvl' + lvl, frameName, 0, false);
        }
        // Arrancar en nivel mínimo (barra más baja)
        bar.playAnim('lvl5', true);

        bar.x     = _baseX + xOffsets[i];
        bar.y     = _baseY;
        bar.alpha = 0.0;
        bars.push(bar);
    }

    // ── API pública ────────────────────────────────────────────────────────
    return {
        bars: bars,

        initAnalyzer: function()
        {
            active = true;
            for (i in 0...NUM_BARS) { _levels[i] = 0.0; _peaks[i] = 0.0; }
            for (i in 0...bars.length)
                FlxTween.tween(bars[i], { alpha: 1.0 }, 0.3);
        },

        dumpSound: function()
        {
            active = false;
            for (i in 0...bars.length)
                FlxTween.tween(bars[i], { alpha: 0.0 }, 0.4);
        },

        /**
         * onBeatHit: llamado desde nene.hx en cada beat.
         * Fija el pico de cada barra con stagger (ola izq→der).
         */
        onBeatHit: function(beat:Int)
        {
            if (!active) return;
            for (i in 0...NUM_BARS)
            {
                var delay:Float = STAGGER[i];
                if (delay <= 0.001)
                {
                    _peaks[i] = HIT_PEAK[i];
                }
                else
                {
                    var barIdx:Int = i;
                    new FlxTimer().start(delay, function(t:Dynamic) {
                        _peaks[barIdx] = HIT_PEAK[barIdx];
                    }, 1);
                }
            }
        },

        update: function(elapsed:Float)
        {
            // Volumen perceptible = slider global × volumen del track
            var vol:Float = 0.0;
            if (FlxG.sound.music != null && FlxG.sound.music.playing)
                vol = FlxG.sound.volume * FlxG.sound.music.volume;
            if (vol < 0.0) vol = 0.0;
            if (vol > 1.0) vol = 1.0;

            // Progreso dentro del beat actual (0.0 = golpe → 1.0 = siguiente golpe)
            var crochet:Float  = (Conductor != null && Conductor.crochet > 0.0) ? Conductor.crochet : 500.0;
            var songPos:Float  = (Conductor != null) ? Conductor.songPosition : 0.0;
            var beatProg:Float = (songPos % crochet) / crochet;
            if (beatProg < 0.0) beatProg += 1.0;

            for (i in 0...NUM_BARS)
            {
                var bar = bars[i];
                if (bar == null) continue;

                // Cuando no está activo, bajar picos suavemente (barras bajan solas)
                if (!active)
                    _peaks[i] *= 0.90;

                // Nivel = peak * (1 - beatProgress * decay) * vol
                var fall:Float = beatProg * DECAY[i];
                if (fall > 1.0) fall = 1.0;
                _levels[i] = _peaks[i] * (1.0 - fall) * vol;

                // Mapear nivel (0.0–1.0) a frame (lvl0=barra llena, lvl5=barra mínima)
                var frameIdx:Int = Math.round((1.0 - _levels[i]) * (NUM_LEVELS - 1));
                if (frameIdx < 0)           frameIdx = 0;
                if (frameIdx >= NUM_LEVELS) frameIdx = NUM_LEVELS - 1;

                var animName:String = 'lvl' + frameIdx;
                if (bar.animName != animName)
                    bar.playAnim(animName, true);

                bar.x = _baseX + xOffsets[i];
                bar.y = _baseY;
            }
        },

        setVisible: function(v:Bool)
        {
            for (i in 0...bars.length) if (bars[i] != null) bars[i].visible = v;
        },

        setShader: function(sh:Dynamic)
        {
            for (i in 0...bars.length) if (bars[i] != null) bars[i].shader = sh;
        },

        /**
         * Actualiza la posición base del visualizador.
         * (llamado cada frame desde nene.hx para seguir al personaje)
         */
        setBase: function(x:Float, y:Float)
        {
            _baseX = x;
            _baseY = y;
        },

        setAlpha: function(a:Float)
        {
            for (i in 0...bars.length) if (bars[i] != null) bars[i].alpha = a;
        },

        destroy: function()
        {
            active = false;
            for (i in 0...bars.length) if (bars[i] != null) bars[i].destroy();
            bars = [];
        }
    };
}
