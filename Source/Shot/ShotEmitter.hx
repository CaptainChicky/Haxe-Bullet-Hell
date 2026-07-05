package shot;

/** A point in space; used for aiming (e.g. the player's position). */
typedef ShotTarget = {
	var x:Float;
	var y:Float;
}

/**
 * Anything that can own a shot script and spawn bullets from prototypes.
 *
 * Enemies implement this via EnemyBulletEmitter; bullets implement it via
 * BulletSubEmitter, which is what lets a fired bullet run its own script and
 * fire further bullets (Touhou-style nesting) without the script engine
 * knowing anything about enemies, bullets, or display lists.
 */
interface IShotEmitter {
	/** World-space origin bullets are fired from (before prototype offset). */
	function getOriginX():Float;
	function getOriginY():Float;

	/** Current aim target (usually the player), or null if none exists. */
	function getTarget():ShotTarget;

	/** Materialize a cloned prototype as a live bullet at (x, y). */
	function spawn(prototype:ShotPrototype, x:Float, y:Float):Void;

	/** False once the owner is gone (enemy dead / bullet removed); the runner stops. */
	function isAlive():Bool;

	/**
	 * Remove the script's owner from play (the Vanish command). Meaningful for
	 * bullet-owned emitters (the bullet despawns itself mid-flight); a no-op
	 * for enemy emitters.
	 */
	function vanish():Void;
}
