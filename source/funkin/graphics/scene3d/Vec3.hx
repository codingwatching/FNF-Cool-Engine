package funkin.graphics.scene3d;

/**
 * Vec3 — Vector 3D de punto flotante con operaciones inline.
 * No genera heap allocation en uso normal (estructuras de valor).
 */
@:structInit
class Vec3
{
	public var x:Float;
	public var y:Float;
	public var z:Float;

	public inline function new(x:Float = 0, y:Float = 0, z:Float = 0)
	{
		this.x = x; this.y = y; this.z = z;
	}

	public inline function set(x:Float, y:Float, z:Float):Vec3
		{ this.x = x; this.y = y; this.z = z; return this; }

	public inline function copyFrom(v:Vec3):Vec3
		{ x = v.x; y = v.y; z = v.z; return this; }

	public inline function clone():Vec3 return new Vec3(x, y, z);

	// ── Arithmetic ─────────────────────────────────────────────────────────

	public inline function add(v:Vec3):Vec3         return new Vec3(x+v.x, y+v.y, z+v.z);
	public inline function sub(v:Vec3):Vec3         return new Vec3(x-v.x, y-v.y, z-v.z);
	public inline function scale(s:Float):Vec3      return new Vec3(x*s,   y*s,   z*s);
	public inline function negate():Vec3            return new Vec3(-x, -y, -z);

	public inline function addSelf(v:Vec3):Vec3     { x+=v.x; y+=v.y; z+=v.z; return this; }
	public inline function subSelf(v:Vec3):Vec3     { x-=v.x; y-=v.y; z-=v.z; return this; }
	public inline function scaleSelf(s:Float):Vec3  { x*=s;   y*=s;   z*=s;   return this; }

	// ── Producto punto / cruzado ────────────────────────────────────────────

	public inline function dot(v:Vec3):Float
		return x*v.x + y*v.y + z*v.z;

	public inline function cross(v:Vec3):Vec3
		return new Vec3(y*v.z - z*v.y, z*v.x - x*v.z, x*v.y - y*v.x);

	// ── Magnitud ────────────────────────────────────────────────────────────

	public inline function lengthSq():Float return x*x + y*y + z*z;
	public inline function length():Float   return Math.sqrt(x*x + y*y + z*z);

	public inline function normalize():Vec3
	{
		final l = length();
		return l > 1e-10 ? new Vec3(x/l, y/l, z/l) : new Vec3(0,0,0);
	}

	public inline function normalizeSelf():Vec3
	{
		final l = length();
		if (l > 1e-10) { x/=l; y/=l; z/=l; }
		return this;
	}

	// ── Interpolation ───────────────────────────────────────────────────────

	public static inline function lerp(a:Vec3, b:Vec3, t:Float):Vec3
		return new Vec3(a.x + (b.x-a.x)*t, a.y + (b.y-a.y)*t, a.z + (b.z-a.z)*t);

	// ── Commonly used statics ──────────────────────────────────────────────

	public static final ZERO   = new Vec3(0,  0,  0);
	public static final ONE    = new Vec3(1,  1,  1);
	public static final UP     = new Vec3(0,  1,  0);
	public static final FORWARD = new Vec3(0, 0, -1);
	public static final RIGHT  = new Vec3(1,  0,  0);

	public function toString():String return 'Vec3($x, $y, $z)';
}
