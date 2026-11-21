--!strict
-- THE INTERACTION NET STRUCTURE
--
-- What a net is made of and how its ports are wired: the symbols, the arithmetic that turns a cell and a slot into a port, building and rewiring cells and wires, and the queries on a net.
-- The six interaction rules that reduce a net are in rules.luau, and the test for two nets being the same up to a renaming of cells is in canon.luau.
-- A net is built by hand here, or with builder.luau, and then reduced one step at a time until no redex is left, at which point the normal form is unique up to isomorphism, if there is one at all. Reduction does not always terminate, so a caller is expected to bound it; see harness.luau.
--
--   const Net = require "./net"
--   const Rules = require "./rules"
--
--   const net = Net.newNet()
--   local a = Net.alloc(net, Net.GAMMA)
--   local b = Net.alloc(net, Net.GAMMA)
--   Net.link(net, Net.principal(a), Net.principal(b))
--
--   while Rules.step(net) do
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

-- The port in a given slot of a cell: 1 is the principal port, 2 and 3 the auxiliaries.
const function port(c: Cell, slot: number): Port
	return (c - 1) * STRIDE + slot
end

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

-- How many ports a cell with this symbol has, principal included.
const function portCount(symbol: Symbol): number
	return
		if symbol == EPSILON then
			1
		else
			3
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

const function alloc(net: Net, symbol: Symbol): Cell
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

const function release(net: Net, c: Cell)
	const p = principal(c)
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

-- Redirect p's wire onto q, leaving p free. Used when a cell dissolves but its continuations must stay connected. q must be a fresh (unwired) port.
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

-- queries ------------------------------------------------------------------
const function wellFormed(net: Net): boolean
	for p, q in net.Link do
		if q ~= 0 and net.Link[q] ~= p then
			return false
		end
	end

	return true
end

-- How many cells are still alive. Every cell ever made keeps its slot in Tag, and a released one is on Free until it is reused, so this is a subtraction rather than a scan.
const function liveCount(net: Net): number
	return #net.Tag - #net.Free
end

-- The cells that are still alive (release() keeps Tag around for slot reuse).
const function liveCells(net: Net): { Cell }
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
		end
	end

	return live
end

return {
	GAMMA = GAMMA,
	DELTA = DELTA,
	EPSILON = EPSILON,
	STRIDE = STRIDE,
	port = port,
	portCount = portCount,
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
	wellFormed = wellFormed,
	liveCells = liveCells,
	liveCount = liveCount,
}
