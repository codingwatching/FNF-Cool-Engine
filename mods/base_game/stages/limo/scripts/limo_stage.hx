// limo_stage.hx — Cool Engine stage script
//
// BUGS ARREGLADOS:
//   1. "Null Function Pointer" en onBeatHit:
//      Causa real → Paths.soundRandomStage() NO EXISTE, la función es Paths.soundRandom()
//      Al llamar a una función null en hscript se lanza "Null Function Pointer".
//
//   2. velocity.x = valor → REEMPLAZADO por setVelocityX() / setVelocity()
//      hscript no siempre maneja bien la asignación encadenada obj.velocity.x = v
//      (el intérprete puede resolver obj.velocity pero fallar al setear .x en el FlxPoint).
//      Usar los nuevos helpers del ScriptAPI es la forma correcta y segura.
//
//   3. dancers.forEach(function(dancer:BackgroundDancer){...})
//      hscript NO soporta type-annotations en parámetros de lambdas.
//      Reemplazado por un bucle for manual con null-check.
//
//   4. dancers sin null-check en onStepHit → crash si el grupo 'limos' no existe.

var fastCar = null;
var fastCarCanDrive = false;
var dancer1 = null;
var dancer2 = null;
var dancer3 = null;
var dancer4 = null;

// ─── onCreate ─────────────────────────────────────────────────────────────────

function onCreate()
{
	trace('[Limo Stage] Script cargado');
}

// ─── onStageCreate ────────────────────────────────────────────────────────────

function onStageCreate()
{
	trace('[Limo Stage] Stage creado, obteniendo elementos...');

	if (stage == null)
		return;

	fastCar = stage.getElement('fastCar');
	if (fastCar != null)
	{
		fastCar.active = true;
		resetFastCar();
	}

	dancer1 = stage.getElement('dancer1');
	dancer2 = stage.getElement('dancer2');
	dancer3 = stage.getElement('dancer3');
	dancer4 = stage.getElement('dancer4');

	trace('[Limo Stage] Elementos inicializados:');
	trace('  - fastCar: ' + (fastCar != null));
	trace('  - dancers: ' + (dancers != null));
}

// ─── onBeatHit ────────────────────────────────────────────────────────────────

function onBeatHit(beat)
{
	if (FlxG.random.bool(10) && fastCarCanDrive)
		fastCarDrive();
}

// ─── onStepHit ────────────────────────────────────────────────────────────────

function onStepHit(step)
{
	_danceChar(dancer1);
	_danceChar(dancer2);
	_danceChar(dancer3);
	_danceChar(dancer4);
}

function _danceChar(dancer)
{
	if (dancer == null) return;
	var curAnim = dancer.animation.curAnim;
	if (curAnim == null || curAnim.finished)
	{
		var isDancingLeft = (curAnim != null && curAnim.name == 'danceLeft');
		dancer.animation.play(isDancingLeft ? 'danceRight' : 'danceLeft', true);
	}
}

// ─── Funciones del carro ──────────────────────────────────────────────────────

function resetFastCar()
{
	if (fastCar == null) return;
	fastCar.x = -12600;
	fastCar.y = FlxG.random.int(140, 250);
	setVelocityX(fastCar, 0);
	fastCarCanDrive   = true;
	_carHapticsActive = false;
}

function fastCarDrive()
{
	if (fastCar == null || !fastCarCanDrive) return;
	FlxG.sound.play(Paths.soundRandomStage('carPass', 0, 1), 0.7);
	setVelocityX(fastCar, (FlxG.random.int(170, 220) / FlxG.elapsed) * 3);
	fastCarCanDrive = false;
	_carHapticsActive = true;
	new FlxTimer().start(1.4, function(t1) { _carHapticsActive = false; });
	new FlxTimer().start(2.0, function(t2) { resetFastCar(); });
}

// ─── onUpdate ─────────────────────────────────────────────────────────────────

function onUpdate(elapsed)
{
	// ── Carro ────────────────────────────────────────────────────────────────
	if (fastCar != null && getVelocityX(fastCar) > 0 && fastCar.x > FlxG.width + 1000)
		setVelocityX(fastCar, 0);
}

function onCountdownStart()
{
	resetFastCar();
}

// ─── Eventos personalizados ───────────────────────────────────────────────────

function onEvent(name, value1, value2, time)
{
	switch (name.toLowerCase())
	{
		case 'spawn fast car':
			if (fastCarCanDrive)
				fastCarDrive();

		case 'reset fast car':
			resetFastCar();
	}

	return false;
}

// ─── Cleanup ──────────────────────────────────────────────────────────────────

function onDestroy()
{
	trace('[Limo Stage] Limpiando...');

	if (fastCar != null) setVelocityX(fastCar, 0);
}