package manager;

import bullet.*;
import enemy.Enemy;
import fx.CancelSparkLayer;
import player.Player;
import openfl.display.Sprite;
import openfl.events.Event;

class CollisionManager extends Sprite {
	private var player:Player;
	private var enemyManager:EnemyManager;
	private var playerBullets:Array<BulletPlayer>;
	private var enemyBullets:Array<BulletEnemy>;
	private var enemyLasers:Array<BulletLaser>;

	/** Continuous laser graze: score every this many frames while overlapping. */
	private static inline final LASER_GRAZE_INTERVAL:Int = 4;

	private static inline final DEFAULT_HITBOX_RADIUS:Float = 3.0;
	private static inline final DEFAULT_GRAZE_EXTRA:Float = 18.0;

	// Scoring callbacks (set by Main)
	public var onEnemyKilled:Enemy->Void = null;
	public var onGraze:Void->Void = null;

	public function new(player:Player, enemyManager:EnemyManager) {
		super();
		this.player = player;
		this.enemyManager = enemyManager;
		this.playerBullets = new Array<BulletPlayer>();
		this.enemyBullets = new Array<BulletEnemy>();
		this.enemyLasers = new Array<BulletLaser>();

		addEventListener(Event.ENTER_FRAME, update);

		// Bullets are updated centrally from ONE stable listener instead of one
		// ENTER_FRAME listener per bullet. OpenFL iterates the live broadcast
		// array while dispatching, so a bullet removing its own listener
		// mid-dispatch made the next listener skip a frame — visible as a
		// permanently lagging bullet inside an otherwise uniform ring.
		// EXIT_FRAME runs after every ENTER_FRAME handler: enemies have moved
		// and patterns have fired before bullets integrate, preserving the old
		// frame order (including a same-frame first update for new bullets).
		addEventListener(Event.EXIT_FRAME, updateBullets);
	}

	private function updateBullets(event:Event):Void {
		if (Main.gamePaused) return;

		// Plain index loops on purpose: a bullet's sub-script can spawn new
		// bullets during update, which append to these arrays and receive
		// their first update in this same pass (matching legacy timing).
		for (bullet in playerBullets) {
			bullet.update();
		}
		for (bullet in enemyBullets) {
			bullet.update();
		}
		for (laser in enemyLasers) {
			laser.update();
		}
		if (CancelSparkLayer.instance != null) {
			CancelSparkLayer.instance.update();
			if (Main.world != null && CancelSparkLayer.instance.parent == Main.world) {
				Main.world.setChildIndex(CancelSparkLayer.instance, Main.world.numChildren - 1);
			}
		}
	}

	public function registerPlayerBullet(bullet:BulletPlayer):Void {
		playerBullets.push(bullet);
	}

	public function registerEnemyBullet(bullet:BulletEnemy):Void {
		enemyBullets.push(bullet);
	}

	public function registerEnemyLaser(laser:BulletLaser):Void {
		enemyLasers.push(laser);
	}

	public function getPlayer():Player {
		return player;
	}

	public function getEnemyManager():EnemyManager {
		return enemyManager;
	}

	private function update(event:Event):Void {
		if (Main.gamePaused) return;

		// Check player bullets vs enemies
		checkPlayerBulletsVsEnemies();

		// Check enemy bullets vs player
		checkEnemyBulletsVsPlayer();

		checkEnemyLasersVsPlayer();

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

				// Circle collision on cached radii (hitTestObject recomputes
				// transformed bounds — too slow per bullet per frame on native)
				var hitDistance:Float = bullet.collisionRadius + enemy.collisionRadius;
				var dx:Float = bullet.x - enemy.x;
				var dy:Float = bullet.y - enemy.y;
				if (dx * dx + dy * dy < hitDistance * hitDistance) {
					if (bullet.piercing) {
						// Piercing bullets fly on through, damaging each enemy
						// at most once for their whole flight.
						if (!bullet.hasPierced(enemy)) {
							bullet.markPierced(enemy);
							enemy.takeDamage(bullet.damage);
							manager.AudioManager.sfxEnemyHit();
							if (!enemy.isAlive() && onEnemyKilled != null) {
								onEnemyKilled(enemy);
							}
						}
						continue; // keep checking further enemies
					}

					enemy.takeDamage(bullet.damage);
					manager.AudioManager.sfxEnemyHit();
					if (!enemy.isAlive() && onEnemyKilled != null) {
						onEnemyKilled(enemy);
					}

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

			// Check if bullet sprite overlaps with player hitbox circle,
			// using the radius cached at bullet construction
			var collisionDistance:Float = playerHitRadius() + bullet.collisionRadius;

			var dx:Float = bullet.x - playerCenterX;
			var dy:Float = bullet.y - playerCenterY;
			var distanceSquared:Float = dx * dx + dy * dy;

			if (distanceSquared < collisionDistance * collisionDistance && !player.isInvincible()) {
				// Player hit!
				player.takeDamage(1);

				// Remove the bullet
				if (bullet.parent != null) {
					bullet.parent.removeChild(bullet);
				}

				break; // Only need one hit to kill player
			}

			// Graze: bullet passes close by without hitting (scored once per bullet)
			if (!bullet.grazed) {
				var grazeDistance:Float = playerGrazeRadius() + bullet.collisionRadius;
				if (distanceSquared < grazeDistance * grazeDistance) {
					bullet.grazed = true;
					if (onGraze != null) onGraze();
					manager.AudioManager.sfxGraze();
				}
			}
		}
	}

	private function playerHitRadius():Float {
		if (player != null) return player.getHitboxRadius();
		return DEFAULT_HITBOX_RADIUS;
	}

	/** Graze ring radius from player center (character def). */
	private function playerGrazeRadius():Float {
		if (player != null) return player.getGrazeRadius();
		return DEFAULT_HITBOX_RADIUS + DEFAULT_GRAZE_EXTRA;
	}

	private function checkEnemyLasersVsPlayer():Void {
		if (!player.isAlive()) return;

		var playerCenterX:Float = player.x;
		var playerCenterY:Float = player.y;

		for (laser in enemyLasers) {
			if (laser.parent == null) continue;

			var seg = laser.segmentEndpoints();
			var halfW = laser.collisionHalfWidth();
			if (halfW <= 0) continue;

			var hitDist = halfW + playerHitRadius();
			var dist = shot.LaserGeometry.distancePointToSegment(playerCenterX, playerCenterY, seg.x1, seg.y1, seg.x2, seg.y2);

			if (dist < hitDist && !player.isInvincible()) {
				player.takeDamage(1);
				break;
			}

			if (laser.collides()) {
				var grazeDist = playerGrazeRadius() + halfW;
				if (dist < grazeDist) {
					laser.grazeCooldown++;
					if (laser.grazeCooldown >= LASER_GRAZE_INTERVAL) {
						laser.grazeCooldown = 0;
						if (onGraze != null) onGraze();
						manager.AudioManager.sfxGraze();
					}
				} else {
					laser.grazeCooldown = 0;
				}
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

		i = enemyLasers.length - 1;
		while (i >= 0) {
			if (enemyLasers[i].parent == null) {
				enemyLasers.splice(i, 1);
			}
			i--;
		}
	}

	public function reset():Void {
		playerBullets = new Array<BulletPlayer>();
		enemyBullets = new Array<BulletEnemy>();
		enemyLasers = new Array<BulletLaser>();
	}

	/** Bomb blast damage: hit every live enemy at once. Deaths route through
	 *  the same onEnemyKilled hook as bullet kills, so score and item drops
	 *  behave exactly as if the player shot them down. Boss transition
	 *  invulnerability still applies (BossEnemy.takeDamage ignores it). */
	public function damageAllEnemies(damage:Int):Void {
		for (enemy in enemyManager.getEnemies()) {
			if (!enemy.isAlive()) continue;
			enemy.takeDamage(damage);
			if (!enemy.isAlive() && onEnemyKilled != null) {
				onEnemyKilled(enemy);
			}
		}
		enemyManager.cleanupDeadEnemies();
	}

	/** Despawn every live enemy bullet and laser (bomb effect). Touhou-style
	 *  bombs clear active beams as well as bullets. Uses destroy() so bound
	 *  bullets and sub-scripts tear down properly. */
	public function clearEnemyBullets():Void {
		cancelEnemyBullets(true);
		cancelEnemyLasers();
	}

	public function clearAllBullets():Void {
		// Remove all player bullets from display
		for (bullet in playerBullets) {
			if (bullet.parent != null) {
				bullet.parent.removeChild(bullet);
			}
		}
		playerBullets = new Array<BulletPlayer>();

		cancelEnemyBullets(true);
		cancelEnemyLasers();
	}

	private function cancelEnemyLasers():Void {
		for (laser in enemyLasers) {
			if (laser.parent != null) laser.destroy();
		}
		enemyLasers = new Array<BulletLaser>();
	}

	private function cancelEnemyBullets(withSparks:Bool):Void {
		for (bullet in enemyBullets) {
			if (bullet.parent != null) {
				if (withSparks) spawnCancelSpark(bullet.x, bullet.y);
				bullet.destroy();
			}
		}
		enemyBullets = new Array<BulletEnemy>();
	}

	private function spawnCancelSpark(x:Float, y:Float):Void {
		if (CancelSparkLayer.instance != null) {
			CancelSparkLayer.instance.spawnAt(x, y);
		}
	}
}
