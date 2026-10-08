package game;

import manager.GameSettings;
import openfl.ui.Keyboard;
import player.PlayerShootingPattern;
import ui.Screen;

/**
 * The run. enter() is the old `setGameState(Playing)` reset: clear the
 * field, restock the player, and start either the campaign or the practice
 * stage. exit() only drops the ESC-pause flag and brings the message panel
 * back; it does not clear enemies or bullets, so game over can leave them
 * on screen.
 *
 * Pause is not a screen. While Main.gamePaused is set, Main.everyFrame
 * returns before update(), which is what freezes the run.
 */
class GameScreen implements Screen {
	private var main:Main;

	public function new(main:Main) {
		this.main = main;
	}

	public function enter():Void {
		Main.gamePaused = false;
		main.pausedPrevMessage = null;

		if (main.spellCeremony != null) {
			main.spellCeremony.reset();
			main.enemyManager.onBossPhaseStarted = main.spellCeremony.onBossPhaseStarted;
			main.enemyManager.onBossPhaseEnded = main.spellCeremony.onBossPhaseEnded;
			main.enemyManager.onBossDefeated = main.spellCeremony.onBossDefeated;
		}

		main.messagePanel.alpha = 0;

		// Respawn player if they were dead
		if (!main.player.isAlive()) {
			main.player.respawn();
		}

		// Fresh run: reset score, lives, bombs, power (per difficulty).
		// God mode toggled on the title screen carries into the run, so
		// keep its max-power grant instead of zeroing it.
		main.score = 0;
		main.lives = GameSettings.startingLives();
		main.bombs = GameSettings.startingBombs();
		main.power = main.player.isGodMode() ? PlayerShootingPattern.MAX_POWER : 0;
		main.hud.setScore(main.score);
		main.hud.setLives(main.lives);
		main.hud.setBombs(main.bombs);
		main.hud.setPower(main.power, PlayerShootingPattern.MAX_POWER);
		if (main.playerShootingPattern != null) {
			main.playerShootingPattern.setPower(main.power);
		}

		// Clear everything when restarting
		main.collisionManager.clearAllBullets();
		main.enemyManager.clearAllEnemies();
		main.itemManager.clear();
		main.dialogueManager.cancel();

		// Full campaign, or a single stage in practice mode
		if (GameSettings.practiceStage > 0) {
			main.stageManager.startRun(GameSettings.practiceStage - 1, true);
		} else {
			main.stageManager.startRun();
		}
	}

	public function exit():Void {
		Main.gamePaused = false;
		main.pausedPrevMessage = null;
		main.messagePanel.alpha = 1;

		main.enemyManager.onBossPhaseStarted = null;
		main.enemyManager.onBossPhaseEnded = null;
		main.enemyManager.onBossDefeated = null;
	}

	public function update():Void {
		// Player handles its own movement and boundaries
		// (frozen while a conversation is on screen)
		if (!main.dialogueManager.isActive()) {
			main.player.updateMovement();
			// Items fall / magnet / collect against the live player
			main.itemManager.update(main.player);
		}

		// Stage progression (pauses automatically outside the run, because
		// this update is not called when the title panel is the top screen)
		main.stageManager.update();
	}

	public function keyDown(code:Int):Bool {
		// A running conversation consumes the action keys (Z / X / SPACE advance).
		// Arrows are intentionally not consumed: movement flags may be set, but
		// update() does not integrate them until the conversation ends.
		if (main.dialogueManager.isActive()) {
			if (code == Keyboard.SPACE || code == 90 || code == 88) {
				main.dialogueManager.advance();
				return true;
			}
		}
		return false;
	}

	public function keyUp(code:Int):Bool {
		return false;
	}
}
