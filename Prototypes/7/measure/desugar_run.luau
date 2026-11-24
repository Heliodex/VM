--!strict
-- CHECKS THE DESUGARER, WRITTEN IN L2 (measure/boot/desugar.l2), AGAINST THE LUAU DESUGARER (Prototypes/6/L2/desugar.luau)
--
-- Each input is run through the L2 tokenizer and parser, then through the L2 desugarer on the VM, and through the Luau parser and desugarer. The two must give the same machine expression, or the same error. Both outputs are written in one notation, so the comparison is exact.
--
-- Two modes. An expression is desugared as Desugar.desugarExpr does, with its imports in scope and the imports' machine expressions wrapped around it. A program is checked first by the Luau checker, which gives the tests of its check nodes and the test of its input; it is desugared as Desugar.desugarProgram does, then its input is checked at the boundary. The L2 side is given the same tests, and the same machine expressions for the imports.
--
--   lute run desugar_run.luau      (from Prototypes/7/measure)

const Checker = require "../../6/L2/checker"
const Desugar = require "../../6/L2/desugar"
const L2 = require "../../6/L2/l2"
const Parser = require "../../6/L2/parser"
const VM = require "../../6/interpreter/vm"
const fs = require "@lute/fs"

local failures = 0
local total = 0
local skipped = 0
local agreed = 0

local function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

local function resolve(name: string): string?
	const ok, text = pcall(readFile, `../../6/L2/programs/{name}`)

	if ok then
		return text :: string
	end

	return nil
end

const tokenizer = L2.compile(readFile "../../6/L2/programs/boot/lex.l2", resolve, "boot/lex.l2")
const parser = L2.compile(readFile "../../6/L2/programs/boot/parse.l2", resolve, "boot/parse.l2")
const desugarer = L2.compile(readFile "boot/desugar.l2", resolve, "boot/desugar.l2")

-- The bytes of a string, as a list of integers.
local function bytesValue(s: string): VM.Value
	local v: VM.Value = VM.NIL

	for i = #s, 1, -1 do
		v = { kind = "cell"; head = string.byte(s, i) :: number; tail = v } :: VM.Cell
	end

	return v
end

-- A list of values, in order, as a value of the machine.
local function listValue(items: { VM.Value }): VM.Value
	local v: VM.Value = VM.NIL

	for i = #items, 1, -1 do
		v = { kind = "cell"; head = items[i]; tail = v } :: VM.Cell
	end

	return v
end

local function cellValue(a: VM.Value, b: VM.Value): VM.Value
	return { kind = "cell"; head = a; tail = b } :: VM.Cell
end

local function conValue(tag: number, payload: VM.Value): VM.Value
	return { kind = "con"; tag = tag; payload = payload } :: VM.Con
end

-- The text of a list of bytes.
local function textOf(v: VM.Value): string
	local out: { string } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, string.char((cur :: VM.Cell).head :: number))
		cur = (cur :: VM.Cell).tail
	end

	return table.concat(out)
end

-- The canonical text of a machine expression of the Luau desugarer.
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

-- The constructors of Code, in their declaration order: their tags.
local showCode: (VM.Value) -> string
showCode = function(v: VM.Value): string
	const con = v :: VM.Con
	const p = con.payload

	if con.tag == 0 then
		return `Q{tostring(p)}`
	elseif con.tag == 1 then
		return "N"
	elseif con.tag == 2 then
		return `V{tostring(p)}`
	elseif con.tag == 3 then
		return `(L {showCode(p)})`
	end

	const pair = p :: VM.Cell

	if con.tag == 4 then
		return `(A {showCode(pair.head)} {showCode(pair.tail)})`
	elseif con.tag == 5 then
		return `(C {showCode(pair.head)} {showCode(pair.tail)})`
	elseif con.tag == 6 then
		return `(I {tostring(pair.head)} {showCode(pair.tail)})`
	elseif con.tag == 7 then
		const rest = pair.tail :: VM.Cell
		return `(IF {showCode(pair.head)} {showCode(rest.head)} {showCode(rest.tail)})`
	elseif con.tag == 8 then
		return `(P {showCode(p)})`
	elseif con.tag == 9 then
		return `(F {showCode(p)})`
	elseif con.tag == 10 then
		return `(K {tostring(pair.head)} {showCode(pair.tail)})`
	elseif con.tag == 11 then
		return `(T {showCode(p)})`
	elseif con.tag == 12 then
		return `(Y {showCode(p)})`
	elseif con.tag == 13 then
		return `(R {tostring(pair.head)} {showCode(pair.tail)})`
	end

	const rest = pair.tail :: VM.Cell
	return `(R {tostring(pair.head)} {showCode(rest.head)} {showCode(rest.tail)})`
end

-- A machine expression of the Luau desugarer, as a value of type Code (the same tags as showCode reads).
local function codeValue(e: any): VM.Value
	const op = e.op

	if op == "quote" then
		if type(e.value) == "number" then
			return conValue(0, e.value)
		end

		return conValue(1, VM.NIL)
	elseif op == "var" then
		return conValue(2, e.index)
	elseif op == "lam" then
		return conValue(3, codeValue(e.body))
	elseif op == "apply" then
		return conValue(4, cellValue(codeValue(e.f), codeValue(e.arg)))
	elseif op == "cell" then
		return conValue(5, cellValue(codeValue(e.head), codeValue(e.tail)))
	elseif op == "index" then
		return conValue(6, cellValue(e.n, codeValue(e.e)))
	elseif op == "if" then
		return conValue(7, cellValue(codeValue(e.c), cellValue(codeValue(e.t), codeValue(e.e))))
	elseif op == "pin" then
		return conValue(8, codeValue(e.e))
	elseif op == "force" then
		return conValue(9, codeValue(e.e))
	elseif op == "construct" then
		return conValue(10, cellValue(e.tag, codeValue(e.e)))
	elseif op == "tagof" then
		return conValue(11, codeValue(e.e))
	elseif op == "payload" then
		return conValue(12, codeValue(e.e))
	elseif op == "prim" then
		if e.b ~= nil then
			return conValue(14, cellValue(e.tag, cellValue(codeValue(e.a), codeValue(e.b))))
		end

		return conValue(13, cellValue(e.tag, codeValue(e.a)))
	end

	error(`unknown expression {tostring(op)}`, 0)
end

-- A test of the checker, as a value of type Test: KAny 0, KNil 1, KInt 2, KFn 3, KPin 4, KPair 5, KList 6, KSum 7, KRec 8, KFixdef 9.
local function testValue(t: any): VM.Value
	const kind = t.kind

	if kind == "any" then
		return conValue(0, VM.NIL)
	elseif kind == "nil" then
		return conValue(1, VM.NIL)
	elseif kind == "int" then
		return conValue(2, VM.NIL)
	elseif kind == "fn" then
		return conValue(3, VM.NIL)
	elseif kind == "pin" then
		return conValue(4, VM.NIL)
	elseif kind == "pair" then
		return conValue(5, cellValue(testValue(t.a), testValue(t.b)))
	elseif kind == "list" then
		return conValue(6, cellValue(testValue(t.item), testValue(t.tail)))
	elseif kind == "sum" then
		local items: { VM.Value } = {}

		for _, c in t.ctors do
			table.insert(items, cellValue(c.tag, testValue(c.payload)))
		end

		return conValue(7, listValue(items))
	elseif kind == "rec" then
		return conValue(8, bytesValue(t.key))
	elseif kind == "fixdef" then
		return conValue(9, cellValue(bytesValue(t.key), testValue(t.body)))
	end

	error(`unknown test {tostring(kind)}`, 0)
end

-- The check nodes of a checked tree, in order: each with its position, its expect text and its test.
local function checksOf(node: any, out: { any })
	if type(node) ~= "table" then
		return
	end

	if node.k == "check" and node.test ~= nil then
		table.insert(out, { at = node.at; expect = node.expect; test = node.test })
	end

	for key, value in node do
		if key ~= "test" and type(value) == "table" then
			checksOf(value, out)
		end
	end
end

-- The input of the desugarer: its imports, its declarations, its expression, its checks, the machine expressions of its imports, and the test of its input (nil when none).
local function inputValue(imports: { string }, decls: VM.Value, expr: VM.Value, checks: { VM.Value }, importCodes: { VM.Value }, inputTest: VM.Value): VM.Value
	local names: { VM.Value } = {}

	for _, n in imports do
		table.insert(names, bytesValue(n))
	end

	return cellValue(listValue(names), cellValue(decls, cellValue(expr, cellValue(listValue(checks), cellValue(listValue(importCodes), inputTest)))))
end

-- The position of a node, as the boot parser gives it: (line . col).
local function posValue(at: any): VM.Value
	return cellValue(at.line, at.col)
end

-- The outcome of the Luau desugarer on an expression: its machine expression, or its error.
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

-- The outcome of the L2 desugarer on a parse of the source, with the given imports, checks and input test.
local function l2Outcome(src: string, imports: { string }, importExprs: { any }, checks: { VM.Value }, inputTest: VM.Value): string?
	const tokenized = L2.run(tokenizer, bytesValue(src), 1e8)

	if tokenized.status ~= "value" then
		return nil
	end

	const parsed = L2.run(parser, (tokenized.value :: VM.Con).payload, 5e8)

	if parsed.status ~= "value" or (parsed.value :: VM.Con).tag ~= 0 then
		return nil
	end

	-- The parse is Ok of (declarations . expression).
	const parts = (parsed.value :: VM.Con).payload :: VM.Cell
	const codes: { VM.Value } = {}

	for _, e in importExprs do
		table.insert(codes, codeValue(e))
	end

	const input = inputValue(imports, parts.head, parts.tail, checks, codes, inputTest)
	const result = L2.run(desugarer, input, 1e9)

	if result.status ~= "value" then
		return `machine {result.status}`
	end

	const out = result.value :: VM.Con

	if out.tag == 0 then
		return "value " .. showCode(out.payload)
	end

	return "error " .. textOf(out.payload)
end

local function report(name: string, host: string?, l2: string?)
	if host == nil or l2 == nil then
		skipped += 1
		print(`SKIP  {name}: the {if host == nil then "Luau" else "L2"} parser refuses it`)
		return
	end

	if string.find(l2, "not in the first slice", 1, true) ~= nil then
		skipped += 1
		print(`SKIP  {name}: {l2}`)
		return
	end

	total += 1

	if host == l2 then
		agreed += 1
		print(`PASS  {name}`)
	else
		failures += 1
		print(`FAIL  {name}`)
		print(`      host: {host}`)
		print(`      l2:   {l2}`)
	end
end

-- An expression: desugared without a checker, with imports (in scope) and their machine expressions.
local function checkExpr(name: string, src: string, imports: { string }?, importExprs: { any }?)
	const names = imports or {}
	const codes = importExprs or {}
	const host = hostExpr(src, names, codes)
	const l2 = l2Outcome(src, names, codes, {}, conValue(0, VM.NIL))
	report(name, host, l2)
end

-- A program: checked first. Its check nodes and the test of its input are given to the L2 desugarer as the checker gives them.
local function checkProgram(name: string, src: string)
	const parsedOk, parsed = pcall(Parser.parse, src)

	if not parsedOk then
		report(name, nil, nil)
		return
	end

	const program = parsed :: Parser.Program
	const checked, res = pcall(Checker.check, program, {}, "t.prog")

	if not checked then
		skipped += 1
		print(`SKIP  {name}: the Luau checker refuses it`)
		return
	end

	const result = res :: any
	const ctors = Desugar.buildCtors(program.decls)
	const host = "value " .. showHost(Desugar.boundary(Desugar.desugarProgram(result.expr, {}, ctors), result.input, result.inputExpect))
	const found: { any } = {}
	checksOf(result.expr, found)
	const checks: { VM.Value } = {}

	for _, c in found do
		table.insert(checks, cellValue(posValue(c.at), cellValue(bytesValue(c.expect), testValue(c.test))))
	end

	const inputTest = conValue(1, cellValue(testValue(result.input), bytesValue(result.inputExpect)))
	const l2 = l2Outcome(src, {}, {}, checks, inputTest)
	report(name, host, l2)
end

local EXPRESSIONS: { { name: string; src: string } } = {
	{ name = "an integer"; src = "5" },
	{ name = "a string"; src = "\"ab\"" },
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
	{ name = "Err applied to a string"; src = "Err \"x\"" },
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

print("desugar_run: the L2 desugarer against the Luau desugarer")

for _, c in EXPRESSIONS do
	-- A case that a checker's test would be needed for is skipped by l2Outcome: its checks are empty here.
	checkExpr(c.name, c.src)
end

checkExpr("an import in scope", "reverse 5", { "reverse" }, { VM.int(7) })
checkExpr("two imports, wrapped in order", "+ a b", { "a"; "b" }, { VM.int(1); VM.int(2) })
checkExpr("an import shadowed", "let reverse = 2\nreverse", { "reverse" }, { VM.int(7) })

for _, c in PROGRAMS do
	checkProgram(c.name, c.src)
end

print(`{agreed} agree of {total} compared, {skipped} skipped, {failures} disagree`)

if failures > 0 then
	error(`{failures} disagree`, 0)
end
