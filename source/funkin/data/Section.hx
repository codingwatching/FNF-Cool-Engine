package funkin.data;

/**
 * SwagSection MEJORADO - Support for multiple characters
 */
typedef SwagSection =
{
	var sectionNotes:Array<Dynamic>;
	var lengthInSteps:Int;
	var typeOfSection:Int;
	var mustHitSection:Bool;
	var bpm:Float;
	var changeBPM:Bool;
	var altAnim:Bool;
	
	// === LEGACY ===
	@:optional var gfSing:Bool; // GF canta (legacy)
	
	// === NUEVO SISTEMA ===
	@:optional var characterIndex:Int; // Index of the character that canta (from array characters)
	@:optional var strumsGroupId:String; // ID del grupo de strums a usar
	@:optional var activeCharacters:Array<Int>; // Array of indices of characters activos in this section
	
	@:optional var stage:String;
}

class Section
{
	public var sectionNotes:Array<Dynamic> = [];

	public var lengthInSteps:Int = 16;
	public var typeOfSection:Int = 0;
	public var mustHitSection:Bool = true;
	
	// === LEGACY ===
	public var gfSing:Bool = false;     // GF canta (legacy, mirror of SwagSection)

	// Nuevo
	public var characterIndex:Int = -1; // -1 = usar logic default (mustHitSection)
	public var strumsGroupId:String = null;
	public var activeCharacters:Array<Int> = null; // null = solo personaje principal

	/**
	 *	Copies the first section into the second section!
	 */
	public static var COPYCAT:Int = 0;

	public function new(lengthInSteps:Int = 16)
	{
		this.lengthInSteps = lengthInSteps;
	}
	
	/**
	 * new: Get character that canta according to logic
	 */
	public function getSingingCharacterIndex(defaultDadIndex:Int = 1, defaultBFIndex:Int = 2):Int
	{
		// If is especificó a character manualmente, usar that
		if (characterIndex >= 0)
			return characterIndex;
		
		// If no, usar logic legacy
		if (mustHitSection)
			return defaultBFIndex; // Boyfriend
		else
			return defaultDadIndex; // Dad
	}
	
	/**
	 * new: Get all the characters activos in this section
	 */
	public function getActiveCharacterIndices(defaultDadIndex:Int = 1, defaultBFIndex:Int = 2):Array<Int>
	{
		// Si se especificaron personajes activos, usar esos
		if (activeCharacters != null && activeCharacters.length > 0)
			return activeCharacters;
		
		// Si no, retornar solo el personaje principal
		return [getSingingCharacterIndex(defaultDadIndex, defaultBFIndex)];
	}
}