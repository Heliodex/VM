--!strict
-- THE SELF-INTERPRETER
--
-- An interpreter for the language, written in the language. It takes a program as data and evaluates it, and the result should match running the program directly.
--
-- A program is quoted as a pair [tag args], where tag is an integer for the form and args is a list of its parts:
--
--   0 quote, args (value)           1 nil, args ()           2 var, args (index)
--   3 lam, args (body)              4 pin, args (e)          5 cell, args (head tail)
--   6 head, args (e)                7 tail, args (e)         8 force, args (e)
--   9 if, args (c t e)             10 apply, args (f arg)
--   11 +, args (a b)               12 -, args (a b)         13 *, args (a b)
--   14 <, args (a b)               15 =, args (a b)         16 ?, args (a)
--
-- The interpreter does not build its own closures and pins. A quoted lam becomes a native lam, and a quoted pin becomes a native pin, so the machine's own errors and laziness apply to the object program. The only thing it has to work out is the environment, which is a list of values, indexed by tails.
--
-- A program that is not well formed is not checked, since the language has no type test beyond isnil.

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

-- What each tag does, as the text of its branch. The branch for tag k is BRANCH[k].
const BRANCH: { [number]: string } = {
	[0] = A, -- a quoted value is stored as it is
	[1] = "~",
	[2] = `(({LOOKUP} {A}) env)`,
	[3] = `(lam v ((rec {A}) [v env]))`,
	[4] = `(pin {ev(A)})`,
	[5] = `[{ev(A)} {ev(B)}]`,
	[6] = `(head {ev(A)})`,
	[7] = `(tail {ev(A)})`,
	[8] = `(force {ev(A)})`,
	[9] = `(if {ev(A)} {ev(B)} {ev(C)})`,
	[10] = `({ev(A)} {ev(B)})`,
	[11] = `(+ {ev(A)} {ev(B)})`,
	[12] = `(- {ev(A)} {ev(B)})`,
	[13] = `(* {ev(A)} {ev(B)})`,
	[14] = `(< {ev(A)} {ev(B)})`,
	[15] = `(= {ev(A)} {ev(B)})`,
	[16] = `(? {ev(A)})`,
}

-- A chain of ifs on the tag, checking 0 first and falling through to 16.
local chain = BRANCH[16]
for tag = 15, 0, -1 do
	chain = `(if (= tag {tag}) {BRANCH[tag]} {chain})`
end

const EVAL = `(fix (lam rec (lam node (lam env ((lam (tag args) {chain}) (head node) (tail node))))))`

const PRIMITIVE_TAGS: { [string]: number } = {
	add = 11,
	sub = 12,
	mul = 13,
	lt = 14,
	eq = 15,
	isnil = 16,
}

-- Builds an expression that evaluates to the quoted form of e.
local function quote(e: M.Expr): M.Expr
	const function node(
		tag: number,
		args: M.Expr
	): M.Expr
		return M.cell(M.int(tag), args)
	end

	if e.op == "quote" then
		return node(0, M.list({ M.int(e.value) }))
	elseif e.op == "nil" then
		return node(1, M.nilv())
	elseif e.op == "var" then
		return node(2, M.list({ M.int(e.index) }))
	elseif e.op == "lam" then
		return node(3, M.list({ quote(e.body) }))
	elseif e.op == "pin" then
		return node(4, M.list({ quote(e.e) }))
	elseif e.op == "cell" then
		return node(5, M.list({ quote(e.head), quote(e.tail) }))
	elseif e.op == "head" then
		return node(6, M.list({ quote(e.e) }))
	elseif e.op == "tail" then
		return node(7, M.list({ quote(e.e) }))
	elseif e.op == "force" then
		return node(8, M.list({ quote(e.e) }))
	elseif e.op == "if" then
		return node(9, M.list({ quote(e.c), quote(e.t), quote(e.e) }))
	elseif e.op == "apply" then
		return node(10, M.list({ quote(e.f), quote(e.arg) }))
	end

	const tag = PRIMITIVE_TAGS[e.name]
	if e.b == nil then
		return node(tag, M.list({ quote(e.a) }))
	end
	return node(tag, M.list({ quote(e.a), quote(e.b) }))
end

-- The expression that runs a program through the self-interpreter, with an empty environment.
const function interpret(
	program: M.Expr
): M.Expr
	return M.app(Reader.parse(EVAL), quote(program), M.nilv())
end

return {
	interpret = interpret,
	quote = quote,
	EVAL = EVAL,
}
