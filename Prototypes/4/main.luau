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
	-- 1. pick a slot: reuse a freed cell id, else it's empty so take the first one
	local c = table.remove(net.Free) or 1

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
