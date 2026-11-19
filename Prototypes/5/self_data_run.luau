--!strict
-- RUNS THE EXAMPLES THROUGH THE CLOSURE-FREE SELF-INTERPRETER
--
-- Checks the closure-free interpreter in self/self_data.luau against the examples, which should all agree. Then runs two probes that the data form cannot get right, and prints what each one gives in the reference machine and in the closure-free interpreter.
--
-- The probes are not failures. They are the cost of representing functions as ordinary cells: the machine can then not tell a function from a pair.
--
--   luau self_data_run.luau      (from Prototypes/5)

const Examples = require "./examples/examples"
const Reader = require "./L1/reader"
const SelfData = require "./L1/self/self_data"
const Self = require "./L1/self/self"
const Text = require "./L1/examples/text"
const VM = require "./interpreter/vm"

const FUEL_FACTOR = 50

local failures = 0
local total = 0

-- Programs whose result depends on whether a function is a native closure. The closure-free interpreter is expected to differ on these, and they are reported rather than failed.
const KNOWN_DIFFERENCES = { "kind of a function" }

local known = 0

const function check(
	ex: {
		name: string,
		program: VM.Expr,
		fuel: number,
		outcome: string,
		expect: string?,
	}
)
	const interpreted = VM.run(SelfData.interpret(ex.program), ex.fuel * FUEL_FACTOR)

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

	if table.find(KNOWN_DIFFERENCES, ex.name) ~= nil then
		known += 1
		print(string.format("KNOWN %s  -> %s  (interpreted %d steps), differs from the direct machine as expected", ex.name, got, interpreted.steps))
	elseif pass then
		print(string.format("PASS  %s  -> %s  (interpreted %d steps)", ex.name, got, interpreted.steps))
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

print(string.format("%d of %d programs agree with the direct machine, and %d known differences", total - failures - known, total, known))

-- A forged function: the cell [1 [[0 [7 ~]] ~]] is a function whose body is the quoted constant 7. The reference machine has no such function, so applying it is an error.
const FORGED_APPLY = "([1 [[0 [7 ~]] ~]] 5)"
-- Taking the head of a function: the reference machine rejects it, the closure-free one reads the tag.
const FUNCTION_HEAD = "(head (fn x x))"

const probes = {
	{ name = "applying a forged function", source = FORGED_APPLY },
	{ name = "head of a function", source = FUNCTION_HEAD },
	{ name = "kind of a function", source = "(kind (fn x x))" },
}

print("")
print("Probes, where the two are expected to differ:")
for _, probe in probes do
	const program = Reader.parse(probe.source)
	const direct = VM.run(program, 100000)
	const data = VM.run(SelfData.interpret(program), 5000000)
	print(string.format("  %s: %s", probe.name, probe.source))
	print(string.format("    direct machine:   %s", if direct.status == "value" then VM.show(direct.value) elseif direct.status == "error" then `error: {tostring(direct.message)}` else "out of fuel"))
	print(string.format("    closure-free:     %s", if data.status == "value" then VM.show(data.value) elseif data.status == "error" then `error: {tostring(data.message)}` else "out of fuel"))
end

print("")
print(string.format("Size of the interpreter's EVAL: %d characters with host closures, %d closure-free", #Self.EVAL, #SelfData.EVAL_DATA))

if failures > 0 then
	error(string.format("%d program(s) disagree", failures))
end
