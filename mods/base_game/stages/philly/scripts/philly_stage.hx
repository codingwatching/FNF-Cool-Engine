var trainSound = null;
var lightWindow = null;
var train = null;
var curLight:Int = 0;
var trainMoving:Bool = false;
var trainCooldown:Int = 0;
var lightColors:Array<FlxColor> = [0xFFB66F43, 0xFF329A6D, 0xFF932C28, 0xFF2663AC, 0xFF502D64];

function onCreate() {
	trace('[Philly Stage] Script cargado');
}

function onStageCreate() {
	trace('[Philly Stage] Stage creado, obteniendo elementos...');

	if (stage != null) {
		trainSound = stage.getSound('trainSound');
		lightWindow = stage.getElement('phillyCityLights');
		train = stage.getElement('train');

		if (lightWindow != null) {
			lightWindow.alpha = 0;
		}

		if (train != null) {
			train.x = 2000;
			train.visible = false;
		}

		trace('[Philly Stage] Elementos inicializados:');
		trace('  - trainSound: ' + (trainSound != null));
		trace('  - lightWindow: ' + (lightWindow != null));
		trace('  - train: ' + (train != null));
	}
}

function onBeatHit(beat) {
	if (!trainMoving)
		trainCooldown += 1;

	if (beat % 8 == 0) {
		FlxTween.tween(lightWindow, {alpha: 0}, 1.3, {
			ease: FlxEase.quadInOut,
			onComplete: function(twn:FlxTween) {
				var nextColor = lightColors[FlxG.random.int(0, lightColors.length - 1)];
				lightWindow.color = nextColor;
				FlxTween.tween(lightWindow, {alpha: 1}, 1.3, {
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

	if (beat % 12 == 4 && FlxG.random.bool(30) && !trainMoving && trainCooldown > 8) {
		trainCooldown = FlxG.random.int(-4, 0);

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
}

function onDestroy() {
	trace('[Philly Stage] Limpiando...');

	// Detener sonido si está reproduciendo
	if (trainSound != null && trainSound.playing)
		trainSound.stop();
}
