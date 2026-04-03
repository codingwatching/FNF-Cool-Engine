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
 * CameraController — Control de cámara basado en eventos.
 * 
 * La cámara sigue al personaje definido por `currentTarget`,
 * que se cambia EXCLUSIVAMENTE a través del evento "Camera Follow"
 * del EventManager. No hay ninguna lógica de mustHitSection aquí.
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
	// Defaults reproducen el comportamiento clásico del engine:
	//   player   → -100 X, -100 Y  (cámara ligeramente a la izquierda/arriba de BF)
	//   opponent → +150 X, -100 Y  (cámara más a la derecha para el oponente)
	//   gf       →    0 X,  -80 Y
	// Los stages que definen cameraBoyfriend/cameraDad en su JSON sobreescriben estos valores.
	public var stageOffsetBf:FlxPoint  = new FlxPoint(-100, -100);
	public var stageOffsetDad:FlxPoint = new FlxPoint(150, -100);
	/** Offset de cámara para GF (camera_girlfriend en Psych). */
	public var stageOffsetGf:FlxPoint  = new FlxPoint(0, -80);

	/** Offset adicional pasado por el evento (campo x/y de FocusCamera en V-Slice). */
	var _extraOffsetX:Float = 0.0;
	var _extraOffsetY:Float = 0.0;

	// === CONFIG ===
	/**
	 * Cuando `true`, el follow de la cámara está bloqueado: `updateFollowPosition`
	 * es un no-op y camFollow se queda donde está (o en _lockedPos si se usó lock()).
	 * Cambiar con lock() / unlock().
	 */
	public var locked:Bool = false;

	/** Posición de mundo a la que se bloqueó la cámara (solo válida cuando locked=true). */
	private var _lockedPos:FlxPoint = new FlxPoint(0, 0);
	/**
	 * Velocidad del lerp de cámara. Equivalente a camera_speed en Psych.
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

		// Escalar defaultZoom según resolución (fix 1080p: 1280/1920 = 1.5×)
		defaultZoom *= Main.resolutionScale();

		// Iniciar la cámara siguiendo el objeto de follow con lerp suave.
		camGame.follow(camFollow, FlxCameraFollowStyle.LOCKON, followLerp);
		camGame.zoom = defaultZoom;

		// Save initial state so resetToInitial() can fully restore it on rewind/restart.
		_initialTarget = currentTarget;
		_initialZoom   = defaultZoom;
		_initialLerp   = followLerp;

		// Posición inicial: sobre el oponente (target por defecto).
		_snapToTarget();
	}

	// ─────────────────────────────────────────────────────────────
	//  API PÚBLICA
	// ─────────────────────────────────────────────────────────────

	/**
	 * Cambiar el personaje al que sigue la cámara.
	 * Llamar desde EventManager al procesar el evento "Camera Follow".
	 *
	 * @param target    "player" | "opponent" | "gf" | "position"
	 *                  (también acepta aliases bf/dad/boyfriend/girlfriend)
	 * @param extraOffX Offset X adicional del evento (campo "x" en FocusCamera V-Slice).
	 * @param extraOffY Offset Y adicional del evento (campo "y" en FocusCamera V-Slice).
	 * @param snap      Si true, mueve camFollow instantáneamente (sin lerp de follow point).
	 *                  Para CLASSIC de V-Slice usar snap=true: el follow point salta
	 *                  al nuevo target y solo camGame.follow() hace el lerp suave.
	 */
	public function setTarget(target:String, extraOffX:Float = 0.0, extraOffY:Float = 0.0, snap:Bool = true):Void
	{
		currentTarget  = resolveTarget(target);
		_extraOffsetX  = extraOffX;
		_extraOffsetY  = extraOffY;
		trace('[CameraController] Target → $currentTarget (extraOff=${extraOffX},${extraOffY} snap=$snap locked=$locked)');

		// Siempre snapear camFollow al nuevo target — la transición suave la
		// hace camGame.follow(camFollow, LOCKON, followLerp), igual que V-Slice.
		// El lerpSpeed de updateFollowPosition añadiría un segundo lerp encadenado
		// que ralentiza y suaviza en exceso la transición.
		// NOTA: _snapToTarget() respeta `locked` internamente — si está bloqueada
		// no moverá camFollow aunque se cambie el target.
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
	 * Bloquea el follow de la cámara en su posición actual (o en x/y si se pasan).
	 * Mientras está bloqueada, los eventos de "Camera Follow" y el lerp normal
	 * no mueven camFollow — la cámara se queda quieta en ese punto.
	 *
	 * @param x  Posición X de mundo opcional. Si null usa la posición actual de camFollow.
	 * @param y  Posición Y de mundo opcional. Si null usa la posición actual de camFollow.
	 */
	public function lock(?x:Float, ?y:Float):Void
	{
		if (_panTween != null)
		{
			_panTween.cancel();
			_panTween = null;
		}
		locked = true;

		// BUG FIX: antes usaba camFollow.x/y como posición de bloqueo.
		// camFollow es el OBJETIVO del lerp — la cámara puede estar todavía
		// a varios píxeles de él.  Usar camFollow.x hace que la cámara salte
		// visiblemente a la posición del objetivo en lugar de quedarse donde está.
		// Ahora usamos el CENTRO REAL de la cámara (scroll + medio viewport / zoom).
		final actualX:Float = (camGame != null)
			? camGame.scroll.x + camGame.width  * 0.5 / camGame.zoom
			: camFollow.x;
		final actualY:Float = (camGame != null)
			? camGame.scroll.y + camGame.height * 0.5 / camGame.zoom
			: camFollow.y;

		_lockedPos.x = x ?? actualX;
		_lockedPos.y = y ?? actualY;

		// Mover camFollow al punto bloqueado para que cuando se llame unlock()
		// y la cámara reanude el follow, parta exactamente de aquí sin salto.
		camFollow.setPosition(_lockedPos.x, _lockedPos.y);

		if (camGame != null)
		{
			// Snap inmediato del scroll al centro bloqueado.
			camGame.scroll.set(
				_lockedPos.x - camGame.width  * 0.5 / camGame.zoom,
				_lockedPos.y - camGame.height * 0.5 / camGame.zoom
			);

			// BUG FIX: followLerp = 1.0 no snapa instantáneamente en framerates altos
			// porque Flixel lo aplica como `lerp * elapsed * 60`, resultando en <1.0
			// de movimiento por frame a >60fps. Usar un valor enorme (999) garantiza
			// que `999 * elapsed * 60 >> 1` para cualquier framerate razonable,
			// haciendo que el scroll siempre iguale camFollow en el mismo frame.
			// Re-registrar el follow fuerza FlxCamera a limpiar su estado interno.
			camGame.follow(camFollow, FlxCameraFollowStyle.LOCKON, 999.0);
		}
	}

	/**
	 * Desbloquea el follow. La cámara vuelve a lerpar hacia el personaje
	 * definido por currentTarget desde la siguiente llamada a update().
	 */
	public function unlock():Void
	{
		locked = false;
		// Restaurar el follow con el lerp normal. lock() re-registró con 999 para
		// garantizar snap inmediato; aquí volvemos al lerp suave original.
		if (camGame != null)
			camGame.follow(camFollow, FlxCameraFollowStyle.LOCKON, followLerp);
	}

	/**
	 * Mueve camFollow instantáneamente a una posición de mundo (sin tween).
	 * No deshabilita el follow — si quieres que se quede ahí usa lock() después.
	 *
	 * @param x  Posición X de mundo.
	 * @param y  Posición Y de mundo.
	 */
	public function moveTo(x:Float, y:Float):Void
	{
		camFollow.setPosition(x, y);
	}

	/**
	 * Tweenea camFollow suavemente hacia (x, y) durante `duration` segundos.
	 * Bloquea el follow automáticamente mientras dura el tween para que el
	 * lerp hacia el personaje no lo cancele; lo desbloquea al terminar salvo
	 * que se pase keepLocked=true.
	 *
	 * @param x           Posición X de mundo destino.
	 * @param y           Posición Y de mundo destino.
	 * @param duration    Duración del tween en segundos (default 0.6).
	 * @param ease        Función de ease (default FlxEase.sineInOut).
	 * @param keepLocked  Si true, la cámara queda locked al terminar (default false).
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
	 * la duración y ease dados. Equivalente a panTo pero calcula el destino
	 * desde el personaje activo en lugar de una posición fija.
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
	 * Centra la cámara en el punto medio entre bf y dad.
	 * Equivalente a setTarget('both') pero instantáneo o con snap.
	 *
	 * @param snap  Si true (default) mueve camFollow instantáneamente.
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
	 * Restaura el estado inicial de la cámara (target, zoom, lerp).
	 * Llamar desde PlayState._finishRestart() y PlayStateEditorState._onRestart()
	 * DESPUÉS de que EventManager.rewindToStart() haya marcado los eventos como
	 * no disparados, para que la cámara quede donde estaba al inicio de la canción.
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
	 * PlayState llama esto DESPUÉS de aplicar todos los overrides del stage
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
		// Si la cámara está bloqueada, no mover camFollow en absoluto.
		if (locked) return;
		// ── Target 'both': centrar entre bf y dad ─────────────────────────
		if (currentTarget == 'both')
		{
			if (boyfriend == null || dad == null) return;

			var bfMid  = boyfriend.getMidpoint();
			var dadMid = dad.getMidpoint();

			var midX = (bfMid.x + dadMid.x) * 0.5;
			var midY = (bfMid.y + dadMid.y) * 0.5;

			// Offset vertical genérico para que no quede en los pies
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

		// Offsets de animación de nota.
		var noteOffX = currentTarget == 'player' ? bfOffsetX : dadOffsetX;
		var noteOffY = currentTarget == 'player' ? bfOffsetY : dadOffsetY;

		// Setear camFollow directo al destino. La transición suave la hace
		// camGame.follow(camFollow, LOCKON, followLerp) — sin doble lerp encadenado.
		// El noteOffset se aplica directamente para el micro-movimiento de notas.
		camFollow.x = targetPos.x + noteOffX;
		camFollow.y = targetPos.y + noteOffY;

		targetPos.put();
	}

	/**
	 * Calcula la posición destino del follow para el target actual.
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

	/** Mueve camFollow instantáneamente al target actual (sin lerp). */
	private function _snapToTarget():Void
	{
		// Si la cámara está bloqueada, nunca mover camFollow desde aquí.
		if (locked) return;

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

	/** Normaliza aliases a los cuatro nombres canónicos. */
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
		// El límite de bump se escala con la resolución para mantener
		// la misma "sensación" visual que en 720p.
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
