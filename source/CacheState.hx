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
import funkin.scripting.ScriptHandler;

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

    // En Android procesar 1 asset por frame para no bloquear el hilo principal.
    // Cargar 8 a la vez (comportamiento desktop) congela el render loop en móvil
    // porque cada getGraphic/getSound es síncrono y los assets pesados (UI/alphabet)
    // pueden tardar >100ms, disparando el watchdog ANR del sistema.
    #if (android || mobileC)
    static inline final ASSETS_PER_FRAME:Int = 1;
    #else
    static inline final ASSETS_PER_FRAME:Int = 8;
    #end

    override function create()
    {
        // NOTA: PathsCache.beginSession() es llamado automáticamente por la señal
        // preStateSwitch en FunkinCache.init(). No llamarlo aquí para evitar doble
        // beginSession() que causaría que los assets del state anterior queden huérfanos.

        funkin.system.CursorManager.hide();

        // ── Estas llamadas YA ocurrieron en Main.initializeGameSystems() ────
        // Highscore.load()          → ya llamado en initializeSaveSystem()
        // KeyBinds.keyCheck()       → ya llamado en initializeGameSystems()
        // PlayerSettings.init()     → ya llamado en initializeGameSystems()
        // Llamarlas de nuevo recrea objetos estáticos y re-lee disco sin necesidad,
        // contribuyendo al RSS elevado al arrancar.
        // ─────────────────────────────────────────────────────────────────────

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

        // ── Scripts globales ────────────────────────────────────────────────
        // FIX (Android): ScriptHandler.loadGlobalScripts() usaba Sys.programPath()
        // + FileSystem.readDirectory() síncrono, lo que en Android puede tardar
        // varios segundos bloqueando el hilo GL y congelando la barra en ~7%.
        // Solución: se registra como un paso más de la cadena de carga (tipo SCRIPTS),
        // de modo que el render loop tiene garantizado al menos 1 frame renderizado
        // antes de ejecutarlo. El comportamiento lógico es idéntico al anterior:
        // los scripts quedan listos antes de entrar a TitleState.
        assetsToCache.push({ type: SCRIPTS, path: '' });

        totalAssets = assetsToCache.length;
        super.create();
    }

    /**
     * Solo cargamos lo que el juego necesita ANTES de llegar al TitleState.
     * Todo lo demás (stages, personajes, canciones) se carga on-demand.
     */
    function buildEssentialList():Void
    {
        #if (!android && !mobileC && !ios)
        final sounds:Array<String> = [
            "menus/confirmMenu", "menus/cancelMenu", "menus/scrollMenu",
            "intro3", "intro2", "intro1", "introGo",
            "soundtray/Volup", "soundtray/Voldown", "soundtray/VolMAX"
        ];
        for (s in sounds)
            assetsToCache.push({ type: SOUND, path: s });
        #end

        #if (!android && !mobileC && !ios)
        final images:Array<String> = [
            "UI/alphabet",
            "soundtray/volumebox",
            "menu/cursor/cursor-default"
        ];
        for (i in images)
            assetsToCache.push({ type: IMAGE, path: i });
        #end
    }

    override function update(elapsed:Float)
    {
        super.update(elapsed);

        if (loadingComplete) return;

        // Procesar hasta ASSETS_PER_FRAME assets por frame
        var processed = 0;
        while (processed < ASSETS_PER_FRAME && currentAssetIndex < totalAssets)
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

                case SCRIPTS:
                    // FIX (Android): ejecutado aquí, después de que el render loop
                    // ya pintó al menos un frame, evitando el freeze en ~7%.
                    // Rescannear global scripts garantiza que los menús del mod activo
                    // (TitleState, MainMenu, FreeplayState…) ya tengan sus hooks.
                    ScriptHandler.loadGlobalScripts();
            }
        }
        catch (_:Dynamic) {}
    }

    function completeLoading():Void
    {
        loadingComplete = true;
        loadingText.text = "Ready!";
        loadingPercentage.text = "100%";

        #if (android || mobileC || ios)
        // En móvil: 2 frames de margen antes del GC para que el driver GL vacíe la cola.
        new FlxTimer().start(0.016, function(_)
        {
            new FlxTimer().start(0.016, function(_)
            {
                funkin.system.MemoryUtil.collectMajor();
                new FlxTimer().start(0.3, function(_)
                {
                    new FlxTimer().start(0.3, function(_) { goToTitle(); });
                });
            });
        });
        #else
        new FlxTimer().start(0.016, function(_)
        {
            funkin.system.MemoryUtil.collectMajor();
            new FlxTimer().start(0.3, function(_)
            {
                try { FlxG.sound.play(Paths.sound('menus/cacheLoaded'), 0.7); }
                catch (_:Dynamic) {}
                new FlxTimer().start(0.3, function(_) { goToTitle(); });
            });
        });
        #end
    }

    function goToTitle():Void
    {
        #if (!mobileC && !android && !ios)
        FlxG.autoPause = false;
        #else
        FlxG.autoPause = true;
        #end

        // Aplicar FPS guardado
        funkin.data.EngineSettings.applyFPS();

        #if (!mobileC && !android && !ios)
        funkin.data.EngineSettings.ensureWindowSize();
        #end

        ShaderManager.init();

        LoadingState.loadAndSwitchState(new TitleState(), true);
        FlxG.camera.fade(FlxColor.BLACK, 0.8, false);
    }
}

typedef AssetInfo = { var type:AssetType; var path:String; }

enum AssetType { SOUND; IMAGE; SCRIPTS; }