// ─────────────────────────────────────────────────────────────────────────────
// phillyStreetsErect.hx — Stage script para Cool Engine
//
// Ubicación: assets/stages/phillyStreetsErect/scripts/phillyStreetsErect.hx
//           o mods/<tu_mod>/stages/phillyStreetsErect/scripts/phillyStreetsErect.hx
//
// Variables inyectadas por el engine disponibles en este script:
//   stage        → la instancia del Stage (el JSON ya creó los sprites)
//   currentStage → alias de stage
//   game         → PlayState
//   playState    → alias de game
//   camGame      → cámara principal
//   camHUD       → cámara del HUD
//   SONG         → SwagSong con datos de la canción
//
// Callbacks disponibles:
//   onStageCreate()          → cuando el stage termina de construirse
//   onUpdate(elapsed)        → cada frame
//   onBeatHit(beat)          → cada beat
//   onStepHit(step)          → cada step
//   onDestroy()              → al salir de PlayState
// ─────────────────────────────────────────────────────────────────────────────

// ── Estado del semáforo ───────────────────────────────────────────────────────
var lightsStop = false;
var lastChange = 0;
var changeInterval = 8;

// ── Estado de los coches ─────────────────────────────────────────────────────
var carWaiting = false;
var carInterruptable = true;
var car2Interruptable = true;

// ── Timer de niebla ──────────────────────────────────────────────────────────
var _timer = 0.0;

// ── Shader de lluvia (si el engine no tiene RuntimeRainShader lo omitimos) ───
var rainShader = null;
var rainShaderFilter = null;
var rainShaderStartIntensity = 0.0;
var rainShaderEndIntensity = 0.01;

// ─────────────────────────────────────────────────────────────────────────────
// onStageCreate — se llama UNA VEZ después de que el JSON construye el stage.
// Los sprites ya existen (phillyCars, phillyTraffic, etc.) — solo inicializamos.
// ─────────────────────────────────────────────────────────────────────────────
function onStageCreate()
{
	// Intentar inicializar el rain shader (puede no existir en este engine)
	ShaderManager.loadShader('adjustColor');

	try
	{
		rainShader = new RuntimeRainShader();
		rainShader.scale = FlxG.height / 200.0;
		rainShader.rainColor = 0xFFa8adb5;

		// Intensidad según la canción actual
		var songId = SONG != null ? SONG.song : "";
		if (songId == "darnell")
		{
			rainShaderStartIntensity = 0;
			rainShaderEndIntensity = 0.01;
		}
		else if (songId == "lit-up" || songId == "lit_up")
		{
			rainShaderStartIntensity = 0.01;
			rainShaderEndIntensity = 0.02;
		}
		else if (songId == "2hot")
		{
			rainShaderStartIntensity = 0.02;
			rainShaderEndIntensity = 0.04;
		}
		else
		{
			rainShaderStartIntensity = 0.01;
			rainShaderEndIntensity = 0.02;
		}

		rainShader.intensity = rainShaderStartIntensity;
		rainShaderFilter = new ShaderFilter(rainShader);
		camGame.filters = [rainShaderFilter];
	}
	catch (e:Dynamic)
	{
		// El engine no tiene RuntimeRainShader — continuar sin él
		rainShader = null;
		rainShaderFilter = null;
		trace("[phillyStreetsErect] Rain shader no disponible: " + e);
	}

	// Semáforo en verde al inicio
	resetStageValues();

	// Coches fuera de pantalla
	resetCar(true, true);
}

// ─────────────────────────────────────────────────────────────────────────────
// onUpdate — cada frame
// ─────────────────────────────────────────────────────────────────────────────

var _applied = false;

function onUpdate(elapsed)
{
	_timer += elapsed;

	// Animación sinusoidal de la niebla — los backdrops ya están en el stage
	// gracias al JSON; solo modificamos su posición Y.
	var mist0 = stage.getElement("mist0");
	var mist1 = stage.getElement("mist1");
	var mist2 = stage.getElement("mist2");
	var mist3 = stage.getElement("mist3");
	var mist4 = stage.getElement("mist4");
	var mist5 = stage.getElement("mist5");

	if (mist0 != null)
		mist0.y = 660 + (Math.sin(_timer * 0.35) * 70);
	if (mist1 != null)
		mist1.y = 500 + (Math.sin(_timer * 0.30) * 80);
	if (mist2 != null)
		mist2.y = 540 + (Math.sin(_timer * 0.40) * 60);
	if (mist3 != null)
		mist3.y = 230 + (Math.sin(_timer * 0.30) * 70);
	if (mist4 != null)
		mist4.y = 170 + (Math.sin(_timer * 0.35) * 50);
	if (mist5 != null)
		mist5.y = -80 + (Math.sin(_timer * 0.08) * 100);

	// Actualizar rain shader
	if (rainShader != null)
	{
		var music = FlxG.sound.music;
		if (music != null && music.length > 0)
		{
			var conductor = null;
			try
			{
				conductor = funkin.data.Conductor.instance;
			}
			catch (e:Dynamic)
			{
			}
			var songPos = conductor != null ? conductor.songPosition : 0.0;
			var remapped = FlxMath.remapToRange(songPos, 0, music.length, rainShaderStartIntensity, rainShaderEndIntensity);
			rainShader.intensity = remapped;
		}
		else
		{
			rainShader.intensity = rainShaderStartIntensity;
		}
		try
		{
			rainShader.updateViewInfo(FlxG.width, FlxG.height, FlxG.camera);
			rainShader.update(elapsed);
		}
		catch (e:Dynamic)
		{
		}
	}

	if (!_applied)
	{
		// CORRECTO: la variable del engine es "chars", no "characters"
		var bf = chars.bf();
		var dad = chars.dad();
		var gf = chars.gf();

		_applyTo(bf, 'adjustColor_bf', -20, -5, -25, -40);
		_applyTo(dad, 'adjustColor_dad', -20, -5, -25, -40);
		_applyTo(gf, 'adjustColor_gf', -20, -5, -25, -40);
	}

	_applied = true;
}

function _applyTo(char, shaderKey, brightness, hue, contrast, saturation)
{
	if (char == null)
	{
		trace('[adjustColorStage] Personaje no encontrado para ' + shaderKey);
		return;
	}

	// Cargar el frag del archivo base bajo un nombre único por personaje.
	// Así ShaderManager.setShaderParam(shaderKey, ...) solo afecta a este personaje.
	var cs = ShaderManager.getShader('adjustColor');
	if (cs == null)
	{
		trace('[adjustColorStage] ERROR: shader adjustColor no encontrado.');
		return;
	}

	// Aplicar el shader al sprite del personaje
	ShaderManager.applyShader(char, 'adjustColor');

	// Setear los params DIRECTAMENTE en la instancia del personaje,
	// NO via ShaderManager.setShaderParam (que actualizaría los 3 a la vez)
	var sh = char.shader;
	if (sh != null)
	{
		sh.setFloat('brightness', brightness);
		sh.setFloat('hue', hue);
		sh.setFloat('contrast', contrast);
		sh.setFloat('saturation', saturation);
		trace('[adjustColorStage] Shader aplicado: ' + shaderKey + ' | brightness=' + brightness + ' hue=' + hue + ' contrast=' + contrast + ' saturation='
			+ saturation);
	}
	else
	{
		trace('[adjustColorStage] WARN: char.shader es null después de applyShader en ' + shaderKey);
		// Fallback: usar filters de OpenFL directamente si shader no funciona en FlxAnimate
		_applyViaFilters(char, brightness, hue, contrast, saturation);
	}
}

// Fallback por si FlxAnimate no expone .shader correctamente
function _applyViaFilters(char, brightness, hue, contrast, saturation)
{
	var cs = ShaderManager.getShader('adjustColor');
	if (cs == null)
		return;

	// ShaderManager.getShader devuelve el CustomShader que tiene .shader (FlxRuntimeShader lazy)
	// Usamos .shader para obtener la instancia compilada
	var instance = cs.shader;
	if (instance == null)
		return;

	instance.setFloat('brightness', brightness);
	instance.setFloat('hue', hue);
	instance.setFloat('contrast', contrast);
	instance.setFloat('saturation', saturation);

	// Aplicar como filtro OpenFL — funciona en cualquier DisplayObject (incluyendo FlxAnimate)
	char.filters = [new ShaderFilter(instance)];
	trace('[adjustColorStage] Shader aplicado via filters fallback.');
}

// ─────────────────────────────────────────────────────────────────────────────
// onBeatHit — cada beat
// ─────────────────────────────────────────────────────────────────────────────
function onBeatHit(beat)
{
	// Intentar mover el coche izquierdo
	if (FlxG.random.bool(10) && beat != (lastChange + changeInterval) && carInterruptable)
	{
		var cars = stage.getElement("phillyCars");
		if (cars != null)
		{
			if (!lightsStop)
				driveCar(cars);
			else
				driveCarLights(cars);
		}
	}

	// Intentar mover el coche derecho (solo en verde)
	if (FlxG.random.bool(10) && beat != (lastChange + changeInterval) && car2Interruptable && !lightsStop)
	{
		var cars2 = stage.getElement("phillyCars2");
		if (cars2 != null)
			driveCarBack(cars2);
	}

	// Cambiar el semáforo al llegar al intervalo
	if (beat == (lastChange + changeInterval))
		changeLights(beat);
}

// ─────────────────────────────────────────────────────────────────────────────
// onDestroy — al salir
// ─────────────────────────────────────────────────────────────────────────────
function onDestroy()
{
	var cars = stage.getElement("phillyCars");
	var cars2 = stage.getElement("phillyCars2");
	if (cars != null)
		FlxTween.cancelTweensOf(cars);
	if (cars2 != null)
		FlxTween.cancelTweensOf(cars2);

	// Limpiar filtros de cámara
	try
	{
		camGame.filters = [];
	}
	catch (e:Dynamic)
	{
	}

	var bf = chars.bf();
	var dad = chars.dad();
	var gf = chars.gf();

	if (bf != null)
	{
		ShaderManager.removeShader(bf);
	}
	if (dad != null)
	{
		ShaderManager.removeShader(dad);
	}
	if (gf != null)
	{
		ShaderManager.removeShader(gf);
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Funciones auxiliares
// ─────────────────────────────────────────────────────────────────────────────

function resetStageValues()
{
	lastChange = 0;
	changeInterval = 8;
	lightsStop = false;
	var traffic = stage.getElement("phillyTraffic");
	if (traffic != null)
		traffic.animation.play("togreen");
}

function resetCar(left, right)
{
	if (left)
	{
		carWaiting = false;
		carInterruptable = true;
		var cars = stage.getElement("phillyCars");
		if (cars != null)
		{
			FlxTween.cancelTweensOf(cars);
			cars.x = 1200;
			cars.y = 818;
			cars.angle = 0;
		}
	}
	if (right)
	{
		car2Interruptable = true;
		var cars2 = stage.getElement("phillyCars2");
		if (cars2 != null)
		{
			FlxTween.cancelTweensOf(cars2);
			cars2.x = 1200;
			cars2.y = 818;
			cars2.angle = 0;
		}
	}
}

function changeLights(beat)
{
	lastChange = beat;
	lightsStop = !lightsStop;

	var traffic = stage.getElement("phillyTraffic");
	if (lightsStop)
	{
		if (traffic != null)
			traffic.animation.play("tored");
		changeInterval = 20;
	}
	else
	{
		if (traffic != null)
			traffic.animation.play("togreen");
		changeInterval = 30;
		if (carWaiting)
		{
			var cars = stage.getElement("phillyCars");
			if (cars != null)
				finishCarLights(cars);
		}
	}
}

// Coche hacia la derecha sin semáforo (verde)
function driveCar(sprite)
{
	carInterruptable = false;
	FlxTween.cancelTweensOf(sprite);
	var variant = FlxG.random.int(1, 4);
	sprite.animation.play("car" + variant);
	var extraOffset = [0, 0];
	var duration = 2.0;
	switch (variant)
	{
		case 1:
			duration = FlxG.random.float(1.0, 1.7);
		case 2:
			extraOffset = [20, -15];
			duration = FlxG.random.float(0.6, 1.2);
		case 3:
			extraOffset = [30, 50];
			duration = FlxG.random.float(1.5, 2.5);
		case 4:
			extraOffset = [10, 60];
			duration = FlxG.random.float(1.5, 2.5);
	}
	var offset = [306.6, 168.3];
	sprite.offset.set(extraOffset[0], extraOffset[1]);
	var path = [
		FlxPoint.get(1570 - offset[0], 1049 - offset[1] - 30),
		FlxPoint.get(2400 - offset[0], 980 - offset[1] - 50),
		FlxPoint.get(3102 - offset[0], 1187 - offset[1] + 40)
	];
	FlxTween.angle(sprite, -8, 18, duration, null);
	FlxTween.quadPath(sprite, path, duration, true, {
		ease: null,
		onComplete: function(_)
		{
			carInterruptable = true;
		}
	});
}

// Coche que frena ante el semáforo en rojo
function driveCarLights(sprite)
{
	carInterruptable = false;
	FlxTween.cancelTweensOf(sprite);
	var variant = FlxG.random.int(1, 4);
	sprite.animation.play("car" + variant);
	var extraOffset = [0, 0];
	var duration = 2.0;
	switch (variant)
	{
		case 1:
			duration = FlxG.random.float(1.0, 1.7);
		case 2:
			extraOffset = [20, -15];
			duration = FlxG.random.float(0.9, 1.5);
		case 3:
			extraOffset = [30, 50];
			duration = FlxG.random.float(1.5, 2.5);
		case 4:
			extraOffset = [10, 60];
			duration = FlxG.random.float(1.5, 2.5);
	}
	var offset = [306.6, 168.3];
	sprite.offset.set(extraOffset[0], extraOffset[1]);
	var path = [
		FlxPoint.get(1500 - offset[0] - 20, 1049 - offset[1] - 20),
		FlxPoint.get(1770 - offset[0] - 80, 994 - offset[1] + 10),
		FlxPoint.get(1950 - offset[0] - 80, 980 - offset[1] + 15)
	];
	FlxTween.angle(sprite, -7, -5, duration, {ease: FlxEase.cubeOut});
	FlxTween.quadPath(sprite, path, duration, true, {
		ease: FlxEase.cubeOut,
		onComplete: function(_)
		{
			carWaiting = true;
			if (!lightsStop)
			{
				var cars = stage.getElement("phillyCars");
				if (cars != null)
					finishCarLights(cars);
			}
		}
	});
}

// Coche que arranca después del verde
function finishCarLights(sprite)
{
	carWaiting = false;
	var duration = FlxG.random.float(1.8, 3.0);
	var startdelay = FlxG.random.float(0.2, 1.2);
	var offset = [306.6, 168.3];
	var path = [
		FlxPoint.get(1950 - offset[0] - 80, 980 - offset[1] + 15),
		FlxPoint.get(2400 - offset[0], 980 - offset[1] - 50),
		FlxPoint.get(3102 - offset[0], 1187 - offset[1] + 40)
	];
	FlxTween.angle(sprite, -5, 18, duration, {ease: FlxEase.sineIn, startDelay: startdelay});
	FlxTween.quadPath(sprite, path, duration, true, {
		ease: FlxEase.sineIn,
		startDelay: startdelay,
		onComplete: function(_)
		{
			carInterruptable = true;
		}
	});
}

// Coche que viene de la derecha hacia la izquierda
function driveCarBack(sprite)
{
	car2Interruptable = false;
	FlxTween.cancelTweensOf(sprite);
	var variant = FlxG.random.int(1, 4);
	sprite.animation.play("car" + variant);
	var extraOffset = [0, 0];
	var duration = 2.0;
	switch (variant)
	{
		case 1:
			duration = FlxG.random.float(1.0, 1.7);
		case 2:
			extraOffset = [20, -15];
			duration = FlxG.random.float(0.6, 1.2);
		case 3:
			extraOffset = [30, 50];
			duration = FlxG.random.float(1.5, 2.5);
		case 4:
			extraOffset = [10, 60];
			duration = FlxG.random.float(1.5, 2.5);
	}
	var offset = [306.6, 168.3];
	sprite.offset.set(extraOffset[0], extraOffset[1]);
	var path = [
		FlxPoint.get(3102 - offset[0], 1127 - offset[1] + 60),
		FlxPoint.get(2400 - offset[0], 980 - offset[1] - 30),
		FlxPoint.get(1570 - offset[0], 1049 - offset[1] - 10)
	];
	FlxTween.angle(sprite, 18, -8, duration, null);
	FlxTween.quadPath(sprite, path, duration, true, {
		ease: null,
		onComplete: function(_)
		{
			car2Interruptable = true;
		}
	});
}
