--!strict
-- THE ENVIRONMENT EXPERIMENT
--
-- The self-interpreter keeps its environment as a linked list, and the question is whether a skew binary random-access list does better. Two parts:
--
--   1. Both representations must agree with the direct machine on every program. The skew list has to be right before its costs mean anything.
--   2. A program nested to depth d, which sums its d bindings. Every binding is read once, so the cost of a read is what grows. Each depth is run with both representations.
--
-- The reference machine keeps its linked list. This only changes the self-interpreter's environment, which is an implementation choice.
--
--   luau env_run.luau      (from Prototypes/5)

const Text = require "./L1/examples/text"
const Reader = require "./L1/reader"
const Self = require "./L1/self/self"
const Examples = require "./examples/examples"
const VM = require "./interpreter/vm"

const FUEL_FACTOR = 50
const SKEW = Self.build(Self.LOOKUP_SKEW, Self.EXTEND_SKEW)
const LIST = Self.EVAL
local failures = 0
local total = 0

const function agrees(
	ex: {
		name: string,
		program: VM.Expr,
		fuel: number,
		outcome: string,
		expect: string?,
	}
): boolean
	const interpreted = VM.run(Self.interpretWith(SKEW, ex.program), ex.fuel * FUEL_FACTOR)

	if interpreted.status == "value" then
		return ex.outcome == "value" and VM.show(interpreted.value) == ex.expect
	elseif interpreted.status == "error" then
		return ex.outcome == "error"
	end

	return ex.outcome == "out_of_fuel"
end

print "Part 1: the skew list agrees with the direct machine"

for _, ex in Examples do
	total += 1

	if not agrees(ex) then
		failures += 1
		print(`FAIL  {ex.name}`)
	end
end

for _, ex in Text.examples do
	total += 1

	if not agrees(ex) then
		failures += 1
		print(`FAIL  {ex.name}`)
	end
end

print(`{total - failures} of {total} programs agree with the direct machine using the skew list`)

-- A program nested to depth d, which sums its d bindings. The body reads binding k once, and the result is d(d+1)/2.
const function nested(d: number): string
	local body = "x0"

	for k = 1, d - 1 do
		body = `(+ {body} x{k})`
	end

	for k = d - 1, 0, -1 do
		body = `(fn x{k} {body})`
	end

	local args = {}

	for k = 1, d do
		table.insert(args, tostring(k))
	end

	return `({body} {table.concat(args, " ")})`
end

print ""
print "Part 2: reading every binding of a nested program"
print "depth  list steps  skew steps  skew/list  result"

for _, d in { 4; 8; 16; 32; 64 } do
	const program = Reader.parse(nested(d))
	const expected = d * (d + 1) // 2
	const listRun = VM.run(Self.interpretWith(LIST, program), 1e9)
	const skewRun = VM.run(Self.interpretWith(SKEW, program), 1e9)
	const listOk = listRun.status == "value" and VM.show(listRun.value) == tostring(expected)
	const skewOk = skewRun.status == "value" and VM.show(skewRun.value) == tostring(expected)

	if not (listOk and skewOk) then
		failures += 1
	end

	print(
		string.format(
			"%5d  %10d  %10d  %9.2f  %s",
			d,
			listRun.steps,
			skewRun.steps,
			skewRun.steps / listRun.steps,
			if listOk and skewOk then
				tostring(expected)
			else
				"WRONG"
		)
	)
end

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
