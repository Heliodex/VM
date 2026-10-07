--!strict
-- SVG rendering of an interaction-combinator net, in the style of Lafont's
-- paper: gamma/delta cells are triangles whose tip is the principal port;
-- epsilon cells are circles; wires join ports; free ports are short dangling
-- stubs.
--
-- The drawing is deliberately regular. Cells sit on a square grid at a fixed
-- pitch, so neighbours are evenly spaced and never crowded. Each cell is turned
-- in quarter turns only, so its ports always point along the grid axes. Branches
-- that the wiring cannot tell apart are placed as mirror images, so a symmetric
-- net is drawn symmetrically rather than lurching to one side; if two such
-- interchangeable cells still end up on the wrong sides of a shared partner, so
-- that their wires cross, their positions are swapped to untangle them. A wire
-- leaves a port along the port's outward normal and curves to its partner; a
-- curve that would cut through a cell body -- even that of one of the two cells
-- it joins, when it has to double back on itself -- is routed around it, so a
-- wire touches a cell only where it is attached, at its port. Cells joined at
-- their principal ports (an active pair) face each other, so that wire is a
-- straight step between the two tips. Parts of a net that share no wires are
-- laid out on their own grids and packed a fixed distance apart.
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

-- Distance from a point to a line segment.
const function segDist(
	px: number,
	py: number,
	ax: number,
	ay: number,
	bx: number,
	by: number
): number
	const dx, dy = bx - ax, by - ay
	const l2 = dx * dx + dy * dy
	if l2 < 1e-9 then
		return math.sqrt((px - ax) ^ 2 + (py - ay) ^ 2)
	end
	local t = ((px - ax) * dx + (py - ay) * dy) / l2
	t = math.max(0, math.min(1, t))
	return math.sqrt((px - (ax + t * dx)) ^ 2 + (py - (ay + t * dy)) ^ 2)
end

-- Whether two open segments cross: shared endpoints and touching do not count.
const function segmentsCross(
	ax: number,
	ay: number,
	bx: number,
	by: number,
	cx: number,
	cy: number,
	dx: number,
	dy: number
): boolean
	const d1 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
	const d2 = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax)
	const d3 = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx)
	const d4 = (dx - cx) * (by - cy) - (dy - cy) * (bx - cx)
	return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0))
		and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))
end

const function pointInTri(
	px: number,
	py: number,
	a: Vec,
	b: Vec,
	c: Vec
): boolean
	const d1 = (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x)
	const d2 = (c.x - b.x) * (py - b.y) - (c.y - b.y) * (px - b.x)
	const d3 = (a.x - c.x) * (py - c.y) - (a.y - c.y) * (px - c.x)
	const neg = d1 < 0 or d2 < 0 or d3 < 0
	const pos = d1 > 0 or d2 > 0 or d3 > 0
	return not (neg and pos)
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

-- The quarter-turn index of a vector: 0 = +x, 1 = -x, 2 = +y, 3 = -y.
const function dirIndexOf(vx: number, vy: number): number
	if math.abs(vx) >= math.abs(vy) then
		return if vx >= 0 then 0 else 1
	end
	return if vy >= 0 then 2 else 3
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

-- Symmetry --------------------------------------------------------------------

-- A port's signature: whether it is principal or auxiliary, whether it is free,
-- and, when wired, the kind of port it meets and which cell owns that port.
-- `pi`, when given, maps the owning cell of a wired partner first, so a
-- candidate symmetry can be checked against the wiring.
const function portSignature(
	net: Net,
	c: Cell,
	slot: number,
	pi: { [Cell]: Cell }?
): string
	const mine = if slot == 1 then "P" else "A"
	const q = net.Link[portOf(c, slot)] or 0
	if q == 0 then
		return `{mine}:free`
	end
	const theirs = if isPrincipalPort(q) then "P" else "A"
	const ownerCell = owner(q)
	const image = if pi then pi[ownerCell] else ownerCell
	return `{mine}:{theirs}:{image}`
end

-- How many page-aligned symmetries a placement has: a half-turn and reflections
-- in a vertical or horizontal line that send every cell to a cell of the same
-- symbol and preserve the wiring. Diagonal mirrors are left out on purpose, so
-- a drawing that only lines up on the slant is not preferred over one that
-- lines up with the page.
const function symmetryCount(
	net: Net,
	grid: { [Cell]: Grid },
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

	const at: { [string]: Cell } = {}
	for _, c in cells do
		at[key(grid[c])] = c
	end

	-- Turn an isometry into a permutation of the cells, or nil when it does not
	-- map the placement onto itself.
	const function permutation(fn: (Grid) -> Grid): { [Cell]: Cell }?
		const pi: { [Cell]: Cell } = {}
		const used: { [Cell]: boolean } = {}
		for _, c in cells do
			const d = at[key(fn(grid[c]))]
			if not d or used[d] then
				return nil
			end
			used[d] = true
			pi[c] = d
		end
		return pi
	end

	const function preserves(pi: { [Cell]: Cell }): boolean
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
			for slot = 1, arity(net.Tag[c]) + 1 do
				table.insert(a, portSignature(net, c, slot, pi))
			end
			for slot = 1, arity(net.Tag[pi[c]]) + 1 do
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

	const function check(pi: { [Cell]: Cell }?): number
		if pi and preserves(pi) then
			return 1
		end
		return 0
	end

	const halfTurn = permutation(function(g: Grid): Grid
		return { x = 2 * cx - g.x, y = 2 * cy - g.y }
	end)
	const vertical = permutation(function(g: Grid): Grid
		return { x = 2 * cx - g.x, y = g.y }
	end)
	const horizontal = permutation(function(g: Grid): Grid
		return { x = g.x, y = 2 * cy - g.y }
	end)
	return check(halfTurn) + check(vertical) + check(horizontal)
end

-- Refine cells into colour classes by repeatedly folding in the kinds of the
-- ports they use and the current colours of their partners. Cells of the same
-- colour are interchangeable as far as the wiring can tell, which is close
-- enough to an automorphism orbit for these small nets.
const function refineColors(net: Net, cells: { Cell }): { [Cell]: string }
	const color: { [Cell]: string } = {}
	for _, c in cells do
		color[c] = net.Tag[c]
	end
	for _ = 1, #cells do
		local changed = false
		const next: { [Cell]: string } = {}
		for _, c in cells do
			const parts: { string } = {}
			for slot = 1, arity(net.Tag[c]) + 1 do
				const mine = if slot == 1 then "P" else "A"
				const q = net.Link[portOf(c, slot)] or 0
				if q == 0 then
					table.insert(parts, `{mine}free`)
				else
					const theirs = if isPrincipalPort(q) then "P" else "A"
					table.insert(parts, `{mine}{theirs}{color[owner(q)]}`)
				end
			end
			table.sort(parts)
			next[c] = `{net.Tag[c]}({table.concat(parts, ",")})`
		end
		for _, c in cells do
			if next[c] ~= color[c] then
				changed = true
				color[c] = next[c]
			end
		end
		if not changed then
			break
		end
	end
	return color
end

-- Place one connected part on the integer grid. A breadth-first walk starts at a
-- cell and puts every wired neighbour in a free slot beside the cell it grows
-- from; the spring guide decides which side. Every choice of root, quarter-turn
-- and reflection of the guide is tried and then folded onto nearby free slots.
-- The candidate with the most page-aligned symmetry wins, with the most compact
-- and shortest-wired layout breaking ties, so equivalent branches spread out
-- evenly instead of the whole part lurching to one side.
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

	const colors = refineColors(net, cells)

	const function build(
		root: Cell,
		rot: number,
		mirror: boolean
	): { [Cell]: Grid }
		const grid: { [Cell]: Grid } = {}
		const occ: { [string]: boolean } = {}
		grid[root] = { x = 0, y = 0 }
		occ[key(grid[root])] = true
		const queue: { Cell } = { root }
		local head = 1

		-- Direction from u towards v, after the guide's rotation and reflection.
		const function lean(u: Cell, v: Cell): (number, number)
			local dxf, dyf = guide[v].x - guide[u].x, guide[v].y - guide[u].y
			if mirror then
				dxf = -dxf
			end
			for _ = 1, rot do
				dxf, dyf = -dyf, dxf
			end
			return dxf, dyf
		end

		const function freeAt(u: Cell): { Vec }
			const list: { Vec } = {}
			for _, d in DIRS do
				const g = { x = grid[u].x + d.x, y = grid[u].y + d.y }
				if not occ[key(g)] then
					table.insert(list, d)
				end
			end
			return list
		end

		const function put(u: Cell, v: Cell, d: Vec)
			const g = { x = grid[u].x + d.x, y = grid[u].y + d.y }
			grid[v] = g
			occ[key(g)] = true
			table.insert(queue, v)
		end

		-- Fall back to the free slot nearest the spring guide.
		const function greedy(u: Cell, v: Cell)
			local dxf, dyf = lean(u, v)
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

		-- Lets two branches of u be recognised as a matching pair: same colour,
		-- and the same kind of port on u and on the partner.
		const function branchKey(u: Cell, slot: number, v: Cell): string
			const mine = if slot == 1 then "P" else "A"
			const q = net.Link[portOf(u, slot)] or 0
			const theirs = if q ~= 0 and isPrincipalPort(q) then "P" else "A"
			return `{mine}{theirs}{colors[v]}`
		end

		while head <= #queue do
			const u = queue[head]
			head += 1
			const pending: { { v: Cell, key: string } } = {}
			for slot = 1, arity(net.Tag[u]) + 1 do
				const q = net.Link[portOf(u, slot)] or 0
				const v = if q ~= 0 then owner(q) else u
				if q ~= 0 and v ~= u and inPart[v] and not grid[v] then
					table.insert(
						pending,
						{ v = v, key = branchKey(u, slot, v) }
					)
				end
			end

			const done: { [number]: boolean } = {}
			-- Equivalent branches go into opposite slots, so a pair of matching
			-- sub-trees mirrors each other on the page.
			for i = 1, #pending do
				if done[i] then
					continue
				end
				for j = i + 1, #pending do
					if done[j] or pending[i].key ~= pending[j].key then
						continue
					end
					local bestScore = -math.huge
					local first: Vec? = nil
					local second: Vec? = nil
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
							const straight = da.x * dix
								+ da.y * diy
								+ db.x * djx
								+ db.y * djy
							const swapped = da.x * djx
								+ da.y * djy
								+ db.x * dix
								+ db.y * diy
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
							end
						end
					end
					if first and second and firstCell and secondCell then
						put(u, firstCell, first)
						put(u, secondCell, second)
						done[i], done[j] = true, true
					end
				end
			end
			for i = 1, #pending do
				if not done[i] then
					greedy(u, pending[i].v)
				end
			end
		end
		return grid
	end

	const function spanAndWires(grid: { [Cell]: Grid }): (number, number)
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

	-- Nudge cells into nearby free slots while that shrinks the part's longest
	-- side. The move must be a strict improvement, so a clean chain is left as a
	-- straight run.
	const function compact(start: { [Cell]: Grid }): { [Cell]: Grid }
		const occ: { [string]: boolean } = {}
		for _, v in start do
			occ[key(v)] = true
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
						const g = { x = home.x + dx, y = home.y + dy }
						if occ[key(g)] then
							continue
						end
						start[c] = g
						const v = value()
						if v < bestValue - 1e-9 then
							bestValue = v
							bestSlot = g
						end
						start[c] = home
					end
				end
				if bestSlot ~= home then
					occ[key(home)] = false
					start[c] = bestSlot
					occ[key(bestSlot)] = true
					improved = true
				end
			end
			if not improved then
				break
			end
		end
		return start
	end

	-- Try every root, quarter-turn and reflection. Keep the candidate with the
	-- most page-aligned symmetry, and only accept a folded version when folding
	-- does not cost it any symmetry, so symmetric parts stay symmetric.
	local best: { [Cell]: Grid }? = nil
	local bestSym = -1
	local bestSpan, bestWires = math.huge, math.huge
	for _, root in cells do
		for rot = 0, 3 do
			for _, mirror in { false, true } do
				const straight = build(root, rot, mirror)
				const straightSym = symmetryCount(net, straight, cells)
				const folded = compact(build(root, rot, mirror))
				local sym = symmetryCount(net, folded, cells)
				local candidate = folded
				if sym < straightSym then
					candidate = straight
					sym = straightSym
				end
				const span, wires = spanAndWires(candidate)
				if
					sym > bestSym
					or (
						sym == bestSym
						and (
							span < bestSpan
							or (span == bestSpan and wires < bestWires)
						)
					)
				then
					bestSym, bestSpan, bestWires = sym, span, wires
					best = candidate
				end
			end
		end
	end
	return best :: { [Cell]: Grid }
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
	const function resetOrientations()
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
	end
	resetOrientations()

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

	-- Swing every free cell to its cheapest quarter turn, refreshing the ports
	-- after each choice, and repeat to a fixed point.
	const function settleOrientations()
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
	end
	settleOrientations()

	-- How many pairs of wires cross, counted on the straight chords between their
	-- port anchors. The drawn wires leave along the port normals, so a chord
	-- crossing is a good enough signal for choosing between placements.
	const function chordCrossings(): number
		const segs: { { Vec } } = {}
		for _, c in cells do
			for slot = 1, arity(net.Tag[c]) + 1 do
				const p = portOf(c, slot)
				const q = net.Link[p] or 0
				if q ~= 0 and p < q and owner(q) ~= c then
					table.insert(segs, { point[p], point[q] })
				end
			end
		end
		local count = 0
		for i = 1, #segs do
			for j = i + 1, #segs do
				const a, b = segs[i], segs[j]
				if
					segmentsCross(
						a[1].x,
						a[1].y,
						a[2].x,
						a[2].y,
						b[1].x,
						b[1].y,
						b[2].x,
						b[2].y
					)
				then
					count += 1
				end
			end
		end
		return count
	end

	-- Cells the wiring cannot tell apart can still land on the wrong sides of a
	-- shared partner, which puts their wires across each other. Swapping the
	-- positions of two such siblings untangles them without changing the drawing
	-- up to a renaming, so try each pair and keep a swap only when it strictly
	-- reduces the number of crossings.
	local crossings = chordCrossings()
	if crossings > 0 then
		const colors = refineColors(net, cells)
		const wired: { [Cell]: { [Cell]: boolean } } = {}
		for _, c in cells do
			wired[c] = {}
		end
		for _, c in cells do
			for slot = 1, arity(net.Tag[c]) + 1 do
				const q = net.Link[portOf(c, slot)] or 0
				if q ~= 0 and owner(q) ~= c then
					wired[c][owner(q)] = true
					wired[owner(q)][c] = true
				end
			end
		end
		const function siblings(u: Cell, v: Cell): boolean
			for w, _ in wired[u] do
				if wired[v][w] then
					return true
				end
			end
			return false
		end

		for _ = 1, 4 do
			local improved = false
			for i = 1, #cells do
				for j = i + 1, #cells do
					const u, v = cells[i], cells[j]
					if colors[u] ~= colors[v] or not siblings(u, v) then
						continue
					end
					pos[u], pos[v] = pos[v], pos[u]
					resetOrientations()
					settleOrientations()
					const next = chordCrossings()
					if next < crossings then
						crossings = next
						improved = true
					else
						pos[u], pos[v] = pos[v], pos[u]
						resetOrientations()
						settleOrientations()
					end
				end
			end
			if not improved then
				break
			end
		end
	end

	-- Routing ---------------------------------------------------------------------

	-- How far a point lies outside a cell body (0 when inside it). A wire that
	-- would otherwise cut through a cell is re-routed along the free lanes, so
	-- a curve never crosses a cell unless it starts or ends on it.
	const function bodyDist(x: number, y: number, c: Cell): number
		if net.Tag[c] == "Epsilon" then
			return math.max(
				0,
				math.sqrt((x - hub[c].x) ^ 2 + (y - hub[c].y) ^ 2)
					- CIRCLE_RADIUS
			)
		end
		if pointInTri(x, y, tip[c], e1[c], e2[c]) then
			return 0
		end
		return math.min(
			segDist(x, y, tip[c].x, tip[c].y, e1[c].x, e1[c].y),
			segDist(x, y, e1[c].x, e1[c].y, e2[c].x, e2[c].y),
			segDist(x, y, e2[c].x, e2[c].y, tip[c].x, tip[c].y)
		)
	end

	const ROUTE_STEP = PITCH / 8
	const ROUTE_CLEAR = PITCH / 8
	const ROUTE_LEAD = PITCH / 4
	const ROUTE_TURN = ROUTE_STEP * 2
	const ROUTE_DX = { 1, -1, 0, 0 }
	const ROUTE_DY = { 0, 0, 1, -1 }

	const function blockedAt(x: number, y: number): boolean
		for _, c in cells do
			if bodyDist(x, y, c) < ROUTE_CLEAR then
				return true
			end
		end
		return false
	end

	-- A* over a fine lattice of the free space, preferring long straights (a
	-- turn costs extra). Returns the polyline P, A, ..., B, Q, or nil when the
	-- ports are boxed in.
	const function route(P: Vec, np: Vec, Q: Vec, nq: Vec): { Vec }?
		const A = { x = P.x + np.x * ROUTE_LEAD, y = P.y + np.y * ROUTE_LEAD }
		const B = { x = Q.x + nq.x * ROUTE_LEAD, y = Q.y + nq.y * ROUTE_LEAD }
		local loX, loY = math.huge, math.huge
		local hiX, hiY = -math.huge, -math.huge
		for _, c in cells do
			if net.Tag[c] == "Epsilon" then
				loX = math.min(loX, hub[c].x - CIRCLE_RADIUS)
				loY = math.min(loY, hub[c].y - CIRCLE_RADIUS)
				hiX = math.max(hiX, hub[c].x + CIRCLE_RADIUS)
				hiY = math.max(hiY, hub[c].y + CIRCLE_RADIUS)
			else
				loX = math.min(loX, tip[c].x, e1[c].x, e2[c].x)
				loY = math.min(loY, tip[c].y, e1[c].y, e2[c].y)
				hiX = math.max(hiX, tip[c].x, e1[c].x, e2[c].x)
				hiY = math.max(hiY, tip[c].y, e1[c].y, e2[c].y)
			end
		end
		loX = math.min(loX, P.x, Q.x, A.x, B.x) - 2 * PITCH
		loY = math.min(loY, P.y, Q.y, A.y, B.y) - 2 * PITCH
		hiX = math.max(hiX, P.x, Q.x, A.x, B.x) + 2 * PITCH
		hiY = math.max(hiY, P.y, Q.y, A.y, B.y) + 2 * PITCH

		const step = ROUTE_STEP
		const cols = math.floor((hiX - loX) / step) + 1
		const rows = math.floor((hiY - loY) / step) + 1
		const function ix(x: number): number
			return math.floor((x - loX) / step + 0.5)
		end
		const function iy(y: number): number
			return math.floor((y - loY) / step + 0.5)
		end
		const function freeNode(ax: number, ay: number): Vec?
			const si, sj = ix(ax), iy(ay)
			for r = 0, 5 do
				for di = -r, r do
					for dj = -r, r do
						if math.max(math.abs(di), math.abs(dj)) == r then
							const i, j = si + di, sj + dj
							if i >= 0 and i < cols and j >= 0 and j < rows then
								const x, y = loX + i * step, loY + j * step
								if not blockedAt(x, y) then
									return { x = x, y = y }
								end
							end
						end
					end
				end
			end
			return nil
		end

		const startNode = freeNode(A.x, A.y)
		const finishNode = freeNode(B.x, B.y)
		if not startNode or not finishNode then
			return nil
		end
		const si, sj = ix(startNode.x), iy(startNode.y)
		const gi, gj = ix(finishNode.x), iy(finishNode.y)

		const stateCount = cols * rows * 4
		const g: { number } = table.create(stateCount, math.huge)
		const back: { number } = table.create(stateCount, -1)
		-- Heap entries carry both the A* priority (f = g + h) and the path cost
		-- g they were queued with, so a stale entry can be told apart from the
		-- current best for the same state.
		const heap: { { f: number, g: number, s: number } } = {}
		const function push(f: number, g: number, s: number)
			table.insert(heap, { f = f, g = g, s = s })
			local i = #heap
			while i > 1 do
				const par = i // 2
				if heap[par].f <= heap[i].f then
					break
				end
				heap[par], heap[i] = heap[i], heap[par]
				i = par
			end
		end
		const function pop(): { f: number, g: number, s: number }
			const top = heap[1]
			const last =
				table.remove(heap) :: { f: number, g: number, s: number }
			if #heap > 0 then
				heap[1] = last
				local i = 1
				while true do
					local m = i
					const l, r = i * 2, i * 2 + 1
					if l <= #heap and heap[l].f < heap[m].f then
						m = l
					end
					if r <= #heap and heap[r].f < heap[m].f then
						m = r
					end
					if m == i then
						break
					end
					heap[i], heap[m] = heap[m], heap[i]
					i = m
				end
			end
			return top
		end

		const startState = ((sj * cols) + si) * 4 + dirIndexOf(np.x, np.y)
		g[startState + 1] = 0
		push(0, 0, startState)
		local goalState = -1
		while #heap > 0 do
			const top = pop()
			if top.g > g[top.s + 1] + 1e-6 then
				continue
			end
			const dir = top.s % 4
			const pos = top.s // 4
			const i = pos % cols
			const j = pos // cols
			if i == gi and j == gj then
				goalState = top.s
				break
			end
			for nd = 0, 3 do
				const ni, nj = i + ROUTE_DX[nd + 1], j + ROUTE_DY[nd + 1]
				if ni < 0 or ni >= cols or nj < 0 or nj >= rows then
					continue
				end
				if blockedAt(loX + ni * step, loY + nj * step) then
					continue
				end
				const move = step + (if nd == dir then 0 else ROUTE_TURN)
				const ns = ((nj * cols) + ni) * 4 + nd
				const ng = top.g + move
				if ng < g[ns + 1] - 1e-6 then
					g[ns + 1] = ng
					back[ns + 1] = top.s
					const h = (math.abs(ni - gi) + math.abs(nj - gj)) * step
					push(ng + h, ng, ns)
				end
			end
		end
		if goalState < 0 then
			return nil
		end

		const nodes: { Vec } = {}
		local s = goalState
		while s >= 0 do
			const pos = s // 4
			const i = pos % cols
			const j = pos // cols
			table.insert(nodes, { x = loX + i * step, y = loY + j * step })
			s = back[s + 1]
		end

		-- Join the lattice at the free node nearest A (and B). Keeping A and B
		-- as well would leave a small kink wherever the lead-in from the port
		-- reverses into the first lattice step; the nearest node is only a few
		-- pixels from A, so leaving the port straight to it is cleaner.
		const raw: { Vec } = { P }
		for k = #nodes, 1, -1 do
			table.insert(raw, nodes[k])
		end
		table.insert(raw, Q)
		const poly: { Vec } = {}
		for _, v in raw do
			const last = poly[#poly]
			if
				last
				and math.abs(last.x - v.x) < 0.5
				and math.abs(last.y - v.y) < 0.5
			then
				continue
			end
			table.insert(poly, v)
		end
		local k = 2
		while k < #poly do
			const a, b = poly[k - 1], poly[k + 1]
			const cross = (poly[k].x - a.x) * (b.y - a.y)
				- (poly[k].y - a.y) * (b.x - a.x)
			if math.abs(cross) < 0.5 then
				table.remove(poly, k)
			else
				k += 1
			end
		end
		return poly
	end

	const function roundedPath(pts: { Vec }): string
		const r = ROUTE_STEP * 0.9
		local d = `M {fmt(pts[1].x)} {fmt(pts[1].y)}`
		for k = 2, #pts - 1 do
			const prev, cur, nxt = pts[k - 1], pts[k], pts[k + 1]
			const inx, iny = unit(cur.x - prev.x, cur.y - prev.y, 0, 0)
			const outx, outy = unit(nxt.x - cur.x, nxt.y - cur.y, 0, 0)
			if inx * outx + iny * outy < -0.999 then
				d ..= ` L {fmt(cur.x)} {fmt(cur.y)}`
			else
				const lenIn =
					math.sqrt((cur.x - prev.x) ^ 2 + (cur.y - prev.y) ^ 2)
				const lenOut =
					math.sqrt((nxt.x - cur.x) ^ 2 + (nxt.y - cur.y) ^ 2)
				const rr = math.min(r, lenIn * 0.5, lenOut * 0.5)
				const ax, ay = cur.x - inx * rr, cur.y - iny * rr
				const bx, by = cur.x + outx * rr, cur.y + outy * rr
				d ..= ` L {fmt(ax)} {fmt(ay)} Q {fmt(cur.x)} {fmt(cur.y)} {fmt(
					bx
				)} {fmt(by)}`
			end
		end
		d ..= ` L {fmt(pts[#pts].x)} {fmt(pts[#pts].y)}`
		return d
	end

	-- Does a bend cut through a cell? The bend leaves `skipA` at P and arrives at
	-- `skipB` at Q, so it may touch those two cells at the ports, but it must not
	-- cut through any cell body -- including those two, which it still clips when
	-- it doubles back on itself.
	const function cubicHits(
		P: Vec,
		c1: Vec,
		c2: Vec,
		Q: Vec,
		skipA: Cell,
		skipB: Cell
	): boolean
		for k = 2, 23 do
			const t = k / 25
			const mt = 1 - t
			const x = mt * mt * mt * P.x
				+ 3 * mt * mt * t * c1.x
				+ 3 * mt * t * t * c2.x
				+ t * t * t * Q.x
			const y = mt * mt * mt * P.y
				+ 3 * mt * mt * t * c1.y
				+ 3 * mt * t * t * c2.y
				+ t * t * t * Q.y
			for _, c in cells do
				if bodyDist(x, y, c) < 1 then
					-- A sample right at P or Q is the wire meeting its own
					-- port, not a crossing; anywhere else is a real hit.
					const atPort = (
						c == skipA and (x - P.x) ^ 2 + (y - P.y) ^ 2 < 4
					)
						or (c == skipB and (x - Q.x) ^ 2 + (y - Q.y) ^ 2 < 4)
					if not atPort then
						return true
					end
				end
			end
		end
		return false
	end

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
					-- partner over one smooth curve. If that bend would cut
					-- through another cell it is routed around instead.
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
					const detour = if cubicHits(
							P,
							c1,
							c2,
							Q,
							owner(p),
							owner(q)
						)
						then route(P, out[p], Q, out[q])
						else nil
					if detour then
						for _, v in detour do
							include(v)
						end
						wires[#wires + 1] =
							`<path d="{roundedPath(detour)}" {wireStyle}/>`
					else
						include(c1)
						include(c2)
						wires[#wires + 1] =
							`<path d="M {fmt(P.x)} {fmt(P.y)} C {fmt(c1.x)} {fmt(
								c1.y
							)} {fmt(c2.x)} {fmt(c2.y)} {fmt(Q.x)} {fmt(
								Q.y
							)}" {wireStyle}/>`
					end
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
