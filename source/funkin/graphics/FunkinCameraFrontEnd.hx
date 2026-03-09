package funkin.graphics;

import flixel.FlxCamera;
import flixel.system.frontEnds.CameraFrontEnd;

/**
 * Override de CameraFrontEnd que usa FunkinCamera como cámara por defecto.
 * Esto permite que todos los sprites usen blend modes avanzados via shaders.
 *
 * Portado de v-slice (FunkinCrew/Funkin).
 */
@:nullSafety
class FunkinCameraFrontEnd extends CameraFrontEnd
{
	public override function reset(?newCamera:FlxCamera):Void
	{
		super.reset(newCamera ?? new FunkinCamera());
	}
}
