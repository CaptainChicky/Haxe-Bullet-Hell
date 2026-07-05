import haxe.Json;
import shot.ShotPrototype;
import shot.ShotCommand.IShotCommand;
import shot.ScriptRunner;
import shot.ShotEmitter;
import shot.CommandRegistry;

/**
 * Headless reproduction of the `shifter` direction-change bug.
 *
 * BulletEnemy imports OpenFL, so it can't run under --interp. HeadlessBullet
 * below replicates BulletEnemy's constructor + everyFrame() control flow
 * line-for-line (minus display/rotation/stage-bounds), driven by the real
 * ScriptRunner and real compiled commands from Assets/patterns/shifter.json.
 *
 * Run with:  haxe -cp Source -cp Tests -main DebugShifter --interp          (buggy path)
 *            haxe -cp Source -cp Tests -main DebugShifter --interp -D fixed (fixed path)
 */
class HeadlessBullet {
	public var id:Int;
	public var x:Float;
	public var y:Float;
	public var velocityX:Float = 0;
	public var velocityY:Float = 0;
	public var alive:Bool = true;

	var direction:Float;
	var speed:Float;
	var accel:Float;
	var angularVelocity:Float;
	var minSpeed:Float;
	var maxSpeed:Float;
	var lifetime:Float;
	var age:Float = 0;
	var script:ScriptRunner = null;

	/** Frames-since-spawn counter, only for trace output. */
	public var frame:Int = 0;

	/** Only the watched bullet prints checkpoint 2/3 traces. */
	public var watched:Bool = false;

	public function new(id:Int, prototype:ShotPrototype, x:Float, y:Float) {
		this.id = id;
		this.x = x;
		this.y = y;
		// --- verbatim from BulletEnemy.new() ---
		direction = prototype.direction;
		speed = prototype.speed;
		accel = prototype.accel;
		angularVelocity = prototype.angularVelocity;
		minSpeed = prototype.minSpeed;
		maxSpeed = prototype.maxSpeed;
		lifetime = prototype.lifetime;
		updateVelocity();
	}

	public function attachScript(runner:ScriptRunner):Void {
		this.script = runner;
	}

	public function destroy():Void {
		alive = false;
		if (script != null) {
			script.stop();
			script = null;
		}
	}

	inline function updateVelocity():Void {
		var rad = direction * Math.PI / 180;
		velocityX = Math.cos(rad) * speed;
		velocityY = Math.sin(rad) * speed;
	}

	public function everyFrame():Void {
		if (!alive) return;
		frame++;

		// Run the bullet's own script (if any) before moving.
		if (script != null) {
			script.update();

			// ---- CHECKPOINT 2: script prototype vs bullet state ----
			if (watched && frame >= 28 && frame <= 32) {
				var proto = script.getPrototype();
				var pd = (proto != null) ? Std.string(proto.direction) : "null(script done)";
				trace('[CP2] bullet#$id frame=$frame  script proto.direction=$pd  bullet.direction=$direction');
			}
		}

#if fixed
		// ---- FIXED PATH: sync flight state from the script's live prototype ----
		if (script != null) {
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
		// Integrate in-flight behavior unconditionally.
		direction += angularVelocity;
		speed += accel;
		if (speed < minSpeed) speed = minSpeed;
		if (speed > maxSpeed) speed = maxSpeed;
		// Write integrated state back so curving accumulates in the prototype
		// (otherwise the sync above would reset it every frame).
		if (script != null) {
			var proto = script.getPrototype();
			if (proto != null) {
				proto.direction = direction;
				proto.speed = speed;
			}
		}
		updateVelocity();
#else
		// ---- BUGGY PATH: verbatim from shipped BulletEnemy.everyFrame ----
		if (angularVelocity != 0 || accel != 0) {
			direction += angularVelocity;
			speed += accel;
			if (speed < minSpeed) speed = minSpeed;
			if (speed > maxSpeed) speed = maxSpeed;
			updateVelocity();
		}
#end

		// ---- CHECKPOINT 3: post-updateVelocity values ----
		if (watched && frame >= 28 && frame <= 32) {
			trace('[CP3] bullet#$id frame=$frame  direction=$direction  vX=${r3(velocityX)}  vY=${r3(velocityY)}');
		}

		x += velocityX;
		y += velocityY;

		age += 1;
		if (lifetime > 0 && age >= lifetime) {
			destroy();
			return;
		}

		// ---- CHECKPOINT 4: watched bullet position over its lifetime ----
		if (watched && (frame % 10 == 0 || (frame >= 28 && frame <= 34))) {
			trace('[CP4] bullet#$id frame=$frame  pos=(${r1(x)}, ${r1(y)})  heading=$direction');
		}
	}

	static inline function r1(v:Float):Float return Math.round(v * 10) / 10;
	static inline function r3(v:Float):Float return Math.round(v * 1000) / 1000;
}

/** Replicates EmitterBase.spawn + BulletSubEmitter for headless bullets. */
class HeadlessWorld {
	public var bullets:Array<HeadlessBullet> = [];
	var nextId = 0;

	public function new() {}

	public function spawn(prototype:ShotPrototype, x:Float, y:Float):HeadlessBullet {
		var bullet = new HeadlessBullet(nextId++, prototype, x, y);
		bullets.push(bullet);

		// ---- CHECKPOINT 1: does the Sub attach fire? ----
		if (prototype.subCommands != null) {
			trace('[CP1] EmitterBase.spawn: bullet#${bullet.id} prototype.subCommands != null -> ATTACHING, length=${prototype.subCommands.length}');
			var subProto = prototype.clone();
			subProto.subCommands = null;
			var runner = new ScriptRunner(new HeadlessSubEmitter(bullet, this), prototype.subCommands, subProto);
			bullet.attachScript(runner);
		} else {
			trace('[CP1] EmitterBase.spawn: bullet#${bullet.id} prototype.subCommands == null -> no script attached');
		}
		return bullet;
	}
}

class HeadlessEnemyEmitter implements IShotEmitter {
	var world:HeadlessWorld;

	public function new(world:HeadlessWorld) this.world = world;

	public function getOriginX():Float return 400;

	public function getOriginY():Float return 100;

	public function getTarget():ShotTarget return {x: 400, y: 500};

	public function spawn(prototype:ShotPrototype, x:Float, y:Float):Void world.spawn(prototype, x, y);

	public function isAlive():Bool return true;

	public function vanish():Void {}
}

class HeadlessSubEmitter implements IShotEmitter {
	var bullet:HeadlessBullet;
	var world:HeadlessWorld;

	public function new(bullet:HeadlessBullet, world:HeadlessWorld) {
		this.bullet = bullet;
		this.world = world;
	}

	public function getOriginX():Float return bullet.x;

	public function getOriginY():Float return bullet.y;

	public function getTarget():ShotTarget return {x: 400, y: 500};

	public function spawn(prototype:ShotPrototype, x:Float, y:Float):Void world.spawn(prototype, x, y);

	public function isAlive():Bool return bullet.alive;

	public function vanish():Void bullet.destroy();
}

class DebugShifter {
	public static function main() {
#if fixed
		trace("=== shifter debug run: FIXED everyFrame (prototype sync + unconditional updateVelocity) ===");
#else
		trace("=== shifter debug run: SHIPPED (buggy) everyFrame ===");
#end
		var patternJson:Dynamic = Json.parse(sys.io.File.getContent("Assets/patterns/shifter.json"));

		// Resolve pattern defaults the same way PatternLoader does.
		var params:Map<String, Dynamic> = new Map();
		var paramDefs:Dynamic = patternJson.parameters;
		if (paramDefs != null)
			for (f in Reflect.fields(paramDefs))
				params.set(f, Reflect.field(Reflect.field(paramDefs, f), "default"));

		var commands:Array<IShotCommand> = CommandRegistry.compileList(patternJson.script, new CompileContext(params));

		var world = new HeadlessWorld();
		var enemyRunner = new ScriptRunner(new HeadlessEnemyEmitter(world), commands);

		// Watch the 3rd stream bullet (spawned around global frame 9) across
		// its own lifetime -- its kink should come ~30 frames after ITS spawn,
		// i.e. around global frame 39, not a fixed global frame.
		var watchedId = 2;

		for (globalFrame in 0...70) {
			enemyRunner.update();
			for (b in world.bullets) {
				if (b.id == watchedId && !b.watched) b.watched = true;
				// Silence checkpoint 1 spam from later spawns after we have a few.
				b.everyFrame();
			}
			if (world.bullets.length >= 6 && globalFrame < 40) continue;
		}

		var w = world.bullets[watchedId];
		trace('=== summary: watched bullet#$watchedId final pos=(${Math.round(w.x)}, ${Math.round(w.y)}) after ${w.frame} frames ===');

		// --- regression check: curving bullet WITH a sub-script (flower seed) ---
		// The prototype sync must not freeze angularVelocity accumulation.
		var seedProto = new ShotPrototype();
		seedProto.direction = 0;
		seedProto.speed = 2.5;
		seedProto.angularVelocity = 1.5;
		var seed = new HeadlessBullet(999, seedProto, 0, 0);
		var idleSub:Array<IShotCommand> = CommandRegistry.compileList(Json.parse('[{"control": "Wait", "frames": 60}]'), new CompileContext(new Map()));
		seed.attachScript(new ScriptRunner(new HeadlessSubEmitter(seed, world), idleSub, seedProto.clone()));
		for (i in 0...40) seed.everyFrame();
		// 40 frames at 1.5 deg/frame -> direction should have accumulated 60 deg.
		trace('=== curving+scripted seed after 40 frames: expected heading 60, pos moved off-axis: pos=(${Math.round(seed.x)}, ${Math.round(seed.y)}) ===');
	}
}
