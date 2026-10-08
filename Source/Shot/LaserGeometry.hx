package shot;

enum LaserPhase {
	Telegraph;
	Active;
	Shutdown;
}

/** Shared laser timing + collision math (no OpenFL — safe for interp tests). */
class LaserGeometry {
	public static function phaseAtAge(age:Int, telegraphFrames:Int, activeFrames:Int):LaserPhase {
		if (age < telegraphFrames) return Telegraph;
		if (age < telegraphFrames + activeFrames) return Active;
		return Shutdown;
	}

	public static function activeLength(age:Int, fullLength:Float, telegraphFrames:Int, activeFrames:Int,
			shutdownFrames:Int, extendFrames:Int, phase:LaserPhase):Float {
		if (phase == Telegraph) return fullLength;
		if (phase == Shutdown) {
			var shutAge = age - telegraphFrames - activeFrames;
			var t = shutdownFrames <= 0 ? 1.0 : shutAge / shutdownFrames;
			return fullLength * (1.0 - t);
		}
		if (extendFrames <= 0) return fullLength;
		var activeAge = age - telegraphFrames;
		var t = activeAge / extendFrames;
		if (t > 1) t = 1;
		if (t < 0) t = 0;
		return fullLength * t;
	}

	public static function distancePointToSegment(px:Float, py:Float, x1:Float, y1:Float, x2:Float, y2:Float):Float {
		var dx = x2 - x1;
		var dy = y2 - y1;
		var lenSq = dx * dx + dy * dy;
		if (lenSq < 1e-9) {
			var ddx = px - x1;
			var ddy = py - y1;
			return Math.sqrt(ddx * ddx + ddy * ddy);
		}
		var t = ((px - x1) * dx + (py - y1) * dy) / lenSq;
		if (t < 0) t = 0;
		else if (t > 1) t = 1;
		var nx = x1 + t * dx;
		var ny = y1 + t * dy;
		var ex = px - nx;
		var ey = py - ny;
		return Math.sqrt(ex * ex + ey * ey);
	}
}
