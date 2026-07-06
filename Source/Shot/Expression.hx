package shot;

/**
 * Resolves JSON script values: literals, "$param" references, arithmetic
 * (+ - * / with correct precedence, parentheses), function calls
 * (sin/cos in DEGREES), and inline randoms (random.between, random.angle).
 *
 * Implementation is a small recursive-descent parser producing an ExprNode
 * AST. Two evaluation modes:
 *
 *   - resolve()/evaluate(): parse + evaluate immediately (compile-time),
 *     the historical behavior. Used for structural values (Rep/Radial
 *     counts, Tween frame counts) that must be fixed at compile.
 *
 *   - compile() -> NumValue: DETERMINISTIC expressions are folded to a
 *     constant at compile time (identical cost + semantics to before);
 *     expressions containing a volatile call (any random.*) keep their AST
 *     and re-evaluate on every NumValue.get() - i.e. every command
 *     execution. {"control":"Set","prop":"speed","value":"random.between(2,6)"}
 *     inside a Loop therefore rolls a fresh speed per iteration.
 *
 * Functions:
 *   sin(deg), cos(deg)              - trig in degrees (engine-wide convention)
 *   random.between(min, max)        - uniform in [min, max)
 *   random.angle(n)                 - one of n evenly spaced angles:
 *                                     floor(random*n) * (360/n)
 */
enum ExprNode {
	EConst(v:Float);
	EParam(name:String);
	EBin(op:String, l:ExprNode, r:ExprNode);
	ENeg(e:ExprNode);
	ECall(name:String, args:Array<ExprNode>);
}

class Expression {
	/** Resolve a JSON value to a number using the given parameter map (compile-time). */
	public static function resolve(value:Dynamic, params:Map<String, Dynamic>):Float {
		if (value == null) return 0;
		if (Std.isOfType(value, String)) {
			return evaluate(cast value, params);
		}
		// Literal Int/Float.
		return cast value;
	}

	/** Evaluate a string expression immediately (compile-time semantics). */
	public static function evaluate(expr:String, params:Map<String, Dynamic>):Float {
		return eval(parse(expr), params);
	}

	/**
	 * Compile a JSON value into a NumValue. Deterministic expressions fold
	 * to a constant; volatile ones (containing random.*) re-evaluate per get().
	 */
	public static function compile(value:Dynamic, params:Map<String, Dynamic>):NumValue {
		if (value == null) return NumValue.of(0);
		if (!Std.isOfType(value, String)) return NumValue.of(cast value);
		var node = parse(cast value);
		if (isVolatile(node, params)) return NumValue.dynamicOf(node, params);
		return NumValue.of(eval(node, params));
	}

	// ------------------------------------------------------------ evaluation

	public static function eval(node:ExprNode, params:Map<String, Dynamic>):Float {
		return switch (node) {
			case EConst(v): v;
			case EParam(name):
				if (params.exists(name)) {
					var raw:Dynamic = params.get(name);
					Std.isOfType(raw, String) ? evaluate(cast raw, params) : cast raw;
				} else {
					trace("Expression: parameter not found: " + name);
					0;
				}
			case ENeg(e): -eval(e, params);
			case EBin(op, l, r):
				var a = eval(l, params);
				var b = eval(r, params);
				switch (op) {
					case "+": a + b;
					case "-": a - b;
					case "*": a * b;
					default: a / b;
				}
			case ECall(name, args):
				call(name, [for (a in args) eval(a, params)]);
		}
	}

	private static function call(name:String, args:Array<Float>):Float {
		inline function arg(i:Int):Float
			return i < args.length ? args[i] : 0;
		return switch (name) {
			case "sin": Math.sin(arg(0) * Math.PI / 180);
			case "cos": Math.cos(arg(0) * Math.PI / 180);
			case "random.between": arg(0) + Math.random() * (arg(1) - arg(0));
			case "random.angle":
				var n = Std.int(arg(0));
				(n <= 0) ? 0 : Math.floor(Math.random() * n) * (360.0 / n);
			default:
				trace("Expression: unknown function: " + name);
				0;
		}
	}

	/** True if evaluating the node twice can give different results. */
	private static function isVolatile(node:ExprNode, params:Map<String, Dynamic>):Bool {
		return switch (node) {
			case EConst(_): false;
			case EParam(name):
				// A parameter whose raw value is itself a string expression
				// may contain a random call.
				if (params.exists(name)) {
					var raw:Dynamic = params.get(name);
					Std.isOfType(raw, String) ? isVolatile(parse(cast raw), params) : false;
				} else false;
			case ENeg(e): isVolatile(e, params);
			case EBin(_, l, r): isVolatile(l, params) || isVolatile(r, params);
			case ECall(name, args):
				if (StringTools.startsWith(name, "random")) true;
				else {
					var v = false;
					for (a in args) if (isVolatile(a, params)) v = true;
					v;
				}
		}
	}

	// ------------------------------------------------------------ parsing

	public static function parse(expr:String):ExprNode {
		var s = StringTools.replace(expr, " ", "");
		if (s.length == 0) return EConst(0);
		var p = new ExprParser(s);
		var node = p.parseExpr();
		if (!p.atEnd()) trace("Expression: unexpected trailing characters in: " + expr);
		return node;
	}
}

/**
 * A compiled numeric value: either a folded constant or a live expression
 * re-evaluated (re-rolling randoms) on every get(). Commands store these
 * instead of raw Floats so inline randomness works per execution.
 */
class NumValue {
	private var constant:Float = 0;
	private var node:ExprNode = null;
	private var params:Map<String, Dynamic> = null;

	private function new() {}

	public static function of(v:Float):NumValue {
		var n = new NumValue();
		n.constant = v;
		return n;
	}

	public static function dynamicOf(node:ExprNode, params:Map<String, Dynamic>):NumValue {
		var n = new NumValue();
		n.node = node;
		n.params = params;
		return n;
	}

	public function get():Float {
		return (node == null) ? constant : Expression.eval(node, params);
	}
}

private class ExprParser {
	private var s:String;
	private var pos:Int = 0;

	public function new(s:String) {
		this.s = s;
	}

	public function atEnd():Bool
		return pos >= s.length;

	private inline function peek():String
		return pos < s.length ? s.charAt(pos) : "";

	// expr := term (('+'|'-') term)*
	public function parseExpr():ExprNode {
		var node = parseTerm();
		while (peek() == "+" || peek() == "-") {
			var op = s.charAt(pos++);
			node = EBin(op, node, parseTerm());
		}
		return node;
	}

	// term := unary (('*'|'/') unary)*
	private function parseTerm():ExprNode {
		var node = parseUnary();
		while (peek() == "*" || peek() == "/") {
			var op = s.charAt(pos++);
			node = EBin(op, node, parseUnary());
		}
		return node;
	}

	// unary := ('-'|'+') unary | atom
	private function parseUnary():ExprNode {
		if (peek() == "-") {
			pos++;
			return ENeg(parseUnary());
		}
		if (peek() == "+") {
			pos++;
			return parseUnary();
		}
		return parseAtom();
	}

	// atom := '(' expr ')' | '$'ident | number | ident '(' args ')'
	private function parseAtom():ExprNode {
		var c = peek();
		if (c == "(") {
			pos++;
			var e = parseExpr();
			if (peek() == ")") pos++;
			else trace("Expression: missing closing parenthesis");
			return e;
		}
		if (c == "$") {
			pos++;
			return EParam(readIdent());
		}
		if (isDigit(c) || c == ".") {
			return EConst(readNumber());
		}
		if (isIdentStart(c)) {
			var name = readIdent();
			if (peek() == "(") {
				pos++;
				var args:Array<ExprNode> = [];
				if (peek() != ")") {
					args.push(parseExpr());
					while (peek() == ",") {
						pos++;
						args.push(parseExpr());
					}
				}
				if (peek() == ")") pos++;
				else trace("Expression: missing ) in call to " + name);
				return ECall(name, args);
			}
			trace("Expression: unexpected identifier '" + name + "' (parameters need a $ prefix)");
			return EConst(0);
		}
		trace("Expression: unexpected character '" + c + "'");
		pos++; // consume so a malformed input cannot loop forever
		return EConst(0);
	}

	/** Identifier chars: letters, digits, underscore, dot (random.between). */
	private function readIdent():String {
		var start = pos;
		while (pos < s.length) {
			var c = s.charAt(pos);
			if (isIdentStart(c) || isDigit(c) || c == ".") pos++;
			else break;
		}
		return s.substring(start, pos);
	}

	private function readNumber():Float {
		var start = pos;
		while (pos < s.length) {
			var c = s.charAt(pos);
			if (isDigit(c) || c == ".") pos++;
			else break;
		}
		var parsed = Std.parseFloat(s.substring(start, pos));
		return Math.isNaN(parsed) ? 0 : parsed;
	}

	private static inline function isDigit(c:String):Bool
		return c >= "0" && c <= "9";

	private static inline function isIdentStart(c:String):Bool
		return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_";
}
