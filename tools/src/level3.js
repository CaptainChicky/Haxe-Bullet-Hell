"use strict";
/**
 * Stage 3 — The Firedancer's Gauntlet. DSL rewrite of the generated
 * level3.json: the showcase-pattern gauntlet (every engine feature gets a
 * field appearance) building through the gaster-frog midboss and the weaver
 * to the sol-firedancer finale.
 *
 * All enemy movement in this stage is chained linear velocity ramps — the
 * path() builder below reproduces the original generator's sampling (lerp
 * from the current velocity, sampled at the END of each chunk), so the
 * compiled output matches the previous level3.json numerically.
 *
 * Compile: node tools/compile.js  ->  Assets/levels/level3.json
 */
const { S, M, spawn, wave, say, level } = require("../bh");

// ---------------------------------------------------------------- movement

/**
 * Chained velocity ramps. rampTo(vx, vy, steps, wait) emits `steps`
 * SetVelocity/Wait pairs sampling the straight line from the current
 * velocity to the target; drift/stop/wait are the M primitives, tracked so
 * the next ramp starts where the last piece ended. done() -> movementScript.
 */
function path(vx0 = 0, vy0 = 0) {
	let cur = [vx0, vy0];
	const actions = [];
	const p = {
		rampTo(vx, vy, steps, wait) {
			for (let i = 1; i <= steps; i++) {
				actions.push(M.vel(
					cur[0] + (vx - cur[0]) * (i / steps),
					cur[1] + (vy - cur[1]) * (i / steps)
				), M.wait(wait));
			}
			cur = [vx, vy];
			return p;
		},
		drift(vx, vy, frames) {
			actions.push(M.vel(vx, vy), M.wait(frames));
			cur = [vx, vy];
			return p;
		},
		stop() { actions.push(M.stop()); cur = [0, 0]; return p; },
		wait(frames) { actions.push(M.wait(frames)); return p; },
		/**
		 * Triangle strafe at constant vy: `legs` quarter-ramps of 4 steps
		 * each, swinging 0 -> sign*amp -> 0 -> -sign*amp -> 0 -> ...
		 */
		weave(amp, vy, wait, legs, sign = 1) {
			let from = 0;
			for (let leg = 0; leg < legs; leg++) {
				const to = leg % 2 === 0 ? sign * amp * (leg % 4 === 0 ? 1 : -1) : 0;
				for (let i = 1; i <= 4; i++) {
					actions.push(M.vel(from + (to - from) * (i / 4), vy), M.wait(wait));
				}
				from = to;
			}
			cur = [from, vy];
			return p;
		},
		done(loop = false) { return { loop: !!loop, actions }; },
	};
	return p;
}

/**
 * Diagonal stream across the field (the recurring escort move): enter at
 * 0.4×peak, swell to full peak sideways speed, then shear off downward at
 * 0.6×peak. side: 1 = from the left, -1 = from the right.
 */
const arcAcross = (side, peak, midVy, wait) =>
	path(side * 0.4 * peak, 1)
		.rampTo(side * peak, midVy, 4, wait)
		.rampTo(side * 0.6 * peak, 3.5, 4, wait)
		.done();

/** Fly in from a flank, brake, strafe on a triangle weave, then dive out. */
const flankSweep = (side, { enterVx = 4, enterVy, holdVy, enterWait, amp, weaveWait, legs, exitVx = 3, exitVy }) =>
	path(side * enterVx, enterVy)
		.rampTo(0, holdVy, 4, enterWait)
		.weave(amp, holdVy, weaveWait, legs, side)
		.rampTo(side * exitVx, exitVy, 4, 9)
		.done();

/** Drop in from the top, weave in place, then accelerate off the bottom. */
const dropSweep = ({ enterVy, amp, weaveVy, weaveWait, legs, sign = 1, exitVy = 4.5 }) =>
	path()
		.drift(0, enterVy, 48)
		.weave(amp, weaveVy, weaveWait, legs, sign)
		.rampTo(0, exitVy, 3, 10)
		.done();

/** Bosses steer themselves via moveSelf — the movement script just parks. */
const parkForever = () => M.script({}, M.hold(99999));

/** The recurring spiral escort riding an arcAcross. */
const spiralEscort = ({ side, y, time, health = 3, bulletSpeed = 3.4, rot = 15, fireDelay = 4, peak = 3.2, midVy, wait }) =>
	spawn({
		at: [side > 0 ? -50 : 1850, y], time,
		pattern: "spiral", health,
		config: { bulletSpeed, rotationChange: side * rot, fireDelay },
		move: arcAcross(side, peak, midVy, wait),
	});

// ------------------------------------------------------------ shot helpers

/** Configure children inside a Scope so moveSelf steering is untouched. */
const burst = (speed, ...fire) => S.scope(S.set("speed", speed), ...fire);

/** moveSelf dash: face `dir`, surge to `speed` and glide back to rest. */
const dash = (dir, speed, frames) => [
	S.set("direction", dir),
	S.tween("speed", speed, frames),
	S.tween("speed", 0, frames),
];

/** Aimed gatling sweep: dense 9-way bursts walking `sweep` deg per shot. */
const aimedGatling = (count, sweep) => [
	S.aim(),
	S.rep(count, burst(13, S.nway(9, 6, 0)), S.add("direction", sweep), S.wait(2)),
];

/** The shared boss idle dance: left/right lunges, then a vertical bob. */
const danceLoop = () => S.loop(
	dash(180, 2.6, 40), S.wait(12),
	dash(0, 2.6, 40), S.wait(12),
	dash(90, 3, 26), S.wait(20),
	dash(270, 3, 26), S.wait(12),
);

// ------------------------------------------------- MIDBOSS: gaster-frog

/** One lunge: hop toward `dir`, warning 3-way, gatling sweep, panic ring. */
const frogLunge = (dir, sweep) => [
	dash(dir, 5, 18), S.set("speed", 0),
	S.aim(), burst(9, S.nway(3, 2, 0)), S.wait(30),
	aimedGatling(20, sweep),
	burst(2.4, S.radial(20, 0)), S.wait(34),
];

const gasterFrogScript = [
	S.set("moveSelf", 1), S.set("direction", 90), S.set("speed", 0),
	S.wait(20),
	S.loop(frogLunge(180, 1.4), frogLunge(0, -1.4)),
];

// --------------------------------------------------- SETPIECE: the weaver

const weaverScript = [
	S.set("speed", 3),
	// Opening: two synchronized rotating geometry wheels — plain 7-ways one
	// way, speed-lines the other — 20 turns, then the dance begins.
	S.concurrent(
		[S.rep(20,
			S.rep(2, S.nway(7, 30, 0), S.add("direction", 180)),
			S.add("direction", 30), S.wait(15),
		)],
		[S.add("direction", 90),
		S.rep(20,
			S.rep(2, S.line(7, "speed", 3, 10.2), S.add("direction", 180)),
			S.add("direction", 30), S.wait(15),
		)],
	),
	S.set("moveSelf", 1), S.set("direction", 90), S.set("speed", 0),
	S.concurrentShared(
		[danceLoop()],
		// twin counter-rotating fire spirals
		[S.concurrent(
			[S.scope(S.set("speed", 3.5),
				S.loop(S.fire(0, 0), S.add("direction", 14), S.wait(3)))],
			[S.scope(S.set("speed", 3.5), S.set("direction", 180),
				S.loop(S.fire(0, 0), S.add("direction", -14), S.wait(3)))],
		)],
		// slow/fast breathing rings
		[S.loop(
			burst(2.4, S.radial(22, 0)), S.wait(32),
			burst(4.2, S.radial(16, 0)), S.wait(46),
		)],
		// periodic aimed speed-string
		[S.loop(
			S.wait(72), S.aim(),
			burst(13, S.rep(8, S.fire(0, 0), S.add("speed", -0.9))),
		)],
	),
];

// -------------------------------------------- FINALE: the sol-firedancer

const solFiredancerScript = [
	S.set("moveSelf", 1), S.set("direction", 90), S.set("speed", 0),

	// I — sideways dashes under a rising curtain of accelerating 6-way rings
	S.concurrentShared(
		[dash(180, 3, 30), S.wait(10), dash(0, 3, 30), S.wait(10), dash(180, 3, 30)],
		[S.scope(
			S.set("speed", 4), S.set("shotAng", 90),
			S.rep(14,
				S.set("direction", 90), S.nway(6, 90, 0),
				S.add("speed", 0.35), S.wait(5),
			),
		)],
	),
	S.wait(24),

	// II — vertical bobbing while a 3-way pinwheel spins 60 turns
	S.concurrentShared(
		[dash(90, 4, 22), S.wait(30), dash(270, 4, 22),
			dash(90, 4, 22), S.wait(30), dash(270, 4, 22)],
		[S.scope(
			S.set("speed", 3.5), S.set("direction", 90),
			S.rep(60, S.nway(3, 20, 0), S.add("direction", 17), S.wait(6)),
		)],
	),
	S.wait(20),

	// III — retreat-and-return under four volleys of layered shockwaves
	// (each volley: rings at speed 4/8/12/16, dense to sparse)
	S.concurrentShared(
		[dash(270, 2.5, 26), S.wait(20), dash(90, 2, 26)],
		[S.rep(4,
			burst(4, S.radial(90, 0)), S.wait(8),
			burst(8, S.radial(72, 0)), S.wait(8),
			burst(12, S.radial(45, 0)), S.wait(8),
			burst(16, S.radial(30, 0)), S.wait(38),
		)],
	),
	S.wait(20),

	// IV — the orbital flail: a ring of 12 offset-bound pods launched to
	// radius 150, orbiting backwards while each sprays a forward-stepping
	// stream of free bullets, then vanishing.
	S.set("speed", 0),
	S.set("offsetAngle", 0),
	S.scope(
		S.set("speed", 0), S.set("offsetDistance", 40), S.set("lifetime", 240),
		S.bind("offset"),
		S.sub(
			S.tween("offsetDistance", 150, 40),
			S.rep(80,
				S.scope(
					S.set("offsetDistance", 0), S.set("speed", 3),
					S.bind("none"), S.fire(0, 0),
				),
				S.add("offsetAngle", -4), S.add("direction", 11), S.wait(2),
			),
			S.vanish(),
		),
		S.rep(12, S.fire(0, 0), S.add("offsetAngle", 30)),
	),
	S.wait(200),

	// V — vertical feint while the aimed gatling rakes across the player
	S.concurrentShared(
		[dash(90, 5, 20), S.wait(40), dash(270, 5, 20)],
		[aimedGatling(26, 1.3)],
	),
	S.wait(30),
	S.set("direction", 90),

	// VI — endgame: the dance loop forever, with aimed speed-strings and a
	// spinning 3-way wheel between breaths
	S.concurrentShared(
		[danceLoop()],
		[S.loop(
			S.aim(),
			burst(14, S.rep(10, S.fire(0, 0), S.add("speed", -1))),
			S.scope(
				S.set("speed", 4), S.set("direction", 90),
				S.rep(24, S.nway(3, 30, 0), S.add("direction", 15), S.wait(2)),
			),
			S.wait(40),
		)],
	),
];

// ------------------------------------------------------------------- waves

// -- opening: spiral rushers stream across from both flanks
const rushOpening = [];
for (let i = 0; i < 4; i++) {
	rushOpening.push(spiralEscort({
		side: 1, y: 90 + 30 * i, time: [0, 0.45, 0.9, 1.35][i],
		bulletSpeed: 3.2, rot: 14, fireDelay: 3, midVy: 2.2, wait: 24,
	}));
}
for (let i = 0; i < 4; i++) {
	rushOpening.push(spiralEscort({
		side: -1, y: 90 + 30 * i, time: [0.9, 1.35, 1.8, 2.25][i],
		bulletSpeed: 3.2, rot: 14, fireDelay: 3, midVy: 2.2, wait: 24,
	}));
}

module.exports = level("level3", "Level 3 – The Firedancer's Gauntlet", {
	dialogue: {
		intro: [
			say("Firedancer", "So you're the storm that scattered my swarm. Every dance ends, Aviator.", "assets/Enemy.png", "right"),
			say("Aviator", "Then let's make the last one worth watching.", "assets/Player.png", "left"),
			say("Firedancer", "Burn brightly, little bird. The gauntlet is open!", "assets/Enemy.png", "right"),
		],
		outro: [
			say("Firedancer", "Beautiful... like falling embers. The sky is yours, for now.", "assets/Enemy.png", "right"),
			say("Aviator", "For now is enough. Time to fly home.", "assets/Player.png", "left"),
		],
	},
	waves: [
		wave(0, rushOpening),

		// -- radial trio drops through the top
		wave(4, [0, 1, 2].map(i => spawn({
			at: [500 + 400 * i, -50], time: 0.4 * i,
			pattern: "radial", health: 4,
			config: { bulletCount: 12, bulletSpeed: 3, rotationSpeed: 9 },
			move: dropSweep({ enterVy: 3, amp: 3.5, weaveVy: 1.4, weaveWait: 10, legs: 4, sign: i === 1 ? -1 : 1 }),
		}))),

		// -- whip pincer + a speed-string dropper
		wave(9, [
			spawn({
				at: [-50, 130], time: 0,
				pattern: "nwhip", health: 6,
				config: { numberOfWhips: 5, numberOfBullets: 8, baseBulletSpeed: 3, speedChange: 0.6, angleChange: 4, patternDelay: 32 },
				move: flankSweep(1, { enterVy: 0.5, holdVy: 1, enterWait: 12, amp: 3, weaveWait: 12, legs: 4, exitVx: 3.5, exitVy: 3.5 }),
			}),
			spawn({
				at: [1850, 130], time: 0.3,
				pattern: "nwhip", health: 6,
				config: { numberOfWhips: 5, numberOfBullets: 8, baseBulletSpeed: 3, speedChange: 0.6, angleChange: -4, patternDelay: 32 },
				move: flankSweep(-1, { enterVy: 0.5, holdVy: 1, enterWait: 12, amp: 3, weaveWait: 12, legs: 4, exitVx: 3.5, exitVy: 3.5 }),
			}),
			spawn({
				at: [900, -50], time: 1,
				pattern: "shotspeed", health: 5,
				config: { direction: 90, baseSpeed: 2.5, speedStep: 0.4, burstCount: 16, fireDelay: 1, volleyDelay: 38 },
				move: dropSweep({ enterVy: 2.4, amp: 2.5, weaveVy: 1.6, weaveWait: 9, legs: 4 }),
			}),
		]),

		// -- the spray tank crawls the width while escorts cross behind it
		wave(13, [
			spawn({
				at: [-50, 90], time: 0,
				pattern: "random", health: 34,
				config: { minSpeed: 2.5, maxSpeed: 6, baseAngle: 90, angleSpread: 62, fireDelay: 3 },
				move: flankSweep(1, { enterVx: 3, enterVy: 0.3, holdVy: 0.5, enterWait: 15, amp: 2.4, weaveWait: 15, legs: 6, exitVy: 2.5 }),
			}),
			spiralEscort({ side: -1, y: 260, time: 1.2, bulletSpeed: 3.5, rot: 16, peak: 3.4, midVy: 2.5, wait: 21 }),
			spiralEscort({ side: 1, y: 300, time: 1.8, bulletSpeed: 3.5, rot: 16, peak: 3.4, midVy: 2.5, wait: 21 }),
		]),

		// -- burst columns + a hunting sniper + parallel spinner pair
		wave(21, [
			spawn({
				at: [-50, 150], time: 0,
				pattern: "controlflow", health: 12,
				config: { shotSpeed: 4.5, direction: 90, volleyDelay: 40, burstCount: 6, burstDelay: 7 },
				move: flankSweep(1, { enterVy: 0.4, holdVy: 0.8, enterWait: 13, amp: 3, weaveWait: 13, legs: 6, exitVy: 3 }),
			}),
			spawn({
				at: [1850, 210], time: 0.4,
				pattern: "sniper", health: 16,
				config: { bulletSpeed: 12, burstCount: 4, burstDelay: 2, orbitDistance: 110, patternDelay: 38 },
				move: flankSweep(-1, { enterVy: 0.4, holdVy: 0.6, enterWait: 13, amp: 2.8, weaveWait: 11, legs: 8, exitVy: 2.5 }),
			}),
			spawn({
				at: [500, -50], time: 1,
				pattern: "parallel", health: 8,
				config: { shotSpeed: 3.2, direction: 90, steadyDelay: 7, spinDelay: 4, spinStep: 30 },
				move: dropSweep({ enterVy: 2.2, amp: 2.6, weaveVy: 1.5, weaveWait: 9, legs: 4 }),
			}),
			spawn({
				at: [1300, -50], time: 1.4,
				pattern: "parallel", health: 8,
				config: { shotSpeed: 3.2, direction: 90, steadyDelay: 7, spinDelay: 4, spinStep: -30 },
				move: dropSweep({ enterVy: 2.2, amp: 2.6, weaveVy: 1.5, weaveWait: 9, legs: 4, sign: -1 }),
			}),
		]),

		// -- heavy geometry: nway-radial-line platform, orbit heavy, laundry
		wave(28, [
			spawn({
				at: [-50, 160], time: 0,
				pattern: "nwayline", health: 18,
				config: { direction: 90, shotSpeed: 4, nwayCount: 9, nwaySpread: 80, radialCount: 28, lineCount: 9, lineSpeedBoost: 6, phaseDelay: 46 },
				move: flankSweep(1, { enterVy: 0.4, holdVy: 0.6, enterWait: 13, amp: 2.6, weaveWait: 14, legs: 6, exitVy: 2.5 }),
			}),
			spawn({
				at: [1850, 200], time: 0.4,
				pattern: "orbit", health: 20,
				config: { orbitDistance: 130, bulletSpeed: 5, rotationSpeed: 6, fireDelay: 2 },
				move: flankSweep(-1, { enterVy: 0.4, holdVy: 0.6, enterWait: 13, amp: 2.6, weaveWait: 14, legs: 6, exitVy: 2.5 }),
			}),
			spawn({
				at: [900, -50], time: 1.2,
				pattern: "laundry", health: 6,
				config: { bulletSpeed: 8, bigCount: 8, bigStep: 9, bigDelay: 5, smallCount: 4, smallStep: 5, smallDelay: 3 },
				move: path().drift(0, 2.6, 66).stop().wait(96).rampTo(0, -8, 4, 7).done(),
			}),
		]),

		// -- vanish feints flank the static-geometry crawler
		wave(35, [
			spawn({
				at: [300, -50], time: 0,
				pattern: "vanish", health: 6,
				move: dropSweep({ enterVy: 2.6, amp: 3, weaveVy: 1.8, weaveWait: 8, legs: 4 }),
			}),
			spawn({
				at: [1500, -50], time: 0.5,
				pattern: "vanish", health: 6,
				move: dropSweep({ enterVy: 2.6, amp: 3, weaveVy: 1.8, weaveWait: 8, legs: 4, sign: -1 }),
			}),
			spawn({
				at: [-50, 220], time: 0.7,
				pattern: "staticgeo", health: 22,
				move: arcAcross(1, 2.6, 1.6, 31),
			}),
			spawn({
				at: [900, -50], time: 1.1,
				pattern: "vardemo", health: 10,
				config: { speed: 4.5, angleStep: 18, fireDelay: 3 },
				move: dropSweep({ enterVy: 2.2, amp: 2.8, weaveVy: 1.5, weaveWait: 7, legs: 6 }),
			}),
		]),

		// -- shifter pincer: mirrored mid-flight kinks from both flanks
		wave(42, [
			spawn({
				at: [-50, 170], time: 0,
				pattern: "shifter", health: 24,
				config: { bulletSpeed: 5, startDirection: 60, shiftDelay: 30, shiftAngle: 100, spokeStep: 24, fireDelay: 6 },
				move: flankSweep(1, { enterVy: 0.3, holdVy: 0.4, enterWait: 13, amp: 2.4, weaveWait: 15, legs: 8, exitVy: 2 }),
			}),
			spawn({
				at: [1850, 170], time: 0.3,
				pattern: "shifter", health: 24,
				config: { bulletSpeed: 5, startDirection: 120, shiftDelay: 30, shiftAngle: -100, spokeStep: -24, fireDelay: 6 },
				move: flankSweep(-1, { enterVy: 0.3, holdVy: 0.4, enterWait: 13, amp: 2.4, weaveWait: 15, legs: 8, exitVy: 2 }),
			}),
			spawn({
				at: [900, -50], time: 1.3,
				pattern: "shotspeed", health: 7,
				config: { direction: 90, baseSpeed: 3, speedStep: 0.5, burstCount: 22, fireDelay: 1, volleyDelay: 33 },
				move: dropSweep({ enterVy: 2.6, amp: 2.4, weaveVy: 1.7, weaveWait: 9, legs: 4, sign: -1 }),
			}),
		]),

		// -- breather stream before the midboss
		wave(50, [
			spiralEscort({ side: 1, y: 140, time: 0, midVy: 2, peak: 3, wait: 25 }),
			spiralEscort({ side: -1, y: 180, time: 1.2, midVy: 2, peak: 3, wait: 25 }),
			spiralEscort({ side: 1, y: 220, time: 2.4, midVy: 2, peak: 3, wait: 25 }),
		]),

		// -- MIDBOSS: the gaster-frog — lunging side-to-side, gatling sweeps
		wave(54, [spawn({
			at: [900, 190], time: 0,
			pattern: "gaster-frog", health: 300,
			script: gasterFrogScript,
			move: parkForever(),
		})]),

		// -- escorts trickle in while the frog fight winds down
		wave(60, [
			spiralEscort({ side: 1, y: 120, time: 2, peak: 3.2, midVy: 2.4, wait: 22 }),
			spiralEscort({ side: -1, y: 120, time: 4.5, peak: 3.2, midVy: 2.4, wait: 22 }),
		]),
		wave(68, [
			spiralEscort({ side: 1, y: 160, time: 0, peak: 3.2, midVy: 1.6, wait: 22 }),
			spiralEscort({ side: -1, y: 200, time: 1.2, peak: 3.2, midVy: 1.6, wait: 22 }),
		]),

		// -- growth mechanics: seed bursts and orbiting pods
		wave(70, [
			spawn({
				at: [-50, 180], time: 0,
				pattern: "seeds", health: 30,
				move: flankSweep(1, { enterVy: 0.4, holdVy: 0.6, enterWait: 13, amp: 2.2, weaveWait: 16, legs: 6, exitVy: 2.5 }),
			}),
			spawn({
				at: [1850, 200], time: 1.5,
				pattern: "pods", health: 26,
				config: { orbitRadius: 120, orbitStep: -3, spinStep: 12, streamSpeed: 4, streamDelay: 1 },
				move: flankSweep(-1, { enterVy: 0.4, holdVy: 0.6, enterWait: 13, amp: 2.2, weaveWait: 16, legs: 6, exitVy: 2.5 }),
			}),
		]),

		// -- the bound-rotation carrier walks a T across the top
		wave(76, [spawn({
			at: [900, -50], time: 0,
			pattern: "bindpos", health: 26,
			config: { startDistance: 25, spokeCount: 12, radialSpeed: 2.8, rotateSpeed: 2, volleyDelay: 22, bindRotation: 0 },
			move: path(0, 2).rampTo(0, 0.4, 4, 21).drift(1, 0.3, 150).drift(-1, 0.3, 150).rampTo(0, 4.5, 4, 10).done(),
		})]),

		// -- fast spiral feints
		wave(80, [
			spawn({
				at: [300, -50], time: 0,
				pattern: "spiral", health: 2,
				config: { bulletSpeed: 4, rotationChange: 18, fireDelay: 4 },
				move: dropSweep({ enterVy: 3, amp: 2.6, weaveVy: 2.4, weaveWait: 6, legs: 2, exitVy: 5 }),
			}),
			spawn({
				at: [1400, -50], time: 1.4,
				pattern: "spiral", health: 2,
				config: { bulletSpeed: 4, rotationChange: -18, fireDelay: 4 },
				move: dropSweep({ enterVy: 3, amp: 2.6, weaveVy: 2.4, weaveWait: 6, legs: 2, sign: -1, exitVy: 5 }),
			}),
		]),

		// -- SETPIECE: the satellite launcher patrols a diamond while low
		//    escorts cross beneath it
		wave(84, [
			spawn({
				at: [900, 200], time: 0,
				pattern: "satellite", health: 260,
				config: {
					podCount: 3, orbitRadius: 110, launchFrames: 40, orbitStep: 1.6,
					chargeFrames: 58, beamCount: 7, beamGap: 2, beamSpeed: 8,
					spoolFrames: 20, cruiseFrames: 25, stallFrames: 26,
					explodeCount: 6, explodeSpeed: 3,
					pulseCount: 12, pulseSpeed: 0.9, pulseLife: 150, pulseDelay: 78,
				},
				move: path().drift(0, 2, 84).stop().wait(36)
					.drift(2, 0.5, 108).drift(-2, -0.5, 108)
					.drift(-2, 0.5, 108).drift(2, -0.5, 108)
					.done(true),
			}),
			spiralEscort({ side: 1, y: 480, time: 3, health: 4, bulletSpeed: 3.6, fireDelay: 5, peak: 3, midVy: 1.2, wait: 25 }),
			spiralEscort({ side: -1, y: 480, time: 5, health: 4, bulletSpeed: 3.6, fireDelay: 5, peak: 3, midVy: 1.2, wait: 25 }),
		]),

		// -- parametric orbit showcase: sincos, transform, clover + snipers
		wave(106, [
			spawn({
				at: [500, -50], time: 0,
				pattern: "sincos", health: 20,
				config: { radiusX: 190, radiusY: 60, count: 12, fireDelay: 5, bearingStep: 5 },
				move: path(0, 2).rampTo(0, 1.2, 4, 21).rampTo(2, 1, 4, 21).rampTo(-2, 1, 6, 20).rampTo(0, 4, 4, 12).done(),
			}),
			spawn({
				at: [1300, -50], time: 1.5,
				pattern: "transform", health: 20,
				config: { radius: 150, scaleX: 1, scaleY: 0.35, count: 16, fireDelay: 6, bearingStep: 4, rotationStep: 2 },
				move: path(0, 2).rampTo(0, 1.2, 4, 21).rampTo(-2, 1, 4, 21).rampTo(2, 1, 6, 20).rampTo(0, 4, 4, 12).done(),
			}),
			spawn({
				at: [900, -50], time: 3,
				pattern: "clover", health: 24,
				config: { radius: 200, scaleX: 1, scaleY: 0.4, count: 20, fireDelay: 5, bearingStep: 5, rotationStep: 2.5 },
				move: path(0, 1.8).rampTo(0, 1, 4, 24).wait(210).rampTo(0, 3.5, 4, 12).done(),
			}),
			spawn({
				at: [-50, 240], time: 1.6,
				pattern: "sniper", health: 16,
				config: { bulletSpeed: 12, burstCount: 3, burstDelay: 2, patternDelay: 46 },
				move: flankSweep(1, { enterVy: 0.3, holdVy: 0.4, enterWait: 13, amp: 2.4, weaveWait: 12, legs: 8, exitVy: 2 }),
			}),
			spawn({
				at: [1850, 240], time: 2,
				pattern: "sniper", health: 16,
				config: { bulletSpeed: 12, burstCount: 3, burstDelay: 2, patternDelay: 46 },
				move: flankSweep(-1, { enterVy: 0.3, holdVy: 0.4, enterWait: 13, amp: 2.4, weaveWait: 12, legs: 8, exitVy: 2 }),
			}),
		]),

		// -- escort stream
		wave(110, [
			spiralEscort({ side: 1, y: 150, time: 0, midVy: 1.6, wait: 22 }),
			spiralEscort({ side: -1, y: 180, time: 1.5, midVy: 1.6, wait: 22 }),
			spiralEscort({ side: 1, y: 240, time: 3, midVy: 1.6, wait: 22 }),
		]),

		// -- the garden: flower + flowerdup hover on slow strafes over whips
		wave(116, [
			spawn({
				at: [600, -50], time: 0,
				pattern: "flower", health: 82,
				config: {
					petalCount: 6, petalSpread: 30, seedSpeed: 3, seedTurn: 1.5,
					trailGap: 4, trailSpeed: 0.4, trailAccel: 0.02, trailMax: 1.4, trailLife: 240,
					tipCount: 3, tipArc: 24, tipSpeed: 4.5, ringDelay: 150, ringRotation: 25,
				},
				move: path(0, 2.2).rampTo(0, 0.3, 4, 19)
					.drift(0.8, 0.2, 180).drift(-0.8, 0.2, 180).drift(0.8, 0.2, 180)
					.rampTo(0, -3, 4, 12).done(),
			}),
			spawn({
				at: [1250, -50], time: 0.5,
				pattern: "flowerdup", health: 92,
				config: {
					copies: 32, ways: 9, fanArc: 90, bulletSpeed: 4, offsetDist: 80,
					trioShift: 22.5, tangentOffset: 0, decelTo: 1, decelFrames: 30,
					curveDeg: 210, curveFrames: 60, endSpeed: 2, volleyDelay: 220,
				},
				move: path(0, 2.2).rampTo(0, 0.3, 4, 19)
					.drift(-0.8, 0.2, 180).drift(0.8, 0.2, 180).drift(-0.8, 0.2, 180)
					.rampTo(0, -3, 4, 12).done(),
			}),
			spawn({
				at: [300, -50], time: 4,
				pattern: "nwhip", health: 5,
				config: { numberOfWhips: 4, numberOfBullets: 6, baseBulletSpeed: 3, speedChange: 1, patternDelay: 28 },
				move: dropSweep({ enterVy: 3.2, amp: 2.8, weaveVy: 2.6, weaveWait: 6, legs: 2, exitVy: 5 }),
			}),
			spawn({
				at: [1550, -50], time: 4.5,
				pattern: "nwhip", health: 5,
				config: { numberOfWhips: 4, numberOfBullets: 6, baseBulletSpeed: 3, speedChange: 1, patternDelay: 28 },
				move: dropSweep({ enterVy: 3.2, amp: 2.8, weaveVy: 2.6, weaveWait: 6, legs: 2, sign: -1, exitVy: 5 }),
			}),
			spawn({
				at: [900, -50], time: 7,
				pattern: "nwhip", health: 5,
				config: { numberOfWhips: 4, numberOfBullets: 6, baseBulletSpeed: 3, speedChange: 1.5, patternDelay: 28 },
				move: dropSweep({ enterVy: 3.2, amp: 3, weaveVy: 2.6, weaveWait: 6, legs: 2, exitVy: 5 }),
			}),
		]),

		// -- last escorts before the weaver
		wave(124, [
			spiralEscort({ side: 1, y: 150, time: 0, midVy: 1.6, wait: 22 }),
			spiralEscort({ side: -1, y: 190, time: 1.5, midVy: 1.6, wait: 22 }),
		]),

		// -- SETPIECE: the weaver
		wave(130, [spawn({
			at: [900, 200], time: 0,
			pattern: "weaver", health: 360,
			script: weaverScript,
			move: parkForever(),
		})]),

		// -- deep-field vanish trio, the calm before the finale
		wave(152, [
			spawn({
				at: [-50, 500], time: 0, pattern: "vanish", health: 8,
				move: arcAcross(1, 3.2, 1.4, 24),
			}),
			spawn({
				at: [1850, 500], time: 2, pattern: "vanish", health: 8,
				move: arcAcross(-1, 3.2, 1.4, 24),
			}),
			spawn({
				at: [-50, 540], time: 4, pattern: "vanish", health: 8,
				move: arcAcross(1, 3.2, 1.4, 24),
			}),
		]),

		// -- FINALE: the sol-firedancer
		wave(170, [spawn({
			at: [900, 210], time: 0,
			pattern: "sol-firedancer", health: 950,
			script: solFiredancerScript,
			move: parkForever(),
		})]),
	],
});
