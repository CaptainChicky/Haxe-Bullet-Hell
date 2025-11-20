package enemy;

import bullet.BulletEnemy;
import openfl.Lib;

// Simple shooting actions
enum ShootingAction {
	Fire(angle:Float, speed:Float);
	Wait(frames:Int);
	Loop(actions:Array<ShootingAction>);
	Rep(count:Int, actions:Array<ShootingAction>);
	SetAngle(value:Float);
	AddAngle(delta:Float);
	SetSpeed(value:Float);
	AddSpeed(delta:Float);
	Radial(count:Int, speed:Float);
	NWay(count:Int, angle:Float, speed:Float);
}

// Script state - tracks current angle and speed
class ScriptState {
	public var currentAngle:Float = 0;
	public var currentSpeed:Float = 5;

	public function new() {}
}

// Execution context for nested Loop/Rep structures
// This represents a single "frame" on the execution stack
class ExecutionContext {
	public var actions:Array<ShootingAction>; // The actions to execute in this context
	public var currentIndex:Int = 0; // Which action we're currently on
	public var iterationCount:Int = 0; // How many times have we iterated
	public var maxIterations:Int; // -1 for infinite Loop, N for Rep

	public function new(actions:Array<ShootingAction>, maxIterations:Int) {
		this.actions = actions;
		this.maxIterations = maxIterations;
	}
}

// Main script executor with proper stack-based execution
// NO array mutation - uses a stack of execution contexts
class ShootingScript {
	private var enemy:Enemy;
	private var collisionManager:Dynamic;
	private var contextStack:Array<ExecutionContext>; // Stack of execution contexts
	private var state:ScriptState; // Shared state (angle, speed)
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
		bullet.x = enemy.x;
		bullet.y = enemy.y;

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