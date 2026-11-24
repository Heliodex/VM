--!strict
-- RUNS THE L2 PROGRAM FILES THROUGH THE BOOTSTRAPPED COMPILER: every stage is an L2 program run on the VM, and the host does none of the compiling
--
-- A program file is compiled as its stages go: the layout (measure/boot/layout.l2, the variant the build uses), the tokenizer and the parser (Prototypes/6/L2/programs/boot), the checker (measure/boot/types.l2, request InferT, which gives the tests of the checks and of the input), and the desugarer (Prototypes/6/L2/programs/boot/desugar.l2). Its imports are compiled the same way, and the checker and the desugarer get them. The machine expression that the desugarer gives is run on the VM, as the Luau machine runs it. Each test's input and output are read the same way, by the tokenizer, the parser and the desugarer, with no checks and the imports in scope.
--
-- The host reads the file format (the sections and the tests) and gives the machine's expressions a value, as l2_run.luau does. Each test is then checked as l2_run.luau checks it: the value's data text, or the outcome.
--
--   lute run boot_pipeline_run.luau      (from Prototypes/7/measure)

const Data = require "../../6/interpreter/data"
const L2 = require "../../6/L2/l2"
const ProgramFile = require "../../6/L2/programfile"
const VM = require "../../6/interpreter/vm"
const Lifecycle = require "../../6/interpreter/lifecycle"
const fs = require "@lute/fs"

local failures = 0
local passes = 0
local tests = 0

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

const BOOT6 = "../../6/L2/programs/boot/"

const layoutC = L2.compile(readFile "boot/layout.l2", resolve, "boot/layout.l2")
const lexC = L2.compile(readFile(BOOT6 .. "lex.l2"), resolve, "boot/lex.l2")
const parseC = L2.compile(readFile(BOOT6 .. "parse.l2"), resolve, "boot/parse.l2")
const checkC = L2.compile(readFile "boot/types.l2", resolve, "boot/types.l2")
const desugarC = L2.compile(readFile(BOOT6 .. "desugar.l2"), resolve, "boot/desugar.l2")

-- The bytes of a string, as a list of integers.
local function bytesValue(s: string): VM.Value
	local v: VM.Value = VM.NIL

	for i = #s, 1, -1 do
		v = { kind = "cell"; head = string.byte(s, i) :: number; tail = v } :: VM.Cell
	end

	return v
end

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

local function textOf(v: VM.Value): string
	local out: { string } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, string.char((cur :: VM.Cell).head :: number))
		cur = (cur :: VM.Cell).tail
	end

	return table.concat(out)
end

local function itemsOf(v: VM.Value): { VM.Value }
	local out: { VM.Value } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, (cur :: VM.Cell).head)
		cur = (cur :: VM.Cell).tail
	end

	return out
end

-- The payload of a stage's result, when the stage went through: a value tagged 0.
local function payloadOf(r: Lifecycle.Result): VM.Value?
	if r.status ~= "value" then
		return nil
	end

	const v = r.value

	if type(v) == "table" and v.kind == "con" and (v :: VM.Con).tag == 0 then
		return (v :: VM.Con).payload
	end

	return nil
end

-- A machine expression of the desugarer, as a value of type Code (tags as the desugarer declares them), gives the expression the machine runs.
local function codeToExpr(v: VM.Value): any
	const con = v :: VM.Con
	const p = con.payload
	const tag = con.tag

	if tag == 0 then
		return VM.int(p :: number)
	elseif tag == 1 then
		return VM.nilv()
	elseif tag == 2 then
		return VM.var(p :: number)
	elseif tag == 3 then
		return VM.lam(codeToExpr(p))
	end

	const pair = p :: VM.Cell

	if tag == 4 then
		return VM.app(codeToExpr(pair.head), codeToExpr(pair.tail))
	elseif tag == 5 then
		return VM.cell(codeToExpr(pair.head), codeToExpr(pair.tail))
	elseif tag == 6 then
		return VM.index(pair.head :: number, codeToExpr(pair.tail))
	elseif tag == 7 then
		const rest = pair.tail :: VM.Cell
		return VM.ite(codeToExpr(pair.head), codeToExpr(rest.head), codeToExpr(rest.tail))
	elseif tag == 8 then
		return VM.pin(codeToExpr(p))
	elseif tag == 9 then
		return VM.force(codeToExpr(p))
	elseif tag == 10 then
		return VM.construct(pair.head :: number, codeToExpr(pair.tail))
	elseif tag == 11 then
		return VM.tagof(codeToExpr(p))
	elseif tag == 12 then
		return VM.payload(codeToExpr(p))
	elseif tag == 13 then
		return VM.prim(pair.head :: number, codeToExpr(pair.tail))
	end

	const rest = pair.tail :: VM.Cell
	return VM.prim(pair.head :: number, codeToExpr(rest.head), codeToExpr(rest.tail))
end

-- A compiled file: the names of its imports, their machine expressions as values of type Code, and the file's own machine expression.
type Compiled = { names: { string }; importCodes: { VM.Value }; code: VM.Value?; expr: any; parsed: VM.Cell?; ok: boolean; why: string }

local compiled: { [string]: Compiled } = {}

local function cellOf(a: VM.Value, b: VM.Value): VM.Value
	return cellValue(a, b)
end

local compileFile: (string) -> Compiled

-- The desugarer's input: (imports . (declarations . (expression . (tests . (import codes . input test))))).
local function desugarInput(names: VM.Value, parsed: VM.Cell, checks: VM.Value, codes: VM.Value, inputTest: VM.Value): VM.Value
	return cellOf(names, cellOf(parsed.head, cellOf(parsed.tail, cellOf(checks, cellOf(codes, inputTest)))))
end

compileFile = function(path: string): Compiled
	if compiled[path] ~= nil then
		return compiled[path]
	end

	const file = ProgramFile.parse(readFile(`../../6/L2/programs/{path}.l2`), path)
	local names: { string } = {}
	local codes: { VM.Value } = {}
	local libraries: { VM.Value } = {}
	local out: Compiled = { names = names; importCodes = codes; code = nil; expr = nil; parsed = nil; ok = false; why = "" }

	for _, imp in file.imports do
		const lib = compileFile((string.gsub(imp.file, "%.l2$", "")))

		if not lib.ok then
			out.why = `import {imp.file}: {lib.why}`
			compiled[path] = out
			return out
		end

		table.insert(names, imp.name)
		table.insert(codes, lib.code :: VM.Value)
		table.insert(libraries, cellValue(bytesValue(imp.name), lib.parsed :: VM.Cell))
	end

	const laid = payloadOf(L2.run(layoutC, bytesValue(file.program), 1e10))

	if laid == nil then
		out.why = "the layout refuses it"
		compiled[path] = out
		return out
	end

	const tokens = payloadOf(L2.run(lexC, laid, 1e10))

	if tokens == nil then
		out.why = "the lexer refuses it"
		compiled[path] = out
		return out
	end

	const parsed = payloadOf(L2.run(parseC, tokens, 5e10))

	if parsed == nil then
		out.why = "the parser refuses it"
		compiled[path] = out
		return out
	end

	const parsedCell = parsed :: VM.Cell
	const checked = L2.run(checkC, conValue(5, cellValue(listValue(libraries), parsedCell)), 1e11)

	if checked.status ~= "value" then
		out.why = `the checker {checked.status}`
		compiled[path] = out
		return out
	end

	const result = (checked.value :: VM.Cell)
	const errors = itemsOf((result.tail :: VM.Cell).head)

	if #errors > 0 then
		out.why = `the checker reports: {textOf(errors[1])}`
		compiled[path] = out
		return out
	end

	const checksAndInput = (result.tail :: VM.Cell).tail :: VM.Cell
	const nameValues: { VM.Value } = {}

	for _, n in names do
		table.insert(nameValues, bytesValue(n))
	end

	const desugared = L2.run(desugarC, desugarInput(listValue(nameValues), parsedCell, checksAndInput.head, listValue(codes), checksAndInput.tail), 1e11)
	const code = payloadOf(desugared)

	if code == nil then
		out.why = `the desugarer {desugared.status}`
		compiled[path] = out
		return out
	end

	out.ok = true
	out.parsed = parsedCell
	out.code = code
	out.expr = codeToExpr(code)
	compiled[path] = out

	return out
end

-- A test's expression, read by the tokenizer, the parser and the desugarer with the imports in scope, and run on the VM: its value, or nil.
local function evalExpr(c: Compiled, text: string, fuel: number): VM.Value?
	const tokens = payloadOf(L2.run(lexC, bytesValue(text), 1e10))

	if tokens == nil then
		return nil
	end

	const parsed = payloadOf(L2.run(parseC, tokens, 5e10))

	if parsed == nil then
		return nil
	end

	const parsedCell = parsed :: VM.Cell
	local nameValues: { VM.Value } = {}

	for _, n in c.names do
		table.insert(nameValues, bytesValue(n))
	end

	const noInputCheck = conValue(0, VM.NIL)
	-- The expression sees the constructors of its file, as the host's evalText does: the declarations are the file's.
	const fileParsed = c.parsed :: VM.Cell
	const testParsed = cellValue(fileParsed.head, parsedCell.tail)
	const desugared = L2.run(desugarC, desugarInput(listValue(nameValues), testParsed, VM.NIL, listValue(c.importCodes), noInputCheck), 1e11)
	const code = payloadOf(desugared)

	if code == nil then
		return nil
	end

	const ran = VM.run(codeToExpr(code), fuel)

	if ran.status ~= "value" then
		return nil
	end

	return ran.value
end

local function report(name: string, pass: boolean, detail: string)
	tests += 1

	if pass then
		passes += 1
	else
		failures += 1
		print(`FAIL  {name}  -> {detail}`)
	end
end

-- The program files, as l2_run.luau lists them: the ones in the programs folder and its subfolders, which the bootstrapped compiler is run on.
local CORPUS = { "add_one", "block_let", "boot/desugar", "boot/layout", "boot/lex", "boot/parse", "boot/types", "cons", "division", "double", "fact", "forms", "head", "imports", "let_block", "letrec_block", "lib/abs", "lib/append", "lib/contains", "lib/filter", "lib/fold", "lib/gcd", "lib/insert", "lib/length", "lib/map", "lib/max", "lib/min", "lib/ninefold", "lib/nth", "lib/range", "lib/reverse", "lib/sort", "lib/sum", "lib/take", "lib/triple", "lib/unwrap_or", "mutual", "option", "pairs", "record_middle", "records", "remainder", "result", "sum_list", "tree" }

print("boot_pipeline_run: the L2 program files, compiled by the bootstrapped compiler")

for _, path in CORPUS do
	const c = compileFile(path)

	if not c.ok then
		report(path, false, `not compiled: {c.why}`)
	else
		const file = ProgramFile.parse(readFile(`../../6/L2/programs/{path}.l2`), path)

		for _, test in file.tests do
			const label = `{path}:{test.line}`
			const input = evalExpr(c, test.input, L2.VALUE_FUEL)

			if input == nil then
				report(label, false, `the input {test.input} does not evaluate`)
			else
				const result = Lifecycle.run(c.expr, input, test.fuel)

				if result.status == "value" then
					const got = Data.write(result.value)

					if test.outcome == "value" then
						const expected = evalExpr(c, test.output :: string, L2.VALUE_FUEL)

						if expected == nil then
							report(label, false, `the output {test.output :: string} does not evaluate`)
						else
							report(label, got == Data.write(expected), `{got} in {result.steps} steps (fuel {test.fuel})`)
						end
					else
						report(label, false, `{got}, the test expects {test.outcome}`)
					end
				else
					report(label, test.outcome == result.status, `{result.status} in {result.steps} steps (fuel {test.fuel})`)
				end
			end
		end
	end
end

print(`{passes} of {tests} tests pass through the bootstrapped compiler`)

if failures > 0 then
	error(`{failures} tests fail`, 0)
end
