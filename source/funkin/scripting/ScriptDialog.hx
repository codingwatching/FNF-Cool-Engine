package funkin.scripting;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;

/**
 * ScriptDialog — diálogo de texto accesible desde scripts Lua y HScript.
 *
 * ─── Uso desde Lua ────────────────────────────────────────────────────────────
 *
 *   -- Notificación rápida
 *   notif("¡Nivel completado!", 3.0)
 *
 *   -- Diálogo con un solo mensaje
 *   local d = quickDialog("Personaje", "¡Hola! Soy un personaje.", 4.0, "onDialogDone")
 *
 *   -- Secuencia de diálogos
 *   dialogSequence(
 *     { {speaker="BF", text="¡Oye!"}, {speaker="GF", text="¿Qué pasa?"} },
 *     "onDialogDone"
 *   )
 *
 *   function onDialogDone()
 *     log("Diálogo terminado")
 *   end
 *
 * ─── Uso desde HScript ────────────────────────────────────────────────────────
 *
 *   var d = ScriptDialog.quick("BF", "¡Hola mundo!", 3.0);
 *   d.onFinish = function() { trace("Hecho"); };
 *   var d2 = ScriptDialog.sequence([
 *     { speaker: "BF", text: "Línea 1" },
 *     { speaker: "GF", text: "Línea 2" }
 *   ], function() { trace("Secuencia completa"); });
 */
class ScriptDialog extends FlxSprite
{
	// ── Configuración ─────────────────────────────────────────────────────────

	/** Callback llamado al terminar o cerrar el diálogo. */
	public var onFinish:Null<Void->Void> = null;

	/** Si el jugador puede saltar líneas con ENTER/SPACE. */
	public var allowSkipLine:Bool = true;

	// ── Estado ────────────────────────────────────────────────────────────────

	var _lines:Array<_DialogLine>  = [];
	var _curLine:Int               = 0;
	var _timer:Null<FlxTimer>      = null;
	var _autoAdvance:Float         = 0.0;
	var _finished:Bool             = false;

	// ── UI ────────────────────────────────────────────────────────────────────

	var _bg:FlxSprite;
	var _speakerText:FlxText;
	var _bodyText:FlxText;

	// ── Dimensiones del panel ─────────────────────────────────────────────────
	static inline final PANEL_H  :Int = 140;
	static inline final PANEL_PAD:Int = 16;

	// ─────────────────────────────────────────────────────────────────────────

	public function new()
	{
		super(0, 0);

		// Fondo semitransparente en la parte inferior de la pantalla
		_bg = new FlxSprite(0, FlxG.height - PANEL_H)
			.makeGraphic(FlxG.width, PANEL_H, 0xCC111111);
		_bg.scrollFactor.set(0, 0);

		var textY = FlxG.height - PANEL_H + PANEL_PAD;

		_speakerText = new FlxText(PANEL_PAD, textY, FlxG.width - PANEL_PAD * 2, '', 22);
		_speakerText.setFormat(Paths.font('Funkin.otf'), 22, FlxColor.YELLOW, LEFT, OUTLINE, FlxColor.BLACK);
		_speakerText.borderSize = 2;
		_speakerText.scrollFactor.set(0, 0);

		_bodyText = new FlxText(PANEL_PAD, textY + 30, FlxG.width - PANEL_PAD * 2, '', 18);
		_bodyText.setFormat(Paths.font('Funkin.otf'), 18, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		_bodyText.borderSize = 1;
		_bodyText.scrollFactor.set(0, 0);

		makeGraphic(1, 1, FlxColor.TRANSPARENT);
		scrollFactor.set(0, 0);
	}

	// ── API estática ──────────────────────────────────────────────────────────

	/**
	 * Crea un diálogo de una sola línea y lo añade al estado actual.
	 * @param speaker  Nombre del hablante (vacío = solo mensaje).
	 * @param text     Texto del mensaje.
	 * @param duration Segundos antes de cerrar automáticamente (0 = sin cierre auto).
	 * @param onDone   Callback al cerrar.
	 */
	public static function quick(speaker:String, text:String,
		duration:Float = 0.0, ?onDone:Void->Void):ScriptDialog
	{
		var d = new ScriptDialog();
		d.addLine(speaker, text, duration);
		if (onDone != null) d.onFinish = onDone;
		d._show();
		return d;
	}

	/**
	 * Crea una secuencia de diálogos y la añade al estado actual.
	 * @param lines   Array de { speaker, text } o { speaker, text, duration }.
	 * @param onDone  Callback al terminar toda la secuencia.
	 */
	public static function sequence(lines:Array<{speaker:String, text:String}>,
		?onDone:Void->Void):ScriptDialog
	{
		var d = new ScriptDialog();
		for (l in lines) d.addLine(l.speaker, l.text);
		if (onDone != null) d.onFinish = onDone;
		d._show();
		return d;
	}

	// ── API de instancia ──────────────────────────────────────────────────────

	/** Añade una línea a la cola de diálogo. */
	public function addLine(speaker:String, text:String, autoAdvance:Float = 0.0):Void
	{
		_lines.push({ speaker: speaker, text: text, autoAdvance: autoAdvance });
	}

	/** Cierra el diálogo inmediatamente. */
	public function close():Void
	{
		if (_finished) return;
		_finished = true;
		if (_timer != null) { _timer.cancel(); _timer = null; }
		_removeFromState();
		if (onFinish != null) { var cb = onFinish; onFinish = null; try cb() catch (_) {}; }
	}

	/** Avanza a la siguiente línea. */
	public function advance():Void
	{
		if (_finished) return;
		_curLine++;
		if (_curLine >= _lines.length)
		{
			close();
			return;
		}
		_showLine(_curLine);
	}

	// ── Internos ──────────────────────────────────────────────────────────────

	function _show():Void
	{
		var state = FlxG.state;
		if (state == null) return;
		state.add(_bg);
		state.add(_speakerText);
		state.add(_bodyText);
		state.add(this);
		_showLine(0);
	}

	function _showLine(idx:Int):Void
	{
		if (idx >= _lines.length) { close(); return; }
		var l = _lines[idx];
		_speakerText.text = l.speaker ?? '';
		_bodyText.text    = l.text    ?? '';

		if (l.autoAdvance > 0)
		{
			_autoAdvance = l.autoAdvance;
			_timer = new FlxTimer();
			_timer.start(_autoAdvance, function(_) { _timer = null; advance(); });
		}
		else
		{
			_autoAdvance = 0;
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (_finished) return;
		if (!allowSkipLine) return;
		if (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.SPACE
			|| FlxG.keys.justPressed.Z || FlxG.keys.justPressed.X)
		{
			if (_timer != null) { _timer.cancel(); _timer = null; }
			advance();
		}
	}

	function _removeFromState():Void
	{
		var state = FlxG.state;
		if (state == null) return;
		state.remove(_bg, true);
		state.remove(_speakerText, true);
		state.remove(_bodyText, true);
		state.remove(this, true);
	}

	override function destroy():Void
	{
		if (_timer != null) { _timer.cancel(); _timer = null; }
		_bg        = null;
		_speakerText = null;
		_bodyText    = null;
		super.destroy();
	}
}

private typedef _DialogLine =
{
	var speaker:String;
	var text:String;
	var autoAdvance:Float;
}
