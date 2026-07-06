package bullet;

import enemy.Enemy;
import manager.CollisionManager;
import shot.ShotPrototype;
import shot.ScriptRunner;
import shot.ShotEmitter;
import openfl.Lib;

/**
 * Shared bullet-materialization logic: builds a BulletEnemy from a cloned
 * prototype, adds it to the display list, registers it for collision, and -
 * if the prototype carries a sub-script - attaches a ScriptRunner so the
 * bullet executes its own pattern after spawning.
 */
private class EmitterBase {
	private var collisionManager:CollisionManager;

	private function new(collisionManager:CollisionManager) {
		this.collisionManager = collisionManager;
	}

	/** Vanish is a no-op for enemy emitters; BulletSubEmitter overrides. */
	public function vanish():Void {}

	public function getTarget():ShotTarget {
		if (collisionManager == null) return null;
		var player = collisionManager.getPlayer();
		if (player == null || !player.isAlive()) return null;
		return {x: player.x, y: player.y};
	}

	public function spawn(prototype:ShotPrototype, x:Float, y:Float):Void {
		var bullet = new BulletEnemy(prototype);
		bullet.x = x;
		bullet.y = y;

		Lib.current.addChild(bullet);

		if (collisionManager != null) {
			collisionManager.registerEnemyBullet(bullet);
		}

		// Bound bullets follow the emitter that fired them (this object):
		// it provides live parent position + liveness. bindSource (the parent
		// script's live prototype) was attached by ScriptRunner.fireClone.
		if (prototype.bindMode != ShotPrototype.BIND_NONE) {
			var self:IShotEmitter = cast this;
			bullet.bindTo(self, prototype.bindMode, prototype.bindSource);
		}

		// Bullets with a sub-script become emitters themselves. The sub-script
		// starts from a clone of this bullet's prototype (inheriting direction,
		// speed, vars, ...) with subCommands stripped to prevent infinite
		// recursion - a Sub inside the sub-script can re-arm it deliberately.
		if (prototype.subCommands != null) {
			var subProto = prototype.clone();
			subProto.subCommands = null;
			// A bound bullet's own children do not implicitly bind to it;
			// a chain must opt in with an explicit Bind in the sub-script.
			subProto.bindMode = ShotPrototype.BIND_NONE;
			var runner = new ScriptRunner(new BulletSubEmitter(bullet, collisionManager), prototype.subCommands, subProto);
			bullet.attachScript(runner);
		}
	}
}

/** Fires bullets from an enemy's position. */
class EnemyBulletEmitter extends EmitterBase implements IShotEmitter {
	private var enemy:Enemy;

	public function new(enemy:Enemy, collisionManager:CollisionManager) {
		super(collisionManager);
		this.enemy = enemy;
	}

	public function getOriginX():Float return enemy.x;

	public function getOriginY():Float return enemy.y;

	public function isAlive():Bool {
		return enemy != null && enemy.isAlive();
	}
}

/** Fires bullets from a bullet's position - enables nested (Touhou-style) patterns. */
class BulletSubEmitter extends EmitterBase implements IShotEmitter {
	private var bullet:BulletEnemy;

	public function new(bullet:BulletEnemy, collisionManager:CollisionManager) {
		super(collisionManager);
		this.bullet = bullet;
	}

	public function getOriginX():Float return bullet.x;

	public function getOriginY():Float return bullet.y;

	public function isAlive():Bool {
		return bullet != null && bullet.parent != null;
	}

	/** The Vanish command: the bullet removes itself mid-flight. */
	override public function vanish():Void {
		if (bullet != null) bullet.destroy();
	}
}
