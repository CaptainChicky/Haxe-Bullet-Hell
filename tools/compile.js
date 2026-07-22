#!/usr/bin/env node
"use strict";
/**
 * BulletHell level/pattern compiler.
 *
 *   node tools/compile.js            compile every source in tools/src/**,
 *                                    validate, and write JSON into Assets/
 *   node tools/compile.js --check    also validate all existing JSON content
 *                                    in Assets/levels and Assets/patterns
 *   node tools/compile.js --dry      compile + validate but write nothing
 *
 * Each source module (plain Node .js) exports one document or an array:
 *
 *   const { level, pattern } = require("../../bh");
 *   module.exports = level("level4", "Stage 4", { waves: [...] });
 *
 * Output is deterministic (stable key order from builders, 2-space indent).
 * Exit code 1 on any validation error; warnings don't fail the build.
 */

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { validateLevel, validatePattern } = require("./bh/validate");

const ROOT = path.resolve(__dirname, "..");
const SRC_DIR = path.join(__dirname, "src");
const ASSETS = path.join(ROOT, "Assets");

const args = process.argv.slice(2);
const CHECK_EXISTING = args.includes("--check");
const DRY = args.includes("--dry");

let errors = 0;
let warnings = 0;

function report(issues) {
	for (const it of issues) {
		const tag = it.level === "error" ? "ERROR" : "warn ";
		console.log(`  ${tag}  ${it.file} :: ${it.path} — ${it.message}`);
		if (it.level === "error") errors++;
		else warnings++;
	}
}

function validateDoc(doc, label) {
	if (doc.kind === "level") return report(validateLevel(doc.data, label, ASSETS));
	if (doc.kind === "pattern") return report(validatePattern(doc.data, label));
	console.log(`  ERROR  ${label} — export is neither level(...) nor pattern(...)`);
	errors++;
}

function outputPath(doc) {
	return doc.kind === "level"
		? path.join(ASSETS, "levels", doc.file + ".json")
		: path.join(ASSETS, "patterns", doc.file + ".json");
}

function listSources(dir) {
	if (!fs.existsSync(dir)) return [];
	const out = [];
	for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) out.push(...listSources(full));
		else if (entry.name.endsWith(".js")) out.push(full);
	}
	return out;
}

// ---------------------------------------------------------------- compile
const sources = listSources(SRC_DIR);
const outputs = [];

for (const src of sources) {
	const rel = path.relative(ROOT, src);
	let exported;
	try {
		exported = require(src);
	} catch (e) {
		console.log(`  ERROR  ${rel} — ${e.message}`);
		errors++;
		continue;
	}
	const docs = Array.isArray(exported) ? exported : [exported];
	for (const doc of docs) {
		if (!doc || typeof doc !== "object" || !doc.kind || !doc.file || !doc.data) {
			console.log(`  ERROR  ${rel} — export must come from level(...) or pattern(...)`);
			errors++;
			continue;
		}
		validateDoc(doc, rel);
		outputs.push({ doc, rel });
	}
}

// duplicate output detection
const seen = new Map();
for (const { doc, rel } of outputs) {
	const out = outputPath(doc);
	if (seen.has(out)) {
		console.log(`  ERROR  ${rel} — output ${path.relative(ROOT, out)} already produced by ${seen.get(out)}`);
		errors++;
	}
	seen.set(out, rel);
}

if (errors === 0 && !DRY) {
	for (const { doc, rel } of outputs) {
		const out = outputPath(doc);
		fs.mkdirSync(path.dirname(out), { recursive: true });
		fs.writeFileSync(out, JSON.stringify(doc.data, null, 2) + "\n");
		console.log(`  wrote  ${path.relative(ROOT, out)}  (from ${rel})`);
	}
} else if (outputs.length > 0 && errors > 0) {
	console.log("  (nothing written: fix errors first)");
}

// Re-seal after writing: the .dat files are what release builds package, so
// leaving them stale would ship the previous content.
if (errors === 0 && !DRY) {
	console.log("");
	try {
		execFileSync(process.execPath, [path.join(__dirname, "seal.js")], { stdio: "inherit" });
	} catch (e) {
		console.log("  ERROR  sealing failed");
		errors++;
	}
}

// ---------------------------------------------------------------- --check
if (CHECK_EXISTING) {
	console.log("\nValidating existing content in Assets/ ...");
	const compiledOutputs = new Set([...seen.keys()]);
	for (const kind of ["levels", "patterns"]) {
		const dir = path.join(ASSETS, kind);
		if (!fs.existsSync(dir)) continue;
		for (const name of fs.readdirSync(dir).sort()) {
			if (!name.endsWith(".json")) continue;
			const full = path.join(dir, name);
			if (compiledOutputs.has(full)) continue; // just validated above
			const rel = path.relative(ROOT, full);
			let doc;
			try {
				doc = JSON.parse(fs.readFileSync(full, "utf8"));
			} catch (e) {
				console.log(`  ERROR  ${rel} — invalid JSON: ${e.message}`);
				errors++;
				continue;
			}
			report(kind === "levels" ? validateLevel(doc, rel, ASSETS) : validatePattern(doc, rel));
		}
	}

	// A stale .dat is invisible in the JSON but is what actually ships.
	console.log("\nVerifying sealed assets ...");
	try {
		execFileSync(process.execPath, [path.join(__dirname, "seal.js"), "--verify"], { stdio: "inherit" });
	} catch (e) {
		errors++;
	}
}

console.log(`\n${sources.length} source file(s), ${outputs.length} document(s), `
	+ `${errors} error(s), ${warnings} warning(s)`);
process.exit(errors > 0 ? 1 : 0);
