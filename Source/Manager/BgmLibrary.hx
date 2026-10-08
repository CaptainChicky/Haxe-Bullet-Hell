package manager;

import haxe.Json;
import openfl.Assets;

typedef BgmManifest = {
	var tracks:Array<BgmTrackData>;
}

typedef BgmTrackData = {
	var id:String;
	@:optional var file:String;
	@:optional var intro:String;
	var title:String;
	@:optional var composer:String;
	@:optional var comment:String;
	/** Loop restart point in seconds (single-file or loop segment after intro). */
	@:optional var loopStart:Float;
	@:optional var loopEnd:Float;
	@:optional var stage:Int;
	@:optional var boss:Bool;
}

/**
 * Reads Assets/bgm/bgm.json. Track lookup is pure logic (tested under --interp).
 */
class BgmLibrary {
	private static inline final MANIFEST:String = "assets/bgm/bgm.json";

	private static var tracks:Array<BgmTrackData> = null;
	private static var loaded:Bool = false;

	public static function ensureLoaded():Void {
		if (loaded) return;
		loaded = true;
		tracks = [];
		if (!Assets.exists(MANIFEST)) return;
		try {
			var doc:BgmManifest = Json.parse(Assets.getText(MANIFEST));
			if (doc.tracks != null) tracks = doc.tracks;
		} catch (e:Dynamic) {
			trace("BgmLibrary: failed to parse " + MANIFEST + ": " + e);
		}
	}

	public static function allTracks():Array<BgmTrackData> {
		ensureLoaded();
		return tracks;
	}

	/** Stage BGM (boss flag false or absent). */
	public static function trackForStage(stageNumber:Int):Null<BgmTrackData> {
		return findTrack(stageNumber, false);
	}

	public static function trackForBoss(stageNumber:Int):Null<BgmTrackData> {
		return findTrack(stageNumber, true);
	}

	public static function trackById(id:String):Null<BgmTrackData> {
		ensureLoaded();
		for (t in tracks) {
			if (t.id == id) return t;
		}
		return null;
	}

	/** @:pure logic for tests — does not touch Assets. */
	public static function findTrack(stageNumber:Int, boss:Bool, ?catalog:Array<BgmTrackData>):Null<BgmTrackData> {
		var list = catalog != null ? catalog : allTracks();
		return cast BgmLogic.findTrack(stageNumber, boss, cast list);
	}

	/** Path to play after optional intro: `file`, or null if only synth is possible. */
	public static function mainLoopPath(track:BgmTrackData):Null<String> {
		if (track.file != null && track.file.length > 0) return track.file;
		return null;
	}

	public static function introPath(track:BgmTrackData):Null<String> {
		if (track.intro != null && track.intro.length > 0) return track.intro;
		return null;
	}

	public static function assetReady(path:String):Bool {
		return path != null && Assets.exists(path);
	}
}
