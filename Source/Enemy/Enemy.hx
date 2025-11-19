package enemy;

import openfl.Lib;
import openfl.events.Event;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.Assets;

class Enemy extends Sprite {
	public static inline final ROTATION_SPEED:Float = -40.0; // Rotation speed in degrees per second

	private var spawnTime:Int = Lib.getTimer(); // To store the time of enemy spawn

	// Add a random salt to the rotation speed to make the enemy's rotation less uniform from other enemies
	private var salt:Float = Math.random() * 20; // gives a decimal between 0 inclusive and 10 exclusive

	// Health system
	private var maxHealth:Int;
	private var currentHealth:Int;

	// Reference to shooting pattern
	private var shootingPattern:EnemyShootingPattern;

	public function new(health:Int = 1) {
		super();

		this.maxHealth = health;
		this.currentHealth = health;

		// Load the image from the assets folder
		var bitmapData:BitmapData = Assets.getBitmapData("assets/Enemy.png");

		// Create a Bitmap using the loaded image
		var bitmap:Bitmap = new Bitmap(bitmapData);

		// Set the position of the sprite to its center
		bitmap.x = -bitmap.width / 2;
		bitmap.y = -bitmap.height / 2;

		// Add the Bitmap to the sprite
		addChild(bitmap);

		// Subscribe to the ENTER_FRAME event to call the everyFrame function on every frame update
		addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	public function setShootingPattern(pattern:EnemyShootingPattern):Void {
		this.shootingPattern = pattern;
	}

	public function takeDamage(damage:Int):Void {
		currentHealth -= damage;
		trace("Enemy hit! Health: " + currentHealth + "/" + maxHealth);

		if (currentHealth <= 0) {
			die();
		}
	}

	public function getHealth():Int {
		return currentHealth;
	}

	public function isAlive():Bool {
		return currentHealth > 0;
	}

	private function die():Void {
		trace("Enemy destroyed!");

		// Stop the shooting pattern
		if (shootingPattern != null) {
			shootingPattern.stopShooting();
		}

		removeEventListener(Event.ENTER_FRAME, everyFrame);
		if (parent != null) {
			parent.removeChild(this);
		}
	}

	private function everyFrame(event:Event):Void {
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