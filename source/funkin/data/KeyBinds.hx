package funkin.data;

import flixel.FlxG;
import funkin.data.SaveData;

class KeyBinds
{
    public static function resetBinds():Void
	{
        SaveData.data.upBind     = "W";
        SaveData.data.downBind   = "S";
        SaveData.data.leftBind   = "A";
        SaveData.data.rightBind  = "D";
        SaveData.data.killBind   = "R";
        SaveData.data.acceptBind = "ENTER";
        SaveData.data.backBind   = "ESCAPE";
        SaveData.data.pauseBind  = "P";
        SaveData.data.cheatBind  = "SEVEN";
        data.PlayerSettings.player1.controls.loadKeyBinds();
    }

    public static function keyCheck():Void
    {
        if (SaveData.data.upBind     == null) SaveData.data.upBind     = "W";
        if (SaveData.data.downBind   == null) SaveData.data.downBind   = "S";
        if (SaveData.data.leftBind   == null) SaveData.data.leftBind   = "A";
        if (SaveData.data.rightBind  == null) SaveData.data.rightBind  = "D";
        if (SaveData.data.killBind   == null) SaveData.data.killBind   = "R";
        if (SaveData.data.acceptBind == null) SaveData.data.acceptBind = "ENTER";
        if (SaveData.data.backBind   == null) SaveData.data.backBind   = "ESCAPE";
        if (SaveData.data.pauseBind  == null) SaveData.data.pauseBind  = "P";
        if (SaveData.data.cheatBind  == null) SaveData.data.cheatBind  = "SEVEN";
    }
}
