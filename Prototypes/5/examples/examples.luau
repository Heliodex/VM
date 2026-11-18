--!strict
-- THE EXAMPLES
--
-- Each example is a program, a fuel budget, and what it should do. outcome is "value" (with expect set to the printed result), "error" or "out_of_fuel". run.luau checks every one. Results are written as they print, so (1 2 3) is a list and (1 . 2) is an improper pair.
--
-- Recursive functions use M.fix, so no example needs a special form for recursion.
-- Variables are indices: V(0) is the innermost binder, V(1) the one outside it.

const M = require "../interpreter/vm"

type Example = {
	name: string,
	program: M.Expr,
	fuel: number,
	outcome: string,
	expect: string?,
}
const FUEL = 1e6

const function value(
	name: string,
	program: M.Expr,
	expect: string,
	fuel: number?
): Example
	return {
		name = name,
		program = program,
		fuel = fuel or FUEL,
		outcome = "value",
		expect = expect,
	}
end

const function failure(
	name: string,
	program: M.Expr,
	outcome: string,
	fuel: number?
): Example
	return {
		name = name,
		program = program,
		fuel = fuel or FUEL,
		outcome = outcome,
		expect = nil,
	}
end

const I = M.int
const V = M.var
const NIL = M.nilv()

const function prim(
	name: string,
	a: M.Expr,
	b: M.Expr?
): M.Expr
	return M.prim(name, a, b)
end

-- λx. x x, and the omega term that applies it to itself. It never finishes.
const selfApply = M.lam(M.app(V(0), V(0)))
const omega = M.app(selfApply, selfApply)
-- length, sum, factorial, fibonacci, map and range, each written with M.fix.
const length = M.app(M.fix, M.lam(M.lam( M.ite(prim("isnil", V(0)), I(0), prim("add", I(1), M.app(V(1), M.tail(V(0))))))))
const sumList = M.app(M.fix, M.lam(M.lam( M.ite(prim("isnil", V(0)), I(0), prim("add", M.head(V(0)), M.app(V(1), M.tail(V(0))))))))
const factorial = M.app(M.fix, M.lam(M.lam( M.ite(prim("eq", V(0), I(0)), I(1), prim("mul", V(0), M.app(V(1), prim("sub", V(0), I(1))))))))
const fibonacci = M.app(M.fix, M.lam(M.lam( M.ite(prim("lt", V(0), I(2)), V(0), prim("add", M.app(V(1), prim("sub", V(0), I(1))), M.app(V(1), prim("sub", V(0), I(2))))))))
const double = M.app(M.fix, M.lam(M.lam( M.ite(prim("isnil", V(0)), NIL, M.cell(prim("mul", M.head(V(0)), I(2)), M.app(V(1), M.tail(V(0))))))))
-- range(n) is the list (n n-1 ... 1)
const range = M.app(M.fix, M.lam(M.lam( M.ite(prim("eq", V(0), I(0)), NIL, M.cell(V(0), M.app(V(1), prim("sub", V(0), I(1))))))))
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
	value(
		"a list", M.list {
			I(1),
			I(2),
			I(3),
		}, "(1 2 3)"
	),
	value("an improper pair", M.cell(I(1), I(2)), "(1 . 2)"),
	value(
		"nested lists", M.list {
			M.list {
				I(1),
			},
			M.list {
				I(2),
				I(3),
			},
		}, "((1) (2 3))"
	),
	-- Closures and scope
	value("application", M.app(M.lam(prim("add", V(0), V(0))), I(21)), "42"),
	value("lexical scope", M.app(M.app(M.lam(M.lam(prim("sub", V(1), V(0)))), I(10)), I(3)), "7"),
	value("a closure keeps its scope", M.app(M.app(M.lam(M.lam(V(1))), I(4)), I(9)), "4"),
	-- Pins: suspended, forced on demand, evaluated at most once
	value("a pin is not run when made", M.app(M.lam(I(5)), M.pin(omega)), "5", 1000),
	value("a branch that forces an unrun pin is not taken", M.ite(I(0), M.force(M.pin(omega)), I(5)), "5", 1000),
	value("a forced pin gives its value twice", M.app(M.lam(M.cell(M.force(V(0)), M.force(V(0)))), M.pin(prim("add", I(1), I(2)))), "(3 . 3)"),
	-- Recursion through the fixed-point combinator
	value(
		"length of a list", M.app(
			length, M.list {
				I(1),
				I(2),
				I(3),
			}
		), "3"
	),
	value("length of nil", M.app(length, NIL), "0"),
	value(
		"sum of a list", M.app(
			sumList, M.list {
				I(1),
				I(2),
				I(3),
			}
		), "6"
	),
	value("factorial of 5", M.app(factorial, I(5)), "120"),
	value("fibonacci of 15", M.app(fibonacci, I(15)), "610"),
	value(
		"map doubles each element", M.app(
			double, M.list {
				I(1),
				I(2),
				I(3),
			}
		), "(2 4 6)"
	),
	value("a long loop, with no host recursion", M.app(sumList, M.app(range, I(10000))), "50005000", 5e6),
	-- Running out of fuel and errors
	failure("omega runs out of fuel", omega, "out_of_fuel", 10000),
	failure(
		"adding a list is an error", prim(
			"add", M.list {
				I(1),
			}, I(1)
		), "error"
	),
	failure("head of an integer is an error", M.head(I(3)), "error"),
	failure("applying an integer is an error", M.app(I(1), I(2)), "error"),
	failure("a variable with no binder is an error", V(0), "error"),
	failure("forcing an integer is an error", M.force(I(3)), "error"),
}

return examples
