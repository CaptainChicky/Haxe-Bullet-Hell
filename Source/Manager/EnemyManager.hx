package manager;

import enemy.*;
import openfl.display.Sprite;
import openfl.events.Event;

class EnemyManager extends Sprite {
	private var enemies:Array<Enemy>;
	private var enemyPatterns:Array<EnemyShootingPattern>;

	public function new() {
		super();
		enemies = new Array<Enemy>();
		enemyPatterns = new Array<EnemyShootingPattern>();
	}

	public function spawnEnemy(x:Float, y:Float, patternType:String, patternConfig:Dynamic, health:Int = 1):Enemy {
		var enemy:Enemy = new Enemy(health);
		enemy.x = x;
		enemy.y = y;
		addChild(enemy);
		enemies.push(enemy);

		// Create the shooting pattern based on type
		var pattern:EnemyShootingPattern = createPattern(enemy, patternType, patternConfig);
		if (pattern != null) {
			enemyPatterns.push(pattern);

			// Set bullet spawn interval if provided
			if (patternConfig.bulletSpawnInterval != null) {
				pattern.setBulletSpawnInterval(patternConfig.bulletSpawnInterval);
			}

			// Auto-start shooting
			pattern.startShooting();
		}

		return enemy;
	}

	private function createPattern(enemy:Enemy, patternType:String, config:Dynamic):EnemyShootingPattern {
		switch (patternType.toLowerCase()) {
			case "spiral":
				var pattern = new SpiralEnemyShootingPattern(enemy);
				// Apply config if provided
				if (config.bulletSpeed != null) {
					// SpiralEnemyShootingPattern doesn't expose setters yet, but we could add them
				}
				return pattern;

			case "nwhip":
				var pattern = new NWhipEnemyShootingPattern(enemy);
				// NWhipEnemyShootingPattern also doesn't expose setters, but uses defaults
				// Could extend this to pass config values
				return pattern;

			default:
				trace("Unknown pattern type: " + patternType);
				return null;
		}
	}

	public function removeEnemy(enemy:Enemy):Void {
		enemies.remove(enemy);
		if (enemy.parent != null) {
			enemy.parent.removeChild(enemy);
		}
	}

	public function clearAllEnemies():Void {
		for (enemy in enemies) {
			if (enemy.parent != null) {
				enemy.parent.removeChild(enemy);
			}
		}
		enemies = new Array<Enemy>();

		// Stop all patterns
		for (pattern in enemyPatterns) {
			pattern.stopShooting();
		}
		enemyPatterns = new Array<EnemyShootingPattern>();
	}

	public function getEnemyCount():Int {
		return enemies.length;
	}

	public function getEnemies():Array<Enemy> {
		return enemies;
	}

	public function cleanupDeadEnemies():Void {
		// Remove dead enemies from tracking
		var i:Int = enemies.length - 1;
		while (i >= 0) {
			if (!enemies[i].isAlive()) {
				enemies.splice(i, 1);
			}
			i--;
		}
	}
}