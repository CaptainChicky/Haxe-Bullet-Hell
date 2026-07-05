package shot;

import shot.ShotCommand.IShotCommand;

/**
 * Fires one bullet by cloning the prototype.
 *
 * Legacy JSON compatibility: a literal 0 for angle/speed means "use the
 * prototype's current value", matching the old Fire(0, 0) convention.
 */
class FireCommand implements IShotCommand {
	private var angle:Float;
	private var speed:Float;

	public function new(angle:Float, speed:Float) {
		this.angle = angle;
		this.speed = speed;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		var dir:Null<Float> = (angle == 0) ? null : angle;
		var spd:Null<Float> = (speed == 0) ? null : speed;
		runner.fire(ctx, dir, spd);
	}
}

/** Fires `count` bullets in a full circle, starting from the prototype's direction. */
class RadialCommand implements IShotCommand {
	private var count:Int;
	private var speed:Float;

	public function new(count:Int, speed:Float) {
		this.count = count;
		this.speed = speed;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (count <= 0) return;
		var base = ctx.prototype.direction;
		var spd:Null<Float> = (speed == 0) ? null : speed;
		var step = 360.0 / count;
		for (i in 0...count) {
			runner.fire(ctx, base + i * step, spd);
		}
	}
}

/** Fires `count` bullets spread evenly across an arc centered on the prototype's direction. */
class NWayCommand implements IShotCommand {
	private var count:Int;
	private var arc:Float;
	private var speed:Float;

	public function new(count:Int, arc:Float, speed:Float) {
		this.count = count;
		this.arc = arc;
		this.speed = speed;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (count <= 0) return;
		var base = ctx.prototype.direction;
		var spd:Null<Float> = (speed == 0) ? null : speed;

		if (count == 1) {
			runner.fire(ctx, base, spd);
			return;
		}

		var start = base - arc / 2;
		var step = arc / (count - 1);
		for (i in 0...count) {
			runner.fire(ctx, start + i * step, spd);
		}
	}
}
