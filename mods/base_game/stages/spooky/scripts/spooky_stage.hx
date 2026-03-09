// SPOOKY STAGE SCRIPT
// Ubication: assets/stages/spooky/scripts/spooky.hx
// Or: assets/songs/south/scripts/spooky_stage.hx (for song specific)

var halloweenBG = null;

var lightningStrikeBeat:Int = 0;
var lightningOffset:Int = 8;

function onCreate()
{
	trace('[Spooky Stage] Script cargado');
}

function onStageCreate()
{
	trace('[Spooky Stage] Stage creado, obteniendo elementos...');
	
	// Obtener elementos del stage
	halloweenBG = stage.getElement('halloweenBG');
	
	trace('[Spooky Stage] Elementos inicializados:');
	trace('  - halloweenBG: ' + (halloweenBG != null));
}

// ==========================================
// BEAT HIT - LIGHTNING
// ==========================================

function onBeatHit(beat)
{
	// 10% de probabilidad de rayo, pero debe haber pasado suficiente tiempo
	if (FlxG.random.bool(10) && beat > lightningStrikeBeat + lightningOffset)
	{
		triggerLightning();
	}
}

// ==========================================
// FUNCIONES DEL RAYO
// ==========================================

function triggerLightning()
{
	trace('[Spooky Stage] ¡Rayo!');
	
	// Reproducir sonido de trueno (aleatorio entre thunder_1 y thunder_2)
	// FIX: Paths.soundRandom() (no soundRandomStage que no existe)
	FlxG.sound.play(Paths.soundRandomStage('thunder_', 1, 2));
	
	// Animar el background
	if (halloweenBG != null && halloweenBG.animation != null)
	{
		halloweenBG.animation.play('lightning');
	}
	
	// Asustar a los personajes
	// FIX: boyfriend y gf no están expuestos directamente → usar chars.bf() / chars.gf()
	var bf = chars.bf();
	if (bf != null)
		bf.playAnim('scared', true);
	
	var gf = chars.gf();
	if (gf != null)
		gf.playAnim('scared', true);
	
	// Actualizar timing del próximo rayo
	// FIX: playState no existe en scripts → usar game.curBeat
	lightningStrikeBeat = game.curBeat;
	lightningOffset = FlxG.random.int(8, 24);
	
	// Flash en la cámara para efecto extra
	// FIX: camGame no está expuesto directamente → usar camera.flash()
	//      (los parámetros null y true extra eran inválidos en FlxCamera.flash)
	camera.flash(FlxColor.WHITE, 0.15);
}

// ==========================================
// EVENTOS PERSONALIZADOS
// ==========================================

function onEvent(name, value1, value2, time)
{
	switch(name.toLowerCase())
	{
		case 'lightning strike':
			// Permitir forzar un rayo desde eventos
			triggerLightning();
		
		case 'set lightning chance':
			// Cambiar la probabilidad del rayo
			trace('[Spooky Stage] Evento: cambiar probabilidad de rayo a ' + value1 + '%');
	}
	return false;
}

// ==========================================
// CLEANUP
// ==========================================

function onDestroy()
{
	trace('[Spooky Stage] Limpiando...');
}
