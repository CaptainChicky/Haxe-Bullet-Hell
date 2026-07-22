package manager;

import shot.ShotCommand.IShotCommand;
import shot.CommandRegistry;
import shot.FlowCommands.WaitCommand;
import haxe.Json;

typedef PatternTemplate = {
	var name:String;
	var description:String;
	var parameters:Dynamic;
	var script:Array<Dynamic>;
}

/**
 * Loads pattern template JSON files and compiles them (with parameter
 * defaults + overrides) into executable command lists.
 *
 * All knowledge of individual controls lives in shot.CommandRegistry;
 * this class only handles file loading, caching, and parameter merging.
 */
class PatternLoader {
	private static var loadedPatterns:Map<String, PatternTemplate> = new Map();

	/** Load (and cache) a pattern template from Assets. */
	public static function loadPattern(patternName:String):PatternTemplate {
		if (loadedPatterns.exists(patternName)) {
			return loadedPatterns.get(patternName);
		}

		var path = "assets/patterns/" + patternName + ".json";
		try {
			// Release builds ship the sealed .dat form; SecureAssets picks it.
			var jsonText = SecureAssets.getText(path);
			if (jsonText == null) throw "asset not found";
			var template:PatternTemplate = Json.parse(jsonText);
			loadedPatterns.set(patternName, template);
			return template;
		} catch (e:Dynamic) {
			trace("Failed to load pattern: " + patternName + " - " + e);
			return null;
		}
	}

	/** Compile a named pattern template with optional parameter overrides. */
	public static function parsePattern(patternName:String, ?params:Dynamic):Array<IShotCommand> {
		var template = loadPattern(patternName);
		if (template == null) {
			return [];
		}

		var paramMap = buildParamMap(template.parameters, params);
		var commands = CommandRegistry.compileList(template.script, new CompileContext(paramMap));

		applyStartDelay(commands, params);
		return commands;
	}

	/** Compile an inline script (e.g. embedded in level JSON). */
	public static function parseInline(scriptData:Array<Dynamic>, ?params:Dynamic):Array<IShotCommand> {
		var paramMap = buildParamMap(null, params);
		var commands = CommandRegistry.compileList(scriptData, new CompileContext(paramMap));

		applyStartDelay(commands, params);
		return commands;
	}

	/** Merge template parameter defaults with caller overrides. */
	private static function buildParamMap(templateParams:Dynamic, overrides:Dynamic):Map<String, Dynamic> {
		var paramMap:Map<String, Dynamic> = new Map();

		if (templateParams != null) {
			for (field in Reflect.fields(templateParams)) {
				var paramDef:Dynamic = Reflect.field(templateParams, field);
				var defaultValue = Reflect.field(paramDef, "default");
				if (defaultValue != null) {
					paramMap.set(field, defaultValue);
				}
			}
		}

		if (overrides != null) {
			for (field in Reflect.fields(overrides)) {
				paramMap.set(field, Reflect.field(overrides, field));
			}
		}

		return paramMap;
	}

	/** If the config declares a startDelay, prepend a Wait. */
	private static function applyStartDelay(commands:Array<IShotCommand>, params:Dynamic):Void {
		if (params == null || !Reflect.hasField(params, "startDelay")) return;
		var startDelay:Float = Reflect.field(params, "startDelay");
		if (startDelay > 0) {
			commands.unshift(new WaitCommand(shot.Expression.NumValue.of(startDelay)));
		}
	}
}
