package shot;

import shot.ShotCommand.IShotCommand;
import shot.Expression.NumValue;

/**
 * Generic prototype-property commands.
 *
 * These are parameterized on a property *name* resolved through
 * ShotPrototype.getProp/setProp, so adding a new bullet property (or using a
 * custom script variable) requires no new command classes and no parser
 * changes: {"control": "Set", "prop": "accel", "value": -0.05} just works.
 *
 * Numeric parameters are NumValues: deterministic expressions are folded to
 * constants at compile time, while volatile ones (containing random.*)
 * re-roll on every execution.
 */

/** prototype[prop] = value */
class SetPropCommand implements IShotCommand {
	private var prop:String;
	private var value:NumValue;

	public function new(prop:String, value:NumValue) {
		this.prop = prop;
		this.value = value;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.prototype.setProp(prop, value.get());
	}
}

/** prototype[prop] += delta */
class AddPropCommand implements IShotCommand {
	private var prop:String;
	private var delta:NumValue;

	public function new(prop:String, delta:NumValue) {
		this.prop = prop;
		this.delta = delta;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.prototype.setProp(prop, ctx.prototype.getProp(prop) + delta.get());
	}
}

/** prototype[prop] = uniform random in [min, max) */
class RandomPropCommand implements IShotCommand {
	private var prop:String;
	private var min:NumValue;
	private var max:NumValue;

	public function new(prop:String, min:NumValue, max:NumValue) {
		this.prop = prop;
		this.min = min;
		this.max = max;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		var lo = min.get();
		var hi = max.get();
		ctx.prototype.setProp(prop, lo + Math.random() * (hi - lo));
	}
}

/** prototype[dst] = prototype[src] * scale (scale defaults to 1). */
class CopyPropCommand implements IShotCommand {
	private var src:String;
	private var dst:String;
	private var scale:NumValue;

	public function new(src:String, dst:String, ?scale:NumValue) {
		this.src = src;
		this.dst = dst;
		this.scale = (scale != null) ? scale : NumValue.of(1);
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.prototype.setProp(dst, ctx.prototype.getProp(src) * scale.get());
	}
}

/** Convenience: set/add spawn offset distance and bearing in one step. */
class OffsetCommand implements IShotCommand {
	private var distance:NumValue;
	private var angle:NumValue;
	private var relative:Bool;

	public function new(distance:NumValue, angle:NumValue, relative:Bool) {
		this.distance = distance;
		this.angle = angle;
		this.relative = relative;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		var p = ctx.prototype;
		if (relative) {
			p.offsetDistance += distance.get();
			p.offsetAngle += angle.get();
		} else {
			p.offsetDistance = distance.get();
			p.offsetAngle = angle.get();
		}
	}
}

/**
 * Rotates the spawn placement by `degrees`: the Cartesian (x, y) offset is
 * rotated about the emitter origin, and the polar offsetAngle advances by
 * the same amount (both placement systems stay in agreement). With
 * withDirection = true the travel direction rotates too - use that to spin
 * an entire pattern, not just where its bullets appear.
 */
class RotateCommand implements IShotCommand {
	private var degrees:NumValue;
	private var withDirection:Bool;

	public function new(degrees:NumValue, withDirection:Bool) {
		this.degrees = degrees;
		this.withDirection = withDirection;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		var p = ctx.prototype;
		var d = degrees.get();
		var rad = d * Math.PI / 180;
		var cos = Math.cos(rad);
		var sin = Math.sin(rad);
		var nx = p.x * cos - p.y * sin;
		var ny = p.x * sin + p.y * cos;
		p.x = nx;
		p.y = ny;
		p.offsetAngle += d;
		if (withDirection) p.direction += d;
	}
}

/**
 * Scales the spawn placement: `factor` multiplies x, y, and offsetDistance
 * uniformly; optional per-axis `x`/`y` factors override `factor` for the
 * Cartesian offset only (offsetDistance is a radius and cannot scale
 * non-uniformly).
 */
class ScaleCommand implements IShotCommand {
	private var factor:NumValue;
	private var fx:NumValue; // null -> use factor
	private var fy:NumValue; // null -> use factor

	public function new(factor:NumValue, ?fx:NumValue, ?fy:NumValue) {
		this.factor = factor;
		this.fx = fx;
		this.fy = fy;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		var p = ctx.prototype;
		var f = factor.get();
		p.x *= (fx != null) ? fx.get() : f;
		p.y *= (fy != null) ? fy.get() : f;
		p.offsetDistance *= f;
	}
}

/**
 * Linearly interpolates prototype[prop] from its current value to `target`
 * over `frames` frames (one step per frame, landing exactly on `target`).
 *
 * This is the engine's first *stateful* command type. Compiled commands are
 * shared across contexts (Concurrent clones, sub-script bullets, Loop
 * re-entry), so per-execution state must NOT live on the command itself:
 * run() captures the start value and allocates a fresh TweenStepCommand,
 * pushed as its own repeat-frame - each execution owns its own state.
 * The target NumValue is evaluated once, at tween start.
 */
class TweenCommand implements IShotCommand {
	private var prop:String;
	private var target:NumValue;
	private var frames:Int;

	public function new(prop:String, target:NumValue, frames:Int) {
		this.prop = prop;
		this.target = target;
		this.frames = frames;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		var to = target.get();
		if (frames <= 0) {
			ctx.prototype.setProp(prop, to);
			return;
		}
		var start = ctx.prototype.getProp(prop);
		ctx.frames.push(new shot.ShotContext.ShotFrame([new TweenStepCommand(prop, start, to, frames)], frames));
	}
}

/** One in-flight tween execution; instantiated fresh by TweenCommand.run(). */
private class TweenStepCommand implements IShotCommand {
	private var prop:String;
	private var start:Float;
	private var target:Float;
	private var total:Int;
	private var i:Int = 0;

	public function new(prop:String, start:Float, target:Float, total:Int) {
		this.prop = prop;
		this.start = start;
		this.target = target;
		this.total = total;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		i++;
		var t = i / total;
		// Final step assigns target exactly (t == 1), no float drift.
		ctx.prototype.setProp(prop, start + (target - start) * t);
		ctx.waitFrames = 1;
	}
}

/** Points the prototype's direction from the (offset) spawn position at the emitter's target. */
class AimAtTargetCommand implements IShotCommand {
	public function new() {}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		var target = runner.getEmitter().getTarget();
		if (target == null) return;

		var pos = runner.spawnPosition(ctx.prototype);
		ctx.prototype.direction = Math.atan2(target.y - pos.y, target.x - pos.x) * 180 / Math.PI;
	}
}
