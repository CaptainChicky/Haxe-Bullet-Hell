package manager;

import enemy.*;
import enemy.MovementScript;
import enemy.ScriptedShootingPattern;
import manager.PatternLoader;
import shot.ShotCommand.IShotCommand;
import openfl.display.Sprite;
import openfl.events.Event;

class EnemyManager extends Sprite {
	/** Field-clear pause between boss phases before the next pattern opens. */
	private static inline final BOSS_TRANSITION_FRAMES:Int = 60;

	private var enemies:Array<Enemy>;
	private var enemyPatterns:Array<EnemyShootingPattern>;
	private var movementScripts:Array<MovementScript>;

	// Boss fight state (one boss at a time)
	private var activeBoss:BossEnemy = null;
	private var bossPattern:EnemyShootingPattern = null;
	private var bossSpriteName:String = null;
	private var bossTransitionFrames:Int = 0;

	public function new() {
		super();
		enemies = new Array<Enemy>();
		enemyPatterns = new Array<EnemyShootingPattern>();
		movementScripts = new Array<MovementScript>();
	}

	/**
	 * Advance all enemies, then all patterns, by one frame. Called from
	 * Main.everyFrame — enemies and patterns own no ENTER_FRAME listeners
	 * (self-removal during OpenFL's broadcast dispatch skips the next
	 * listener's update for a frame; see CollisionManager for the full story).
	 * All enemies move before any pattern fires, so a pattern always fires
	 * from its enemy's post-move position — same as the old listener order.
	 */
	public function update():Void {
		for (enemy in enemies) {
			enemy.update();
		}
		for (pattern in enemyPatterns) {
			pattern.update();
		}

		// Boss phase transition: short breather after the field clear, then
		// the next phase's pattern opens fire.
		if (bossTransitionFrames > 0) {
			bossTransitionFrames--;
			if (bossTransitionFrames == 0 && activeBoss != null && activeBoss.isAlive()) {
				startBossPhase(activeBoss, activeBoss.getPhaseIndex());
			}
		}
	}

	public function spawnEnemy(x:Float, y:Float, patternType:String, patternConfig:Dynamic, health:Int = 1, velocityX:Float = 0, velocityY:Float = 0, movementScriptData:Dynamic = null, ?spriteName:String):Enemy {
		var enemy:Enemy = new Enemy(GameSettings.scaleHealth(health), spriteName);
		enemy.x = x;
		enemy.y = y;
		enemy.setVelocity(velocityX, velocityY);
		addChild(enemy);
		enemies.push(enemy);

		// Create the shooting pattern based on type
		var pattern:EnemyShootingPattern = createPattern(enemy, patternType, patternConfig, spriteName);
		if (pattern != null) {
			enemyPatterns.push(pattern);

			// Link the pattern to the enemy
			enemy.setShootingPattern(pattern);

			// Auto-start shooting
			pattern.startShooting();
		}

		// Create and attach movement script if provided
		if (movementScriptData != null) {
			attachMovement(enemy, movementScriptData);
		}

		return enemy;
	}

	/** Attach (or replace) an enemy's movement script. */
	private function attachMovement(enemy:Enemy, scriptData:Dynamic):Void {
		var old = enemy.getMovementScript();
		if (old != null) {
			old.stop();
			movementScripts.remove(old);
		}
		var script:MovementScript = createMovementScript(enemy, scriptData);
		if (script != null) {
			movementScripts.push(script);
			enemy.setMovementScript(script);
			script.start();
		}
	}

	/**
	 * Spawn a multi-phase boss from a full EnemySpawnData carrying a `boss`
	 * block. The top-level movementScript is the entrance; each phase may
	 * replace it. Phase clears are driven by BossEnemy.onPhaseDepleted.
	 */
	public function spawnBoss(spawnData:Dynamic):BossEnemy {
		var boss = new BossEnemy(spawnData.boss, spawnData.sprite);
		boss.x = spawnData.x;
		boss.y = spawnData.y;
		boss.setVelocity(
			spawnData.velocityX != null ? spawnData.velocityX : 0,
			spawnData.velocityY != null ? spawnData.velocityY : 0
		);
		addChild(boss);
		enemies.push(boss);

		activeBoss = boss;
		bossSpriteName = spawnData.sprite;
		bossTransitionFrames = 0;

		if (spawnData.movementScript != null) {
			attachMovement(boss, spawnData.movementScript);
		}

		boss.onPhaseDepleted = function() {
			onBossPhaseDepleted(boss);
		};
		startBossPhase(boss, 0);
		return boss;
	}

	private function startBossPhase(boss:BossEnemy, index:Int):Void {
		var phase = boss.getPhase(index);

		var cfg:Dynamic = (phase.patternConfig != null) ? phase.patternConfig : {};
		if (phase.script != null) {
			cfg.patternScript = {actions: phase.script};
		}
		var patternName:String = (phase.pattern != null) ? phase.pattern : "inline";

		var pattern = createPattern(boss, patternName, cfg, bossSpriteName);
		if (pattern != null) {
			enemyPatterns.push(pattern);
			boss.setShootingPattern(pattern);
			pattern.startShooting();
			bossPattern = pattern;
		}

		if (phase.movementScript != null) {
			attachMovement(boss, phase.movementScript);
		}
	}

	private function onBossPhaseDepleted(boss:BossEnemy):Void {
		// Silence the guns and wipe the field before anything else happens
		if (bossPattern != null) {
			bossPattern.stopShooting();
			enemyPatterns.remove(bossPattern);
			bossPattern = null;
		}
		var collisionManager = EnemyShootingPattern.getCollisionManager();
		if (collisionManager != null) {
			collisionManager.clearEnemyBullets();
		}

		if (boss.getPhaseIndex() >= boss.getPhaseCount() - 1) {
			// Last phase cleared: the boss is done
			activeBoss = null;
			boss.defeat();
			return;
		}

		boss.startNextPhase(); // grants transition invincibility
		bossTransitionFrames = BOSS_TRANSITION_FRAMES;
	}

	/** The live boss, or null when no boss fight is running. */
	public function getActiveBoss():BossEnemy {
		return (activeBoss != null && activeBoss.isAlive()) ? activeBoss : null;
	}

	private function createPattern(enemy:Enemy, patternType:String, config:Dynamic, ?spriteName:String):EnemyShootingPattern {
		var patternName = patternType.toLowerCase();
		var commands:Array<IShotCommand> = null;

		// Check if inline script is provided
		if (config.patternScript != null && config.patternScript.actions != null) {
			// Compile inline script directly from level JSON (handles startDelay in config)
			commands = PatternLoader.parseInline(config.patternScript.actions, config);
		} else {
			// Try loading from pattern template file
			commands = PatternLoader.parsePattern(patternName, config);
		}

		// Create scripted pattern if we have commands
		if (commands != null && commands.length > 0) {
			var collisionManager = EnemyShootingPattern.getCollisionManager();
			// Bosses fire visibly bigger bullets by default
			var bulletSize:Float = Std.isOfType(enemy, BossEnemy) ? BossEnemy.BULLET_SIZE : 1;
			var pattern = new ScriptedShootingPattern(enemy, commands, collisionManager, spriteName, bulletSize);
			return pattern;
		}

		trace("Pattern not found and no inline script provided: " + patternType);
		return null;
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

		// Any boss fight in progress is over
		activeBoss = null;
		bossPattern = null;
		bossSpriteName = null;
		bossTransitionFrames = 0;
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