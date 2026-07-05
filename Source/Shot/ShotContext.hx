package shot;

import shot.ShotCommand.IShotCommand;

/**
 * One stack frame of script execution: a command list with a program counter
 * and repetition bookkeeping (maxIterations == -1 means loop forever).
 */
class ShotFrame {
	public var commands:Array<IShotCommand>;
	public var index:Int = 0;
	public var iteration:Int = 0;
	public var maxIterations:Int;

	public function new(commands:Array<IShotCommand>, maxIterations:Int) {
		this.commands = commands;
		this.maxIterations = maxIterations;
	}
}

/**
 * One independent thread of script execution.
 *
 * Unifies what the old engine modelled three ways (ScriptState, the main
 * executor's stack, and ConcurrentBranch): every context owns its own
 * prototype and frame stack, so the main script and each concurrent branch
 * run through the exact same code path - and Concurrent can nest freely.
 */
class ShotContext {
	/** The mutable bullet prototype this context's commands operate on. */
	public var prototype:ShotPrototype;

	/** Frame stack for nested Loop / Rep blocks. */
	public var frames:Array<ShotFrame>;

	/** Fractional frames left to wait before executing further commands. */
	public var waitFrames:Float = 0;

	/** Number of live child contexts spawned by a Concurrent command.
	 *  While > 0 this context is suspended. */
	public var blockedBy:Int = 0;

	/** Parent context to unblock when this context finishes (null for root). */
	public var parent:ShotContext;

	public var isComplete:Bool = false;

	public function new(commands:Array<IShotCommand>, prototype:ShotPrototype, ?parent:ShotContext) {
		this.prototype = prototype;
		this.parent = parent;
		// Root frame executes exactly once.
		this.frames = [new ShotFrame(commands, 1)];
	}

	public inline function topFrame():ShotFrame {
		return frames[frames.length - 1];
	}
}
