var trainSound = null;
var lightWindow = null;
var train = null;
var trainMoving:Bool = false;
var trainCooldown:Int = 0;
var SATURATION = -16;
var HUE = -26;
var BRIGHTNESS = -5;
var CONTRAST = 0;

// ==========================================
// INICIALIZACIÓN
// ==========================================

var lightColors:Array<FlxColor> = [0xFFB66F43, 0xFF329A6D, 0xFF932C28, 0xFF2663AC, 0xFF502D64];

function onCreate() {
	trace('[Philly Stage] Script cargado');

	// Esperar a que el stage esté listo
	// Se llamará onStageCreate cuando esté disponible
}

function onStageCreate() {
	trace('[Philly Stage] Stage creado, obteniendo elementos...');

	// Obtener elementos del stage
	if (stage != null) {
		trainSound = stage.getSound('trainSound');
		lightWindow = stage.getElement('phillyCityLights');
		train = stage.getElement('train');

		if (lightWindow != null) {
			lightWindow.color = 0xFF000000;
		}

		if (train != null) {
			train.x = 2000;
			train.visible = false;
		}

		trace('[Philly Stage] Elementos inicializados:');
		trace('  - trainSound: ' + (trainSound != null));
		trace('  - phillyCityLights: ' + (lightWindow != null));
		trace('  - train: ' + (train != null));
	}

	ShaderManager.loadShader('adjustColor');
}

// ==========================================
// BEAT HIT - LUCES Y TREN
// ==========================================

var transitioninCurse:Bool = false;

function onBeatHit(beat) {
	if (!trainMoving)
		trainCooldown += 1;

	if (beat % 8 == 0) {
		FlxTween.color(lightWindow, 1.3, lightWindow.color, 0xFF000000, {
			ease: FlxEase.quadInOut,
			onComplete: function(twn:FlxTween) {
				var nextColor = lightColors[FlxG.random.int(0, lightColors.length - 1)];
				FlxTween.color(lightWindow, 1.3, 0xFF000000, nextColor, {
					ease: FlxEase.quadInOut
				});
			}
		});
	}

	switch (trainMoving) {
		case true:
			gf.setAnimReplace('danceLeft', 'hairBlow');
			gf.setAnimReplace('danceRight', 'hairBlow');
	}

	if (beat % 8 == 4 && FlxG.random.bool(30) && !trainMoving && trainCooldown > 8) {
		trainCooldown = FlxG.random.int(-4, 0);
		trainMoving = true;
		if (trainSound != null)
			trainSound.play(true);

		new FlxTimer().start(4.4, function(tmr:FlxTimer) {
			if (train != null) {
				train.x = 2000;
				train.visible = true;
				trainMoving = true;
			}
		});
	}
}

// ==========================================
// UPDATE - MOVIMIENTO DEL TREN
// ==========================================

var _shadersApplied:Bool = false;

function onUpdate(elapsed) {
	if (trainMoving && train != null) {
		train.x -= 2000 * elapsed;
		if (train.x < -4200) {
			train.visible = false;
			trainMoving = false;
			trace('[Philly Stage] Train finished passing');

			gf.clearAnimReplacements();
			gf.playAnim('hairFall',true);
		}
	}

	if (!_shadersApplied) {
		var bf = chars.bf();
		var dad = chars.dad();
		var gf = chars.gf();
		if (bf != null && dad != null && gf != null) {
			_shadersApplied = true;
			_applyTo(bf, BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(dad, BRIGHTNESS, HUE, CONTRAST, SATURATION);
			_applyTo(gf, BRIGHTNESS, HUE, CONTRAST, SATURATION);
		}
	}
}

function _applyTo(char, brightness, hue, contrast, saturation) {
	if (char == null)
		return;
	ShaderManager.applyShader(char, 'adjustColor');
	var sh = char.shader;
	if (sh != null) {
		sh.setFloat('brightness', brightness);
		sh.setFloat('hue', hue);
		sh.setFloat('contrast', contrast);
		sh.setFloat('saturation', saturation);
	} else {
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

function onDestroy() {
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
