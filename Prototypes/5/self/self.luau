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
--   11 +, args (a b)               12 -, args (a b)         13 mul, args (a b)
--   14 <, args (a b)               15 =, args (a b)         16 kind, args (a)
--   17 div, args (a b)             18 mod, args (a b)
--
-- The interpreter does not build its own closures and pins. A quoted lam becomes a native lam, and a quoted pin becomes a native pin, so the machine's own errors and laziness apply to the object program. The only thing it has to work out is the environment, which is a list of values, indexed by tails.
--
-- A program that is not well formed is not checked. The only type test in the language is kind, and the interpreter does not use it to check programs.

const M = require "../interpreter/vm"
const Reader = require "../interpreter/reader"
const Code = require "../interpreter/code"

-- The environment representations. An environment is a lookup, which takes an index and an environment, and an extend, which takes a value and an environment and returns the new environment. Both are text, so an interpreter can be built with either.

-- A linked list of values, indexed by tails.
const LOOKUP_LIST = "(fix (lam find (lam n (lam e (if (= n 0) (head e) ((find (- n 1)) (tail e)))))))"
const EXTEND_LIST = "(lam (x env) [x env])"

-- A skew binary random-access list (Okasaki). Its entries are [size tree], and a tree is [size [value [left right]]], with leaves whose children are nil. The entries are ordered newest first, and two adjacent trees of the same size merge into one. An index is found by skipping whole entries, then descending one tree.
const LOOKUP_TREE = "(fix (lam tl (lam t (lam i ((lam (x l r) (if (= i 0) x (if (< (- i 1) (head l)) ((tl l) (- i 1)) ((tl r) (- (- i 1) (head l)))))) (head (tail t)) (head (tail (tail t))) (tail (tail (tail t))))))))"
const LOOKUP_SKEW = `(fix (lam look (lam i (lam env ((lam (e rest) (if (< i (head e)) (({LOOKUP_TREE} (tail e)) i) ((look (- i (head e))) rest))) (head env) (tail env))))))`
const EXTEND_SKEW = "(lam (x env) (if (? env) [[1 [1 [x [~ ~]]]] ~] ((lam (e1 rest1) (if (? rest1) [[1 [1 [x [~ ~]]]] env] ((lam (e2 rest2) (if (= (head e1) (head e2)) [[(+ (* 2 (head e1)) 1) [(+ (* 2 (head e1)) 1) [x [(tail e1) (tail e2)]]]] rest2] [[1 [1 [x [~ ~]]]] env])) (head rest1) (tail rest1)))) (head env) (tail env))))"

-- Evaluates the subexpression sub in the current environment.
const function ev(sub: string): string
	return `((rec {sub}) env)`
end

const A = "(head args)"
const B = "(head (tail args))"
const C = "(head (tail (tail args)))"

-- The interpreter for an environment with the given lookup and extend.
const function build(
	lookup: string,
	extend: string
): string
	-- What each tag does, as the text of its branch. The branch for tag k is BRANCH[k].
	const BRANCH: { [number]: string } = {
		[0] = A, -- a quoted value is stored as it is
		[1] = "~",
		[2] = `(({lookup} {A}) env)`,
		[3] = `(lam v ((rec {A}) ({extend} v env)))`,
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
		[16] = `(kind {ev(A)})`,
		[17] = `(div {ev(A)} {ev(B)})`,
		[18] = `(mod {ev(A)} {ev(B)})`,
	}

	-- A chain of ifs on the tag, checking 0 first and falling through to the highest.
	local chain = BRANCH[18]
	for tag = 17, 0, -1 do
		chain = `(if (= tag {tag}) {BRANCH[tag]} {chain})`
	end

	return `(fix (lam rec (lam node (lam env ((lam (tag args) {chain}) (head node) (tail node))))))`
end

const EVAL = build(LOOKUP_LIST, EXTEND_LIST)

-- Builds an expression that evaluates to the quoted form of e. The tags are in code.luau.
const function quote(e: M.Expr): M.Expr
	return Code.toExpr(Code.toValue(e))
end

-- The expression that runs a program through an interpreter, with an empty environment.
const function interpretWith(
	evaluator: string,
	program: M.Expr
): M.Expr
	return M.app(Reader.parse(evaluator), quote(program), M.nilv())
end

-- The same, with the list representation.
const function interpret(
	program: M.Expr
): M.Expr
	return interpretWith(EVAL, program)
end

return {
	interpret = interpret,
	interpretWith = interpretWith,
	build = build,
	quote = quote,
	EVAL = EVAL,
	LOOKUP_LIST = LOOKUP_LIST,
	EXTEND_LIST = EXTEND_LIST,
	LOOKUP_SKEW = LOOKUP_SKEW,
	EXTEND_SKEW = EXTEND_SKEW,
}
