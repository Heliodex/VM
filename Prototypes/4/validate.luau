--!strict
-- VALIDATION OF THE TESTS IN cases.luau
--
-- Runs every case and checks only what it should reduce to: no diagrams are drawn, so a run is fast.
-- Prints one line per case and exits with an error if any case fails. main.luau is for looking at reductions; this is for knowing whether they are right.
--
--   luau validate.luau

const Canon = require "./canon"
const Cases = require "./cases"
const H = require "./harness"
const Net = require "./net"

local failures = 0

for _, test in Cases.tests do
	const limit = test.budget or H.DEFAULT_BUDGET
	const net = Cases.build(test.start)
	const report = H.reduce(net, limit)
	const finished = report.outcome == "reduced"

	const ok =
		if test.expect then
			finished and Net.wellFormed(net) and Canon.isomorphic(net, Cases.build(test.expect))
		else
			not finished and Net.wellFormed(net)

	if not ok then
		failures += 1
	end

	print(`{if ok then "PASS" else "FAIL"}  {test.name}  ({H.describe(report)})`)
end

if failures > 0 then
	error(`{failures} of {#Cases.tests} cases failed`)
end

print(`all {#Cases.tests} cases passed`)
