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
    pupil.loadCharacterSparrow('abot/systemEyes');
    // BUGFIX: comprobar que anim no es null antes de añadir callback
    if (pupil.anim != null)
    {
        pupil.anim.onFrameChange.add(function(name, frameNumber, frameIndex) {
            if (frameNumber == 16) pupil.anim.pause();
        });
    }

    abot = new FunkinSprite(0, 0);
    abot.loadCharacterSparrow('abot/abotSystem');

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
    // Sin esto el A-Bot se quedaba en la posición inicial de postCreate.
    if (hasSetupAbot)
    {
        var offX:Float = 0.0;
        var offY:Float = 0.0;
        // BUGFIX: getCurAnimName() es el método unificado que funciona tanto
        // para Sparrow (donde animation.curAnim puede ser null en Atlas)
        // como para Animate Atlas. Nunca usar animation.curAnim.name directamente.
        var animName = character.getCurAnimName();
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
            var vizBaseX:Float = bx + 207;
            var vizBaseY:Float = by + 84;
            viz.setBase(vizBaseX, vizBaseY);
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

    // Frame 13 de danceLeft → marcar animationFinished para que
    // transitionState() dispare la transición a RAISE.
    if (currentState == STATE_PRE_RAISE)
    {
        var curAnimName = character.getCurAnimName();
        var curFrame    = (character.anim != null) ? character.anim.curFrame : -1;
        if (curAnimName == 'danceLeft' && curFrame == 13)
            animationFinished = true;
    }

    transitionState();
}

function onDestroy()
{
    if (viz != null)      { viz.destroy();       viz       = null; }
    if (abot != null)     { abot.destroy();      abot      = null; }
    if (pupil != null)    { pupil.destroy();     pupil     = null; }
    if (eyeWhites != null){ eyeWhites.destroy(); eyeWhites = null; }
    if (stereoBG != null) { stereoBG.destroy();  stereoBG  = null; }
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
    // FIX: case con múltiples valores — el preprocesador los expande a casos
    // separados. Este patrón (case 2, 4, ...:) es válido en Haxe pero no en
    // HScript directamente; el preprocesador de HScriptInstance lo convierte.
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

function onBeatHit(beat:Int)
{
    if (viz != null) viz.onBeatHit(beat);
}

/**
 * onEvent: intercepta los eventos de cámara ANTES de que el engine los procese.
 *
 * Retornar false = no cancelar el evento (el engine sigue moviendo la cámara).
 */
function onEvent(name:String, v1:String, v2:String, time:Float):Bool
{
    var lname:String = (name != null) ? name.toLowerCase() : '';

    if (lname == 'camera follow' || lname == 'camera'
     || lname == 'camera focus'  || lname == 'focus camera' || lname == 'focus')
    {
        var target:String = (v1 != null) ? v1.toLowerCase() : '';
        if (target == 'bf')
            movePupilsRight();
        else if (target == 'dad' || target == 'opponent')
            movePupilsLeft();
    }

    return false;
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

// ══════════════════════════════════════════════════════════════════════════════
//  TREN
// ══════════════════════════════════════════════════════════════════════════════

function setTrainPassing(value:Bool):Void { trainPassing = value; }

function checkTrainPassing(raised:Bool):Void
{
    // FIX Bug 4: el preprocesador elimina el valor por defecto "= false" del
    // parámetro porque HScript no soporta default args. Cuando se llama como
    // checkTrainPassing() sin argumento, raised llega como null en HScript.
    // Esta línea restaura el comportamiento correcto del valor por defecto.
    if (raised == null) raised = false;

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
    switch (currentState)
    {
        case 0: // DEFAULT
            if (health <= VULTURE_THRESHOLD) currentState = STATE_PRE_RAISE;
            checkTrainPassing(false);

        case 1: // PRE_RAISE
            if (health > VULTURE_THRESHOLD)
                currentState = STATE_DEFAULT;
            else if (animationFinished)
            {
                currentState = STATE_RAISE;
                character.playAnim('raiseKnife', true);
                animationFinished = false;
            }
            checkTrainPassing(false);

        case 2: // RAISE
            if (animationFinished) { currentState = STATE_READY; animationFinished = false; }
            checkTrainPassing(true);

        case 3: // READY
            if (health > VULTURE_THRESHOLD) currentState = STATE_LOWER;
            checkTrainPassing(true);

        case 4: // LOWER
            if (animationFinished) { currentState = STATE_DEFAULT; animationFinished = false; }
            checkTrainPassing(false);

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
    var animName = character.getCurAnimName();
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

    var vizBaseX:Float = abot.x + 207;
    var vizBaseY:Float = abot.y + 124;

    // FIX Bug 1+2: require() ahora aplica el preprocesador al módulo Y lo
    // recibe correctamente como objeto {create, padNum} gracias al return
    // explícito al final de ABotVis.hx.
    var vizModule:Dynamic = require('ABotVis.hx');
    if (vizModule != null)
        viz = vizModule.create(vizBaseX, vizBaseY);
    else
        log('WARN: no se pudo cargar ABotVis.hx');

    // ── Orden de profundidad (de atrás hacia adelante) ────────────────────
    // 1. stereoBG   — fondo negro de la pantalla
    // 2. barras viz — sobre el fondo, bajo el marco del aBot
    // 3. eyeWhites  — blanco de ojos
    // 4. pupil      — pupilas
    // 5. abot       — marco/cuerpo del A-Bot (tapa bordes de las barras)
    // 6. character  — Nene encima de todo
    addBehindChar(stereoBG, character);

    if (viz != null)
    {
        var _vizBars = viz.bars;
        for (bar in _vizBars)
            addBehindChar(bar, character);
    }

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
