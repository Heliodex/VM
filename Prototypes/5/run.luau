--!strict
-- RUNS THE EXAMPLES
--
-- Runs every example in examples.luau and text.luau, and checks that the rejects in text.luau do not read. Prints one line for each, with the number of steps it took. Ends with an error if any of them does not behave as written.
--
--   luau run.luau      (from Prototypes/5)

const Examples = require "./examples/examples"
const Programs = require "./examples/programs"
const Reader = require "./interpreter/reader"
const Text = require "./examples/text"
const VM = require "./interpreter/vm"

local failures = 0
local total = 0

const function report(
	ex: {
		name: string,
		program: VM.Expr,
		fuel: number,
		outcome: string,
		expect: string?,
	}
)
	const result = VM.run(ex.program, ex.fuel)
	local got: string
	local pass: boolean

	total += 1

	if result.status == "value" then
		got = VM.show(result.value)
		pass = ex.outcome == "value" and got == ex.expect
	elseif result.status == "error" then
		got = `error: {tostring(result.message)}`
		pass = ex.outcome == "error"
	else
		got = "out of fuel"
		pass = ex.outcome == "out_of_fuel"
	end

	if pass then
		print(string.format("PASS  %s  -> %s  (%d steps)", ex.name, got, result.steps))
	else
		failures += 1
		print(
			string.format(
				"FAIL  %s  -> %s  (%d steps), expected %s", ex.name, got, result.steps, if ex.outcome == "value" then
					tostring(ex.expect)
				else
					ex.outcome
			)
		)
	end
end

for _, ex in Examples do
	report(ex)
end

for _, ex in Text.examples do
	report(ex)
end

for _, ex in Programs.examples do
	report(ex)
end

for _, source in Text.rejects do
	total += 1

	const ok, err = pcall(Reader.parse, source)

	if ok then
		failures += 1
		print(string.format("FAIL  reject %q  -> it read, but it should not", source))
	else
		print(string.format("PASS  reject %q  -> %s", source, tostring(err)))
	end
end

-- Builders reject a bad primitive or an out-of-range integer as soon as they are called.
const builderRejects: { [string]: () -> VM.Expr } = {
	["a primitive that is not known"] = function()
		return VM.prim("nope", VM.int(1), VM.int(2))
	end,
	["a binary primitive with one argument"] = function()
		return VM.prim("add", VM.int(1))
	end,
	["kind with two arguments"] = function()
		return VM.prim("kind", VM.int(1), VM.int(2))
	end,
	["an integer past the range"] = function()
		return VM.int(9007199254740992)
	end,
}

for name, build in builderRejects do
	total += 1

	const ok, err = pcall(build)

	if ok then
		failures += 1
		print(string.format("FAIL  builder %s  -> it built, but it should not", name))
	else
		print(string.format("PASS  builder %s  -> %s", name, tostring(err)))
	end
end

-- A raise ends the run with its value as the message: the bytes if it is a list of bytes, otherwise the printed value.
const raised: { { source: string, message: string } } = {
	{ source = "(raise [104 [105 ~]])", message = "hi" },
	{ source = "(raise ~)", message = "" },
	{ source = "(raise [300 ~])", message = "(300)" },
	{ source = "(raise (+ 1 2))", message = "3" },
}

for _, case in raised do
	total += 1

	const result = VM.run(Reader.parse(case.source), 1000)

	if result.status == "error" and result.message == case.message then
		print(string.format("PASS  raise %s  -> %q", case.source, case.message))
	else
		failures += 1
		print(string.format("FAIL  raise %s  -> %s, expected %q", case.source, result.status, case.message))
	end
end

-- The shorthand is the nested form: a bracket of three or more reads to the same expression as its right-nested pairs.
const shorthand: { { short: string, nested: string } } = {
	{ short = "[1 2 3]", nested = "[1 [2 3]]" },
	{ short = "[1 2 3 ~]", nested = "[1 [2 [3 ~]]]" },
	{ short = "[[1 2] 3 4]", nested = "[[1 2] [3 4]]" },
}

for _, case in shorthand do
	total += 1

	const a = VM.run(Reader.parse(case.short), 1000)
	const b = VM.run(Reader.parse(case.nested), 1000)

	if a.status == "value" and b.status == "value" and VM.show(a.value) == VM.show(b.value) then
		print(string.format("PASS  %s is %s  -> %s", case.short, case.nested, VM.show(a.value)))
	else
		failures += 1
		print(string.format("FAIL  %s is %s", case.short, case.nested))
	end
end

print(string.format("%d of %d checks passed", total - failures, total))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
