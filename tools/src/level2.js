"use strict";
/**
 * Stage 2 — Rolling Advance. DSL rewrite of the hand-written level2.json:
 * keeps the mixed-formation identity (crossing vanguard, the bigger
 * sun-explosion II, the left-flank rush, the sniper turret, the orbit
 * heavy, and the simpleburst pre-boss), with wave timings paced to the
 * rebalanced player DPS (~25-35 at stage-2 power).
 *
 * Compile: node tools/compile.js  ->  Assets/levels/level2.json
 */
const { S, M, spawn, wave, say, level } = require("../bh");

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

// -------------------------------------------------- sun-explosion II (midboss)

// Stage-2 variant of the signature script: same fan opening, but the ring
// volleys alternate sparse and dense before the looping barrage.
const sunExplosion2Script = [
	S.set("direction", 90), S.set("speed", 4),
	S.rep(8, S.nway(5, 90, 0), S.add("direction", 2), S.add("speed", 0.5), S.wait(3)),
	S.set("direction", 90), S.set("speed", 4), S.wait(30),
	S.rep(8, S.nway(8, 45, 0), S.add("direction", -4), S.add("speed", 1), S.wait(3)),
	S.set("direction", 90), S.set("speed", 4), S.wait(30),
	S.rep(12, S.nway(12, 200, 0), S.add("direction", 5), S.add("speed", 0.5), S.wait(3)),
	S.set("direction", 90), S.set("speed", 0), S.wait(30),
	// Ring speed ladders capped at 15 (was 25) — see level1's RING_SET note;
	// stage 2 gets to be a touch faster than stage 1's cap of 14.
	rings([[80, 4], [40, 7], [20, 10], [10, 12.5], [5, 15]]), S.wait(10), S.wait(30),
	rings([[120, 4], [90, 7], [72, 10], [45, 12.5], [30, 15]]), S.wait(10), S.wait(30),
	rings([[40, 4], [20, 7], [10, 10], [5, 12.5], [2, 15]]), S.wait(120),
	S.set("direction", 90),
	S.loop(
		S.set("speed", 3),
		S.rep(10, S.fire(0, 0), S.add("speed", 0.2), S.wait(5)),
		S.wait(30),
		rings([[40, 2], [30, 3], [20, 5], [10, 8], [5, 12]]),
		S.wait(120),
	),
];

// --------------------------------------------------------- the left-flank rush

/** One rusher: streams in from the left, fires briefly, escapes up-right. */
function rusher(index, patternName, health, config, script) {
	return spawn({
		at: [-50, 120 + index * 30], time: index * 0.25,
		pattern: patternName, health,
		config, script,
		move: M.script({},
			M.drift(3, 0.3, 40),
			M.hold(90),
			M.vel(3.5, -1),
		),
	});
}

const rushWave = [];
for (let i = 0; i < 10; i++) {
	if (i === 2 || i === 7) {
		// A couple of snipers hide in the stream
		rushWave.push(rusher(i, "sniper", 10, { bulletSpeed: 10, burstCount: 2, burstDelay: 3, patternDelay: 50 }));
	} else if (i === 4) {
		// One aimed-ring bomber in the middle of the pack
		rushWave.push(rusher(i, "rush-bomb", 14, undefined, [
			S.set("speed", 5), S.offset(40, 0),
			S.loop(S.aim(), S.radial(10, 0), S.addOffset(0, 20), S.wait(50)),
		]));
	} else {
		// Whip fodder with per-ship variation so the volleys desync
		rushWave.push(rusher(i, "nwhip", 10, {
			numberOfWhips: 2, numberOfBullets: 4, baseBulletSpeed: 3,
			speedChange: [0.2, 0.5, 3, 0.4, 4, 0.3, 5, 0.2, 4, 0.5][i],
			patternDelay: [10, 30, 0, 50, 0, 60, 40, 0, 10, 80][i] || 30,
		}));
	}
}

// ------------------------------------------------------------------- the level

module.exports = level("level2", "Level 2 - Rolling Advance", {
	dialogue: {
		intro: [
			say("Swarm Vanguard", "You clipped our scouts. Impressive. Now meet the formations they were scouting FOR.", "assets/Enemy(second).png", "right"),
			say("Aviator", "Formations just means more of you fall in order.", "assets/Player.png", "left"),
		],
		outro: [
			say("Swarm Vanguard", "Enough. The Firedancer will finish this personally.", "assets/Enemy(second).png", "right"),
			say("Aviator", "Firedancer? ...Fine. I'll bring the wind.", "assets/Player.png", "left"),
		],
	},
	waves: [
		// -- vanguard pair crosses in from both flanks
		wave(0, [
			spawn({
				at: [-50, 180], time: 0,
				pattern: "nwhip", health: 20,
				config: { numberOfWhips: 5, numberOfBullets: 5, baseBulletSpeed: 3, speedChange: 0.25 },
				move: M.script({},
					M.drift(3, 0, 100),
					M.easeTo({ from: [3, 0], to: [0, 0], frames: 40 }),
					M.hold(300),
					M.vel(2, -1),
				),
			}),
			spawn({
				at: [1850, 300], time: 2,
				pattern: "spiral", health: 18,
				config: { bulletSpeed: 3, rotationChange: 5 },
				move: M.script({},
					M.drift(-3, 0.3, 100),
					M.easeTo({ from: [-3, 0.3], to: [0, 0], frames: 40 }),
					M.hold(280),
					M.vel(-3, -1),
				),
			}),
		]),

		// -- top pair: dense radial + wide whip fan
		wave(10, [
			spawn({
				at: [500, -50], time: 0,
				pattern: "radial", health: 22,
				config: { bulletCount: 16, bulletSpeed: 3, rotationSpeed: 2 },
				move: dropIn(2.5, 80, 380, -2),
			}),
			spawn({
				at: [1400, -50], time: 1,
				pattern: "nwhip", health: 22,
				config: { numberOfWhips: 8, numberOfBullets: 6, baseBulletSpeed: 3, speedChange: 0.3 },
				move: dropIn(2.5, 90, 360, -2),
			}),
		]),

		// -- MIDBOSS: sun-explosion II with two spray escorts; it leaves on its
		//    own after ~40s if unbeaten
		wave(22, [
			spawn({
				at: [CX, -80], time: 0,
				pattern: "sunexplosion", health: 300,
				script: sunExplosion2Script,
				move: M.script({},
					M.drift(0, 3, 120),
					M.hold(2400),
					M.vel(0, -2.5),
				),
			}),
			spawn({
				at: [-50, 250], time: 3,
				pattern: "random", health: 14,
				config: { minSpeed: 1, maxSpeed: 4, baseAngle: 90, angleSpread: 50, fireDelay: 6 },
				move: M.script({},
					M.drift(1.8, 0, 90),
					M.hold(420),
					M.vel(2.2, -1),
				),
			}),
			spawn({
				at: [1850, 250], time: 6,
				pattern: "random", health: 14,
				config: { minSpeed: 1, maxSpeed: 4, baseAngle: 90, angleSpread: 50, fireDelay: 6 },
				move: M.script({},
					M.drift(-1.8, 0, 90),
					M.hold(420),
					M.vel(-2.2, -1),
				),
			}),
		]),

		// -- the left-flank rush: ten small ships stream across in a column
		wave(54, rushWave),

		// -- sniper turret holds the center while a bomber dashes underneath
		wave(70, [
			spawn({
				at: [950, -60], time: 0,
				pattern: "sniper", health: 60,
				config: { bulletSpeed: 13, burstCount: 5, burstDelay: 4, orbitDistance: 40, patternDelay: 45 },
				move: dropIn(2.5, 100, 700, -3),
			}),
			spawn({
				at: [-50, 130], time: 2,
				pattern: "dash-bomb", health: 16,
				script: [
					S.set("speed", 7), S.offset(50, 0),
					S.loop(S.aim(), S.radial(16, 0), S.addOffset(0, 25), S.wait(16)),
				],
				move: M.script({},
					M.drift(5, 0, 20),
					M.vel(5, -1),
				),
			}),
		]),

		// -- heavies: the orbit satellite and a wide whip platform
		wave(84, [
			spawn({
				at: [500, -50], time: 0,
				pattern: "orbit", health: 90,
				config: { orbitDistance: 150, bulletSpeed: 4, rotationSpeed: 2, fireDelay: 7 },
				move: dropIn(2, 100, 640, -2.5),
			}),
			spawn({
				at: [1400, -50], time: 2,
				pattern: "nwhip", health: 40,
				config: { numberOfWhips: 4, numberOfBullets: 6, baseBulletSpeed: 3, speedChange: 0.2, angleChange: 1.5 },
				move: dropIn(2, 90, 600, -2),
			}),
		]),

		// -- FINALE: the simpleburst commander — twin concurrent barrages,
		//    stays until destroyed
		wave(98, [
			spawn({
				at: [950, -80], time: 0,
				pattern: "custom-boss-simpleburst", health: 320,
				script: [
					S.set("speed", 7),
					S.offset(130, 0),
					S.set("direction", 90),
					S.concurrent(
						[S.loop(
							S.offset(130, 0),
							S.aim(),
							S.radial(16, 0),
							S.addOffset(0, 287),
							S.wait(180),
							S.offset(0, 0),
						)],
						[S.loop(
							S.offset(0, 0),
							S.radial(20, 3),
							S.wait(40),
							S.nway(7, 90, 2),
							S.wait(40),
							S.radial(10, 6),
							S.wait(60),
							S.set("speed", 12),
							S.rep(10, S.fire(0, 0), S.add("speed", -1)),
							S.set("speed", 7),
							S.wait(60),
							S.offset(130, 0),
						)],
					),
				],
				move: M.script({},
					M.drift(0, 3, 95),
					M.stop(),
					M.wait(99999),
				),
			}),
		]),
	],
});
