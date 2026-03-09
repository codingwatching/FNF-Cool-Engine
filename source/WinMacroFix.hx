package;

#if macro
import haxe.macro.Context;
import sys.io.File;
import sys.FileSystem;

using StringTools;
/**
 * WinMacroFix.hx — source/WinMacroFix.hx
 *
 * Parchea los .h generados de FlxKey y FlxColor DESPUÉS de que Haxe
 * los genera pero ANTES de que MSVC los compile.
 * Inyecta #undef al principio de cada header para eliminar las macros
 * de windows.h que colisionan (TRANSPARENT, DELETE, etc.).
 *
 * En project.xml añade:
 *   <haxeflag name="--macro" value="WinMacroFix.apply()" if="windows"/>
 */
class WinMacroFix
{
	static final UNDEFS_COLOR = '
#ifdef TRANSPARENT
#undef TRANSPARENT
#endif
#ifdef BLACK
#undef BLACK
#endif
#ifdef WHITE
#undef WHITE
#endif
#ifdef RED
#undef RED
#endif
#ifdef GREEN
#undef GREEN
#endif
#ifdef BLUE
#undef BLUE
#endif
';

	static final UNDEFS_KEY = '
#ifdef DELETE
#undef DELETE
#endif
#ifdef HOME
#undef HOME
#endif
#ifdef END
#undef END
#endif
#ifdef INSERT
#undef INSERT
#endif
#ifdef PAUSE
#undef PAUSE
#endif
#ifdef PRINT
#undef PRINT
#endif
#ifdef ESCAPE
#undef ESCAPE
#endif
';

	public static function apply()
	{
		Context.onAfterGenerate(function()
		{
			// Usar ruta absoluta del proyecto para que funcione sin importar
			// el directorio de trabajo durante la ejecución del macro.
			var cwd = Sys.getCwd().split("\\").join("/");
			if (cwd.endsWith("/")) cwd = cwd.substr(0, cwd.length - 1);

			var colorRel = 'include/flixel/util/_FlxColor/FlxColor_Impl_.h';
			var keyRel   = 'include/flixel/input/keyboard/_FlxKey/FlxKey_Impl_.h';

			// Todas las posibles rutas de salida de Lime (debug, release, 32bit)
			var baseDirs = [
				'export/debug/windows/obj',
				'export/release/windows/obj',
				'export/32bit/windows/obj',
				'export/debug/windows/cpp/obj',
				'export/release/windows/cpp/obj',
			];

			// También respetar HXCPP_OUT si viene definido
			var envOut = Context.definedValue('HXCPP_OUT');
			if (envOut != null && envOut != '')
				baseDirs.unshift(envOut.split("\\").join("/"));

			// Construir candidatos con ruta absoluta Y relativa
			var candidateDirs = [];
			for (b in baseDirs)
			{
				candidateDirs.push(cwd + '/' + b); // absoluta
				candidateDirs.push(b);              // relativa (fallback)
			}

			var targets = [];
			for (dir in candidateDirs)
			{
				var cp = dir + '/' + colorRel;
				var kp = dir + '/' + keyRel;
				if (FileSystem.exists(cp) && !_alreadyHas(targets, cp))
					targets.push({ path: cp, undefs: UNDEFS_COLOR });
				if (FileSystem.exists(kp) && !_alreadyHas(targets, kp))
					targets.push({ path: kp, undefs: UNDEFS_KEY });
				if (targets.length == 2) break;
			}
			trace('[WinMacroFix] cwd=' + cwd + ' targets=' + targets.length);

			for (t in targets)
			{
				if (!FileSystem.exists(t.path))
				{
					trace('[WinMacroFix] No encounter: ' + t.path);
					continue;
				}

				var content = File.getContent(t.path);

				// Solo parchear si aún no tiene los undefs (evita doble parcheo)
				if (content.indexOf('#undef TRANSPARENT') != -1 ||
				    content.indexOf('#undef DELETE') != -1)
				{
					trace('[WinMacroFix] Now parched: ' + t.path);
					continue;
				}

				// Inyectar después del primer #pragma once o #ifndef guard
				var insertAfter = '#pragma once';
				var idx = content.indexOf(insertAfter);
				if (idx == -1)
				{
					// Si no hay pragma once, insertar al principio
					content = t.undefs + content;
				}
				else
				{
					var pos = idx + insertAfter.length;
					content = content.substr(0, pos) + '\n' + t.undefs + content.substr(pos);
				}

				File.saveContent(t.path, content);
				trace('[WinMacroFix] Parched OK: ' + t.path);
			}
		});
	}

	static function _alreadyHas(arr:Array<{path:String, undefs:String}>, path:String):Bool
	{
		for (t in arr) if (t.path == path) return true;
		return false;
	}
}
#end