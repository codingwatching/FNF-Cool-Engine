package funkin.audio;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;

/**
 * SoundTray — persiste entre cambios de state igual que los stickers.
 *
 * system: Same pattern as StickerTransition/StickerTransitionContainer:
 *  - SoundTrayContainer extiende openfl.display.Sprite
 *  - La FlxCamera es hijo del Sprite de OpenFL (NO de FlxG.cameras.list)
 *    → never is destroys when Flixel resetea the cameras to the change state
 *  - Update via FlxG.signals.preUpdate (sobrevive cambios de state)
 *  - Insertado via FlxG.addChildBelowMouse con z muy alto (encima de stickers)
 *
 * FIXES adicionales:
 *  1. Sin doble volumen: limpia volumeUpKeys/volumeDownKeys/muteKeys de Flixel.
 *  2. Barras correctas: Math.round en vez de Math.floor (fix float 0.5999...).
 *  3. Fade in/out al mostrar/ocultar.
 */
class SoundTray extends FlxBasic
{
    /**
     * Singleton activo del SoundTray.
     * VolumePlugin lo usa para delegar volumeUp/volumeDown/toggleMute.
     */
    public static var instance(default, null):Null<SoundTray> = null;

    /**
     * When is in true, the SoundTray ignora the keys of volumen.
     * Usado por ScriptEditorSubState (y cualquier UI con input de texto)
     * para evitar que escribir 0, + o - cambie el volumen.
     */
    public static var blockInput:Bool = false;

    // ── Contenedor OpenFL persistente ─────────────────────────────────────────
    private static var _container:SoundTrayContainer;

    // ── Sprites ───────────────────────────────────────────────────────────────
    private var volumeBox:FlxSprite;
    private var volumeBarBg:FlxSprite;
    private var volumeBar:FlxSprite;

    // ── Sonidos ───────────────────────────────────────────────────────────────
    private var volumeUpSound:String   = "assets/sounds/soundtray/Volup.ogg";
    private var volumeDownSound:String = "assets/sounds/soundtray/Voldown.ogg";
    private var volumeMaxSound:String  = "assets/sounds/soundtray/VolMAX.ogg";

    // ── Estado ────────────────────────────────────────────────────────────────
    private var hideTimer:FlxTimer;
    private var currentTween:FlxTween;
    private var alphaTween:FlxTween;

    private var isShowing:Bool  = false;
    private var isMuted:Bool    = false;
    private var volumeBeforeMute:Float = 1.0;

    // Indica si la barra activa debe mostrarse (false solo cuando vol=0/muted).
    // Separado de volumeBar.alpha para que _setAlpha no confunda "oculto por fade"
    // con "oculto porque no hay volumen" — sin esto, tras un hide la barra no
    // volvía to aparecer in the primer press porque alpha=0 bloqueaba the fade-in.
    private var _barVisible:Bool = false;

    private static inline var SHOWN_Y:Float   = 10;
    private static inline var TWEEN_TIME:Float = 0.3;

    public function new()
    {
        super();

        // Registrar singleton ANTES de cualquier acceso externo
        SoundTray.instance = this;

        loadVolume();

        // ── FIX: desactivar teclas de volumen nativas de Flixel ───────────────
        // Sin esto, PLUS/MINUS lo procesa Flixel (+0.1) Y SoundTray (+0.1)
        // → the volumen sube 0.2 of golpe = 2 barras by pulsación.
        FlxG.sound.volumeUpKeys   = [];
        FlxG.sound.volumeDownKeys = [];
        FlxG.sound.muteKeys       = [];

        // ── Sprites ───────────────────────────────────────────────────────────
        volumeBox = new FlxSprite(0, 0);
        volumeBox.loadGraphic("assets/images/soundtray/volumebox.png");
        volumeBox.scale.set(0.6, 0.6);
        volumeBox.updateHitbox();
        volumeBox.screenCenter(X);
        volumeBox.scrollFactor.set(0, 0);

        volumeBarBg = new FlxSprite(0, 0);
        volumeBarBg.loadGraphic("assets/images/soundtray/bars_10.png");
        volumeBarBg.scale.set(0.6, 0.6);
        volumeBarBg.updateHitbox();
        volumeBarBg.scrollFactor.set(0, 0);
        volumeBarBg.alpha = 0.35;

        volumeBar = new FlxSprite(0, 0);
        volumeBar.loadGraphic("assets/images/soundtray/bars_10.png");
        volumeBar.scale.set(0.6, 0.6);
        volumeBar.updateHitbox();
        volumeBar.scrollFactor.set(0, 0);

        // Empezar oculto y transparente
        var hiddenY:Float = -(volumeBox.height + 20);
        volumeBox.y = hiddenY;
        _setAlpha(0);

        // ── critical: globalManager → sobrevive cambios of state ──────────────
        hideTimer = new FlxTimer(FlxTimer.globalManager);

        updateVolumeBar();

        // ── Crear/reusar el contenedor OpenFL persistente ─────────────────────
        if (_container == null)
            _container = new SoundTrayContainer();

        _container.attachSprites(volumeBox, volumeBarBg, volumeBar);
        _container.insert();
    }

    // ── Plugin lifecycle ──────────────────────────────────────────────────────
    // El update de los sprites lo hace SoundTrayContainer via preUpdate signal.
    // Here only manejamos input.

    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);
        // Input gestionado exclusivamente por VolumePlugin (conectado a
        // FlxG.signals.preUpdate). Handle the keys here and in VolumePlugin
        // provocaba dos calldas to volumeUp/Down by frame → the volumen subía/
        // bajaba 0.2 of golpe and after _roundVol it dejaba atascado in a
        // valor incorrecto. NO procesar input en este update.
    }

    // The render it handles SoundTrayContainer — nada that do here.
    override public function draw():Void {}

    // ── Mostrar / Ocultar ─────────────────────────────────────────────────────

    public function show():Void
    {
        if (currentTween != null) currentTween.cancel();
        if (alphaTween   != null) alphaTween.cancel();
        if (hideTimer    != null) hideTimer.cancel();

        // globalManager → el tween no se destruye al cambiar de state
        currentTween = FlxTween.globalManager.tween(volumeBox, {y: SHOWN_Y}, TWEEN_TIME,
            {ease: FlxEase.quartOut});

        alphaTween = FlxTween.globalManager.num(volumeBox.alpha, 1.0, TWEEN_TIME,
            {ease: FlxEase.quartOut}, function(v) { _setAlpha(v); });

        isShowing = true;

        hideTimer.start(1.5, function(_) { hide(); });
    }

    public function hide():Void
    {
        if (currentTween != null) currentTween.cancel();
        if (alphaTween   != null) alphaTween.cancel();
        if (hideTimer    != null) hideTimer.cancel();

        var hiddenY:Float = -(volumeBox.height + 20);

        currentTween = FlxTween.globalManager.tween(volumeBox, {y: hiddenY}, TWEEN_TIME,
            {ease: FlxEase.quartIn});

        alphaTween = FlxTween.globalManager.num(volumeBox.alpha, 0.0, TWEEN_TIME,
            {ease: FlxEase.quartIn}, function(v) { _setAlpha(v); });

        isShowing = false;
    }

    public function forceHide():Void
    {
        if (currentTween != null) currentTween.cancel();
        if (alphaTween   != null) alphaTween.cancel();
        if (hideTimer    != null) hideTimer.cancel();

        var hiddenY:Float = -(volumeBox.height + 20);
        volumeBox.y = hiddenY;
        _setAlpha(0);

        isShowing = false;
    }

    // ── Control de volumen ────────────────────────────────────────────────────

    public function volumeUp():Void
    {
        // Desmutar si estaba muteado — delegamos a CoreAudio para que el
        // masterVolume quede en sync y CoreAudio.update() no lo deshaga.
        if (isMuted) { isMuted = false; funkin.audio.CoreAudio.setMuted(false); }

        var v = _roundVol(funkin.audio.CoreAudio.masterVolume + 0.1);
        if (v >= 1.0) { v = 1.0; FlxG.sound.play(volumeMaxSound); }
        else            FlxG.sound.play(volumeUpSound);

        // Usar CoreAudio como fuente de verdad para que su update() no
        // sobreescriba el valor que acabamos de poner.
        funkin.audio.CoreAudio.setMasterVolume(v);
        saveVolume();
        updateVolumeBar();
        show();
    }

    public function volumeDown():Void
    {
        if (isMuted) { isMuted = false; funkin.audio.CoreAudio.setMuted(false); }

        var v = _roundVol(funkin.audio.CoreAudio.masterVolume - 0.1);
        if (v < 0.0) v = 0.0;

        FlxG.sound.play(volumeDownSound);
        funkin.audio.CoreAudio.setMasterVolume(v);

        // Sincronizar isMuted con el auto-mute que puede haber activado
        // setMasterVolume(0) → sin esto, isMuted queda false aunque muted=true
        // y el siguiente toggle del 0 no funciona bien.
        if (v <= 0) { isMuted = true; volumeBeforeMute = 0.5; }

        saveVolume();
        updateVolumeBar();
        show();
    }

    public function toggleMute():Void
    {
        if (isMuted)
        {
            isMuted = false;
            final restoreVol:Float = (volumeBeforeMute > 0) ? volumeBeforeMute : 0.5;
            funkin.audio.CoreAudio.setMuted(false);
            funkin.audio.CoreAudio.setMasterVolume(restoreVol);
            FlxG.sound.play(volumeUpSound);
        }
        else
        {
            isMuted = true;
            volumeBeforeMute = (funkin.audio.CoreAudio.masterVolume > 0)
                ? funkin.audio.CoreAudio.masterVolume : 0.5;
            FlxG.sound.play(volumeDownSound);
            funkin.audio.CoreAudio.setMuted(true);
        }

        updateVolumeBar();
        saveVolume();
        show();
    }

    // ── Helpers internos ──────────────────────────────────────────────────────

    private inline function _setAlpha(a:Float):Void
    {
        volumeBox.alpha   = a;
        volumeBarBg.alpha = a * 0.35;
        volumeBar.alpha   = _barVisible ? a : 0;
    }

    private inline function _roundVol(v:Float):Float
        return Math.round(v * 10) / 10;

    private function syncBarsToBox():Void
    {
        volumeBarBg.x = volumeBox.x + (volumeBox.width  - volumeBarBg.width)  / 2;
        volumeBarBg.y = volumeBox.y + (volumeBox.height - volumeBarBg.height) / 2 - 20;
        volumeBar.x   = volumeBarBg.x;
        volumeBar.y   = volumeBarBg.y;
    }

    private function updateVolumeBar():Void
    {
        // Leer masterVolume de CoreAudio, no FlxG.sound.volume — CoreAudio.update()
        // puede be still sincronizando FlxG.sound.volume in the same frame.
        var barLevel:Int = isMuted ? 0 : Math.round(funkin.audio.CoreAudio.masterVolume * 10);
        barLevel = Std.int(Math.max(0, Math.min(10, barLevel)));

        if (barLevel == 0)
        {
            _barVisible = false;
            volumeBar.alpha = 0;
        }
        else
        {
            _barVisible = true;
            volumeBar.loadGraphic("assets/images/soundtray/bars_" + barLevel + ".png");
            volumeBar.scale.set(0.6, 0.6);
            volumeBar.updateHitbox();
            volumeBar.alpha = volumeBox.alpha;
        }

        syncBarsToBox();
    }

    // _forceVolumeSync() eliminado: ya no es necesario.
    // CoreAudio.setMasterVolume() / CoreAudio.setMuted() sincronizan
    // FlxG.sound.volume en todos los sounds directamente.

    private function saveVolume():Void
    {
        // Guardar siempre el volumen REAL (masterVolume de CoreAudio, no FlxG.sound.volume
        // that puede be 0 if is muteado) for that the unmute restaure correctly.
        FlxG.save.data.volume = isMuted ? volumeBeforeMute : funkin.audio.CoreAudio.masterVolume;
        FlxG.save.data.muted  = isMuted;
        FlxG.save.flush();
    }

    private function loadVolume():Void
    {
        // Cargar desde CoreAudio en lugar de leer FlxG.save directamente —
        // CoreAudio.loadVolume() already habrá corrido before (from initialize())
        // y tiene el valor correcto en masterVolume.
        // Solo inicializamos isMuted/volumeBeforeMute localmente.
        if (FlxG.save.data.muted != null)
        {
            isMuted = FlxG.save.data.muted;
            if (isMuted)
            {
                final savedVol:Float = (FlxG.save.data.volume != null) ? FlxG.save.data.volume : 1.0;
                volumeBeforeMute = (savedVol > 0) ? savedVol : 0.5;
            }
        }
        // No tocar FlxG.sound.volume here — CoreAudio it manages.
    }

    override public function destroy():Void
    {
        if (SoundTray.instance == this)
            SoundTray.instance = null;
        super.destroy();
    }
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * SoundTrayContainer — OpenFL Sprite persistente entre cambios de state.
 *
 * La clave: la FlxCamera es addChild() del Sprite (igual que StickerTransitionContainer),
 * is not in FlxG.cameras.list. Flixel only destroys cameras that are in
 * esa lista cuando cambia de state → la nuestra sobrevive siempre.
 *
 * Z-index 99999 → por encima de stickers (9999) y de cualquier state.
 */
@:access(flixel.FlxCamera)
class SoundTrayContainer extends openfl.display.Sprite
{
    private var trayCamera:FlxCamera;

    private var sprBox:FlxSprite;
    private var sprBg:FlxSprite;
    private var sprBar:FlxSprite;

    private var _updateConnected:Bool = false;

    public function new():Void
    {
        super();
        visible = false;

        trayCamera = new FlxCamera();
        trayCamera.bgColor = 0x00000000;
        addChild(trayCamera.flashSprite);

        FlxG.signals.gameResized.add((_, _) -> onResize());
        scrollRect = new openfl.geom.Rectangle();
        onResize();
    }

    /** Asigna the tres sprites of the tray and the apunta to nuestra camera. */
    public function attachSprites(box:FlxSprite, bg:FlxSprite, bar:FlxSprite):Void
    {
        sprBox = box;
        sprBg  = bg;
        sprBar = bar;

        sprBox.cameras = [trayCamera];
        sprBg.cameras  = [trayCamera];
        sprBar.cameras = [trayCamera];
    }

    /**
     * Inserta el container en OpenFL por encima de todo.
     * Usa remove() antes de add() para evitar conectar el signal dos veces.
     */
    public function insert():Void
    {
        // Z 99999 → encima de stickers (9999) y de cualquier otra capa
        FlxG.addChildBelowMouse(this, 99999);
        visible = true;
        onResize();

        if (!_updateConnected)
        {
            FlxG.signals.preUpdate.add(_manualUpdate);
            _updateConnected = true;
        }
    }

    // ── Update manual (via signal → sobrevive state switch) ───────────────────

    private function _manualUpdate():Void
    {
        if (!visible || sprBox == null) return;

        var elapsed = FlxG.elapsed;

        // Sincronizar barras to the position of the box (the tween moves box.and)
        _syncBars();

        sprBox.update(elapsed);
        sprBg.update(elapsed);
        sprBar.update(elapsed);

        trayCamera.update(elapsed);
        trayCamera.clearDrawStack();
        trayCamera.canvas.graphics.clear();

        sprBox.draw();
        sprBg.draw();
        sprBar.draw();

        trayCamera.render();
    }

    private function _syncBars():Void
    {
        if (sprBox == null || sprBg == null || sprBar == null) return;
        sprBg.x  = sprBox.x + (sprBox.width  - sprBg.width)  / 2;
        sprBg.y  = sprBox.y + (sprBox.height - sprBg.height) / 2 - 20;
        sprBar.x = sprBg.x;
        sprBar.y = sprBg.y;
    }

    // ── Resize ────────────────────────────────────────────────────────────────

    public function onResize():Void
    {
        x = y = 0;
        scaleX = scaleY = 1;

        __scrollRect.setTo(
            0, 0,
            FlxG.camera._scrollRect.scrollRect.width,
            FlxG.camera._scrollRect.scrollRect.height
        );

        trayCamera.onResize();
        trayCamera._scrollRect.scrollRect = scrollRect;
    }
}
