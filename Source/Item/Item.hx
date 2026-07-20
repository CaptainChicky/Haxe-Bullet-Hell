package item;

import openfl.display.Sprite;

/** What an item grants when collected. */
enum ItemType {
	PowerItem; // +1 power (player shot strength)
	PointItem; // flat score bonus
	BombItem; // +1 bomb
	LifeItem; // +1 life
}

/**
 * One falling pickup. Vector-drawn (no art assets needed): each type has a
 * distinct color + glyph so they read at a glance over the white field.
 * Physics: small upward pop at spawn, gravity down to a terminal fall speed.
 * ItemManager drives update() and handles magnetism/collection.
 */
class Item extends Sprite {
	public static inline final RADIUS:Float = 9;

	private static inline final GRAVITY:Float = 0.12;
	private static inline final TERMINAL_FALL:Float = 2.4;
	private static inline final MAGNET_SPEED:Float = 11.0;

	public var itemType(default, null):ItemType;
	public var velocityX:Float;
	public var velocityY:Float;

	public function new(type:ItemType, ?scatter:Bool = true) {
		super();
		this.itemType = type;

		// Pop upward and slightly sideways, then fall
		velocityX = scatter ? (Math.random() - 0.5) * 2.0 : 0;
		velocityY = scatter ? -(2.0 + Math.random() * 1.5) : 0;

		draw();
		mouseEnabled = false;
	}

	private function draw():Void {
		var r = RADIUS;
		switch (itemType) {
			case PowerItem: // red square, white up-triangle ("more power")
				drawSquare(0xd42a3c);
				graphics.beginFill(0xffffff);
				graphics.moveTo(0, -r * 0.45);
				graphics.lineTo(r * 0.45, r * 0.35);
				graphics.lineTo(-r * 0.45, r * 0.35);
				graphics.endFill();

			case PointItem: // blue square, white inner dot
				drawSquare(0x2a66d4);
				graphics.beginFill(0xffffff);
				graphics.drawCircle(0, 0, r * 0.35);
				graphics.endFill();

			case BombItem: // green circle, white cross
				graphics.lineStyle(2, 0x0d0d16, 0.9);
				graphics.beginFill(0x2ab04a);
				graphics.drawCircle(0, 0, r);
				graphics.endFill();
				graphics.lineStyle();
				graphics.beginFill(0xffffff);
				graphics.drawRect(-r * 0.5, -r * 0.15, r, r * 0.3);
				graphics.drawRect(-r * 0.15, -r * 0.5, r * 0.3, r);
				graphics.endFill();

			case LifeItem: // magenta star
				graphics.lineStyle(2, 0x0d0d16, 0.9);
				graphics.beginFill(0xe040a0);
				drawStar(r * 1.2, r * 0.55, 5);
				graphics.endFill();
		}
	}

	private function drawSquare(color:Int):Void {
		var r = RADIUS;
		graphics.lineStyle(2, 0x0d0d16, 0.9);
		graphics.beginFill(color);
		graphics.drawRoundRect(-r, -r, r * 2, r * 2, 5, 5);
		graphics.endFill();
		graphics.lineStyle();
	}

	private function drawStar(outer:Float, inner:Float, points:Int):Void {
		var step = Math.PI / points;
		graphics.moveTo(0, -outer);
		for (i in 1...points * 2) {
			var radius = (i % 2 == 0) ? outer : inner;
			var angle = -Math.PI / 2 + i * step;
			graphics.lineTo(Math.cos(angle) * radius, Math.sin(angle) * radius);
		}
	}

	/** Advance one frame. When magnetTo* is set the item flies straight at it
	 *  (collection-line vacuum / proximity magnet) instead of falling. */
	public function update(magnet:Bool, targetX:Float, targetY:Float):Void {
		if (magnet) {
			var dx = targetX - x;
			var dy = targetY - y;
			var dist = Math.sqrt(dx * dx + dy * dy);
			if (dist > 0.001) {
				var step = (dist < MAGNET_SPEED) ? dist : MAGNET_SPEED;
				x += dx / dist * step;
				y += dy / dist * step;
			}
			return;
		}

		velocityY += GRAVITY;
		if (velocityY > TERMINAL_FALL) velocityY = TERMINAL_FALL;
		// Sideways scatter decays so items settle into a clean fall
		velocityX *= 0.98;
		x += velocityX;
		y += velocityY;
	}
}
