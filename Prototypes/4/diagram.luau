--!strict
-- SVG rendering of an interaction-combinator net, in the style of Lafont's
-- paper: gamma/delta cells are triangles whose tip is the principal port;
-- epsilon cells are circles; wires join ports; free ports are short dangling
-- stubs.
--
-- The drawing is deliberately regular. Cells sit on a square grid at a fixed
-- pitch, so neighbours are evenly spaced and never crowded; a branch is folded
-- into a compact block rather than trailing off into a long line. Each cell is
-- turned in quarter turns only, so its ports always point along the grid axes.
-- A wire leaves a port along the port's outward normal and curves to its
-- partner, and every cell chooses the quarter turn that keeps its wires
-- straightest. Cells joined at their principal ports (an active pair) face each
-- other, so that wire is a straight step between the two tips. Parts of a net
-- that share no wires are laid out on their own grids and packed a fixed
-- distance apart.
--
--   const toSvg = require("./diagram")
--   print(toSvg(net))
--
-- `toSvg` only reads Net.Tag / Net.Link / Net.Free.

const Types = require "./types"

type Cell = Types.Cell
type Port = Types.Port
type Symbol = Types.Symbol
type Net = Types.Net
type Vec = { x: number, y: number }

const STRIDE = 3

const function owner(p: Port): Cell
	return (p - 1) // STRIDE + 1
end
const function portOf(c: Cell, slot: number): Port
	return (c - 1) * STRIDE + slot
end
const function arity(symbol: Symbol): number
	return if symbol == "Epsilon" then 0 else 2
end
const function isPrincipalPort(p: Port): boolean
	return (p - 1) % STRIDE == 0
end
const function liveCells(net: Net): { Cell }
	const freed: { [Cell]: boolean } = {}
	for _, c in net.Free do
		freed[c] = true
	end
	const live: { Cell } = {}
	for c = 1, #net.Tag do
		if not freed[c] then
			table.insert(live, c)
		end
	end
	return live
end

-- geometry --------------------------------------------------------------------

const PITCH = 100 -- distance between neighbouring grid slots, in pixels
const TIP_LEN = 19 -- centre -> principal tip
const BASE_LEN = 13 -- centre -> base edge
const HALF_WIDTH = 15 -- half the base edge length
const CIRCLE_RADIUS = 13 -- epsilon radius
const FREE_LEN = 15 -- length of a free-port stub
const STUB_RADIUS = 3.5
const LOOP_LEN = 22
const MARGIN = 24
const ORIENT_ITERS = 6
const WIRE_BULGE = 0.5 -- fraction of the gap a wire uses to leave its port
const WIRE_BULGE_MAX = 48

-- Quarter-turn directions, in a fixed order so a net always draws the same way.
const DIRS: { Vec } = {
	{ x = 1, y = 0 },
	{ x = 0, y = 1 },
	{ x = -1, y = 0 },
	{ x = 0, y = -1 },
}

const function fmt(v: number): string
	return string.format("%.1f", v)
end

const function colorOf(symbol: Symbol): (string, string, string)
	if symbol == "Gamma" then
		return "#c8e6c9", "#2e7d32", "#1b5e20"
	elseif symbol == "Delta" then
		return "#bbdefb", "#1565c0", "#0d47a1"
	else
		return "#f8bbd0", "#c2185b", "#880e4f"
	end
end

const function labelOf(symbol: Symbol): string
	if symbol == "Gamma" then
		return "γ"
	elseif symbol == "Delta" then
		return "δ"
	else
		return "ε"
	end
end

-- Unit vector, falling back to (fx, fy) when the input is degenerate.
const function unit(
	x: number,
	y: number,
	fx: number,
	fy: number
): (number, number)
	const d = math.sqrt(x * x + y * y)
	if d < 0.01 then
		return fx, fy
	end
	return x / d, y / d
end

const function place(a: Vec, b: Vec, t: number): Vec
	return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t }
end

-- The direction (one of the four quarter turns) that points most nearly from
-- `a` towards `b`.
const function dirToward(a: Vec, b: Vec): number
	local best, bestDot = 0, -math.huge
	for i, d in DIRS do
		const dot = (b.x - a.x) * d.x + (b.y - a.y) * d.y
		if dot > bestDot then
			bestDot = dot
			best = i - 1
		end
	end
	return best
end

-- The position of a port, for a cell centred at `center` and turned to face `d`.
const function anchorOf(center: Vec, d: Vec, symbol: Symbol, slot: number): Vec
	if symbol == "Epsilon" then
		return {
			x = center.x + d.x * CIRCLE_RADIUS,
			y = center.y + d.y * CIRCLE_RADIUS,
		}
	end
	if slot == 1 then
		return { x = center.x + d.x * TIP_LEN, y = center.y + d.y * TIP_LEN }
	end
	const n = { x = -d.y, y = d.x }
	const a = {
		x = center.x - d.x * BASE_LEN + n.x * HALF_WIDTH,
		y = center.y - d.y * BASE_LEN + n.y * HALF_WIDTH,
	}
	const b = {
		x = center.x - d.x * BASE_LEN - n.x * HALF_WIDTH,
		y = center.y - d.y * BASE_LEN - n.y * HALF_WIDTH,
	}
	return place(a, b, if slot == 2 then 1 / 3 else 2 / 3)
end

-- The outward normal of a port: principal points along the tip, auxiliary ports
-- point back out of the base.
const function normalOf(d: Vec, slot: number): Vec
	if slot == 1 then
		return d
	end
	return { x = -d.x, y = -d.y }
end

-- layout ----------------------------------------------------------------------

-- Group cells into connected parts: two cells belong to the same part when a
-- wire joins one of their ports. Different parts have no wires, cells or ports
-- in common, so they can be laid out independently and then packed.
const function components(net: Net, cells: { Cell }): { { Cell } }
	const parent: { [Cell]: Cell } = {}
	for _, c in cells do
		parent[c] = c
	end

	const function find(c: Cell): Cell
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
		for slot = 1, arity(net.Tag[c]) + 1 do
			const q = net.Link[portOf(c, slot)] or 0
			if q ~= 0 and owner(q) ~= c then
				const a, b = find(c), find(owner(q))
				if a ~= b then
					parent[a] = b
				end
			end
		end
	end

	const byRoot: { [Cell]: { Cell } } = {}
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

-- Fruchterman-Reingold on one part. The result is not drawn directly: it only
-- suggests which way each wire should run, so that the grid placement below
-- keeps wired cells on the side of each other that the springs prefer. It is
-- deterministic (starts on a circle), so a given part always draws the same way.
const function guidePart(net: Net, cells: { Cell }): { [Cell]: Vec }
	const n = #cells
	const pos: { [Cell]: Vec } = {}
	if n == 1 then
		pos[cells[1]] = { x = 0, y = 0 }
		return pos
	end

	const W, H = 640, 640
	const k = math.min(96, 0.9 * math.sqrt((W * H) / n))
	local temp = 72
	const radius = 34 * math.sqrt(n)
	for i, c in cells do
		const angle = 2 * math.pi * (i - 1) / n
		pos[c] = { x = radius * math.cos(angle), y = radius * math.sin(angle) }
	end

	const disp: { [Cell]: Vec } = {}
	for _ = 1, 300 do
		for _, c in cells do
			disp[c] = { x = 0, y = 0 }
		end

		for i = 1, n do
			for j = i + 1, n do
				const a, b = cells[i], cells[j]
				local dx, dy = pos[a].x - pos[b].x, pos[a].y - pos[b].y
				local d = math.sqrt(dx * dx + dy * dy)
				if d < 0.01 then
					dx, dy, d = 0.01, 0, 0.01
				end
				const force = (k * k) / d
				const ux, uy = dx / d, dy / d
				disp[a].x += ux * force
				disp[a].y += uy * force
				disp[b].x -= ux * force
				disp[b].y -= uy * force
			end
		end

		for _, c in cells do
			for slot = 1, arity(net.Tag[c]) + 1 do
				const p = portOf(c, slot)
				const q = net.Link[p] or 0
				if q ~= 0 and p < q then
					const a, b = owner(p), owner(q)
					if a ~= b then
						const dx, dy = pos[a].x - pos[b].x, pos[a].y - pos[b].y
						const d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
						const force = (d * d) / k
						const ux, uy = dx / d, dy / d
						disp[a].x -= ux * force
						disp[a].y -= uy * force
						disp[b].x += ux * force
						disp[b].y += uy * force
					end
				end
			end
		end

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

type Grid = { x: number, y: number }

const function key(g: Grid): string
	return `{g.x},{g.y}`
end

-- The nearest free grid slot to `origin`, searched outwards in rings. Only used
-- when every immediate neighbour of a cell is already taken.
const function freeNear(origin: Grid, occ: { [string]: boolean }): Grid
	local r = 1
	while r < 128 do
		for dx = -r, r do
			for dy = -r, r do
				if math.abs(dx) + math.abs(dy) == r then
					const g = { x = origin.x + dx, y = origin.y + dy }
					if not occ[key(g)] then
						return g
					end
				end
			end
		end
		r += 1
	end
	return { x = origin.x + 1, y = origin.y }
end

-- Place one connected part on the integer grid. A breadth-first walk starts at
-- an arbitrary cell and puts every wired neighbour in a free slot beside the
-- cell it grows from; the spring guide decides which side. The guide is tried
-- in each of the four quarter-turn rotations, and the placement with the most
-- compact bounding box (shortest wires breaking the tie) is kept, so a branch
-- whose springs point straight up and down is laid out as an L-shape instead
-- of trailing off into a long line.
const function placePart(net: Net, cells: { Cell }): { [Cell]: Grid }
	if #cells == 1 then
		return { [cells[1]] = { x = 0, y = 0 } }
	end

	const guide = guidePart(net, cells)
	const inPart: { [Cell]: boolean } = {}
	for _, c in cells do
		inPart[c] = true
	end

	const function wiredNeighbours(c: Cell): { Cell }
		const list: { Cell } = {}
		for slot = 1, arity(net.Tag[c]) + 1 do
			const q = net.Link[portOf(c, slot)] or 0
			if q ~= 0 and owner(q) ~= c and inPart[owner(q)] then
				table.insert(list, owner(q))
			end
		end
		return list
	end

	const edges: { { Cell } } = {}
	for _, c in cells do
		for _, v in wiredNeighbours(c) do
			if c < v then
				table.insert(edges, { c, v })
			end
		end
	end

	const function build(rot: number): { [Cell]: Grid }
		const grid: { [Cell]: Grid } = {}
		const occ: { [string]: boolean } = {}
		const root = cells[1]
		grid[root] = { x = 0, y = 0 }
		occ[key(grid[root])] = true
		const queue: { Cell } = { root }
		local head = 1
		while head <= #queue do
			const u = queue[head]
			head += 1
			for _, v in wiredNeighbours(u) do
				if grid[v] then
					continue
				end
				local dxf, dyf =
					guide[v].x - guide[u].x, guide[v].y - guide[u].y
				for _ = 1, rot do
					dxf, dyf = -dyf, dxf
				end
				local best: Grid? = nil
				local bestDot = -math.huge
				for _, d in DIRS do
					const g = { x = grid[u].x + d.x, y = grid[u].y + d.y }
					if not occ[key(g)] then
						const dot = d.x * dxf + d.y * dyf
						if dot > bestDot then
							bestDot = dot
							best = g
						end
					end
				end
				const slot = best or freeNear(grid[u], occ)
				grid[v] = slot
				occ[key(slot)] = true
				table.insert(queue, v)
			end
		end
		return grid
	end

	const function score(grid: { [Cell]: Grid }): number
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
		return math.max(maxX - minX, maxY - minY) * 1000 + wires
	end

	local best = build(0)
	local bestScore = score(best)
	for rot = 1, 3 do
		const candidate = build(rot)
		const s = score(candidate)
		if s < bestScore - 1e-9 then
			bestScore = s
			best = candidate
		end
	end

	-- Nudge cells into nearby free slots while that shrinks the part's longest
	-- side, so a star laid out as a line folds into an L. The move must be a
	-- strict improvement, so a clean chain is left as a straight run.
	const occ: { [string]: boolean } = {}
	for _, v in best do
		occ[key(v)] = true
	end

	const function compactScore(): number
		local minX, minY = math.huge, math.huge
		local maxX, maxY = -math.huge, -math.huge
		for _, v in best do
			minX = math.min(minX, v.x)
			minY = math.min(minY, v.y)
			maxX = math.max(maxX, v.x)
			maxY = math.max(maxY, v.y)
		end
		local wires = 0
		for _, edge in edges do
			const a, b = best[edge[1]], best[edge[2]]
			wires += math.abs(a.x - b.x) + math.abs(a.y - b.y)
		end
		return math.max(maxX - minX, maxY - minY) * 1000 + wires
	end

	for _ = 1, 30 do
		local improved = false
		for _, c in cells do
			const home = best[c]
			local bestSlot = home
			local bestValue = compactScore()
			for dx = -2, 2 do
				for dy = -2, 2 do
					if dx == 0 and dy == 0 then
						continue
					end
					const g = { x = home.x + dx, y = home.y + dy }
					if occ[key(g)] then
						continue
					end
					best[c] = g
					const value = compactScore()
					if value < bestValue - 1e-9 then
						bestValue = value
						bestSlot = g
					end
					best[c] = home
				end
			end
			if bestSlot ~= home then
				occ[key(home)] = false
				best[c] = bestSlot
				occ[key(bestSlot)] = true
				improved = true
			end
		end
		if not improved then
			break
		end
	end
	return best
end

type PartBox = {
	grid: { [Cell]: Grid },
	minX: number,
	minY: number,
	w: number,
	h: number,
	margin: number,
}

-- Lay out every part on its own grid, then pack the parts into rows so the
-- whole drawing stays roughly square. Each part keeps a one-slot halo, and
-- neighbouring parts stay a fixed two-slot gap apart.
const PART_MARGIN = 1
const PART_GAP = 2
const function layout(net: Net, cells: { Cell }): { [Cell]: Vec }
	if #cells == 0 then
		return {}
	end
	const parts = components(net, cells)

	const pixel = function(g: { [Cell]: Grid }): { [Cell]: Vec }
		const pos: { [Cell]: Vec } = {}
		for c, v in g do
			pos[c] = { x = v.x * PITCH, y = v.y * PITCH }
		end
		return pos
	end

	if #parts == 1 then
		return pixel(placePart(net, cells))
	end

	const boxes: { PartBox } = {}
	local area = 0
	local widest = 0
	for _, part in parts do
		const g = placePart(net, part)
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
		table.insert(boxes, {
			grid = g,
			minX = minX,
			minY = minY,
			w = w,
			h = h,
			margin = PART_MARGIN,
		})
	end

	const target = math.max(widest, math.sqrt(area))
	const placed: { [Cell]: Grid } = {}
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
			placed[c] = { x = v.x + ox, y = v.y + oy }
		end
		x += b.w + PART_GAP
		rowH = math.max(rowH, b.h)
	end
	return pixel(placed)
end

-- render ----------------------------------------------------------------------

const function toSvg(net: Net): string
	const cells = liveCells(net)
	const pos = layout(net, cells)

	const centroid: Vec = { x = 0, y = 0 }
	for _, c in cells do
		centroid.x += pos[c].x
		centroid.y += pos[c].y
	end
	if #cells > 0 then
		centroid.x /= #cells
		centroid.y /= #cells
	end

	-- Cells whose principal port is wired to another cell's principal port form
	-- an active pair. Their two tips are forced to face each other, so that wire
	-- is a straight step between the tips. Every other cell is free to turn to
	-- whichever quarter turn best serves its wires.
	const ppPartner: { [Cell]: Cell } = {}
	const paired: { [Cell]: boolean } = {}
	for _, c in cells do
		const q = net.Link[portOf(c, 1)] or 0
		if q ~= 0 and owner(q) ~= c and isPrincipalPort(q) then
			ppPartner[c] = owner(q)
			paired[c] = true
		end
	end

	const ori: { [Cell]: number } = {}
	for _, c in cells do
		if paired[c] then
			ori[c] = dirToward(pos[c], pos[ppPartner[c]])
		else
			const q = net.Link[portOf(c, 1)] or 0
			if q ~= 0 and owner(q) ~= c then
				ori[c] = dirToward(pos[c], pos[owner(q)])
			else
				ori[c] = dirToward(pos[c], centroid)
			end
		end
	end

	local point: { [Port]: Vec } = {} -- where a wire meets the cell
	local out: { [Port]: Vec } = {} -- outward normal: wires leave along this
	local tip: { [Cell]: Vec } = {}
	local e1: { [Cell]: Vec } = {}
	local e2: { [Cell]: Vec } = {}
	local hub: { [Cell]: Vec } = {}

	const function computePorts()
		point, out, tip, e1, e2, hub = {}, {}, {}, {}, {}, {}
		for _, c in cells do
			const center = pos[c]
			const d = DIRS[ori[c] + 1]
			if net.Tag[c] == "Epsilon" then
				hub[c] = center
				point[portOf(c, 1)] = anchorOf(center, d, net.Tag[c], 1)
				out[portOf(c, 1)] = d
			else
				const n = { x = -d.y, y = d.x }
				tip[c] = {
					x = center.x + d.x * TIP_LEN,
					y = center.y + d.y * TIP_LEN,
				}
				e1[c] = {
					x = center.x - d.x * BASE_LEN + n.x * HALF_WIDTH,
					y = center.y - d.y * BASE_LEN + n.y * HALF_WIDTH,
				}
				e2[c] = {
					x = center.x - d.x * BASE_LEN - n.x * HALF_WIDTH,
					y = center.y - d.y * BASE_LEN - n.y * HALF_WIDTH,
				}
				point[portOf(c, 1)] = tip[c]
				out[portOf(c, 1)] = d
				-- auxiliary ports sit on the base edge, opposite the tip
				point[portOf(c, 2)] = place(e1[c], e2[c], 1 / 3)
				point[portOf(c, 3)] = place(e1[c], e2[c], 2 / 3)
				out[portOf(c, 2)] = { x = -d.x, y = -d.y }
				out[portOf(c, 3)] = { x = -d.x, y = -d.y }
			end
		end
	end

	-- Cost of turning a cell to face `idx`: how far each of its wired ports has
	-- to swing from its outward normal to point at the partner. A wire is drawn
	-- leaving along that normal, so a smaller cost means a straighter wire. A
	-- principal-to-principal wire is weighted up, so an active pair stays facing
	-- each other even if an auxiliary wire would prefer otherwise.
	const function orientationCost(c: Cell, idx: number): number
		const d = DIRS[idx + 1]
		local total = 0
		for slot = 1, arity(net.Tag[c]) + 1 do
			const p = portOf(c, slot)
			const q = net.Link[p] or 0
			if q == 0 or owner(q) == c then
				continue
			end
			const A = anchorOf(pos[c], d, net.Tag[c], slot)
			const B = point[q]
			const n = normalOf(d, slot)
			const dx, dy = unit(B.x - A.x, B.y - A.y, n.x, n.y)
			const weight = if slot == 1 and isPrincipalPort(q) then 3 else 1
			total += weight * (1 - (n.x * dx + n.y * dy))
		end
		return total
	end

	-- Swing each free cell through the four quarter turns and keep the cheapest.
	-- Ties keep the current direction, which keeps the result deterministic and
	-- stops it oscillating.
	const function chooseOrientation(c: Cell)
		local best = orientationCost(c, ori[c])
		local bestIdx = ori[c]
		for idx = 0, 3 do
			const cost = orientationCost(c, idx)
			if cost < best - 1e-9 then
				best = cost
				bestIdx = idx
			end
		end
		ori[c] = bestIdx
	end

	for _ = 1, ORIENT_ITERS do
		computePorts()
		for _, c in cells do
			if not paired[c] then
				chooseOrientation(c)
				computePorts()
			end
		end
	end
	computePorts()

	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	const function include(v: Vec)
		minX = math.min(minX, v.x)
		minY = math.min(minY, v.y)
		maxX = math.max(maxX, v.x)
		maxY = math.max(maxY, v.y)
	end
	for _, c in cells do
		if net.Tag[c] == "Epsilon" then
			const center = hub[c]
			include {
				x = center.x - CIRCLE_RADIUS - 2,
				y = center.y - CIRCLE_RADIUS - 2,
			}
			include {
				x = center.x + CIRCLE_RADIUS + 2,
				y = center.y + CIRCLE_RADIUS + 2,
			}
		else
			include(tip[c])
			include(e1[c])
			include(e2[c])
		end
	end

	const wireStyle =
		'fill="none" stroke="#78909c" stroke-width="1.6" stroke-linecap="round"'
	const stubStyle =
		'fill="none" stroke="#90a4ae" stroke-width="1.4" stroke-linecap="round"'
	const dotStyle = 'fill="#ffffff" stroke="#90a4ae" stroke-width="1.4"'

	const wires: { string } = {}
	const stubs: { string } = {}
	for _, c in cells do
		for slot = 1, arity(net.Tag[c]) + 1 do
			const p = portOf(c, slot)
			const q = net.Link[p] or 0
			if q == 0 then
				const P, o = point[p], out[p]
				const E = { x = P.x + o.x * FREE_LEN, y = P.y + o.y * FREE_LEN }
				include(E)
				stubs[#stubs + 1] =
					`<line x1="{fmt(P.x)}" y1="{fmt(P.y)}" x2="{fmt(E.x)}" y2="{fmt(
						E.y
					)}" {stubStyle}/>`
				stubs[#stubs + 1] =
					`<circle cx="{fmt(E.x)}" cy="{fmt(E.y)}" r="{STUB_RADIUS}" {dotStyle}/>`
			elseif p < q then
				const P, Q = point[p], point[q]
				if owner(q) == c then
					const c1 = {
						x = P.x + out[p].x * LOOP_LEN,
						y = P.y + out[p].y * LOOP_LEN,
					}
					const c2 = {
						x = Q.x + out[q].x * LOOP_LEN,
						y = Q.y + out[q].y * LOOP_LEN,
					}
					include(c1)
					include(c2)
					wires[#wires + 1] =
						`<path d="M {fmt(P.x)} {fmt(P.y)} C {fmt(c1.x)} {fmt(
							c1.y
						)} {fmt(c2.x)} {fmt(c2.y)} {fmt(Q.x)} {fmt(Q.y)}" {wireStyle}/>`
				else
					-- The wire leaves each port along its normal and bends to the
					-- partner over one smooth curve, so it always meets the cell
					-- cleanly and the turn is never concentrated in a kink.
					const gap = math.max(
						0.01,
						math.sqrt((Q.x - P.x) ^ 2 + (Q.y - P.y) ^ 2)
					)
					const k = math.min(gap * WIRE_BULGE, WIRE_BULGE_MAX)
					const c1 = {
						x = P.x + out[p].x * k,
						y = P.y + out[p].y * k,
					}
					const c2 = {
						x = Q.x + out[q].x * k,
						y = Q.y + out[q].y * k,
					}
					include(c1)
					include(c2)
					wires[#wires + 1] =
						`<path d="M {fmt(P.x)} {fmt(P.y)} C {fmt(c1.x)} {fmt(
							c1.y
						)} {fmt(c2.x)} {fmt(c2.y)} {fmt(Q.x)} {fmt(Q.y)}" {wireStyle}/>`
				end
			end
		end
	end

	const bodies: { string } = {}
	for _, c in cells do
		const fill, stroke, text = colorOf(net.Tag[c])
		if net.Tag[c] == "Epsilon" then
			const center = hub[c]
			bodies[#bodies + 1] = `<circle cx="{fmt(center.x)}" cy="{fmt(
				center.y
			)}" r="{CIRCLE_RADIUS}" fill="{fill}" stroke="{stroke}" stroke-width="1.6"/>`
		else
			bodies[#bodies + 1] = `<polygon points="{fmt(tip[c].x)},{fmt(
				tip[c].y
			)} {fmt(e1[c].x)},{fmt(e1[c].y)} {fmt(e2[c].x)},{fmt(e2[c].y)}" fill="{fill}" stroke="{stroke}" stroke-width="1.6" stroke-linejoin="round"/>`
		end
		bodies[#bodies + 1] =
			`<text x="{fmt(pos[c].x)}" y="{fmt(pos[c].y)}" font-size="13" font-weight="600" fill="{text}" text-anchor="middle" dominant-baseline="central">{labelOf(
				net.Tag[c]
			)}</text>`
	end

	local x, y = minX - MARGIN, minY - MARGIN
	local w, h = (maxX - minX) + 2 * MARGIN, (maxY - minY) + 2 * MARGIN
	if #cells == 0 then
		x, y, w, h = 0, 0, 160, 80
	end

	const pieces = {
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="{fmt(x)} {fmt(y)} {fmt(
			w
		)} {fmt(h)}" width="{fmt(w)}" height="{fmt(h)}" font-family="system-ui, sans-serif">`,
		`<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" />`,
	}
	for _, group in { wires, stubs, bodies } do
		const joined = table.concat(group, "\n")
		if joined ~= "" then
			pieces[#pieces + 1] = joined
		end
	end
	pieces[#pieces + 1] = `</svg>`
	return table.concat(pieces, "\n")
end

return toSvg
