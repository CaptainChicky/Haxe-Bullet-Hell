# BulletHell authoring tools

A tiny, zero-dependency Node toolchain for writing level and pattern content.
Sources are plain JavaScript modules; the compiler validates them and emits the
exact JSON formats the engine already parses. **The engine is untouched** —
hand-written JSON in `Assets/levels` and `Assets/patterns` keeps working, and
the validator can check that content too.

```
tools/
  compile.js       CLI — compile + validate + write
  bh/index.js      the DSL (S = shot scripts, M = movement, level/wave/spawn/pattern)
  bh/validate.js   static validator (shared by compiled and hand-written JSON)
  src/             your level/pattern sources (*.js) — compiled recursively
```

## Usage

```sh
node tools/compile.js            # compile tools/src/** -> Assets/levels|patterns
node tools/compile.js --check    # also validate all existing JSON in Assets/
node tools/compile.js --dry      # compile + validate, write nothing
```

Exit code is 1 on any validation error and nothing is written; warnings don't
fail the build. Output is deterministic: stable key order, 2-space indent.

## Writing a level

A source module builds data with the helpers from `tools/bh` and exports the
result of `level(...)` or `pattern(...)` (or an array of them):

```js
const { S, M, spawn, wave, say, level } = require("../bh");

// Reuse is plain JavaScript: functions, loops, constants.
function sideGunner(x, time) {
    return spawn({
        at: [x, -40], time,
        pattern: "spiral",
        config: { arms: 3, rotationSpeed: 4 },
        health: 4,
        move: M.script({},
            M.enterFrom("top", 3, 60),
            M.easeTo({ from: [0, 3], to: [0, 0], frames: 30 }),
            M.hold(240),
        ),
    });
}

module.exports = level("level4", "Stage 4 - Example", {
    dialogue: {
        intro: [
            say("Aviator", "Something's jamming the radar...", "assets/Player.png", "left"),
            say("???", "That would be me.", "assets/Enemy.png", "right"),
        ],
    },
    waves: [
        wave(0, [sideGunner(150, 0), sideGunner(650, 1.5)]),
        wave(12, [/* ... */]),
    ],
});
```

`spawn()` fields: `at: [x, y]` (required), `time` (seconds within the wave),
`pattern` + `config`, or `script: [S...]` for an inline shot script, `health`,
`velocity: [vx, vy]`, `move: M.script(...)`, `sprite`, `boss`.

## S — shot scripts

Mirrors `Source/Shot/CommandRegistry` one to one; every helper returns the JSON
object the engine parses, so anything you can write by hand you can write here.

| Helper | JSON control |
|---|---|
| `S.wait(f)` / `S.loop(...)` / `S.rep(n, ...)` | Wait / Loop / Rep |
| `S.concurrent(a, b)` / `S.concurrentShared(a, b)` | Concurrent (share: true) |
| `S.sub(...)` / `S.scope(...)` / `S.vanish()` | Sub / Scope / Vanish |
| `S.fire(angle, speed)` / `S.radial(n, s)` / `S.nway(n, a, s)` | Fire / Radial / NWay |
| `S.line(n, prop, from, to)` / `S.dup(n, props)` | Line / Dup |
| `S.set(p, v)` / `S.add(p, d)` / `S.random(p, min, max)` | Set / Add / Random |
| `S.copy(from, to, scale?)` / `S.tween(p, to, f, rel?)` | Copy / Tween |
| `S.offset(dist, angle)` / `S.rotate(deg, withDir?)` | SetOffset / Rotate |
| `S.scale(f)` / `S.scaleXY(x, y)` | Scale |
| `S.bind(mode)` / `S.aim()` | Bind / AimAtPlayer |

Values can be numbers or expression strings (`"$speed * 2"`, `"sin(frame)"`),
exactly as in hand-written JSON. `S.sub()` with no actions clears an inherited
sub-script (same as the engine).

## M — movement scripts

This is where hand-written JSON bloated most, so movement gets the higher-level
helpers. Everything compiles down to the engine's three movement ops
(SetVelocity / Wait / Stop):

- `M.vel(vx, vy)`, `M.wait(f)`, `M.stop()` — the primitives
- `M.hold(f)` — stop and sit still
- `M.drift(vx, vy, f)` — constant velocity for f frames
- `M.enterFrom(side, speed, f)` — fly in from `"left" | "right" | "top" | "bottom"`
- `M.easeTo({from, to, frames, steps?, ease?})` — smooth velocity ramp,
  ease: `"linear" | "quadOut" | "sineInOut"` (default)
- `M.weave({vx, vy, period, cycles, step?})` — sinusoidal strafing
- `M.script({loop: true?}, ...parts)` — assemble the final movementScript

## Bosses

A spawn with a `boss` block becomes a multi-phase boss (see
`tools/src/level4.js` for a full example):

```js
spawn({
    at: [900, -80], time: 0, sprite: "enemy2",
    move: M.script({}, M.drift(0, 3.5, 86), M.stop()),   // entrance
    boss: boss("Aurelia, Queen of the Aviary",
        phase({ name: "Opening - Gilded Volley", health: 40,
                config: { volleySpeed: 6.5 }, script: [S.loop(/* ... */)] }),
        phase({ name: "Last Word - ...", health: 70,
                pattern: "spiral", config: { /* ... */ },
                move: M.script({}, M.stop()) }),
    ),
})
```

Phases are fought in order. Clearing a phase wipes the bullet field, swaps
the pattern (and movement, if the phase has `move`), and grants the boss brief
invincibility; clearing the last phase kills the boss. `name` is the spell
card title shown on the boss health bar.

## Patterns

```js
const { S, pattern } = require("../bh");
module.exports = pattern("burst", "Aimed 3-way burst",
    { count: { type: "int", default: 3, description: "Bullets per burst" } },
    [
        S.loop(
            S.aim(),
            S.nway("$count", 15, 4),
            S.wait(45),
        ),
    ]);
```

## Validation

`bh/validate.js` statically checks both compiled and hand-written content:

- unknown controls, missing required fields, misspelled fields (warns)
- expression syntax: balanced parens, unknown functions, `$params` that aren't
  declared by the pattern (or present in the spawn's `patternConfig`)
- **infinite loops that never Wait** — would spin inside one frame (error)
- unreachable commands after a `Concurrent` with a never-finishing branch
- movement scripts, dialogue entries (portrait file existence), wave ordering,
  spawn/boss field shapes

Run `node tools/compile.js --check` in CI or before committing content.
