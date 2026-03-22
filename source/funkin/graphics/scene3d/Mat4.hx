package funkin.graphics.scene3d;

/**
 * Mat4 — Matriz 4×4 column-major para transformaciones 3D.
 *
 * Almacena 16 floats en un Array<Float> plano indexado [col*4 + row].
 * Critical operations (multiply, transformVec3) are inline for
 * que el compilador C++ las expanda sin overhead de llamada.
 *
 * Compatible con openfl.display3D.Context3D.setProgramConstantsFromMatrix()
 * que espera exactamente este layout column-major.
 */
class Mat4
{
	public var m:Array<Float>;

	public inline function new()
	{
		m = [
			1,0,0,0,
			0,1,0,0,
			0,0,1,0,
			0,0,0,1
		];
	}

	// ── Identidad ──────────────────────────────────────────────────────────

	public inline function identity():Mat4
	{
		m[0]=1; m[1]=0; m[2]=0;  m[3]=0;
		m[4]=0; m[5]=1; m[6]=0;  m[7]=0;
		m[8]=0; m[9]=0; m[10]=1; m[11]=0;
		m[12]=0;m[13]=0;m[14]=0; m[15]=1;
		return this;
	}

	// ── Copia ──────────────────────────────────────────────────────────────

	public inline function copyFrom(src:Mat4):Mat4
	{
		for (i in 0...16) m[i] = src.m[i];
		return this;
	}

	public inline function clone():Mat4
	{
		final r = new Mat4();
		for (i in 0...16) r.m[i] = m[i];
		return r;
	}

	// ── Multiplication (this × b, result in out — avoids new) ───────────

	public static inline function multiply(a:Mat4, b:Mat4, out:Mat4):Mat4
	{
		final am = a.m; final bm = b.m; final om = out.m;

		om[0]  = am[0]*bm[0]  + am[4]*bm[1]  + am[8]*bm[2]  + am[12]*bm[3];
		om[1]  = am[1]*bm[0]  + am[5]*bm[1]  + am[9]*bm[2]  + am[13]*bm[3];
		om[2]  = am[2]*bm[0]  + am[6]*bm[1]  + am[10]*bm[2] + am[14]*bm[3];
		om[3]  = am[3]*bm[0]  + am[7]*bm[1]  + am[11]*bm[2] + am[15]*bm[3];

		om[4]  = am[0]*bm[4]  + am[4]*bm[5]  + am[8]*bm[6]  + am[12]*bm[7];
		om[5]  = am[1]*bm[4]  + am[5]*bm[5]  + am[9]*bm[6]  + am[13]*bm[7];
		om[6]  = am[2]*bm[4]  + am[6]*bm[5]  + am[10]*bm[6] + am[14]*bm[7];
		om[7]  = am[3]*bm[4]  + am[7]*bm[5]  + am[11]*bm[6] + am[15]*bm[7];

		om[8]  = am[0]*bm[8]  + am[4]*bm[9]  + am[8]*bm[10] + am[12]*bm[11];
		om[9]  = am[1]*bm[8]  + am[5]*bm[9]  + am[9]*bm[10] + am[13]*bm[11];
		om[10] = am[2]*bm[8]  + am[6]*bm[9]  + am[10]*bm[10]+ am[14]*bm[11];
		om[11] = am[3]*bm[8]  + am[7]*bm[9]  + am[11]*bm[10]+ am[15]*bm[11];

		om[12] = am[0]*bm[12] + am[4]*bm[13] + am[8]*bm[14] + am[12]*bm[15];
		om[13] = am[1]*bm[12] + am[5]*bm[13] + am[9]*bm[14] + am[13]*bm[15];
		om[14] = am[2]*bm[12] + am[6]*bm[13] + am[10]*bm[14]+ am[14]*bm[15];
		om[15] = am[3]*bm[12] + am[7]*bm[13] + am[11]*bm[14]+ am[15]*bm[15];
		return out;
	}

	// ── Transformar Vec3 (sin dividir por w) ───────────────────────────────

	public inline function transformVec3(v:Vec3, out:Vec3):Vec3
	{
		final x = m[0]*v.x + m[4]*v.y + m[8]*v.z  + m[12];
		final y = m[1]*v.x + m[5]*v.y + m[9]*v.z  + m[13];
		final z = m[2]*v.x + m[6]*v.y + m[10]*v.z + m[14];
		out.x = x; out.y = y; out.z = z;
		return out;
	}

	// ── Translation / Scales / Rotation ─────────────────────────────────────

	public inline function setTranslation(x:Float, y:Float, z:Float):Mat4
	{
		identity();
		m[12] = x; m[13] = y; m[14] = z;
		return this;
	}

	public inline function setScale(x:Float, y:Float, z:Float):Mat4
	{
		identity();
		m[0] = x; m[5] = y; m[10] = z;
		return this;
	}

	public inline function setRotationX(rad:Float):Mat4
	{
		final c = Math.cos(rad); final s = Math.sin(rad);
		identity();
		m[5]  =  c; m[9]  = -s;
		m[6]  =  s; m[10] =  c;
		return this;
	}

	public inline function setRotationY(rad:Float):Mat4
	{
		final c = Math.cos(rad); final s = Math.sin(rad);
		identity();
		m[0]  =  c; m[8]  =  s;
		m[2]  = -s; m[10] =  c;
		return this;
	}

	public inline function setRotationZ(rad:Float):Mat4
	{
		final c = Math.cos(rad); final s = Math.sin(rad);
		identity();
		m[0]  =  c; m[4]  = -s;
		m[1]  =  s; m[5]  =  c;
		return this;
	}

	// ── TRS composition from Euler ────────────────────────────────────────

	static var _tmp1:Mat4 = new Mat4();
	static var _tmp2:Mat4 = new Mat4();

	/**
	 * Construye la matriz TRS: Translation × Rotation(XYZ euler) × Scale.
	 * Reutiliza buffers static for avoid allocations in the loop of render.
	 */
	public function setTRS(tx:Float, ty:Float, tz:Float,
	                       rx:Float, ry:Float, rz:Float,
	                       sx:Float, sy:Float, sz:Float):Mat4
	{
		// Rx
		final cx = Math.cos(rx); final sx2 = Math.sin(rx);
		// Ry
		final cy = Math.cos(ry); final sy2 = Math.sin(ry);
		// Rz
		final cz = Math.cos(rz); final sz2 = Math.sin(rz);

		// Combined rotation Rz * Ry * Rx (column-major, scale baked in)
		m[0]  = cy*cz*sx;
		m[1]  = cy*sz2*sx;
		m[2]  = -sy2*sx;
		m[3]  = 0;

		m[4]  = (sx2*sy2*cz - cx*sz2)*sy;
		m[5]  = (sx2*sy2*sz2 + cx*cz)*sy;
		m[6]  = sx2*cy*sy;
		m[7]  = 0;

		m[8]  = (cx*sy2*cz + sx2*sz2)*sz;
		m[9]  = (cx*sy2*sz2 - sx2*cz)*sz;
		m[10] = cx*cy*sz;
		m[11] = 0;

		m[12] = tx; m[13] = ty; m[14] = tz; m[15] = 1;
		return this;
	}

	// ── Perspective projection ──────────────────────────────────────────────

	/**
	 * Projection perspectiva standard (column-major, clip space OpenGL [-1,1]).
	 * @param fovY   vertical field of view in radians
	 * @param aspect ancho/alto
	 * @param near   plano cercano (> 0)
	 * @param far    plano lejano
	 */
	public function setPerspective(fovY:Float, aspect:Float, near:Float, far:Float):Mat4
	{
		final f  = 1.0 / Math.tan(fovY * 0.5);
		final nf = 1.0 / (near - far);

		m[0]=f/aspect; m[1]=0; m[2]=0;               m[3]=0;
		m[4]=0;        m[5]=f; m[6]=0;               m[7]=0;
		m[8]=0;        m[9]=0; m[10]=(far+near)*nf;  m[11]=-1;
		m[12]=0;       m[13]=0;m[14]=2*far*near*nf;  m[15]=0;
		return this;
	}

	// ── LookAt ─────────────────────────────────────────────────────────────

	/**
	 * Construye la matriz de vista (eye → center, up).
	 */
	public function setLookAt(ex:Float, ey:Float, ez:Float,
	                          cx2:Float, cy2:Float, cz2:Float,
	                          ux:Float, uy:Float, uz:Float):Mat4
	{
		var fx = cx2-ex; var fy = cy2-ey; var fz = cz2-ez;
		var fl = Math.sqrt(fx*fx+fy*fy+fz*fz);
		if (fl < 1e-10) { identity(); return this; }
		fx/=fl; fy/=fl; fz/=fl;

		var sx = fy*uz - fz*uy;
		var sy = fz*ux - fx*uz;
		var sz = fx*uy - fy*ux;
		var sl = Math.sqrt(sx*sx+sy*sy+sz*sz);
		if (sl > 1e-10) { sx/=sl; sy/=sl; sz/=sl; }

		final ux2 = sy*fz - sz*fy;
		final uy2 = sz*fx - sx*fz;
		final uz2 = sx*fy - sy*fx;

		m[0]=sx;  m[1]=ux2; m[2]=-fx;  m[3]=0;
		m[4]=sy;  m[5]=uy2; m[6]=-fy;  m[7]=0;
		m[8]=sz;  m[9]=uz2; m[10]=-fz; m[11]=0;
		m[12]=-(sx*ex+sy*ey+sz*ez);
		m[13]=-(ux2*ex+uy2*ey+uz2*ez);
		m[14]= (fx*ex+fy*ey+fz*ez);
		m[15]=1;
		return this;
	}

	// ── Inversion (for normals) ───────────────────────────────────────────

	/**
	 * Invierte la matriz y la pone en `out`. Devuelve false si es singular.
	 */
	public function invert(out:Mat4):Bool
	{
		final a = m; final b = out.m;
		final a00=a[0]; final a01=a[1]; final a02=a[2];  final a03=a[3];
		final a10=a[4]; final a11=a[5]; final a12=a[6];  final a13=a[7];
		final a20=a[8]; final a21=a[9]; final a22=a[10]; final a23=a[11];
		final a30=a[12];final a31=a[13];final a32=a[14]; final a33=a[15];

		final b00=a00*a11-a01*a10; final b01=a00*a12-a02*a10;
		final b02=a00*a13-a03*a10; final b03=a01*a12-a02*a11;
		final b04=a01*a13-a03*a11; final b05=a02*a13-a03*a12;
		final b06=a20*a31-a21*a30; final b07=a20*a32-a22*a30;
		final b08=a20*a33-a23*a30; final b09=a21*a32-a22*a31;
		final b10=a21*a33-a23*a31; final b11=a22*a33-a23*a32;

		var det = b00*b11-b01*b10+b02*b09+b03*b08-b04*b07+b05*b06;
		if (Math.abs(det) < 1e-15) return false;
		det = 1.0/det;

		b[0] =( a11*b11-a12*b10+a13*b09)*det;
		b[1] =(-a01*b11+a02*b10-a03*b09)*det;
		b[2] =( a31*b05-a32*b04+a33*b03)*det;
		b[3] =(-a21*b05+a22*b04-a23*b03)*det;
		b[4] =(-a10*b11+a12*b08-a13*b07)*det;
		b[5] =( a00*b11-a02*b08+a03*b07)*det;
		b[6] =(-a30*b05+a32*b02-a33*b01)*det;
		b[7] =( a20*b05-a22*b02+a23*b01)*det;
		b[8] =( a10*b10-a11*b08+a13*b06)*det;
		b[9] =(-a00*b10+a01*b08-a03*b06)*det;
		b[10]=( a30*b04-a31*b02+a33*b00)*det;
		b[11]=(-a20*b04+a21*b02-a23*b00)*det;
		b[12]=(-a10*b09+a11*b07-a12*b06)*det;
		b[13]=( a00*b09-a01*b07+a02*b06)*det;
		b[14]=(-a30*b03+a31*b01-a32*b00)*det;
		b[15]=( a20*b03-a21*b01+a22*b00)*det;
		return true;
	}

	// ── Transponer (para normales mat) ──────────────────────────────────────

	public inline function transpose(out:Mat4):Mat4
	{
		final a = m; final b = out.m;
		b[0]=a[0]; b[1]=a[4]; b[2]=a[8];  b[3]=a[12];
		b[4]=a[1]; b[5]=a[5]; b[6]=a[9];  b[7]=a[13];
		b[8]=a[2]; b[9]=a[6]; b[10]=a[10];b[11]=a[14];
		b[12]=a[3];b[13]=a[7];b[14]=a[11];b[15]=a[15];
		return out;
	}
}
