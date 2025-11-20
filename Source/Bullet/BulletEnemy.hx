package bullet;

import openfl.Lib;
import openfl.events.Event;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.Assets;

class BulletEnemy extends Sprite {
	public static inline final ROTATION_SPEED:Float = 90.0; // Rotation speed in degrees per second

	public var velocityX:Float;
	public var velocityY:Float;

	private var spawnTime:Int = Lib.getTimer(); // To store the time of bullet spawn

	// Add a random salt to the rotation speed to make the bullet's rotation less uniform from other bullets
	private var salt:Float = Math.random() * 20; // gives a decimal between 0 inclusive and 10 exclusive

	public function new() {
		super();

		// Load the image from the assets folder
		var bitmapData:BitmapData = Assets.getBitmapData("assets/BulletEnemy.png");

		// Create a Bitmap using the loaded image
		var bitmap:Bitmap = new Bitmap(bitmapData);

		// Set the position of the sprite to its center
		bitmap.x = -bitmap.width / 2;
		bitmap.y = -bitmap.height / 2;

		// Add the Bitmap to the sprite
		addChild(bitmap);

		// Set the spawn time to the current time
		spawnTime = Lib.getTimer();

		// Register the "everyFrame" function to be called on every frame update
		addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	private function everyFrame(event:Event):Void {
		// Check if bullet was removed (e.g., by collision)
		if (parent == null) {
			removeEventListener(Event.ENTER_FRAME, everyFrame);
			return;
		}

		// Update the bullet's position based on its velocity
		x += velocityX;
		y += velocityY;

		// Get the width and height of the stage (window screen)
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		// Check if the bullet is out of the stage boundaries
		if (x < -100 || x > stageWidth + 100 || y < -100 || y > stageHeight + 100) {
			// Remove the bullet from the stage
			removeEventListener(Event.ENTER_FRAME, everyFrame);
			if (parent != null) {
				parent.removeChild(this);
			}
			return;
		}

		// Update the bullet's rotation based on the elapsed time since its spawn
		var currentTime:Int = Lib.getTimer();
		var deltaTime:Float = (currentTime - spawnTime) / 1000.0; // Convert milliseconds to seconds

		// Rotate the bullet
		// the salt adds between 0 and 10 degrees to the initial rotational position
		// delta position updates betwene every frame
		rotation = salt + (ROTATION_SPEED * deltaTime);
	}
}