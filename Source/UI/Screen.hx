package ui;

/**
 * One mode in the screen stack (the title panel, the run, and later the
 * Phase 6 menus).
 *
 * Main keeps the single raw keyCode listener. After the global keys (F11,
 * the options panel, ESC pause, music), it offers the event to whichever
 * screen is on top. `keyDown` / `keyUp` return true when that screen
 * consumed the key.
 *
 * `update` runs from Main.everyFrame, and only for the top screen. It is
 * not an ENTER_FRAME listener, so an ESC pause — which returns before the
 * screen is updated — freezes whatever the screen was driving.
 */
interface Screen {
	function enter():Void;
	function exit():Void;
	function update():Void;
	function keyDown(code:Int):Bool;
	function keyUp(code:Int):Bool;
}
