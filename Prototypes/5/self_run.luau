--!strict
-- RUNS THE EXAMPLES THROUGH THE SELF-INTERPRETER
--
-- Quotes every example, runs it through self.luau, and checks that the result is the one the example expects. Prints the steps the direct run and the interpreted run each take, so the cost of interpreting can be read off.
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

	local got: string
	local pass: boolean

	total += 1

	if interpreted.status == "value" then
		got = VM.show(interpreted.value)
		pass = ex.outcome == "value" and got == ex.expect
	elseif interpreted.status == "error" then
		got = `error: {tostring(interpreted.message)}`
		pass = ex.outcome == "error"
	else
		got = "out of fuel"
		pass = ex.outcome == "out_of_fuel"
	end

	if pass then
		print(string.format("PASS  %s  -> %s  (direct %d steps, interpreted %d)", ex.name, got, direct.steps, interpreted.steps))
	else
		failures += 1
		print(string.format("FAIL  %s  -> %s  (interpreted %d steps), expected %s", ex.name, got, interpreted.steps, ex.outcome))
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
