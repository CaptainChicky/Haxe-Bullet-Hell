package shot;

/** Anything a MovementScript can drive (an Enemy, or a GhostOrigin after death). */
interface IMovable {
	function setVelocity(vx:Float, vy:Float):Void;
}

/**
 * Implemented by emitters whose owner can die while offset-bound bullets are
 * still deriving their position from it (EnemyBulletEmitter, and the test
 * fakes). Bound bullets retain/release a refcount over their bound lifetime;
 * the display side creates the ghost at owner death and the anchor drops it
 * once the refcount returns to zero.
 */
interface IGhostAnchor {
	/** Called by a bullet when it offset-binds to this anchor. */
	function retainBound():Void;

	/** Called by a bullet when it despawns or unbinds. Drops the ghost at 0. */
	function releaseBound():Void;

	/** The ghost origin standing in for the dead owner, or null if none. */
	function getGhost():GhostOrigin;
}

/**
 * "Ghost parent": a pure coordinate origin that survives its owner's death so
 * offset-bound bullets (position derived from parent_origin + offset every
 * frame, never integrating their own velocity) keep deriving position and run
 * their patterns to completion instead of freezing in place forever.
 *
 * The owner is fully dead the moment it dies - not drawn, not collidable, not
 * targetable; only this origin survives. The ghost keeps advancing the owner's
 * last velocity (and its MovementScript, retargeted here with loop forced off)
 * so orbit chains and pods drift off-screen to their intended despawn. If the
 * origin never leaves the screen, maxOrphanFrames caps the orphan's life:
 * `expired` flips and bound bullets force-vanish - no bullet is ever immortal.
 */
class GhostOrigin implements IMovable {
	public static inline final DEFAULT_MAX_ORPHAN_FRAMES:Int = 60; // 1s @ 60fps

	public var x:Float;
	public var y:Float;
	public var velocityX:Float;
	public var velocityY:Float;

	/** Frames the ghost may live before force-vanishing its bullets. */
	public var maxOrphanFrames(default, null):Int;

	/** True once maxOrphanFrames elapsed; bound bullets must vanish. */
	public var expired(default, null):Bool = false;

	private var age:Int = 0;

	public function new(x:Float, y:Float, velocityX:Float = 0, velocityY:Float = 0, maxOrphanFrames:Int = DEFAULT_MAX_ORPHAN_FRAMES) {
		this.x = x;
		this.y = y;
		this.velocityX = velocityX;
		this.velocityY = velocityY;
		this.maxOrphanFrames = maxOrphanFrames;
	}

	public function setVelocity(vx:Float, vy:Float):Void {
		velocityX = vx;
		velocityY = vy;
	}

	/** Advance one frame: integrate velocity, age toward the safety cap. */
	public function tick():Void {
		if (expired) return;
		x += velocityX;
		y += velocityY;
		age++;
		if (age >= maxOrphanFrames) expired = true;
	}
}
