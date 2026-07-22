"use strict";
/**
 * amitaba — a manji (卍, the Buddhist swastika) drawn in bullets.
 *
 * The figure is RIGID: every bullet is offset-bound to the emitter with a
 * Cartesian (x, y) placement and rotates itself one `spinStep` per frame via
 * the Rotate transform, so the whole glyph turns as one body and rides along
 * with the enemy instead of smearing into a spray. Each arm is a straight
 * spoke of `armBullets` plus a perpendicular hook of `bendBullets` at the tip;
 * `handed` flips 卍 <-> 卐.
 *
 * Nested in the four diagonal gaps between the arms sit four laser pods, which
 * run the satellite.json beam verbatim: a short column of bullets that spools
 * up from a standstill, cruises, brakes to a dead stop, and hangs — each bullet
 * carrying a per-bullet `fuse` (longer for the earlier shots) so the whole
 * stopped column detonates into radial fragments in one instant.
 *
 * After `holdFrames` the glyph releases: every bullet fires a free copy of
 * itself outward along its own bearing (`outAngle`, advanced by the rotation
 * it has accumulated) and vanishes. Then the emitter draws the next one.
 *
 * Compile: node tools/compile.js  ->  Assets/patterns/amitaba.json
 */
const { S, pattern } = require("../../bh");

// --------------------------------------------------------- the glyph's bullets
// One figure bullet: hold formation while the glyph turns, then break outward.
// `outAngle` is set per bullet at fire time (spoke bearing, or hook bearing for
// the hook bullets); adding the total rotation gives the true outward heading
// at release without paying for a per-frame Add.
const figureBullet = [
	S.rep("$holdFrames",
		S.rotate("$spinStep"),
		S.wait(1),
	),
	S.scope(
		// Children of an offset-bound bullet must zero the offset or they
		// spawn at (bullet + offset) instead of at the bullet (see pods.json).
		S.set("x", 0), S.set("y", 0), S.offset(0, 0),
		S.set("speed", "$releaseSpeed"),
		S.set("direction", "outAngle + $spinStep * $holdFrames"),
		S.fire(0, 0),
	),
	S.vanish(),
];

// ------------------------------------------------------------- the laser pods
// Shared-prototype Concurrent: branch 1 keeps the pod rotating with the glyph
// (it owns offsetAngle on the live root prototype, which is what BIND_OFFSET
// reads for position); branch 2 fires the beams. Branch 2's Scope shields its
// burst configuration from branch 1, and vice versa.
const laserPod = [
	S.concurrentShared(
		[S.rep("$holdFrames",
			S.addOffset(0, "$spinStep"),
			S.wait(1),
		)],
		[S.rep("$laserVolleys",
			S.wait("$laserDelay"),
			S.scope(
				S.set("direction", "offsetAngle"),   // outward, before the offset is zeroed
				S.offset(0, 0), S.set("x", 0), S.set("y", 0),
				S.set("speed", 0),
				S.set("fuse", "($laserCount - 1) * $laserGap"),
				S.sub(
					S.tween("speed", "$laserSpeed", "$laserSpool"),
					S.wait("$laserCruise"),
					S.tween("speed", 0, "$laserBrake"),
					S.wait("$laserHang"),
					S.wait("fuse"),                   // the column detonates as one
					S.scope(
						S.set("speed", "$burstSpeed"),
						S.radial("$burstCount", 0),
					),
					S.vanish(),
				),
				S.rep("$laserCount",
					S.fire(0, 0),
					S.add("fuse", "-$laserGap"),
					S.wait("$laserGap"),
				),
			),
		)],
	),
	S.vanish(),
];

module.exports = pattern("amitaba",
	"Rigid rotating manji (卍) of offset-bound bullets — four hooked arms that "
	+ "hold formation, with a satellite-style laser pod nested in each diagonal "
	+ "gap; the glyph breaks outward when the hold ends",
	{
		armCount:     { type: "int",   default: 4,   description: "Arms of the glyph (4 = a manji)" },
		armBullets:   { type: "int",   default: 6,   description: "Bullets along each straight arm" },
		bendBullets:  { type: "int",   default: 4,   description: "Bullets in each perpendicular hook" },
		spacing:      { type: "float", default: 34,  description: "Distance between adjacent bullets" },
		handed:       { type: "float", default: -1,  description: "Hook direction: -1 = 卍, 1 = 卐" },
		baseAngle:    { type: "float", default: 0,   description: "Starting rotation of the whole glyph" },
		spinStep:     { type: "float", default: 0.3, description: "Glyph rotation, degrees per frame (0 = frozen)" },
		holdFrames:   { type: "int",   default: 260, description: "Frames the glyph holds before breaking apart" },
		releaseSpeed: { type: "float", default: 2.4, description: "Speed each bullet leaves at when the glyph breaks" },
		drawDelay:    { type: "int",   default: 1,   description: "Frames between arms while the glyph inscribes itself" },
		cycleDelay:   { type: "int",   default: 90,  description: "Frames between one glyph and the next" },

		laserRadius:  { type: "float", default: 95,  description: "Pod distance from center (sits in the gap between arms)" },
		laserCount:   { type: "int",   default: 5,   description: "Bullets per beam" },
		laserGap:     { type: "int",   default: 3,   description: "Frames between beam bullets" },
		laserSpeed:   { type: "float", default: 9,   description: "Beam bullet speed after spool-up" },
		laserSpool:   { type: "int",   default: 18,  description: "Frames a beam bullet spools up from speed 0" },
		laserCruise:  { type: "int",   default: 26,  description: "Frames a beam bullet flies at full speed" },
		laserBrake:   { type: "int",   default: 10,  description: "Frames a beam bullet takes to brake to a stop" },
		laserHang:    { type: "int",   default: 26,  description: "Frames the stopped column hangs before detonating" },
		laserDelay:   { type: "int",   default: 60,  description: "Frames a pod charges between beams" },
		laserVolleys: { type: "int",   default: 2,   description: "Beams each pod fires per glyph" },
		burstCount:   { type: "int",   default: 4,   description: "Radial fragments per detonating beam bullet" },
		burstSpeed:   { type: "float", default: 2.6, description: "Detonation fragment speed" },
	},
	[
		S.set("speed", 0),
		S.bind("offset"),
		S.offset(0, 0),
		S.loop(
			// -- the glyph itself
			S.sub(...figureBullet),
			S.set("arm", 0),
			S.rep("$armCount",
				S.set("bearing", "arm * (360 / $armCount) + $baseAngle"),
				S.set("hookBearing", "bearing + 90 * $handed"),

				// straight arm, center outward
				S.set("outAngle", "bearing"),
				S.set("d", "$spacing"),
				S.rep("$armBullets",
					S.set("x", "cos(bearing) * d"),
					S.set("y", "sin(bearing) * d"),
					S.fire(0, 0),
					S.add("d", "$spacing"),
				),

				// the hook, turning off the arm's tip
				S.set("outAngle", "hookBearing"),
				S.set("tipD", "$spacing * $armBullets"),
				S.set("e", "$spacing"),
				S.rep("$bendBullets",
					S.set("x", "cos(bearing) * tipD + cos(hookBearing) * e"),
					S.set("y", "sin(bearing) * tipD + sin(hookBearing) * e"),
					S.fire(0, 0),
					S.add("e", "$spacing"),
				),

				S.add("arm", 1),
				S.wait("$drawDelay"),
			),

			// -- one laser pod per diagonal gap
			S.scope(
				S.set("x", 0), S.set("y", 0),
				S.sub(...laserPod),
				S.set("pod", 0),
				S.rep("$armCount",
					S.offset("$laserRadius", "pod * (360 / $armCount) + 180 / $armCount + $baseAngle"),
					S.fire(0, 0),
					S.add("pod", 1),
				),
			),

			S.wait("$holdFrames + $cycleDelay"),
		),
	]);
