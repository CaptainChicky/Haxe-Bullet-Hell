package player;

import bullet.BulletPlayer;
import manager.CollisionManager;
import openfl.events.Event;
import openfl.display.Sprite;
import openfl.Lib;

/** Selectable player shot types (1/2/3 on the title screen). */
enum PlayerShotType {
	Spread; // wide 5-way cover (the original pattern)
	Pierce; // narrow, fast, concentrated forward damage
	Homing; // straight core + flankers that chase enemies
}

/** One bullet of a volley. turnRate != 0 makes it homing. */
private typedef VolleyShot = {
	var offsetX:Float;
	var velX:Float;
	var velY:Float;
	@:optional var turnRate:Float;
}

/**
 * Fires the player's volley every frame while Z is held.
 * The volley layout depends on the selected shot type and on focus mode
 * (hold Shift: slower movement, tighter pattern) — same framework, three
 * layouts, each with a focused variant.
 */
class PlayerShootingPattern extends Sprite {
	private var player:Player; // Reference to the player that uses this shooting pattern
	private var isShooting:Bool = false;
	private var collisionManager:CollisionManager;
	private var shotType:PlayerShotType = Spread;

	// Power level 0..MAX (from collected items): every 4 power = +1 damage
	// per bullet, so max power triples the volley's punch.
	public static inline final MAX_POWER:Int = 8;
	private var power:Int = 0;

	public function new(player:Player, collisionManager:CollisionManager) {
		super();
		this.player = player;
		this.collisionManager = collisionManager;
	}

	public function setShotType(type:PlayerShotType):Void {
		shotType = type;
	}

	/** Set the current power level (clamped to 0..MAX_POWER). */
	public function setPower(value:Int):Void {
		power = value < 0 ? 0 : (value > MAX_POWER ? MAX_POWER : value);
	}

	public function getShotType():PlayerShotType {
		return shotType;
	}

	/** Bullet layout for the current type + focus state. */
	private function volley(focused:Bool):Array<VolleyShot> {
		return switch (shotType) {
			case Spread:
				focused
					// Focused: everything flies straight ahead, tightly packed
					? [
						{offsetX: -14, velX: 0, velY: -20},
						{offsetX: -7, velX: 0, velY: -20},
						{offsetX: 0, velX: 0, velY: -20},
						{offsetX: 7, velX: 0, velY: -20},
						{offsetX: 14, velX: 0, velY: -20}
					]
					// Unfocused: 3 center (tight, parallel) + 2 angled flankers
					: [
						{offsetX: -30, velX: -1, velY: -10},
						{offsetX: -7, velX: 0, velY: -20},
						{offsetX: 0, velX: 0, velY: -20},
						{offsetX: 7, velX: 0, velY: -20},
						{offsetX: 30, velX: 1, velY: -10}
					];

			case Pierce:
				focused
					? [
						{offsetX: -4, velX: 0, velY: -30},
						{offsetX: 0, velX: 0, velY: -30},
						{offsetX: 4, velX: 0, velY: -30}
					]
					: [
						{offsetX: -9, velX: 0, velY: -26},
						{offsetX: 0, velX: 0, velY: -26},
						{offsetX: 9, velX: 0, velY: -26}
					];

			case Homing:
				focused
					// Focused: tight core, flankers launch forward and steer hard
					? [
						{offsetX: -6, velX: 0, velY: -20},
						{offsetX: 6, velX: 0, velY: -20},
						{offsetX: -18, velX: 0, velY: -14, turnRate: 8},
						{offsetX: 18, velX: 0, velY: -14, turnRate: 8}
					]
					// Unfocused: flankers launch outward and curve back in
					: [
						{offsetX: -6, velX: 0, velY: -20},
						{offsetX: 6, velX: 0, velY: -20},
						{offsetX: -26, velX: -4, velY: -13, turnRate: 5},
						{offsetX: 26, velX: 4, velY: -13, turnRate: 5}
					];
		}
	}

	private function spawnPlayerBullet():Void {
		manager.AudioManager.sfxFire();
		var shots = volley(player.isFocused());

		var damage = 1 + Std.int(power / 4);

		for (config in shots) {
			var bullet:BulletPlayer = new BulletPlayer();
			bullet.x = player.x + config.offsetX;
			bullet.y = player.y;
			bullet.velocityX = config.velX;
			bullet.velocityY = config.velY;
			bullet.damage = damage;

			if (config.turnRate != null && config.turnRate != 0) {
				bullet.enableHoming(config.turnRate, collisionManager.getEnemyManager());
			}

			Lib.current.addChild(bullet); // Add the bullet to the stage

			// Register bullet with collision manager
			if (collisionManager != null) {
				collisionManager.registerPlayerBullet(bullet);
			}
		}
	}

	private function everyFrame(event:Event):Void {
		if (Main.gamePaused) return;

		if (isShooting) {
			spawnPlayerBullet();
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
