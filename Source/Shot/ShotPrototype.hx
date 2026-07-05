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
		p.accel = accel;
		p.angularVelocity = angularVelocity;
		p.minSpeed = minSpeed;
		p.maxSpeed = maxSpeed;
		p.lifetime = lifetime;
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
			case "accel", "acceleration": accel;
			case "angularVelocity", "turn": angularVelocity;
			case "minSpeed": minSpeed;
			case "maxSpeed": maxSpeed;
			case "lifetime": lifetime;
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
			case "accel", "acceleration": accel = value;
			case "angularVelocity", "turn": angularVelocity = value;
			case "minSpeed": minSpeed = value;
			case "maxSpeed": maxSpeed = value;
			case "lifetime": lifetime = value;
			default: vars.set(name, value);
		}
	}
}
