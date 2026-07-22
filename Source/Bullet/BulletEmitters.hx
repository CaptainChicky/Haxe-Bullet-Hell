package bullet;

import enemy.Enemy;
import manager.CollisionManager;
import shot.GhostOrigin;
import shot.GhostOrigin.IGhostAnchor;
import shot.ShotPrototype;
import shot.ScriptRunner;
import shot.ShotEmitter;
import openfl.Lib;
import openfl.display.DisplayObjectContainer;

/**
 * Shared bullet-materialization logic: builds a BulletEnemy from a cloned
 * prototype, adds it to the display list, registers it for collision, and -
 * if the prototype carries a sub-script - attaches a ScriptRunner so the
 * bullet executes its own pattern after spawning.
 */
private class EmitterBase implements IGhostAnchor {
	private var collisionManager:CollisionManager;
	public var bulletSprite:String = null;

	// Ghost-parent bookkeeping (see shot.GhostOrigin): offset-bound bullets
	// retain while bound; the ghost stands in for the owner after death and is
	// dropped once the last bound bullet releases.
	private var boundCount:Int = 0;
	private var ghost:GhostOrigin = null;

	private function new(collisionManager:CollisionManager, ?bulletSprite:String) {
		this.collisionManager = collisionManager;
		this.bulletSprite = bulletSprite;
	}

	public function retainBound():Void {
		boundCount++;
	}

	public function releaseBound():Void {
		boundCount--;
		if (boundCount <= 0) ghost = null;
	}

	public function getGhost():GhostOrigin {
		return ghost;
	}

	public function getBoundCount():Int {
		return boundCount;
	}

	/** Stand up the ghost origin at owner death (called by the display side,
	 *  which also ticks it every frame while it lives). */
	public function beginGhost(x:Float, y:Float, vx:Float, vy:Float, maxOrphanFrames:Int = GhostOrigin.DEFAULT_MAX_ORPHAN_FRAMES):GhostOrigin {
		ghost = new GhostOrigin(x, y, vx, vy, maxOrphanFrames);
		return ghost;
	}

	/** Vanish is a no-op for enemy emitters; BulletSubEmitter overrides. */
	public function vanish():Void {}

	public function getTarget():ShotTarget {
		if (collisionManager == null) return null;
		var player = collisionManager.getPlayer();
		if (player == null || !player.isAlive()) return null;
		return {x: player.x, y: player.y};
	}

	public function spawn(prototype:ShotPrototype, x:Float, y:Float):Void {
		var bullet = new BulletEnemy(prototype, bulletSprite);
		bullet.x = x;
		bullet.y = y;

		// Playfield space, not the stage root: x/y above came from
		// getOriginX/Y, i.e. the firing enemy's playfield coordinates. The
		// stage root is offset from the playfield by FIELD_X (see Main.world),
		// so parenting here is what keeps bullets emerging from the enemy
		// rather than 60px to its left.
		var container:DisplayObjectContainer = (Main.world != null) ? Main.world : Lib.current;
		container.addChild(bullet);

		if (collisionManager != null) {
			collisionManager.registerEnemyBullet(bullet);
		}

		// Bound bullets follow the emitter that fired them (this object):
		// it provides live parent position + liveness. bindSource (the parent
		// script's live prototype) was attached by ScriptRunner.fireClone.
		if (prototype.bindMode != ShotPrototype.BIND_NONE) {
			var self:IShotEmitter = cast this;
			bullet.bindTo(self, prototype.bindMode, prototype.bindSource);
		}

		// Bullets with a sub-script become emitters themselves. The sub-script
		// starts from a clone of this bullet's prototype (inheriting direction,
		// speed, vars, ...) with subCommands stripped to prevent infinite
		// recursion - a Sub inside the sub-script can re-arm it deliberately.
		if (prototype.subCommands != null) {
			var subProto = prototype.clone();
			subProto.subCommands = null;
			// A bound bullet's own children do not implicitly bind to it;
			// a chain must opt in with an explicit Bind in the sub-script.
			subProto.bindMode = ShotPrototype.BIND_NONE;
			var runner = new ScriptRunner(new BulletSubEmitter(bullet, collisionManager, bulletSprite), prototype.subCommands, subProto);
			bullet.attachScript(runner);
		}
	}
}

/** Fires bullets from an enemy's position. */
class EnemyBulletEmitter extends EmitterBase implements IShotEmitter {
	private var enemy:Enemy;

	public function new(enemy:Enemy, collisionManager:CollisionManager, ?bulletSprite:String) {
		super(collisionManager, bulletSprite);
		this.enemy = enemy;
	}

	public function getOriginX():Float return enemy.x;

	public function getOriginY():Float return enemy.y;

	public function isAlive():Bool {
		return enemy != null && enemy.isAlive();
	}
}

/** Fires bullets from a bullet's position - enables nested (Touhou-style) patterns. */
class BulletSubEmitter extends EmitterBase implements IShotEmitter {
	private var bullet:BulletEnemy;

	public function new(bullet:BulletEnemy, collisionManager:CollisionManager, ?bulletSprite:String) {
		super(collisionManager, bulletSprite);
		this.bullet = bullet;
	}

	public function getOriginX():Float return bullet.x;

	public function getOriginY():Float return bullet.y;

	public function isAlive():Bool {
		return bullet != null && bullet.parent != null;
	}

	/** The Vanish command: the bullet removes itself mid-flight. */
	override public function vanish():Void {
		if (bullet != null) bullet.destroy();
	}
}
