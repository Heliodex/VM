--!strict
-- PAGE-ALIGNED SYMMETRY OF A PLACED PART
--
-- How many of the page's own axes a placement is symmetric about, so that the placer can prefer a drawing that lines up with the page.

local Net = require "../../engine/net"
local Types = require "../../engine/types"
local G = require "./geometry"

type Cell = Types.Cell
type Net = Types.Net
type Grid = G.Grid

-- A port's signature: whether it is principal or auxiliary, whether it is free, and, when wired, the kind of port it meets and which cell owns that port.
-- `pi`, when given, maps the owning cell of a wired partner first, so a candidate symmetry can be checked against the wiring.
const function portSignature(
	net: Net,
	c: Cell,
	slot: number,
	pi: {
		[Cell]: Cell,
	}?
): string
	const mine =
		if slot == 1 then
			"P"
		else
			"A"
	const q = net.Link[Net.port(c, slot)] or 0

	if q == 0 then
		return `{mine}:free`
	end

	const theirs =
		if Net.isPrincipal(q) then
			"P"
		else
			"A"
	const ownerCell = Net.owner(q)
	const image =
		if pi then
			pi[ownerCell]
		else
			ownerCell

	return `{mine}:{theirs}:{image}`
end

-- How many page-aligned symmetries a placement has: a half-turn and reflections in a vertical or horizontal line that send every cell to a cell of the same symbol and preserve the wiring. Diagonal mirrors are left out on purpose, so a drawing that only lines up on the slant is not preferred over one that lines up with the page.
const function symmetryCount(
	net: Net,
	grid: {
		[Cell]: G.Grid,
	},
	cells: { Cell }
): number
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge

	for _, v in grid do
		minX = math.min(minX, v.x)
		minY = math.min(minY, v.y)
		maxX = math.max(maxX, v.x)
		maxY = math.max(maxY, v.y)
	end

	const cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
	const at: {
		[string]: Cell,
	} = {}

	for _, c in cells do
		at[G.key(grid[c])] = c
	end

	-- Turn an isometry into a permutation of the cells, or nil when it does not map the placement onto itself.
	const function permutation(fn: (G.Grid) -> G.Grid): {
		[Cell]: Cell,
	}?
		const pi: {
			[Cell]: Cell,
		} = {}
		const used: {
			[Cell]: boolean,
		} = {}

		for _, c in cells do
			const d = at[G.key(fn(grid[c]))]

			if not d or used[d] then
				return nil
			end

			used[d] = true
			pi[c] = d
		end

		return pi
	end

	const function preserves(
		pi: {
			[Cell]: Cell,
		}
	): boolean
		local moved = false

		for _, c in cells do
			if pi[c] ~= c then
				moved = true
				break
			end
		end

		if not moved then
			return false
		end

		for _, c in cells do
			const a: { string } = {}
			const b: { string } = {}

			for slot = 1, Net.portCount(net.Tag[c]) do
				table.insert(a, portSignature(net, c, slot, pi))
			end

			for slot = 1, Net.portCount(net.Tag[pi[c]]) do
				table.insert(b, portSignature(net, pi[c], slot, nil))
			end

			table.sort(a)
			table.sort(b)

			if table.concat(a, "|") ~= table.concat(b, "|") then
				return false
			end
		end

		return true
	end

	const function check(
		pi: {
			[Cell]: Cell,
		}?
	): number
		if pi and preserves(pi) then
			return 1
		end

		return 0
	end

	const halfTurn = permutation(function(g: G.Grid): G.Grid
		return {
			x = 2 * cx - g.x,
			y = 2 * cy - g.y,
		}
	end)
	const vertical = permutation(function(g: G.Grid): G.Grid
		return {
			x = 2 * cx - g.x,
			y = g.y,
		}
	end)
	const horizontal = permutation(function(g: G.Grid): G.Grid
		return {
			x = g.x,
			y = 2 * cy - g.y,
		}
	end)

	return check(halfTurn) + check(vertical) + check(horizontal)
end

return {
	symmetryCount = symmetryCount,
}
