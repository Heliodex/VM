--!strict
-- VALIDATION OF THE TESTS IN cases.luau AND THE NUMERALS
--
-- Runs every case and checks only what it should reduce to, then checks that numerals read back to the number they were built from. No diagrams are drawn, so a run is fast.
-- Prints one line per check and exits with an error if any check fails. main.luau is for looking at reductions; this is for knowing whether they are right.
--
--   luau validate.luau

const B = require "./builder"
const Canon = require "./canon"
const Cases = require "./cases"
const H = require "./harness"
const L = require "./lambda"
const Net = require "./net"
const N = require "./numerals"

local failures = 0
local total = 0

const function report(
	ok: boolean,
	label: string
)
	total += 1

	if not ok then
		failures += 1
	end

	print(
		`{
			if ok then
				"PASS"
			else
				"FAIL"
		}  {label}`
	)
end

for _, test in Cases.tests do
	const limit = test.budget or H.DEFAULT_BUDGET
	const net = Cases.build(test.start)
	const result = H.reduce(net, limit)
	const finished = result.outcome == "reduced"
	const ok =
		if test.expect then
			finished and Net.wellFormed(net) and Canon.isomorphic(net, Cases.build(test.expect))
		else
			not finished and Net.wellFormed(net)
	report(ok, `{test.name}  ({H.describe(result)})`)
end

-- Each numeral reduces to itself and reads back as the number it was built from.
for n = 0, 5 do
	const net = N.numeral(n)
	const result = H.reduce(net, H.DEFAULT_BUDGET)
	report(result.outcome == "reduced" and N.readback(net) == n, `numeral {n} reads back as {n}  ({H.describe(result)})`)
end

-- A value that is not a numeral reads back as nothing.
do
	const b = B.new()
	L.lam(
		b, function(
			x
		)
			return x
		end
	)
	const identity = b:finish()
	report(N.readback(identity) == nil, "the identity does not read back as a numeral")
end

if failures > 0 then
	error(`{failures} of {total} checks failed`)
end

print(`all {total} checks passed`)
