package funkin.graphics.scene3d;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

using StringTools;

/**
 * Model3DLoader — Carga modelos 3D en formato OBJ / MTL.
 *
 * Soporta:
 *  • Vértices (v), normales (vn), coordenadas de textura (vt)
 *  • Caras trianguladas y no trianguladas (fan-triangulation automática)
 *  • Materiales básicos desde .mtl (color diffuse → color de vértice)
 *  • Múltiples objetos en un solo archivo (o:, g:)
 *  • Archivos multi-material (usemtl)
 *
 * ─── Rutas de búsqueda ────────────────────────────────────────────────────────
 *
 *   Para personajes (renderType: "model3d"):
 *     mods/{mod}/characters/models/{name}.obj
 *     assets/characters/models/{name}.obj
 *
 *   Para stages (type: "model3d"):
 *     mods/{mod}/stages/{stage}/models/{name}.obj
 *     mods/{mod}/stages/models/{name}.obj
 *     assets/stages/{stage}/models/{name}.obj
 *     assets/stages/models/{name}.obj
 *
 *   También acepta paths absolutos o relativos completos.
 *
 * ─── Uso desde JSON de stage ─────────────────────────────────────────────────
 *
 *   {
 *     "type": "model3d",
 *     "name": "spinning_cube",
 *     "asset": "cube",
 *     "position": [640, 360, 0],
 *     "modelScale": 100,
 *     "modelRotX": 0,
 *     "modelRotY": 0,
 *     "modelRotZ": 0
 *   }
 *
 * ─── Uso desde JSON de personaje ─────────────────────────────────────────────
 *
 *   {
 *     "path": "bf",
 *     "renderType": "model3d",
 *     "modelFile": "bf_low_poly",
 *     "modelScale": 1.0,
 *     "animations": [ ... ]
 *   }
 *
 * ─── Uso desde HScript ────────────────────────────────────────────────────────
 *
 *   var mesh = Model3DLoader.load("path/to/model.obj");
 *   if (mesh != null) {
 *     var obj3d = new Flx3DObject();
 *     obj3d.mesh = mesh;
 *     myScene.add(obj3d);
 *   }
 *
 *   // Cargar para un personaje (busca en characters/models/)
 *   var mesh = Model3DLoader.loadForCharacter("bf_low_poly");
 *
 *   // Cargar para un stage (busca en stages/{stage}/models/)
 *   var mesh = Model3DLoader.loadForStage("rock_formation", "week5");
 */
class Model3DLoader
{
	// ── API pública ───────────────────────────────────────────────────────────

	/**
	 * Carga un archivo OBJ desde cualquier ruta del sistema de archivos.
	 * Si la ruta no es absoluta se busca en los paths estándar.
	 *
	 * @param path   Ruta al .obj (absoluta o relativa a la raíz del proyecto).
	 * @return       Flx3DMesh listo para usar, o null si no se puede cargar.
	 */
	public static function load(path:String):Null<Flx3DMesh>
	{
		#if sys
		// Resolver path si es relativo
		final resolved = _resolve(path, null, null) ?? path;
		if (!FileSystem.exists(resolved))
		{
			trace('[Model3DLoader] Archivo no encontrado: "$resolved"');
			return null;
		}
		return _parseOBJ(File.getContent(resolved), resolved);
		#else
		// En targets web, intentar con Assets.getText
		try
		{
			final txt = lime.utils.Assets.getText(path);
			if (txt != null) return _parseOBJ(txt, path);
		}
		catch (_) {}
		return null;
		#end
	}

	/**
	 * Carga un modelo para un personaje.
	 * Busca en:
	 *   mods/{mod}/characters/models/{name}.obj
	 *   assets/characters/models/{name}.obj
	 */
	public static function loadForCharacter(name:String):Null<Flx3DMesh>
	{
		final path = _resolve(name, 'character', null);
		if (path == null)
		{
			trace('[Model3DLoader] Modelo de personaje no encontrado: "$name"');
			return null;
		}
		#if sys
		return _parseOBJ(File.getContent(path), path);
		#else
		return null;
		#end
	}

	/**
	 * Carga un modelo para un stage.
	 * Busca en:
	 *   mods/{mod}/stages/{stageName}/models/{name}.obj
	 *   assets/stages/{stageName}/models/{name}.obj
	 */
	public static function loadForStage(name:String, ?stageName:String):Null<Flx3DMesh>
	{
		final path = _resolve(name, 'stage', stageName);
		if (path == null)
		{
			trace('[Model3DLoader] Modelo de stage no encontrado: "$name"');
			return null;
		}
		#if sys
		return _parseOBJ(File.getContent(path), path);
		#else
		return null;
		#end
	}

	/**
	 * Devuelve la ruta resuelta a un modelo sin cargarlo.
	 * Útil para precachear o verificar existencia.
	 */
	public static function resolve(name:String, ?context:String, ?stageName:String):Null<String>
		return _resolve(name, context, stageName);

	// ── Resolución de rutas ───────────────────────────────────────────────────

	static function _resolve(name:String, ?context:String, ?stageName:String):Null<String>
	{
		#if sys
		// Si es un path ya existente devolver directo
		if (FileSystem.exists(name)) return name;
		// Añadir extensión si no la tiene
		final withExt = name.endsWith('.obj') ? name : '$name.obj';
		if (FileSystem.exists(withExt)) return withExt;

		final candidates:Array<String> = [];
		final modRoot = mods.ModManager.modRoot();

		if (context == 'character')
		{
			if (modRoot != null)
			{
				candidates.push('$modRoot/characters/models/$withExt');
				candidates.push('$modRoot/assets/characters/models/$withExt');
			}
			candidates.push('assets/characters/models/$withExt');
		}
		else if (context == 'stage')
		{
			final sn = stageName ?? Paths.currentStage ?? '';
			if (modRoot != null)
			{
				if (sn != '') candidates.push('$modRoot/stages/$sn/models/$withExt');
				candidates.push('$modRoot/stages/models/$withExt');
				candidates.push('$modRoot/assets/stages/models/$withExt');
			}
			if (sn != '') candidates.push('assets/stages/$sn/models/$withExt');
			candidates.push('assets/stages/models/$withExt');
		}
		else
		{
			// Búsqueda genérica
			if (modRoot != null) candidates.push('$modRoot/models/$withExt');
			candidates.push('assets/models/$withExt');
			candidates.push('assets/data/models/$withExt');
		}

		for (p in candidates)
			if (FileSystem.exists(p)) return p;
		#end
		return null;
	}

	// ── Parser OBJ ────────────────────────────────────────────────────────────

	static function _parseOBJ(content:String, sourcePath:String):Null<Flx3DMesh>
	{
		if (content == null || content.length == 0) return null;

		// Datos intermedios
		final posArr:Array<Float>   = [];   // [x,y,z, ...]
		final normArr:Array<Float>  = [];   // [nx,ny,nz, ...]
		final uvArr:Array<Float>    = [];   // [u,v, ...]

		// Material actual
		var matR:Float = 1.0; var matG:Float = 1.0;
		var matB:Float = 1.0; var matA:Float = 1.0;
		final matColors:Map<String, Array<Float>> = new Map();

		// Resultado: vértices expandidos (sin índices compartidos, para normales per-face correctas)
		final outVerts:Array<Float>  = [];  // stride 12: x,y,z, nx,ny,nz, u,v, r,g,b,a
		final outIdx:Array<Int>      = [];

		var vertCounter = 0;

		// Cargar .mtl si existe
		final mtlPath = _resolveMtl(sourcePath);
		if (mtlPath != null) _parseMTL(File.getContent(mtlPath), matColors);

		for (rawLine in content.split('\n'))
		{
			final line = rawLine.trim();
			if (line.length == 0 || line.startsWith('#')) continue;

			final tok = line.split(' ');
			if (tok.length == 0) continue;

			switch (tok[0])
			{
				case 'v':   // posición
					if (tok.length >= 4)
					{
						posArr.push(_pf(tok[1])); posArr.push(_pf(tok[2])); posArr.push(_pf(tok[3]));
					}

				case 'vn':  // normal
					if (tok.length >= 4)
					{
						normArr.push(_pf(tok[1])); normArr.push(_pf(tok[2])); normArr.push(_pf(tok[3]));
					}

				case 'vt':  // textura
					if (tok.length >= 3)
					{
						uvArr.push(_pf(tok[1])); uvArr.push(1.0 - _pf(tok[2])); // OBJ UV es Y-up
					}

				case 'usemtl': // cambio de material
					final mtlName = tok.length > 1 ? tok[1] : '';
					if (matColors.exists(mtlName))
					{
						final c = matColors.get(mtlName);
						matR = c[0]; matG = c[1]; matB = c[2]; matA = c.length > 3 ? c[3] : 1.0;
					}

				case 'f':   // cara (3+ vértices)
					// Triangular en fan: v0, v1, v2 / v0, v2, v3 / ...
					final faceVerts:Array<Array<Int>> = [];
					for (i in 1...tok.length)
					{
						if (tok[i].trim() == '') continue;
						faceVerts.push(_parseFaceVertex(tok[i]));
					}
					if (faceVerts.length < 3) continue;

					// Fan triangulation
					for (i in 1...(faceVerts.length - 1))
					{
						for (fi in [0, i, i + 1])
						{
							final fv    = faceVerts[fi];
							final pi    = (fv[0] - 1) * 3;  // 1-indexed → 0-indexed
							final ti    = fv.length > 1 && fv[1] > 0 ? (fv[1] - 1) * 2 : -1;
							final ni    = fv.length > 2 && fv[2] > 0 ? (fv[2] - 1) * 3 : -1;

							// Position
							outVerts.push(pi >= 0 && pi + 2 < posArr.length  ? posArr[pi]     : 0);
							outVerts.push(pi >= 0 && pi + 2 < posArr.length  ? posArr[pi + 1] : 0);
							outVerts.push(pi >= 0 && pi + 2 < posArr.length  ? posArr[pi + 2] : 0);
							// Normal
							outVerts.push(ni >= 0 && ni + 2 < normArr.length ? normArr[ni]     : 0);
							outVerts.push(ni >= 0 && ni + 2 < normArr.length ? normArr[ni + 1] : 1);
							outVerts.push(ni >= 0 && ni + 2 < normArr.length ? normArr[ni + 2] : 0);
							// UV
							outVerts.push(ti >= 0 && ti + 1 < uvArr.length   ? uvArr[ti]       : 0);
							outVerts.push(ti >= 0 && ti + 1 < uvArr.length   ? uvArr[ti + 1]   : 0);
							// Color (material)
							outVerts.push(matR); outVerts.push(matG); outVerts.push(matB); outVerts.push(matA);

							outIdx.push(vertCounter++);
						}
					}
			}
		}

		if (outIdx.length == 0)
		{
			trace('[Model3DLoader] No se encontraron caras en el OBJ "$sourcePath"');
			return null;
		}

		final mesh = new Flx3DMesh();
		mesh.name  = _baseName(sourcePath);
		mesh.setGeometry(outVerts, outIdx);

		trace('[Model3DLoader] Cargado "$sourcePath": ${Std.int(outIdx.length / 3)} triángulos, $vertCounter vértices.');
		return mesh;
	}

	/** Parsea "v/vt/vn" → [v, vt, vn] (0 si falta). */
	static function _parseFaceVertex(token:String):Array<Int>
	{
		final parts = token.split('/');
		final v  = parts.length > 0 && parts[0] != '' ? Std.parseInt(parts[0]) ?? 0 : 0;
		final vt = parts.length > 1 && parts[1] != '' ? Std.parseInt(parts[1]) ?? 0 : 0;
		final vn = parts.length > 2 && parts[2] != '' ? Std.parseInt(parts[2]) ?? 0 : 0;
		return [v, vt, vn];
	}

	// ── Parser MTL ────────────────────────────────────────────────────────────

	static function _parseMTL(content:String, out:Map<String, Array<Float>>):Void
	{
		var currentMat = 'default';
		out.set(currentMat, [1, 1, 1, 1]);

		for (rawLine in content.split('\n'))
		{
			final line = rawLine.trim();
			if (line.startsWith('#') || line == '') continue;
			final tok = line.split(' ');
			switch (tok[0])
			{
				case 'newmtl':
					currentMat = tok.length > 1 ? tok[1] : 'default';
					if (!out.exists(currentMat)) out.set(currentMat, [1, 1, 1, 1]);
				case 'Kd':  // diffuse color
					if (tok.length >= 4)
					{
						final c = out.get(currentMat) ?? [1, 1, 1, 1];
						c[0] = _pf(tok[1]); c[1] = _pf(tok[2]); c[2] = _pf(tok[3]);
						out.set(currentMat, c);
					}
				case 'd', 'Tr':  // alpha / transparency
					if (tok.length >= 2)
					{
						final c = out.get(currentMat) ?? [1, 1, 1, 1];
						c[3] = tok[0] == 'Tr' ? 1.0 - _pf(tok[1]) : _pf(tok[1]);
						out.set(currentMat, c);
					}
			}
		}
	}

	/** Busca el .mtl referenciado desde el mismo directorio que el .obj. */
	static function _resolveMtl(objPath:String):Null<String>
	{
		#if sys
		final dir   = objPath.substring(0, Std.int(Math.max(objPath.lastIndexOf('/'), objPath.lastIndexOf('\\'))));
		final base  = _baseName(objPath);
		final mtl   = '$dir/$base.mtl';
		return FileSystem.exists(mtl) ? mtl : null;
		#else
		return null;
		#end
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	static inline function _pf(s:String):Float
	{
		final f = Std.parseFloat(s.trim());
		return Math.isNaN(f) ? 0.0 : f;
	}

	static function _baseName(path:String):String
	{
		var s = path;
		final sl = Std.int(Math.max(s.lastIndexOf('/'), s.lastIndexOf('\\')));
		if (sl >= 0) s = s.substr(sl + 1);
		final dot = s.lastIndexOf('.');
		return dot >= 0 ? s.substr(0, dot) : s;
	}
}
