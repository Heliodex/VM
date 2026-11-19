--!strict
-- THE CLOSURE-FREE SELF-INTERPRETER
--
-- self.luau uses the host's closures for the object language's functions. This version does not. A function is data: the cell [1 [body env]], where body is the quoted body and env is the environment it was made in. Application is done by EVAL itself, which runs the body in [argument env].
--
-- This is the test of whether the object language needs closures as a value. Everything the examples do is handled, but the data form is not checked: a cell that looks like a function is applied as one, and head and tail accept it as an ordinary pair. self_data_run.luau shows where that changes the result.
--
-- The tags are those of self.luau, with the function value as a cell in place of a native closure.

const Self = require "./self"
const M = require "../interpreter/vm"
const Reader = require "../interpreter/reader"

-- The value at an index in the environment.
const LOOKUP = "(fix (lam find (lam n (lam e (if (= n 0) (head e) ((find (- n 1)) (tail e)))))))"

-- Evaluates the subexpression sub in the current environment.
local function ev(sub: string): string
	return `((rec {sub}) env)`
end

const A = "(head args)"
const B = "(head (tail args))"
const C = "(head (tail (tail args)))"

-- The branch for each tag. Lam builds a function as data. Apply reads one out, checks its tag, and runs its body.
const BRANCH: { [number]: string } = {
	[0] = A,
	[1] = "~",
	[2] = `(({LOOKUP} {A}) env)`,
	[3] = `[1 [{A} env]]`,
	[4] = `(pin {ev(A)})`,
	[5] = `[{ev(A)} {ev(B)}]`,
	[6] = `(head {ev(A)})`,
	[7] = `(tail {ev(A)})`,
	[8] = `(force {ev(A)})`,
	[9] = `(if {ev(A)} {ev(B)} {ev(C)})`,
	[10] = `((lam (f a) (if (= (head f) 1) ((rec (head (tail f))) [a (tail (tail f))]) (head ~))) {ev(A)} {ev(B)})`,
	[11] = `(+ {ev(A)} {ev(B)})`,
	[12] = `(- {ev(A)} {ev(B)})`,
	[13] = `(* {ev(A)} {ev(B)})`,
	[14] = `(< {ev(A)} {ev(B)})`,
	[15] = `(= {ev(A)} {ev(B)})`,
	[16] = `(kind {ev(A)})`,
	[17] = `(div {ev(A)} {ev(B)})`,
	[18] = `(mod {ev(A)} {ev(B)})`,
	[19] = `(raise {ev(A)})`,
}

-- A chain of ifs on the tag, checking 0 first and falling through to the highest.
local chain = BRANCH[19]
for tag = 18, 0, -1 do
	chain = `(if (= tag {tag}) {BRANCH[tag]} {chain})`
end

const EVAL_DATA = `(fix (lam rec (lam node (lam env ((lam (tag args) {chain}) (head node) (tail node))))))`

-- The expression that runs a program through the closure-free interpreter, with an empty environment.
const function interpret(
	program: M.Expr
): M.Expr
	return M.app(Reader.parse(EVAL_DATA), Self.quote(program), M.nilv())
end

return {
	interpret = interpret,
	EVAL_DATA = EVAL_DATA,
}
