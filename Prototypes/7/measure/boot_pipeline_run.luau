--!strict
-- RUNS THE L2 PROGRAM FILES THROUGH THE BOOTSTRAPPED COMPILER (boot_pipeline.luau): every stage is an L2 program run on the VM
--
-- A program file is compiled by boot_pipeline.luau: the layout, the tokenizer, the parser, the checker (request InferT, which gives the tests of the checks and of the input) and the desugarer, all L2 programs in Prototypes/6/L2/programs/boot and their imports. The machine expression that the desugarer gives is run on the VM. Each test's input and output are read by the same stages, with the file's declarations in scope. The host reads the file format and checks each test as l2_run.luau does: the value's data text, or the outcome.
--
--   lute run boot_pipeline_run.luau      (from Prototypes/7/measure)

const ProgramFile = require "../../6/L2/programfile"
const Data = require "../../6/interpreter/data"
const Lifecycle = require "../../6/interpreter/lifecycle"
const pipeline = require "./boot_pipeline"
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

-- The program files, as l2_run.luau lists them: the ones in the programs folder and its subfolders.
local CORPUS = { "add_one", "block_let", "boot/desugar", "boot/layout", "boot/lex", "boot/parse", "boot/types", "cons", "division", "double", "fact", "forms", "head", "imports", "let_block", "letrec_block", "lib/abs", "lib/append", "lib/contains", "lib/filter", "lib/fold", "lib/gcd", "lib/insert", "lib/length", "lib/map", "lib/max", "lib/min", "lib/ninefold", "lib/nth", "lib/range", "lib/reverse", "lib/sort", "lib/sum", "lib/take", "lib/triple", "lib/unwrap_or", "mutual", "option", "pairs", "record_middle", "records", "remainder", "result", "sum_list", "tree" }

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
print "boot_pipeline_run: the L2 program files, compiled by the bootstrapped compiler"

for _, path in CORPUS do
	const text = readFile(`../../6/L2/programs/{path}.l2`)
	const c = pipeline.compileText(text, `{path}.l2`, pipeline.loadFile)

	if not c.ok then
		report(path, false, `not compiled: {c.stage}: {c.message}`)
	else
		const file = ProgramFile.parse(text, nil)

		for _, test in file.tests do
			const label = `{path}:{test.line}`
			const input = pipeline.evalExpr(c, test.input, 1e10)

			if input == nil then
				report(label, false, `the input {test.input} does not evaluate`)
			else
				const result = pipeline.runMachine(c, input, test.fuel)

				if result.status == "value" then
					const got = Data.write(result.value)

					if test.outcome == "value" then
						const expected = pipeline.evalExpr(c, test.output :: string, 1e10)

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
