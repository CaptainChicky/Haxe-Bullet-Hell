import manager.SpriteFrames;
import manager.SpriteFrames.FrameRect;
import ui.MenuList;
import ui.Screen;
import ui.ScreenManager;

/**
 * Screen stack, menu cursor, and sprite-strip geometry. No OpenFL — this
 * runs under `haxe --interp` with TestShot. The pixel lock for that geometry
 * is Tests/TestSpriteFrames.hx (four colored rectangles).
 */
class TestFoundation {
	public static function run():Int {
		var failures = 0;
		function check(cond:Bool, msg:String):Void {
			if (!cond) {
				failures++;
				Sys.println("FAIL: " + msg);
			} else {
				Sys.println("ok:   " + msg);
			}
		}

		menu(check);
		screens(check);
		layout(check);
		return failures;
	}

	static function menu(check:Bool->String->Void):Void {
		var list = new MenuList(4);
		var confirmed:Array<Int> = [];
		var backs = 0;
		list.onConfirm = function(i) confirmed.push(i);
		list.onBack = function() backs++;

		check(list.index == 0, "menu: starts on the first row");
		list.move(1);
		check(list.index == 1, "menu: down one row");
		list.move(1);
		list.move(1);
		list.move(1);
		check(list.index == 0, "menu: down wraps from the last row to the first");
		list.move(-1);
		check(list.index == 3, "menu: up wraps from the first row to the last");

		check(list.keyDown(MenuList.KEY_DOWN), "menu: DOWN is consumed");
		check(list.index == 0, "menu: DOWN from the last row wraps");
		check(list.keyDown(MenuList.KEY_UP), "menu: UP is consumed");
		check(list.index == 3, "menu: UP from the first row wraps");

		check(list.keyDown(MenuList.KEY_CONFIRM), "menu: Z is consumed");
		check(confirmed.length == 1 && confirmed[0] == 3, "menu: Z confirms the highlighted row");
		check(list.keyDown(MenuList.KEY_BACK), "menu: X is consumed");
		check(backs == 1, "menu: X goes back");

		check(!list.keyDown(37), "menu: LEFT is not a menu key");
		check(list.keyDown(32) == false, "menu: SPACE is not confirm");

		var bare = new MenuList(2);
		check(bare.keyDown(MenuList.KEY_CONFIRM), "menu: Z is consumed even with no confirm callback");
		check(bare.keyDown(MenuList.KEY_BACK), "menu: X is consumed even with no back callback");

		var empty = new MenuList(0);
		var emptyHits = 0;
		empty.onConfirm = function(_) emptyHits++;
		empty.move(1);
		empty.move(-1);
		check(empty.index == 0, "menu: empty list does not move");
		check(empty.keyDown(MenuList.KEY_CONFIRM), "menu: Z on an empty list is still consumed");
		check(emptyHits == 0, "menu: Z on an empty list does not confirm");

		var one = new MenuList(1);
		one.move(1);
		one.move(-1);
		check(one.index == 0, "menu: a single row stays put");
		one.reset();
		list.reset();
		check(list.index == 0, "menu: reset returns to the first row");
	}

	static function screens(check:Bool->String->Void):Void {
		var stack = new ScreenManager();
		var a = new FakeScreen();
		var b = new FakeScreen();
		var c = new FakeScreen();

		check(stack.pop() == null && stack.size() == 0, "screen: pop on an empty stack is a no-op");
		check(!stack.keyDown(1) && !stack.keyUp(1), "screen: keys on an empty stack are not consumed");
		stack.update();

		stack.push(a);
		check(stack.current() == a && a.enters == 1 && a.exits == 0, "screen: push enters the new top");
		stack.push(b);
		check(stack.current() == b && a.enters == 1 && a.exits == 0 && b.enters == 1,
			"screen: push leaves the screen underneath entered");

		stack.update();
		check(a.updates == 0 && b.updates == 1, "screen: only the top screen updates");
		check(stack.keyDown(7) && b.keys.length == 1 && b.keys[0] == 7 && a.keys.length == 0,
			"screen: keys go to the top screen and keep its return value");
		check(!stack.keyDown(1) && b.keys.length == 2, "screen: a screen may decline a key");

		var popped = stack.pop();
		check(popped == b && b.exits == 1 && stack.current() == a && a.exits == 0,
			"screen: pop exits the top and reveals the one under it");

		stack.replace(c);
		check(a.exits == 1 && c.enters == 1 && stack.current() == c && stack.size() == 1,
			"screen: replace exits the old top and enters the new one");

		var fresh = new ScreenManager();
		fresh.replace(a);
		check(fresh.current() == a && a.enters == 2, "screen: replace on an empty stack just enters");
	}

	static function layout(check:Bool->String->Void):Void {
		// These numbers are the sheet contract. TestSpriteFrames paints
		// rectangles at the same coordinates and checks the cut pixels.
		expect(check, SpriteFrames.layout(4, 20, 4, null, 5, 4),
			[{x: 0, y: 0, w: 5, h: 4}, {x: 5, y: 0, w: 5, h: 4}, {x: 10, y: 0, w: 5, h: 4}, {x: 15, y: 0, w: 5, h: 4}],
			"strip: explicit cell size, origin 0,0");
		expect(check, SpriteFrames.layout(4, 20, 4),
			[{x: 0, y: 0, w: 5, h: 4}, {x: 5, y: 0, w: 5, h: 4}, {x: 10, y: 0, w: 5, h: 4}, {x: 15, y: 0, w: 5, h: 4}],
			"strip: no rect and no cell size divides the sheet left to right");
		expect(check, SpriteFrames.layout(4, 30, 10, [3, 2, 4, 4]),
			[{x: 3, y: 2, w: 4, h: 4}, {x: 7, y: 2, w: 4, h: 4}, {x: 11, y: 2, w: 4, h: 4}, {x: 15, y: 2, w: 4, h: 4}],
			"strip: rect is the first cell, later frames sit immediately to its right");
		expect(check, SpriteFrames.layout(3, 40, 8, [4, 1, 99, 99], 6, 5),
			[{x: 4, y: 1, w: 6, h: 5}, {x: 10, y: 1, w: 6, h: 5}, {x: 16, y: 1, w: 6, h: 5}],
			"strip: frameW/frameH win over rect's width and height; rect still supplies the origin");
		expect(check, SpriteFrames.layout(4, 16, 4, null, 5, 4),
			[{x: 0, y: 0, w: 5, h: 4}, {x: 5, y: 0, w: 5, h: 4}, {x: 10, y: 0, w: 5, h: 4}],
			"strip: a cell that would hang off the sheet is dropped");
		expect(check, SpriteFrames.layout(4, 21, 4),
			[{x: 0, y: 0, w: 5, h: 4}, {x: 5, y: 0, w: 5, h: 4}, {x: 10, y: 0, w: 5, h: 4}, {x: 15, y: 0, w: 5, h: 4}],
			"strip: inferred cell width truncates, leftover columns are not a partial frame");
		expect(check, SpriteFrames.layout(1, 20, 4, null, 5, 4), [],
			"strip: a single frame is not an animation");
		expect(check, SpriteFrames.layout(4, 8, 2),
			[{x: 0, y: 0, w: 2, h: 2}, {x: 2, y: 0, w: 2, h: 2}, {x: 4, y: 0, w: 2, h: 2}, {x: 6, y: 0, w: 2, h: 2}],
			"strip: inferred height is the whole sheet");
		expect(check, SpriteFrames.layout(4, 20, 4, [-1, 0, 4, 4]), [],
			"strip: a negative origin cuts nothing");
		expect(check, SpriteFrames.layout(4, 20, 4, null, 0, 4), [],
			"strip: frameW of 0 cuts nothing");
		expect(check, SpriteFrames.layout(4, 20, 5, [0, 2, 4, 4]), [],
			"strip: a cell taller than the sheet cuts nothing");
	}

	static function expect(check:Bool->String->Void, got:Array<FrameRect>, exp:Array<FrameRect>, msg:String):Void {
		if (got.length != exp.length) {
			check(false, msg + " (got " + got.length + " frames, expected " + exp.length + ")");
			return;
		}
		for (i in 0...got.length) {
			var g = got[i];
			var e = exp[i];
			if (g.x != e.x || g.y != e.y || g.w != e.w || g.h != e.h) {
				check(false, msg + " (frame " + i + " is " + g.x + "," + g.y + " " + g.w + "x" + g.h
					+ ", expected " + e.x + "," + e.y + " " + e.w + "x" + e.h + ")");
				return;
			}
		}
		check(true, msg);
	}
}

class FakeScreen implements Screen {
	public var enters = 0;
	public var exits = 0;
	public var updates = 0;
	public var keys:Array<Int> = [];

	public function new() {}

	public function enter():Void enters++;

	public function exit():Void exits++;

	public function update():Void updates++;

	public function keyDown(code:Int):Bool {
		keys.push(code);
		return code != 1;
	}

	public function keyUp(code:Int):Bool {
		return false;
	}
}
