package shot;

import shot.ShotCommand.IShotCommand;
import shot.FlowCommands;
import shot.PropertyCommands;
import shot.FireCommands;
import shot.Expression.NumValue;

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

	/** Compile a numeric value lazily: deterministic expressions fold to a
	 *  constant; volatile ones (random.*) re-evaluate per command execution. */
	public function val(value:Dynamic):NumValue {
		return Expression.compile(value, params);
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
 * Only canonical control names are registered; the legacy aliases
 * (SetAngle, SetSpeed, RandomAngle, ...) were removed after all content
 * was migrated to the generic Set/Add/Random/Copy notation.
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
		parsers.set("Wait", (d, c) -> new WaitCommand(c.val(d.frames)));
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
		parsers.set("Fire", (d, c) -> new FireCommand(c.val(d.angle), c.val(d.speed)));
		parsers.set("Radial", (d, c) -> new RadialCommand(c.int(d.count), c.val(d.speed)));
		parsers.set("NWay", (d, c) -> new NWayCommand(c.int(d.count), c.val(d.angle), c.val(d.speed)));
		// {"control": "Line", "count": 5, "prop": "speed", "from": 1, "to": 5}
		// -> 5 bullets stepping the property linearly; prototype restored after.
		parsers.set("Line", (d, c) -> new LineCommand(c.int(d.count), c.str(d.prop, "speed"), c.val(d.from), c.val(d.to)));
		// {"control": "Dup", "count": 5, "props": {
		//     "direction": {"from": -30, "to": 30},   // interpolated across copies
		//     "speed":     {"min": 2, "max": 6},      // random per copy
		//     "lifetime":  {"step": 10}}}             // current + i*10
		parsers.set("Dup", (d, c) -> {
			var specs:Array<DupSpec> = [];
			var props:Dynamic = d.props;
			if (props != null) for (name in Reflect.fields(props)) {
				var spec:Dynamic = Reflect.field(props, name);
				if (spec.from != null || spec.to != null)
					specs.push({prop: name, kind: DRange, a: c.val(spec.from), b: c.val(spec.to)});
				else if (spec.min != null || spec.max != null)
					specs.push({prop: name, kind: DRandom, a: c.val(spec.min), b: c.val(spec.max)});
				else if (spec.step != null)
					specs.push({prop: name, kind: DStep, a: c.val(spec.step), b: NumValue.of(0)});
				else
					trace("Dup: property '" + name + "' needs from/to, min/max, or step");
			}
			return new DupCommand(c.int(d.count), specs);
		});

		// --- Generic prototype properties (new-style) -------------------------
		// {"control": "Set",    "prop": "accel", "value": 0.1}
		// {"control": "Add",    "prop": "turn",  "delta": -0.5}
		// {"control": "Random", "prop": "speed", "min": 2, "max": 6}
		// {"control": "Copy",   "from": "direction", "to": "offsetAngle"}
		parsers.set("Set", (d, c) -> new SetPropCommand(c.str(d.prop, "direction"), c.val(d.value)));
		parsers.set("Add", (d, c) -> new AddPropCommand(c.str(d.prop, "direction"), c.val(d.delta)));
		parsers.set("Random", (d, c) -> new RandomPropCommand(c.str(d.prop, "direction"), c.val(d.min), c.val(d.max)));
		// Copy supports optional scaling: {"control":"Copy", "from":"speed", "to":"turn", "scale":0.5}
		parsers.set("Copy", (d, c) -> new CopyPropCommand(c.str(d.from, "direction"), c.str(d.to, "direction"),
			c.val(d.scale != null ? d.scale : 1)));
		// {"control": "Tween", "prop": "speed", "to": 6, "frames": 30}
		parsers.set("Tween", (d, c) -> new TweenCommand(c.str(d.prop, "direction"), c.val(d.to), c.int(d.frames), d.relative == true));

		// --- Spawn placement transforms ---------------------------------------
		// {"control": "SetOffset", "distance": 40, "angle": 90}  polar spawn offset
		// {"control": "AddOffset", "distanceDelta": 5, "angleDelta": 15}
		parsers.set("SetOffset", (d, c) -> new OffsetCommand(c.val(d.distance), c.val(d.angle), false));
		parsers.set("AddOffset", (d, c) -> new OffsetCommand(c.val(d.distanceDelta), c.val(d.angleDelta), true));
		// {"control": "Rotate", "degrees": 15}                   rotates (x,y) + offsetAngle
		// {"control": "Rotate", "degrees": 15, "withDirection": true}   ...and direction
		// {"control": "Scale", "factor": 2}                      scales x, y, offsetDistance
		// {"control": "Scale", "x": 2, "y": 0.5}                 per-axis Cartesian only
		parsers.set("Rotate", (d, c) -> new RotateCommand(c.val(d.degrees), d.withDirection == true));
		parsers.set("Scale", (d, c) -> new ScaleCommand(c.val(d.factor != null ? d.factor : 1),
			d.x != null ? c.val(d.x) : null, d.y != null ? c.val(d.y) : null));

		// --- Binding ------------------------------------------------------------
		// {"control": "Bind", "mode": "position"} -> bullets fired from now on
		// move in their parent's frame of reference; "full" also re-derives
		// flight state from the parent's live prototype each frame.
		parsers.set("Bind", (d, c) -> {
			var mode = switch (c.str(d.mode, "position")) {
				case "full": ShotPrototype.BIND_FULL;
				case "offset": ShotPrototype.BIND_OFFSET;
				case "none": ShotPrototype.BIND_NONE;
				default: ShotPrototype.BIND_POSITION;
			};
			return new SetPropCommand("bindMode", NumValue.of(mode));
		});

		// --- Aiming -----------------------------------------------------------
		parsers.set("AimAtPlayer", (d, c) -> new AimAtTargetCommand());

	}
}
