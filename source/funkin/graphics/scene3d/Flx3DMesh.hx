package funkin.graphics.scene3d;

import openfl.display3D.Context3D;
import openfl.display3D.VertexBuffer3D;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.Context3DVertexBufferFormat;
import lime.utils.Float32Array;
import lime.utils.UInt16Array;

/**
 * Flx3DMesh — Geometry 3D almacenada in GPU.
 *
 * Format of vertex (10 floats by vertex, stride = 40 bytes):
 *   [0..2]  position  (x, y, z)
 *   [3..5]  normal    (nx, ny, nz)
 *   [6..7]  uv        (u, v)
 *   [8..9]  color     (r, g)   ← usamos 2 floats para pack RGBA (b en color.b, a en color.a del shader)
 *
 * Optimization: the VBO/IBO is suben a sola vez to GPU and is reusan.
 * For meshes dynamic, call rebuild() when cambie the geometry.
 */
class Flx3DMesh
{
	// Stride: position(3) + normal(3) + uv(2) + color(4) = 12 floats = 48 bytes
	// pero usamos 10 para mantenerlo alineado en 4 floats/registro de Context3D
	static inline end STRIDE   = 12; // floats by vertex
	static inline final FLOATS_P = 3;  // position offset
	static inline final FLOATS_N = 3;  // normal offset
	static inline final FLOATS_U = 2;  // uv offset
	static inline final FLOATS_C = 4;  // color offset (r,g,b,a)

	/** Datos de vertices en CPU (Float32Array para carga directa a GPU). */
	public var vertices(default, null):Float32Array;
	/** Indices of triangles in CPU. */
	public var indices(default, null):UInt16Array;
	/** Number of triangles = indices.length / 3. */
	public var triangleCount(default, null):Int = 0;
	/** Number of vertices. */
	public var vertexCount(default, null):Int = 0;

	/** Nombre para debug. */
	public var name:String = 'mesh';

	var _vbo  :Null<VertexBuffer3D> = null;
	var _ibo  :Null<IndexBuffer3D>  = null;
	var _dirty:Bool = true;

	public function new() {}

	// ── Build of geometry ──────────────────────────────────────────

	/**
	 * Load geometry cruda.
	 * @param verts   Array plano of floats: [x,and,z, nx,ny,nz, u,v, r,g,b,to, ...] by vertex
	 * @param idxs    Array of indices (triangles, without strip)
	 */
	public function setGeometry(verts:Array<Float>, idxs:Array<Int>):Void
	{
		vertexCount   = Std.int(verts.length / STRIDE);
		triangleCount = Std.int(idxs.length / 3);

		vertices = new Float32Array(verts.length);
		for (i in 0...verts.length) vertices[i] = verts[i];

		indices = new UInt16Array(idxs.length);
		for (i in 0...idxs.length) indices[i] = idxs[i];

		_dirty = true;
	}

	// ── Upload / bind ──────────────────────────────────────────────────────

	/**
	 * Sube the geometry to GPU if is marcada as dirty.
	 * Calldo automatically by Flx3DScene before of each draw.
	 */
	public function upload(ctx:Context3D):Void
	{
		if (!_dirty) return;
		_dirty = false;

		if (vertices == null || indices == null) return;

		// Destruir buffers anteriores
		if (_vbo != null) { _vbo.dispose(); _vbo = null; }
		if (_ibo != null) { _ibo.dispose(); _ibo = null; }

		_vbo = ctx.createVertexBuffer(vertexCount, STRIDE);
		_vbo.uploadFromTypedArray(vertices);

		_ibo = ctx.createIndexBuffer(indices.length);
		_ibo.uploadFromTypedArray(indices);
	}

	/**
	 * Registra the attributes of vertex in Context3D and draws the mesh.
	 * Slots de atributo:
	 *   0 = position (va_position en GLSL)
	 *   1 = normal   (va_normal)
	 *   2 = uv       (va_uv)
	 *   3 = color    (va_color)
	 */
	public function draw(ctx:Context3D):Void
	{
		if (_vbo == null || _ibo == null || triangleCount == 0) return;

		ctx.setVertexBufferAt(0, _vbo, 0,  Context3DVertexBufferFormat.FLOAT_3); // position
		ctx.setVertexBufferAt(1, _vbo, 3,  Context3DVertexBufferFormat.FLOAT_3); // normal
		ctx.setVertexBufferAt(2, _vbo, 6,  Context3DVertexBufferFormat.FLOAT_2); // uv
		ctx.setVertexBufferAt(3, _vbo, 8,  Context3DVertexBufferFormat.FLOAT_4); // color

		ctx.drawTriangles(_ibo, 0, triangleCount);
	}

	/** Marcar geometry as sucia for re-subir in the next draw. */
	public inline function markDirty():Void _dirty = true;

	/** Liberar recursos de GPU. */
	public function dispose():Void
	{
		if (_vbo != null) { _vbo.dispose(); _vbo = null; }
		if (_ibo != null) { _ibo.dispose(); _ibo = null; }
		vertices = null;
		indices  = null;
	}
}
