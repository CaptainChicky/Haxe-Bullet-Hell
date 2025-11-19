package manager;

import bullet.*;
import enemy.Enemy;
import player.Player;
import openfl.display.Sprite;
import openfl.events.Event;

class CollisionManager extends Sprite {
	private var player:Player;
	private var enemyManager:EnemyManager;
	private var playerBullets:Array<BulletPlayer>;
	private var enemyBullets:Array<BulletEnemy>;

	// Player hitbox size (the small black dot)
	private static inline final PLAYER_HITBOX_RADIUS:Float = 3.0;

	public function new(player:Player, enemyManager:EnemyManager) {
		super();
		this.player = player;
		this.enemyManager = enemyManager;
		this.playerBullets = new Array<BulletPlayer>();
		this.enemyBullets = new Array<BulletEnemy>();

		addEventListener(Event.ENTER_FRAME, update);
	}

	public function registerPlayerBullet(bullet:BulletPlayer):Void {
		playerBullets.push(bullet);
	}

	public function registerEnemyBullet(bullet:BulletEnemy):Void {
		enemyBullets.push(bullet);
	}

	private function update(event:Event):Void {
		// Check player bullets vs enemies
		checkPlayerBulletsVsEnemies();

		// Check enemy bullets vs player
		checkEnemyBulletsVsPlayer();

		// Clean up dead bullets
		cleanupBullets();

		// Clean up dead enemies
		enemyManager.cleanupDeadEnemies();
	}

	private function checkPlayerBulletsVsEnemies():Void {
		var enemies:Array<Enemy> = enemyManager.getEnemies();

		for (bullet in playerBullets) {
			if (bullet.parent == null) continue; // Bullet already removed

			for (enemy in enemies) {
				if (!enemy.isAlive()) continue;

				// Simple bounding box collision
				if (bullet.hitTestObject(enemy)) {
					enemy.takeDamage(1);

					// Remove the bullet
					if (bullet.parent != null) {
						bullet.parent.removeChild(bullet);
					}
					break; // Bullet can only hit one enemy
				}
			}
		}
	}

	private function checkEnemyBulletsVsPlayer():Void {
		if (!player.isAlive()) return;

		// Player hitbox is centered on the player sprite
		var playerCenterX:Float = player.x;
		var playerCenterY:Float = player.y;

		for (bullet in enemyBullets) {
			if (bullet.parent == null) continue; // Bullet already removed

			// Check if bullet sprite overlaps with player hitbox circle
			// We need to account for the bullet's size
			var bulletRadius:Float = Math.max(bullet.width, bullet.height) / 2;
			var collisionDistance:Float = PLAYER_HITBOX_RADIUS + bulletRadius;

			var dx:Float = bullet.x - playerCenterX;
			var dy:Float = bullet.y - playerCenterY;
			var distanceSquared:Float = dx * dx + dy * dy;

			if (distanceSquared < collisionDistance * collisionDistance) {
				// Player hit!
				trace("COLLISION DETECTED! Bullet at (" + bullet.x + ", " + bullet.y + ") hit player at (" + playerCenterX + ", " + playerCenterY + ")");
				player.takeDamage(1);

				// Remove the bullet
				if (bullet.parent != null) {
					bullet.parent.removeChild(bullet);
				}

				break; // Only need one hit to kill player
			}
		}
	}

	private function cleanupBullets():Void {
		// Remove bullets that are no longer in the display tree
		var i:Int = playerBullets.length - 1;
		while (i >= 0) {
			if (playerBullets[i].parent == null) {
				playerBullets.splice(i, 1);
			}
			i--;
		}

		i = enemyBullets.length - 1;
		while (i >= 0) {
			if (enemyBullets[i].parent == null) {
				enemyBullets.splice(i, 1);
			}
			i--;
		}
	}

	public function reset():Void {
		playerBullets = new Array<BulletPlayer>();
		enemyBullets = new Array<BulletEnemy>();
	}

	public function clearAllBullets():Void {
		// Remove all player bullets from display
		for (bullet in playerBullets) {
			if (bullet.parent != null) {
				bullet.parent.removeChild(bullet);
			}
		}

		// Remove all enemy bullets from display
		for (bullet in enemyBullets) {
			if (bullet.parent != null) {
				bullet.parent.removeChild(bullet);
			}
		}

		// Clear arrays
		playerBullets = new Array<BulletPlayer>();
		enemyBullets = new Array<BulletEnemy>();
	}
}
