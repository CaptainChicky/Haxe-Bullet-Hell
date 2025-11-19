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
		var bullet:BulletPlayer = new BulletPlayer();
		bullet.x = player.x;
		bullet.y = player.y;

		// Calculate the velocity of the bullet to move towards the top of the board
		var bulletVelocityX:Float = 0;
		var bulletVelocityY:Float = -3; // Adjust the speed as needed

		// Set the velocity of the bullet
		bullet.velocityX = bulletVelocityX;
		bullet.velocityY = bulletVelocityY;

		Lib.current.addChild(bullet); // Add the bullet to the stage

		// Register bullet with collision manager
		if (collisionManager != null) {
			collisionManager.registerPlayerBullet(bullet);
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
