package funkin.states;

import flixel.FlxG;
import flixel.FlxObject;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.gameplay.PlayState;
import funkin.menus.StoryMenuState;
import funkin.menus.FreeplayState;
import funkin.states.LoadingState;
import funkin.data.Conductor;
import funkin.gameplay.objects.character.Character;
import funkin.transitions.StateTransition;
import funkin.scripting.StateScriptHandler;
import funkin.scripting.ScriptHandler;

using StringTools;

/**
* GameOverSubstate: coded from CharacterData, programmable using StateScriptHandler
* AND the character/song scripts already loaded in PlayState.
*
* ── Scripts de estado (assets/states/gameoversubstate/) ──────────────────────
*   Los mismos callbacks de siempre.
*
* ── Scripts de personaje (assets/characters/{char}/scripts/) ─────────────────
* ── Scripts of song   (assets/songs/{song}/scripts/)       ─────────────────
*   Callbacks available (furthermore of the own of the character):
*     onGameOverConfig(cfg)        → modifica la config ANTES de inicializar.
*                                    cfg = { deathChar, deathSound, loopMusic,
*                                            endSound, camFrame, bpm }
*                                    Devuelve el objeto cfg modificado (o nada).
*     onGameOverCreate(substate)   → se llama al final del constructor.
*     onGameOverUpdate(elapsed)    → cada frame.
*     onGameOverBeatHit(beat)      → cada beat.
*     onGameOverRetry()            → the player pressed ACCEPT. Returns true = cancelar.
*     onGameOverBack()             → the player pressed BACK.  Returns true = cancelar.
*     onGameOverDeathAnimEnd()     → animation firstDeath terminada.
*     onGameOverEndConfirm()       → endBullshit iniciado. Retorna true = cancelar.
*     onGameOverDestroy()          → antes de destruir.
*
* Optional fields in the character's JSON:
*   "charDeath":        "bf-dead"              (default)
*   "gameOverSound":    "fnf_loss_sfx"         (default)
*   "gameOverMusic":    "gameplay/gameOver"     (default)
*   "gameOverEnd":      "gameplay/gameOverEnd"  (default)
*   "gameOverBpm":      100                     (default)
*   "gameOverCamFrame": 12                      (default)
*/

class GameOverSubstate extends MusicBeatSubstate
{
	public var bf:Character;
	public var camFollow:FlxObject;
	public var isEnding:Bool = false;

	var _loopMusic    : String;
	var _endSound     : String;
	var _camFrame     : Int;
	var _musicStarted : Bool = false;

	var animationSuffix:String = '';
	public function new(x:Float, y:Float, boyfriend:Character)
	{
		super();

		if (PlayState.instance?.vocals?.playing ?? false)
			PlayState.instance.vocals.stop();

		final cd = boyfriend.characterData;

		// ── Config por defecto desde CharacterData ────────────────────────────
		var cfg:Dynamic = {
			deathChar  : (cd?.charDeath != null && cd.charDeath != '') ? cd.charDeath : 'bf-dead',
			deathSound : cd?.gameOverSound    ?? 'gameplay/gameover/fnf_loss_sfx',
			loopMusic  : cd?.gameOverMusic    ?? 'gameplay/gameOver',
			endSound   : cd?.gameOverEnd      ?? 'gameplay/gameOverEnd',
			camFrame   : cd?.gameOverCamFrame ?? 12,
			bpm        : cd?.gameOverBpm      ?? 100,
			deathSuffix: cd?.deathAnimSuffix ?? '',
		};
		
		animationSuffix = cfg.deathSuffix;

		// ── Hook: char/song scripts pueden sobreescribir la config ───────────
		// Se llama en TODOS los scripts activos (char, song, stage, global).
		// El script puede modificar cfg directamente y/o devolverlo.
		var cfgOverride = ScriptHandler.callOnScriptsReturn('onGameOverConfig', [cfg], null);
		if (cfgOverride != null) cfg = cfgOverride;

		// ── Aplicar config ────────────────────────────────────────────────────
		_loopMusic = cfg.loopMusic;
		_endSound  = cfg.endSound;
		_camFrame  = cfg.camFrame;

		Conductor.songPosition = 0;
		Conductor.changeBPM(cfg.bpm);

		bf = new Character(x, y, cfg.deathChar, true);
		add(bf);

		camFollow = new FlxObject(bf.getGraphicMidpoint().x, bf.getGraphicMidpoint().y, 1, 1);
		add(camFollow);

		FlxG.camera.scroll.set();
		FlxG.camera.target = null;

		FlxG.sound.play(Paths.sound(cfg.deathSound));
		bf.playAnim('firstDeath'+animationSuffix);

		// ── State scripts (assets/states/gameoversubstate/) ──────────────────
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('GameOverSubstate', this, [
			'bf'        => bf,
			'camFollow' => camFollow,
			'isEnding'  => false,
		]);
		StateScriptHandler.callOnScripts('onCreate', [this]);

		// ── Notificar char/song scripts that the substate is listo ───────────
		ScriptHandler.callOnScripts('onGameOverCreate', [this]);

		#if mobileC
		addVirtualPad(NONE, A_B);
		#end
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		StateScriptHandler.fireRaw('onUpdate', [elapsed]);
		ScriptHandler.callOnScripts('onGameOverUpdate', [elapsed]);

		if (controls.ACCEPT && !isEnding)
		{
			var cancel = StateScriptHandler.callOnScripts('onRetry', []);
			if (!cancel) cancel = (ScriptHandler.callOnScriptsReturn('onGameOverRetry', [], false) == true);
			if (!cancel) endBullshit();
		}

		if (controls.BACK)
		{
			var cancel = StateScriptHandler.callOnScripts('onBack', []);
			if (!cancel) cancel = (ScriptHandler.callOnScriptsReturn('onGameOverBack', [], false) == true);
			if (!cancel)
			{
				FlxG.sound.music?.stop();
				if (PlayState.isStoryMode)
					StateTransition.switchState(new StoryMenuState());
				else
					StateTransition.switchState(new FreeplayState());
			}
		}

		if (bf.animation.curAnim?.name == 'firstDeath'+animationSuffix)
		{
			if (bf.animation.curAnim.curFrame == _camFrame)
				FlxG.camera.follow(camFollow, LOCKON, 0.01);

			if (bf.animation.curAnim.finished && !_musicStarted)
			{
				_musicStarted = true;
				StateScriptHandler.fireRaw('onDeathAnimFinished', []);
				ScriptHandler.callOnScripts('onGameOverDeathAnimEnd', []);
				FlxG.sound.playMusic(Paths.music(_loopMusic));
				bf.playAnim('deathLoop'+animationSuffix);
			}
		}

		if (FlxG.sound.music?.playing ?? false)
			Conductor.songPosition = FlxG.sound.music.time;
	}

	override function beatHit()
	{
		super.beatHit();
		StateScriptHandler.fireRaw('onBeatHit', [curBeat]);
		ScriptHandler.callOnScripts('onGameOverBeatHit', [curBeat]);
	}

	public function endBullshit():Void
	{
		if (isEnding) return;
		isEnding = true;

		if (StateScriptHandler.callOnScripts('onEndConfirm', [])) { isEnding = false; return; }
		if (ScriptHandler.callOnScriptsReturn('onGameOverEndConfirm', [], false) == true) { isEnding = false; return; }

		bf.playAnim('deathConfirm'+animationSuffix, true);
		FlxG.sound.music?.stop();
		FlxG.sound.play(Paths.music(_endSound));

		new FlxTimer().start(0.7, function(_)
		{
			FlxG.camera.fade(FlxColor.BLACK, 2, false, function()
			{
				LoadingState.loadAndSwitchState(new PlayState());
			});
		});
	}

	override function destroy()
	{
		ScriptHandler.callOnScripts('onGameOverDestroy', []);
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		super.destroy();
	}
}
