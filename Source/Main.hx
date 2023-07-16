package;

import enemy.*;
import player.PlayerShootingPattern;
import enemy.Enemy;
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
	private var enemy:Enemy;

	private var currentGameState:GameState;
	private var messageField:TextField;

	private var arrowKeyUp:Bool;
	private var arrowKeyDown:Bool;
	private var arrowKeyLeft:Bool;
	private var arrowKeyRight:Bool;

	private var playerAxisSpeed:Int;

	private var previousTime:Int = 0;
	private var currentTime:Int;
	private var deltaTime:Float;

	private var spiralEnemyShootingPattern:SpiralEnemyShootingPattern;
	private var nWhipEnemyShootingPattern:NWhipEnemyShootingPattern;
	private var playerShootingPattern:PlayerShootingPattern;

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

		player = new Player();
		player.x = stageWidth / 2;
		player.y = stageHeight - player.height / 2 - 10;
		addChild(player);

		enemy = new Enemy();
		enemy.x = stageWidth / 2;
		enemy.y = 10 + enemy.height / 2;
		addChild(enemy);

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

		arrowKeyUp = false;
		arrowKeyDown = false;
		arrowKeyLeft = false;
		arrowKeyRight = false;

		playerAxisSpeed = 5;
		playerShootingPattern = new PlayerShootingPattern(player);

		this.addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	private function setGameState(state:GameState):Void {
		currentGameState = state;

		if (state == Paused) {
			messageField.alpha = 1;
		} else {
			messageField.alpha = 0;

			enemyShootSequence();
		}
	}

	private function enemyShootSequence():Void {
		spiralEnemyShootingPattern = new SpiralEnemyShootingPattern(enemy);
		nWhipEnemyShootingPattern = new NWhipEnemyShootingPattern(enemy);
		// start shooting
		//spiralEnemyShootingPattern.startShooting();
		
		nWhipEnemyShootingPattern.setBulletSpawnInterval(1);
		nWhipEnemyShootingPattern.startShooting();
	}

	private function keyDown(event:KeyboardEvent):Void {
		if (currentGameState == Paused && event.keyCode == Keyboard.SPACE) {
			setGameState(Playing);
		} else if (event.keyCode == Keyboard.UP) {
			arrowKeyUp = true;
		} else if (event.keyCode == Keyboard.DOWN) {
			arrowKeyDown = true;
		} else if (event.keyCode == Keyboard.LEFT) {
			arrowKeyLeft = true;
		} else if (event.keyCode == Keyboard.RIGHT) {
			arrowKeyRight = true;
		} else if (event.keyCode == 90) { // "z" key
			if (currentGameState == Playing) {
				playerShootingPattern.startShooting();
			}
		}
	}

	private function keyUp(event:KeyboardEvent):Void {
		if (event.keyCode == 38) { // Up
			arrowKeyUp = false;
		} else if (event.keyCode == 40) { // Down
			arrowKeyDown = false;
		} else if (event.keyCode == 37) { // Left
			arrowKeyLeft = false;
		} else if (event.keyCode == 39) { // Right
			arrowKeyRight = false;
		} else if (event.keyCode == 90) { // "z" key
			playerShootingPattern.stopShooting();
		}
	}

	private function everyFrame(event:Event):Void {
		if (currentGameState == Playing) {
			if (arrowKeyUp) {
				player.y -= playerAxisSpeed;
			}

			if (arrowKeyDown) {
				player.y += playerAxisSpeed;
			}

			if (arrowKeyLeft) {
				player.x -= playerAxisSpeed;
			}

			if (arrowKeyRight) {
				player.x += playerAxisSpeed;
			}

			if (player.y < player.height / 2) {
				player.y = player.height / 2;
			}

			if (player.y > stageHeight - player.height / 2 - 10) {
				player.y = stageHeight - player.height / 2 - 10;
			}

			if (player.x < player.width / 2) {
				player.x = player.width / 2;
			}

			if (player.x > stageWidth - player.width / 2 - 10) {
				player.x = stageWidth - player.width / 2 - 10;
			}
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
