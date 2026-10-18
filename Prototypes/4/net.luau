--!strict
-- THE INTERACTION NET ENGINE
--
-- Everything there is to know about a net and about reducing one: the symbols and the arithmetic on ports, building and rewiring cells and wires, the six interaction rules, and the step that applies one of them. A net is built by hand here -- there is no higher-level syntax for one yet -- and then reduced one step at a time until no redex is left, at which point the normal form is unique up to isomorphism, if there is one at all. Reduction does not always terminate, so a caller is expected to bound it; see main.luau.
--
--   const Net = require "./net"
--
--   const net = Net.newNet()
--   local a = Net.alloc(net, Net.GAMMA)
--   local b = Net.alloc(net, Net.GAMMA)
--   Net.link(net, Net.principal(a), Net.principal(b))
--
--   while Net.step(net) do
--       ...
--   end

const Types = require "./types"

type Gamma = Types.Gamma
type Delta = Types.Delta
type Epsilon = Types.Epsilon
type Symbol = Types.Symbol
type Cell = Types.Cell
type Port = Types.Port
const GAMMA: Gamma = "Gamma"
const DELTA: Delta = "Delta"
const EPSILON: Epsilon = "Epsilon"
const STRIDE = 3

const function principal(
	a: Cell
): Port
	return (a - 1) * STRIDE + 1
end

const function aux1(
	a: Cell
): Port
	return (a - 1) * STRIDE + 2
end

const function aux2(
	a: Cell
): Port
	return aux1(a) + 1
end

const function owner(
	p: Port
): Cell
	return (p - 1) // STRIDE + 1
end

const function isPrincipal(
	p: Port
): boolean
	return (p - 1) % STRIDE == 0
end

-- To sum up, a net is completely described by the following data:
--     a finite set X (of free ports),
--     a finite set C (of cells),
--     a symbol l(c) for each c ∈ C,
--     a finite set W (of wires),
--     a set δw of 0 or 2 ports for each w ∈ W.
type Net = Types.Net

const function newNet(): Net
	return {
		Tag = {},
		Link = {},
		Active = {},
		Free = {},
	}
end

const function alloc(
	net: Net,
	symbol: Symbol
): Cell
	-- 1. pick a slot: reuse a freed cell id, else grow by one
	const c = table.remove(net.Free) or #net.Tag + 1
	-- 2. record the symbol l(c)
	net.Tag[c] = symbol
	-- 3. clear all three of its ports (mark them as free ports)
	const p = principal(c)
	net.Link[p], net.Link[p + 1], net.Link[p + 2] = 0, 0, 0

	-- 4. give the caller a handle
	return c
end

const function release(
	net: Net,
	c: Cell
)
	const p = principal(c)
	net.Link[p], net.Link[p + 1], net.Link[p + 2] = 0, 0, 0
	table.insert(net.Free, c)
end

-- Wire two ports. 0 is safe as the "free" sentinel because port ids start at 1.
const function link(
	net: Net,
	p: Port,
	q: Port
)
	net.Link[p], net.Link[q] = q, p

	if isPrincipal(p) and isPrincipal(q) then
		table.insert(net.Active, p)
end end

const function splice(
	net: Net,
	p: Port,
	q: Port
)
	-- remember what p and q were wired to
	local r, s = net.Link[p], net.Link[q]

	-- if p and q were wired directly to each other, both ends die with them
	if r == q then
		r = 0
	end

	if s == p then
		s = 0
	end

	-- detach p and q from the graph
	net.Link[p], net.Link[q] = 0, 0

	-- reconnect the surviving ends to each other
	if r ~= 0 then
		net.Link[r] = s
	end

	if s ~= 0 then
		net.Link[s] = r
	end

	-- joining two continuations may have created a fresh redex
	if r ~= 0 and s ~= 0 and isPrincipal(r) and isPrincipal(s) then
		table.insert(net.Active, r)
end end

-- Redirect p's wire onto q, leaving p free. Used when a cell dissolves but its continuations must stay connected. q must be a fresh (unwired) port.
const function move(
	net: Net,
	p: Port,
	q: Port
)
	const r = net.Link[p]
	net.Link[p] = 0
	net.Link[q] = r

	if r == 0 then
		return
	end

	net.Link[r] = q

	if isPrincipal(q) and isPrincipal(r) then
		table.insert(net.Active, q)
end end

type Rule = (net: Net, a: Cell, b: Cell) -> ()
-- The six interaction rules of Fig. 2, keyed by the pair of symbols meeting.
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
	splice(net, aux1(a), aux2(b))
	splice(net, aux2(a), aux1(b))
	release(net, a)
	release(net, b)
end
-- Annihilation: delta-delta connects them straight.
RULES[DELTA][DELTA] = function(
	net,
	a,
	b
)
	splice(net, aux1(a), aux1(b))
	splice(net, aux2(a), aux2(b))
	release(net, a)
	release(net, b)
end
-- Annihilation: two erasers simply vanish.
RULES[EPSILON][EPSILON] = function(
	net,
	a,
	b
)
	release(net, a)
	release(net, b)
end

-- Commutation of two different binary cells: each becomes two copies, wired into the square of Fig. 2. a and b must carry different symbols.
const function commute(
	net: Net,
	a: Cell,
	b: Cell
)
	const atag = net.Tag[a]
	const btag = net.Tag[b]
	const a1, a2 = alloc(net, atag), alloc(net, atag)
	const b1, b2 = alloc(net, btag), alloc(net, btag)
	-- every continuation now meets the principal port of a copy
	move(net, aux1(a), principal(b1))
	move(net, aux2(a), principal(b2))
	move(net, aux1(b), principal(a2))
	move(net, aux2(b), principal(a1))
	-- cross-wire the copies
	link(net, aux2(b1), aux1(a1))
	link(net, aux1(b1), aux1(a2))
	link(net, aux2(b2), aux2(a1))
	link(net, aux1(b2), aux2(a2))
	release(net, a)
	release(net, b)
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

	const e1, e2 = alloc(net, EPSILON), alloc(net, EPSILON)
	move(net, aux1(x), principal(e1))
	move(net, aux2(x), principal(e2))
	release(net, x)
	release(net, e)
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

		if q == 0 or not isPrincipal(q) or net.Link[q] ~= p then
			continue -- free port, stale entry, or already reduced
		end

		const a, b = owner(p), owner(q)
		const rule = RULES[net.Tag[a]][net.Tag[b]]

		if not rule then
			error(`No rule for {net.Tag[a]} meeting {net.Tag[b]}`)
		end

		rule(net, a, b)

		return true
	end

	return false
end

-- queries ------------------------------------------------------------------
const function wellFormed(
	net: Net
): boolean
	for p, q in net.Link do
		if q ~= 0 and net.Link[q] ~= p then
			return false
	end end

	return true
end

-- The cells that are still alive (release() keeps Tag around for slot reuse).
const function liveCells(
	net: Net
): { Cell }
	const freed: {
		[Cell]: boolean,
	} = {}

	for _, c in net.Free do
		freed[c] = true
	end

	const live: { Cell } = {}

	for c = 1, #net.Tag do
		if net.Tag[c] ~= nil and not freed[c] then
			table.insert(live, c)
	end end

	return live
end

-- Same net up to renaming of cells. Cell ids are recycled during reduction, so two equal results usually have completely different ids.
const function isomorphic(
	a: Net,
	b: Net
): boolean
	const left, right = liveCells(a), liveCells(b)

	if #left ~= #right then
		return false
	end

	const map: {
		[Cell]: Cell,
	} = {}
	const taken: {
		[Cell]: boolean,
	} = {}

	const function verify(): boolean
		for _, ca in left do
			const cb = map[ca]
			const pa, pb = (ca - 1) * STRIDE, (cb - 1) * STRIDE

			for slot = 1, STRIDE do
				const x, y = a.Link[pa + slot] or 0, b.Link[pb + slot] or 0
				const x0, y0 = x == 0, y == 0

				if x0 ~= y0 then
					return false
				end

				if x == 0 then
					continue
				end

				if map[owner(x)] ~= owner(y) or (x - 1) % STRIDE ~= (y - 1) % STRIDE then
					return false
		end end end

		return true
	end

	const function search(
		i: number
	): boolean
		if i > #left then
			return verify()
		end

		const ca = left[i]

		for _, cb in right do
			if not taken[cb] and a.Tag[ca] == b.Tag[cb] then
				map[ca], taken[cb] = cb, true

				if search(i + 1) then
					return true
				end

				map[ca], taken[cb] = nil, nil
		end end

		return false
	end

	return search(1)
end

return {
	GAMMA = GAMMA,
	DELTA = DELTA,
	EPSILON = EPSILON,
	STRIDE = STRIDE,

	principal = principal,
	aux1 = aux1,
	aux2 = aux2,
	owner = owner,
	isPrincipal = isPrincipal,

	newNet = newNet,
	alloc = alloc,
	release = release,
	link = link,
	splice = splice,
	move = move,

	step = step,

	wellFormed = wellFormed,
	liveCells = liveCells,
	isomorphic = isomorphic,
}
