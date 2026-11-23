--!strict
-- GENERATES THE FIXTURES OF THE FAST MACHINE (Phase 4)
--
-- Every case is a program, the mode it runs in, an input, and a fuel budget, with the outcome the Luau reference (reference/) gives: its status, its steps, its value as bytes, or its error message. The Go machine (fast/) must give the same on every case.
--
--   body  the program's body, evaluated with the frame [NIL, input] (the reference's runForm: no law entry)
--   run   the program applied to the input (the reference's run: one law entry)
--
-- The cases are: hand-written forms, one for each rule of SPEC.md section 3 and each primitive, with the errors; the Prototype 5 examples; every test of every Prototype 6 L2 program (the same budgets cross_run uses); and the checker, Phase 0's variant checker on Prototype 6's types.l2, which is the benchmark.
--
-- Run from Prototypes/7/measure, because the L2 compiler and the file reads use paths from that folder:
--   cd Prototypes/7/measure && lute run ../fast/gen/gen.luau > ../fast/testdata/cases.txt
--
-- A line starting with # is a comment. The checker's reference timing is one of them.

const P5Examples = require "../../../5/examples/examples"
const L2 = require "../../../6/L2/l2"
const ProgramFile = require "../../../6/L2/programfile"
const Lifecycle = require "../../../6/interpreter/lifecycle"
const P6VM = require "../../../6/interpreter/vm"
const Compile = require "../../measure/compile"
const O = require "../../measure/outcomes"
const V = require "../../measure/vm_values"
const Format = require "../../reference/format"
const Int = require "../../reference/int"
const Interp = require "../../reference/interp"
const Lower = require "../../reference/lower"
const Types = require "../../reference/types"
const fs = require "@lute/fs"

type Form = Types.Form
type Value = Types.Value
type Law = Types.Law
const NIL = Format.NIL
-- The helpers that have jets (the owner names of measure/boot/types.l2 at its present lines).
-- Each helper, with the arity of the law that a jet replaces. hdOr is curried, so its jet is the inner law of two arguments (the outer law of one argument has the list as a free variable of the inner one).
const JET_ARITY: { [string]: number } = { ["tl@24"] = 1, ["hdOr@14"] = 2, ["stP@63"] = 1, ["findB@84"] = 2, ["setB@100"] = 3, ["same@39"] = 2 }
-- The laws of those helpers, as the checker's lowering makes them (filled by the benchmark below).
const jetLaws: { [string]: Law } = {}
const P6_PROGRAMS = "../../6/L2/programs/"
const BOOT6 = "../../6/L2/programs/boot/"

-- ---- builders, so the cases read like the spec
const function lit(v: Value): Form
	return { op = "lit"; value = v }
end

const function arg(i: number): Form
	return { op = "arg"; index = i }
end

const function call(f: Form, ...: Form): Form
	local args: { Form } = { ... }

	return { op = "call"; f = f; args = args }
end

-- A cell, built by the primitive cons (tag 14), as the reference's lowering builds it.
const function cellForm(a: Form, b: Form): Form
	return { op = "prim", tag = 12, args = { a, b } }
end

const function conForm(tag: number, e: Form): Form
	return { op = "con"; tag = tag; e = e }
end

const function caseForm(e: Form, alts: { Types.Alt }, elseBody: Form?): Form
	return { op = "case"; e = e; alts = alts; elseBody = elseBody }
end

const function ifForm(c: Form, t: Form, e: Form): Form
	return { op = "if"; c = c; t = t; e = e }
end

const function letForm(e: Form, b: Form): Form
	return { op = "let"; e = e; body = b }
end

const function delayForm(f: Form, ...: Form): Form
	local args: { Form } = { ... }

	return { op = "delay"; call = { op = "call"; f = f; args = args } }
end

const function forceForm(e: Form): Form
	return { op = "force"; e = e }
end

const function prim(tag: number, ...: Form): Form
	local args: { Form } = { ... }

	return { op = "prim"; tag = tag; args = args }
end

const function law(arity: number, body: Form): Law
	return { kind = "law"; arity = arity; body = body }
end

-- A value of the list (1 2 …): cells ending in nil.
const function list(...: Value): Value
	local items: { Value } = { ... }
	local v: Value = NIL

	for i = #items, 1, -1 do
		v = { kind = "cell"; head = items[i]; tail = v }
	end

	return v
end

-- ---- the output
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

-- One line of the cases file: the case, and the reference's outcome for it. A value that has no binary form is not a case (the reference's values are data, except where a case is about a thunk).
const function line(name: string, mode: string, program: Law, input: Value, fuel: number, outcome: Types.Outcome)
	const programBytes = Format.encodeProgram(program)
	const inputBytes = Format.encodeValue(input)
	local valueHex = ""
	local message = ""

	if outcome.status == "value" then
		const ok, bytes = pcall(Format.encodeValue, outcome.value)

		if not ok then
			print(`# skipped {name}: its value has no binary form`)

			return
		end

		valueHex = hex(bytes :: string)
	elseif outcome.status == "error" then
		message = outcome.message
	end

	print(
		table.concat(
			{
				name,
				mode,
				hex(programBytes :: string),
				hex(inputBytes :: string),
				string.format("%d", fuel),
				outcome.status,
				string.format("%d", outcome.steps),
				valueHex,
				message,
			},
			"\t"
		)
	)
end

-- The reference runs a case, and the case is written with its outcome.
const function emit(name: string, mode: string, program: Law, input: Value, fuel: number)
	const outcome =
		if mode == "body" then
			Interp.runForm(program.body, input, fuel)
		else
			Interp.run(program, input, fuel)
	line(name, mode, program, input, fuel, outcome)
end

-- ---- 1. hand-written cases: one for each rule of section 3, and each primitive
do
	const inc = law(1, prim(0, arg(1), lit(1)))
	const two = law(2, prim(0, arg(1), arg(2)))
	const one = law(1, prim(1, arg(1), lit(10)))
	const big100: Value = Int.fromMagnitude(false, { 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 16 })
	const bigNeg: Value = Int.fromMagnitude(true, { 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 16 })
	const pow53: Value = Int.fromMagnitude(false, { 0; 0; 0; 0; 0; 0; 32 })
	const unitLaw = law(1, arg(1))
	const thunkForm = delayForm(lit(inc), lit(1))
	emit("lit", "body", law(1, lit(7)), NIL, 100)
	emit("arg is the input", "body", law(1, arg(1)), 5, 100)
	emit("call of a law, the spec's 7 steps", "body", law(1, call(lit(inc), lit(41))), NIL, 100)
	emit("run a law on an input (one entry)", "run", inc, 41, 100)
	emit("cell list (1 2)", "body", law(1, cellForm(lit(1), cellForm(lit(2), lit(NIL)))), NIL, 100)
	emit("con 0 5", "body", law(1, conForm(0, lit(5))), NIL, 100)
	emit("case takes the payload", "body", law(1, caseForm(conForm(1, lit(9)), { { tag = 0; body = lit(0) }; { tag = 1; body = arg(2) } }, lit(0))), NIL, 100)
	emit("case else gets the constructor", "body", law(1, caseForm(conForm(5, lit(1)), { { tag = 0; body = lit(0) } }, arg(2))), NIL, 100)
	emit("case with no branch is an error", "body", law(1, caseForm(conForm(5, lit(1)), { { tag = 0; body = lit(0) } }, nil)), NIL, 100)
	emit("case of a non-constructor is an error", "body", law(1, caseForm(lit(3), { { tag = 0; body = lit(0) } }, nil)), NIL, 100)
	emit("if takes then on non-zero", "body", law(1, ifForm(lit(0), lit(1), lit(2))), NIL, 100)
	emit("if takes then on non-zero (big)", "body", law(1, ifForm(lit(big100), lit(1), lit(2))), NIL, 100)
	emit("if of nil is an error", "body", law(1, ifForm(lit(NIL), lit(1), lit(2))), NIL, 100)
	emit("let binds a slot", "body", law(1, letForm(lit(3), prim(0, arg(2), arg(2)))), NIL, 100)
	emit("let inside a call argument", "body", law(1, call(lit(inc), letForm(lit(3), prim(0, arg(2), lit(1))))), NIL, 100)
	emit("case payload then let", "body", law(1, caseForm(conForm(0, lit(4)), { { tag = 0; body = letForm(lit(2), prim(0, arg(2), arg(3))) } }, nil)), NIL, 100)
	emit("delay then force", "body", law(1, forceForm(thunkForm)), NIL, 100)
	emit("force twice runs the call once", "body", law(1, letForm(thunkForm, cellForm(forceForm(arg(2)), forceForm(arg(2))))), NIL, 100)
	emit("force of a non-thunk is an error", "body", law(1, forceForm(lit(5))), NIL, 100)
	emit("kind of each kind of value", "body", law(1, cellForm(prim(7, lit(5)), cellForm(prim(7, lit(NIL)), cellForm(prim(7, cellForm(lit(1), lit(2))), cellForm(prim(7, lit(inc)), cellForm(prim(7, conForm(1, lit(1))), prim(7, thunkForm))))))), NIL, 100)
	emit("head and tail of a cell", "body", law(1, cellForm(prim(8, cellForm(lit(1), lit(2))), prim(9, cellForm(lit(1), lit(2))))), NIL, 100)
	emit("head of a non-cell is an error", "body", law(1, prim(8, lit(5))), NIL, 100)
	emit("tail of a non-cell is an error", "body", law(1, prim(9, lit(NIL))), NIL, 100)
	emit("division rounds down", "body", law(1, cellForm(prim(3, lit(-7), lit(2)), cellForm(prim(3, lit(7), lit(-2)), cellForm(prim(4, lit(-7), lit(2)), prim(4, lit(7), lit(-2)))))), NIL, 100)
	emit("division by zero is an error", "body", law(1, prim(3, lit(1), lit(0))), NIL, 100)
	emit("modulus by zero is an error", "body", law(1, prim(4, lit(1), lit(0))), NIL, 100)
	emit("lt and eq", "body", law(1, cellForm(prim(5, lit(1), lit(2)), cellForm(prim(5, lit(2), lit(1)), cellForm(prim(6, lit(3), lit(3)), prim(6, lit(3), lit(4)))))), NIL, 100)
	emit("integer operations on integers that are not int64 (2^100 squared)", "body", law(1, prim(2, lit(big100), lit(big100))), NIL, 100)
	emit("2^53 - 1 plus 1 is 2^53", "body", law(1, prim(0, lit(Int.MAX_SAFE), lit(1))), NIL, 100)
	emit("-2^100 minus 1", "body", law(1, prim(1, lit(bigNeg), lit(1))), NIL, 100)
	emit("2^100 div 2^53", "body", law(1, prim(3, lit(big100), lit(pow53))), NIL, 100)
	emit("-2^100 mod 7 (sign of the divisor)", "body", law(1, prim(4, lit(bigNeg), lit(7))), NIL, 100)
	emit("2^100 as a value", "body", law(1, lit(big100)), NIL, 100)
	emit("tagof a constructor, of a number", "body", law(1, cellForm(prim(10, conForm(3, lit(1))), cellForm(prim(10, lit(5)), prim(11, conForm(3, lit(9)))))), NIL, 100)
	emit("payload of a non-constructor is an error", "body", law(1, prim(11, lit(5))), NIL, 100)
	emit("a partial application is a function", "body", law(1, call(lit(two), lit(1))), NIL, 100)
	emit("a partial application completed", "body", law(1, call(call(lit(two), lit(1)), lit(2))), NIL, 100)
	emit("over-application applies the result", "body", law(1, call(lit(law(1, lit(one))), lit(0), lit(5))), NIL, 100)
	emit("a call of a non-function is an error", "body", law(1, call(lit(5), lit(1))), NIL, 100)
	emit("no slot is an error", "body", law(1, arg(5)), NIL, 100)
	emit("the identity law", "body", law(1, call(lit(unitLaw), lit(42))), NIL, 100)
	-- recursion by self-reference: count n, down to zero
	const count = law(1, ifForm(arg(1), call(arg(0), prim(1, arg(1), lit(1))), lit(0)))
	emit("self-reference counts down", "run", count, 100, 100000)
	emit("out of fuel", "run", count, 1e6, 50)
	emit("out of fuel at the first step", "body", law(1, lit(1)), NIL, 0)
	-- a deep program: 20,000 lets, each binding a literal, in the body of one law
	local deep: Form = arg(1)

	for i = 1, 20000 do
		deep = letForm(lit(i), deep)
	end

	emit("a program 20,000 forms deep", "body", law(1, deep), 7, 1e6)
end

-- ---- 2. the Prototype 5 examples, with the budget cross_run gives them
for _, ex in P5Examples do
	emit(`P5 {ex.name}`, "body", law(1, Lower.expr(ex.program)), NIL, 20 * ex.fuel)
end

-- ---- 3. every test of every L2 program in Prototype 6
const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

const function resolve(name: string): string?
	const ok, text = pcall(readFile, P6_PROGRAMS .. name)

	if ok then
		return text :: string
	end

	return nil
end

-- A test's input as a value of the core (cross_run's convertInput): integers, nil, cells and constructors deeply, and a closed closure lowered to a law.
local function convertInput(v: P6VM.Value): Value
	if type(v) == "number" then
		return v
	end

	if v.kind == "closure" then
		if v.env ~= nil then
			error("an input closure with an environment cannot be lowered", 0)
		end

		return Lower.closedClosure(v.body)
	elseif v.kind == "nil" then
		return NIL
	elseif v.kind == "cell" then
		return { kind = "cell"; head = convertInput(v.head); tail = convertInput(v.tail) }
	elseif v.kind == "con" then
		return { kind = "con"; tag = v.tag; payload = convertInput(v.payload) }
	end

	error("an input value of kind " .. tostring(v.kind) .. " cannot be converted", 0)
end

do
	local files: { string } = {}

	const function listDir(folder: string, prefix: string)
		for _, entry in fs.listdir(folder) do
			if entry.type == "dir" then
				listDir(`{folder}/{entry.name}`, `{prefix}{entry.name}/`)
			elseif entry.type == "file" and string.sub(entry.name, -3) == ".l2" then
				table.insert(files, `{prefix}{entry.name}`)
			end
		end
	end

	listDir(P6_PROGRAMS, "")

	for _, name in files do
		const compiled = L2.compile(readFile(P6_PROGRAMS .. name), resolve, name)
		const file = ProgramFile.parse(readFile(P6_PROGRAMS .. name), name)
		const program = Lower.expr(compiled.expr)

		for i, test in file.tests do
			local ran, input = pcall(L2.evalText, compiled, test.input, L2.VALUE_FUEL)

			if ran then
				local converted: Value? = nil
				local okConvert = pcall(function()
					converted = convertInput(input :: P6VM.Value)
				end)

				if okConvert then
					emit(`P6 {name} test {i}`, "body", law(1, call(program, arg(1))), converted :: Value, 20 * test.fuel + 10000)
				end
			end
		end
	end
end

-- ---- 4. the benchmark: the variant checker (measure/boot/types.l2) on Prototype 6's types.l2
do
	const layoutC = Compile.compile(readFile "boot/layout.l2", "boot/layout.l2")
	const lexer = Compile.compile(readFile(BOOT6 .. "lex.l2"), "lex.l2")
	const parser = Compile.compile(readFile(BOOT6 .. "parse.l2"), "parse.l2")
	const checker = Compile.compile(readFile "boot/types.l2", "boot/types.l2")
	const typesP6 = Compile.compile(readFile(BOOT6 .. "types.l2"), "types.l2")
	-- The request: the input of the checker, as the VM's own layout, lex and parse give it.
	const laid = Lifecycle.run(layoutC.expr, V.bytesValue(typesP6.raw), 1e10)
	const lexed = Lifecycle.run(lexer.expr, O.payloadOf(O.valueOf(laid)), 1e8)
	const parsed = Lifecycle.run(parser.expr, O.payloadOf(O.valueOf(lexed)), 5e8)
	const request: P6VM.Value = { kind = "con"; tag = 3; payload = O.payloadOf(O.valueOf(parsed)) }
	const input = convertInput(request)
	const body = call(
		Lower.expr(
			checker.expr,
			function(e, l)
				const owner = V.ownerOf(e)
				print(`# law {owner} {l.arity} {hex(Format.encodeValue(l) :: string)}`)

				if JET_ARITY[owner] == l.arity then
					jetLaws[owner] = l
				end
			end
		),
		arg(1)
	)
	const started = os.clock()
	const outcome = Interp.runForm(body, input, 1e10)
	const seconds = os.clock() - started
	print(`# reference checker: {outcome.status} after {string.format("%d", outcome.steps)} steps in {string.format("%.3f", seconds)}s`)
	line("checker: variant types.l2 on types.l2", "body", law(1, body), input, 1e10, outcome)
end

-- ---- 5. the jets: each law a jet replaces, called on a range of inputs. The reference's steps are the fuel a jet must declare.
-- Each jet's law, as the value's bytes with the header (sha256 of them without the first byte is the content hash, SPEC.md 12.7).
for owner, l in jetLaws do
	print(`# jet {owner} lawvalue {hex(Format.encodeValue(l) :: string)}`)
end

do
	const tl = jetLaws["tl@24"]
	const hd = jetLaws["hdOr@14"]
	const st = jetLaws["stP@63"]
	const big: Value = Int.fromMagnitude(false, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16 })

	for i, v in { NIL, { kind = "cell", head = 1, tail = NIL } :: Value, { kind = "cell", head = { kind = "cell", head = 1, tail = 2 }, tail = 3 } :: Value, { kind = "cell", head = NIL, tail = NIL } :: Value, 5, big, { kind = "con", tag = 0, payload = 1 } :: Value, list(1, 2) } do
		emit(`jet tl@24 {i}`, "body", law(1, call(lit(tl), arg(1))), v, 1000)
	end

	for i, v in { NIL, list(5), list(NIL), 5, { kind = "con", tag = 0, payload = 1 } :: Value, { kind = "cell", head = big, tail = NIL } :: Value } do
		for j, d in { 0, 7, NIL } do
			emit(`jet hdOr@14 {i}.{j}`, "body", law(1, call(lit(hd), arg(1), lit(d))), v, 1000)
		end
	end

	for i, v in { { kind = "con", tag = 0, payload = list(3, NIL) } :: Value, NIL, 5, { kind = "con", tag = 1, payload = 2 } :: Value, list(1) } do
		emit(`jet stP@63 {i}`, "body", law(1, call(lit(st), arg(1))), v, 1000)
	end
end

-- ---- 6. the radix-4 trie of the checker (findB and setB): random tries, built as the checker builds them (SPEC-free: the constructors are tags 0 for TEmpty, 1 for TNode, and the node is (binding . (c0 . (c1 . (c2 . c3))))), with ids and bindings at random, and the fuel at the edges of each call's cost.
do
	math.randomseed(7)
	const EMPTY: Value = { kind = "con", tag = 0, payload = NIL }

	const function bindOf(): Value
		if math.random(0, 1) == 0 then
			return { kind = "con", tag = 0, payload = math.random(0, 3) }
		end

		return { kind = "con", tag = 1, payload = math.random(0, 9) }
	end

	const function kidsOf(a: Value, b: Value, c: Value, d: Value): Value
		return { kind = "cell", head = a, tail = { kind = "cell", head = b, tail = { kind = "cell", head = c, tail = d } } }
	end

	local function randomTrie(depth: number): Value
		if depth == 0 or math.random() < 0.3 then
			return EMPTY
		end

		const payload: Value = { kind = "cell", head = bindOf(), tail = kidsOf(randomTrie(depth - 1), randomTrie(depth - 1), randomTrie(depth - 1), randomTrie(depth - 1)) }

		return { kind = "con", tag = 1, payload = payload }
	end

	const F = jetLaws["findB@84"]
	const S = jetLaws["setB@100"]

	for i = 1, 300 do
		const trie = randomTrie(4)
		const id = math.random(0, 255)
		emit(`jet findB@84 {i}`, "body", law(1, call(lit(F), arg(1), lit(id))), trie, 1e6)
	end

	-- the fuel edges: exactly the call's steps, and one less
	for i = 1, 40 do
		const trie = randomTrie(4)
		const id = math.random(0, 255)
		const outcome = Interp.runForm(call(lit(F), arg(1), lit(id)), trie, 1e6)
		emit(`jet findB@84 edge {i} exact`, "body", law(1, call(lit(F), arg(1), lit(id))), trie, outcome.steps)
		emit(`jet findB@84 edge {i} one less`, "body", law(1, call(lit(F), arg(1), lit(id))), trie, outcome.steps - 1)
	end

	emit("jet findB@84 negative id", "body", law(1, call(lit(F), arg(1), lit(-1))), EMPTY, 500)

	for i = 1, 300 do
		const trie = randomTrie(4)
		const id = math.random(0, 255)
		const b = bindOf()
		emit(`jet setB@100 {i}`, "body", law(1, call(lit(S), arg(1), lit(id), lit(b))), trie, 1e6)
	end

	for i = 1, 40 do
		const trie = randomTrie(4)
		const id = math.random(0, 255)
		const b = bindOf()
		const outcome = Interp.runForm(call(lit(S), arg(1), lit(id), lit(b)), trie, 1e6)
		emit(`jet setB@100 edge {i} exact`, "body", law(1, call(lit(S), arg(1), lit(id), lit(b))), trie, outcome.steps)
		emit(`jet setB@100 edge {i} one less`, "body", law(1, call(lit(S), arg(1), lit(id), lit(b))), trie, outcome.steps - 1)
	end
end

-- ---- 7. the incremental re-check (Phase 7): the same checker on Prototype 6's types.l2, with one declaration changed. The change is div10's error branch, from 0 to 1: one line of one function.
do
	const base = readFile(BOOT6 .. "types.l2")
	const marker = "Err e -> 0\nlet mod10"
	const found = string.find(base, marker, 1, true)

	if found == nil then
		error("the marker of the changed declaration is not in types.l2", 0)
	end

	const second = string.find(base, marker, found + 1, true)

	if second ~= nil then
		error("the marker of the changed declaration is not unique", 0)
	end

	const modified = string.sub(base, 1, found - 1) .. "Err e -> 1\nlet mod10" .. string.sub(base, found + #marker)
	const modC = Compile.compile(modified, "types.l2")
	const laid = Lifecycle.run(Compile.compile(readFile "boot/layout.l2", "boot/layout.l2").expr, V.bytesValue(modC.raw), 1e10)
	const lexer = Compile.compile(readFile(BOOT6 .. "lex.l2"), "lex.l2")
	const parser = Compile.compile(readFile(BOOT6 .. "parse.l2"), "parse.l2")
	const lexed = Lifecycle.run(lexer.expr, O.payloadOf(O.valueOf(laid)), 1e8)
	const parsed = Lifecycle.run(parser.expr, O.payloadOf(O.valueOf(lexed)), 5e8)
	const request: P6VM.Value = { kind = "con", tag = 3, payload = O.payloadOf(O.valueOf(parsed)) }
	const input = convertInput(request)
	const checkerExpr = Compile.compile(readFile "boot/types.l2", "boot/types.l2")
	const body = call(Lower.expr(checkerExpr.expr, nil), arg(1))
	const outcome = Interp.runForm(body, input, 1e10)
	print(`# changed declaration: {outcome.status} after {string.format("%d", outcome.steps)} steps`)
	line("checker: variant types.l2 with div10 changed", "body", law(1, body), input, 1e10, outcome)
end

-- ---- 8. the name comparison, same (measure/boot/types.l2): two lists, compared a byte at a time. Random names, equal names, names that differ in their last byte, non-lists, and elements that are not integers (which the body refuses, so the jet must give up there).
do
	math.randomseed(11)
	const SAME = jetLaws["same@39"]

	const function listOf(items: { number }): Value
		return list(table.unpack(items))
	end

	const function randomItems(): { number }
		local items: { number } = {}

		for _ = 1, math.random(0, 4) do
			table.insert(items, math.random(0, 2))
		end

		return items
	end

	for i = 1, 300 do
		const a = randomItems()
		local b = randomItems()

		if i % 3 == 0 then
			b = table.clone(a)
		elseif i % 3 == 1 then
			b = table.clone(a)

			if #b > 0 then
				b[#b] = (b[#b] + 1) % 3
			end
		end

		emit(`jet same@39 {i}`, "body", law(1, call(lit(SAME), arg(1), lit(listOf(b)))), listOf(a), 1e6)
	end

	emit("jet same@39 nil and nil", "body", law(1, call(lit(SAME), arg(1), lit(NIL))), NIL, 1000)
	emit("jet same@39 nil and a number", "body", law(1, call(lit(SAME), arg(1), lit(5))), NIL, 1000)
	emit("jet same@39 a number and nil", "body", law(1, call(lit(SAME), arg(1), lit(NIL))), 5, 1000)
	emit("jet same@39 a number and a list", "body", law(1, call(lit(SAME), arg(1), lit(list(1)))), 5, 1000)
	emit("jet same@39 a list and a number", "body", law(1, call(lit(SAME), arg(1), lit(7))), list(1), 1000)
	emit("jet same@39 a big element", "body", law(1, call(lit(SAME), arg(1), lit(list(1, 2)))), list(Int.fromMagnitude(false, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16 })), 1000)
	emit("jet same@39 a cell element", "body", law(1, call(lit(SAME), arg(1), lit(list(1)))), list({ kind = "cell", head = 1, tail = 2 } :: Value), 1000)
	-- the fuel edges, on a name that recurses
	const deep = listOf { 0, 1, 2, 0, 1 }
	const outcome = Interp.runForm(call(lit(SAME), arg(1), lit(deep)), deep, 1e6)
	emit("jet same@39 edge exact", "body", law(1, call(lit(SAME), arg(1), lit(deep))), deep, outcome.steps)
	emit("jet same@39 edge one less", "body", law(1, call(lit(SAME), arg(1), lit(deep))), deep, outcome.steps - 1)
end

-- ---- 9. the corpus helpers that take most of the interpreted steps: first (the checker's and the parser's), hd (the layout's) and kn (the parser's token kinds). Each is a law of one argument, so its jet is a walk of one match, and its cost is one number per arm.

do
	const wanted: { [string]: number } = { ["check:first@19"] = 1, ["layout:hd@11"] = 1, ["parse:kn@22"] = 1 }
	const found: { [string]: Law } = {}

	const function collect(c: Compile.Compiled, stage: string)
		Lower.expr(c.expr, function(e, l)
			const key = `{stage}:{V.ownerOf(e)}`

			if wanted[key] == l.arity then
				found[key] = l
			end
		end)
	end

	collect(Compile.compile(readFile("boot/layout.l2"), "boot/layout.l2"), "layout")
	collect(Compile.compile(readFile(BOOT6 .. "parse.l2"), "parse.l2"), "parse")
	collect(Compile.compile(readFile("boot/types.l2"), "boot/types.l2"), "check")

	const firstLaw = found["check:first@19"]
	const hdLaw = found["layout:hd@11"]
	const knLaw = found["parse:kn@22"]

	const inputs: { Value } = {
		NIL,
		{ kind = "cell", head = 1, tail = NIL },
		{ kind = "cell", head = { kind = "cell", head = 1, tail = 2 }, tail = 3 },
		{ kind = "cell", head = NIL, tail = NIL },
		5,
		{ kind = "con", tag = 0, payload = 1 },
	}

	for i, v in inputs do
		emit(`jet check:first@19 {i}`, "body", law(1, call(lit(firstLaw), arg(1))), v, 1000)
		emit(`jet layout:hd@11 {i}`, "body", law(1, call(lit(hdLaw), arg(1))), v, 1000)
	end

	for k = 0, 17 do
		const token: Value = { kind = "cell", head = { kind = "con", tag = k, payload = NIL }, tail = NIL }
		emit(`jet parse:kn@22 tag {k}`, "body", law(1, call(lit(knLaw), arg(1))), token, 1000)
	end

	emit("jet parse:kn@22 not a token", "body", law(1, call(lit(knLaw), arg(1))), 5, 1000)
	emit("jet parse:kn@22 nil", "body", law(1, call(lit(knLaw), arg(1))), NIL, 1000)
end

-- ---- 10. the list helpers the corpus runs most, in the checker and the parser: lenOf (the checker's length), envKid and envPut (the checker's name environment, a list of (byte . node) pairs), and same as the parser has it (a different body from the checker's: its test on a list is a nil test, so a number is not a cell, and the walk gives up on that). Each is found by its owner and arity, as in section 9, and called on lists, with the arguments of the call read from one pair (or a triple of pairs), so every arm of each body is taken: a list that ends, a key found or not, a number and a nil, a non-number key that the body refuses.

do
	math.randomseed(23)
	const wanted: { [string]: number } = { ["check:lenOf@55"] = 1, ["check:envKid@292"] = 2, ["check:envPut@302"] = 3, ["parse:same@20"] = 2 }
	const found: { [string]: Law } = {}

	const function collect(c: Compile.Compiled, stage: string)
		Lower.expr(c.expr, function(e, l)
			const key = `{stage}:{V.ownerOf(e)}`

			if wanted[key] == l.arity then
				found[key] = l
			end
		end)
	end

	collect(Compile.compile(readFile("boot/types.l2"), "boot/types.l2"), "check")
	collect(Compile.compile(readFile(BOOT6 .. "parse.l2"), "parse.l2"), "parse")

	const LEN = found["check:lenOf@55"]
	const KID = found["check:envKid@292"]
	const PUT = found["check:envPut@302"]
	const SAME = found["parse:same@20"]

	const function cellV(a: Value, b: Value): Value
		return { kind = "cell", head = a, tail = b }
	end

	const function listOfV(items: { Value }): Value
		local v: Value = NIL

		for i = #items, 1, -1 do
			v = cellV(items[i], v)
		end

		return v
	end

	const function randInts(n: number, hi: number): { Value }
		local out: { Value } = {}

		for _ = 1, n do
			table.insert(out, math.random(0, hi))
		end

		return out
	end

	-- lenOf: lists of 0 to 12 numbers, and values that are not lists.
	for i = 1, 40 do
		emit(`jet check:lenOf@55 {i}`, "body", law(1, call(lit(LEN), arg(1))), listOfV(randInts(math.random(0, 12), 9)), 1e6)
	end

	emit("jet check:lenOf@55 a number", "body", law(1, call(lit(LEN), arg(1))), 5, 1000)
	emit("jet check:lenOf@55 a pair", "body", law(1, call(lit(LEN), arg(1))), cellV(1, 2), 1000)
	emit("jet check:lenOf@55 a constructor", "body", law(1, call(lit(LEN), arg(1))), { kind = "con", tag = 0, payload = 1 }, 1000)

	-- envKid: (kids . b), kids a list of (key . value) pairs, with keys 0 to 5; b is a key, or a key that is not in the list, or a non-number.
	for i = 1, 60 do
		local entries: { Value } = {}

		for k = 0, math.random(0, 6) do
			table.insert(entries, cellV(k * 2 + math.random(0, 1) * 0, math.random(0, 9)))
		end

		const b = math.random(0, 14)
		emit(`jet check:envKid@292 {i}`, "body", law(1, call(lit(KID), prim(8, arg(1)), prim(9, arg(1)))), cellV(listOfV(entries), b), 1e6)
	end

	emit("jet check:envKid@292 no list", "body", law(1, call(lit(KID), prim(8, arg(1)), prim(9, arg(1)))), cellV(5, 1), 1000)
	emit("jet check:envKid@292 nil", "body", law(1, call(lit(KID), prim(8, arg(1)), prim(9, arg(1)))), cellV(NIL, 1), 1000)
	emit("jet check:envKid@292 a key that is not a number", "body", law(1, call(lit(KID), prim(8, arg(1)), prim(9, arg(1)))), cellV(listOfV({ cellV({ kind = "con", tag = 0, payload = 1 }, 2) }), 1), 1000)
	emit("jet check:envKid@292 a non-number b", "body", law(1, call(lit(KID), prim(8, arg(1)), prim(9, arg(1)))), cellV(listOfV({ cellV(1, 2) }), { kind = "con", tag = 0, payload = 1 }), 1000)

	-- envPut: (kids . (b . child)), the same kids, and a child that is a number.
	for i = 1, 60 do
		local entries: { Value } = {}

		for k = 0, math.random(0, 6) do
			table.insert(entries, cellV(k, math.random(0, 9)))
		end

		const b = math.random(0, 7)
		emit(`jet check:envPut@302 {i}`, "body", law(1, call(lit(PUT), prim(8, arg(1)), prim(8, prim(9, arg(1))), prim(9, prim(9, arg(1))))), cellV(listOfV(entries), cellV(b, math.random(0, 9))), 1e6)
	end

	emit("jet check:envPut@302 nil", "body", law(1, call(lit(PUT), prim(8, arg(1)), prim(8, prim(9, arg(1))), prim(9, prim(9, arg(1))))), cellV(NIL, cellV(1, 2)), 1000)
	emit("jet check:envPut@302 a number", "body", law(1, call(lit(PUT), prim(8, arg(1)), prim(8, prim(9, arg(1))), prim(9, prim(9, arg(1))))), cellV(5, cellV(1, 2)), 1000)

	-- parse's same: (a . b), lists of numbers from 0 to 2, equal, differing in the last, of different length; a nil and a number; non-numbers.
	for i = 1, 300 do
		const a = randInts(math.random(0, 4), 2)
		local b: { Value } = {}

		if i % 3 == 0 then
			b = table.clone(a)
		elseif i % 3 == 1 then
			b = table.clone(a)

			if #b > 0 then
				b[#b] = ((b[#b] :: number) + 1) % 3
			end
		else
			b = randInts(math.random(0, 4), 2)
		end

		emit(`jet parse:same@20 {i}`, "body", law(1, call(lit(SAME), prim(8, arg(1)), prim(9, arg(1)))), cellV(listOfV(a), listOfV(b)), 1e6)
	end

	emit("jet parse:same@20 nil and nil", "body", law(1, call(lit(SAME), prim(8, arg(1)), prim(9, arg(1)))), cellV(NIL, NIL), 1000)
	emit("jet parse:same@20 nil and a list", "body", law(1, call(lit(SAME), prim(8, arg(1)), prim(9, arg(1)))), cellV(NIL, listOfV({ 1 })), 1000)
	emit("jet parse:same@20 a list and nil", "body", law(1, call(lit(SAME), prim(8, arg(1)), prim(9, arg(1)))), cellV(listOfV({ 1 }), NIL), 1000)
	emit("jet parse:same@20 a number and nil", "body", law(1, call(lit(SAME), prim(8, arg(1)), prim(9, arg(1)))), cellV(5, NIL), 1000)
	emit("jet parse:same@20 nil and a number", "body", law(1, call(lit(SAME), prim(8, arg(1)), prim(9, arg(1)))), cellV(NIL, 5), 1000)
	emit("jet parse:same@20 a non-number element", "body", law(1, call(lit(SAME), prim(8, arg(1)), prim(9, arg(1)))), cellV(listOfV({ { kind = "con", tag = 0, payload = 1 } }), listOfV({ 1 })), 1000)
end

-- ---- 11. prune (the checker's chase of a type variable through the trie's bindings): random tries of bindings, Unbound or Bound to a type variable of a larger id (so the chase ends) or to a constructor, built as the checker builds them (section 6's layout), and types that are variables and constructors, with the edge inputs the jet must refuse.
do
	math.randomseed(31)
	const PRUNE_ARITY = 2
	const found: { [string]: Law } = {}

	Lower.expr((Compile.compile(readFile("boot/types.l2"), "boot/types.l2")).expr, function(e, l)
		if V.ownerOf(e) == "prune@126" and l.arity == PRUNE_ARITY then
			found["prune"] = l
		end
	end)

	const PRUNE = found["prune"]
	const EMPTY: Value = { kind = "con", tag = 0, payload = NIL }

	const function tvar(id: number): Value
		return { kind = "con", tag = 0, payload = id }
	end

	const function tcon(): Value
		return { kind = "con", tag = 1, payload = { kind = "cell", head = NIL, tail = NIL } }
	end

	const function cellV(a: Value, b: Value): Value
		return { kind = "cell", head = a, tail = b }
	end

	-- A trie of the entries { id, binding }, built as the checker's setB builds it: the binding of id 0 is the node's own, and id is split into id div 4 and id mod 4 below the node.
	local function trieOf(entries: { { id: number, b: Value } }): Value
		if #entries == 0 then
			return EMPTY
		end

		local root: Value = { kind = "con", tag = 0, payload = 0 }
		local subs: { { { id: number, b: Value } } } = { {}, {}, {}, {} }

		for _, e in entries do
			if e.id == 0 then
				root = e.b
			else
				table.insert(subs[(e.id % 4) + 1], { id = e.id // 4, b = e.b })
			end
		end

		local kids = cellV(trieOf(subs[1]), cellV(trieOf(subs[2]), cellV(trieOf(subs[3]), trieOf(subs[4]))))

		return { kind = "con", tag = 1, payload = cellV(root, kids) }
	end

	local function randomEntries(): { { id: number, b: any } }
		local entries: { { id: number, b: any } } = {}

		for id = 0, 15 do
			if math.random() < 0.6 then
				local b: any

				if math.random() < 0.5 then
					b = { kind = "con", tag = 0, payload = math.random(0, 3) }
				elseif id < 15 and math.random() < 0.7 then
					b = { kind = "con", tag = 1, payload = tvar(math.random(id + 1, 15)) }
				else
					b = { kind = "con", tag = 1, payload = tcon() }
				end

				table.insert(entries, { id = id, b = b })
			end
		end

		return entries
	end

	local function callPrune(): Form
		return call(lit(PRUNE), prim(8, arg(1)), prim(9, arg(1)))
	end

	for i = 1, 400 do
		const entries = randomEntries()
		local t: Value

		if math.random() < 0.8 then
			t = tvar(math.random(0, 15))
		else
			t = tcon()
		end

		emit(`jet check:prune@126 {i}`, "body", law(1, callPrune()), cellV(trieOf(entries), t), 1e6)
	end

	emit("jet check:prune@126 not a type", "body", law(1, callPrune()), cellV(EMPTY, 5), 1000)
	emit("jet check:prune@126 a negative variable", "body", law(1, callPrune()), cellV(EMPTY, tvar(-1)), 1000)
	emit("jet check:prune@126 a constructor of tag 2", "body", law(1, callPrune()), cellV(EMPTY, { kind = "con", tag = 2, payload = 0 }), 1000)
	emit("jet check:prune@126 a variable in an empty trie", "body", law(1, callPrune()), cellV(EMPTY, tvar(7)), 1000)
end

