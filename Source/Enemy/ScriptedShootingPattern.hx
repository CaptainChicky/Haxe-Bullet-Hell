package enemy;

import bullet.BulletEmitters.EnemyBulletEmitter;
import manager.CollisionManager;
import shot.ShotCommand.IShotCommand;
import shot.ScriptRunner;
import openfl.events.Event;

/**
 * Shooting pattern driven by a compiled shot script.
 * Bridges the frame loop to a ScriptRunner firing through an EnemyBulletEmitter.
 */
class ScriptedShootingPattern extends EnemyShootingPattern {
	private var runner:ScriptRunner;

	public function new(enemy:Enemy, commands:Array<IShotCommand>, collisionManager:CollisionManager) {
		super(enemy);
		var emitter = new EnemyBulletEmitter(enemy, collisionManager);
		this.runner = new ScriptRunner(emitter, commands);
	}

	// Override to use script update for pattern execution
	override private function everyFrame(event:Event):Void {
		if (runner != null) {
			runner.update();
		}
	}

	override public function stopShooting():Void {
		super.stopShooting();
		if (runner != null) {
			runner.stop();
		}
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
