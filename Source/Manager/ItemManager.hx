package manager;

import enemy.BossEnemy;
import enemy.Enemy;
import item.Item;
import item.Item.ItemType;
import player.Player;
import openfl.display.Sprite;

/**
 * Owns every pickup on the field: spawning drops when enemies die, the fall /
 * magnet / collection physics, and reporting what the player picked up.
 * All items are children of this sprite, so clearing is trivial and z-order
 * is one addChild decision in Main (items render under the player).
 *
 * Collection rules (Touhou-style):
 *  - touching an item collects it
 *  - flying above the collection line (fraction of field height) vacuums
 *    every item on screen toward the player
 *  - items within a short proximity radius always home in
 */
class ItemManager extends Sprite {
	/** Fraction of the field height forming the auto-collect line. */
	public static inline final COLLECTION_LINE_FRACTION:Float = 0.30;

	private static inline final PICKUP_RADIUS:Float = 24.0;
	private static inline final PROXIMITY_MAGNET_RADIUS:Float = 48.0;

	// Drop-table odds for normal enemies (per extra drop beyond the first)
	private static inline final BOMB_DROP_CHANCE:Float = 0.02;
	private static inline final LIFE_DROP_CHANCE:Float = 0.004;

	/** Fired once per collected item with its type (set by Main). */
	public var onCollected:ItemType->Void = null;

	private var items:Array<Item> = [];

	public function new() {
		super();
		mouseEnabled = false;
		mouseChildren = false;
	}

	/** Spawn one item at field coordinates. */
	public function spawnItem(type:ItemType, x:Float, y:Float, scatter:Bool = true):Void {
		var item = new Item(type, scatter);
		item.x = x;
		item.y = y;
		addChild(item);
		items.push(item);
	}

	/** Drops for a defeated enemy. Tougher enemies drop more; bosses shower.
	 *  Deliberately stingy: each power item is only +0.25 power, and reaching
	 *  the 4.00 cap should take roughly three stages of collecting. */
	public function dropForEnemy(enemy:Enemy):Void {
		if (Std.isOfType(enemy, BossEnemy)) {
			// Boss defeat: a shower of goodies plus a guaranteed bomb
			for (i in 0...4) spawnItem(PowerItem, enemy.x + jitter(60), enemy.y + jitter(30));
			for (i in 0...8) spawnItem(PointItem, enemy.x + jitter(60), enemy.y + jitter(30));
			spawnItem(BombItem, enemy.x, enemy.y);
			return;
		}

		// Rare treats first so they aren't crowded out
		if (Math.random() < LIFE_DROP_CHANCE) {
			spawnItem(LifeItem, enemy.x, enemy.y);
		} else if (Math.random() < BOMB_DROP_CHANCE) {
			spawnItem(BombItem, enemy.x, enemy.y);
		}

		var hp = enemy.getMaxHealth();
		if (hp < 15) {
			// Fodder: 60% chance of one drop, point-biased
			if (Math.random() < 0.6) {
				spawnItem((Math.random() < 0.4) ? PowerItem : PointItem, enemy.x + jitter(24), enemy.y + jitter(12));
			}
		} else if (hp < 40) {
			// Mid-tier: always one drop, 50/50
			spawnItem((Math.random() < 0.5) ? PowerItem : PointItem, enemy.x + jitter(24), enemy.y + jitter(12));
		} else {
			// Tanky / midboss-class: a power item plus a coin-flip second drop
			spawnItem(PowerItem, enemy.x + jitter(24), enemy.y + jitter(12));
			spawnItem((Math.random() < 0.5) ? PowerItem : PointItem, enemy.x + jitter(24), enemy.y + jitter(12));
		}
	}

	/** Power spilled on player death: scatter items where they died. */
	public function spillPower(x:Float, y:Float, count:Int):Void {
		for (i in 0...count) {
			spawnItem(PowerItem, x + jitter(50), y - 30 + jitter(20));
		}
	}

	private static function jitter(range:Float):Float {
		return (Math.random() - 0.5) * range;
	}

	/** Advance all items one frame against the player (magnet + collection). */
	public function update(player:Player):Void {
		var vacuum = player.isAlive() && player.y < Main.fieldHeight * COLLECTION_LINE_FRACTION;

		var i = items.length - 1;
		while (i >= 0) {
			var item = items[i];

			var dx = player.x - item.x;
			var dy = player.y - item.y;
			var distSq = dx * dx + dy * dy;

			var magnet = player.isAlive()
				&& (vacuum || distSq < PROXIMITY_MAGNET_RADIUS * PROXIMITY_MAGNET_RADIUS);
			item.update(magnet, player.x, player.y);

			if (player.isAlive() && distSq < PICKUP_RADIUS * PICKUP_RADIUS) {
				// Collected
				removeAt(i);
				if (onCollected != null) onCollected(item.itemType);
			} else if (item.y > Main.fieldHeight + 30) {
				// Fell off the bottom
				removeAt(i);
			}
			i--;
		}
	}

	private function removeAt(index:Int):Void {
		var item = items[index];
		if (item.parent != null) item.parent.removeChild(item);
		items.splice(index, 1);
	}

	public function clear():Void {
		for (item in items) {
			if (item.parent != null) item.parent.removeChild(item);
		}
		items = [];
	}
}
