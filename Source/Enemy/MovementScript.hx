package enemy;

import shot.GhostOrigin.IMovable;

// Movement action types
enum MovementAction {
	SetVelocity(vx:Float, vy:Float);
	Wait(frames:Int);
	Stop;
}

class MovementScript {
	private var target:IMovable;
	private var actions:Array<MovementAction>;
	private var currentActionIndex:Int = 0;
	private var waitFramesRemaining:Int = 0;
	private var isActive:Bool = false;
	private var isPaused:Bool = false;
	private var loop:Bool = false;

	public function new(target:IMovable, loop:Bool = false) {
		this.target = target;
		this.actions = new Array<MovementAction>();
		this.loop = loop;
	}

	public function addAction(action:MovementAction):Void {
		actions.push(action);
	}

	/** Redirect the script's velocity writes (e.g. to a GhostOrigin after death). */
	public function retarget(newTarget:IMovable):Void {
		target = newTarget;
	}

	/** Force loop off so a looping path plays once and leaves (ghost mode). */
	public function disableLoop():Void {
		loop = false;
	}

	public function start():Void {
		isActive = true;
		currentActionIndex = 0;
		executeCurrentAction();
	}

	public function stop():Void {
		isActive = false;
	}

	public function pause():Void {
		isPaused = true;
		// Stop enemy movement when pausing
		target.setVelocity(0, 0);
	}

	public function resume():Void {
		isPaused = false;
		// Re-execute current action to restore velocity if needed
		if (isActive && currentActionIndex < actions.length) {
			var action = actions[currentActionIndex];
			if (waitFramesRemaining == 0) {
				// Only restore velocity if not in the middle of a Wait
				switch (action) {
					case SetVelocity(vx, vy):
						target.setVelocity(vx, vy);
					case Stop:
						target.setVelocity(0, 0);
					case Wait(_):
						// Don't restore velocity during wait
				}
			}
		}
	}

	public function update():Void {
		if (!isActive || isPaused || actions.length == 0) return;

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
				target.setVelocity(vx, vy);
				nextAction(); // Immediately go to next action

			case Wait(frames):
				waitFramesRemaining = frames;
				// Don't go to next action yet, wait for frames to count down

			case Stop:
				target.setVelocity(0, 0);
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
