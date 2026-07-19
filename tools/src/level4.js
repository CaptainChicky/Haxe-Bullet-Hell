"use strict";
/**
 * Stage 4 — boss stage. First real level authored in the DSL: a short escort
 * intro, then a four-phase boss fight with spell cards.
 *
 * Compile: node tools/compile.js  ->  Assets/levels/level4.json
 */
const { S, M, spawn, wave, say, level, boss, phase } = require("../bh");

// Screen coordinates follow the existing levels (~1800 wide playfield).
const CX = 900;

// --------------------------------------------------------------------- escorts

function sideSpiral(x, dirX, time) {
	return spawn({
		at: [x, 140], time,
		pattern: "spiral",
		config: {},
		health: 3,
		velocity: [dirX, 0],
	});
}

function topRadial(x, time) {
	return spawn({
		at: [x, -50], time,
		pattern: "radial",
		config: {},
		health: 4,
		velocity: [0, 2],
		move: M.script({},
			M.drift(0, 2, 90),
			M.hold(300),
			M.drift(0, -3, 120),
		),
	});
}

// ------------------------------------------------------------------ the boss

const phase1 = phase({
	name: "Opening - Gilded Volley",
	health: 40,
	config: { volleyCount: 5, volleySpeed: 6.5, ringCount: 26, ringSpeed: 2.5, startDelay: 40 },
	script: [
		S.loop(
			S.aim(),
			S.rep(3, S.nway("$volleyCount", 12, "$volleySpeed"), S.wait(9)),
			S.wait(26),
			S.radial("$ringCount", "$ringSpeed"),
			S.wait(45),
		),
	],
});

const phase2 = phase({
	name: "Feather Sign - Petal Storm",
	health: 50,
	config: { arms: 7, armSpeed: 3, spin: 7, armGap: 6, dartSpeed: 8 },
	script: [
		S.set("angle", 0),
		S.concurrent(
			// rotating radial arms...
			[S.loop(S.radial("$arms", "$armSpeed"), S.add("angle", "$spin"), S.wait("$armGap"))],
			// ...plus a periodic aimed dart burst (own prototype clone, so the
			// aim doesn't disturb the arm rotation)
			[S.loop(S.wait(110), S.aim(), S.rep(4, S.fire(0, "$dartSpeed"), S.wait(5)))],
		),
	],
	move: M.script({ loop: true }, M.weave({ vx: 2.2, vy: 0, period: 200, cycles: 1 })),
});

const phase3 = phase({
	name: "Cage Sign - Starfall Lattice",
	health: 55,
	config: {
		rainMin: 2.5, rainMax: 6, rainSpread: 55, rainGap: 3,
		lineCount: 6, lineMin: 4, lineMax: 9,
	},
	script: [
		S.concurrent(
			// falling stars: random speed/angle rain in a downward cone
			[S.loop(
				S.random("speed", "$rainMin", "$rainMax"),
				S.random("angle", "90 - $rainSpread", "90 + $rainSpread"),
				S.fire(0, 0),
				S.wait("$rainGap"),
			)],
			// lattice bars: aimed lines of bullets at staggered speeds
			[S.loop(
				S.wait(70),
				S.aim(),
				S.line("$lineCount", "speed", "$lineMin", "$lineMax"),
			)],
		),
	],
	move: M.script({ loop: true },
		M.drift(1.5, 0, 60),
		M.drift(-1.5, 0, 120),
		M.drift(1.5, 0, 60),
	),
});

const phase4 = phase({
	name: "Last Word - Thousand-Wing Bloom",
	health: 70,
	config: { arms: 5, spiralSpeed: 2.8, spinA: 5, spinB: -3.5, burstSpeed: 6 },
	script: [
		S.set("angle", 0),
		S.concurrent(
			// counter-rotating double spiral (each branch keeps its own angle)
			[S.loop(S.radial("$arms", "$spiralSpeed"), S.add("angle", "$spinA"), S.wait(5))],
			[S.loop(S.radial("$arms", "$spiralSpeed"), S.add("angle", "$spinB"), S.wait(5))],
			// occasional aimed fan on top
			[S.loop(S.wait(150), S.scope(S.aim(), S.rep(2, S.nway(9, 8, "$burstSpeed"), S.wait(8))))],
		),
	],
	move: M.script({}, M.stop()),
});

const aurelia = spawn({
	at: [CX, -80], time: 0,
	sprite: "enemy2",
	// entrance: glide down to the fighting position, then phases take over
	move: M.script({}, M.drift(0, 3.5, 86), M.stop()),
	boss: boss("Aurelia, Queen of the Aviary", phase1, phase2, phase3, phase4),
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
		// honor guard skirmish while the queen watches
		wave(0, [
			sideSpiral(-50, 3, 0),
			sideSpiral(1850, -3, 0),
			topRadial(CX, 1.5),
		]),
		wave(7, [
			topRadial(CX - 400, 0),
			topRadial(CX + 400, 0),
		]),
		// the queen herself
		wave(16, [aurelia]),
	],
});
