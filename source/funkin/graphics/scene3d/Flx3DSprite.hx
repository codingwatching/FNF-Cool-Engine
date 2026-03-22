package funkin.graphics.scene3d;

import flixel.FlxSprite;
import flixel.FlxG;

/**
 * Flx3DSprite — FlxSprite que contiene y renderiza una escena 3D.
 *
 * ─── Uso ─────────────────────────────────────────────────────────────────────
 *
 *   // Crear sprite 3D
 *   var sp3d = new Flx3DSprite(0, 0, 640, 480);
 *   add(sp3d);
 *
 *   // Add objects to the escena
 *   var cube = new Flx3DObject();
 *   cube.mesh = Flx3DPrimitives.cube();
 *   sp3d.scene.add(cube);
 *
 *   // The camera
 *   sp3d.scene.camera.position.set(0, 1, 4);
 *   sp3d.scene.camera.target.set(0, 0, 0);
 *
 *   // Animar en update()
 *   cube.rotY += elapsed * 1.5;
 *
 * ─── Rendimiento ─────────────────────────────────────────────────────────────
 *   • renderEveryFrame: true (default) — re-renderiza cada update()
 *   • renderEveryFrame: false — solo renderiza cuando llames a sp3d.scene.render()
 *   • For escenas static, setea renderEveryFrame = false and call
 *     scene.render() solo cuando cambie algo.
 */
class Flx3DSprite extends FlxSprite
{
	/** Escena 3D interna. */
	public var scene(default, null):Flx3DScene;

	/** Si true, renderiza la escena en cada update(). Default: true. */
	public var renderEveryFrame:Bool = true;

	/** Callback when the contexto 3D is listo. */
	public var onReady:Null<Void->Void> = null;

	var _sceneW:Int;
	var _sceneH:Int;
	var _initialized:Bool = false;

	public function new(x:Float = 0, y:Float = 0, sceneW:Int = 640, sceneH:Int = 480)
	{
		super(x, y);
		_sceneW = sceneW;
		_sceneH = sceneH;

		scene = new Flx3DScene(sceneW, sceneH);

		// Initialize in the next frame for that Stage3D is available
		// (in mobile is diferimos a tick more)
		FlxG.stage.addEventListener(openfl.events.Event.ENTER_FRAME, _onFirstFrame);
	}

	function _onFirstFrame(_):Void
	{
		FlxG.stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _onFirstFrame);
		scene.init(function()
		{
			_initialized = true;
			// Hacer un primer render para popular el BitmapData
			scene.render();
			if (scene.output != null)
				loadGraphic(scene.output);
			if (onReady != null) onReady();
		});
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (!_initialized || !renderEveryFrame) return;

		scene.render();

		// Re-sincronizar el BitmapData con el sprite cada frame
		// (Flixel cachea el graphic, pero scene.output es el mismo objeto
		// so that the bitmap is updates in-place in GPU — the sprite it verá)
		if (scene.output != null && pixels != scene.output)
			loadGraphic(scene.output);
	}

	/** Redimensiona la escena 3D y el sprite. */
	public function resizeScene(w:Int, h:Int):Void
	{
		_sceneW = w; _sceneH = h;
		scene.resize(w, h);
		if (scene.output != null)
			loadGraphic(scene.output);
	}

	override public function destroy():Void
	{
		scene.dispose();
		super.destroy();
	}

	// ── Helpers of acceso fast ───────────────────────────────────────────

	/** Acceso directo to the camera 3D of the escena.
	 *  (Llamado cam3D para no colisionar con FlxBasic.camera:FlxCamera) */
	public var cam3D(get, never):Flx3DCamera;
	inline function get_cam3D():Flx3DCamera return scene.camera;

	/** Adds a object to the escena. */
	public inline function addObject(obj:Flx3DObject):Flx3DObject
		return scene.add(obj);

	/** Creates a cubo and it adds. Shorthand of uso frecuente. */
	public function makeCube(w:Float=1, h:Float=1, d:Float=1,
	                         color:Int = 0xFFFFFFFF):Flx3DObject
	{
		final obj = new Flx3DObject();
		obj.mesh  = Flx3DPrimitives.cube(w, h, d,
			((color >> 16) & 0xFF) / 255.0,
			((color >>  8) & 0xFF) / 255.0,
			( color        & 0xFF) / 255.0,
			((color >> 24) & 0xFF) / 255.0
		);
		scene.add(obj);
		return obj;
	}

	/** Creates a esfera and the adds. */
	public function makeSphere(radius:Float=0.5, segments:Int=16,
	                           color:Int = 0xFFFFFFFF):Flx3DObject
	{
		final obj = new Flx3DObject();
		obj.mesh  = Flx3DPrimitives.sphere(radius, segments, Std.int(segments*0.75),
			((color >> 16) & 0xFF) / 255.0,
			((color >>  8) & 0xFF) / 255.0,
			( color        & 0xFF) / 255.0,
			((color >> 24) & 0xFF) / 255.0
		);
		scene.add(obj);
		return obj;
	}

	/** Creates a plano and it adds. */
	public function makePlane(w:Float=2, d:Float=2, segs:Int=1,
	                          color:Int = 0xFFFFFFFF):Flx3DObject
	{
		final obj = new Flx3DObject();
		obj.mesh  = Flx3DPrimitives.plane(w, d, segs, segs,
			((color >> 16) & 0xFF) / 255.0,
			((color >>  8) & 0xFF) / 255.0,
			( color        & 0xFF) / 255.0,
			((color >> 24) & 0xFF) / 255.0
		);
		scene.add(obj);
		return obj;
	}
}
