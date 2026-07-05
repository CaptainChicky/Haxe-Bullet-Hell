package shot;

import shot.ShotCommand.IShotCommand;
import shot.ShotContext.ShotFrame;
import shot.ShotEmitter.IShotEmitter;

/**
 * Executes a compiled shot script against an IShotEmitter.
 *
 * One runner drives a list of ShotContexts (the root plus any concurrent
 * branches, which may themselves branch). Each active context receives a
 * 1.0-frame budget per update, so fractional Waits accumulate correctly and
 * several instantaneous commands can execute within a single frame - the
 * same timing semantics as the previous engine, but through one code path.
 */
class ScriptRunner {
	/** Safety valve against runaway zero-wait loops within one frame. */
	static inline final MAX_COMMANDS_PER_FRAME:Int = 1000;

	private var emitter:IShotEmitter;
	private var contexts:Array<ShotContext>;
	private var isActive:Bool = true;

	public var isPaused:Bool = false;

	public function new(emitter:IShotEmitter, commands:Array<IShotCommand>, ?prototype:ShotPrototype) {
		this.emitter = emitter;
		var proto = (prototype != null) ? prototype : new ShotPrototype();
		this.contexts = [new ShotContext(commands, proto)];
	}

	public function update():Void {
		if (isPaused || !isActive) return;
		if (!emitter.isAlive()) {
			isActive = false;
			return;
		}

		// Iterate over a snapshot: Concurrent commands append new contexts,
		// which should start executing next frame (matches old behavior).
		var snapshot = contexts.copy();
		for (ctx in snapshot) {
			if (!ctx.isComplete && ctx.blockedBy == 0) {
				step(ctx);
			}
		}

		// Drop finished contexts, unblocking parents.
		var i = contexts.length - 1;
		while (i >= 0) {
			var ctx = contexts[i];
			if (ctx.isComplete) {
				if (ctx.parent != null) ctx.parent.blockedBy--;
				contexts.splice(i, 1);
			}
			i--;
		}

		if (contexts.length == 0) isActive = false;
	}

	/** Run one context for (up to) one frame of budget. */
	private function step(ctx:ShotContext):Void {
		var budget:Float = 1.0;

		// Pay down any pending wait first.
		if (ctx.waitFrames > 0) {
			var spent = Math.min(ctx.waitFrames, budget);
			ctx.waitFrames -= spent;
			budget -= spent;
			if (ctx.waitFrames > 0 || budget <= 0) return;
		}

		var executed = 0;
		while (budget > 0 && executed < MAX_COMMANDS_PER_FRAME) {
			executed++;

			if (ctx.frames.length == 0) {
				ctx.isComplete = true;
				return;
			}

			var frame = ctx.topFrame();

			// Frame exhausted: loop, repeat, or pop.
			if (frame.index >= frame.commands.length) {
				frame.iteration++;
				if (frame.maxIterations == -1 || frame.iteration < frame.maxIterations) {
					frame.index = 0; // restart (infinite Loop or next Rep iteration)
				} else {
					ctx.frames.pop(); // parent's index was pre-incremented; nothing else to do
					if (ctx.frames.length == 0) {
						ctx.isComplete = true;
						return;
					}
				}
				continue;
			}

			// Pre-increment program counter, then run. Commands that push
			// frames or spawn branches never touch the index.
			var cmd = frame.commands[frame.index];
			frame.index++;
			cmd.run(ctx, this);

			// A Concurrent command suspended us until its children finish.
			if (ctx.blockedBy > 0) return;

			// A Wait command consumed budget.
			if (ctx.waitFrames > 0) {
				var spent = Math.min(ctx.waitFrames, budget);
				ctx.waitFrames -= spent;
				budget -= spent;
				if (ctx.waitFrames > 0) return;
			}
		}
	}

	// ------------------------------------------------------------------ API used by commands

	/** Spawn concurrent branches. Each branch clones the parent's prototype. */
	public function branch(parent:ShotContext, branches:Array<Array<IShotCommand>>):Void {
		for (commands in branches) {
			var child = new ShotContext(commands, parent.prototype.clone(), parent);
			contexts.push(child);
			parent.blockedBy++;
		}
	}

	/** Clone the context's prototype into a live bullet, applying the spawn offset.
	 *  Direction/speed overrides support the legacy Fire(angle, speed) semantics. */
	public function fire(ctx:ShotContext, ?directionOverride:Null<Float>, ?speedOverride:Null<Float>):Void {
		var proto = ctx.prototype.clone();
		if (directionOverride != null) proto.direction = directionOverride;
		if (speedOverride != null) proto.speed = speedOverride;

		var pos = spawnPosition(ctx.prototype);
		emitter.spawn(proto, pos.x, pos.y);
	}

	/** World-space spawn position for the current prototype (origin + offset). */
	public function spawnPosition(proto:ShotPrototype):{x:Float, y:Float} {
		var x = emitter.getOriginX();
		var y = emitter.getOriginY();
		if (proto.offsetDistance != 0) {
			var rad = proto.offsetAngle * Math.PI / 180;
			x += Math.cos(rad) * proto.offsetDistance;
			y += Math.sin(rad) * proto.offsetDistance;
		}
		return {x: x, y: y};
	}

	public function getEmitter():IShotEmitter {
		return emitter;
	}

	public function pause():Void isPaused = true;

	public function resume():Void isPaused = false;

	public function stop():Void isActive = false;
}
