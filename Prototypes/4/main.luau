--!strict
-- PROTOTYPE BASED ON INTERACTION COMBINATORS

type Gamma = "Gamma"
type Delta = "Delta"
type Epsilon = "Epsilon"

type Symbol = Gamma | Delta | Epsilon

type Cell = number
type Port = number

const GAMMA: Gamma = "Gamma"
const DELTA: Delta = "Delta"
const EPSILON: Epsilon = "Epsilon"

const ARITY = table.freeze {
	[GAMMA] = 2,
	[DELTA] = 2,
	[EPSILON] = 0,
}
const STRIDE = 3

const function principal(a: Cell): Port
	return (a - 1) * STRIDE + 1
end
const function aux1(a: Cell): Port
	return (a - 1) * STRIDE + 2
end
const function aux2(a: Cell): Port
	return aux1(a) + 1
end
const function owner(p: Port): Cell
	return (p - 1) // STRIDE + 1
end
const function isPrincipal(p: Port): boolean
	return (p - 1) % STRIDE == 0
end

-- To sum up, a net is completely described by the following data:
--     a finite set X (of free ports),
--     a finite set C (of cells),
--     a symbol l(c) for each c ∈ C,
--     a finite set W (of wires),
--     a set δw of 0 or 2 ports for each w ∈ W.
type Net = {
	read Tag: { Symbol },
	read Link: { Port },
	read Active: { Port },
	read Free: { Cell },
}

const function newNet(): Net
	return {
		Tag = {},
		Link = {},
		Active = {},
		Free = {},
	}
end

const function alloc(net: Net, symbol: Symbol): Cell
	-- 1. pick a slot: reuse a freed cell id, else grow by one
	local c = table.remove(net.Free) or (#net.Tag + 1)

	-- 2. record the symbol l(c)
	net.Tag[c] = symbol

	-- 3. clear all three of its ports (mark them as free ports)
	local p = principal(c)
	net.Link[p], net.Link[p + 1], net.Link[p + 2] = 0, 0, 0

	-- 4. give the caller a handle
	return c
end

const function release(net: Net, c: Cell)
	local p = principal(c)
	net.Link[p], net.Link[p + 1], net.Link[p + 2] = 0, 0, 0
	table.insert(net.Free, c)
end

-- Wire two ports. 0 is safe as the "free" sentinel because port ids start at 1.
const function link(net: Net, p: Port, q: Port)
	net.Link[p], net.Link[q] = q, p
	if isPrincipal(p) and isPrincipal(q) then
		table.insert(net.Active, p)
	end
end

const function splice(net: Net, p: Port, q: Port)
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
	end
end

-- Redirect p's wire onto q, leaving p free. Used when a cell dissolves but its
-- continuations must stay connected. q must be a fresh (unwired) port.
const function move(net: Net, p: Port, q: Port)
	const r = net.Link[p]
	net.Link[p] = 0
	net.Link[q] = r
	if r == 0 then
		return
	end

	net.Link[r] = q
	if isPrincipal(q) and isPrincipal(r) then
		table.insert(net.Active, q)
	end
end

type Rule = (net: Net, a: Cell, b: Cell) -> ()

-- The six interaction rules of Fig. 2, keyed by the pair of symbols meeting.
const RULES: { [Symbol]: { [Symbol]: Rule } } = {
	[GAMMA] = {},
	[DELTA] = {},
	[EPSILON] = {},
}

-- Annihilation: gamma-gamma exchanges the auxiliary ports.
RULES[GAMMA][GAMMA] = function(net, a, b)
	splice(net, aux1(a), aux2(b))
	splice(net, aux2(a), aux1(b))
	release(net, a)
	release(net, b)
end

-- Annihilation: delta-delta connects them straight.
RULES[DELTA][DELTA] = function(net, a, b)
	splice(net, aux1(a), aux1(b))
	splice(net, aux2(a), aux2(b))
	release(net, a)
	release(net, b)
end

-- Annihilation: two erasers simply vanish.
RULES[EPSILON][EPSILON] = function(net, a, b)
	release(net, a)
	release(net, b)
end

-- Commutation of two different binary cells: each becomes two copies, wired
-- into the square of Fig. 2. a and b must carry different symbols.
const function commute(net: Net, a: Cell, b: Cell)
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
-- Exactly one of a, b is the eraser, so the binary cell is found regardless of
-- the order in which the active pair happened to be discovered.
const function erase(net: Net, a: Cell, b: Cell)
	local x, e = a, b
	if net.Tag[x] == EPSILON then
		x, e = b, a
	end

	local e1, e2 = alloc(net, EPSILON), alloc(net, EPSILON)
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
const function step(net: Net): boolean
	local active = net.Active
	while #active > 0 do
		local n = #active
		local p = active[n]
		active[n] = nil

		local q = net.Link[p]
		if q == 0 or not isPrincipal(q) or net.Link[q] ~= p then
			continue -- free port, stale entry, or already reduced
		end

		local a, b = owner(p), owner(q)
		local rule = RULES[net.Tag[a]][net.Tag[b]]
		if not rule then
			error(`No rule for {net.Tag[a]} meeting {net.Tag[b]}`)
		end
		rule(net, a, b)
		return true
	end
	return false
end

const function reduce(net: Net)
	while step(net) do
	end
end

-- test layer -----------------------------------------------------------------

-- A net for a test is written as a list of cells, each of the form
--   { symbol, label, label, ... }   -- principal port first, then auxiliaries
-- Ports that share a label are wired together; a label used on a single port is
-- a free port. So { {GAMMA, "p", "a", "b"}, {GAMMA, "p", "c", "d"} } is two
-- gammas joined at their principal ports with all four auxiliaries free.
type Spec = { { string } }

const function compile(spec: Spec): Net
	local net = newNet()
	local endpoints: { [string]: { Port } } = {}
	for _, cell in spec do
		local c = alloc(net, cell[1] :: Symbol)
		local ports = { principal(c), aux1(c), aux2(c) }
		for i = 2, #cell do
			local label = cell[i]
			local group = endpoints[label]
			if group then
				table.insert(group, ports[i - 1])
			else
				endpoints[label] = { ports[i - 1] }
			end
		end
	end
	for label, group in endpoints do
		if #group == 2 then
			link(net, group[1], group[2])
		elseif #group > 2 then
			error(`label "{label}" is used {#group} times`)
		end
	end
	return net
end

const function wellFormed(net: Net): boolean
	for p, q in net.Link do
		if q ~= 0 and net.Link[q] ~= p then
			return false
		end
	end
	return true
end

-- The cells that are still alive (release() keeps Tag around for slot reuse).
const function liveCells(net: Net): { Cell }
	local freed: { [Cell]: boolean } = {}
	for _, c in net.Free do
		freed[c] = true
	end
	local live = {}
	for c = 1, #net.Tag do
		if net.Tag[c] ~= nil and not freed[c] then
			table.insert(live, c)
		end
	end
	return live
end

-- Same net up to renaming of cells. Cell ids are recycled during reduction, so
-- two equal results usually have completely different ids.
const function isomorphic(a: Net, b: Net): boolean
	local left, right = liveCells(a), liveCells(b)
	if #left ~= #right then
		return false
	end

	local map: { [Cell]: Cell } = {}
	local taken: { [Cell]: boolean } = {}

	const function verify(): boolean
		for _, ca in left do
			local cb = map[ca]
			local pa, pb = (ca - 1) * STRIDE, (cb - 1) * STRIDE
			for slot = 1, STRIDE do
				local x, y = a.Link[pa + slot] or 0, b.Link[pb + slot] or 0
				if (x == 0) ~= (y == 0) then
					return false
				end
				if x == 0 then
					continue
				end
				if
					map[owner(x)] ~= owner(y)
					or (x - 1) % STRIDE ~= (y - 1) % STRIDE
				then
					return false
				end
			end
		end
		return true
	end

	const function search(i: number): boolean
		if i > #left then
			return verify()
		end
		local ca = left[i]
		for _, cb in right do
			if not taken[cb] and a.Tag[ca] == b.Tag[cb] then
				map[ca], taken[cb] = cb, true
				if search(i + 1) then
					return true
				end
				map[ca], taken[cb] = nil, nil
			end
		end
		return false
	end

	return search(1)
end

const function check(name: string, ok: boolean)
	print(if ok then `PASS {name}` else `FAIL {name}`)
end

-- tests -----------------------------------------------------------------------

type Test = {
	read name: string,
	read start: Spec,
	read expect: Spec?, -- nil means the reduction is expected not to finish
	read budget: number?,
}

local tests: { Test } = {
	{
		name = "epsilon-epsilon annihilates to nothing",
		start = { { EPSILON, "p" }, { EPSILON, "p" } },
		expect = {},
	},
	{
		name = "gamma-gamma exchanges its wires",
		start = {
			{ GAMMA, "p", "a", "b" },
			{ GAMMA, "p", "c", "d" },
			{ DELTA, "e", "a", "f" },
			{ DELTA, "g", "b", "h" },
			{ DELTA, "i", "c", "j" },
			{ DELTA, "k", "d", "l" },
		},
		expect = {
			{ DELTA, "e", "ad", "f" },
			{ DELTA, "g", "bc", "h" },
			{ DELTA, "i", "bc", "j" },
			{ DELTA, "k", "ad", "l" },
		},
	},
	{
		name = "delta-delta is straight",
		start = {
			{ DELTA, "p", "a", "b" },
			{ DELTA, "p", "c", "d" },
			{ GAMMA, "e", "a", "f" },
			{ GAMMA, "g", "b", "h" },
			{ GAMMA, "i", "c", "j" },
			{ GAMMA, "k", "d", "l" },
		},
		expect = {
			{ GAMMA, "e", "ac", "f" },
			{ GAMMA, "g", "bd", "h" },
			{ GAMMA, "i", "ac", "j" },
			{ GAMMA, "k", "bd", "l" },
		},
	},
	{
		name = "gamma-erase spawns one eraser per auxiliary",
		start = {
			{ GAMMA, "p", "A", "B" },
			{ DELTA, "u", "A", "v" },
			{ DELTA, "w", "B", "x" },
			{ EPSILON, "p" },
		},
		expect = {
			{ DELTA, "u", "m", "v" },
			{ DELTA, "w", "n", "x" },
			{ EPSILON, "m" },
			{ EPSILON, "n" },
		},
	},
	{
		name = "gamma meets delta in the commutation square",
		start = {
			{ GAMMA, "p", "a", "b" },
			{ DELTA, "p", "c", "d" },
		},
		expect = {
			{ DELTA, "p1", "m2", "m1" },
			{ DELTA, "p2", "m4", "m3" },
			{ GAMMA, "p3", "m1", "m3" },
			{ GAMMA, "p4", "m2", "m4" },
		},
	},
	{
		name = "a gamma erased on every port vanishes completely",
		start = {
			{ GAMMA, "p", "A", "B" },
			{ EPSILON, "p" },
			{ EPSILON, "A" },
			{ EPSILON, "B" },
		},
		expect = {},
	},
	{
		name = "delta(epsilon, x) = gamma(x, epsilon)",
		start = {
			{ DELTA, "p", "e", "x" },
			{ GAMMA, "p", "x", "f" },
			{ EPSILON, "e" },
			{ EPSILON, "f" },
		},
		expect = nil, -- does not terminate
		budget = 200,
	},
}

for _, test in tests do
	local net = compile(test.start)
	local finished = false
	for _ = 1, test.budget or 1000 do
		if not step(net) then
			finished = true
			break
		end
	end

	if test.expect then
		local ok = finished
			and wellFormed(net)
			and isomorphic(net, compile(test.expect))
		check(test.name, ok)
	else
		check(`{test.name} never finishes`, not finished and wellFormed(net))
	end
end
