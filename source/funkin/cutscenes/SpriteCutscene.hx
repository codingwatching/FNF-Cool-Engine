package funkin.cutscenes;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.sound.FlxSound;
import haxe.Json;
import mods.ModManager;
import animationdata.FunkinSprite;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * SpriteCutscene v2 — sistema de cutscenes con sprites basado en JSON.
 *
 * ─── Usage from PlayState (automatic via meta.json) ──────────────────────────
 *
 *   meta.json:
 *   {
 *     "introCutscene": "thorns-intro",     → assets/data/cutscenes/thorns-intro.json
 *     "outroCutscene": "thorns-outro"      → assets/data/cutscenes/thorns-outro.json
 *   }
 *
 * ─── Uso desde script ────────────────────────────────────────────────────────
 *
 *   var cut = new SpriteCutscene(game, 'thorns-intro');
 *   cut.play(function() { log("cutscene terminada"); });
 *
 * ─── Resolution of files JSON ─────────────────────────────────────────────
 *
 *   mods/{mod}/data/cutscenes/{key}.json    ← mod override
 *   assets/data/cutscenes/{key}.json        ← base game
 *   mods/{mod}/data/cutscenes/{song}/{key}.json
 *   assets/data/cutscenes/{song}/{key}.json
 *
 * ─── Referencia del formato JSON ─────────────────────────────────────────────
 *   Ver SpriteCutsceneData.hx for the documentación complete of the format.
 */
class SpriteCutscene
{
	// ── config ────────────────────────────────────────────────────────────────
	public var skippable:Bool = true;

	// ── state ─────────────────────────────────────────────────────────────────
	public var playing(default, null):Bool  = false;
	public var finished(default, null):Bool = false;

	// ── privado ───────────────────────────────────────────────────────────────
	var _state:flixel.FlxState;
	var _doc:SpriteCutsceneData.CutsceneDocument;
	var _sprites:Map<String, FlxSprite> = [];
	var _sounds:Map<String, FlxSound>   = [];
	var _onComplete:Null<Void->Void>    = null;
	var _stepIdx:Int   = 0;
	var _blocked:Bool  = false;
	var _skipped:Bool  = false;

	// Seguimiento propio de timers y tweens para cancelarlos sin tocar
	// the globalManager (that mataría timers of audio and otros systems).
	var _timers:Array<FlxTimer>  = [];
	var _tweens:Array<FlxTween>  = [];

	// Seguimiento of camera: sprite to the that the camera sigue opcionalmente.
	var _camTarget:Null<FlxSprite> = null;
	/** Zoom original de FlxG.camera antes de la cutscene, para restaurarlo en reset. */
	var _origCamZoom:Float = 1.0;
	/** Position X original of FlxG.camera before of the cutscene. */
	var _origCamX:Float    = 0.0;
	/** Position and original of FlxG.camera before of the cutscene. */
	var _origCamY:Float    = 0.0;

	// Camera dedicada for the sprites of cutscene — is sitúa above
	// de camHUD para que los sprites tapen el gameplay completamente.
	var _camCutscene:FlxCamera;

	// Bandera que indica si deshabilitamos el follow de FlxG.camera al
	// empezar the cutscene (for that the tweens of scroll no luchen with it).
	var _camFollowDisabled:Bool = false;

	// Log of cameras that this cutscene ocultó, for restaurarlas to the terminar.
	// Map<"hud"|"game"|"countdown", Bool> — guarda la visibilidad ORIGINAL.
	var _hiddenCams:Map<String, Bool>  = [];
	// Save the alpha original of each camera tocada by setCamVisible.
	var _hiddenCamsAlpha:Map<String, Float> = [];

	// Mapa de callbacks registrados por CutsceneBuilder para los pasos 'call' y
	// 'callAsync'. La clave es el id del paso (campo step.id generado por el builder).
	// Permite ejecutar funciones Haxe/HScript arbitrarias dentro de la secuencia.
	var _callbackMap:Map<String, Dynamic> = [];

	// Lista de funciones a llamar cuando la cutscene termine o se salte.
	// Is registran via the paso internal '_registerCleanup'.
	var _cleanupCallbacks:Array<Dynamic> = [];

	// ── constructor ───────────────────────────────────────────────────────────

	/**
	 * @param state  Estado padre (normalmente PlayState.instance)
	 * @param key    Key of the JSON (without extension ni path)
	 * @param song   Song current (for resolve rutas of subcarpeta)
	 */
	public function new(state:flixel.FlxState, key:String, ?song:String)
	{
		_state = state;
		_doc   = _loadDocument(key, song);
		if (_doc != null && _doc.skippable == false) skippable = false;

		_initCamera();
	}

	/**
	 * Crea una SpriteCutscene a partir de un documento ya construido en memoria
	 * (sin necesidad de un JSON). Usado por CutsceneBuilder.
	 * @param callbacks  Map opcional de id→fn para pasos call/callAsync.
	 */
	public static function fromDoc(state:flixel.FlxState,
		doc:SpriteCutsceneData.CutsceneDocument,
		?callbacks:Map<String, Dynamic>):SpriteCutscene
	{
		var sc       = new SpriteCutscene(state, '__noop__');
		sc._doc      = doc;
		sc.skippable = doc.skippable ?? true;
		if (callbacks != null)
			for (k => v in callbacks) sc._callbackMap.set(k, v);
		return sc;
	}

	function _initCamera():Void
	{
		// Create camera dedicada that is adds to the end of the list of cameras
		// → se renderiza encima de camGame y camHUD, tapando el gameplay.
		_camCutscene = new FlxCamera();
		_camCutscene.bgColor = 0x00000000; // transparente

		// FIX flash blanco: el canvas de OpenFL que subyace a cada FlxCamera
		// se inicializa como un bitmap blanco. Flixel lo limpia con bgColor
		// durante its primer draw(), but only if the camera already era visible in
		// ese momento — si la hacemos visible en preUpdate (antes del draw)
		// vemos un destello blanco exactamente 1 frame.
		//
		// Solution: conectarse to postDraw a SOLA VEZ for activar the camera
		// after of that the frame current haya terminado of renderizarse.
		// En el siguiente frame Flixel la limpia con bgColor antes de dibujar,
		// so never is ve the bitmap blanco inicial.
		_camCutscene.visible = false;
		FlxG.cameras.add(_camCutscene, false);

		FlxG.signals.postDraw.addOnce(_onFirstPostDraw);
	}

	/** Active _camCutscene after of the first frame complete for avoid the flash blanco. */
	function _onFirstPostDraw():Void
	{
		if (_camCutscene != null)
			_camCutscene.visible = true;
	}

	/** Inicia la cutscene. `onComplete` se llama cuando termina o se salta. */
	public function play(?onComplete:Void->Void):Void
	{
		if (_doc == null || _doc.steps == null || _doc.steps.length == 0)
		{
			if (onComplete != null) onComplete();
			return;
		}
		_onComplete = onComplete;
		playing     = true;
		finished    = false;
		_stepIdx    = 0;
		// Save the state current of the camera for that cameraReset sepa
		// to what values return.
		_origCamZoom = FlxG.camera.zoom;
		_origCamX    = FlxG.camera.scroll.x;
		_origCamY    = FlxG.camera.scroll.y;
		// FIX camera is bloquea to the terminar: FlxCamera.follow() sigue active
		// durante la cutscene y cada frame lerpa scroll hacia camFollow,
		// peleando con los tweens de cameraPan/cameraZoom. Lo deshabilitamos
		// here and it restauramos in _cleanup() for that the CameraController
		// retome el control limpiamente al volver al gameplay.
		_camFollowDisabled = false;
		var _ps = funkin.gameplay.PlayState.instance;
		if (_ps != null && _ps.cameraController != null)
		{
			FlxG.camera.follow(null); // desconectar follow
			_camFollowDisabled = true;
		}
		// FIX animaciones: congelar los personajes del PlayState mientras
		// dura the cutscene for that no sigan bailando/animándose by its cuenta.
		_setCharactersFrozen(true);
		// Conectar the update of seguimiento of camera
		FlxG.signals.preUpdate.add(_onPreUpdate);
		_nextStep();
	}

	/** Salta la cutscene inmediatamente (limpia todo y llama onComplete). */
	public function skip():Void
	{
		if (!playing || _skipped) return;
		if (!skippable) return;
		_skipped = true;
		_cleanup();
		_finish();
	}

	/**
	 * Registra a function of callback for the pasos 'call' or 'callAsync'.
	 * Callr before of play(). CutsceneBuilder it hace automatically.
	 * param id  ID del paso (generado por CutsceneBuilder o puesto a mano en el JSON)
	 * param fn  Function to ejecutar.
	 *            For 'call':      fn()  — without parameters
	 *            Para 'callAsync': fn(done:Void->Void)  — debe llamar done() para continuar
	 */
	public function registerCallback(id:String, fn:Dynamic):Void
	{
		_callbackMap.set(id, fn);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Execution of pasos
	// ═════════════════════════════════════════════════════════════════════════

	function _nextStep():Void
	{
		if (_skipped || _doc == null) return;

		if (_stepIdx >= _doc.steps.length)
		{
			_finish();
			return;
		}

		var step = _doc.steps[_stepIdx];
		_stepIdx++;
		_executeStep(step);
	}

	function _executeStep(step:SpriteCutsceneData.CutsceneStep):Void
	{
		switch (step.action)
		{
			case 'add':
				_doAdd(step);

			case 'remove':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) _state.remove(spr);
				_nextStep();

			case 'setAlpha':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) spr.alpha = step.alpha ?? 1.0;
				_nextStep();

			case 'setColor':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) spr.color = _parseColor(step.color ?? 'WHITE');
				_nextStep();

			case 'setVisible':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) spr.visible = step.visible ?? true;
				_nextStep();

			case 'setPosition':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) { spr.x = step.x ?? spr.x; spr.y = step.y ?? spr.y; }
				_nextStep();

			case 'screenCenter':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) _screenCenter(spr, step.axis ?? 'xy');
				_nextStep();

			case 'wait':
				_blocked = true;
				var _t = new FlxTimer();
				_timers.push(_t);
				_t.start(step.time ?? 0.1, function(_) {
					_timers.remove(_t);
					_blocked = false;
					_nextStep();
				});

			case 'fadeTimer':
				_doFadeTimer(step);

			case 'tween':
				_doTween(step);

			case 'playAnim':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null && spr.animation != null)
					spr.animation.play(step.anim ?? '', step.force ?? false);
				_nextStep();

			// ── stageAnim ─────────────────────────────────────────────────────
			// Controla personajes YA EXISTENTES en el PlayState (bf, dad, gf, o
			// cualquier nombre of the stage) without necesidad of add sprites nuevos.
			// JSON: { "action": "stageAnim", "sprite": "bf", "anim": "hey", "force": true }
			// Names valid for "sprite":
			//   "bf" / "boyfriend"  → PlayState.boyfriend
			//   "dad" / "opponent"  → PlayState.dad
			//   "gf" / "girlfriend" → PlayState.gf
			case 'stageAnim':
				_doStageAnim(step);

			case 'playSound':
				_doPlaySound(step);

			case 'waitSound':
				_doWaitSound(step);

			case 'cameraFade':
				_doCameraFade(step);

			case 'cameraFlash':
				var col = _parseColor(step.color ?? 'WHITE');
				var dur = step.duration ?? 0.5;
				if (step.async ?? false)
				{
					FlxG.camera.flash(col, dur);
					_nextStep();
				}
				else
				{
					_blocked = true;
					FlxG.camera.flash(col, dur, function() { _blocked = false; _nextStep(); });
				}

			case 'cameraShake':
				FlxG.camera.shake(step.intensity ?? 0.03, step.duration ?? 0.2);
				_nextStep();

			// ── cameraZoom ────────────────────────────────────────────────────────
			// Tweenea the zoom of the camera of the gameplay (FlxG.camera).
			// JSON: { "action":"cameraZoom", "zoom":1.3, "duration":0.5, "ease":"quadOut", "async":true }
			case 'cameraZoom':
				_doCameraZoom(step);

			// ── cameraMove ────────────────────────────────────────────────────────
			// Salta the camera to (camX, camY) instantly (without tween).
			// JSON: { "action":"cameraMove", "camX":760, "camY":450 }
			case 'cameraMove':
				// FIX: move the scroll, no the position of screen
				if (step.camX != null) FlxG.camera.scroll.x = step.camX;
				if (step.camY != null) FlxG.camera.scroll.y = step.camY;
				_nextStep();

			// ── cameraPan ─────────────────────────────────────────────────────────
			// Tween of position of the camera towards (camX, camY).
			// JSON: { "action":"cameraPan", "camX":760, "camY":450, "duration":1.0, "ease":"sineInOut", "async":true }
			case 'cameraPan':
				_doCameraPan(step);

			// ── cameraTween ───────────────────────────────────────────────────────
			// Tween libre sobre propiedades de FlxG.camera (zoom, x, y).
			// JSON: { "action":"cameraTween", "camProps":{"zoom":1.2,"x":400}, "duration":0.8, "ease":"quadOut" }
			case 'cameraTween':
				_doCameraTween(step);

			// ── cameraReset ───────────────────────────────────────────────────────
			// Restaura the zoom and the position that tenía the camera before of the cutscene.
			// JSON: { "action":"cameraReset", "duration":0.5, "ease":"quadOut", "async":true }
			case 'cameraReset':
				_doCameraReset(step);

			// ── cameraTarget ──────────────────────────────────────────────────────
			// Centra the camera in a sprite (of the cutscene or of the stage) until that is
			// cancele. The camera sigue to the sprite in each frame from _camTarget.
			// JSON: { "action":"cameraTarget", "camTarget":"senpaiEvil" }
			// JSON: { "action":"cameraTarget", "camTarget":null }   ← dejar de seguir
			case 'cameraTarget':
				// FIX: renamed from "target" to "camTarget" in SpriteCutsceneData
				// to avoid collision with the fadeTimer "target:Float" field.
				var targetId:Null<String> = (step : Dynamic).camTarget;
				if (targetId == null || targetId == '' || targetId == 'null')
				{
					_camTarget = null;
				}
				else
				{
					var t = _sprites.get(targetId);
					if (t == null) t = _resolveStageChar(targetId);
					_camTarget = t;
					// Centrar inmediatamente
					if (_camTarget != null)
						FlxG.camera.focusOn(_camTarget.getMidpoint());
				}
				_nextStep();

			// ── setCamVisible ──────────────────────────────────────────────────────
			// Muestra u oculta a camera of the PlayState with fade suave of alpha.
			// JSON: { "action": "setCamVisible", "cam": "hud", "visible": false }
			//       { "action": "setCamVisible", "cam": "hud", "visible": false, "duration": 0.4, "async": true }
			// Valores para "cam": "hud" | "game" | "countdown"
			// duration (default 0.3s), ease, async igual que otros tweens.
			// To the terminar/saltar the cutscene is restauran alpha and visible automatically.
			case 'setCamVisible':
				_doSetCamVisible(step);

			// ── call ───────────────────────────────────────────────────────────────
			// Ejecuta a function registrada with registerCallback() without bloquear.
			// JSON / builder: { action:'call', id:'myFn' }
			// The function is call without parameters: fn()
			case 'call':
				var cbId:String = step.id ?? '';
				var cb = _callbackMap.get(cbId);
				if (cb != null) try { cb(); } catch (e:Dynamic) trace('[SpriteCutscene] call error: $e');
				_nextStep();

			// ── callAsync ──────────────────────────────────────────────────────────
			// Ejecuta a function that receives a callback `done:Void->Void`.
			// La cutscene se bloquea hasta que el script llame a done().
			// JSON / builder: { action:'callAsync', id:'myFn' }
			// The function receives done: fn(done) { ...; done(); }
			case 'callAsync':
				var asyncId:String = step.id ?? '';
				var asyncCb = _callbackMap.get(asyncId);
				if (asyncCb == null) { _nextStep(); return; }
				_blocked = true;
				try
				{
					asyncCb(function() {
						if (_skipped) return;
						_blocked = false;
						_nextStep();
					});
				}
				catch (e:Dynamic)
				{
					trace('[SpriteCutscene] callAsync error: $e');
					_blocked = false;
					_nextStep();
				}

			// ── waitBeat ───────────────────────────────────────────────────────────
			// Bloquea la cutscene hasta que Conductor llega al beat indicado.
			// If the beat already passed, continúa inmediatamente.
			// JSON / builder: { action:'waitBeat', beat:8 }
			case 'waitBeat':
				var targetBeat:Int = Std.int((step : Dynamic).beat ?? 0);
				// Read curBeat via Conductor to avoid needing @:privateAccess in MusicBeatState.
				var getCurrentBeat = function():Int
					return Std.int(funkin.data.Conductor.getBeatAtTime(funkin.data.Conductor.songPosition));
				if (getCurrentBeat() >= targetBeat) { _nextStep(); return; }
				_blocked = true;
				var _bt = new FlxTimer();
				_timers.push(_bt);
				_bt.start(0.016, function(t:FlxTimer) {
					if (_skipped) return;
					if (getCurrentBeat() >= targetBeat) {
						_timers.remove(t); t.cancel();
						_blocked = false;
						_nextStep();
					} else {
						t.reset(0.016);
					}
				});

			// ── waitStep ───────────────────────────────────────────────────────────
			// Bloquea hasta que Conductor llega al step indicado.
			// JSON / builder: { action:'waitStep', step:32 }
			case 'waitStep':
				var targetStep:Int = Std.int((step : Dynamic).step ?? 0);
				var getCurrentStep = function():Int
					return Std.int(funkin.data.Conductor.getStepAtTime(funkin.data.Conductor.songPosition));
				if (getCurrentStep() >= targetStep) { _nextStep(); return; }
				_blocked = true;
				var _st = new FlxTimer();
				_timers.push(_st);
				_st.start(0.016, function(t:FlxTimer) {
					if (_skipped) return;
					if (getCurrentStep() >= targetStep) {
						_timers.remove(t); t.cancel();
						_blocked = false;
						_nextStep();
					} else {
						t.reset(0.016);
					}
				});

			// ── _registerCleanup (interno, generado por CutsceneBuilder.onCleanup) ──
			// Registra a function for callrla when the cutscene termine or is salte.
			case '_registerCleanup':
				var cleanId:String = step.id ?? '';
				var cleanFn = _callbackMap.get(cleanId);
				if (cleanFn != null) _cleanupCallbacks.push(cleanFn);
				_nextStep();

			// ── subtitle ──────────────────────────────────────────────────────────
			// Muestra a subtitle. no bloquea the cutscene (async).
			// JSON: { "action": "subtitle", "text": "Hello", "duration": 3.0,
			//         "size": 28, "color": "0xFFFF00", "bgAlpha": 0.7,
			//         "align": "center", "bold": true, "font": "vcr.ttf",
			//         "y": 620, "fadeIn": 0.2, "fadeOut": 0.3 }
			case 'subtitle':
				final _sd:Dynamic = step;
				final _subText = _sd.text != null ? Std.string(_sd.text) : '';
				if (_subText != '')
				{
					final _subDur = _sd.duration != null ? _sd.duration : 3.0;
					// Construir opts solo con campos que existan en el paso
					var _subOpts:Dynamic = null;
					inline function _hasF(f:String) return Reflect.hasField(_sd, f) && Reflect.field(_sd, f) != null;
					if (_hasF('size') || _hasF('color') || _hasF('bgColor') || _hasF('bgAlpha')
					 || _hasF('align') || _hasF('bold')  || _hasF('font')    || _hasF('y')
					 || _hasF('padX')  || _hasF('padY')  || _hasF('fadeIn')  || _hasF('fadeOut'))
					{
						_subOpts = {};
						if (_hasF('size'))    _subOpts.size    = _sd.size;
						if (_hasF('bgAlpha')) _subOpts.bgAlpha = _sd.bgAlpha;
						if (_hasF('align'))   _subOpts.align   = _sd.align;
						if (_hasF('bold'))    _subOpts.bold    = _sd.bold;
						if (_hasF('font'))    _subOpts.font    = _sd.font;
						if (_hasF('padX'))    _subOpts.padX    = _sd.padX;
						if (_hasF('padY'))    _subOpts.padY    = _sd.padY;
						if (_hasF('fadeIn'))  _subOpts.fadeIn  = _sd.fadeIn;
						if (_hasF('fadeOut')) _subOpts.fadeOut = _sd.fadeOut;
						// color y bgColor como Int (pueden venir como "0xFFFF00" o int)
						if (_hasF('color'))
							_subOpts.color = Std.parseInt(Std.string(_sd.color)) ?? _sd.color;
						if (_hasF('bgColor'))
							_subOpts.bgColor = Std.parseInt(Std.string(_sd.bgColor)) ?? _sd.bgColor;
						// y puede reutilizar el campo y del step (Float)
						if (_hasF('y')) _subOpts.y = _sd.y;
					}
					funkin.ui.SubtitleManager.instance.show(_subText, _subDur, _subOpts);
				}
				_nextStep();

			// ── subtitleHide ──────────────────────────────────────────────────────
			// Hides the subtitle current.
			// JSON: { "action": "subtitleHide" }
			//       { "action": "subtitleHide", "instant": true }
			case 'subtitleHide', 'subtitle hide':
				final _sdH:Dynamic = step;
				funkin.ui.SubtitleManager.instance.hide(_sdH.instant == true);
				_nextStep();

			// ── subtitleClear ─────────────────────────────────────────────────────
			// Hides the subtitle and empty the cola.
			// JSON: { "action": "subtitleClear" }
			case 'subtitleClear', 'subtitle clear':
				funkin.ui.SubtitleManager.instance.clear();
				_nextStep();

			// ── subtitleStyle ─────────────────────────────────────────────────────
			// Changes the estilo global for futuros subtitles.
			// JSON: { "action": "subtitleStyle", "size": 28, "color": "0xFFFFFF",
			//         "bgAlpha": 0.6, "align": "center", "bold": true }
			case 'subtitleStyle', 'subtitle style':
				final _sdS:Dynamic = step;
				final _styleOpts:Dynamic = {};
				inline function _cpF(f:String) {
					if (Reflect.hasField(_sdS, f) && Reflect.field(_sdS, f) != null)
						Reflect.setField(_styleOpts, f, Reflect.field(_sdS, f));
				}
				_cpF('size'); _cpF('color'); _cpF('bgColor'); _cpF('bgAlpha');
				_cpF('align'); _cpF('bold'); _cpF('font'); _cpF('y');
				_cpF('padX'); _cpF('padY'); _cpF('fadeIn'); _cpF('fadeOut');
				funkin.ui.SubtitleManager.instance.setStyle(_styleOpts);
				_nextStep();

			// ── subtitleResetStyle ────────────────────────────────────────────────
			// Restaura el estilo global a los defaults.
			// JSON: { "action": "subtitleResetStyle" }
			case 'subtitleResetStyle', 'subtitle reset style':
				funkin.ui.SubtitleManager.instance.resetStyle();
				_nextStep();

			case 'end':
				_cleanup();
				_finish();

			default:
				trace('[SpriteCutscene] Action desconocida: "${step.action}"');
				_nextStep();
		}
	}

	// ── add ───────────────────────────────────────────────────────────────────

	function _doAdd(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var id = step.sprite ?? '';
		var spr = _sprites.get(id);

		// Create the sprite if no exists still
		if (spr == null)
		{
			spr = _createSprite(id);
			if (spr == null) { _nextStep(); return; }
			_sprites.set(id, spr);
		}

		if (step.alpha != null) spr.alpha = step.alpha;
		// Asignar the camera of cutscene for that the sprite is renderice
		// por encima del HUD y el gameplay.
		spr.cameras = [_camCutscene];
		_state.add(spr);
		_nextStep();
	}

	function _createSprite(id:String):Null<FlxSprite>
	{
		if (_doc.sprites == null) return null;
		var data:SpriteCutsceneData.CutsceneSpriteData = Reflect.field(_doc.sprites, id);
		if (data == null)
		{
			trace('[SpriteCutscene] Sprite "$id" no encontrado en "sprites".');
			return null;
		}

		var spr:FlxSprite;
		var sf = data.scrollFactor ?? 0.0;

		switch (data.type ?? 'rect')
		{
			// ── Rectangle solid ─────────────────────────────────────────────
			case 'rect':
				spr = new FlxSprite();
				var w = Std.int((data.width  ?? 1.0) * FlxG.width);
				var h = Std.int((data.height ?? 1.0) * FlxG.height);
				spr.makeGraphic(w, h, _parseColor(data.color ?? 'BLACK'));
				spr.scrollFactor.set(sf, sf);

			// ── Image static (images/) ──────────────────────────────────────
			case 'image':
				var imgSpr = new FunkinSprite();
				var key = data.image ?? id;
				var g = Paths.getGraphic(key);
				if (g != null) imgSpr.loadGraphic(g);
				else imgSpr.makeGraphic(150, 150, 0x00000000);
				imgSpr.scrollFactor.set(sf, sf);
				spr = imgSpr;

			// ── Personaje (characters/images/) ────────────────────────────────
			//    FunkinSprite.loadCharacterSparrow detecta automatically:
			//    Multi-Animate (.sheets) → Animate folder → Sparrow → Packer
			case 'character':
				var charSpr = new FunkinSprite();
				charSpr.scrollFactor.set(sf, sf);
				charSpr.loadCharacterSparrow(data.image ?? id);
				_addAnims(charSpr, data);
				spr = charSpr;

			// ── Stage sprite (stages/) ────────────────────────────────────────
			case 'stage':
				var stageSpr = new FunkinSprite();
				stageSpr.scrollFactor.set(sf, sf);
				stageSpr.loadStageSparrow(data.image ?? id);
				_addAnims(stageSpr, data);
				spr = stageSpr;

			// ── Atlas generic (images/) — auto-detecta Sparrow/Packer/Animate ─
			//    FunkinSprite.loadAsset detecta by extension XML/TXT/Animation.json
			case 'atlas', 'sparrow', 'packer', 'animate', 'flxanimate', 'auto':
				var atlasSpr = new FunkinSprite();
				atlasSpr.scrollFactor.set(sf, sf);

				var pathList:Array<String> = data.paths;
				if (pathList != null && pathList.length > 1)
					// Explicit multi-atlas (multiple PNG+XML or Animate folders)
					atlasSpr.loadMultiAnimateAtlas(pathList);
				else if (pathList != null && pathList.length == 1)
					atlasSpr.loadAsset(pathList[0]);
				else
					atlasSpr.loadAsset(data.image ?? id);

				_addAnims(atlasSpr, data);
				spr = atlasSpr;

			// ── Placeholder visible para tipos desconocidos ───────────────────
			default:
				trace('[SpriteCutscene] Tipo desconocido "${data.type}" para sprite "$id" — usando placeholder.');
				spr = new FlxSprite();
				spr.makeGraphic(150, 150, 0x44FF0000);
				spr.scrollFactor.set(sf, sf);
		}

		// Propiedades comunes
		if (data.x != null)      spr.x = data.x;
		if (data.y != null)      spr.y = data.y;
		if (data.alpha != null)  spr.alpha = data.alpha;
		if (data.angle != null)  spr.angle = data.angle;
		if (data.flipX != null)  spr.flipX = data.flipX;
		if (data.flipY != null)  spr.flipY = data.flipY;
		spr.antialiasing = data.antialiasing ?? true;

		if (data.scale != null)
		{
			spr.setGraphicSize(Std.int(spr.width * data.scale));
			spr.updateHitbox();
		}
		else if (data.scaleX != null || data.scaleY != null)
		{
			spr.scale.set(data.scaleX ?? 1.0, data.scaleY ?? 1.0);
			spr.updateHitbox();
		}

		if (data.center == true) _screenCenter(spr, 'xy');

		return spr;
	}

	// ── _addAnims: registra animaciones en un FunkinSprite ───────────────────
	// FunkinSprite.addAnim() detecta automatically if the sprite is Animate
	// (frame labels) o Sparrow (addByPrefix/addByIndices).

	function _addAnims(spr:FunkinSprite, data:SpriteCutsceneData.CutsceneSpriteData):Void
	{
		if (data.animations == null) return;
		var anims:Array<SpriteCutsceneData.CutsceneSpriteAnim> = cast data.animations;
		for (anim in anims)
			spr.addAnim(anim.name, anim.prefix, anim.fps ?? 24, anim.loop ?? false, anim.indices);
	}

	// ── fadeTimer ─────────────────────────────────────────────────────────────

	function _doFadeTimer(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var spr = _sprites.get(step.sprite ?? '');
		if (spr == null) { _nextStep(); return; }

		var target   = step.target   ?? 0.0;
		var stepAmt  = step.step     ?? 0.15;
		var interval = step.interval ?? 0.3;
		_blocked = true;

		var _ft = new FlxTimer();
		_timers.push(_ft);
		_ft.start(interval, function(tmr:FlxTimer)
		{
			if (_skipped) return;

			if (target < spr.alpha)
				spr.alpha = Math.max(target, spr.alpha - stepAmt);
			else
				spr.alpha = Math.min(target, spr.alpha + stepAmt);

			if (Math.abs(spr.alpha - target) < 0.001)
			{
				spr.alpha = target;
				_blocked  = false;
				_timers.remove(tmr);
				_nextStep();
			}
			else
			{
				tmr.reset(interval);
			}
		});
	}

	// ── tween ─────────────────────────────────────────────────────────────────

	function _doTween(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var spr = _sprites.get(step.sprite ?? '');
		if (spr == null) { _nextStep(); return; }

		var dur  = step.duration ?? 1.0;
		var ease = _parseEase(step.ease);

		if (step.async ?? false)
		{
			var tw = FlxTween.tween(spr, step.props ?? {}, dur, { ease: ease ?? FlxEase.linear });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(spr, step.props ?? {}, dur, {
				ease:       ease ?? FlxEase.linear,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	// ── stageAnim ─────────────────────────────────────────────────────────────

	/**
	 * Busca un personaje existente en el PlayState por nombre y le lanza la
	 * animation indicada. This allows do cutscenes usando directamente
	 * the characters of the stage without add sprites extra.
	 *
	 * Nombres reconocidos para el campo "sprite":
	 *   "bf" | "boyfriend"  → PlayState.boyfriend
	 *   "dad" | "opponent"  → PlayState.dad
	 *   "gf" | "girlfriend" → PlayState.gf
	 *
	 * If "wait" is true, the cutscene is bloquea until that the animation termine.
	 * JSON: { "action": "stageAnim", "sprite": "bf", "anim": "hey",
	 *         "force": true, "wait": false }
	 */
	function _doStageAnim(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var char = _resolveStageChar(step.sprite ?? '');
		if (char == null)
		{
			trace('[SpriteCutscene] stageAnim: personaje "${step.sprite}" no encontrado.');
			_nextStep();
			return;
		}

		var animName = step.anim ?? '';
		var force    = step.force ?? true;

		// Usar playAnim if is a Character (FNF), animation.play if is generic
		if (Std.isOfType(char, funkin.gameplay.objects.character.Character))
			cast(char, funkin.gameplay.objects.character.Character).playAnim(animName, force);
		else if (char.animation != null)
			char.animation.play(animName, force);

		// If wait=true wait to that the animation termine before of continuar
		if ((step : Dynamic).wait == true && char.animation != null)
		{
			_blocked = true;
			var _wt = new FlxTimer();
			_timers.push(_wt);
			// Poll cada frame (0.016s) hasta que la anim acabe
			_wt.start(0.016, function(t:FlxTimer)
			{
				if (_skipped) return;
				var anim = char.animation;
				// The animation acabó if finished=true or already no is the same
				if (anim == null || anim.curAnim == null || anim.curAnim.finished)
				{
					_timers.remove(t);
					t.cancel();
					_blocked = false;
					_nextStep();
				}
				else
				{
					t.reset(0.016);
				}
			});
		}
		else
		{
			_nextStep();
		}
	}

	/**
	 * Resuelve el nombre de personaje a un FlxSprite del PlayState activo.
	 * Devuelve null si no hay PlayState activo o el nombre no coincide.
	 */
	function _resolveStageChar(name:String):Null<FlxSprite>
	{
		var ps = funkin.gameplay.PlayState.instance;
		if (ps == null) return null;

		return switch (name.toLowerCase())
		{
			case 'bf', 'boyfriend':           ps.boyfriend;
			case 'dad', 'opponent', 'enemy':  ps.dad;
			case 'gf', 'girlfriend':          ps.gf;
			// Fallback: search in sprites of cutscene by if alguien reutilizó the name
			default:
				var found = _sprites.get(name);
				if (found != null) found else null;
		};
	}

	// ── playSound ─────────────────────────────────────────────────────────────

	function _doPlaySound(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var key     = step.key ?? '';
		var vol     = step.volume ?? 1.0;
		var id      = step.id;
		var stepDyn = (step : Dynamic);

		// ── Resolution of ruta ────────────────────────────────────────────────
		// Por defecto usa Paths.sound().
		// "music": true  → Paths.music()       (carpeta music/ del mod)
		// "stage": true  → Paths.soundStage()  (carpeta stages/<curStage>/... del mod)
		//                  Perfecto para sonidos que viven en phillyStreets/sounds/
		//                  o phillyStreets/music/ sin copiarlos a la carpeta global.
		//
		// Ejemplos en JSON:
		//   { "action":"playSound", "key":"Darnell_Lighter", "stage":true }
		//      → stages/phillyStreets/sounds/Darnell_Lighter.ogg
		//   { "action":"playSound", "key":"darnellCanCutscene", "music":true, "stage":true }
		//      → stages/phillyStreets/music/darnellCanCutscene.ogg
		var isMusic:Bool = stepDyn.music == true;
		var isStage:Bool = stepDyn.stage == true;

		var path:String;
		if (isStage)
		{
			// soundStage espera "stageName/subpath/key" — anteponemos el stage actual
			// and the subcarpeta according to if is music or sound.
			var curStage = funkin.gameplay.PlayState.curStage ?? Paths.currentStage;
			var sub      = isMusic ? 'music' : 'sounds';
			path = Paths.soundStage('$curStage/$sub/$key');
		}
		else if (isMusic)
		{
			path = Paths.music(key);
		}
		else
		{
			path = Paths.sound(key);
		}

		var snd = FlxG.sound.play(path, vol);

		if (id != null && snd != null)
			_sounds.set(id, snd);

		_nextStep(); // playSound never bloquea by itself only — usar waitSound
	}

	// ── waitSound ─────────────────────────────────────────────────────────────

	function _doWaitSound(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var id = step.id ?? '';
		var snd = _sounds.get(id);

		if (snd == null) { _nextStep(); return; }
		if (!snd.playing) { _nextStep(); return; }

		_blocked = true;
		var prevComplete = snd.onComplete;
		snd.onComplete = function()
		{
			if (prevComplete != null) prevComplete();
			_blocked = false;
			_nextStep();
		};
	}

	// ── cameraFade ────────────────────────────────────────────────────────────

	function _doCameraFade(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var col    = _parseColor(step.color ?? 'BLACK');
		var dur    = step.duration ?? 0.5;
		var fadeIn = step.fadeIn   ?? false;

		if (step.async ?? false)
		{
			FlxG.camera.fade(col, dur, fadeIn);
			_nextStep();
		}
		else
		{
			_blocked = true;
			FlxG.camera.fade(col, dur, fadeIn, function()
			{
				_blocked = false;
				_nextStep();
			});
		}
	}

	// ─── helpers ──────────────────────────────────────────────────────────────

	function _screenCenter(spr:FlxSprite, axis:String):Void
	{
		switch (axis.toLowerCase())
		{
			case 'x':  spr.x = (FlxG.width  - spr.width)  * 0.5;
			case 'y':  spr.y = (FlxG.height - spr.height) * 0.5;
			default:   spr.screenCenter();
		}
	}

	static function _parseColor(s:String):FlxColor
	{
		if (s == null) return FlxColor.BLACK;
		return switch (s.toUpperCase())
		{
			case 'BLACK':       FlxColor.BLACK;
			case 'WHITE':       FlxColor.WHITE;
			case 'RED':         FlxColor.RED;
			case 'GREEN':       FlxColor.GREEN;
			case 'BLUE':        FlxColor.BLUE;
			case 'YELLOW':      FlxColor.YELLOW;
			case 'CYAN':        FlxColor.CYAN;
			case 'MAGENTA':     FlxColor.MAGENTA;
			case 'TRANSPARENT': FlxColor.TRANSPARENT;
			default:
				try   { return FlxColor.fromString(s); }
				catch (_) { return FlxColor.BLACK; }
		};
	}

	static function _parseEase(s:Null<String>):Null<Float->Float>
	{
		if (s == null) return null;
		return switch (s.toLowerCase())
		{
			case 'linear':       FlxEase.linear;
			case 'quadin':       FlxEase.quadIn;
			case 'quadout':      FlxEase.quadOut;
			case 'quadinout':    FlxEase.quadInOut;
			case 'sinein':       FlxEase.sineIn;
			case 'sineout':      FlxEase.sineOut;
			case 'sineinout':    FlxEase.sineInOut;
			case 'cubein':       FlxEase.cubeIn;
			case 'cubeout':      FlxEase.cubeOut;
			case 'cubeinout':    FlxEase.cubeInOut;
			case 'elasticin':    FlxEase.elasticIn;
			case 'elasticout':   FlxEase.elasticOut;
			case 'bouncein':     FlxEase.bounceIn;
			case 'bounceout':    FlxEase.bounceOut;
			case 'backin':       FlxEase.backIn;
			case 'backout':      FlxEase.backOut;
			default:             null;
		};
	}

	// ── camera helpers ──────────────────────────────────────────────────────────

	function _doCameraZoom(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var targetZoom = step.zoom ?? 1.0;
		var dur  = step.duration ?? 0.5;
		var ease = _parseEase(step.ease);

		if (step.async ?? false)
		{
			var tw = FlxTween.tween(FlxG.camera, {zoom: targetZoom}, dur,
				{ ease: ease ?? FlxEase.quadOut });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(FlxG.camera, {zoom: targetZoom}, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	function _doCameraPan(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var dur  = step.duration ?? 0.6;
		var ease = _parseEase(step.ease);

		// FIX: cameraPan moves the SCROLL (what parte of the mundo is ve),
		// no camera.x/and (that are position in screen — always 0,0 in FNF).
		// FlxG.camera.scroll es un FlxPoint con x/y tweeneable directamente.
		var props:Dynamic = {};
		if (step.camX != null) Reflect.setField(props, 'x', step.camX);
		if (step.camY != null) Reflect.setField(props, 'y', step.camY);

		if (step.async ?? false)
		{
			var tw = FlxTween.tween(FlxG.camera.scroll, props, dur,
				{ ease: ease ?? FlxEase.sineInOut });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(FlxG.camera.scroll, props, dur,
			{
				ease: ease ?? FlxEase.sineInOut,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	function _doCameraTween(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var props = step.camProps ?? {};
		var dur   = step.duration ?? 0.5;
		var ease  = _parseEase(step.ease);

		if (step.async ?? false)
		{
			var tw = FlxTween.tween(FlxG.camera, props, dur,
				{ ease: ease ?? FlxEase.quadOut });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(FlxG.camera, props, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	function _doCameraReset(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var dur  = step.duration ?? 0.0;
		var ease = _parseEase(step.ease);

		var scrollProps:Dynamic = { x: _origCamX, y: _origCamY };

		if (dur <= 0)
		{
			FlxG.camera.zoom     = _origCamZoom;
			FlxG.camera.scroll.x = _origCamX;
			FlxG.camera.scroll.y = _origCamY;
			_nextStep();
		}
		else if (step.async ?? false)
		{
			FlxTween.tween(FlxG.camera,        { zoom: _origCamZoom }, dur, { ease: ease ?? FlxEase.quadOut });
			var tw = FlxTween.tween(FlxG.camera.scroll, scrollProps,   dur, { ease: ease ?? FlxEase.quadOut });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			FlxTween.tween(FlxG.camera, { zoom: _origCamZoom }, dur, { ease: ease ?? FlxEase.quadOut });
			var tw = FlxTween.tween(FlxG.camera.scroll, scrollProps, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	// ── setCamVisible ─────────────────────────────────────────────────────────

	/**
	 * Muestra u oculta a camera of the PlayState with a fade suave of alpha.
	 *
	 * JSON:
	 *   { "action": "setCamVisible", "cam": "hud", "visible": false }
	 *   { "action": "setCamVisible", "cam": "hud", "visible": false, "duration": 0.4, "ease": "quadOut" }
	 *   { "action": "setCamVisible", "cam": "hud", "visible": false, "duration": 0.4, "async": true }
	 *
	 * - "duration" controla how much dura the fade (default: 0.3s).
	 *   With duration=0 the cambio is instant (without tween).
	 * - "async": true → no bloquea la cadena de pasos (el fade corre en paralelo).
	 * - The visibilidad and alpha originales is restauran automatically in cleanup.
	 *
	 * @param step  Paso completo (se leen cam, visible, duration, ease, async)
	 */
	function _doSetCamVisible(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var ps = funkin.gameplay.PlayState.instance;
		if (ps == null) { _nextStep(); return; }

		var camName:String = (step : Dynamic).cam ?? 'hud';
		var key = camName.toLowerCase().replace('cam', '');

		var cam:FlxCamera = switch (key)
		{
			case 'hud':        ps.camHUD;
			case 'game':       ps.camGame;
			case 'countdown':  ps.camCountdown;
			default:           null;
		};

		if (cam == null) { _nextStep(); return; }

		// Save alpha and visible originales the first vez that tocamos this camera.
		if (!_hiddenCamsAlpha.exists(key))
			_hiddenCamsAlpha.set(key, cam.alpha);
		if (!_hiddenCams.exists(key))
			_hiddenCams.set(key, cam.visible);

		var makeVisible:Bool = step.visible ?? true;
		var dur:Float        = step.duration ?? 0.3;
		var ease             = _parseEase(step.ease);
		var isAsync:Bool     = step.async ?? false;
		var targetAlpha:Float = makeVisible ? 1.0 : 0.0;

		// If vamos to mostrar the camera, activar visible before of the fade
		// para que el tween sea visible desde el primer frame.
		if (makeVisible) cam.visible = true;

		if (dur <= 0)
		{
			// Instant: without tween
			cam.alpha   = targetAlpha;
			if (!makeVisible) cam.visible = false;
			_nextStep();
		}
		else if (isAsync)
		{
			var tw = FlxTween.tween(cam, { alpha: targetAlpha }, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(_)
				{
					// Al terminar el fade-out, ocultar visible para
					// so the camera doesn't consume fill-rect every frame.
					if (!makeVisible) cam.visible = false;
				}
			});
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(cam, { alpha: targetAlpha }, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(t)
				{
					_tweens.remove(t);
					if (!makeVisible) cam.visible = false;
					_blocked = false;
					_nextStep();
				}
			});
			_tweens.push(tw);
		}
	}

	// ── cleanup / finish ──────────────────────────────────────────────────────

	/** Tick of seguimiento of camera — is conecta to FlxG.signals.preUpdate. */
	function _onPreUpdate():Void
	{
		// Sincronizar _camCutscene con FlxG.camera en cada frame para que
		// los sprites con scrollFactor=1 aparezcan correctamente sobre el stage.
		if (_camCutscene != null)
		{
			_camCutscene.scroll.copyFrom(FlxG.camera.scroll);
			_camCutscene.zoom = FlxG.camera.zoom;
		}

		if (_camTarget != null && playing)
			FlxG.camera.focusOn(_camTarget.getMidpoint());
	}

	/**
	 * Congela/descongela los personajes del PlayState durante la cutscene.
	 * Pausa/reanuda sus animaciones para que no sigan bailando mientras
	 * la cutscene reproduce sus propias animaciones con stageAnim.
	 */
	function _setCharactersFrozen(freeze:Bool):Void
	{
		var ps = funkin.gameplay.PlayState.instance;
		if (ps == null) return;
		var chars:Array<Dynamic> = [];
		if (ps.boyfriend != null) chars.push(ps.boyfriend);
		if (ps.dad       != null) chars.push(ps.dad);
		if (ps.gf        != null) chars.push(ps.gf);
		for (c in chars)
		{
			if (c == null) continue;
			try
			{
				// FunkinSprite / FlxAnimate: pause/reanudar the animation
				if (freeze)
				{
					if (c.animation != null && c.animation.curAnim != null)
						c.animation.curAnim.paused = true;
					// FlxAnimate usa anim.pause() / anim.resume()
					if (Reflect.hasField(c, 'anim') && c.anim != null)
						c.anim.pause();
				}
				else
				{
					if (c.animation != null && c.animation.curAnim != null)
						c.animation.curAnim.paused = false;
					if (Reflect.hasField(c, 'anim') && c.anim != null)
						c.anim.resume();
				}
			}
			catch (_:Dynamic) {}
		}
	}

	/**
	 * Forces to bf, dad and gf to volver to its animation idle/dance after of
	 * que la cutscene termine.
	 *
	 * ESTRATEGIA para evitar el "snap" brusco al idle:
	 *  • Animations no looping (intro2, laughCutscene…):  avanzar to the last
	 *    frame. Character.update() verá animFinished=true in the next tick
	 *    and callrá to dance() by itself only — the transition queda to cargo of the
	 *    system of animation of the character, exactamente igual to when the
	 *    animation termina durante the gameplay.
	 *  • Animaciones looping: forzar returnToIdle() directamente porque nunca
	 *    terminarían solas and the character is quedaría frozen in that pose.
	 */
	function _returnCharactersToIdle():Void
	{
		var ps = funkin.gameplay.PlayState.instance;
		if (ps == null) return;
		var chars:Array<Dynamic> = [ps.boyfriend, ps.dad, ps.gf];
		for (c in chars)
		{
			if (c == null) continue;
			try
			{
				var anim = c.animation;
				if (anim == null || anim.curAnim == null) continue;

				if (anim.curAnim.looped)
				{
					// Looping → would never end: force idle now
					if (Std.isOfType(c, funkin.gameplay.objects.character.Character))
						cast(c, funkin.gameplay.objects.character.Character).returnToIdle();
				}
				else
				{
					// No-looping → avanzar to the last frame for that the update
					// loop del Character detecte animFinished y llame a dance().
					// This preserves the natural transition defined in the character.
					final last = anim.curAnim.numFrames - 1;
					if (anim.curAnim.curFrame < last)
						anim.curAnim.curFrame = last;
					// Unpause (in case _setCharactersFrozen left it paused)
					anim.curAnim.paused = false;
				}
			}
			catch (_:Dynamic) {}
		}
	}

	function _cleanup():Void
	{
		// FIX animaciones: reanudar los personajes al terminar la cutscene
		_setCharactersFrozen(false);
		// FIX animaciones persisten: forzar a cada personaje a su idle/dance
		// after of the cutscene. _setCharactersFrozen(false) only despausa the
		// animation that quedó active (ej. intro2, laughCutscene); with this the
		// reseteamos limpiamente a la pose de espera sin esperar al update loop.
		_returnCharactersToIdle();
		// Desconectar the tick of seguimiento of camera
		FlxG.signals.preUpdate.remove(_onPreUpdate);
		// By if the cutscene ended before of that is disparara the postDraw inicial
		FlxG.signals.postDraw.remove(_onFirstPostDraw);
		_camTarget = null;

		// FIX camera is bloquea to the character: restaurar the follow that
		// desconectamos in play(). Also hacemos snap inmediato to the
		// position correct of the target for that the camera no "vuele" from
		// where quedó the cutscene until the character with a lerp largo.
		if (_camFollowDisabled)
		{
			var ps = funkin.gameplay.PlayState.instance;
			if (ps != null && ps.cameraController != null)
			{
				var cc = ps.cameraController;
				// Snap del camFollow al target actual ANTES de re-activar follow,
				// so the first frame post-cutscene the camera already is in the sitio correct.
				cc.snapshotInitialState(); // refresca los valores internos tras cambios de zoom
				FlxG.camera.follow(cc.camFollow, flixel.FlxCamera.FlxCameraFollowStyle.LOCKON, cc.followLerp);
			}
			_camFollowDisabled = false;
		}

		// FIX setCamVisible: restaurar visibilidad y alpha originales de cada
		// camera that the cutscene modificó with setCamVisible.
		var ps2 = funkin.gameplay.PlayState.instance;
		if (ps2 != null)
		{
			for (key => wasVisible in _hiddenCams)
			{
				var cam:FlxCamera = switch (key)
				{
					case 'hud':        ps2.camHUD;
					case 'game':       ps2.camGame;
					case 'countdown':  ps2.camCountdown;
					default:           null;
				};
				if (cam != null)
				{
					// Cancel any pending alpha tween on this camera
					FlxTween.cancelTweensOf(cam);
					cam.alpha   = _hiddenCamsAlpha.exists(key) ? _hiddenCamsAlpha.get(key) : 1.0;
					cam.visible = wasVisible;
				}
			}
		}
		_hiddenCams.clear();
		_hiddenCamsAlpha.clear();

		for (spr in _sprites) _state.remove(spr);
		for (snd in _sounds)  if (snd.playing) snd.stop();
		_sprites.clear();
		_sounds.clear();
		_callbackMap.clear();

		// Llamar callbacks de limpieza registrados con onCleanup()
		for (fn in _cleanupCallbacks)
			try { fn(); } catch (e:Dynamic) trace('[SpriteCutscene] onCleanup error: $e');
		_cleanupCallbacks = [];

		// Cancelar solo los timers y tweens de ESTA cutscene,
		// without tocar the globalManager (that mataría timers of audio/music).
		for (t in _timers)  { try t.cancel() catch (_) {}; }
		for (tw in _tweens) { try tw.cancel() catch (_) {}; }
		_timers  = [];
		_tweens  = [];

		// Remove the camera dedicada of the list of Flixel.
		if (_camCutscene != null)
		{
			FlxG.cameras.remove(_camCutscene, true);
			_camCutscene = null;
		}
	}

	function _finish():Void
	{
		playing  = false;
		finished = true;
		final cb = _onComplete;
		_onComplete = null;
		if (cb != null) cb();
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Carga del JSON
	// ═════════════════════════════════════════════════════════════════════════

	static function _loadDocument(key:String, ?song:String):Null<SpriteCutsceneData.CutsceneDocument>
	{
		#if sys
		var path = _resolvePath(key, song);
		if (path == null)
		{
			trace('[SpriteCutscene] JSON no encontrado para key="$key" song="$song".');
			return null;
		}
		try
		{
			var raw = File.getContent(path);
			return Json.parse(raw);
		}
		catch (e)
		{
			trace('[SpriteCutscene] Error al parsear "$path": $e');
			return null;
		}
		#else
		return null;
		#end
	}

	static function _resolvePath(key:String, ?song:String):Null<String>
	{
		#if sys
		var candidates:Array<String> = [];
		var modRoot = ModManager.modRoot();

		// With subcarpeta of song
		if (song != null)
		{
			if (modRoot != null)
			{
				candidates.push('$modRoot/data/cutscenes/$song/$key.json');
				candidates.push('$modRoot/data/cutscenes/$key.json');
				candidates.push('$modRoot/songs/$song/$key.json');
			}
			candidates.push('assets/data/cutscenes/$song/$key.json');
			candidates.push('assets/songs/$song/$key.json');
		}

		// Sin subcarpeta
		if (modRoot != null)
			candidates.push('$modRoot/data/cutscenes/$key.json');
		candidates.push('assets/data/cutscenes/$key.json');

		for (p in candidates)
			if (FileSystem.exists(p)) return p;
		#end
		return null;
	}

	// ── API static of conveniencia ──────────────────────────────────────────

	/**
	 * Crea y ejecuta una cutscene directamente.
	 * Equivalente a: new SpriteCutscene(state, key).play(onComplete)
	 */
	public static function create(state:flixel.FlxState, key:String,
		?song:String, ?onComplete:Void->Void):SpriteCutscene
	{
		var cut = new SpriteCutscene(state, key, song);
		cut.play(onComplete);
		return cut;
	}

	/** Comprueba si existe el JSON de una cutscene sin cargarla. */
	public static function exists(key:String, ?song:String):Bool
	{
		return _resolvePath(key, song) != null;
	}
}
