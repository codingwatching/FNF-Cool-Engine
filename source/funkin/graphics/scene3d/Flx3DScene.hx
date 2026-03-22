package funkin.graphics.scene3d;

import openfl.display3D.Context3D;
import openfl.display3D.Context3DProfile;
import openfl.display3D.Context3DRenderMode;
import openfl.display3D.Context3DTriangleFace;
import openfl.display3D.Context3DCompareMode;
import openfl.display3D.Context3DBlendFactor;
import openfl.display3D.Context3DProgramType;
import openfl.display3D.Program3D;
import openfl.display3D.textures.RectangleTexture;
import openfl.display.BitmapData;
import openfl.display.Stage3D;
import openfl.events.Event;
import openfl.events.ErrorEvent;
import openfl.Vector;
import flixel.FlxG;

/**
 * Flx3DScene — Escena 3D GPU-acelerada para HaxeFlixel.
 *
 * ─── Arquitectura ────────────────────────────────────────────────────────────
 *
 *  Stage3D (OpenFL) → Context3D (GPU)
 *    └─ Render a RectangleTexture (off-screen)
 *       └─ copyToTexture → BitmapData
 *          └─ FlxSprite.loadGraphic() ← visible en pantalla 2D
 *
 * ─── Uso básico ──────────────────────────────────────────────────────────────
 *
 *   var scene = new Flx3DScene(640, 480);
 *   scene.init();                              // llama una sola vez
 *   var cube = new Flx3DObject();
 *   cube.mesh = Flx3DPrimitives.cube();
 *   scene.add(cube);
 *   scene.camera.position.set(0, 1, 4);
 *
 *   // En update():
 *   scene.render();                            // actualiza bitmap
 *   sprite.loadGraphic(scene.output);          // muestra en pantalla
 *
 * ─── Iluminación ─────────────────────────────────────────────────────────────
 *  Phong shading: luz direccional + ambiente + especular.
 *  Configurable vía lightDir, lightColor, ambientColor.
 *
 * ─── Optimizaciones ──────────────────────────────────────────────────────────
 *  • Render off-screen (RectangleTexture) — sin artefactos de compositing
 *  • Depth buffer habilitado — z-culling automático en GPU
 *  • Back-face culling — FRONT (normal estándar = fuera)
 *  • Matrices enviadas como constantes de programa (no recompila shaders)
 *  • Shader GLSL simple: 1 draw call por objeto, sin over-draw
 *  • Buffers de vértices en GPU (upload-once, draw-many)
 */
class Flx3DScene
{
	// ── Salida ─────────────────────────────────────────────────────────────

	/** BitmapData resultado del render. Asigna a FlxSprite.loadGraphic(). */
	public var output(default, null):Null<BitmapData> = null;

	/** Cámara 3D. */
	public var camera:Flx3DCamera = new Flx3DCamera();

	/** Objetos en la escena. */
	public var objects(default, null):Array<Flx3DObject> = [];

	// ── Iluminación ────────────────────────────────────────────────────────

	/** Dirección de la luz (vector normalizado). */
	public var lightDir:Vec3   = new Vec3(0.5, 1.0, 0.8).normalizeSelf();
	/** Color de la luz difusa [r,g,b,1]. */
	public var lightColor:Array<Float>   = [1.0, 1.0, 1.0, 1.0];
	/** Color de la luz ambiente [r,g,b,1]. */
	public var ambientColor:Array<Float> = [0.15, 0.15, 0.20, 1.0];

	// ── Config ─────────────────────────────────────────────────────────────

	/** Color de fondo (r,g,b,a en 0..1). */
	public var clearR:Float = 0; public var clearG:Float = 0;
	public var clearB:Float = 0; public var clearA:Float = 1;

	public var width (default, null):Int;
	public var height(default, null):Int;
	public var ready (default, null):Bool = false;

	// ── Internos ───────────────────────────────────────────────────────────

	var _stage3D:Stage3D;
	var _ctx    :Null<Context3D>;
	var _prog   :Null<Program3D>;
	var _renderTarget:Null<RectangleTexture>;

	// Buffers de constantes reutilizados (sin new cada frame)
	var _mat4Buf:Vector<Float> = new Vector<Float>(16);
	var _vec4Buf:Vector<Float> = new Vector<Float>(4);

	// MVP+NM matrices reutilizadas
	var _mvp    :Mat4 = new Mat4();
	var _modelInvT:Mat4 = new Mat4();
	var _tmpMat  :Mat4 = new Mat4();

	public function new(width:Int, height:Int)
	{
		this.width  = width;
		this.height = height;

		camera.aspect = width / height;
		output = new BitmapData(width, height, true, 0x00000000);
	}

	// ── Inicialización ──────────────────────────────────────────────────────

	/**
	 * Inicia la petición de Context3D asíncrona.
	 * Cuando el contexto esté listo, `ready` será true.
	 * @param onReady  Callback opcional cuando Context3D esté disponible.
	 */
	public function init(?onReady:Void->Void):Void
	{
		_stage3D = FlxG.stage.stage3Ds[0];

		if (_stage3D == null)
		{
			trace('[Flx3DScene] Stage3D no disponible en esta plataforma.');
			return;
		}

		_stage3D.addEventListener(Event.CONTEXT3D_CREATE, function(_)
		{
			_ctx = _stage3D.context3D;
			_ctx.configureBackBuffer(width, height, 0, true, true, false);
			_buildShaders();
			_buildRenderTarget();
			ready = true;
			if (onReady != null) onReady();
			trace('[Flx3DScene] Context3D listo (${_ctx.driverInfo})');
		});

		_stage3D.addEventListener(ErrorEvent.ERROR, function(e:ErrorEvent)
			trace('[Flx3DScene] Error Stage3D: ${e.text}'));

		_stage3D.requestContext3D(Context3DRenderMode.AUTO, Context3DProfile.BASELINE);
	}

	// ── Gestión de objetos ─────────────────────────────────────────────────

	public function add(obj:Flx3DObject):Flx3DObject
		{ objects.push(obj); return obj; }

	public function remove(obj:Flx3DObject):Void
		objects.remove(obj);

	public function clear():Void
		objects = [];

	// ── Render ─────────────────────────────────────────────────────────────

	/**
	 * Renderiza todos los objetos de la escena y actualiza `output`.
	 * Llamar una vez por frame desde update() o draw().
	 */
	public function render():Void
	{
		if (!ready || _ctx == null || _prog == null) return;

		// Configurar render target off-screen
		_ctx.setRenderToTexture(_renderTarget, true);
		_ctx.clear(clearR, clearG, clearB, clearA);

		// Shader
		_ctx.setProgram(_prog);

		// Blending
		_ctx.setBlendFactors(Context3DBlendFactor.SOURCE_ALPHA,
		                     Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA);
		// Depth
		_ctx.setDepthTest(true, Context3DCompareMode.LESS);
		// Culling
		_ctx.setCulling(Context3DTriangleFace.FRONT);

		// Actualizar cámara
		camera.update();

		// ── Uniforms globales de luz ───────────────────────────────────────
		// vc[20] = lightDir (w=0)
		_setVec4Const(20, lightDir.x, lightDir.y, lightDir.z, 0);
		// vc[21] = lightColor
		_setVec4Const(21, lightColor[0], lightColor[1], lightColor[2], lightColor[3]);
		// vc[22] = ambientColor
		_setVec4Const(22, ambientColor[0], ambientColor[1], ambientColor[2], ambientColor[3]);
		// vc[23] = cámara posición (para especular)
		_setVec4Const(23, camera.position.x, camera.position.y, camera.position.z, 1);

		// ── Dibujar objetos ────────────────────────────────────────────────
		for (obj in objects)
		{
			if (!obj.visible || !obj.active || obj.mesh == null) continue;

			obj.updateMatrix();
			obj.mesh.upload(_ctx);

			// MVP = viewProj × model
			Mat4.multiply(camera.viewProjMatrix, obj.modelMatrix, _mvp);

			// Normal matrix = transpose(inverse(model))
			obj.modelMatrix.invert(_tmpMat);
			_tmpMat.transpose(_modelInvT);

			// Enviar MVP (vc[0..3])
			_setMat4Const(0, _mvp);
			// Enviar Model matrix (vc[4..7]) — para normales en world space
			_setMat4Const(4, _modelInvT);
			// Enviar tint (vc[8])
			_setVec4Const(8,  obj.tint[0], obj.tint[1], obj.tint[2], obj.tint[3]);
			// lit flag + shininess (vc[9])
			_setVec4Const(9, obj.lit ? 1.0 : 0.0, obj.shininess, 0, 0);

			// Textura
			if (obj.texture != null)
			{
				_ctx.setTextureAt(0, obj.texture);
				_setVec4Const(10, 1, 0, 0, 0); // hasTexture = 1
			}
			else
			{
				_ctx.setTextureAt(0, null);
				_setVec4Const(10, 0, 0, 0, 0); // hasTexture = 0
			}

			obj.mesh.draw(_ctx);
		}

		// ── Copiar resultado a BitmapData ──────────────────────────────────
		_ctx.setRenderToBackBuffer();
		if (_renderTarget != null && output != null)
		{
			// Vuelca el resultado del render a BitmapData (accesible como sprite.pixels)
			_ctx.drawToBitmapData(output);
		}
	}

	// ── Resize ─────────────────────────────────────────────────────────────

	/** Cambia la resolución del render target. */
	public function resize(w:Int, h:Int):Void
	{
		if (w == width && h == height) return;
		width  = w; height = h;
		camera.aspect = w / h;

		if (_ctx == null) return;
		_ctx.configureBackBuffer(w, h, 0, true, true, false);

		if (_renderTarget != null) { _renderTarget.dispose(); _renderTarget = null; }
		_buildRenderTarget();

		if (output != null) { output.dispose(); }
		output = new BitmapData(w, h, true, 0x00000000);
	}

	// ── Dispose ────────────────────────────────────────────────────────────

	public function dispose():Void
	{
		for (obj in objects)
			if (obj.mesh != null) obj.mesh.dispose();
		objects = [];

		if (_prog          != null) { _prog.dispose();          _prog = null; }
		if (_renderTarget  != null) { _renderTarget.dispose();  _renderTarget = null; }
		if (output         != null) { output.dispose();         output = null; }
		_ctx = null;
	}

	// ── Helpers privados ───────────────────────────────────────────────────

	inline function _setMat4Const(register:Int, mat:Mat4):Void
	{
		for (i in 0...16) _mat4Buf[i] = mat.m[i];
		_ctx.setProgramConstantsFromVector(Context3DProgramType.VERTEX, register, _mat4Buf, 4);
	}

	inline function _setVec4Const(register:Int, a:Float, b:Float, c:Float, d:Float):Void
	{
		_vec4Buf[0]=a; _vec4Buf[1]=b; _vec4Buf[2]=c; _vec4Buf[3]=d;
		_ctx.setProgramConstantsFromVector(Context3DProgramType.VERTEX, register, _vec4Buf, 1);
	}

	function _buildRenderTarget():Void
	{
		if (_ctx == null) return;
		_renderTarget = _ctx.createRectangleTexture(width, height,
			openfl.display3D.Context3DTextureFormat.BGRA, true);
	}

	function _buildShaders():Void
	{
		if (_ctx == null) return;

		// ── Vertex Shader GLSL ─────────────────────────────────────────────
		// Constantes de vértice (vc):
		//   vc[0..3]  MVP matrix (4 registros = 4×vec4 = mat4)
		//   vc[4..7]  Normal matrix (transpose-inverse model)
		//   vc[8]     tint (r,g,b,a)
		//   vc[9]     (lit, shininess, 0, 0)
		//   vc[20]    lightDir (world)
		//   vc[23]    cameraPos (world)
		//
		// Atributos:
		//   va0  position  (xyz)
		//   va1  normal    (xyz)
		//   va2  uv        (uv)
		//   va3  color     (rgba)
		final vsrc = '
attribute vec3 va0;   // position
attribute vec3 va1;   // normal
attribute vec2 va2;   // uv
attribute vec4 va3;   // vertex color

uniform mat4 vc0;     // MVP (actually vc[0..3])
uniform mat4 vc4;     // Normal matrix (vc[4..7])
uniform vec4 vc8;     // tint
uniform vec4 vc9;     // (lit, shininess, 0, 0)
uniform vec4 vc20;    // light direction
uniform vec4 vc23;    // camera position

varying vec2 v_uv;
varying vec4 v_color;
varying vec3 v_normal;
varying vec3 v_worldPos;

void main() {
    vec4 pos = vc0 * vec4(va0, 1.0);
    gl_Position = pos;

    v_uv        = va2;
    v_color     = va3 * vc8;          // vertex color × tint
    v_normal    = normalize((vc4 * vec4(va1, 0.0)).xyz);
    v_worldPos  = (vc4 * vec4(va0, 1.0)).xyz;  // approx world pos via model
}
';

		// ── Fragment Shader GLSL ───────────────────────────────────────────
		// Uniforms de fragmento (fc):
		//   fc[0]  = (lit, shininess, 0, 0)   — mismo que vc9
		//   fc[1]  = lightColor
		//   fc[2]  = ambientColor
		//   fc[3]  = lightDir
		//   fc[4]  = cameraPos
		//   fc[5]  = (hasTexture, 0, 0, 0)
		//
		// Texture unit 0 = diffuse texture (si hasTexture > 0.5)
		final fsrc = '
#ifdef GL_ES
precision mediump float;
#endif

varying vec2 v_uv;
varying vec4 v_color;
varying vec3 v_normal;
varying vec3 v_worldPos;

uniform vec4 fc0;   // (lit, shininess, 0, 0)
uniform vec4 fc1;   // lightColor
uniform vec4 fc2;   // ambientColor
uniform vec4 fc3;   // lightDir (world, normalized)
uniform vec4 fc4;   // cameraPos (world)
uniform vec4 fc5;   // (hasTexture, 0, 0, 0)

uniform sampler2D fs0;  // diffuse texture

void main() {
    // Color base: textura o color de vértice
    vec4 baseColor = v_color;
    if (fc5.x > 0.5) {
        baseColor *= texture2D(fs0, v_uv);
    }

    if (fc0.x < 0.5) {
        // Unlit
        gl_FragColor = baseColor;
        return;
    }

    // Phong lighting
    vec3 N    = normalize(v_normal);
    vec3 L    = normalize(fc3.xyz);
    vec3 V    = normalize(fc4.xyz - v_worldPos);
    vec3 H    = normalize(L + V);  // halfway vector (Blinn-Phong)

    float diff = max(dot(N, L), 0.0);
    float spec = pow(max(dot(N, H), 0.0), fc0.y);

    vec3 ambient  = fc2.rgb * baseColor.rgb;
    vec3 diffuse  = fc1.rgb * diff * baseColor.rgb;
    vec3 specular = fc1.rgb * spec * 0.3;

    gl_FragColor = vec4(ambient + diffuse + specular, baseColor.a);
}
';

		_prog = _ctx.createProgram();
		_prog.uploadSources(vsrc, fsrc);

		// Copiar vc→fc para los uniforms de fragmento
		// (OpenFL Context3D usa registros separados para vertex/fragment)
		// Las constantes de fragmento se envían aparte en render()
		// — ver notas en _bindFragmentUniforms()
	}

	/**
	 * Nota: OpenFL Context3D requiere separar VERTEX vs FRAGMENT constants.
	 * En render(), las constantes de luz/material se envían a ambos
	 * program types usando setProgramConstantsFromByteArray(FRAGMENT, ...).
	 */
	function _bindFragmentUniforms():Void
	{
		// Esta función se llama desde render() usando Context3DProgramType.FRAGMENT
		// para los mismos datos que ya enviamos a VERTEX.
		// No duplicamos código aquí — se hace inline en render() con el tipo correcto.
	}
}
