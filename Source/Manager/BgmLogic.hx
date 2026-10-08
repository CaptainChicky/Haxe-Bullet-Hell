package manager;

typedef BgmTrackRef = {
	var id:String;
	@:optional var stage:Int;
	@:optional var boss:Bool;
}

class BgmLogic {
	public static function findTrack(stageNumber:Int, boss:Bool, catalog:Array<BgmTrackRef>):Null<BgmTrackRef> {
		var fallback:Null<BgmTrackRef> = null;
		for (t in catalog) {
			if (t.stage != stageNumber) continue;
			var isBoss = t.boss == true;
			if (isBoss == boss) return t;
			if (!isBoss && !boss) fallback = t;
		}
		return fallback;
	}
}
