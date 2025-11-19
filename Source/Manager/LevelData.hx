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
	@:optional var health:Int; // Enemy health (defaults to 1 if not specified)
	@:optional var velocityX:Float; // X velocity (pixels per frame, defaults to 0)
	@:optional var velocityY:Float; // Y velocity (pixels per frame, defaults to 0)
	@:optional var movementScript:MovementScriptData; // Scripted movement pattern
}

typedef MovementScriptData = {
	@:optional var loop:Bool; // Whether to loop the script (defaults to false)
	var actions:Array<MovementActionData>; // List of movement actions
}

typedef MovementActionData = {
	var type:String; // "SetVelocity", "Wait", or "Stop"
	@:optional var vx:Float; // X velocity for SetVelocity
	@:optional var vy:Float; // Y velocity for SetVelocity
	@:optional var frames:Int; // Frame count for Wait
}