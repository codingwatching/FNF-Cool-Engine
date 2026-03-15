// ─────────────────────────────────────────────────────────────────
//  BF – Fakeout Death Script
//  Basado en la lógica de V-Slice (bf.hxc)
//  Compatible con el sistema de callbacks de GameOverSubstate
// ─────────────────────────────────────────────────────────────────

// Estado interno del fakeout
var _doingFakeout:Bool   = false;  // ¿se activó el fakeout esta death?
var _fakeoutDone:Bool    = false;  // ¿ya terminó la animación de fakeout?

// ── Se llama al final del constructor de GameOverSubstate ─────────
function onGameOverCreate(substate)
{
    // Probabilidad 1/4096 (igual que V-Slice)
    if (FlxG.random.bool((1 / 4096) * 100))
    {
        _doingFakeout = true;
        _fakeoutDone  = false;

        // Sustituye firstDeath por fakeoutDeath
        bf.playAnim('fakeoutDeath', true);

        // Sonido del fakeout
        // Asegúrate de tener el archivo en assets/sounds/gameplay/gameover/fakeout_death.*
        FlxG.sound.play(Paths.sound('gameplay/gameover/fakeout_death'));
    }
}

// ── Bloquea ACCEPT mientras el fakeout no haya terminado ─────────
function onGameOverRetry()
{
    if (_doingFakeout && !_fakeoutDone)
        return true; // true = cancelar el retry
}

// ── Bloquea BACK también (igual que mustNotExit de V-Slice) ──────
function onGameOverBack()
{
    if (_doingFakeout && !_fakeoutDone)
        return true; // true = cancelar el back
}

// ── Lógica principal: detecta el fin del fakeout ─────────────────
function onGameOverUpdate(elapsed)
{
    if (!_doingFakeout || _fakeoutDone) return;

    var anim = bf.animation.curAnim;
    if (anim == null) return;

    if (anim.name == 'fakeoutDeath' && anim.finished)
    {
        _fakeoutDone = true;

        // Reproduce el sonido de muerte normal (el que GameOverSubstate
        // ya tocó en el constructor, lo repetimos porque el fakeout lo tapó)
        FlxG.sound.play(Paths.sound('fnf_loss_sfx'));

        // Vuelve a firstDeath → el engine detectará esta animación
        // con normalidad en su propio update() y continuará
        // con deathLoop, música, etc.
        bf.playAnim('firstDeath', true);
    }
}
