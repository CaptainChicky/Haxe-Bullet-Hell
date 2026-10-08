package;

import manager.*;
import enemy.*;
import item.Item.ItemType;
import player.PlayerShootingPattern;
import player.PlayerShootingPattern.PlayerShotType;
import player.Player;
import ui.HUD;
import ui.DialogueManager;
import ui.BossHealthBar;
import ui.StageBackground;
import ui.ScreenManager;
import ui.LegacyTitleScreen;
import ui.MenuList;
import game.GameScreen;
import openfl.ui.Keyboard;
import openfl.events.KeyboardEvent;
import openfl.text.Font;
import openfl.text.TextFormatAlign;
import openfl.text.TextFormat;
import openfl.text.TextField;
import openfl.display.FPS;
import openfl.display.Sprite;
import openfl.display.StageScaleMode;
import openfl.events.Event;
import openfl.Assets;
import openfl.Lib;

@:allow(game.GameScreen)
@:allow(ui.LegacyTitleScreen)
class Main extends Sprite {
	var inited:Bool;

	private var stageWidth:Int;
	private var stageHeight:Int;

	// Playfield size — the 1800x1080 box levels are authored against, NOT the
	// 1920x1080 stage it sits centred inside (see DisplaySettings.FIELD_W and
	// the `world` container). Fixed rather than read from the live stage: the
	// window can be fullscreen or any windowed size and OpenFL scales the
	// logical stage to fit, so live stage dimensions are meaningless here.
	// Culling, spawn math, and player clamping must all use these.
	// Kept equal to what init() assigns, so a pre-init read is still correct.
	public static var fieldWidth(default, null):Int = DisplaySettings.FIELD_W;
	public static var fieldHeight(default, null):Int = DisplaySettings.FIELD_H;

	// Center message panel (title screen, stage announcements, game over)
	private static inline final MESSAGE_PANEL_W:Int = 560;
	private static inline final MESSAGE_PANEL_H:Int = 240;

	private var player:Player;

	// Title panel and the run. Game over and all-clear return to the title
	// screen (the panel stays up, enemies keep simulating). ESC pause is NOT
	// a screen: it sets gamePaused while the run stays on top of the stack.
	private var screens:ScreenManager;
	private var titleScreen:LegacyTitleScreen;
	private var gameScreen:GameScreen;

	// In-run pause (ESC). Every per-frame listener in the game
	// (CollisionManager, LevelManager, Player, DialogueManager,
	// PlayerShootingPattern) checks this flag, so the whole simulation
	// freezes in place — including AnimatedBitmap, which only advances from
	// those updates. Static so those handlers can read it without plumbing.
	public static var gamePaused:Bool = false;

	// Message that was on screen when pause hit (e.g. a "Stage N" banner),
	// restored on resume. null = panel was hidden.
	private var pausedPrevMessage:String = null;
	private var messagePanel:Sprite;
	private var messageField:TextField;
	private var messageFormat:TextFormat;
	private var headlineFormat:TextFormat;

	private var playerShootingPattern:PlayerShootingPattern;

	// Managers
	private var enemyManager:EnemyManager;
	private var levelManager:LevelManager;
	private var collisionManager:CollisionManager;
	private var stageManager:StageManager;
	private var itemManager:ItemManager;
	private var background:StageBackground;

	/** Container for everything in playfield space, offset to centre the
	 *  1800x1080 field inside the 16:9 stage. UI (HUD, panels, dialogue, bomb
	 *  flash) is *not* in here — it lays out against the full stage.
	 *
	 *  Static because bullets are spawned far from here (BulletEmitters,
	 *  PlayerShootingPattern) and MUST land in this container: their positions
	 *  come from an enemy's or the player's x/y, which are playfield
	 *  coordinates. Parenting a bullet to the stage root instead draws it
	 *  FIELD_X pixels left of the thing that fired it. */
	public static var world(default, null):Sprite;

	// Run state
	private static inline final START_LIVES:Int = 3;
	private static inline final START_BOMBS:Int = 3;
	private static inline final RESPAWN_INVINCIBLE_FRAMES:Int = 180;
	private static inline final BOMB_INVINCIBLE_FRAMES:Int = 120;

	// Bomb blast damage to every enemy on screen (Touhou-style: bombs are a
	// panic button AND meaningful burst damage — roughly 1.5s of max DPS
	// applied to the whole field at once).
	private static inline final BOMB_DAMAGE:Int = 40;
	private static inline final SCORE_PER_HEALTH:Int = 100;
	private static inline final SCORE_PER_GRAZE:Int = 10;

	private static inline final POINT_ITEM_SCORE:Int = 500;
	private static inline final MAX_LIVES:Int = 8;
	private static inline final MAX_BOMBS:Int = 8;

	// Power economy (Touhou-style): each power item is worth +0.25 toward the
	// 4.00 cap; dying costs a full 1.00, spilled back as recoverable items.
	private static inline final POWER_PER_ITEM:Float = 0.25;
	private static inline final DEATH_POWER_LOSS:Float = 1.0;
	private static inline final DEATH_POWER_SPILL_ITEMS:Int = 4;

	private var score:Int = 0;
	private var lives:Int = START_LIVES;
	private var bombs:Int = START_BOMBS;
	private var power:Float = 0;
	private var hud:HUD;
	private var bossBar:BossHealthBar;
	private var bombFlash:Sprite;
	private var dialogueManager:DialogueManager;

	// Ordered list of stages making up one full run
	private static final STAGES:Array<String> = [
		"assets/levels/level1.json",
		"assets/levels/level2.json",
		"assets/levels/level3.json",
		"assets/levels/level4.json"
	];

	// God mode key sequence tracking
	private var keySequence:String = "";

	// Selected player shot type (1/2/3 on the title screen)
	private var shotType:PlayerShotType = Spread;

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

		// Clear colour, which is what shows in the letterbox/pillarbox bars when
		// the window aspect doesn't match the logical playfield. Black reads as
		// intentional framing; white read as a rendering glitch.
		Lib.current.stage.color = 0x000000;

		// Render the fixed logical playfield scaled to fit the real window,
		// preserving aspect (letterbox/pillarbox). Everything below lays out
		// in logical coordinates and is independent of the actual resolution.
		Lib.current.stage.scaleMode = StageScaleMode.SHOW_ALL;

		DisplaySettings.load();
		DisplaySettings.apply();

		stageWidth = DisplaySettings.LOGICAL_W;
		stageHeight = DisplaySettings.LOGICAL_H;
		fieldWidth = DisplaySettings.FIELD_W;
		fieldHeight = DisplaySettings.FIELD_H;

		// Scrolling stage backdrop — must be the very first child so
		// everything else renders above it. Sized to the whole stage, not the
		// playfield, so it covers the full screen edge to edge.
		background = new StageBackground(stageWidth, stageHeight);
		addChild(background);

		// Every gameplay object lives in here, offset so that playfield
		// coordinate (0,0) lands at the top-left of the centred 1800x1080 box.
		// Level scripts and all culling/spawn math stay in playfield space and
		// never need to know the stage is wider than the field.
		world = new Sprite();
		world.x = DisplaySettings.FIELD_X;
		world.y = DisplaySettings.FIELD_Y;
		addChild(world);

		// Create managers
		enemyManager = new EnemyManager();
		world.addChild(enemyManager); // Add to display tree so enemies are rendered

		// Item drops render above enemies but under the player
		itemManager = new ItemManager();
		itemManager.onCollected = onItemCollected;
		world.addChild(itemManager);

		// Create player with playfield dimensions
		player = new Player(fieldWidth, fieldHeight);
		player.x = fieldWidth / 2;
		player.y = fieldHeight - player.height / 2 - 10;
		player.setSpawnPosition(player.x, player.y);
		world.addChild(player);
		Player.playerX = player.x;
		Player.playerY = player.y;

		// Create level manager
		levelManager = new LevelManager(enemyManager);
		world.addChild(levelManager);

		// Create collision manager
		collisionManager = new CollisionManager(player, enemyManager);
		world.addChild(collisionManager);

		world.addChild(new fx.CancelSparkLayer());

		// Set collision manager for enemy patterns
		EnemyShootingPattern.setCollisionManager(collisionManager);

		// Create stage manager (sequences the stage list into a run)
		AudioManager.init();

		stageManager = new StageManager(levelManager, enemyManager, STAGES);
		stageManager.onStageBegin = function(stageNumber:Int) {
			background.setTheme(stageNumber);
			AudioManager.playMusic(stageNumber);
		};
		stageManager.onStageMessage = showMessage;
		stageManager.onMessageClear = hideMessage;
		stageManager.onAllStagesCleared = onAllStagesCleared;
		stageManager.onPlayDialogue = function(entries, onDone) {
			// Ceasefire while people talk: no stray bullets, no held-down shot.
			collisionManager.clearEnemyBullets();
			playerShootingPattern.stopShooting();
			dialogueManager.start(entries, onDone);
		};

		// Set player death callback
		player.setOnDeathCallback(onPlayerDeath);

		// Scoring + item-drop hooks
		collisionManager.onEnemyKilled = function(enemy:Enemy) {
			addScore(enemy.getMaxHealth() * SCORE_PER_HEALTH);
			itemManager.dropForEnemy(enemy);
		};
		collisionManager.onGraze = function() {
			addScore(SCORE_PER_GRAZE);
		};

		uiFont = Assets.getFont("assets/fonts/NotoSans-Regular.ttf");

		messageFormat = new TextFormat(uiFont.fontName, 18, 0xd8d8e0, true);
		messageFormat.align = TextFormatAlign.CENTER;
		headlineFormat = new TextFormat(uiFont.fontName, 26, 0xffd766, true);
		headlineFormat.align = TextFormatAlign.CENTER;

		// Backing panel so messages read over the white field and any bullets
		// (same visual language as the HUD and dialogue box)
		messagePanel = new Sprite();
		messagePanel.graphics.beginFill(0x0d0d16, 0.85);
		messagePanel.graphics.drawRoundRect(0, 0, MESSAGE_PANEL_W, MESSAGE_PANEL_H, 18, 18);
		messagePanel.graphics.endFill();
		messagePanel.graphics.lineStyle(1, 0x3a4260, 0.9);
		messagePanel.graphics.drawRoundRect(0, 0, MESSAGE_PANEL_W, MESSAGE_PANEL_H, 18, 18);
		messagePanel.graphics.lineStyle();
		messagePanel.graphics.beginFill(0xffd766, 0.85);
		messagePanel.graphics.drawRoundRect(16, 0, MESSAGE_PANEL_W - 32, 3, 2, 2);
		messagePanel.graphics.endFill();
		messagePanel.x = (stageWidth - MESSAGE_PANEL_W) / 2;
		messagePanel.y = (stageHeight - MESSAGE_PANEL_H) / 2;
		messagePanel.mouseEnabled = false;
		addChild(messagePanel);

		messageField = new TextField();
		messagePanel.addChild(messageField);
		messageField.embedFonts = true;
		messageField.width = MESSAGE_PANEL_W - 40;
		messageField.height = MESSAGE_PANEL_H - 40;
		messageField.x = 20;
		messageField.y = 20;
		messageField.defaultTextFormat = messageFormat;
		messageField.selectable = false;
		messageField.multiline = true;
		messageField.wordWrap = true;

		// HUD (score / lives / bombs / power, top-right)
		hud = new HUD(stageWidth, uiFont.fontName);
		hud.setScore(score);
		hud.setLives(lives);
		hud.setBombs(bombs);
		hud.setPower(power, PlayerShootingPattern.MAX_POWER);
		addChild(hud);

		// Boss status strip (hidden until a boss fight starts)
		bossBar = new BossHealthBar(stageWidth, uiFont.fontName);
		addChild(bossBar);

		// Dialogue overlay (hidden until a stage plays a conversation)
		dialogueManager = new DialogueManager(stageWidth, stageHeight, uiFont.fontName);
		addChild(dialogueManager);

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

		stage.addEventListener(KeyboardEvent.KEY_DOWN, keyDown);
		stage.addEventListener(KeyboardEvent.KEY_UP, keyUp);

		// Losing window focus (alt-tab, Win+Shift+S snip overlay) auto-pauses
		// mid-run so the player doesn't die off-screen.
		stage.addEventListener(Event.DEACTIVATE, function(_) {
			if (inRun() && !gamePaused) {
				togglePause();
			}
		});

		playerShootingPattern = new PlayerShootingPattern(player, collisionManager);
		playerShootingPattern.setShotType(shotType);
		applySpeedProfile(shotType);
		hud.setShotType(shotTypeName(shotType));

		screens = new ScreenManager();
		titleScreen = new LegacyTitleScreen(this);
		gameScreen = new GameScreen(this);
		optionsList = new MenuList(OPTION_ROWS.length);
		titleScreen.arm(titleText());
		screens.push(titleScreen);

		this.addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	/** True while the run is the top screen. Game over and the title panel are not. */
	private function inRun():Bool {
		return screens != null && screens.current() == gameScreen;
	}

	/** Leave the title panel and start a run. GameScreen.enter does the reset. */
	private function startRun():Void {
		screens.replace(gameScreen);
	}

	/**
	 * Leave the run (if one is current) and show `message` on the title
	 * panel. Game over and all-clear use this; the field is not cleared
	 * here — GameScreen.exit only unpauses and reveals the panel.
	 */
	private function showPanelScreen(message:String):Void {
		if (screens.current() == titleScreen) {
			showMessage(message);
			return;
		}
		titleScreen.arm(message);
		screens.replace(titleScreen);
	}

	/** ESC during a run: freeze the whole simulation and show the pause
	 *  panel. ESC again resumes, restoring whatever message (stage banner,
	 *  ...) was on screen when pause hit. */
	private function togglePause():Void {
		if (!inRun()) {
			return;
		}

		if (!gamePaused) {
			gamePaused = true;
			pausedPrevMessage = (messagePanel.alpha > 0) ? messageField.text : null;
			showMessage(pauseText());
		} else {
			gamePaused = false;
			if (pausedPrevMessage != null) {
				showMessage(pausedPrevMessage);
				pausedPrevMessage = null;
			} else {
				messagePanel.alpha = 0;
			}
		}
		AudioManager.setMusicDucked(gamePaused);
	}

	/* OPTIONS SCREEN
	 *
	 * Reuses the message panel rather than introducing a second UI system:
	 * it's the same text-in-a-panel idiom as the title and pause screens.
	 * Reachable with O from either, and closes back to whichever opened it.
	 * UP/DOWN go through MenuList so the wrap matches every other menu.
	 * LEFT/RIGHT still edit the row, and ESC / O still close it — Z and X
	 * stay swallowed, so a bomb or a confirm can't fire through the panel. */

	private static final OPTION_ROWS:Array<String> = ["Display", "Window size", "Music", "Volume"];

	private var optionsOpen:Bool = false;
	private var optionsList:MenuList;

	/** Panel text to restore when options closes (title or pause screen). */
	private var optionsReturnText:String = null;

	private function optionsText():String {
		var lines = "OPTIONS";
		for (i in 0...OPTION_ROWS.length) {
			var value = switch (i) {
				case 0: DisplaySettings.modeName();
				case 1: DisplaySettings.windowSizeName();
				case 2: AudioManager.musicMuted ? "Off" : "On";
				default: Math.round(AudioManager.musicVolume * 100) + "%";
			}
			lines += "\n" + (i == optionsList.index ? "> " : "  ") + OPTION_ROWS[i] + ":  " + value;
		}
		return lines + "\n\nUP/DOWN select · LEFT/RIGHT change · F11 fullscreen · ESC back";
	}

	private function openOptions():Void {
		optionsOpen = true;
		optionsList.reset();
		optionsReturnText = (messagePanel.alpha > 0) ? messageField.text : null;
		showMessage(optionsText());
	}

	private function closeOptions():Void {
		optionsOpen = false;
		DisplaySettings.save();

		if (optionsReturnText != null) {
			showMessage(optionsReturnText);
			optionsReturnText = null;
		} else {
			messagePanel.alpha = 0;
		}
	}

	/** Adjust the highlighted option. `step` is -1 or +1. */
	private function changeOption(step:Int):Void {
		switch (optionsList.index) {
			case 0:
				DisplaySettings.cycleMode();
				DisplaySettings.apply();
			case 1:
				// Only meaningful windowed; changing it in fullscreen would
				// silently do nothing, so switch to windowed as well.
				DisplaySettings.cycleWindowScale(step);
				DisplaySettings.mode = DisplaySettings.WINDOWED;
				DisplaySettings.apply();
			case 2:
				AudioManager.toggleMusicMuted();
			default:
				AudioManager.nudgeMusicVolume(step * 0.1);
		}
		showMessage(optionsText());
	}

	/** Options-screen key handling. Returns true if the key was consumed. */
	private function handleOptionsKeys(keyCode:Int):Bool {
		if (!optionsOpen) {
			return false;
		}

		switch (keyCode) {
			case Keyboard.ESCAPE, 79: // ESC / "o"
				closeOptions();
			case Keyboard.UP, Keyboard.DOWN:
				optionsList.keyDown(keyCode);
				showMessage(optionsText());
			case Keyboard.LEFT:
				changeOption(-1);
			case Keyboard.RIGHT:
				changeOption(1);
			default:
				// Swallow everything else so the game can't be started or
				// bombed from behind the options panel.
		}
		return true;
	}

	/** F11: flip fullscreen/windowed from anywhere, mid-run included. */
	private function toggleDisplayMode():Void {
		DisplaySettings.cycleMode();
		DisplaySettings.apply();
		DisplaySettings.save();

		if (optionsOpen) {
			showMessage(optionsText());
		} else {
			refreshTitleMessage();
		}
	}

	private function pauseText():String {
		return "PAUSED\nESC to resume · O options · Q quit to main menu"
			+ "\nM music: " + (AudioManager.musicMuted ? "Off" : "On")
			+ " · [ ] volume: " + Math.round(AudioManager.musicVolume * 100) + "%";
	}

	/** Q on the pause panel: abandon the run and return to the title screen. */
	private function quitToTitle():Void {
		gamePaused = false;
		pausedPrevMessage = null;
		AudioManager.setMusicDucked(false);
		AudioManager.stopMusic();

		stageManager.stop();
		levelManager.stopLevel();
		dialogueManager.cancel();
		playerShootingPattern.stopShooting();

		collisionManager.clearAllBullets();
		enemyManager.clearAllEnemies();
		itemManager.clear();

		showPanelScreen(titleText());
	}

	/** Music controls (work on any screen, paused included). Returns true if
	 *  the key was a music key. */
	private function handleMusicKeys(keyCode:Int):Bool {
		switch (keyCode) {
			case 77: // "m"
				AudioManager.toggleMusicMuted();
			case 219: // "["
				AudioManager.nudgeMusicVolume(-0.1);
			case 221: // "]"
				AudioManager.nudgeMusicVolume(0.1);
			default:
				return false;
		}
		// Refresh whichever settings text is on screen
		if (gamePaused) {
			showMessage(pauseText());
		} else {
			refreshTitleMessage();
		}
		return true;
	}

	private function shotTypeName(type:PlayerShotType):String {
		return switch (type) {
			case Spread: "Spread";
			case Pierce: "Pierce";
			case Homing: "Homing";
		}
	}

	private function titleText():String {
		var practice = (GameSettings.practiceStage == 0)
			? "Off"
			: "Stage " + GameSettings.practiceStage;
		return "BULLET HELL"
			+ "\nPress SPACE to start"
			+ "\nARROW KEYS move · Z shoot · X bomb · SHIFT focus · ESC pause"
			+ "\nShot type [1/2/3]: " + shotTypeName(shotType)
			+ "\nD difficulty: " + GameSettings.difficultyName()
			+ " · P practice: " + practice
			+ "\nO options (" + DisplaySettings.modeName() + ")"
			+ " · M music: " + (AudioManager.musicMuted ? "Off" : "On")
			+ " · [ ] volume: " + Math.round(AudioManager.musicVolume * 100) + "%";
	}

	/** Movement speeds per shot type (unfocused / focused): homing trades
	 *  speed for auto-aim, spread is the baseline, pierce is fastest to
	 *  compensate for having to line its narrow shot up manually. */
	private function applySpeedProfile(type:PlayerShotType):Void {
		switch (type) {
			case Homing: player.setSpeedProfile(4.2, 1.8);
			case Spread: player.setSpeedProfile(5.2, 2.2);
			case Pierce: player.setSpeedProfile(6.5, 2.8);
		}
	}

	/** Select a shot type (title / game-over screen only). */
	private function selectShotType(type:PlayerShotType):Void {
		shotType = type;
		if (playerShootingPattern != null) {
			playerShootingPattern.setShotType(type);
		}
		applySpeedProfile(type);
		hud.setShotType(shotTypeName(type));
		refreshTitleMessage();
	}

	/** Re-render the title panel if it is currently on screen. */
	private function refreshTitleMessage():Void {
		if (screens.current() == titleScreen && StringTools.startsWith(messageField.text, "BULLET HELL")) {
			showMessage(titleText());
		}
	}

	private function showMessage(text:String):Void {
		messageField.text = text;
		messageField.setTextFormat(messageFormat);

		// First line is the headline: bigger and gold
		var newline = text.indexOf("\n");
		messageField.setTextFormat(headlineFormat, 0, newline > 0 ? newline : text.length);

		// Vertically center the block inside the panel
		var offset = (MESSAGE_PANEL_H - messageField.textHeight) / 2 - 4;
		messageField.y = offset > 12 ? offset : 12;

		messagePanel.alpha = 1;
	}

	private function hideMessage():Void {
		if (inRun()) {
			messagePanel.alpha = 0;
		}
	}

	private function addScore(points:Int):Void {
		score += points;
		hud.setScore(score);
	}

	/** Clamp + apply a new power level to shot strength and the HUD. */
	private function setPower(value:Float):Void {
		power = value < 0 ? 0 : (value > PlayerShootingPattern.MAX_POWER ? PlayerShootingPattern.MAX_POWER : value);
		playerShootingPattern.setPower(power);
		hud.setPower(power, PlayerShootingPattern.MAX_POWER);
	}

	private function onItemCollected(type:ItemType):Void {
		AudioManager.sfxItemPickup();
		switch (type) {
			case PowerItem:
				setPower(power + POWER_PER_ITEM);
			case PointItem:
				addScore(POINT_ITEM_SCORE);
			case BombItem:
				if (bombs < MAX_BOMBS) {
					bombs++;
					hud.setBombs(bombs);
				}
			case LifeItem:
				if (lives < MAX_LIVES) {
					lives++;
					hud.setLives(lives);
				}
		}
	}

	private function useBomb():Void {
		if (!inRun() || !player.isAlive() || bombs <= 0) {
			return;
		}

		bombs--;
		hud.setBombs(bombs);
		AudioManager.sfxBomb();

		// Wipe every enemy bullet, damage everything on screen, and give the
		// player breathing room
		collisionManager.clearEnemyBullets();
		collisionManager.damageAllEnemies(BOMB_DAMAGE);
		player.setInvincible(BOMB_INVINCIBLE_FRAMES);

		// Screen flash, faded out in everyFrame
		bombFlash.alpha = 0.6;
	}

	private function onAllStagesCleared():Void {
		AudioManager.stopMusic();
		playerShootingPattern.stopShooting();
		var headline = (GameSettings.practiceStage > 0) ? "PRACTICE COMPLETE!" : "ALL STAGES CLEAR!";
		showPanelScreen(headline + "\nFinal Score: " + score + "\n\nPress SPACE to play again");
	}

	private function keyDown(event:KeyboardEvent):Void {
		// Display mode works anywhere, mid-run included
		if (event.keyCode == Keyboard.F11) {
			toggleDisplayMode();
			return;
		}

		// The options panel owns every key while it's up (including ESC, so it
		// closes options rather than toggling pause underneath)
		if (handleOptionsKeys(event.keyCode)) {
			return;
		}

		if (event.keyCode == Keyboard.ESCAPE) {
			togglePause();
			return;
		}

		// "o" opens options from the title screen or the pause panel
		if (event.keyCode == 79 && (gamePaused || screens.current() == titleScreen)) {
			openOptions();
			return;
		}

		// Music settings live on the pause/title "menu" but work anywhere
		if (handleMusicKeys(event.keyCode)) {
			return;
		}

		// While paused only ESC, Q (quit to title) and music keys do anything;
		// keyUp still runs, so held movement/focus keys release cleanly even if
		// let go mid-pause.
		if (gamePaused) {
			if (event.keyCode == 81) { // "q"
				quitToTitle();
			}
			return;
		}

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
				if (player.isGodMode()) {
					setPower(PlayerShootingPattern.MAX_POWER);
				}
				keySequence = ""; // Reset after activating
			}
		}

		// The current screen owns its own keys (title: shot type, difficulty,
		// practice, SPACE to start; run: dialogue advance). Anything it does
		// not consume falls through, so an arrow held on the title panel
		// still sets a movement flag the way the old chain did.
		if (screens.keyDown(event.keyCode)) {
			return;
		}

		if (event.keyCode == Keyboard.UP) {
			player.setMoveUp(true);
		} else if (event.keyCode == Keyboard.DOWN) {
			player.setMoveDown(true);
		} else if (event.keyCode == Keyboard.LEFT) {
			player.setMoveLeft(true);
		} else if (event.keyCode == Keyboard.RIGHT) {
			player.setMoveRight(true);
		} else if (event.keyCode == 90) { // "z" key
			if (inRun()) {
				playerShootingPattern.startShooting();
			}
		} else if (event.keyCode == 88) { // "x" key
			useBomb();
		} else if (event.keyCode == Keyboard.SHIFT) {
			player.setFocused(true);
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
		} else if (event.keyCode == Keyboard.SHIFT) {
			player.setFocused(false);
		}
		if (screens != null) screens.keyUp(event.keyCode);
	}

	private function onPlayerDeath():Void {
		lives--;
		hud.setLives(lives);
		AudioManager.sfxPlayerDeath();

		if (lives > 0) {
			// Respawn mid-run: clear the bullet field so the return is fair,
			// refill bombs (per-life stock), and grant invincibility frames.
			// Some power spills out as recoverable items where the player died.
			itemManager.spillPower(player.x, player.y, DEATH_POWER_SPILL_ITEMS);
			setPower(power - DEATH_POWER_LOSS);
			collisionManager.clearEnemyBullets();
			bombs = GameSettings.startingBombs();
			hud.setBombs(bombs);
			player.respawn();
			player.setInvincible(RESPAWN_INVINCIBLE_FRAMES);
			return;
		}

		// Out of lives: game over
		trace("GAME OVER!");
		AudioManager.stopMusic();
		stageManager.stop();
		dialogueManager.cancel();
		showPanelScreen("GAME OVER\nFinal Score: " + score + "\n\nPress SPACE to restart");

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
		if (gamePaused) {
			return;
		}

		// Backdrop drifts on every unpaused frame (title screen included)
		background.update();
		AudioManager.tick();

		// Run-only work (player, items, stage clock) lives on GameScreen.
		// The title / game-over panel is a different screen, so this is a
		// no-op there. ESC pause returned above, which also freezes any
		// AnimatedBitmap those updates would have advanced.
		screens.update();

		// Enemies + patterns advance even on the game-over panel (bullets
		// stay in flight), exactly as their per-object ENTER_FRAME listeners
		// did before updates were centralized.
		enemyManager.update();

		// Boss bar follows whichever boss (if any) is alive
		bossBar.track(enemyManager.getActiveBoss());

		// HUD steps aside when the player fights underneath it
		hud.trackPlayer(player.x, player.y);

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
		#if sys
		// SDL minimizes windows carrying its fullscreen flag on focus loss.
		// The game no longer uses that flag (fullscreen is faked with
		// borderless + resize, see DisplaySettings.apply), so this is belt and
		// braces rather than the load-bearing fix it once was — it only still
		// matters if anything ever sets a real SDL fullscreen mode again.
		// SDL re-reads the hint from the environment on every focus-loss
		// event, so setting it here, after window creation, works fine.
		Sys.putEnv("SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS", "0");
		#end
		Lib.current.stage.align = openfl.display.StageAlign.TOP_LEFT;
		Lib.current.addChild(new Main());
	}
}
