package shot;

import shot.ShotCommand.IShotCommand;
import shot.ShotContext.ShotFrame;

/** Suspends the context for a (possibly fractional) number of frames. */
class WaitCommand implements IShotCommand {
	private var frames:Float;

	public function new(frames:Float) {
		this.frames = frames;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (frames > 0) ctx.waitFrames = frames;
	}
}

/** Runs a block of commands forever. */
class LoopCommand implements IShotCommand {
	private var body:Array<IShotCommand>;

	public function new(body:Array<IShotCommand>) {
		this.body = body;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.frames.push(new ShotFrame(body, -1));
	}
}

/** Runs a block of commands a fixed number of times. */
class RepCommand implements IShotCommand {
	private var count:Int;
	private var body:Array<IShotCommand>;

	public function new(count:Int, body:Array<IShotCommand>) {
		this.count = count;
		this.body = body;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (count > 0) ctx.frames.push(new ShotFrame(body, count));
	}
}

/**
 * Runs several command sequences in parallel, each with an independent clone
 * of the prototype. The parent context resumes after all branches complete.
 * Branches may themselves contain Concurrent blocks (nesting now supported).
 *
 * With share = true, branches operate on the PARENT's prototype instead of
 * clones - required for e.g. two simultaneous Tweens animating different
 * properties of the same upcoming bullet (flowering).
 */
class ConcurrentCommand implements IShotCommand {
	private var branches:Array<Array<IShotCommand>>;
	private var share:Bool;

	public function new(branches:Array<Array<IShotCommand>>, share:Bool = false) {
		this.branches = branches;
		this.share = share;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (branches.length > 0) runner.branch(ctx, branches, share);
	}
}

/**
 * Removes the script's owner from play. For a bullet-owned script this
 * despawns the bullet mid-flight (the `vanish()` primitive - static geometry,
 * seeds, timed disappearing walls). Also terminates this script context.
 */
class VanishCommand implements IShotCommand {
	public function new() {}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		runner.getEmitter().vanish();
		// Halt: clear the frame stack so no further commands run this frame,
		// letting the runner retire the context normally next iteration.
		ctx.frames.resize(0);
	}
}

/**
 * Attaches a sub-script to the prototype: every bullet fired from now on
 * (until the next Sub / ClearSub) runs the given script itself after
 * spawning, becoming its own emitter. Pass an empty body to clear.
 */
class SubCommand implements IShotCommand {
	private var body:Array<IShotCommand>;

	public function new(body:Array<IShotCommand>) {
		this.body = body;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.prototype.subCommands = (body.length > 0) ? body : null;
	}
}
