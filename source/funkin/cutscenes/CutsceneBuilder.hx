package funkin.cutscenes;

import funkin.cutscenes.SpriteCutsceneData;

/**
 * CutsceneBuilder — escribe cutscenes completas en HScript sin necesitar un JSON.
 *
 * ─── Sintaxis natural (igual que en PlayState) ───────────────────────────────
 *
 *   var b = cutscene.builder().skippable(false);
 *
 *   b.defineRect('bg', 'BLACK')
 *    .defineSprite('can', { type:'sparrow', image:'game/weekend/can',
 *                           x:950, y:725, antialiasing:true,
 *                           animations:[{ name:'up', prefix:'can kicked up0', fps:24 }] });
 *
 *   b.add('bg')
 *    .bf.playAnim('intro1')       // igual que stageAnim('bf','intro1')
 *    .wait(0.7)
 *    .playSound('darnellCanCutscene', { music:true, stage:true })
 *    .tween('bg', {alpha:0}, 2.0, {async:true})
 *    .cameraZoom(0.66, 2.5, {ease:'quadInOut', async:true})
 *    .cameraPan(800, 400, 2.5, {ease:'quadInOut', async:true})
 *    .wait(3.0)
 *    .dad.playAnim('lightCan')
 *    .playSound('Darnell_Lighter', {stage:true})
 *    .wait(1.0)
 *    .bf.playAnim('cock')
 *    .wait(0.4)
 *    .dad.playAnim('kickCan')
 *    .sprite('can').add().playAnim('up')
 *    .wait(0.5)
 *    .dad.playAnim('kneeCan')
 *    .sprite('can').playAnim('forward')
 *    .wait(0.2)
 *    .bf.playAnim('intro2')
 *    .remove('can')
 *    .cameraFlash('WHITE', 0.25, true)
 *    .wait(0.8)
 *    .dad.playAnim('laughCutscene')
 *    .gf.playAnim('laughCutscene')
 *    .wait(1.8)
 *    .cameraZoom(0.77, 2.0, {ease:'sineInOut', async:true})
 *    .remove('bg')
 *    .play(onDone);
 *
 * ─── Proxies disponibles ────────────────────────────────────────────────────
 *
 *   b.bf  / b.boyfriend   → CharacterProxy para Boyfriend
 *   b.dad / b.opponent    → CharacterProxy para Dad
 *   b.gf  / b.girlfriend  → CharacterProxy para GF
 *   b.sprite('id')        → SpriteProxy para cualquier sprite de la cutscene
 *
 * ─── Methods of CharacterProxy ──────────────────────────────────────────────
 *
 *   .bf.playAnim('hey')          // lanza animation (force=true by default)
 *   .bf.playAnim('hey', false)   // force=false
 *   .bf.dance()                  // vuelve al idle/dance
 *
 * ─── Methods of SpriteProxy ─────────────────────────────────────────────────
 *
 *   .sprite('can').add()
 *   .sprite('can').remove()
 *   .sprite('can').playAnim('up')
 *   .sprite('can').tween({alpha:0}, 1.0)
 *   .sprite('can').tween({alpha:0}, 1.0, {ease:'quadOut', async:true})
 *   .sprite('can').setAlpha(0.5)
 *   .sprite('can').setVisible(false)
 *   .sprite('can').setPosition(100, 200)
 */
class CutsceneBuilder
{
	// ── estado interno ────────────────────────────────────────────────────────
	var _steps:Array<CutsceneStep>      = [];
	var _sprites:Dynamic                = {};
	var _skippable:Bool                 = true;
	var _callbacks:Map<String, Dynamic> = [];
	var _cbCounter:Int                  = 0;

	// ── proxies de personaje ──────────────────────────────────────────────────
	/** Proxy para Boyfriend. Permite: b.bf.playAnim('hey') */
	public var bf:CharacterProxy;
	/** Alias de bf. */
	public var boyfriend:CharacterProxy;
	/** Proxy para Dad/Oponente. */
	public var dad:CharacterProxy;
	/** Alias de dad. */
	public var opponent:CharacterProxy;
	/** Proxy para GF. */
	public var gf:CharacterProxy;
	/** Alias de gf. */
	public var girlfriend:CharacterProxy;

	// ─────────────────────────────────────────────────────────────────────────

	public function new()
	{
		bf         = new CharacterProxy(this, 'bf');
		boyfriend  = bf;
		dad        = new CharacterProxy(this, 'dad');
		opponent   = dad;
		gf         = new CharacterProxy(this, 'gf');
		girlfriend = gf;
	}

	// ── config ────────────────────────────────────────────────────────────────

	/** Define si la cutscene se puede saltar con ESC (default: true). */
	public function skippable(v:Bool):CutsceneBuilder
	{
		_skippable = v;
		return this;
	}

	// ── definition of sprites ─────────────────────────────────────────────────

	/**
	 * Defines a rectangle of color.
	 * Por defecto 2×2 en (-100,-100) con scrollFactor=0: cubre toda la pantalla.
	 */
	public function defineRect(id:String, color:String = 'BLACK',
		w:Float = 2, h:Float = 2, x:Float = -100, y:Float = -100):CutsceneBuilder
	{
		Reflect.setField(_sprites, id, {
			type:'rect', color:color, width:w, height:h,
			x:x, y:y, scrollFactor:0, alpha:1
		});
		return this;
	}

	/**
	 * Defines a sprite with datos completos (equivalente to the section "sprites" of the JSON).
	 * Acepta exactamente los mismos campos: type, image, x, y, alpha,
	 * scrollFactor, antialiasing, scale, animations, etc.
	 */
	public function defineSprite(id:String, data:Dynamic):CutsceneBuilder
	{
		Reflect.setField(_sprites, id, data);
		return this;
	}

	// ── proxy de sprite de cutscene ───────────────────────────────────────────

	/**
	 * Devuelve un SpriteProxy para operar sobre un sprite de la cutscene.
	 *   b.sprite('can').add()
	 *   b.sprite('can').playAnim('up')
	 *   b.sprite('can').tween({alpha:0}, 1.0, {async:true})
	 */
	public function sprite(id:String):SpriteProxy
		return new SpriteProxy(this, id);

	// ── acciones de sprite ────────────────────────────────────────────────────

	/** Adds a sprite to the escena. */
	public function add(id:String, ?alpha:Float):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'add', sprite:id };
		if (alpha != null) s.alpha = alpha;
		return _push(s);
	}

	/** Quita un sprite de la escena. */
	public function remove(id:String):CutsceneBuilder
		return _push({ action:'remove', sprite:id });

	/** Changes the alpha instantly. */
	public function setAlpha(id:String, alpha:Float):CutsceneBuilder
		return _push({ action:'setAlpha', sprite:id, alpha:alpha });

	/** Changes the visibilidad instantly. */
	public function setVisible(id:String, v:Bool):CutsceneBuilder
		return _push({ action:'setVisible', sprite:id, visible:v });

	/** Moves a sprite to (x, and) instantly. */
	public function setPosition(id:String, x:Float, y:Float):CutsceneBuilder
		return _push({ action:'setPosition', sprite:id, x:x, y:y });

	/**
	 * Tweenea propiedades de un sprite de la cutscene.
	 * @param props  { alpha:0 } | { x:100, y:200 } | cualquier propiedad de FlxSprite
	 * @param opts   Opcional: { ease:'quadOut', async:true }
	 */
	public function tween(id:String, props:Dynamic, duration:Float,
		?opts:Dynamic):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'tween', sprite:id, props:props, duration:duration };
		_applyOpts(s, opts);
		return _push(s);
	}

	/** Plays an animation en un sprite de la cutscene. */
	public function playAnim(id:String, anim:String, ?force:Bool):CutsceneBuilder
		return _push({ action:'playAnim', sprite:id, anim:anim, force:force ?? false });

	// ── acciones de personaje ─────────────────────────────────────────────────

	/**
	 * Lanza a animation in bf/dad/gf of the PlayState.
	 * Preferiblemente usa los proxies: b.bf.playAnim('hey')
	 * @param who   "bf" | "dad" | "gf" y sus aliases
	 * @param opts  Opcional: { force:true, wait:false }
	 */
	public function stageAnim(who:String, anim:String, ?opts:Dynamic):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'stageAnim', sprite:who, anim:anim, force:true };
		_applyOpts(s, opts);
		return _push(s);
	}

	// ── esperas ───────────────────────────────────────────────────────────────

	/** Espera `seconds` segundos antes de continuar. */
	public function wait(seconds:Float):CutsceneBuilder
		return _push({ action:'wait', time:seconds });

	// ── sonido ────────────────────────────────────────────────────────────────

	/**
	 * Reproduce un sonido.
	 * @param opts  Opcional: { volume:1.0, music:false, stage:false, id:'myId' }
	 */
	public function playSound(key:String, ?opts:Dynamic):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'playSound', key:key };
		_applyOpts(s, opts);
		return _push(s);
	}

	/** Bloquea la cutscene hasta que termine el sonido con el id dado. */
	public function waitSound(id:String):CutsceneBuilder
		return _push({ action:'waitSound', id:id });

	// ── camera ────────────────────────────────────────────────────────────────

	/** Tweenea el zoom. @param opts { ease:'quadOut', async:true } */
	public function cameraZoom(zoom:Float, duration:Float, ?opts:Dynamic):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'cameraZoom', zoom:zoom, duration:duration };
		_applyOpts(s, opts);
		return _push(s);
	}

	/** Moves the camera instantly to the coordenadas of scroll (x, and). */
	public function cameraMove(x:Float, y:Float):CutsceneBuilder
		return _push({ action:'cameraMove', camX:x, camY:y });

	/** Tweenea the position of the camera. @param opts { ease:'sineInOut', async:true } */
	public function cameraPan(x:Float, y:Float, duration:Float, ?opts:Dynamic):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'cameraPan', camX:x, camY:y, duration:duration };
		_applyOpts(s, opts);
		return _push(s);
	}

	/** Restaura zoom and position to the state previo. @param opts { duration:0.5, async:true } */
	public function cameraReset(?opts:Dynamic):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'cameraReset' };
		_applyOpts(s, opts);
		return _push(s);
	}

	/** Flash of the camera. */
	public function cameraFlash(?color:String, ?duration:Float, ?async:Bool):CutsceneBuilder
	{
		var s:Dynamic = { action:'cameraFlash', color:color ?? 'WHITE', duration:duration ?? 0.5 };
		if (async == true) s.async = true;
		return _push(cast s);
	}

	/** Fade of the camera. @param opts { fadeIn:false, async:false } */
	public function cameraFade(?color:String, ?duration:Float, ?opts:Dynamic):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'cameraFade', color:color ?? 'BLACK', duration:duration ?? 0.5 };
		_applyOpts(s, opts);
		return _push(s);
	}

	/** Shake of the camera. */
	public function cameraShake(?intensity:Float, ?duration:Float):CutsceneBuilder
		return _push({ action:'cameraShake', intensity:intensity ?? 0.03, duration:duration ?? 0.2 });

	/** Hace that the camera siga to a sprite. null = dejar of seguir. */
	public function cameraTarget(?spriteId:String):CutsceneBuilder
	{
		var s:Dynamic = { action:'cameraTarget', camTarget:spriteId };
		return _push(cast s);
	}

	/** Fade of alpha of a camera of the PlayState. @param opts { duration:0.3, async:true } */
	public function setCamVisible(cam:String, visible:Bool, ?opts:Dynamic):CutsceneBuilder
	{
		var s:Dynamic = { action:'setCamVisible', cam:cam, visible:visible };
		_applyOpts(cast s, opts);
		return _push(cast s);
	}

	// ── callbacks — ejecutar code Haxe/HScript arbitrario ──────────────────

	/**
	 * Ejecuta a function in this punto of the cutscene without bloquearla.
	 * The function is call inmediatamente and the cutscene continúa to the next paso.
	 *
	 *   b.call(function() {
	 *       FlxG.sound.play(Paths.sound('explosion'));
	 *       FlxTween.tween(mySprite, {alpha: 0}, 0.5);
	 *   })
	 *   b.call(function() { log('checkpoint'); })
	 */
	public function call(fn:Dynamic):CutsceneBuilder
	{
		var id = '__cb_' + (_cbCounter++);
		_callbacks.set(id, fn);
		var s:Dynamic = { action:'call', id:id };
		return _push(cast s);
	}

	/**
	 * Ejecuta a function asynchronous that bloquea the cutscene until that
	 * the function llame to its argumento `done`.
	 * Useful for wait to that termine a FlxTween, a FlxTimer, etc.
	 *
	 *   b.callAsync(function(done) {
	 *       FlxTween.tween(mySprite, {alpha:0}, 1.0, { onComplete: function(_) done() });
	 *   })
	 *
	 *   b.callAsync(function(done) {
	 *       new FlxTimer().start(2.0, function(_) done());
	 *   })
	 */
	public function callAsync(fn:Dynamic):CutsceneBuilder
	{
		var id = '__cbA_' + (_cbCounter++);
		_callbacks.set(id, fn);
		var s:Dynamic = { action:'callAsync', id:id };
		return _push(cast s);
	}

	// ── beats y steps ─────────────────────────────────────────────────────────

	/**
	 * Bloquea la cutscene hasta que Conductor llegue al beat indicado.
	 * If the beat already passed continúa inmediatamente.
	 *
	 *   b.waitBeat(8)    // wait until the beat 8 of the song
	 */
	public function waitBeat(beat:Int):CutsceneBuilder
	{
		var s:Dynamic = { action:'waitBeat', beat:beat };
		return _push(cast s);
	}

	/**
	 * Bloquea la cutscene hasta que Conductor llegue al step indicado.
	 * Un beat = 4 steps.
	 *
	 *   b.waitStep(32)   // esperar hasta el step 32 (= beat 8)
	 */
	public function waitStep(step:Int):CutsceneBuilder
	{
		var s:Dynamic = { action:'waitStep', step:step };
		return _push(cast s);
	}

	/**
	 * Ejecuta a function each vez that is dispara a beat mientras the
	 * cutscene is active.
	 * The log is hace via onBeatHitHooks of PlayState, and is elimina
	 * automatically when the cutscene termina or is salta.
	 *
	 * `fn` receives the number of beat current as argument: function(beat) { ... }
	 *
	 *   b.onBeat(function(beat) {
	 *       if (beat % 2 == 0) mySprite.scale.set(1.1, 1.1);
	 *   })
	 */
	public function onBeat(fn:Dynamic):CutsceneBuilder
	{
		var hookId = '__onBeat_' + (_cbCounter++);
		return call(function() {
			var ps = funkin.gameplay.PlayState.instance;
			if (ps == null) return;
			ps.onBeatHitHooks.set(hookId, fn);
		}).onCleanup(function() {
			var ps = funkin.gameplay.PlayState.instance;
			if (ps != null) ps.onBeatHitHooks.remove(hookId);
		});
	}

	/**
	 * Ejecuta a function each vez that is dispara a step mientras the
	 * cutscene is active.
	 *
	 * `fn` receives the number of step current: function(step) { ... }
	 *
	 *   b.onStep(function(step) {
	 *       if (step % 4 == 0) mySprite.animation.play('bop');
	 *   })
	 */
	public function onStep(fn:Dynamic):CutsceneBuilder
	{
		var hookId = '__onStep_' + (_cbCounter++);
		return call(function() {
			var ps = funkin.gameplay.PlayState.instance;
			if (ps == null) return;
			ps.onStepHitHooks.set(hookId, fn);
		}).onCleanup(function() {
			var ps = funkin.gameplay.PlayState.instance;
			if (ps != null) ps.onStepHitHooks.remove(hookId);
		});
	}

	/**
	 * Registra a function that is call when the cutscene termina or is salta.
	 * Useful for clear recursos creados with call() or callAsync().
	 *
	 *   b.call(function() { someExternalTimer.start(); })
	 *    .onCleanup(function() { someExternalTimer.cancel(); })
	 */
	public function onCleanup(fn:Dynamic):CutsceneBuilder
	{
		var id = '__clean_' + (_cbCounter++);
		_callbacks.set(id, fn);
		var s:Dynamic = { action:'_registerCleanup', id:id };
		return _push(cast s);
	}

	// ── paso raw / comentario ─────────────────────────────────────────────────

	/** Inserta un comentario (no-op en runtime). */
	public function comment(text:String):CutsceneBuilder
	{
		var s:Dynamic = { comment:text };
		return _push(cast s);
	}

	/** Adds a paso arbitrario in format raw (same object that the JSON). */
	public function step(raw:Dynamic):CutsceneBuilder
		return _push(cast raw);

	// ── finalización ──────────────────────────────────────────────────────────

	/**
	 * Adds the paso `end` end. Optional — play() it adds automatically.
	 */
	public function end():CutsceneBuilder
		return _push({ action:'end' });

	/**
	 * Construye el documento, crea la SpriteCutscene y la lanza.
	 * @param onComplete  Callback al terminar o saltar.
	 * @return            The instancia for poder callr skip() after.
	 */
	public function play(?onComplete:Void->Void):SpriteCutscene
	{
		if (_steps.length == 0 || _steps[_steps.length - 1].action != 'end')
			_push({ action:'end' });

		var doc:CutsceneDocument = { sprites:_sprites, steps:_steps, skippable:_skippable };
		var state = funkin.gameplay.PlayState.instance;
		var cut   = SpriteCutscene.fromDoc(state, doc, _callbacks);
		cut.play(onComplete);
		return cut;
	}

	// ── internos ──────────────────────────────────────────────────────────────

	@:allow(funkin.cutscenes.CharacterProxy)
	@:allow(funkin.cutscenes.SpriteProxy)
	function _push(s:CutsceneStep):CutsceneBuilder
	{
		_steps.push(s);
		return this;
	}

	@:allow(funkin.cutscenes.SpriteProxy)
	static function _applyOpts(s:CutsceneStep, opts:Dynamic):Void
	{
		if (opts == null) return;
		for (field in Reflect.fields(opts))
			Reflect.setField(s, field, Reflect.field(opts, field));
	}
}

// ─────────────────────────────────────────────────────────────────────────────
//  CharacterProxy
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Proxy que representa a bf, dad o gf dentro del builder.
 * All its methods añaden a paso to the builder and returnsn the builder
 * para seguir encadenando.
 *
 *   b.bf.playAnim('hey')     → igual que b.stageAnim('bf', 'hey')
 *   b.dad.playAnim('idle')
 *   b.gf.dance()
 */
class CharacterProxy
{
	var _b:CutsceneBuilder;
	var _who:String;

	public function new(b:CutsceneBuilder, who:String)
	{
		_b   = b;
		_who = who;
	}

	/**
	 * Lanza a animation in this character.
	 * @param anim   Nombre of the animation (igual that in Character.playAnim)
	 * @param force  Force restart although already is reproduciéndose (default: true)
	 */
	public function playAnim(anim:String, ?force:Bool):CutsceneBuilder
		return _b._push({ action:'stageAnim', sprite:_who, anim:anim, force:force ?? true });

	/**
	 * Vuelve al idle/dance.
	 * Lanza 'idle' with force=false; Character.update() elegirá the anim correct.
	 */
	public function dance():CutsceneBuilder
		return _b._push({ action:'stageAnim', sprite:_who, anim:'idle', force:false });
}

// ─────────────────────────────────────────────────────────────────────────────
//  SpriteProxy
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Proxy para un sprite definido en la cutscene (no un personaje del stage).
 * Se obtiene con b.sprite('id').
 *
 *   b.sprite('can').add()
 *   b.sprite('can').playAnim('up')
 *   b.sprite('can').tween({ alpha:0 }, 1.0, { async:true })
 *   b.sprite('can').remove()
 */
class SpriteProxy
{
	var _b:CutsceneBuilder;
	var _id:String;

	public function new(b:CutsceneBuilder, id:String)
	{
		_b  = b;
		_id = id;
	}

	/** Adds the sprite to the escena. */
	public function add(?alpha:Float):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'add', sprite:_id };
		if (alpha != null) s.alpha = alpha;
		return _b._push(s);
	}

	/** Quita el sprite de la escena. */
	public function remove():CutsceneBuilder
		return _b._push({ action:'remove', sprite:_id });

	/** Plays an animation en el sprite. */
	public function playAnim(anim:String, ?force:Bool):CutsceneBuilder
		return _b._push({ action:'playAnim', sprite:_id, anim:anim, force:force ?? false });

	/**
	 * Tweenea propiedades del sprite.
	 * @param props  { alpha:0 } | { x:100, y:200 } | etc.
	 * @param opts   Opcional: { ease:'quadOut', async:true }
	 */
	public function tween(props:Dynamic, duration:Float, ?opts:Dynamic):CutsceneBuilder
	{
		var s:CutsceneStep = { action:'tween', sprite:_id, props:props, duration:duration };
		CutsceneBuilder._applyOpts(s, opts);
		return _b._push(s);
	}

	/** Changes the alpha instantly. */
	public function setAlpha(alpha:Float):CutsceneBuilder
		return _b._push({ action:'setAlpha', sprite:_id, alpha:alpha });

	/** Changes the visibilidad instantly. */
	public function setVisible(v:Bool):CutsceneBuilder
		return _b._push({ action:'setVisible', sprite:_id, visible:v });

	/** Moves the sprite to (x, and) instantly. */
	public function setPosition(x:Float, y:Float):CutsceneBuilder
		return _b._push({ action:'setPosition', sprite:_id, x:x, y:y });
}
