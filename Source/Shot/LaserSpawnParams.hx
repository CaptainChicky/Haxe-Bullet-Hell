package shot;

/**
 * Parameters for a single enemy laser beam (FireLaser / spawnLaser).
 * Binding fields are wired by ScriptRunner.fireLaser from the firing prototype.
 */
typedef LaserSpawnParams = {
	var angle:Float;
	var length:Float;
	var width:Float;
	var telegraphFrames:Int;
	var activeFrames:Int;
	var shutdownFrames:Int;
	var extendFrames:Int;
	/** Beam rotation in degrees per frame (sweep lasers). */
	var angularVelocity:Float;
	var bindMode:Int;
	var bindSource:ShotPrototype;
}
