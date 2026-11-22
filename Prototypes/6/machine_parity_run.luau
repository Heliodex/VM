--!strict
-- MACHINE PARITY
--
-- The fast machine (VM.run) and the reference machine (VM.runReference) give the same status, the same steps, and the same value or message on every example and constructor example.
--
--   lute run machine_parity_run.luau      (from Prototypes/6)

const VM = require "./interpreter/vm"
const Examples = require "./examples/examples"
const Constructors = require "./examples/constructors"

local total = 0
local failures = 0

local function compare(name: string, program: any, fuel: number)
	total += 1
	const ref = VM.runReference(program, fuel)
	const fast = VM.run(program, fuel)
	local same = ref.status == fast.status and ref.steps == fast.steps

	if same and ref.status == "value" and fast.status == "value" then
		same = VM.show(ref.value) == VM.show(fast.value)
	elseif same and ref.status == "error" and fast.status == "error" then
		same = ref.message == fast.message
	end

	if not same then
		failures += 1
		print(`DIFF {name}: reference {ref.status} {ref.steps} steps, fast {fast.status} {fast.steps} steps`)
	end
end

for _, ex in Examples do
	compare(ex.name, ex.program, ex.fuel)
end

for _, ex in Constructors do
	compare(ex.name, ex.program, ex.fuel)
end

print(string.format("%d of %d examples give the same status, steps and value or message in both machines", total - failures, total))
