#!/usr/bin/env node
"use strict";
/**
 * Seals Assets/levels/*.json and Assets/patterns/*.json into the .dat files
 * that actually ship. The .json stays in the repo as the editable source of
 * truth; project.xml excludes it from the package, so a release build contains
 * only the sealed form.
 *
 *   node tools/seal.js            (re)seal every level/pattern, prune orphans
 *   node tools/seal.js --verify   check every .dat round-trips to its .json
 *   node tools/seal.js --clean    delete all .dat files
 *
 * compile.js runs this automatically after writing JSON. Run it by hand after
 * hand-editing a JSON file, otherwise the build ships the previous content.
 * Exit code 1 if anything is missing or stale under --verify.
 */

const fs = require("fs");
const path = require("path");
const { seal, unseal } = require("./bh/crypt");

const ROOT = path.resolve(__dirname, "..");
const ASSETS = path.join(ROOT, "Assets");
const SEALED_DIRS = ["levels", "patterns"];

const args = process.argv.slice(2);
const VERIFY = args.includes("--verify");
const CLEAN = args.includes("--clean");

const rel = (p) => path.relative(ROOT, p).replace(/\\/g, "/");

function jsonFiles(dir) {
	if (!fs.existsSync(dir)) return [];
	return fs.readdirSync(dir).filter((n) => n.endsWith(".json")).sort();
}

let failures = 0;
let written = 0;
let removed = 0;

for (const kind of SEALED_DIRS) {
	const dir = path.join(ASSETS, kind);
	if (!fs.existsSync(dir)) continue;

	const expected = new Set();

	for (const name of jsonFiles(dir)) {
		const src = path.join(dir, name);
		const out = path.join(dir, name.replace(/\.json$/, ".dat"));
		expected.add(path.basename(out));
		if (CLEAN) continue;

		const plaintext = fs.readFileSync(src);

		// Parse before sealing: a sealed file with a typo in it is invisible.
		try {
			JSON.parse(plaintext.toString("utf8"));
		} catch (e) {
			console.log(`  ERROR  ${rel(src)} — invalid JSON: ${e.message}`);
			failures++;
			continue;
		}

		const sealed = seal(plaintext);

		if (VERIFY) {
			if (!fs.existsSync(out)) {
				console.log(`  ERROR  ${rel(out)} — missing (run: node tools/seal.js)`);
				failures++;
			} else if (unseal(fs.readFileSync(out)) !== plaintext.toString("utf8")) {
				console.log(`  ERROR  ${rel(out)} — stale (run: node tools/seal.js)`);
				failures++;
			}
			continue;
		}

		// Sealing is deterministic, so skip untouched files and keep mtimes
		// stable for incremental builds.
		if (fs.existsSync(out) && fs.readFileSync(out).equals(sealed)) continue;

		fs.writeFileSync(out, sealed);
		console.log(`  sealed ${rel(out)}`);
		written++;
	}

	// Drop .dat files whose .json is gone, so deleted content can't linger in a
	// build in a form nobody can read.
	for (const name of fs.readdirSync(dir)) {
		if (!name.endsWith(".dat")) continue;
		if (!CLEAN && expected.has(name)) continue;
		if (VERIFY) {
			console.log(`  ERROR  ${rel(path.join(dir, name))} — orphaned (no matching .json)`);
			failures++;
			continue;
		}
		fs.unlinkSync(path.join(dir, name));
		console.log(`  removed ${rel(path.join(dir, name))}`);
		removed++;
	}
}

if (VERIFY) {
	console.log(failures === 0 ? "\nsealed assets are up to date" : `\n${failures} problem(s)`);
} else if (CLEAN) {
	console.log(`\n${removed} sealed file(s) removed`);
} else {
	console.log(`\n${written} sealed, ${removed} removed, ${failures} error(s)`);
}

process.exit(failures > 0 ? 1 : 0);
