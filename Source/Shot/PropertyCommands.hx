package shot;

import shot.ShotCommand.IShotCommand;

/**
 * Generic prototype-property commands.
 *
 * These are parameterized on a property *name* resolved through
 * ShotPrototype.getProp/setProp, so adding a new bullet property (or using a
 * custom script variable) requires no new command classes and no parser
 * changes: {"control": "Set", "prop": "accel", "value": -0.05} just works.
 */

/** prototype[prop] = value */
class SetPropCommand implements IShotCommand {
	private var prop:String;
	private var value:Float;

	public function new(prop:String, value:Float) {
		this.prop = prop;
		this.value = value;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.prototype.setProp(prop, value);
	}
}

/** prototype[prop] += delta */
class AddPropCommand implements IShotCommand {
	private var prop:String;
	private var delta:Float;

	public function new(prop:String, delta:Float) {
		this.prop = prop;
		this.delta = delta;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.prototype.setProp(prop, ctx.prototype.getProp(prop) + delta);
	}
}

/** prototype[prop] = uniform random in [min, max) */
class RandomPropCommand implements IShotCommand {
	private var prop:String;
	private var min:Float;
	private var max:Float;

	public function new(prop:String, min:Float, max:Float) {
		this.prop = prop;
		this.min = min;
		this.max = max;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.prototype.setProp(prop, min + Math.random() * (max - min));
	}
}

/** prototype[dst] = prototype[src] (covers CopyAngleToOffset / CopyOffsetToAngle) */
class CopyPropCommand implements IShotCommand {
	private var src:String;
	private var dst:String;

	public function new(src:String, dst:String) {
		this.src = src;
		this.dst = dst;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.prototype.setProp(dst, ctx.prototype.getProp(src));
	}
}

/** Convenience: set/add spawn offset distance and bearing in one step. */
class OffsetCommand implements IShotCommand {
	private var distance:Float;
	private var angle:Float;
	private var relative:Bool;

	public function new(distance:Float, angle:Float, relative:Bool) {
		this.distance = distance;
		this.angle = angle;
		this.relative = relative;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		var p = ctx.prototype;
		if (relative) {
			p.offsetDistance += distance;
			p.offsetAngle += angle;
		} else {
			p.offsetDistance = distance;
			p.offsetAngle = angle;
		}
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
