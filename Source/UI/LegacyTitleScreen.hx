package ui;

import manager.GameSettings;
import openfl.ui.Keyboard;
import player.PlayerShootingPattern.PlayerShotType;

/**
 * The message-panel screen: boot title, game over, and all-clear. It reuses
 * Main's panel rather than drawing its own. Shot type, difficulty, practice,
 * and SPACE-to-start are the same keys as before. The in-run pause panel is
 * not a screen — ESC still flips Main.gamePaused while the run stays current.
 */
class LegacyTitleScreen implements Screen {
	private var main:Main;

	/** Shown on the next enter(). Cleared once displayed. */
	private var armed:String = null;

	public function new(main:Main) {
		this.main = main;
	}

	public function arm(message:String):Void {
		armed = message;
	}

	public function enter():Void {
		if (armed != null) {
			var message = armed;
			armed = null;
			main.showMessage(message);
		}
	}

	public function exit():Void {}

	public function update():Void {}

	public function keyDown(code:Int):Bool {
		switch (code) {
			case 49:
				main.selectCharacterShot(0); // "1"
				return true;
			case 50:
				main.selectCharacterShot(1); // "2"
				return true;
			case 51:
				main.selectCharacterShot(2); // "3"
				return true;
			case 67: // "c"
				main.cycleCharacter();
				return true;
			case 68: // "d"
				GameSettings.cycleDifficulty();
				main.refreshTitleMessage();
				return true;
			case 80: // "p"
				GameSettings.cyclePractice(main.stageManager.getStageCount());
				main.refreshTitleMessage();
				return true;
			case Keyboard.SPACE:
				main.startRun();
				return true;
			default:
				return false;
		}
	}

	public function keyUp(code:Int):Bool {
		return false;
	}
}
