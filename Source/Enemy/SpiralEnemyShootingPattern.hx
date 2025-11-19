package enemy;

import bullet.BulletEnemy;
import openfl.events.Event;
import openfl.display.Sprite;
import openfl.Lib;

class SpiralEnemyShootingPattern extends EnemyShootingPattern {

	private var bulletSpeed:Float = 5; // Speed of the bullet pixels per second
	private var rotationChange:Float = 12.0; // Change in rotation (degrees) for each shot
	private var currentRotation:Float = 0.0; // Initial rotation for the first shot

    public function new(enemy:Enemy) {
        super(enemy);
    }

    private function spawnEnemyBullet():Void {
		var bullet:BulletEnemy = new BulletEnemy();
		bullet.x = enemy.x;
		bullet.y = enemy.y;

		// Calculate the velocity of the bullet in a spiral pattern
		var bulletVelocityX:Float = Math.cos(currentRotation * Math.PI / 180) * bulletSpeed;
		var bulletVelocityY:Float = Math.sin(currentRotation * Math.PI / 180) * bulletSpeed;

		// Update the current rotation for the next shot
		currentRotation += rotationChange;

		// Set the velocity of the bullet
		bullet.velocityX = bulletVelocityX;
		bullet.velocityY = bulletVelocityY;

		Lib.current.addChild(bullet); // Add the bullet to the stage
		registerBullet(bullet); // Register with collision manager
	}
}