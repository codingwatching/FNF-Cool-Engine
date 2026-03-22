package funkin.graphics.scene3d;

/**
 * Flx3DCamera — Camera 3D with projection perspectiva.
 *
 * Controls position, orientation and projection parameters.
 * Las matrices view/projection se recalculan solo cuando cambian
 * the parameters (dirty flag), not every frame.
 */
class Flx3DCamera
{
	// ── Position and orientation ──────────────────────────────────────────────

	/** Position in espacio mundo. */
	public var position:Vec3 = new Vec3(0, 0, 5);
	/** Punto al que mira. */
	public var target:Vec3   = new Vec3(0, 0, 0);
	/** Vector "arriba" (normalmente 0,1,0). */
	public var up:Vec3       = new Vec3(0, 1, 0);

	// ── Projection ─────────────────────────────────────────────────────────

	/** Field of view vertical en grados. */
	public var fovDegrees(default, set):Float = 60.0;
	function set_fovDegrees(v:Float):Float { fovDegrees = v; _projDirty = true; return v; }

	/** Aspect ratio (ancho/alto). */
	public var aspect(default, set):Float = 16/9;
	function set_aspect(v:Float):Float { aspect = v; _projDirty = true; return v; }

	/** Plano cercano de recorte. */
	public var near(default, set):Float = 0.1;
	function set_near(v:Float):Float { near = v; _projDirty = true; return v; }

	/** Plano lejano de recorte. */
	public var far(default, set):Float = 1000.0;
	function set_far(v:Float):Float { far = v; _projDirty = true; return v; }

	// ── Matrices ────────────────────────────────────────────────────────────

	/** Matriz de vista (world → camera space). */
	public var viewMatrix     (default, null):Mat4 = new Mat4();
	/** Matriz of projection (camera → clip space). */
	public var projMatrix     (default, null):Mat4 = new Mat4();
	/** Combination viewProj precalculada. */
	public var viewProjMatrix (default, null):Mat4 = new Mat4();

	var _projDirty:Bool = true;
	var _tmp:Mat4 = new Mat4();

	public function new() {}

	// ── API ────────────────────────────────────────────────────────────────

	/** Actualiza las matrices si es necesario. Llamar antes de cada render. */
	public function update():Void
	{
		// View always is recalcula (position/target pueden change each frame)
		viewMatrix.setLookAt(
			position.x, position.y, position.z,
			target.x,   target.y,   target.z,
			up.x,       up.y,       up.z
		);

		if (_projDirty)
		{
			_projDirty = false;
			projMatrix.setPerspective(fovDegrees * (Math.PI / 180.0), aspect, near, far);
		}

		Mat4.multiply(projMatrix, viewMatrix, viewProjMatrix);
	}

	/** Moves the camera for orbitar alrededor of the target. */
	public function orbit(yawDeg:Float, pitchDeg:Float, radius:Float):Void
	{
		final yaw   = yawDeg   * (Math.PI / 180.0);
		final pitch = pitchDeg * (Math.PI / 180.0);

		position.x = target.x + radius * Math.cos(pitch) * Math.sin(yaw);
		position.y = target.y + radius * Math.sin(pitch);
		position.z = target.z + radius * Math.cos(pitch) * Math.cos(yaw);
	}
}
