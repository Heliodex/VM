--!strict
-- RUNS THE CASES OF measure/cases THROUGH THE HOST AND THE BOOTSTRAPPED COMPILER, AND CHECKS EACH TEST AGAINST ITS EXPECTED OUTCOME
--
-- These are programs the program files of Prototype 6 do not cover: a checker failure at the input boundary, with its message; records with a with and a match; a mutual group; an early return; a user sum matched; an import. Each test of each case is run by the host compiler (Prototype 6's L2.compile) and by the bootstrapped compiler (boot_pipeline), and both must give the outcome the test expects. The expected outcomes are written in the test lines, as the program files write them.
--
--   lute run cases_run.luau      (from Prototypes/7/measure)
--
-- The cases are braced programs (named .case, so the layout is not applied to them, as the malformed programs are not): an import is a library file, which the layout does apply to.

const L2 = require "../../6/L2/l2"
const ProgramFile = require "../../6/L2/programfile"
const Data = require "../../6/interpreter/data"
const pipeline = require "./boot_pipeline"
const fs = require "@lute/fs"

local failures = 0
local passes = 0

local function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

-- Imports come from the programs folder of Prototype 6, as the program files' do.
local function resolveHost(name: string): string?
	local ok, text = pcall(readFile, `../../6/L2/programs/{name}`)

	if ok then
		return text :: string
	end

	return nil
end

local function check(label: string, pass: boolean, detail: string)
	if pass then
		passes += 1
	else
		failures += 1
		print(`FAIL  {label}  -> {detail}`)
	end
end

-- The outcome of a test on the host: its value's data text, or its status; the same rule as l2_run.luau.
local function hostOutcome(compiled: any, input: string, fuel: number): (string, number)
	const ran, value = pcall(L2.evalText, compiled, input, L2.VALUE_FUEL)

	if not ran then
		return `input raises {tostring(value)}`, 0
	end

	const result = L2.run(compiled, value, fuel)

	if result.status == "value" then
		return Data.write(result.value), result.steps
	end

	return result.status, result.steps
end

-- The outcome of a test on the bootstrapped compiler, by the same rule.
local function bootOutcome(compiled: any, input: string, fuel: number): (string, number)
	const inputValue = pipeline.evalExpr(compiled, input, 1e10)

	if inputValue == nil then
		return "the input does not evaluate", 0
	end

	const ran = pipeline.runMachine(compiled, inputValue, fuel)

	if ran.status == "value" then
		return Data.write(ran.value), ran.steps
	end

	return ran.status, ran.steps
end

-- The expected outcome of a test, on each compiler: its output's data text when it is a value, or the outcome named.
local function expectedOutcome(compiledHost: any, compiledBoot: any, test: any): (string, string)
	if test.outcome == "value" then
		const expectedHost = L2.evalText(compiledHost, test.output :: string, L2.VALUE_FUEL)
		const expectedBoot = pipeline.evalExpr(compiledBoot, test.output :: string, 1e10)

		if expectedBoot == nil then
			return Data.write(expectedHost), "the expected output does not evaluate on the bootstrapped compiler"
		end

		return Data.write(expectedHost), Data.write(expectedBoot)
	end

	return test.outcome, test.outcome
end

local CASES = { "input_pair", "records_with", "mutual_group", "early_return", "sums_match", "import_append" }
print "cases_run: the cases of measure/cases, on the host compiler and the bootstrapped compiler"

for _, name in CASES do
	const text = readFile(`cases/{name}.case`)
	const file = ProgramFile.parse(text, `{name}.case`)
	const hostCompiled = L2.compile(text, resolveHost, `{name}.case`)
	const bootCompiled = pipeline.compileText(
		text,
		`{name}.case`,
		function(path: string): string?
			const ok, loaded = pcall(function(): string
				return readFile(`cases/{path}`)
			end)

			if ok then
				return loaded
			end

			return resolveHost(path)
		end
	)

	if not bootCompiled.ok then
		check(name, false, `the bootstrapped compiler refuses it at {bootCompiled.stage}: {bootCompiled.message}`)
	else
		for _, test in file.tests do
			const label = `{name}:{test.line}`
			const hostGot, hostSteps = hostOutcome(hostCompiled, test.input, test.fuel)
			const bootGot, bootSteps = bootOutcome(bootCompiled, test.input, test.fuel)
			const wantHost, wantBoot = expectedOutcome(hostCompiled, bootCompiled, test)
			check(label, hostGot == wantHost and bootGot == wantBoot, `host {hostGot} (expected {wantHost}), boot {bootGot} (expected {wantBoot})`)
		end
	end
end

print(`{passes} of {passes + failures} checks pass`)

if failures > 0 then
	error(`{failures} checks fail`, 0)
end
