package funkin.data;

import funkin.gameplay.GameState;
import funkin.gameplay.PlayState;

class Ranking
{
	/** Genera la letra de ranking basada en la accuracy del GameState actual. */
	public static function generateLetterRank():String
	{
		var gs       = GameState.get();
		var acc      = gs.accuracy;
		var daRanking:String = 'N/A';

		// Sistema de ranking estilo osu!mania
		var thresholds:Array<{rank:String, min:Float}> = [
			{rank: 'SS', min: 99.99},
			{rank: 'S',  min: 94.99},
			{rank: 'A',  min: 89.99},
			{rank: 'B',  min: 79.99},
			{rank: 'C',  min: 69.99},
			{rank: 'D',  min: 59.99},
		];

		for (t in thresholds)
		{
			if (acc >= t.min)
			{
				daRanking = t.rank;
				break;
			}
		}

		// Casos especiales
		if (acc == 0 && gs.misses == 0)
			daRanking = 'N/A';
		else if (acc <= 59.99 && !PlayState.startingSong)
			daRanking = 'F';

		return daRanking;
	}
}