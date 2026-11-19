--!strict
-- THE TEXT EXAMPLES
--
-- The examples of examples.luau again, written in the text syntax and read by reader.luau. Each gives the same outcome as its builder version, so the reader and the builders are checked against each other.
--
-- rejects are sources that must not read. run.luau checks that each one raises an error.

const Reader = require "../interpreter/reader"
const VM = require "../interpreter/vm"

type Example = {
	name: string,
	program: VM.Expr,
	fuel: number,
	outcome: string,
	expect: string?,
}

const FUEL = 1e6

const function value(
	name: string,
	source: string,
	expect: string,
	fuel: number?
): Example
	return {
		name = name,
		program = Reader.parse(source),
		fuel = fuel or FUEL,
		outcome = "value",
		expect = expect,
	}
end

const function failure(
	name: string,
	source: string,
	outcome: string,
	fuel: number?
): Example
	return {
		name = name,
		program = Reader.parse(source),
		fuel = fuel or FUEL,
		outcome = outcome,
		expect = nil,
	}
end

const OMEGA = "((lam x (x x)) (lam x (x x)))"

-- The recursive functions of examples.luau, each written with fix.
const LENGTH = "(fix (lam rec (lam l (if (? l) 0 (+ 1 (rec (tail l)))))))"
const SUM = "(fix (lam rec (lam l (if (? l) 0 (+ (head l) (rec (tail l)))))))"
const FACTORIAL = "(fix (lam rec (lam n (if (= n 0) 1 (* n (rec (- n 1)))))))"
const FIBONACCI = "(fix (lam rec (lam n (if (< n 2) n (+ (rec (- n 1)) (rec (- n 2)))))))"
const DOUBLE = "(fix (lam rec (lam l (if (? l) ~ [(* (head l) 2) (rec (tail l))]))))"
const RANGE = "(fix (lam rec (lam n (if (= n 0) ~ [n (rec (- n 1))]))))"

const examples: { Example } = {
	-- Values and primitives
	value("a constant", "42", "42"),
	value("addition", "(+ 2 3)", "5"),
	value("subtraction can go negative", "(- 2 3)", "-1"),
	value("the largest integer", "9007199254740991", "9007199254740991"),
	value("division", "(div 7 2)", "3"),
	value("division rounds down, not towards zero", "(div -7 2)", "-4"),
	value("remainder takes the sign of the divisor", "(mod 7 -2)", "-1"),
	value("subtraction, then the remainder", "(mod -7 2)", "1"),
	value("multiplication with a negative gives 0, not -0", "(* 0 -1)", "0"),
	value("division by half-way stays exact", "(div 9007199254740991 2)", "4503599627370495"),
	value("the smallest integer, rounded down", "(div -9007199254740991 2)", "-4503599627370496"),
	value("division near the limit stays exact", "(div 9007199254740991 -3)", "-3002399751580331"),
	value("nil test on nil", "(? ~)", "1"),
	value("nil test on a pair", "(? [1 ~])", "0"),
	value("kind of an integer", "(kind 7)", "0"),
	value("kind of nil", "(kind ~)", "1"),
	value("kind of a pair", "(kind [1 ~])", "2"),
	value("kind of a function", "(kind (lam x x))", "3"),
	value("kind of a pin", "(kind (pin 1))", "4"),
	value("less-than", "(< 2 3)", "1"),
	value("comments are ignored", "; the answer\n(+ 40 2) ; trailing", "42"),

	-- Conditionals evaluate only the branch taken
	value("only the taken branch runs", "(if 1 7 (head 3))", "7"),
	value("the other branch is taken on zero", "(if 0 (head 3) 8)", "8"),

	-- Pairs and lists
	value("head and tail", "(head (tail [1 [2 ~]]))", "2"),
	value("a list", "(list 1 2 3)", "(1 2 3)"),
	value("an improper pair", "[1 2]", "(1 . 2)"),
	value("nested lists", "(list (list 1) (list 2 3))", "((1) (2 3))"),

	-- Closures and scope
	value("application", "((lam x (+ x x)) 21)", "42"),
	value("lexical scope", "((lam (x y) (- x y)) 10 3)", "7"),
	value("a closure keeps its scope", "((lam x (lam _ x)) 4 9)", "4"),

	-- Pins
	value("a pin is not run when made", `((lam p 5) (pin {OMEGA}))`, "5", 1000),
	value("a branch that forces an unrun pin is not taken", `(if 0 (force (pin {OMEGA})) 5)`, "5", 1000),
	value("a forced pin gives its value twice", "((lam p [(force p) (force p)]) (pin (+ 1 2)))", "(3 . 3)"),

	-- Recursion through fix
	value("length of a list", `({LENGTH} (list 1 2 3))`, "3"),
	value("length of nil", `({LENGTH} ~)`, "0"),
	value("sum of a list", `({SUM} (list 1 2 3))`, "6"),
	value("factorial of 5", `({FACTORIAL} 5)`, "120"),
	value("fibonacci of 15", `({FIBONACCI} 15)`, "610"),
	value("map doubles each element", `({DOUBLE} (list 1 2 3))`, "(2 4 6)"),
	value("a long loop, with no host recursion", `({SUM} ({RANGE} 10000))`, "50005000", 5000000),

	-- Running out of fuel and errors
	failure("omega runs out of fuel", OMEGA, "out_of_fuel", 10000),
	failure("adding a list is an error", "(+ [1 ~] 1)", "error"),
	failure("head of an integer is an error", "(head 3)", "error"),
	failure("applying an integer is an error", "(3 2)", "error"),
	failure("forcing an integer is an error", "(force 3)", "error"),
	failure("division by zero is an error", "(div 1 0)", "error"),
	failure("remainder by zero is an error", "(mod 1 0)", "error"),
	failure("addition past the largest integer is an error", "(+ 9007199254740991 1)", "error"),
	failure("subtraction past the smallest integer is an error", "(- -9007199254740991 2)", "error"),
	value("mutual recursion: even of 6", "(mutual ((ev (lam k (if (= k 0) 1 (od (- k 1))))) (od (lam k (if (= k 0) 0 (ev (- k 1)))))) (ev 6))", "1"),
	value("mutual recursion: odd of 7", "(mutual ((ev (lam k (if (= k 0) 1 (od (- k 1))))) (od (lam k (if (= k 0) 0 (ev (- k 1)))))) (od 7))", "1"),
	value("mutual recursion: three functions in a ring", "(mutual ((a (lam k (if (= k 0) 0 (b (- k 1))))) (b (lam k (if (= k 0) 1 (c (- k 1))))) (c (lam k (if (= k 0) 2 (a (- k 1)))))) (a 7))", "1"),
	value("a bracket of three is a pair with a pair as its tail", "[1 2 3]", "(1 2 . 3)"),
	value("a bracket of four ending in nil is a list", "[1 2 3 ~]", "(1 2 3)"),
	value("a bracket of three can hold brackets", "[[1 2] 3 ~]", "((1 . 2) 3)"),
	value("a string is a list of its bytes", '"abc"', "(97 98 99)"),
	value("the empty string is nil", '""', "()"),
	value("an escaped quote is one byte", '"a\\"b"', "(97 34 98)"),
	value("escapes for a newline, a tab and a zero byte", '"\\n\\t\\0"', "(10 9 0)"),
	value("a string can be taken apart", '(head "hi")', "104"),
	value("a string can hold a semicolon and parentheses", '"a;(b)"', "(97 59 40 98 41)"),
	value(
		"a recursive function over a string",
		'(letrec len (lam s (if (? s) 0 (+ 1 (len (tail s))))) (len "hello"))',
		"5"
	),
	failure("raise stops the run with an error", "(raise 7)", "error"),
	failure("raise stops the run even inside a cell", "[1 (raise [104 ~])]", "error"),
}

const rejects: { string } = {
	"",
	'"abc',
	"[1]",
	"[]",
	'"a\\qb"',
	"\"a\nb\"",
	"(mutual () 1)",
	"(mutual ((f 1)) f)",
	"(mutual ((f (lam x x) extra)) f)",
	"(mutual ((f (lam x (g x)))) 1)",
	"(+ 1)",
	"(lam + +)",
	"(foo)",
	"(+",
	")",
	"1 2",
	"(lam (x (y)) x)",
	"()",
	"[1]",
	"nope",
	"(lam x y)",
	"(letrec f 1 (f 1))",
	"(letrec f (add 1 2) 1)",
	"9007199254740992",
	"-9007199254740992",
	"99999999999999999999",
}

return {
	examples = examples,
	rejects = rejects,
}
