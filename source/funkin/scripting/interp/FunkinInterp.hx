package funkin.scripting.interp;

import flixel.FlxG;
#if HSCRIPT_ALLOWED
import hscript.Interp;
import hscript.Expr;
// hscript.Expr.Error existe en 2.4+ como clase base de errores
// En versiones muy antiguas puede no tener `.e` — usar Dynamic como fallback
#end

class FunkinInterp extends Interp
{
	public var scriptObject:Dynamic = null;

	public function new()
	{
		super();
	}

	// ── 1. Interceptar Lectura y Funciones ──
	override public function resolve(id:String):Dynamic
	{
		var l = locals.get(id);
		if (l != null)
			return l.r;

		// FIX: usar exists() en vez de `v != null`.
		// StringMap.get() devuelve null tanto cuando la clave no existe como cuando
		// la clave existe con valor null. La comprobación `v != null` hacía que
		// variables intencionalmente nulas (gf, dad, bf en canciones sin esos
		// personajes, health = 0, etc.) no se encontrasen y se lanzase
		// EUnknownVariable en silencio, haciendo que los scripts fallaran sin
		// mostrar ningún error visible al usuario.
		if (variables.exists(id))
			return variables.get(id);

		if (scriptObject != null)
		{
			try
			{
				if (Reflect.hasField(scriptObject, id) || Reflect.getProperty(scriptObject, id) != null)
				{
					var prop = Reflect.getProperty(scriptObject, id);

					// Si es una función, hacemos un auto-bind para que 'this' apunte al objeto correcto
					if (Reflect.isFunction(prop))
					{
						return Reflect.makeVarArgs(function(args)
						{
							return Reflect.callMethod(scriptObject, prop, args);
						});
					}
					return prop; // Retornar variable normal
				}
			}
			catch (e:Dynamic)
			{
			}
		}

		throw hscript.Expr.Error.EUnknownVariable(id);
	}

	override public function expr(e:hscript.Expr):Dynamic
	{
		// FIX: separar la inspección estructural (que necesita try/catch por
		// compatibilidad de versiones de hscript) de la evaluación real.
		//
		// El problema original: un único try/catch envolvía TODO, incluyendo
		// `expr(params[2])` (evaluar el RHS de la asignación). Si el RHS lanzaba
		// un error de runtime (EUnknownVariable, etc.), el catch lo tragaba en
		// silencio y llamaba a `super.expr(e)`, que volvía a evaluar el RHS dos
		// veces y hacía que los errores nunca llegasen a _handleError.
		//
		// Solución: el try/catch solo cubre la inspección de la estructura del
		// Expr (que puede fallar por diferencias entre hscript 2.4/2.5). La
		// evaluación del RHS y la escritura en variables/scriptObject quedan
		// FUERA del try/catch para que los errores de runtime propaguen
		// normalmente hasta HScriptInstance._handleError.

		// Paso 1 — inspección estructural (try/catch solo para compat de versiones)
		var assignId:Null<String> = null;
		var assignRhsExpr:Dynamic = null;

		try
		{
			var isStruct = Reflect.hasField(e, "e");
			var def = isStruct ? Reflect.field(e, "e") : e;

			if (Type.enumConstructor(def) == "EBinop")
			{
				var params = Type.enumParameters(def);
				if (params[0] == "=")
				{
					var def1 = isStruct ? Reflect.field(params[1], "e") : params[1];
					if (Type.enumConstructor(def1) == "EIdent")
					{
						assignId = Type.enumParameters(def1)[0];
						assignRhsExpr = params[2];
					}
				}
			}
		}
		catch (structEx:Dynamic)
		{
			// La inspección estructural falló (diferencia de API entre versiones
			// de hscript) → delegar en super sin intentar la redirección.
			return super.expr(e);
		}

		// Si no es una asignación simple `ident = valor`, delegar en super.
		if (assignId == null)
			return super.expr(e);

		// Paso 2 — evaluación real: los errores de runtime propagan normalmente.
		var val = expr(assignRhsExpr);

		if (locals.exists(assignId))
		{
			locals.get(assignId).r = val;
			return val;
		}

		// Si la variable le pertenece al Stage/Character, actualizarla ahí directamente
		if (scriptObject != null)
		{
			try
			{
				if (Reflect.hasField(scriptObject, assignId) || Reflect.getProperty(scriptObject, assignId) != null)
				{
					Reflect.setProperty(scriptObject, assignId, val);
					return val;
				}
			}
			catch (_:Dynamic)
			{
			}
		}

		variables.set(assignId, val);
		return val;
	}
}
