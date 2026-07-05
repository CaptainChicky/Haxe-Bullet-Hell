package shot;

import shot.ShotCommand.IShotCommand;
import shot.FlowCommands;
import shot.PropertyCommands;
import shot.FireCommands;

/**
 * Helper passed to command parsers: resolves parameterized values and
 * compiles nested command lists (for Loop / Rep / Concurrent / Sub bodies).
 */
class CompileContext {
	private var params:Map<String, Dynamic>;

	public function new(params:Map<String, Dynamic>) {
		this.params = params;
	}

	public function num(value:Dynamic):Float {
		return Expression.resolve(value, params);
	}

	public function int(value:Dynamic):Int {
		return Std.int(Expression.resolve(value, params));
	}

	public function str(value:Dynamic, fallback:String):String {
		return (value != null && Std.isOfType(value, String)) ? cast value : fallback;
	}

	public function compileList(data:Array<Dynamic>):Array<IShotCommand> {
		return CommandRegistry.compileList(data, this);
	}
}

typedef CommandParser = (data:Dynamic, ctx:CompileContext) -> IShotCommand;

/**
 * Maps JSON "control" names to command parsers.
 *
 * This is the extension point that replaces the old ShootingAction enum:
 * adding a bullet behavior means writing an IShotCommand class and calling
 * register() - no enum, no interpreter switch, no PatternLoader edits.
 * All legacy control names are registered as aliases of the generic
 * property commands, so existing pattern JSON keeps working unchanged.
 */
class CommandRegistry {
	private static var parsers:Map<String, CommandParser> = null;

	public static function register(name:String, parser:CommandParser):Void {
		ensureDefaults();
		parsers.set(name, parser);
	}

	/** Compile one JSON action object; returns null (with a warning) for unknown controls. */
	public static function compile(data:Dynamic, ctx:CompileContext):IShotCommand {
		ensureDefaults();
		var control:String = data.control;
		var parser = parsers.get(control);
		if (parser == null) {
			trace("CommandRegistry: unknown control type: " + control);
			return null;
		}
		return parser(data, ctx);
	}

	public static function compileList(data:Array<Dynamic>, ctx:CompileContext):Array<IShotCommand> {
		var out:Array<IShotCommand> = [];
		if (data == null) return out;
		for (entry in data) {
			var cmd = compile(entry, ctx);
			if (cmd != null) out.push(cmd);
		}
		return out;
	}

	private static function ensureDefaults():Void {
		if (parsers != null) return;
		parsers = new Map();

		// --- Flow control ---------------------------------------------------
		parsers.set("Wait", (d, c) -> new WaitCommand(c.num(d.frames)));
		parsers.set("Loop", (d, c) -> new LoopCommand(c.compileList(d.actions)));
		parsers.set("Rep", (d, c) -> new RepCommand(c.int(d.count), c.compileList(d.actions)));
		parsers.set("Concurrent", (d, c) -> {
			var branches:Array<Array<IShotCommand>> = [];
			var raw:Array<Dynamic> = d.branches;
			if (raw != null) for (b in raw) branches.push(c.compileList(b));
			// {"share": true} -> branches mutate the parent's prototype directly
			// (parallel Tweens on one bullet) instead of independent clones.
			return new ConcurrentCommand(branches, d.share == true);
		});
		parsers.set("Sub", (d, c) -> new SubCommand(c.compileList(d.actions)));
		// {"control": "Scope", "actions": [...]} -> body mutates a discarded
		// clone; use for burst-configuration inside a bullet's own script so
		// the bullet's flight state (curving etc.) is not hijacked.
		parsers.set("Scope", (d, c) -> new ScopeCommand(c.compileList(d.actions)));
		parsers.set("Vanish", (d, c) -> new VanishCommand());

		// --- Firing -----------------------------------------------------------
		parsers.set("Fire", (d, c) -> new FireCommand(c.num(d.angle), c.num(d.speed)));
		parsers.set("Radial", (d, c) -> new RadialCommand(c.int(d.count), c.num(d.speed)));
		parsers.set("NWay", (d, c) -> new NWayCommand(c.int(d.count), c.num(d.angle), c.num(d.speed)));

		// --- Generic prototype properties (new-style) -------------------------
		// {"control": "Set",    "prop": "accel", "value": 0.1}
		// {"control": "Add",    "prop": "turn",  "delta": -0.5}
		// {"control": "Random", "prop": "speed", "min": 2, "max": 6}
		// {"control": "Copy",   "from": "direction", "to": "offsetAngle"}
		parsers.set("Set", (d, c) -> new SetPropCommand(c.str(d.prop, "direction"), c.num(d.value)));
		parsers.set("Add", (d, c) -> new AddPropCommand(c.str(d.prop, "direction"), c.num(d.delta)));
		parsers.set("Random", (d, c) -> new RandomPropCommand(c.str(d.prop, "direction"), c.num(d.min), c.num(d.max)));
		parsers.set("Copy", (d, c) -> new CopyPropCommand(c.str(d.from, "direction"), c.str(d.to, "direction")));
		// {"control": "Tween", "prop": "speed", "to": 6, "frames": 30}
		parsers.set("Tween", (d, c) -> new TweenCommand(c.str(d.prop, "direction"), c.num(d.to), c.int(d.frames)));

		// --- Aiming -----------------------------------------------------------
		parsers.set("AimAtPlayer", (d, c) -> new AimAtTargetCommand());

		// --- Legacy aliases (existing pattern JSON keeps working) --------------
		parsers.set("SetAngle", (d, c) -> new SetPropCommand("direction", c.num(d.value)));
		parsers.set("AddAngle", (d, c) -> new AddPropCommand("direction", c.num(d.delta)));
		parsers.set("SetSpeed", (d, c) -> new SetPropCommand("speed", c.num(d.value)));
		parsers.set("AddSpeed", (d, c) -> new AddPropCommand("speed", c.num(d.delta)));
		parsers.set("SetOffset", (d, c) -> new OffsetCommand(c.num(d.distance), c.num(d.angle), false));
		parsers.set("AddOffset", (d, c) -> new OffsetCommand(c.num(d.distanceDelta), c.num(d.angleDelta), true));
		parsers.set("CopyAngleToOffset", (d, c) -> new CopyPropCommand("direction", "offsetAngle"));
		parsers.set("CopyOffsetToAngle", (d, c) -> new CopyPropCommand("offsetAngle", "direction"));
		parsers.set("RandomSpeed", (d, c) -> new RandomPropCommand("speed", c.num(d.min), c.num(d.max)));
		parsers.set("RandomAngle", (d, c) -> new RandomPropCommand("direction", c.num(d.min), c.num(d.max)));
	}
}
