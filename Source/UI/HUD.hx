package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * Top-right status column: score, lives, bombs.
 * Uses the embedded UI font (system fonts don't exist on native targets).
 */
class HUD extends Sprite {
	private var scoreField:TextField;
	private var livesField:TextField;
	private var bombsField:TextField;

	public function new(stageWidth:Int, fontName:String) {
		super();
		scoreField = makeField(stageWidth, fontName, 10);
		livesField = makeField(stageWidth, fontName, 36);
		bombsField = makeField(stageWidth, fontName, 62);
	}

	private function makeField(stageWidth:Int, fontName:String, y:Float):TextField {
		var format = new TextFormat(fontName, 16, 0x777777, true);
		format.align = TextFormatAlign.RIGHT;
		var field = new TextField();
		field.embedFonts = true;
		field.defaultTextFormat = format;
		field.selectable = false;
		field.width = 240;
		field.height = 24;
		field.x = stageWidth - field.width - 10;
		field.y = y;
		addChild(field);
		return field;
	}

	public function setScore(value:Int):Void {
		scoreField.text = "Score: " + value;
	}

	public function setLives(value:Int):Void {
		livesField.text = "Lives: " + value;
	}

	public function setBombs(value:Int):Void {
		bombsField.text = "Bombs: " + value;
	}
}
