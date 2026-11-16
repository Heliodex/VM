--!strict
-- ORIENTING THE CELLS AND FIXING THEIR PORTS
--
-- Given the grid positions of a part, works out where every port of every cell sits on the page.
-- Each free cell swings to the quarter turn that makes its wires straightest, then wires that still cross are untangled by swapping the positions of two cells the wiring cannot tell apart.

local Canon = require "../canon"
local G = require "./geometry"
local Net = require "../net"
local Types = require "../types"

type Cell = Types.Cell
type Net = Types.Net
type Port = Types.Port
type Vec = G.Vec

-- Everything the drawing needs about where cells and ports are, once they are placed and turned.
export type Scene = {
	net: Net,
	cells: { Cell },
	pos: { [Cell]: Vec },
	ori: { [Cell]: number },
	point: { [Port]: Vec },
	out: { [Port]: Vec },
	tip: { [Cell]: Vec },
	e1: { [Cell]: Vec },
	e2: { [Cell]: Vec },
	hub: { [Cell]: Vec },
}

const function orient(
	net: Net,
	cells: { Cell },
	pos: { [Cell]: Vec }
): Scene

	const centroid: G.Vec = {
		x = 0,
		y = 0,
	}

	for _, c in cells do
		centroid.x += pos[c].x
		centroid.y += pos[c].y
	end

	if #cells > 0 then
		centroid.x /= #cells
		centroid.y /= #cells
	end

	-- Cells whose principal port is wired to another cell's principal port form an active pair. Their two tips are forced to face each other, so that wire is a straight step between the tips. Every other cell is free to turn to whichever quarter turn best serves its wires.
	const ppPartner: {
		[Cell]: Cell,
	} = {}
	const paired: {
		[Cell]: boolean,
	} = {}

	for _, c in cells do
		const q = net.Link[Net.port(c, 1)] or 0

		if q ~= 0 and Net.owner(q) ~= c and Net.isPrincipal(q) then
			ppPartner[c] = Net.owner(q)
			paired[c] = true
	end end

	const ori: {
		[Cell]: number,
	} = {}

	const function resetOrientations()
		for _, c in cells do
			if paired[c] then
				ori[c] = G.dirToward(pos[c], pos[ppPartner[c]])
			else
				const q = net.Link[Net.port(c, 1)] or 0

				if q ~= 0 and Net.owner(q) ~= c then
					ori[c] = G.dirToward(pos[c], pos[Net.owner(q)])
				else
					ori[c] = G.dirToward(pos[c], centroid)
	end end end end

	resetOrientations()
	local point: {
		[Port]: G.Vec,
	} = {} -- where a wire meets the cell
	local out: {
		[Port]: G.Vec,
	} = {} -- outward normal: wires leave along this
	local tip: {
		[Cell]: G.Vec,
	} = {}
	local e1: {
		[Cell]: G.Vec,
	} = {}
	local e2: {
		[Cell]: G.Vec,
	} = {}
	local hub: {
		[Cell]: G.Vec,
	} = {}

	const function computePorts()
		point, out, tip, e1, e2, hub = {}, {}, {}, {}, {}, {}

		for _, c in cells do
			const center = pos[c]
			const d = G.DIRS[ori[c] + 1]

			if net.Tag[c] == "Epsilon" then
				hub[c] = center
				point[Net.port(c, 1)] = G.anchorOf(center, d, net.Tag[c], 1)
				out[Net.port(c, 1)] = d
			else
				const n = {
					x = -d.y,
					y = d.x,
				}
				tip[c] = {
					x = center.x + d.x * G.TIP_LEN,
					y = center.y + d.y * G.TIP_LEN,
				}
				e1[c] = {
					x = center.x - d.x * G.BASE_LEN + n.x * G.HALF_WIDTH,
					y = center.y - d.y * G.BASE_LEN + n.y * G.HALF_WIDTH,
				}
				e2[c] = {
					x = center.x - d.x * G.BASE_LEN - n.x * G.HALF_WIDTH,
					y = center.y - d.y * G.BASE_LEN - n.y * G.HALF_WIDTH,
				}
				point[Net.port(c, 1)] = tip[c]
				out[Net.port(c, 1)] = d
				-- auxiliary ports sit on the base edge, opposite the tip
				point[Net.port(c, 2)] = G.lerp(e1[c], e2[c], 1 / 3)
				point[Net.port(c, 3)] = G.lerp(e1[c], e2[c], 2 / 3)
				out[Net.port(c, 2)] = {
					x = -d.x,
					y = -d.y,
				}
				out[Net.port(c, 3)] = {
					x = -d.x,
					y = -d.y,
				}
	end end end

	-- Cost of turning a cell to face `idx`: how far each of its wired ports has to swing from its outward normal to point at the partner. A wire is drawn leaving along that normal, so a smaller cost means a straighter wire. A principal-to-principal wire is weighted up, so an active pair stays facing each other even if an auxiliary wire would prefer otherwise.
	const function orientationCost(
		c: Cell,
		idx: number
	): number
		const d = G.DIRS[idx + 1]
		local total = 0

		for slot = 1, Net.portCount(net.Tag[c]) do
			const p = Net.port(c, slot)
			const q = net.Link[p] or 0

			if q == 0 or Net.owner(q) == c then
				continue
			end

			const A = G.anchorOf(pos[c], d, net.Tag[c], slot)
			const B = point[q]
			const n = G.normalOf(d, slot)
			const dx, dy = G.unit(B.x - A.x, B.y - A.y, n.x, n.y)
			const weight =
				if slot == 1 and Net.isPrincipal(q) then
					3
				else
					1
			total += weight * (1 - (n.x * dx + n.y * dy))
		end

		return total
	end

	-- Swing each free cell through the four quarter turns and keep the cheapest.
	-- Ties keep the current direction, which keeps the result deterministic and stops it oscillating.
	const function chooseOrientation(
		c: Cell
	)
		local best = orientationCost(c, ori[c])
		local bestIdx = ori[c]

		for idx = 0, 3 do
			const cost = orientationCost(c, idx)

			if cost < best - 1e-9 then
				best = cost
				bestIdx = idx
		end end

		ori[c] = bestIdx
	end

	-- Swing every free cell to its cheapest quarter turn, refreshing the ports after each choice, and repeat to a fixed point.
	const function settleOrientations()
		for _ = 1, G.ORIENT_ITERS do
			computePorts()

			for _, c in cells do
				if not paired[c] then
					chooseOrientation(c)
					computePorts()
		end end end

		computePorts()
	end

	settleOrientations()

	-- How many pairs of wires cross, counted on the straight chords between their port anchors. The drawn wires leave along the port normals, so a chord crossing is a good enough signal for choosing between placements.
	const function chordCrossings(): number
		const segs: { { G.Vec } } = {}

		for _, c in cells do
			for slot = 1, Net.portCount(net.Tag[c]) do
				const p = Net.port(c, slot)
				const q = net.Link[p] or 0

				if q ~= 0 and p < q and Net.owner(q) ~= c then
					table.insert(
						segs, {
							point[p],
							point[q],
						}
					)
		end end end

		local count = 0

		for i = 1, #segs do
			for j = i + 1, #segs do
				const a, b = segs[i], segs[j]

				if G.segmentsCross(a[1].x, a[1].y, a[2].x, a[2].y, b[1].x, b[1].y, b[2].x, b[2].y) then
					count += 1
		end end end

		return count
	end

	-- Cells the wiring cannot tell apart can still land on the wrong sides of a shared partner, which puts their wires across each other. Swapping the positions of two such siblings untangles them without changing the drawing up to a renaming, so try each pair and keep a swap only when it strictly reduces the number of crossings.
	local crossings = chordCrossings()

	if crossings > 0 then
		const colors = Canon.refineKinds(net, cells)
		const wired: {
			[Cell]: {
				[Cell]: boolean,
			},
		} = {}

		for _, c in cells do
			wired[c] = {}
		end

		for _, c in cells do
			for slot = 1, Net.portCount(net.Tag[c]) do
				const q = net.Link[Net.port(c, slot)] or 0

				if q ~= 0 and Net.owner(q) ~= c then
					wired[c][Net.owner(q)] = true
					wired[Net.owner(q)][c] = true
		end end end

		const function siblings(
			u: Cell,
			v: Cell
		): boolean
			for w, _ in wired[u] do
				if wired[v][w] then
					return true
			end end

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
			end end end

			if not improved then
				break
	end end end

	return {
		net = net,
		cells = cells,
		pos = pos,
		ori = ori,
		point = point,
		out = out,
		tip = tip,
		e1 = e1,
		e2 = e2,
		hub = hub,
	}
end

return {
	orient = orient,
}
