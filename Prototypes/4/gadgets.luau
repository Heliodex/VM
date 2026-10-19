--!strict
-- THE STANDARD CONSTRUCTIONS
--
-- The three combinators are enough to build every interaction system there is, but only through a handful of nets that get used over and over.
-- This file builds them one at a time, each with the property it has to satisfy, so that everything above can be written without touching a raw cell.
--
--   local G = require "./gadgets"
--
--   local m = G.multiplexer(b, 3)
--   local d = G.dualMultiplexer(b, 3)
--   b:wire(m.principal, d.principal)
--
-- A construction is handed a builder rather than returning a net of its own, so that a gadget is a fragment of whatever net is being built and its free ports can be wired to anything, including other gadgets.
-- Nothing here has a principal port wired up: a gadget does nothing until its principal port meets another cell, which leaves the caller free to compose them.
--
-- Figures are from Y. Lafont, "Interaction Combinators", Information and Computation 137 (1997), §2.2.

local B = require "./builder"
local Net = require "./net"
local Types = require "./types"

type Builder = B.Builder
type Fragment = Types.Fragment
type Port = Types.Port
type Symbol = Types.Symbol

-- Every construction here has the same shape: a chain of cells, where one auxiliary of each cell carries the port added at that level and the other leads on to the rest of the chain.
-- What separates them is the symbol used and which auxiliary does which, and that single choice is the whole of the difference between a construction and its dual.
--
-- It comes down to how each binary cell annihilates against itself.
-- Gamma meets gamma across its auxiliaries, so a gamma chain and a plain copy of it wired at the principals come out with their ports joined in the opposite order, and a multiplexer can only cancel against a backward one.
-- Delta meets delta straight across, so a delta chain is its own dual and cancels against a plain copy of itself.
const function chain(
	b: Builder,
	symbol: Symbol,
	mirrored: boolean,
	n: number
): Fragment
	if n < 2 then
		error(`a multiplexer needs an arity of at least 2, got {n}`)
	end

	const top =
		if symbol == Net.DELTA then
			b:delta()
		else
			b:gamma()
	-- the port added at this level, and the auxiliary that leads on to the rest of the chain
	const here =
		if mirrored then
			top.aux2
		else
			top.aux1
	const further =
		if mirrored then
			top.aux1
		else
			top.aux2
	const ports: { Port } = {
		here :: Port,
	}

	if n == 2 then
		table.insert(ports, further :: Port)
	else
		const tail = chain(b, symbol, mirrored, n - 1)
		b:wire(further, tail.principal)

		for _, p in tail.ports do
			table.insert(ports, p)
	end end

	return {
		principal = top.principal,
		ports = ports,
	}
end

-- Fig. 4: M(n), built from gamma and epsilon alone, with the port added at each level on the first auxiliary.
-- Requires an arity of at least 2, since M(1) is a bare wire and a wire has no cell to build.
const function multiplexer(
	b: Builder,
	n: number
): Fragment
	return chain(b, Net.GAMMA, false, n)
end

-- Fig. 4: M(n)*, the same net with its ports taken in the opposite order, which is what M(n) cancels against to leave an identity wiring.
const function dualMultiplexer(
	b: Builder,
	n: number
): Fragment
	return chain(b, Net.GAMMA, true, n)
end

-- Fig. 5: T(n), the autodual multiplexer, built from delta and epsilon alone.
-- It needs no separate dual, since T(n) cancels against another plain T(n) to leave an identity wiring.
const function autodualMultiplexer(
	b: Builder,
	n: number
): Fragment
	return chain(b, Net.DELTA, false, n)
end

-- T(p, q), the transpositor of arity 2p+q, which cancels against a plain copy of itself to leave the involution t(p, q).
-- That involution swaps each of the first p pairs of ports, 1 with 2 and so on, and leaves the last q ports alone.
-- Built as Fig. 5 shows it: the p pairs go through gammas, whose principals reach the same delta chain as the q ports that pass straight through.
-- A port that passes straight through needs no cell at all, so it is simply the tail port itself and the fragment hands that port back.
const function transpositor(
	b: Builder,
	p: number,
	q: number
): Fragment
	if p + q < 1 then
		error(`a transpositor needs p + q of at least 1, got {p} + {q}`)
	end

	if p + q == 1 then
		if p == 0 then
			error("T(0, 1) is a bare wire, which has no cell to build")
		end

		-- T(1, 0) leaves nothing for a tail to do, so its single gamma is the whole construction
		const only = b:gamma()

		return {
			principal = only.principal,
			ports = {
				only.aux1 :: Port,
				only.aux2 :: Port,
			},
		}
	end

	const tail = autodualMultiplexer(b, p + q)
	const ports: { Port } = {}

	for k = 1, p do
		const cell = b:gamma()
		b:wire(cell.principal, tail.ports[k])
		table.insert(ports, cell.aux1 :: Port)
		table.insert(ports, cell.aux2 :: Port)
	end

	for j = 1, q do
		table.insert(ports, tail.ports[p + j])
	end

	return {
		principal = tail.principal,
		ports = ports,
	}
end

-- T(sigma), the permutation net of arity n for an involutive permutation sigma, which cancels against a plain copy of itself to leave the wiring sigma.
-- Any involution is a product of disjoint transpositions, so it is t(p, q) seen under a relabelling: send each pair to the front and each fixed point to the back and a transpositor does the rest.
-- The relabelling itself costs no cells, because it is only a wiring: the fragment hands back the transpositor's ports in a different order.
const function permutation(
	b: Builder,
	sigma: { number }
): Fragment
	const n = #sigma

	for i = 1, n do
		const image = sigma[i]

		if image < 1 or image > n then
			error(`port {i} is sent to {image}, which is outside 1 to {n}`)
		end

		if sigma[image] ~= i then
			error(`port {i} goes to {image}, which goes to {sigma[image]}, so this is not an involution`)
		end
	end

	local pairs = 0

	for i = 1, n do
		if sigma[i] ~= i then
			pairs += 1
		end
	end

	pairs //= 2

	const transposed = transpositor(b, pairs, n - 2 * pairs)
	-- the transpositor expects each swapped pair first and each fixed port afterwards, so work out which of its ports each of ours is
	const where: { number } = {}
	local pair = 1
	local fixed = 2 * pairs + 1

	for i = 1, n do
		if sigma[i] == i then
			where[i] = fixed
			fixed += 1
		elseif where[i] == nil then
			where[i] = pair
			where[sigma[i]] = pair + 1
			pair += 2
		end
	end

	const ports: { Port } = {}

	for i = 1, n do
		ports[i] = transposed.ports[where[i]]
	end

	return {
		principal = transposed.principal,
		ports = ports,
	}
end

return {
	multiplexer = multiplexer,
	dualMultiplexer = dualMultiplexer,
	autodualMultiplexer = autodualMultiplexer,
	transpositor = transpositor,
	permutation = permutation,
}
