package manager;

/**
 * Per-spell capture history (seen / captured counts), keyed by
 * stage/bossName/phaseName. Persisted to spells.json in app storage
 * (same location as DisplaySettings).
 */
class SpellStore {
	private static var records:Map<String, SpellRecord> = null;
	private static var loaded:Bool = false;

	public static function spellKey(stage:Int, bossName:String, phaseName:String):String {
		return stage + "/" + bossName + "/" + phaseName;
	}

	public static function recordSeen(stage:Int, bossName:String, phaseName:String):Void {
		ensureLoaded();
		var key = spellKey(stage, bossName, phaseName);
		var rec = records.get(key);
		if (rec == null) {
			rec = {seen: 0, captured: 0};
			records.set(key, rec);
		}
		rec.seen++;
		save();
	}

	public static function recordCapture(stage:Int, bossName:String, phaseName:String):Void {
		ensureLoaded();
		var key = spellKey(stage, bossName, phaseName);
		var rec = records.get(key);
		if (rec == null) {
			rec = {seen: 1, captured: 0};
			records.set(key, rec);
		}
		rec.captured++;
		save();
	}

	public static function getRecord(stage:Int, bossName:String, phaseName:String):SpellRecord {
		ensureLoaded();
		var rec = records.get(spellKey(stage, bossName, phaseName));
		return rec != null ? rec : {seen: 0, captured: 0};
	}

	private static function ensureLoaded():Void {
		if (!loaded) {
			load();
			loaded = true;
		}
	}

	#if sys
	private static function storePath():String {
		return appStorageDir() + "spells.json";
	}

	private static function appStorageDir():String {
		#if lime
		return lime.system.System.applicationStorageDirectory;
		#else
		return "./";
		#end
	}
	#end

	public static function load():Void {
		records = new Map<String, SpellRecord>();
		#if sys
		try {
			var path = storePath();
			if (!sys.FileSystem.exists(path)) {
				return;
			}
			var data:Dynamic = haxe.Json.parse(sys.io.File.getContent(path));
			if (data == null || !Reflect.hasField(data, "spells")) {
				return;
			}
			var spells:Dynamic = Reflect.field(data, "spells");
			for (key in Reflect.fields(spells)) {
				var entry:Dynamic = Reflect.field(spells, key);
				records.set(key, {
					seen: Reflect.hasField(entry, "seen") ? Std.int(Reflect.field(entry, "seen")) : 0,
					captured: Reflect.hasField(entry, "captured") ? Std.int(Reflect.field(entry, "captured")) : 0,
				});
			}
		} catch (e:Dynamic) {
			trace("SpellStore: could not load (" + e + ")");
		}
		#end
	}

	public static function save():Void {
		#if sys
		try {
			var dir = appStorageDir();
			if (dir != null && dir != "" && !sys.FileSystem.exists(dir)) {
				sys.FileSystem.createDirectory(dir);
			}
			var spells:Dynamic = {};
			for (key in records.keys()) {
				var rec = records.get(key);
				Reflect.setField(spells, key, {seen: rec.seen, captured: rec.captured});
			}
			sys.io.File.saveContent(storePath(), haxe.Json.stringify({spells: spells}));
		} catch (e:Dynamic) {
			trace("SpellStore: could not save (" + e + ")");
		}
		#end
	}
}

typedef SpellRecord = {
	var seen:Int;
	var captured:Int;
}
