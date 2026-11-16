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
const Codes = require "./codes"
const G = require "./gadgets"
const H = require "./harness"
const L = require "./lambda"
const Li = require "./lists"
const Net = require "./net"
const N = require "./numerals"
const Rec = require "./recursion"
const Rules = require "./rules"
const Types = require "./types"

type Builder = B.Builder
type Net = Types.Net
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

-- Lists: build a list of numerals, take it apart, and read the parts back.
local function listOf(
	b: Builder,
	elements: { number }
): Port
	local list = Li.nilValue(b)

	for i = #elements, 1, -1 do
		list = L.app(b, L.app(b, Li.cons(b), N.church(b, elements[i])), list)
	end

	return list
end

-- Build a term with `build`, reduce it, and return the report and the net.
local function evaluate(
	build: (Builder) -> Port
): (H.Report, Net)
	const b = B.new()
	build(b)
	const net = b:finish()

	return H.reduce(net, H.DEFAULT_BUDGET), net
end

const DEFAULT = 9

for _, elements in {
	{},
	{
		4,
	},
	{
		2,
		3,
	},
} do
	const want = #elements == 0
	const result, net = evaluate(function(
		b
	)
		return L.app(b, Li.isNil(b), listOf(b, elements))
	end)
	report(result.outcome == "reduced" and Bo.readback(net) == want, `isNil of {#elements} elements is {want}  ({H.describe(result)})`)
end

do
	const result, net = evaluate(function(
		b
	)
		return L.app(
			b, L.app(
				b, Li.head(b), listOf(
					b, {
						2,
						3,
					}
				)
			), N.church(b, DEFAULT)
		)
	end)
	report(result.outcome == "reduced" and N.readback(net) == 2, `head of [2, 3] is 2  ({H.describe(result)})`)
end

do
	const result, net = evaluate(function(
		b
	)
		const rest = L.app(
			b, L.app(
				b, Li.tail(b), listOf(
					b, {
						2,
						3,
					}
				)
			), N.church(b, DEFAULT)
		)

		return L.app(b, L.app(b, Li.head(b), rest), N.church(b, DEFAULT))
	end)
	report(result.outcome == "reduced" and N.readback(net) == 3, `head of tail of [2, 3] is 3  ({H.describe(result)})`)
end

do
	const result, net = evaluate(function(
		b
	)
		return L.app(b, L.app(b, Li.head(b), Li.nilValue(b)), N.church(b, DEFAULT))
	end)
	report(result.outcome == "reduced" and N.readback(net) == DEFAULT, `head of [] is the default {DEFAULT}  ({H.describe(result)})`)
end

do
	const result, net = evaluate(function(
		b
	)
		return L.app(
			b, Li.isNil(b), L.app(
				b, L.app(
					b, Li.tail(b), listOf(
						b, {
							2,
						}
					)
				), Bo.boolean(b, false)
			)
		)
	end)
	report(result.outcome == "reduced" and Bo.readback(net) == true, `tail of [2] is empty  ({H.describe(result)})`)
end

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

-- Codes: a code has no δ in it, decoding it gives back the net it was made from, and a δ fan copies it so that each copy decodes to the same net.
const function steps(
	net: Net
): number
	local count = 0

	while count < ARITH_BUDGET and Rules.step(net) do
		count += 1
	end

	return count
end

const encodable: { {
	name: string,
	make: () -> Net,
} } = {
	{
		name = "T(4)",
		make = function()
			const b = B.new()
			G.autodualMultiplexer(b, 4)

			return b:finish()
		end,
	},
	{
		name = "T(2, 1)",
		make = function()
			const b = B.new()
			G.transpositor(b, 2, 1)

			return b:finish()
		end,
	},
	{
		name = "numeral 3",
		make = function()
			return N.numeral(3)
		end,
	},
}

for _, case in encodable do
	const original = case.make()
	const b = B.new()
	const code = Codes.encode(b, original)
	const clean = not Codes.hasDelta(b.net)
	const d = Codes.decoder(b, #Codes.freePorts(original))
	b:wire(code, d.principal)
	const net = b:finish()
	const taken = steps(net)
	report(clean and taken < ARITH_BUDGET and Canon.isomorphic(net, case.make()), `the code of {case.name} has no δ and decodes to it  ({taken} steps)`)
end

for n = 0, 3 do
	const b = B.new()
	const code = Codes.encode(b, N.numeral(n))
	const fan = b:delta()
	b:wire(code, fan.principal)
	b:wire(fan.aux1, Codes.decoder(b, 1).principal)
	b:wire(fan.aux2, Codes.decoder(b, 1).principal)
	const net = b:finish()
	const taken = steps(net)
	const twice = B.new()
	N.church(twice, n)
	N.church(twice, n)
	report(taken < ARITH_BUDGET and Canon.isomorphic(net, twice:finish()), `a δ fan copies the code of numeral {n} into two that decode  ({taken} steps)`)
end

-- Recursion through codes: length and sum fold over a list, and the recursive function on its own reduces to a normal form instead of unfolding.
do
	const b = B.new()
	Rec.length(b)
	const net = b:finish()
	const taken = steps(net)
	report(taken < ARITH_BUDGET, `length on its own reaches a normal form  ({taken} steps)`)
end

for _, elements in {
	{},
	{
		7,
	},
	{
		7,
		8,
	},
	{
		1,
		2,
		3,
	},
} do
	local expected = 0

	for _, k in elements do
		expected += k
	end

	for _, case in {
		{
			name = "length",
			build = Rec.length,
			want = #elements,
		},
		{
			name = "sum",
			build = Rec.sum,
			want = expected,
		},
	} do
		const b = B.new()
		L.app(b, case.build(b), listOf(b, elements))
		const net = b:finish()
		const taken = steps(net)
		report(taken < ARITH_BUDGET and N.readback(net) == case.want, `{case.name} of {#elements} elements is {case.want}  ({taken} steps)`)
end end

if failures > 0 then
	error(`{failures} of {total} checks failed`)
end

print(`all {total} checks passed`)
