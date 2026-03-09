// phillyStreets.hx — Cool Engine stage script
// Reescrito desde V-Slice. Usa ShaderManager en lugar de RuntimeRainShader.
//
// SETUP:
//   Coloca rain.frag en:  assets/shaders/rain.frag
//                     o:  mods/<tu-mod>/shaders/rain.frag
//
// HOOKS disponibles en Cool Engine (se llaman directamente por nombre de función):
//   onStageCreate()           — equivale a onCreate / buildStage
//   onUpdate(elapsed:Float)   — cada frame
//   onBeatHit(beat:Int)       — cada beat
//   onDestroy()               — al salir
//   onGameOver()              — al morir
//   onRestart()               — al reiniciar (F5 / death retry)
//   onPause()                 — al pausar
//   onResume()                — al despausar
//
// Variables inyectadas automáticamente:
//   camGame, camHUD, camCountdown — cámaras
//   ShaderManager                 — API de shaders
//   FlxG, FlxTween, FlxEase, FlxMath, FlxPoint, FlxTimer
//   Conductor, Paths, game (PlayState)
//   stage (Stage actual), SONG (chart actual)


// ─── Estado de lluvia ──────────────────────────────────────────────────────────

var rainShaderName:String = 'rain';   // nombre del archivo rain.frag (sin extensión)
var rainTime:Float = 0.0;

var rainStartIntensity:Float = 0.0;
var rainEndIntensity:Float   = 0.0;

// ─── Estado de semáforos / coches ─────────────────────────────────────────────

var lightsStop:Bool        = false;
var lastChange:Int         = 0;
var changeInterval:Int     = 8;
var carWaiting:Bool        = false;
var carInterruptable:Bool  = true;
var car2Interruptable:Bool = true;

// ─────────────────────────────────────────────────────────────────────────────

function onStageCreate():Void
{
    // ── Determinar intensidades de lluvia según canción ────────────────────
    var songId:String = (game != null && game.SONG != null) ? game.SONG.song.toLowerCase() : '';
    switch (songId)
    {
        case 'darnell':
            rainStartIntensity = 0.0;
            rainEndIntensity   = 0.1;
        case 'lit-up':
            rainStartIntensity = 0.1;
            rainEndIntensity   = 0.2;
        case '2hot':
            rainStartIntensity = 0.2;
            rainEndIntensity   = 0.4;
        default:
            rainStartIntensity = 0.0;
            rainEndIntensity   = 0.1;
    }

    // ── Limpiar caché del shader antes de aplicar ──────────────────────────
    // FIX: evita que ShaderManager cargue una versión vieja del shader que
    // tenía uniforms vec3 uRainColor → warnings uRainColorR/G/B → GLSL roto → negro.
    ShaderManager.clearShader(rainShaderName);

    // ── Cargar y aplicar shader a camGame ──────────────────────────────────
    // FIX: aplicar aquí y no en onUpdate. En el frame 0 de onUpdate, camGame
    // todavía no ha renderizado su canvas → bitmap vacío → pantalla negra.
    ShaderManager.applyShaderToCamera(rainShaderName, camGame);

    // ── Parámetros iniciales ───────────────────────────────────────────────
    ShaderManager.setShaderParam(rainShaderName, 'uScale',     FlxG.height / 200.0);
    ShaderManager.setShaderParam(rainShaderName, 'uIntensity', rainStartIntensity);
    ShaderManager.setShaderParam(rainShaderName, 'uTime',      0.0);
    ShaderManager.setShaderParam(rainShaderName, 'uScreenW',   FlxG.width  * 1.0);
    ShaderManager.setShaderParam(rainShaderName, 'uScreenH',   FlxG.height * 1.0);

    // ── Charco ────────────────────────────────────────────────────────────
    var puddleProp = stage != null ? stage.getElement('puddle') : null;
    if (puddleProp != null)
    {
        ShaderManager.setShaderParam(rainShaderName, 'uPuddleY',      puddleProp.y + 80.0);
        ShaderManager.setShaderParam(rainShaderName, 'uPuddleScaleY', 0.3);
    }
    else
    {
        ShaderManager.setShaderParam(rainShaderName, 'uPuddleY',      0.0);
        ShaderManager.setShaderParam(rainShaderName, 'uPuddleScaleY', 0.0);
    }

    // ── Inicializar semáforos y coches ─────────────────────────────────────
    resetCar(true, true);
    resetStageValues();
}

function onUpdate(elapsed:Float):Void
{
    // ── Actualizar lluvia ──────────────────────────────────────────────────
    rainTime += elapsed;

    var songLen:Float = (FlxG.sound.music != null) ? FlxG.sound.music.length : 1.0;
    var songPos:Float = (Conductor != null) ? Conductor.songPosition : 0.0;

    var intensity:Float = (songLen > 0)
        ? FlxMath.remapToRange(songPos, 0, songLen, rainStartIntensity, rainEndIntensity)
        : rainStartIntensity;

    ShaderManager.setShaderParam(rainShaderName, 'uTime',      rainTime);
    ShaderManager.setShaderParam(rainShaderName, 'uIntensity', intensity);
    // uScreenW/uScreenH pueden cambiar si la ventana se redimensiona
    ShaderManager.setShaderParam(rainShaderName, 'uScreenW', FlxG.width * 1.0);
    ShaderManager.setShaderParam(rainShaderName, 'uScreenH', FlxG.height * 1.0);

    // ── Sky scroll ────────────────────────────────────────────────────────
    var sky = stage != null ? stage.getElement('phillySkybox') : null;
    if (sky != null)
        sky.x -= elapsed * 22;
}

function onBeatHit(beat:Int):Void
{
    // ── Coches ────────────────────────────────────────────────────────────
    var phillyCars  = stage != null ? stage.getElement('phillyCars')  : null;
    var phillyCars2 = stage != null ? stage.getElement('phillyCars2') : null;

    if (FlxG.random.bool(10) && beat != (lastChange + changeInterval) && carInterruptable)
    {
        if (phillyCars != null)
        {
            if (!lightsStop)
                driveCar(phillyCars);
            else
                driveCarLights(phillyCars);
        }
    }

    if (FlxG.random.bool(10)
        && beat != (lastChange + changeInterval)
        && car2Interruptable
        && !lightsStop
        && phillyCars2 != null)
    {
        driveCarBack(phillyCars2);
    }

    if (beat == (lastChange + changeInterval))
        changeLights(beat);
}

function onGameOver():Void
{
    // Quitar lluvia para que no tape el game over screen
    clearFilters(camGame);
}

function onRestart():Void
{
    // Re-aplicar lluvia al reiniciar (clearFilters lo borró en onGameOver)
    ShaderManager.applyShaderToCamera(rainShaderName, camGame);
    ShaderManager.setShaderParam(rainShaderName, 'uScale',     FlxG.height / 200.0);
    ShaderManager.setShaderParam(rainShaderName, 'uIntensity', rainStartIntensity);
    ShaderManager.setShaderParam(rainShaderName, 'uTime',      rainTime);
                ShaderManager.setShaderParam(rainShaderName, 'uScreenW', FlxG.width * 1.0);
    ShaderManager.setShaderParam(rainShaderName, 'uScreenH', FlxG.height * 1.0);

    var puddleProp = stage != null ? stage.getElement('puddle') : null;
    if (puddleProp != null)
    {
        ShaderManager.setShaderParam(rainShaderName, 'uPuddleY',      puddleProp.y + 80.0);
        ShaderManager.setShaderParam(rainShaderName, 'uPuddleScaleY', 0.3);
    }

    resetCar(true, true);
    resetStageValues();
}

function onDestroy():Void
{
    var phillyCars  = stage != null ? stage.getElement('phillyCars')  : null;
    var phillyCars2 = stage != null ? stage.getElement('phillyCars2') : null;
    if (phillyCars  != null) FlxTween.cancelTweensOf(phillyCars);
    if (phillyCars2 != null) FlxTween.cancelTweensOf(phillyCars2);
}

// ─── Semáforos ────────────────────────────────────────────────────────────────

function changeLights(beat:Int):Void
{
    lastChange  = beat;
    lightsStop  = !lightsStop;

    var traffic = stage != null ? stage.getElement('phillyTraffic') : null;
    if (lightsStop)
    {
        if (traffic != null) traffic.animation.play('tored');
        changeInterval = 20;
    }
    else
    {
        if (traffic != null) traffic.animation.play('togreen');
        changeInterval = 30;
        if (carWaiting)
        {
            var phillyCars = stage != null ? stage.getElement('phillyCars') : null;
            if (phillyCars != null) finishCarLights(phillyCars);
        }
    }
}

function resetStageValues():Void
{
    lastChange     = 0;
    changeInterval = 8;
    lightsStop     = false;
    var traffic = stage != null ? stage.getElement('phillyTraffic') : null;
    if (traffic != null) traffic.animation.play('togreen');
}

// ─── Coches ───────────────────────────────────────────────────────────────────

function resetCar(left:Bool, right:Bool):Void
{
    if (left)
    {
        carWaiting      = false;
        carInterruptable = true;
        var cars = stage != null ? stage.getElement('phillyCars') : null;
        if (cars != null)
        {
            FlxTween.cancelTweensOf(cars);
            cars.x = 1200; cars.y = 818; cars.angle = 0;
        }
    }
    if (right)
    {
        car2Interruptable = true;
        var cars2 = stage != null ? stage.getElement('phillyCars2') : null;
        if (cars2 != null)
        {
            FlxTween.cancelTweensOf(cars2);
            cars2.x = 1200; cars2.y = 818; cars2.angle = 0;
        }
    }
}

function driveCar(sprite:FlxSprite):Void
{
    carInterruptable = false;
    FlxTween.cancelTweensOf(sprite);
    var variant:Int     = FlxG.random.int(1, 4);
    sprite.animation.play('car' + variant);
    var extraOffset = [0, 0];
    var duration:Float  = 2.0;
    switch (variant)
    {
        case 1: duration = FlxG.random.float(1.0, 1.7);
        case 2: extraOffset = [20, -15]; duration = FlxG.random.float(0.6, 1.2);
        case 3: extraOffset = [30,  50]; duration = FlxG.random.float(1.5, 2.5);
        case 4: extraOffset = [10,  60]; duration = FlxG.random.float(1.5, 2.5);
    }
    var offset = [306.6, 168.3];
    sprite.offset.set(extraOffset[0], extraOffset[1]);
    var path = [
        FlxPoint.get(1570 - offset[0],       1049 - offset[1] - 30),
        FlxPoint.get(2400 - offset[0],        980 - offset[1] - 50),
        FlxPoint.get(3102 - offset[0],       1187 - offset[1] + 40)
    ];
    FlxTween.angle(sprite, -8, 18, duration, null);
    FlxTween.quadPath(sprite, path, duration, true, {
        ease: null,
        onComplete: function(_) { carInterruptable = true; }
    });
}

function driveCarBack(sprite:FlxSprite):Void
{
    car2Interruptable = false;
    FlxTween.cancelTweensOf(sprite);
    var variant:Int    = FlxG.random.int(1, 4);
    sprite.animation.play('car' + variant);
    var extraOffset    = [0, 0];
    var duration:Float = 2.0;
    switch (variant)
    {
        case 1: duration = FlxG.random.float(1.0, 1.7);
        case 2: extraOffset = [20, -15]; duration = FlxG.random.float(0.6, 1.2);
        case 3: extraOffset = [30,  50]; duration = FlxG.random.float(1.5, 2.5);
        case 4: extraOffset = [10,  60]; duration = FlxG.random.float(1.5, 2.5);
    }
    var offset = [306.6, 168.3];
    sprite.offset.set(extraOffset[0], extraOffset[1]);
    var path = [
        FlxPoint.get(3102 - offset[0],       1127 - offset[1] + 60),
        FlxPoint.get(2400 - offset[0],        980 - offset[1] - 30),
        FlxPoint.get(1570 - offset[0],       1049 - offset[1] - 10)
    ];
    FlxTween.angle(sprite, 18, -8, duration, null);
    FlxTween.quadPath(sprite, path, duration, true, {
        ease: null,
        onComplete: function(_) { car2Interruptable = true; }
    });
}

function driveCarLights(sprite:FlxSprite):Void
{
    carInterruptable = false;
    FlxTween.cancelTweensOf(sprite);
    var variant:Int    = FlxG.random.int(1, 4);
    sprite.animation.play('car' + variant);
    var extraOffset    = [0, 0];
    var duration:Float = 2.0;
    switch (variant)
    {
        case 1: duration = FlxG.random.float(1.0, 1.7);
        case 2: extraOffset = [20, -15]; duration = FlxG.random.float(0.9, 1.5);
        case 3: extraOffset = [30,  50]; duration = FlxG.random.float(1.5, 2.5);
        case 4: extraOffset = [10,  60]; duration = FlxG.random.float(1.5, 2.5);
    }
    var offset = [306.6, 168.3];
    sprite.offset.set(extraOffset[0], extraOffset[1]);
    var path = [
        FlxPoint.get(1500 - offset[0] - 20,  1049 - offset[1] - 20),
        FlxPoint.get(1770 - offset[0] - 80,   994 - offset[1] + 10),
        FlxPoint.get(1950 - offset[0] - 80,   980 - offset[1] + 15)
    ];
    FlxTween.angle(sprite, -7, -5, duration, {ease: FlxEase.cubeOut});
    FlxTween.quadPath(sprite, path, duration, true, {
        ease: FlxEase.cubeOut,
        onComplete: function(_) {
            carWaiting = true;
            if (!lightsStop)
            {
                var phillyCars = stage != null ? stage.getElement('phillyCars') : null;
                if (phillyCars != null) finishCarLights(phillyCars);
            }
        }
    });
}

function finishCarLights(sprite:FlxSprite):Void
{
    carWaiting = false;
    var duration:Float  = FlxG.random.float(1.8, 3.0);
    var startdelay:Float = FlxG.random.float(0.2, 1.2);
    var offset = [306.6, 168.3];
    var path = [
        FlxPoint.get(1950 - offset[0] - 80,   980 - offset[1] + 15),
        FlxPoint.get(2400 - offset[0],         980 - offset[1] - 50),
        FlxPoint.get(3102 - offset[0],        1187 - offset[1] + 40)
    ];
    FlxTween.angle(sprite, -5, 18, duration, {ease: FlxEase.sineIn, startDelay: startdelay});
    FlxTween.quadPath(sprite, path, duration, true, {
        ease: FlxEase.sineIn,
        startDelay: startdelay,
        onComplete: function(_) { carInterruptable = true; }
    });
}
