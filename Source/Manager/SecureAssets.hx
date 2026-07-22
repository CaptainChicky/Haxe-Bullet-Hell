package manager;

import haxe.io.Bytes;
import openfl.Assets;

/**
 * Reads level/pattern JSON, preferring the sealed .dat form that release
 * builds package (see AssetSeal and tools/bh/crypt.js).
 *
 * Callers still ask for "assets/levels/level1.json"; the .json → .dat swap
 * happens here. Debug builds package the plaintext instead, so the game runs
 * straight from the repo without a seal step — see the assets tags in
 * project.xml.
 */
class SecureAssets {
	/**
	 * Load a JSON asset in whichever form is packaged. Returns null if neither
	 * is present, or if the sealed one fails its integrity check.
	 */
	public static function getText(path:String):String {
		var sealedPath = sealedName(path);

		if (Assets.exists(sealedPath)) {
			var bytes:Bytes = Assets.getBytes(sealedPath);
			var text = AssetSeal.open(bytes);
			if (text != null) return text;
			trace("Sealed asset failed integrity check: " + sealedPath);
			return null;
		}

		if (Assets.exists(path)) return Assets.getText(path);
		return null;
	}

	/** True if either form of the asset is available. */
	public static function exists(path:String):Bool {
		return Assets.exists(sealedName(path)) || Assets.exists(path);
	}

	private static function sealedName(path:String):String {
		return StringTools.endsWith(path, ".json") ? path.substr(0, path.length - 5) + ".dat" : path + ".dat";
	}
}
