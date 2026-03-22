package funkin.system;

#if sys
import sys.io.Process;
#end
#if windows
import extensions.InitAPI;
#end
import flixel.FlxG;
import openfl.system.Capabilities;

using StringTools;

/**
 * SystemInfo — detection cross-platform of información of hardware.
 *
 * ─── What it detects ─────────────────────────────────────────────────────────────
 *   • System operativo (nombre + version)
 *   • CPU (nombre, arquitectura, 32/64-bit)
 *   • GPU (nombre OpenGL, size maximum of texture)
 *   • VRAM (when the driver it expone via GL_GPU_MEM_INFO)
 *   • RAM total of the system (only in targets nativos)
 *
 * ─── Inspiration ─────────────────────────────────────────────────────────────
 * Codename Engine SystemInfo, adaptado to the system of modules of Cool Engine.
 * No hereda of FramerateCategory — is a module puro of datos.
 *
 * ─── Uso ─────────────────────────────────────────────────────────────────────
 *   SystemInfo.init();          // una sola vez al arrancar
 *   trace(SystemInfo.summary);  // string legible para debug overlay
 *
 * @author  Cool Engine Team
 * @since   0.5.1
 */
class SystemInfo
{
	// ── Datos public (read-only tras init()) ─────────────────────────────────

	public static var osName(default, null):String   = "Unknown";
	public static var cpuName(default, null):String  = "Unknown";
	public static var gpuName(default, null):String  = "Unknown";
	public static var vRAM(default, null):String     = "Unknown";
	public static var gpuMaxTextureSize(default, null):String = "Unknown";
	public static var totalRAM(default, null):String = "Unknown";
	public static var ramType(default, null):String  = "";

	/** true after of callr init(). */
	public static var initialized(default, null):Bool = false;

	// ── Resumen compacto para debug overlay ──────────────────────────────────

	public static var summary(get, never):String;
	static function get_summary():String return _summary;
	static var _summary:String = "";

	// ── Init ─────────────────────────────────────────────────────────────────

	/**
	 * Recopila the información of hardware.
	 * Callr a VEZ after of that FlxGame is in escena (necesita context3D).
	 */
	public static function init():Void
	{
		if (initialized) return;

		_detectOS();
		_detectCPU();
		_detectGPU();
		_detectRAM();
		_buildSummary();

		initialized = true;
		trace('[SystemInfo] ' + _summary.split('\n').join(' | '));
	}

	/**
	 * Version segura for mobile: omite _detectGPU() that requiere GL calls.
	 * ctx.gl.getParameter() desde el event thread de Lime crashea en Android
	 * porque the render ocurre in a thread native separated (violación of context).
	 */
	public static function initSafe():Void
	{
		if (initialized) return;

		_detectOS();
		_detectCPU();
		_detectRAM();
		// GPU omitida intencionalmente en mobile — sin GL calls
		_buildSummary();

		initialized = true;
		trace('[SystemInfo] (safe/mobile) ' + _summary.split('\n').join(' | '));
	}

	// ── Detection ─────────────────────────────────────────────────────────────

	static function _detectOS():Void
	{
		try
		{
			#if windows
			// Leer la build del registro para distinguir Win10 vs Win11
			var build:Int = _readRegistry(
				"HKEY_LOCAL_MACHINE",
				"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
				"CurrentBuildNumber"
			);
			var edition:String = _readRegistry(
				"HKEY_LOCAL_MACHINE",
				"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
				"ProductName"
			);
			if (build >= 22000)
				edition = edition.replace("Windows 10", "Windows 11");
			var lcu:String = _readRegistry(
				"HKEY_LOCAL_MACHINE",
				"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
				build >= 22000 ? "LCUVer" : "WinREVersion"
			);
			osName = edition + (lcu.length > 0 ? ' $lcu' : '');

			#elseif linux
			// Leer /etc/os-release buscando PRETTY_NAME
			var content:String = sys.io.File.getContent("/etc/os-release");
			for (line in content.split("\n"))
			{
				if (line.startsWith("PRETTY_NAME="))
				{
					osName = line.substring(line.indexOf("=") + 1).trim();
					// Quitar comillas si las hay
					if (osName.charAt(0) == '"')
						osName = osName.substring(1, osName.length - 1);
					break;
				}
			}

			#elseif mac
			var p = new Process("sw_vers", ["-productVersion"]);
			if (p.exitCode() == 0)
				osName = "macOS " + p.stdout.readAll().toString().trim();

			#else
			// Fallback generic via lime
			if (lime.system.System.platformLabel != null)
				osName = lime.system.System.platformLabel;
			#end
		}
		catch (e:Dynamic)
		{
			trace('[SystemInfo] OS detection failed: $e');
		}
	}

	static function _detectCPU():Void
	{
		try
		{
			#if windows
			cpuName = _readRegistry(
				"HKEY_LOCAL_MACHINE",
				"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
				"ProcessorNameString"
			).trim();

			#elseif mac
			var p = new Process("sysctl", ["-n", "machdep.cpu.brand_string"]);
			if (p.exitCode() == 0)
				cpuName = p.stdout.readAll().toString().trim();

			#elseif linux
			var content:String = sys.io.File.getContent("/proc/cpuinfo");
			for (line in content.split("\n"))
			{
				if (line.startsWith("model name"))
				{
					cpuName = line.substring(line.indexOf(":") + 2).trim();
					break;
				}
			}
			#end
		}
		catch (e:Dynamic)
		{
			trace('[SystemInfo] CPU detection failed: $e');
		}

		// Add arquitectura/bits
		final arch  = Capabilities.cpuArchitecture;
		final bits  = Capabilities.supports64BitProcesses ? "64-bit" : "32-bit";
		if (cpuName != "Unknown" && cpuName.length > 0)
			cpuName = '$cpuName ($arch $bits)';
	}

	static function _detectGPU():Void
	{
		try
		{
			@:privateAccess
			if (FlxG.renderTile)
			{
				var ctx = flixel.FlxG.stage.context3D;
				if (ctx != null && ctx.gl != null)
				{
					// Renderer name (we remove the driver suffix after /)
					gpuName = Std.string(ctx.gl.getParameter(ctx.gl.RENDERER))
						.split("/")[0].trim();

					// Maximum texture size
					#if !flash
					var maxTex:Int = FlxG.bitmap.maxTextureSize;
					gpuMaxTextureSize = '${maxTex}×${maxTex}';
					#end

					// VRAM via NV extension (GL_GPU_MEM_INFO_TOTAL_AVAILABLE_MEM_NVX)
					// The value is in KB when available.
					@:privateAccess
					if (openfl.display3D.Context3D.__glMemoryTotalAvailable != -1)
					{
						var kb:Int = cast ctx.gl.getParameter(
							openfl.display3D.Context3D.__glMemoryTotalAvailable
						);
						// Some drivers report 1 or invalid values on APUs
						if (kb > 16)
							vRAM = MemoryUtil.formatBytes(kb * 1024.0);
					}
				}
			}
		}
		catch (e:Dynamic)
		{
			trace('[SystemInfo] GPU detection failed: $e');
		}
	}

	static function _detectRAM():Void
	{
		try
		{
			#if windows
			// GlobalMemoryStatusEx to través of the log no applies;
			// usamos the API of Lime / openfl if is available.
			// Si el proyecto tiene lime-native-dll lo expone en System.totalMemory,
			// pero eso es la RAM usada, no la total. Usamos wmic como fallback.
			var p = new Process("wmic", ["memorychip", "get", "capacity"]);
			if (p.exitCode() == 0)
			{
				var lines = p.stdout.readAll().toString().split("\n");
				var totalBytes:Float = 0;
				for (line in lines)
				{
					var n = Std.parseFloat(line.trim());
					if (!Math.isNaN(n) && n > 0) totalBytes += n;
				}
				if (totalBytes > 0)
					totalRAM = MemoryUtil.formatBytes(totalBytes);
			}

			#elseif linux
			var content:String = sys.io.File.getContent("/proc/meminfo");
			for (line in content.split("\n"))
			{
				if (line.startsWith("MemTotal:"))
				{
					// Formato: "MemTotal:       16328904 kB"
					var parts = line.split(":")[1].trim().split(" ");
					var kb:Float = Std.parseFloat(parts[0]);
					if (!Math.isNaN(kb)) totalRAM = MemoryUtil.formatBytes(kb * 1024);
					break;
				}
			}

			#elseif mac
			var p = new Process("sysctl", ["-n", "hw.memsize"]);
			if (p.exitCode() == 0)
			{
				var bytes:Float = Std.parseFloat(p.stdout.readAll().toString().trim());
				if (!Math.isNaN(bytes) && bytes > 0)
					totalRAM = MemoryUtil.formatBytes(bytes);
			}
			#end
		}
		catch (e:Dynamic)
		{
			trace('[SystemInfo] RAM detection failed: $e');
		}
	}

	static function _buildSummary():Void
	{
		var parts:Array<String> = [];
		if (osName  != "Unknown" && osName.length  > 0) parts.push('OS: $osName');
		if (cpuName != "Unknown" && cpuName.length > 0) parts.push('CPU: $cpuName');
		if (gpuName != "Unknown" && gpuName.length > 0)
		{
			var gpuStr = 'GPU: $gpuName';
			if (vRAM != "Unknown") gpuStr += ' ($vRAM VRAM)';
			if (gpuMaxTextureSize != "Unknown") gpuStr += ' [max: $gpuMaxTextureSize]';
			parts.push(gpuStr);
		}
		if (totalRAM != "Unknown" && totalRAM.length > 0) parts.push('RAM: $totalRAM');
		_summary = parts.join("\n");
	}

	// ── Helpers plataforma ────────────────────────────────────────────────────

	/**
	 * Lee un valor del registro de Windows.
	 * Devuelve "" si falla o no estamos en Windows.
	 */
	static function _readRegistry(hive:String, key:String, value:String):Dynamic
	{
		#if (windows && sys)
		try
		{
			// Usamos reg.exe como fallback universal (siempre disponible en Win)
			var p = new Process("reg", [
				"query", '$hive\\$key', "/v", value, "/t", "REG_SZ"
			]);
			if (p.exitCode() != 0) return "";
			var output = p.stdout.readAll().toString();
			// Formato: "    ValName    REG_SZ    ActualValue"
			for (line in output.split("\n"))
			{
				if (line.indexOf(value) >= 0 && line.indexOf("REG_") >= 0)
				{
					var parts = ~/[ \t]+/.split(line.trim());
					if (parts.length >= 3)
					{
						var raw = parts[parts.length - 1].trim();
						// If it's an integer, return Int
						var asInt = Std.parseInt(raw);
						if (raw == Std.string(asInt)) return asInt;
						return raw;
					}
				}
			}
		}
		catch (e:Dynamic) {}
		#end
		return "";
	}
}
