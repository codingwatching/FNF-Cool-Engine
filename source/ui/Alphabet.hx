package ui;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.util.FlxTimer;
import haxe.Json;

using StringTools;

// ═══════════════════════════════════════════════════════════════════════════
//  AlphabetConfig  —  cargado una vez desde  data/alphabetConfig.json
//  Puede sobreescribirse por mod sin recompilar.
// ═══════════════════════════════════════════════════════════════════════════
class AlphabetConfig
{
	// ── singleton ────────────────────────────────────────────────────────────

	static var _instance:AlphabetConfig;

	public static var instance(get, never):AlphabetConfig;
	static function get_instance():AlphabetConfig
	{
		if (_instance == null) _instance = new AlphabetConfig();
		return _instance;
	}

	/** Fuerza una recarga (p.ej. al cambiar de mod en runtime). */
	public static function reload():Void { _instance = null; }

	// ── campos ───────────────────────────────────────────────────────────────

	public var atlasKey:String            = 'UI/alphabet';
	public var charFrameRate:Int          = 24;
	public var charScale:Float            = 1.0;

	public var letterSpacing:Float        = 3;
	public var spaceWidth:Float           = -1;   // -1 = auto (20 normal / 40 bold)
	public var lineHeight:Float           = 55;

	public var typedDelay:Float           = 0.05;
	public var typedRandom:Bool           = true;
	public var startDelay:Float           = 0;

	public var boldRowHeight:Float        = 60;
	public var normalRowYBase:Float       = 90;
	public var normalRowHeight:Float      = 60;
	public var typedLetterOffsetX:Float   = 90;

	public var symbolNameMap:Map<String,String>;
	public var charYOffsets:Map<String,Float>;

	// ── constructor ──────────────────────────────────────────────────────────

	function new()
	{
		symbolNameMap = [
			"."      => "period",
			","      => "comma",
			"'"      => "apostrophe",
			"!"      => "exclamation",
			"?"      => "question",
			"/"      => "forward slash",
			"\\"     => "back slash",
			"\""     => "quote",
			"\u2022" => "bullet",
			"\u00A1" => "inverted exclamation",
			"\u00BF" => "inverted question",
			"&"      => "ampersand",
			"<"      => "less than",
			">"      => "greater than",
			";"      => "semicolon",
			":"      => "colon",
			"["      => "open bracket",
			"]"      => "close bracket",
			"{"      => "open curly",
			"}"      => "close curly",
			"|"      => "pipe",
			"~"      => "tilde",
			"#"      => "hash",
			"$"      => "dollar",
			"%"      => "percent",
			"("      => "open paren",
			")"      => "close paren",
			"*"      => "asterisk",
			"+"      => "plus",
			"-"      => "minus",
			"="      => "equals",
			"@"      => "at",
			"^"      => "caret",
			"_"      => "underscore",
		];

		charYOffsets = [
			"."      => 50,
			","      => 50,
			"_"      => 50,
			";"      => 20,
			":"      => 20,
			"\u00BF" => 10,
			"\u00A1" => 10,
		];

		tryLoadJson();
	}

	// ── carga del JSON externo ────────────────────────────────────────────────

	function tryLoadJson():Void
	{
		var raw:String = null;

		try { raw = Paths.getText('data/alphabetConfig.json'); }
		catch (e) { return; }

		if (raw == null || raw.trim() == "") return;

		var obj:Dynamic;
		try   { obj = Json.parse(raw); }
		catch (e) { FlxG.log.warn('[AlphabetConfig] Invalid JSON: $e'); return; }

		// campos escalares
		if (obj.atlasKey           != null) atlasKey           = obj.atlasKey;
		if (obj.charFrameRate      != null) charFrameRate       = Std.int(obj.charFrameRate);
		if (obj.charScale          != null) charScale           = obj.charScale;
		if (obj.letterSpacing      != null) letterSpacing       = obj.letterSpacing;
		if (obj.spaceWidth         != null) spaceWidth          = obj.spaceWidth;
		if (obj.lineHeight         != null) lineHeight          = obj.lineHeight;
		if (obj.typedDelay         != null) typedDelay          = obj.typedDelay;
		if (obj.typedRandom        != null) typedRandom         = obj.typedRandom;
		if (obj.startDelay         != null) startDelay          = obj.startDelay;
		if (obj.boldRowHeight      != null) boldRowHeight       = obj.boldRowHeight;
		if (obj.normalRowYBase     != null) normalRowYBase      = obj.normalRowYBase;
		if (obj.normalRowHeight    != null) normalRowHeight     = obj.normalRowHeight;
		if (obj.typedLetterOffsetX != null) typedLetterOffsetX  = obj.typedLetterOffsetX;

		// mapas (el JSON puede agregar / sobreescribir entradas individuales)
		if (obj.symbolNameMap != null)
			for (k in Reflect.fields(obj.symbolNameMap))
				symbolNameMap.set(k, Reflect.field(obj.symbolNameMap, k));

		if (obj.charYOffsets != null)
			for (k in Reflect.fields(obj.charYOffsets))
				charYOffsets.set(k, Reflect.field(obj.charYOffsets, k));
	}
}


// ═══════════════════════════════════════════════════════════════════════════
//  Alphabet  —  FlxSpriteGroup de glifos AlphaCharacter
// ═══════════════════════════════════════════════════════════════════════════
class Alphabet extends FlxSpriteGroup
{
	// ── API public ───────────────────────────────────────────────────────────
	//
	//  Cada propiedad con Null<T> toma el valor de AlphabetConfig si no se
	//  assigns explicitly. Assign them before calling rebuild().

	public var text:String        = "";
	public var bold:Bool          = false;
	public var typed:Bool         = false;

	public var letterSpacing:Null<Float>  = null;
	public var spaceWidth:Null<Float>     = null;
	public var lineHeight:Null<Float>     = null;
	public var charScale:Null<Float>      = null;
	public var atlasKey:Null<String>      = null;
	public var charFrameRate:Null<Int>    = null;
	public var typedDelay:Null<Float>     = null;

	// comportamiento menu
	public var isMenuItem:Bool  = false;
	public var targetY:Float    = 0;

	// ── privado ───────────────────────────────────────────────────────────────

	var _lastSprite:AlphaCharacter;
	var _lastWasSpace:Bool = false;
	var _xPosResetted:Bool = false;
	var _splitWords:Array<String> = [];
	var _yMulti:Float = 1;

	// resolution instancia → config
	inline function cfg() return AlphabetConfig.instance;
	inline function _spacing()  return letterSpacing  != null ? letterSpacing  : cfg().letterSpacing;
	inline function _lheight()  return lineHeight     != null ? lineHeight     : cfg().lineHeight;
	inline function _scale()    return charScale      != null ? charScale      : cfg().charScale;
	inline function _atlas()    return atlasKey       != null ? atlasKey       : cfg().atlasKey;
	inline function _fps()      return charFrameRate  != null ? charFrameRate  : cfg().charFrameRate;
	inline function _delay()    return typedDelay     != null ? typedDelay     : cfg().typedDelay;
	inline function _space()
	{
		if (spaceWidth != null) return spaceWidth;
		var sw = cfg().spaceWidth;
		return sw >= 0 ? sw : (bold ? 40.0 : 20.0);
	}

	// ── constructor ──────────────────────────────────────────────────────────

	public function new(x:Float, y:Float, text:String = "", bold:Bool = false, typed:Bool = false)
	{
		super(x, y);
		this.text  = text;
		this.bold  = bold;
		this.typed = typed;
		if (text != "") build();
	}

	// ── API ──────────────────────────────────────────────────────────────────

	/** Borra y vuelve a renderizar el texto actual. */
	public function rebuild():Void
	{
		clear();
		_lastSprite   = null;
		_lastWasSpace = false;
		_xPosResetted = false;
		_yMulti       = 1;
		_splitWords   = [];
		build();
	}

	// ── build internal ─────────────────────────────────────────────────

	function build():Void
	{
		_splitWords = text.split("");
		typed ? buildTyped() : buildImmediate();
	}

	function buildImmediate():Void
	{
		var xPos:Float = 0;
		for (ch in _splitWords)
		{
			if (ch == " " || ch == "-") { _lastWasSpace = true; continue; }
			if (!AlphaCharacter.supportsChar(ch)) continue;

			if (_lastSprite != null)
				xPos = _lastSprite.x + _lastSprite.width + _spacing();

			if (_lastWasSpace) { xPos += _space(); _lastWasSpace = false; }

			var letter = spawnChar(ch, xPos, 0);
			add(letter);
			_lastSprite = letter;
		}
	}

	function buildTyped():Void
	{
		var loopNum:Int = 0;
		var xPos:Float  = 0;
		var curRow:Int  = 0;

		new FlxTimer().start(cfg().startDelay + _delay(), function(tmr:FlxTimer)
		{
			var ch = _splitWords[loopNum];

			if (ch == "\n")
			{
				_yMulti++;
				_xPosResetted = true;
				xPos = 0;
				curRow++;
			}
			else if (ch == " ")
			{
				_lastWasSpace = true;
			}
			else if (AlphaCharacter.supportsChar(ch))
			{
				if (_lastSprite != null && !_xPosResetted)
				{
					_lastSprite.updateHitbox();
					xPos += _lastSprite.width + _spacing();
				}
				else _xPosResetted = false;

				if (_lastWasSpace) { xPos += _space(); _lastWasSpace = false; }

				var letter = spawnChar(ch, xPos, _lheight() * _yMulti);
				letter.row = curRow;
				if (!bold) letter.x += cfg().typedLetterOffsetX;

				if (FlxG.random.bool(40))
					FlxG.sound.play(Paths.soundRandom('GF_', 1, 4));

				add(letter);
				_lastSprite = letter;
			}

			loopNum++;

			if (cfg().typedRandom)
				tmr.time = FlxG.random.float(_delay() * 0.8, _delay() * 1.8);

		}, _splitWords.length);
	}

	function spawnChar(ch:String, x:Float, y:Float):AlphaCharacter
	{
		var letter = new AlphaCharacter(x, y, _atlas(), bold, _fps());
		letter.scale.set(_scale(), _scale());
		letter.createChar(ch);
		letter.updateHitbox();
		return letter;
	}

	// ── update ────────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		if (isMenuItem)
		{
			var scaledY = FlxMath.remapToRange(targetY, 0, 1, 0, 1.3);
			y = FlxMath.lerp(y, (scaledY * 120) + (FlxG.height * 0.38) - 50, 0.16);
			x = FlxMath.lerp(x, (targetY * 20) + 90, 0.16);
		}
		super.update(elapsed);
	}
}

// ═══════════════════════════════════════════════════════════════════════════
//  AlphaCharacter  —  sprite de un solo glifo
// ═══════════════════════════════════════════════════════════════════════════
class AlphaCharacter extends FlxSprite
{
	public static var alphabet:String =
		"abcdefghijklmnopqrstuvwxyz" +
		"àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿšžß";

	public static var numbers:String  = "1234567890";

	/** Symbols whose name in the atlas is the character itself. */
	public static var directSymbols:String = "#$%&*+-:;<=>@[]^_.!?{}()/\\|~\"',";

	public var row:Int = 0;

	var _bold:Bool;
	var _fps:Int;

	public function new(x:Float, y:Float, atlasKey:String = 'UI/alphabet', bold:Bool = false, fps:Int = 24)
	{
		super(x, y);
		_bold        = bold;
		_fps         = fps;
		frames       = Paths.getSparrowAtlas(atlasKey);
		antialiasing = true;
	}

	// ── static ────────────────────────────────────────────────────────────

	public static function supportsChar(ch:String):Bool
		return alphabet.indexOf(ch.toLowerCase()) != -1
			|| numbers.indexOf(ch)                != -1
			|| isSymbol(ch);

	public static function isSymbol(ch:String):Bool
		return AlphabetConfig.instance.symbolNameMap.exists(ch)
			|| directSymbols.indexOf(ch) != -1;

	// ── punto de entrada ─────────────────────────────────────────────────────

	public function createChar(ch:String):Void
	{
		var lo = ch.toLowerCase();
		if      (numbers.indexOf(ch)  != -1)  createNumber(ch);
		else if (isSymbol(ch))                 createSymbol(ch);
		else if (alphabet.indexOf(lo) != -1)  createLetter(ch);
		updateHitbox();
	}

	// ── privados ─────────────────────────────────────────────────────────────

	inline function suffix():String  return _bold ? " bold" : " normal";

	/**
	 * Alternativa a addByPrefix que evita el WARNING
	 * "Could not parse frame number of ' instance NNNNN'".
	 *
	 * Flixel's addByPrefix intenta parsear el texto que sigue al prefijo como
	 * number of frame. The atlases exportados by Adobe Animate CC nombran its
	 * frames como "a bold instance 10001", "a bold instance 10002", etc. — el
	 * fragmento " instance 10001" no es un entero, por lo que Flixel imprime el
	 * warning (although after adds the frame igualmente).
	 *
	 * This function recoge the nombres of frame directamente of the atlas, the filtra
	 * by prefix and sorts alphabetically (matches the XML order),
	 * then use addByNames — that no intenta parsear numbers — for register the
	 * animation without warnings.
	 */
	function _addByPrefixSafe(animName:String, prefix:String):Void
	{
		if (frames == null) return;

		// Recoger todos los nombres de frame que comienzan con el prefijo dado.
		final names:Array<String> = [];
		for (frame in frames.frames)
		{
			if (frame != null && frame.name != null && frame.name.startsWith(prefix))
				names.push(frame.name);
		}

		if (names.length == 0)
		{
			// Fallback: usar addByPrefix original (genera warning pero no rompe nada)
			animation.addByPrefix(animName, prefix, _fps);
		}
		else
		{
			// Ordenar by name: the frames of Animate CC tienen suffix numeric
			// con padding uniforme ("instance 10001" < "instance 10002"), por lo
			// that the lexicographic order matches the animation order.
			names.sort(function(a, b) return a < b ? -1 : a > b ? 1 : 0);
			animation.addByNames(animName, names, _fps);
		}

		animation.play(animName);
	}

	function addAnim(name:String, prefix:String):Void
	{
		_addByPrefixSafe(name, prefix + suffix());
	}

	function createLetter(ch:String):Void
	{
		var cfg = AlphabetConfig.instance;
		var lo  = ch.toLowerCase();

		// Las letras en el atlas usan:
		//   "a bold instance"       → bold
		//   "to uppercase instance"  → normal uppercase  (ch != it)
		//   "to lowercase instance"  → normal lowercase  (ch == it)
		//
		// NO hay sufijo " bold"/" normal" adicional en las letras.
		var prefix:String = if (_bold)
			lo + " bold"
		else
			lo + " " + (ch != lo ? "uppercase" : "lowercase");

		_addByPrefixSafe(lo, prefix);

		updateHitbox();
		y  = (cfg.normalRowYBase - height);
		y += row * cfg.normalRowHeight;
	}

	function createNumber(num:String):Void
	{
		var cfg = AlphabetConfig.instance;
		addAnim(num, num); 
		updateHitbox();
		y  = (cfg.normalRowYBase - height);
		y += row * cfg.normalRowHeight;
	}

	function createSymbol(ch:String):Void
	{
		var cfg    = AlphabetConfig.instance;
		var prefix = cfg.symbolNameMap.exists(ch) ? cfg.symbolNameMap.get(ch) : ch;
		addAnim(ch, prefix); 
		updateHitbox();
		if (cfg.charYOffsets.exists(ch))
			y += cfg.charYOffsets.get(ch);
	}
}
