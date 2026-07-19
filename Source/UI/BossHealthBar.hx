package ui;

import enemy.BossEnemy;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * Boss status strip across the top of the screen: boss name, dots for the
 * phases still to come, the current phase's spell card name, and the phase
 * health bar. Poll track() every frame from Main; it hides itself when no
 * boss is alive.
 */
class BossHealthBar extends Sprite {
	private static inline final BAR_HEIGHT:Int = 10;
	private static inline final ROW_HEIGHT:Int = 20;
	private static inline final SPELL_FLASH_FRAMES:Int = 45;

	// Phase fill colors, indexed by phases REMAINING after this one
	// (final phase red, earlier phases cooler)
	private static final PHASE_COLORS:Array<Int> = [0xff5566, 0xffaa44, 0xffd766, 0x66ddff, 0xcc88ff];

	private var barWidth:Int;
	private var nameField:TextField;
	private var spellField:TextField;
	private var fill:Sprite;
	private var markers:Sprite;

	private var lastBoss:BossEnemy = null;
	private var lastPhase:Int = -1;
	private var spellFlash:Int = 0;

	public function new(stageWidth:Int, fontName:String) {
		super();

		// Leave room for the FPS counter (top-left) and the HUD panel (top-right)
		x = 70;
		y = 8;
		barWidth = stageWidth - 70 - 270;
		mouseEnabled = false;
		visible = false;

		var nameFormat = new TextFormat(fontName, 15, 0xffffff, true);
		nameField = makeField(nameFormat, 0, 0, barWidth * 0.5);

		var spellFormat = new TextFormat(fontName, 15, 0xffd766, true);
		spellFormat.align = TextFormatAlign.RIGHT;
		spellField = makeField(spellFormat, barWidth * 0.35, 0, barWidth * 0.65);

		// Bar backing
		graphics.beginFill(0x0d0d16, 0.7);
		graphics.drawRoundRect(0, ROW_HEIGHT + 2, barWidth, BAR_HEIGHT + 4, 8, 8);
		graphics.endFill();
		graphics.lineStyle(1, 0x8899cc, 0.5);
		graphics.drawRoundRect(0, ROW_HEIGHT + 2, barWidth, BAR_HEIGHT + 4, 8, 8);

		fill = new Sprite();
		fill.x = 2;
		fill.y = ROW_HEIGHT + 4;
		addChild(fill);

		markers = new Sprite();
		markers.y = 10;
		addChild(markers);
	}

	private function makeField(format:TextFormat, x:Float, y:Float, width:Float):TextField {
		var field = new TextField();
		field.embedFonts = true;
		field.defaultTextFormat = format;
		field.selectable = false;
		field.x = x;
		field.y = y;
		field.width = width;
		field.height = ROW_HEIGHT;
		addChild(field);
		return field;
	}

	/** Call once per frame with getActiveBoss() (null hides the bar). */
	public function track(boss:BossEnemy):Void {
		if (boss == null) {
			visible = false;
			lastBoss = null;
			lastPhase = -1;
			return;
		}
		visible = true;

		if (boss != lastBoss || boss.getPhaseIndex() != lastPhase) {
			lastBoss = boss;
			lastPhase = boss.getPhaseIndex();
			refreshLabels(boss);
			spellFlash = SPELL_FLASH_FRAMES;
		}

		// Spell card name fades/slides in at the start of each phase
		if (spellFlash > 0) {
			spellFlash--;
			var t = 1 - spellFlash / SPELL_FLASH_FRAMES;
			spellField.alpha = t;
			spellField.y = -6 * (1 - t);
		}

		redrawFill(boss);
	}

	private function refreshLabels(boss:BossEnemy):Void {
		nameField.text = boss.getBossName();
		var spell = boss.getPhaseName();
		spellField.text = spell;

		// One dot per phase still to come after the current one
		markers.graphics.clear();
		var remaining = boss.getPhaseCount() - boss.getPhaseIndex() - 1;
		var nameWidth = nameField.textWidth + 8;
		for (i in 0...remaining) {
			markers.graphics.beginFill(0xffd766);
			markers.graphics.drawCircle(nameWidth + 10 + i * 14, 0, 4);
			markers.graphics.endFill();
		}
	}

	private function redrawFill(boss:BossEnemy):Void {
		var fraction:Float = boss.getPhaseHealth() / boss.getPhaseMaxHealth();
		if (fraction < 0) fraction = 0;

		var remaining = boss.getPhaseCount() - boss.getPhaseIndex() - 1;
		var color = PHASE_COLORS[remaining < PHASE_COLORS.length ? remaining : PHASE_COLORS.length - 1];

		fill.graphics.clear();
		if (fraction > 0) {
			fill.graphics.beginFill(color, boss.isInvulnerable() ? 0.45 : 0.9);
			fill.graphics.drawRoundRect(0, 0, (barWidth - 4) * fraction, BAR_HEIGHT, 6, 6);
			fill.graphics.endFill();
		}
	}
}
