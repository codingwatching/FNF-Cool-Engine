package funkin.graphics.scene3d;

import openfl.display3D.textures.RectangleTexture;

/**
 * Flx3DObject — Nodo de la escena 3D.
 *
 * Combina transform (TRS), mesh y material opcional.
 * La matriz de modelo se recalcula solo cuando algún campo cambia.
 */
class Flx3DObject
{
	// ── Identificación ──────────────────────────────────────────────────────

	public var name   :String  = 'object';
	public var visible:Bool    = true;
	public var active :Bool    = true;

	// ── Transform ───────────────────────────────────────────────────────────

	public var x      :Float = 0;
	public var y      :Float = 0;
	public var z      :Float = 0;

	/** Rotación en radianes (orden XYZ). */
	public var rotX   :Float = 0;
	public var rotY   :Float = 0;
	public var rotZ   :Float = 0;

	public var scaleX :Float = 1;
	public var scaleY :Float = 1;
	public var scaleZ :Float = 1;

	// ── Material ────────────────────────────────────────────────────────────

	/** Mesh asignado a este objeto. */
	public var mesh    :Null<Flx3DMesh>          = null;
	/** Textura difusa (si es null, se usa el color del vértice). */
	public var texture :Null<RectangleTexture>   = null;
	/** Multiplicador de color base [r,g,b,a]. */
	public var tint    :Array<Float>             = [1,1,1,1];

	/** Si true, recibe iluminación. Si false, se renderiza sin iluminación (unlit). */
	public var lit     :Bool = true;
	/** Factor de brillo especular (0=mate, 1=brillante). */
	public var shininess:Float = 32.0;

	// ── Matriz de modelo ────────────────────────────────────────────────────

	public var modelMatrix(default, null):Mat4 = new Mat4();

	// ── API ────────────────────────────────────────────────────────────────

	public function new() {}

	/**
	 * Recalcula la matriz de modelo a partir de position/rotation/scale.
	 * Llamar antes de cada render (Flx3DScene lo hace automáticamente).
	 */
	public function updateMatrix():Void
	{
		modelMatrix.setTRS(x, y, z, rotX, rotY, rotZ, scaleX, scaleY, scaleZ);
	}

	/** Helpers de posición rápida. */
	public inline function setPosition(px:Float, py:Float, pz:Float):Void
		{ x = px; y = py; z = pz; }

	public inline function setRotation(rx:Float, ry:Float, rz:Float):Void
		{ rotX = rx; rotY = ry; rotZ = rz; }

	public inline function setScale(sx:Float, sy:Float, sz:Float):Void
		{ scaleX = sx; scaleY = sy; scaleZ = sz; }

	public inline function setUniformScale(s:Float):Void
		{ scaleX = s; scaleY = s; scaleZ = s; }
}
