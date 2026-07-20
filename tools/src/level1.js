"use strict";
/**
 * Stage 1 — Introduction. DSL rewrite of the hand-written level1.json:
 * same cast (scouts, the sun-explosion midboss, and the unique orbit /
 * nway-radial-line / parallel-spirals / laundry / random-bomb setpieces),
 * but with paced waves, gentler stage-1 bullet speeds, and health tuned to
 * the rebalanced player DPS (~10-25 at stage-1 power).
 *
 * Compile: node tools/compile.js  ->  Assets/levels/level1.json
 */
const { S, M, spawn, wave, say, level } = require("../bh");

// Playfield is ~1800x1080 (fullscreen); CX is the horizontal center.
const CX = 900;

// --------------------------------------------------------------------- helpers

/** Radial rings fired closest-first: [[count, speed], ...] with a gap between. */
function rings(pairs, gap = 10) {
	const out = [];
	pairs.forEach(([count, speed], i) => {
		out.push(S.radial(count, speed));
		if (i < pairs.length - 1) out.push(S.wait(gap));
	});
	return out;
}

/** Enter from the top, settle, sit for `holdFrames`, then fly off the top. */
function dropIn(speed, enterFrames, holdFrames, exitVy = -2.5) {
	return M.script({},
		M.drift(0, speed, enterFrames),
		M.easeTo({ from: [0, speed], to: [0, 0], frames: 30 }),
		M.hold(holdFrames),
		M.vel(0, exitVy),
	);
}

// ------------------------------------------------------- the sunexplosion boss

// Signature midboss script kept intact from the original hand-written level:
// three widening fans, three volleys of collapsing radial rings, then a
// looping fire-line + slow-ring barrage until it leaves or dies.
// Ring speed ladder capped at 14 (was 25): a speed-25 bullet crosses the
// whole field in ~0.7s, which is Lunatic reaction time — stage 1 should sit
// around Touhou Easy/Normal, the fast top ring is still a clear overtake.
const RING_SET = [[110, 4], [84, 6.5], [64, 9], [44, 11.5], [30, 14]];

const sunExplosionScript = [
	S.set("direction", 90), S.set("speed", 4),
	S.rep(8, S.nway(5, 90, 0), S.add("direction", 2), S.add("speed", 0.5), S.wait(3)),
	S.set("direction", 90), S.set("speed", 4), S.wait(30),
	S.rep(8, S.nway(8, 45, 0), S.add("direction", -4), S.add("speed", 1), S.wait(3)),
	S.set("direction", 90), S.set("speed", 4), S.wait(30),
	S.rep(12, S.nway(12, 200, 0), S.add("direction", 5), S.add("speed", 0.5), S.wait(3)),
	S.set("direction", 90), S.set("speed", 0), S.wait(30),
	rings(RING_SET), S.wait(10), S.wait(30),
	rings(RING_SET), S.wait(10), S.wait(30),
	rings(RING_SET), S.wait(120),
	S.set("direction", 90),
	S.loop(
		S.set("speed", 3),
		S.rep(10, S.fire(0, 0), S.add("speed", 0.2), S.wait(5)),
		S.wait(30),
		rings([[120, 2], [90, 3], [72, 5], [45, 8], [30, 12]]),
		S.wait(120),
	),
];

// ------------------------------------------------------------------- the level

module.exports = level("level1", "Level 1 - Introduction", {
	dialogue: {
		intro: [
			say("Aviator", "The border's gone quiet... too quiet. Something is stirring past the treeline.", "assets/Player.png", "left"),
			say("???", "Turn back, little bird. The sky belongs to the Swarm tonight.", "assets/Enemy.png", "right"),
			say("Aviator", "Funny, I was about to say the same thing to you.", "assets/Player.png", "left"),
		],
		outro: [
			say("Aviator", "Scouts, nothing more. Whoever sent them is still out there.", "assets/Player.png", "left"),
		],
	},
	waves: [
		// -- opening: two scouts cross in from the sides, trade a few volleys,
		//    and slip away upward
		wave(0, [
			spawn({
				at: [-50, 170], time: 0,
				pattern: "nwhip", health: 8,
				config: { numberOfWhips: 3, numberOfBullets: 4, baseBulletSpeed: 3, speedChange: 0.4, patternDelay: 80 },
				move: M.script({},
					M.drift(2.5, 0, 100),
					M.easeTo({ from: [2.5, 0], to: [0, 0], frames: 40 }),
					M.hold(300),
					M.vel(1, -2),
				),
			}),
			spawn({
				at: [1850, 170], time: 1,
				pattern: "spiral", health: 8,
				config: { bulletSpeed: 3.5, rotationChange: 14 },
				move: M.script({},
					M.drift(-2.5, 0, 100),
					M.easeTo({ from: [-2.5, 0], to: [0, 0], frames: 40 }),
					M.hold(300),
					M.vel(-1, -2),
				),
			}),
		]),

		// -- a trio drops in from the top: two slow spirals framing a radial
		wave(10, [
			spawn({
				at: [450, -50], time: 0,
				pattern: "spiral", health: 8,
				config: { bulletSpeed: 3, rotationChange: 9 },
				move: dropIn(2.5, 80, 330),
			}),
			spawn({
				at: [1350, -50], time: 0,
				pattern: "spiral", health: 8,
				config: { bulletSpeed: 3, rotationChange: -9 },
				move: dropIn(2.5, 80, 330),
			}),
			spawn({
				at: [CX, -50], time: 1.5,
				pattern: "radial", health: 14,
				config: { bulletCount: 10, bulletSpeed: 3, rotationSpeed: 6 },
				move: dropIn(2, 90, 330),
			}),
		]),

		// -- a weaving whip-thrower with two crossing spiral runners
		wave(22, [
			spawn({
				at: [CX, -60], time: 0,
				pattern: "nwhip", health: 18,
				config: { numberOfWhips: 5, numberOfBullets: 6, baseBulletSpeed: 3, speedChange: 0.6, patternDelay: 60 },
				move: M.script({},
					M.drift(0, 2.5, 90),
					M.weave({ vx: 2, vy: 0.2, period: 140, cycles: 3 }),
					M.vel(0, -2.5),
				),
			}),
			spawn({
				at: [-50, 300], time: 2,
				pattern: "spiral", health: 8,
				config: { bulletSpeed: 3.5, rotationChange: 11 },
				velocity: [3, 0],
			}),
			spawn({
				at: [1850, 300], time: 2,
				pattern: "spiral", health: 8,
				config: { bulletSpeed: 3.5, rotationChange: -11 },
				velocity: [-3, 0],
			}),
		]),

		// -- MIDBOSS: the sun-explosion. Sits center-stage through its fan /
		//    collapsing-ring routine, leaves on its own after ~45s if unbeaten.
		wave(34, [
			spawn({
				at: [CX, -80], time: 0,
				pattern: "sunexplosion", health: 200,
				script: sunExplosionScript,
				move: M.script({},
					M.drift(0, 3, 110),
					M.hold(2600),
					M.vel(0, -2.5),
				),
			}),
		]),

		// -- the orbit setpiece: a satellite gunner with escorts
		wave(58, [
			spawn({
				at: [1450, -60], time: 0,
				pattern: "orbit", health: 26,
				config: { orbitDistance: 150, bulletSpeed: 4, rotationSpeed: 3, fireDelay: 4 },
				move: dropIn(2.5, 100, 720),
			}),
			spawn({
				at: [-50, 320], time: 1,
				pattern: "spiral", health: 8,
				config: { bulletSpeed: 3.5, rotationChange: 12 },
				velocity: [3, 0],
			}),
			spawn({
				at: [400, -60], time: 2,
				pattern: "nwhip", health: 12,
				config: { numberOfWhips: 3, numberOfBullets: 5, baseBulletSpeed: 3, speedChange: 0.5, patternDelay: 70 },
				move: dropIn(2.5, 80, 540),
			}),
		]),

		// -- mixed arms: the nway-radial-line setpiece, a sniper, and a
		//    random-spray gunner
		wave(72, [
			spawn({
				at: [700, -60], time: 0,
				pattern: "nway-radial-line", health: 22,
				script: [
					S.set("direction", 90), S.set("speed", 4),
					S.loop(
						S.nway(10, 90, 0), S.wait(60),
						S.radial(36, 0), S.wait(60),
						S.set("speed", 12),
						S.rep(10, S.fire(0, 0), S.add("speed", -1)),
						S.set("speed", 5), S.wait(60),
					),
				],
				move: dropIn(2.5, 100, 780),
			}),
			spawn({
				at: [1300, -60], time: 1.5,
				pattern: "sniper", health: 16,
				config: { bulletSpeed: 12, burstCount: 3, burstDelay: 4, orbitDistance: 150, patternDelay: 70 },
				move: dropIn(2.5, 90, 720),
			}),
			spawn({
				at: [300, -60], time: 3,
				pattern: "random", health: 12,
				config: { minSpeed: 1, maxSpeed: 3.5, baseAngle: 90, angleSpread: 40, fireDelay: 5 },
				move: dropIn(2.5, 90, 660),
			}),
		]),

		// -- the parallel-spirals setpiece holds the center alone
		wave(86, [
			spawn({
				at: [CX, -60], time: 0,
				pattern: "parallel-spirals", health: 26,
				script: [
					S.set("direction", 90), S.set("speed", 5),
					S.concurrent(
						[S.loop(S.fire(0, 0), S.add("direction", 16), S.wait(2))],
						[
							S.set("direction", 180), S.set("speed", 8),
							S.loop(S.fire(0, 0), S.add("direction", -8), S.wait(0.8)),
						],
						[S.loop(S.fire(90, 0), S.wait(8))],
					),
				],
				move: dropIn(2.5, 110, 720),
			}),
		]),

		// -- finale: laundry tumbler + the aimed random-bomb turret
		wave(98, [
			spawn({
				at: [1250, -60], time: 0,
				pattern: "laundry", health: 26,
				script: [
					S.set("direction", 90), S.set("speed", 9),
					S.concurrent(
						[S.loop(S.radial(10, 0), S.add("direction", 8), S.wait(4))],
						[S.loop(S.radial(4, 0), S.add("direction", 4), S.wait(2))],
						[S.loop(S.radial(4, 0), S.add("direction", -4), S.wait(2))],
					),
				],
				move: dropIn(2.5, 100, 780),
			}),
			spawn({
				at: [500, -60], time: 2,
				pattern: "random-bomb", health: 30,
				script: [
					S.set("speed", 6), S.offset(80, 0),
					S.loop(S.aim(), S.radial(20, 0), S.addOffset(0, 25), S.wait(18)),
				],
				move: dropIn(2.5, 110, 780),
			}),
		]),
	],
});
