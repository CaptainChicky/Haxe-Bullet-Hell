package manager;

/**
 * Run-wide settings chosen on the title screen (difficulty, practice mode).
 * Static so spawn-time consumers (EnemyManager, BulletEnemy) read them
 * without plumbing. Difficulty shapes four levers:
 *
 *   starting lives / bombs  - resource generosity
 *   enemy health multiplier - how long enemies survive
 *   bullet speed multiplier - applied at velocity integration only, so shot
 *                             scripts still see their own authored speeds
 */
class GameSettings {
	public static final DIFFICULTY_NAMES:Array<String> = ["Easy", "Normal", "Hard", "Lunatic"];

	private static final LIVES:Array<Int> = [5, 3, 3, 2];
	private static final BOMBS:Array<Int> = [4, 3, 2, 2];
	private static final HEALTH_MULT:Array<Float> = [0.75, 1.0, 1.25, 1.5];
	private static final BULLET_SPEED_MULT:Array<Float> = [0.8, 1.0, 1.15, 1.3];

	/** Index into the arrays above; Normal by default. */
	public static var difficulty:Int = 1;

	/** Practice mode: 0 = off (full run), N = play only stage N. */
	public static var practiceStage:Int = 0;

	public static function difficultyName():String {
		return DIFFICULTY_NAMES[difficulty];
	}

	public static function cycleDifficulty():Void {
		difficulty = (difficulty + 1) % DIFFICULTY_NAMES.length;
	}

	/** Cycle Off -> Stage 1 -> ... -> Stage `stageCount` -> Off. */
	public static function cyclePractice(stageCount:Int):Void {
		practiceStage = (practiceStage + 1) % (stageCount + 1);
	}

	public static function startingLives():Int {
		return LIVES[difficulty];
	}

	public static function startingBombs():Int {
		return BOMBS[difficulty];
	}

	/** Scale an authored enemy health value (never below 1). */
	public static function scaleHealth(health:Int):Int {
		var scaled = Math.round(health * HEALTH_MULT[difficulty]);
		return scaled < 1 ? 1 : scaled;
	}

	public static function bulletSpeedMultiplier():Float {
		return BULLET_SPEED_MULT[difficulty];
	}
}
