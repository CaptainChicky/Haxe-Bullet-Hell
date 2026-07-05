package shot;

/**
 * A single compiled script command.
 *
 * The runner pre-increments the frame's program counter before calling run(),
 * so commands never advance the index themselves. Commands act by:
 *   - mutating ctx.prototype                (property commands)
 *   - calling runner.fire(ctx)              (fire commands)
 *   - setting ctx.waitFrames                (Wait)
 *   - pushing a ShotFrame onto ctx.frames   (Loop / Rep)
 *   - spawning child contexts via runner    (Concurrent)
 *
 * New behaviors are added by implementing this interface and registering a
 * parser in CommandRegistry - no central enum to modify.
 */
interface IShotCommand {
	function run(ctx:ShotContext, runner:ScriptRunner):Void;
}
