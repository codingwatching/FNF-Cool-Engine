var trainSound = null;
var phillyCityLights = null;
var train = null;
var curLight:Int = 0;
var trainMoving:Bool = false;
var trainCooldown:Int = 0;
var SATURATION = -16;
var HUE = -26;
var BRIGHTNESS = -5;
var CONTRAST = 0;

// ==========================================
// INICIALIZACIÓN
// ==========================================

function onCreate()
{
	trace('[Philly Stage] Script cargado');

	// Esperar a que el stage esté listo
	// Se llamará onStageCreate cuando esté disponible
}

function onStageCreate()
{
	trace('[Philly Stage] Stage creado, obteniendo elementos...');

	// Obtener elementos del stage
	if (stage != null)
	{
		trainSound = stage.getSound('trainSound');
		phillyCityLights = stage.getGroup('phillyCityLights');
		train = stage.getElement('train');

		trace('[Philly Stage] Elementos inicializados:');
		trace('  - trainSound: ' + (trainSound != null));
		trace('  - phillyCityLights: ' + (phillyCityLights != null));
		trace('  - train: ' + (train != null));
	}

	ShaderManager.loadShader('adjustColor');
}

// ==========================================
// BEAT HIT - LUCES Y TREN
// ==========================================

function onBeatHit(beat)
{
	if (!trainMoving)
		trainCooldown += 1;

	if (beat % 4 == 0 && phillyCityLights != null)
	{
		phillyCityLights.forEach(function(light:FlxSprite)
		{
			light.visible = false;
		});

		curLight = FlxG.random.int(0, phillyCityLights.length - 1);
		phillyCityLights.members[curLight].visible = true;
	}

	if (beat % 8 == 4 && FlxG.random.bool(30) && !trainMoving && trainCooldown > 8)
	{
		trainCooldown = FlxG.random.int(-4, 0);
		trainMoving = true;
		if (trainSound != null)
			trainSound.play(true);
	}
}

// ==========================================
// UPDATE - MOVIMIENTO DEL TREN
// ==========================================

var _shadersApplied:Bool = false;

function onUpdate(elapsed)
{
	if (trainMoving && train != null)
	{
		train.x -= 150;
		train.visible = false;

		if (train.x < -4000)
		{
			train.visible = true;
			new FlxTimer().start(2, function(tmr:FlxTimer)
			{
				FlxTween.tween(train, {x: 2000}, 3, {type: FlxTweenType.ONESHOT});
				trainMoving = false;
			});
		}
	}

	if (!_shadersApplied)
	{
		var bf = chars.bf();
		var dad = chars.dad();
		var gf = chars.gf();
		if (bf != null && dad != null && gf != null)
		{
			_shadersApplied = true;
			_applyTo(bf, BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(dad, BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(gf, BRIGHTNESS, HUE, CONTRAST, SATURATION);
		}
	}
}

function _applyTo(char, brightness, hue, contrast, saturation)
{
	if (char == null)
		return;
	ShaderManager.applyShader(char, 'adjustColor');
	var sh = char.shader;
	if (sh != null)
	{
		sh.setFloat('brightness', brightness);
		sh.setFloat('hue', hue);
		sh.setFloat('contrast', contrast);
		sh.setFloat('saturation', saturation);
	}
	else
	{
		var cs = ShaderManager.getShader('adjustColor');
		if (cs == null)
			return;
		var inst = cs.shader;
		if (inst == null)
			return;
		inst.setFloat('brightness', brightness);
		inst.setFloat('hue', hue);
		inst.setFloat('contrast', contrast);
		inst.setFloat('saturation', saturation);
		char.filters = [new openfl.filters.ShaderFilter(inst)];
	}
}

// ==========================================
// CLEANUP
// ==========================================

function onDestroy()
{
	trace('[Philly Stage] Limpiando...');

	// Detener sonido si está reproduciendo
	if (trainSound != null && trainSound.playing)
		trainSound.stop();

	var bf = chars.bf();
	var dad = chars.dad();
	var gf = chars.gf();

	if (bf != null)
		ShaderManager.removeShader(bf);
	if (dad != null)
		ShaderManager.removeShader(dad);
	if (gf != null)
		ShaderManager.removeShader(gf);
}
