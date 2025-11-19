package enemy;

import enemy.Enemy;

// Movement action types
enum MovementAction {
	SetVelocity(vx:Float, vy:Float);
	Wait(frames:Int);
	Stop;
}

class MovementScript {
	private var enemy:Enemy;
	private var actions:Array<MovementAction>;
	private var currentActionIndex:Int = 0;
	private var waitFramesRemaining:Int = 0;
	private var isActive:Bool = false;
	private var loop:Bool = false;

	public function new(enemy:Enemy, loop:Bool = false) {
		this.enemy = enemy;
		this.actions = new Array<MovementAction>();
		this.loop = loop;
	}

	public function addAction(action:MovementAction):Void {
		actions.push(action);
	}

	public function start():Void {
		isActive = true;
		currentActionIndex = 0;
		executeCurrentAction();
	}

	public function stop():Void {
		isActive = false;
	}

	public function update():Void {
		if (!isActive || actions.length == 0) return;

		// If we're waiting, count down
		if (waitFramesRemaining > 0) {
			waitFramesRemaining--;
			if (waitFramesRemaining == 0) {
				// Wait finished, move to next action
				nextAction();
			}
		}
	}

	private function executeCurrentAction():Void {
		if (currentActionIndex >= actions.length) {
			if (loop) {
				currentActionIndex = 0;
			} else {
				isActive = false;
				return;
			}
		}

		var action = actions[currentActionIndex];

		switch (action) {
			case SetVelocity(vx, vy):
				enemy.setVelocity(vx, vy);
				nextAction(); // Immediately go to next action

			case Wait(frames):
				waitFramesRemaining = frames;
				// Don't go to next action yet, wait for frames to count down

			case Stop:
				enemy.setVelocity(0, 0);
				nextAction(); // Immediately go to next action
		}
	}

	private function nextAction():Void {
		currentActionIndex++;
		executeCurrentAction();
	}

	public function isRunning():Bool {
		return isActive;
	}
}