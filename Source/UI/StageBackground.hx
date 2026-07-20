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
		var palette = THEMES[(stageNumber - 1) % THEMES.length];

		gradient.graphics.clear();
		var matrix = new Matrix();
		matrix.createGradientBox(fieldWidth, fieldHeight, Math.PI / 2);
		gradient.graphics.beginGradientFill(GradientType.LINEAR, [palette[0], palette[1]], [1, 1], [0, 255], matrix);
		gradient.graphics.drawRect(0, 0, fieldWidth, fieldHeight);
		gradient.graphics.endFill();

		for (layer in layers) {
			removeChild(layer.container);
		}
		layers = [];

		// Back to front: big slow soft blobs, mid drifters, fast small flecks
		addLayer(palette[2], 0.4, 6, 60, 110, 0.20);
		addLayer(palette[2], 1.0, 9, 24, 46, 0.16);
		addLayer(palette[2], 2.2, 14, 4, 9, 0.22);
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
