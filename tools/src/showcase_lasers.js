"use strict";
const { M, spawn, wave, level } = require("../bh");

const CX = 900;

module.exports = level("showcase_lasers", "Showcase: lasers", {
	waves: [
		wave(0, spawn({
			at: [CX, 280],
			pattern: "lasers_showcase",
			health: 999,
			move: M.script({}, M.stop(), M.wait(3600)),
		})),
	],
});
