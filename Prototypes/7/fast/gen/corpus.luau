--!strict
-- GENERATES THE CORPUS BUILD FOR THE FAST MACHINE (Phase 8)
--
-- The build of each file in the corpus is the bootstrapped front end, as the Phase 0 harness runs it: its imports (each library through layout, lex and parse, and the checker gets them as InferI), then the file itself through layout, lex, parse and check. The four stages are core programs (the lowered L2 compilations), and each stage's input is the previous stage's payload.
--
-- The output is testdata/corpus.txt: the four programs, each file's program section and its imports, and the reference's outcome at every stage, so the Go build can be checked stage by stage. The Go build times the same stages.
--
-- Run from Prototypes/7/measure, as gen.luau does:
--   cd Prototypes/7/measure && lute run ../fast/gen/corpus.luau > ../fast/testdata/corpus.txt

const ProgramFile = require "../../../6/L2/programfile"
const Compile = require "../../measure/compile"
const Format = require "../../reference/format"
const Interp = require "../../reference/interp"
const Lower = require "../../reference/lower"
const Types = require "../../reference/types"
const fs = require "@lute/fs"

type Value = Types.Value
type Form = Types.Form
const BOOT6 = "../../6/L2/programs/boot/"
const P6 = "../../6/L2/programs/"
const FUEL_LAYOUT = 1e10
const FUEL_LEX = 1e8
const FUEL_PARSE = 5e8
const FUEL_CHECK = 1e10

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

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

const function bytesValue(s: string): Value
	local v: Value = Format.NIL

	for i = #s, 1, -1 do
		const cell: Types.Cell = { kind = "cell", head = string.byte(s, i) :: number, tail = v }
		v = cell
	end

	return v
end

const function program(c: Compile.Compiled): string
	const body: Form = { op = "call", f = Lower.expr(c.expr, nil), args = { { op = "arg", index = 1 } } }
	const bytes = Format.encodeProgram { kind = "law", arity = 1, body = body }

	return bytes :: string
end

-- The reference's outcome for a stage, with the stage's fuel: the value's payload, when the value is a tagged result of tag 0 (the stage went through), or nil.
local function stage(c: Compile.Compiled, input: Value, fuel: number): Types.Outcome
	const body: Form = { op = "call", f = Lower.expr(c.expr, nil), args = { { op = "arg", index = 1 } } }

	return Interp.runForm(body, input, fuel)
end

const function payloadOf(o: Types.Outcome): Value?
	if o.status ~= "value" then
		return nil
	end

	const v = o.value

	if type(v) == "table" and v.kind == "con" and v.tag == 0 then
		return v.payload
	end

	return nil
end

-- The line of an outcome, as expect lines read it: the status, then the value's bytes or the message.
const function describe(o: Types.Outcome): string
	if o.status == "value" then
		return `value {hex(Format.encodeValue(o.value) :: string)}`
	end

	if o.status == "error" then
		return `error {o.message}`
	end

	return "out_of_fuel"
end

-- The four stage programs, lowered from the compilations the Phase 0 harness uses: layout from measure/boot (the variant), lex and parse from Prototype 6's boot files, and the variant checker.
const layoutC = Compile.compile(readFile "boot/layout.l2", "boot/layout.l2")
const lexC = Compile.compile(readFile(BOOT6 .. "lex.l2"), "lex.l2")
const parseC = Compile.compile(readFile(BOOT6 .. "parse.l2"), "parse.l2")
const checkC = Compile.compile(readFile "boot/types.l2", "boot/types.l2")
print(`# program layout {hex(program(layoutC))}`)
print(`# program lex {hex(program(lexC))}`)
print(`# program parse {hex(program(parseC))}`)
print(`# program check {hex(program(checkC))}`)
-- The corpus: the same four files as the Phase 0 harness.
const corpus = { "lex.l2", "parse.l2", "layout.l2", "types.l2" }
local lines = 0
local bytes = 0

for _, file in corpus do
	const text = readFile(BOOT6 .. file)
	const parsedFile = ProgramFile.parse(text, nil)
	const raw = Compile.compile(text, "boot/" .. file).raw
	bytes += #text

	for _ in string.gmatch(text, "\n") do
		lines += 1
	end

	print(`file {file} {hex(raw)}`)
	-- Imports: each library through the stages, so the checker gets it as a parsed program.
	const imports = parsedFile.imports
	local expects: { string } = {}
	local libraries: { Value } = {}
	local refused: string? = nil

	for _, imp in imports do
		const libRaw = ProgramFile.parse(readFile(P6 .. imp.file), nil).program :: string
		print(`import {file} {imp.name} {imp.file} {hex(libRaw)}`)
		const laid = stage(layoutC, bytesValue(libRaw), FUEL_LAYOUT)
		const laidPayload = payloadOf(laid)

		if laidPayload == nil then
			refused = `{imp.file} layout`
			break
		end

		const lexed = stage(lexC, laidPayload, FUEL_LEX)
		const lexedPayload = payloadOf(lexed)

		if lexedPayload == nil then
			refused = `{imp.file} lex`
			break
		end

		const parsed = stage(parseC, lexedPayload, FUEL_PARSE)
		const parsedPayload = payloadOf(parsed)

		if parsedPayload == nil then
			refused = `{imp.file} parse`
			break
		end

		const library: Types.Cell = { kind = "cell", head = bytesValue(imp.name), tail = parsedPayload }
		table.insert(libraries, library)
	end

	if refused ~= nil then
		print(`# refused {file}: {refused}`)
		continue
	end

	-- The file itself.
	const laid = stage(layoutC, bytesValue(raw), FUEL_LAYOUT)
	print(`expect {file} layout {describe(laid)}`)
	const bracketed = payloadOf(laid)

	if bracketed == nil then
		print(`# refused {file}: layout`)
		continue
	end

	const lexed = stage(lexC, bracketed, FUEL_LEX)
	print(`expect {file} lex {describe(lexed)}`)
	const lexedPayload = payloadOf(lexed)

	if lexedPayload == nil then
		print(`# refused {file}: lex`)
		continue
	end

	const parsed = stage(parseC, lexedPayload, FUEL_PARSE)
	print(`expect {file} parse {describe(parsed)}`)
	const parsedPayload = payloadOf(parsed)

	if parsedPayload == nil then
		print(`# refused {file}: parse`)
		continue
	end

	-- The checker's request: the file's parse, with the libraries if there are any (InferI, tag 4).
	local request: Value = { kind = "con", tag = 3, payload = parsedPayload }

	if #libraries > 0 then
		local cells: Value = Format.NIL

		for i = #libraries, 1, -1 do
			const cell: Types.Cell = { kind = "cell", head = libraries[i], tail = cells }
			cells = cell
		end

		const pair: Types.Cell = { kind = "cell", head = cells, tail = parsedPayload }
		const withLibraries: Types.Con = { kind = "con", tag = 4, payload = pair }
		request = withLibraries
	end

	const checked = stage(checkC, request, FUEL_CHECK)
	print(`expect {file} check {describe(checked)}`)
end

print(`# corpus: {bytes} bytes, {lines} lines`)
