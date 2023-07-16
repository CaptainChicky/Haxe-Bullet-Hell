package player;

import bullet.BulletPlayer;
import openfl.events.Event;
import openfl.display.Sprite;
import openfl.Lib;

class PlayerShootingPattern extends Sprite {
	private var player:Player; // Reference to the player that uses this shooting pattern
	private var isShooting:Bool = false;

	public function new(player:Player) {
		super();
		this.player = player;
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
