package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * Top-right status panel: score, lives, bombs, power, shot type.
 *
 * Design notes:
 *  - Labels are small and dim on the left; values are bright and right-
 *    aligned so the eye finds the numbers, not the words.
 *  - Lives and bombs are drawn vector icons (hearts / sparks), not text —
 *    the embedded font can't be trusted for symbol glyphs on native.
 *  - Power is a segmented gauge (16 cells = 0.25 per cell, Touhou-style).
 *  - The whole panel fades to near-transparent when the player flies into
 *    its corner of the field (trackPlayer, called every frame by Main), so
 *    it never hides bullets in the top-right.
 */
class HUD extends Sprite {
	private static inline final PANEL_WIDTH:Int = 240;
	private static inline final PANEL_HEIGHT:Int = 158;
	private static inline final PAD:Int = 14;

	// Proximity fade: alpha target drops when the player is this close to
	// the panel's bounds (field pixels), easing between states.
	private static inline final FADE_MARGIN:Float = 150.0;
	private static inline final FADED_ALPHA:Float = 0.22;

	private static inline final LABEL_COLOR:Int = 0x9aa3c0;
	private static inline final ACCENT:Int = 0xffd766;

	private var scoreField:TextField;
	private var powerField:TextField;
	private var shotField:TextField;

	private var livesIcons:Sprite;
	private var bombsIcons:Sprite;
	private var powerBar:Sprite;

	private var fadeTarget:Float = 1.0;

	public function new(stageWidth:Int, fontName:String) {
		super();

		x = stageWidth - PANEL_WIDTH - 12;
		y = 12;
		mouseEnabled = false;
		mouseChildren = false;

		// Backing panel: dark card with a thin gold accent along the top
		graphics.beginFill(0x0d0d16, 0.72);
		graphics.drawRoundRect(0, 0, PANEL_WIDTH, PANEL_HEIGHT, 12, 12);
		graphics.endFill();
		graphics.lineStyle(1, 0x3a4260, 0.9);
		graphics.drawRoundRect(0, 0, PANEL_WIDTH, PANEL_HEIGHT, 12, 12);
		graphics.lineStyle();
		graphics.beginFill(ACCENT, 0.85);
		graphics.drawRoundRect(10, 0, PANEL_WIDTH - 20, 3, 2, 2);
		graphics.endFill();

		// SCORE row
		makeLabel(fontName, "SCORE", 12);
		scoreField = makeValue(fontName, 12 - 4, 19, ACCENT);

		// LIVES row (icons right-aligned)
		makeLabel(fontName, "LIVES", 46);
		livesIcons = new Sprite();
		livesIcons.y = 46 + 9;
		addChild(livesIcons);

		// BOMBS row
		makeLabel(fontName, "BOMBS", 70);
		bombsIcons = new Sprite();
		bombsIcons.y = 70 + 9;
		addChild(bombsIcons);

		// POWER row: numeric value + segmented gauge underneath
		makeLabel(fontName, "POWER", 96);
		powerField = makeValue(fontName, 96 - 3, 14, 0xffb066);
		powerBar = new Sprite();
		powerBar.x = PAD;
		powerBar.y = 118;
		addChild(powerBar);

		// SHOT row
		makeLabel(fontName, "SHOT", 134);
		shotField = makeValue(fontName, 134 - 2, 13, 0xccd2e8);
	}

	private function makeLabel(fontName:String, text:String, y:Float):TextField {
		var format = new TextFormat(fontName, 11, LABEL_COLOR, true);
		var field = new TextField();
		field.embedFonts = true;
		field.defaultTextFormat = format;
		field.selectable = false;
		field.width = 90;
		field.height = 18;
		field.x = PAD;
		field.y = y;
		field.text = text;
		addChild(field);
		return field;
	}

	private function makeValue(fontName:String, y:Float, size:Int, color:Int):TextField {
		var format = new TextFormat(fontName, size, color, true);
		format.align = TextFormatAlign.RIGHT;
		var field = new TextField();
		field.embedFonts = true;
		field.defaultTextFormat = format;
		field.selectable = false;
		field.width = PANEL_WIDTH - PAD * 2;
		field.height = size + 10;
		field.x = PAD;
		field.y = y;
		addChild(field);
		return field;
	}

	/** 1234567 -> "1,234,567" (embedded-font-safe: plain ASCII comma). */
	private static function formatNumber(value:Int):String {
		var s = Std.string(value);
		var out = "";
		var count = 0;
		var i = s.length - 1;
		while (i >= 0) {
			out = s.charAt(i) + out;
			count++;
			if (count % 3 == 0 && i > 0) out = "," + out;
			i--;
		}
		return out;
	}

	public function setScore(value:Int):Void {
		scoreField.text = formatNumber(value);
	}

	public function setLives(value:Int):Void {
		drawIconRow(livesIcons, value, drawHeart);
	}

	public function setBombs(value:Int):Void {
		drawIconRow(bombsIcons, value, drawSpark);
	}

	/** Draw up to 8 icons right-aligned inside the panel; 0 draws a dim dash. */
	private function drawIconRow(holder:Sprite, count:Int, draw:Sprite->Float->Float->Void):Void {
		holder.graphics.clear();
		while (holder.numChildren > 0) holder.removeChildAt(0);

		if (count <= 0) {
			holder.graphics.beginFill(0x555b70);
			holder.graphics.drawRect(PANEL_WIDTH - PAD - 12, 4, 12, 2);
			holder.graphics.endFill();
			return;
		}

		var shown = count > 8 ? 8 : count;
		var step = 18.0;
		var startX = PANEL_WIDTH - PAD - 7 - (shown - 1) * step;
		for (i in 0...shown) {
			draw(holder, startX + i * step, 6);
		}
	}

	/** Small vector heart centered on (cx, cy). */
	private function drawHeart(holder:Sprite, cx:Float, cy:Float):Void {
		var g = holder.graphics;
		g.lineStyle(1, 0x0d0d16, 0.8);
		g.beginFill(0xff7788);
		g.drawCircle(cx - 3, cy - 2.5, 3.6);
		g.drawCircle(cx + 3, cy - 2.5, 3.6);
		g.endFill();
		g.lineStyle();
		g.beginFill(0xff7788);
		g.moveTo(cx - 6.2, cy - 1);
		g.lineTo(cx + 6.2, cy - 1);
		g.lineTo(cx, cy + 6.5);
		g.lineTo(cx - 6.2, cy - 1);
		g.endFill();
	}

	/** Small four-point spark centered on (cx, cy). */
	private function drawSpark(holder:Sprite, cx:Float, cy:Float):Void {
		var g = holder.graphics;
		g.lineStyle(1, 0x0d0d16, 0.8);
		g.beginFill(0x88ccff);
		g.moveTo(cx, cy - 7);
		g.lineTo(cx + 2, cy - 2);
		g.lineTo(cx + 7, cy);
		g.lineTo(cx + 2, cy + 2);
		g.lineTo(cx, cy + 7);
		g.lineTo(cx - 2, cy + 2);
		g.lineTo(cx - 7, cy);
		g.lineTo(cx - 2, cy - 2);
		g.lineTo(cx, cy - 7);
		g.endFill();
		g.lineStyle();
	}

	public function setPower(value:Float, max:Float):Void {
		var maxed = value >= max;
		powerField.text = maxed ? "MAX" : formatPower(value);

		// Segmented gauge: one cell per 0.25 power
		var cells = Std.int(max * 4 + 0.5);
		var filled = Std.int(value * 4 + 0.5);
		var barW = PANEL_WIDTH - PAD * 2;
		var gap = 2.0;
		var cellW = (barW - gap * (cells - 1)) / cells;

		var g = powerBar.graphics;
		g.clear();
		for (i in 0...cells) {
			var cx = i * (cellW + gap);
			if (i < filled) {
				g.beginFill(maxed ? ACCENT : 0xff9955);
			} else {
				g.beginFill(0x2a2f45);
			}
			g.drawRoundRect(cx, 0, cellW, 8, 2, 2);
			g.endFill();
		}
		if (maxed) {
			// Glow line under a full gauge
			g.beginFill(ACCENT, 0.35);
			g.drawRoundRect(-2, -2, barW + 4, 12, 4, 4);
			g.endFill();
		}
	}

	/** Power is in 0.25 steps: always show two decimals ("1.25", "4.00"). */
	private static function formatPower(value:Float):String {
		var hundredths = Math.round(value * 100);
		var whole = Std.int(hundredths / 100);
		var frac = hundredths - whole * 100;
		return whole + "." + (frac < 10 ? "0" : "") + frac;
	}

	public function setShotType(name:String):Void {
		shotField.text = name;
	}

	/** Call once per frame with the player's field position: fades the panel
	 *  out when the player is fighting underneath it. */
	public function trackPlayer(px:Float, py:Float):Void {
		var inside = px > x - FADE_MARGIN
			&& px < x + PANEL_WIDTH + FADE_MARGIN
			&& py > y - FADE_MARGIN
			&& py < y + PANEL_HEIGHT + FADE_MARGIN;
		fadeTarget = inside ? FADED_ALPHA : 1.0;
		alpha += (fadeTarget - alpha) * 0.12;
	}
}
