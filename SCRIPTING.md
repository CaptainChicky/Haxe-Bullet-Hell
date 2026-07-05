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
| `Shot/PropertyCommands.hx` | Generic `Set`/`Add`/`Random`/`Copy`/`Offset`/`AimAtTarget` |
| `Shot/FireCommands.hx` | `Fire`, `Radial`, `NWay` |
| `Shot/CommandRegistry.hx` | JSON `"control"` name → command parser (the extension point) |
| `Shot/Expression.hx` | `"$param"` references and arithmetic in JSON values |
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
{"control": "Vanish"}                                            // bullet removes itself mid-flight
```

`Tween` is stateful: it interpolates the property one step per frame and lands exactly on `to` after `frames` frames, then the script continues. To run two tweens simultaneously on the *same* upcoming bullet, use `Concurrent` with `"share": true` (branches normally clone the prototype; `share` makes them mutate the parent's):

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

Available properties: `direction` (alias `angle`), `speed`, `offsetDistance`, `offsetAngle`, `accel` (alias `acceleration`), `angularVelocity` (alias `turn`), `minSpeed`, `maxSpeed`, `lifetime` — plus any custom variable name.

### Sub-scripts (bullets that fire bullets)

```jsonc
{"control": "Sub", "actions": [
    {"control": "Wait", "frames": 45},
    {"control": "Radial", "count": 8, "speed": 2}
]}
```

Every bullet fired *after* a `Sub` carries that script and executes it itself after spawning (the bullet becomes its own emitter). The bullet syncs its flight state (`direction`, `speed`, `accel`, `turn`, speed clamps) from the sub-script's live prototype every frame via `ScriptRunner.getPrototype()`, so a sub-script that mutates `direction` mid-flight steers the bullet itself (see `Assets/patterns/shifter.json`); the bullet writes its integrated direction/speed back so curving keeps accumulating. The sub-script starts from a clone of the bullet's prototype (inheriting direction/speed/vars) with the sub-script stripped so it doesn't recurse by accident. `{"control": "Sub", "actions": []}` clears it. Because the bullet adopts the sub-script prototype's flight properties, wrap any *fire-configuration* mutations (setting direction/speed/turn just to shape a burst of children) in `Scope` — otherwise the bullet itself adopts them. See `Assets/patterns/flower.json` for a full example: curving seed bullets whose `Scope`d burst fires accelerating petals while the seed keeps curving.

### Values and expressions

Any numeric field accepts a literal, a `"$param"` reference, or arithmetic: `"$base - $spread"`, `"$rotationSpeed * $fireDelay"` (correct `*`/`/` precedence, left-to-right associativity).

## Running the tests

The engine tests run without OpenFL:

```
haxe -cp Source -cp Tests -main TestShot --interp
```

(Source folders are lowercase to match package names, so this works on case-sensitive filesystems.)
