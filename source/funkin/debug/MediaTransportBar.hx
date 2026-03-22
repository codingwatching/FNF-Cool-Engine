package funkin.debug;

// ─── Core ─────────────────────────────────────────────────────────────────────
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.math.FlxRect;
import flixel.text.FlxText;

// ─── Engine ───────────────────────────────────────────────────────────────────
import funkin.data.Conductor;

using StringTools;

/**
 * MediaTransportBar v1.0
 *
 * Barra of playback estilo YouTube in screen complete.
 * Sin control de volumen (lo maneja SoundTray).
 * Diseñada for reutilizarse in any editor of the engine.
 *
 * ─── Uso minimum ───────────────────────────────────────────────────────────────
 *
 *   // En create():
 *   var bar = new MediaTransportBar(0, FlxG.height - MediaTransportBar.BAR_H, FlxG.width, camHUD);
 *   bar.songLength    = FlxG.sound.music.length;
 *   bar.onSeek        = function(ms)     { FlxG.sound.music.time = ms; Conductor.songPosition = ms; };
 *   bar.onPlayToggle  = function(playing) { if (playing) FlxG.sound.music.resume() else FlxG.sound.music.pause(); };
 *   bar.onStop        = function()        { FlxG.sound.music.stop(); };
 *   bar.onSpeedChange = function(rate)    { FlxG.sound.music.pitch = rate; };
 *   add(bar);
 *
 *   // En update():
 *   bar.songPosition = Conductor.songPosition;
 *
 * ─── Controles ────────────────────────────────────────────────────────────────
 *
 *   Click/drag progress bar  → seek
 *   |< (⏮)                   → ir al inicio
 *   << (⏪)                   → retroceder 4 beats
 *   ▶ / ⏸                     → play / pause
 *   >> (⏩)                   → avanzar 4 beats
 *   >| (⏭)                   → ir al final
 *   ⏹                        → stop (vuelve a 0)
 *   Botones de velocidad     → 25% 50% 75% 1× 1.25× 1.5× 2×
 *
 * Compatible con: PlayStateEditorState, CutsceneEditor, ChartingState, ModChartEditorState, etc.
 *
 * @author Cool Engine Team
 */
class MediaTransportBar extends FlxGroup
{
    // ── Dimensiones public ──────────────────────────────────────────────────
    /** Altura total de la barra — usar para posicionarla en el estado padre. */
    public static inline final BAR_H         : Int = 56;

    // ── Dimensiones internas ──────────────────────────────────────────────────
    static inline final PROG_ZONE_H  : Int = 18;   // zona de hit del scrubber
    static inline final PROG_H_IDLE  : Int = 4;    // grosor en reposo
    static inline final PROG_H_HOVER : Int = 8;    // grosor al hover
    static inline final CTRL_H       : Int = 38;   // fila de controles

    // ── Paleta ────────────────────────────────────────────────────────────────
    static inline final C_BG          : Int = 0xEA0C0C16;
    static inline final C_PROG_TRACK  : Int = 0xFF353550;
    static inline final C_PROG_FILL   : Int = 0xFF00D9FF;
    static inline final C_PROG_DOT    : Int = 0xFFFFFFFF;
    static inline final C_BTN         : Int = 0xFF161628;
    static inline final C_BTN_HOV     : Int = 0xFF242440;
    static inline final C_BTN_ACT     : Int = 0xFF003344;
    static inline final C_TEXT        : Int = 0xFFDDDDFF;
    static inline final C_TEXT_DIM    : Int = 0xFF6666AA;
    static inline final C_ACCENT      : Int = 0xFF00D9FF;
    static inline final C_SPEED_LBL   : Int = 0xFF44446A;

    // ── API public ───────────────────────────────────────────────────────────

    /** Duration total of the pista in ms. Asignar tras load the audio. */
    public var songLength : Float = 1;

    /**
     * Position current of playback in ms.
     * Actualizar cada frame: `bar.songPosition = Conductor.songPosition;`
     * The setter ignora the assignment while the usuario arrastra the scrubber.
     */
    public var songPosition(get, set) : Float;

    /** State of playback — refleja the toggle internal of the barra. */
    public var isPlaying : Bool = false;

    /** Velocidad of playback actualmente seleccionada. */
    public var playbackRate : Float = 1.0;

    // ── Callbacks ─────────────────────────────────────────────────────────────

    /** Seek solicitado by the usuario. Parameter: time in ms. */
    public var onSeek        : Float -> Void = null;

    /** Toggle play/pause. `true` = reproduciendo. */
    public var onPlayToggle  : Bool  -> Void = null;

    /** Stop y regreso al inicio. */
    public var onStop        : Void  -> Void = null;

    /** Cambio of speed. Parameter: multiplier (0.25 – 2.0). */
    public var onSpeedChange : Float -> Void = null;

    // ── Estado interno ────────────────────────────────────────────────────────
    var _cam    : FlxCamera;
    var _bw     : Int;     // ancho total
    var _bx     : Float;   // X origen
    var _by     : Float;   // Y origen

    // Progreso
    var _progBg     : FlxSprite;
    var _progFill   : FlxSprite;
    var _progDot    : FlxSprite;
    var _progZone   : FlxSprite;  // zona de hit transparente
    var _prevFillW  : Int  = -1;
    var _prevFillH  : Int  = -1;

    // Botones de transporte
    var _btnToStart : _MTBtn;
    var _btnBack    : _MTBtn;
    var _btnPlay    : _MTBtn;
    var _btnFwd     : _MTBtn;
    var _btnToEnd   : _MTBtn;
    var _btnStop    : _MTBtn;

    // Textos
    var _timeTxt    : FlxText;
    var _bpmTxt     : FlxText;

    // Velocidad
    static final SPEED_VALS : Array<Float>  = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    static final SPEED_LBLS : Array<String> = ["25%", "50%", "75%", "1×", "1.25×", "1.5×", "2×"];
    var _speedBtns  : Array<_MTBtn> = [];

    // Drag / hover
    var _scrubDrag  : Bool  = false;
    var _progHov    : Bool  = false;
    var _pos        : Float = 0;

    // ═════════════════════════════════════════════════════════════════════════
    //  Constructor
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * @param x     X del borde izquierdo (normalmente 0).
     * @param y     Y del borde superior (normalmente `FlxG.height - BAR_H`).
     * @param width Ancho total (normalmente `FlxG.width`).
     * @param cam   Camera HUD of the state padre.
     */
    public function new(x:Float, y:Float, width:Int, cam:FlxCamera)
    {
        super();
        _bx  = x;
        _by  = y;
        _bw  = width;
        _cam = cam;

        _buildBg();
        _buildProgress();
        _buildControls();
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Build
    // ═════════════════════════════════════════════════════════════════════════

    function _buildBg():Void
    {
        var bg = new FlxSprite(_bx, _by).makeGraphic(_bw, BAR_H, C_BG);
        _reg(bg);
        add(bg);

        // Line of separation superior
        var sep = new FlxSprite(_bx, _by).makeGraphic(_bw, 1, 0xFF1E1E38);
        _reg(sep);
        add(sep);
    }

    function _buildProgress():Void
    {
        // Pista de fondo (siempre ancho completo)
        _progBg = new FlxSprite(_bx, _by + 7).makeGraphic(_bw, PROG_H_HOVER, C_PROG_TRACK);
        _reg(_progBg);
        add(_progBg);

        // Relleno de progreso (se redimensiona cada frame con makeGraphic)
        _progFill = new FlxSprite(_bx, _by + 7).makeGraphic(1, PROG_H_HOVER, C_PROG_FILL);
        _reg(_progFill);
        add(_progFill);

        // Bolita del playhead — solo visible en hover
        _progDot = new FlxSprite(_bx, _by + 7 - 4).makeGraphic(14, 14, C_PROG_DOT);
        _reg(_progDot);
        _progDot.visible = false;
        add(_progDot);

        // Zona of hit invisible that covers all the area of the scrubber
        _progZone = new FlxSprite(_bx, _by).makeGraphic(_bw, PROG_ZONE_H + 4, 0x00000000);
        _reg(_progZone);
        add(_progZone);
    }

    function _buildControls():Void
    {
        final cy  = _by + PROG_ZONE_H;   // Y de la fila de controles
        final bh  = 26;                  // height of button
        final by2 = cy + Std.int((CTRL_H - bh) / 2);

        // ── Botones de transporte ─────────────────────────────────────────────
        // Anchos: transporte small = 28, play = 36
        var bx : Float = _bx + 10;

        _btnToStart = _mkBtn(bx, by2, 28, bh, '⏮', _onToStart);   bx += 30;
        _btnBack    = _mkBtn(bx, by2, 28, bh, '⏪', _onBack);       bx += 30;
        _btnPlay    = _mkBtn(bx, by2, 36, bh, '▶',  _onPlayPause);  bx += 40;
        _btnFwd     = _mkBtn(bx, by2, 28, bh, '⏩', _onFwd);        bx += 30;
        _btnToEnd   = _mkBtn(bx, by2, 28, bh, '⏭', _onToEnd);      bx += 30;
        _btnStop    = _mkBtn(bx, by2, 28, bh, '⏹', _onStop);       bx += 36;

        // ── Tiempo ────────────────────────────────────────────────────────────
        _timeTxt = new FlxText(bx, by2 + 4, 130, '0:00 / 0:00', 11);
        _timeTxt.setFormat(Paths.font('vcr.ttf'), 11, C_TEXT, LEFT);
        _reg(_timeTxt);
        add(_timeTxt);
        bx += 136;

        // ── BPM ───────────────────────────────────────────────────────────────
        _bpmTxt = new FlxText(bx, by2 + 4, 90, '100 BPM', 11);
        _bpmTxt.setFormat(Paths.font('vcr.ttf'), 11, C_TEXT_DIM, LEFT);
        _reg(_bpmTxt);
        add(_bpmTxt);

        // ── Velocidades (alineadas a la derecha) ──────────────────────────────
        final sbw  = 38;
        final sgap = 3;
        final totalSpeedW = SPEED_VALS.length * sbw + (SPEED_VALS.length - 1) * sgap;
        var rx : Float = _bx + _bw - 10 - totalSpeedW;

        for (i in 0...SPEED_VALS.length)
        {
            final s   = SPEED_VALS[i];
            final lbl = SPEED_LBLS[i];
            final btn = _mkBtn(rx, by2, sbw, bh, lbl, () -> _onSpeed(s));
            _speedBtns.push(btn);
            rx += sbw + sgap;
        }

        // Etiqueta "SPEED" justo to the izquierda of the primer button of velocidad
        final speedLblX = _bx + _bw - 10 - totalSpeedW - 54;
        var speedLbl = new FlxText(speedLblX, by2 + 6, 50, 'SPEED', 10);
        speedLbl.setFormat(Paths.font('vcr.ttf'), 10, C_TEXT_DIM, RIGHT);
        _reg(speedLbl);
        add(speedLbl);

        _refreshSpeedBtns();
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Update
    // ═════════════════════════════════════════════════════════════════════════

    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);

        final mx = FlxG.mouse.x;
        final my = FlxG.mouse.y;

        // ── Hover del scrubber ────────────────────────────────────────────────
        _progHov = (mx >= _bx && mx <= _bx + _bw && my >= _by && my <= _by + PROG_ZONE_H + 4);

        // ── Drag del scrubber ─────────────────────────────────────────────────
        if (FlxG.mouse.justPressed && _progHov)   _scrubDrag = true;
        if (FlxG.mouse.justReleased)              _scrubDrag = false;

        if (_scrubDrag && songLength > 0)
        {
            final ratio = FlxMath.bound((mx - _bx) / _bw, 0, 1);
            _pos = ratio * songLength;
            if (onSeek != null) onSeek(_pos);
        }

        // ── Actualizar visuales ───────────────────────────────────────────────
        _updateProgress();
        _updateTexts();
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Update of visuales
    // ═════════════════════════════════════════════════════════════════════════

    function _updateProgress():Void
    {
        final ratio = (songLength > 0) ? FlxMath.bound(_pos / songLength, 0, 1) : 0;
        final ph    = _progHov ? PROG_H_HOVER : PROG_H_IDLE;
        final py    = _by + Std.int((PROG_ZONE_H - ph) / 2);
        final fw    = Std.int(Math.max(1, ratio * _bw));

        // Fondo of pista — only redibuja if changed the grosor
        if (_prevFillH != ph)
        {
            _progBg.makeGraphic(_bw, ph, C_PROG_TRACK);
            _prevFillH = ph;
        }
        _progBg.y = py;

        // Filled — redibuja if changed the anchura or the grosor
        if (_prevFillW != fw || _prevFillH != ph)
        {
            _progFill.makeGraphic(fw, ph, C_PROG_FILL);
            _prevFillW = fw;
        }
        _progFill.y = py;

        // Bolita del playhead
        _progDot.visible = _progHov;
        if (_progHov)
        {
            _progDot.x = _bx + ratio * _bw - _progDot.width * 0.5;
            _progDot.y = py - (_progDot.height - ph) * 0.5;
        }
    }

    function _updateTexts():Void
    {
        _timeTxt.text = '${_fmtMs(_pos)} / ${_fmtMs(songLength)}';
        _bpmTxt.text  = '${Std.int(Conductor.getBPMFromTime(_pos))} BPM';
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Callbacks de botones
    // ═════════════════════════════════════════════════════════════════════════

    function _onToStart():Void
    {
        _doSeek(0);
    }

    function _onBack():Void
    {
        _doSeek(_pos - Conductor.crochet * 4);
    }

    function _onPlayPause():Void
    {
        isPlaying = !isPlaying;
        _btnPlay.label.text = isPlaying ? '⏸' : '▶';
        if (onPlayToggle != null) onPlayToggle(isPlaying);
    }

    function _onFwd():Void
    {
        _doSeek(_pos + Conductor.crochet * 4);
    }

    function _onToEnd():Void
    {
        _doSeek(songLength);
    }

    function _onStop():Void
    {
        isPlaying = false;
        _btnPlay.label.text = '▶';
        _doSeek(0);
        if (onStop != null) onStop();
    }

    function _onSpeed(rate:Float):Void
    {
        playbackRate = rate;
        _refreshSpeedBtns();
        if (onSpeedChange != null) onSpeedChange(rate);
    }

    function _doSeek(ms:Float):Void
    {
        _pos = FlxMath.bound(ms, 0, songLength);
        if (onSeek != null) onSeek(_pos);
    }

    function _refreshSpeedBtns():Void
    {
        for (i in 0...SPEED_VALS.length)
            _speedBtns[i].setActive(Math.abs(SPEED_VALS[i] - playbackRate) < 0.01);
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═════════════════════════════════════════════════════════════════════════

    /** Registra scrollFactor and camera in a FlxSprite/FlxText. */
    inline function _reg(s:flixel.FlxBasic):Void
    {
        if (Std.isOfType(s, FlxSprite))
            (cast s : FlxSprite).scrollFactor.set(0, 0);
        else if (Std.isOfType(s, FlxText))
            (cast s : FlxText).scrollFactor.set(0, 0);
        s.cameras = [_cam];
    }

    /** Creates and registra a button of transporte. */
    function _mkBtn(x:Float, y:Float, w:Int, h:Int, lbl:String, cb:Void->Void):_MTBtn
    {
        var btn = new _MTBtn(x, y, w, h, lbl, C_BTN, C_TEXT, cb);
        btn.scrollFactor.set(0, 0);
        btn.cameras = [_cam];
        add(btn);
        add(btn.label);
        return btn;
    }

    /** Formatea ms en `m:ss`. */
    static function _fmtMs(ms:Float):String
    {
        final sec = Std.int(ms / 1000);
        final m   = Std.int(sec / 60);
        final s   = sec % 60;
        return '${m}:${s < 10 ? "0" : ""}${s}';
    }

    // ── Getters / setters ─────────────────────────────────────────────────────

    function get_songPosition():Float
        return _pos;

    function set_songPosition(v:Float):Float
    {
        if (!_scrubDrag) _pos = v;
        return _pos;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _MTBtn — button minimalista without dependencias of FlxUI
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Button of transporte for MediaTransportBar.
 * Idéntico in funcionamiento to MiniBtn2 of the PlayStateEditorState
 * pero con soporte de estado "activo" para los botones de velocidad.
 */
private class _MTBtn extends FlxSprite
{
    public var label    : FlxText;
    public var onClick  : Void -> Void;

    var _base    : Int;
    var _hover   : Int;
    var _active  : Int;
    var _isHov   : Bool = false;
    var _isAct   : Bool = false;

    public function new(x:Float, y:Float, w:Int, h:Int, lbl:String, color:Int, txtColor:Int, ?cb:Void->Void)
    {
        super(x, y);
        makeGraphic(w, h, color);
        _base   = color;
        _hover  = _lighten(color, 22);
        _active = 0xFF003344;
        onClick = cb;

        label = new FlxText(x, y, w, lbl, 11);
        label.setFormat(Paths.font('vcr.ttf'), 11, txtColor, CENTER);
        label.scrollFactor.set(0, 0);
    }

    // Propaga the assignment of camera to the label automatically
    override private function set_cameras(value:Array<flixel.FlxCamera>):Array<flixel.FlxCamera>
    {
        if (label != null) label.cameras = value;
        return super.set_cameras(value);
    }

    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);
        if (!alive || !exists || !visible) return;

        final cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
        final ov  = FlxG.mouse.overlaps(this, cam);

        if (ov != _isHov)
        {
            _isHov = ov;
            _redraw();
        }

        // Mantener the label centrado over the button
        label.x = x;
        label.y = y + (height - label.height) * 0.5;

        if (ov && FlxG.mouse.justPressed && onClick != null)
            onClick();
    }

    /** Marca the button as active/inactive (for buttons of velocidad). */
    public function setActive(v:Bool):Void
    {
        if (v == _isAct) return;
        _isAct = v;
        label.color = v ? 0xFF00D9FF : 0xFFDDDDFF;
        _redraw();
    }

    function _redraw():Void
    {
        final c = _isAct ? _active : (_isHov ? _hover : _base);
        makeGraphic(Std.int(width), Std.int(height), c);
    }

    static function _lighten(c:Int, amt:Int):Int
    {
        final a = (c >> 24) & 0xFF;
        final r = Std.int(Math.min(255, ((c >> 16) & 0xFF) + amt));
        final g = Std.int(Math.min(255, ((c >>  8) & 0xFF) + amt));
        final b = Std.int(Math.min(255, ( c        & 0xFF) + amt));
        return (a << 24) | (r << 16) | (g << 8) | b;
    }
}
