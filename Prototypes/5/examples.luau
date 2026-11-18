--!strict
-- THE EXAMPLES
--
-- Each example is a program, a fuel budget, and what it should do. outcome is "value" (with expect set to the printed result), "error" or "out_of_fuel". run.luau checks every one. Results are written as they print, so (1 2 3) is a list and (1 . 2) is an improper pair.
--
-- Recursive functions use M.fix, so no example needs a special form for recursion.

const M = require "./vm"

type Example = {
	name: string,
	program: any,
	fuel: number,
	outcome: string,
	expect: string?,
}

const FUEL = 1000000

local function value(name: string, program: any, expect: string, fuel: number?): Example
	return { name = name, program = program, fuel = fuel or FUEL, outcome = "value", expect = expect }
end

local function failure(name: string, program: any, outcome: string, fuel: number?): Example
	return { name = name, program = program, fuel = fuel or FUEL, outcome = outcome, expect = nil }
end

const I = M.int
const V = M.var
const NIL = M.nilv()

local function prim(name: string, a: any, b: any?): any
	return M.prim(name, a, b)
end

-- λx. x x, and the omega term that applies it to itself. It never finishes.
local function selfApply(name: string): any
	return M.lam(name, M.app(V(name), V(name)))
end
const omega = M.app(selfApply("x"), selfApply("x"))

-- length, sum, factorial, fibonacci, map and range, each written with M.fix.
const length = M.app(
	M.fix,
	M.lam(
		"rec",
		M.lam("l", M.ite(prim("isnil", V("l")), I(0), prim("add", I(1), M.app(V("rec"), M.tail(V("l"))))))
	)
)

const sumList = M.app(
	M.fix,
	M.lam(
		"rec",
		M.lam("l", M.ite(prim("isnil", V("l")), I(0), prim("add", M.head(V("l")), M.app(V("rec"), M.tail(V("l"))))))
	)
)

const factorial = M.app(
	M.fix,
	M.lam(
		"rec",
		M.lam("n", M.ite(prim("eq", V("n"), I(0)), I(1), prim("mul", V("n"), M.app(V("rec"), prim("sub", V("n"), I(1))))))
	)
)

const fibonacci = M.app(
	M.fix,
	M.lam(
		"rec",
		M.lam(
			"n",
			M.ite(
				prim("lt", V("n"), I(2)),
				V("n"),
				prim("add", M.app(V("rec"), prim("sub", V("n"), I(1))), M.app(V("rec"), prim("sub", V("n"), I(2))))
			)
		)
	)
)

const double = M.app(
	M.fix,
	M.lam(
		"rec",
		M.lam(
			"l",
			M.ite(
				prim("isnil", V("l")),
				NIL,
				M.cell(prim("mul", M.head(V("l")), I(2)), M.app(V("rec"), M.tail(V("l"))))
			)
		)
	)
)

-- range(n) is the list (n n-1 ... 1)
const range = M.app(
	M.fix,
	M.lam(
		"rec",
		M.lam("n", M.ite(prim("eq", V("n"), I(0)), NIL, M.cell(V("n"), M.app(V("rec"), prim("sub", V("n"), I(1))))))
	)
)

const examples: { Example } = {
	-- Values and primitives
	value("a constant", I(42), "42"),
	value("addition", prim("add", I(2), I(3)), "5"),
	value("subtraction can go negative", prim("sub", I(2), I(3)), "-1"),
	value("isnil on nil", prim("isnil", NIL), "1"),
	value("isnil on a cell", prim("isnil", M.cell(I(1), NIL)), "0"),
	value("less-than", prim("lt", I(2), I(3)), "1"),

	-- Conditionals evaluate only the branch taken
	value("only the taken branch runs", M.ite(I(1), I(7), M.head(I(3))), "7"),
	value("the other branch is taken on zero", M.ite(I(0), M.head(I(3)), I(8)), "8"),

	-- Cells and lists
	value("head and tail", M.head(M.tail(M.cell(I(1), M.cell(I(2), NIL)))), "2"),
	value("a list", M.list({ I(1), I(2), I(3) }), "(1 2 3)"),
	value("an improper pair", M.cell(I(1), I(2)), "(1 . 2)"),
	value("nested lists", M.list({ M.list({ I(1) }), M.list({ I(2), I(3) }) }), "((1) (2 3))"),

	-- Closures and scope
	value("application", M.app(M.lam("x", prim("add", V("x"), V("x"))), I(21)), "42"),
	value("lexical scope", M.app(M.app(M.lam("x", M.lam("y", prim("sub", V("x"), V("y")))), I(10)), I(3)), "7"),
	value("a closure keeps its scope", M.app(M.app(M.lam("x", M.lam("_", V("x"))), I(4)), I(9)), "4"),

	-- Pins: suspended, forced on demand, evaluated at most once
	value("a pin is not run when made", M.app(M.lam("p", I(5)), M.pin(omega)), "5", 1000),
	value("a branch that forces an unrun pin is not taken", M.ite(I(0), M.force(M.pin(omega)), I(5)), "5", 1000),
	value(
		"a forced pin gives its value twice",
		M.app(M.lam("p", M.cell(M.force(V("p")), M.force(V("p")))), M.pin(prim("add", I(1), I(2)))),
		"(3 . 3)"
	),

	-- Recursion through the fixed-point combinator
	value("length of a list", M.app(length, M.list({ I(1), I(2), I(3) })), "3"),
	value("length of nil", M.app(length, NIL), "0"),
	value("sum of a list", M.app(sumList, M.list({ I(1), I(2), I(3) })), "6"),
	value("factorial of 5", M.app(factorial, I(5)), "120"),
	value("fibonacci of 15", M.app(fibonacci, I(15)), "610"),
	value("map doubles each element", M.app(double, M.list({ I(1), I(2), I(3) })), "(2 4 6)"),
	value("a long loop, with no host recursion", M.app(sumList, M.app(range, I(10000))), "50005000", 5000000),

	-- Running out of fuel and errors
	failure("omega runs out of fuel", omega, "out_of_fuel", 10000),
	failure("adding a list is an error", prim("add", M.list({ I(1) }), I(1)), "error"),
	failure("head of an integer is an error", M.head(I(3)), "error"),
	failure("applying an integer is an error", M.app(I(1), I(2)), "error"),
	failure("an unbound variable is an error", V("nope"), "error"),
	failure("forcing an integer is an error", M.force(I(3)), "error"),
}

return examples
