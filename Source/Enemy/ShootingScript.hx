package enemy;

import bullet.BulletEnemy;
import player.Player;
import openfl.Lib;

// Shooting actions with position, random, and aiming support
enum ShootingAction {
	Fire(angle:Float, speed:Float);
	Wait(frames:Int);
	Loop(actions:Array<ShootingAction>);
	Rep(count:Int, actions:Array<ShootingAction>);
	SetAngle(value:Float);
	AddAngle(delta:Float);
	SetSpeed(value:Float);
	AddSpeed(delta:Float);
	SetOffset(distance:Float, angle:Float); // Set spawn offset from enemy
	AddOffset(distanceDelta:Float, angleDelta:Float); // Add to spawn offset
	RandomSpeed(min:Float, max:Float); // Randomize speed
	RandomAngle(min:Float, max:Float); // Randomize angle
	AimAtPlayer; // Set angle toward player
	Radial(count:Int, speed:Float);
	NWay(count:Int, angle:Float, speed:Float);
}

// Script state - tracks current angle, speed, and spawn offset
class ScriptState {
	public var currentAngle:Float = 0;
	public var currentSpeed:Float = 5;
	public var offsetDistance:Float = 0; // Distance from enemy center to spawn bullet
	public var offsetAngle:Float = 0; // Angle (bearing) for the offset position

	public function new() {}
}

// Execution context for nested Loop/Rep structures
class ExecutionContext {
	public var actions:Array<ShootingAction>;
	public var currentIndex:Int = 0;
	public var iterationCount:Int = 0;
	public var maxIterations:Int; // -1 for infinite Loop, N for Rep

	public function new(actions:Array<ShootingAction>, maxIterations:Int) {
		this.actions = actions;
		this.maxIterations = maxIterations;
	}
}

// Main script executor with position, random, and aiming support
class ShootingScript {
	private var enemy:Enemy;
	private var collisionManager:Dynamic;
	private var contextStack:Array<ExecutionContext>;
	private var state:ScriptState;
	private var waitFrames:Int = 0;
	private var isActive:Bool = true;

	public var isPaused:Bool = false;

	public function new(enemy:Enemy, actions:Array<ShootingAction>, collisionManager:Dynamic) {
		this.enemy = enemy;
		this.collisionManager = collisionManager;
		this.state = new ScriptState();

		// Initialize with root context (executes once, not a loop)
		this.contextStack = [new ExecutionContext(actions, 1)];
	}

	public function update():Void {
		if (isPaused || !isActive) return;

		// Handle wait
		if (waitFrames > 0) {
			waitFrames--;
			return;
		}

		// Check if we have any contexts to execute
		if (contextStack.length == 0) {
			isActive = false;
			return;
		}

		// Get the current (top of stack) execution context
		var ctx = contextStack[contextStack.length - 1];

		// Check if current context has finished all its actions
		if (ctx.currentIndex >= ctx.actions.length) {
			// Finished all actions in this context
			if (ctx.maxIterations == -1) {
				// Infinite loop - restart this context
				ctx.currentIndex = 0;
				ctx.iterationCount++;
			} else {
				// Finite repetition - check if we need to repeat
				ctx.iterationCount++;
				if (ctx.iterationCount < ctx.maxIterations) {
					// Need to repeat - restart this context
					ctx.currentIndex = 0;
				} else {
					// Done with all iterations - pop this context off the stack
					contextStack.pop();

					// If stack is now empty, we're completely done
					if (contextStack.length == 0) {
						isActive = false;
						return;
					}

					// Otherwise, advance the parent context's index
					var parentCtx = contextStack[contextStack.length - 1];
					parentCtx.currentIndex++;
				}
			}
			return; // Wait for next frame to continue
		}

		// Execute the current action
		var action = ctx.actions[ctx.currentIndex];
		executeAction(action);
	}

	private function executeAction(action:ShootingAction):Void {
		var ctx = contextStack[contextStack.length - 1];

		switch (action) {
			case Fire(angle, speed):
				// Use current state if both angle and speed are 0
				var useAngle = (angle == 0 && speed == 0) ? state.currentAngle : angle;
				var useSpeed = (angle == 0 && speed == 0) ? state.currentSpeed : speed;
				fireBullet(useAngle, useSpeed);
				ctx.currentIndex++;

			case Wait(frames):
				waitFrames = frames;
				ctx.currentIndex++;

			case Loop(actions):
				// Push a new context for infinite loop (maxIterations = -1)
				var loopCtx = new ExecutionContext(actions, -1);
				contextStack.push(loopCtx);
				// Don't increment parent index - will happen when loop exits (never for infinite)

			case Rep(count, actions):
				// Push a new context for repeated execution (maxIterations = count)
				var repCtx = new ExecutionContext(actions, count);
				contextStack.push(repCtx);
				// Don't increment parent index - will happen when all reps are done

			case SetAngle(value):
				state.currentAngle = value;
				ctx.currentIndex++;

			case AddAngle(delta):
				state.currentAngle += delta;
				ctx.currentIndex++;

			case SetSpeed(value):
				state.currentSpeed = value;
				ctx.currentIndex++;

			case AddSpeed(delta):
				state.currentSpeed += delta;
				ctx.currentIndex++;

			case SetOffset(distance, angle):
				state.offsetDistance = distance;
				state.offsetAngle = angle;
				ctx.currentIndex++;

			case AddOffset(distanceDelta, angleDelta):
				state.offsetDistance += distanceDelta;
				state.offsetAngle += angleDelta;
				ctx.currentIndex++;

			case RandomSpeed(min, max):
				state.currentSpeed = min + Math.random() * (max - min);
				ctx.currentIndex++;

			case RandomAngle(min, max):
				state.currentAngle = min + Math.random() * (max - min);
				ctx.currentIndex++;

			case AimAtPlayer:
				// Calculate angle from enemy to player
				var player:Player = getPlayer();
				if (player != null) {
					var dx = player.x - enemy.x;
					var dy = player.y - enemy.y;
					state.currentAngle = Math.atan2(dy, dx) * 180 / Math.PI;
				}
				ctx.currentIndex++;

			case Radial(count, speed):
				fireRadial(count, speed);
				ctx.currentIndex++;

			case NWay(count, angle, speed):
				fireNWay(count, angle, speed);
				ctx.currentIndex++;
		}
	}

	private function fireBullet(angle:Float, speed:Float):Void {
		var bullet = new BulletEnemy();

		// Calculate spawn position with offset
		var spawnX = enemy.x;
		var spawnY = enemy.y;

		if (state.offsetDistance > 0) {
			var offsetRad = state.offsetAngle * Math.PI / 180;
			spawnX += Math.cos(offsetRad) * state.offsetDistance;
			spawnY += Math.sin(offsetRad) * state.offsetDistance;
		}

		bullet.x = spawnX;
		bullet.y = spawnY;

		var angleRad = angle * Math.PI / 180;
		bullet.velocityX = Math.cos(angleRad) * speed;
		bullet.velocityY = Math.sin(angleRad) * speed;

		Lib.current.addChild(bullet);

		if (collisionManager != null) {
			collisionManager.registerEnemyBullet(bullet);
		}
	}

	private function fireRadial(count:Int, speed:Float):Void {
		var angleStep = 360.0 / count;
		var baseAngle = state.currentAngle;
		var useSpeed = (speed == 0) ? state.currentSpeed : speed;
		for (i in 0...count) {
			var angle = baseAngle + (i * angleStep);
			fireBullet(angle, useSpeed);
		}
	}

	private function fireNWay(count:Int, arcAngle:Float, speed:Float):Void {
		var baseAngle = state.currentAngle;
		var startAngle = baseAngle - (arcAngle / 2);
		var angleStep = arcAngle / (count - 1);
		var useSpeed = (speed == 0) ? state.currentSpeed : speed;
		for (i in 0...count) {
			var angle = startAngle + (i * angleStep);
			fireBullet(angle, useSpeed);
		}
	}

	private function getPlayer():Player {
		// Get player from collision manager
		if (collisionManager != null && Reflect.hasField(collisionManager, "getPlayer")) {
			return Reflect.callMethod(collisionManager, Reflect.field(collisionManager, "getPlayer"), []);
		}
		return null;
	}

	public function pause():Void {
		isPaused = true;
	}

	public function resume():Void {
		isPaused = false;
	}

	public function stop():Void {
		isActive = false;
	}
}
