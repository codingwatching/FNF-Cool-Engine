package;

import flixel.util.FlxTimer;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.data.KeyBinds;
import funkin.menus.TitleState;
import funkin.gameplay.objects.hud.Highscore;
import data.PlayerSettings;
import funkin.states.LoadingState;
import funkin.graphics.shaders.ShaderManager;

using StringTools;

import Paths;

class CacheState extends funkin.states.MusicBeatState
{
    var loadingBar:FlxSprite;
    var loadingText:FlxText;
    var loadingPercentage:FlxText;

    var assetsToCache:Array<AssetInfo> = [];
    var currentAssetIndex:Int = 0;
    var totalAssets:Int = 0;

    var loadingComplete:Bool = false;
    var barMaxWidth:Float = 0;

    override function create()
    {
        // NOTA: PathsCache.beginSession() es llamado automáticamente por la señal
        // preStateSwitch en FunkinCache.init(). No llamarlo aquí para evitar doble
        // beginSession() que causaría que los assets del state anterior queden huérfanos.

        funkin.system.CursorManager.hide();

        Highscore.load();
        KeyBinds.keyCheck();
        PlayerSettings.init();
        PlayerSettings.player1.controls.loadKeyBinds();

        // FIX: 'FPSCap' es un campo obsoleto — el engine ya usa 'fpsTarget'.
        // CacheState no debe sobreescribir el framerate que Main.initializeFramerate()
        // configuró correctamente (60fps en Android, 120fps en desktop).
        // El bloque anterior ponía 240fps por defecto cuando FPSCap era null.

        // ── UI ─────────────────────────────────────────────────────────────
        var barBG:FlxSprite = new FlxSprite(0, 500).makeGraphic(FlxG.width - 100, 40, 0xFF333333);
        barBG.screenCenter(X);
        add(barBG);

        barMaxWidth = FlxG.width - 110;

        loadingBar = new FlxSprite(barBG.x + 5, barBG.y + 5).makeGraphic(10, 30, FlxColor.LIME);
        add(loadingBar);

        loadingText = new FlxText(0, 450, FlxG.width, "Loading...");
        loadingText.setFormat(Paths.font("Funkin.otf"), 28, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
        add(loadingText);

        loadingPercentage = new FlxText(0, 550, FlxG.width, "0%");
        loadingPercentage.setFormat(Paths.font("Funkin.otf"), 24, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
        add(loadingPercentage);

        // ── Lista mínima de assets esenciales ──────────────────────────────
        buildEssentialList();

        totalAssets = assetsToCache.length;
        super.create();
    }

    /**
     * Solo cargamos lo que el juego necesita ANTES de llegar al TitleState.
     * Todo lo demás (stages, personajes, canciones) se carga on-demand.
     */
    function buildEssentialList():Void
    {
        // Sonidos de UI — se usan en TODOS los menús
        final sounds:Array<String> = [
            "menus/confirmMenu", "menus/cancelMenu", "menus/scrollMenu",
            "intro3", "intro2", "intro1", "introGo",
            "soundtray/Volup", "soundtray/Voldown", "soundtray/VolMAX"
        ];
        for (s in sounds)
            assetsToCache.push({ type: SOUND, path: s });

        // Imágenes de UI esenciales
        // Nota: soundtray/bars_* se excluyen del preload intencionalmente —
        // cargamos lazy en el primer uso del SoundTray. Como SoundTray es un
        // plugin persistente, sus FlxSprites mantienen useCount > 0 y FunkinCache
        // los rescata en cada clearSecondLayer() sin necesidad de marcarlos permanentes.
        // Eliminarlos aquí ahorra ~10 texturas cargadas durante el arranque.
        final images:Array<String> = [
            "UI/alphabet",
            "soundtray/volumebox",
            "menu/cursor/cursor-default"
        ];
        for (i in images)
            assetsToCache.push({ type: IMAGE, path: i });
    }

    override function update(elapsed:Float)
    {
        super.update(elapsed);

        if (loadingComplete) return;

        // Procesar hasta 8 assets por frame (lista corta → termina rápido)
        var processed = 0;
        while (processed < 8 && currentAssetIndex < totalAssets)
        {
            cacheAsset(assetsToCache[currentAssetIndex]);
            currentAssetIndex++;
            processed++;
        }

        // Actualizar UI con scaleX en lugar de makeGraphic() (0 alloc)
        final pct:Float = totalAssets > 0 ? currentAssetIndex / totalAssets : 1.0;
        final targetW = barMaxWidth * pct;
        loadingBar.scale.x = targetW / 10; // 10 es el ancho base del makeGraphic inicial
        loadingBar.updateHitbox();
        loadingPercentage.text = Math.floor(pct * 100) + "%";

        if (currentAssetIndex >= totalAssets)
            completeLoading();
    }

    function cacheAsset(asset:AssetInfo):Void
    {
        try
        {
            switch (asset.type)
            {
                case SOUND:
                    final path = Paths.sound(asset.path);
                    final snd = Paths.getSound(path);
                    if (snd != null)
                        Paths.cache.addExclusion(path);

                case IMAGE:
                    final path = Paths.image(asset.path);
                    final g = Paths.getGraphic(asset.path);
                    if (g != null)
                        Paths.cache.addExclusion(path);
            }
        }
        catch (_:Dynamic) {}
    }

    function completeLoading():Void
    {
        loadingComplete = true;
        loadingText.text = "Ready!";
        loadingPercentage.text = "100%";

        new FlxTimer().start(0.4, function(_)
        {
            try { FlxG.sound.play(Paths.sound('menus/cacheLoaded'), 0.7); }
            catch (_:Dynamic) {}

            new FlxTimer().start(0.3, function(_) { goToTitle(); });
        });
    }

    function goToTitle():Void
    {
        // FIX (música al minimizar): autoPause = false
        FlxG.autoPause = false;

        // Aplicar FPS guardado
        funkin.data.EngineSettings.applyFPS();

        // FIX (ventana pequeña): forzar tamaño 1080p
        funkin.data.EngineSettings.ensureWindowSize();

        // ── Shaders ────────────────────────────────────────────────────────
        // init() lee FlxG.save.data.shadersEnabled, crea los shaders y se
        // engancha a postStateSwitch para re-aplicarse en cada estado
        // automáticamente. Solo necesitas esta línea — no más setup en otros states.
        ShaderManager.init();
        ShaderManager.applyMenuPreset();

        LoadingState.loadAndSwitchState(new TitleState(), true);
        FlxG.camera.fade(FlxColor.BLACK, 0.8, false);
    }
}

typedef AssetInfo = { var type:AssetType; var path:String; }

enum AssetType { SOUND; IMAGE; }
