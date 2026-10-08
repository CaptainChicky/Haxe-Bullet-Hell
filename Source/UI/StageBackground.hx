package ui;

import openfl.display.GradientType;
import openfl.display.Sprite;
import openfl.geom.Matrix;

/** One parallax layer: a pattern tile drawn twice, scrolled and wrapped. */
private typedef Layer = {
	var container:Sprite;
	var speed:Float;
}

/**
 * Procedural scrolling stage background (no art assets): a soft vertical
 * gradient plus three parallax layers of translucent shapes drifting downward
 * (the classic "flying forward" read). Colors are deliberately pale pastels so
 * bullets and enemies keep their contrast — the playfield used to be plain
 * white. Each stage gets its own palette via setTheme(); Main drives update()
 * once per unpaused frame.
 */
class StageBackground extends Sprite {
	// Per-stage palettes: [gradient top, gradient bottom, shape tint]
	private static final THEMES:Array<Array<Int>> = [
		[0xeef4ff, 0xdde8fa, 0xb8cdee], // stage 1: pale sky
		[0xeffaef, 0xdcf0dd, 0xb5dcb8], // stage 2: pale meadow
		[0xf5effa, 0xe8dcf2, 0xcdb4e0], // stage 3: pale dusk
		[0xfdf5e8, 0xf7e7cc, 0xe8cfa0], // stage 4: pale gold
	];

	private var fieldWidth:Int;
	private var fieldHeight:Int;
	private var layers:Array<Layer> = [];
	private var gradient:Sprite;
	private var themeNumber:Int = 1;
	private var spellMode:Bool = false;

	public function new(fieldWidth:Int, fieldHeight:Int) {
		super();
		this.fieldWidth = fieldWidth;
		this.fieldHeight = fieldHeight;
		mouseEnabled = false;
		mouseChildren = false;

		gradient = new Sprite();
		addChild(gradient);

		setTheme(1);
	}

	/** Rebuild all layers with the palette for a 1-based stage number. */
	public function setTheme(stageNumber:Int):Void {
		themeNumber = stageNumber;
		spellMode = false;
		rebuildTheme();
	}

	/** Darken the current stage gradient during an active spell card. */
	public function setSpellMode(active:Bool):Void {
		if (spellMode == active) {
			return;
		}
		spellMode = active;
		rebuildTheme();
	}

	private function rebuildTheme():Void {
		var palette = THEMES[(themeNumber - 1) % THEMES.length];
		var top = palette[0];
		var bottom = palette[1];
		var shape = palette[2];
		if (spellMode) {
			top = darken(top, 0.55);
			bottom = darken(bottom, 0.55);
			shape = darken(shape, 0.65);
		}

		gradient.graphics.clear();
		var matrix = new Matrix();
		matrix.createGradientBox(fieldWidth, fieldHeight, Math.PI / 2);
		gradient.graphics.beginGradientFill(GradientType.LINEAR, [top, bottom], [1, 1], [0, 255], matrix);
		gradient.graphics.drawRect(0, 0, fieldWidth, fieldHeight);
		gradient.graphics.endFill();

		for (layer in layers) {
			removeChild(layer.container);
		}
		layers = [];

		// Back to front: big slow soft blobs, mid drifters, fast small flecks
		addLayer(shape, 0.4, 6, 60, 110, spellMode ? 0.14 : 0.20);
		addLayer(shape, 1.0, 9, 24, 46, spellMode ? 0.11 : 0.16);
		addLayer(shape, 2.2, 14, 4, 9, spellMode ? 0.15 : 0.22);
	}

	private function darken(color:Int, factor:Float):Int {
		var r = Std.int(((color >> 16) & 0xff) * factor);
		var g = Std.int(((color >> 8) & 0xff) * factor);
		var b = Std.int((color & 0xff) * factor);
		return (r << 16) | (g << 8) | b;
	}

	/** Build one wrapping layer of `count` random circles per tile. */
	private function addLayer(color:Int, speed:Float, count:Int, minR:Float, maxR:Float, alpha:Float):Void {
		var container = new Sprite();

		// One random shape set, drawn into two identical tiles stacked exactly
		// a field-height apart — the wrap snap is then seamless.
		var shapes:Array<{x:Float, y:Float, r:Float}> = [];
		for (i in 0...count) {
			shapes.push({
				x: Math.random() * fieldWidth,
				y: Math.random() * fieldHeight,
				r: minR + Math.random() * (maxR - minR)
			});
		}

		for (tile in 0...2) {
			var tileSprite = new Sprite();
			tileSprite.y = (tile - 1) * fieldHeight; // tiles at -H and 0
			tileSprite.graphics.beginFill(color, alpha);
			for (shape in shapes) {
				tileSprite.graphics.drawCircle(shape.x, shape.y, shape.r);
			}
			tileSprite.graphics.endFill();
			container.addChild(tileSprite);
		}

		container.y = 0;
		addChild(container);
		layers.push({container: container, speed: speed});
	}

	/** Scroll one frame (call only while unpaused; freezing with pause). */
	public function update():Void {
		for (layer in layers) {
			layer.container.y += layer.speed;
			if (layer.container.y >= fieldHeight) {
				layer.container.y -= fieldHeight;
			}
		}
	}
}
