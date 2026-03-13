package funkin.graphics.scene3d;

/**
 * Flx3DCamera — Cámara 3D con proyección perspectiva.
 *
 * Controla posición, orientación y parámetros de proyección.
 * Las matrices view/projection se recalculan solo cuando cambian
 * los parámetros (dirty flag), no cada frame.
 */
class Flx3DCamera
{
	// ── Posición y orientación ──────────────────────────────────────────────

	/** Posición en espacio mundo. */
	public var position:Vec3 = new Vec3(0, 0, 5);
	/** Punto al que mira. */
	public var target:Vec3   = new Vec3(0, 0, 0);
	/** Vector "arriba" (normalmente 0,1,0). */
	public var up:Vec3       = new Vec3(0, 1, 0);

	// ── Proyección ─────────────────────────────────────────────────────────

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
	/** Matriz de proyección (camera → clip space). */
	public var projMatrix     (default, null):Mat4 = new Mat4();
	/** Combinación viewProj precalculada. */
	public var viewProjMatrix (default, null):Mat4 = new Mat4();

	var _projDirty:Bool = true;
	var _tmp:Mat4 = new Mat4();

	public function new() {}

	// ── API ────────────────────────────────────────────────────────────────

	/** Actualiza las matrices si es necesario. Llamar antes de cada render. */
	public function update():Void
	{
		// View siempre se recalcula (posición/target pueden cambiar cada frame)
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

	/** Mueve la cámara para orbitar alrededor del target. */
	public function orbit(yawDeg:Float, pitchDeg:Float, radius:Float):Void
	{
		final yaw   = yawDeg   * (Math.PI / 180.0);
		final pitch = pitchDeg * (Math.PI / 180.0);

		position.x = target.x + radius * Math.cos(pitch) * Math.sin(yaw);
		position.y = target.y + radius * Math.sin(pitch);
		position.z = target.z + radius * Math.cos(pitch) * Math.cos(yaw);
	}
}
