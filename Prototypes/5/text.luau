--!strict
-- THE TEXT EXAMPLES
--
-- The examples of examples.luau again, written in the text syntax and read by reader.luau. Each gives the same outcome as its builder version, so the reader and the builders are checked against each other.
--
-- rejects are sources that must not read. run.luau checks that each one raises an error.

const Reader = require "./reader"
const VM = require "./vm"

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
const LENGTH = "(fix (lam rec (lam l (if (isnil l) 0 (add 1 (rec (tail l)))))))"
const SUM = "(fix (lam rec (lam l (if (isnil l) 0 (add (head l) (rec (tail l)))))))"
const FACTORIAL = "(fix (lam rec (lam n (if (eq n 0) 1 (mul n (rec (sub n 1)))))))"
const FIBONACCI = "(fix (lam rec (lam n (if (lt n 2) n (add (rec (sub n 1)) (rec (sub n 2)))))))"
const DOUBLE = "(fix (lam rec (lam l (if (isnil l) () (cell (mul (head l) 2) (rec (tail l)))))))"
const RANGE = "(fix (lam rec (lam n (if (eq n 0) () (cell n (rec (sub n 1)))))))"

const examples: { Example } = {
	-- Values and primitives
	value("a constant", "42", "42"),
	value("addition", "(add 2 3)", "5"),
	value("subtraction can go negative", "(sub 2 3)", "-1"),
	value("isnil on nil", "(isnil ())", "1"),
	value("isnil on a cell", "(isnil (cell 1 ()))", "0"),
	value("less-than", "(lt 2 3)", "1"),
	value("comments are ignored", "; the answer\n(add 40 2) ; trailing", "42"),

	-- Conditionals evaluate only the branch taken
	value("only the taken branch runs", "(if 1 7 (head 3))", "7"),
	value("the other branch is taken on zero", "(if 0 (head 3) 8)", "8"),

	-- Cells and lists
	value("head and tail", "(head (tail (cell 1 (cell 2 ()))))", "2"),
	value("a list", "(list 1 2 3)", "(1 2 3)"),
	value("an improper pair", "(cell 1 2)", "(1 . 2)"),
	value("nested lists", "(list (list 1) (list 2 3))", "((1) (2 3))"),

	-- Closures and scope
	value("application", "((lam x (add x x)) 21)", "42"),
	value("lexical scope", "((lam (x y) (sub x y)) 10 3)", "7"),
	value("a closure keeps its scope", "((lam x (lam _ x)) 4 9)", "4"),

	-- Pins
	value("a pin is not run when made", `((lam p 5) (pin {OMEGA}))`, "5", 1000),
	value("a branch that forces an unrun pin is not taken", `(if 0 (force (pin {OMEGA})) 5)`, "5", 1000),
	value("a forced pin gives its value twice", "((lam p (cell (force p) (force p))) (pin (add 1 2)))", "(3 . 3)"),

	-- Recursion through fix
	value("length of a list", `({LENGTH} (list 1 2 3))`, "3"),
	value("length of nil", `({LENGTH} ())`, "0"),
	value("sum of a list", `({SUM} (list 1 2 3))`, "6"),
	value("factorial of 5", `({FACTORIAL} 5)`, "120"),
	value("fibonacci of 15", `({FIBONACCI} 15)`, "610"),
	value("map doubles each element", `({DOUBLE} (list 1 2 3))`, "(2 4 6)"),
	value("a long loop, with no host recursion", `({SUM} ({RANGE} 10000))`, "50005000", 5000000),

	-- Running out of fuel and errors
	failure("omega runs out of fuel", OMEGA, "out_of_fuel", 10000),
	failure("adding a list is an error", "(add (list 1) 1)", "error"),
	failure("head of an integer is an error", "(head 3)", "error"),
	failure("applying an integer is an error", "(3 2)", "error"),
	failure("an unbound variable is an error", "nope", "error"),
	failure("forcing an integer is an error", "(force 3)", "error"),
}

const rejects: { string } = {
	"",
	"(add 1)",
	"(lam add add)",
	"(foo)",
	"(add",
	")",
	"1 2",
	"(lam (x (y)) x)",
}

return {
	examples = examples,
	rejects = rejects,
}
