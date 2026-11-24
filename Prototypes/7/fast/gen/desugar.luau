--!strict
-- GENERATES THE DESUGARER FIXTURE OF THE GO PIPELINE (Prototype 8, step 1)
--
-- The desugarer parity run's inputs (measure/desugar_run.luau): the expressions (with and without imports), and the programs, each as the Luau desugarer gives it, in the notation the parity run compares (showHost), or "error" and its message, or "skip" where the Luau parser or checker refuses the source. The corpus programs are not listed: the program-file and converter fixtures cover them.
--
-- Each line: desugar <kind> <name> <source> <imports> <import values> <host>, every field hex, with - for an empty list. kind is expr (an expression, with the given imports, whose values are integers) or program (a program, checked first). The Go test (fast/desugar_test.go) must give the same for the bootstrapped desugarer.
--
-- Run from Prototypes/7/measure:
--   cd Prototypes/7/measure && lute run ../fast/gen/desugar.luau > ../fast/testdata/desugar.txt

const Checker = require "../../../6/L2/checker"
const Desugar = require "../../../6/L2/desugar"
const Parser = require "../../../6/L2/parser"
const VM = require "../../../6/interpreter/vm"

const function hex(s: string): string
	return (
		string.gsub(
			s,
			".",
			function(c: string): string
				return string.format("%02x", string.byte(c))
			end
		)
	)
end

const function hexList(items: { string }): string
	if #items == 0 then
		return "-"
	end

	local out: { string } = {}

	for _, item in items do
		table.insert(out, hex(item))
	end

	return table.concat(out, ",")
end

local function showHost(e: any): string
	const op = e.op

	if op == "quote" then
		if type(e.value) == "number" then
			return `Q{e.value}`
		end

		return "N"
	elseif op == "var" then
		return `V{e.index}`
	elseif op == "lam" then
		return `(L {showHost(e.body)})`
	elseif op == "apply" then
		return `(A {showHost(e.f)} {showHost(e.arg)})`
	elseif op == "cell" then
		return `(C {showHost(e.head)} {showHost(e.tail)})`
	elseif op == "index" then
		return `(I {e.n} {showHost(e.e)})`
	elseif op == "if" then
		return `(IF {showHost(e.c)} {showHost(e.t)} {showHost(e.e)})`
	elseif op == "pin" then
		return `(P {showHost(e.e)})`
	elseif op == "force" then
		return `(F {showHost(e.e)})`
	elseif op == "construct" then
		return `(K {e.tag} {showHost(e.e)})`
	elseif op == "tagof" then
		return `(T {showHost(e.e)})`
	elseif op == "payload" then
		return `(Y {showHost(e.e)})`
	elseif op == "prim" then
		if e.b ~= nil then
			return `(R {e.tag} {showHost(e.a)} {showHost(e.b)})`
		end

		return `(R {e.tag} {showHost(e.a)})`
	end

	error(`unknown expression {tostring(op)}`, 0)
end

local function hostExpr(src: string, imports: { string }, importExprs: { any }): (string?, any?)
	const parsedOk, parsed = pcall(Parser.parse, src)

	if not parsedOk then
		return nil, nil
	end

	const program = parsed :: Parser.Program
	const ok, res = pcall(function()
		const ctors = Desugar.buildCtors(program.decls)

		return Desugar.wrapImports(Desugar.desugarExpr(program.expr, imports, ctors), importExprs)
	end)

	if ok then
		return "value " .. showHost(res), nil
	end

	return "error " .. tostring(res), nil
end

local EXPRESSIONS: { { name: string; src: string } } = {
	{ name = "an integer"; src = "5" },
	{ name = "a string"; src = '"ab"' },
	{ name = "nil"; src = "~" },
	{ name = "a pair"; src = "(1 . 2)" },
	{ name = "a list"; src = "[1 2 3]" },
	{ name = "a nested pair in a list"; src = "[1 (2 . 3)]" },
	{ name = "a prim applied"; src = "+ 1 2" },
	{ name = "a prim partly applied"; src = "+ 1" },
	{ name = "a prim as a value"; src = "+" },
	{ name = "a unary prim"; src = "@ 5" },
	{ name = "division"; src = "/ 6 3" },
	{ name = "remainder by zero"; src = "% 7 0" },
	{ name = "division as a value"; src = "/" },
	{ name = "cons applied"; src = "cons 1 ~" },
	{ name = "cons partly applied"; src = "cons 1" },
	{ name = "cons over-applied"; src = "cons 1 2 3" },
	{ name = "fst"; src = "fst (1 . 2)" },
	{ name = "snd as a value"; src = "snd" },
	{ name = "head of a list"; src = "head [1 2]" },
	{ name = "tail of a list"; src = "tail [1 2]" },
	{ name = "pin and force"; src = "force (pin 1)" },
	{ name = "a fn of two names"; src = "fn (x y)\n\t(- x y)" },
	{ name = "a fn of one name"; src = "fn x\n\t(+ x 1)" },
	{ name = "a let"; src = "let x = 3\nx" },
	{ name = "a let shadowing a prim name"; src = "let x = 3\n(+ x x)" },
	{ name = "a letrec"; src = "letrec f = fn n\n\t(if (< n 1) 0 (f (- n 1)))\n(f 3)" },
	{ name = "an if"; src = "if 1 2 3" },
	{ name = "Ok applied"; src = "Ok 5" },
	{ name = "Err applied to a string"; src = 'Err "x"' },
	{ name = "Ok as a value"; src = "Ok" },
	{ name = "a match on Result"; src = "match (Ok 1) {\n\tOk v -> v\n\tErr e -> 0\n}" },
	{ name = "a match with a wildcard payload"; src = "match (Ok 1) {\n\tOk _ -> 2\n\t_ -> 3\n}" },
	{ name = "a match that binds the value"; src = "match 5 {\n\tx -> (+ x 1)\n}" },
	{ name = "a match on a fn argument"; src = "fn r\n\tmatch r {\n\t\tOk v -> v\n\t\tErr e -> 0\n\t}" },
	{ name = "an unbound name"; src = "y" },
	{ name = "a binder that is a primitive"; src = "let + = 1\n2" },
	{ name = "a fn with a name twice"; src = "fn (x x)\n\tx" },
	{ name = "a letrec of a non-fn"; src = "letrec x = 1\nx" },
	{ name = "an arm after a catch-all"; src = "match 1 {\n\t_ -> 2\n\tOk v -> 3\n}" },
	{ name = "an unknown constructor in a match"; src = "match 1 {\n\tFoo v -> 2\n}" },
	{ name = "a constructor applied to nothing"; src = "Err" },
	{ name = "untyped"; src = "untyped 5" },
	{ name = "early return in a body"; src = "fn r\n\tlet v = (Ok 1)?\n\t(+ v 1)" },
	{ name = "early return in an argument"; src = "fn r\n\t(+ 2 ((Ok 1)?))" },
	{ name = "early return in a let value"; src = "fn r\n\tlet v = ((+ 1 (Ok 2)?))\n\tv" },
	{ name = "early return in an if branch that is the result"; src = "fn r\n\tif r ((Ok 1)?) ((Ok 2)?)" },
	{ name = "early return in an if branch that is not the result"; src = "fn r\n\t(+ 1 (if r ((Ok 1)?) 2))" },
	{ name = "early return in a match arm that is the result"; src = "fn r\n\tmatch r {\n\t\tOk v -> (Ok (+ v 1))?\n\t\tErr e -> r\n\t}" },
	{ name = "early return where the function is not"; src = "(+ 1 (Ok 2)?)" },
	{ name = "a user sum"; src = "type Shape = Circle Int | Square Int | Dot\nCircle 5" },
	{ name = "a user sum with a match"; src = "type Shape = Circle Int | Square Int | Dot\nmatch (Square 2) {\n\tCircle r -> r\n\tSquare s -> s\n\tDot -> 0\n}" },
	{ name = "a constructor with no payload, matched"; src = "type Shape = Circle Int | Dot\nmatch Dot {\n\tCircle r -> r\n\t_ -> 7\n}" },
	{ name = "a constructor with no payload, applied"; src = "type Shape = Circle Int | Dot\nDot 1 2" },
	{ name = "a record"; src = "type Point = Point {\n\tx: Int\n\ty: Int\n}\nPoint {\n\tx = 1\n\ty = 2\n}" },
	{ name = "a record accessor"; src = "type Point = Point {\n\tx: Int\n\ty: Int\n}\nx (Point {\n\tx = 1\n\ty = 2\n})" },
	{ name = "a record matched"; src = "type Point = Point {\n\tx: Int\n\ty: Int\n}\nmatch (Point {\n\tx = 1\n\ty = 2\n}) {\n\tPoint {\n\t\tx = a\n\t\ty = b\n\t} -> (+ a b)\n}" },
	{ name = "a record with a field missing"; src = "type Point = Point {\n\tx: Int\n\ty: Int\n}\nPoint {\n\tx = 1\n}" },
	{ name = "a record with a field that is not one"; src = "type Point = Point {\n\tx: Int\n\ty: Int\n}\nPoint {\n\tx = 1\n\tz = 2\n}" },
	{ name = "a with"; src = "type Point = Point {\n\tx: Int\n\ty: Int\n}\nlet p = (Point {\n\tx = 1\n\ty = 2\n})\nwith p {\n\ty = 5\n}" },
	{ name = "a with that takes a field that is not one"; src = "type Point = Point {\n\tx: Int\n\ty: Int\n}\nlet p = (Point {\n\tx = 1\n\ty = 2\n})\nwith p {\n\tz = 5\n}" },
	{ name = "a record used without braces"; src = "type Point = Point {\n\tx: Int\n\ty: Int\n}\nPoint 1" },
	{ name = "a sum declared twice"; src = "type A = Foo | Bar\ntype B = Baz | Foo\nFoo" },
	{ name = "a mutual group"; src = "letrec {\n\tf = fn n\n\t\t(if n 0 (g (- n 1)))\n\tg = fn n\n\t\t(if n 1 (f (- n 1)))\n\t(f 3)\n}" },
	{ name = "a mutual group that binds a non-fn"; src = "letrec {\n\tf = 1\n\t(f 3)\n}" },
	{ name = "a record named without its fields"; src = "type P = P {\n\tx: Int\n}\nP" },
	{ name = "a record field given twice"; src = "type P = P {\n\tx: Int\n}\nP {\n\tx = 1\n\tx = 2\n}" },
	{ name = "a record pattern of a constructor that is not a record"; src = "match 1 {\n\tFoo {\n\t\tx = a\n\t} -> a\n}" },
	{ name = "a record pattern with a field the record lacks"; src = "type P = P {\n\tx: Int\n}\nmatch (P {\n\tx = 1\n}) {\n\tP {\n\t\tz = a\n\t} -> a\n}" },
	{ name = "a record pattern that names a field twice"; src = "type P = P {\n\tx: Int\n}\nmatch (P {\n\tx = 1\n}) {\n\tP {\n\t\tx = a\n\t\tx = b\n\t} -> a\n}" },
	{ name = "a record pattern that misses a field"; src = "type P = P {\n\tx: Int\n\ty: Int\n}\nmatch (P {\n\tx = 1\n\ty = 2\n}) {\n\tP {\n\t\tx = a\n\t} -> a\n}" },
	{ name = "a bind to a constructor with no payload"; src = "type S = A | B\nmatch A {\n\tB x -> 1\n\t_ -> 2\n}" },
	{ name = "a record constructor matched as a sum"; src = "type P = P {\n\tx: Int\n}\nmatch (P {\n\tx = 1\n}) {\n\tP v -> 1\n}" },
	{ name = "a with on a field that is not a record field"; src = "let z = 1\nwith z {\n\tx = 2\n}" },
	{ name = "a with that gives a field twice"; src = "type P = P {\n\tx: Int\n\ty: Int\n}\nlet p = (P {\n\tx = 1\n\ty = 2\n})\nwith p {\n\ty = 5\n\ty = 6\n}" },
	{ name = "an early return in a let value that is not the result"; src = "fn r\n\tlet v = (if r ((Ok 1)?) 2)\n\tv" },
	{ name = "an early return in an argument of a call that is not the result"; src = "fn r\n\tlet v = ((+ 1 (Ok 2)?))\n\tv" },
	{ name = "a catch-all bound name"; src = "match 1 {\n\tx -> x\n}" },
	{ name = "a fn parameter that is a constructor"; src = "fn Foo\n\t1" },
	{ name = "a let of the underscore"; src = "let _ = 1\n2" },
	{ name = "a type declared with a record and a sum of the same name"; src = "type P = P {\n\tx: Int\n}\ntype Q = P | R\nP { x = 1 }" },
	{ name = "a shadowed import"; src = "let reverse = 2\nreverse" },
}

local PROGRAMS: { { name: string; src: string } } = {
	{ name = "a check of an integer"; src = "fn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (+ v 1)\n\t\tErr e -> 0\n}" },
	{ name = "a check of a pair"; src = "fn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (fst v)\n\t\tErr e -> 0\n}" },
	{ name = "a check of a list"; src = "fn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (@ v)\n\t\tErr e -> 0\n}" },
	{ name = "the input of a program"; src = "fn x\n\t(+ x 1)" },
	{ name = "the input of a program that is a pair"; src = "fn p\n\t(fst p)" },
	{ name = "a program that returns a constructor"; src = "fn x\n\tOk x" },
}


-- An expression, desugared with the given imports (values are integers, the machine expressions of the imports).
local function emitExpr(name: string, src: string, imports: { string }, values: { number })
	const codes: { any } = {}

	for _, v in values do
		table.insert(codes, VM.int(v))
	end

	const host, _ = hostExpr(src, imports, codes)

	if host == nil then
		print(`desugar expr {hex(name)} {hex(src)} {hexList(imports)} {hexList({})} {hex("skip")}`)

		return
	end

	local valueText: { string } = {}

	for _, v in values do
		table.insert(valueText, tostring(v))
	end

	print(`desugar expr {hex(name)} {hex(src)} {hexList(imports)} {hexList(valueText)} {hex(host)}`)
end

for _, c in EXPRESSIONS do
	emitExpr(c.name, c.src, {}, {})
end

emitExpr("an import in scope", "reverse 5", { "reverse" }, { 7 })
emitExpr("two imports, wrapped in order", "+ a b", { "a", "b" }, { 1, 2 })
emitExpr("an import shadowed", "let reverse = 2\nreverse", { "reverse" }, { 7 })

for _, c in PROGRAMS do
	const parsedOk, parsed = pcall(Parser.parse, c.src)

	if not parsedOk then
		print(`desugar program {hex(c.name)} {hex(c.src)} - - {hex("skip")}`)
	else
		const program = parsed :: Parser.Program
		const checked, res = pcall(Checker.check, program, {}, "t.prog")

		if not checked then
			print(`desugar program {hex(c.name)} {hex(c.src)} - - {hex("skip")}`)
		else
			const result = res :: any
			const ctors = Desugar.buildCtors(program.decls)
			const host = "value " .. showHost(Desugar.boundary(Desugar.desugarProgram(result.expr, {}, ctors), result.input, result.inputExpect))
			print(`desugar program {hex(c.name)} {hex(c.src)} - - {hex(host)}`)
		end
	end
end
