package manager;

/**
 * Horizontal strip layout for an animated skin.
 *
 * Frame i occupies the pixel rectangle
 *   (originX + i * frameW, originY, frameW, frameH)
 * with no gaps and no second row. originX/originY are `rect`'s x/y when a
 * 4-element rect is set, otherwise 0,0.
 *
 * Cell size, in order:
 *   - frameW / frameH when those fields are set
 *   - otherwise rect's width / height, so rect is the *first cell*, not the
 *     bounding box of the whole strip
 *   - otherwise floor(sheetWidth / frameCount) by the full sheet height
 *
 * Cells that would extend past the sheet are omitted. A static skin (no
 * `frames`, or fewer than 2) does not come through here — SpriteLibrary
 * keeps the single-bitmap path for that.
 *
 * Tests/TestFoundation.hx locks these numbers, and Tests/TestSpriteFrames.hx
 * paints four solid rectangles in this order and checks the cut cells.
 */
typedef FrameRect = {
	var x:Int;
	var y:Int;
	var w:Int;
	var h:Int;
}

class SpriteFrames {
	public static inline final MODE_LOOP:String = "loop";
	public static inline final MODE_ONCE:String = "once";
	public static inline final MODE_PINGPONG:String = "pingpong";

	/** Playback rate used when an animated skin omits `fps`. */
	public static inline final DEFAULT_FPS:Float = 8.0;

	public static function layout(count:Int, sheetW:Int, sheetH:Int, ?rect:Array<Float>, ?frameW:Int, ?frameH:Int):Array<FrameRect> {
		var out:Array<FrameRect> = [];
		if (count < 2 || sheetW <= 0 || sheetH <= 0) return out;

		var hasRect = rect != null && rect.length == 4;
		var originX = hasRect ? Std.int(rect[0]) : 0;
		var originY = hasRect ? Std.int(rect[1]) : 0;
		if (originX < 0 || originY < 0) return out;

		var cellW = 0;
		var cellH = 0;
		if (frameW != null) {
			if (frameW <= 0) return out;
			cellW = frameW;
		} else if (hasRect) {
			cellW = Std.int(rect[2]);
		} else {
			cellW = Std.int(sheetW / count);
		}
		if (frameH != null) {
			if (frameH <= 0) return out;
			cellH = frameH;
		} else if (hasRect) {
			cellH = Std.int(rect[3]);
		} else {
			cellH = sheetH;
		}
		if (cellW <= 0 || cellH <= 0) return out;
		if (originY + cellH > sheetH) return out;

		for (i in 0...count) {
			var x = originX + i * cellW;
			if (x + cellW > sheetW) break;
			out.push({x: x, y: originY, w: cellW, h: cellH});
		}
		return out;
	}
}
