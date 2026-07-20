package manager;

// Type definitions for level data structures

typedef LevelData = {
	var name:String;
	var waves:Array<WaveData>;
	@:optional var dialogue:DialogueData; // Conversations played around the stage
}

typedef DialogueData = {
	@:optional var intro:Array<DialogueEntryData>; // Before the first wave spawns
	@:optional var outro:Array<DialogueEntryData>; // After the stage is cleared
}

typedef DialogueEntryData = {
	var speaker:String; // Display name shown above the text box
	var text:String; // Body text (typewritten)
	@:optional var portrait:String; // Asset path, e.g. "assets/Player.png"
	@:optional var side:String; // "left" (default) or "right" portrait placement
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
	@:optional var sprite:String; // Skin name from assets/sprites.json ("enemy2", ...) or a direct .png path; null/absent = default art
	@:optional var boss:BossData; // Present = spawn a multi-phase boss instead of a regular enemy
}

typedef BossData = {
	@:optional var name:String; // Shown on the boss health bar
	var phases:Array<BossPhaseData>; // Fought in order; clearing the last one kills the boss
}

typedef BossPhaseData = {
	@:optional var name:String; // Spell card name shown on the boss bar
	var health:Int; // Damage needed to clear this phase
	@:optional var timeoutFrames:Null<Int>; // Phase auto-clears (no drops) after this many frames; absent = no timeout
	@:optional var pattern:String; // Pattern template name (Assets/patterns/<name>.json)
	@:optional var patternConfig:Dynamic; // Parameters for the pattern / inline script
	@:optional var script:Array<Dynamic>; // Inline shot script actions (instead of pattern)
	@:optional var movementScript:MovementScriptData; // Replaces the boss's movement for this phase
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
