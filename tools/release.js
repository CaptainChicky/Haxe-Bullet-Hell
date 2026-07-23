#!/usr/bin/env node
"use strict";
/**
 * Release build wrapper: seal -> build -> clean.
 *
 *   node tools/release.js windows         -> openfl build windows -release
 *   node tools/release.js html5 -clean    -> openfl build html5 -release -clean
 *
 * The sealed .dat files are build output (gitignored) and are what a release
 * build actually packages. Rather than leaving them littered next to the JSON
 * in Assets/, this seals them, runs the build while they exist, then deletes
 * them again — so the working tree only ever holds the editable JSON at rest.
 *
 * Why a wrapper and not a lime hook: lime resolves the asset list while parsing
 * project.xml, so the .dat must exist BEFORE the build starts. <prebuild> runs
 * too late to add them, and a <postbuild> delete would break the next build.
 * Sealing here, before openfl is invoked, is the only spot that works.
 *
 * Debug builds package the JSON directly and never need this — build those with
 * `openfl build <target> -debug` as usual.
 */

const path = require("path");
const { spawnSync } = require("child_process");

const TOOLS = __dirname;
const SEAL = path.join(TOOLS, "seal.js");

const passthrough = process.argv.slice(2);
if (passthrough.length === 0) {
	console.error("usage: node tools/release.js <target> [extra openfl flags]");
	console.error("       e.g. node tools/release.js windows");
	console.error("            node tools/release.js html5 -clean");
	process.exit(2);
}

// Ensure -release is present exactly once.
if (!passthrough.includes("-release")) passthrough.splice(1, 0, "-release");

// shell:true only for `openfl` (a .cmd on PATH on Windows). Node subprocesses
// use an absolute exe path, so a shell would only mangle it — e.g. splitting
// "C:\Program Files\nodejs\node.exe" at the space.
function run(label, cmd, args, shell) {
	const r = spawnSync(cmd, args, { stdio: "inherit", shell: !!shell });
	if (r.error) {
		console.error(`\n${label} failed to launch: ${r.error.message}`);
		return 1;
	}
	return r.status == null ? 1 : r.status;
}

let buildStatus = 1;
try {
	// 1. Seal: create the .dat the build will package.
	const sealStatus = run("seal", process.execPath, [SEAL]);
	if (sealStatus !== 0) {
		console.error("\nSealing failed; not building.");
		process.exit(sealStatus);
	}

	// 2. Build with the sealed content in place.
	console.log(`\n> openfl build ${passthrough.join(" ")}\n`);
	buildStatus = run("build", "openfl", ["build", ...passthrough], true);
} finally {
	// 3. Clean: remove the .dat so the working tree stays JSON-only, even if
	//    the build threw or failed partway through.
	console.log("");
	run("clean", process.execPath, [SEAL, "--clean"]);
}

process.exit(buildStatus);
