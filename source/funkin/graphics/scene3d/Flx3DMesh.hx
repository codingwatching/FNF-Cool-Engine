package funkin.graphics.scene3d;

import openfl.display3D.Context3D;
import openfl.display3D.VertexBuffer3D;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.Context3DVertexBufferFormat;
import lime.utils.Float32Array;
import lime.utils.UInt16Array;

/**
 * Flx3DMesh — Geometría 3D almacenada en GPU.
 *
 * Formato de vértice (10 floats por vértice, stride = 40 bytes):
 *   [0..2]  position  (x, y, z)
 *   [3..5]  normal    (nx, ny, nz)
 *   [6..7]  uv        (u, v)
 *   [8..9]  color     (r, g)   ← usamos 2 floats para pack RGBA (b en color.b, a en color.a del shader)
 *
 * Optimización: los VBO/IBO se suben una sola vez a GPU y se reusan.
 * Para meshes dinámicas, llama rebuild() cuando cambie la geometría.
 */
class Flx3DMesh
{
	// Stride: position(3) + normal(3) + uv(2) + color(4) = 12 floats = 48 bytes
	// pero usamos 10 para mantenerlo alineado en 4 floats/registro de Context3D
	static inline final STRIDE   = 12; // floats por vértice
	static inline final FLOATS_P = 3;  // position offset
	static inline final FLOATS_N = 3;  // normal offset
	static inline final FLOATS_U = 2;  // uv offset
	static inline final FLOATS_C = 4;  // color offset (r,g,b,a)

	/** Datos de vértices en CPU (Float32Array para carga directa a GPU). */
	public var vertices(default, null):Float32Array;
	/** Índices de triángulos en CPU. */
	public var indices(default, null):UInt16Array;
	/** Número de triángulos = indices.length / 3. */
	public var triangleCount(default, null):Int = 0;
	/** Número de vértices. */
	public var vertexCount(default, null):Int = 0;

	/** Nombre para debug. */
	public var name:String = 'mesh';

	var _vbo  :Null<VertexBuffer3D> = null;
	var _ibo  :Null<IndexBuffer3D>  = null;
	var _dirty:Bool = true;

	public function new() {}

	// ── Construcción de geometría ──────────────────────────────────────────

	/**
	 * Carga geometría cruda.
	 * @param verts   Array plano de floats: [x,y,z, nx,ny,nz, u,v, r,g,b,a, ...] por vértice
	 * @param idxs    Array de índices (triángulos, sin strip)
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
	 * Sube la geometría a GPU si está marcada como dirty.
	 * Llamado automáticamente por Flx3DScene antes de cada draw.
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
	 * Registra los atributos de vértice en Context3D y dibuja el mesh.
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

	/** Marcar geometría como sucia para re-subir en el próximo draw. */
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
