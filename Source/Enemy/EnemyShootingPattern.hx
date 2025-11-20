package enemy;

import bullet.BulletEnemy;
import manager.CollisionManager;
import openfl.events.Event;
import openfl.display.Sprite;

/**
 * Abstract base class for enemy shooting patterns.
 * Provides core functionality for managing collision detection and event listeners.
 * Subclasses (like ScriptedShootingPattern) override everyFrame() to implement pattern logic.
 */
abstract class EnemyShootingPattern extends Sprite {
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
		super();
		this.enemy = enemy;
	}

	// Subclasses override this to implement their update logic
	private function everyFrame(event:Event):Void {
		// Override in subclass
	}

	public function startShooting():Void {
		isShooting = true;
		addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	public function stopShooting():Void {
		isShooting = false;
		removeEventListener(Event.ENTER_FRAME, everyFrame);
	}

	// Accessor for subclasses to get the enemy reference
	private function getEnemy():Enemy {
		return enemy;
	}

	// Accessor for subclasses to check shooting status
	private function isCurrentlyShooting():Bool {
		return isShooting;
	}
}
