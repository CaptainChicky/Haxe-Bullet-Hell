package enemy;

import bullet.BulletEmitters.EnemyBulletEmitter;
import manager.CollisionManager;
import enemy.MovementScript;
import shot.GhostOrigin;
import shot.ShotCommand.IShotCommand;
import shot.ScriptRunner;
import openfl.events.Event;

/**
 * Shooting pattern driven by a compiled shot script.
 * Bridges the frame loop to a ScriptRunner firing through an EnemyBulletEmitter.
 */
class ScriptedShootingPattern extends EnemyShootingPattern {
	private var runner:ScriptRunner;
	private var emitter:EnemyBulletEmitter;
	private var ghostMovement:MovementScript = null;

	public function new(enemy:Enemy, commands:Array<IShotCommand>, collisionManager:CollisionManager, ?bulletSprite:String) {
		super(enemy);
		this.emitter = new EnemyBulletEmitter(enemy, collisionManager, bulletSprite);
		this.runner = new ScriptRunner(emitter, commands);
	}

	// Override to use script update for pattern execution
	override private function everyFrame(event:Event):Void {
		if (runner != null) {
			runner.update();

			// Firedancer-style self-movement: a pattern that sets the script
			// variable moveSelf to nonzero drives the ENEMY's velocity from the
			// script's live direction/speed each frame (so Tween on speed gives
			// smooth acceleration). Movement-only patterns: move.json, move2.json.
			var proto = runner.getPrototype();
			if (proto != null && proto.getProp("moveSelf") != 0) {
				var rad = proto.direction * Math.PI / 180;
				getEnemy().setVelocity(Math.cos(rad) * proto.speed, Math.sin(rad) * proto.speed);
			}
		}
	}

	override public function stopShooting():Void {
		super.stopShooting();
		if (runner != null) {
			runner.stop();
		}
	}

	/**
	 * Ghost-parent orphan handling: if the enemy died while offset-bound
	 * bullets still derive their position from it, stand up a GhostOrigin at
	 * the enemy's last position/velocity and keep ticking it here (the engine
	 * stays display-free; only the position is read by the bind path). The
	 * enemy's movementScript is retargeted to the ghost with loop forced off,
	 * so a looping path plays once and carries the formation off-screen
	 * instead of orbiting forever.
	 */
	override public function onOwnerDied():Void {
		if (emitter == null || emitter.getBoundCount() <= 0) return;
		var enemy = getEnemy();
		var maxFrames = Std.int(runner.getPrototype().getProp("maxOrphanFrames"));
		if (maxFrames <= 0) maxFrames = GhostOrigin.DEFAULT_MAX_ORPHAN_FRAMES;
		var ghost = emitter.beginGhost(enemy.x, enemy.y, enemy.getVelocityX(), enemy.getVelocityY(), maxFrames);
		ghostMovement = enemy.getMovementScript();
		if (ghostMovement != null) {
			ghostMovement.disableLoop();
			ghostMovement.retarget(ghost);
		}
		addEventListener(Event.ENTER_FRAME, ghostFrame);
	}

	private function ghostFrame(event:Event):Void {
		var ghost = emitter.getGhost();
		if (ghost == null) {
			// Refcount reached zero (or force-vanish emptied it): torn down.
			removeEventListener(Event.ENTER_FRAME, ghostFrame);
			ghostMovement = null;
			return;
		}
		if (ghostMovement != null) ghostMovement.update();
		ghost.tick();
	}

	public function pauseScript():Void {
		if (runner != null) {
			runner.pause();
		}
	}

	public function resumeScript():Void {
		if (runner != null) {
			runner.resume();
		}
	}
}
