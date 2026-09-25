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

local function principal(a: Cell): Port
	return (a - 1) * STRIDE + 1
end
local function aux1(a: Cell): Port
	return (a - 1) * STRIDE + 2
end
local function aux2(a: Cell): Port
	return aux1(a) + 1
end
local function owner(p: Port): Cell
	return (p - 1) // STRIDE + 1
end
local function isPrincipal(p: Port): boolean
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

local function newNet(): Net
	return {
		Tag = {},
		Link = {},
		Active = {},
		Free = {},
	}
end

local function alloc(net: Net, symbol: Symbol): Cell
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

local function release(net: Net, c: Cell)
	local p = principal(c)
	net.Link[p], net.Link[p + 1], net.Link[p + 2] = 0, 0, 0
	table.insert(net.Free, c)
end

-- Wire two ports. 0 is safe as the "free" sentinel because port ids start at 1.
local function link(net: Net, p: Port, q: Port)
	net.Link[p], net.Link[q] = q, p
	if isPrincipal(p) and isPrincipal(q) then
		table.insert(net.Active, p)
	end
end

local function splice(net: Net, p: Port, q: Port)
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
local function move(net: Net, p: Port, q: Port)
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
local function commute(net: Net, a: Cell, b: Cell)
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
local function erase(net: Net, a: Cell, b: Cell)
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
local function step(net: Net): boolean
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

local function reduce(net: Net)
	while step(net) do
	end
end

-- self-checks ---------------------------------------------------------------

local function wellFormed(net: Net): boolean
	for p, q in net.Link do
		if q ~= 0 and net.Link[q] ~= p then
			return false
		end
	end
	return true
end

local function check(name: string, ok: boolean)
	print(if ok then `PASS {name}` else `FAIL {name}`)
end

-- annihilation: gamma-gamma swaps auxiliary ports
do
	local net = newNet()
	local g1, g2 = alloc(net, GAMMA), alloc(net, GAMMA)
	local c1, c2, c3, c4 =
		alloc(net, DELTA),
		alloc(net, DELTA),
		alloc(net, DELTA),
		alloc(net, DELTA)
	link(net, principal(g1), principal(g2))
	link(net, aux1(g1), aux1(c1))
	link(net, aux2(g1), aux1(c2))
	link(net, aux1(g2), aux1(c3))
	link(net, aux2(g2), aux1(c4))
	reduce(net)
	check(
		"gamma-gamma swaps",
		net.Link[aux1(c1)] == aux1(c4) and net.Link[aux1(c2)] == aux1(c3)
	)
end

-- annihilation: delta-delta is straight
do
	local net = newNet()
	local d1, d2 = alloc(net, DELTA), alloc(net, DELTA)
	local c1, c2, c3, c4 =
		alloc(net, GAMMA),
		alloc(net, GAMMA),
		alloc(net, GAMMA),
		alloc(net, GAMMA)
	link(net, principal(d1), principal(d2))
	link(net, aux1(d1), aux1(c1))
	link(net, aux2(d1), aux1(c2))
	link(net, aux1(d2), aux1(c3))
	link(net, aux2(d2), aux1(c4))
	reduce(net)
	check(
		"delta-delta straight",
		net.Link[aux1(c1)] == aux1(c3) and net.Link[aux1(c2)] == aux1(c4)
	)
end

-- erasing must not depend on which principal port was noticed first
do
	local net = newNet()
	local g = alloc(net, GAMMA)
	local c = alloc(net, DELTA)
	link(net, aux1(g), aux1(c)) -- a wired continuation on the binary cell
	local e = alloc(net, EPSILON)
	link(net, principal(e), principal(g)) -- link() keeps its first argument
	reduce(net)

	local successor = net.Link[aux1(c)]
	check("erase is order-insensitive", wellFormed(net))
	check(
		"continuation rerouted to an eraser",
		successor ~= 0 and net.Tag[owner(successor)] == EPSILON
	)
end

-- the non-terminating net from the interaction calculus:
--   delta(epsilon, x) = gamma(x, epsilon)
-- it reduces forever, never reaching a normal form.
do
	local net = newNet()
	local d, g = alloc(net, DELTA), alloc(net, GAMMA)
	local e1, e2 = alloc(net, EPSILON), alloc(net, EPSILON)
	link(net, aux1(d), principal(e1))
	link(net, aux2(d), aux1(g))
	link(net, aux2(g), principal(e2))
	link(net, principal(d), principal(g))

	local steps = 0
	for _ = 1, 400 do
		if not step(net) then
			break
		end
		steps += 1
	end
	check(
		"non-terminating net keeps reducing",
		steps == 400 and wellFormed(net)
	)
end
