package manager;

import enemy.*;
import enemy.MovementScript;
import openfl.display.Sprite;
import openfl.events.Event;

class EnemyManager extends Sprite {
	private var enemies:Array<Enemy>;
	private var enemyPatterns:Array<EnemyShootingPattern>;
	private var movementScripts:Array<MovementScript>;

	public function new() {
		super();
		enemies = new Array<Enemy>();
		enemyPatterns = new Array<EnemyShootingPattern>();
		movementScripts = new Array<MovementScript>();
	}

	public function spawnEnemy(x:Float, y:Float, patternType:String, patternConfig:Dynamic, health:Int = 1, velocityX:Float = 0, velocityY:Float = 0, movementScriptData:Dynamic = null):Enemy {
		var enemy:Enemy = new Enemy(health);
		enemy.x = x;
		enemy.y = y;
		enemy.setVelocity(velocityX, velocityY);
		addChild(enemy);
		enemies.push(enemy);

		// Create the shooting pattern based on type
		var pattern:EnemyShootingPattern = createPattern(enemy, patternType, patternConfig);
		if (pattern != null) {
			enemyPatterns.push(pattern);

			// Link the pattern to the enemy
			enemy.setShootingPattern(pattern);

			// Set bullet spawn interval if provided
			if (patternConfig.bulletSpawnInterval != null) {
				pattern.setBulletSpawnInterval(patternConfig.bulletSpawnInterval);
			}

			// Auto-start shooting
			pattern.startShooting();
		}

		// Create and attach movement script if provided
		if (movementScriptData != null) {
			var movementScript:MovementScript = createMovementScript(enemy, movementScriptData);
			if (movementScript != null) {
				movementScripts.push(movementScript);
				enemy.setMovementScript(movementScript);
				movementScript.start();
			}
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

	private function createMovementScript(enemy:Enemy, scriptData:Dynamic):MovementScript {
		if (scriptData == null || scriptData.actions == null) {
			return null;
		}

		var loop:Bool = scriptData.loop != null ? scriptData.loop : false;
		var script:MovementScript = new MovementScript(enemy, loop);

		// Parse each action
		var actions:Array<Dynamic> = scriptData.actions;
		for (actionData in actions) {
			var actionType:String = actionData.type;

			switch (actionType) {
				case "SetVelocity":
					var vx:Float = actionData.vx != null ? actionData.vx : 0;
					var vy:Float = actionData.vy != null ? actionData.vy : 0;
					script.addAction(SetVelocity(vx, vy));

				case "Wait":
					var frames:Int = actionData.frames != null ? actionData.frames : 0;
					script.addAction(Wait(frames));

				case "Stop":
					script.addAction(Stop);

				default:
					trace("Unknown movement action type: " + actionType);
			}
		}

		return script;
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

		// Stop all movement scripts
		for (script in movementScripts) {
			script.stop();
		}
		movementScripts = new Array<MovementScript>();
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

	public function stopAllShooting():Void {
		// Stop all enemy patterns from shooting without removing enemies
		for (pattern in enemyPatterns) {
			pattern.stopShooting();
		}
	}

	public function pauseAllMovementScripts():Void {
		// Pause all movement scripts (stops enemy movement)
		for (script in movementScripts) {
			script.pause();
		}
	}

	public function resumeAllMovementScripts():Void {
		// Resume all movement scripts
		for (script in movementScripts) {
			script.resume();
		}
	}
}