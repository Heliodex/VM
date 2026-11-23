--!strict
-- MACHINE PARITY
--
-- The fast machine (VM.run) and the reference machine (VM.runReference) give the same status, the same steps, and the same value or message on every example and constructor example.
--
--   lute run machine_parity_run.luau      (from Prototypes/6)

const Constructors = require "./examples/constructors"
const Examples = require "./examples/examples"
const VM = require "./interpreter/vm"

local total = 0
local failures = 0

local function compare(name: string, program: any, fuel: number)
	total += 1
	const ref = VM.runReference(program, fuel)
	const fast = VM.run(program, fuel)
	const directOk, direct = pcall(VM.runDirect, program, fuel)

	if not directOk then
		failures += 1
		print(`DIRECT FAILED {name}: {tostring(direct)}`)

		return
	end

	const directResult: any = direct
	const hybrid = VM.runHybrid(program, fuel)
	local sameHybrid = ref.status == hybrid.status and ref.steps == hybrid.steps

	if sameHybrid and ref.status == "value" and hybrid.status == "value" then
		sameHybrid = VM.show(ref.value) == VM.show(hybrid.value)
	elseif sameHybrid and ref.status == "error" and hybrid.status == "error" then
		sameHybrid = ref.message == hybrid.message
	end

	if not sameHybrid then
		failures += 1
		print(`HYBRID DIFF {name}`)
	end

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

	local sameDirect = ref.status == directResult.status and ref.steps == directResult.steps

	if sameDirect and ref.status == "value" and directResult.status == "value" then
		sameDirect = VM.show(ref.value) == VM.show(directResult.value)
	elseif sameDirect and ref.status == "error" and directResult.status == "error" then
		sameDirect = ref.message == directResult.message
	end

	if not sameDirect then
		failures += 1
		print(`DIRECT DIFF {name}: reference {ref.status} {ref.steps} steps, direct {directResult.status} {directResult.steps} steps`)
	end
end

for _, ex in Examples do
	compare(ex.name, ex.program, ex.fuel)
end

for _, ex in Constructors do
	compare(ex.name, ex.program, ex.fuel)
end

print(string.format("%d of %d checks give the same status, steps and value or message as the reference (fast, direct and hybrid machines)", 3 * total - failures, 3 * total))
