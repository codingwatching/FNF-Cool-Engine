/**
 * nene.hx — Script de personaje para Nene
 * Port de V-Slice. Carga ABotVis.hx con require().
 *
 * Estructura esperada:
 *   assets/characters/nene/scripts/nene.hx
 *   assets/characters/nene/scripts/ABotVis.hx
 */

// ══════════════════════════════════════════════════════════════════════════════
//  ESTADOS
// ══════════════════════════════════════════════════════════════════════════════

var STATE_DEFAULT            = 0;
var STATE_PRE_RAISE          = 1;
var STATE_RAISE              = 2;
var STATE_READY              = 3;
var STATE_LOWER              = 4;
var STATE_HAIR_BLOWING       = 5;
var STATE_HAIR_FALLING       = 6;
var STATE_HAIR_BLOWING_RAISE = 7;
var STATE_HAIR_FALLING_RAISE = 8;

var PUPIL_RIGHT = 0;
var PUPIL_LEFT  = 1;

// ══════════════════════════════════════════════════════════════════════════════
//  VARIABLES DE ESTADO
// ══════════════════════════════════════════════════════════════════════════════

var currentState:Int        = 0;
var pupilState:Int          = 0;
var VULTURE_THRESHOLD:Float = 0.5;
var MIN_BLINK_DELAY:Int     = 3;
var MAX_BLINK_DELAY:Int     = 7;
var blinkCountdown:Int      = 3;
var trainPassing:Bool       = false;
var animationFinished:Bool  = false;
var hasDanced:Bool          = false;

// ══════════════════════════════════════════════════════════════════════════════
//  SPRITES DEL A-BOT
// ══════════════════════════════════════════════════════════════════════════════

var abot:FunkinSprite      = null;
var stereoBG:FunkinSprite  = null;
var eyeWhites:FunkinSprite = null;
var pupil:FunkinSprite     = null;

/** Objeto devuelto por ABotVis.create() */
var viz:Dynamic = null;

var hasSetupAbot:Bool     = false;
var currentShader:Dynamic = null;

// Offset base del abot respecto al personaje (calculado en setupAbot)
var abotOffsetX:Float = 0.0;
var abotOffsetY:Float = 0.0;

// ══════════════════════════════════════════════════════════════════════════════
//  LIFECYCLE
// ══════════════════════════════════════════════════════════════════════════════

function onCreate()
{
    blinkCountdown = MIN_BLINK_DELAY;

    stereoBG = new FunkinSprite(0, 0);
    // stereoBG es una imagen estática — sin Animation.json, carga como PNG directo
    stereoBG.loadGraphic(Paths.characterimage('abot/stereoBG'));

    eyeWhites = new FunkinSprite(0, 0);
    eyeWhites.makeGraphic(160, 60, 0xFFFFFFFF);

    pupil = new FunkinSprite(0, 0);
    pupil.loadAsset('characters/images/abot/systemEyes');
    // BUGFIX: comprobar que anim no es null antes de añadir callback
    if (pupil.anim != null)
    {
        pupil.anim.onFrameChange.add(function(name, frameNumber, frameIndex) {
            if (frameNumber == 16) pupil.anim.pause();
        });
    }

    abot = new FunkinSprite(0, 0);
    abot.loadAsset('characters/images/abot/aBot');

    log('onCreate OK');
}

function postCreate()
{
    setupAbot();
}

function onUpdate(elapsed:Float)
{
    if (abot == null) return;

    abot.visible      = character.visible;
    pupil.visible     = character.visible;
    eyeWhites.visible = character.visible;
    stereoBG.visible  = character.visible;
    if (viz != null) viz.setVisible(character.visible);

    // BUGFIX: actualizar posición del A-Bot cada frame para seguir al personaje.
    // Sin esto el A-Bot se quedaba en la posición inicial de postCreate y
    // "desaparecía" cuando el personaje se movía con el scroll del stage.
    if (hasSetupAbot)
    {
        var offX:Float = 0.0;
        var offY:Float = 0.0;
        var _ca = (character.animation != null) ? character.animation.curAnim : null;
        var animName = (_ca != null) ? _ca.name : '';
        if (character.animOffsets.exists(animName))
        {
            offX = character.animOffsets.get(animName)[0];
            offY = character.animOffsets.get(animName)[1];
        }

        var bx:Float = character.x - 95 - (-offX * character.scale.x);
        var by:Float = character.y + 384 - (-offY * character.scale.y);

        abot.x      = bx;
        abot.y      = by;
        stereoBG.x  = bx + 150;  stereoBG.y  = by + 30;
        eyeWhites.x = bx + 40;   eyeWhites.y = by + 250;
        pupil.x     = bx + 50;   pupil.y     = by + 238;

        if (viz != null)
        {
            var _vizBars = viz.bars;
            if (_vizBars != null)
            {
                var vizBaseX:Float = bx + 207;
                var vizBaseY:Float = by + 84;
                for (i in 0..._vizBars.length)
                {
                    _vizBars[i].x = vizBaseX + i * 13;
                    _vizBars[i].y = vizBaseY;
                }
            }
        }
    }

    synchronizeShader();

    if (viz != null) viz.update(elapsed);

    // Tracking de pupilas
    if (pupil.anim != null && pupil.anim.isPlaying)
    {
        if (pupilState == PUPIL_RIGHT && pupil.anim.curFrame >= 17)
        {
            pupilState = PUPIL_LEFT;
            pupil.anim.pause();
        }
        else if (pupilState == PUPIL_LEFT && pupil.anim.curFrame >= 30)
        {
            pupilState = PUPIL_RIGHT;
            pupil.anim.pause();
        }
    }

    // Frame 13 de danceLeft → transición PRE_RAISE
    if (currentState == STATE_PRE_RAISE)
    {
        var curAnim = character.animation.curAnim;
        if (curAnim != null && curAnim.name == 'danceLeft' && curAnim.curFrame == 13)
        {
            animationFinished = true;
            transitionState();
        }
    }

    transitionState();
}

function onDestroy()
{
    if (viz != null) { viz.destroy(); viz = null; }
    if (abot      != null) { abot.destroy();      abot      = null; }
    if (pupil     != null) { pupil.destroy();     pupil     = null; }
    if (eyeWhites != null) { eyeWhites.destroy(); eyeWhites = null; }
    if (stereoBG  != null) { stereoBG.destroy();  stereoBG  = null; }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ANIMACIÓN / DANCE
// ══════════════════════════════════════════════════════════════════════════════

function overrideDance():Bool
{
    if (abot != null && abot.anim != null)
        abot.anim.play('', true, false, 1);

    switch (currentState)
    {
        case 0: // DEFAULT
            character.playAnim(hasDanced ? 'danceRight' : 'danceLeft', false);
            hasDanced = !hasDanced;
        case 1: // PRE_RAISE
            character.playAnim('danceLeft', false);
            hasDanced = false;
        case 3: // READY
            if (blinkCountdown == 0)
            {
                character.playAnim('idleKnife', false);
                blinkCountdown = FlxG.random.int(MIN_BLINK_DELAY, MAX_BLINK_DELAY);
            }
            else blinkCountdown--;
        case 4: // LOWER
            if (character.getCurAnimName() != 'lowerKnife')
                character.playAnim('lowerKnife', false);
        default:
    }

    return true;
}

function onAnimEnd(animName:String)
{
    switch (currentState)
    {
        case 2, 4, 5, 6, 7, 8:
            animationFinished = true;
            transitionState();
        default:
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  GAMEPLAY
// ══════════════════════════════════════════════════════════════════════════════

function onNoteHit(note:Dynamic)  { if (note != null) moveByNoteKind(note.noteType); }
function onNoteMiss(note:Dynamic) { if (note != null) moveByNoteKind(note.noteType); }

function onSongStart()
{
    if (viz != null) viz.initAnalyzer();
}

function onSongEnd()
{
    if (viz != null) viz.dumpSound();
}

// ══════════════════════════════════════════════════════════════════════════════
//  PUPILAS
// ══════════════════════════════════════════════════════════════════════════════

function movePupilsLeft():Void  { if (pupil != null && pupil.anim != null) pupil.anim.play('', true, false, 0);  }
function movePupilsRight():Void { if (pupil != null && pupil.anim != null) pupil.anim.play('', true, false, 17); }

function moveByNoteKind(kind:String):Void
{
    if      (kind == 'weekend-1-lightcan') movePupilsLeft();
    else if (kind == 'weekend-1-cockgun')  movePupilsRight();
}

function onSongEvent(eventName:String, value1:String, value2:String):Void
{
    if (eventName != 'FocusCamera') return;
    var ch:Int = Std.parseInt(value1);
    if      (ch == 0) movePupilsRight();
    else if (ch == 1) movePupilsLeft();
}

// ══════════════════════════════════════════════════════════════════════════════
//  TREN
// ══════════════════════════════════════════════════════════════════════════════

function setTrainPassing(value:Bool):Void { trainPassing = value; }

function checkTrainPassing(raised:Bool = false):Void
{
    if (!trainPassing) return;
    currentState = raised ? STATE_HAIR_BLOWING_RAISE : STATE_HAIR_BLOWING;
    character.playAnim(raised ? 'hairBlowKnife' : 'hairBlowNormal', true);
    animationFinished = false;
}

// ══════════════════════════════════════════════════════════════════════════════
//  MÁQUINA DE ESTADOS
// ══════════════════════════════════════════════════════════════════════════════

function transitionState():Void
{
    if (game == null) return;

    switch (currentState)
    {
        case 0: // DEFAULT
            if (game.health <= VULTURE_THRESHOLD) currentState = STATE_PRE_RAISE;
            checkTrainPassing();

        case 1: // PRE_RAISE
            if (game.health > VULTURE_THRESHOLD)
                currentState = STATE_DEFAULT;
            else if (animationFinished)
            {
                currentState = STATE_RAISE;
                character.playAnim('raiseKnife', true);
                animationFinished = false;
            }
            checkTrainPassing();

        case 2: // RAISE
            if (animationFinished) { currentState = STATE_READY; animationFinished = false; }
            checkTrainPassing(true);

        case 3: // READY
            if (game.health > VULTURE_THRESHOLD) currentState = STATE_LOWER;
            checkTrainPassing(true);

        case 4: // LOWER
            if (animationFinished) { currentState = STATE_DEFAULT; animationFinished = false; }
            checkTrainPassing();

        case 5: // HAIR_BLOWING
            if (!trainPassing) { currentState = STATE_HAIR_FALLING; character.playAnim('hairFallNormal', true); animationFinished = false; }
            else if (animationFinished) { character.playAnim('hairBlowNormal', true); animationFinished = false; }

        case 6: // HAIR_FALLING
            if (animationFinished) { currentState = STATE_DEFAULT; animationFinished = false; }

        case 7: // HAIR_BLOWING_RAISE
            if (!trainPassing) { currentState = STATE_HAIR_FALLING_RAISE; character.playAnim('hairFallKnife', true); animationFinished = false; }
            else if (animationFinished) { character.playAnim('hairBlowKnife', true); animationFinished = false; }

        case 8: // HAIR_FALLING_RAISE
            if (animationFinished) { currentState = STATE_READY; animationFinished = false; }

        default:
            currentState = STATE_DEFAULT;
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SETUP DEL A-BOT
// ══════════════════════════════════════════════════════════════════════════════

function setupAbot():Void
{
    if (abot == null) return;
    if (character == null) return; // postCreate se llama 2 veces; la primera sin character inyectado
    if (hasSetupAbot) return;      // BUGFIX: evitar doble setup y sprites duplicados

    var offX:Float = 0.0;
    var offY:Float = 0.0;
    var _ca = (character.animation != null) ? character.animation.curAnim : null;
    var animName = (_ca != null) ? _ca.name : '';
    if (character.animOffsets.exists(animName))
    {
        offX = character.animOffsets.get(animName)[0];
        offY = character.animOffsets.get(animName)[1];
    }

    abot.x = character.x - 95 - (-offX * character.scale.x);
    abot.y = character.y + 384 - (-offY * character.scale.y);

    stereoBG.x  = abot.x + 150;  stereoBG.y  = abot.y + 30;
    eyeWhites.x = abot.x + 40;   eyeWhites.y = abot.y + 250;
    pupil.x     = abot.x + 50;   pupil.y     = abot.y + 238;

    // Cargar ABotVis como script separado y crear la instancia del visualizador
    var vizBaseX:Float = abot.x + 207;
    var vizBaseY:Float = abot.y + 84;

    var vizModule:Dynamic = require('ABotVis.hx');
    if (vizModule != null)
    {
        viz = vizModule.get('create')(vizBaseX, vizBaseY);

        // Añadir las barras al estado antes del abot
        if (viz != null)
        {
            var _vizBars = viz.bars;
            for (bar in _vizBars)
                addBehindChar(bar, character);
        }
    }
    else
        log('WARN: no se pudo cargar ABotVis.hx');

    addBehindChar(stereoBG, character);
    addBehindChar(eyeWhites, character);
    addBehindChar(pupil, character);
    addBehindChar(abot, character);

    hasSetupAbot = true;
    log('A-Bot listo en (' + abot.x + ', ' + abot.y + ')');
}

// ══════════════════════════════════════════════════════════════════════════════
//  SYNC DE SHADER
// ══════════════════════════════════════════════════════════════════════════════

function synchronizeShader():Void
{
    var sh = character.shader;
    if (sh == currentShader) return;
    currentShader = sh;

    if (abot      != null) abot.shader      = sh;
    if (stereoBG  != null) stereoBG.shader  = sh;
    if (eyeWhites != null) eyeWhites.shader = sh;
    if (pupil     != null) pupil.shader     = sh;
    if (viz       != null) viz.setShader(sh);
}
