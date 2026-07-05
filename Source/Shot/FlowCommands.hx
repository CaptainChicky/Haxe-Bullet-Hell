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
 * Runs its body against a CLONE of the prototype, discarded when the block
 * ends - mutations inside affect only bullets fired inside the block.
 *
 * This is what separates "configure a one-shot burst of children" from
 * "steer the bullet that owns this script": a bullet syncs its flight state
 * from the script's ROOT prototype (ScriptRunner.getPrototype()), which a
 * Scope never touches. flower.json's seeds keep curving through their petal
 * burst because the burst's Set turn/speed/accel happen inside a Scope.
 *
 * Executes inline within the same frame budget (unlike a Concurrent branch,
 * which starts the next frame). Nests freely. Like Tween, per-execution
 * state (the saved prototype) is allocated fresh in run(), so the compiled
 * command can be shared across Loop iterations and contexts.
 *
 * Note: the clone is a snapshot at Scope entry. In a multi-frame Scope
 * (body contains Waits), writes the owning bullet makes to the root
 * prototype during the block are not visible inside it.
 */
class ScopeCommand implements IShotCommand {
	private var body:Array<IShotCommand>;

	public function new(body:Array<IShotCommand>) {
		this.body = body;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (body.length == 0) return;
		var saved = ctx.prototype;
		ctx.prototype = saved.clone();
		var cmds = body.copy();
		cmds.push(new RestorePrototypeCommand(saved));
		ctx.frames.push(new ShotFrame(cmds, 1));
	}
}

/** Sentinel appended to a Scope body: restores the pre-Scope prototype. */
private class RestorePrototypeCommand implements IShotCommand {
	private var saved:ShotPrototype;

	public function new(saved:ShotPrototype) {
		this.saved = saved;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		ctx.prototype = saved;
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
