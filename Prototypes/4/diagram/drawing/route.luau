--!strict
-- ROUTING WIRES AROUND CELLS
--
-- A wire leaves each port along its normal and bends to its partner over one smooth curve.
-- If that curve would cut through a cell body it is routed instead, along the free lanes between cells, and drawn with its corners rounded.

local Types = require "../../engine/types"
local G = require "./geometry"
local Orient = require "./orient"

type Cell = Types.Cell
type Vec = G.Vec
type Scene = Orient.Scene

-- Routing ---------------------------------------------------------------------
-- How far a point lies outside a cell body (0 when inside it). A wire that would otherwise cut through a cell is re-routed along the free lanes, so a curve never crosses a cell unless it starts or ends on it.
const function bodyDist(
	scene: Scene,
	x: number,
	y: number,
	c: Cell
): number
	if scene.net.Tag[c] == "Epsilon" then
		return math.max(0, math.sqrt((x - scene.hub[c].x) ^ 2 + (y - scene.hub[c].y) ^ 2) - G.CIRCLE_RADIUS)
	end

	if G.pointInTri(x, y, scene.tip[c], scene.e1[c], scene.e2[c]) then
		return 0
	end

	return math.min(G.segDist(x, y, scene.tip[c].x, scene.tip[c].y, scene.e1[c].x, scene.e1[c].y), G.segDist(x, y, scene.e1[c].x, scene.e1[c].y, scene.e2[c].x, scene.e2[c].y), G.segDist(x, y, scene.e2[c].x, scene.e2[c].y, scene.tip[c].x, scene.tip[c].y))
end

const ROUTE_STEP = G.PITCH / 8
const ROUTE_CLEAR = G.PITCH / 8
const ROUTE_LEAD = G.PITCH / 4
const ROUTE_TURN = ROUTE_STEP * 2
const ROUTE_DX = {
	1,
	-1,
	0,
	0,
}
const ROUTE_DY = {
	0,
	0,
	1,
	-1,
}

const function blockedAt(
	scene: Scene,
	x: number,
	y: number
): boolean
	for _, c in scene.cells do
		if bodyDist(scene, x, y, c) < ROUTE_CLEAR then
			return true
	end end

	return false
end

-- A* over a fine lattice of the free space, preferring long straights (a turn costs extra). Returns the polyline P, A, ..., B, Q, or nil when the ports are boxed in.
const function route(
	scene: Scene,
	P: G.Vec,
	np: G.Vec,
	Q: G.Vec,
	nq: G.Vec
): { G.Vec }?
	const A = {
		x = P.x + np.x * ROUTE_LEAD,
		y = P.y + np.y * ROUTE_LEAD,
	}
	const B = {
		x = Q.x + nq.x * ROUTE_LEAD,
		y = Q.y + nq.y * ROUTE_LEAD,
	}
	local loX, loY = math.huge, math.huge
	local hiX, hiY = -math.huge, -math.huge

	for _, c in scene.cells do
		if scene.net.Tag[c] == "Epsilon" then
			loX = math.min(loX, scene.hub[c].x - G.CIRCLE_RADIUS)
			loY = math.min(loY, scene.hub[c].y - G.CIRCLE_RADIUS)
			hiX = math.max(hiX, scene.hub[c].x + G.CIRCLE_RADIUS)
			hiY = math.max(hiY, scene.hub[c].y + G.CIRCLE_RADIUS)
		else
			loX = math.min(loX, scene.tip[c].x, scene.e1[c].x, scene.e2[c].x)
			loY = math.min(loY, scene.tip[c].y, scene.e1[c].y, scene.e2[c].y)
			hiX = math.max(hiX, scene.tip[c].x, scene.e1[c].x, scene.e2[c].x)
			hiY = math.max(hiY, scene.tip[c].y, scene.e1[c].y, scene.e2[c].y)
	end end

	loX = math.min(loX, P.x, Q.x, A.x, B.x) - 2 * G.PITCH
	loY = math.min(loY, P.y, Q.y, A.y, B.y) - 2 * G.PITCH
	hiX = math.max(hiX, P.x, Q.x, A.x, B.x) + 2 * G.PITCH
	hiY = math.max(hiY, P.y, Q.y, A.y, B.y) + 2 * G.PITCH
	const step = ROUTE_STEP
	const cols = math.floor((hiX - loX) / step) + 1
	const rows = math.floor((hiY - loY) / step) + 1

	const function ix(
		x: number
	): number
		return math.floor((x - loX) / step + 0.5)
	end

	const function iy(
		y: number
	): number
		return math.floor((y - loY) / step + 0.5)
	end

	const function freeNode(
		ax: number,
		ay: number
	): G.Vec?
		const si, sj = ix(ax), iy(ay)

		for r = 0, 5 do
			for di = -r, r do
				for dj = -r, r do
					if math.max(math.abs(di), math.abs(dj)) == r then
						const i, j = si + di, sj + dj

						if i >= 0 and i < cols and j >= 0 and j < rows then
							const x, y = loX + i * step, loY + j * step

							if not blockedAt(scene, x, y) then
								return {
									x = x,
									y = y,
								}
		end end end end end end

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
	-- Heap entries carry both the A* priority (f = g + h) and the path cost g they were queued with, so a stale entry can be told apart from the current best for the same state.
	const heap: { {
		f: number,
		g: number,
		s: number,
	} } = {}

	const function push(
		f: number,
		g: number,
		s: number
	)
		table.insert(
			heap, {
				f = f,
				g = g,
				s = s,
			}
		)
		local i = #heap

		while i > 1 do
			const par = i // 2

			if heap[par].f <= heap[i].f then
				break
			end

			heap[par], heap[i] = heap[i], heap[par]
			i = par
	end end

	const function pop(): {
		f: number,
		g: number,
		s: number,
	}
		const top = heap[1]
		const last = table.remove(heap) :: {
			f: number,
			g: number,
			s: number,
		}

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
		end end

		return top
	end

	const startState = (sj * cols + si) * 4 + G.dirIndexOf(np.x, np.y)
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

			if blockedAt(scene, loX + ni * step, loY + nj * step) then
				continue
			end

			const move = step + (
				if nd == dir then
					0
				else
					ROUTE_TURN
			)
			const ns = (nj * cols + ni) * 4 + nd
			const ng = top.g + move

			if ng < g[ns + 1] - 1e-6 then
				g[ns + 1] = ng
				back[ns + 1] = top.s
				const h = (math.abs(ni - gi) + math.abs(nj - gj)) * step
				push(ng + h, ng, ns)
	end end end

	if goalState < 0 then
		return nil
	end

	const nodes: { G.Vec } = {}
	local s = goalState

	while s >= 0 do
		const pos = s // 4
		const i = pos % cols
		const j = pos // cols
		table.insert(
			nodes, {
				x = loX + i * step,
				y = loY + j * step,
			}
		)
		s = back[s + 1]
	end

	-- Join the lattice at the free node nearest A (and B). Keeping A and B as well would leave a small kink wherever the lead-in from the port reverses into the first lattice step; the nearest node is only a few pixels from A, so leaving the port straight to it is cleaner.
	const raw: { G.Vec } = {
		P,
	}

	for k = #nodes, 1, -1 do
		table.insert(raw, nodes[k])
	end

	table.insert(raw, Q)
	const poly: { G.Vec } = {}

	for _, v in raw do
		const last = poly[#poly]

		if last and math.abs(last.x - v.x) < 0.5 and math.abs(last.y - v.y) < 0.5 then
			continue
		end

		table.insert(poly, v)
	end

	local k = 2

	while k < #poly do
		const a, b = poly[k - 1], poly[k + 1]
		const cross = (poly[k].x - a.x) * (b.y - a.y) - (poly[k].y - a.y) * (b.x - a.x)

		if math.abs(cross) < 0.5 then
			table.remove(poly, k)
		else
			k += 1
	end end

	return poly
end

const function roundedPath(
	pts: { G.Vec }
): string
	const r = ROUTE_STEP * 0.9
	local d = `M {G.fmt(pts[1].x)} {G.fmt(pts[1].y)}`

	for k = 2, #pts - 1 do
		const prev, cur, nxt = pts[k - 1], pts[k], pts[k + 1]
		const inx, iny = G.unit(cur.x - prev.x, cur.y - prev.y, 0, 0)
		const outx, outy = G.unit(nxt.x - cur.x, nxt.y - cur.y, 0, 0)

		if inx * outx + iny * outy < -0.999 then
			d ..= ` L {G.fmt(cur.x)} {G.fmt(cur.y)}`
		else
			const lenIn = math.sqrt((cur.x - prev.x) ^ 2 + (cur.y - prev.y) ^ 2)
			const lenOut = math.sqrt((nxt.x - cur.x) ^ 2 + (nxt.y - cur.y) ^ 2)
			const rr = math.min(r, lenIn * 0.5, lenOut * 0.5)
			const ax, ay = cur.x - inx * rr, cur.y - iny * rr
			const bx, by = cur.x + outx * rr, cur.y + outy * rr
			d ..= ` L {G.fmt(ax)} {G.fmt(ay)} Q {G.fmt(cur.x)} {G.fmt(cur.y)} {G.fmt(bx)} {G.fmt(by)}`
	end end

	d ..= ` L {G.fmt(pts[#pts].x)} {G.fmt(pts[#pts].y)}`

	return d
end

-- Does a bend cut through a cell? The bend leaves `skipA` at P and arrives at
-- `skipB` at Q, so it may touch those two cells at the ports, but it must not cut through any cell body -- including those two, which it still clips when it doubles back on itself.
const function cubicHits(
	scene: Scene,
	P: G.Vec,
	c1: G.Vec,
	c2: G.Vec,
	Q: G.Vec,
	skipA: Cell,
	skipB: Cell
): boolean
	for k = 2, 23 do
		const t = k / 25
		const mt = 1 - t
		const x = mt * mt * mt * P.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * Q.x
		const y = mt * mt * mt * P.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * Q.y

		for _, c in scene.cells do
			if bodyDist(scene, x, y, c) < 1 then
				-- A sample right at P or Q is the wire meeting its own port, not a crossing; anywhere else is a real hit.
				const atPort = c == skipA and (x - P.x) ^ 2 + (y - P.y) ^ 2 < 4 or c == skipB and (x - Q.x) ^ 2 + (y - Q.y) ^ 2 < 4

				if not atPort then
					return true
	end end end end

	return false
end

return {
	cubicHits = cubicHits,
	route = route,
	roundedPath = roundedPath,
}
