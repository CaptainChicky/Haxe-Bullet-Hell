package player;

import openfl.Lib;
import openfl.events.Event;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.Assets;

class Player extends Sprite {
	public static inline final ROTATION_SPEED:Float = 40.0; // Rotation speed in degrees per second

	private var spawnTime:Int = Lib.getTimer(); // To store the time of player spawn

	// Movement state
	private var moveUp:Bool = false;
	private var moveDown:Bool = false;
	private var moveLeft:Bool = false;
	private var moveRight:Bool = false;

	private var moveSpeed:Int = 5;

	// Boundary constraints
	private var stageWidth:Int;
	private var stageHeight:Int;

	// Spawn position
	private var spawnX:Float;
	private var spawnY:Float;

	// Health system
	private var health:Int = 1;
	private var alive:Bool = true;

	// Callback for game over
	private var onDeathCallback:Void->Void;

	public function new(stageWidth:Int, stageHeight:Int) {
		super();

		this.stageWidth = stageWidth;
		this.stageHeight = stageHeight;

		// Load the image from the assets folder
		var bitmapData:BitmapData = Assets.getBitmapData("assets/Player.png");

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

	public function setMoveUp(value:Bool):Void {
		moveUp = value;
	}

	public function setMoveDown(value:Bool):Void {
		moveDown = value;
	}

	public function setMoveLeft(value:Bool):Void {
		moveLeft = value;
	}

	public function setMoveRight(value:Bool):Void {
		moveRight = value;
	}

	public function setOnDeathCallback(callback:Void->Void):Void {
		this.onDeathCallback = callback;
	}

	public function setSpawnPosition(x:Float, y:Float):Void {
		this.spawnX = x;
		this.spawnY = y;
	}

	public function respawn():Void {
		trace("Player respawned!");
		health = 1;
		alive = true;

		// Make player visible again
		this.visible = true;

		// Reset to spawn position
		this.x = spawnX;
		this.y = spawnY;

		// Reset movement flags
		moveUp = false;
		moveDown = false;
		moveLeft = false;
		moveRight = false;
	}

	public function takeDamage(damage:Int):Void {
		if (!alive) return;

		health -= damage;
		trace("Player hit! Health: " + health);

		if (health <= 0) {
			die();
		}
	}

	public function isAlive():Bool {
		return alive;
	}

	private function die():Void {
		trace("Player died!");
		alive = false;

		// Make player invisible
		this.visible = false;

		// Reset movement flags to prevent stuck inputs
		moveUp = false;
		moveDown = false;
		moveLeft = false;
		moveRight = false;

		// Trigger game over callback
		if (onDeathCallback != null) {
			onDeathCallback();
		}
	}

	public function updateMovement():Void {
		if (!alive) return; // Can't move if dead

		if (moveUp) {
			y -= moveSpeed;
		}

		if (moveDown) {
			y += moveSpeed;
		}

		if (moveLeft) {
			x -= moveSpeed;
		}

		if (moveRight) {
			x += moveSpeed;
		}

		// Enforce boundaries
		if (y < height / 2) {
			y = height / 2;
		}

		if (y > stageHeight - height / 2 - 10) {
			y = stageHeight - height / 2 - 10;
		}

		if (x < width / 2) {
			x = width / 2;
		}

		if (x > stageWidth - width / 2 - 10) {
			x = stageWidth - width / 2 - 10;
		}
	}

	private function everyFrame(event:Event):Void {
		// Update the player's rotation based on the elapsed time since the last frame
		// will rotate based on spawn time
		var currentTime:Int = Lib.getTimer();
		var deltaTime:Float = (currentTime - spawnTime) / 1000.0;  // Convert milliseconds to seconds

		// Rotate the player
		rotation = ROTATION_SPEED * deltaTime;
	}
}