package ui;

import manager.DisplaySettings;
import openfl.Assets;
import openfl.display.Bitmap;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * Spell-card declaration overlay: optional boss cut-in sliding across the
 * playfield, large spell name that docks under the boss bar, field vignette,
 * and capture result toasts. Frame-driven via update() — no ENTER_FRAME.
 */
class SpellCardAnnounce extends Sprite {
	private static inline final CUTIN_FRAMES:Int = 60;
	private static inline final NAME_INTRO:Int = 45;
	private static inline final NAME_DOCK:Int = 30;
	private static inline final TOAST_IN:Int = 12;
	private static inline final TOAST_HOLD:Int = 90;
	private static inline final TOAST_OUT:Int = 30;

	private var fontName:String;
	private var stageWidth:Int;

	private var vignette:Sprite;
	private var portrait:Bitmap;
	private var nameLarge:TextField;
	private var nameDocked:TextField;
	private var toast:Sprite;
	private var toastField:TextField;

	private var ceremonyFrames:Int = 0;
	private var ceremonyActive:Bool = false;
	private var spellName:String = "";
	private var hasPortrait:Bool = false;

	private var toastFrames:Int = 0;

	public function new(stageWidth:Int, fontName:String) {
		super();
		this.stageWidth = stageWidth;
		this.fontName = fontName;
		mouseEnabled = false;
		mouseChildren = false;

		vignette = new Sprite();
		addChild(vignette);

		portrait = new Bitmap();
		portrait.smoothing = true;
		addChild(portrait);

		var largeFormat = new TextFormat(fontName, 36, 0xffd766, true);
		largeFormat.align = TextFormatAlign.RIGHT;
		nameLarge = makeField(largeFormat, 0, 0, 720, 52);
		addChild(nameLarge);

		var dockFormat = new TextFormat(fontName, 16, 0xffd766, true);
		nameDocked = makeField(dockFormat, 70, 52, stageWidth - 340, 22);
		nameDocked.visible = false;
		addChild(nameDocked);

		toast = new Sprite();
		toast.visible = false;
		toast.mouseEnabled = false;
		addChild(toast);
		var toastFormat = new TextFormat(fontName, 32, 0xffffff, true);
		toastFormat.align = TextFormatAlign.CENTER;
		toastField = makeField(toastFormat, 0, 0, 640, 44);
		toast.addChild(toastField);
	}

	private function makeField(format:TextFormat, x:Float, y:Float, w:Float, h:Float):TextField {
		var field = new TextField();
		field.embedFonts = true;
		field.defaultTextFormat = format;
		field.selectable = false;
		field.x = x;
		field.y = y;
		field.width = w;
		field.height = h;
		return field;
	}

	public function beginSpell(name:String, cutInPath:String):Void {
		spellName = name;
		ceremonyActive = true;
		ceremonyFrames = CUTIN_FRAMES + NAME_INTRO + NAME_DOCK;
		toastFrames = 0;
		toast.visible = false;

		nameLarge.text = name;
		nameLarge.visible = name.length > 0;
		nameDocked.text = name;
		nameDocked.visible = false;

		hasPortrait = false;
		portrait.visible = false;
		if (cutInPath != null && cutInPath.length > 0) {
			try {
				var data = Assets.getBitmapData(cutInPath);
				if (data != null) {
					portrait.bitmapData = data;
					var scale = 280 / data.height;
					portrait.scaleX = portrait.scaleY = scale;
					hasPortrait = true;
					portrait.visible = true;
					portrait.alpha = 0.92;
				}
			} catch (_:Dynamic) {}
		}

		if (!hasPortrait) {
			ceremonyFrames = NAME_INTRO + NAME_DOCK;
		}

		redrawVignette(0.45);
	}

	public function finishSpell():Void {
		ceremonyActive = false;
		ceremonyFrames = 0;
		portrait.visible = false;
		nameLarge.visible = false;
		nameDocked.visible = false;
		redrawVignette(0);
	}

	public function clearDockedName():Void {
		nameDocked.visible = false;
		nameDocked.text = "";
	}

	public function showToast(message:String, success:Bool):Void {
		toastField.text = message;
		toastField.textColor = success ? 0xffd766 : 0xff8899;
		var w = toastField.textWidth + 80;
		var h = toastField.textHeight + 32;
		toastField.width = w;
		toast.graphics.clear();
		toast.graphics.beginFill(0x0d0d16, 0.9);
		toast.graphics.drawRoundRect(0, 0, w, h, 16, 16);
		toast.graphics.endFill();
		toast.graphics.lineStyle(2, success ? 0xffd766 : 0xff8899, 0.85);
		toast.graphics.drawRoundRect(0, 0, w, h, 16, 16);
		toast.x = (stageWidth - w) / 2;
		toast.y = DisplaySettings.LOGICAL_H * 0.38;
		toast.visible = true;
		toast.alpha = 0;
		toastFrames = TOAST_IN + TOAST_HOLD + TOAST_OUT;
	}

	public function update():Void {
		if (ceremonyActive && ceremonyFrames > 0) {
			tickCeremony();
		}
		if (toastFrames > 0) {
			tickToast();
		}
	}

	private function tickCeremony():Void {
		ceremonyFrames--;
		var total = hasPortrait ? (CUTIN_FRAMES + NAME_INTRO + NAME_DOCK) : (NAME_INTRO + NAME_DOCK);
		var elapsed = total - ceremonyFrames;

		var fx = DisplaySettings.FIELD_X;
		var fy = DisplaySettings.FIELD_Y;
		var fw = DisplaySettings.FIELD_W;
		var fh = DisplaySettings.FIELD_H;

		if (hasPortrait && elapsed < CUTIN_FRAMES) {
			var t = elapsed / CUTIN_FRAMES;
			var ease = 1 - Math.pow(1 - t, 2);
			portrait.x = fx - 200 + (fw * 0.55) * ease;
			portrait.y = fy - 120 + (fh * 0.45) * ease;
			portrait.alpha = 0.35 + 0.57 * ease;
			nameLarge.visible = false;
			redrawVignette(0.45);
		} else {
			portrait.visible = false;
			var nameElapsed = hasPortrait ? elapsed - CUTIN_FRAMES : elapsed;
			if (nameElapsed < NAME_INTRO) {
				var t = nameElapsed / NAME_INTRO;
				var ease = 1 - Math.pow(1 - t, 3);
				nameLarge.visible = spellName.length > 0;
				nameLarge.alpha = ease;
				nameLarge.x = fx + fw * 0.22 + (fw * 0.35) * (1 - ease);
				nameLarge.y = fy + fh * 0.32;
				redrawVignette(0.42);
			} else if (nameElapsed < NAME_INTRO + NAME_DOCK) {
				var t = (nameElapsed - NAME_INTRO) / NAME_DOCK;
				var ease = t * t * (3 - 2 * t);
				nameLarge.visible = spellName.length > 0;
				nameLarge.alpha = 1 - ease * 0.85;
				nameLarge.x = fx + fw * 0.57;
				nameLarge.y = fy + fh * 0.32 + (52 - fy - fh * 0.32 + 52) * ease;
				nameDocked.visible = spellName.length > 0;
				nameDocked.alpha = ease;
				redrawVignette(0.38 - 0.18 * ease);
			} else {
				nameLarge.visible = false;
				nameDocked.visible = spellName.length > 0;
				nameDocked.alpha = 1;
				redrawVignette(0.2);
			}
		}

		if (ceremonyFrames == 0) {
			ceremonyActive = false;
			portrait.visible = false;
			nameLarge.visible = false;
		}
	}

	private function tickToast():Void {
		toastFrames--;
		var since = (TOAST_IN + TOAST_HOLD + TOAST_OUT) - toastFrames;
		if (since < TOAST_IN) {
			toast.alpha = since / TOAST_IN;
		} else if (toastFrames < TOAST_OUT) {
			toast.alpha = toastFrames / TOAST_OUT;
		} else {
			toast.alpha = 1;
		}
		if (toastFrames == 0) {
			toast.visible = false;
		}
	}

	private function redrawVignette(strength:Float):Void {
		vignette.graphics.clear();
		if (strength <= 0.001) {
			return;
		}
		var w = DisplaySettings.LOGICAL_W;
		var h = DisplaySettings.LOGICAL_H;
		var edge = 120;
		var a = strength;
		vignette.graphics.beginFill(0x000000, a);
		vignette.graphics.drawRect(0, 0, w, edge);
		vignette.graphics.drawRect(0, h - edge, w, edge);
		vignette.graphics.drawRect(0, 0, edge, h);
		vignette.graphics.drawRect(w - edge, 0, edge, h);
		vignette.graphics.endFill();
	}
}
