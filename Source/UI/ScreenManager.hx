package ui;

/**
 * Stack of screens. push() enters the new top and leaves the screen under
 * it entered, so a submenu can pop back to it. replace() exits the old top
 * first — that is how the title panel and the run swap. Only the top screen
 * receives update and keys.
 */
class ScreenManager {
	private var stack:Array<Screen> = [];

	public function new() {}

	public function push(screen:Screen):Void {
		stack.push(screen);
		screen.enter();
	}

	/** Exit and remove the top screen. Null when the stack is empty. */
	public function pop():Screen {
		if (stack.length == 0) return null;
		var screen = stack.pop();
		screen.exit();
		return screen;
	}

	/** Exit the current top, then enter `screen` as the new top. */
	public function replace(screen:Screen):Void {
		pop();
		push(screen);
	}

	public function current():Screen {
		return stack.length == 0 ? null : stack[stack.length - 1];
	}

	public function size():Int {
		return stack.length;
	}

	public function update():Void {
		var screen = current();
		if (screen != null) screen.update();
	}

	public function keyDown(code:Int):Bool {
		var screen = current();
		return screen != null && screen.keyDown(code);
	}

	public function keyUp(code:Int):Bool {
		var screen = current();
		return screen != null && screen.keyUp(code);
	}
}
