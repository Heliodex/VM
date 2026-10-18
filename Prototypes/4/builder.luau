--!strict
-- A COMPOSITIONAL INTERFACE FOR BUILDING NETS
--
-- net.luau can rewire ports, but building a net from nothing with it means
-- tracking cell ids and port numbers by hand. A builder resolves a port once,
-- when the cell that owns it is made, and hands back a handle for it; wires
-- then join handles rather than integers, so a net is written in the order it
-- reads instead of in the order its labels happen to fall.
--
--   local B = require "./builder"
--
--   local b = B.new()
--   local g = b:gamma()
--   local d = b:delta()
--   b:meet(g, d)
--   b:wire(g.aux1, d.aux2)
--   local net = b:finish()
--
-- A port that is never wired stays free. That is how a gadget hands its inputs
-- and outputs to whatever net it gets plugged into, and how a test net says
-- where its answer is expected to appear.
--
-- There is deliberately nothing here for arithmetic, lists or control flow.
-- Anything a program computes has to come out of the six interaction rules,
-- not out of this file.

local Net = require "./net"
local Types = require "./types"

type Net = Types.Net
type Symbol = Types.Symbol
type Cell = Types.Cell
type Port = Types.Port
-- One cell, with its ports already resolved. An eraser has no auxiliaries, so
-- its aux1 and aux2 are nil rather than ports that do not exist.
export type Handle = {
	read cell: Cell,
	read symbol: Symbol,
	read principal: Port,
	read aux1: Port?,
	read aux2: Port?,
}
export type Builder = {
	net: Net,
}
local Builder = {}
Builder.__index = Builder

function Builder.new(): Builder
	return setmetatable(
		{
			net = Net.newNet(),
		} :: Builder, Builder
	)
end

local function make(
	self: Builder,
	symbol: Symbol
): Handle
	local c = Net.alloc(self.net, symbol)
	local binary = symbol ~= Net.EPSILON

	return {
		cell = c,
		symbol = symbol,
		principal = Net.principal(c),
		aux1 = if binary then
			Net.aux1(c)
		else
			nil,
		aux2 = if binary then
			Net.aux2(c)
		else
			nil,
	}
end

function Builder.gamma(
	self: Builder
): Handle
	return make(self, Net.GAMMA)
end

function Builder.delta(
	self: Builder
): Handle
	return make(self, Net.DELTA)
end

function Builder.epsilon(
	self: Builder
): Handle
	return make(self, Net.EPSILON)
end

-- Join two principal ports. This is the only wire that can start a net
-- reducing: everything else is a continuation waiting on one.
function Builder.meet(
	self: Builder,
	a: Handle,
	b: Handle
)
	Net.link(self.net, a.principal, b.principal)
end

-- Join any two ports. An eraser has no auxiliaries, so wiring to one is
-- rejected here rather than silently producing a net no rule can match.
function Builder.wire(
	self: Builder,
	a: Port?,
	b: Port?
)
	if not a or not b then
		error "cannot wire to a port that does not exist"
	end

	Net.link(self.net, a, b)
end

-- The net as it stands. A builder is finished with once: cells made after
-- this point belong to a net nothing else refers to.
function Builder.finish(
	self: Builder
): Net
	return self.net
end

return Builder
