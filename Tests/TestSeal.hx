import haxe.Json;
import haxe.io.Bytes;
import manager.AssetSeal;

/**
 * Cross-checks the Haxe reader (manager.AssetSeal) against the Node writer
 * (tools/bh/crypt.js) using the real sealed assets. If these two ever drift,
 * a release build silently loads no content at all — so this runs over every
 * level and pattern, not a sample.
 *
 * Run from the repo root:  haxe Tests/seal.hxml
 */
class TestSeal {
	static var failures:Int = 0;
	static var checked:Int = 0;

	static function main() {
		if (!sys.FileSystem.exists("Assets/levels")) {
			Sys.println("run from the repo root");
			Sys.exit(1);
		}

		for (dir in ["Assets/levels", "Assets/patterns"]) {
			for (name in sys.FileSystem.readDirectory(dir)) {
				if (!StringTools.endsWith(name, ".dat")) continue;
				checkFile(dir + "/" + name, dir + "/" + name.substr(0, name.length - 4) + ".json");
			}
		}

		checkTamperDetection();

		Sys.println('\n$checked file(s) checked, $failures failure(s)');
		Sys.exit(failures > 0 ? 1 : 0);
	}

	/** A sealed file must reproduce its source JSON byte for byte. */
	static function checkFile(sealedPath:String, jsonPath:String):Void {
		checked++;

		if (!sys.FileSystem.exists(jsonPath)) {
			fail(sealedPath + " — orphaned, no matching .json");
			return;
		}

		var opened = AssetSeal.open(Bytes.ofData(sys.io.File.getBytes(sealedPath).getData()));
		if (opened == null) {
			fail(sealedPath + " — AssetSeal.open() returned null");
			return;
		}

		var expected = sys.io.File.getContent(jsonPath);
		if (opened != expected) {
			fail(sealedPath + " — decoded text differs from " + jsonPath);
			return;
		}

		// The whole point is that the game can parse it afterwards.
		try {
			Json.parse(opened);
		} catch (e:Dynamic) {
			fail(sealedPath + " — decoded text is not valid JSON: " + e);
		}
	}

	/** A flipped byte anywhere must be rejected, not silently mis-parsed. */
	static function checkTamperDetection():Void {
		var path = "Assets/levels/level1.dat";
		if (!sys.FileSystem.exists(path)) return;

		var original = sys.io.File.getBytes(path);

		// One in the body, one in the tag, one in the magic.
		for (offset in [0, Std.int(original.length / 2), original.length - 1]) {
			checked++;
			var tampered = original.sub(0, original.length);
			tampered.set(offset, tampered.get(offset) ^ 0xFF);
			if (AssetSeal.open(tampered) != null) {
				fail('tampered byte at offset $offset was accepted');
			}
		}

		checked++;
		if (AssetSeal.open(Bytes.ofString("BHD1 short")) != null) fail("truncated container was accepted");
	}

	static function fail(message:String):Void {
		Sys.println("  FAIL  " + message);
		failures++;
	}
}
