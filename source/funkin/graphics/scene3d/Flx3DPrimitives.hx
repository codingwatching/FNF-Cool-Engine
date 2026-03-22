package funkin.graphics.scene3d;

/**
 * Flx3DPrimitives — constructores of geometry basic 3D.
 * Todos devuelven un Flx3DMesh listo para usar.
 */
class Flx3DPrimitives
{
	// ── Cubo ───────────────────────────────────────────────────────────────

	/**
	 * Cubo unitario centrado en el origen (w=h=d=1).
	 * @param w   ancho   (X)
	 * @param h   alto    (Y)
	 * @param d   profundidad (Z)
	 * @param r,g,b,a color by default de todos los vertices
	 */
	public static function cube(w:Float=1, h:Float=1, d:Float=1,
	                            r:Float=1, g:Float=1, b:Float=1, a:Float=1):Flx3DMesh
	{
		final hx = w*0.5; final hy = h*0.5; final hz = d*0.5;

		// Cada cara tiene 4 vertices (no compartidos para normales correctas)
		// stride: x,y,z, nx,ny,nz, u,v, r,g,b,a  = 12 floats
		final v:Array<Float> = [
			// Frente (+Z)
			-hx,-hy, hz,  0,0,1,  0,1,  r,g,b,a,
			 hx,-hy, hz,  0,0,1,  1,1,  r,g,b,a,
			 hx, hy, hz,  0,0,1,  1,0,  r,g,b,a,
			-hx, hy, hz,  0,0,1,  0,0,  r,g,b,a,
			// Back (-Z)
			 hx,-hy,-hz,  0,0,-1, 0,1,  r,g,b,a,
			-hx,-hy,-hz,  0,0,-1, 1,1,  r,g,b,a,
			-hx, hy,-hz,  0,0,-1, 1,0,  r,g,b,a,
			 hx, hy,-hz,  0,0,-1, 0,0,  r,g,b,a,
			// Izquierda (-X)
			-hx,-hy,-hz, -1,0,0,  0,1,  r,g,b,a,
			-hx,-hy, hz, -1,0,0,  1,1,  r,g,b,a,
			-hx, hy, hz, -1,0,0,  1,0,  r,g,b,a,
			-hx, hy,-hz, -1,0,0,  0,0,  r,g,b,a,
			// Derecha (+X)
			 hx,-hy, hz,  1,0,0,  0,1,  r,g,b,a,
			 hx,-hy,-hz,  1,0,0,  1,1,  r,g,b,a,
			 hx, hy,-hz,  1,0,0,  1,0,  r,g,b,a,
			 hx, hy, hz,  1,0,0,  0,0,  r,g,b,a,
			// Arriba (+Y)
			-hx, hy, hz,  0,1,0,  0,1,  r,g,b,a,
			 hx, hy, hz,  0,1,0,  1,1,  r,g,b,a,
			 hx, hy,-hz,  0,1,0,  1,0,  r,g,b,a,
			-hx, hy,-hz,  0,1,0,  0,0,  r,g,b,a,
			// Abajo (-Y)
			-hx,-hy,-hz,  0,-1,0, 0,1,  r,g,b,a,
			 hx,-hy,-hz,  0,-1,0, 1,1,  r,g,b,a,
			 hx,-hy, hz,  0,-1,0, 1,0,  r,g,b,a,
			-hx,-hy, hz,  0,-1,0, 0,0,  r,g,b,a,
		];

		final idx:Array<Int> = [];
		for (f in 0...6)
		{
			final base = f * 4;
			idx.push(base);   idx.push(base+1); idx.push(base+2);
			idx.push(base);   idx.push(base+2); idx.push(base+3);
		}

		final mesh = new Flx3DMesh();
		mesh.name  = 'cube';
		mesh.setGeometry(v, idx);
		return mesh;
	}

	// ── Plano ──────────────────────────────────────────────────────────────

	/**
	 * Plano XZ centrado en el origen, subdividido.
	 * @param w,d        dimensiones
	 * @param segW,segD  subdivisiones in X and Z (minimum 1)
	 */
	public static function plane(w:Float=1, d:Float=1, segW:Int=1, segD:Int=1,
	                             r:Float=1, g:Float=1, b:Float=1, a:Float=1):Flx3DMesh
	{
		if (segW < 1) segW = 1;
		if (segD < 1) segD = 1;

		final v:Array<Float>  = [];
		final idx:Array<Int>  = [];
		final hw = w * 0.5;
		final hd = d * 0.5;

		for (iz in 0...(segD+1))
		{
			for (ix in 0...(segW+1))
			{
				final fx = ix / segW;
				final fz = iz / segD;
				v.push(-hw + fx*w);  // x
				v.push(0);            // y
				v.push(-hd + fz*d);  // z
				v.push(0); v.push(1); v.push(0); // normal up
				v.push(fx); v.push(fz);           // uv
				v.push(r);  v.push(g); v.push(b); v.push(a);
			}
		}

		final cols = segW + 1;
		for (iz in 0...segD)
		{
			for (ix in 0...segW)
			{
				final tl = iz*cols + ix;
				idx.push(tl);        idx.push(tl+cols);   idx.push(tl+1);
				idx.push(tl+1);      idx.push(tl+cols);   idx.push(tl+cols+1);
			}
		}

		final mesh = new Flx3DMesh();
		mesh.name  = 'plane';
		mesh.setGeometry(v, idx);
		return mesh;
	}

	// ── Esfera UV ──────────────────────────────────────────────────────────

	/**
	 * Esfera UV (longitud/latitud).
	 * @param radius   radio
	 * @param segW     segmentos horizontales (≥3)
	 * @param segH     segmentos verticales   (≥2)
	 */
	public static function sphere(radius:Float=0.5, segW:Int=16, segH:Int=12,
	                              r:Float=1, g:Float=1, b:Float=1, a:Float=1):Flx3DMesh
	{
		if (segW < 3) segW = 3;
		if (segH < 2) segH = 2;

		final v:Array<Float> = [];
		final idx:Array<Int> = [];
		final PI = Math.PI;
		final TAU = 2.0 * PI;

		for (iy in 0...(segH+1))
		{
			final phi = PI * iy / segH;
			for (ix in 0...(segW+1))
			{
				final theta = TAU * ix / segW;
				final sp = Math.sin(phi);
				final cp = Math.cos(phi);
				final st = Math.sin(theta);
				final ct = Math.cos(theta);

				final nx2 = sp * ct;
				final ny2 = cp;
				final nz2 = sp * st;

				v.push(radius*nx2); v.push(radius*ny2); v.push(radius*nz2);
				v.push(nx2); v.push(ny2); v.push(nz2);
				v.push(ix/segW); v.push(iy/segH);
				v.push(r); v.push(g); v.push(b); v.push(a);
			}
		}

		final cols = segW + 1;
		for (iy in 0...segH)
		{
			for (ix in 0...segW)
			{
				final tl = iy*cols + ix;
				if (iy > 0)
				{
					idx.push(tl);      idx.push(tl+cols); idx.push(tl+1);
				}
				if (iy < segH-1)
				{
					idx.push(tl+1);    idx.push(tl+cols); idx.push(tl+cols+1);
				}
			}
		}

		final mesh = new Flx3DMesh();
		mesh.name  = 'sphere';
		mesh.setGeometry(v, idx);
		return mesh;
	}

	// ── Cilindro ──────────────────────────────────────────────────────────

	/**
	 * Cilindro con tapas, centrado en el origen, eje Y.
	 * @param radius     radio de la base
	 * @param height     altura total
	 * @param segments   subdivisiones angulares (≥3)
	 */
	public static function cylinder(radius:Float=0.5, height:Float=1.0, segments:Int=16,
	                                r:Float=1, g:Float=1, b:Float=1, a:Float=1):Flx3DMesh
	{
		if (segments < 3) segments = 3;

		final v:Array<Float> = [];
		final idx:Array<Int> = [];
		final hy = height * 0.5;
		final PI = Math.PI;
		final TAU = 2.0 * PI;

		// ── Cuerpo lateral ──────────────────────────────────────────────────
		// Dos anillos: bottom (y=-hy) y top (y=+hy), con vertices duplicados
		// para normales apuntando radialmente hacia fuera.
		for (i in 0...(segments+1))
		{
			final theta = TAU * i / segments;
			final cx = Math.cos(theta);
			final cz = Math.sin(theta);
			final u  = i / segments;

			// Ring bottom
			v.push(cx*radius); v.push(-hy); v.push(cz*radius);
			v.push(cx); v.push(0); v.push(cz); // normal radial
			v.push(u); v.push(1);
			v.push(r); v.push(g); v.push(b); v.push(a);

			// Ring top
			v.push(cx*radius); v.push( hy); v.push(cz*radius);
			v.push(cx); v.push(0); v.push(cz);
			v.push(u); v.push(0);
			v.push(r); v.push(g); v.push(b); v.push(a);
		}

		// Lateral quads
		for (i in 0...segments)
		{
			final b0 = i * 2;
			final t0 = b0 + 1;
			final b1 = b0 + 2;
			final t1 = b0 + 3;
			idx.push(b0); idx.push(b1); idx.push(t0);
			idx.push(t0); idx.push(b1); idx.push(t1);
		}

		// ── Tapa inferior ─────────────────────────────────────────────────
		end capBaseBot = Std.int(v.length / 12); // vertex index of the centro
		v.push(0); v.push(-hy); v.push(0);
		v.push(0); v.push(-1); v.push(0);
		v.push(0.5); v.push(0.5);
		v.push(r); v.push(g); v.push(b); v.push(a);

		for (i in 0...segments)
		{
			final theta = TAU * i / segments;
			final cx = Math.cos(theta);
			final cz = Math.sin(theta);
			v.push(cx*radius); v.push(-hy); v.push(cz*radius);
			v.push(0); v.push(-1); v.push(0);
			v.push(0.5 + 0.5*cx); v.push(0.5 + 0.5*cz);
			v.push(r); v.push(g); v.push(b); v.push(a);
		}

		for (i in 0...segments)
		{
			final a2 = capBaseBot + 1 + i;
			final b2 = capBaseBot + 1 + (i + 1) % segments;
			idx.push(capBaseBot); idx.push(b2); idx.push(a2);
		}

		// ── Tapa superior ─────────────────────────────────────────────────
		final capBaseTop = Std.int(v.length / 12);
		v.push(0); v.push(hy); v.push(0);
		v.push(0); v.push(1); v.push(0);
		v.push(0.5); v.push(0.5);
		v.push(r); v.push(g); v.push(b); v.push(a);

		for (i in 0...segments)
		{
			final theta = TAU * i / segments;
			final cx = Math.cos(theta);
			final cz = Math.sin(theta);
			v.push(cx*radius); v.push(hy); v.push(cz*radius);
			v.push(0); v.push(1); v.push(0);
			v.push(0.5 + 0.5*cx); v.push(0.5 + 0.5*cz);
			v.push(r); v.push(g); v.push(b); v.push(a);
		}

		for (i in 0...segments)
		{
			final a2 = capBaseTop + 1 + i;
			final b2 = capBaseTop + 1 + (i + 1) % segments;
			idx.push(capBaseTop); idx.push(a2); idx.push(b2);
		}

		final mesh = new Flx3DMesh();
		mesh.name  = 'cylinder';
		mesh.setGeometry(v, idx);
		return mesh;
	}
}
