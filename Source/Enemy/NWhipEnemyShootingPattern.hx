package enemy;

import bullet.BulletEnemy;
import openfl.events.Event;
import openfl.display.Sprite;
import openfl.Lib;
import haxe.Timer;

class NWhipEnemyShootingPattern extends EnemyShootingPattern {
	private var whipFullAngle:Float = 90; // The full angle of the whip
	private var numberOfWhips:Int = 1; // The number of whips to fire

	private var baseAngle:Float = 0;

	private var numberOfBullets:Int = 8; // The number of bullets to fire in each whip

	private var angleToFire:Float = 90; // The angle to fire at
	private var salt:Int = 2; // The salt to add to the angle to fire at

	private var baseBulletSpeed:Float = 4; // Speed of the bullet pixels per second
	private var speedChange:Float = 1; // Change in rotation (degrees) for each shot

	public function new(enemy:Enemy) {
		super(enemy);

		addEventListener(Event.ENTER_FRAME, everyFrame);

		baseAngle = whipFullAngle / numberOfWhips;
		angleToFire = (90 - (numberOfBullets/2 * salt)) - (0.5 * (numberOfWhips - 1)) * baseAngle; // The lowest angle to fire at
		trace("angleToFire: " + angleToFire);
	}

	private function spawnWhipRow():Void {
		// for all the bullets in this whip row
		for (i in 0...numberOfWhips) {
			// spawn the bullet
			var bullet:BulletEnemy = new BulletEnemy();
			bullet.x = enemy.x;
			bullet.y = enemy.y;

			// bullet velocity for this whip row
			var bulletVelocityX:Float = Math.cos(angleToFire * Math.PI / 180) * baseBulletSpeed;
			var bulletVelocityY:Float = Math.sin(angleToFire * Math.PI / 180) * baseBulletSpeed;

			// Set the velocity of the bullet
			bullet.velocityX = bulletVelocityX;
			bullet.velocityY = bulletVelocityY;

			Lib.current.addChild(bullet); // Add the bullet to the stage

			angleToFire += baseAngle; // Increase the angle to fire at
		}
	}

	private function spawnEnemyBullet():Void {
		var currentIndex:Int = 0;
	
		function spawnNextBullet():Void {
			if (currentIndex < numberOfBullets) {
				angleToFire = (90 - (numberOfBullets/2 * salt)) - (0.5 * (numberOfWhips - 1)) * baseAngle; // Reset the angle to fire at
				angleToFire += currentIndex * salt; // Add the salt to the angle to fire at
				spawnWhipRow();
				baseBulletSpeed += speedChange; // Increase the speed of the bullet
	
				currentIndex++;
	
				// we have to manually create a function to pass to the timer into
				// Wait for 0.5 seconds before spawning the next bullet
				Timer.delay(spawnNextBullet, 40);
			} else {
				// All bullets have been spawned, reset the baseBulletSpeed
				baseBulletSpeed = 4; // Reset the speed of the bullet
			}
		}
	
		// Start spawning the bullets
		spawnNextBullet();
	}

	//override on every frame so that the base angle is the player's angle

}
