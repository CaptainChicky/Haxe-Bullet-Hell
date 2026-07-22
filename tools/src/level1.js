"use strict";
/**
 * Stage 1 — Introduction. Scouts and light setpieces building to Vesper, the
 * Lantern Moth: a proper three-phase stage boss (the old sun-explosion
 * midboss and its collapsing-ring routine are gone — every ring it fired was
 * the same idea at five radii).
 *
 * Balance model (Touhou Easy/Normal, tuned against the rebalanced player):
 *  - Stage-1 power is ~10-25 peak single-target DPS, call it ~10-12 effective
 *    once dodging eats uptime. Boss phases are sized for ~20-28s each, with
 *    generous timeouts so a weak run can never stall out.
 *  - Dodge ceiling is deliberately low: nothing faster than ~7 px/frame, and
 *    everything fast is aimed and telegraphed. The dense layers are all slow.
 *
 * Compile: node tools/compile.js  ->  Assets/levels/level1.json
 */
const { S, M, spawn, wave, say, level, boss, phase } = require("../bh");

// Playfield is ~1800x1080 (fullscreen); CX is the horizontal center.
const CX = 900;

// --------------------------------------------------------------------- helpers

/** Enter from the top, settle, sit for `holdFrames`, then fly off the top. */
function dropIn(speed, enterFrames, holdFrames, exitVy = -2.5) {
	return M.script({},
		M.drift(0, speed, enterFrames),
		M.easeTo({ from: [0, speed], to: [0, 0], frames: 30 }),
		M.hold(holdFrames),
		M.vel(0, exitVy),
	);
}

// ------------------------------------------------------- MIDBOSS: Hive Lantern

// Deliberately a trailer for the boss: slow lantern orbs that drift down and
// pop into a soft petal ring, over a lazy two-arm pinwheel. Holds ~35s.
const hiveLanternScript = [
	S.set("direction", 90), S.set("speed", 2.6),
	S.concurrent(
		[S.loop(S.radial(3, 0), S.add("direction", 6), S.wait(7))],
		[S.set("direction", 210), S.loop(S.radial(3, 0), S.add("direction", -6), S.wait(7))],
		[S.loop(
			S.wait(120),
			S.scope(
				S.size(2.0), S.set("direction", 90), S.set("speed", 1.8),
				S.sub(
					S.wait(75),
					S.scope(S.size(1), S.set("speed", 2.4), S.radial(8, 0)),
					S.vanish(),
				),
				S.dup(2, { x: { from: -220, to: 220 } }),
			),
		)],
	),
];

// -------------------------------------------------- BOSS: Vesper, Lantern Moth

// P1 — nonspell: a four-spoke pinwheel that reverses spin every ~2.5s, with
// aimed dart pairs punching through it. Teaches the two stage-1 skills:
// read the spoke gaps, and step off the aim line before the darts land.
const vesperPhase1 = phase({
	health: 200,
	timeout: 40,
	script: [
		S.set("direction", 90), S.set("speed", 2.8),
		S.wait(24),
		S.concurrent(
			[S.loop(
				S.rep(30, S.radial(4, 0), S.add("direction", 5.5), S.wait(5)),
				S.rep(30, S.radial(4, 0), S.add("direction", -5.5), S.wait(5)),
			)],
			[S.loop(S.wait(115), S.aim(), S.rep(2, S.nway(3, 18, 5.5), S.wait(10)))],
		),
	],
});

/** A ring that coasts out, stalls to a near-hover, then beats outward again. */
function wingbeat(count, speed) {
	return S.scope(
		S.set("speed", speed),
		S.sub(
			S.tween("speed", 0.6, 40),
			S.wait(22),
			S.tween("speed", 3.2, 44),
		),
		S.radial(count, 0),
	);
}

// P2 — spell: the rings hang in the air mid-flight, so the field reads as a
// set of stalled walls the player weaves through rather than a stream to
// outrun. Each beat is offset from the last, and the boss drifts sideways so
// the walls never stack in the same place twice.
const vesperPhase2 = phase({
	name: "Moth Sign - Dusted Wingbeat",
	health: 260,
	timeout: 50,
	script: [
		S.set("direction", 90), S.wait(20),
		S.concurrent(
			[S.loop(
				wingbeat(20, 4.5), S.add("direction", 9), S.wait(58),
				wingbeat(20, 4.5), S.add("direction", -15), S.wait(58),
			)],
			[S.loop(S.wait(150), S.aim(), S.nway(3, 22, 5.0))],
		),
	],
	move: M.script({ loop: true },
		M.drift(1.4, 0, 130),
		M.drift(-1.4, 0, 260),
		M.drift(1.4, 0, 130),
	),
});

// P3 — Last Word: lantern orbs (size 2.2) sink slowly across the field and
// bloom into petal rings on a delay, so the danger is where they *will* be,
// not where they are. A slow counter-rotating spiral is the canvas under it.
const lanternVolley = S.scope(
	S.size(2.2), S.set("direction", 90), S.set("speed", 1.6),
	S.sub(
		S.wait(80),
		S.scope(S.size(1), S.set("speed", 2.6), S.radial(10, 0)),
		S.vanish(),
	),
	S.dup(3, { direction: { from: 70, to: 110 }, x: { from: -300, to: 300 } }),
);

const vesperPhase3 = phase({
	name: "Lamp Sign - Candleflame Vigil",
	health: 320,
	timeout: 60,
	script: [
		S.set("direction", 90), S.set("speed", 2.6),
		S.wait(24),
		S.concurrent(
			[S.loop(S.radial(3, 0), S.add("direction", 6.5), S.wait(6))],
			[S.set("direction", 240), S.loop(S.radial(3, 0), S.add("direction", -5.5), S.wait(6))],
			[S.loop(S.wait(105), lanternVolley)],
			[S.loop(S.wait(200), S.aim(), S.rep(2, S.nway(3, 20, 5.2), S.wait(11)))],
		),
	],
	move: M.script({}, M.stop()),
});

const vesper = spawn({
	at: [CX, -80], time: 0,
	sprite: "enemy2",
	// entrance glide; phase 1 has no move script so it isn't cut short
	move: M.script({}, M.drift(0, 3, 100), M.stop()),
	boss: boss("Vesper, the Lantern Moth",
		vesperPhase1, vesperPhase2, vesperPhase3),
});

// ------------------------------------------------------------------- the level

module.exports = level("level1", "Level 1 - Introduction", {
	dialogue: {
		intro: [
			say("Aviator", "The border's gone quiet... too quiet. Something is stirring past the treeline.", "assets/Player.png", "left"),
			say("???", "Turn back, little bird. The sky belongs to the Swarm tonight.", "assets/Enemy.png", "right"),
			say("Aviator", "Funny, I was about to say the same thing to you.", "assets/Player.png", "left"),
		],
		outro: [
			say("Vesper", "You put out the lantern... the swarm will scatter without it...", "assets/Enemy(second).png", "right"),
			say("Aviator", "Scouts and a lamplighter. Whoever lit the fire is still out there.", "assets/Player.png", "left"),
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

		// -- MIDBOSS: the Hive Lantern — pinwheel canvas plus delayed lantern
		//    blooms, a preview of Vesper's last phase. Leaves after ~35s.
		wave(34, [
			spawn({
				at: [CX, -80], time: 0,
				pattern: "hive-lantern", health: 170,
				script: hiveLanternScript,
				move: M.script({},
					M.drift(0, 3, 110),
					M.hold(2000),
					M.vel(0, -2.5),
				),
			}),
		]),

		// -- the orbit setpiece: a satellite gunner with escorts
		wave(52, [
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
		wave(66, [
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
		wave(80, [
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

		// -- last pressure wave: laundry tumbler + the aimed random-bomb turret
		wave(92, [
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
				move: dropIn(2.5, 100, 660),
			}),
			spawn({
				at: [500, -60], time: 2,
				pattern: "random-bomb", health: 30,
				script: [
					S.set("speed", 6), S.offset(80, 0),
					S.loop(S.aim(), S.radial(20, 0), S.addOffset(0, 25), S.wait(18)),
				],
				move: dropIn(2.5, 110, 660),
			}),
		]),

		// -- BOSS: Vesper, the Lantern Moth
		wave(106, [vesper]),
	],
});
