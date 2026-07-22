package manager;

import openfl.Lib;

/**
 * Display configuration.
 *
 * The game renders into a *fixed logical playfield* (LOGICAL_W x LOGICAL_H)
 * and OpenFL scales that to whatever the real window is — Main sets
 * StageScaleMode.SHOW_ALL, so the field is letterboxed/pillarboxed to fit and
 * never distorted. Everything gameplay-side (level coordinates, culling,
 * spawn math, UI layout) is written against the logical size and never sees
 * the physical resolution, so one build runs identically on any monitor.
 *
 * That indirection is also what makes windowed mode possible at all: the
 * window can be any size without changing the playfield, which used to be
 * captured from the live stage at startup.
 *
 * Mode is persisted to the app storage directory so it survives restarts.
 */
class DisplaySettings {
	/** Logical *stage* size — the canvas the whole game is composed on, and what
	 *  gets scaled to the window. Deliberately 16:9: SHOW_ALL preserves aspect,
	 *  so any mismatch between this ratio and the monitor's becomes letterbox
	 *  bars. At 16:9 the common case (nearly every modern display) fills edge
	 *  to edge with no bars at all; 4:3 or 21:9 monitors still get correct,
	 *  centred bars rather than a stretched or cropped picture. */
	public static inline final LOGICAL_W:Int = 1920;
	public static inline final LOGICAL_H:Int = 1080;

	/** Authored *playfield* size, a 1800x1080 box centred inside the stage.
	 *  Level scripts treat CX = 900 as the horizontal centre (see
	 *  tools/src/level*.js), so this width must stay 1800 — Main parents all
	 *  gameplay to a container shifted by FIELD_X so those coordinates keep
	 *  landing where they were authored to. */
	public static inline final FIELD_W:Int = 1800;
	public static inline final FIELD_H:Int = 1080;

	public static final FIELD_X:Int = Std.int((LOGICAL_W - FIELD_W) / 2);
	public static final FIELD_Y:Int = Std.int((LOGICAL_H - FIELD_H) / 2);

	public static inline final FULLSCREEN:Int = 0;
	public static inline final WINDOWED:Int = 1;

	public static final MODE_NAMES:Array<String> = ["Fullscreen", "Windowed"];

	/** Windowed presets. Every one is exactly LOGICAL_W:LOGICAL_H (16:9), so
	 *  windowed mode is purely "the same picture, smaller" — SHOW_ALL's fit
	 *  scale is uniform and no window size can ever introduce letterbox bars.
	 *  That is the whole point of the preset list rather than a free resize:
	 *  the player picks a magnification, not an aspect ratio.
	 *
	 *  Fallback only: these 1080p-era sizes are used when the display bounds
	 *  aren't known yet (during boot, or on html5). Once they are, the list is
	 *  rebuilt from the actual monitor — see refreshWindowSizes, without which
	 *  every option here is uselessly small on a 1440p or 4K panel. */
	private static var windowSizes:Array<Array<Int>> = [[960, 540], [1280, 720], [1600, 900]];

	/** Fractions of the largest usable 16:9 box, from small to large. The top
	 *  step is 1.0 on purpose: the largest windowed option should be as big as
	 *  a window can actually get, since anyone picking it wants the screen. */
	private static final SIZE_STEPS:Array<Float> = [0.55, 0.75, 1.0];

	/** Vertical pixels reserved for window chrome: the title bar (~32px) plus
	 *  the taskbar (~48px), with slack. Both sit *outside* the client area this
	 *  sizes, so a window given the full display height has its bottom edge
	 *  pushed off-screen. A fixed reserve rather than a percentage because
	 *  chrome is a constant number of pixels — scaling it with the display
	 *  wastes ~180px on a 4K panel, which is where the largest preset should
	 *  be gaining the most. */
	private static inline final CHROME_H:Float = 96;

	/** Rebuild the preset list from the display the window is actually on, so
	 *  "large" means large on a 4K panel too. Every entry is snapped to an
	 *  exact 16:9 ratio (height forced to a multiple of 9, width derived) —
	 *  approximate ratios would reintroduce the sub-pixel letterboxing the
	 *  preset list exists to avoid. */
	private static function refreshWindowSizes(displayWidth:Float, displayHeight:Float):Void {
		// Cap by width too: on an ultra-wide, height is the binding constraint,
		// but on a tall/rotated display the 16:9 box would overflow sideways.
		var maxH = displayHeight - CHROME_H;
		var maxByWidth = displayWidth * 9 / 16;
		if (maxByWidth < maxH) maxH = maxByWidth;

		var sizes:Array<Array<Int>> = [];
		for (step in SIZE_STEPS) {
			var units = Math.round(maxH * step / 9); // height in multiples of 9
			if (units < 30) units = 30; // never below 480x270, which is unplayable
			sizes.push([units * 16, units * 9]);
		}
		windowSizes = sizes;
		if (windowScale >= windowSizes.length) windowScale = windowSizes.length - 1;
	}

	/** Borderless desktop fullscreen, not an exclusive display-mode switch:
	 *  the window stays composited, so Win+Shift+S and other overlays can
	 *  capture it. Fullscreen is still the default — windowed is opt-in. */
	public static var mode:Int = FULLSCREEN;

	/** Index into windowSizes. Defaults to the middle step — on a 1080p display
	 *  that lands near 1280x720, and it scales up with the monitor. */
	public static var windowScale:Int = 1;

	public static function modeName():String {
		return MODE_NAMES[mode];
	}

	public static function windowedWidth():Int {
		return windowSizes[windowScale][0];
	}

	public static function windowedHeight():Int {
		return windowSizes[windowScale][1];
	}

	/** Human-readable window size, e.g. "1440 x 864". Only meaningful in
	 *  windowed mode; fullscreen always fills the display. */
	public static function windowSizeName():String {
		if (mode == FULLSCREEN) {
			return "-- (fullscreen)";
		}
		return windowedWidth() + " x " + windowedHeight();
	}

	public static function cycleMode():Void {
		mode = (mode + 1) % MODE_NAMES.length;
	}

	public static function cycleWindowScale(step:Int):Void {
		windowScale += step;
		if (windowScale < 0) {
			windowScale = windowSizes.length - 1;
		} else if (windowScale >= windowSizes.length) {
			windowScale = 0;
		}
	}

	/** Push the current mode onto the real window. Safe to call before the
	 *  window exists (html5 during boot) — it just does nothing. */
	public static function apply():Void {
		var window = (Lib.application != null) ? Lib.application.window : null;
		if (window == null) {
			return;
		}

		// Never lime's `window.fullscreen`: that is a real SDL display-mode
		// switch, which drops the window out of the compositor. Screen capture
		// then returns a stale frame (the last composited windowed one), which
		// is exactly the bug this replaces. Borderless + resize to the display
		// bounds is visually identical and stays capturable.
		window.fullscreen = false;

		var bounds = (window.display != null) ? window.display.bounds : null;

		// Re-derive the presets every time: window.display follows the window,
		// so dragging to a second monitor and reopening options offers sizes
		// that suit *that* monitor.
		if (bounds != null && bounds.width > 0 && bounds.height > 0) {
			refreshWindowSizes(bounds.width, bounds.height);
		}

		if (mode == FULLSCREEN) {
			window.borderless = true;
			if (bounds != null) {
				// Deliberately one pixel taller than the display, hanging one
				// pixel off the top. A borderless window whose rect *exactly*
				// matches the monitor rect gets promoted by DWM to independent
				// flip: the swapchain scans out directly and the window stops
				// being composited into the desktop surface. Screen capture
				// reads that surface, so Win+Shift+S then grabs the desktop
				// *behind* the game — the window appears to vanish. (The first
				// capture also demotes the window back to composition, which is
				// why the second attempt and every one after it worked.)
				//
				// Players reach for Win+Shift+S, not an in-game key, so this
				// has to work on the first press. Failing DWM's exact-match
				// test is what keeps the window composited.
				//
				// The overhang is invisible: SHOW_ALL centres the 1920x1080
				// logical stage in the 1082-tall window, putting content one
				// pixel down from the window top, i.e. exactly at display y=0.
				// Width is untouched so the fit scale stays 1.0.
				window.move(Std.int(bounds.x), Std.int(bounds.y) - 1);
				window.resize(Std.int(bounds.width), Std.int(bounds.height) + 2);
			}
			return;
		}

		window.borderless = false;

		var w = windowedWidth();
		var h = windowedHeight();
		window.resize(w, h);

		// Re-centre on whichever display the window is on; resizing from the
		// top-left otherwise leaves it hanging off the bottom-right.
		if (bounds != null) {
			window.move(Std.int(bounds.x + (bounds.width - w) / 2), Std.int(bounds.y + (bounds.height - h) / 2));
		}
	}

	/* PERSISTENCE */

	#if sys
	private static function settingsDir():String {
		return lime.system.System.applicationStorageDirectory;
	}

	private static function settingsPath():String {
		return settingsDir() + "display.json";
	}
	#end

	public static function load():Void {
		#if sys
		try {
			var path = settingsPath();
			if (!sys.FileSystem.exists(path)) {
				return;
			}
			var data:Dynamic = haxe.Json.parse(sys.io.File.getContent(path));
			if (Reflect.hasField(data, "mode")) {
				mode = clamp(Std.int(Reflect.field(data, "mode")), 0, MODE_NAMES.length - 1);
			}
			if (Reflect.hasField(data, "windowScale")) {
				windowScale = clamp(Std.int(Reflect.field(data, "windowScale")), 0, windowSizes.length - 1);
			}
		} catch (e:Dynamic) {
			// Corrupt or unreadable settings file: fall back to the defaults
			// rather than refusing to launch.
			trace("DisplaySettings: could not load settings (" + e + ")");
		}
		#end
	}

	public static function save():Void {
		#if sys
		try {
			var dir = settingsDir();
			if (dir != null && dir != "" && !sys.FileSystem.exists(dir)) {
				sys.FileSystem.createDirectory(dir);
			}
			sys.io.File.saveContent(settingsPath(), haxe.Json.stringify({
				mode: mode,
				windowScale: windowScale
			}));
		} catch (e:Dynamic) {
			trace("DisplaySettings: could not save settings (" + e + ")");
		}
		#end
	}

	private static function clamp(value:Int, min:Int, max:Int):Int {
		return value < min ? min : (value > max ? max : value);
	}
}
