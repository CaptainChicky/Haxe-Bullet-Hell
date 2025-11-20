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
	Concurrent(branches:Array<Array<ShootingAction>>); // Run multiple action sequences in parallel
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

// Branch executor for concurrent execution - independent state + context
class ConcurrentBranch {
	public var contextStack:Array<ExecutionContext>;
	public var state:ScriptState;
	public var waitFrames:Float = 0;
	public var isComplete:Bool = false;

	public function new(actions:Array<ShootingAction>, baseState:ScriptState) {
		// Each branch gets its own state copy
		this.state = new ScriptState();
		this.state.currentAngle = baseState.currentAngle;
		this.state.currentSpeed = baseState.currentSpeed;
		this.state.offsetDistance = baseState.offsetDistance;
		this.state.offsetAngle = baseState.offsetAngle;

		// Initialize with root context
		this.contextStack = [new ExecutionContext(actions, 1)];
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
	private var concurrentBranches:Array<ConcurrentBranch> = null; // Active when in concurrent mode

	public var isPaused:Bool = false;

	public function new(enemy:Enemy, actions:Array<ShootingAction>, collisionManager:Dynamic) {
		this.enemy = enemy;
		this.collisionManager = collisionManager;
		this.state = new ScriptState();

		// Initialize with root context (executes once, not a loop)
		this.contextStack = [new ExecutionContext(actions, 1)];

		// trace("ShootingScript created with " + actions.length + " actions");
		// if (actions.length > 0) {
		//  	trace("First action type: " + actions[0]);
		// }
	}

	public function update():Void {
		if (isPaused || !isActive) return;

		// Check if we're in concurrent mode
		if (concurrentBranches != null) {
			updateConcurrent();
			return;
		}

		// Normal single-threaded execution
		updateSingle();
	}

	private function updateSingle():Void {
		// Start with a full frame budget (1.0 frame of time to spend)
		var frameBudget:Float = 1.0;

		// Handle waiting - consume frame budget
		if (waitFrames > 0) {
			var timeSpent = Math.min(waitFrames, frameBudget);
			waitFrames -= timeSpent;
			frameBudget -= timeSpent;

			// If still waiting, we've used up time
			if (waitFrames > 0) {
				return;
			}

			// If we used all the budget completing the wait, return and continue next frame
			if (frameBudget <= 0) {
				return;
			}
			// Otherwise, we have frameBudget remaining to process actions
		}

		// Process actions until we hit a Wait or run out of frame budget
		// This allows multiple actions (and waits) to execute in the same frame
		var actionsThisFrame = 0;
		while (frameBudget > 0 && actionsThisFrame < 1000) {
			actionsThisFrame++;
			// Check if we have any contexts to execute
			if (contextStack.length == 0) {
				// trace("Context stack empty, deactivating pattern");
				isActive = false;
				return;
			}

			// Get the current (top of stack) execution context
			var ctx = contextStack[contextStack.length - 1];

			// if (actionsThisFrame == 1) {
			//  	trace("Frame action processing: currentIndex=" + ctx.currentIndex + " of " + ctx.actions.length + " actions, iterationCount=" + ctx.iterationCount + "/" + ctx.maxIterations);
			// }

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

	private function updateConcurrent():Void {
		// Process all concurrent branches, each gets full frame budget
		for (branch in concurrentBranches) {
			if (branch.isComplete) continue;

			processBranch(branch);
		}

		// Check if all branches are complete
		var allComplete = true;
		for (branch in concurrentBranches) {
			if (!branch.isComplete) {
				allComplete = false;
				break;
			}
		}

		if (allComplete) {
			// Exit concurrent mode and advance parent context
			concurrentBranches = null;
			var ctx = contextStack[contextStack.length - 1];
			ctx.currentIndex++;
		}
	}

	private function processBranch(branch:ConcurrentBranch):Void {
		var frameBudget:Float = 1.0;

		// Handle waiting - consume frame budget
		if (branch.waitFrames > 0) {
			var timeSpent = Math.min(branch.waitFrames, frameBudget);
			branch.waitFrames -= timeSpent;
			frameBudget -= timeSpent;

			if (branch.waitFrames > 0) {
				return;
			}

			// If we used all the budget completing the wait, return and continue next frame
			if (frameBudget <= 0) {
				return;
			}
		}

		// Process actions until we hit a Wait or run out of frame budget
		var actionsThisFrame = 0;
		while (frameBudget > 0 && actionsThisFrame < 1000) {
			actionsThisFrame++;
			// Check if we have any contexts to execute
			if (branch.contextStack.length == 0) {
				branch.isComplete = true;
				return;
			}

			// Get the current (top of stack) execution context
			var ctx = branch.contextStack[branch.contextStack.length - 1];

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
						branch.contextStack.pop();

						// If stack is now empty, this branch is complete
						if (branch.contextStack.length == 0) {
							branch.isComplete = true;
							return;
						}

						// Otherwise, advance the parent context's index
						var parentCtx = branch.contextStack[branch.contextStack.length - 1];
						parentCtx.currentIndex++;
					}
				}
				continue;
			}

			// Execute the current action on this branch
			var action = ctx.actions[ctx.currentIndex];
			executeActionOnBranch(action, branch);

			// If we just set a wait, consume frame budget
			if (branch.waitFrames > 0) {
				var timeSpent = Math.min(branch.waitFrames, frameBudget);
				branch.waitFrames -= timeSpent;
				frameBudget -= timeSpent;

				if (branch.waitFrames > 0) {
					return;
				}
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

			case Concurrent(branches):
				// Enter concurrent mode - create branches with independent state
				concurrentBranches = [];
				for (branchActions in branches) {
					var branch = new ConcurrentBranch(branchActions, state);
					concurrentBranches.push(branch);
				}
				// Don't increment parent index - will happen when all branches complete

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
				// trace("Executing NWay: count=" + count + ", angle=" + angle + ", speed=" + speed);
				fireNWay(count, angle, speed);
				ctx.currentIndex++;
		}
	}

	private function executeActionOnBranch(action:ShootingAction, branch:ConcurrentBranch):Void {
		var ctx = branch.contextStack[branch.contextStack.length - 1];

		switch (action) {
			case Fire(angle, speed):
				// Use branch state values when parameters are 0
				var useAngle = (angle == 0) ? branch.state.currentAngle : angle;
				var useSpeed = (speed == 0) ? branch.state.currentSpeed : speed;
				fireBulletWithState(useAngle, useSpeed, branch.state);
				ctx.currentIndex++;

			case Wait(frames):
				branch.waitFrames = frames;
				ctx.currentIndex++;

			case Loop(actions):
				// Push a new context for infinite loop
				var loopCtx = new ExecutionContext(actions, -1);
				branch.contextStack.push(loopCtx);

			case Rep(count, actions):
				// Push a new context for repeated execution
				var repCtx = new ExecutionContext(actions, count);
				branch.contextStack.push(repCtx);

			case Concurrent(branches):
				// Nested concurrent not supported - ignore
				trace("Warning: Nested Concurrent not supported");
				ctx.currentIndex++;

			case SetAngle(value):
				branch.state.currentAngle = value;
				ctx.currentIndex++;

			case AddAngle(delta):
				branch.state.currentAngle += delta;
				ctx.currentIndex++;

			case SetSpeed(value):
				branch.state.currentSpeed = value;
				ctx.currentIndex++;

			case AddSpeed(delta):
				branch.state.currentSpeed += delta;
				ctx.currentIndex++;

			case SetOffset(distance, angle):
				branch.state.offsetDistance = distance;
				branch.state.offsetAngle = angle;
				ctx.currentIndex++;

			case AddOffset(distanceDelta, angleDelta):
				branch.state.offsetDistance += distanceDelta;
				branch.state.offsetAngle += angleDelta;
				ctx.currentIndex++;

			case CopyAngleToOffset:
				branch.state.offsetAngle = branch.state.currentAngle;
				ctx.currentIndex++;

			case CopyOffsetToAngle:
				branch.state.currentAngle = branch.state.offsetAngle;
				ctx.currentIndex++;

			case RandomSpeed(min, max):
				branch.state.currentSpeed = min + Math.random() * (max - min);
				ctx.currentIndex++;

			case RandomAngle(min, max):
				branch.state.currentAngle = min + Math.random() * (max - min);
				ctx.currentIndex++;

			case AimAtPlayer:
				// Calculate angle from spawn position to player
				var player:Player = getPlayer();
				if (player != null) {
					var spawnX = enemy.x;
					var spawnY = enemy.y;

					if (branch.state.offsetDistance > 0) {
						var offsetRad = branch.state.offsetAngle * Math.PI / 180;
						spawnX += Math.cos(offsetRad) * branch.state.offsetDistance;
						spawnY += Math.sin(offsetRad) * branch.state.offsetDistance;
					}

					var dx = player.x - spawnX;
					var dy = player.y - spawnY;
					branch.state.currentAngle = Math.atan2(dy, dx) * 180 / Math.PI;
				}
				ctx.currentIndex++;

			case Radial(count, speed):
				fireRadialWithState(count, speed, branch.state);
				ctx.currentIndex++;

			case NWay(count, angle, speed):
				fireNWayWithState(count, angle, speed, branch.state);
				ctx.currentIndex++;
		}
	}

	private function fireBullet(angle:Float, speed:Float):Void {
		fireBulletWithState(angle, speed, state);
	}

	private function fireBulletWithState(angle:Float, speed:Float, bulletState:ScriptState):Void {
		// trace("fireBulletWithState called: angle=" + angle + ", speed=" + speed + ", enemy.x=" + enemy.x + ", enemy.y=" + enemy.y);
		var bullet = new BulletEnemy();

		// Calculate spawn position with offset
		var spawnX = enemy.x;
		var spawnY = enemy.y;

		if (bulletState.offsetDistance > 0) {
			var offsetRad = bulletState.offsetAngle * Math.PI / 180;
			spawnX += Math.cos(offsetRad) * bulletState.offsetDistance;
			spawnY += Math.sin(offsetRad) * bulletState.offsetDistance;
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
		fireRadialWithState(count, speed, state);
	}

	private function fireRadialWithState(count:Int, speed:Float, bulletState:ScriptState):Void {
		var angleStep = 360.0 / count;
		var baseAngle = bulletState.currentAngle;
		var useSpeed = (speed == 0) ? bulletState.currentSpeed : speed;
		for (i in 0...count) {
			var angle = baseAngle + (i * angleStep);
			fireBulletWithState(angle, useSpeed, bulletState);
		}
	}

	private function fireNWay(count:Int, arcAngle:Float, speed:Float):Void {
		fireNWayWithState(count, arcAngle, speed, state);
	}

	private function fireNWayWithState(count:Int, arcAngle:Float, speed:Float, bulletState:ScriptState):Void {
		var baseAngle = bulletState.currentAngle;
		var useSpeed = (speed == 0) ? bulletState.currentSpeed : speed;

		// Special case: single bullet fires straight at baseAngle
		if (count == 1) {
			fireBulletWithState(baseAngle, useSpeed, bulletState);
			return;
		}

		var startAngle = baseAngle - (arcAngle / 2);
		var angleStep = arcAngle / (count - 1);
		for (i in 0...count) {
			var angle = startAngle + (i * angleStep);
			fireBulletWithState(angle, useSpeed, bulletState);
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