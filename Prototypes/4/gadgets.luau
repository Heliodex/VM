--!strict
-- THE STANDARD CONSTRUCTIONS
--
-- The three combinators are enough to build every interaction system there is, but only through a handful of nets that are used over and over.
-- This file builds them one at a time, each with the property it has to satisfy, so that everything above it can be written without touching a raw cell.
--
--   local G = require "./gadgets"
--
--   local m = G.multiplexer(b, 3)
--   local d = G.dualMultiplexer(b, 3)
--   b:wire(m.principal, d.principal)
--
-- A construction is handed a builder rather than returning a net of its own, so that a gadget is a fragment of whatever net is being built and its free ports can be wired to anything, including other gadgets.
-- Nothing here has a main port wired up: a gadget does nothing until its principal port meets another cell, which is what leaves the caller free to compose them.
--
-- Figures are from Y. Lafont, "Interaction Combinators", Information and Computation 137 (1997), §2.2.

local B = require "./builder"
local Types = require "./types"

type Builder = B.Builder
type Fragment = Types.Fragment
type Port = Types.Port

-- A multiplexer of arity n: M(2) is a single gamma, and each further one is a gamma carrying the one before it.
-- Multiplexers are built from gamma and epsilon alone, never from delta, which is what Fig. 4 requires.
const function multiplexer(
	b: Builder,
	n: number
): Fragment
	if n < 2 then
		error(`a multiplexer needs an arity of at least 2, got {n}`)
	end

	const top = b:gamma()
	const ports: { Port } = {
		top.aux1 :: Port,
	}

	if n == 2 then
		table.insert(ports, top.aux2 :: Port)
	else
		const rest = multiplexer(b, n - 1)
		b:wire(top.aux2, rest.principal)

		for _, p in rest.ports do
			table.insert(ports, p)
	end end

	return {
		principal = top.principal,
		ports = ports,
	}
end

-- The dual of a multiplexer, which is the same net with its ports taken in the opposite order.
-- The dual is what lets a pair cancel: gamma meets gamma across the auxiliaries, so two constructions that put their ports in the same order would join them crossed, and there would be no identity wiring.
const function dualMultiplexer(
	b: Builder,
	n: number
): Fragment
	if n < 2 then
		error(`a multiplexer needs an arity of at least 2, got {n}`)
	end

	const top = b:gamma()
	local ports: { Port } = {}

	if n == 2 then
		-- the base case is where the reversal shows
		table.insert(ports, top.aux2 :: Port)
		table.insert(ports, top.aux1 :: Port)
	else
		const rest = dualMultiplexer(b, n - 1)
		b:wire(top.aux1, rest.principal)
		-- the new port goes first, so that the k-th port here meets the k-th port of the multiplexer it cancels against
		table.insert(ports, top.aux2 :: Port)

		for _, p in rest.ports do
			table.insert(ports, p)
	end end

	return {
		principal = top.principal,
		ports = ports,
	}
end

-- A gamma wired to a port by one auxiliary, so that the port is closed off without anything reducing.
-- With the ports left bare a cancelled gadget leaves no cells at all, and in that net every wiring is indistinguishable from every other, so a test of a wiring needs something left behind to compare.
const function probe(
	b: Builder,
	p: Port
): B.Handle
	const h = b:gamma()
	b:wire(h.aux1, p)

	return h
end

-- Probe every port of a fragment, in order, and hand back the probes.
const function probeAll(
	b: Builder,
	ports: { Port }
): { B.Handle }
	const handles: { B.Handle } = {}

	for i, p in ports do
		handles[i] = probe(b, p)
	end

	return handles
end

return {
	multiplexer = multiplexer,
	dualMultiplexer = dualMultiplexer,
	probe = probe,
	probeAll = probeAll,
}
