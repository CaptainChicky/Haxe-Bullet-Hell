package;

import manager.*;
import enemy.*;
import player.PlayerShootingPattern;
import player.Player;
import ui.HUD;
import openfl.ui.Keyboard;
import openfl.events.KeyboardEvent;
import openfl.text.Font;
import openfl.text.TextFormatAlign;
import openfl.text.TextFormat;
import openfl.text.TextField;
import openfl.display.FPS;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.Assets;
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
	private var messageFormat:TextFormat;

	private var playerShootingPattern:PlayerShootingPattern;

	// Managers
	private var enemyManager:EnemyManager;
	private var levelManager:LevelManager;
	private var collisionManager:CollisionManager;
	private var stageManager:StageManager;

	// Run state
	private static inline final START_LIVES:Int = 3;
	private static inline final START_BOMBS:Int = 3;
	private static inline final RESPAWN_INVINCIBLE_FRAMES:Int = 180;
	private static inline final BOMB_INVINCIBLE_FRAMES:Int = 120;
	private static inline final SCORE_PER_HEALTH:Int = 100;
	private static inline final SCORE_PER_GRAZE:Int = 10;

	private var score:Int = 0;
	private var lives:Int = START_LIVES;
	private var bombs:Int = START_BOMBS;
	private var hud:HUD;
	private var bombFlash:Sprite;

	// Ordered list of stages making up one full run
	private static final STAGES:Array<String> = [
		"assets/levels/level1.json",
		"assets/levels/level2.json",
		"assets/levels/level3.json"
	];

	// God mode key sequence tracking
	private var keySequence:String = "";

	// Embedded UI font (bundled TTF: system fonts like Verdana don't exist on
	// native targets, so every TextField must use this).
	public static var uiFont(default, null):Font;

	private var fpsCounter:FPS;

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
		player.setSpawnPosition(player.x, player.y);
		addChild(player);

		// Create level manager
		levelManager = new LevelManager(enemyManager);
		addChild(levelManager);

		// Create collision manager
		collisionManager = new CollisionManager(player, enemyManager);
		addChild(collisionManager);

		// Set collision manager for enemy patterns
		EnemyShootingPattern.setCollisionManager(collisionManager);

		// Create stage manager (sequences the stage list into a run)
		stageManager = new StageManager(levelManager, enemyManager, STAGES);
		stageManager.onStageMessage = showMessage;
		stageManager.onMessageClear = hideMessage;
		stageManager.onAllStagesCleared = onAllStagesCleared;

		// Set player death callback
		player.setOnDeathCallback(onPlayerDeath);

		// Scoring hooks
		collisionManager.onEnemyKilled = function(enemy:Enemy) {
			addScore(enemy.getMaxHealth() * SCORE_PER_HEALTH);
		};
		collisionManager.onGraze = function() {
			addScore(SCORE_PER_GRAZE);
		};

		uiFont = Assets.getFont("assets/fonts/NotoSans-Regular.ttf");

		messageFormat = new TextFormat(uiFont.fontName, 18, 0xbbbbbb, true);
		messageFormat.align = TextFormatAlign.CENTER;
		messageField = new TextField();
		addChild(messageField);
		messageField.embedFonts = true;
		messageField.width = 500;
		messageField.height = 160;
		messageField.y = stageHeight / 2 - messageField.height / 2;
		messageField.x = stageWidth / 2 - messageField.width / 2;
		messageField.defaultTextFormat = messageFormat;
		messageField.selectable = false;
		messageField.multiline = true;
		messageField.wordWrap = true;
		messageField.text = "Press SPACE to start\nUse ARROW KEYS to move, Z to shoot, X to bomb";

		// HUD (score / lives / bombs, top-right)
		hud = new HUD(stageWidth, uiFont.fontName);
		hud.setScore(score);
		hud.setLives(lives);
		hud.setBombs(bombs);
		addChild(hud);

		// Bomb screen flash overlay (invisible until a bomb goes off)
		bombFlash = new Sprite();
		bombFlash.graphics.beginFill(0xFFFFFF);
		bombFlash.graphics.drawRect(0, 0, stageWidth, stageHeight);
		bombFlash.graphics.endFill();
		bombFlash.alpha = 0;
		bombFlash.mouseEnabled = false;
		addChild(bombFlash);

		// FPS counter (top-left); also our benchmark for native vs HTML5.
		fpsCounter = new FPS(10, 10, 0x888888);
		fpsCounter.embedFonts = true;
		fpsCounter.defaultTextFormat = new TextFormat(uiFont.fontName, 14, 0x888888);
		fpsCounter.setTextFormat(fpsCounter.defaultTextFormat);
		addChild(fpsCounter);

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

			// Respawn player if they were dead
			if (!player.isAlive()) {
				player.respawn();
			}

			// Fresh run: reset score, lives, bombs
			score = 0;
			lives = START_LIVES;
			bombs = START_BOMBS;
			hud.setScore(score);
			hud.setLives(lives);
			hud.setBombs(bombs);

			// Clear everything when restarting
			collisionManager.clearAllBullets();
			enemyManager.clearAllEnemies();

			// Start the run from stage 1
			stageManager.startRun();
		}
	}

	private function showMessage(text:String):Void {
		messageField.text = text;
		messageField.setTextFormat(messageFormat);
		messageField.alpha = 1;
	}

	private function hideMessage():Void {
		if (currentGameState == Playing) {
			messageField.alpha = 0;
		}
	}

	private function addScore(points:Int):Void {
		score += points;
		hud.setScore(score);
	}

	private function useBomb():Void {
		if (currentGameState != Playing || !player.isAlive() || bombs <= 0) {
			return;
		}

		bombs--;
		hud.setBombs(bombs);

		// Wipe every enemy bullet and give the player breathing room
		collisionManager.clearEnemyBullets();
		player.setInvincible(BOMB_INVINCIBLE_FRAMES);

		// Screen flash, faded out in everyFrame
		bombFlash.alpha = 0.6;
	}

	private function onAllStagesCleared():Void {
		currentGameState = Paused;
		playerShootingPattern.stopShooting();
		showMessage("ALL STAGES CLEAR!\nFinal Score: " + score + "\n\nPress SPACE to play again");
	}

	private function keyDown(event:KeyboardEvent):Void {
		// Track number keys for god mode sequence
		if (event.keyCode >= 48 && event.keyCode <= 57) { // Number keys 0-9
			var digit:String = String.fromCharCode(event.keyCode);
			keySequence += digit;

			// Keep only last 4 characters
			if (keySequence.length > 4) {
				keySequence = keySequence.substr(keySequence.length - 4);
			}

			// Check for god mode sequence "6969"
			if (keySequence == "6969") {
				player.toggleGodMode();
				keySequence = ""; // Reset after activating
			}
		}

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
		} else if (event.keyCode == 88) { // "x" key
			useBomb();
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
		lives--;
		hud.setLives(lives);

		if (lives > 0) {
			// Respawn mid-run: clear the bullet field so the return is fair,
			// refill bombs (per-life stock), and grant invincibility frames.
			collisionManager.clearEnemyBullets();
			bombs = START_BOMBS;
			hud.setBombs(bombs);
			player.respawn();
			player.setInvincible(RESPAWN_INVINCIBLE_FRAMES);
			return;
		}

		// Out of lives: game over
		trace("GAME OVER!");
		currentGameState = Paused;
		stageManager.stop();
		showMessage("GAME OVER\nFinal Score: " + score + "\n\nPress SPACE to restart");

		// Stop all enemy shooting but keep them visible
		enemyManager.stopAllShooting();

		// Pause all enemy movement scripts
		enemyManager.pauseAllMovementScripts();

		// Keep bullets on screen (don't clear them)

		// Stop player shooting
		playerShootingPattern.stopShooting();

		// Stop the level timer (but don't clear enemies)
		levelManager.stopLevel();
	}

	private function everyFrame(event:Event):Void {
		if (currentGameState == Playing) {
			// Player handles its own movement and boundaries
			player.updateMovement();

			// Stage progression (pauses automatically outside Playing)
			stageManager.update();
		}

		// Fade out the bomb flash
		if (bombFlash != null && bombFlash.alpha > 0) {
			bombFlash.alpha -= 0.03;
			if (bombFlash.alpha < 0) bombFlash.alpha = 0;
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

		// Native targets don't reliably dispatch RESIZE at startup; init
		// directly (idempotent) instead of waiting for one.
		init();
	}

	public static function main() {
		Lib.current.stage.align = openfl.display.StageAlign.TOP_LEFT;
		Lib.current.addChild(new Main());
	}
}
