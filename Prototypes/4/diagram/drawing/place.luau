--!strict
-- PLACING ONE CONNECTED PART
--
-- Puts every cell of one connected part on the integer grid. A spring layout suggests which way each wire should run, then a breadth-first walk places cells on the grid to match it.

local Canon = require "../../engine/canon"
local Net = require "../../engine/net"
local Types = require "../../engine/types"
local G = require "./geometry"
local Symmetry = require "./symmetry"

type Cell = Types.Cell
type Net = Types.Net
type Vec = G.Vec
type Grid = G.Grid

-- Fruchterman-Reingold on one part. The result is not drawn directly: it only suggests which way each wire should run, so that the grid placement below keeps wired cells on the side of each other that the springs prefer. It is deterministic (starts on a circle), so a given part always draws the same way.
const function guidePart(
	net: Net,
	cells: { Cell }
): {
	[Cell]: G.Vec,
}
	const n = #cells
	const pos: {
		[Cell]: G.Vec,
	} = {}

	if n == 1 then
		pos[cells[1]] = {
			x = 0,
			y = 0,
		}

		return pos
	end

	const W, H = 640, 640
	const k = math.min(96, 0.9 * math.sqrt(W * H / n))
	local temp = 72
	const radius = 34 * math.sqrt(n)

	for i, c in cells do
		const angle = 2 * math.pi * (i - 1) / n
		pos[c] = {
			x = radius * math.cos(angle),
			y = radius * math.sin(angle),
		}
	end

	const disp: {
		[Cell]: G.Vec,
	} = {}

	for _ = 1, 300 do
		for _, c in cells do
			disp[c] = {
				x = 0,
				y = 0,
			}
		end

		for i = 1, n do
			for j = i + 1, n do
				const a, b = cells[i], cells[j]
				local dx, dy = pos[a].x - pos[b].x, pos[a].y - pos[b].y
				local d = math.sqrt(dx * dx + dy * dy)

				if d < 0.01 then
					dx, dy, d = 0.01, 0, 0.01
				end

				const force = k * k / d
				const ux, uy = dx / d, dy / d
				disp[a].x += ux * force
				disp[a].y += uy * force
				disp[b].x -= ux * force
				disp[b].y -= uy * force
		end end

		for _, c in cells do
			for slot = 1, Net.portCount(net.Tag[c]) do
				const p = Net.port(c, slot)
				const q = net.Link[p] or 0

				if q ~= 0 and p < q then
					const a, b = Net.owner(p), Net.owner(q)

					if a ~= b then
						const dx, dy = pos[a].x - pos[b].x, pos[a].y - pos[b].y
						const d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
						const force = d * d / k
						const ux, uy = dx / d, dy / d
						disp[a].x -= ux * force
						disp[a].y -= uy * force
						disp[b].x += ux * force
						disp[b].y += uy * force
		end end end end

		for _, c in cells do
			const dx, dy = disp[c].x, disp[c].y
			const d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
			const step = math.min(d, temp)
			pos[c].x += dx / d * step
			pos[c].y += dy / d * step
			const pad = 60
			pos[c].x = math.max(-W / 2 + pad, math.min(W / 2 - pad, pos[c].x))
			pos[c].y = math.max(-H / 2 + pad, math.min(H / 2 - pad, pos[c].y))
		end

		temp *= 0.95
	end

	return pos
end

-- The nearest free grid slot to `origin`, searched outwards in rings. Only used when every immediate neighbour of a cell is already taken.
const function freeNear(
	origin: G.Grid,
	occ: {
		[string]: boolean,
	}
): G.Grid
	local r = 1

	while r < 128 do
		for dx = -r, r do
			for dy = -r, r do
				if math.abs(dx) + math.abs(dy) == r then
					const g = {
						x = origin.x + dx,
						y = origin.y + dy,
					}

					if not occ[G.key(g)] then
						return g
		end end end end

		r += 1
	end

	return {
		x = origin.x + 1,
		y = origin.y,
	}
end

-- Place one connected part on the integer grid. A breadth-first walk starts at a cell and puts every wired neighbour in a free slot beside the cell it grows from; the spring guide decides which side. Every choice of root, quarter-turn and reflection of the guide is tried and then folded onto nearby free slots.
-- The candidate with the most page-aligned symmetry wins, with the most compact and shortest-wired layout breaking ties, so equivalent branches spread out evenly instead of the whole part lurching to one side.
const function placePart(
	net: Net,
	cells: { Cell }
): {
	[Cell]: G.Grid,
}
	if #cells == 1 then
		return {
			[cells[1]] = {
				x = 0,
				y = 0,
			},
		}
	end

	const guide = guidePart(net, cells)
	const inPart: {
		[Cell]: boolean,
	} = {}

	for _, c in cells do
		inPart[c] = true
	end

	const function wiredNeighbours(
		c: Cell
	): { Cell }
		const list: { Cell } = {}

		for slot = 1, Net.portCount(net.Tag[c]) do
			const q = net.Link[Net.port(c, slot)] or 0

			if q ~= 0 and Net.owner(q) ~= c and inPart[Net.owner(q)] then
				table.insert(list, Net.owner(q))
		end end

		return list
	end

	const edges: { { Cell } } = {}

	for _, c in cells do
		for _, v in wiredNeighbours(c) do
			if c < v then
				table.insert(
					edges, {
						c,
						v,
					}
				)
	end end end

	const colors = Canon.refineKinds(net, cells)

	const function build(
		root: Cell,
		rot: number,
		mirror: boolean
	): {
		[Cell]: G.Grid,
	}
		const grid: {
			[Cell]: G.Grid,
		} = {}
		const occ: {
			[string]: boolean,
		} = {}
		grid[root] = {
			x = 0,
			y = 0,
		}
		occ[G.key(grid[root])] = true
		const queue: { Cell } = {
			root,
		}
		local head = 1

		-- Direction from u towards v, after the guide's rotation and reflection.
		const function lean(
			u: Cell,
			v: Cell
		): (number, number)
			local dxf, dyf = guide[v].x - guide[u].x, guide[v].y - guide[u].y

			if mirror then
				dxf = -dxf
			end

			for _ = 1, rot do
				dxf, dyf = -dyf, dxf
			end

			return dxf, dyf
		end

		const function freeAt(
			u: Cell
		): { G.Vec }
			const list: { G.Vec } = {}

			for _, d in G.DIRS do
				const g = {
					x = grid[u].x + d.x,
					y = grid[u].y + d.y,
				}

				if not occ[G.key(g)] then
					table.insert(list, d)
			end end

			return list
		end

		const function put(
			u: Cell,
			v: Cell,
			d: G.Vec
		)
			const g = {
				x = grid[u].x + d.x,
				y = grid[u].y + d.y,
			}
			grid[v] = g
			occ[G.key(g)] = true
			table.insert(queue, v)
		end

		-- Fall back to the free slot nearest the spring guide.
		const function greedy(
			u: Cell,
			v: Cell
		)
			local dxf, dyf = lean(u, v)
			local best: G.Grid? = nil
			local bestDot = -math.huge

			for _, d in G.DIRS do
				const g = {
					x = grid[u].x + d.x,
					y = grid[u].y + d.y,
				}

				if not occ[G.key(g)] then
					const dot = d.x * dxf + d.y * dyf

					if dot > bestDot then
						bestDot = dot
						best = g
			end end end

			const slot = best or freeNear(grid[u], occ)
			grid[v] = slot
			occ[G.key(slot)] = true
			table.insert(queue, v)
		end

		-- Lets two branches of u be recognised as a matching pair: same colour, and the same kind of port on u and on the partner.
		const function branchKey(
			u: Cell,
			slot: number,
			v: Cell
		): string
			const mine =
				if slot == 1 then
					"P"
				else
					"A"
			const q = net.Link[Net.port(u, slot)] or 0
			const theirs =
				if q ~= 0 and Net.isPrincipal(q) then
					"P"
				else
					"A"

			return `{mine}{theirs}{colors[v]}`
		end

		while head <= #queue do
			const u = queue[head]
			head += 1
			const pending: { {
				v: Cell,
				key: string,
			} } = {}

			for slot = 1, Net.portCount(net.Tag[u]) do
				const q = net.Link[Net.port(u, slot)] or 0
				const v =
					if q ~= 0 then
						Net.owner(q)
					else
						u

				if q ~= 0 and v ~= u and inPart[v] and not grid[v] then
					table.insert(
						pending, {
							v = v,
							key = branchKey(u, slot, v),
						}
					)
			end end

			const done: { boolean } = {}

			-- Equivalent branches go into opposite slots, so a pair of matching sub-trees mirrors each other on the page.
			for i = 1, #pending do
				if done[i] then
					continue
				end

				for j = i + 1, #pending do
					if done[j] or pending[i].key ~= pending[j].key then
						continue
					end

					local bestScore = -math.huge
					local first: G.Vec? = nil
					local second: G.Vec? = nil
					local firstCell: Cell? = nil
					local secondCell: Cell? = nil
					const free = freeAt(u)

					for _, da in free do
						for _, db in free do
							if da.x ~= -db.x or da.y ~= -db.y then
								continue
							end

							const dix, diy = lean(u, pending[i].v)
							const djx, djy = lean(u, pending[j].v)
							const straight = da.x * dix + da.y * diy + db.x * djx + db.y * djy
							const swapped = da.x * djx + da.y * djy + db.x * dix + db.y * diy
							const score = math.max(straight, swapped)
							local c1, c2 = pending[i].v, pending[j].v
							local g1, g2 = da, db

							if swapped > straight then
								c1, c2 = pending[j].v, pending[i].v
								g1, g2 = db, da
							end

							if score > bestScore then
								bestScore = score
								first, second = g1, g2
								firstCell, secondCell = c1, c2
					end end end

					if first and second and firstCell and secondCell then
						put(u, firstCell, first)
						put(u, secondCell, second)
						done[i], done[j] = true, true
			end end end

			for i = 1, #pending do
				if not done[i] then
					greedy(u, pending[i].v)
		end end end

		return grid
	end

	const function spanAndWires(
		grid: {
			[Cell]: G.Grid,
		}
	): (number, number)
		local minX, minY = math.huge, math.huge
		local maxX, maxY = -math.huge, -math.huge

		for _, v in grid do
			minX = math.min(minX, v.x)
			minY = math.min(minY, v.y)
			maxX = math.max(maxX, v.x)
			maxY = math.max(maxY, v.y)
		end

		local wires = 0

		for _, edge in edges do
			const a, b = grid[edge[1]], grid[edge[2]]
			wires += math.abs(a.x - b.x) + math.abs(a.y - b.y)
		end

		return math.max(maxX - minX, maxY - minY), wires
	end

	-- Nudge cells into nearby free slots while that shrinks the part's longest side. The move must be a strict improvement, so a clean chain is left as a straight run.
	const function compact(
		start: {
			[Cell]: G.Grid,
		}
	): {
		[Cell]: G.Grid,
	}
		const occ: {
			[string]: boolean,
		} = {}

		for _, v in start do
			occ[G.key(v)] = true
		end

		const function value(): number
			const span, wires = spanAndWires(start)

			return span * 1000 + wires
		end

		for _ = 1, 30 do
			local improved = false

			for _, c in cells do
				const home = start[c]
				local bestSlot = home
				local bestValue = value()

				for dx = -2, 2 do
					for dy = -2, 2 do
						if dx == 0 and dy == 0 then
							continue
						end

						const g = {
							x = home.x + dx,
							y = home.y + dy,
						}

						if occ[G.key(g)] then
							continue
						end

						start[c] = g
						const v = value()

						if v < bestValue - 1e-9 then
							bestValue = v
							bestSlot = g
						end

						start[c] = home
				end end

				if bestSlot ~= home then
					occ[G.key(home)] = false
					start[c] = bestSlot
					occ[G.key(bestSlot)] = true
					improved = true
			end end

			if not improved then
				break
		end end

		return start
	end

	-- Try every root, quarter-turn and reflection. Keep the candidate with the most page-aligned symmetry, and only accept a folded version when folding does not cost it any symmetry, so symmetric parts stay symmetric.
	local best: {
		[Cell]: G.Grid,
	}? = nil
	local bestSym = -1
	local bestSpan, bestWires = math.huge, math.huge

	for _, root in cells do
		for rot = 0, 3 do
			for _, mirror in {
				false,
				true,
			} do
				const straight = build(root, rot, mirror)
				const straightSym = Symmetry.symmetryCount(net, straight, cells)
				const folded = compact(build(root, rot, mirror))
				local sym = Symmetry.symmetryCount(net, folded, cells)
				local candidate = folded

				if sym < straightSym then
					candidate = straight
					sym = straightSym
				end

				const span, wires = spanAndWires(candidate)

				if sym > bestSym or sym == bestSym and (span < bestSpan or span == bestSpan and wires < bestWires) then
					bestSym, bestSpan, bestWires = sym, span, wires
					best = candidate
	end end end end

	return best :: {
		[Cell]: G.Grid,
	}
end

return {
	placePart = placePart,
}
