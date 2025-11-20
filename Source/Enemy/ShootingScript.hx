package enemy;

import bullet.BulletEnemy;
import openfl.Lib;

// Simple shooting actions based on _controls.json
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

	public function clone():ScriptState {
		var state = new ScriptState();
		state.currentAngle = this.currentAngle;
		state.currentSpeed = this.currentSpeed;
		return state;
	}
}

// Execution thread for a script
class ScriptThread {
	public var actions:Array<ShootingAction>;
	public var currentIndex:Int = 0;
	public var waitFrames:Int = 0;
	public var repStack:Array<Int> = [];
	public var isActive:Bool = true;
	public var state:ScriptState;

	public function new(actions:Array<ShootingAction>, state:ScriptState) {
		this.actions = actions;
		this.state = state;
	}
}

// Main script executor
class ShootingScript {
	private var enemy:Enemy;
	private var mainThread:ScriptThread;
	private var collisionManager:Dynamic;

	public var isPaused:Bool = false;

	public function new(enemy:Enemy, actions:Array<ShootingAction>, collisionManager:Dynamic) {
		this.enemy = enemy;
		this.collisionManager = collisionManager;

		var state = new ScriptState();
		this.mainThread = new ScriptThread(actions, state);
	}

	public function update():Void {
		if (isPaused || !mainThread.isActive) return;

		// Handle wait
		if (mainThread.waitFrames > 0) {
			mainThread.waitFrames--;
			return;
		}

		// Check if done
		if (mainThread.currentIndex >= mainThread.actions.length) {
			mainThread.isActive = false;
			return;
		}

		// Execute current action
		var action = mainThread.actions[mainThread.currentIndex];
		executeAction(mainThread, action);
	}

	private function executeAction(thread:ScriptThread, action:ShootingAction):Void {
		switch (action) {
			case Fire(angle, speed):
				// Use current state if values are 0
				var useAngle = (angle == 0 && speed == 0) ? thread.state.currentAngle : angle;
				var useSpeed = (angle == 0 && speed == 0) ? thread.state.currentSpeed : speed;
				fireBullet(useAngle, useSpeed);
				thread.currentIndex++;

			case Wait(frames):
				thread.waitFrames = frames;
				thread.currentIndex++;

			case Loop(actions):
				// Only append a new Loop AFTER the current iteration finishes
				var loopActions = actions.copy();
				thread.actions = thread.actions.slice(0, thread.currentIndex)
					.concat(loopActions)
					.concat([Loop(actions)]) // append loop as a single item
					.concat(thread.actions.slice(thread.currentIndex + 1));

			case Rep(count, actions):
				// If this is the FIRST time entering this Rep instruction, attach a counter to it.
				if (!Reflect.hasField(action, "___counter")) {
					Reflect.setField(action, "___counter", 0);
				}

				var current = Reflect.field(action, "___counter");

				if (current < count) {
					// Increase counter
					Reflect.setField(action, "___counter", current + 1);

					// Build injected list
					var injected = actions.copy();

					// If more loops remain, append THIS SAME Rep action again
					if (current + 1 < count) {
						injected.push(action);
					}

					// Replace this Rep with injected sequence
					thread.actions = thread.actions.slice(0, thread.currentIndex)
						.concat(injected)
						.concat(thread.actions.slice(thread.currentIndex + 1));

					// Important: do NOT advance index
				} else {
					// Finished the Rep — delete its counter and move on
					Reflect.deleteField(action, "___counter");
					thread.currentIndex++;
				}

			case SetAngle(value):
				thread.state.currentAngle = value;
				thread.currentIndex++;

			case AddAngle(delta):
				thread.state.currentAngle += delta;
				thread.currentIndex++;

			case SetSpeed(value):
				thread.state.currentSpeed = value;
				thread.currentIndex++;

			case AddSpeed(delta):
				thread.state.currentSpeed += delta;
				thread.currentIndex++;

			case Radial(count, speed):
				fireRadial(count, speed);
				thread.currentIndex++;

			case NWay(count, angle, speed):
				fireNWay(count, angle, speed);
				thread.currentIndex++;
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
		var baseAngle = mainThread.state.currentAngle;
		var useSpeed = (speed == 0) ? mainThread.state.currentSpeed : speed;
		for (i in 0...count) {
			var angle = baseAngle + (i * angleStep);
			fireBullet(angle, useSpeed);
		}
	}

	private function fireNWay(count:Int, arcAngle:Float, speed:Float):Void {
		var baseAngle = mainThread.state.currentAngle;
		var startAngle = baseAngle - (arcAngle / 2);
		var angleStep = arcAngle / (count - 1);
		var useSpeed = (speed == 0) ? mainThread.state.currentSpeed : speed;
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
		mainThread.isActive = false;
	}
}
