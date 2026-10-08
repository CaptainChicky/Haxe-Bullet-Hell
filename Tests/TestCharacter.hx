import manager.BgmLogic;
import manager.BgmLogic.BgmTrackRef;
import manager.CharacterLogic;
import manager.CharacterLogic.CharacterSpeaker;

class TestCharacter {
	public static function run():Int {
		var failures = 0;
		function check(cond:Bool, msg:String):Void {
			if (!cond) {
				failures++;
				Sys.println("FAIL: " + msg);
			} else {
				Sys.println("ok:   " + msg);
			}
		}

		var aviator:CharacterSpeaker = {id: "aviator", name: "The Aviator", frameH: 64};
		check(CharacterLogic.matchesSpeaker("Aviator", aviator), "speaker matches short name");
		check(CharacterLogic.matchesSpeaker("The Aviator", aviator), "speaker matches full name");
		check(CharacterLogic.stripOriginY(64, 2) == 128, "lean-right strip y offset");

		var catalog:Array<BgmTrackRef> = [
			{id: "st01", stage: 1},
			{id: "st01_boss", stage: 1, boss: true}
		];
		var stage = BgmLogic.findTrack(1, false, catalog);
		var boss = BgmLogic.findTrack(1, true, catalog);
		check(stage != null && stage.id == "st01", "bgm: stage track");
		check(boss != null && boss.id == "st01_boss", "bgm: boss track");

		return failures;
	}
}
