package player;

import bullet.BulletPlayer;
import manager.CollisionManager;
import openfl.events.Event;
import openfl.display.Sprite;
import openfl.Lib;

class PlayerShootingPattern extends Sprite {
	private var player:Player; // Reference to the player that uses this shooting pattern
	private var isShooting:Bool = false;
	private var collisionManager:CollisionManager;

	public function new(player:Player, collisionManager:CollisionManager) {
		super();
		this.player = player;
		this.collisionManager = collisionManager;
	}

	private function spawnPlayerBullet():Void {
		// 5 bullets: 3 center (tight, parallel) + 2 flankers (angled spreads)
		var bulletConfigs = [
			{offsetX: -30, velX: -1, velY: -10}, // Left flanker (angled out)
			{offsetX: -7, velX: 0, velY: -20},  // Left center (parallel)
			{offsetX: 0, velX: 0, velY: -20},    // Center (parallel)
			{offsetX: 7, velX: 0, velY: -20},   // Right center (parallel)
			{offsetX: 30, velX: 1, velY: -10}    // Right flanker (angled out)
		];
		
		for (config in bulletConfigs) {
			var bullet:BulletPlayer = new BulletPlayer();
			bullet.x = player.x + config.offsetX;
			bullet.y = player.y;

			// Calculate the velocity of the bullet to move towards the top of the board
			// Adjust the speed as needed
			var bulletVelocityX:Float = config.velX;
			var bulletVelocityY:Float = config.velY;

			// Set the velocity of the bullet
			bullet.velocityX = bulletVelocityX;
			bullet.velocityY = bulletVelocityY;

			Lib.current.addChild(bullet); // Add the bullet to the stage

			// Register bullet with collision manager
			if (collisionManager != null) {
				collisionManager.registerPlayerBullet(bullet);
			}
		}
	}

	private function everyFrame(event:Event):Void {
		if (isShooting) {
			spawnPlayerBullet();
		}
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
