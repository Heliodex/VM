--!strict
-- RUNS THE EXAMPLES
--
-- Runs every example in examples.luau and prints one line for each, with the number of steps it took. Ends with an error if any example does not behave as written.
--
--   luau run.luau      (from Prototypes/5)

const Examples = require "./examples"
const VM = require "./vm"

local failures = 0

for _, ex in ipairs(Examples) do
	const result = VM.run(ex.program, ex.fuel)
	local got: string
	local pass: boolean

	if result.status == "value" then
		got = VM.show(result.value)
		pass = ex.outcome == "value" and got == ex.expect
	elseif result.status == "error" then
		got = "error: " .. tostring(result.message)
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
end end

print(string.format("%d of %d examples passed", #Examples - failures, #Examples))

if failures > 0 then
	error(string.format("%d example(s) failed", failures))
end
