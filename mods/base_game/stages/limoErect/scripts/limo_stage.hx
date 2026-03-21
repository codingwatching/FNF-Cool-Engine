// ============================================================================
//  limo_stage.hx  —  Limo Erect Stage Script
//  Cool Engine HScript
// ============================================================================

var fastCar        = null;
var fastCarCanDrive = false;
var _shadersApplied = false;

var dancer1 = null;
var dancer2 = null;
var dancer3 = null;
var dancer4 = null;
var sky     = null;

var shootingStar      = null;
var shootingStarBeat  = 0;
var shootingStarOffset = 2;
var BRIGHTNESS = -30.0;
var HUE        = -30.0;
var CONTRAST   =   0.0;
var SATURATION = -20.0;

// ── Mists: sprite del stage + sprite gemelo (leapfrog) ───────────────────────
// El PNG de mist es 512×512. Con escala 1.5 = 768px, que no cubre 1280px.
// Solución: dos sprites por capa que se persiguen uno al otro.
// Cuando el primero sale por la derecha, se teleporta DETRÁS del segundo, y viceversa.
// Esto replica exactamente el tiling continuo de FlxBackdrop.
var mist1 = null;  var mist1b = null;
var mist2 = null;  var mist2b = null;
var mist3 = null;  var mist3b = null;
var mist4 = null;  var mist4b = null;
var mist5 = null;  var mist5b = null;

var _mistTimer = 0.0;
var _carHapticsActive = false;

// ============================================================================
//  INIT
// ============================================================================

function onCreate()
{
	trace('[Limo Stage] Script cargado');
}

function onStageCreate()
{
	trace('[Limo Stage] Stage creado...');
	if (stage == null) { trace('[Limo Stage] ERROR: stage es null'); return; }

	fastCar = stage.getElement('fastCar');
	if (fastCar != null) { fastCar.active = true; resetFastCar(); }

	dancer1 = stage.getElement('dancer1');
	dancer2 = stage.getElement('dancer2');
	dancer3 = stage.getElement('dancer3');
	dancer4 = stage.getElement('dancer4');
	sky     = stage.getElement('limoSunset');

	// ── Shooting star ─────────────────────────────────────────────────────────
	// firstAnimation en el JSON la reproduce al cargar — la ocultamos de inmediato
	shootingStar = stage.getElement('shooting star');
	if (shootingStar != null)
	{
		shootingStar.blend   = BlendMode.ADD;
		shootingStar.visible = false;
		shootingStar.animation.stop(); // para la animación que auto-arrancó
	}

	ShaderManager.loadShader('adjustColor');
	trace('[Limo Stage] Init OK');
}


/**
 * Crea un sprite gemelo copiando el gráfico, escala, alpha, blend,
 * scrollFactor y velocidad del original. Lo posiciona a la derecha
 * del original para que juntos cubran toda la pantalla sin huecos.
 */
function _makeCompanion(src)
{
	if (src == null) return null;

	var b = new FlxSprite();
	b.loadGraphic(src.graphic); // mismo gráfico, sin duplicar memoria
	b.scale.set(src.scale.x, src.scale.y);
	b.updateHitbox();
	b.alpha   = src.alpha;
	b.blend   = src.blend;
	b.color   = src.color;
	b.scrollFactor.set(src.scrollFactor.x, src.scrollFactor.y);
	b.active  = true;

	// Posicionar justo a la derecha del original
	b.x = src.x + (src.frameWidth * src.scale.x);
	b.y = src.y;

	setVelocityX(b, getVelocityX(src));

	add(b); // añadir al PlayState para que se renderice
	return b;
}

/**
 * Leapfrog loop para dos sprites (a y b).
 * Cuando uno sale por la derecha, se teleporta detrás del otro.
 * Así siempre hay cobertura continua, igual que FlxBackdrop.
 */
function _loopPair(a, b)
{
	if (a == null || b == null) return;

	var w = a.frameWidth * a.scale.x;

	if (a.x > FlxG.width + 100)
		a.x = b.x + w - 4; // -4 para evitar gap de 1px por redondeo

	if (b.x > FlxG.width + 100)
		b.x = a.x + w - 4;
}

// ============================================================================
//  UPDATE
// ============================================================================

function onUpdate(elapsed)
{
	// ── Shaders — una sola vez ────────────────────────────────────────────────
	if (!_shadersApplied)
	{
		var bf  = chars.bf();
		var dad = chars.dad();
		var gf  = chars.gf();
		if (bf != null && dad != null && gf != null)
		{
			_shadersApplied = true;
			_applyTo(bf,      BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(dad,     BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(gf,      BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(dancer1, BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(dancer2, BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(dancer3, BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(dancer4, BRIGHTNESS, HUE, CONTRAST, SATURATION);
		}
	}

	// ── Shooting star: ocultar cuando termina la animación ───────────────────
	if (shootingStar != null && shootingStar.visible)
	{
		var anim = shootingStar.animation.curAnim;
		if (anim != null && anim.finished)
			shootingStar.visible = false;
	}

	// ── Seno vertical — cada frame ────────────────────────────────────────────
	_mistTimer += elapsed;

	if (mist1 != null) { mist1.y = -380 + (Math.sin(_mistTimer * 0.4) * 300); if (mist1b != null) mist1b.y = mist1.y; }
	if (mist2 != null) { mist2.y = -20  + (Math.sin(_mistTimer * 0.5) * 200); if (mist2b != null) mist2b.y = mist2.y; }
	if (mist3 != null) { mist3.y = 100  + (Math.sin(_mistTimer)       * 200); if (mist3b != null) mist3b.y = mist3.y; }
	if (mist4 != null) { mist4.y = 10   + (Math.sin(_mistTimer * 0.8) * 100); if (mist4b != null) mist4b.y = mist4.y; }
	if (mist5 != null) { mist5.y = -400 + (Math.sin(_mistTimer * 0.2) * 150); if (mist5b != null) mist5b.y = mist5.y; }

	// ── Leapfrog loop — cada frame ────────────────────────────────────────────
	_loopPair(mist1, mist1b);
	_loopPair(mist2, mist2b);
	_loopPair(mist3, mist3b);
	_loopPair(mist4, mist4b);
	_loopPair(mist5, mist5b);

	// ── Carro ────────────────────────────────────────────────────────────────
	if (fastCar != null && getVelocityX(fastCar) > 0 && fastCar.x > FlxG.width + 1000)
		setVelocityX(fastCar, 0);
}

// ============================================================================
//  BEAT / STEP
// ============================================================================

function onBeatHit(beat)
{
	if (FlxG.random.bool(10) && fastCarCanDrive)
		fastCarDrive();

	if (shootingStar != null && FlxG.random.bool(10) && beat > (shootingStarBeat + shootingStarOffset))
		doShootingStar(beat);
}

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

// ============================================================================
//  SHOOTING STAR
// ============================================================================

function doShootingStar(beat)
{
	if (shootingStar == null) return;
	shootingStar.visible = true;
	shootingStar.x       = FlxG.random.int(50, 900);
	shootingStar.y       = FlxG.random.int(-10, 20);
	shootingStar.flipX   = FlxG.random.bool(50);
	shootingStar.animation.play('shooting star', true);
	shootingStarBeat   = beat;
	shootingStarOffset = FlxG.random.int(4, 8);
}

// ============================================================================
//  CARRO RÁPIDO
// ============================================================================

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

// ============================================================================
//  EVENTOS
// ============================================================================

function onEvent(name, value1, value2, time)
{
	switch (name.toLowerCase())
	{
		case 'spawn fast car': if (fastCarCanDrive) fastCarDrive();
		case 'reset fast car': resetFastCar();
		case 'shooting star':  doShootingStar(Math.floor(Conductor.songPosition / Conductor.crochet));
	}
	return false;
}

function onCountdownStart()
{
	resetFastCar();
	shootingStarBeat   = 0;
	shootingStarOffset = 2;
}

// ============================================================================
//  SHADERS
// ============================================================================

function _applyTo(char, brightness, hue, contrast, saturation)
{
	if (char == null) return;
	ShaderManager.applyShader(char, 'adjustColor');
	var sh = char.shader;
	if (sh != null)
	{
		sh.setFloat('brightness', brightness);
		sh.setFloat('hue',        hue);
		sh.setFloat('contrast',   contrast);
		sh.setFloat('saturation', saturation);
	}
	else
	{
		var cs = ShaderManager.getShader('adjustColor');
		if (cs == null) return;
		var inst = cs.shader;
		if (inst == null) return;
		inst.setFloat('brightness', brightness);
		inst.setFloat('hue',        hue);
		inst.setFloat('contrast',   contrast);
		inst.setFloat('saturation', saturation);
		char.filters = [new openfl.filters.ShaderFilter(inst)];
	}
}

// ============================================================================
//  CLEANUP
// ============================================================================

function onDestroy()
{
	if (fastCar != null) setVelocityX(fastCar, 0);

	// Eliminar sprites gemelos del PlayState
	if (mist1b != null) remove(mist1b, true);
	if (mist2b != null) remove(mist2b, true);
	if (mist3b != null) remove(mist3b, true);
	if (mist4b != null) remove(mist4b, true);
	if (mist5b != null) remove(mist5b, true);

	var bf  = chars.bf();
	var dad = chars.dad();
	var gf  = chars.gf();

	if (bf      != null) ShaderManager.removeShader(bf);
	if (dad     != null) ShaderManager.removeShader(dad);
	if (gf      != null) ShaderManager.removeShader(gf);
	if (dancer1 != null) ShaderManager.removeShader(dancer1);
	if (dancer2 != null) ShaderManager.removeShader(dancer2);
	if (dancer3 != null) ShaderManager.removeShader(dancer3);
	if (dancer4 != null) ShaderManager.removeShader(dancer4);
}
