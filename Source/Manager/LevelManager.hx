package manager;

import manager.EnemyManager;
import manager.LevelData;
import openfl.Assets;
import openfl.events.Event;
import openfl.display.Sprite;
import openfl.Lib;
import haxe.Json;

class LevelManager extends Sprite {
	private var enemyManager:EnemyManager;
	private var currentLevel:LevelData;

	private var currentWaveIndex:Int = 0;
	private var levelStartTime:Float = 0;
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
		try {
			var levelJson:String = Assets.getText(levelPath);
			currentLevel = Json.parse(levelJson);
			trace("Loaded level: " + currentLevel.name);
			startLevel();
		} catch (e:Dynamic) {
			trace("Error loading level: " + e);
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
		levelStartTime = Lib.getTimer() / 1000.0;
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
		var currentTime:Float = Lib.getTimer() / 1000.0;
		var timeSinceLevelStart:Float = currentTime - levelStartTime;

		// Check if it's time to start this wave
		if (timeSinceLevelStart >= wave.startTime) {
			startWave(wave);
			currentWaveIndex++;

			// Recursively check for next wave (in case multiple waves have same start time)
			checkAndStartNextWave();
		}
	}

	private function startWave(wave:WaveData):Void {
		trace("Starting wave with " + wave.enemies.length + " enemy spawn(s)");
		waveStartTime = Lib.getTimer() / 1000.0;

		// Queue all enemy spawns for this wave
		for (enemySpawn in wave.enemies) {
			pendingSpawns.push({
				spawnData: enemySpawn,
				waveStartTime: waveStartTime
			});
		}
	}

	private function update(event:Event):Void {
		if (!isLevelActive && pendingSpawns.length == 0) {
			return;
		}

		var currentTime:Float = Lib.getTimer() / 1000.0;

		// Check if we should start a new wave
		if (isLevelActive) {
			checkAndStartNextWave();
		}

		// Process pending enemy spawns
		var i:Int = pendingSpawns.length - 1;
		while (i >= 0) {
			var pending = pendingSpawns[i];
			var timeSinceWaveStart:Float = currentTime - pending.waveStartTime;

			if (timeSinceWaveStart >= pending.spawnData.spawnTime) {
				// Spawn the enemy
				spawnEnemy(pending.spawnData);
				pendingSpawns.splice(i, 1);
			}
			i--;
		}
	}

	private function spawnEnemy(spawnData:EnemySpawnData):Void {
		var health:Int = (spawnData.health != null) ? spawnData.health : 1;
		trace("Spawning enemy at (" + spawnData.x + ", " + spawnData.y + ") with pattern: " + spawnData.pattern + ", health: " + health);
		enemyManager.spawnEnemy(
			spawnData.x,
			spawnData.y,
			spawnData.pattern,
			spawnData.patternConfig,
			health
		);
	}

	public function stopLevel():Void {
		isLevelActive = false;
		pendingSpawns = new Array();
		enemyManager.clearAllEnemies();
	}

	public function isActive():Bool {
		return isLevelActive || pendingSpawns.length > 0;
	}
}