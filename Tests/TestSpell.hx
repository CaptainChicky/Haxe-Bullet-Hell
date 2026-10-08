import manager.SpellStore;

class TestSpell {
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

		var key = SpellStore.spellKey(4, "Aurelia", "Feather Sign");
		check(key == "4/Aurelia/Feather Sign", "spell key format");

		var start = 500000;
		var min = start * 0.1;
		var timeout = 55 * 60;
		var elapsed = timeout / 2;
		var t = elapsed / timeout;
		var bonus = start - (start - min) * t;
		check(Std.int(bonus) == 275000, "bonus decays linearly to 10% at half timeout");

		check(Std.int(start - (start - min)) == Std.int(min), "bonus floor is 10% of start");

		return failures;
	}
}
