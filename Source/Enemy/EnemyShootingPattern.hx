package enemy;

import bullet.BulletEnemy;
import manager.CollisionManager;

/**
 * Abstract base class for enemy shooting patterns.
 * Updated centrally by EnemyManager once per frame (patterns own no
 * ENTER_FRAME listeners; see the lagging-bullet note in CollisionManager).
 * Subclasses (like ScriptedShootingPattern) override update() to implement pattern logic.
 */
abstract class EnemyShootingPattern {
	private var enemy:Enemy;
	private var isShooting:Bool = false;

	// Static collision manager shared across all patterns
	private static var collisionManager:CollisionManager;

	public static function setCollisionManager(manager:CollisionManager):Void {
		collisionManager = manager;
	}

	public static function getCollisionManager():CollisionManager {
		return collisionManager;
	}

	// Helper method for subclasses to register bullets with collision system
	private function registerBullet(bullet:BulletEnemy):Void {
		if (collisionManager != null) {
			collisionManager.registerEnemyBullet(bullet);
		}
	}

	public function new(enemy:Enemy) {
		this.enemy = enemy;
	}

	// Subclasses override this to implement their per-frame logic.
	// Called every frame by EnemyManager regardless of shooting state
	// (subclasses gate on isShooting and may keep ticking a ghost origin).
	public function update():Void {
		// Override in subclass
	}

	public function startShooting():Void {
		isShooting = true;
	}

	public function stopShooting():Void {
		isShooting = false;
	}

	/** Called by Enemy.die() after the enemy is fully dead. Subclasses may
	 *  keep a ghost origin alive for still-bound bullets. */
	public function onOwnerDied():Void {}

	// Accessor for subclasses to get the enemy reference
	private function getEnemy():Enemy {
		return enemy;
	}

	// Accessor for subclasses to check shooting status
	private function isCurrentlyShooting():Bool {
		return isShooting;
	}
}
