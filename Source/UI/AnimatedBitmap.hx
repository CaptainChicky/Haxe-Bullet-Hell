package ui;

import manager.SpriteFrames;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;

/**
 * A strip of frames, centered on this sprite's origin (same as the static
 * Bitmap enemies and bullets already center).
 *
 * There is no ENTER_FRAME listener. The owner calls advance() once from its
 * own update — BulletEnemy.update, which CollisionManager drives, and
 * Enemy.update, which EnemyManager drives. Both of those are skipped while
 * Main.gamePaused is set, so an ESC pause freezes the animation on whatever
 * cell it was showing.
 *
 * `fps` is in animation-frames per second against the 60 fps game clock.
 * One advance() banks `fps` and steps once per 60 banked (fps 8 steps on
 * the 8th, 15th, 23rd... call; fps 60 steps every call).
 *
 * mode:
 *   loop     — 0,1,2,...,0
 *   once     — play through and hold the last frame
 *   pingpong — 0,1,2,3,2,1,0,1,... (the ends are not repeated)
 */
class AnimatedBitmap extends Sprite {
	public var frameIndex(default, null):Int = 0;
	public var frameCount(get, never):Int;

	inline function get_frameCount():Int {
		return frames.length;
	}

	private var frames:Array<BitmapData>;
	private var bitmap:Bitmap;
	private var fps:Float;
	private var mode:String;
	private var direction:Int = 1;
	private var bank:Float = 0;
	private var finished:Bool = false;

	public function new(frames:Array<BitmapData>, fps:Float, mode:String) {
		super();
		this.frames = frames;
		this.fps = fps;
		this.mode = (mode == null) ? SpriteFrames.MODE_LOOP : mode;
		bitmap = new Bitmap(frames[0]);
		addChild(bitmap);
		place(frames[0]);
	}

	public function currentBitmapData():BitmapData {
		return bitmap.bitmapData;
	}

	public function advance():Void {
		if (finished || fps <= 0 || frames.length <= 1) return;
		bank += fps;
		while (bank >= 60) {
			bank -= 60;
			if (!step()) {
				finished = true;
				bank = 0;
				return;
			}
		}
	}

	/** False when a "once" clip is already holding its last frame. */
	private function step():Bool {
		switch (mode) {
			case SpriteFrames.MODE_ONCE:
				if (frameIndex >= frames.length - 1) return false;
				setFrame(frameIndex + 1);
				return true;
			case SpriteFrames.MODE_PINGPONG:
				if (frames.length <= 1) return false;
				var next = frameIndex + direction;
				if (next >= frames.length || next < 0) {
					direction = -direction;
					next = frameIndex + direction;
				}
				setFrame(next);
				return true;
			default:
				setFrame((frameIndex + 1) % frames.length);
				return true;
		}
	}

	private function setFrame(index:Int):Void {
		frameIndex = index;
		var data = frames[index];
		bitmap.bitmapData = data;
		place(data);
	}

	/** Float division: an odd cell must sit at -w/2, not a truncated integer. */
	private function place(data:BitmapData):Void {
		bitmap.x = -data.width / 2.0;
		bitmap.y = -data.height / 2.0;
	}
}
