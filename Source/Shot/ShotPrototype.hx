package shot;

/**
 * A mutable prototype describing the "next bullet to be fired".
 *
 * Script commands mutate this object (direction, speed, offset, acceleration, ...).
 * When a Fire-style command executes, the prototype is *cloned* into a concrete
 * bullet, so later script mutations never affect bullets already in flight.
 *
 * New bullet properties should be added here (plus in getProp/setProp) rather
 * than as new script-command variants: the generic Set/Add/Random/Copy commands
 * pick them up automatically, and unknown names transparently become custom
 * script variables stored in `vars`.
 */
class ShotPrototype {
	// --- Aiming / spawn placement -------------------------------------------
	/** Travel direction in degrees (0 = right, 90 = down). */
	public var direction:Float = 0;

	/** Initial speed in pixels per frame. */
	public var speed:Float = 5;

	/** Distance from the emitter origin at which the bullet spawns. */
	public var offsetDistance:Float = 0;

	/** Bearing (degrees) of the spawn offset relative to the emitter origin. */
	public var offsetAngle:Float = 0;

	/** Cartesian spawn offset from the emitter origin, applied IN ADDITION
	 *  to the polar offset above. Shaped by the Rotate/Scale transforms. */
	public var x:Float = 0;
	public var y:Float = 0;

	// --- In-flight behavior --------------------------------------------------
	/** Change in speed per frame after spawning (pixels/frame^2). */
	public var accel:Float = 0;

	/** Change in direction per frame after spawning (degrees/frame). Curving bullets. */
	public var angularVelocity:Float = 0;

	/** Speed is clamped to [minSpeed, maxSpeed] while accelerating. */
	public var minSpeed:Float = 0;
	public var maxSpeed:Float = 1e9;

	/** Frames the bullet lives before auto-despawn. <= 0 means unlimited. */
	public var lifetime:Float = 0;

	// --- Binding --------------------------------------------------------------
	public static inline final BIND_NONE:Int = 0;
	public static inline final BIND_POSITION:Int = 1;
	public static inline final BIND_FULL:Int = 2;

	/**
	 * How bullets fired from this prototype relate to their firer:
	 *   BIND_NONE (default)  - fully independent clone, historical behavior.
	 *   BIND_POSITION        - the bullet moves in its parent's frame of
	 *                          reference: parent translation carries it along
	 *                          while its own velocity still integrates on top.
	 *   BIND_FULL            - position binding PLUS flight state (direction,
	 *                          speed, accel, turn, clamps) re-derived every
	 *                          frame from the parent script's live prototype.
	 * Set via {"control": "Bind", "mode": "position"|"full"|"none"}.
	 */
	public var bindMode:Int = BIND_NONE;

	/**
	 * Runtime wiring: the parent script's live (root) prototype, attached by
	 * ScriptRunner.fireClone to the fired clone when bindMode != BIND_NONE.
	 * Never copied by clone() - it identifies a specific live parent.
	 */
	public var bindSource:ShotPrototype = null;

	// --- Extensibility hooks -------------------------------------------------
	/** Free-form script variables. Unknown property names in Set/Add/etc. land here. */
	public var vars:Map<String, Float>;

	/**
	 * Optional script the spawned bullet runs itself after being fired
	 * (compiled command list assigned by the "Sub" control).
	 * The bullet becomes its own emitter, enabling Touhou-style nested patterns.
	 */
	public var subCommands:Array<ShotCommand.IShotCommand> = null;

	public function new() {
		vars = new Map();
	}

	/** Deep-enough copy: value fields are copied, vars map is duplicated,
	 *  subCommands is shared (compiled commands are immutable). */
	public function clone():ShotPrototype {
		var p = new ShotPrototype();
		p.direction = direction;
		p.speed = speed;
		p.offsetDistance = offsetDistance;
		p.offsetAngle = offsetAngle;
		p.x = x;
		p.y = y;
		p.accel = accel;
		p.angularVelocity = angularVelocity;
		p.minSpeed = minSpeed;
		p.maxSpeed = maxSpeed;
		p.lifetime = lifetime;
		p.bindMode = bindMode; // config travels; bindSource (runtime wiring) does not
		p.subCommands = subCommands;
		for (k in vars.keys()) p.vars.set(k, vars.get(k));
		return p;
	}

	/** Generic property read used by script commands. Unknown names read from `vars` (default 0). */
	public function getProp(name:String):Float {
		return switch (name) {
			case "direction", "angle": direction;
			case "speed": speed;
			case "offsetDistance": offsetDistance;
			case "offsetAngle": offsetAngle;
			case "x": x;
			case "y": y;
			case "accel", "acceleration": accel;
			case "angularVelocity", "turn": angularVelocity;
			case "minSpeed": minSpeed;
			case "maxSpeed": maxSpeed;
			case "lifetime": lifetime;
			case "bindMode": bindMode;
			default: vars.exists(name) ? vars.get(name) : 0;
		}
	}

	/** Generic property write used by script commands. Unknown names write into `vars`. */
	public function setProp(name:String, value:Float):Void {
		switch (name) {
			case "direction", "angle": direction = value;
			case "speed": speed = value;
			case "offsetDistance": offsetDistance = value;
			case "offsetAngle": offsetAngle = value;
			case "x": x = value;
			case "y": y = value;
			case "accel", "acceleration": accel = value;
			case "angularVelocity", "turn": angularVelocity = value;
			case "minSpeed": minSpeed = value;
			case "maxSpeed": maxSpeed = value;
			case "lifetime": lifetime = value;
			case "bindMode": bindMode = Std.int(value);
			default: vars.set(name, value);
		}
	}
}
