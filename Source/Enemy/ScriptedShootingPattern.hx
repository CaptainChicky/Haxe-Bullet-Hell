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

	public function new(enemy:Enemy, commands:Array<IShotCommand>, collisionManager:CollisionManager, ?bulletSprite:String) {
		super(enemy);
		var emitter = new EnemyBulletEmitter(enemy, collisionManager, bulletSprite);
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
