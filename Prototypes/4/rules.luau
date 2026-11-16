--!strict
-- THE SIX INTERACTION RULES
--
-- The rules of Fig. 2 of Lafont's paper, keyed by the pair of symbols that meet, and the single step that applies whichever one is ready.
-- Each rule rewires the cells in place through the wiring primitives of net.luau, so a rule never has to know how ports are numbered.

local Net = require "./net"
local Types = require "./types"

type Symbol = Types.Symbol
type Cell = Types.Cell
type Net = Types.Net
const GAMMA, DELTA, EPSILON = Net.GAMMA, Net.DELTA, Net.EPSILON
type Rule = (net: Net, a: Cell, b: Cell) -> ()
const RULES: {
	[Symbol]: {
		[Symbol]: Rule,
	},
} = {
	[GAMMA] = {},
	[DELTA] = {},
	[EPSILON] = {},
}
-- Annihilation: gamma-gamma exchanges the auxiliary ports.
RULES[GAMMA][GAMMA] = function(
	net,
	a,
	b
)
	Net.splice(net, Net.aux1(a), Net.aux2(b))
	Net.splice(net, Net.aux2(a), Net.aux1(b))
	Net.release(net, a)
	Net.release(net, b)
end
-- Annihilation: delta-delta connects them straight.
RULES[DELTA][DELTA] = function(
	net,
	a,
	b
)
	Net.splice(net, Net.aux1(a), Net.aux1(b))
	Net.splice(net, Net.aux2(a), Net.aux2(b))
	Net.release(net, a)
	Net.release(net, b)
end
-- Annihilation: two erasers simply vanish.
RULES[EPSILON][EPSILON] = function(
	net,
	a,
	b
)
	Net.release(net, a)
	Net.release(net, b)
end

-- Commutation of two different binary cells: each becomes two copies, wired into the square of Fig. 2. a and b must carry different symbols.
const function commute(
	net: Net,
	a: Cell,
	b: Cell
)
	const atag = net.Tag[a]
	const btag = net.Tag[b]
	const a1, a2 = Net.alloc(net, atag), Net.alloc(net, atag)
	const b1, b2 = Net.alloc(net, btag), Net.alloc(net, btag)
	-- every continuation now meets the principal port of a copy
	Net.move(net, Net.aux1(a), Net.principal(b1))
	Net.move(net, Net.aux2(a), Net.principal(b2))
	Net.move(net, Net.aux1(b), Net.principal(a2))
	Net.move(net, Net.aux2(b), Net.principal(a1))
	-- cross-wire the copies
	Net.link(net, Net.aux2(b1), Net.aux1(a1))
	Net.link(net, Net.aux1(b1), Net.aux1(a2))
	Net.link(net, Net.aux2(b2), Net.aux2(a1))
	Net.link(net, Net.aux1(b2), Net.aux2(a2))
	Net.release(net, a)
	Net.release(net, b)
end

RULES[GAMMA][DELTA] = commute
RULES[DELTA][GAMMA] = commute

-- Commutation with an eraser: every auxiliary port gets its own eraser.
-- Exactly one of a, b is the eraser, so the binary cell is found regardless of the order in which the active pair happened to be discovered.
const function erase(
	net: Net,
	a: Cell,
	b: Cell
)
	local x, e = a, b

	if net.Tag[x] == EPSILON then
		x, e = b, a
	end

	const e1, e2 = Net.alloc(net, EPSILON), Net.alloc(net, EPSILON)
	Net.move(net, Net.aux1(x), Net.principal(e1))
	Net.move(net, Net.aux2(x), Net.principal(e2))
	Net.release(net, x)
	Net.release(net, e)
end

RULES[GAMMA][EPSILON] = erase
RULES[EPSILON][GAMMA] = erase
RULES[DELTA][EPSILON] = erase
RULES[EPSILON][DELTA] = erase

-- Perform a single interaction, if any. Returns whether one happened.
const function step(
	net: Net
): boolean
	-- Pop the *oldest* redex, not the newest. With a LIFO stack, freshly created redexes keep landing on top of older ones, so an older pair can be starved forever; delta(epsilon, x) = gamma(x, epsilon) then grows without bound instead of cycling. FIFO is fair: every enqueued pair is eventually taken.
	const active = net.Active

	while #active > 0 do
		const p = active[1]
		table.remove(active, 1)
		const q = net.Link[p]

		if q == 0 or not Net.isPrincipal(q) or net.Link[q] ~= p then
			continue -- free port, stale entry, or already reduced
		end

		const a, b = Net.owner(p), Net.owner(q)
		const rule = RULES[net.Tag[a]][net.Tag[b]]

		if not rule then
			error(`No rule for {net.Tag[a]} meeting {net.Tag[b]}`)
		end

		rule(net, a, b)

		return true
	end

	return false
end

return {
	step = step,
}
