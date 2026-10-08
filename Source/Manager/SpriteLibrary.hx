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
	@:optional var facing:String;
	@:optional var angleOffset:Float;
	/** Multiplier on the narrow-axis collision radius. */
	@:optional var hitScale:Float;
	/** Brief scale/alpha pop-in on spawn. */
	@:optional var spawnFx:Bool;
	/** Set only when the skin actually animates (2 or more cells). */
	@:optional var frames:Array<BitmapData>;
	@:optional var fps:Float;
	/** "loop", "once", or "pingpong". */
	@:optional var mode:String;
}

/**
 * One skin part as authored: an asset, an optional spritesheet cell, and
 * an optional horizontal animation strip. See SpriteFrames for the cell
 * geometry. Omitting `frames` (or asking for fewer than 2) keeps the
 * original single-bitmap path.
 */
typedef SpriteDef = {
	var source:String; // asset path, e.g. "assets/Enemy.png"
	@:optional var rect:Array<Float>; // [x, y, w, h] first cell, or the only cell when static
	@:optional var scale:Float; // uniform visual scale (collision radius follows)
	@:optional var frames:Int; // strip length; omit for a static bitmap
	@:optional var fps:Float; // animation frames per second; default 8
	@:optional var frameW:Int;
	@:optional var frameH:Int;
	@:optional var mode:String; // "loop" | "once" | "pingpong"
	@:optional var facing:String; // "spin" | "velocity" | "player" | "fixed"
	@:optional var angleOffset:Float;
	@:optional var hitScale:Float;
	@:optional var spawnFx:Bool;
}

/**
 * Data-driven enemy/bullet art. A spawn's `sprite` field names a skin from
 * the manifest (assets/sprites.json); each skin maps to an enemy sprite and
 * the bullet sprite its patterns fire. Adding art is a manifest edit, no code.
 *
 *   {"skins": {"drone": {"enemy": "assets/Drone.png",
 *                        "bullet": {"source": "assets/Sheet.png",
 *                                   "rect": [0, 0, 16, 16], "scale": 1.5,
 *                                   "frames": 4, "fps": 8, "mode": "loop"}}}}
 *
 * Conveniences:
 *  - a skin part can be a plain string (asset path) instead of an object
 *  - a `sprite` value ending in ".png" is a drop-in: used directly as the
 *    enemy art with the default bullet art, no manifest entry needed
 *  - "default" and "enemy2" are built in, so existing content needs nothing
 *  - a part with no `frames` resolves to one BitmapData, exactly as before
 */
class SpriteLibrary {
	public static inline final FACING_SPIN:String = "spin";
	public static inline final FACING_VELOCITY:String = "velocity";
	public static inline final FACING_PLAYER:String = "player";
	public static inline final FACING_FIXED:String = "fixed";

	private static inline final MANIFEST:String = "assets/sprites.json";

	private static var skins:Map<String, {enemy:SpriteDef, bullet:SpriteDef}> = null;
	private static var bitmapCache:Map<String, BitmapData> = new Map();
	private static var frameCache:Map<String, Array<BitmapData>> = new Map();
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

	/**
	 * Cut a horizontal strip out of `sheet` using SpriteFrames.layout.
	 * Public so the four-color rectangle test can drive it without an asset.
	 * The returned cells are independent copies; the sheet is not modified.
	 */
	public static function cutFrames(sheet:BitmapData, def:SpriteDef):Array<BitmapData> {
		var rects = SpriteFrames.layout(def.frames == null ? 0 : def.frames, sheet.width, sheet.height, def.rect, def.frameW, def.frameH);
		var out:Array<BitmapData> = [];
		for (rect in rects) {
			var cell = new BitmapData(rect.w, rect.h, true, 0);
			cell.copyPixels(sheet, new Rectangle(rect.x, rect.y, rect.w, rect.h), new Point(0, 0));
			out.push(cell);
		}
		return out;
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
		var scale = (def.scale != null && def.scale > 0) ? def.scale : 1.0;
		var requested = (def.frames != null) ? def.frames : 0;
		if (requested > 1) {
			var frames = frameCache.get(cacheKey);
			if (frames == null) {
				var sheet = Assets.getBitmapData(def.source);
				frames = cutFrames(sheet, def);
				frameCache.set(cacheKey, frames);
				if (frames.length != requested) {
					trace("SpriteLibrary: " + cacheKey + " asked for " + requested + " frames, cut " + frames.length
						+ " (sheet " + sheet.width + "x" + sheet.height + ")");
				}
			}
			if (frames.length > 1) {
				return withBulletBehavior({
					bitmapData: frames[0],
					scale: scale,
					frames: frames,
					fps: (def.fps != null) ? def.fps : SpriteFrames.DEFAULT_FPS,
					mode: canonicalMode(def.mode)
				}, def);
			}
		}

		// Static path: one bitmap, optionally cropped to `rect`. Unchanged
		// for any skin that does not ask for 2 or more frames.
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
		return withBulletBehavior({bitmapData: bmd, scale: scale}, def);
	}

	private static function withBulletBehavior(base:ResolvedSprite, def:SpriteDef):ResolvedSprite {
		base.facing = canonicalFacing(def.facing);
		base.angleOffset = (def.angleOffset != null) ? def.angleOffset : 0.0;
		base.hitScale = (def.hitScale != null && def.hitScale > 0) ? def.hitScale : 1.0;
		base.spawnFx = def.spawnFx == true;
		return base;
	}

	private static function canonicalFacing(facing:String):String {
		if (facing == null || facing == FACING_SPIN) return FACING_SPIN;
		if (facing == FACING_VELOCITY || facing == FACING_PLAYER || facing == FACING_FIXED) return facing;
		var key = "facing:" + facing;
		if (!warned.exists(key)) {
			warned.set(key, true);
			trace("SpriteLibrary: unknown bullet facing \"" + facing + "\", using spin");
		}
		return FACING_SPIN;
	}

	private static function canonicalMode(mode:String):String {
		if (mode == null || mode == SpriteFrames.MODE_LOOP) return SpriteFrames.MODE_LOOP;
		if (mode == SpriteFrames.MODE_ONCE || mode == SpriteFrames.MODE_PINGPONG) return mode;
		var key = "mode:" + mode;
		if (!warned.exists(key)) {
			warned.set(key, true);
			trace("SpriteLibrary: unknown animation mode \"" + mode + "\", using loop");
		}
		return SpriteFrames.MODE_LOOP;
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
		return {
			source: raw.source,
			rect: raw.rect,
			scale: raw.scale,
			frames: optInt(raw.frames),
			fps: optFloat(raw.fps),
			frameW: optInt(raw.frameW),
			frameH: optInt(raw.frameH),
			mode: (raw.mode is String) ? (raw.mode : String) : null,
			facing: (raw.facing is String) ? (raw.facing : String) : null,
			angleOffset: optFloat(raw.angleOffset),
			hitScale: optFloat(raw.hitScale),
			spawnFx: raw.spawnFx == true
		};
	}

	private static function optInt(v:Dynamic):Null<Int> {
		if (v == null) return null;
		return Std.int(v);
	}

	private static function optFloat(v:Dynamic):Null<Float> {
		if (v == null) return null;
		return (v : Float);
	}
}
