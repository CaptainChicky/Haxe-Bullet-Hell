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

	public function new() {}

	public function getOriginX():Float return 0;

	public function getOriginY():Float return 0;

	public function getTarget():ShotTarget return {x: targetX, y: targetY};

	public function spawn(prototype:ShotPrototype, x:Float, y:Float):Void {
		spawns.push({proto: prototype, x: x, y: y, frame: frame});
	}

	public function isAlive():Bool return alive;
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
		for (name in ["spiral", "nwhip", "orbit", "sniper", "random", "radial", "flower"]) {
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

		// --- Emitter death stops the runner -------------------------------------------
		var loopFire = compile('[{"control": "Loop", "actions": [{"control": "Fire", "angle": 0, "speed": 1}, {"control": "Wait", "frames": 1}]}]');
		var em2 = new FakeEmitter();
		var runner2 = new ScriptRunner(em2, loopFire);
		runner2.update();
		em2.alive = false;
		runner2.update();
		runner2.update();
		check(em2.spawns.length == 1, "lifecycle: runner stops firing once emitter dies");

		Sys.println(failures == 0 ? "\nALL TESTS PASSED" : '\n$failures TEST(S) FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
