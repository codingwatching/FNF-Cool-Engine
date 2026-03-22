package funkin.gameplay.objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.data.Song.StrumsGroupData;
import funkin.gameplay.notes.NoteSkinSystem;
import funkin.gameplay.notes.StrumNote;

/**
 * StrumsGroup - Representa un grupo de 4 flechas (strums)
 * 
 * Cada grupo tiene:
 * - 4 StrumNotes (LEFT, DOWN, UP, RIGHT)
 * - Position X/and configurable
 * - Visibilidad configurable
 * - Flag de CPU/Player
 * - Espaciado entre flechas configurable
 * 
 * This allows have multiple grupos of strums by song
 * Ejemplo: 2 grupos para CPU (dad_strums_1, dad_strums_2), 1 para jugador
 */
class StrumsGroup
{
	public var strums:FlxTypedGroup<FlxSprite>;
	public var data:StrumsGroupData;
	public var id:String;
	public var isCPU:Bool;
	public var isVisible:Bool;
	
	// Individual strums (for acceso fast)
	public var leftStrum:FlxSprite;
	public var downStrum:FlxSprite;
	public var upStrum:FlxSprite;
	public var rightStrum:FlxSprite;
	
	private var spacing:Float = 110;
	private var scale:Float = 1.0;
	
	public function new(groupData:StrumsGroupData)
	{
		this.data = groupData;
		this.id = groupData.id;
		this.isCPU = groupData.cpu;
		// BUGFIX: if the field "visible" no is in the JSON, groupData.visible
		// llega como null (Haxe no inicializa campos de typedef desde JSON).
		// Normalize to Bool explicit for that the logic of visibility in
		// _finishRestart (isVisible == true) funcione correctamente en todos
		// los targets. GF (id empieza con 'gf_') oculto si no se dice otra cosa.
		this.isVisible = (groupData.visible == true);
		this.spacing = groupData.spacing != null ? groupData.spacing : 110;
		this.scale = groupData.scale != null ? groupData.scale : 1.0;
		
		strums = new FlxTypedGroup<FlxSprite>();
		
		createStrums();
		
		trace('[StrumsGroup] Creado grupo "$id" - CPU: $isCPU, Visible: $isVisible, en (${groupData.x}, ${groupData.y})');
	}
	
	/**
	 * Crear las 4 flechas
	 */
	private function createStrums():Void
	{
		for (i in 0...4)
		{
			var strum:StrumNote = new StrumNote(
				data.x + (i * spacing),
				data.y,
				i
			);
			
			strum.ID = i;
			strum.visible = isVisible;
			
			if (scale != 1.0)
			{
				strum.scale.set(scale, scale);
				strum.updateHitbox();
				// FIX: after of change the scale there is that volver to centrar and re-appliesr
				// los offsets de la skin para la anim 'static'. centerOffsets() solo no
				// basta porque no recalcula los _animOffsets del JSON de skin.
				strum.playAnim('static', true);
			}
			
			strums.add(strum);
			
			// Guardar referencias individuales
			switch (i)
			{
				case 0:
					leftStrum = strum;
				case 1:
					downStrum = strum;
				case 2:
					upStrum = strum;
				case 3:
					rightStrum = strum;
			}
		}
	}
	
	/**
	 * Get strum by direction
	 */
	public function getStrum(direction:Int):FlxSprite
	{
		if (direction < 0 || direction > 3)
			return null;
		
		return switch (direction)
		{
			case 0: leftStrum;
			case 1: downStrum;
			case 2: upStrum;
			case 3: rightStrum;
			default: null;
		}
	}
	
	/**
	 * Aplica configuraciones de downscroll/middlescroll al grupo.
	 * Usar en rewind restart en lugar de calcular posiciones manualmente.
	 */
	public function applyScrollSettings(downscroll:Bool, middlescroll:Bool, upscrollY:Float):Void
	{
		var finalY:Float = downscroll ? (flixel.FlxG.height - 150) : upscrollY;
		var members = strums.members;
		for (j in 0...members.length)
		{
			var s = members[j];
			if (s == null) continue;
			s.y = finalY;
			if (!isCPU)
			{
				// Para el player: ajustar X si middlescroll cambia
				if (middlescroll)
					s.x = (data.x - (flixel.FlxG.width / 4)) + (j * spacing);
				else
					s.x = data.x + (j * spacing);
			}
			else
			{
				// CPU: ocultar completamente en middlescroll (visible=false).
				// Usar visible en lugar de alpha para que no reciba draw calls.
				if (middlescroll)
				{
					s.visible = false;
					s.alpha   = 0.0;
				}
				else
				{
					s.visible = isVisible;
					s.alpha   = isVisible ? 1.0 : 0.0;
				}
			}
		}
	}

	/**
	 * Recarga la skin en todos los StrumNotes del grupo.
	 * Usar tras cambiar la skin activa (p.ej. en rewind de canciones pixel).
	 */
	public function reloadAllStrumSkins(skinData:funkin.gameplay.notes.NoteSkinSystem.NoteSkinData):Void
	{
		strums.forEach(function(s:FlxSprite) {
			if (Std.isOfType(s, StrumNote))
				cast(s, StrumNote).reloadSkin(skinData);
		});
	}

	/**
	 * Tocar animation of confirm in a strum
	 */
	public function playConfirm(direction:Int):Void
	{
		var strum = getStrum(direction);
		if (strum != null && Std.isOfType(strum, StrumNote))
		{
			var strumNote:StrumNote = cast(strum, StrumNote);
			strumNote.playAnim('confirm', true);
		}
	}
	
	/**
	 * Tocar animation of pressed in a strum
	 */
	public function playPressed(direction:Int):Void
	{
		var strum = getStrum(direction);
		if (strum != null && Std.isOfType(strum, StrumNote))
		{
			var strumNote:StrumNote = cast(strum, StrumNote);
			strumNote.playAnim('pressed', true);
		}
	}
	
	/**
	 * Resetear strum a static
	 */
	public function resetStrum(direction:Int):Void
	{
		var strum = getStrum(direction);
		if (strum != null && Std.isOfType(strum, StrumNote))
		{
			var strumNote:StrumNote = cast(strum, StrumNote);
			strumNote.playAnim('static', true);
		}
	}
	
	/**
	 * Update animaciones
	 */
	public function update():Void
	{
		strums.forEach(function(spr:FlxSprite)
		{
			if (Std.isOfType(spr, StrumNote))
			{
				var strumNote:StrumNote = cast(spr, StrumNote);
				// The auto-reset ahora it handles the method update() of StrumNote
				// No necesitamos do nada here
			}
		});
	}
	
	/**
	 * Cambiar visibilidad del grupo
	 */
	public function setVisible(visible:Bool):Void
	{
		isVisible = visible;
		data.visible = visible;
		
		// Iteration directa — without closure
		{
			final m = strums.members; final l = m.length;
			for (i in 0...l) { final s = m[i]; if (s != null) s.visible = visible; }
		}
	}
	
	/**
	 * Move grupo to new position
	 */
	public function setPosition(x:Float, y:Float):Void
	{
		data.x = x;
		data.y = y;
		
		var i:Int = 0;
		// Iteration directa — without closure
		{
			final m = strums.members; final l = m.length;
			for (j in 0...l) { final s = m[j]; if (s != null) { s.x = x + (j * spacing); s.y = y; } }
		}
	}
	
	/**
	 * Cambiar espaciado entre flechas
	 */
	public function setSpacing(newSpacing:Float):Void
	{
		spacing = newSpacing;
		data.spacing = newSpacing;
		
		var i:Int = 0;
		strums.forEach(function(spr:FlxSprite)
		{
			spr.x = data.x + (i * spacing);
			i++;
		});
	}
	
	/**
	 * Destruir
	 */
	public function destroy():Void
	{
		if (strums != null)
		{
			strums.forEach(function(spr:FlxSprite)
			{
				if (spr != null)
					spr.destroy();
			});
			strums.clear();
			strums = null;
		}
		
		leftStrum = null;
		downStrum = null;
		upStrum = null;
		rightStrum = null;
		data = null;
	}
}
