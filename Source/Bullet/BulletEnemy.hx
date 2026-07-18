package bullet;

import shot.GhostOrigin;
import shot.GhostOrigin.IGhostAnchor;
import shot.ShotPrototype;
import shot.ScriptRunner;
import shot.ShotEmitter.IShotEmitter;
import openfl.Lib;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.Assets;

/**
 * An enemy bullet, constructed from a cloned ShotPrototype.
 *
 * The prototype defines the bullet's whole flight profile: direction, speed,
 * per-frame acceleration and angular velocity (curving), speed clamps, and
 * lifetime. Bullets may also carry their own ScriptRunner (attached by the
 * emitter when the prototype has a sub-script), letting a bullet fire further
 * bullets after spawning.
 */
class BulletEnemy extends Sprite {
	public static inline final ROTATION_SPEED:Float = 90.0; // Sprite spin, degrees per second (visual only)

	/** Cached textures - one per bullet variant. */
	private static var cachedBitmapData:BitmapData = null;
	private static var cachedBitmapData2:BitmapData = null;

	// Kept public for compatibility with any external velocity reads.
	public var velocityX:Float = 0;
	public var velocityY:Float = 0;

	// Flight state (from prototype).
	private var direction:Float; // degrees
	private var speed:Float; // px/frame
	private var accel:Float;
	private var angularVelocity:Float;
	private var minSpeed:Float;
	private var maxSpeed:Float;
	private var lifetime:Float; // frames; <= 0 means unlimited
	private var age:Float = 0;

	/** Optional script this bullet runs itself (nested patterns). */
	private var script:ScriptRunner = null;

	/** Which bullet sprite variant this bullet (and its children) use. */
	public var bulletSprite:String = null;

	/** Collision radius, cached at construction. Reading width/height on a
	 *  display object recomputes transformed bounds every call — far too
	 *  expensive per bullet per frame on native. */
	public var collisionRadius(default, null):Float = 0;

	/** Set once this bullet has been graze-scored (one graze per bullet). */
	public var grazed:Bool = false;

	// --- Binding (see ShotPrototype.bindMode) --------------------------------
	private var bindMode:Int = ShotPrototype.BIND_NONE;
	private var bindAnchor:IShotEmitter = null; // parent position/liveness source
	private var bindSource:ShotPrototype = null; // parent's live prototype (full mode)
	private var anchorLastX:Float = 0;
	private var anchorLastY:Float = 0;
	private var ghostOrigin:GhostOrigin = null; // dead parent's ghost (offset mode)
	private var bindRetained:Bool = false; // holds a refcount on the anchor

	private var spawnTime:Int = Lib.getTimer();

	// Random salt so bullet sprite spin isn't uniform across bullets.
	private var salt:Float = Math.random() * 20;

	public function new(?prototype:ShotPrototype, ?bulletSpriteVariant:String) {
		super();

		if (prototype == null) prototype = new ShotPrototype();
		direction = prototype.direction;
		speed = prototype.speed;
		accel = prototype.accel;
		angularVelocity = prototype.angularVelocity;
		minSpeed = prototype.minSpeed;
		maxSpeed = prototype.maxSpeed;
		lifetime = prototype.lifetime;
		bulletSprite = bulletSpriteVariant;
		updateVelocity();

		var bmd:BitmapData;
		if (bulletSpriteVariant == "enemy2") {
			if (cachedBitmapData2 == null)
				cachedBitmapData2 = Assets.getBitmapData("assets/BulletEnemy(second).png");
			bmd = cachedBitmapData2;
		} else {
			if (cachedBitmapData == null)
				cachedBitmapData = Assets.getBitmapData("assets/BulletEnemy.png");
			bmd = cachedBitmapData;
		}
		var bitmap:Bitmap = new Bitmap(bmd);
		bitmap.x = -bitmap.width / 2;
		bitmap.y = -bitmap.height / 2;
		addChild(bitmap);
		collisionRadius = Math.max(bmd.width, bmd.height) / 2;

		spawnTime = Lib.getTimer();
	}

	/** Attach a script this bullet runs on its own (called by the emitter). */
	public function attachScript(runner:ScriptRunner):Void {
		this.script = runner;
	}

	/** Bind this bullet to its parent (called by the emitter at spawn).
	 *  anchor provides live parent position + liveness; source is the parent
	 *  script's live prototype (used by BIND_FULL). */
	public function bindTo(anchor:IShotEmitter, mode:Int, source:ShotPrototype):Void {
		bindAnchor = anchor;
		bindMode = mode;
		bindSource = source;
		anchorLastX = anchor.getOriginX();
		anchorLastY = anchor.getOriginY();
		// Offset-bound bullets never integrate their own velocity, so the
		// anchor must outlive its owner as a ghost origin: refcount while bound.
		if (mode == ShotPrototype.BIND_OFFSET && Std.isOfType(anchor, IGhostAnchor)) {
			cast(anchor, IGhostAnchor).retainBound();
			bindRetained = true;
		}
	}

	private function releaseBind():Void {
		if (bindRetained) {
			bindRetained = false;
			cast(bindAnchor, IGhostAnchor).releaseBound();
		}
	}

	private inline function updateVelocity():Void {
		var rad = direction * Math.PI / 180;
		velocityX = Math.cos(rad) * speed;
		velocityY = Math.sin(rad) * speed;
	}

	/** Advance one frame. Driven centrally by CollisionManager (bullets must
	 *  never own ENTER_FRAME listeners: self-removal during the broadcast
	 *  dispatch skips the next listener's update — the "lagging bullet" bug). */
	public function update():Void {
		// Check if bullet was removed (e.g., by collision)
		if (parent == null) {
			releaseBind();
			return;
		}

		// Run the bullet's own script (if any) before moving, then sync flight
		// state FROM the script's live prototype: a sub-script that mutates
		// direction/speed/... mid-flight (e.g. shifter's delayed Add) must
		// steer this bullet, not just the prototype of bullets it fires next.
		if (script != null) {
			script.update();

			// The script may have despawned this bullet (Vanish command).
			if (parent == null) {
				releaseBind();
				return;
			}

			// In BIND_FULL mode the parent's live prototype owns flight
			// state (bind wins); the bullet's own script can still fire
			// children or Vanish, but cannot steer.
			if (bindMode != ShotPrototype.BIND_FULL) {
				var proto = (script != null) ? script.getPrototype() : null;
				if (proto != null) {
					direction = proto.direction;
					speed = proto.speed;
					accel = proto.accel;
					angularVelocity = proto.angularVelocity;
					minSpeed = proto.minSpeed;
					maxSpeed = proto.maxSpeed;
				}
			}
		}

		// Bound bullets follow their parent.
		var bindDX:Float = 0;
		var bindDY:Float = 0;
		if (bindAnchor != null) {
			if (!bindAnchor.isAlive()) {
				// Parent died. Offset-bound bullets retarget their origin to
				// the parent's ghost (see shot.GhostOrigin) and stay bound so
				// the pattern keeps running; everything else orphan-releases:
				// keep current state, continue as a normal independent bullet.
				if (ghostOrigin == null && bindMode == ShotPrototype.BIND_OFFSET && Std.isOfType(bindAnchor, IGhostAnchor)) {
					ghostOrigin = cast(bindAnchor, IGhostAnchor).getGhost();
				}
				if (ghostOrigin == null) {
					releaseBind();
					bindAnchor = null;
					bindSource = null;
					bindMode = ShotPrototype.BIND_NONE;
				} else if (ghostOrigin.expired) {
					// Ghost hit maxOrphanFrames with this bullet still bound:
					// force-resolve by vanishing (no immortal bullets).
					despawn();
					return;
				}
			} else {
				if (bindMode == ShotPrototype.BIND_FULL && bindSource != null) {
					direction = bindSource.direction;
					speed = bindSource.speed;
					accel = bindSource.accel;
					angularVelocity = bindSource.angularVelocity;
					minSpeed = bindSource.minSpeed;
					maxSpeed = bindSource.maxSpeed;
				}
				var px = bindAnchor.getOriginX();
				var py = bindAnchor.getOriginY();
				bindDX = px - anchorLastX;
				bindDY = py - anchorLastY;
				anchorLastX = px;
				anchorLastY = py;
			}
		}

		// Apply in-flight prototype behavior unconditionally: the recompute
		// must happen every frame, not only when angularVelocity/accel are
		// nonzero, or purely script-driven direction changes never take effect.
		direction += angularVelocity;
		speed += accel;
		if (speed < minSpeed) speed = minSpeed;
		if (speed > maxSpeed) speed = maxSpeed;

		// Write the integrated state back so the prototype stays the single
		// source of truth: without this, the sync above would reset a curving
		// bullet's direction to the prototype's stale value every frame and
		// angularVelocity would stop accumulating (breaks flower's seeds).
		if (script != null) {
			var proto = script.getPrototype();
			if (proto != null) {
				proto.direction = direction;
				proto.speed = speed;
			}
		}
		updateVelocity();

		// BIND_OFFSET: position is directly parent + polar/cartesian offset from
		// the script's live prototype (no velocity integration). The sub-script
		// controls the bullet's position entirely by mutating offsetDistance/
		// offsetAngle (e.g. tweening outward, then adding angle to orbit).
		if (bindMode == ShotPrototype.BIND_OFFSET && bindAnchor != null && script != null) {
			var proto = script.getPrototype();
			if (proto != null) {
				var px = (ghostOrigin != null) ? ghostOrigin.x : bindAnchor.getOriginX();
				var py = (ghostOrigin != null) ? ghostOrigin.y : bindAnchor.getOriginY();
				if (proto.offsetDistance != 0) {
					var rad = proto.offsetAngle * Math.PI / 180;
					px += Math.cos(rad) * proto.offsetDistance;
					py += Math.sin(rad) * proto.offsetDistance;
				}
				px += proto.x;
				py += proto.y;
				x = px;
				y = py;
			}
		} else {
			x += velocityX + bindDX;
			y += velocityY + bindDY;
		}

		// Lifetime expiry.
		age += 1;
		if (lifetime > 0 && age >= lifetime) {
			despawn();
			return;
		}

		// Despawn outside stage boundaries.
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;
		if (x < -100 || x > stageWidth + 100 || y < -100 || y > stageHeight + 100) {
			despawn();
			return;
		}

		// Cosmetic sprite spin based on time since spawn.
		var deltaTime:Float = (Lib.getTimer() - spawnTime) / 1000.0;
		rotation = salt + (ROTATION_SPEED * deltaTime);
	}

	/** Public destroy hook (used by the Vanish command via BulletSubEmitter). */
	public function destroy():Void {
		despawn();
	}

	private function despawn():Void {
		releaseBind();
		if (script != null) {
			script.stop();
			script = null;
		}
		if (parent != null) {
			parent.removeChild(this);
		}
	}
}
