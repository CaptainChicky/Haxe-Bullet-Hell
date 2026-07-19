package manager;

import openfl.Assets;
import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import haxe.Json;

/** A resolved skin part, ready to render. */
typedef ResolvedSprite = {
	var bitmapData:BitmapData;
	var scale:Float;
}

/** One skin part as authored: an asset plus optional spritesheet sub-rect. */
typedef SpriteDef = {
	var source:String; // asset path, e.g. "assets/Enemy.png"
	@:optional var rect:Array<Float>; // [x, y, w, h] sub-rectangle (spritesheet cell)
	@:optional var scale:Float; // uniform visual scale (collision radius follows)
}

/**
 * Data-driven enemy/bullet art. A spawn's `sprite` field names a skin from
 * the manifest (assets/sprites.json); each skin maps to an enemy sprite and
 * the bullet sprite its patterns fire. Adding art is a manifest edit, no code.
 *
 *   {"skins": {"drone": {"enemy": "assets/Drone.png",
 *                        "bullet": {"source": "assets/Sheet.png",
 *                                   "rect": [0, 0, 16, 16], "scale": 1.5}}}}
 *
 * Conveniences:
 *  - a skin part can be a plain string (asset path) instead of an object
 *  - a `sprite` value ending in ".png" is a drop-in: used directly as the
 *    enemy art with the default bullet art, no manifest entry needed
 *  - "default" and "enemy2" are built in, so existing content needs nothing
 */
class SpriteLibrary {
	private static inline final MANIFEST:String = "assets/sprites.json";

	private static var skins:Map<String, {enemy:SpriteDef, bullet:SpriteDef}> = null;
	private static var bitmapCache:Map<String, BitmapData> = new Map();
	private static var warned:Map<String, Bool> = new Map();

	/** Resolve the enemy art for a skin name (null -> "default"). */
	public static function enemySprite(?skin:String):ResolvedSprite {
		ensureLoaded();
		if (skin != null && StringTools.endsWith(skin, ".png")) {
			return resolve("enemy:" + skin, {source: skin});
		}
		return resolve("enemy:" + skinKey(skin), lookup(skin).enemy);
	}

	/** Resolve the bullet art for a skin name (null -> "default"). */
	public static function bulletSprite(?skin:String):ResolvedSprite {
		ensureLoaded();
		// Drop-in .png skins keep the default bullet art
		var key = (skin != null && StringTools.endsWith(skin, ".png")) ? null : skin;
		return resolve("bullet:" + skinKey(key), lookup(key).bullet);
	}

	private static function skinKey(?skin:String):String {
		return (skin == null) ? "default" : skin;
	}

	private static function lookup(?skin:String):{enemy:SpriteDef, bullet:SpriteDef} {
		var key = skinKey(skin);
		var found = skins.get(key);
		if (found == null) {
			if (!warned.exists(key)) {
				warned.set(key, true);
				trace("SpriteLibrary: unknown skin \"" + key + "\", using default");
			}
			found = skins.get("default");
		}
		return found;
	}

	private static function resolve(cacheKey:String, def:SpriteDef):ResolvedSprite {
		var bmd = bitmapCache.get(cacheKey);
		if (bmd == null) {
			bmd = Assets.getBitmapData(def.source);
			if (def.rect != null && def.rect.length == 4) {
				var w = Std.int(def.rect[2]);
				var h = Std.int(def.rect[3]);
				var cell = new BitmapData(w, h, true, 0);
				cell.copyPixels(bmd, new Rectangle(def.rect[0], def.rect[1], w, h), new Point(0, 0));
				bmd = cell;
			}
			bitmapCache.set(cacheKey, bmd);
		}
		return {bitmapData: bmd, scale: (def.scale != null && def.scale > 0) ? def.scale : 1.0};
	}

	private static function ensureLoaded():Void {
		if (skins != null) {
			return;
		}
		skins = new Map();

		// Built-in skins: existing content works without any manifest
		skins.set("default", {enemy: {source: "assets/Enemy.png"}, bullet: {source: "assets/BulletEnemy.png"}});
		skins.set("enemy2", {enemy: {source: "assets/Enemy(second).png"}, bullet: {source: "assets/BulletEnemy(second).png"}});

		if (!Assets.exists(MANIFEST)) {
			return;
		}
		try {
			var doc:Dynamic = Json.parse(Assets.getText(MANIFEST));
			var manifest:Dynamic = doc.skins;
			if (manifest == null) {
				return;
			}
			for (name in Reflect.fields(manifest)) {
				var raw:Dynamic = Reflect.field(manifest, name);
				var base = skins.exists(name) ? skins.get(name) : skins.get("default");
				skins.set(name, {
					enemy: normalize(raw.enemy, base.enemy),
					bullet: normalize(raw.bullet, base.bullet)
				});
			}
		} catch (e:Dynamic) {
			trace("SpriteLibrary: failed to parse " + MANIFEST + ": " + e);
		}
	}

	/** A skin part may be a plain path string, a SpriteDef object, or absent. */
	private static function normalize(raw:Dynamic, fallback:SpriteDef):SpriteDef {
		if (raw == null) {
			return fallback;
		}
		if (raw is String) {
			return {source: (raw : String)};
		}
		return {source: raw.source, rect: raw.rect, scale: raw.scale};
	}
}
