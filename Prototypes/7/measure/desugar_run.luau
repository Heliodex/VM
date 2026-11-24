--!strict
-- CHECKS THE DESUGARER, WRITTEN IN L2 (measure/boot/desugar.l2), AGAINST THE LUAU DESUGARER (Prototypes/6/L2/desugar.luau)
--
-- Each input is run through the L2 tokenizer and parser, then through the L2 desugarer on the VM, and through the Luau parser and desugarer. The two must give the same machine expression, or the same error. Both are written in one notation, so the comparison is exact. An input that uses a form the first slice does not desugar yet is skipped, and counted.
--
--   lute run desugar_run.luau      (from Prototypes/7/measure)

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
local CODE_TAG = { "QInt", "QNil", "CVar", "CLam", "CApp", "CCell", "CIndex", "CIf", "CPin", "CForce", "CConstruct", "CTagof", "CPayload", "CPrim1", "CPrim2" }

-- The canonical text of a value of type Code, as the L2 desugarer gives it.
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

-- The outcome of the Luau desugarer: its expression, or its error.
local function hostOutcome(src: string): string?
	const parsedOk, parsed = pcall(Parser.parse, src)

	if not parsedOk then
		return nil
	end

	const program = parsed :: Parser.Program
	const ok, res = pcall(Desugar.desugarExpr, program.expr, {}, Desugar.buildCtors(program.decls))

	if ok then
		return "value " .. showHost(res)
	end

	return "error " .. tostring(res)
end

-- The outcome of the L2 desugarer, run on the expression of an L2 parse.
local function l2Outcome(src: string): string?
	const tokenized = L2.run(tokenizer, bytesValue(src), 1e8)

	if tokenized.status ~= "value" then
		return nil
	end

	const parsed = L2.run(parser, (tokenized.value :: VM.Con).payload, 5e8)

	if parsed.status ~= "value" or (parsed.value :: VM.Con).tag ~= 0 then
		return nil
	end

	-- The parse is Ok of (declarations . expression): the desugarer takes the expression.
	const expr = ((parsed.value :: VM.Con).payload :: VM.Cell).tail
	const result = L2.run(desugarer, expr, 1e9)

	if result.status ~= "value" then
		return `machine {result.status}`
	end

	const out = result.value :: VM.Con

	if out.tag == 0 then
		return "value " .. showCode(out.payload)
	end

	return "error " .. textOf(out.payload)
end

local function check(name: string, src: string)
	const host = hostOutcome(src)
	const l2 = l2Outcome(src)

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

local CASES: { { name: string; src: string } } = {
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
	{ name = "a binder that is a constructor"; src = "let Foo = 1\n2" },
	{ name = "a fn with a name twice"; src = "fn (x x)\n\tx" },
	{ name = "a letrec of a non-fn"; src = "letrec x = 1\nx" },
	{ name = "an arm after a catch-all"; src = "match 1 {\n\t_ -> 2\n\tOk v -> 3\n}" },
	{ name = "an unknown constructor in a match"; src = "match 1 {\n\tFoo v -> 2\n}" },
	{ name = "a constructor applied to nothing"; src = "Err" },
	{ name = "untyped"; src = "untyped 5" },
}

print("desugar_run: the L2 desugarer against the Luau desugarer")

for _, c in CASES do
	check(c.name, c.src)
end

print(`{agreed} agree of {total} compared, {skipped} skipped, {failures} disagree`)

if failures > 0 then
	error(`{failures} disagree`, 0)
end
