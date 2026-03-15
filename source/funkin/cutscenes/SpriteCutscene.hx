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
 * ─── Uso desde PlayState (automático vía meta.json) ──────────────────────────
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
 * ─── Resolución de archivos JSON ─────────────────────────────────────────────
 *
 *   mods/{mod}/data/cutscenes/{key}.json    ← mod override
 *   assets/data/cutscenes/{key}.json        ← base game
 *   mods/{mod}/data/cutscenes/{song}/{key}.json
 *   assets/data/cutscenes/{song}/{key}.json
 *
 * ─── Referencia del formato JSON ─────────────────────────────────────────────
 *   Ver SpriteCutsceneData.hx para la documentación completa del formato.
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
	// el globalManager (que mataría timers de audio y otros sistemas).
	var _timers:Array<FlxTimer>  = [];
	var _tweens:Array<FlxTween>  = [];

	// Cámara dedicada para los sprites de cutscene — se sitúa ENCIMA
	// de camHUD para que los sprites tapen el gameplay completamente.
	var _camCutscene:FlxCamera;

	// ── constructor ───────────────────────────────────────────────────────────

	/**
	 * @param state  Estado padre (normalmente PlayState.instance)
	 * @param key    Clave del JSON (sin extensión ni ruta)
	 * @param song   Canción actual (para resolver rutas de subcarpeta)
	 */
	public function new(state:flixel.FlxState, key:String, ?song:String)
	{
		_state = state;
		_doc   = _loadDocument(key, song);
		if (_doc != null && _doc.skippable == false) skippable = false;

		// Crear cámara dedicada que se añade AL FINAL de la lista de cámaras
		// → se renderiza encima de camGame y camHUD, tapando el gameplay.
		_camCutscene = new FlxCamera();
		_camCutscene.bgColor = 0x00000000; // transparente
		FlxG.cameras.add(_camCutscene, false);
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

	// ═════════════════════════════════════════════════════════════════════════
	//  Ejecución de pasos
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
			// cualquier nombre del stage) sin necesidad de añadir sprites nuevos.
			// JSON: { "action": "stageAnim", "sprite": "bf", "anim": "hey", "force": true }
			// Nombres válidos para "sprite":
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

			case 'end':
				_cleanup();
				_finish();

			default:
				trace('[SpriteCutscene] Acción desconocida: "${step.action}"');
				_nextStep();
		}
	}

	// ── add ───────────────────────────────────────────────────────────────────

	function _doAdd(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var id = step.sprite ?? '';
		var spr = _sprites.get(id);

		// Crear el sprite si no existe aún
		if (spr == null)
		{
			spr = _createSprite(id);
			if (spr == null) { _nextStep(); return; }
			_sprites.set(id, spr);
		}

		if (step.alpha != null) spr.alpha = step.alpha;
		// Asignar la cámara de cutscene para que el sprite se renderice
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
			// ── Rectángulo sólido ─────────────────────────────────────────────
			case 'rect':
				spr = new FlxSprite();
				var w = Std.int((data.width  ?? 1.0) * FlxG.width);
				var h = Std.int((data.height ?? 1.0) * FlxG.height);
				spr.makeGraphic(w, h, _parseColor(data.color ?? 'BLACK'));
				spr.scrollFactor.set(sf, sf);

			// ── Imagen estática (images/) ──────────────────────────────────────
			case 'image':
				var imgSpr = new FunkinSprite();
				var key = data.image ?? id;
				var g = Paths.getGraphic(key);
				if (g != null) imgSpr.loadGraphic(g);
				else imgSpr.makeGraphic(150, 150, 0x00000000);
				imgSpr.scrollFactor.set(sf, sf);
				spr = imgSpr;

			// ── Personaje (characters/images/) ────────────────────────────────
			//    FunkinSprite.loadCharacterSparrow detecta automáticamente:
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

			// ── Atlas genérico (images/) — auto-detecta Sparrow/Packer/Animate ─
			//    FunkinSprite.loadAsset detecta por extensión XML/TXT/Animation.json
			case 'atlas', 'sparrow', 'packer', 'animate', 'flxanimate', 'auto':
				var atlasSpr = new FunkinSprite();
				atlasSpr.scrollFactor.set(sf, sf);

				var pathList:Array<String> = data.paths;
				if (pathList != null && pathList.length > 1)
					// Multi-atlas explícito (varios PNG+XML o carpetas Animate)
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
	// FunkinSprite.addAnim() detecta automáticamente si el sprite es Animate
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
	 * animación indicada. Esto permite hacer cutscenes usando directamente
	 * los personajes del stage sin añadir sprites extra.
	 *
	 * Nombres reconocidos para el campo "sprite":
	 *   "bf" | "boyfriend"  → PlayState.boyfriend
	 *   "dad" | "opponent"  → PlayState.dad
	 *   "gf" | "girlfriend" → PlayState.gf
	 *
	 * Si "wait" es true, la cutscene se bloquea hasta que la animación termine.
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

		// Usar playAnim si es un Character (FNF), animation.play si es genérico
		if (Std.isOfType(char, funkin.gameplay.objects.character.Character))
			cast(char, funkin.gameplay.objects.character.Character).playAnim(animName, force);
		else if (char.animation != null)
			char.animation.play(animName, force);

		// Si wait=true esperar a que la animación termine antes de continuar
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
				// La animación acabó si finished=true o ya no está la misma
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
			// Fallback: buscar en sprites de cutscene por si alguien reutilizó el nombre
			default:
				var found = _sprites.get(name);
				if (found != null) found else null;
		};
	}

	// ── playSound ─────────────────────────────────────────────────────────────

	function _doPlaySound(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var key = step.key ?? '';
		var vol = step.volume ?? 1.0;
		var id  = step.id;

		var snd = FlxG.sound.play(Paths.sound(key), vol);

		if (id != null && snd != null)
			_sounds.set(id, snd);

		_nextStep(); // playSound nunca bloquea por sí solo — usar waitSound
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

	// ── cleanup / finish ──────────────────────────────────────────────────────

	function _cleanup():Void
	{
		for (spr in _sprites) _state.remove(spr);
		for (snd in _sounds)  if (snd.playing) snd.stop();
		_sprites.clear();
		_sounds.clear();

		// Cancelar solo los timers y tweens de ESTA cutscene,
		// sin tocar el globalManager (que mataría timers de audio/música).
		for (t in _timers)  { try t.cancel() catch (_) {}; }
		for (tw in _tweens) { try tw.cancel() catch (_) {}; }
		_timers  = [];
		_tweens  = [];

		// Eliminar la cámara dedicada de la lista de Flixel.
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

		// Con subcarpeta de canción
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

	// ── API estática de conveniencia ──────────────────────────────────────────

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
