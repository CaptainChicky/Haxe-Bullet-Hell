package enemy;

import bullet.BulletEnemy;
import manager.CollisionManager;
import openfl.events.Event;
import openfl.display.Sprite;
import openfl.Lib;

abstract class EnemyShootingPattern extends Sprite {
	private var enemy:Enemy; // Reference to the enemy that uses this shooting pattern

	private var patternStartTime:Int = Lib.getTimer();

	private var bulletSpawnTimer:Float = 0;
	private var bulletSpawnInterval:Float = 0.01; // Adjust the interval as needed, in seconds

	//private var bulletSpeed:Float = 5; // Speed of the bullet pixels per second
	//private var rotationChange:Float = 12.0; // Change in rotation (degrees) for each shot
	//private var currentRotation:Float = 0.0; // Initial rotation for the first shot

	private var isShooting:Bool = false;

	// Collision manager for registering bullets
	private static var collisionManager:CollisionManager;

	public static function setCollisionManager(manager:CollisionManager):Void {
		collisionManager = manager;
	}

	// Helper method for subclasses to register bullets
	private function registerBullet(bullet:BulletEnemy):Void {
		if (collisionManager != null) {
			collisionManager.registerEnemyBullet(bullet);
		}
	}

	public function new(enemy:Enemy) {
		super();
		this.enemy = enemy;
	}

	abstract private function spawnEnemyBullet():Void;

	private function everyFrame(event:Event):Void {
		var currentTime:Int = Lib.getTimer();
		var deltaTime:Float = (currentTime - patternStartTime) / 1000.0; // deltaTime is in seconds
		patternStartTime = currentTime;

		bulletSpawnTimer += deltaTime; // deltaTime is in seconds

		if (isShooting && (bulletSpawnTimer >= bulletSpawnInterval)) {
			spawnEnemyBullet();
			bulletSpawnTimer = 0;
		}
	}

	public function setBulletSpawnInterval(bulletSpawnInterval:Float):Void {
		this.bulletSpawnInterval = bulletSpawnInterval;
	}

	public function startShooting():Void {
		isShooting = true;
		addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	public function stopShooting():Void {
		isShooting = false;
		removeEventListener(Event.ENTER_FRAME, everyFrame);
	}
}