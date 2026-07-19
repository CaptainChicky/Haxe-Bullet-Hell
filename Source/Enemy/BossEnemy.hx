package enemy;

import manager.LevelData.BossData;
import manager.LevelData.BossPhaseData;

/**
 * Multi-phase boss. Total health is the sum of the phase healths, but damage
 * never spills across a phase boundary: each phase ends exactly at zero, the
 * field is wiped and the pattern swapped (orchestrated by EnemyManager via
 * onPhaseDepleted), and only clearing the LAST phase kills the boss.
 */
class BossEnemy extends Enemy {
	public static inline final TRANSITION_INVULN_FRAMES:Int = 90;
	public static inline final VISUAL_SCALE:Float = 1.6;

	private var data:BossData;
	private var phaseIndex:Int = 0;
	private var phaseHealth:Int;
	private var invulnFrames:Int = 0;

	/** Set by EnemyManager: fired once when the current phase's health empties. */
	public var onPhaseDepleted:Void->Void = null;

	public function new(data:BossData, ?spriteName:String) {
		var total = 0;
		for (phase in data.phases) {
			total += phase.health;
		}
		super(total, spriteName);
		this.data = data;
		this.phaseHealth = data.phases[0].health;
		setVisualScale(VISUAL_SCALE);
	}

	override public function takeDamage(damage:Int):Void {
		if (!isAlive() || invulnFrames > 0) {
			return;
		}
		if (damage > phaseHealth) {
			damage = phaseHealth; // no spill into the next phase
		}
		phaseHealth -= damage;
		currentHealth -= damage;
		if (phaseHealth <= 0 && onPhaseDepleted != null) {
			onPhaseDepleted();
		}
	}

	/** Advance to the next phase and grant transition mercy invincibility.
	 *  EnemyManager calls this after clearing the bullet field. */
	public function startNextPhase():Void {
		phaseIndex++;
		phaseHealth = data.phases[phaseIndex].health;
		invulnFrames = TRANSITION_INVULN_FRAMES;
	}

	/** Final phase cleared: run the normal enemy death path. */
	public function defeat():Void {
		currentHealth = 0;
		die();
	}

	override public function update():Void {
		if (invulnFrames > 0) {
			invulnFrames--;
			// Blink while invulnerable so the player knows shots are wasted
			alpha = ((invulnFrames & 7) < 4) ? 0.55 : 1.0;
			if (invulnFrames == 0) {
				alpha = 1.0;
			}
		}
		super.update();
	}

	public function getBossName():String {
		return (data.name != null) ? data.name : "BOSS";
	}

	public function getPhase(index:Int):BossPhaseData {
		return data.phases[index];
	}

	public function getPhaseIndex():Int {
		return phaseIndex;
	}

	public function getPhaseCount():Int {
		return data.phases.length;
	}

	public function getPhaseName():String {
		var name = data.phases[phaseIndex].name;
		return (name != null) ? name : "";
	}

	public function getPhaseHealth():Int {
		return phaseHealth;
	}

	public function getPhaseMaxHealth():Int {
		return data.phases[phaseIndex].health;
	}

	public function isInvulnerable():Bool {
		return invulnFrames > 0;
	}
}
