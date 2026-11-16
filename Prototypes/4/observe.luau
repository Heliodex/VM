--!strict
-- OBSERVING A VALUE
--
-- A value is read by applying it to a probe and an eraser and reducing. What the value does with the probe is what its normal form records, and two values are told apart by comparing those normal forms.
-- This is needed because the normal form of a value can depend on how its copies were arranged, so comparing a value's net directly is not sound (see numerals.luau).
-- Numerals and booleans are both read this way. Each has its own readback, which compares an observation with the observations of the canonical values.

const B = require "./builder"
const L = require "./lambda"
const Net = require "./net"
const Rules = require "./rules"
const Types = require "./types"

type Builder = B.Builder
type Net = Types.Net
type Port = Types.Port

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

return {
	probe = probe,
	observe = observe,
}
