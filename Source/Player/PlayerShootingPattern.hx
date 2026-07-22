package player;

import bullet.BulletPlayer;
import manager.CollisionManager;
import openfl.events.Event;
import openfl.display.Sprite;
import openfl.Lib;

/** Selectable player shot types (1/2/3 on the title screen). */
enum PlayerShotType {
	Spread; // wide multi-stream cover; medium speed, medium damage
	Pierce; // few piercing streams, highest focused damage; fastest movement
	Homing; // seeker volleys that never miss; lowest DPS, slowest movement
}

/** One bullet of a volley. turnRate != 0 makes it homing. */
private typedef VolleyShot = {
	var offsetX:Float;
	var velX:Float;
	var velY:Float;
	@:optional var turnRate:Float;
}

/**
 * Fires the player's volley on a per-type cadence while Z is held.
 *
 * Balance model (Touhou-style): collecting power items grows the NUMBER of
 * bullet streams (and shortens homing's cooldown), not just raw damage.
 * Power is 0.00..4.00 in 0.25 steps; the integer part is the "tier" (0..4)
 * that picks the volley layout. Rough single-target DPS targets at 60fps:
 *
 *   tier          0     1     2     3     4
 *   Spread       10    20    30    40    50   (coverage; only some streams hit)
 *   Pierce       15   22.5   30    45    60   (narrow, but bullets pierce)
 *   Homing        8    12    16    24    32   (never misses)
 *
 * Focus mode (hold Shift) tightens each layout, it does not change DPS.
 */
class PlayerShootingPattern extends Sprite {
	private var player:Player; // Reference to the player that uses this shooting pattern
	private var isShooting:Bool = false;
	private var collisionManager:CollisionManager;
	private var shotType:PlayerShotType = Spread;

	// Power level 0.00..MAX (each power item = +0.25). Std.int(power) is the
	// volley tier.
	public static inline final MAX_POWER:Float = 4.0;

	private var power:Float = 0;

	// Frames until the next volley may fire
	private var cooldown:Int = 0;

	public function new(player:Player, collisionManager:CollisionManager) {
		super();
		this.player = player;
		this.collisionManager = collisionManager;
	}

	public function setShotType(type:PlayerShotType):Void {
		shotType = type;
	}

	/** Set the current power level (clamped to 0..MAX_POWER). */
	public function setPower(value:Float):Void {
		power = value < 0 ? 0 : (value > MAX_POWER ? MAX_POWER : value);
	}

	public function getShotType():PlayerShotType {
		return shotType;
	}

	/** Volley tier 0..4 — the integer part of power picks the layout. */
	private function tier():Int {
		var t = Std.int(power);
		return t > 4 ? 4 : t;
	}

	/** Frames between volleys for the current type (homing speeds up with power). */
	private function fireInterval():Int {
		return switch (shotType) {
			case Spread: 6;
			case Pierce: 8;
			case Homing: [30, 24, 22, 18, 15][tier()];
		}
	}

	/** Damage per bullet for the current type and tier. */
	private function bulletDamage():Int {
		return switch (shotType) {
			case Spread: 1;
			case Pierce: [2, 3, 2, 3, 4][tier()];
			case Homing: 2;
		}
	}

	/** Bullet layout for the current type + tier + focus state. */
	private function volley(focused:Bool):Array<VolleyShot> {
		return switch (shotType) {
			case Spread:
				// Streams grow 1 -> 5 with power. Unfocused: outer streams fan
				// out for coverage. Focused: same count, all tight and parallel.
				switch (tier()) {
					case 0:
						[{offsetX: 0, velX: 0, velY: -20}];
					case 1:
						focused
							? [{offsetX: -5, velX: 0, velY: -20}, {offsetX: 5, velX: 0, velY: -20}]
							: [{offsetX: -8, velX: 0, velY: -20}, {offsetX: 8, velX: 0, velY: -20}];
					case 2:
						focused
							? [
								{offsetX: -8, velX: 0, velY: -20},
								{offsetX: 0, velX: 0, velY: -20},
								{offsetX: 8, velX: 0, velY: -20}
							]
							: [
								{offsetX: -12, velX: -0.7, velY: -19},
								{offsetX: 0, velX: 0, velY: -20},
								{offsetX: 12, velX: 0.7, velY: -19}
							];
					case 3:
						focused
							? [
								{offsetX: -12, velX: 0, velY: -20},
								{offsetX: -4, velX: 0, velY: -20},
								{offsetX: 4, velX: 0, velY: -20},
								{offsetX: 12, velX: 0, velY: -20}
							]
							: [
								{offsetX: -24, velX: -1.6, velY: -14},
								{offsetX: -8, velX: 0, velY: -20},
								{offsetX: 8, velX: 0, velY: -20},
								{offsetX: 24, velX: 1.6, velY: -14}
							];
					default:
						focused
							? [
								{offsetX: -14, velX: 0, velY: -20},
								{offsetX: -7, velX: 0, velY: -20},
								{offsetX: 0, velX: 0, velY: -20},
								{offsetX: 7, velX: 0, velY: -20},
								{offsetX: 14, velX: 0, velY: -20}
							]
							: [
								{offsetX: -30, velX: -2, velY: -12},
								{offsetX: -14, velX: -0.7, velY: -19},
								{offsetX: 0, velX: 0, velY: -20},
								{offsetX: 14, velX: 0.7, velY: -19},
								{offsetX: 30, velX: 2, velY: -12}
							];
				}

			case Pierce:
				// One rail-like stream growing to two; bullets fly fast and
				// pierce through enemies (damage rises with tier instead of
				// stream count on odd tiers).
				var spacing = focused ? 4.0 : 9.0;
				if (tier() < 2) {
					[{offsetX: 0, velX: 0, velY: -34}];
				} else {
					[
						{offsetX: -spacing, velX: 0, velY: -34},
						{offsetX: spacing, velX: 0, velY: -34}
					];
				}

			case Homing:
				// Pure seeker volleys on a slow cadence: 2 seekers at tier 0
				// (~2 volleys/sec), growing to 4 while the cooldown shortens.
				var turn = focused ? 8.0 : 5.0;
				var shots:Array<VolleyShot> = focused
					? [
						{offsetX: -10, velX: 0, velY: -16, turnRate: turn},
						{offsetX: 10, velX: 0, velY: -16, turnRate: turn}
					]
					: [
						{offsetX: -14, velX: -2, velY: -15, turnRate: turn},
						{offsetX: 14, velX: 2, velY: -15, turnRate: turn}
					];
				if (tier() >= 2) {
					shots.push({offsetX: 0, velX: 0, velY: -18, turnRate: turn});
				}
				if (tier() >= 3) {
					shots.push(focused
						? {offsetX: 0, velX: 0, velY: -13, turnRate: turn}
						: {offsetX: 0, velX: 0, velY: -13, turnRate: 4});
				}
				shots;
		}
	}

	private function spawnPlayerBullet():Void {
		manager.AudioManager.sfxFire();
		var shots = volley(player.isFocused());

		var damage = bulletDamage();
		var piercing = (shotType == Pierce);

		for (config in shots) {
			var bullet:BulletPlayer = new BulletPlayer();
			bullet.x = player.x + config.offsetX;
			bullet.y = player.y;
			bullet.velocityX = config.velX;
			bullet.velocityY = config.velY;
			bullet.damage = damage;
			bullet.piercing = piercing;

			if (config.turnRate != null && config.turnRate != 0) {
				bullet.enableHoming(config.turnRate, collisionManager.getEnemyManager());
			}

			// Playfield space, not the stage root — bullet.x came from player.x,
			// which is a playfield coordinate (see Main.world).
			var container:openfl.display.DisplayObjectContainer = (Main.world != null) ? Main.world : Lib.current;
			container.addChild(bullet);

			// Register bullet with collision manager
			if (collisionManager != null) {
				collisionManager.registerPlayerBullet(bullet);
			}
		}
	}

	private function everyFrame(event:Event):Void {
		if (Main.gamePaused) return;

		if (cooldown > 0) cooldown--;

		if (isShooting && cooldown <= 0) {
			spawnPlayerBullet();
			cooldown = fireInterval();
		}
	}

	public function startShooting():Void {
		isShooting = true;
		addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	public function stopShooting():Void {
		isShooting = false;
		removeEventListener(Event.ENTER_FRAME, everyFrame);
	}
}
