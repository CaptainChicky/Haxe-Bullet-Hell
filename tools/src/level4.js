"use strict";
/**
 * Stage 4 — The Gilded Court. Final stage: a real escort gauntlet, the
 * Seneschal midboss, then Aurelia as a six-phase final boss.
 *
 * Balance model (Touhou-style, tuned against the rebalanced player):
 *  - By stage 4 the player is at power 3.00-4.00 → ~40-60 peak single-target
 *    DPS, call it ~30 effective once dodging eats uptime.
 *  - Boss phases alternate unnamed "nonspells" and named spell cards, each
 *    sized for ~25-40s of effective damage, with a Touhou-style timeout so
 *    an underpowered run can never stall the fight (timeouts award no drops).
 *  - Dodge ceiling is Touhou Hard: nothing faster than ~14 px/frame, fast
 *    bullets always telegraphed (aimed lines / layered rings), dense layers
 *    kept slow and readable.
 *
 * Compile: node tools/compile.js  ->  Assets/levels/level4.json
 */
const { S, M, spawn, wave, say, level, boss, phase } = require("../bh");

// Screen coordinates follow the existing levels (~1800x1080 playfield).
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

/** Spiral escort crossing the field. side: 1 = from the left, -1 = right. */
function crosser(side, y, time, health = 18) {
	return spawn({
		at: [side > 0 ? -50 : 1850, y], time,
		pattern: "spiral", health,
		config: { bulletSpeed: 3.4, rotationChange: side * 14, fireDelay: 4 },
		move: M.script({},
			M.drift(side * 3, 1.2, 120),
			M.drift(side * 2.2, 3, 200),
		),
	});
}

// --------------------------------------------------------------------- escorts

function topRadial(x, time, health = 30) {
	return spawn({
		at: [x, -50], time,
		pattern: "radial", health,
		config: { bulletCount: 14, bulletSpeed: 3.2, rotationSpeed: 4 },
		move: dropIn(2.5, 90, 360),
	});
}

function sniper(x, y, time) {
	return spawn({
		at: [x, -50], time,
		pattern: "sniper", health: 26,
		config: { bulletSpeed: 12, burstCount: 3, burstDelay: 3, orbitDistance: 120, patternDelay: 42 },
		move: dropIn(2.5, 60 + y / 3, 420),
	});
}

/** Royal guard: heavy platform cycling wide fans and a dense ring. */
function royalGuard(x, mirror, time) {
	return spawn({
		at: [x, -60], time,
		pattern: "guard-fans", health: 75,
		script: [
			S.set("direction", 90), S.set("speed", 3.4),
			S.loop(
				S.rep(6, S.nway(7, 60, 0), S.add("direction", mirror * 4), S.wait(9)),
				S.set("direction", 90), S.wait(26),
				S.radial(30, 2.6), S.wait(48),
			),
		],
		move: dropIn(2.2, 100, 640),
	});
}

// --------------------------------------------- MIDBOSS: Seneschal of the Court

// Rotating twin-spoke cage (slow, readable lattice) with periodic aimed
// three-way darts punching through it. Holds ~42s, leaves if unbeaten.
const seneschalScript = [
	S.set("direction", 90), S.set("speed", 3.0),
	S.concurrent(
		[S.loop(S.radial(8, 0), S.add("direction", 5.5), S.wait(6))],
		[S.set("direction", 112), S.loop(S.radial(8, 0), S.add("direction", -5.5), S.wait(6))],
		[S.loop(S.wait(90), S.aim(), S.rep(3, S.nway(3, 15, 7), S.wait(7)))],
	),
];

// ------------------------------------------------------------------ the boss

// P1 — nonspell: aimed fan volleys trading with slow full rings. Classic
// opener: teaches the "sidestep the fans, weave the ring" rhythm.
const phase1 = phase({
	health: 700,
	timeout: 40,
	script: [
		S.wait(30),
		S.loop(
			S.aim(),
			S.rep(3, S.nway(5, 14, 6.2), S.wait(8)),
			S.wait(18),
			S.scope(S.set("direction", 90), S.radial(32, 2.4)),
			S.wait(30),
			S.aim(),
			S.rep(3, S.nway(7, 10, 6.8), S.wait(7)),
			S.wait(18),
			S.scope(S.set("direction", 90), S.add("direction", "random.between(-12, 12)"), S.radial(32, 2.8)),
			S.wait(34),
		),
	],
});

// P2 — spell: twin spirals that periodically reverse spin (the moiré
// "breathing" read), with aimed feather darts forcing repositioning.
const phase2 = phase({
	name: "Feather Sign - Moulting Cyclone",
	health: 900,
	timeout: 55,
	script: [
		S.wait(20),
		S.concurrent(
			[S.loop(
				S.rep(26, S.radial(5, 2.8), S.add("direction", 7.3), S.wait(4)),
				S.rep(26, S.radial(5, 3.3), S.add("direction", -6.1), S.wait(4)),
			)],
			[S.set("direction", 36), S.loop(
				S.rep(26, S.radial(5, 2.8), S.add("direction", -7.3), S.wait(4)),
				S.rep(26, S.radial(5, 3.3), S.add("direction", 6.1), S.wait(4)),
			)],
			[S.loop(S.wait(96), S.aim(), S.rep(3, S.nway(3, 26, 7.4), S.wait(6)))],
		),
	],
	move: M.script({ loop: true }, M.weave({ vx: 2.0, vy: 0, period: 220, cycles: 1 })),
});

// P3 — nonspell: the queen dances (moveSelf lunges) while raking aimed
// gatling sweeps and panic rings — pressure phase, sparse but personal.
const dash = (dir, speed, frames) => [
	S.set("direction", dir),
	S.tween("speed", speed, frames),
	S.tween("speed", 0, frames),
];

const phase3 = phase({
	health: 700,
	timeout: 40,
	script: [
		S.set("moveSelf", 1), S.set("direction", 90), S.set("speed", 0),
		S.wait(24),
		S.loop(
			dash(180, 4, 20),
			S.aim(), S.scope(S.set("speed", 8), S.nway(3, 3, 0)), S.wait(26),
			S.aim(), S.rep(16, S.scope(S.set("speed", 12), S.nway(7, 7, 0)), S.add("direction", 1.5), S.wait(3)),
			S.scope(S.set("speed", 2.5), S.radial(24, 0)), S.wait(40),
			dash(0, 4, 20),
			S.aim(), S.scope(S.set("speed", 8), S.nway(3, 3, 0)), S.wait(26),
			S.aim(), S.rep(16, S.scope(S.set("speed", 12), S.nway(7, 7, 0)), S.add("direction", -1.5), S.wait(3)),
			S.scope(S.set("speed", 2.5), S.radial(24, 0)), S.wait(40),
		),
	],
	move: M.script({}, M.stop()),
});

// P4 — spell: crossing curtain sheets build a drifting diamond lattice while
// slow giant orbs (size 2.4) force the player to keep choosing new cells.
const phase4 = phase({
	name: "Cage Sign - Gilded Aviary",
	health: 950,
	timeout: 60,
	script: [
		S.wait(20),
		S.concurrent(
			[S.loop(
				S.scope(S.set("direction", 78), S.dup(11, { x: { from: -700, to: 700 }, speed: { min: 2.2, max: 2.6 } })),
				S.wait(46),
				S.scope(S.set("direction", 102), S.dup(11, { x: { from: -630, to: 770 }, speed: { min: 2.2, max: 2.6 } })),
				S.wait(46),
			)],
			[S.loop(S.wait(150), S.scope(S.size(2.4), S.aim(), S.rep(2, S.fire(0, 3.0), S.wait(12))))],
			[S.loop(S.random("direction", 65, 115), S.fire(0, "random.between(2.4, 4.6)"), S.wait(6))],
		),
	],
	move: M.script({ loop: true },
		M.drift(1.1, 0, 110),
		M.drift(-1.1, 0, 220),
		M.drift(1.1, 0, 110),
	),
});

// P5 — spell: the showpiece. Radial seed rings decelerate, curl into a
// blooming petal spiral (each seed steers itself via its sub-script), then
// re-accelerate outward — alternating curl direction each ring — while
// aimed dart fans keep the player honest.
function bloom(curl) {
	return S.scope(
		S.set("speed", 5.2),
		S.sub(
			S.concurrentShared(
				[S.tween("speed", 0.8, 36)],
				[S.wait(10), S.tween("direction", curl, 50, true)],
			),
			S.tween("speed", 3.4, 40),
		),
		S.radial(28, 0),
	);
}

const phase5 = phase({
	name: "Wing Sign - Thousand-Feather Bloom",
	health: 1000,
	timeout: 65,
	script: [
		S.wait(24),
		S.concurrent(
			[S.loop(
				bloom(130), S.add("direction", 6.5), S.wait(52),
				bloom(-130), S.add("direction", 6.5), S.wait(52),
			)],
			[S.loop(S.wait(140), S.aim(), S.rep(3, S.nway(5, 9, 7.2), S.wait(6)))],
		),
	],
	move: M.script({}, M.stop()),
});

// P6 — Last Word: everything the court has left, layered but readable —
// slow counter-rotating spirals as the canvas, layered shockwave rings as
// the telegraphed fast threat, orbital pod rings that orbit and spray, and
// aimed spear fans on a long cadence.
const phase6 = phase({
	name: "Last Word - Empress of the Endless Sky",
	health: 1200,
	timeout: 90,
	script: [
		S.wait(30),
		S.concurrent(
			[S.loop(S.radial(5, 2.9), S.add("direction", 4.7), S.wait(5))],
			[S.set("direction", 36), S.loop(S.radial(5, 2.9), S.add("direction", -3.9), S.wait(5))],
			[S.loop(
				S.wait(300),
				S.scope(
					S.set("speed", 0), S.set("offsetDistance", 40), S.set("offsetAngle", 0), S.set("lifetime", 280),
					S.bind("offset"),
					S.sub(
						S.tween("offsetDistance", 200, 50),
						S.rep(56,
							S.scope(S.set("offsetDistance", 0), S.set("speed", 3.1), S.bind("none"), S.fire(0, 0)),
							S.add("offsetAngle", -3.2), S.add("direction", 12), S.wait(3),
						),
						S.vanish(),
					),
					S.rep(8, S.fire(0, 0), S.add("offsetAngle", 45)),
				),
			)],
			[S.loop(
				S.wait(210),
				S.scope(S.radial(56, 2.2)), S.wait(12),
				S.scope(S.radial(44, 4.4)), S.wait(12),
				S.scope(S.radial(30, 6.6)),
			)],
			[S.loop(S.wait(170), S.aim(), S.rep(2, S.nway(9, 7, 7.4), S.wait(9)))],
		),
	],
	move: M.script({}, M.stop()),
});

const aurelia = spawn({
	at: [CX, -80], time: 0,
	sprite: "enemy2",
	// entrance: glide down to the fighting position; phase 1 deliberately has
	// no move script so this glide isn't replaced mid-entrance.
	move: M.script({}, M.drift(0, 3.2, 100), M.stop()),
	boss: boss("Aurelia, Queen of the Aviary",
		phase1, phase2, phase3, phase4, phase5, phase6),
});

// ------------------------------------------------------------------- the level

module.exports = level("level4", "Stage 4 - The Gilded Court", {
	dialogue: {
		intro: [
			say("Aviator", "The signal jamming, the swarms, the fire... it all leads here.", "assets/Player.png", "left"),
			say("???", "And here you are, little bird, at the doors of my court.", "assets/Enemy(second).png", "right"),
			say("Aurelia", "I am Aurelia, Queen of the Aviary. Every wing in this sky beats at MY command.", "assets/Enemy(second).png", "right"),
			say("Aviator", "Then I'll just have to clip yours.", "assets/Player.png", "left"),
			say("Aurelia", "Bold. Let us see how you dance beneath a thousand wings!", "assets/Enemy(second).png", "right"),
		],
		outro: [
			say("Aurelia", "My court... my beautiful, gilded court...", "assets/Enemy(second).png", "right"),
			say("Aviator", "The sky doesn't belong to anyone. That's what makes it worth flying.", "assets/Player.png", "left"),
			say("Aurelia", "Hmph. Then fly, little bird... while I rebuild my choir.", "assets/Enemy(second).png", "right"),
		],
	},
	waves: [
		// -- honor guard skirmish: crossers from both flanks
		wave(0, [
			crosser(1, 140, 0), crosser(-1, 180, 0.8),
			crosser(1, 220, 1.6), crosser(-1, 140, 2.4),
			crosser(1, 180, 3.2), crosser(-1, 220, 4.0),
		]),

		// -- radial platforms with sniper cover
		wave(9, [
			topRadial(CX - 420, 0),
			topRadial(CX + 420, 0.6),
			sniper(CX - 120, 200, 1.5),
			sniper(CX + 120, 200, 2.0),
		]),

		// -- the royal guard: two heavy fan platforms + crosser pressure
		wave(21, [
			royalGuard(CX - 320, 1, 0),
			royalGuard(CX + 320, -1, 0.7),
			crosser(1, 300, 3, 16),
			crosser(-1, 340, 4.5, 16),
		]),

		// -- MIDBOSS: the Seneschal — rotating cage + aimed darts; holds ~42s
		wave(34, [
			spawn({
				at: [CX, -70], time: 0,
				pattern: "seneschal-cage", health: 500,
				script: seneschalScript,
				move: M.script({},
					M.drift(0, 3, 100),
					M.hold(2500),
					M.vel(0, -2.5),
				),
			}),
		]),

		// -- escorts trickle through the cage's tail end
		wave(52, [
			crosser(1, 160, 0, 16),
			crosser(-1, 200, 1.4, 16),
			crosser(1, 240, 2.8, 16),
		]),

		// -- last pressure wave before the throne
		wave(62, [
			spawn({
				at: [CX - 500, -50], time: 0,
				pattern: "random", health: 30,
				config: { minSpeed: 1.5, maxSpeed: 4, baseAngle: 90, angleSpread: 55, fireDelay: 5 },
				move: dropIn(2.4, 90, 420),
			}),
			spawn({
				at: [CX + 500, -50], time: 0.8,
				pattern: "random", health: 30,
				config: { minSpeed: 1.5, maxSpeed: 4, baseAngle: 90, angleSpread: 55, fireDelay: 5 },
				move: dropIn(2.4, 90, 420),
			}),
			spawn({
				at: [CX, -50], time: 1.6,
				pattern: "shotspeed", health: 24,
				config: { direction: 90, baseSpeed: 2.6, speedStep: 0.45, burstCount: 16, fireDelay: 1, volleyDelay: 40 },
				move: dropIn(2.6, 80, 380),
			}),
		]),

		// -- the queen herself
		wave(74, [aurelia]),
	],
});
