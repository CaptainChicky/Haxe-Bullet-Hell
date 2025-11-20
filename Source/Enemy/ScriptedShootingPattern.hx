package enemy;

import enemy.ShootingScript;
import openfl.events.Event;

class ScriptedShootingPattern extends EnemyShootingPattern {
	private var shootingScript:ShootingScript;

	public function new(enemy:Enemy, actions:Array<ShootingAction>, collisionManager:Dynamic) {
		super(enemy);
		this.shootingScript = new ShootingScript(enemy, actions, collisionManager);
	}

	// Override to use script update for pattern execution
	override private function everyFrame(event:Event):Void {
		if (shootingScript != null) {
			shootingScript.update();
		}
	}

	override public function stopShooting():Void {
		super.stopShooting();
		if (shootingScript != null) {
			shootingScript.stop();
		}
	}

	public function pauseScript():Void {
		if (shootingScript != null) {
			shootingScript.pause();
		}
	}

	public function resumeScript():Void {
		if (shootingScript != null) {
			shootingScript.resume();
		}
	}
}
