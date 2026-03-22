package funkin.gameplay;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.FlxCamera.FlxCameraFollowStyle;
import funkin.gameplay.objects.character.Character;

using StringTools;

/**
 * CameraController — Control of camera basado in events.
 * 
 * The camera sigue to the character definido by `currentTarget`,
 * that changes EXCLUSIVELY through the event "Camera Follow"
 * of the EventManager. There is no mustHitSection logic here.
 */
class CameraController
{
	// === CAMERAS ===
	public var camGame:FlxCamera;
	public var camHUD:FlxCamera;

	// === FOLLOW OBJECT ===
	// Expuesto para que EventManager pueda leerlo si hace falta.
	public var camFollow:FlxObject;
	private var camPos:FlxPoint;

	// === CHARACTERS ===
	// Se guardan las referencias para poder resolver el target por nombre.
	private var boyfriend:Character;
	private var dad:Character;
	private var gf:Character;

	// === TARGET ACTUAL ===
	// "player" | "opponent" | "gf"
	// Cambiar con setTarget() desde EventManager.
	public var currentTarget:String = 'opponent';

	// === INITIAL STATE (for restart/rewind) ===
	// Saved at construction time so resetToInitial() can fully restore the camera.
	private var _initialTarget : String = 'opponent';
	private var _initialZoom   : Float  = 1.05;
	private var _initialLerp   : Float  = 0.04;

	// === LERP SPEED del follow ===
	// Puede sobreescribirse por evento (Camera Follow, value2).
	public var followLerp:Float = 0.04;

	// === ZOOM ===
	public var defaultZoom:Float = 1.05;
	public var zoomEnabled:Bool  = false;
	private var zoomTween:FlxTween;
	private var _panTween:FlxTween;

	// === NOTE MOVEMENT OFFSETS ===
	public var dadOffsetX:Int = 0;
	public var dadOffsetY:Int = 0;
	public var bfOffsetX:Int  = 0;
	public var bfOffsetY:Int  = 0;

	// === STAGE CAMERA OFFSETS ===
	// Definidos en el stage JSON como cameraBoyfriend / cameraDad / cameraGirlfriend.
	// Defaults reproducen the comportamiento classic of the engine:
	//   player   → -100 X, -100 and  (camera ligeramente to the izquierda/arriba of BF)
	//   opponent → +150 X, -100 and  (camera more to the derecha for the oponente)
	//   gf       →    0 X,  -80 Y
	// Los stages que definen cameraBoyfriend/cameraDad en su JSON sobreescriben estos valores.
	public var stageOffsetBf:FlxPoint  = new FlxPoint(-100, -100);
	public var stageOffsetDad:FlxPoint = new FlxPoint(150, -100);
	/** Offset of camera for GF (camera_girlfriend in Psych). */
	public var stageOffsetGf:FlxPoint  = new FlxPoint(0, -80);

	/** Offset adicional pasado por el evento (campo x/y de FocusCamera en V-Slice). */
	var _extraOffsetX:Float = 0.0;
	var _extraOffsetY:Float = 0.0;

	// === CONFIG ===
	/**
	 * When `true`, the follow of the camera is bloqueado: `updateFollowPosition`
	 * is a no-op and camFollow is queda where is (or in _lockedPos if is usó lock()).
	 * Cambiar con lock() / unlock().
	 */
	public var locked:Bool = false;

	/** Position of mundo to the that is bloqueó the camera (only valid when locked=true). */
	private var _lockedPos:FlxPoint = new FlxPoint(0, 0);
	/**
	 * Velocidad of the lerp of camera. Equivalente to camera_speed in Psych.
	 * Se inicializa a 2.4 (default de Cool Engine). PlayState lo sobreescribe
	 * con currentStage.cameraSpeed * BASE_LERP_SPEED tras cargar el stage.
	 */
	public var lerpSpeed:Float = 2.4;
	public static inline var BASE_LERP_SPEED:Float = 2.4;
	private static inline var NOTE_OFFSET_AMOUNT:Float = 30.0;

	// ─────────────────────────────────────────────────────────────

	public function new(camGame:FlxCamera, camHUD:FlxCamera,
		boyfriend:Character, dad:Character, ?gf:Character)
	{
		this.camGame    = camGame;
		this.camHUD     = camHUD;
		this.boyfriend  = boyfriend;
		this.dad        = dad;
		this.gf         = gf;

		camFollow = new FlxObject(0, 0, 1, 1);
		camPos    = new FlxPoint();

		// Scale defaultZoom according to resolution (fix 1080p: 1280/1920 = 1.5×)
		defaultZoom *= Main.resolutionScale();

		// Start the camera siguiendo the object of follow with lerp suave.
		camGame.follow(camFollow, FlxCameraFollowStyle.LOCKON, followLerp);
		camGame.zoom = defaultZoom;

		// Save initial state so resetToInitial() can fully restore it on rewind/restart.
		_initialTarget = currentTarget;
		_initialZoom   = defaultZoom;
		_initialLerp   = followLerp;

		// Position inicial: over the oponente (target by default).
		_snapToTarget();
	}

	// ─────────────────────────────────────────────────────────────
	//  API public
	// ─────────────────────────────────────────────────────────────

	/**
	 * Change the character to the that sigue the camera.
	 * Llamar desde EventManager al procesar el evento "Camera Follow".
	 *
	 * @param target    "player" | "opponent" | "gf" | "position"
	 *                  (also acepta aliases bf/dad/boyfriend/girlfriend)
	 * @param extraOffX Offset X adicional del evento (campo "x" en FocusCamera V-Slice).
	 * @param extraOffY Offset Y adicional del evento (campo "y" en FocusCamera V-Slice).
	 * @param snap      If true, moves camFollow instantly (without lerp of follow point).
	 *                  Para CLASSIC de V-Slice usar snap=true: el follow point salta
	 *                  al nuevo target y solo camGame.follow() hace el lerp suave.
	 */
	public function setTarget(target:String, extraOffX:Float = 0.0, extraOffY:Float = 0.0, snap:Bool = true):Void
	{
		currentTarget  = resolveTarget(target);
		_extraOffsetX  = extraOffX;
		_extraOffsetY  = extraOffY;
		trace('[CameraController] Target → $currentTarget (extraOff=${extraOffX},${extraOffY} snap=$snap)');

		// Always snapear camFollow to the new target — the transition suave the
		// hace camGame.follow(camFollow, LOCKON, followLerp), igual que V-Slice.
		// The lerpSpeed of updateFollowPosition añadiría a segundo lerp encadenado
		// that ralentiza and suaviza in exceso the transition.
		_snapToTarget();
	}

	/**
	 * Actualizar lerp speed del follow.
	 * Llamar desde EventManager si se especifica value2 en el evento.
	 */
	public function setFollowLerp(lerp:Float):Void
	{
		followLerp = lerp;
		camGame.followLerp = lerp;
	}

	// ─────────────────────────────────────────────────────────────
	//  LOCK / UNLOCK
	// ─────────────────────────────────────────────────────────────

	/**
	 * Bloquea the follow of the camera in its position current (or in x/and if is pasan).
	 * While is bloqueada, the events of "Camera Follow" and the lerp normal
	 * no mueven camFollow — the camera is queda quieta in that punto.
	 *
	 * @param x  Position X of mundo optional. If null use the position current of camFollow.
	 * @param and  Position and of mundo optional. If null use the position current of camFollow.
	 */
	public function lock(?x:Float, ?y:Float):Void
	{
		locked = true;
		_lockedPos.x = x ?? camFollow.x;
		_lockedPos.y = y ?? camFollow.y;
		camFollow.setPosition(_lockedPos.x, _lockedPos.y);
	}

	/**
	 * Desbloquea the follow. The camera vuelve to lerpar towards the character
	 * definido por currentTarget desde la siguiente llamada a update().
	 */
	public function unlock():Void
	{
		locked = false;
	}

	/**
	 * Moves camFollow instantly to a position of mundo (without tween).
	 * No deshabilita the follow — if quieres that is quede ahí use lock() after.
	 *
	 * @param x  Position X of mundo.
	 * @param and  Position and of mundo.
	 */
	public function moveTo(x:Float, y:Float):Void
	{
		camFollow.setPosition(x, y);
	}

	/**
	 * Tweenea camFollow suavemente hacia (x, y) durante `duration` segundos.
	 * Bloquea the follow automatically mientras dura the tween for that the
	 * lerp hacia el personaje no lo cancele; lo desbloquea al terminar salvo
	 * que se pase keepLocked=true.
	 *
	 * @param x           Position X of mundo destino.
	 * @param and           Position and of mundo destino.
	 * @param duration    Duration of the tween in segundos (default 0.6).
	 * @param ease        Function of ease (default FlxEase.sineInOut).
	 * @param keepLocked  If true, the camera queda locked to the terminar (default false).
	 * @param onComplete  Callback opcional al terminar el tween.
	 */
	public function panTo(x:Float, y:Float, ?duration:Float, ?ease:Float->Float,
		?keepLocked:Bool, ?onComplete:Void->Void):Void
	{
		var dur:Float = duration ?? 0.6;
		var easeFunc = ease ?? FlxEase.sineInOut;
		var stayLocked:Bool = keepLocked ?? false;

		// Bloquar mientras dura el tween para que updateFollowPosition no lo cancele
		locked = true;

		if (_panTween != null) { _panTween.cancel(); _panTween = null; }

		_panTween = FlxTween.tween(camFollow, { x: x, y: y }, dur,
		{
			ease: easeFunc,
			onComplete: function(t)
			{
				_panTween = null;
				if (!stayLocked) locked = false;
				if (onComplete != null) onComplete();
			}
		});
	}

	/**
	 * Tweenea camFollow al target actual (calculado en este momento) con
	 * the duration and ease dados. Equivalente to panTo but calcula the destino
	 * from the character active in lugar of a position fija.
	 * Usado por FocusCamera V-Slice con ease/duration.
	 */
	public function tweenToTarget(duration:Float, ?ease:Float->Float):Void
	{
		final dest = _computeTargetPos();
		if (dest == null) return;
		panTo(dest.x, dest.y, duration, ease ?? FlxEase.sineOut);
		dest.put();
	}

	/**
	 * Centra the camera in the punto medio between bf and dad.
	 * Equivalente to setTarget('both') but instant or with snap.
	 *
	 * @param snap  If true (default) moves camFollow instantly.
	 *              Si false aplica un panTo suave de 0.6s.
	 */
	public function centerBetweenChars(?snap:Bool):Void
	{
		if (boyfriend == null || dad == null) return;
		var bfMid  = boyfriend.getMidpoint();
		var dadMid = dad.getMidpoint();
		var cx = (bfMid.x + dadMid.x) * 0.5;
		var cy = (bfMid.y + dadMid.y) * 0.5;
		bfMid.put();
		dadMid.put();

		if (snap ?? true)
			moveTo(cx, cy);
		else
			panTo(cx, cy);
	}

	/**
	 * Restaura the state inicial of the camera (target, zoom, lerp).
	 * Llamar desde PlayState._finishRestart() y PlayStateEditorState._onRestart()
	 * after of that EventManager.rewindToStart() haya marcado the events as
	 * no disparados, for that the camera quede where estaba to the start of the song.
	 */
	public function resetToInitial():Void
	{
		// Cancel any active zoom tween first
		if (zoomTween != null) { zoomTween.cancel(); zoomTween = null; }
		if (_panTween  != null) { _panTween.cancel();  _panTween  = null; }

		locked        = false;

		currentTarget = _initialTarget;
		defaultZoom   = _initialZoom;
		followLerp    = _initialLerp;
		zoomEnabled   = false;
		dadOffsetX    = 0;
		dadOffsetY    = 0;
		bfOffsetX     = 0;
		bfOffsetY     = 0;

		camGame.zoom        = defaultZoom;
		camGame.followLerp  = followLerp;

		_snapToTarget();
		trace('[CameraController] resetToInitial → target=$currentTarget zoom=$defaultZoom');
	}

	/**
	 * Toma una foto del estado actual como "estado inicial".
	 * PlayState call this after of appliesr all the overrides of the stage
	 * (defaultCamZoom, stageOffsets, lerpSpeed) para que resetToInitial()
	 * vuelva al punto correcto tras un rewind.
	 */
	public function snapshotInitialState():Void
	{
		_initialTarget = currentTarget;
		_initialZoom   = defaultZoom;
		_initialLerp   = followLerp;
		trace('[CameraController] snapshotInitialState → target=$_initialTarget zoom=$_initialZoom lerp=$_initialLerp');
	}

	// ─────────────────────────────────────────────────────────────
	//  UPDATE
	// ─────────────────────────────────────────────────────────────

	/**
	 * Llamar desde PlayState.update() cada frame.
	 * Ya NO recibe mustHitSection — el target se controla por eventos.
	 */
	public function update(elapsed:Float):Void
	{
		updateFollowPosition(elapsed);
		lerpZoom(elapsed);
	}

	// ─────────────────────────────────────────────────────────────
	//  INTERNOS
	// ─────────────────────────────────────────────────────────────

	private function updateFollowPosition(elapsed:Float):Void
	{
		// If the camera is bloqueada, no move camFollow in absoluto.
		if (locked) return;
		// ── Target 'both': centrar entre bf y dad ─────────────────────────
		if (currentTarget == 'both')
		{
			if (boyfriend == null || dad == null) return;

			var bfMid  = boyfriend.getMidpoint();
			var dadMid = dad.getMidpoint();

			var midX = (bfMid.x + dadMid.x) * 0.5;
			var midY = (bfMid.y + dadMid.y) * 0.5;

			// Offset vertical generic for that no quede in the pies
			midY -= 100;

			camFollow.x = midX;
			camFollow.y = midY;

			bfMid.put();
			dadMid.put();
			return;
		}

		// ── Target normal ─────────────────────────────────────────────────
		var targetChar = getTargetCharacter();
		if (targetChar == null) return;

		var targetPos = targetChar.getMidpoint();

		// Offsets propios del personaje (definidos en su JSON).
		targetPos.x += targetChar.cameraOffset[0];
		targetPos.y += targetChar.cameraOffset[1];

		// Stage offset (cameraBoyfriend/cameraDad/cameraGirlfriend del stage.json).
		var stageOff = switch (currentTarget)
		{
			case 'player':   stageOffsetBf;
			case 'opponent': stageOffsetDad;
			case 'gf':       stageOffsetGf;
			default:         stageOffsetDad;
		};
		targetPos.x += stageOff.x + _extraOffsetX;
		targetPos.y += stageOff.y + _extraOffsetY;

		// Offsets of animation of note.
		var noteOffX = currentTarget == 'player' ? bfOffsetX : dadOffsetX;
		var noteOffY = currentTarget == 'player' ? bfOffsetY : dadOffsetY;

		// Setear camFollow directo to the destino. The transition suave the hace
		// camGame.follow(camFollow, LOCKON, followLerp) — sin doble lerp encadenado.
		// El noteOffset se aplica directamente para el micro-movimiento de notas.
		camFollow.x = targetPos.x + noteOffX;
		camFollow.y = targetPos.y + noteOffY;

		targetPos.put();
	}

	/**
	 * Calcula the position destino of the follow for the target current.
	 * Devuelve un FlxPoint pooled — el caller debe llamar .put().
	 */
	private function _computeTargetPos():Null<flixel.math.FlxPoint>
	{
		var targetChar = getTargetCharacter();
		if (targetChar == null) return null;
		var pos = targetChar.getMidpoint();
		pos.x += targetChar.cameraOffset[0];
		pos.y += targetChar.cameraOffset[1];
		var stageOff = switch (currentTarget)
		{
			case 'player':   stageOffsetBf;
			case 'opponent': stageOffsetDad;
			case 'gf':       stageOffsetGf;
			default:         stageOffsetDad;
		};
		pos.x += stageOff.x + _extraOffsetX;
		pos.y += stageOff.y + _extraOffsetY;
		return pos;
	}

	private function lerpZoom(elapsed:Float):Void
	{
		var lerpVal:Float = FlxMath.bound(elapsed * 3.125, 0, 1);
		camGame.zoom = FlxMath.lerp(camGame.zoom, defaultZoom, lerpVal);
		camHUD.zoom  = FlxMath.lerp(camHUD.zoom,  1.0,         lerpVal);
	}

	/** Moves camFollow instantly to the target current (without lerp). */
	private function _snapToTarget():Void
	{
		// ── Target 'both': snap al centro entre bf y dad ──────────────────
		if (currentTarget == 'both')
		{
			if (boyfriend == null || dad == null) return;
			var bfMid  = boyfriend.getMidpoint();
			var dadMid = dad.getMidpoint();
			camFollow.setPosition(
				(bfMid.x + dadMid.x) * 0.5,
				(bfMid.y + dadMid.y) * 0.5
			);
			bfMid.put();
			dadMid.put();
			return;
		}

		var targetChar = getTargetCharacter();
		if (targetChar == null) return;

		var mid = targetChar.getMidpoint();
		// BUG FIX: igual que en updateFollowPosition, GF necesita su propio stageOffset.
		var stageOff = switch (currentTarget)
		{
			case 'player':   stageOffsetBf;
			case 'opponent': stageOffsetDad;
			case 'gf':       stageOffsetGf;
			default:         stageOffsetDad;
		};
		camFollow.setPosition(
			mid.x + targetChar.cameraOffset[0] + stageOff.x + _extraOffsetX,
			mid.y + targetChar.cameraOffset[1] + stageOff.y + _extraOffsetY
		);
		mid.put();
	}

	private function getTargetCharacter():Character
	{
		return switch (currentTarget)
		{
			case 'player':   boyfriend;
			case 'opponent': dad;
			case 'gf':       gf;
			default:         dad;
		};
	}

	/** Normalizes aliases to the cuatro names canónicos. */
	private function resolveTarget(raw:String):String
	{
		return switch (raw.toLowerCase().trim())
		{
			case 'player'   | 'bf' | 'boyfriend':          'player';
			case 'opponent' | 'dad' | 'enemy':             'opponent';
			case 'gf'       | 'girlfriend':                 'gf';
			case 'both'     | 'center' | 'middle' | 'all': 'both';
			default: raw;
		};
	}

	// ─────────────────────────────────────────────────────────────
	//  ZOOM Y EFECTOS
	// ─────────────────────────────────────────────────────────────

	public function bumpZoom():Void
	{
		if (!zoomEnabled) return;
		// The limit of bump is scales with the resolution for mantener
		// the same "sensación" visual that in 720p.
		var bumpLimit:Float = 1.35 * Main.resolutionScale();
		if (camGame.zoom < bumpLimit)
		{
			camGame.zoom += 0.015 * Main.resolutionScale();
			camHUD.zoom  += 0.03;
		}
	}

	public function applyNoteOffset(character:Character, noteData:Int):Void
	{
		var camX:Float = 0;
		var camY:Float = 0;

		switch (noteData)
		{
			case 0: camX = -NOTE_OFFSET_AMOUNT;
			case 1: camY =  NOTE_OFFSET_AMOUNT;
			case 2: camY = -NOTE_OFFSET_AMOUNT;
			case 3: camX =  NOTE_OFFSET_AMOUNT;
		}

		if (character == dad)
		{
			dadOffsetX = Std.int(camX);
			dadOffsetY = Std.int(camY);
		}
		else if (character == boyfriend)
		{
			bfOffsetX = Std.int(camX);
			bfOffsetY = Std.int(camY);
		}
	}

	public function resetOffsets():Void
	{
		dadOffsetX = 0; dadOffsetY = 0;
		bfOffsetX  = 0; bfOffsetY  = 0;
	}

	public function tweenZoomIn():Void
	{
		if (zoomTween != null) zoomTween.cancel();
		zoomTween = FlxTween.tween(camGame, {zoom: defaultZoom}, 1, {ease: FlxEase.elasticInOut});
	}

	public function shake(intensity:Float = 0.05, duration:Float = 0.1):Void
		camGame.shake(intensity, duration);

	public function flash(duration:Float = 0.5, color:Int = 0xFFFFFFFF):Void
		camGame.flash(color, duration);

	// ─────────────────────────────────────────────────────────────

	public function destroy():Void
	{
		if (zoomTween != null) { zoomTween.cancel(); zoomTween = null; }
		if (_panTween  != null) { _panTween.cancel();  _panTween  = null; }
		camPos.put();
		stageOffsetBf.put();
		stageOffsetDad.put();
		stageOffsetGf.put();
		_lockedPos.put();
		camFollow = null;
	}
}
