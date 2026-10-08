package game;

import enemy.BossEnemy;
import manager.AudioManager;
import manager.SpellStore;
import manager.StageManager;
import ui.BossHealthBar;
import ui.SpellCardAnnounce;
import ui.StageBackground;

/** Spell-card bonus tracking, capture rules, and ceremony wiring. */
class SpellCeremony {
	private var main:Main;
	private var bar:BossHealthBar;
	private var background:StageBackground;
	private var announce:SpellCardAnnounce;
	private var stageManager:StageManager;

	private var active:Bool = false;
	private var captureFailed:Bool = false;
	private var startBonus:Int = 0;
	private var currentBonus:Float = 0;
	private var minBonus:Float = 0;
	private var bossName:String = "";
	private var stageNumber:Int = 1;
	private var phaseName:String = "";

	public function new(main:Main, bar:BossHealthBar, background:StageBackground, announce:SpellCardAnnounce, stageManager:StageManager) {
		this.main = main;
		this.bar = bar;
		this.background = background;
		this.announce = announce;
		this.stageManager = stageManager;
	}

	public function onBossPhaseStarted(boss:BossEnemy, phaseIndex:Int):Void {
		bossName = boss.getBossName();
		stageNumber = stageManager.getStageNumber();
		var phase = boss.getPhase(phaseIndex);
		phaseName = phase.name != null ? phase.name : "";

		if (phase.spell != true) {
			stopSpellVisuals();
			return;
		}

		active = true;
		captureFailed = false;
		startBonus = phase.bonus != null ? phase.bonus : 0;
		minBonus = startBonus * 0.1;
		currentBonus = startBonus;

		background.setSpellMode(true);
		bar.setSpellMode(true);
		bar.setBonusDisplay(Math.floor(currentBonus));

		var cutIn = phase.cutIn != null ? phase.cutIn : "";
		announce.beginSpell(phaseName, cutIn);
		SpellStore.recordSeen(stageNumber, bossName, phaseName);
		AudioManager.sfxSpellDeclare();
	}

	public function onBossPhaseEnded(boss:BossEnemy, phaseIndex:Int, cleared:Bool):Void {
		var phase = boss.getPhase(phaseIndex);
		if (phase.spell != true) {
			return;
		}

		var captured = cleared && !captureFailed && currentBonus > 0;
		if (captured) {
			var award = Math.floor(currentBonus);
			main.addScore(award);
			announce.showToast("SPELL CARD CAPTURE!", true);
			AudioManager.sfxSpellCapture();
			SpellStore.recordCapture(stageNumber, bossName, phaseName);
		} else {
			announce.showToast("CAPTURE FAILED", false);
			AudioManager.sfxSpellFail();
		}

		active = false;
		stopSpellVisuals();
	}

	public function onBossDefeated(_boss:BossEnemy):Void {
		AudioManager.playMusic(stageManager.getStageNumber());
		reset();
	}

	/** Abandon any in-progress spell presentation (quit to title, run restart). */
	public function reset():Void {
		active = false;
		captureFailed = false;
		currentBonus = 0;
		stopSpellVisuals();
		announce.clearDockedName();
	}

	public function onBomb():Void {
		if (active) {
			captureFailed = true;
			currentBonus = 0;
			bar.setBonusDisplay(0);
		}
	}

	public function onPlayerDeath():Void {
		if (active) {
			captureFailed = true;
			currentBonus = 0;
			bar.setBonusDisplay(0);
		}
	}

	public function update(boss:BossEnemy):Void {
		announce.update();
		if (!active || boss == null) {
			return;
		}

		if (captureFailed) {
			bar.setBonusDisplay(0);
			return;
		}

		var phase = boss.getPhase(boss.getPhaseIndex());
		var timeout = phase.timeoutFrames;
		if (timeout != null && timeout > 0 && startBonus > 0) {
			var elapsed = boss.getPhaseElapsedFrames();
			var t = elapsed / timeout;
			if (t > 1) t = 1;
			currentBonus = startBonus - (startBonus - minBonus) * t;
		}
		bar.setBonusDisplay(Math.floor(currentBonus));
	}

	private function stopSpellVisuals():Void {
		background.setSpellMode(false);
		bar.setSpellMode(false);
		bar.setBonusDisplay(-1);
		announce.finishSpell();
	}
}
