"use strict";
/**
 * BulletHell authoring DSL.
 *
 * Level/pattern sources are plain Node modules (see tools/src/) that build
 * JSON with these helpers and export the result via level() / pattern().
 * tools/compile.js validates everything and writes the exact JSON formats
 * the engine already parses — the engine itself is untouched.
 *
 * Two builder namespaces:
 *   S — shot-script controls (mirror Source/Shot/CommandRegistry 1:1)
 *   M — enemy movement helpers (compile to SetVelocity/Wait/Stop chains,
 *       the main source of hand-written JSON bloat)
 *
 * Everything is a pure function returning plain data: deterministic output,
 * reusable via ordinary JS functions, variables and loops.
 */

// ---------------------------------------------------------------------------
// small utils
// ---------------------------------------------------------------------------

/** Flatten one level of nesting so helpers can return action groups. */
function flat(parts) {
	const out = [];
	for (const p of parts) {
		if (Array.isArray(p)) out.push(...flat(p));
		else if (p !== null && p !== undefined) out.push(p);
	}
	return out;
}

function round2(v) {
	return Math.round(v * 100) / 100;
}

// ---------------------------------------------------------------------------
// S — shot script builders (bullet patterns)
// ---------------------------------------------------------------------------

const S = {
	// --- flow -------------------------------------------------------------
	wait: (frames) => ({ control: "Wait", frames }),
	loop: (...actions) => ({ control: "Loop", actions: flat(actions) }),
	rep: (count, ...actions) => ({ control: "Rep", count, actions: flat(actions) }),
	/** concurrent(branchA, branchB, ...) — each branch is an array of actions. */
	concurrent: (...branches) => ({ control: "Concurrent", branches: branches.map(flat) }),
	/** Like concurrent, but branches share (mutate) the parent prototype. */
	concurrentShared: (...branches) => ({ control: "Concurrent", share: true, branches: branches.map(flat) }),
	/** Attach a script the fired bullet runs itself (nested patterns). */
	sub: (...actions) => ({ control: "Sub", actions: flat(actions) }),
	/** Run body against a discarded prototype clone (burst configuration). */
	scope: (...actions) => ({ control: "Scope", actions: flat(actions) }),
	vanish: () => ({ control: "Vanish" }),

	// --- firing -----------------------------------------------------------
	/** fire() uses the prototype's current direction/speed (engine 0-convention). */
	fire: (angle = 0, speed = 0) => ({ control: "Fire", angle, speed }),
	radial: (count, speed = 0) => ({ control: "Radial", count, speed }),
	nway: (count, angle, speed = 0) => ({ control: "NWay", count, angle, speed }),
	line: (count, prop, from, to) => ({ control: "Line", count, prop, from, to }),
	/** dup(5, {direction: {from:-30, to:30}, speed: {min:2, max:6}}) */
	dup: (count, props) => ({ control: "Dup", count, props }),

	// --- prototype properties ----------------------------------------------
	set: (prop, value) => ({ control: "Set", prop, value }),
	/** Bullet visual + hitbox scale (engine "size" property; bosses default 1.5). */
	size: (value) => ({ control: "Set", prop: "size", value }),
	add: (prop, delta) => ({ control: "Add", prop, delta }),
	random: (prop, min, max) => ({ control: "Random", prop, min, max }),
	copy: (from, to, scale) => scale === undefined
		? { control: "Copy", from, to }
		: { control: "Copy", from, to, scale },
	tween: (prop, to, frames, relative = false) => relative
		? { control: "Tween", prop, to, frames, relative: true }
		: { control: "Tween", prop, to, frames },

	// --- placement / transforms --------------------------------------------
	offset: (distance, angle) => ({ control: "SetOffset", distance, angle }),
	addOffset: (distanceDelta, angleDelta) => ({ control: "AddOffset", distanceDelta, angleDelta }),
	rotate: (degrees, withDirection = false) => withDirection
		? { control: "Rotate", degrees, withDirection: true }
		: { control: "Rotate", degrees },
	scale: (factor) => ({ control: "Scale", factor }),
	scaleXY: (x, y) => ({ control: "Scale", x, y }),

	// --- binding / aiming ---------------------------------------------------
	/** mode: "position" | "full" | "offset" | "none" */
	bind: (mode = "position") => ({ control: "Bind", mode }),
	aim: () => ({ control: "AimAtPlayer" }),
};

// ---------------------------------------------------------------------------
// M — enemy movement helpers (compile to SetVelocity/Wait/Stop)
// ---------------------------------------------------------------------------

const M = {
	vel: (vx, vy) => ({ type: "SetVelocity", vx, vy }),
	wait: (frames) => ({ type: "Wait", frames }),
	stop: () => ({ type: "Stop" }),

	/** Stop and sit still for `frames`. */
	hold: (frames) => [M.stop(), M.wait(frames)],

	/** Travel at (vx, vy) for `frames`. */
	drift: (vx, vy, frames) => [M.vel(vx, vy), M.wait(frames)],

	/**
	 * Screen entry: fly in from a side at `speed` for `frames`, then keep
	 * whatever comes next (chain hold()/drift()/easeTo after it).
	 * side: "left" | "right" | "top" | "bottom"
	 */
	enterFrom: (side, speed, frames) => {
		const v = {
			left: [speed, 0],
			right: [-speed, 0],
			top: [0, speed],
			bottom: [0, -speed],
		}[side];
		if (!v) throw new Error(`enterFrom: unknown side "${side}"`);
		return M.drift(v[0], v[1], frames);
	},

	/**
	 * Smoothly change velocity from [vx0,vy0] to [vx1,vy1] over `frames`,
	 * sampled into `steps` SetVelocity/Wait chunks (default: one chunk per
	 * ~5 frames). ease: "linear" | "quadOut" | "sineInOut".
	 */
	easeTo: ({ from, to, frames, steps, ease = "sineInOut" }) => {
		const fns = {
			linear: (t) => t,
			quadOut: (t) => 1 - (1 - t) * (1 - t),
			sineInOut: (t) => 0.5 - 0.5 * Math.cos(Math.PI * t),
		};
		const fn = fns[ease];
		if (!fn) throw new Error(`easeTo: unknown ease "${ease}"`);
		const n = Math.max(1, steps || Math.round(frames / 5));
		const chunk = frames / n;
		const out = [];
		for (let i = 0; i < n; i++) {
			// velocity at the midpoint of the chunk, so the integral ~matches
			const t = fn((i + 0.5) / n);
			out.push(M.vel(
				round2(from[0] + (to[0] - from[0]) * t),
				round2(from[1] + (to[1] - from[1]) * t)
			));
			out.push(M.wait(Math.round(chunk * (i + 1)) - Math.round(chunk * i)));
		}
		return out;
	},

	/**
	 * Sinusoidal weave: horizontal velocity swings ±vx with `period` frames
	 * per full cycle, for `cycles` cycles, while sinking at vy. Sampled every
	 * `step` frames (default 6).
	 */
	weave: ({ vx, vy = 0, period, cycles, step = 6 }) => {
		const total = Math.round(period * cycles);
		const out = [];
		for (let f = 0; f < total; f += step) {
			const frames = Math.min(step, total - f);
			out.push(M.vel(round2(vx * Math.sin((2 * Math.PI * f) / period)), vy));
			out.push(M.wait(frames));
		}
		return out;
	},

	/** Assemble a movement script: M.script({loop: true}, partA, partB, ...) */
	script: (opts, ...parts) => ({
		loop: !!(opts && opts.loop),
		actions: flat(parts),
	}),
};

// ---------------------------------------------------------------------------
// level / wave / spawn / pattern constructors
// ---------------------------------------------------------------------------

/**
 * spawn({at: [x, y], time: 0, pattern: "spiral", config: {...},
 *        health: 3, sprite: "enemy2", move: M.script(...),
 *        script: [S...]})       // inline shot script instead of `pattern`
 */
function spawn(o) {
	const e = {
		spawnTime: o.time ?? 0,
		x: o.at[0],
		y: o.at[1],
		pattern: o.pattern ?? "inline",
		patternConfig: o.config ? { ...o.config } : {},
	};
	if (o.script) e.patternConfig.patternScript = { actions: flat([o.script]) };
	if (o.health !== undefined) e.health = o.health;
	if (o.velocity) { e.velocityX = o.velocity[0]; e.velocityY = o.velocity[1]; }
	if (o.move) e.movementScript = o.move;
	if (o.sprite) e.sprite = o.sprite;
	if (o.boss) e.boss = o.boss;
	return e;
}

/**
 * boss("Name", phase(...), phase(...)) -> value for spawn({boss: ...}).
 * Phases are fought in order; clearing the last one kills the boss.
 */
function boss(name, ...phases) {
	return { name, phases: flat(phases) };
}

/**
 * phase({name, health, timeout, pattern, config, script, move})
 * name    spell card title shown on the boss bar (omit for a "nonspell")
 * health  damage needed to clear the phase
 * timeout seconds until the phase auto-clears with no drops (Touhou-style);
 *         omit for no timeout. The boss bar shows the countdown.
 * pattern + config, or script: [S...] for an inline shot script
 * move    M.script(...) replacing the boss's movement for this phase
 */
function phase(o) {
	const p = { health: o.health };
	if (o.name) p.name = o.name;
	if (o.timeout) p.timeoutFrames = Math.round(o.timeout * 60);
	if (o.pattern) p.pattern = o.pattern;
	if (o.config) p.patternConfig = { ...o.config };
	if (o.script) p.script = flat([o.script]);
	if (o.move) p.movementScript = o.move;
	return p;
}

/** wave(startTimeSeconds, [spawn, ...]) */
function wave(startTime, enemies) {
	return { startTime, enemies: flat([enemies]) };
}

/** One dialogue line. side defaults to "left". */
function say(speaker, text, portrait, side) {
	const d = { speaker, text };
	if (portrait) d.portrait = portrait;
	if (side) d.side = side;
	return d;
}

/**
 * level("level4", "Stage 4 — ...", {dialogue: {...}, waves: [...]})
 * -> written to Assets/levels/<file>.json
 */
function level(file, name, { dialogue, waves }) {
	const data = { name };
	if (dialogue) data.dialogue = dialogue;
	data.waves = waves;
	return { kind: "level", file, data };
}

/**
 * pattern("myPattern", "description", {param: {type, default, description}}, [S...])
 * -> written to Assets/patterns/<name>.json
 */
function pattern(name, description, parameters, script) {
	return {
		kind: "pattern",
		file: name,
		data: { name, description, parameters: parameters || {}, script: flat([script]) },
	};
}

module.exports = { S, M, spawn, wave, say, level, pattern, boss, phase, flat };
