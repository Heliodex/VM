--!strict
-- GENERATES THE LOWERING FIXTURE OF THE CONVERTER (Prototype 8, step 1)
--
-- For each file of the 2,500-line corpus's program files, the program law the bootstrapped compiler gives: the expression that boot_pipeline.luau's compile gives (the desugarer's output read as an expression, with the checker's input check), lowered by reference/lower.luau and applied to the input. The Go converter (fast/convert.go) takes the same desugarer output and must give these bytes exactly.
--
-- The output is testdata/convert.txt: for each file, law <file> <hex of the program law>, and code <file> <hex of the desugarer's output (the Code value), which the converter's input is.
--
-- Run from Prototypes/7/measure:
--   cd Prototypes/7/measure && lute run ../fast/gen/convert.luau > ../fast/testdata/convert.txt

const Pipeline = require "../../measure/boot_pipeline"
const Format = require "../../reference/format"
const Lower = require "../../reference/lower"
const Types = require "../../reference/types"
const fs = require "@lute/fs"

type Form = Types.Form
const BOOT6 = "../../6/L2/programs/boot/"

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

-- The program law of an expression: the expression lowered, applied to the input (argument 1), as corpus2500.luau's program does.
const function programLaw(e: any): string
	const body: Form = {
		op = "call",
		f = Lower.expr(e, nil),
		args = { { op = "arg", index = 1 } },
	}

	return Format.encodeProgram { kind = "law", arity = 1, body = body } :: string
end

-- The files of the 2,500-line corpus: the four boot files, then 13 of the standard library (corpus2500.luau).
const BOOT_FILES = { "lex.l2", "parse.l2", "layout.l2", "types.l2" }
const LIB_FILES = { "abs", "append", "contains", "filter", "fold", "gcd", "insert", "length", "map", "nth", "reverse", "sum", "take" }

for _, file in BOOT_FILES do
	const c = Pipeline.compileText(readFile(BOOT6 .. file), "boot/" .. file, Pipeline.loadFile)

	if not c.ok then
		error(`{file}: the bootstrapped compiler refuses it at {c.stage}: {c.message}`, 0)
	end

	print(`law {file} {hex(programLaw(c.expr))}`)
	print(`code {file} {hex(Format.encodeValue(c.code :: any) :: string)}`)
end

for _, name in LIB_FILES do
	const file = "lib/" .. name .. ".l2"
	const c = Pipeline.compileText(readFile("../../6/L2/programs/" .. file), file, Pipeline.loadFile)

	if not c.ok then
		error(`{file}: the bootstrapped compiler refuses it at {c.stage}: {c.message}`, 0)
	end

	print(`law {file} {hex(programLaw(c.expr))}`)
	print(`code {file} {hex(Format.encodeValue(c.code :: any) :: string)}`)
end
