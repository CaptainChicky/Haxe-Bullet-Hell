package shot;

/**
 * Resolves JSON script values: literals, "$param" references, and simple
 * arithmetic expressions ("$base + $spread", "$speed * 2").
 *
 * Extracted from PatternLoader so both pattern templates and inline level
 * scripts share one implementation. The old evaluator relied on
 * Array.indexOf to pair operators with operands, which broke whenever the
 * same value appeared twice in an expression; this version is a plain
 * sequential fold with correct * and / precedence.
 */
class Expression {
	/** Resolve a JSON value to a number using the given parameter map. */
	public static function resolve(value:Dynamic, params:Map<String, Dynamic>):Float {
		if (value == null) return 0;

		if (Std.isOfType(value, String)) {
			return evaluate(cast value, params);
		}

		// Literal Int/Float.
		return cast value;
	}

	/** Evaluate a string: bare number, "$param", or arithmetic expression. */
	public static function evaluate(expr:String, params:Map<String, Dynamic>):Float {
		expr = StringTools.replace(expr, " ", "");
		if (expr.length == 0) return 0;

		// Split into (term, op, term, op, term ...) on + and -.
		// A leading "-" negates the first term rather than acting as an operator.
		var terms:Array<String> = [];
		var ops:Array<String> = [];
		var current = "";
		for (i in 0...expr.length) {
			var c = expr.charAt(i);
			if ((c == "+" || c == "-") && current.length > 0) {
				terms.push(current);
				ops.push(c);
				current = "";
			} else {
				current += c;
			}
		}
		terms.push(current);

		var result = evaluateTerm(terms[0], params);
		for (i in 0...ops.length) {
			var t = evaluateTerm(terms[i + 1], params);
			result = (ops[i] == "+") ? result + t : result - t;
		}
		return result;
	}

	/** Evaluate a term containing only * and / (left to right). */
	private static function evaluateTerm(term:String, params:Map<String, Dynamic>):Float {
		var factors:Array<String> = [];
		var ops:Array<String> = [];
		var current = "";
		for (i in 0...term.length) {
			var c = term.charAt(i);
			if (c == "*" || c == "/") {
				factors.push(current);
				ops.push(c);
				current = "";
			} else {
				current += c;
			}
		}
		factors.push(current);

		var result = evaluateFactor(factors[0], params);
		for (i in 0...ops.length) {
			var f = evaluateFactor(factors[i + 1], params);
			result = (ops[i] == "*") ? result * f : result / f;
		}
		return result;
	}

	/** Evaluate an atom: "$param", "-$param", or a numeric literal. */
	private static function evaluateFactor(factor:String, params:Map<String, Dynamic>):Float {
		if (factor.length == 0) return 0;

		var negate = false;
		if (factor.charAt(0) == "-") {
			negate = true;
			factor = factor.substr(1);
		}

		var value:Float;
		if (factor.charAt(0) == "$") {
			var name = factor.substr(1);
			if (params.exists(name)) {
				var raw:Dynamic = params.get(name);
				value = Std.isOfType(raw, String) ? evaluate(cast raw, params) : cast raw;
			} else {
				trace("Expression: parameter not found: " + name);
				value = 0;
			}
		} else {
			var parsed = Std.parseFloat(factor);
			value = Math.isNaN(parsed) ? 0 : parsed;
		}

		return negate ? -value : value;
	}
}
