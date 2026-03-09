// phillyStreets.hx — Cool Engine stage script
//
// El shader de lluvia está embebido aquí con createShader().
// NO necesita rain.frag en disco.
//
// FIX (shader negro con .frag):
//   Cuando un shader se aplica como ShaderFilter de cámara, openfl_TextureCoordv
//   está en pixel-space (ej. 640, 360), NO en UV [0..1].
//   flixel_texture2D() divide por openfl_TextureSize internamente → correcto.
//   texture2D() SIN dividir muestrea fuera de [0,1] → GL_CLAMP → negro.
//
// FIX (shader sin efecto con createShader):
//   FlxRuntimeShader compila el GLSL la primera vez que se renderiza, no al
//   construirse. setFloat() antes del primer render falla silenciosamente
//   porque el uniform location no está bound todavía.
//   SOLUCIÓN: crear el shader con `new FlxRuntimeShader(fragCode)` directamente,
//   aplicarlo con setFilters(camGame, [makeShaderFilter(shader)]) y llamar
//   setFloat en onUpdate() CADA FRAME en lugar de solo en la inicialización.
//   Así el primer set exitoso ocurre tras el primer render, garantizando el efecto.

// ─── GLSL del shader de lluvia ────────────────────────────────────────────────

var RAIN_FRAG =
    '#pragma header\n'
  + 'uniform float uTime;\n'
  + 'uniform float uScale;\n'
  + 'uniform float uIntensity;\n'
  + 'uniform float uPuddleY;\n'
  + 'uniform float uPuddleScaleY;\n'
  + 'uniform float uScreenW;\n'
  + 'uniform float uScreenH;\n'
  + '\n'
  + 'float hash(float n){return fract(sin(n)*43758.5453123);}\n'
  + 'float hash2(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123);}\n'
  + '\n'
  + 'float raindrop(vec2 uv,float t){\n'
  + '  float speed=0.7+hash(floor(uv.x*38.0))*0.6;\n'
  + '  float ofs=hash(floor(uv.x*38.0)*17.3);\n'
  + '  float xd=t*speed*0.12;\n'
  + '  float y=fract(uv.y+xd-t*speed+ofs);\n'
  + '  float head=smoothstep(0.06,0.0,abs(y-0.05));\n'
  + '  float tail=smoothstep(0.22,0.0,y)*(1.0-smoothstep(0.0,0.05,y));\n'
  + '  return clamp(head*1.2+tail*0.6,0.0,1.0);\n'
  + '}\n'
  + '\n'
  + 'float rainLayer(vec2 uv,float t,float cw,float ch,float density,float spd){\n'
  + '  vec2 cs=vec2(cw,ch);\n'
  + '  vec2 cell=floor(uv/cs);\n'
  + '  vec2 cuv=fract(uv/cs);\n'
  + '  if(hash2(cell)>=density)return 0.0;\n'
  + '  float xf=smoothstep(0.45,0.0,abs(cuv.x*2.0-1.0));\n'
  + '  return raindrop(cuv,t*spd)*xf;\n'
  + '}\n'
  + '\n'
  + 'float puddle(vec2 px,float t){\n'
  + '  if(uPuddleScaleY<=0.0)return 0.0;\n'
  + '  float dy=px.y-uPuddleY;\n'
  + '  if(dy<0.0)return 0.0;\n'
  + '  float d=dy*uPuddleScaleY;\n'
  + '  return(sin(d*20.0-t*4.0)*0.5+0.5)*exp(-d*1.2)*0.35;\n'
  + '}\n'
  + '\n'
  + 'void main(){\n'
  + '  vec4 tex=flixel_texture2D(bitmap,openfl_TextureCoordv);\n'
  + '  vec2 sc=openfl_TextureCoordv/openfl_TextureSize;\n'
  + '  float scale=(uScale>0.01)?uScale:3.5;\n'
  + '  vec2 uv=sc*scale;\n'
  + '\n'
  + '  float dark=clamp(uIntensity*0.7,0.0,0.55);\n'
  + '  vec3 base=mix(tex.rgb,vec3(0.18,0.22,0.32),dark);\n'
  + '\n'
  + '  float rain=0.0;\n'
  + '  rain+=rainLayer(uv,uTime,0.025,0.09,0.60,1.00)*1.00;\n'
  + '  rain+=rainLayer(uv*0.65,uTime,0.035,0.12,0.50,0.75)*0.65;\n'
  + '  rain+=rainLayer(uv*1.5,uTime,0.018,0.07,0.70,1.30)*0.40;\n'
  + '  rain=clamp(rain,0.0,1.0);\n'
  + '\n'
  + '  float df=rain*clamp(uIntensity*5.0,0.5,1.0);\n'
  + '  base=mix(base,vec3(0.75,0.87,1.0),clamp(df*0.55,0.0,0.55));\n'
  + '\n'
  + '  float sw=(uScreenW>1.0)?uScreenW:1280.0;\n'
  + '  float sh=(uScreenH>1.0)?uScreenH:720.0;\n'
  + '  base=mix(base,vec3(0.35,0.45,0.75),puddle(vec2(sc.x*sw,sc.y*sh),uTime)*uIntensity);\n'
  + '\n'
  + '  gl_FragColor=vec4(base,tex.a);\n'
  + '}\n';

// ─── Estado ───────────────────────────────────────────────────────────────────

var rainShader = null;    // FlxRuntimeShader creado con new FlxRuntimeShader(RAIN_FRAG)
var rainTime:Float = 0.0;

var rainStartIntensity:Float = 0.0;
var rainEndIntensity:Float   = 0.0;

var lightsStop:Bool        = false;
var lastChange:Int         = 0;
var changeInterval:Int     = 8;
var carWaiting:Bool        = false;
var carInterruptable:Bool  = true;
var car2Interruptable:Bool = true;

// ─────────────────────────────────────────────────────────────────────────────

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

    // Crear el shader aquí — aún no lo aplicamos a la cámara porque
    // la primera vez que se renderiza se compila el GLSL.
    // setFilters() y las primeras llamadas setFloat() se hacen en onUpdate.
    rainShader = FlxRuntimeShader.new(RAIN_FRAG);

    resetCar(true, true);
    resetStageValues();
}

var shaderApplied:Bool = false;

function onUpdate(elapsed:Float):Void
{
    // ── Aplicar el filtro de cámara una sola vez ───────────────────────────
    // Lo hacemos en onUpdate (no en onStageCreate) para asegurarnos de que
    // el canvas de camGame ya haya tenido al menos un render cycle.
    if (!shaderApplied && rainShader != null)
    {
        setFilters(camGame, [makeShaderFilter(rainShader)]);

        var puddleProp = stage != null ? stage.getElement('puddle') : null;
        if (puddleProp != null)
        {
            rainShader.setFloat('uPuddleY',      puddleProp.y + 80.0);
            rainShader.setFloat('uPuddleScaleY', 0.3);
        }
        else
        {
            rainShader.setFloat('uPuddleY',      0.0);
            rainShader.setFloat('uPuddleScaleY', 0.0);
        }

        shaderApplied = true;
    }

    // ── Actualizar uniforms CADA frame ────────────────────────────────────
    // Llamar setFloat() cada frame garantiza que el primer intento exitoso
    // (tras el primer render/compilación GLSL) aplique los valores correctos.
    if (rainShader != null)
    {
        rainTime += elapsed;

        var songLen:Float = (FlxG.sound.music != null) ? FlxG.sound.music.length : 1.0;
        var songPos:Float = (Conductor != null) ? Conductor.songPosition : 0.0;
        var intensity:Float = (songLen > 0)
            ? FlxMath.remapToRange(songPos, 0.0, songLen, rainStartIntensity, rainEndIntensity)
            : rainStartIntensity;

        rainShader.setFloat('uTime',      rainTime);
        rainShader.setFloat('uIntensity', intensity);
        rainShader.setFloat('uScale',     FlxG.height / 200.0);
        rainShader.setFloat('uScreenW',   FlxG.width  * 1.0);
        rainShader.setFloat('uScreenH',   FlxG.height * 1.0);
    }

    // ── Sky scroll ─────────────────────────────────────────────────────────
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
    clearFilters(camGame);
    rainShader = null;
    shaderApplied = false;
}

function onRestart():Void
{
    // Recrear el shader al reiniciar
    shaderApplied = false;
    rainShader = FlxRuntimeShader.new(RAIN_FRAG);
}

function onDestroy():Void
{
    var phillyCars  = stage != null ? stage.getElement('phillyCars')  : null;
    var phillyCars2 = stage != null ? stage.getElement('phillyCars2') : null;
    if (phillyCars  != null) FlxTween.cancelTweensOf(phillyCars);
    if (phillyCars2 != null) FlxTween.cancelTweensOf(phillyCars2);
    rainShader = null;
}

// ─── Semáforos ────────────────────────────────────────────────────────────────

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

// ─── Coches ───────────────────────────────────────────────────────────────────

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
