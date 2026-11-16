--!strict
-- THE NETS UNDER TEST
--
-- Each test builds a net, says what it should reduce to, and gives the step budget it is allowed.

local B = require "./builder"
local G = require "./gadgets"
local L = require "./lambda"
local Types = require "./types"

type Builder = B.Builder
type Net = Types.Net
type Port = Types.Port
-- A net is described by a function that builds one into a builder it is handed.
-- build owns the builder and finishes it, so a test never has to say where its net begins or ends and can simply end at its last wire.
-- Free ports are whatever was left unwired, and are where the answer of a reduction is expected to show up.
type Build = (Builder) -> ()

const function build(
	f: Build
): Net
	local b = B.new()
	f(b)

	return b:finish()
end

-- lambda tests ---------------------------------------------------------------
-- The identity abstraction, as a value. Its root is the abstraction's principal port and its variable is used once, straight through to the body.
const function identity(
	b: Builder
): Port
	return L.lam(
		b, function(
			x: Port
		): Port
			return x
		end
	)
end

-- gadget tests ----------------------------------------------------------------
-- A probe closes off a port without anything reducing, since it is wired on an auxiliary.
-- Left bare, a cancelled multiplexer pair leaves no cells at all, and in a net with no cells every wiring looks like every other, so a probe has to carry a tail whose length says which port it came from before a crossed pairing can be told apart from the identity.
local function tail(
	b: Builder,
	h: B.Handle,
	depth: number
)
	local cur = h

	for _ = 1, depth do
		const next = b:gamma()
		b:wire(cur.aux2, next.aux1)
		cur = next
end end

local function probe(
	b: Builder,
	p: Port,
	depth: number
): B.Handle
	const h = b:gamma()
	b:wire(h.aux1, p)
	tail(b, h, depth)

	return h
end

-- The net a gadget pair should reduce to when port i of one side meets port image(i) of the other.
-- Every port carries a tail of its own length, so a pairing other than the one expected ends up joining tails of different lengths and cannot pass for the right one.
local function paired(
	b: Builder,
	n: number,
	image: (number) -> number
)
	for i = 1, n do
		const left, right = b:gamma(), b:gamma()
		b:wire(left.aux1, right.aux1)
		tail(b, left, i - 1)
		tail(b, right, image(i) - 1)
end end

type Test = {
	read name: string,
	read start: Build,
	read expect: Build?,
	read budget: number?,
}
-- nil means the reduction is expected not to finish
const tests: { Test } = {
	{
		name = "epsilon-epsilon annihilates to nothing",
		start = function(
			b
		)
			local e1, e2 = b:epsilon(), b:epsilon()
			b:meet(e1, e2)
		end,
		expect = function()
		end,
	},
	{
		name = "gamma-gamma exchanges its wires",
		start = function(
			b
		)
			local g1, g2 = b:gamma(), b:gamma()
			local d1, d2, d3, d4 = b:delta(), b:delta(), b:delta(), b:delta()
			b:meet(g1, g2)
			b:wire(g1.aux1, d1.aux1)
			b:wire(g1.aux2, d2.aux1)
			b:wire(g2.aux1, d3.aux1)
			b:wire(g2.aux2, d4.aux1)
		end,
		-- the crossed pairs become the deltas' own auxiliaries
		expect = function(
			b
		)
			local d1, d2, d3, d4 = b:delta(), b:delta(), b:delta(), b:delta()
			b:wire(d1.aux1, d4.aux1)
			b:wire(d2.aux1, d3.aux1)
		end,
	},
	{
		name = "delta-delta is straight",
		start = function(
			b
		)
			local d1, d2 = b:delta(), b:delta()
			local g1, g2, g3, g4 = b:gamma(), b:gamma(), b:gamma(), b:gamma()
			b:meet(d1, d2)
			b:wire(d1.aux1, g1.aux1)
			b:wire(d1.aux2, g2.aux1)
			b:wire(d2.aux1, g3.aux1)
			b:wire(d2.aux2, g4.aux1)
		end,
		expect = function(
			b
		)
			local g1, g2, g3, g4 = b:gamma(), b:gamma(), b:gamma(), b:gamma()
			b:wire(g1.aux1, g3.aux1)
			b:wire(g2.aux1, g4.aux1)
		end,
	},
	{
		name = "gamma-erase spawns one eraser per auxiliary",
		start = function(
			b
		)
			local g = b:gamma()
			local d1, d2 = b:delta(), b:delta()
			local e = b:epsilon()
			b:meet(g, e)
			b:wire(g.aux1, d1.aux1)
			b:wire(g.aux2, d2.aux1)
		end,
		expect = function(
			b
		)
			local d1, d2 = b:delta(), b:delta()
			local e1, e2 = b:epsilon(), b:epsilon()
			b:wire(d1.aux1, e1.principal)
			b:wire(d2.aux1, e2.principal)
		end,
	},
	{
		name = "gamma meets delta in the commutation square",
		start = function(
			b
		)
			local g, d = b:gamma(), b:delta()
			b:meet(g, d)
		end,
		expect = function(
			b
		)
			local d1, d2 = b:delta(), b:delta()
			local g1, g2 = b:gamma(), b:gamma()
			b:wire(d1.aux2, g1.aux1)
			b:wire(d1.aux1, g2.aux1)
			b:wire(d2.aux2, g1.aux2)
			b:wire(d2.aux1, g2.aux2)
		end,
	},
	{
		name = "a gamma erased on every port vanishes completely",
		start = function(
			b
		)
			local g = b:gamma()
			local e1, e2, e3 = b:epsilon(), b:epsilon(), b:epsilon()
			b:meet(g, e1)
			b:wire(g.aux1, e2.principal)
			b:wire(g.aux2, e3.principal)
		end,
		expect = function()
		end,
	},
	{
		name = "M3 meets its dual and cancels to nothing",
		start = function(
			b
		)
			const m = G.multiplexer(b, 3)
			const d = G.dualMultiplexer(b, 3)
			b:wire(m.principal, d.principal)
		end,
		expect = function()
		end,
	},
	{
		name = "M3 meeting its dual joins its ports in order",
		start = function(
			b
		)
			const m = G.multiplexer(b, 3)
			const d = G.dualMultiplexer(b, 3)
			b:wire(m.principal, d.principal)

			for k, p in m.ports do
				probe(b, p, k - 1)
			end

			for k, p in d.ports do
				probe(b, p, k - 1)
		end end,
		-- the k-th port on one side has to meet the k-th on the other, so each pair is rebuilt with its tails
		expect = function(
			b
		)
			for k = 1, 3 do
				const left, right = b:gamma(), b:gamma()
				b:wire(left.aux1, right.aux1)
				tail(b, left, k - 1)
				tail(b, right, k - 1)
		end end,
	},
	{
		name = "T3 meets itself and cancels to nothing",
		start = function(
			b
		)
			const x = G.autodualMultiplexer(b, 3)
			const y = G.autodualMultiplexer(b, 3)
			b:wire(x.principal, y.principal)
		end,
		expect = function()
		end,
	},
	{
		name = "T3 meeting itself joins its ports in order",
		start = function(
			b
		)
			const x = G.autodualMultiplexer(b, 3)
			const y = G.autodualMultiplexer(b, 3)
			b:wire(x.principal, y.principal)

			for k, p in x.ports do
				probe(b, p, k - 1)
			end

			for k, p in y.ports do
				probe(b, p, k - 1)
		end end,
		-- a delta chain is its own dual, so this cancels against a plain copy of itself rather than against a mirrored one
		expect = function(
			b
		)
			for k = 1, 3 do
				const left, right = b:gamma(), b:gamma()
				b:wire(left.aux1, right.aux1)
				tail(b, left, k - 1)
				tail(b, right, k - 1)
		end end,
	},
	{
		name = "T(1,1) meets itself and swaps its first pair",
		start = function(
			b
		)
			const x = G.transpositor(b, 1, 1)
			const y = G.transpositor(b, 1, 1)
			b:wire(x.principal, y.principal)

			for i, p in x.ports do
				probe(b, p, i - 1)
			end

			for i, p in y.ports do
				probe(b, p, i - 1)
		end end,
		expect = function(
			b
		)
			paired(
				b, 3, function(
					i
				)
					return
						if i <= 2 then
							3 - i
						else
							i
				end
			)
		end,
	},
	{
		name = "T(2,1) meets itself and swaps both its pairs",
		start = function(
			b
		)
			const x = G.transpositor(b, 2, 1)
			const y = G.transpositor(b, 2, 1)
			b:wire(x.principal, y.principal)

			for i, p in x.ports do
				probe(b, p, i - 1)
			end

			for i, p in y.ports do
				probe(b, p, i - 1)
		end end,
		-- the first four ports are swapped in pairs and the fifth is left alone
		expect = function(
			b
		)
			paired(
				b, 5, function(
					i
				)
					return
						if i <= 4 then
							if i % 2 == 1 then
								i + 1
							else
								i - 1
						else
							i
				end
			)
		end,
	},
	{
		name = "T(sigma) meets itself and realises sigma",
		start = function(
			b
		)
			const sigma = {
				3,
				2,
				1,
			}
			const x = G.permutation(b, sigma)
			const y = G.permutation(b, sigma)
			b:wire(x.principal, y.principal)

			for i, p in x.ports do
				probe(b, p, i - 1)
			end

			for i, p in y.ports do
				probe(b, p, i - 1)
		end end,
		-- a transposition of two ports that are not next to each other, so the relabelling onto the transpositor is doing real work
		expect = function(
			b
		)
			paired(
				b, 3, function(
					i
				)
					return 4 - i
				end
			)
		end,
	},
	{
		name = "delta(epsilon, x) = gamma(x, epsilon)",
		start = function(
			b
		)
			local d, g = b:delta(), b:gamma()
			local e1, e2 = b:epsilon(), b:epsilon()
			b:meet(d, g)
			b:wire(d.aux1, e1.principal)
			b:wire(d.aux2, g.aux1)
			b:wire(g.aux2, e2.principal)
		end,
		expect = nil, -- does not terminate
		budget = 200,
	},
	{
		name = "lambda: identity applied to identity is identity",
		start = function(
			b
		)
			L.app(b, identity(b), identity(b))
		end,
		expect = function(
			b
		)
			identity(b)
		end,
	},
	{
		name = "lambda: constant applied to two values erases the second",
		start = function(
			b
		)
			const constant = L.lam(
				b, function(
					x: Port
				): Port
					return L.lam(
						b, function(
							_y: Port
						): Port
							return x
						end
					)
				end
			)
			L.app(b, L.app(b, constant, identity(b)), identity(b))
		end,
		expect = function(
			b
		)
			identity(b)
		end,
	},
	{
		name = "lambda: a variable used twice is shared",
		start = function(
			b
		)
			const double = L.lam(
				b, function(
					x: Port
				): Port
					const copies = L.share(b, x, 2)

					return L.app(b, copies[1], copies[2])
				end
			)
			L.app(b, double, identity(b))
		end,
		expect = function(
			b
		)
			identity(b)
		end,
	},
	{
		name = "lambda: a variable used three times is shared",
		start = function(
			b
		)
			const triple = L.lam(
				b, function(
					x: Port
				): Port
					const copies = L.share(b, x, 3)

					return L.app(b, L.app(b, copies[1], copies[2]), copies[3])
				end
			)
			L.app(b, triple, identity(b))
		end,
		expect = function(
			b
		)
			identity(b)
		end,
	},
	{
		name = "lambda: an unused argument is erased",
		start = function(
			b
		)
			const ignore = L.lam(
				b, function(
					_x: Port
				): Port
					return identity(b)
				end
			)
			L.app(b, ignore, identity(b))
		end,
		expect = function(
			b
		)
			identity(b)
		end,
	},
}

return {
	build = build,
	tests = tests,
}
