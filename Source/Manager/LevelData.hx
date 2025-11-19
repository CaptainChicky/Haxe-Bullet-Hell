package manager;

// Type definitions for level data structures

typedef LevelData = {
	var name:String;
	var waves:Array<WaveData>;
}

typedef WaveData = {
	var startTime:Float; // Time in seconds when this wave starts
	var enemies:Array<EnemySpawnData>;
}

typedef EnemySpawnData = {
	var spawnTime:Float; // Time in seconds relative to wave start
	var x:Float;
	var y:Float;
	var pattern:String; // "spiral", "nwhip", etc.
	var patternConfig:Dynamic; // Configuration for the pattern
}
