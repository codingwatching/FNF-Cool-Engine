package funkin.graphics.scene3d;

import openfl.display3D.textures.RectangleTexture;

/**
 * Flx3DObject — Nodo de la escena 3D.
 *
 * Combina transform (TRS), mesh y material opcional.
 * The model matrix is only recalculated when some field changes.
 */
class Flx3DObject
{
	// ── Identification ──────────────────────────────────────────────────────

	public var name   :String  = 'object';
	public var visible:Bool    = true;
	public var active :Bool    = true;

	// ── Transform ───────────────────────────────────────────────────────────

	public var x      :Float = 0;
	public var y      :Float = 0;
	public var z      :Float = 0;

	/** Rotation in radianes (orden XYZ). */
	public var rotX   :Float = 0;
	public var rotY   :Float = 0;
	public var rotZ   :Float = 0;

	public var scaleX :Float = 1;
	public var scaleY :Float = 1;
	public var scaleZ :Float = 1;

	// ── Material ────────────────────────────────────────────────────────────

	/** Mesh asignado a este objeto. */
	public var mesh    :Null<Flx3DMesh>          = null;
	/** Texture difusa (if is null, is use the color of the vertex). */
	public var texture :Null<RectangleTexture>   = null;
	/** Multiplicador de color base [r,g,b,a]. */
	public var tint    :Array<Float>             = [1,1,1,1];

	/** If true, receives lighting. If false, rendered without lighting (unlit). */
	public var lit     :Bool = true;
	/** Factor de brillo especular (0=mate, 1=brillante). */
	public var shininess:Float = 32.0;

	// ── Matriz de modelo ────────────────────────────────────────────────────

	public var modelMatrix(default, null):Mat4 = new Mat4();

	// ── API ────────────────────────────────────────────────────────────────

	public function new() {}

	/**
	 * Recalcula la matriz de modelo a partir de position/rotation/scale.
	 * Callr before of each render (Flx3DScene it hace automatically).
	 */
	public function updateMatrix():Void
	{
		modelMatrix.setTRS(x, y, z, rotX, rotY, rotZ, scaleX, scaleY, scaleZ);
	}

	/** Helpers of position fast. */
	public inline function setPosition(px:Float, py:Float, pz:Float):Void
		{ x = px; y = py; z = pz; }

	public inline function setRotation(rx:Float, ry:Float, rz:Float):Void
		{ rotX = rx; rotY = ry; rotZ = rz; }

	public inline function setScale(sx:Float, sy:Float, sz:Float):Void
		{ scaleX = sx; scaleY = sy; scaleZ = sz; }

	public inline function setUniformScale(s:Float):Void
		{ scaleX = s; scaleY = s; scaleZ = s; }
}
