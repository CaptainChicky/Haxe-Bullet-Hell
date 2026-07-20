package manager;

import manager.LevelData.DialogueEntryData;

enum StageState {
	Idle; // not running (title / game over / all clear)
	Intro; // stage started, intro message still on screen
	IntroDialogue; // pre-stage conversation playing (waves not started yet)
	Running; // stage in progress
	OutroDialogue; // post-stage conversation playing (field is empty)
	ClearDelay; // stage beaten, showing "Stage Clear" before the next one
}

/**
 * Sequences an ordered list of level files into a full run.
 *
 * Drives LevelManager: prepares each stage, plays intro dialogue, starts the
 * waves, watches for completion (level done spawning AND no enemies left),
 * plays outro dialogue, shows transition messages via callbacks, and advances
 * to the next stage. Main calls update() once per frame while the game is in
 * the Playing state, so progression pauses automatically on game over / pause.
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
	private var currentLevel:LevelData = null;
	private var runSingle:Bool = false;

	/** A stage is starting (1-based number) — retheme backgrounds etc. */
	public var onStageBegin:Int->Void = null;

	/** Show a centered overlay message. */
	public var onStageMessage:String->Void = null;

	/** Hide the overlay message. */
	public var onMessageClear:Void->Void = null;

	/** The last stage was beaten. */
	public var onAllStagesCleared:Void->Void = null;

	/** Play a conversation; invoke the callback when it finishes.
	 *  Wired by Main to the DialogueManager overlay. */
	public var onPlayDialogue:(entries:Array<DialogueEntryData>, onDone:Void->Void) -> Void = null;

	public function new(levelManager:LevelManager, enemyManager:EnemyManager, stages:Array<String>) {
		this.levelManager = levelManager;
		this.enemyManager = enemyManager;
		this.stages = stages;
	}

	/** Start a fresh run. Defaults to the full campaign from stage 1;
	 *  practice mode passes a start index with single = true to play exactly
	 *  one stage and then report the run as cleared. */
	public function startRun(startIndex:Int = 0, single:Bool = false):Void {
		index = (startIndex >= 0 && startIndex < stages.length) ? startIndex : 0;
		runSingle = single;
		startStage();
	}

	public function getStageCount():Int {
		return stages.length;
	}

	public function stop():Void {
		state = Idle;
	}

	public function getStageNumber():Int {
		return index + 1;
	}

	private function startStage():Void {
		if (onStageBegin != null) onStageBegin(index + 1);
		if (onStageMessage != null) onStageMessage("Stage " + (index + 1));
		currentLevel = levelManager.prepare(stages[index]);
		state = Intro;
		delayCounter = INTRO_FRAMES;
	}

	/** Dialogue entries for the current stage, or null. */
	private function dialogueFor(intro:Bool):Array<DialogueEntryData> {
		if (currentLevel == null || currentLevel.dialogue == null) return null;
		var entries = intro ? currentLevel.dialogue.intro : currentLevel.dialogue.outro;
		return (entries != null && entries.length > 0) ? entries : null;
	}

	private function beginWaves():Void {
		state = Running;
		levelManager.startPrepared();
	}

	private function stageCleared():Void {
		if (!runSingle && index < stages.length - 1) {
			state = ClearDelay;
			delayCounter = CLEAR_DELAY_FRAMES;
			if (onStageMessage != null) onStageMessage("Stage " + (index + 1) + " Clear!");
		} else {
			state = Idle;
			if (onAllStagesCleared != null) onAllStagesCleared();
		}
	}

	public function update():Void {
		switch (state) {
			case Idle:

			case Intro:
				delayCounter--;
				if (delayCounter <= 0) {
					if (onMessageClear != null) onMessageClear();
					var intro = dialogueFor(true);
					if (intro != null && onPlayDialogue != null) {
						state = IntroDialogue;
						onPlayDialogue(intro, beginWaves);
					} else {
						beginWaves();
					}
				}

			case IntroDialogue:
				// Waiting for the dialogue completion callback (beginWaves).

			case Running:
				// Stage is beaten when the level has nothing left to spawn and
				// every enemy is gone (killed or flew off-screen).
				if (!levelManager.isActive() && enemyManager.getEnemyCount() == 0) {
					var outro = dialogueFor(false);
					if (outro != null && onPlayDialogue != null) {
						state = OutroDialogue;
						onPlayDialogue(outro, stageCleared);
					} else {
						stageCleared();
					}
				}

			case OutroDialogue:
				// Waiting for the dialogue completion callback (stageCleared).

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
