package funkin.graphics.shaders;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.graphics.frames.FlxFrame;
import funkin.graphics.shaders.FunkinRuntimeShader;
/**
 * Shader base para efectos de post-proceso.
 * Expone coordenadas de pantalla, cámara y frame como uniforms.
 *
 * Portado de v-slice (FunkinCrew/Funkin).
 */
class RuntimePostEffectShader extends FunkinRuntimeShader
{
	@:glVertexHeader('
		// Coordenada de pantalla normalizada
		//   (0,0) = esquina superior izquierda
		//   (1,1) = esquina inferior derecha
		varying vec2 screenCoord;
	', true)
	@:glVertexBody('
		screenCoord = vec2(
			openfl_TextureCoord.x > 0.0 ? 1.0 : 0.0,
			openfl_TextureCoord.y > 0.0 ? 1.0 : 0.0
		);
	')
	@:glFragmentHeader('
		varying vec2 screenCoord;

		// Resolución de pantalla (FlxG.width, FlxG.height)
		uniform vec2 uScreenResolution;

		// Límites de la cámara (left, top, right, bottom)
		uniform vec4 uCameraBounds;

		// Límites del frame (left, top, right, bottom)
		uniform vec4 uFrameBounds;

		// Convierte coord de pantalla a coord de mundo (px)
		vec2 screenToWorld(vec2 sc) {
			float left   = uCameraBounds.x;
			float top    = uCameraBounds.y;
			float right  = uCameraBounds.z;
			float bottom = uCameraBounds.w;
			vec2 scale   = vec2(right - left, bottom - top);
			vec2 offset  = vec2(left, top);
			return sc * scale + offset;
		}

		// Convierte coord de mundo a coord de pantalla normalizada
		vec2 worldToScreen(vec2 wc) {
			float left   = uCameraBounds.x;
			float top    = uCameraBounds.y;
			float right  = uCameraBounds.z;
			float bottom = uCameraBounds.w;
			vec2 scale   = vec2(right - left, bottom - top);
			vec2 offset  = vec2(left, top);
			return (wc - offset) / scale;
		}

		// Convierte coord de pantalla a coord de frame normalizada
		vec2 screenToFrame(vec2 sc) {
			float left   = uFrameBounds.x;
			float top    = uFrameBounds.y;
			float right  = uFrameBounds.z;
			float bottom = uFrameBounds.w;
			float w      = right - left;
			float h      = bottom - top;
			float cx     = clamp(sc.x, left, right);
			float cy     = clamp(sc.y, top, bottom);
			return vec2((cx - left) / w, (cy - top) / h);
		}

		vec2 bitmapCoordScale() {
			return openfl_TextureCoordv / screenCoord;
		}

		vec2 screenToBitmap(vec2 sc) {
			return sc * bitmapCoordScale();
		}

		vec4 sampleBitmapScreen(vec2 sc) {
			return texture2D(bitmap, screenToBitmap(sc));
		}

		vec4 sampleBitmapWorld(vec2 wc) {
			return sampleBitmapScreen(worldToScreen(wc));
		}
	', true)
	public function new(?fragmentSource:String, ?vertexSource:String)
	{
		// Pasa vertex shader opcional al FunkinRuntimeShader base
		super(fragmentSource, vertexSource);
		// Los uniforms pueden ser null si el contexto GL aún no está listo.
		try { uScreenResolution.value = [FlxG.width, FlxG.height]; } catch (_:Dynamic) {}
		try { uCameraBounds.value     = [0, 0, FlxG.width, FlxG.height]; } catch (_:Dynamic) {}
		try { uFrameBounds.value      = [0, 0, FlxG.width, FlxG.height]; } catch (_:Dynamic) {}
	}

	/**
	 * Actualiza los uniforms de resolución y límites de cámara.
	 * Llama esto cuando la cámara o el tamaño de pantalla cambia.
	 */
	public function updateViewInfo(screenWidth:Float, screenHeight:Float, camera:FlxCamera):Void
	{
		// Null-guard: los uniforms pueden ser null si el GL program no compiló correctamente
		if (uScreenResolution != null) uScreenResolution.value = [screenWidth, screenHeight];
		if (uCameraBounds != null && camera != null)
			uCameraBounds.value = [camera.viewLeft, camera.viewTop, camera.viewRight, camera.viewBottom];
	}

	/**
	 * Actualiza los uniforms de límites de frame.
	 */
	public function updateFrameInfo(frame:FlxFrame):Void
	{
		if (uFrameBounds != null && frame != null && frame.uv != null)
			uFrameBounds.value = [frame.uv.left, frame.uv.top, frame.uv.right, frame.uv.bottom];
	}

	// __createGLProgram ya está manejado en FunkinRuntimeShader con Log.warn()
}
