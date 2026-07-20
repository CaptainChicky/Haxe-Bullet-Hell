package bullet;

import enemy.Enemy;
import manager.EnemyManager;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.Assets;

class BulletPlayer extends Sprite {
	public static inline final ROTATION_SPEED:Float = 90.0; // Rotation speed in degrees per second

	/** Cached texture shared by all player bullets. */
	private static var cachedBitmapData:BitmapData = null;

	public var velocityX:Float;
	public var velocityY:Float;

	/** Damage dealt on hit; scales with the player's power level. */
	public var damage:Int = 1;

	/** Pierce shot: the bullet passes through enemies, damaging each once. */
	public var piercing:Bool = false;

	// Enemies this piercing bullet has already damaged (small, linear scan is fine)
	private var piercedEnemies:Array<Enemy> = null;

	/** Collision radius, cached at construction (see BulletEnemy.collisionRadius). */
	public var collisionRadius(default, null):Float = 0;

	// Homing (0 = straight flight). Set via enableHoming().
	private var homingTurnRate:Float = 0; // max steer, degrees per frame
	private var homingDirection:Float = 0; // current heading, degrees
	private var homingSpeed:Float = 0; // px per frame
	private var enemySource:EnemyManager = null;

	// Frames since spawn (drives cosmetic spin; freezes cleanly with pause)
	private var ageFrames:Int = 0;

	// Add a random salt to the rotation speed to make the bullet's rotation less uniform from other bullets
	private var salt:Float = Math.random() * 20; // gives a decimal between 0 inclusive and 10 exclusive

	public function new() {
		super();

		// Load the image from the assets folder
		if (cachedBitmapData == null)
			cachedBitmapData = Assets.getBitmapData("assets/BulletPlayer.png");
		var bitmapData:BitmapData = cachedBitmapData;

		// Create a Bitmap using the loaded image
		var bitmap:Bitmap = new Bitmap(bitmapData);

		// Set the position of the sprite to its center
		bitmap.x = -bitmap.width / 2;
		bitmap.y = -bitmap.height / 2;

		// Add the Bitmap to the sprite
		addChild(bitmap);
		collisionRadius = Math.max(bitmapData.width, bitmapData.height) / 2;
	}

	/** Has this piercing bullet already damaged the given enemy? */
	public function hasPierced(enemy:Enemy):Bool {
		return piercedEnemies != null && piercedEnemies.indexOf(enemy) >= 0;
	}

	/** Record an enemy as damaged so a piercing bullet hits it only once. */
	public function markPierced(enemy:Enemy):Void {
		if (piercedEnemies == null) piercedEnemies = [];
		piercedEnemies.push(enemy);
	}

	/** Make this bullet steer toward the nearest living enemy each frame.
	 *  Heading/speed are derived from the current velocity. */
	public function enableHoming(turnRate:Float, enemySource:EnemyManager):Void {
		this.homingTurnRate = turnRate;
		this.enemySource = enemySource;
		homingSpeed = Math.sqrt(velocityX * velocityX + velocityY * velocityY);
		homingDirection = Math.atan2(velocityY, velocityX) * 180 / Math.PI;
	}

	private function steerTowardNearestEnemy():Void {
		var nearest:Enemy = null;
		var nearestDistSq:Float = 1e18;
		for (enemy in enemySource.getEnemies()) {
			if (!enemy.isAlive()) continue;
			var dx = enemy.x - x;
			var dy = enemy.y - y;
			var distSq = dx * dx + dy * dy;
			if (distSq < nearestDistSq) {
				nearestDistSq = distSq;
				nearest = enemy;
			}
		}
		if (nearest == null) return; // nothing to chase: hold heading

		var desired = Math.atan2(nearest.y - y, nearest.x - x) * 180 / Math.PI;
		var delta = desired - homingDirection;
		// Wrap to [-180, 180] so we always turn the short way around
		while (delta > 180) delta -= 360;
		while (delta < -180) delta += 360;
		if (delta > homingTurnRate) delta = homingTurnRate;
		if (delta < -homingTurnRate) delta = -homingTurnRate;
		homingDirection += delta;

		var rad = homingDirection * Math.PI / 180;
		velocityX = Math.cos(rad) * homingSpeed;
		velocityY = Math.sin(rad) * homingSpeed;
	}

	/** Advance one frame. Driven centrally by CollisionManager (bullets must
	 *  never own ENTER_FRAME listeners: self-removal during the broadcast
	 *  dispatch skips the next listener's update — the "lagging bullet" bug). */
	public function update():Void {
		// Check if bullet was removed (e.g., by collision)
		if (parent == null) {
			return;
		}

		if (homingTurnRate != 0 && enemySource != null) {
			steerTowardNearestEnemy();
		}

		// Update the bullet's position based on its velocity
		x += velocityX;
		y += velocityY;

		// Get the width and height of the stage (window screen)
		// Fixed playfield, not live window size (see Enemy.update).
		var stageWidth:Int = Main.fieldWidth;
		var stageHeight:Int = Main.fieldHeight;

		// Check if the bullet is out of the stage boundaries
		if (x < -100 || x > stageWidth + 100 || y < -100 || y > stageHeight + 100) {
			// Remove the bullet from the stage
			if (parent != null) {
				parent.removeChild(this);
			}
			return;
		}

		// Cosmetic spin from frames alive
		// the salt adds between 0 and 10 degrees to the initial rotational position
		ageFrames++;
		rotation = salt + (ROTATION_SPEED * ageFrames / 60.0);
	}
}
