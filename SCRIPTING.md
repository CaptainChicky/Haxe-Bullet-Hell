# Shot Scripting Engine

The shooting system is a prototype-based scripting engine (in the spirit of Touhou / BulletML). It lives in `Source/Shot` and has **no OpenFL dependencies**, so it can be unit-tested headlessly (see `Tests/TestShot.hx`).

## Core idea

Every script owns a mutable **`ShotPrototype`** — a description of "the next bullet to be fired": direction, speed, spawn offset, acceleration, angular velocity (curving), speed clamps, lifetime, custom variables, and an optional sub-script. Commands mutate the prototype; `Fire` **clones** it into a live bullet, so bullets already in flight are never affected by later script commands.

```
JSON pattern ──ScriptCompiler/CommandRegistry──▶ Array<IShotCommand>
                                                       │
ScriptRunner ── mutates ──▶ ShotPrototype ── clone ──▶ IShotEmitter.spawn ──▶ BulletEnemy
```

## Architecture

| File | Responsibility |
|---|---|
| `Shot/ShotPrototype.hx` | The mutable bullet template + generic `getProp`/`setProp` |
| `Shot/ShotCommand.hx` | `IShotCommand` interface — one class per behavior, no central enum |
| `Shot/ShotContext.hx` | An execution thread: prototype + frame stack + wait/blocking state |
| `Shot/ScriptRunner.hx` | The interpreter: frame budget, loops, concurrency, firing |
| `Shot/FlowCommands.hx` | `Wait`, `Loop`, `Rep`, `Concurrent`, `Sub`, `Scope`, `Vanish` |
| `Shot/PropertyCommands.hx` | Generic `Set`/`Add`/`Random`/`Copy`/`Offset`/`Tween`/`Rotate`/`Scale`/`AimAtTarget` |
| `Shot/FireCommands.hx` | `Fire`, `Radial`, `NWay`, `Line`, `Dup` |
| `Shot/CommandRegistry.hx` | JSON `"control"` name → command parser (the extension point) |
| `Shot/Expression.hx` | Expression AST: `$param`s, arithmetic, `sin`/`cos`, inline randoms, `NumValue` |
| `Shot/ShotEmitter.hx` | `IShotEmitter` — anything that can fire (enemy **or bullet**) |
| `Bullet/BulletEmitters.hx` | `EnemyBulletEmitter`, `BulletSubEmitter` (nested patterns) |

`ScriptRunner` executes any number of `ShotContext`s. `Concurrent` spawns child contexts (each with a **cloned** prototype) and suspends the parent until they finish — and because branches are ordinary contexts, `Concurrent` now nests arbitrarily.

## Adding a new command

No enum, no interpreter switch, no loader changes:

```haxe
class HomingCommand implements IShotCommand {
    public function new(strength:Float) { ... }
    public function run(ctx:ShotContext, runner:ScriptRunner):Void { ... }
}

// anywhere during startup:
CommandRegistry.register("Homing", (d, c) -> new HomingCommand(c.num(d.strength)));
```

## Adding a new bullet property

Add a field to `ShotPrototype` and a case in its `getProp`/`setProp` — the generic commands pick it up immediately. Property names **not** listed there automatically become custom script variables (stored in `prototype.vars`).

## JSON reference

All legacy controls still work (`Fire`, `Wait`, `Loop`, `Rep`, `Concurrent`, `SetAngle`, `AddAngle`, `SetSpeed`, `AddSpeed`, `SetOffset`, `AddOffset`, `CopyAngleToOffset`, `CopyOffsetToAngle`, `RandomSpeed`, `RandomAngle`, `AimAtPlayer`, `Radial`, `NWay`). `Fire`/`Radial`/`NWay` keep the convention that a literal `0` for angle/speed means "use the prototype's current value".

New generic controls:

```jsonc
{"control": "Set",    "prop": "accel", "value": 0.1}        // prototype.accel = 0.1
{"control": "Add",    "prop": "turn",  "delta": -0.5}       // curving bullets
{"control": "Random", "prop": "speed", "min": 2, "max": 6}
{"control": "Copy",   "from": "direction", "to": "offsetAngle"}
{"control": "Tween",  "prop": "speed", "to": 6, "frames": 30}   // linear interp over N frames
{"control": "Tween",  "prop": "direction", "to": 210, "frames": 60, "relative": true}  // add 210° to current over 60 frames
{"control": "Vanish"}                                            // bullet removes itself mid-flight
```

`Tween` is stateful: it interpolates the property one step per frame and lands exactly on `to` after `frames` frames, then the script continues. With `"relative": true`, the target is interpreted as *current value + to* rather than an absolute value — essential when many bullets start at different directions/speeds but all need the same delta (e.g. every petal curves +210° from its own starting direction). To run two tweens simultaneously on the *same* upcoming bullet, use `Concurrent` with `"share": true` (branches normally clone the prototype; `share` makes them mutate the parent's):

```jsonc
{"control": "Concurrent", "share": true, "branches": [
    [{"control": "Tween", "prop": "speed", "to": 10, "frames": 30}],
    [{"control": "Tween", "prop": "turn",  "to": 5,  "frames": 30}]
]}
```

`Vanish` despawns the script's owner: inside a `Sub` script it removes the bullet itself (and halts the script); on an enemy-owned script it is a no-op.

### Scope — one-shot child configuration vs steering yourself

```jsonc
{"control": "Scope", "actions": [
    {"control": "Set", "prop": "turn", "value": 0},
    {"control": "Radial", "count": 8, "speed": 2}
]}
```

`Scope` runs its body against a **clone** of the prototype, discarded when the block ends. Mutations inside (including custom vars) affect only bullets fired inside the block; afterwards the prototype is exactly what it was before. Unlike a `Concurrent` branch, the body executes inline within the same frame budget (no one-frame scheduling delay), and `Scope` nests freely.

Why it exists: inside a bullet's own `Sub` script, the prototype does double duty. Mutating `direction`/`speed`/`turn` **steers the bullet itself** (that's how `shifter.json` kinks mid-flight, and it's usually what you want) — but a burst script like `flower.json`'s seed-to-petal explosion mutates those same properties only to *configure the children it's about to fire*. Without `Scope`, the seed permanently adopts the petals' direction/turn/accel at the moment of the burst and stops curving. **Rule of thumb: in a bullet's own script, wrap burst-configuration in `Scope`; leave steering mutations unscoped.** The bullet syncs its flight state from the script's *root* prototype, which a `Scope` never touches.

Caveat: the clone is a snapshot at `Scope` entry — in a multi-frame `Scope` (body containing `Wait`s), the owning bullet's live direction/speed updates during the block aren't visible inside it.

Available properties: `direction` (alias `angle`), `speed`, `offsetDistance`, `offsetAngle`, `x`, `y`, `accel` (alias `acceleration`), `angularVelocity` (alias `turn`), `minSpeed`, `maxSpeed`, `lifetime`, `bindMode` — plus any custom variable name.

### Cartesian placement + transforms

`x`/`y` are a **Cartesian spawn offset** from the emitter origin, applied *in addition* to the polar offset (`offsetDistance`/`offsetAngle`). Two transform commands reshape placement:

```jsonc
{"control": "Rotate", "degrees": 15}                        // rotates (x,y) about the origin AND advances offsetAngle
{"control": "Rotate", "degrees": 15, "withDirection": true} // ...and rotates travel direction (spin a whole pattern)
{"control": "Scale", "factor": 2}                           // scales x, y, and offsetDistance uniformly
{"control": "Scale", "x": 2, "y": 0.5}                      // per-axis Cartesian factors (offsetDistance is a radius, stays uniform)
```

Rotation follows the engine's angle convention (0° = +x, 90° = +y/down), so rotating a Cartesian point and adding the same degrees to a polar bearing agree.

### Line and Dup (multi-fire)

```jsonc
{"control": "Line", "count": 5, "prop": "speed", "from": 1, "to": 5}
```

`Line` fires `count` bullets stepping **one property** linearly from `from` to `to` inclusive (e.g. increasing speed strings the bullets out along the travel direction). The prototype's value is restored afterwards. `from`/`to` re-evaluate per execution, so volatile endpoints give a fresh line per volley.

```jsonc
{"control": "Dup", "count": 5, "props": {
    "direction": {"from": -30, "to": 30},   // interpolated across copies (inclusive)
    "speed":     {"min": 2, "max": 6},      // uniform random, rolled per copy
    "lifetime":  {"step": 10}               // prototype value + i*10
}}
```

`Dup` spawns `count` independent clones with declarative per-copy spreads on any number of properties. Because each copy is a full clone fed through the normal spawn path, spreading a *placement* property (`offsetAngle`, `x`, `y`) moves the spawn position per copy — `{"offsetAngle": {"from": 0, "to": 360}}` is a positional ring. The script's own prototype is never touched.

### Bind (bullets that follow their parent)

```jsonc
{"control": "Bind", "mode": "position"}   // or "full", "offset", or "none" to clear
{"control": "Fire", "angle": 0, "speed": 0}
```

Every bullet fired while `bindMode` is set stays attached to the emitter that fired it (enemy or bullet):

- **`position`** — the bullet moves in its parent's frame of reference: the parent's translation carries it along each frame while the bullet's own direction/speed/accel/turn still integrate on top. A pattern fired by a moving boss travels with the boss.
- **`full`** — position binding *plus* flight state (direction, speed, accel, turn, speed clamps) re-derived every frame from the parent script's **live root prototype**. Mutate the parent's prototype and every fully-bound bullet re-steers in unison. Because the source is the *root* prototype, parent-side `Scope` blocks (burst configuration) are invisible to bound children — the same ownership rule as bullet steering. A fully-bound bullet's own sub-script can still fire children or `Vanish`, but cannot steer (**bind wins**).
- **`offset`** — the bullet's position is directly computed as `parent_origin + polar_offset + cartesian_offset` every frame, reading `offsetDistance`/`offsetAngle`/`x`/`y` from the sub-script's live prototype. The bullet's own velocity is **not** integrated; movement comes entirely from the sub-script mutating the offset (e.g. tweening `offsetDistance` to launch outward, then adding to `offsetAngle` to orbit). Children fired from an offset-bound bullet should `Scope` and reset `offsetDistance` to 0 so they spawn at the pod's position, not at pod + orbitRadius. See `Assets/patterns/pods.json` for the canonical example.

Rules and behaviors:

- **Parent death → orphan-release** (`position`/`full`): the bullet keeps its current position and flight state and continues as a normal independent bullet. Tradeoff: cascade-vanish (children die with the parent) is the tidier mental model and prevents stranded formations, but it lets the player erase whole patterns by sniping one parent bullet; orphan-release was chosen as the default. Cascade could be added later as a third mode without breaking anything.
- **Parent death → ghost parent** (`offset`): orphan-release would strand an offset-bound bullet forever — its state is speed 0 and all of its motion comes from the sub-script mutating the offset, so "released with current state" means frozen mid-screen with an infinite `Loop` still firing. Instead, when an enemy dies with offset-bound bullets still attached, a lightweight **ghost origin** survives as a pure coordinate source: the bullets stay bound, keep deriving `ghost + offset` every frame, and their patterns run to completion. The enemy is otherwise fully dead the instant it dies — not drawn, not collidable, excluded from targeting and wave-clear/scoring; only the origin outlives it.
  - The ghost **keeps moving**: it inherits the enemy's velocity at death and the enemy's `movementScript` is retargeted to it (with `loop` forced off, so a looping path plays once and leaves). Orbit chains and pods therefore drift off-screen with the ghost and despawn on their own via the normal cull, which uses each bullet's *derived* world position.
  - Safety cap: each ghost lives at most `maxOrphanFrames` (default 60 = 1s @ 60fps; override by setting a `maxOrphanFrames` script variable on the pattern's root prototype, e.g. for a long scripted drift-out). Once the cap hits, bullets still bound are force-resolved by Vanish — orphaned formations disappear ~1s after their owner dies, and no bullet is ever immortal.
  - Lifecycle: bound bullets refcount their parent anchor; the ghost is dropped the moment the last one despawns (or at the cap).
- `bindMode` is part of the prototype and travels through `clone()` (so `Concurrent` branches inherit it), **except** into a bullet's sub-script starting prototype, which is reset to `none` — a bound bullet's children don't implicitly bind to it; a chain opts in with another `Bind` inside the sub-script.
- The runtime link to the parent (`bindSource`) is attached at fire time and is never copied by `clone()`.
- One-frame lag caveat: children re-derive from the parent's position/prototype as of when *they* update; depending on display-list update order a bound bullet can trail its parent's movement by one frame. Cosmetically invisible at 60fps, but don't build frame-exact logic on it.

### Sub-scripts (bullets that fire bullets)

```jsonc
{"control": "Sub", "actions": [
    {"control": "Wait", "frames": 45},
    {"control": "Radial", "count": 8, "speed": 2}
]}
```

Every bullet fired *after* a `Sub` carries that script and executes it itself after spawning (the bullet becomes its own emitter). The bullet syncs its flight state (`direction`, `speed`, `accel`, `turn`, speed clamps) from the sub-script's live prototype every frame via `ScriptRunner.getPrototype()`, so a sub-script that mutates `direction` mid-flight steers the bullet itself (see `Assets/patterns/shifter.json`); the bullet writes its integrated direction/speed back so curving keeps accumulating. The sub-script starts from a clone of the bullet's prototype (inheriting direction/speed/vars) with the sub-script stripped so it doesn't recurse by accident. `{"control": "Sub", "actions": []}` clears it. Because the bullet adopts the sub-script prototype's flight properties, wrap any *fire-configuration* mutations (setting direction/speed/turn just to shape a burst of children) in `Scope` — otherwise the bullet itself adopts them. See `Assets/patterns/flower.json` for a full example: curving seed bullets whose `Scope`d burst fires accelerating petals while the seed keeps curving.

### Values and expressions

Any numeric field accepts a literal, a `"$param"` reference, or an expression:

- Arithmetic `+ - * /` with correct precedence and left-to-right associativity, **and parentheses**: `"2 * ($base + 4)"`.
- Trig **in degrees** (the engine-wide convention): `"sin($phase) * 40"`, `"cos(90)"`.
- Inline randoms: `"random.between(2, 6)"` (uniform in `[min, max)`) and `"random.angle(8)"` (one of `n` evenly spaced angles — `floor(random*n) * 360/n` — for grouping shots into discrete spokes).
- **Live prototype reads**: a bare identifier (no `$` prefix) resolves through the executing context's prototype `getProp` — custom script variables (`"sin(bearing) * 40"`) and built-in properties (`"speed * 2"`) alike. Inside a `Scope` it reads the Scope's clone; in a sub-script, that bullet's own prototype. This is what makes parametric orbits possible: `sincos.json` and `transform.json` recompute `x`/`y` from an advancing per-bullet variable every frame.

**Evaluation model**: deterministic expressions are folded to constants at compile time (zero per-frame cost, identical semantics to before). Expressions containing any `random.*` call **or a bare-identifier prototype read** stay live and **re-evaluate on every command execution** — `{"control": "Set", "prop": "speed", "value": "random.between(2, 6)"}` inside a `Loop` gives each volley a fresh speed, and a `Wait` with a volatile frame count re-rolls each iteration. Structural values (`Rep`/`Radial`/`NWay`/`Line`/`Dup` **counts**, `Tween` **frames**) are fixed at compile time — prototype reads there see no live prototype and evaluate to 0.

`Copy` supports scaling — `dst = src * k`:

```jsonc
{"control": "Copy", "from": "speed", "to": "turn", "scale": 0.5}
```

(This needed its own small addition: expressions can reference `$params` but not live prototype properties, so `src * k` isn't expressible in the expression language itself.)

### Script variables and scoping (status)

`vars` remains one flat `Map<String, Float>` per prototype. **`Scope` already provides block scoping with shadowing**: a variable set inside a `Scope` (like any prototype mutation there) is discarded when the block ends, so nested blocks can reuse names freely. **Expressions can now read vars and properties directly** (bare identifiers, see "Values and expressions" above), which is what makes script variables genuinely useful. Still missing for a full scoped-variable story:

1. **Write-through to outer scopes** (mutating an outer counter from inside a block): requires a variable-environment stack parallel to the `ShotFrame` stack, with reads walking up the parent chain and an explicit `Declare`/`Let` command to distinguish "new local" from "assign outer".
2. **Types beyond Float**: `vars` and `getProp`/`setProp` are all-Float; strings/bools would need a tagged value union threaded through every generic command.

Neither is individually hard, but both touch `ShotContext`, `ShotPrototype`, and every property command — deliberately left out of this batch.

### Enemy self-movement (moveSelf)

Setting the script variable `moveSelf` to nonzero on an **enemy-owned** script makes the enemy's velocity derive from the script's live root `direction`/`speed` every frame — the firedancer model where the same language moves the actor and fires its bullets:

```jsonc
{"control": "Set", "prop": "moveSelf", "value": 1},
{"control": "Loop", "actions": [
    {"control": "Set", "prop": "direction", "value": 90},
    {"control": "Tween", "prop": "speed", "to": 16, "frames": 60},   // smooth acceleration
    {"control": "Set", "prop": "speed", "value": 0},
    {"control": "Wait", "frames": 30}
]}
```

`Tween` on `speed` gives acceleration/deceleration; `Set`/`Add` on `direction` steers. Movement-only patterns fire no bullets at all (`move.json`, `move2.json`). The sync lives in `ScriptedShootingPattern` (display side), not the shot engine — bullets are unaffected, and a level `movementScript` on the same enemy would fight it (the pattern reasserts velocity every frame), so use one or the other.

## Running the tests

The engine tests run without OpenFL:

```
haxe -cp Source -cp Tests -main TestShot --interp
```

(Source folders are lowercase to match package names, so this works on case-sensitive filesystems.)

## Level-side formats & the authoring DSL

The shot-script language above is unchanged, but levels grew some blocks (all optional, all parsed in `Source/Manager/LevelData.hx`):

- **`dialogue: {intro: [...], outro: [...]}`** — conversations of `{speaker, text, portrait?, side?}` played before the waves / after the field clears (`Source/UI/DialogueManager.hx`).
- **`boss: {name?, phases: [...]}`** on a spawn — multi-phase boss. Each phase: `{name?, health, pattern? | script?, patternConfig?, movementScript?}`. Phase clears wipe the bullet field, swap the pattern (and movement), and grant brief invulnerability; the last phase kills the boss (`Source/Enemy/BossEnemy.hx`, orchestration in `EnemyManager`).
- **`sprite`** on a spawn — a skin name from `assets/sprites.json` (enemy + bullet art, optional spritesheet `rect` cell, `scale`) or a direct `.png` path drop-in (`Source/Manager/SpriteLibrary.hx`).

Instead of hand-writing level JSON, prefer the **authoring DSL**: JavaScript sources in `tools/src/` compiled by `node tools/compile.js` into the exact JSON formats above, with high-level movement helpers (`enterFrom`, `easeTo`, `weave`) and a static validator that also checks all hand-written JSON via `--check`. Full reference: `tools/README.md`.
