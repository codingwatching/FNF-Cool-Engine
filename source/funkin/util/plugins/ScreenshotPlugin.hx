package funkin.util.plugins;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import openfl.display.Bitmap;
import openfl.display.Sprite;
import openfl.display.BitmapData;
import openfl.display.PNGEncoderOptions;
import funkin.states.MusicBeatState;
import openfl.utils.ByteArray;
import openfl.events.MouseEvent;

/**
 * ScreenshotPlugin — Capturas de pantalla al estilo V-Slice.
 *
 * ─── Uso ───────────────────────────────────────────────────────────────────
 *  • Pulsa F12 para capturar la pantalla.
 *  • Aparece un flash blanco + sonido de confirmación.
 *  • Una miniatura de la captura aparece en la esquina inferior-derecha
 *    durante ~1.5 s y se puede clicar para abrir la carpeta de capturas.
 *  • Las capturas se guardan en screenshots/ como PNG con timestamp.
 *
 * ─── Integración ───────────────────────────────────────────────────────────
 *  Llama a ScreenshotPlugin.initialize() en Main.setupGame(), después de
 *  createGame() (necesita FlxG disponible). Ejemplo:
 *
 *      funkin.util.plugins.ScreenshotPlugin.initialize();
 *
 * ─── Sonido ────────────────────────────────────────────────────────────────
 *  Coloca assets/sounds/screenshot.ogg (o .mp3) para el sonido de captura.
 *  Si el archivo no existe, simplemente no se reproduce ningún sonido.
 */
class ScreenshotPlugin extends FlxBasic
{
    // ── Singleton ─────────────────────────────────────────────────────────────
    public static var instance(default, null):Null<ScreenshotPlugin> = null;

    // ── Ruta de capturas ──────────────────────────────────────────────────────
    public static final SCREENSHOT_FOLDER:String = 'screenshots';

    // ── Tiempos de animación (segundos) ───────────────────────────────────────
    static final FLASH_FADE_DURATION:Float       = 0.20;
    static final PREVIEW_INITIAL_DELAY:Float     = 0.25;
    static final PREVIEW_FADE_IN_DURATION:Float  = 0.30;
    static final PREVIEW_FADE_OUT_DELAY:Float    = 1.25;
    static final PREVIEW_FADE_OUT_DURATION:Float = 0.30;
    static final PREVIEW_MARGIN:Int              = 12;

    // ── Objetos OpenFL ────────────────────────────────────────────────────────

    /** Overlay blanco que parpadea al capturar. */
    var flashSprite:Sprite;
    var flashBitmap:Bitmap;

    /** Contenedor de la miniatura en esquina. */
    var previewSprite:Sprite;
    var shotPreviewBitmap:Bitmap;
    var outlineBitmap:Bitmap;

    // ── Estado ────────────────────────────────────────────────────────────────
    /** Frames desde que se pulsó F12 (necesitamos saltar 1 frame para capturar sin UI flash). */
    var screenshotTakenFrame:Int = 0;

    /** true mientras el state está cambiando → cancelar feedback visual. */
    var stateChanging:Bool = false;

    // ── Constructor ───────────────────────────────────────────────────────────

    public function new()
    {
        super();

        var w:Int = FlxG.width;
        var h:Int = FlxG.height;

        // ── Flash overlay ──────────────────────────────────────────────────────
        flashSprite = new Sprite();
        flashSprite.mouseEnabled = false;
        flashSprite.alpha = 0;
        flashBitmap = new Bitmap(new BitmapData(w, h, true, FlxColor.WHITE));
        flashSprite.addChild(flashBitmap);

        // ── Preview (miniatura) ────────────────────────────────────────────────
        previewSprite = new Sprite();
        previewSprite.alpha = 0;

        // Borde blanco de 5 px alrededor de la miniatura
        outlineBitmap = new Bitmap(new BitmapData(
            Std.int(w / 5) + 10,
            Std.int(h / 5) + 10,
            true,
            0xFFFFFFFF
        ));
        previewSprite.addChild(outlineBitmap);

        shotPreviewBitmap = new Bitmap();
        previewSprite.addChild(shotPreviewBitmap);

        _positionPreview();

        FlxG.stage.addChild(flashSprite);

        // ── Señales ────────────────────────────────────────────────────────────
        FlxG.signals.gameResized.add(_onResize);
        FlxG.signals.preStateSwitch.add(_onPreStateSwitch);
        FlxG.signals.postStateSwitch.add(_onPostStateSwitch);

        trace('[ScreenshotPlugin] Listo. Pulsa F12 para capturar la pantalla.');
    }

    // ── Inicialización pública ────────────────────────────────────────────────

    /**
     * Inicializa el plugin. Llama UNA SOLA VEZ desde Main.setupGame()
     * después de createGame().
     */
    public static function initialize():Void
    {
        if (instance != null) return;
        instance = new ScreenshotPlugin();
        FlxG.plugins.addPlugin(instance);
    }

    // ── Update ────────────────────────────────────────────────────────────────

    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);

        var justPressedScreenshot:Bool = false;

        if (FlxG.state is MusicBeatState) 
        {
            var curState = cast(FlxG.state, MusicBeatState);
            
            // Usamos @:privateAccess para leer 'controls' aunque sea privado
            @:privateAccess {
                if (curState.controls != null)
                    justPressedScreenshot = curState.controls.SCREENSHOT;
            }
        }
        
        // También dejamos el F12 por si acaso
        if (FlxG.keys.justPressed.F12) justPressedScreenshot = true;

        // Esperamos un frame extra tras la pulsación para que el flash
        // haya desaparecido antes de leer los pixels de la pantalla.
        if (justPressedScreenshot && screenshotTakenFrame == 0)
        {
            // Quitar preview anterior antes de capturar
            FlxG.stage.removeChild(previewSprite);
            screenshotTakenFrame++;
        }
        else if (screenshotTakenFrame > 1)
        {
            screenshotTakenFrame = 0;
            capture();
        }
        else if (screenshotTakenFrame > 0)
        {
            screenshotTakenFrame++;
        }
    }

    // ── Captura ───────────────────────────────────────────────────────────────

    /** Captura la pantalla, la guarda y muestra el feedback visual. */
    public function capture():Void
    {
        var shot:Bitmap = new Bitmap(BitmapData.fromImage(FlxG.stage.window.readPixels()));
        _saveScreenshot(shot);
        _showFlash();
        _showPreview(shot);
    }

    // ── Flash ─────────────────────────────────────────────────────────────────

    function _showFlash():Void
    {
        if (stateChanging) return;

        // Sonido de captura (opcional — no falla si el archivo no existe)
        try { FlxG.sound.play(Paths.sound('screenshot'), 1.0); } catch (_:Dynamic) {}

        FlxTween.cancelTweensOf(flashSprite);
        flashSprite.alpha = 1;
        FlxTween.tween(flashSprite, {alpha: 0}, FLASH_FADE_DURATION);
    }

    // ── Preview ───────────────────────────────────────────────────────────────

    function _showPreview(shot:Bitmap):Void
    {
        if (stateChanging) return;

        // Rellenar miniatura
        shotPreviewBitmap.bitmapData = shot.bitmapData;
        shotPreviewBitmap.x = outlineBitmap.x + 5;
        shotPreviewBitmap.y = outlineBitmap.y + 5;
        shotPreviewBitmap.width  = outlineBitmap.width  - 10;
        shotPreviewBitmap.height = outlineBitmap.height - 10;

        FlxG.stage.removeChild(previewSprite);
        _positionPreview();

        var targetAlpha:Float  = 1.0;
        var changingAlpha:Bool = false;

        // Interactividad: hover dimming + clic para abrir carpeta
        previewSprite.buttonMode = true;

        var onDown  = function(e:MouseEvent) { _onPreviewClick(e); };
        var onOver  = function(e:MouseEvent) { if (!changingAlpha) previewSprite.alpha = 0.6; targetAlpha = 0.6; };
        var onOut   = function(e:MouseEvent) { if (!changingAlpha) previewSprite.alpha = 1.0; targetAlpha = 1.0; };

        previewSprite.addEventListener(MouseEvent.MOUSE_DOWN, onDown);
        previewSprite.addEventListener(MouseEvent.MOUSE_OVER, onOver);
        previewSprite.addEventListener(MouseEvent.MOUSE_OUT,  onOut);

        // Posición inicial: ligeramente por debajo para el slide-up
        previewSprite.y += 10;
        FlxG.stage.addChild(previewSprite);
        previewSprite.alpha = 0;

        FlxTween.cancelTweensOf(previewSprite);

        new FlxTimer().start(PREVIEW_INITIAL_DELAY, function(_)
        {
            changingAlpha = true;
            FlxTween.tween(previewSprite, {alpha: targetAlpha, y: previewSprite.y - 10},
                PREVIEW_FADE_IN_DURATION,
            {
                ease: FlxEase.quartOut,
                onComplete: function(_)
                {
                    changingAlpha = false;

                    new FlxTimer().start(PREVIEW_FADE_OUT_DELAY, function(_)
                    {
                        changingAlpha = true;
                        FlxTween.tween(previewSprite, {alpha: 0, y: previewSprite.y + 10},
                            PREVIEW_FADE_OUT_DURATION,
                        {
                            ease: FlxEase.quartInOut,
                            onComplete: function(_)
                            {
                                changingAlpha = false;
                                previewSprite.removeEventListener(MouseEvent.MOUSE_DOWN, onDown);
                                previewSprite.removeEventListener(MouseEvent.MOUSE_OVER, onOver);
                                previewSprite.removeEventListener(MouseEvent.MOUSE_OUT,  onOut);
                                FlxG.stage.removeChild(previewSprite);
                            }
                        });
                    });
                }
            });
        });
    }

    function _onPreviewClick(e:MouseEvent):Void
    {
        if (previewSprite.alpha <= 0.01) return;
        _openScreenshotsFolder();
    }

    /** Coloca el previewSprite en la esquina inferior-derecha. */
    function _positionPreview():Void
    {
        var pw:Int = Std.int(FlxG.width  / 5) + 10;
        var ph:Int = Std.int(FlxG.height / 5) + 10;
        previewSprite.x = FlxG.stage.stageWidth  - pw - PREVIEW_MARGIN;
        previewSprite.y = FlxG.stage.stageHeight - ph - PREVIEW_MARGIN;
    }

    // ── Guardado ──────────────────────────────────────────────────────────────

    function _saveScreenshot(bitmap:Bitmap):Void
    {
        #if sys
        try
        {
            if (!sys.FileSystem.exists(SCREENSHOT_FOLDER))
                sys.FileSystem.createDirectory(SCREENSHOT_FOLDER);

            var ts:String   = _timestamp();
            var base:String = 'screenshot-$ts';
            var path:String = '$SCREENSHOT_FOLDER/$base.png';

            // Evitar sobreescribir si existe (raro, pero puede pasar al spamear)
            var copy:Int = 2;
            while (sys.FileSystem.exists(path))
            {
                path = '$SCREENSHOT_FOLDER/$base ($copy).png';
                copy++;
            }

            var encoder:PNGEncoderOptions = new PNGEncoderOptions();
            var bytes:ByteArray = bitmap.bitmapData.encode(bitmap.bitmapData.rect, encoder);
            sys.io.File.saveBytes(path, bytes);

            trace('[ScreenshotPlugin] Guardado: $path');
        }
        catch (e:Dynamic)
        {
            trace('[ScreenshotPlugin] Error al guardar la captura: $e');
        }
        #end
    }

    /** Devuelve un string con formato YYYY-MM-DD_HH-MM-SS. */
    function _timestamp():String
    {
        var d  = Date.now();
        return '${d.getFullYear()}-${_p(d.getMonth()+1)}-${_p(d.getDate())}'
             + '_${_p(d.getHours())}-${_p(d.getMinutes())}-${_p(d.getSeconds())}';
    }

    private inline function _p(n:Int):String
        return n < 10 ? '0$n' : '$n';

    function _openScreenshotsFolder():Void
    {
        #if sys
        var absPath:String = sys.FileSystem.absolutePath(SCREENSHOT_FOLDER);
        #if windows
        Sys.command('explorer', [absPath]);
        #elseif mac
        Sys.command('open', [absPath]);
        #elseif linux
        Sys.command('xdg-open', [absPath]);
        #end
        #end
    }

    // ── Resize ────────────────────────────────────────────────────────────────

    function _onResize(w:Int, h:Int):Void
    {
        flashBitmap.bitmapData = new BitmapData(w, h, true, FlxColor.WHITE);
        outlineBitmap.bitmapData = new BitmapData(
            Std.int(w / 5) + 10,
            Std.int(h / 5) + 10,
            true,
            0xFFFFFFFF
        );
        _positionPreview();
    }

    // ── State switch ──────────────────────────────────────────────────────────

    function _onPreStateSwitch():Void
    {
        stateChanging = true;
        FlxTween.cancelTweensOf(flashSprite);
        FlxTween.cancelTweensOf(previewSprite);
        flashSprite.alpha   = 0;
        previewSprite.alpha = 0;
        if (previewSprite.parent != null) FlxG.stage.removeChild(previewSprite);
    }

    function _onPostStateSwitch():Void
    {
        stateChanging = false;
    }

    // ── Destroy ───────────────────────────────────────────────────────────────

    override public function destroy():Void
    {
        if (instance == this) instance = null;

        FlxG.signals.gameResized.remove(_onResize);
        FlxG.signals.preStateSwitch.remove(_onPreStateSwitch);
        FlxG.signals.postStateSwitch.remove(_onPostStateSwitch);

        if (flashSprite.parent   != null) FlxG.stage.removeChild(flashSprite);
        if (previewSprite.parent != null) FlxG.stage.removeChild(previewSprite);

        super.destroy();
    }
}
