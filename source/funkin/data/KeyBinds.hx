package funkin.data;

import flixel.FlxG;

class KeyBinds
{
    public static function resetBinds():Void
	{
        FlxG.save.data.upBind     = "W";
        FlxG.save.data.downBind   = "S";
        FlxG.save.data.leftBind   = "A";
        FlxG.save.data.rightBind  = "D";
        FlxG.save.data.killBind   = "R";
        FlxG.save.data.acceptBind = "ENTER";
        FlxG.save.data.backBind   = "ESCAPE";
        FlxG.save.data.pauseBind  = "P";
        FlxG.save.data.cheatBind  = "SEVEN";
        data.PlayerSettings.player1.controls.loadKeyBinds();
    }

    public static function keyCheck():Void
    {
        if (FlxG.save.data.upBind     == null) FlxG.save.data.upBind     = "W";
        if (FlxG.save.data.downBind   == null) FlxG.save.data.downBind   = "S";
        if (FlxG.save.data.leftBind   == null) FlxG.save.data.leftBind   = "A";
        if (FlxG.save.data.rightBind  == null) FlxG.save.data.rightBind  = "D";
        if (FlxG.save.data.killBind   == null) FlxG.save.data.killBind   = "R";
        if (FlxG.save.data.acceptBind == null) FlxG.save.data.acceptBind = "ENTER";
        if (FlxG.save.data.backBind   == null) FlxG.save.data.backBind   = "ESCAPE";
        if (FlxG.save.data.pauseBind  == null) FlxG.save.data.pauseBind  = "P";
        if (FlxG.save.data.cheatBind  == null) FlxG.save.data.cheatBind  = "SEVEN";
    }
}
