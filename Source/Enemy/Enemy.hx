package enemy;

import openfl.Lib;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import manager.SpriteLibrary;
import enemy.MovementScript;
import shot.GhostOrigin.IMovable;

class Enemy extends Sprite implements IMovable {
	public static inline final ROTATION_SPEED:Float = -40.0; // Rotation speed in degrees per second

	private var spawnTime:Int = Lib.getTimer(); // To store the time of enemy spawn

	// Add a random salt to the rotation speed to make the enemy's rotation less uniform from other enemies
	private var salt:Float = Math.random() * 20; // gives a decimal between 0 inclusive and 10 exclusive

	// Health system
	private var maxHealth:Int;
	private var currentHealth:Int;

	/** Collision radius, cached at construction (see BulletEnemy.collisionRadius). */
	public var collisionRadius(default, null):Float = 0;

	// Reference to shooting pattern
	private var shootingPattern:EnemyShootingPattern;

	// Movement system
	private var velocityX:Float = 0;
	private var velocityY:Float = 0;
	private var movementScript:MovementScript;

	public function new(health:Int = 1, ?spriteName:String) {
		super();

		this.maxHealth = health;
		this.currentHealth = health;

		// Skin lookup: spriteName selects from the sprite manifest
		// (assets/sprites.json), or is a direct .png path drop-in.
		var resolved = SpriteLibrary.enemySprite(spriteName);
		var bitmapData:BitmapData = resolved.bitmapData;

		// Create a Bitmap using the loaded image
		var bitmap:Bitmap = new Bitmap(bitmapData);

		// Set the position of the sprite to its center
		bitmap.x = -bitmap.width / 2;
		bitmap.y = -bitmap.height / 2;

		// Add the Bitmap to the sprite
		addChild(bitmap);
		collisionRadius = Math.max(bitmapData.width, bitmapData.height) / 2;
		if (resolved.scale != 1) {
			setVisualScale(resolved.scale);
		}
	}

	/** Uniformly scale the sprite AND its cached collision radius (skin scale,
	 *  boss enlargement). Multiplies, so both can stack. Lives here because
	 *  collisionRadius is only writable from this class. */
	private function setVisualScale(factor:Float):Void {
		scaleX *= factor;
		scaleY *= factor;
		collisionRadius *= factor;
	}

	public function setShootingPattern(pattern:EnemyShootingPattern):Void {
		this.shootingPattern = pattern;
	}

	public function setVelocity(vx:Float, vy:Float):Void {
		this.velocityX = vx;
		this.velocityY = vy;
	}

	public function setMovementScript(script:MovementScript):Void {
		this.movementScript = script;
	}

	public function getMovementScript():MovementScript {
		return movementScript;
	}

	public function getVelocityX():Float {
		return velocityX;
	}

	public function getVelocityY():Float {
		return velocityY;
	}

	public function takeDamage(damage:Int):Void {
		currentHealth -= damage;

		if (currentHealth <= 0) {
			die();
		}
	}

	public function getHealth():Int {
		return currentHealth;
	}

	public function getMaxHealth():Int {
		return maxHealth;
	}

	public function isAlive():Bool {
		return currentHealth > 0;
	}

	private function die():Void {
		trace("Enemy destroyed!");

		// Off-screen removal reaches here with health remaining; zero it so
		// isAlive() is false on every death path (bound bullets key off it).
		currentHealth = 0;

		// Stop the shooting pattern
		if (shootingPattern != null) {
			shootingPattern.stopShooting();
		}

		if (parent != null) {
			parent.removeChild(this);
		}

		// After the enemy is fully dead (not drawn, not collidable, not
		// targetable), the pattern may stand up a ghost origin for any
		// offset-bound bullets still deriving position from this enemy.
		if (shootingPattern != null) {
			shootingPattern.onOwnerDied();
		}
	}

	/** Advance one frame. Driven centrally by EnemyManager (same reasoning as
	 *  bullets: self-removing ENTER_FRAME listeners skip neighbors mid-dispatch). */
	public function update():Void {
		if (!isAlive()) return;

		// Update movement script if it exists
		if (movementScript != null) {
			movementScript.update();
		}

		// Update movement
		x += velocityX;
		y += velocityY;

		// Get the width and height of the stage (window screen)
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		// Check if the enemy is out of the stage boundaries
		if (x < -100 || x > stageWidth + 100 || y < -100 || y > stageHeight + 100) {
			// Remove the enemy from the stage
			trace("Enemy moved off-screen, removing...");
			die();
			return;
		}

		// Update the enemy's rotation based on the elapsed time since the last frame
		// will rotate based on spawn time
		var currentTime:Int = Lib.getTimer();
		var deltaTime:Float = (currentTime - spawnTime) / 1000.0; // Convert milliseconds to seconds

		// Rotate the player
		// the salt adds between 0 and 10 degrees to the initial rotational position
		// delta position updates betwene every frame
		rotation = salt + (ROTATION_SPEED * deltaTime);
	}
}