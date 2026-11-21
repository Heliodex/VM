--!strict
-- THE CLOSURE-FREE SELF-INTERPRETER
--
-- self.luau uses the host's closures for the object language's functions. This version does not. A function is data: the cell [1 [body env]], where body is the quoted body and env is the environment it was made in. Application is done by EVAL itself, which runs the body in [argument env].
--
-- This is the test of whether the object language needs closures as a value. Everything the examples do is handled, but the data form is not checked: a cell that looks like a function is applied as one, and head and tail accept it as an ordinary pair. self_data_run.luau shows where that changes the result.
--
-- The tags are those of self.luau, with the function value as a cell in place of a native closure.

const M = require "../../interpreter/vm"
const Reader = require "../reader"
const Self = require "./self"

-- The value at an index in the environment.
const LOOKUP = "(fix (fn find (fn n (fn e (if (= n 0) (head e) ((find (- n 1)) (tail e)))))))"

-- Evaluates the subexpression sub in the current environment.
local function ev(sub: string): string
	return `((rec {sub}) env)`
end

-- Walks an address n from 2 up through the value v: the low bit of n is the last step, so walk n v is the step for n mod 2 applied to walk (n / 2) v. A 0 is head and a 1 is tail.
const WALK = "(fix (fn w (fn n (fn v (if (= n 1) v (let s ((w (/ n 2)) v) (if (= (% n 2) 0) (head s) (tail s))))))))"
const A = "(head args)"
const B = "(head (tail args))"
const C = "(head (tail (tail args)))"
-- The branch for each tag. Lam builds a function as data. Apply reads one out, checks its tag, and runs its body.
const BRANCH: { string } = {
	[0] = A,
	[2] = `(({LOOKUP} {A}) env)`,
	[3] = `[1 [{A} env]]`,
	[4] = `(pin {ev(A)})`,
	[5] = `[{ev(A)} {ev(B)}]`,
	[6] = `(({WALK} {A}) {ev(B)})`,
	[8] = `(force {ev(A)})`,
	[9] = `(if {ev(A)} {ev(B)} {ev(C)})`,
	[10] = `((fn (f a) (if (= (head f) 1) ((rec (head (tail f))) [a (tail (tail f))]) (head ~))) {ev(A)} {ev(B)})`,
	[11] = `(+ {ev(A)} {ev(B)})`,
	[12] = `(- {ev(A)} {ev(B)})`,
	[13] = `(* {ev(A)} {ev(B)})`,
	[16] = `(< {ev(A)} {ev(B)})`,
	[17] = `(= {ev(A)} {ev(B)})`,
	[18] = `(@ {ev(A)})`,
	-- The constructor forms have no text syntax in L1, so the interpreter cannot build them: an interpreted program that uses one fails as an error, as a malformed form would.
	[19] = "(head ~)",
	[20] = "(head ~)",
	[21] = "(head ~)",
	[14] = `(/ {ev(A)} {ev(B)})`,
	[15] = `(% {ev(A)} {ev(B)})`,
}
-- A chain of ifs on the tag, checking 0 first and falling through to the highest.
local chain = "(head ~)"

for tag = 21, 0, -1 do
	if BRANCH[tag] ~= nil then
		chain = `(if (= tag {tag}) {BRANCH[tag]} {chain})`
	end
end

const EVAL_DATA = `(fix (fn rec (fn node (fn env ((fn (tag args) {chain}) (head node) (tail node))))))`

-- The expression that runs a program through the closure-free interpreter, with an empty environment.
const function interpret(program: M.Expr): M.Expr
	return M.app(Reader.parse(EVAL_DATA), Self.quote(program), M.nilv())
end

return {
	interpret = interpret,
	EVAL_DATA = EVAL_DATA,
}
