"use strict";
/**
 * starry — a hexagram: two equilateral triangles sharing a center, one turned
 * 60° from the other, with every edge extended outward far past the playfield.
 *
 * Six extended edges is exactly six lines whose outward normals sit at
 * 30° + 60k and whose distance from the center is the triangles' inradius
 * (= circumradius * cos 60°). Each line is a row of `lineBullets` spaced
 * `spacing` apart, centered on its foot point — make the row long enough and
 * the edges read as running off to infinity.
 *
 * Same rigid construction as [amitaba]: bullets are offset-bound with a
 * Cartesian placement and each turns itself `spinStep` per frame with Rotate,
 * so the star holds its shape, rides the enemy, and rotates as one body.
 * After `holdFrames` every bullet fires a free copy of itself outward along
 * its line's normal and vanishes, and the next star is inscribed.
 *
 * Compile: node tools/compile.js  ->  Assets/patterns/starry.json
 */
const { S, pattern } = require("../../bh");

// One star bullet: hold the line while the star turns, then break outward
// perpendicular to its own edge (`outAngle`, plus the rotation accumulated).
const figureBullet = [
	S.rep("$holdFrames",
		S.rotate("$spinStep"),
		S.wait(1),
	),
	S.scope(
		// Zero the offset or children spawn at (bullet + offset), not at the
		// bullet — the offset-bound child rule from pods.json.
		S.set("x", 0), S.set("y", 0), S.offset(0, 0),
		S.set("speed", "$releaseSpeed"),
		S.set("direction", "outAngle + $spinStep * $holdFrames"),
		S.fire(0, 0),
	),
	S.vanish(),
];

module.exports = pattern("starry",
	"Two overlapping equilateral triangles (a hexagram) whose six edges extend "
	+ "outward past the playfield — a rigid, slowly turning wall of bullets that "
	+ "breaks outward along the edge normals when the hold ends",
	{
		radius:       { type: "float", default: 230, description: "Circumradius of each triangle (vertex distance)" },
		lineBullets:  { type: "int",   default: 21,  description: "Bullets per extended edge (odd = one on the foot point)" },
		spacing:      { type: "float", default: 60,  description: "Distance between adjacent bullets along an edge" },
		baseAngle:    { type: "float", default: 0,   description: "Starting rotation of the whole star" },
		spinStep:     { type: "float", default: 0.25, description: "Star rotation, degrees per frame (0 = frozen)" },
		holdFrames:   { type: "int",   default: 300, description: "Frames the star holds before breaking apart" },
		releaseSpeed: { type: "float", default: 2.2, description: "Speed each bullet leaves at when the star breaks" },
		drawDelay:    { type: "int",   default: 1,   description: "Frames between edges while the star inscribes itself" },
		cycleDelay:   { type: "int",   default: 110, description: "Frames between one star and the next" },
	},
	[
		S.set("speed", 0),
		S.bind("offset"),
		S.offset(0, 0),
		S.sub(...figureBullet),
		S.loop(
			S.set("edge", 0),
			S.rep(6,
				// Outward normal of this edge, and the along-edge direction.
				S.set("n", "edge * 60 + 30 + $baseAngle"),
				S.set("t", "n + 90"),
				S.set("outAngle", "n"),
				// Walk from one end of the edge to the other. The foot point
				// sits at the inradius along the normal.
				S.set("s", "-($lineBullets - 1) * $spacing / 2"),
				S.rep("$lineBullets",
					S.set("x", "$radius * cos(60) * cos(n) + s * cos(t)"),
					S.set("y", "$radius * cos(60) * sin(n) + s * sin(t)"),
					S.fire(0, 0),
					S.add("s", "$spacing"),
				),
				S.add("edge", 1),
				S.wait("$drawDelay"),
			),
			S.wait("$holdFrames + $cycleDelay"),
		),
	]);
