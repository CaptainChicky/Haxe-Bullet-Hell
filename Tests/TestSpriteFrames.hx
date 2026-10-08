import manager.SpriteLibrary;
import manager.SpriteFrames;
import ui.AnimatedBitmap;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

/**
 * Locks the animation-strip geometry with pixels, not with a second copy of
 * the layout math. Four solid rectangles are drawn left to right into a
 * bitmap; the cutter must hand those colors back in that order, and
 * AnimatedBitmap must show them only when advance() is called.
 *
 *   haxe -cp Source -cp Tests -main TestSpriteFrames -lib openfl -lib lime -neko Export/testframes.n
 *   neko Export/testframes.n
 */
class TestSpriteFrames {
	static inline var RED:UInt = 0xFFFF0000;
	static inline var GREEN:UInt = 0xFF00FF00;
	static inline var BLUE:UInt = 0xFF0000FF;
	static inline var YELLOW:UInt = 0xFFFFFF00;
	static inline var SENTINEL:UInt = 0xFF111111;

	static var failures = 0;

	static function check(cond:Bool, msg:String):Void {
		if (!cond) {
			failures++;
			Sys.println("FAIL: " + msg);
		} else {
			Sys.println("ok:   " + msg);
		}
	}

	static function paint(sheet:BitmapData, ox:Int, oy:Int, fw:Int, fh:Int, colors:Array<UInt>):Void {
		for (i in 0...colors.length) {
			sheet.fillRect(new Rectangle(ox + i * fw, oy, fw, fh), colors[i]);
		}
	}

	/** Every corner of the cell is `color`, so a one-pixel shift fails. */
	static function cellIs(frame:BitmapData, color:UInt, msg:String):Bool {
		if (frame == null) {
			check(false, msg + " (no frame)");
			return false;
		}
		var w = frame.width - 1;
		var h = frame.height - 1;
		var corners = [frame.getPixel32(0, 0), frame.getPixel32(w, 0), frame.getPixel32(0, h), frame.getPixel32(w, h)];
		for (pixel in corners) {
			if (pixel != color) {
				check(false, msg + " (pixel " + StringTools.hex(pixel, 8) + ", expected " + StringTools.hex(color, 8) + ")");
				return false;
			}
		}
		return true;
	}

	static function colorsOf(frames:Array<BitmapData>, colors:Array<UInt>, msg:String):Void {
		if (frames.length != colors.length) {
			check(false, msg + " (got " + frames.length + " frames, expected " + colors.length + ")");
			return;
		}
		var ok = true;
		for (i in 0...colors.length) {
			if (frames[i].width <= 0 || frames[i].height <= 0 || !cellIs(frames[i], colors[i], msg + " frame " + i)) {
				ok = false;
				break;
			}
		}
		if (ok) check(true, msg);
	}

	static function main():Void {
		var colors = [RED, GREEN, BLUE, YELLOW];

		// Explicit cell size. 4 cells of 5x4, packed from (0, 0).
		var fw = 5;
		var fh = 4;
		var packed = new BitmapData(fw * 4, fh, true, SENTINEL);
		paint(packed, 0, 0, fw, fh, colors);
		colorsOf(SpriteLibrary.cutFrames(packed, {source: "unused", frames: 4, frameW: fw, frameH: fh}), colors,
			"pixels: explicit frameW/frameH cuts four rectangles left to right");

		// rect is the first cell. The strip is inset so a cutter that starts
		// at (0, 0) or treats rect as the whole strip grabs the sentinel.
		var ox = 3;
		var oy = 2;
		var cell = 4;
		var inset = new BitmapData(24, 12, true, SENTINEL);
		paint(inset, ox, oy, cell, cell, colors);
		check(inset.getPixel32(0, 0) == SENTINEL, "pixels: the sheet outside the strip stays the sentinel");
		colorsOf(SpriteLibrary.cutFrames(inset, {source: "unused", frames: 4, rect: [ox, oy, cell, cell]}), colors,
			"pixels: rect is the first cell and the next three frames continue to its right");

		// No rect and no cell size: the sheet itself is the strip.
		var inferred = new BitmapData(fw * 4, fh, true, SENTINEL);
		paint(inferred, 0, 0, fw, fh, colors);
		colorsOf(SpriteLibrary.cutFrames(inferred, {source: "unused", frames: 4}), colors,
			"pixels: omitting frame size divides the sheet into four equal cells");

		// A skin with no frames does not go through the cutter. layout() is
		// what resolve() asks for, and a missing count yields no cells.
		check(SpriteFrames.layout(0, packed.width, packed.height).length == 0,
			"pixels: a skin with no frame count is not cut into a strip");

		var frames = SpriteLibrary.cutFrames(packed, {source: "unused", frames: 4, frameW: fw, frameH: fh, fps: 8, mode: "loop"});
		var anim = new AnimatedBitmap(frames, 60, "loop");
		check(anim.frameIndex == 0 && anim.currentBitmapData() == frames[0], "anim: starts on frame 0");
		// Not calling advance is the pause. The object has no clock of its own.
		check(anim.frameIndex == 0 && anim.currentBitmapData() == frames[0], "anim: without advance() the frame stays put");
		anim.advance();
		check(anim.frameIndex == 1 && anim.currentBitmapData() == frames[1] && anim.currentBitmapData().getPixel32(0, 0) == GREEN,
			"anim: one advance at 60 fps shows the next rectangle");
		anim.advance();
		anim.advance();
		check(anim.frameIndex == 3 && anim.currentBitmapData().getPixel32(0, 0) == YELLOW, "anim: loop reaches the last rectangle");
		anim.advance();
		check(anim.frameIndex == 0 && anim.currentBitmapData().getPixel32(0, 0) == RED, "anim: loop wraps to the first rectangle");

		var paced = new AnimatedBitmap(frames, 8, "loop");
		for (i in 0...7) paced.advance();
		check(paced.frameIndex == 0, "anim: fps 8 holds frame 0 for the first 7 calls");
		paced.advance();
		check(paced.frameIndex == 1, "anim: fps 8 steps on the 8th call");
		for (i in 0...6) paced.advance();
		check(paced.frameIndex == 1, "anim: fps 8 holds frame 1 for the next 6 calls");
		paced.advance();
		check(paced.frameIndex == 2, "anim: fps 8 steps again on the 15th call");

		var once = new AnimatedBitmap(frames, 60, "once");
		for (i in 0...6) once.advance();
		check(once.frameIndex == 3 && once.currentBitmapData().getPixel32(0, 0) == YELLOW,
			"anim: once plays to the last rectangle and holds it");

		var pong = new AnimatedBitmap(frames, 60, "pingpong");
		var seen:Array<Int> = [];
		for (i in 0...7) {
			pong.advance();
			seen.push(pong.frameIndex);
		}
		var pongOk = seen.length == 7;
		var expect = [1, 2, 3, 2, 1, 0, 1];
		if (pongOk) {
			for (i in 0...expect.length) {
				if (seen[i] != expect[i]) pongOk = false;
			}
		}
		check(pongOk, "anim: pingpong is 1,2,3,2,1,0,1 with the ends not repeated");

		var fast = new AnimatedBitmap(frames, 120, "loop");
		fast.advance();
		check(fast.frameIndex == 2, "anim: fps 120 steps two frames per call");

		Sys.println(failures == 0 ? "\nALL TESTS PASSED" : '\n$failures TEST(S) FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
