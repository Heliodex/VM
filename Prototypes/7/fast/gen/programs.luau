--!strict
-- GENERATES THE PROGRAM FIXTURE OF THE GO PIPELINE (Prototype 8, step 2)
--
-- For each L2 program file (the 45 files that boot_pipeline_run.luau runs), each test: its input and its expected output, as the bootstrapped compile gives them (boot_pipeline.luau's evalExpr, on the Prototype 6 machine), in the core's binary encoding (reference/format.luau). A value that holds a function is written as "-": only data is compared.
--
-- The Go tests (fast/programs_test.go) evaluate the same test expressions through the Go pipeline and run the program on the Go machine; the two must give the same encodings.
--
-- Run from Prototypes/7/measure:
--   cd Prototypes/7/measure && lute run ../fast/gen/programs.luau > ../fast/testdata/programs.txt

const ProgramFile = require "../../../6/L2/programfile"
const Format = require "../../reference/format"
const Pipeline = require "../../measure/boot_pipeline"
const Types = require "../../reference/types"
const fs = require "@lute/fs"

const PROGRAMS = "../../6/L2/programs/"

const NAMES = {
	"add_one",
	"block_let",
	"boot/desugar",
	"boot/layout",
	"boot/lex",
	"boot/parse",
	"boot/types",
	"cons",
	"division",
	"double",
	"fact",
	"forms",
	"head",
	"imports",
	"let_block",
	"letrec_block",
	"lib/abs",
	"lib/append",
	"lib/contains",
	"lib/filter",
	"lib/fold",
	"lib/gcd",
	"lib/insert",
	"lib/length",
	"lib/map",
	"lib/max",
	"lib/min",
	"lib/ninefold",
	"lib/nth",
	"lib/range",
	"lib/reverse",
	"lib/sort",
	"lib/sum",
	"lib/take",
	"lib/triple",
	"lib/unwrap_or",
	"mutual",
	"option",
	"pairs",
	"record_middle",
	"records",
	"remainder",
	"result",
	"sum_list",
	"tree",
}

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

-- A machine value as a core value (reference/types), or nil when it holds a function or a pin, which the comparison does not cover.
local function core(v: any): Types.Value?
	if type(v) == "number" then
		return v
	end

	if type(v) ~= "table" then
		return nil
	end

	if v.kind == "nil" then
		return Format.NIL
	elseif v.kind == "cell" then
		const h = core(v.head)
		const t = core(v.tail)

		if h == nil or t == nil then
			return nil
		end

		return { kind = "cell"; head = h; tail = t }
	elseif v.kind == "con" then
		const p = core(v.payload)

		if p == nil then
			return nil
		end

		return { kind = "con"; tag = v.tag; payload = p }
	end

	return nil
end

-- The encoding of a value, or "-" when it holds a function.
local function encoded(v: any): string
	const c = core(v)

	if c == nil then
		return "-"
	end

	return hex(Format.encodeValue(c) :: string)
end

for _, path in NAMES do
	const text = readFile(PROGRAMS .. path .. ".l2")
	const c = Pipeline.compileText(text, path .. ".l2", Pipeline.loadFile)

	if not c.ok then
		error(`{path}: the bootstrapped compiler refuses it at {c.stage}: {c.message}`, 0)
	end

	const file = ProgramFile.parse(text, nil)

	for _, test in file.tests do
		const input = Pipeline.evalExpr(c, test.input, 1e10)

		if input == nil then
			error(`{path}:{test.line}: the input {test.input} does not evaluate`, 0)
		end

		const output = Pipeline.evalExpr(c, test.output :: string, 1e10)

		if output == nil then
			error(`{path}:{test.line}: the output {test.output :: string} does not evaluate`, 0)
		end

		print(`test {path} {test.line} {encoded(input)} {encoded(output)}`)
	end
end
