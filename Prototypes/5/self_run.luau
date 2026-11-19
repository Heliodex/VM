--!strict
-- RUNS THE EXAMPLES THROUGH THE SELF-INTERPRETER
--
-- Quotes every example, runs it through self.luau, and checks that the interpreted run has the same outcome as the direct run: the same status, and for a value the same printed value. Errors are compared by status only, since the interpreter raises its own messages. The direct run must also match what the example expects. Prints the steps each run takes, so the cost of interpreting can be read off.
--
-- The interpreted run gets 50 times the fuel, since every step of the program costs several steps of the interpreter.
--
--   luau self_run.luau      (from Prototypes/5)

const Examples = require "./examples/examples"
const Self = require "./self/self"
const Text = require "./examples/text"
const Programs = require "./examples/programs"
const VM = require "./interpreter/vm"

const FUEL_FACTOR = 50

local failures = 0
local total = 0

-- The outcome of a run as one string, so two runs can be compared. Errors are reduced to "error", since the messages come from different machines.
const function describe(
	r: VM.Outcome
): string
	if r.status == "value" then
		return "value " .. VM.show(r.value)
	elseif r.status == "error" then
		return "error"
	end

	return "out of fuel"
end

const function check(
	ex: {
		name: string,
		program: VM.Expr,
		fuel: number,
		outcome: string,
		expect: string?,
	}
)
	const direct = VM.run(ex.program, ex.fuel)
	const interpreted = VM.run(Self.interpret(ex.program), ex.fuel * FUEL_FACTOR)

	-- The direct run is the reference: it must match the example, and the interpreted run must match it.
	local expected = if ex.outcome == "value" then "value " .. tostring(ex.expect) elseif ex.outcome == "error" then "error" else "out of fuel"
	local pass = describe(direct) == expected and describe(interpreted) == describe(direct)

	total += 1

	if pass then
		print(string.format("PASS  %s  -> %s  (direct %d steps, interpreted %d)", ex.name, describe(direct), direct.steps, interpreted.steps))
	else
		failures += 1
		print(string.format("FAIL  %s  -> direct %s, interpreted %s (interpreted %d steps), expected %s", ex.name, describe(direct), describe(interpreted), interpreted.steps, expected))
	end
end

for _, ex in Examples do
	check(ex)
end

for _, ex in Text.examples do
	check(ex)
end

for _, ex in Programs.examples do
	check(ex)
end

print(string.format("%d of %d programs agree with the direct machine", total - failures, total))

if failures > 0 then
	error(string.format("%d program(s) disagree", failures))
end
