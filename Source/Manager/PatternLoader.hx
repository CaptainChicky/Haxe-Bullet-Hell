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
				var frames:Float = resolveValue(actionData.frames, paramMap);
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

			case "SetOffset":
				var distance:Float = resolveValue(actionData.distance, paramMap);
				var angle:Float = resolveValue(actionData.angle, paramMap);
				return SetOffset(distance, angle);

			case "AddOffset":
				var distanceDelta:Float = resolveValue(actionData.distanceDelta, paramMap);
				var angleDelta:Float = resolveValue(actionData.angleDelta, paramMap);
				return AddOffset(distanceDelta, angleDelta);

			case "CopyAngleToOffset":
				return CopyAngleToOffset;

			case "CopyOffsetToAngle":
				return CopyOffsetToAngle;

			case "RandomSpeed":
				var min:Float = resolveValue(actionData.min, paramMap);
				var max:Float = resolveValue(actionData.max, paramMap);
				return RandomSpeed(min, max);

			case "RandomAngle":
				var min:Float = resolveValue(actionData.min, paramMap);
				var max:Float = resolveValue(actionData.max, paramMap);
				return RandomAngle(min, max);

			case "AimAtPlayer":
				return AimAtPlayer;

			default:
				trace("Unknown control type: " + control);
				return null;
		}
	}

	// Resolve a value - could be literal or parameter reference
	private static function resolveValue(value:Dynamic, paramMap:Map<String, Dynamic>):Dynamic {
		if (value == null) return 0;

		// Check if it's a string parameter reference or expression
		if (Std.isOfType(value, String)) {
			var str:String = cast value;

			// Check for arithmetic expressions with +, -, *, or /
			if (str.indexOf("+") != -1 || str.indexOf("-") != -1 || str.indexOf("*") != -1 || str.indexOf("/") != -1) {
				return evaluateExpression(str, paramMap);
			}

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

	private static function evaluateExpression(expr:String, paramMap:Map<String, Dynamic>):Float {
		// Simple expression evaluator supporting +, -, *, /
		expr = StringTools.replace(expr, " ", ""); // Remove whitespace

		// First handle * and / (higher precedence)
		var terms:Array<String> = [];
		var currentTerm:String = "";

		var i = 0;
		while (i < expr.length) {
			var char = expr.charAt(i);

			if (char == "+" || char == "-") {
				if (currentTerm.length > 0) {
					terms.push(currentTerm);
					currentTerm = "";
				}
				terms.push(char);
				i++;
			} else {
				currentTerm += char;
				i++;
			}
		}
		if (currentTerm.length > 0) {
			terms.push(currentTerm);
		}

		// Evaluate each term (which may contain * or /)
		var evaluatedTerms:Array<Float> = [];
		for (term in terms) {
			if (term == "+" || term == "-") {
				evaluatedTerms.push(Math.NaN); // Use NaN as operator marker
			} else {
				evaluatedTerms.push(evaluateTerm(term, paramMap));
			}
		}

		// Now process + and - from left to right
		var result:Float = 0;
		var operation:String = "+";

		for (value in evaluatedTerms) {
			if (Math.isNaN(value)) {
				// This shouldn't happen in well-formed expressions
				continue;
			}
			result = (operation == "+") ? result + value : result - value;

			// Check if next is an operator
			var idx = evaluatedTerms.indexOf(value);
			if (idx + 1 < evaluatedTerms.length) {
				var next = evaluatedTerms[idx + 1];
				if (Math.isNaN(next)) {
					// Determine operation from terms array
					if (idx + 1 < terms.length && (terms[idx + 1] == "+" || terms[idx + 1] == "-")) {
						operation = terms[idx + 1];
					}
				}
			}
		}

		return result;
	}

	private static function evaluateTerm(term:String, paramMap:Map<String, Dynamic>):Float {
		// Evaluate a term that may contain * or /
		var factors:Array<String> = [];
		var currentFactor:String = "";

		var i = 0;
		while (i < term.length) {
			var char = term.charAt(i);

			if (char == "*" || char == "/") {
				if (currentFactor.length > 0) {
					factors.push(currentFactor);
					currentFactor = "";
				}
				factors.push(char);
				i++;
			} else {
				currentFactor += char;
				i++;
			}
		}
		if (currentFactor.length > 0) {
			factors.push(currentFactor);
		}

		// If no operators, just resolve the value
		if (factors.length == 1) {
			var val = resolveValue(factors[0], paramMap);
			return (val is Float) ? val : Std.parseFloat(Std.string(val));
		}

		// Evaluate * and / from left to right
		var result:Float = 0;
		var operation:String = "*";
		var firstValue = true;

		for (factor in factors) {
			if (factor == "*" || factor == "/") {
				operation = factor;
			} else {
				var val = resolveValue(factor, paramMap);
				var numVal:Float = (val is Float) ? val : Std.parseFloat(Std.string(val));

				if (firstValue) {
					result = numVal;
					firstValue = false;
				} else {
					result = (operation == "*") ? result * numVal : result / numVal;
				}
			}
		}

		return result;
	}
}