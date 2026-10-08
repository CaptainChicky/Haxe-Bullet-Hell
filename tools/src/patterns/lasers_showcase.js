"use strict";
const { S, pattern } = require("../../bh");

const CX = 900;
const beam = {
	length: 720,
	width: 22,
	telegraphFrames: 45,
	activeFrames: 90,
	shutdownFrames: 18,
	extendFrames: 12,
};

module.exports = pattern(
	"lasers_showcase",
	"Static cross + sweeping boss laser (Phase 2 acceptance)",
	{
		crossDelay: { type: "int", default: 150, description: "Frames between cross volleys" },
		sweepTurn: { type: "float", default: 0.35, description: "Boss laser sweep deg/frame" },
	},
	[
		S.bind("position"),
		S.loop(
			S.rep(4,
				S.laser({ ...beam, angle: 0 }),
				S.add("direction", 90),
			),
			S.wait("$crossDelay"),
			S.set("direction", 0),
			S.laser({ ...beam, length: 800, width: 28, sweep: "$sweepTurn", activeFrames: 120 }),
			S.wait(180),
		),
	],
);
