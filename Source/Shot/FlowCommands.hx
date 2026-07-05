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
 */
class ConcurrentCommand implements IShotCommand {
	private var branches:Array<Array<IShotCommand>>;

	public function new(branches:Array<Array<IShotCommand>>) {
		this.branches = branches;
	}

	public function run(ctx:ShotContext, runner:ScriptRunner):Void {
		if (branches.length > 0) runner.branch(ctx, branches);
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
