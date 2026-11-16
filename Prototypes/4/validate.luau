--!strict
-- VALIDATION OF THE TESTS IN cases.luau AND THE NUMERALS
--
-- Runs every case and checks only what it should reduce to, then checks that numerals read back to the number they were built from. No diagrams are drawn, so a run is fast.
-- Prints one line per check and exits with an error if any check fails. main.luau is for looking at reductions; this is for knowing whether they are right.
--
--   luau validate.luau

const A = require "./arithmetic"
const Bo = require "./booleans"
const B = require "./builder"
const Canon = require "./canon"
const Cases = require "./cases"
const H = require "./harness"
const L = require "./lambda"
const Net = require "./net"
const N = require "./numerals"
const Types = require "./types"

type Builder = B.Builder
type Port = Types.Port
const ARITH_BUDGET = 20000
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

-- Arithmetic: apply each operator to numerals in one net, reduce it, and read the result back.
-- The operands are built into the same net as the operator, so the reduction does all the work.
local function compute(
	op: (Builder) -> Port,
	operands: { number }
): (H.Report, number?)
	const b = B.new()
	local term = op(b)

	for _, k in operands do
		term = L.app(b, term, N.church(b, k))
	end

	const net = b:finish()
	const result = H.reduce(net, ARITH_BUDGET)

	return result, N.readback(net)
end

for n = 0, 5 do
	const result, got = compute(
		A.successor, {
			n,
		}
	)
	report(result.outcome == "reduced" and got == n + 1, `successor of {n} is {n + 1}  ({H.describe(result)})`)
end

for m = 0, 3 do
	for n = 0, 3 do
		const result, got = compute(
			A.addition, {
				m,
				n,
			}
		)
		report(result.outcome == "reduced" and got == m + n, `{m} + {n} = {m + n}  ({H.describe(result)})`)
end end

for m = 0, 3 do
	for n = 0, 3 do
		const result, got = compute(
			A.product, {
				m,
				n,
			}
		)
		report(result.outcome == "reduced" and got == m * n, `{m} * {n} = {m * n}  ({H.describe(result)})`)
end end

-- Booleans read back as themselves, and nothing else reads back as a boolean.
for _, value in {
	true,
	false,
} do
	const net = Bo.booleanNet(value)
	report(Bo.readback(net) == value, `{value} reads back as {value}`)
end

-- A conditional selects the branch its condition names, whether the branches are numbers or booleans.
for _, c in {
	true,
	false,
} do
	do
		const b = B.new()
		local term = Bo.conditional(b)
		term = L.app(b, term, Bo.boolean(b, c))
		term = L.app(b, term, N.church(b, 2))
		term = L.app(b, term, N.church(b, 5))
		const net = b:finish()
		const result = H.reduce(net, H.DEFAULT_BUDGET)
		const want =
			if c then
				2
			else
				5
		report(result.outcome == "reduced" and N.readback(net) == want, `if {c} then 2 else 5 is {want}  ({H.describe(result)})`)
	end

	do
		const b = B.new()
		local term = Bo.conditional(b)
		term = L.app(b, term, Bo.boolean(b, c))
		term = L.app(b, term, Bo.boolean(b, true))
		term = L.app(b, term, Bo.boolean(b, false))
		const net = b:finish()
		const result = H.reduce(net, H.DEFAULT_BUDGET)
		report(result.outcome == "reduced" and Bo.readback(net) == c, `if {c} then true else false is {c}  ({H.describe(result)})`)
end end

-- Values that are not booleans read back as nothing.
do
	const b = B.new()
	L.lam(
		b, function(
			x: Port
		): Port
			return x
		end
	)
	report(Bo.readback(b:finish()) == nil, "the identity does not read back as a boolean")
end

-- A value that is not a numeral reads back as nothing. λf.λx.λy.x is not one: applied to two values it gives an abstraction, not a chain of applications.
-- (The identity is not a counterexample: λx.x is η-equal to λf.λx.f x, which is numeral 1.)
do
	const b = B.new()
	L.lam(
		b, function(
			_f
		)
			return L.lam(
				b, function(
					x
				)
					return L.lam(
						b, function(
							_y
						)
							return x
						end
					)
				end
			)
		end
	)
	const constant = b:finish()
	report(N.readback(constant) == nil, "λf.λx.λy.x does not read back as a numeral")
end

if failures > 0 then
	error(`{failures} of {total} checks failed`)
end

print(`all {total} checks passed`)
