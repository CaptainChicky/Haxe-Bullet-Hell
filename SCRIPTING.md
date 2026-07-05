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
| `Shot/FlowCommands.hx` | `Wait`, `Loop`, `Rep`, `Concurrent`, `Sub` |
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
```

Available properties: `direction` (alias `angle`), `speed`, `offsetDistance`, `offsetAngle`, `accel` (alias `acceleration`), `angularVelocity` (alias `turn`), `minSpeed`, `maxSpeed`, `lifetime` — plus any custom variable name.

### Sub-scripts (bullets that fire bullets)

```jsonc
{"control": "Sub", "actions": [
    {"control": "Wait", "frames": 45},
    {"control": "Radial", "count": 8, "speed": 2}
]}
```

Every bullet fired *after* a `Sub` carries that script and executes it itself after spawning (the bullet becomes its own emitter). The sub-script starts from a clone of the bullet's prototype (inheriting direction/speed/vars) with the sub-script stripped so it doesn't recurse by accident. `{"control": "Sub", "actions": []}` clears it. See `Assets/patterns/flower.json` for a full example: curving seed bullets that burst into accelerating petals.

### Values and expressions

Any numeric field accepts a literal, a `"$param"` reference, or arithmetic: `"$base - $spread"`, `"$rotationSpeed * $fireDelay"` (correct `*`/`/` precedence, left-to-right associativity).

## Running the tests

The engine tests run without OpenFL:

```
haxe -cp Source -cp Tests -main TestShot --interp
```

(On case-sensitive filesystems, use a lowercase symlink for `Source/Shot` → `shot`, since packages are lowercase.)
