--!strict
-- NATURAL NUMBERS AS CHURCH NUMERALS
--
-- The number n is the value λf.λx. f(f(...(f x))), with n applications of f to x, built with the lambda encoding of lambda.luau. Zero is λf.λx.x, where f is erased.
-- A numeral is a closed value, so the value convention applies: its normal form has exactly one free port, its principal root.
--
--   const N = require "./numerals"
--
--   const net = N.numeral(3)
--   H.reduce(net)
--   print(N.readback(net)) -- 3
--
-- Readback is observational. Two nets that compute the same function can have different normal forms: when a value shares a variable between copies, the copies can be arranged in different trees, and interaction nets have no rule that reshapes such a tree. So a value is not read by comparing its net. It is applied to a probe and an eraser, the result is reduced, and that is compared with the same process run on each numeral. The probe is built so that each application leaves one visible cell behind, and the copies made along the way are all fed, so none of them is left unused.

const B = require "./builder"
const Canon = require "./canon"
const L = require "./lambda"
const Net = require "./net"
const Rules = require "./rules"
const Types = require "./types"

type Builder = B.Builder
type Net = Types.Net
type Port = Types.Port

-- The numeral n, built into `b`. Returns its root, the principal port of the outermost abstraction.
const function church(
	b: Builder,
	n: number
): Port
	if n < 0 or n ~= math.floor(n) then
		error(`a numeral is a natural number, not {n}`)
	end

	return L.lam(
		b, function(
			f: Port
		): Port
			const fs = L.share(b, f, n)

			return L.lam(
				b, function(
					x: Port
				): Port
					-- f(f(...(f x))): the innermost application is the last copy of f
					local body = x

					for i = n, 1, -1 do
						body = L.app(b, fs[i], body)
					end

					return body
				end
			)
		end
	)
end

-- The numeral n as a net of its own, with its root free.
const function numeral(
	n: number
): Net
	const b = B.new()
	church(b, n)

	return b:finish()
end

-- The probe that observation applies a value to: T = λy.λz. G, where G is a gamma cell with y on its aux1 and z on its aux2. Each application of T adds one G cell, so the normal form of a value applied to T and an eraser is a chain whose length is the number of applications.
const function probe(
	b: Builder
): Port
	return L.lam(
		b, function(
			y: Port
		): Port
			return L.lam(
				b, function(
					z: Port
				): Port
					const g = b:gamma()
					b:wire(g.aux1 :: Port, y)
					b:wire(g.aux2 :: Port, z)

					return g.principal :: Port
				end
			)
		end
	)
end

-- The most steps an observation may take. A value that does not finish within this has no reading.
const OBSERVE_BUDGET = 5000

-- The normal form of `original` applied to the probe and then to an eraser, or nil if it does not finish or has no single free root.
const function observe(
	original: Net
): Net?
	local root: Port? = nil
	local free = 0

	for _, c in Net.liveCells(original) do
		for slot = 1, Net.portCount(original.Tag[c]) do
			const p = Net.port(c, slot)

			if (original.Link[p] or 0) == 0 then
				free += 1

				if Net.isPrincipal(p) then
					root = p
	end end end end

	if free ~= 1 then
		return nil
	end

	if root == nil then
		return nil
	end

	const found: Port = root
	-- observe on a copy, so reading a value never changes it
	const net: Net = {
		Tag = table.clone(original.Tag),
		Link = table.clone(original.Link),
		Active = table.clone(original.Active),
		Free = table.clone(original.Free),
	}
	const b = B.from(net)
	const applied = L.app(b, found, probe(b))
	L.app(b, applied, b:epsilon().principal)
	-- Plain stepping: the harness would also fingerprint every state to look for cycles, which costs far more than the observation itself.
	local steps = 0

	while Rules.step(net) do
		steps += 1

		if steps > OBSERVE_BUDGET then
			return nil
	end end

	return net
end

-- The largest numeral readback will try.
const MAX_READBACK = 64
-- What each numeral observes as, so that a numeral is observed once however many values are read back.
local observed: { Net? } = {}
local tried: { boolean } = {}

-- The number that a closed value stands for, or nil if it is not a numeral.
-- It is the k whose observation is the same as the value's.
const function readback(
	original: Net
): number?
	const seen = observe(original)

	if not seen then
		return nil
	end

	for k = 0, MAX_READBACK do
		if not tried[k] then
			tried[k] = true
			observed[k] = observe(numeral(k))
		end

		const expected = observed[k]

		if expected and Canon.isomorphic(seen, expected) then
			return k
	end end

	return nil
end

return {
	church = church,
	numeral = numeral,
	readback = readback,
}
