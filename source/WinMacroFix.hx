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
 * FIX: la búsqueda recursiva se limita a export/<buildType>/
 * para no parchear headers de debug cuando se compila release (y viceversa).
 *
 * En project.hxp añade (solo para Windows):
 *   addHaxeFlag("--macro WinMacroFix.apply()");
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
			var cwd = Sys.getCwd().split("\\").join("/");
			if (cwd.endsWith("/")) cwd = cwd.substr(0, cwd.length - 1);

			var colorRel = 'flixel/util/_FlxColor/FlxColor_Impl_.h';
			var keyRel   = 'flixel/input/keyboard/_FlxKey/FlxKey_Impl_.h';

			// Determinar el tipo de build para acotar la búsqueda al directorio correcto.
			// Sin esto, una búsqueda amplia encuentra primero los headers de debug y
			// parchea esos en lugar de los de release (o viceversa).
			var buildType = Context.defined('debug') ? 'debug' : 'release';
			if (Context.defined('32bit')) buildType = '32bit';

			trace('[WinMacroFix] buildType=' + buildType + ' cwd=' + cwd);

			// Raíz de búsqueda: sólo dentro de export/<buildType>/
			var searchRoot = cwd + '/export/' + buildType;

			// HXCPP_OUT tiene prioridad si está definido y apunta al buildType correcto
			var targets:Array<{path:String, undefs:String}> = [];
			var envOut = Context.definedValue('HXCPP_OUT');
			if (envOut != null && envOut != '')
			{
				var base = envOut.split("\\").join("/");
				_tryAdd(targets, base + '/include/' + colorRel, UNDEFS_COLOR);
				_tryAdd(targets, base + '/include/' + keyRel,   UNDEFS_KEY);
			}

			// Búsqueda recursiva acotada al buildType correcto
			if (targets.length < 2 && FileSystem.exists(searchRoot))
			{
				var needles = [
					{ rel: colorRel, undefs: UNDEFS_COLOR },
					{ rel: keyRel,   undefs: UNDEFS_KEY   },
				];
				for (t in _findHeaders(searchRoot, needles))
					if (!_alreadyHas(targets, t.path))
						targets.push(t);
			}

			trace('[WinMacroFix] targets=' + targets.length);
			for (t in targets)
				trace('[WinMacroFix] found: ' + t.path);

			if (targets.length == 0)
			{
				trace('[WinMacroFix] WARNING: no headers found under ' + searchRoot
				    + ' — the patch was NOT applied. MSVC may fail with C2059.');
				return;
			}

			for (t in targets)
			{
				var content:String;
				try { content = File.getContent(t.path); }
				catch(e) { trace('[WinMacroFix] Cannot read: ' + t.path + ' — ' + e); continue; }

				// Evitar doble parcheo
				if (content.indexOf('#undef TRANSPARENT') != -1 ||
				    content.indexOf('#undef DELETE') != -1)
				{
					trace('[WinMacroFix] Already patched: ' + t.path);
					continue;
				}

				// Inyectar después del primer #pragma once, o al principio si no existe
				var insertAfter = '#pragma once';
				var idx = content.indexOf(insertAfter);
				if (idx == -1)
					content = t.undefs + content;
				else
				{
					var pos = idx + insertAfter.length;
					content = content.substr(0, pos) + '\n' + t.undefs + content.substr(pos);
				}

				try
				{
					File.saveContent(t.path, content);
					trace('[WinMacroFix] Patched OK: ' + t.path);
				}
				catch(e) { trace('[WinMacroFix] Cannot write: ' + t.path + ' — ' + e); }
			}
		});
	}

	// ── helpers ────────────────────────────────────────────────────────────────

	static function _findHeaders(
		startDir : String,
		needles  : Array<{rel:String, undefs:String}>
	) : Array<{path:String, undefs:String}>
	{
		var out:Array<{path:String, undefs:String}> = [];
		_walk(startDir, needles, out);
		return out;
	}

	static function _walk(
		dir     : String,
		needles : Array<{rel:String, undefs:String}>,
		out     : Array<{path:String, undefs:String}>
	) : Void
	{
		if (out.length >= needles.length) return;

		var entries:Array<String>;
		try { entries = FileSystem.readDirectory(dir); } catch(_) { return; }

		for (entry in entries)
		{
			var full = dir + '/' + entry;
			if (FileSystem.isDirectory(full))
			{
				// Saltar directorios que nunca contienen headers generados de Haxe
				if (entry == 'bin' || entry == 'assets' || entry == 'haxe' ||
				    entry == 'backup' || entry == 'export') continue;
				_walk(full, needles, out);
				if (out.length >= needles.length) return;
			}
			else
			{
				var norm = full.split("\\").join("/");
				for (n in needles)
					if (norm.endsWith('/' + n.rel) && !_alreadyHas(out, norm))
					{
						out.push({ path: norm, undefs: n.undefs });
						break;
					}
			}
		}
	}

	static function _tryAdd(arr:Array<{path:String, undefs:String}>, path:String, undefs:String):Void
	{
		if (FileSystem.exists(path) && !_alreadyHas(arr, path))
			arr.push({ path: path, undefs: undefs });
	}

	static function _alreadyHas(arr:Array<{path:String, undefs:String}>, path:String):Bool
	{
		for (t in arr) if (t.path == path) return true;
		return false;
	}
}
#end
