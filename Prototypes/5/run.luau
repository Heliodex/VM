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

print(string.format("%d of %d checks passed", total - failures, total))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
