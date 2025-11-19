package;

import manager.*;
import enemy.*;
import player.PlayerShootingPattern;
import player.Player;
import openfl.ui.Keyboard;
import openfl.events.KeyboardEvent;
import openfl.text.TextFormatAlign;
import openfl.text.TextFormat;
import openfl.text.TextField;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.Lib;

enum GameState {
	Paused;
	Playing;
}

class Main extends Sprite {
	var inited:Bool;

	private var stageWidth:Int;
	private var stageHeight:Int;

	private var player:Player;
	private var currentGameState:GameState;
	private var messageField:TextField;

	private var playerShootingPattern:PlayerShootingPattern;

	// Managers
	private var enemyManager:EnemyManager;
	private var levelManager:LevelManager;
	private var collisionManager:CollisionManager;

	/* ENTRY POINT */
	function resize(e) {
		if (!inited)
			init();
	}

	function init() {
		if (inited)
			return;
		inited = true;

		Lib.current.stage.color = 0xFFFFFF;

		stageWidth = Lib.current.stage.stageWidth;
		stageHeight = Lib.current.stage.stageHeight;

		// Create managers
		enemyManager = new EnemyManager();
		addChild(enemyManager); // Add to display tree so enemies are rendered

		// Create player with stage dimensions
		player = new Player(stageWidth, stageHeight);
		player.x = stageWidth / 2;
		player.y = stageHeight - player.height / 2 - 10;
		addChild(player);

		// Create level manager
		levelManager = new LevelManager(enemyManager);
		addChild(levelManager);

		// Create collision manager
		collisionManager = new CollisionManager(player, enemyManager);
		addChild(collisionManager);

		// Set collision manager for enemy patterns
		EnemyShootingPattern.setCollisionManager(collisionManager);

		// Set player death callback
		player.setOnDeathCallback(onPlayerDeath);

		var messageFormat:TextFormat = new TextFormat("Verdana", 18, 0xbbbbbb, true);
		messageFormat.align = TextFormatAlign.CENTER;
		messageField = new TextField();
		addChild(messageField);
		messageField.width = 500;
		messageField.y = stageHeight / 2 - messageField.height / 2;
		messageField.x = stageWidth / 2 - messageField.width / 2;
		messageField.defaultTextFormat = messageFormat;
		messageField.selectable = false;
		messageField.text = "Press SPACE to start\nUse ARROW KEYS to move";

		setGameState(Paused);

		stage.addEventListener(KeyboardEvent.KEY_DOWN, keyDown);
		stage.addEventListener(KeyboardEvent.KEY_UP, keyUp);

		playerShootingPattern = new PlayerShootingPattern(player, collisionManager);

		this.addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	private function setGameState(state:GameState):Void {
		currentGameState = state;

		if (state == Paused) {
			messageField.alpha = 1;
		} else {
			messageField.alpha = 0;

			// Start the level!
			levelManager.loadLevel("assets/levels/level1.json");
		}
	}

	private function keyDown(event:KeyboardEvent):Void {
		if (currentGameState == Paused && event.keyCode == Keyboard.SPACE) {
			setGameState(Playing);
		} else if (event.keyCode == Keyboard.UP) {
			player.setMoveUp(true);
		} else if (event.keyCode == Keyboard.DOWN) {
			player.setMoveDown(true);
		} else if (event.keyCode == Keyboard.LEFT) {
			player.setMoveLeft(true);
		} else if (event.keyCode == Keyboard.RIGHT) {
			player.setMoveRight(true);
		} else if (event.keyCode == 90) { // "z" key
			if (currentGameState == Playing) {
				playerShootingPattern.startShooting();
			}
		}
	}

	private function keyUp(event:KeyboardEvent):Void {
		if (event.keyCode == 38) { // Up
			player.setMoveUp(false);
		} else if (event.keyCode == 40) { // Down
			player.setMoveDown(false);
		} else if (event.keyCode == 37) { // Left
			player.setMoveLeft(false);
		} else if (event.keyCode == 39) { // Right
			player.setMoveRight(false);
		} else if (event.keyCode == 90) { // "z" key
			playerShootingPattern.stopShooting();
		}
	}

	private function onPlayerDeath():Void {
		trace("GAME OVER!");
		setGameState(Paused);

		// Update message field
		messageField.text = "GAME OVER\n\nPress SPACE to restart";
		messageField.alpha = 1;

		// Stop level and clear bullets
		levelManager.stopLevel();
		collisionManager.reset();

		// Stop player shooting
		playerShootingPattern.stopShooting();
	}

	private function everyFrame(event:Event):Void {
		if (currentGameState == Playing) {
			// Player handles its own movement and boundaries
			player.updateMovement();
		}
	}

	/* SETUP */
	public function new() {
		super();

		addEventListener(Event.ADDED_TO_STAGE, added);
	}

	function added(e) {
		removeEventListener(Event.ADDED_TO_STAGE, added);

		stage.addEventListener(Event.RESIZE, resize);
	}

	public static function main() {
		Lib.current.stage.align = openfl.display.StageAlign.TOP_LEFT;
		Lib.current.addChild(new Main());
	}
}