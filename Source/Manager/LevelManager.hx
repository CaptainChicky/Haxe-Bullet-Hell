package manager;

import manager.EnemyManager;
import manager.LevelData;
import openfl.events.Event;
import openfl.display.Sprite;
import openfl.Lib;
import haxe.Json;

class LevelManager extends Sprite {
	private var enemyManager:EnemyManager;
	private var currentLevel:LevelData;

	// Level clock in seconds, accumulated from unpaused frames — never wall
	// clock. Wall clock kept ticking through pause/minimize, so waves and
	// spawns skipped ahead by the pause length on resume; frame time makes an
	// ESC pause and a focus-loss pause exactly equivalent (both freeze it).
	private static inline final FRAME_SECONDS:Float = 1.0 / 60.0;

	private var currentWaveIndex:Int = 0;
	private var levelTime:Float = 0;
	private var waveStartTime:Float = 0;

	private var pendingSpawns:Array<{spawnData:EnemySpawnData, waveStartTime:Float}>;

	private var isLevelActive:Bool = false;

	public function new(enemyManager:EnemyManager) {
		super();
		this.enemyManager = enemyManager;
		this.pendingSpawns = new Array();

		addEventListener(Event.ENTER_FRAME, update);
	}

	public function loadLevel(levelPath:String):Void {
		if (prepare(levelPath) != null) {
			startPrepared();
		}
	}

	/** Parse and store level data WITHOUT starting the waves. Lets the stage
	 *  flow read metadata (e.g. dialogue) and play intro conversations before
	 *  any enemy spawns. Returns null on load failure. */
	public function prepare(levelPath:String):LevelData {
		try {
			// Release builds ship the sealed .dat form; SecureAssets picks it.
			var levelJson:String = SecureAssets.getText(levelPath);
			if (levelJson == null) throw "asset not found: " + levelPath;
			currentLevel = Json.parse(levelJson);
			trace("Loaded level: " + currentLevel.name);
			return currentLevel;
		} catch (e:Dynamic) {
			trace("Error loading level: " + e);
			currentLevel = null;
			return null;
		}
	}

	/** Start the waves of a previously prepare()d level. */
	public function startPrepared():Void {
		if (currentLevel != null) {
			startLevel();
		}
	}

	public function loadLevelFromString(levelJson:String):Void {
		try {
			currentLevel = Json.parse(levelJson);
			trace("Loaded level: " + currentLevel.name);
			startLevel();
		} catch (e:Dynamic) {
			trace("Error parsing level JSON: " + e);
		}
	}

	private function startLevel():Void {
		if (currentLevel == null || currentLevel.waves == null || currentLevel.waves.length == 0) {
			trace("No valid level data to start");
			return;
		}

		currentWaveIndex = 0;
		levelTime = 0;
		isLevelActive = true;
		pendingSpawns = new Array();

		trace("Starting level with " + currentLevel.waves.length + " wave(s)");

		// Queue up the first wave
		checkAndStartNextWave();
	}

	private function checkAndStartNextWave():Void {
		if (currentWaveIndex >= currentLevel.waves.length) {
			trace("All waves completed!");
			isLevelActive = false;
			return;
		}

		var wave:WaveData = currentLevel.waves[currentWaveIndex];

		// Check if it's time to start this wave
		if (levelTime >= wave.startTime) {
			startWave(wave);
			currentWaveIndex++;

			// Recursively check for next wave (in case multiple waves have same start time)
			checkAndStartNextWave();
		}
	}

	private function startWave(wave:WaveData):Void {
		trace("Starting wave with " + wave.enemies.length + " enemy spawn(s)");
		waveStartTime = levelTime;

		// Queue all enemy spawns for this wave
		for (enemySpawn in wave.enemies) {
			pendingSpawns.push({
				spawnData: enemySpawn,
				waveStartTime: waveStartTime
			});
		}
	}

	private function update(event:Event):Void {
		if (Main.gamePaused) return;

		if (!isLevelActive && pendingSpawns.length == 0) {
			return;
		}

		levelTime += FRAME_SECONDS;

		// Check if we should start a new wave
		if (isLevelActive) {
			checkAndStartNextWave();
		}

		// Process pending enemy spawns
		var i:Int = pendingSpawns.length - 1;
		while (i >= 0) {
			var pending = pendingSpawns[i];
			var timeSinceWaveStart:Float = levelTime - pending.waveStartTime;

			if (timeSinceWaveStart >= pending.spawnData.spawnTime) {
				// Spawn the enemy
				spawnEnemy(pending.spawnData);
				pendingSpawns.splice(i, 1);
			}
			i--;
		}
	}

	private function spawnEnemy(spawnData:EnemySpawnData):Void {
		if (spawnData.boss != null) {
			trace("Spawning boss at (" + spawnData.x + ", " + spawnData.y + ") with "
				+ spawnData.boss.phases.length + " phase(s)");
			enemyManager.spawnBoss(spawnData);
			return;
		}

		var health:Int = (spawnData.health != null) ? spawnData.health : 1;
		var vx:Float = (spawnData.velocityX != null) ? spawnData.velocityX : 0;
		var vy:Float = (spawnData.velocityY != null) ? spawnData.velocityY : 0;
		var sprite:String = spawnData.sprite;
		trace("Spawning enemy at (" + spawnData.x + ", " + spawnData.y + ") with pattern: " + spawnData.pattern + ", health: " + health + ", velocity: (" + vx + ", " + vy + ")");
		enemyManager.spawnEnemy(
			spawnData.x,
			spawnData.y,
			spawnData.pattern,
			spawnData.patternConfig,
			health,
			vx,
			vy,
			spawnData.movementScript,
			sprite
		);
	}

	public function stopLevel():Void {
		isLevelActive = false;
		pendingSpawns = new Array();
		// Don't clear enemies - just stop wave progression
	}

	public function isActive():Bool {
		return isLevelActive || pendingSpawns.length > 0;
	}
}
