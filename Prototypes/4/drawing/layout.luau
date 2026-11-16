--!strict
-- PLACING THE PARTS OF A NET ON THE GRID
--
-- Cells that share no wires are laid out on their own grids, then packed into rows so the whole drawing stays roughly square.
-- Each part keeps a one-slot halo, and neighbouring parts stay a fixed two-slot gap apart.

local G = require "./geometry"
local Net = require "../net"
local Place = require "./place"
local Types = require "../types"

type Cell = Types.Cell
type Net = Types.Net
type Vec = G.Vec
type Grid = G.Grid

-- Group cells into connected parts: two cells belong to the same part when a wire joins one of their ports. Different parts have no wires, cells or ports in common, so they can be laid out independently and then packed.
const function components(
	net: Net,
	cells: { Cell }
): { { Cell } }
	const parent: {
		[Cell]: Cell,
	} = {}

	for _, c in cells do
		parent[c] = c
	end

	const function find(
		c: Cell
	): Cell
		local root = c

		while parent[root] ~= root do
			root = parent[root]
		end

		while parent[c] ~= root do
			parent[c], c = root, parent[c]
		end

		return root
	end

	for _, c in cells do
		for slot = 1, Net.portCount(net.Tag[c]) do
			const q = net.Link[Net.port(c, slot)] or 0

			if q ~= 0 and Net.owner(q) ~= c then
				const a, b = find(c), find(Net.owner(q))

				if a ~= b then
					parent[a] = b
	end end end end

	const byRoot: {
		[Cell]: { Cell },
	} = {}
	const order: { Cell } = {}

	for _, c in cells do
		const root = find(c)
		local group = byRoot[root]

		if not group then
			group = {}
			byRoot[root] = group
			table.insert(order, root)
		end

		table.insert(group, c)
	end

	const parts: { { Cell } } = {}

	for _, root in order do
		table.insert(parts, byRoot[root])
	end

	return parts
end

type PartBox = {
	grid: {
		[Cell]: G.Grid,
	},
	minX: number,
	minY: number,
	w: number,
	h: number,
	margin: number,
}
-- Lay out every part on its own grid, then pack the parts into rows so the whole drawing stays roughly square. Each part keeps a one-slot halo, and neighbouring parts stay a fixed two-slot gap apart.
const PART_MARGIN = 1
const PART_GAP = 2

const function layout(
	net: Net,
	cells: { Cell }
): {
	[Cell]: G.Vec,
}
	if #cells == 0 then
		return {}
	end

	const parts = components(net, cells)

	const function pixel(
		g: {
			[Cell]: G.Grid,
		}
	): {
		[Cell]: G.Vec,
	}
		const pos: {
			[Cell]: G.Vec,
		} = {}

		for c, v in g do
			pos[c] = {
				x = v.x * G.PITCH,
				y = v.y * G.PITCH,
			}
		end

		return pos
	end

	if #parts == 1 then
		return pixel(Place.placePart(net, cells))
	end

	const boxes: { PartBox } = {}
	local area = 0
	local widest = 0

	for _, part in parts do
		const g = Place.placePart(net, part)
		local minX, minY = math.huge, math.huge
		local maxX, maxY = -math.huge, -math.huge

		for _, v in g do
			minX = math.min(minX, v.x)
			minY = math.min(minY, v.y)
			maxX = math.max(maxX, v.x)
			maxY = math.max(maxY, v.y)
		end

		const w = maxX - minX + 2 * PART_MARGIN
		const h = maxY - minY + 2 * PART_MARGIN
		area += w * h
		widest = math.max(widest, w)
		table.insert(
			boxes, {
				grid = g,
				minX = minX,
				minY = minY,
				w = w,
				h = h,
				margin = PART_MARGIN,
			}
		)
	end

	const target = math.max(widest, math.sqrt(area))
	const placed: {
		[Cell]: G.Grid,
	} = {}
	local x, y, rowH = 0, 0, 0

	for _, b in boxes do
		if x > 0 and x + b.w > target then
			x = 0
			y += rowH + PART_GAP
			rowH = 0
		end

		const ox = x + b.margin - b.minX
		const oy = y + b.margin - b.minY

		for c, v in b.grid do
			placed[c] = {
				x = v.x + ox,
				y = v.y + oy,
			}
		end

		x += b.w + PART_GAP
		rowH = math.max(rowH, b.h)
	end

	return pixel(placed)
end

return {
	layout = layout,
}
