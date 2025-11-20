package enemy;

import bullet.BulletEnemy;
import player.Player;
import openfl.Lib;

// Shooting actions with position, random, and aiming support
enum ShootingAction {
	Fire(angle:Float, speed:Float);
	Wait(frames:Float);
	Loop(actions:Array<ShootingAction>);
	Rep(count:Int, actions:Array<ShootingAction>);
	SetAngle(value:Float);
	AddAngle(delta:Float);
	SetSpeed(value:Float);
	AddSpeed(delta:Float);
	SetOffset(distance:Float, angle:Float); // Set spawn offset from enemy
	AddOffset(distanceDelta:Float, angleDelta:Float); // Add to spawn offset
	CopyAngleToOffset; // Copy currentAngle to offsetAngle
	CopyOffsetToAngle; // Copy offsetAngle to currentAngle
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
	private var waitFrames:Float = 0;
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

		// Start with a full frame budget (1.0 frame of time to spend)
		var frameBudget:Float = 1.0;

		// Handle waiting - consume frame budget
		if (waitFrames > 0) {
			var timeSpent = Math.min(waitFrames, frameBudget);
			waitFrames -= timeSpent;
			frameBudget -= timeSpent;

			// If still waiting, we've used up the whole frame
			if (waitFrames > 0) {
				return;
			}
			// Otherwise, we have frameBudget remaining to process actions
		}

		// Process actions until we hit a Wait or run out of frame budget
		// This allows multiple actions (and waits) to execute in the same frame
		while (frameBudget > 0) {
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
				continue; // Continue processing in the same frame
			}

			// Execute the current action
			var action = ctx.actions[ctx.currentIndex];
			executeAction(action);

			// If we just set a wait, consume frame budget
			if (waitFrames > 0) {
				var timeSpent = Math.min(waitFrames, frameBudget);
				waitFrames -= timeSpent;
				frameBudget -= timeSpent;

				// If still waiting, we've used up frame budget
				if (waitFrames > 0) {
					return;
				}
				// Otherwise continue with remaining frame budget
			}
		}
	}

	private function executeAction(action:ShootingAction):Void {
		var ctx = contextStack[contextStack.length - 1];

		switch (action) {
			case Fire(angle, speed):
				// Use state values when parameters are 0
				var useAngle = (angle == 0) ? state.currentAngle : angle;
				var useSpeed = (speed == 0) ? state.currentSpeed : speed;
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

			case CopyAngleToOffset:
				state.offsetAngle = state.currentAngle;
				ctx.currentIndex++;

			case CopyOffsetToAngle:
				state.currentAngle = state.offsetAngle;
				ctx.currentIndex++;

			case RandomSpeed(min, max):
				state.currentSpeed = min + Math.random() * (max - min);
				ctx.currentIndex++;

			case RandomAngle(min, max):
				state.currentAngle = min + Math.random() * (max - min);
				ctx.currentIndex++;

			case AimAtPlayer:
				// Calculate angle from spawn position (including offset) to player
				var player:Player = getPlayer();
				if (player != null) {
					// Calculate spawn position with offset
					var spawnX = enemy.x;
					var spawnY = enemy.y;

					if (state.offsetDistance > 0) {
						var offsetRad = state.offsetAngle * Math.PI / 180;
						spawnX += Math.cos(offsetRad) * state.offsetDistance;
						spawnY += Math.sin(offsetRad) * state.offsetDistance;
					}

					var dx = player.x - spawnX;
					var dy = player.y - spawnY;
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
		if (collisionManager != null) {
			try {
				return collisionManager.getPlayer();
			} catch (e:Dynamic) {
				trace("Failed to get player: " + e);
			}
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