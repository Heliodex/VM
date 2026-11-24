--!strict
-- THE BOOTSTRAPPED COMPILER, AS A MODULE: a program file, given as text, through the L2 stages, each an L2 program run on the VM
--
-- The stages are the layout (Prototypes/6/L2/programs/boot/layout.l2), the tokenizer and the parser (boot/lex.l2, boot/parse.l2), the checker (boot/types.l2, request InferT, which gives the tests of the checks and of the input), and the desugarer (boot/desugar.l2). The imports of a file are compiled the same way, and the checker and the desugarer get them. The desugarer's machine expression is what the file runs as.
--
-- A stage that refuses gives its message: compileText reports the stage and the message, and the file is not compiled. The host reads the file format (the sections and the tests) with ProgramFile, and nothing else.
--
--   local pipeline = require "./boot_pipeline"       (from Prototypes/7/measure)

const L2 = require "../../6/L2/l2"
const ProgramFile = require "../../6/L2/programfile"
const Lifecycle = require "../../6/interpreter/lifecycle"
const VM = require "../../6/interpreter/vm"
const fs = require "@lute/fs"

local M = {}

local function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

-- The programs folder of Prototype 6, where the boot stages and the library files are.
M.PROGRAMS = "../../6/L2/programs/"

local function resolve(name: string): string?
	const ok, text = pcall(readFile, M.PROGRAMS .. name)

	if ok then
		return text :: string
	end

	return nil
end

local stages: { [string]: any } = {}

-- A stage, compiled once: the layout is the one in the boot folder, the others are the same files.
local function stage(name: string): any
	if stages[name] == nil then
		stages[name] = L2.compile(readFile(M.PROGRAMS .. "boot/" .. name .. ".l2"), resolve, "boot/" .. name .. ".l2")
	end

	return stages[name]
end

M.stage = stage

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

M.bytesValue = bytesValue
M.textOf = textOf
M.itemsOf = itemsOf

-- A stage's result: its tag and payload, when it finished, or the status it ended with.
local function runStage(name: string, input: VM.Value, fuel: number): (number?, VM.Value?, string)
	const r = Lifecycle.run(stage(name).expr, input, fuel)

	if r.status ~= "value" then
		return nil, nil, r.status
	end

	const v = r.value :: VM.Con

	return v.tag, v.payload, "value"
end

M.runStage = runStage

-- The desugarer's machine expression, as a value of type Code (the tags the desugarer declares), as an expression of the machine.
-- Whether two expressions have the same form, as tables: the fixed point is recognised by its form, since codeToExpr makes new tables.
local function sameForm(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	for k, v in a do
		if not sameForm(v, b[k]) then
			return false
		end
	end

	for k in b do
		if a[k] == nil then
			return false
		end
	end

	return true
end

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
		-- The desugarer's fixed point (fixCode) is the machine's VM.fix: the lowering finds it by its identity, so the same form is given the identity.
		local f = codeToExpr(pair.head)

		if sameForm(f, VM.fix) then
			f = VM.fix
		end

		return VM.app(f, codeToExpr(pair.tail))
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

M.codeToExpr = codeToExpr
-- A compiled file. When ok is false, stage says which stage refused it, and message is its message.
export type Compiled = {
	ok: boolean,
	stage: string?,
	message: string?,
	names: { string },
	importCodes: { VM.Value },
	code: VM.Value?,
	expr: any,
	parsed: VM.Cell?,
}

local function refused(out: Compiled, name: string, message: string): Compiled
	out.stage = name
	out.message = message

	return out
end

-- The desugarer's input: (imports . (declarations . (expression . (tests . (import codes . input test))))).
local function desugarInput(names: VM.Value, parsed: VM.Cell, checks: VM.Value, codes: VM.Value, inputTest: VM.Value): VM.Value
	return cellValue(names, cellValue(parsed.head, cellValue(parsed.tail, cellValue(checks, cellValue(codes, inputTest)))))
end

-- Compiles a program file given as text, with the imports that loadImport gives by their path (for example lib/reverse.l2).
local compileTextInner: (string, string, (string) -> string) -> Compiled
compileTextInner = function(text: string, name: string, loadImport: (string) -> string): Compiled
	-- The host lays out a section only when its file is named .l2, and the boot layout is run on the same condition: the reader gives the raw section.
	const file = ProgramFile.parse(text, nil)
	const laysOut = string.sub(name, -3) == ".l2"
	-- The compiled imports, by their path: each library is compiled once.
	const imports: { [string]: Compiled } = {}
	local names: { string } = {}
	local codes: { VM.Value } = {}
	local libraries: { VM.Value } = {}
	local out: Compiled = { ok = false; stage = nil; message = nil; names = names; importCodes = codes; code = nil; expr = nil; parsed = nil }

	for _, imp in file.imports do
		if imports[imp.file] == nil then
			const loadedOk, loaded = pcall(loadImport, imp.file)

			if not loadedOk then
				return refused(out, "import", `cannot find {imp.file}`)
			end

			imports[imp.file] = compileTextInner(loaded :: string, imp.file, loadImport)
		end

		const lib = imports[imp.file]

		if not lib.ok then
			return refused(out, `import {imp.file} ({lib.stage})`, lib.message :: string)
		end

		table.insert(names, imp.name)
		table.insert(codes, lib.code :: VM.Value)
		table.insert(libraries, cellValue(bytesValue(imp.name), lib.parsed :: VM.Cell))
	end

	local laid: VM.Value = bytesValue(file.program)

	if laysOut then
		const tagLaid, laidValue, statusLaid = runStage("layout", bytesValue(file.program), 1e10)

		if tagLaid ~= 0 then
			return refused(
				out,
				"layout",
				if laidValue == nil then
					statusLaid
				else
					textOf(laidValue :: VM.Value)
			)
		end

		laid = laidValue :: VM.Value
	end

	const tagTokens, tokens, statusTokens = runStage("lex", laid, 1e10)

	if tagTokens ~= 0 then
		return refused(
			out,
			"lex",
			if tokens == nil then
				statusTokens
			else
				textOf(tokens :: VM.Value)
		)
	end

	const tagParsed, parsed, statusParsed = runStage("parse", tokens :: VM.Value, 5e10)

	if tagParsed ~= 0 then
		return refused(
			out,
			"parse",
			if parsed == nil then
				statusParsed
			else
				textOf(parsed :: VM.Value)
		)
	end

	const parsedCell = parsed :: VM.Cell
	const checked = Lifecycle.run(stage "types".expr, conValue(5, cellValue(listValue(libraries), parsedCell)), 1e11)

	if checked.status ~= "value" then
		return refused(out, "check", checked.status)
	end

	const result = checked.value :: VM.Cell
	const errors = itemsOf((result.tail :: VM.Cell).head)

	if #errors > 0 then
		return refused(out, "check", textOf(errors[1]))
	end

	const checksAndInput = (result.tail :: VM.Cell).tail :: VM.Cell
	local nameValues: { VM.Value } = {}

	for _, n in names do
		table.insert(nameValues, bytesValue(n))
	end

	const tagCode, code, statusCode = runStage("desugar", desugarInput(listValue(nameValues), parsedCell, checksAndInput.head, listValue(codes), checksAndInput.tail), 1e11)

	if tagCode ~= 0 then
		return refused(
			out,
			"desugar",
			if code == nil then
				statusCode
			else
				textOf(code :: VM.Value)
		)
	end

	out.ok = true
	out.parsed = parsedCell
	out.code = code
	out.expr = codeToExpr(code :: VM.Value)

	return out
end
M.compileText = function(text: string, name: string, loadImport: (string) -> string?): Compiled
	return compileTextInner(
		text,
		name,
		function(file: string): string
			const loaded = loadImport(file)

			if loaded == nil then
				error(`the import {file} is not found`, 0)
			end

			return loaded :: string
		end
	)
end
-- A test's expression, read by the tokenizer, the parser and the desugarer with the file's declarations and imports in scope, and run on the VM: its value, or nil.
M.evalExpr = function(c: Compiled, text: string, fuel: number): VM.Value?
	const tagTokens, tokens = runStage("lex", bytesValue(text), 1e10)

	if tagTokens ~= 0 then
		return nil
	end

	const tagParsed, parsed = runStage("parse", tokens :: VM.Value, 5e10)

	if tagParsed ~= 0 then
		return nil
	end

	const parsedCell = parsed :: VM.Cell
	local nameValues: { VM.Value } = {}

	for _, n in c.names do
		table.insert(nameValues, bytesValue(n))
	end

	const fileParsed = c.parsed :: VM.Cell
	const testParsed = cellValue(fileParsed.head, parsedCell.tail)
	const tagCode, code = runStage("desugar", desugarInput(listValue(nameValues), testParsed, VM.NIL, listValue(c.importCodes), conValue(0, VM.NIL)), 1e11)

	if tagCode ~= 0 then
		return nil
	end

	const ran = VM.run(codeToExpr(code :: VM.Value), fuel)

	if ran.status ~= "value" then
		return nil
	end

	return ran.value
end
-- A compiled file run on an input value, as the machine runs a program: the result of the lifecycle.
M.runMachine = function(c: any, input: VM.Value, fuel: number): Lifecycle.Result
	return Lifecycle.run(c.expr, input, fuel)
end
-- The text of a program file in the programs folder, with its path (without .l2), for loadImport.
M.loadFile = function(file: string): string
	return readFile(M.PROGRAMS .. file)
end

return M
