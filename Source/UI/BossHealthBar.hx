package ui;

import enemy.BossEnemy;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * Boss status strip across the top of the screen: boss name, dots for the
 * phases still to come, the current phase's spell card name, and the phase
 * health bar — all on a dark backing panel (the playfield is white, so
 * unbacked text/dots were unreadable). A new phase also raises a large
 * centered spell card banner that holds, then fades.
 * Poll track() every frame from Main; it hides itself when no boss is alive.
 */
class BossHealthBar extends Sprite {
	private static inline final BAR_HEIGHT:Int = 10;
	private static inline final ROW_HEIGHT:Int = 22;
	private static inline final PANEL_PAD:Int = 8;

	// Spell card intro banner: slide/fade in, hold, fade out (frames)
	private static inline final BANNER_IN:Int = 20;
	private static inline final BANNER_HOLD:Int = 100;
	private static inline final BANNER_OUT:Int = 40;

	// Phase fill colors, indexed by phases REMAINING after this one
	// (final phase red, earlier phases cooler)
	private static final PHASE_COLORS:Array<Int> = [0xff5566, 0xffaa44, 0xffd766, 0x66ddff, 0xcc88ff];

	private var barWidth:Int;
	private var nameField:TextField;
	private var spellField:TextField;
	private var timerField:TextField;
	private var fill:Sprite;
	private var markers:Sprite;

	// Damage ghost: a pale bar that lags behind the real fill and eases down
	// toward it, so chunks of damage read as a visible "bite".
	private var ghostFraction:Float = 1.0;

	// Large centered spell card announcement (own panel, below the strip)
	private var banner:Sprite;
	private var bannerField:TextField;
	private var bannerFrames:Int = 0;
	private static inline final BANNER_TOTAL:Int = BANNER_IN + BANNER_HOLD + BANNER_OUT;

	private var lastBoss:BossEnemy = null;
	private var lastPhase:Int = -1;

	public function new(stageWidth:Int, fontName:String) {
		super();

		// Leave room for the FPS counter (top-left) and the HUD panel (top-right)
		x = 70;
		y = 8;
		barWidth = stageWidth - 70 - 270;
		mouseEnabled = false;
		visible = false;

		// Dark backing panel behind the whole strip (text row + bar)
		var panelH = ROW_HEIGHT + BAR_HEIGHT + PANEL_PAD * 2;
		graphics.beginFill(0x0d0d16, 0.85);
		graphics.drawRoundRect(-PANEL_PAD, -PANEL_PAD, barWidth + PANEL_PAD * 2, panelH, 12, 12);
		graphics.endFill();
		graphics.lineStyle(1, 0x8899cc, 0.5);
		graphics.drawRoundRect(-PANEL_PAD, -PANEL_PAD, barWidth + PANEL_PAD * 2, panelH, 12, 12);

		var nameFormat = new TextFormat(fontName, 15, 0xffffff, true);
		nameField = makeField(nameFormat, 0, 0, barWidth * 0.5);

		var spellFormat = new TextFormat(fontName, 15, 0xffd766, true);
		spellFormat.align = TextFormatAlign.RIGHT;
		spellField = makeField(spellFormat, barWidth * 0.35, 0, barWidth * 0.65 - 64);

		// Phase timeout countdown (seconds), far right of the text row.
		// Hidden when the phase has no timeout.
		var timerFormat = new TextFormat(fontName, 15, 0xffffff, true);
		timerFormat.align = TextFormatAlign.RIGHT;
		timerField = makeField(timerFormat, barWidth - 58, 0, 58);

		// Bar backing (inset track under the text row)
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

		// Centered spell card banner (positions relative to this strip's x)
		banner = new Sprite();
		banner.visible = false;
		banner.mouseEnabled = false;
		addChild(banner);

		var bannerFormat = new TextFormat(fontName, 28, 0xffd766, true);
		bannerFormat.align = TextFormatAlign.CENTER;
		bannerField = new TextField();
		bannerField.embedFonts = true;
		bannerField.defaultTextFormat = bannerFormat;
		bannerField.selectable = false;
		bannerField.width = barWidth;
		bannerField.height = 44;
		banner.addChild(bannerField);
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
			bannerFrames = 0;
			banner.visible = false;
			return;
		}
		visible = true;

		if (boss != lastBoss || boss.getPhaseIndex() != lastPhase) {
			lastBoss = boss;
			lastPhase = boss.getPhaseIndex();
			ghostFraction = 1.0;
			refreshLabels(boss);
			raiseBanner(boss);
		}

		updateBanner();
		updateTimer(boss);
		redrawFill(boss);
	}

	/** Countdown to the phase timeout; turns red in the last ten seconds. */
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
		spellField.text = boss.getPhaseName();

		// One dot per phase still to come after the current one, drawn as
		// bright discs with dark outline rings so they read on any backdrop.
		markers.graphics.clear();
		var remaining = boss.getPhaseCount() - boss.getPhaseIndex() - 1;
		var dotY = ROW_HEIGHT / 2 - 1;
		var dotX = nameField.textWidth + 16;
		for (i in 0...remaining) {
			markers.graphics.lineStyle(2, 0x0d0d16);
			markers.graphics.beginFill(0xffd766);
			markers.graphics.drawCircle(dotX + i * 16, dotY, 5);
			markers.graphics.endFill();
		}
	}

	/** Big centered spell card announcement at the start of each phase. */
	private function raiseBanner(boss:BossEnemy):Void {
		var spell = boss.getPhaseName();
		if (spell == null || spell.length == 0) {
			banner.visible = false;
			bannerFrames = 0;
			return;
		}
		bannerField.text = spell;

		// Size the panel to the text
		var w = bannerField.textWidth + 60;
		var h = bannerField.textHeight + 24;
		bannerField.width = w;
		bannerField.y = 10;
		banner.graphics.clear();
		banner.graphics.beginFill(0x0d0d16, 0.85);
		banner.graphics.drawRoundRect(0, 0, w, h, 14, 14);
		banner.graphics.endFill();
		banner.graphics.lineStyle(2, 0xffd766, 0.8);
		banner.graphics.drawRoundRect(0, 0, w, h, 14, 14);

		banner.x = (barWidth - w) / 2;
		banner.visible = true;
		bannerFrames = BANNER_TOTAL;
	}

	private function updateBanner():Void {
		if (bannerFrames <= 0) {
			return;
		}
		bannerFrames--;

		var sinceStart = BANNER_TOTAL - bannerFrames;
		var baseY = ROW_HEIGHT + BAR_HEIGHT + 40;
		if (sinceStart < BANNER_IN) {
			// Slide down + fade in
			var t = sinceStart / BANNER_IN;
			banner.alpha = t;
			banner.y = baseY - 18 * (1 - t);
		} else if (bannerFrames < BANNER_OUT) {
			// Fade out
			banner.alpha = bannerFrames / BANNER_OUT;
			banner.y = baseY;
		} else {
			banner.alpha = 1;
			banner.y = baseY;
		}

		if (bannerFrames == 0) {
			banner.visible = false;
		}
	}

	private function redrawFill(boss:BossEnemy):Void {
		var fraction:Float = boss.getPhaseHealth() / boss.getPhaseMaxHealth();
		if (fraction < 0) fraction = 0;

		// Ghost eases down toward the live fraction (snaps up on phase reset)
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
			// Bright core strip gives the bar depth
			fill.graphics.beginFill(0xffffff, barAlpha * 0.25);
			fill.graphics.drawRoundRect(1, 1.5, w - 2 > 0 ? w - 2 : 0, BAR_HEIGHT * 0.35, 3, 3);
			fill.graphics.endFill();
		}
	}
}
