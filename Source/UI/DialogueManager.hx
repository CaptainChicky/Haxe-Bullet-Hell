package ui;

import manager.LevelData.DialogueEntryData;
import openfl.Assets;
import openfl.display.Bitmap;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;

/**
 * Modal dialogue overlay: portrait + speaker name + typewritten text box at
 * the bottom of the screen. Driven by an array of DialogueEntryData (from
 * level JSON). Main routes Z/Space to advance() while isActive().
 *
 * First advance() while text is still typing reveals the full line;
 * the next one moves to the following entry. Completing the last entry
 * hides the overlay and fires the completion callback.
 */
class DialogueManager extends Sprite {
	private static inline final BOX_HEIGHT:Int = 170;
	private static inline final BOX_MARGIN:Int = 40;
	private static inline final PORTRAIT_SIZE:Int = 120;
	private static inline final CHARS_PER_FRAME:Float = 1.5;

	private var stageWidth:Int;
	private var stageHeight:Int;
	private var fontName:String;

	private var entries:Array<DialogueEntryData> = null;
	private var entryIndex:Int = 0;
	private var onComplete:Void->Void = null;

	// Typewriter state
	private var fullText:String = "";
	private var charsShown:Float = 0;

	// Display parts (rebuilt per entry)
	private var box:Sprite;
	private var portraitHolder:Sprite;
	private var nameField:TextField;
	private var textField:TextField;
	private var advanceArrow:Sprite;
	private var arrowBlink:Int = 0;

	public function new(stageWidth:Int, stageHeight:Int, fontName:String) {
		super();
		this.stageWidth = stageWidth;
		this.stageHeight = stageHeight;
		this.fontName = fontName;
		visible = false;
		mouseEnabled = false;

		buildBox();
		addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	private function buildBox():Void {
		var boxWidth = stageWidth - BOX_MARGIN * 2;
		var boxY = stageHeight - BOX_HEIGHT - BOX_MARGIN;

		box = new Sprite();
		box.graphics.beginFill(0x0d0d16, 0.88);
		box.graphics.drawRoundRect(0, 0, boxWidth, BOX_HEIGHT, 18, 18);
		box.graphics.endFill();
		box.graphics.lineStyle(2, 0x8899cc, 0.9);
		box.graphics.drawRoundRect(0, 0, boxWidth, BOX_HEIGHT, 18, 18);
		box.x = BOX_MARGIN;
		box.y = boxY;
		addChild(box);

		portraitHolder = new Sprite();
		box.addChild(portraitHolder);

		var nameFormat = new TextFormat(fontName, 18, 0xffd766, true);
		nameField = new TextField();
		nameField.embedFonts = true;
		nameField.defaultTextFormat = nameFormat;
		nameField.selectable = false;
		nameField.autoSize = TextFieldAutoSize.LEFT;
		box.addChild(nameField);

		var textFormat = new TextFormat(fontName, 19, 0xf0f0f0);
		textFormat.leading = 6;
		textField = new TextField();
		textField.embedFonts = true;
		textField.defaultTextFormat = textFormat;
		textField.selectable = false;
		textField.multiline = true;
		textField.wordWrap = true;
		box.addChild(textField);

		// Advance indicator: a small drawn triangle (the embedded font has no
		// reliable glyph for ▼ on native targets).
		advanceArrow = new Sprite();
		advanceArrow.graphics.beginFill(0x8899cc);
		advanceArrow.graphics.moveTo(-7, -5);
		advanceArrow.graphics.lineTo(7, -5);
		advanceArrow.graphics.lineTo(0, 5);
		advanceArrow.graphics.endFill();
		advanceArrow.x = boxWidth - 28;
		advanceArrow.y = BOX_HEIGHT - 24;
		advanceArrow.visible = false;
		box.addChild(advanceArrow);
	}

	/** Begin a conversation. Fires onComplete after the last entry is advanced. */
	public function start(entries:Array<DialogueEntryData>, onComplete:Void->Void):Void {
		if (entries == null || entries.length == 0) {
			if (onComplete != null) onComplete();
			return;
		}
		this.entries = entries;
		this.entryIndex = 0;
		this.onComplete = onComplete;
		visible = true;
		showEntry(entries[0]);
	}

	public function isActive():Bool {
		return entries != null;
	}

	/** Z/Space pressed: reveal remaining text, or move to the next entry. */
	public function advance():Void {
		if (entries == null) return;

		if (charsShown < fullText.length) {
			charsShown = fullText.length;
			textField.text = fullText;
			return;
		}

		entryIndex++;
		if (entryIndex < entries.length) {
			showEntry(entries[entryIndex]);
		} else {
			finish();
		}
	}

	/** Abort mid-conversation without firing the callback (run restart). */
	public function cancel():Void {
		entries = null;
		onComplete = null;
		visible = false;
	}

	private function finish():Void {
		var done = onComplete;
		entries = null;
		onComplete = null;
		visible = false;
		if (done != null) done();
	}

	private function showEntry(entry:DialogueEntryData):Void {
		fullText = (entry.text != null) ? entry.text : "";
		charsShown = 0;
		textField.text = "";
		advanceArrow.visible = false;

		// Portrait (optional; silently skipped if the asset is missing)
		while (portraitHolder.numChildren > 0)
			portraitHolder.removeChildAt(0);
		var hasPortrait = false;
		if (entry.portrait != null && Assets.exists(entry.portrait)) {
			var bmd = Assets.getBitmapData(entry.portrait);
			if (bmd != null) {
				var bmp = new Bitmap(bmd);
				bmp.smoothing = true;
				var scale = Math.min(PORTRAIT_SIZE / bmd.width, PORTRAIT_SIZE / bmd.height);
				bmp.scaleX = bmp.scaleY = scale;
				bmp.x = -bmd.width * scale / 2;
				bmp.y = -bmd.height * scale / 2;
				portraitHolder.addChild(bmp);
				hasPortrait = true;
			}
		}

		// Layout: portrait on the speaker's side, text fills the rest.
		var boxWidth = stageWidth - BOX_MARGIN * 2;
		var onRight = (entry.side == "right");
		var portraitPad = hasPortrait ? PORTRAIT_SIZE + 40 : 24;
		portraitHolder.x = onRight ? boxWidth - PORTRAIT_SIZE / 2 - 24 : PORTRAIT_SIZE / 2 + 24;
		portraitHolder.y = BOX_HEIGHT / 2;
		portraitHolder.visible = hasPortrait;

		var textX = onRight ? 24 : portraitPad;
		var textWidth = boxWidth - portraitPad - 24 - (onRight ? 24 : 0);
		nameField.x = textX;
		nameField.y = 16;
		nameField.text = (entry.speaker != null) ? entry.speaker : "";
		textField.x = textX;
		textField.y = 48;
		textField.width = textWidth;
		textField.height = BOX_HEIGHT - 60;
	}

	private function everyFrame(event:Event):Void {
		if (Main.gamePaused) return;
		if (entries == null) return;

		// Typewriter reveal
		if (charsShown < fullText.length) {
			charsShown += CHARS_PER_FRAME;
			if (charsShown > fullText.length) charsShown = fullText.length;
			textField.text = fullText.substr(0, Std.int(charsShown));
		} else {
			// Blinking advance indicator once the line is fully shown
			arrowBlink++;
			advanceArrow.visible = (Std.int(arrowBlink / 20) % 2 == 0);
		}
	}
}
