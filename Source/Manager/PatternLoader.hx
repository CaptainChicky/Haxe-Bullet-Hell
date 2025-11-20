package manager;

import enemy.ShootingScript.ShootingAction;
import openfl.Assets;
import haxe.Json;

typedef PatternTemplate = {
	var name:String;
	var description:String;
	var parameters:Dynamic;
	var script:Array<Dynamic>;
}

class PatternLoader {
	private static var loadedPatterns:Map<String, PatternTemplate> = new Map();

	// Load a pattern template from JSON file
	public static function loadPattern(patternName:String):PatternTemplate {
		// Check cache
		if (loadedPatterns.exists(patternName)) {
			return loadedPatterns.get(patternName);
		}

		// Load from file
		var path = "assets/patterns/" + patternName + ".json";

		try {
			var jsonText = Assets.getText(path);
			var template:PatternTemplate = Json.parse(jsonText);
			loadedPatterns.set(patternName, template);
			return template;
		} catch (e:Dynamic) {
			trace("Failed to load pattern: " + patternName + " - " + e);
			return null;
		}
	}

	// Parse pattern with parameter overrides
	public static function parsePattern(patternName:String, ?params:Dynamic):Array<ShootingAction> {
		var template = loadPattern(patternName);
		if (template == null) {
			return [];
		}

		// Build parameter map with defaults + overrides
		var paramMap:Map<String, Dynamic> = new Map();

		// Add defaults from template
		if (template.parameters != null) {
			var paramFields = Reflect.fields(template.parameters);
			for (field in paramFields) {
				var paramDef:Dynamic = Reflect.field(template.parameters, field);
				var defaultValue = Reflect.field(paramDef, "default");
				if (defaultValue != null) {
					paramMap.set(field, defaultValue);
				}
			}
		}

		// Override with provided params
		if (params != null) {
			var overrideFields = Reflect.fields(params);
			for (field in overrideFields) {
				paramMap.set(field, Reflect.field(params, field));
			}
		}

		// Parse script actions
		return parseActions(template.script, paramMap);
	}

	// Parse array of action objects (public for inline scripts)
	public static function parseActions(scriptData:Array<Dynamic>, paramMap:Map<String, Dynamic>):Array<ShootingAction> {
		var actions:Array<ShootingAction> = [];

		for (actionData in scriptData) {
			var action = parseAction(actionData, paramMap);
			if (action != null) {
				actions.push(action);
			}
		}

		return actions;
	}

	// Parse a single action object
	private static function parseAction(actionData:Dynamic, paramMap:Map<String, Dynamic>):ShootingAction {
		var control:String = actionData.control;

		switch (control) {
			case "Fire":
				var angle:Float = resolveValue(actionData.angle, paramMap);
				var speed:Float = resolveValue(actionData.speed, paramMap);
				return Fire(angle, speed);

			case "Wait":
				var frames:Int = cast resolveValue(actionData.frames, paramMap);
				return Wait(frames);

			case "Loop":
				var loopActions = parseActions(actionData.actions, paramMap);
				return Loop(loopActions);

			case "Rep":
				var count:Int = cast resolveValue(actionData.count, paramMap);
				var repActions = parseActions(actionData.actions, paramMap);
				return Rep(count, repActions);

			case "SetAngle":
				var value:Float = resolveValue(actionData.value, paramMap);
				return SetAngle(value);

			case "AddAngle":
				var delta:Float = resolveValue(actionData.delta, paramMap);
				return AddAngle(delta);

			case "SetSpeed":
				var value:Float = resolveValue(actionData.value, paramMap);
				return SetSpeed(value);

			case "AddSpeed":
				var delta:Float = resolveValue(actionData.delta, paramMap);
				return AddSpeed(delta);

			case "Radial":
				var count:Int = cast resolveValue(actionData.count, paramMap);
				var speed:Float = resolveValue(actionData.speed, paramMap);
				return Radial(count, speed);

			case "NWay":
				var count:Int = cast resolveValue(actionData.count, paramMap);
				var angle:Float = resolveValue(actionData.angle, paramMap);
				var speed:Float = resolveValue(actionData.speed, paramMap);
				return NWay(count, angle, speed);

			default:
				trace("Unknown control type: " + control);
				return null;
		}
	}

	// Resolve a value - could be literal or parameter reference
	private static function resolveValue(value:Dynamic, paramMap:Map<String, Dynamic>):Dynamic {
		if (value == null) return 0;

		// Check if it's a string parameter reference like "$bulletSpeed"
		if (Std.isOfType(value, String)) {
			var str:String = cast value;
			if (str.charAt(0) == "$") {
				var paramName = str.substr(1);

				// Handle special variables
				if (paramName == "currentAngle" || paramName == "currentSpeed") {
					// These are runtime state variables, return 0 as placeholder
					// They'll be resolved during execution
					return 0;
				}

				// Look up in param map
				if (paramMap.exists(paramName)) {
					return paramMap.get(paramName);
				}
				trace("Parameter not found: " + paramName);
				return 0;
			}
		}

		// Return literal value
		return value;
	}
}
