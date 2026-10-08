package manager;

import haxe.Json;
import openfl.Assets;

typedef CharacterManifest = {
	var characters:Array<CharacterDef>;
}

typedef CharacterDef = {
	var id:String;
	var name:String;
	var sheet:String;
	var frameW:Int;
	var frameH:Int;
	var idleFrames:Int;
	var leanFrames:Int;
	var fps:Float;
	@:optional var portraits:Dynamic;
	@:optional var select:String;
	var shotTypes:Array<String>;
	var speed:{normal:Float, focused:Float};
	var hitboxRadius:Float;
	var grazeRadius:Float;
	@:optional var description:String;
}

/**
 * Playable character manifest (Assets/characters.json). Falls back to a
 * built-in Aviator wrapping assets/Player.png when the file or sheet is absent.
 */
class CharacterLibrary {
	private static inline final MANIFEST:String = "assets/characters.json";
	private static inline final FALLBACK_SHEET:String = "assets/Player.png";

	private static var byId:Map<String, CharacterDef> = null;
	private static var order:Array<String> = null;
	private static var loaded:Bool = false;

	public static function ensureLoaded():Void {
		if (loaded) return;
		loaded = true;
		byId = new Map();
		order = [];

		if (Assets.exists(MANIFEST)) {
			try {
				var doc:CharacterManifest = Json.parse(Assets.getText(MANIFEST));
				if (doc.characters != null) {
					for (c in doc.characters) {
						register(c);
					}
				}
			} catch (e:Dynamic) {
				trace("CharacterLibrary: failed to parse " + MANIFEST + ": " + e);
			}
		}

		if (order.length == 0) {
			register(builtinAviator());
		}
	}

	private static function register(c:CharacterDef):Void {
		byId.set(c.id, c);
		if (order.indexOf(c.id) < 0) order.push(c.id);
	}

	private static function builtinAviator():CharacterDef {
		return {
			id: "aviator",
			name: "The Aviator",
			sheet: FALLBACK_SHEET,
			frameW: 32,
			frameH: 32,
			idleFrames: 1,
			leanFrames: 1,
			fps: 8,
			shotTypes: ["Spread", "Pierce", "Homing"],
			speed: {normal: 5.2, focused: 2.2},
			hitboxRadius: 3,
			grazeRadius: 24,
			description: "Default pilot."
		};
	}

	public static function ids():Array<String> {
		ensureLoaded();
		return order.copy();
	}

	public static function get(id:String):CharacterDef {
		ensureLoaded();
		var c = byId.get(id);
		if (c != null) return c;
		return byId.get(order[0]);
	}

	/** True when the character sheet asset exists and has animation strips. */
	public static function hasAnimatedSheet(c:CharacterDef):Bool {
		if (!Assets.exists(c.sheet)) return false;
		return c.idleFrames > 1 || c.leanFrames > 1;
	}

	/** Effective sheet path: character sheet or legacy Player.png. */
	public static function resolveSheet(c:CharacterDef):String {
		if (Assets.exists(c.sheet)) return c.sheet;
		if (Assets.exists(FALLBACK_SHEET)) return FALLBACK_SHEET;
		return c.sheet;
	}

	/**
	 * Portrait for dialogue: explicit path wins; else match speaker to
	 * character `name` or `id` and pick portraits[expression].
	 */
	public static function resolvePortrait(speaker:String, ?expression:String, ?explicit:String):Null<String> {
		if (explicit != null && explicit.length > 0) return explicit;
		if (expression == null || expression.length == 0) return null;

		ensureLoaded();
		for (id in order) {
			var c = byId.get(id);
			if (c == null) continue;
			if (!matchesSpeaker(speaker, c)) continue;
			if (c.portraits == null) return null;
			var path:Dynamic = Reflect.field(c.portraits, expression);
			if (path is String) return (path : String);
		}
		return null;
	}

	public static function matchesSpeaker(speaker:String, c:CharacterDef):Bool {
		return CharacterLogic.matchesSpeaker(speaker, c);
	}

	/** Vertical strip index: 0 idle, 1 lean left, 2 lean right. */
	public static function stripOriginY(c:CharacterDef, strip:Int):Int {
		return CharacterLogic.stripOriginY(c.frameH, strip);
	}
}
