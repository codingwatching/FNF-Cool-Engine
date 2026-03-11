// phillyStreets.hx — Cool Engine stage script
//
// Usa ShaderManager.applyShaderToCamera("rain", camGame) para aplicar el shader.
// A partir de la corrección en ShaderManager, applyShaderToCamera() gestiona
// internamente un sprite overlay — no hace falta crear ni destruir nada manualmente.
// Para quitar el shader: ShaderManager.removeShaderFromCamera("rain", camGame).

var rainTime:Float = 0.0;
var shaderApplied:Bool = false;
var shaderDelay:Int = 0;  // esperar 2 frames antes de aplicar

var rainStartIntensity:Float = 0.0;
var rainEndIntensity:Float   = 0.0;

var lightsStop:Bool        = false;
var lastChange:Int         = 0;
var changeInterval:Int     = 8;
var carWaiting:Bool        = false;
var carInterruptable:Bool  = true;
var car2Interruptable:Bool = true;

function onStageCreate():Void
{
    var songId = (game != null && game.SONG != null) ? game.SONG.song.toLowerCase() : '';
    switch (songId)
    {
        case 'darnell':
            rainStartIntensity = 0.10;
            rainEndIntensity   = 0.30;
        case 'lit-up':
            rainStartIntensity = 0.30;
            rainEndIntensity   = 0.55;
        case '2hot':
            rainStartIntensity = 0.55;
            rainEndIntensity   = 0.90;
        default:
            rainStartIntensity = 0.10;
            rainEndIntensity   = 0.30;
    }

    ShaderManager.loadShader("rain");
    resetCar(true, true);
    resetStageValues();
}

function onUpdate(elapsed:Float):Void
{
    // Esperar 2 frames para que camGame haya renderizado su primer frame.
    if (!shaderApplied)
    {
        shaderDelay++;
        if (shaderDelay < 2) return;

        // applyShaderToCamera() crea el overlay internamente y lo gestiona.
        // No hace falta crear ningún FlxSprite manualmente.
        ShaderManager.applyShaderToCamera("rain", camGame);

        var puddleProp = stage != null ? stage.getElement('puddle') : null;
        if (puddleProp != null)
        {
            ShaderManager.setShaderParam("rain", "uPuddleY",      puddleProp.y + 80.0);
            ShaderManager.setShaderParam("rain", "uPuddleScaleY", 0.3);
        }
        else
        {
            ShaderManager.setShaderParam("rain", "uPuddleY",      0.0);
            ShaderManager.setShaderParam("rain", "uPuddleScaleY", 0.0);
        }

        shaderApplied = true;
    }

    rainTime += elapsed;

    var intensity:Float = rainStartIntensity;
    if (FlxG.sound.music != null && FlxG.sound.music.length > 100)
    {
        var songLen:Float = FlxG.sound.music.length;
        var songPos:Float = (Conductor != null) ? Conductor.songPosition : 0.0;
        intensity = FlxMath.remapToRange(songPos, 0.0, songLen, rainStartIntensity, rainEndIntensity);
        intensity = FlxMath.bound(intensity, rainStartIntensity, rainEndIntensity);
    }

    ShaderManager.setShaderParam("rain", "uTime",      rainTime);
    ShaderManager.setShaderParam("rain", "uIntensity", intensity);
    ShaderManager.setShaderParam("rain", "uScale",     FlxG.height / 200.0);
    ShaderManager.setShaderParam("rain", "uScreenW",   FlxG.width  * 1.0);
    ShaderManager.setShaderParam("rain", "uScreenH",   FlxG.height * 1.0);

    var sky = stage != null ? stage.getElement('phillySkybox') : null;
    if (sky != null)
        sky.x -= elapsed * 22;
}

function onBeatHit(beat:Int):Void
{
    var phillyCars  = stage != null ? stage.getElement('phillyCars')  : null;
    var phillyCars2 = stage != null ? stage.getElement('phillyCars2') : null;

    if (FlxG.random.bool(10) && beat != (lastChange + changeInterval) && carInterruptable)
    {
        if (phillyCars != null)
        {
            if (!lightsStop) driveCar(phillyCars);
            else             driveCarLights(phillyCars);
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
    // removeShaderFromCamera quita el overlay gestionado por ShaderManager.
    ShaderManager.removeShaderFromCamera("rain", camGame);
    shaderApplied = false;
    rainTime = 0.0;
}

function onRestart():Void
{
    ShaderManager.removeShaderFromCamera("rain", camGame);
    shaderApplied = false;
    shaderDelay   = 0;
    rainTime      = 0.0;
}

function onDestroy():Void
{
    var phillyCars  = stage != null ? stage.getElement('phillyCars')  : null;
    var phillyCars2 = stage != null ? stage.getElement('phillyCars2') : null;
    if (phillyCars  != null) FlxTween.cancelTweensOf(phillyCars);
    if (phillyCars2 != null) FlxTween.cancelTweensOf(phillyCars2);

    ShaderManager.removeShaderFromCamera("rain", camGame);
}

function changeLights(beat:Int):Void
{
    lastChange = beat;
    lightsStop = !lightsStop;

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

function resetCar(left:Bool, right:Bool):Void
{
    if (left)
    {
        carWaiting       = false;
        carInterruptable = true;
        var cars = stage != null ? stage.getElement('phillyCars') : null;
        if (cars != null) { FlxTween.cancelTweensOf(cars); cars.x = 1200; cars.y = 818; cars.angle = 0; }
    }
    if (right)
    {
        car2Interruptable = true;
        var cars2 = stage != null ? stage.getElement('phillyCars2') : null;
        if (cars2 != null) { FlxTween.cancelTweensOf(cars2); cars2.x = 1200; cars2.y = 818; cars2.angle = 0; }
    }
}

function driveCar(sprite):Void
{
    carInterruptable = false;
    FlxTween.cancelTweensOf(sprite);
    var v = FlxG.random.int(1, 4);
    sprite.animation.play('car' + v);
    var eo = [0, 0];
    var dur = 2.0;
    switch (v) {
        case 1: dur = FlxG.random.float(1.0, 1.7);
        case 2: eo = [20, -15]; dur = FlxG.random.float(0.6, 1.2);
        case 3: eo = [30,  50]; dur = FlxG.random.float(1.5, 2.5);
        case 4: eo = [10,  60]; dur = FlxG.random.float(1.5, 2.5);
    }
    var off = [306.6, 168.3];
    sprite.offset.set(eo[0], eo[1]);
    FlxTween.angle(sprite, -8, 18, dur, null);
    FlxTween.quadPath(sprite, [
        FlxPoint.get(1570-off[0], 1049-off[1]-30),
        FlxPoint.get(2400-off[0],  980-off[1]-50),
        FlxPoint.get(3102-off[0], 1187-off[1]+40)
    ], dur, true, { ease: null, onComplete: function(_) { carInterruptable = true; } });
}

function driveCarBack(sprite):Void
{
    car2Interruptable = false;
    FlxTween.cancelTweensOf(sprite);
    var v = FlxG.random.int(1, 4);
    sprite.animation.play('car' + v);
    var eo = [0, 0];
    var dur = 2.0;
    switch (v) {
        case 1: dur = FlxG.random.float(1.0, 1.7);
        case 2: eo = [20, -15]; dur = FlxG.random.float(0.6, 1.2);
        case 3: eo = [30,  50]; dur = FlxG.random.float(1.5, 2.5);
        case 4: eo = [10,  60]; dur = FlxG.random.float(1.5, 2.5);
    }
    var off = [306.6, 168.3];
    sprite.offset.set(eo[0], eo[1]);
    FlxTween.angle(sprite, 18, -8, dur, null);
    FlxTween.quadPath(sprite, [
        FlxPoint.get(3102-off[0], 1127-off[1]+60),
        FlxPoint.get(2400-off[0],  980-off[1]-30),
        FlxPoint.get(1570-off[0], 1049-off[1]-10)
    ], dur, true, { ease: null, onComplete: function(_) { car2Interruptable = true; } });
}

function driveCarLights(sprite):Void
{
    carInterruptable = false;
    FlxTween.cancelTweensOf(sprite);
    var v = FlxG.random.int(1, 4);
    sprite.animation.play('car' + v);
    var eo = [0, 0];
    var dur = 2.0;
    switch (v) {
        case 1: dur = FlxG.random.float(1.0, 1.7);
        case 2: eo = [20, -15]; dur = FlxG.random.float(0.9, 1.5);
        case 3: eo = [30,  50]; dur = FlxG.random.float(1.5, 2.5);
        case 4: eo = [10,  60]; dur = FlxG.random.float(1.5, 2.5);
    }
    var off = [306.6, 168.3];
    sprite.offset.set(eo[0], eo[1]);
    FlxTween.angle(sprite, -7, -5, dur, { ease: FlxEase.cubeOut });
    FlxTween.quadPath(sprite, [
        FlxPoint.get(1500-off[0]-20, 1049-off[1]-20),
        FlxPoint.get(1770-off[0]-80,  994-off[1]+10),
        FlxPoint.get(1950-off[0]-80,  980-off[1]+15)
    ], dur, true, {
        ease: FlxEase.cubeOut,
        onComplete: function(_) {
            carWaiting = true;
            if (!lightsStop) {
                var c = stage != null ? stage.getElement('phillyCars') : null;
                if (c != null) finishCarLights(c);
            }
        }
    });
}

function finishCarLights(sprite):Void
{
    carWaiting = false;
    var dur   = FlxG.random.float(1.8, 3.0);
    var delay = FlxG.random.float(0.2, 1.2);
    var off   = [306.6, 168.3];
    FlxTween.angle(sprite, -5, 18, dur, { ease: FlxEase.sineIn, startDelay: delay });
    FlxTween.quadPath(sprite, [
        FlxPoint.get(1950-off[0]-80,  980-off[1]+15),
        FlxPoint.get(2400-off[0],     980-off[1]-50),
        FlxPoint.get(3102-off[0],    1187-off[1]+40)
    ], dur, true, {
        ease: FlxEase.sineIn,
        startDelay: delay,
        onComplete: function(_) { carInterruptable = true; }
    });
}
