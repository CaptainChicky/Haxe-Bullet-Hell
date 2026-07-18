package manager;

enum StageState {
	Idle; // not running (title / game over / all clear)
	Intro; // stage started, intro message still on screen
	Running; // stage in progress
	ClearDelay; // stage beaten, showing "Stage Clear" before the next one
}

/**
 * Sequences an ordered list of level files into a full run.
 *
 * Drives LevelManager: starts each stage, watches for completion (level done
 * spawning AND no enemies left), shows transition messages via callbacks, and
 * advances to the next stage. Main calls update() once per frame while the
 * game is in the Playing state, so progression pauses automatically on game
 * over / pause.
 */
class StageManager {
	private static inline final INTRO_FRAMES:Int = 90;
	private static inline final CLEAR_DELAY_FRAMES:Int = 180;

	private var stages:Array<String>;
	private var index:Int = 0;
	private var levelManager:LevelManager;
	private var enemyManager:EnemyManager;

	private var state:StageState = Idle;
	private var delayCounter:Int = 0;

	/** Show a centered overlay message. */
	public var onStageMessage:String->Void = null;

	/** Hide the overlay message. */
	public var onMessageClear:Void->Void = null;

	/** The last stage was beaten. */
	public var onAllStagesCleared:Void->Void = null;

	public function new(levelManager:LevelManager, enemyManager:EnemyManager, stages:Array<String>) {
		this.levelManager = levelManager;
		this.enemyManager = enemyManager;
		this.stages = stages;
	}

	/** Start a fresh run from stage 1. */
	public function startRun():Void {
		index = 0;
		startStage();
	}

	public function stop():Void {
		state = Idle;
	}

	public function getStageNumber():Int {
		return index + 1;
	}

	private function startStage():Void {
		if (onStageMessage != null) onStageMessage("Stage " + (index + 1));
		levelManager.loadLevel(stages[index]);
		state = Intro;
		delayCounter = INTRO_FRAMES;
	}

	public function update():Void {
		switch (state) {
			case Idle:

			case Intro:
				delayCounter--;
				if (delayCounter <= 0) {
					if (onMessageClear != null) onMessageClear();
					state = Running;
				}

			case Running:
				// Stage is beaten when the level has nothing left to spawn and
				// every enemy is gone (killed or flew off-screen).
				if (!levelManager.isActive() && enemyManager.getEnemyCount() == 0) {
					if (index < stages.length - 1) {
						state = ClearDelay;
						delayCounter = CLEAR_DELAY_FRAMES;
						if (onStageMessage != null) onStageMessage("Stage " + (index + 1) + " Clear!");
					} else {
						state = Idle;
						if (onAllStagesCleared != null) onAllStagesCleared();
					}
				}

			case ClearDelay:
				delayCounter--;
				if (delayCounter <= 0) {
					if (onMessageClear != null) onMessageClear();
					index++;
					startStage();
				}
		}
	}
}
