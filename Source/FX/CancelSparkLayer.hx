package fx;

import openfl.display.Shape;
import openfl.display.Sprite;

/**
 * Pooled vector star sparks when enemy bullets are cancelled (bomb, phase wipe).
 * Parent to Main.world; driven from CollisionManager.updateBullets (no own listener).
 */
class CancelSparkLayer extends Sprite {
	public static var instance:CancelSparkLayer = null;

	private static inline final MAX_ACTIVE:Int = 200;
	private static inline final POOL_SIZE:Int = 220;
	private static inline final LIFETIME:Int = 14;

	private var pool:Array<Spark> = [];
	private var active:Array<Spark> = [];

	public function new() {
		super();
		instance = this;
		mouseEnabled = false;
		for (i in 0...POOL_SIZE) {
			pool.push(new Spark());
		}
	}

	public function spawnAt(x:Float, y:Float):Void {
		if (active.length >= MAX_ACTIVE) return;
		var spark = pool.pop();
		if (spark == null) return;
		spark.begin(x, y, LIFETIME);
		addChild(spark);
		active.push(spark);
	}

	public function update():Void {
		var i = active.length - 1;
		while (i >= 0) {
			if (!active[i].tick()) {
				var spark = active.splice(i, 1)[0];
				removeChild(spark);
				pool.push(spark);
			}
			i--;
		}
	}
}

private class Spark extends Shape {
	private var life:Int = 0;
	private var maxLife:Int = 1;
	private var vx:Float = 0;
	private var vy:Float = 0;
	private var baseScale:Float = 1;

	public function new() {
		super();
		graphics.beginFill(0xfff0a8, 1);
		graphics.moveTo(6, 0);
		graphics.lineTo(1.5, 1.5);
		graphics.lineTo(0, 6);
		graphics.lineTo(-1.5, 1.5);
		graphics.lineTo(-6, 0);
		graphics.lineTo(-1.5, -1.5);
		graphics.lineTo(0, -6);
		graphics.lineTo(1.5, -1.5);
		graphics.lineTo(6, 0);
		graphics.endFill();
	}

	public function begin(x:Float, y:Float, frames:Int):Void {
		this.x = x;
		this.y = y;
		maxLife = frames;
		life = frames;
		var angle = Math.random() * Math.PI * 2;
		var speed = 0.6 + Math.random() * 1.4;
		vx = Math.cos(angle) * speed;
		vy = Math.sin(angle) * speed;
		rotation = Math.random() * 360;
		baseScale = 0.9 + Math.random() * 0.4;
		visible = true;
		applyVisual();
	}

	public function tick():Bool {
		if (life <= 0) return false;
		x += vx;
		y += vy;
		vx *= 0.92;
		vy *= 0.92;
		life--;
		applyVisual();
		return life > 0;
	}

	private function applyVisual():Void {
		var t = life / maxLife;
		alpha = t;
		var s = baseScale * (0.4 + 0.6 * t);
		scaleX = scaleY = s;
	}
}
