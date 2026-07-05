package bullet;

import shot.ShotPrototype;
import shot.ScriptRunner;
import openfl.Lib;
import openfl.events.Event;
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

	/** Cached texture - loading BitmapData per bullet was a per-spawn cost. */
	private static var cachedBitmapData:BitmapData = null;

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

	private var spawnTime:Int = Lib.getTimer();

	// Random salt so bullet sprite spin isn't uniform across bullets.
	private var salt:Float = Math.random() * 20;

	public function new(?prototype:ShotPrototype) {
		super();

		if (prototype == null) prototype = new ShotPrototype();
		direction = prototype.direction;
		speed = prototype.speed;
		accel = prototype.accel;
		angularVelocity = prototype.angularVelocity;
		minSpeed = prototype.minSpeed;
		maxSpeed = prototype.maxSpeed;
		lifetime = prototype.lifetime;
		updateVelocity();

		if (cachedBitmapData == null) {
			cachedBitmapData = Assets.getBitmapData("assets/BulletEnemy.png");
		}
		var bitmap:Bitmap = new Bitmap(cachedBitmapData);
		bitmap.x = -bitmap.width / 2;
		bitmap.y = -bitmap.height / 2;
		addChild(bitmap);

		spawnTime = Lib.getTimer();

		addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	/** Attach a script this bullet runs on its own (called by the emitter). */
	public function attachScript(runner:ScriptRunner):Void {
		this.script = runner;
	}

	private inline function updateVelocity():Void {
		var rad = direction * Math.PI / 180;
		velocityX = Math.cos(rad) * speed;
		velocityY = Math.sin(rad) * speed;
	}

	private function everyFrame(event:Event):Void {
		// Check if bullet was removed (e.g., by collision)
		if (parent == null) {
			removeEventListener(Event.ENTER_FRAME, everyFrame);
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
				removeEventListener(Event.ENTER_FRAME, everyFrame);
				return;
			}

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

		x += velocityX;
		y += velocityY;

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
		removeEventListener(Event.ENTER_FRAME, everyFrame);
		if (script != null) {
			script.stop();
			script = null;
		}
		if (parent != null) {
			parent.removeChild(this);
		}
	}
}
