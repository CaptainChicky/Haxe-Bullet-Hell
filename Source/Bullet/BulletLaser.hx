package bullet;

import shot.GhostOrigin;
import shot.GhostOrigin.IGhostAnchor;
import shot.LaserGeometry;
import shot.LaserGeometry.LaserPhase;
import shot.LaserSpawnParams;
import shot.ShotPrototype;
import shot.ShotEmitter.IShotEmitter;
import openfl.display.Sprite;

/**
 * Vector-drawn enemy laser: telegraph (no hit) → active beam → shutdown fade.
 * Origin and angle follow the same binding conventions as BulletEnemy.
 */
class BulletLaser extends Sprite {
	public static inline final TELEGRAPH_LINE_WIDTH:Float = 2.0;
	public static inline final TELEGRAPH_ALPHA:Float = 0.45;
	public static inline final ACTIVE_CORE_ALPHA:Float = 0.95;
	public static inline final ACTIVE_GLOW_ALPHA:Float = 0.35;

	private var beamAngle:Float;
	private var fullLength:Float;
	private var fullWidth:Float;
	private var telegraphFrames:Int;
	private var activeFrames:Int;
	private var shutdownFrames:Int;
	private var extendFrames:Int;
	private var angularVelocity:Float;

	private var age:Int = 0;
	private var state:LaserPhase = Telegraph;

	private var bindMode:Int = ShotPrototype.BIND_NONE;
	private var bindAnchor:IShotEmitter = null;
	private var bindSource:ShotPrototype = null;
	private var anchorLastX:Float = 0;
	private var anchorLastY:Float = 0;
	private var ghostOrigin:GhostOrigin = null;
	private var bindRetained:Bool = false;

	/** Frames since last graze tick while the player overlaps (collision pass). */
	public var grazeCooldown:Int = 0;

	public function new(params:LaserSpawnParams) {
		super();
		beamAngle = params.angle;
		fullLength = params.length;
		fullWidth = params.width;
		telegraphFrames = params.telegraphFrames;
		activeFrames = params.activeFrames;
		shutdownFrames = params.shutdownFrames;
		extendFrames = params.extendFrames < 0 ? 0 : params.extendFrames;
		angularVelocity = params.angularVelocity;
		bindMode = params.bindMode;
		bindSource = params.bindSource;
		redraw();
	}

	public function bindTo(anchor:IShotEmitter, mode:Int, source:ShotPrototype):Void {
		bindAnchor = anchor;
		bindMode = mode;
		bindSource = source;
		anchorLastX = anchor.getOriginX();
		anchorLastY = anchor.getOriginY();
		if (mode == ShotPrototype.BIND_OFFSET && Std.isOfType(anchor, IGhostAnchor)) {
			cast(anchor, IGhostAnchor).retainBound();
			bindRetained = true;
		}
	}

	public function getState():LaserPhase {
		return state;
	}

	public function collides():Bool {
		return state == Active;
	}

	/** Current beam length (extends during the active phase). */
	public function currentLength():Float {
		return LaserGeometry.activeLength(age, fullLength, telegraphFrames, activeFrames, shutdownFrames, extendFrames, state);
	}

	/** Half of the collision strip width during the active phase. */
	public function collisionHalfWidth():Float {
		if (state != Active) return 0;
		return fullWidth * 0.5;
	}

	public function segmentEndpoints():{x1:Float, y1:Float, x2:Float, y2:Float} {
		var len = currentLength();
		var rad = beamAngle * Math.PI / 180;
		var ox = x;
		var oy = y;
		return {
			x1: ox,
			y1: oy,
			x2: ox + Math.cos(rad) * len,
			y2: oy + Math.sin(rad) * len,
		};
	}

	public function update():Void {
		if (parent == null) {
			releaseBind();
			return;
		}

		applyBinding();

		if (bindMode == ShotPrototype.BIND_FULL && bindSource != null) {
			beamAngle = bindSource.direction;
		}
		beamAngle += angularVelocity;

		updateState();
		redraw();

		age++;
		if (state == Shutdown) {
			var shutAge = age - telegraphFrames - activeFrames;
			if (shutAge >= shutdownFrames) despawn();
		}
	}

	private function updateState():Void {
		state = LaserGeometry.phaseAtAge(age, telegraphFrames, activeFrames);
	}

	private function applyBinding():Void {
		if (bindAnchor == null) return;

		if (!bindAnchor.isAlive()) {
			if (ghostOrigin == null && bindMode == ShotPrototype.BIND_OFFSET && Std.isOfType(bindAnchor, IGhostAnchor)) {
				ghostOrigin = cast(bindAnchor, IGhostAnchor).getGhost();
			}
			if (ghostOrigin == null) {
				releaseBind();
				bindAnchor = null;
				bindSource = null;
				bindMode = ShotPrototype.BIND_NONE;
			} else if (ghostOrigin.expired) {
				despawn();
				return;
			}
		}

		var bindDX:Float = 0;
		var bindDY:Float = 0;
		if (bindAnchor != null && bindAnchor.isAlive()) {
			var px = bindAnchor.getOriginX();
			var py = bindAnchor.getOriginY();
			bindDX = px - anchorLastX;
			bindDY = py - anchorLastY;
			anchorLastX = px;
			anchorLastY = py;
		}

		if (bindMode == ShotPrototype.BIND_OFFSET && bindAnchor != null) {
			// Lasers rarely use offset bind; keep origin at anchor when parent lives.
			var ax = (ghostOrigin != null) ? ghostOrigin.x : bindAnchor.getOriginX();
			var ay = (ghostOrigin != null) ? ghostOrigin.y : bindAnchor.getOriginY();
			x = ax;
			y = ay;
		} else if (bindMode != ShotPrototype.BIND_NONE) {
			x += bindDX;
			y += bindDY;
		}
	}

	private function redraw():Void {
		graphics.clear();
		var len = currentLength();
		if (len <= 0.5) return;

		rotation = beamAngle;

		switch (state) {
			case Telegraph:
				graphics.lineStyle(TELEGRAPH_LINE_WIDTH, 0xFF88AA, TELEGRAPH_ALPHA);
				graphics.moveTo(0, 0);
				graphics.lineTo(len, 0);
			case Active:
				var half = fullWidth * 0.5;
				graphics.lineStyle(fullWidth, 0xFF3366, ACTIVE_GLOW_ALPHA);
				graphics.moveTo(0, 0);
				graphics.lineTo(len, 0);
				graphics.lineStyle(Math.max(2, fullWidth * 0.35), 0xFFFFFF, ACTIVE_CORE_ALPHA);
				graphics.moveTo(0, 0);
				graphics.lineTo(len, 0);
			case Shutdown:
				var shutAge = age - telegraphFrames - activeFrames;
				var t = shutdownFrames <= 0 ? 1.0 : shutAge / shutdownFrames;
				var w = fullWidth * (1.0 - t);
				var a = ACTIVE_CORE_ALPHA * (1.0 - t);
				if (w > 0.5 && a > 0.02) {
					graphics.lineStyle(w, 0xFF6699, a);
					graphics.moveTo(0, 0);
					graphics.lineTo(len, 0);
				}
		}
	}

	public function destroy():Void {
		despawn();
	}

	private function releaseBind():Void {
		if (bindRetained) {
			bindRetained = false;
			cast(bindAnchor, IGhostAnchor).releaseBound();
		}
	}

	private function despawn():Void {
		releaseBind();
		if (parent != null) parent.removeChild(this);
	}
}
