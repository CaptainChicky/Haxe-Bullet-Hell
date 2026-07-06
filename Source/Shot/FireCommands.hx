package shot;

import shot.ShotCommand.IShotCommand;
import shot.Expression.NumValue;

/**
 * Fires one bullet by cloning the prototype.
 *
 * Legacy JSON compatibility: a literal 0 for angle/speed means "use the
 * prototype's current value", matching the old Fire(0, 0) convention.
 */
class FireCommand implements IShotCommand {
	private var angle:NumValue;
	private var speed:NumValue;

	public function new(angle:NumValue, speed:NumValue) {
		this.angle = angle;
		this.speed = speed;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		var a = angle.get();
		var s = speed.get();
		var dir:Null<Float> = (a == 0) ? null : a;
		var spd:Null<Float> = (s == 0) ? null : s;
		runner.fire(ctx, dir, spd);
	}
}

/** Fires `count` bullets in a full circle, starting from the prototype's direction. */
class RadialCommand implements IShotCommand {
	private var count:Int;
	private var speed:NumValue;

	public function new(count:Int, speed:NumValue) {
		this.count = count;
		this.speed = speed;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (count <= 0) return;
		var base = ctx.prototype.direction;
		var s = speed.get();
		var spd:Null<Float> = (s == 0) ? null : s;
		var step = 360.0 / count;
		for (i in 0...count) {
			runner.fire(ctx, base + i * step, spd);
		}
	}
}

/** Fires `count` bullets spread evenly across an arc centered on the prototype's direction. */
class NWayCommand implements IShotCommand {
	private var count:Int;
	private var arc:NumValue;
	private var speed:NumValue;

	public function new(count:Int, arc:NumValue, speed:NumValue) {
		this.count = count;
		this.arc = arc;
		this.speed = speed;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (count <= 0) return;
		var base = ctx.prototype.direction;
		var s = speed.get();
		var spd:Null<Float> = (s == 0) ? null : s;

		if (count == 1) {
			runner.fire(ctx, base, spd);
			return;
		}

		var a = arc.get();
		var start = base - a / 2;
		var step = a / (count - 1);
		for (i in 0...count) {
			runner.fire(ctx, start + i * step, spd);
		}
	}
}

/**
 * Fires `count` bullets stepping ONE property linearly from `from` to `to`
 * (inclusive) across the shots - e.g. increasing speed down a line of
 * bullets so they string out along the travel direction. The prototype's
 * value of the property is restored afterwards. from/to are evaluated once
 * per execution (so random.between endpoints give a fresh line per volley).
 */
class LineCommand implements IShotCommand {
	private var count:Int;
	private var prop:String;
	private var from:NumValue;
	private var to:NumValue;

	public function new(count:Int, prop:String, from:NumValue, to:NumValue) {
		this.count = count;
		this.prop = prop;
		this.from = from;
		this.to = to;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (count <= 0) return;
		var p = ctx.prototype;
		var saved = p.getProp(prop);
		var a = from.get();
		var b = to.get();
		for (i in 0...count) {
			var t = (count == 1) ? 0.0 : i / (count - 1);
			p.setProp(prop, a + (b - a) * t);
			runner.fire(ctx);
		}
		p.setProp(prop, saved);
	}
}

/** How one Dup property spec varies across copies. */
enum DupKind {
	/** Linear interpolation from a to b across the copies (inclusive). */
	DRange;
	/** Uniform random in [a, b) rolled independently per copy. */
	DRandom;
	/** prototype value + i * a for copy index i. */
	DStep;
}

typedef DupSpec = {
	var prop:String;
	var kind:DupKind;
	var a:NumValue;
	var b:NumValue; // unused for DStep
}

/**
 * Spawns `count` copies of the prototype where each copy's properties come
 * from a declarative per-copy spread:
 *
 *   {"control": "Dup", "count": 5, "props": {
 *       "direction": {"from": -30, "to": 30},   // interpolated across copies
 *       "speed":     {"min": 2, "max": 6},      // random per copy
 *       "lifetime":  {"step": 10}               // current + i*10
 *   }}
 *
 * Each copy is an independent clone (spread offsetAngle/x/y specs therefore
 * move the SPAWN POSITION per copy, not just flight values). The script's
 * prototype is never touched. Range endpoints are evaluated once per Dup
 * execution; DRandom rolls per copy.
 */
class DupCommand implements IShotCommand {
	private var count:Int;
	private var specs:Array<DupSpec>;

	public function new(count:Int, specs:Array<DupSpec>) {
		this.count = count;
		this.specs = specs;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (count <= 0) return;
		// Evaluate range endpoints once per execution.
		var lo:Array<Float> = [for (s in specs) s.a.get()];
		var hi:Array<Float> = [for (s in specs) (s.kind == DStep) ? 0 : s.b.get()];

		for (i in 0...count) {
			var copy = ctx.prototype.clone();
			for (j in 0...specs.length) {
				var s = specs[j];
				var v:Float = switch (s.kind) {
					case DRange:
						var t = (count == 1) ? 0.0 : i / (count - 1);
						lo[j] + (hi[j] - lo[j]) * t;
					case DRandom:
						lo[j] + Math.random() * (hi[j] - lo[j]);
					case DStep:
						ctx.prototype.getProp(s.prop) + lo[j] * i;
				}
				copy.setProp(s.prop, v);
			}
			runner.fireClone(copy);
		}
	}
}
