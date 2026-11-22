--!strict
-- THE CONSTRUCTOR EXAMPLES
--
-- Examples of the constructor forms: a constructor, its tag and its payload. The L1 text syntax has no constructors, so these are built directly, and only run.luau checks them. The self-interpreters and the printer cannot take them, since neither can write a constructor.

const Primitives = require "../interpreter/primitives"
const M = require "../interpreter/vm"

type Example = {
	name: string,
	program: M.Expr,
	fuel: number,
	outcome: string,
	expect: string?,
}
const FUEL = 1e6

const function value(name: string, program: M.Expr, expect: string): Example
	return {
		name = name,
		program = program,
		fuel = FUEL,
		outcome = "value",
		expect = expect,
	}
end

const function failure(name: string, program: M.Expr, outcome: string): Example
	return {
		name = name,
		program = program,
		fuel = FUEL,
		outcome = outcome,
		expect = nil,
	}
end

const I = M.int

const function prim(name: string, a: M.Expr, b: M.Expr?): M.Expr
	return M.prim(Primitives.TAG[name], a, b)
end

const examples: { Example } = {
	value("kind of a constructor", prim("kind", M.construct(0, I(1))), "5"),
	value("the tag of a constructor", M.tagof(M.construct(3, I(7))), "3"),
	value("the payload of a constructor", M.payload(M.construct(3, I(7))), "7"),
	value("the tag of an integer is -1", M.tagof(I(3)), "-1"),
	value("a match on a constructor", M.ite(prim("eq", M.tagof(M.construct(1, I(9))), I(1)), M.payload(M.construct(1, I(9))), I(0)), "9"),
	failure("the payload of an integer is an error", M.payload(I(3)), "error"),
}

return examples
