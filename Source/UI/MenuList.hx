package ui;

/**
 * Vertical menu cursor shared by every menu screen so they all navigate
 * the same way: UP/DOWN move and wrap, Z confirms the highlighted row,
 * X goes back.
 *
 * This is input only — the screen draws the rows. The options panel uses
 * `keyDown` for UP/DOWN (so wrap matches) but keeps its own LEFT/RIGHT
 * value editing and ESC-to-close; it does not confirm or back through Z/X.
 *
 * Key codes are the raw values Main already dispatches (no OpenFL import,
 * so the cursor can be tested under haxe --interp):
 *   UP 38, DOWN 40, Z 90, X 88.
 */
class MenuList {
	public static inline final KEY_UP:Int = 38;
	public static inline final KEY_DOWN:Int = 40;
	public static inline final KEY_CONFIRM:Int = 90; // Z
	public static inline final KEY_BACK:Int = 88; // X

	public var length(default, null):Int;
	public var index(default, null):Int = 0;

	/** Highlighted row. Not called when the list is empty. */
	public var onConfirm:Int->Void = null;

	public var onBack:Void->Void = null;

	public function new(length:Int) {
		this.length = length < 0 ? 0 : length;
	}

	public function reset():Void {
		index = 0;
	}

	/** Move by `delta` rows. Wraps in both directions. No-op when empty. */
	public function move(delta:Int):Void {
		if (length <= 0) return;
		index = (index + delta) % length;
		if (index < 0) index += length;
	}

	/**
	 * UP/DOWN/Z/X. Returns true when the key belongs to the menu, even if
	 * the matching callback is null, so Z does not fall through into
	 * shooting while a menu is up.
	 */
	public function keyDown(code:Int):Bool {
		switch (code) {
			case KEY_UP:
				move(-1);
				return true;
			case KEY_DOWN:
				move(1);
				return true;
			case KEY_CONFIRM:
				if (onConfirm != null && length > 0) onConfirm(index);
				return true;
			case KEY_BACK:
				if (onBack != null) onBack();
				return true;
			default:
				return false;
		}
	}
}
