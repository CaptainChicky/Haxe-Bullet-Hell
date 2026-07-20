package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * Top-right status panel: score, lives, bombs, shot type.
 * Uses the embedded UI font (system fonts don't exist on native targets).
 */
class HUD extends Sprite {
	private static inline final PANEL_WIDTH:Int = 240;
	private static inline final ROW_HEIGHT:Int = 26;
	private static inline final PAD:Int = 12;

	private var scoreField:TextField;
	private var livesField:TextField;
	private var bombsField:TextField;
	private var powerField:TextField;
	private var shotField:TextField;

	public function new(stageWidth:Int, fontName:String) {
		super();

		// Subtle backing panel so the numbers read over any bullet pattern
		var rows = 5;
		var panelHeight = rows * ROW_HEIGHT + PAD * 2 - 6;
		graphics.beginFill(0x0d0d16, 0.55);
		graphics.drawRoundRect(0, 0, PANEL_WIDTH, panelHeight, 14, 14);
		graphics.endFill();
		graphics.lineStyle(1, 0x8899cc, 0.35);
		graphics.drawRoundRect(0, 0, PANEL_WIDTH, panelHeight, 14, 14);
		x = stageWidth - PANEL_WIDTH - 10;
		y = 10;
		mouseEnabled = false;

		scoreField = makeField(fontName, PAD + ROW_HEIGHT * 0, 0xffd766); // gold: the number that matters
		livesField = makeField(fontName, PAD + ROW_HEIGHT * 1, 0xff8899); // soft red
		bombsField = makeField(fontName, PAD + ROW_HEIGHT * 2, 0x99ccff); // soft blue
		powerField = makeField(fontName, PAD + ROW_HEIGHT * 3, 0xffaa66); // orange (power items)
		shotField = makeField(fontName, PAD + ROW_HEIGHT * 4, 0xbbbbcc); // neutral
	}

	private function makeField(fontName:String, y:Float, color:Int):TextField {
		var format = new TextFormat(fontName, 16, color, true);
		format.align = TextFormatAlign.RIGHT;
		var field = new TextField();
		field.embedFonts = true;
		field.defaultTextFormat = format;
		field.selectable = false;
		field.width = PANEL_WIDTH - PAD * 2;
		field.height = ROW_HEIGHT;
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
		scoreField.text = "Score  " + formatNumber(value);
	}

	public function setLives(value:Int):Void {
		livesField.text = "Lives  " + repeatMarks(value, 8);
	}

	public function setBombs(value:Int):Void {
		bombsField.text = "Bombs  " + repeatMarks(value, 8);
	}

	public function setPower(value:Float, max:Float):Void {
		powerField.text = (value >= max) ? "Power  MAX" : "Power  " + formatPower(value) + " / " + formatPower(max);
	}

	/** Power is in 0.25 steps: always show two decimals ("1.25", "4.00"). */
	private static function formatPower(value:Float):String {
		var hundredths = Math.round(value * 100);
		var whole = Std.int(hundredths / 100);
		var frac = hundredths - whole * 100;
		return whole + "." + (frac < 10 ? "0" : "") + frac;
	}

	public function setShotType(name:String):Void {
		shotField.text = "Shot  " + name;
	}

	/** Show small counts as tally marks ("* * *"), large ones as a number. */
	private static function repeatMarks(value:Int, cap:Int):String {
		if (value > cap) return Std.string(value);
		var out = "";
		for (i in 0...value) out += (i == 0 ? "*" : " *");
		if (value == 0) out = "-";
		return out;
	}
}
