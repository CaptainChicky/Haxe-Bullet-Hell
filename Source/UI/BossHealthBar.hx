package ui;

import enemy.BossEnemy;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * Boss status strip: name, spell-phase history stars, optional capture bonus,
 * phase timeout, and health bar. Spell card names during a spell phase are
 * shown by SpellCardAnnounce (docked under this strip); nonspell phases omit
 * the spell title. Poll track() every frame from Main.
 */
class BossHealthBar extends Sprite {
	private static inline final BAR_HEIGHT:Int = 10;
	private static inline final ROW_HEIGHT:Int = 22;
	private static inline final PANEL_PAD:Int = 8;
	private static inline final STAR_ROW_Y:Int = ROW_HEIGHT + BAR_HEIGHT + 14;

	private static final PHASE_COLORS:Array<Int> = [0xff5566, 0xffaa44, 0xffd766, 0x66ddff, 0xcc88ff];

	private var barWidth:Int;
	private var nameField:TextField;
	private var bonusField:TextField;
	private var timerField:TextField;
	private var fill:Sprite;
	private var markers:Sprite;

	private var ghostFraction:Float = 1.0;

	private var lastBoss:BossEnemy = null;
	private var lastPhase:Int = -1;
	private var spellMode:Bool = false;
	private var bonusValue:Int = -1;

	public function new(stageWidth:Int, fontName:String) {
		super();

		x = 70;
		y = 8;
		barWidth = stageWidth - 70 - 270;
		mouseEnabled = false;
		visible = false;

		var panelH = ROW_HEIGHT + BAR_HEIGHT + PANEL_PAD * 2 + 14;
		graphics.beginFill(0x0d0d16, 0.85);
		graphics.drawRoundRect(-PANEL_PAD, -PANEL_PAD, barWidth + PANEL_PAD * 2, panelH, 12, 12);
		graphics.endFill();
		graphics.lineStyle(1, 0x8899cc, 0.5);
		graphics.drawRoundRect(-PANEL_PAD, -PANEL_PAD, barWidth + PANEL_PAD * 2, panelH, 12, 12);

		var nameFormat = new TextFormat(fontName, 15, 0xffffff, true);
		nameField = makeField(nameFormat, 0, 0, barWidth * 0.55);

		var bonusFormat = new TextFormat(fontName, 14, 0xffd766, true);
		bonusFormat.align = TextFormatAlign.RIGHT;
		bonusField = makeField(bonusFormat, barWidth * 0.4, 0, barWidth * 0.6 - 64);
		bonusField.visible = false;

		var timerFormat = new TextFormat(fontName, 15, 0xffffff, true);
		timerFormat.align = TextFormatAlign.RIGHT;
		timerField = makeField(timerFormat, barWidth - 58, 0, 58);

		graphics.lineStyle();
		graphics.beginFill(0x000000, 0.6);
		graphics.drawRoundRect(0, ROW_HEIGHT, barWidth, BAR_HEIGHT + 4, 8, 8);
		graphics.endFill();
		graphics.lineStyle(1, 0x8899cc, 0.7);
		graphics.drawRoundRect(0, ROW_HEIGHT, barWidth, BAR_HEIGHT + 4, 8, 8);

		fill = new Sprite();
		fill.x = 2;
		fill.y = ROW_HEIGHT + 2;
		addChild(fill);

		markers = new Sprite();
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

	public function setSpellMode(active:Bool):Void {
		spellMode = active;
	}

	public function setBonusDisplay(value:Int):Void {
		bonusValue = value;
		if (value < 0) {
			bonusField.visible = false;
			bonusField.text = "";
		} else {
			bonusField.visible = spellMode;
			bonusField.text = formatBonus(value);
		}
	}

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
			ghostFraction = 1.0;
			refreshLabels(boss);
		}

		updateTimer(boss);
		redrawFill(boss);
	}

	private function updateTimer(boss:BossEnemy):Void {
		var remaining = boss.getPhaseTimeoutRemaining();
		if (remaining < 0) {
			timerField.text = "";
			return;
		}
		var seconds = Std.int((remaining + 59) / 60);
		timerField.textColor = (seconds <= 10) ? 0xff5566 : 0xffffff;
		timerField.text = Std.string(seconds);
	}

	private function refreshLabels(boss:BossEnemy):Void {
		nameField.text = boss.getBossName();
		drawSpellStars(boss.countSpellPhasesRemaining());
	}

	private function drawSpellStars(remaining:Int):Void {
		markers.graphics.clear();
		if (remaining <= 0) {
			return;
		}
		var startX = nameField.textWidth + 20;
		for (i in 0...remaining) {
			drawStar(markers.graphics, startX + i * 18, STAR_ROW_Y, 6, 0xffd766, 0x0d0d16);
		}
	}

	private function drawStar(g:openfl.display.Graphics, cx:Float, cy:Float, r:Float, fillColor:Int, lineColor:Int):Void {
		g.lineStyle(2, lineColor, 1);
		g.beginFill(fillColor, 1);
		var points = 5;
		var inner = r * 0.45;
		for (i in 0...(points * 2)) {
			var angle = (i * Math.PI / points) - Math.PI / 2;
			var rad = (i % 2 == 0) ? r : inner;
			var px = cx + Math.cos(angle) * rad;
			var py = cy + Math.sin(angle) * rad;
			if (i == 0) {
				g.moveTo(px, py);
			} else {
				g.lineTo(px, py);
			}
		}
		g.lineTo(cx + Math.cos(-Math.PI / 2) * r, cy + Math.sin(-Math.PI / 2) * r);
		g.endFill();
	}

	private function formatBonus(value:Int):String {
		return Std.string(value);
	}

	private function redrawFill(boss:BossEnemy):Void {
		var fraction:Float = boss.getPhaseHealth() / boss.getPhaseMaxHealth();
		if (fraction < 0) fraction = 0;

		if (ghostFraction < fraction) ghostFraction = fraction;
		ghostFraction += (fraction - ghostFraction) * 0.06;

		var remaining = boss.getPhaseCount() - boss.getPhaseIndex() - 1;
		var color = PHASE_COLORS[remaining < PHASE_COLORS.length ? remaining : PHASE_COLORS.length - 1];

		fill.graphics.clear();
		if (ghostFraction > fraction + 0.002) {
			fill.graphics.beginFill(0xffffff, 0.35);
			fill.graphics.drawRoundRect(0, 0, (barWidth - 4) * ghostFraction, BAR_HEIGHT, 6, 6);
			fill.graphics.endFill();
		}
		if (fraction > 0) {
			var barAlpha = boss.isInvulnerable() ? 0.45 : 0.9;
			var w = (barWidth - 4) * fraction;
			fill.graphics.beginFill(color, barAlpha);
			fill.graphics.drawRoundRect(0, 0, w, BAR_HEIGHT, 6, 6);
			fill.graphics.endFill();
			fill.graphics.beginFill(0xffffff, barAlpha * 0.25);
			fill.graphics.drawRoundRect(1, 1.5, w - 2 > 0 ? w - 2 : 0, BAR_HEIGHT * 0.35, 3, 3);
			fill.graphics.endFill();
		}
	}
}
