"use strict";
/**
 * Static validator for compiled level / pattern JSON (both DSL output and
 * legacy hand-written files). Catches the errors that otherwise only show up
 * as runtime trace()s or silent misbehavior:
 *
 *   - unknown control names / misspelled fields
 *   - zero-frame infinite loops (Loop with no Wait/Tween on any iteration)
 *   - unreachable commands after an infinite construct
 *   - malformed Concurrent/Rep/Dup structures
 *   - expression syntax errors and undefined $parameter references
 *   - malformed movement scripts, waves and dialogue
 *
 * Returns a list of {level: "error"|"warning", file, path, message}.
 */

const fs = require("fs");
const path = require("path");

// --- control schema: allowed + required fields per control -----------------
// (mirrors Source/Shot/CommandRegistry.hx)
const CONTROLS = {
	Wait: { req: ["frames"], opt: [] },
	Loop: { req: ["actions"], opt: [] },
	Rep: { req: ["count", "actions"], opt: [] },
	Concurrent: { req: ["branches"], opt: ["share"] },
	Sub: { req: ["actions"], opt: [] },
	Scope: { req: ["actions"], opt: [] },
	Vanish: { req: [], opt: [] },
	Fire: { req: [], opt: ["angle", "speed"] },
	Radial: { req: ["count"], opt: ["speed"] },
	NWay: { req: ["count", "angle"], opt: ["speed"] },
	Line: { req: ["count", "prop", "from", "to"], opt: [] },
	Dup: { req: ["count", "props"], opt: [] },
	Set: { req: ["prop", "value"], opt: [] },
	Add: { req: ["prop", "delta"], opt: [] },
	Random: { req: ["prop", "min", "max"], opt: [] },
	Copy: { req: ["from", "to"], opt: ["scale"] },
	Tween: { req: ["prop", "to", "frames"], opt: ["relative"] },
	Rotate: { req: ["degrees"], opt: ["withDirection"] },
	Scale: { req: [], opt: ["factor", "x", "y"] },
	Bind: { req: ["mode"], opt: [] },
	AimAtPlayer: { req: [], opt: [] },
	// legacy aliases (existing content)
	SetAngle: { req: ["value"], opt: [] },
	AddAngle: { req: ["delta"], opt: [] },
	SetSpeed: { req: ["value"], opt: [] },
	AddSpeed: { req: ["delta"], opt: [] },
	SetOffset: { req: ["distance", "angle"], opt: [] },
	AddOffset: { req: ["distanceDelta", "angleDelta"], opt: [] },
	CopyAngleToOffset: { req: [], opt: [] },
	CopyOffsetToAngle: { req: [], opt: [] },
	RandomSpeed: { req: ["min", "max"], opt: [] },
	RandomAngle: { req: ["min", "max"], opt: [] },
};

// Fields holding names/enums rather than numeric expressions.
const NAME_FIELDS = new Set(["control", "prop", "mode"]);
const BOOL_FIELDS = new Set(["share", "withDirection", "relative"]);
const KNOWN_FUNCTIONS = new Set(["sin", "cos", "random.between", "random.angle"]);
const BIND_MODES = new Set(["position", "full", "offset", "none"]);

class Ctx {
	constructor(file) {
		this.file = file;
		this.issues = [];
	}
	error(p, msg) {
		this.issues.push({ level: "error", file: this.file, path: p, message: msg });
	}
	warn(p, msg) {
		this.issues.push({ level: "warning", file: this.file, path: p, message: msg });
	}
}

// ---------------------------------------------------------------------------
// expressions
// ---------------------------------------------------------------------------

/** Syntax-check an expression string; report undefined $params against
 *  paramSet (null = don't check params). */
function checkExpression(ctx, p, expr, paramSet) {
	const s = String(expr);
	let depth = 0;
	for (const ch of s) {
		if (ch === "(") depth++;
		else if (ch === ")") depth--;
		if (depth < 0) break;
	}
	if (depth !== 0) ctx.error(p, `unbalanced parentheses in expression "${s}"`);

	if (/[^A-Za-z0-9_.$+\-*/(), ]/.test(s)) {
		ctx.error(p, `illegal character in expression "${s}"`);
	}

	// identifiers followed by "(" must be known functions
	const callRe = /([A-Za-z_][A-Za-z0-9_.]*)\s*\(/g;
	let m;
	while ((m = callRe.exec(s)) !== null) {
		if (!KNOWN_FUNCTIONS.has(m[1])) {
			ctx.error(p, `unknown function "${m[1]}" in expression "${s}"`);
		}
	}

	if (paramSet) {
		const paramRe = /\$([A-Za-z_][A-Za-z0-9_]*)/g;
		while ((m = paramRe.exec(s)) !== null) {
			if (!paramSet.has(m[1])) {
				ctx.error(p, `undefined parameter "$${m[1]}" in expression "${s}"`);
			}
		}
	}
}

/** A numeric field: number, or expression string. */
function checkNum(ctx, p, v, paramSet) {
	if (typeof v === "number") return;
	if (typeof v === "string") return checkExpression(ctx, p, v, paramSet);
	ctx.error(p, `expected number or expression string, got ${JSON.stringify(v)}`);
}

// ---------------------------------------------------------------------------
// shot scripts
// ---------------------------------------------------------------------------

/** Does executing this action list consume at least one frame per pass?
 *  (Wait > 0, Tween frames > 0, or a blocking Concurrent whose branches all
 *  consume time — conservative: any branch consuming time blocks the parent.) */
function consumesTime(actions) {
	if (!Array.isArray(actions)) return false;
	for (const a of actions) {
		if (!a || typeof a !== "object") continue;
		switch (a.control) {
			case "Wait":
				if (typeof a.frames === "string" || (typeof a.frames === "number" && a.frames > 0)) return true;
				break;
			case "Tween":
				if (typeof a.frames === "string" || (typeof a.frames === "number" && a.frames > 0)) return true;
				break;
			case "Loop":
				// an inner infinite loop that consumes time blocks forever —
				// which also means "this list does not finish in zero frames"
				if (consumesTime(a.actions)) return true;
				break;
			case "Rep":
				if (consumesTime(a.actions)) return true;
				break;
			case "Scope":
				if (consumesTime(a.actions)) return true;
				break;
			case "Concurrent":
				// parent blocks until every branch finishes; if any branch
				// takes time, at least one frame passes
				if (Array.isArray(a.branches) && a.branches.some((b) => consumesTime(b))) return true;
				break;
		}
	}
	return false;
}

/** Does this list contain an infinite Loop (i.e. it never finishes)? */
function neverFinishes(actions) {
	if (!Array.isArray(actions)) return false;
	for (const a of actions) {
		if (!a || typeof a !== "object") continue;
		if (a.control === "Loop") return true;
		if (a.control === "Rep" && neverFinishes(a.actions)) return true;
		if (a.control === "Scope" && neverFinishes(a.actions)) return true;
		if (a.control === "Concurrent" && Array.isArray(a.branches)
			&& a.branches.some((b) => neverFinishes(b))) return true;
	}
	return false;
}

function checkScript(ctx, p, actions, paramSet) {
	if (!Array.isArray(actions)) {
		ctx.error(p, "script must be an array of control objects");
		return;
	}
	actions.forEach((a, i) => {
		const ap = `${p}[${i}]`;
		if (!a || typeof a !== "object" || Array.isArray(a)) {
			ctx.error(ap, "control entry must be an object");
			return;
		}
		const schema = CONTROLS[a.control];
		if (!schema) {
			ctx.error(ap, `unknown control "${a.control}"`);
			return;
		}
		// field inventory
		for (const key of Object.keys(a)) {
			if (key === "control") continue;
			if (!schema.req.includes(key) && !schema.opt.includes(key)) {
				ctx.warn(ap, `"${a.control}" does not use field "${key}" (typo?)`);
			}
		}
		for (const key of schema.req) {
			if (a[key] === undefined) ctx.error(ap, `"${a.control}" is missing required field "${key}"`);
		}
		// field values
		for (const [key, v] of Object.entries(a)) {
			if (key === "control" || v === undefined) continue;
			if (key === "actions" || key === "branches" || key === "props") continue;
			if (NAME_FIELDS.has(key)) {
				if (typeof v !== "string") ctx.error(`${ap}.${key}`, "must be a string");
				else if (a.control === "Bind" && !BIND_MODES.has(v)) {
					ctx.error(`${ap}.${key}`, `unknown bind mode "${v}"`);
				}
			} else if (BOOL_FIELDS.has(key)) {
				if (typeof v !== "boolean") ctx.error(`${ap}.${key}`, "must be a boolean");
			} else if (a.control === "Copy" && (key === "from" || key === "to")) {
				if (typeof v !== "string") ctx.error(`${ap}.${key}`, "Copy from/to are property names (strings)");
			} else {
				checkNum(ctx, `${ap}.${key}`, v, paramSet);
			}
		}
		// recurse
		if (a.control === "Loop" || a.control === "Rep" || a.control === "Sub" || a.control === "Scope") {
			checkScript(ctx, `${ap}.actions`, a.actions, paramSet);
			// Empty Sub is meaningful: it clears an inherited sub-script
			// (FlowCommands sets subCommands = null for an empty body).
			if (Array.isArray(a.actions) && a.actions.length === 0 && a.control !== "Sub") {
				ctx.error(ap, `"${a.control}" has an empty actions array`);
			}
		}
		if (a.control === "Loop" && Array.isArray(a.actions) && !consumesTime(a.actions)) {
			ctx.error(ap, "infinite Loop whose body never Waits: would spin forever within one frame "
				+ "(the engine's 1000-command safety valve will throttle it, but this is a content bug)");
		}
		if (a.control === "Concurrent") {
			if (!Array.isArray(a.branches) || a.branches.some((b) => !Array.isArray(b))) {
				ctx.error(ap, "Concurrent branches must be an array of action arrays");
			} else {
				a.branches.forEach((b, j) => checkScript(ctx, `${ap}.branches[${j}]`, b, paramSet));
				// commands after a Concurrent with a never-finishing branch are dead
				const blocked = a.branches.some((b) => neverFinishes(b));
				if (blocked && i < actions.length - 1) {
					ctx.warn(ap, "commands after this Concurrent are unreachable: "
						+ "a branch contains an infinite Loop, so the parent never resumes");
				}
			}
		}
		if (a.control === "Loop" && i < actions.length - 1) {
			ctx.warn(ap, "commands after an infinite Loop are unreachable");
		}
		if (a.control === "Dup" && a.props && typeof a.props === "object") {
			for (const [name, spec] of Object.entries(a.props)) {
				const sp = `${ap}.props.${name}`;
				if (!spec || typeof spec !== "object") {
					ctx.error(sp, "Dup property spec must be an object");
					continue;
				}
				const hasRange = spec.from !== undefined || spec.to !== undefined;
				const hasRandom = spec.min !== undefined || spec.max !== undefined;
				const hasStep = spec.step !== undefined;
				if (!hasRange && !hasRandom && !hasStep) {
					ctx.error(sp, "Dup spec needs from/to, min/max, or step");
				}
				for (const [k, v] of Object.entries(spec)) {
					if (!["from", "to", "min", "max", "step"].includes(k)) {
						ctx.warn(sp, `Dup spec does not use field "${k}"`);
					} else {
						checkNum(ctx, `${sp}.${k}`, v, paramSet);
					}
				}
			}
		}
	});
}

// ---------------------------------------------------------------------------
// movement scripts
// ---------------------------------------------------------------------------

function checkMovement(ctx, p, script) {
	if (!script || typeof script !== "object") {
		ctx.error(p, "movementScript must be an object");
		return;
	}
	for (const key of Object.keys(script)) {
		if (!["loop", "actions"].includes(key)) ctx.warn(p, `movementScript does not use field "${key}"`);
	}
	if (!Array.isArray(script.actions)) {
		ctx.error(p, "movementScript.actions must be an array");
		return;
	}
	script.actions.forEach((a, i) => {
		const ap = `${p}.actions[${i}]`;
		switch (a && a.type) {
			case "SetVelocity":
				for (const k of Object.keys(a)) {
					if (!["type", "vx", "vy"].includes(k)) ctx.warn(ap, `SetVelocity does not use field "${k}"`);
				}
				break;
			case "Wait":
				if (typeof a.frames !== "number" || a.frames < 0) {
					ctx.error(ap, "movement Wait needs a non-negative numeric frames");
				}
				break;
			case "Stop":
				break;
			default:
				ctx.error(ap, `unknown movement action type "${a && a.type}"`);
		}
	});
}

// ---------------------------------------------------------------------------
// dialogue
// ---------------------------------------------------------------------------

function checkDialogue(ctx, p, dialogue, assetRoot) {
	for (const key of Object.keys(dialogue)) {
		if (!["intro", "outro"].includes(key)) ctx.warn(p, `dialogue does not use field "${key}"`);
	}
	for (const part of ["intro", "outro"]) {
		const entries = dialogue[part];
		if (entries === undefined) continue;
		if (!Array.isArray(entries)) {
			ctx.error(`${p}.${part}`, "must be an array of dialogue entries");
			continue;
		}
		entries.forEach((e, i) => {
			const ep = `${p}.${part}[${i}]`;
			if (typeof e.speaker !== "string") ctx.error(ep, "dialogue entry needs a speaker string");
			if (typeof e.text !== "string") ctx.error(ep, "dialogue entry needs a text string");
			if (e.side !== undefined && e.side !== "left" && e.side !== "right") {
				ctx.error(ep, `side must be "left" or "right"`);
			}
			for (const key of Object.keys(e)) {
				if (!["speaker", "text", "portrait", "side"].includes(key)) {
					ctx.warn(ep, `dialogue entry does not use field "${key}"`);
				}
			}
			if (typeof e.portrait === "string" && assetRoot) {
				// runtime path "assets/Foo.png" lives at "<repo>/Assets/Foo.png"
				const rel = e.portrait.replace(/^assets\//, "");
				if (!fs.existsSync(path.join(assetRoot, rel))) {
					ctx.warn(ep, `portrait asset not found: ${e.portrait}`);
				}
			}
		});
	}
}

// ---------------------------------------------------------------------------
// top-level files
// ---------------------------------------------------------------------------

const SPAWN_FIELDS = ["spawnTime", "x", "y", "pattern", "patternConfig", "health",
	"velocityX", "velocityY", "movementScript", "sprite", "boss"];

/** Skin names accepted by SpriteLibrary: built-ins plus the sprite manifest. */
let skinCache = null;
function knownSkins(assetRoot) {
	if (skinCache) return skinCache;
	skinCache = new Set(["default", "enemy2"]);
	if (assetRoot) {
		try {
			const doc = JSON.parse(fs.readFileSync(path.join(assetRoot, "sprites.json"), "utf8"));
			for (const name of Object.keys(doc.skins || {})) skinCache.add(name);
		} catch { /* no manifest is fine — built-ins still work */ }
	}
	return skinCache;
}

function checkSpawn(ctx, p, e, assetRoot) {
	for (const key of Object.keys(e)) {
		if (!SPAWN_FIELDS.includes(key)) ctx.warn(p, `spawn does not use field "${key}" (typo?)`);
	}
	if (e.sprite !== undefined) {
		if (typeof e.sprite !== "string") {
			ctx.error(`${p}.sprite`, "sprite must be a skin name or .png path string");
		} else if (e.sprite.endsWith(".png")) {
			// direct drop-in: runtime path "assets/Foo.png" lives at "<repo>/Assets/Foo.png"
			const rel = e.sprite.replace(/^assets\//, "");
			if (assetRoot && !fs.existsSync(path.join(assetRoot, rel))) {
				ctx.warn(`${p}.sprite`, `sprite asset not found: ${e.sprite}`);
			}
		} else if (!knownSkins(assetRoot).has(e.sprite)) {
			ctx.warn(`${p}.sprite`, `unknown sprite skin "${e.sprite}" (not built in, not in sprites.json) — falls back to default art`);
		}
	}
	if (typeof e.spawnTime !== "number") ctx.error(p, "spawn needs numeric spawnTime (seconds)");
	if (typeof e.x !== "number" || typeof e.y !== "number") ctx.error(p, "spawn needs numeric x and y");
	if (typeof e.pattern !== "string") ctx.error(p, "spawn needs a pattern name string");
	if (e.health !== undefined && (!Number.isInteger(e.health) || e.health <= 0)) {
		ctx.error(p, "health must be a positive integer");
	}

	const config = e.patternConfig;
	if (config && typeof config === "object") {
		// inline scripts resolve $params against the patternConfig keys
		const paramSet = new Set(Object.keys(config));
		const inline = config.patternScript;
		if (inline) {
			if (!Array.isArray(inline.actions)) {
				ctx.error(`${p}.patternConfig.patternScript`, "needs an actions array");
			} else {
				checkScript(ctx, `${p}.patternConfig.patternScript.actions`, inline.actions, paramSet);
			}
		}
		for (const [k, v] of Object.entries(config)) {
			if (k === "patternScript") continue;
			if (typeof v === "string") checkExpression(ctx, `${p}.patternConfig.${k}`, v, paramSet);
		}
	}

	if (e.movementScript) checkMovement(ctx, `${p}.movementScript`, e.movementScript);
	if (e.boss) checkBoss(ctx, `${p}.boss`, e.boss);
}

// Boss spawns (see Source/Enemy/BossEnemy.hx): phases with health + pattern.
function checkBoss(ctx, p, boss) {
	for (const key of Object.keys(boss)) {
		if (!["name", "phases"].includes(key)) ctx.warn(p, `boss does not use field "${key}"`);
	}
	if (!Array.isArray(boss.phases) || boss.phases.length === 0) {
		ctx.error(p, "boss needs a non-empty phases array");
		return;
	}
	boss.phases.forEach((ph, i) => {
		const pp = `${p}.phases[${i}]`;
		for (const key of Object.keys(ph)) {
			if (!["name", "health", "pattern", "patternConfig", "script", "movementScript"].includes(key)) {
				ctx.warn(pp, `boss phase does not use field "${key}"`);
			}
		}
		if (!Number.isInteger(ph.health) || ph.health <= 0) {
			ctx.error(pp, "boss phase needs a positive integer health");
		}
		const hasPattern = typeof ph.pattern === "string";
		const hasScript = Array.isArray(ph.script);
		if (!hasPattern && !hasScript) ctx.error(pp, "boss phase needs a pattern name or an inline script");
		if (hasScript) {
			const paramSet = new Set(Object.keys(ph.patternConfig || {}));
			checkScript(ctx, `${pp}.script`, ph.script, paramSet);
		}
		if (ph.movementScript) checkMovement(ctx, `${pp}.movementScript`, ph.movementScript);
	});
}

/** Validate one level document. assetRoot = absolute path of Assets/. */
function validateLevel(doc, file, assetRoot) {
	const ctx = new Ctx(file);
	if (!doc || typeof doc !== "object") {
		ctx.error("$", "level file must be a JSON object");
		return ctx.issues;
	}
	for (const key of Object.keys(doc)) {
		if (!["name", "waves", "dialogue"].includes(key)) ctx.warn("$", `level does not use field "${key}"`);
	}
	if (typeof doc.name !== "string") ctx.error("$", "level needs a name string");
	if (doc.dialogue) checkDialogue(ctx, "dialogue", doc.dialogue, assetRoot);
	if (!Array.isArray(doc.waves) || doc.waves.length === 0) {
		ctx.error("$", "level needs a non-empty waves array");
		return ctx.issues;
	}
	let lastStart = -Infinity;
	doc.waves.forEach((w, i) => {
		const wp = `waves[${i}]`;
		for (const key of Object.keys(w)) {
			if (!["startTime", "enemies"].includes(key)) ctx.warn(wp, `wave does not use field "${key}"`);
		}
		if (typeof w.startTime !== "number") ctx.error(wp, "wave needs numeric startTime (seconds)");
		else {
			if (w.startTime < lastStart) {
				ctx.warn(wp, "waves are not sorted by startTime: LevelManager starts them in "
					+ "array order, so this wave will be delayed until its predecessors start");
			}
			lastStart = Math.max(lastStart, w.startTime);
		}
		if (!Array.isArray(w.enemies) || w.enemies.length === 0) {
			ctx.error(wp, "wave needs a non-empty enemies array");
			return;
		}
		w.enemies.forEach((e, j) => checkSpawn(ctx, `${wp}.enemies[${j}]`, e, assetRoot));
	});
	return ctx.issues;
}

/** Validate one pattern template document. */
function validatePattern(doc, file) {
	const ctx = new Ctx(file);
	if (!doc || typeof doc !== "object") {
		ctx.error("$", "pattern file must be a JSON object");
		return ctx.issues;
	}
	for (const key of Object.keys(doc)) {
		if (!["name", "description", "parameters", "script", "note"].includes(key)) {
			ctx.warn("$", `pattern does not use field "${key}"`);
		}
	}
	if (typeof doc.name !== "string") ctx.error("$", "pattern needs a name string");
	const params = doc.parameters && typeof doc.parameters === "object" ? doc.parameters : {};
	const paramSet = new Set(Object.keys(params));
	// startDelay is injected by the engine's config handling
	paramSet.add("startDelay");
	checkScript(ctx, "script", doc.script, paramSet);
	return ctx.issues;
}

module.exports = { validateLevel, validatePattern };
