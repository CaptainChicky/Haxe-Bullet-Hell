import shot.ShotPrototype;
import shot.ShotCommand.IShotCommand;
import shot.ScriptRunner;
import shot.ShotEmitter;
import shot.CommandRegistry;
import shot.Expression;
import haxe.Json;

class FakeEmitter implements IShotEmitter {
	public var spawns:Array<{proto:ShotPrototype, x:Float, y:Float, frame:Int}> = [];
	public var frame:Int = 0;
	public var alive:Bool = true;
	public var targetX:Float = 100;
	public var targetY:Float = 0;
	public var originX:Float = 0;
	public var originY:Float = 0;

	public function new() {}

	public function getOriginX():Float return originX;

	public function getOriginY():Float return originY;

	public function getTarget():ShotTarget return {x: targetX, y: targetY};

	public function spawn(prototype:ShotPrototype, x:Float, y:Float):Void {
		spawns.push({proto: prototype, x: x, y: y, frame: frame});
	}

	public function isAlive():Bool return alive;

	public var vanished:Bool = false;

	public function vanish():Void {
		vanished = true;
		alive = false;
	}
}

/**
 * Mirrors the shipped BulletEnemy.everyFrame control flow (script update ->
 * sync flight state from the script's root prototype -> integrate turn/accel
 * -> write direction/speed back), minus display/stage concerns, so the full
 * bullet<->sub-script feedback loop is testable under --interp.
 * If BulletEnemy.everyFrame changes, keep this in sync.
 */
class HeadlessTestBullet {
	public var x:Float = 0;
	public var y:Float = 0;
	public var alive:Bool = true;
	public var direction:Float;
	public var speed:Float;
	public var accel:Float;
	public var angularVelocity:Float;
	public var minSpeed:Float;
	public var maxSpeed:Float;
	public var script:ScriptRunner = null;

	// Binding (mirrors BulletEnemy).
	public var bindMode:Int = ShotPrototype.BIND_NONE;
	public var bindAnchor:IShotEmitter = null;
	public var bindSource:ShotPrototype = null;
	var anchorLastX:Float = 0;
	var anchorLastY:Float = 0;

	public function new(p:ShotPrototype) {
		direction = p.direction;
		speed = p.speed;
		accel = p.accel;
		angularVelocity = p.angularVelocity;
		minSpeed = p.minSpeed;
		maxSpeed = p.maxSpeed;
	}

	public function bindTo(anchor:IShotEmitter, mode:Int, source:ShotPrototype):Void {
		bindAnchor = anchor;
		bindMode = mode;
		bindSource = source;
		anchorLastX = anchor.getOriginX();
		anchorLastY = anchor.getOriginY();
	}

	public function everyFrame():Void {
		if (!alive) return;
		if (script != null) {
			script.update();
			if (!alive) return;
			// In BIND_FULL mode the parent's live prototype owns flight state.
			if (bindMode != ShotPrototype.BIND_FULL) {
				var proto = script.getPrototype();
				if (proto != null) {
					direction = proto.direction;
					speed = proto.speed;
					accel = proto.accel;
					angularVelocity = proto.angularVelocity;
					minSpeed = proto.minSpeed;
					maxSpeed = proto.maxSpeed;
				}
			}
		}
		// Bound bullets follow their parent.
		var bindDX:Float = 0;
		var bindDY:Float = 0;
		if (bindAnchor != null) {
			if (!bindAnchor.isAlive()) {
				// Orphan-release.
				bindAnchor = null;
				bindSource = null;
				bindMode = ShotPrototype.BIND_NONE;
			} else {
				if (bindMode == ShotPrototype.BIND_FULL && bindSource != null) {
					direction = bindSource.direction;
					speed = bindSource.speed;
					accel = bindSource.accel;
					angularVelocity = bindSource.angularVelocity;
					minSpeed = bindSource.minSpeed;
					maxSpeed = bindSource.maxSpeed;
				}
				var px = bindAnchor.getOriginX();
				var py = bindAnchor.getOriginY();
				bindDX = px - anchorLastX;
				bindDY = py - anchorLastY;
				anchorLastX = px;
				anchorLastY = py;
			}
		}
		direction += angularVelocity;
		speed += accel;
		if (speed < minSpeed) speed = minSpeed;
		if (speed > maxSpeed) speed = maxSpeed;
		if (script != null) {
			var proto = script.getPrototype();
			if (proto != null) {
				proto.direction = direction;
				proto.speed = speed;
			}
		}
		var rad = direction * Math.PI / 180;
		if (bindMode == ShotPrototype.BIND_OFFSET && bindAnchor != null && script != null) {
			var proto = script.getPrototype();
			if (proto != null) {
				var px = bindAnchor.getOriginX();
				var py = bindAnchor.getOriginY();
				if (proto.offsetDistance != 0) {
					var orad = proto.offsetAngle * Math.PI / 180;
					px += Math.cos(orad) * proto.offsetDistance;
					py += Math.sin(orad) * proto.offsetDistance;
				}
				px += proto.x;
				py += proto.y;
				x = px;
				y = py;
			}
		} else {
			x += Math.cos(rad) * speed + bindDX;
			y += Math.sin(rad) * speed + bindDY;
		}
	}
}

/** FakeEmitter anchored to a HeadlessTestBullet (mirrors BulletSubEmitter). */
class FakeBulletEmitter implements IShotEmitter {
	public var bullet:HeadlessTestBullet;
	public var spawns:Array<{proto:ShotPrototype, x:Float, y:Float}> = [];

	public function new(bullet:HeadlessTestBullet) {
		this.bullet = bullet;
	}

	public function getOriginX():Float return bullet.x;

	public function getOriginY():Float return bullet.y;

	public function getTarget():ShotTarget return null;

	public function spawn(prototype:ShotPrototype, x:Float, y:Float):Void {
		spawns.push({proto: prototype, x: x, y: y});
	}

	public function isAlive():Bool return bullet.alive;

	public function vanish():Void bullet.alive = false;
}

class TestShot {
	static var failures = 0;

	static function check(cond:Bool, msg:String):Void {
		if (!cond) {
			failures++;
			Sys.println("FAIL: " + msg);
		} else {
			Sys.println("ok:   " + msg);
		}
	}

	static function compile(json:String, ?params:Dynamic):Array<IShotCommand> {
		var paramMap:Map<String, Dynamic> = new Map();
		if (params != null)
			for (f in Reflect.fields(params))
				paramMap.set(f, Reflect.field(params, f));
		return CommandRegistry.compileList(Json.parse(json), new CompileContext(paramMap));
	}

	static function run(commands:Array<IShotCommand>, frames:Int):FakeEmitter {
		var em = new FakeEmitter();
		var runner = new ScriptRunner(em, commands);
		for (i in 0...frames) {
			em.frame = i;
			runner.update();
		}
		return em;
	}

	public static function main() {
		// --- Expression evaluator ---------------------------------------------
		var p:Map<String, Dynamic> = ["base" => 90.0, "spread" => 15.0, "n" => 3.0];
		check(Expression.evaluate("$base - $spread", p) == 75, "expr: $base - $spread = 75");
		check(Expression.evaluate("$base + $spread", p) == 105, "expr: $base + $spread = 105");
		check(Expression.evaluate("$n * 2 + 4", p) == 10, "expr: precedence $n * 2 + 4 = 10");
		check(Expression.evaluate("10 - 2 - 3", p) == 5, "expr: left assoc 10 - 2 - 3 = 5 (old evaluator broke on repeated values)");
		check(Expression.evaluate("$n + $n", p) == 6, "expr: repeated param $n + $n = 6");
		check(Expression.evaluate("12 / $n / 2", p) == 2, "expr: 12 / $n / 2 = 2");

		// --- Spiral: fire every frame, +12 degrees each shot --------------------
		var spiral = compile('[
			{"control": "SetSpeed", "value": "$$bulletSpeed"},
			{"control": "SetAngle", "value": 0},
			{"control": "Loop", "actions": [
				{"control": "Fire", "angle": 0, "speed": 0},
				{"control": "AddAngle", "delta": 12},
				{"control": "Wait", "frames": 1}
			]}
		]', {bulletSpeed: 5});
		var em = run(spiral, 5);
		check(em.spawns.length == 5, "spiral: 5 bullets after 5 frames (one per frame)");
		check(em.spawns[0].proto.direction == 0 && em.spawns[0].proto.speed == 5, "spiral: first bullet dir=0 speed=5 (Fire 0,0 uses prototype)");
		check(em.spawns[3].proto.direction == 36, "spiral: 4th bullet direction = 36");
		check(em.spawns[1].proto.direction == 12 && em.spawns[0].proto.direction == 0, "spiral: cloned prototypes - later mutation didn't touch earlier bullet");

		// --- Rep + fractional waits --------------------------------------------
		var rep = compile('[{"control": "Rep", "count": 3, "actions": [
			{"control": "Fire", "angle": 90, "speed": 2},
			{"control": "Wait", "frames": 0.5}
		]}]');
		em = run(rep, 3);
		check(em.spawns.length == 3, "rep: exactly 3 bullets");
		check(em.spawns[0].frame == 0 && em.spawns[1].frame == 0 && em.spawns[2].frame == 1,
			"rep: 0.5-frame waits -> two shots frame 0, one shot frame 1 (frame budget)");

		// --- NWay geometry -------------------------------------------------------
		var nway = compile('[
			{"control": "SetAngle", "value": 90},
			{"control": "NWay", "count": 3, "angle": 90, "speed": 4}
		]');
		em = run(nway, 1);
		check(em.spawns.length == 3, "nway: 3 bullets");
		check(em.spawns[0].proto.direction == 45 && em.spawns[2].proto.direction == 135, "nway: arc 45..135 centered on 90");

		// --- Radial --------------------------------------------------------------
		var radial = compile('[{"control": "Radial", "count": 4, "speed": 3}]');
		em = run(radial, 1);
		check(em.spawns.length == 4 && em.spawns[3].proto.direction == 270, "radial: 4 bullets, last at 270");

		// --- Offset + AimAtPlayer ------------------------------------------------
		var aim = compile('[
			{"control": "SetOffset", "distance": 50, "angle": 90},
			{"control": "AimAtPlayer"},
			{"control": "Fire", "angle": 0, "speed": 5}
		]');
		em = run(aim, 1); // target at (100, 0); spawn at (0, 50)
		check(Math.abs(em.spawns[0].x - 0) < 1e-9 && Math.abs(em.spawns[0].y - 50) < 1e-9, "offset: bullet spawns at offset position (0,50)");
		var expected = Math.atan2(0 - 50, 100 - 0) * 180 / Math.PI;
		check(Math.abs(em.spawns[0].proto.direction - expected) < 1e-9, "aim: direction points from offset spawn to target");

		// --- Concurrent: independent prototype clones, parent resumes after -----
		var conc = compile('[
			{"control": "SetSpeed", "value": 7},
			{"control": "Concurrent", "branches": [
				[{"control": "SetAngle", "value": 10}, {"control": "Wait", "frames": 2}, {"control": "Fire", "angle": 0, "speed": 0}],
				[{"control": "SetAngle", "value": 20}, {"control": "Fire", "angle": 0, "speed": 0}]
			]},
			{"control": "Fire", "angle": 99, "speed": 1}
		]');
		em = run(conc, 6);
		check(em.spawns.length == 3, "concurrent: 3 total bullets");
		check(em.spawns[0].proto.direction == 20 && em.spawns[0].proto.speed == 7, "concurrent: branch inherits cloned prototype (speed 7)");
		check(em.spawns[1].proto.direction == 10, "concurrent: branches have independent directions");
		var last = em.spawns[2];
		check(last.proto.direction == 99, "concurrent: parent resumes after all branches complete");
		check(last.frame > em.spawns[1].frame, "concurrent: parent fired after slow branch finished");

		// --- Nested concurrent (new capability) -----------------------------------
		var nested = compile('[{"control": "Concurrent", "branches": [
			[{"control": "Concurrent", "branches": [
				[{"control": "Fire", "angle": 1, "speed": 1}],
				[{"control": "Fire", "angle": 2, "speed": 1}]
			]}],
			[{"control": "Fire", "angle": 3, "speed": 1}]
		]}]');
		em = run(nested, 4);
		check(em.spawns.length == 3, "nested concurrent: all 3 branches fired (old engine only warned)");

		// --- Generic property commands + curving bullets ---------------------------
		var generic = compile('[
			{"control": "Set", "prop": "accel", "value": 0.5},
			{"control": "Set", "prop": "turn", "value": -3},
			{"control": "Add", "prop": "accel", "delta": 0.25},
			{"control": "Fire", "angle": 45, "speed": 6}
		]');
		em = run(generic, 1);
		check(em.spawns[0].proto.accel == 0.75 && em.spawns[0].proto.angularVelocity == -3,
			"generic props: accel/turn set via Set/Add without any new command classes");

		// --- Custom script variables -----------------------------------------------
		var vars = compile('[
			{"control": "Set", "prop": "myCounter", "value": 4},
			{"control": "Add", "prop": "myCounter", "delta": 1},
			{"control": "Copy", "from": "myCounter", "to": "speed"},
			{"control": "Fire", "angle": 90, "speed": 0}
		]');
		em = run(vars, 1);
		check(em.spawns[0].proto.speed == 5, "vars: unknown prop names become script variables, Copy moves them into speed");

		// --- Expressions read live prototype vars/properties ------------------------
		var exprVars = compile('[
			{"control": "Set", "prop": "phase", "value": 90},
			{"control": "Set", "prop": "y", "value": "sin(phase) * 40"},
			{"control": "Set", "prop": "speed", "value": "speed + phase / 30"},
			{"control": "Fire", "angle": 90, "speed": 0}
		]');
		em = run(exprVars, 1);
		check(Math.abs(em.spawns[0].proto.y - 40) < 1e-9, "expr vars: sin(phase) reads a live script variable");
		check(Math.abs(em.spawns[0].proto.speed - 8) < 1e-9, "expr vars: built-in properties readable too (speed + phase/30 = 8)");

		var exprLive = compile('[
			{"control": "Set", "prop": "k", "value": 0},
			{"control": "Rep", "count": 3, "actions": [
				{"control": "Add", "prop": "k", "delta": 1},
				{"control": "Fire", "angle": "k * 10", "speed": 1}
			]}
		]');
		em = run(exprLive, 1);
		check(em.spawns.length == 3 && em.spawns[0].proto.direction == 10 && em.spawns[2].proto.direction == 30,
			"expr vars: var references stay volatile, re-evaluated per execution (k*10 -> 10..30)");

		// --- Sub-scripts attach to fired prototypes ---------------------------------
		var sub = compile('[
			{"control": "Sub", "actions": [{"control": "Wait", "frames": 10}, {"control": "Radial", "count": 8, "speed": 2}]},
			{"control": "Fire", "angle": 90, "speed": 3},
			{"control": "Sub", "actions": []},
			{"control": "Fire", "angle": 90, "speed": 3}
		]');
		em = run(sub, 1);
		check(em.spawns[0].proto.subCommands != null && em.spawns[1].proto.subCommands == null,
			"sub: first bullet carries sub-script, second cleared");
		// Simulate the bullet running its own script:
		var bulletEm = new FakeEmitter();
		var bulletRunner = new ScriptRunner(bulletEm, em.spawns[0].proto.subCommands);
		for (i in 0...11) { bulletEm.frame = i; bulletRunner.update(); }
		check(bulletEm.spawns.length == 8, "sub: bullet-owned runner fires its radial burst after 10 frames");
		check(bulletEm.spawns.length == 8 && bulletEm.spawns[0].frame == 10, "sub: burst timing correct");

		// --- Legacy pattern files compile & run ---------------------------------------
		for (name in ["spiral", "nwhip", "orbit", "sniper", "random", "radial", "flower", "shifter", "satellite",
			"sincos", "transform", "clover", "laundry", "bindpos"]) {
			var text = sys.io.File.getContent("Assets/patterns/" + name + ".json");
			var template:Dynamic = Json.parse(text);
			var paramMap:Map<String, Dynamic> = new Map();
			for (f in Reflect.fields(template.parameters)) {
				var def = Reflect.field(Reflect.field(template.parameters, f), "default");
				if (def != null) paramMap.set(f, def);
			}
			var cmds = CommandRegistry.compileList(template.script, new CompileContext(paramMap));
			var e = run(cmds, 60);
			check(cmds.length > 0 && e.spawns.length > 0, 'legacy pattern "$name" compiles and fires (${e.spawns.length} bullets in 60 frames)');
		}

		// --- Movement-only patterns: no bullets, moveSelf set -------------------------
		for (name in ["move", "move2"]) {
			var text = sys.io.File.getContent("Assets/patterns/" + name + ".json");
			var template:Dynamic = Json.parse(text);
			var paramMap:Map<String, Dynamic> = new Map();
			for (f in Reflect.fields(template.parameters)) {
				var def = Reflect.field(Reflect.field(template.parameters, f), "default");
				if (def != null) paramMap.set(f, def);
			}
			var cmds = CommandRegistry.compileList(template.script, new CompileContext(paramMap));
			var e = new FakeEmitter();
			var r = new ScriptRunner(e, cmds);
			for (i in 0...200) r.update();
			check(e.spawns.length == 0 && r.getPrototype().getProp("moveSelf") == 1,
				'movement pattern "$name" fires no bullets and sets moveSelf');
		}

		// --- Emitter death stops the runner -------------------------------------------
		var loopFire = compile('[{"control": "Loop", "actions": [{"control": "Fire", "angle": 0, "speed": 1}, {"control": "Wait", "frames": 1}]}]');
		var em2 = new FakeEmitter();
		var runner2 = new ScriptRunner(em2, loopFire);
		runner2.update();
		em2.alive = false;
		runner2.update();
		runner2.update();
		check(em2.spawns.length == 1, "lifecycle: runner stops firing once emitter dies");

		// --- Vanish: emitter's owner despawns, script halts --------------------
		var vanishScript = compile('[
			{"control": "Wait", "frames": 5},
			{"control": "Vanish"},
			{"control": "Fire", "angle": 0, "speed": 1}
		]');
		var em3 = new FakeEmitter();
		var runner3 = new ScriptRunner(em3, vanishScript);
		for (i in 0...10) runner3.update();
		check(em3.vanished, "vanish: emitter.vanish() called after the wait");
		check(em3.spawns.length == 0, "vanish: no commands execute after Vanish (Fire skipped)");

		// --- Tween: linear interpolation landing exactly on target -------------
		var tweenScript = compile('[
			{"control": "Set", "prop": "speed", "value": 2},
			{"control": "Tween", "prop": "speed", "to": 10, "frames": 4},
			{"control": "Fire", "angle": 90, "speed": 0}
		]');
		var em4 = run(tweenScript, 20);
		check(em4.spawns.length == 1 && em4.spawns[0].proto.speed == 10, "tween: property lands exactly on target (speed 10)");
		check(em4.spawns[0].frame == 4, 'tween: took 4 frames (fired on frame ${em4.spawns[0].frame})');

		// --- Tween inside Loop: fresh state per execution -----------------------
		var tweenLoop = compile('[
			{"control": "Rep", "count": 2, "actions": [
				{"control": "Set", "prop": "speed", "value": 0},
				{"control": "Tween", "prop": "speed", "to": 6, "frames": 3},
				{"control": "Fire", "angle": 90, "speed": 0}
			]}
		]');
		var em5 = run(tweenLoop, 20);
		check(em5.spawns.length == 2 && em5.spawns[0].proto.speed == 6 && em5.spawns[1].proto.speed == 6,
			"tween: shared compiled command re-runs cleanly (state is per-execution)");

		// --- Concurrent share: two parallel tweens on ONE prototype -------------
		var parallelTween = compile('[
			{"control": "Set", "prop": "speed", "value": 0},
			{"control": "Set", "prop": "turn", "value": 0},
			{"control": "Concurrent", "share": true, "branches": [
				[{"control": "Tween", "prop": "speed", "to": 10, "frames": 5}],
				[{"control": "Tween", "prop": "turn", "to": 5, "frames": 5}]
			]},
			{"control": "Fire", "angle": 90, "speed": 0}
		]');
		var em6 = run(parallelTween, 20);
		check(em6.spawns.length == 1 && em6.spawns[0].proto.speed == 10 && em6.spawns[0].proto.angularVelocity == 5,
			"concurrent share: parallel tweens both landed on the same prototype");

		// --- Default Concurrent still clones (regression) ------------------------
		var cloneCheck = compile('[
			{"control": "Set", "prop": "speed", "value": 0},
			{"control": "Concurrent", "branches": [
				[{"control": "Set", "prop": "speed", "value": 99}]
			]},
			{"control": "Fire", "angle": 90, "speed": 0}
		]');
		var em7 = run(cloneCheck, 5);
		check(em7.spawns.length == 1 && em7.spawns[0].proto.speed == 0,
			"concurrent default: branches still clone (parent prototype untouched)");

		// --- getPrototype survives script completion (last-frame mutation) ------
		var lastMutation = compile('[
			{"control": "Wait", "frames": 3},
			{"control": "Add", "prop": "direction", "delta": -120}
		]');
		var em8 = new FakeEmitter();
		var runner8 = new ScriptRunner(em8, lastMutation);
		var startDir = runner8.getPrototype().direction;
		for (i in 0...6) runner8.update();
		check(runner8.getPrototype() != null && runner8.getPrototype().direction == startDir - 120,
			"getPrototype: retained after completion, final-frame Add not lost");

		// --- Scope: body mutates a discarded clone -------------------------------
		var scopeScript = compile('[
			{"control": "Set", "prop": "turn", "value": 1.5},
			{"control": "Set", "prop": "speed", "value": 3},
			{"control": "Scope", "actions": [
				{"control": "Set", "prop": "turn", "value": 0},
				{"control": "Set", "prop": "speed", "value": 9},
				{"control": "Set", "prop": "burstVar", "value": 7},
				{"control": "Fire", "angle": 0, "speed": 0}
			]},
			{"control": "Fire", "angle": 0, "speed": 0}
		]');
		var em9 = run(scopeScript, 3);
		check(em9.spawns.length == 2, "scope: both Fires executed");
		check(em9.spawns[0].proto.speed == 9 && em9.spawns[0].proto.angularVelocity == 0,
			"scope: bullet fired inside gets scoped values (speed 9, turn 0)");
		check(em9.spawns[1].proto.speed == 3 && em9.spawns[1].proto.angularVelocity == 1.5,
			"scope: prototype restored after block - outside Fire sees pre-scope values");
		check(!em9.spawns[1].proto.vars.exists("burstVar"),
			"scope: custom vars set inside the block are discarded too");
		check(em9.spawns[0].frame == 0 && em9.spawns[1].frame == 0,
			"scope: executes inline within the same frame budget (no branch delay)");

		// --- Scope inside Rep: fresh clone per execution (stateful pattern) -----
		var scopeLoop = compile('[
			{"control": "Set", "prop": "speed", "value": 1},
			{"control": "Rep", "count": 2, "actions": [
				{"control": "Scope", "actions": [
					{"control": "Add", "prop": "speed", "delta": 10},
					{"control": "Fire", "angle": 0, "speed": 0}
				]},
				{"control": "Wait", "frames": 1}
			]}
		]');
		var em10 = run(scopeLoop, 5);
		check(em10.spawns.length == 2 && em10.spawns[0].proto.speed == 11 && em10.spawns[1].proto.speed == 11,
			"scope in Rep: each execution clones fresh (no accumulation across iterations)");

		// --- REGRESSION: curving seed keeps curving through and after a Scoped burst
		// (flower.json seeds: prior fix made the bullet adopt the burst's
		// turn=0 / random direction / petal accel permanently).
		var seedProto = new ShotPrototype();
		seedProto.direction = 0;
		seedProto.speed = 2.5;
		seedProto.angularVelocity = 1.5;
		var burstSub = compile('[
			{"control": "Wait", "frames": 20},
			{"control": "Scope", "actions": [
				{"control": "Set", "prop": "turn", "value": 0},
				{"control": "Set", "prop": "speed", "value": 1},
				{"control": "Set", "prop": "accel", "value": 0.08},
				{"control": "Set", "prop": "maxSpeed", "value": 6},
				{"control": "Random", "prop": "direction", "min": 0, "max": 360},
				{"control": "Radial", "count": 8, "speed": 0}
			]}
		]');
		var seed = new HeadlessTestBullet(seedProto);
		var seedEm = new FakeBulletEmitter(seed);
		seed.script = new ScriptRunner(seedEm, burstSub, seedProto.clone());
		var dirAt20:Float = 0;
		for (f in 0...60) {
			seed.everyFrame();
			if (f == 19) dirAt20 = seed.direction;
		}
		check(Math.abs(dirAt20 - 30) < 1e-6, "seed burst: curving accumulates before the burst (30 deg at frame 20)");
		check(seedEm.spawns.length == 8, "seed burst: 8 petals fired at the burst");
		check(Math.abs(seed.direction - 90) < 1e-6,
			'seed burst: seed keeps curving through and after the burst (dir=${seed.direction}, expected 90)');
		check(Math.abs(seed.speed - 2.5) < 1e-6 && Math.abs(seed.angularVelocity - 1.5) < 1e-6,
			"seed burst: seed keeps its own speed/turn (petal accel/turn=0 did not leak)");
		check(seedEm.spawns[0].proto.accel == 0.08 && seedEm.spawns[0].proto.angularVelocity == 0 && seedEm.spawns[0].proto.maxSpeed == 6,
			"seed burst: petals got the scoped burst properties");

		// --- Shifter semantics still intact: sub-script Add steers the bullet ---
		var kinkProto = new ShotPrototype();
		kinkProto.direction = 90;
		kinkProto.speed = 3;
		var kinkSub = compile('[
			{"control": "Wait", "frames": 30},
			{"control": "Add", "prop": "direction", "delta": -120}
		]');
		var kink = new HeadlessTestBullet(kinkProto);
		kink.script = new ScriptRunner(new FakeBulletEmitter(kink), kinkSub, kinkProto.clone());
		for (f in 0...40) kink.everyFrame();
		check(Math.abs(kink.direction - (-30)) < 1e-6,
			"shifter semantics: unscoped sub-script Add still steers the bullet (90 -> -30)");

		// ======================================================================
		// Item 2: expression extensions
		// ======================================================================
		var xp:Map<String, Dynamic> = ["base" => 90.0, "n" => 4.0];
		check(Math.abs(Expression.evaluate("sin(90)", xp) - 1) < 1e-12, "expr fn: sin(90) = 1 (degrees)");
		check(Math.abs(Expression.evaluate("cos(0) * 4", xp) - 4) < 1e-12, "expr fn: cos(0) * 4 = 4");
		check(Math.abs(Expression.evaluate("sin($base - 60)", xp) - 0.5) < 1e-12, "expr fn: params inside call args, sin(30) = 0.5");
		check(Expression.evaluate("2 * (3 + 4)", xp) == 14, "expr: parentheses now supported");
		check(Expression.evaluate("-(2 + 3)", xp) == -5, "expr: unary minus on a group");
		check(Expression.evaluate("$base - $n * 2", xp) == 82, "expr: legacy precedence semantics intact");

		var allIn = true, sawDistinct = false, firstV:Float = -1;
		for (i in 0...300) {
			var v = Expression.evaluate("random.between(2, 6)", xp);
			if (v < 2 || v >= 6) allIn = false;
			if (i == 0) firstV = v else if (v != firstV) sawDistinct = true;
		}
		check(allIn && sawDistinct, "expr fn: random.between(2,6) stays in [2,6) and varies");

		var anglesOk = true;
		var angleSeen = [false, false, false, false];
		for (i in 0...300) {
			var v = Expression.evaluate("random.angle(4)", xp);
			if (v != 0 && v != 90 && v != 180 && v != 270) anglesOk = false
			else angleSeen[Std.int(v / 90)] = true;
		}
		check(anglesOk && angleSeen[0] && angleSeen[1] && angleSeen[2] && angleSeen[3],
			"expr fn: random.angle(4) hits exactly {0, 90, 180, 270}");

		// Volatile expressions re-roll PER COMMAND EXECUTION (the whole point).
		var inlineRand = compile('[{"control": "Loop", "actions": [
			{"control": "Set", "prop": "speed", "value": "random.between(2, 6)"},
			{"control": "Fire", "angle": 90, "speed": 0},
			{"control": "Wait", "frames": 1}
		]}]');
		var emA = run(inlineRand, 30);
		var inRange = true, varies = false;
		for (s in emA.spawns) {
			if (s.proto.speed < 2 || s.proto.speed >= 6) inRange = false;
			if (s.proto.speed != emA.spawns[0].proto.speed) varies = true;
		}
		check(emA.spawns.length == 30 && inRange && varies,
			"inline random: Set re-rolls per loop iteration (30 bullets, varied speeds in range)");

		// Deterministic expressions still fold to constants (params captured).
		var folded = compile('[{"control": "Set", "prop": "speed", "value": "sin($$a) * 10"},
			{"control": "Fire", "angle": 90, "speed": 0}]', {a: 90});
		var emB = run(folded, 1);
		check(Math.abs(emB.spawns[0].proto.speed - 10) < 1e-12, "expr fn: functions usable in command values via $params");

		// Copy scaling (needed its own small addition - see notes).
		var copyScale = compile('[
			{"control": "Set", "prop": "speed", "value": 4},
			{"control": "Copy", "from": "speed", "to": "myVar", "scale": 3},
			{"control": "Copy", "from": "myVar", "to": "speed", "scale": 0.5},
			{"control": "Fire", "angle": 90, "speed": 0}
		]');
		var emC = run(copyScale, 1);
		check(emC.spawns[0].proto.speed == 6, "copy scale: dst = src * k (4*3=12 into var, *0.5 back = 6)");
		check(emC.spawns[0].proto.vars.get("myVar") == 12, "copy scale: works into custom vars too");

		// ======================================================================
		// Item 3: Cartesian position + transforms
		// ======================================================================
		var cart = compile('[
			{"control": "Set", "prop": "x", "value": 30},
			{"control": "Set", "prop": "y", "value": -10},
			{"control": "Fire", "angle": 90, "speed": 1}
		]');
		var emD = run(cart, 1);
		check(emD.spawns[0].x == 30 && emD.spawns[0].y == -10, "cartesian: bullet spawns at origin + (x, y)");

		var both = compile('[
			{"control": "SetOffset", "distance": 50, "angle": 0},
			{"control": "Set", "prop": "x", "value": 30},
			{"control": "Set", "prop": "y", "value": -10},
			{"control": "Fire", "angle": 90, "speed": 1}
		]');
		var emE = run(both, 1);
		check(Math.abs(emE.spawns[0].x - 80) < 1e-9 && Math.abs(emE.spawns[0].y - (-10)) < 1e-9,
			"cartesian: polar and Cartesian offsets compose (50,0) + (30,-10)");

		var rot = compile('[
			{"control": "Set", "prop": "x", "value": 10},
			{"control": "Set", "prop": "direction", "value": 0},
			{"control": "Rotate", "degrees": 90},
			{"control": "Fire", "angle": 0, "speed": 1}
		]');
		var emF = run(rot, 1);
		check(Math.abs(emF.spawns[0].x - 0) < 1e-9 && Math.abs(emF.spawns[0].y - 10) < 1e-9,
			"rotate: (10,0) rotated 90 deg -> (0,10) (matches offsetAngle convention)");
		check(emF.spawns[0].proto.offsetAngle == 90, "rotate: polar offsetAngle rotates in step");
		check(emF.spawns[0].proto.direction == 0, "rotate: direction untouched by default");

		var rotDir = compile('[
			{"control": "Set", "prop": "direction", "value": 45},
			{"control": "Rotate", "degrees": 90, "withDirection": true},
			{"control": "Fire", "angle": 0, "speed": 1}
		]');
		var emG = run(rotDir, 1);
		check(emG.spawns[0].proto.direction == 135, "rotate withDirection: travel direction rotates too");

		var scl = compile('[
			{"control": "Set", "prop": "x", "value": 10},
			{"control": "Set", "prop": "y", "value": 5},
			{"control": "SetOffset", "distance": 50, "angle": 90},
			{"control": "Scale", "factor": 2},
			{"control": "Fire", "angle": 0, "speed": 1}
		]');
		var emH = run(scl, 1);
		check(emH.spawns[0].proto.x == 20 && emH.spawns[0].proto.y == 10 && emH.spawns[0].proto.offsetDistance == 100,
			"scale: factor scales x, y, and offsetDistance uniformly");

		var sclAxis = compile('[
			{"control": "Set", "prop": "x", "value": 10},
			{"control": "Set", "prop": "y", "value": 10},
			{"control": "SetOffset", "distance": 50, "angle": 0},
			{"control": "Scale", "x": 3, "y": 0.5},
			{"control": "Fire", "angle": 0, "speed": 1}
		]');
		var emI = run(sclAxis, 1);
		check(emI.spawns[0].proto.x == 30 && emI.spawns[0].proto.y == 5 && emI.spawns[0].proto.offsetDistance == 50,
			"scale: per-axis x/y factors leave offsetDistance alone");

		// ======================================================================
		// Item 1: Bind
		// ======================================================================
		// clone(): bindMode travels, bindSource (runtime wiring) does not.
		var bproto = new ShotPrototype();
		bproto.bindMode = ShotPrototype.BIND_FULL;
		bproto.bindSource = new ShotPrototype();
		var bclone = bproto.clone();
		check(bclone.bindMode == ShotPrototype.BIND_FULL && bclone.bindSource == null,
			"bind: clone copies bindMode but never bindSource");

		// Position bind: bullet moves in the parent's frame of reference.
		var posBind = compile('[
			{"control": "Bind", "mode": "position"},
			{"control": "Set", "prop": "direction", "value": 0},
			{"control": "Set", "prop": "speed", "value": 1},
			{"control": "Fire", "angle": 0, "speed": 0}
		]');
		var parentEm = new FakeEmitter();
		var parentRunner = new ScriptRunner(parentEm, posBind);
		parentRunner.update();
		check(parentEm.spawns.length == 1 && parentEm.spawns[0].proto.bindMode == ShotPrototype.BIND_POSITION,
			"bind: Bind control marks the fired clone");
		check(parentEm.spawns[0].proto.bindSource == parentRunner.getPrototype(),
			"bind: fireClone wires bindSource to the parent's live root prototype");

		var childP = parentEm.spawns[0].proto;
		var child = new HeadlessTestBullet(childP);
		child.x = parentEm.spawns[0].x;
		child.y = parentEm.spawns[0].y;
		child.bindTo(parentEm, childP.bindMode, childP.bindSource); // as EmitterBase.spawn does
		for (f in 0...10) {
			parentEm.originX += 5; // parent moves right 5 px/frame
			parentEm.originY += 2;
			child.everyFrame();
		}
		check(Math.abs(child.x - (50 + 10)) < 1e-9 && Math.abs(child.y - 20) < 1e-9,
			"bind position: parent translation (50,20) carries child while own velocity (10,0) integrates on top");

		// Unbound bullets are NOT dragged by a moving parent (default unchanged).
		var freeP = new ShotPrototype();
		freeP.direction = 0;
		freeP.speed = 1;
		var freeB = new HeadlessTestBullet(freeP);
		var movEm = new FakeEmitter();
		for (f in 0...10) {
			movEm.originX += 5;
			freeB.everyFrame();
		}
		check(freeB.x == 10 && freeB.y == 0, "bind: default (unbound) bullets ignore parent movement entirely");

		// Full bind: flight state re-derived from the parent's live prototype;
		// the bullet's own sub-script cannot steer (bind wins).
		var fullBind = compile('[
			{"control": "Bind", "mode": "full"},
			{"control": "Set", "prop": "direction", "value": 0},
			{"control": "Set", "prop": "speed", "value": 2},
			{"control": "Sub", "actions": [
				{"control": "Wait", "frames": 3},
				{"control": "Add", "prop": "direction", "delta": 45}
			]},
			{"control": "Fire", "angle": 0, "speed": 0}
		]');
		var parentEm2 = new FakeEmitter();
		var parentRunner2 = new ScriptRunner(parentEm2, fullBind);
		parentRunner2.update();
		var childP2 = parentEm2.spawns[0].proto;
		var child2 = new HeadlessTestBullet(childP2);
		child2.bindTo(parentEm2, childP2.bindMode, childP2.bindSource);
		// Attach its sub-script exactly like EmitterBase.spawn does.
		var subProto2 = childP2.clone();
		subProto2.subCommands = null;
		subProto2.bindMode = ShotPrototype.BIND_NONE;
		child2.script = new ScriptRunner(new FakeBulletEmitter(child2), childP2.subCommands, subProto2);
		for (f in 0...6) child2.everyFrame();
		check(child2.direction == 0, "bind full: own sub-script Add cannot steer a fully-bound bullet (bind wins)");
		// Parent script steers ALL fully-bound children by mutating its live prototype.
		parentRunner2.getPrototype().direction = 90;
		var yBefore = child2.y;
		child2.everyFrame();
		check(child2.direction == 90 && child2.y > yBefore,
			"bind full: mutating the parent's live prototype re-steers the bound bullet next frame");

		// Orphan-release: parent dies -> bullet keeps state, continues independently.
		parentEm2.alive = false;
		var xBefore = child2.x;
		parentEm2.originX += 100; // must have no effect anymore
		child2.everyFrame();
		child2.everyFrame();
		check(child2.bindMode == ShotPrototype.BIND_NONE && Math.abs(child2.x - xBefore) < 1e-9 && child2.direction == 90,
			"bind orphan: parent death releases the bullet with its current state (no cascade-vanish, no drag)");

		// Sub-script prototypes strip bindMode: children of a bound bullet
		// don't implicitly bind to it (checked at the clone level above and
		// via the wiring convention replicated here).
		check(subProto2.bindMode == ShotPrototype.BIND_NONE, "bind: sub-script prototype starts unbound (explicit chain opt-in)");

		// ======================================================================
		// Item 4: Line and Dup
		// ======================================================================
		var line = compile('[
			{"control": "Set", "prop": "direction", "value": 90},
			{"control": "Set", "prop": "speed", "value": 9},
			{"control": "Line", "count": 5, "prop": "speed", "from": 1, "to": 5},
			{"control": "Fire", "angle": 0, "speed": 0}
		]');
		var emJ = run(line, 1);
		check(emJ.spawns.length == 6, "line: 5 line bullets + 1 plain Fire");
		var lineOk = true;
		for (i in 0...5) if (emJ.spawns[i].proto.speed != i + 1 || emJ.spawns[i].proto.direction != 90) lineOk = false;
		check(lineOk, "line: speeds step 1..5 inclusive along direction 90");
		check(emJ.spawns[5].proto.speed == 9, "line: prototype property restored afterwards");

		var lineOne = compile('[{"control": "Line", "count": 1, "prop": "speed", "from": 4, "to": 8}]');
		var emK = run(lineOne, 1);
		check(emK.spawns.length == 1 && emK.spawns[0].proto.speed == 4, "line: count 1 fires at 'from'");

		var dup = compile('[
			{"control": "Set", "prop": "speed", "value": 2},
			{"control": "Set", "prop": "direction", "value": 0},
			{"control": "Dup", "count": 3, "props": {
				"direction": {"from": -30, "to": 30},
				"speed": {"step": 1}
			}},
			{"control": "Fire", "angle": 0, "speed": 0}
		]');
		var emL = run(dup, 1);
		check(emL.spawns.length == 4, "dup: 3 copies + 1 plain Fire");
		check(emL.spawns[0].proto.direction == -30 && emL.spawns[1].proto.direction == 0 && emL.spawns[2].proto.direction == 30,
			"dup: from/to interpolates across copies (inclusive)");
		check(emL.spawns[0].proto.speed == 2 && emL.spawns[1].proto.speed == 3 && emL.spawns[2].proto.speed == 4,
			"dup: step adds i*step per copy");
		check(emL.spawns[3].proto.direction == 0 && emL.spawns[3].proto.speed == 2,
			"dup: script prototype untouched (copies are independent clones)");

		var dupRand = compile('[{"control": "Dup", "count": 50, "props": {"speed": {"min": 2, "max": 6}}}]');
		var emM = run(dupRand, 1);
		var dupIn = true, dupVaries = false;
		for (s in emM.spawns) {
			if (s.proto.speed < 2 || s.proto.speed >= 6) dupIn = false;
			if (s.proto.speed != emM.spawns[0].proto.speed) dupVaries = true;
		}
		check(emM.spawns.length == 50 && dupIn && dupVaries, "dup: min/max rolls independently per copy, in range");

		// Dup spreading a PLACEMENT property moves spawn positions per copy.
		var dupPos = compile('[
			{"control": "SetOffset", "distance": 100, "angle": 0},
			{"control": "Dup", "count": 2, "props": {"offsetAngle": {"from": 0, "to": 90}}}
		]');
		var emN = run(dupPos, 1);
		check(Math.abs(emN.spawns[0].x - 100) < 1e-9 && Math.abs(emN.spawns[0].y) < 1e-9
			&& Math.abs(emN.spawns[1].x) < 1e-9 && Math.abs(emN.spawns[1].y - 100) < 1e-9,
			"dup: spreading offsetAngle produces per-copy spawn positions (fireClone uses the copy's placement)");

		// --- satellite end-to-end: the Sub's Scope+Bind+Dup spawns a bound ring --
		{
			var text = sys.io.File.getContent("Assets/patterns/satellite.json");
			var template:Dynamic = Json.parse(text);
			var paramMap:Map<String, Dynamic> = new Map();
			for (f in Reflect.fields(template.parameters))
				paramMap.set(f, Reflect.field(Reflect.field(template.parameters, f), "default"));
			var cmds = CommandRegistry.compileList(template.script, new CompileContext(paramMap));
			var enemyEm = run(cmds, 1);
			var anchorProto = enemyEm.spawns[0].proto;
			var anchor = new HeadlessTestBullet(anchorProto);
			var anchorEm = new FakeBulletEmitter(anchor);
			var subProto = anchorProto.clone();
			subProto.subCommands = null;
			subProto.bindMode = ShotPrototype.BIND_NONE;
			anchor.script = new ScriptRunner(anchorEm, anchorProto.subCommands, subProto);
			for (f in 0...20) anchor.everyFrame();
			var ringOk = anchorEm.spawns.length == 6;
			for (sp in anchorEm.spawns)
				if (sp.proto.bindMode != ShotPrototype.BIND_POSITION || sp.proto.bindSource != anchor.script.getPrototype())
					ringOk = false;
			check(ringOk, "satellite e2e: Sub's Scoped Bind+Dup spawned 6 position-bound satellites wired to the anchor");
			check(anchor.bindMode == ShotPrototype.BIND_NONE && Math.abs(anchor.direction - 90) < 1e-9,
				"satellite e2e: the anchor itself stays unbound and unsteered (Scope contained the burst)");
		}

		Sys.println(failures == 0 ? "\nALL TESTS PASSED" : '\n$failures TEST(S) FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
