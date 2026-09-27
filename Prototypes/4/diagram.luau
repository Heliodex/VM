--!strict
-- SVG rendering of an interaction-combinator net, in the style of Lafont's
-- paper: gamma/delta cells are triangles whose tip is the principal port, drawn
-- pointing along the wire attached to it; epsilon cells are circles; wires are
-- curves; free ports are short dangling stubs.
--
-- Cells are laid out to keep wired ports near each other, and a wire leaves its
-- port aimed at the partner. When the body of a cell lies between a port and its
-- partner the wire leaves tangentially instead of reversing, so it never doubles
-- back on itself immediately after leaving the cell. Each cell also picks its
-- own tip direction to minimise the total bending of its wires, so cells of the
-- same type are free to face different ways when their wiring differs. Finally,
-- parts of a net that share no wires are laid out separately and packed into
-- their own boxes, so their wires cannot cross and they stay a sensible
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

-- Fruchterman-Reingold on one connected part: repulsion between every pair of
-- cells, springs along the wires. Deterministic (starts on a circle), so a
-- given part always draws the same way.
const function layoutPart(net: Net, cells: { Cell }): { [Cell]: Vec }
	const n = #cells
	const pos: { [Cell]: Vec } = {}
	if n == 1 then
		pos[cells[1]] = { x = 0, y = 0 }
		return pos
	end

	const W, H = 640, 640
	-- Cap the natural FR spacing so small parts do not drift apart into huge,
	-- mostly-empty drawings. Larger parts still spread out to fill the area.
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

-- Room reserved around a part for cell bodies and the bulge of its wires. The
-- proportional term keeps large parts from having their wires spill into a
-- neighbour, while lone cells stay tight.
const PART_MARGIN = 36
const PART_MARGIN_SCALE = 0.2
const PART_GAP = 26

type PartBox = {
	pos: { [Cell]: Vec },
	minX: number,
	minY: number,
	w: number,
	h: number,
	margin: number,
}

-- Lay out every part on its own, then pack the parts into rows sized to keep
-- the whole drawing roughly square. Each part keeps its own box, so the wires
-- of one part cannot cross the wires of another, and neighbouring parts stay a
-- fixed, modest distance apart instead of drifting off to opposite corners.
const function layout(net: Net, cells: { Cell }): { [Cell]: Vec }
	if #cells == 0 then
		return {}
	end
	const parts = components(net, cells)
	if #parts == 1 then
		return layoutPart(net, cells)
	end

	const boxes: { PartBox } = {}
	local area = 0
	local widest = 0
	for _, part in parts do
		const pos = layoutPart(net, part)
		local minX, minY = math.huge, math.huge
		local maxX, maxY = -math.huge, -math.huge
		for _, c in part do
			minX = math.min(minX, pos[c].x)
			minY = math.min(minY, pos[c].y)
			maxX = math.max(maxX, pos[c].x)
			maxY = math.max(maxY, pos[c].y)
		end
		const w = maxX - minX
		const h = maxY - minY
		const margin = PART_MARGIN + PART_MARGIN_SCALE * math.max(w, h)
		area += (w + 2 * margin) * (h + 2 * margin)
		widest = math.max(widest, w + 2 * margin)
		table.insert(boxes, {
			pos = pos,
			minX = minX,
			minY = minY,
			w = w,
			h = h,
			margin = margin,
		})
	end
	const targetScale = math.sqrt(area)
	const placed: { [Cell]: Vec } = {}
	const function packBoxes(target: number, apply: boolean): (number, number)
		local x, y, rowH = 0, 0, 0
		local maxX, maxY = 0, 0
		for _, b in boxes do
			const bw = b.w + 2 * b.margin
			const bh = b.h + 2 * b.margin
			if x > 0 and x + bw > target then
				x = 0
				y += rowH + PART_GAP
				rowH = 0
			end
			if apply then
				const ox = x + b.margin - b.minX
				const oy = y + b.margin - b.minY
				for c, v in b.pos do
					placed[c] = { x = v.x + ox, y = v.y + oy }
				end
			end
			maxX = math.max(maxX, x + bw)
			maxY = math.max(maxY, y + bh)
			x += bw + PART_GAP
			rowH = math.max(rowH, bh)
		end
		return maxX, maxY
	end

	-- Try several widths and keep the one whose pack is closest to square, so
	-- two parts sit side by side when that is more compact and many parts form a
	-- tidy grid rather than one long column.
	local bestTarget = widest + PART_GAP
	local bestScore = math.huge
	for _, scale in { 0.9, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4 } do
		const target = math.max(widest, targetScale * scale) + PART_GAP
		const maxX, maxY = packBoxes(target, false)
		const score = math.max(maxX, maxY)
		if score < bestScore then
			bestScore = score
			bestTarget = target
		end
	end
	packBoxes(bestTarget, true)
	return placed
end

-- geometry --------------------------------------------------------------------

const TIP_LEN = 20 -- centre -> principal tip
const BASE_LEN = 14 -- centre -> base edge
const HALF_WIDTH = 16 -- half the base edge length
const CIRCLE_RADIUS = 14 -- epsilon radius
const FREE_LEN = 18 -- length of a free-port stub
const STUB_RADIUS = 3.5
const WIRE_TENSION = 0.32 -- how far a wire bulges along the port normal
const WIRE_TENSION_MAX = 90 -- cap on that bulge, so wraps stay tight
const LEAVE_BIAS = 0.3 -- lift wires skimming a cell edge a little off the body
const LOOP_LEN = 26
const MARGIN = 28
const ORIENT_ITERS = 8
const ORIENT_SAMPLES = 72 -- candidate directions tried per cell (5 degrees apart)

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

-- Which way a wire should leave a port. Normally that is straight at the
-- partner, but a port whose body lies between it and the partner must leave
-- tangentially instead. Clamping the desired direction to the outward half-plane
-- turns what would be an immediate 180-degree hairpin into at worst a smooth
-- quarter turn, while the small outward bias keeps the wire from hugging the
-- cell's edge.
const function leaveTangent(n: Vec, P: Vec, Q: Vec): Vec
	const dx, dy = unit(Q.x - P.x, Q.y - P.y, n.x, n.y)
	const dn = dx * n.x + dy * n.y
	if dn >= 0 then
		return { x = dx, y = dy }
	end
	const tx, ty = unit(dx - dn * n.x, dy - dn * n.y, -n.y, n.x)
	const bx, by = unit(
		tx + n.x * LEAVE_BIAS,
		ty + n.y * LEAVE_BIAS,
		tx,
		ty
	)
	return { x = bx, y = by }
end

-- Where a cell's principal port wants to point: at the partner of its principal
-- wire, or away from the centre when that wire is free.
const function principalTarget(
	net: Net,
	c: Cell,
	pos: { [Cell]: Vec },
	centroid: Vec
): (number, number)
	const q = net.Link[portOf(c, 1)] or 0
	if q ~= 0 and owner(q) ~= c then
		return pos[owner(q)].x, pos[owner(q)].y
	end
	return pos[c].x - centroid.x, pos[c].y - centroid.y
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

	-- u[c] is the unit direction of cell c's principal port (the tip). Port
	-- positions depend on the orientations and vice-versa, so iterate to a
	-- fixed point: each cell aims its tip at the partner of its principal wire.
	const ux: { [Cell]: number } = {}
	const uy: { [Cell]: number } = {}
	for _, c in cells do
		const tx, ty = principalTarget(net, c, pos, centroid)
		ux[c], uy[c] = unit(tx - pos[c].x, ty - pos[c].y, 0, 1)
	end

	local point: { [Port]: Vec } = {} -- where a wire meets the cell
	local out: { [Port]: Vec } = {} -- outward normal: wires leave along this
	local tan: { [Port]: Vec } = {} -- actual leave direction for a wired port
	local tip: { [Cell]: Vec } = {}
	local e1: { [Cell]: Vec } = {}
	local e2: { [Cell]: Vec } = {}
	local hub: { [Cell]: Vec } = {}

	const function computePorts()
		point, out, tip, e1, e2, hub = {}, {}, {}, {}, {}, {}
		for _, c in cells do
			const center = pos[c]
			const u = { x = ux[c], y = uy[c] }
			if net.Tag[c] == "Epsilon" then
				hub[c] = center
				point[portOf(c, 1)] = {
					x = center.x + u.x * CIRCLE_RADIUS,
					y = center.y + u.y * CIRCLE_RADIUS,
				}
				out[portOf(c, 1)] = u
			else
				const n = { x = -u.y, y = u.x }
				tip[c] = {
					x = center.x + u.x * TIP_LEN,
					y = center.y + u.y * TIP_LEN,
				}
				e1[c] = {
					x = center.x - u.x * BASE_LEN + n.x * HALF_WIDTH,
					y = center.y - u.y * BASE_LEN + n.y * HALF_WIDTH,
				}
				e2[c] = {
					x = center.x - u.x * BASE_LEN - n.x * HALF_WIDTH,
					y = center.y - u.y * BASE_LEN - n.y * HALF_WIDTH,
				}
				point[portOf(c, 1)] = tip[c]
				out[portOf(c, 1)] = u
				-- auxiliary ports sit on the base edge, opposite the tip
				point[portOf(c, 2)] = place(e1[c], e2[c], 1 / 3)
				point[portOf(c, 3)] = place(e1[c], e2[c], 2 / 3)
				out[portOf(c, 2)] = { x = -u.x, y = -u.y }
				out[portOf(c, 3)] = { x = -u.x, y = -u.y }
			end
		end
	end

	-- Cost of orienting a cell along u, using the leave rules its wires will
	-- actually use. The principal wire leaves along the tip, so its bend is the
	-- angle to its partner; auxiliary wires leave adaptively, so a partner in
	-- front of the base costs at most a quarter turn. Minimising the total lets
	-- each cell swing to whichever direction best serves all of its wires,
	-- rather than always facing its principal partner.
	const function orientationCost(c: Cell, u: Vec): number
		const center = pos[c]
		local anchors: { Vec }
		local normals: { Vec }
		if net.Tag[c] == "Epsilon" then
			anchors = {{
				x = center.x + u.x * CIRCLE_RADIUS,
				y = center.y + u.y * CIRCLE_RADIUS,
			}}
			normals = { u }
		else
			const n = { x = -u.y, y = u.x }
			const neg = { x = -u.x, y = -u.y }
			const tip = {
				x = center.x + u.x * TIP_LEN,
				y = center.y + u.y * TIP_LEN,
			}
			const a = {
				x = center.x - u.x * BASE_LEN + n.x * HALF_WIDTH,
				y = center.y - u.y * BASE_LEN + n.y * HALF_WIDTH,
			}
			const b = {
				x = center.x - u.x * BASE_LEN - n.x * HALF_WIDTH,
				y = center.y - u.y * BASE_LEN - n.y * HALF_WIDTH,
			}
			anchors = { tip, place(a, b, 1 / 3), place(a, b, 2 / 3) }
			normals = { u, neg, neg }
		end

		local total = 0
		for slot = 1, #anchors do
			const p = portOf(c, slot)
			const q = net.Link[p] or 0
			if q == 0 or owner(q) == c then
				continue
			end
			const A = anchors[slot]
			const B = point[q]
			const nrm = normals[slot]
			const dx, dy = unit(B.x - A.x, B.y - A.y, nrm.x, nrm.y)
			local t
			if slot == 1 then
				t = nrm
			else
				t = leaveTangent(nrm, A, B)
			end
			total += 1 - (t.x * dx + t.y * dy)
		end
		return total
	end

	-- Swing each cell through a fixed set of candidate directions and keep the
	-- cheapest. This runs Gauss-Seidel: the ports are refreshed after each cell,
	-- so later cells see the choices made so far. Ties keep the current
	-- direction, which keeps the result deterministic and stops it oscillating.
	const function chooseOrientation(c: Cell)
		local bx, by = ux[c], uy[c]
		local best = orientationCost(c, { x = bx, y = by })
		for k = 0, ORIENT_SAMPLES - 1 do
			const angle = 2 * math.pi * k / ORIENT_SAMPLES
			const u = { x = math.cos(angle), y = math.sin(angle) }
			const cost = orientationCost(c, u)
			if cost < best - 1e-6 then
				best = cost
				bx, by = u.x, u.y
			end
		end
		ux[c], uy[c] = bx, by
	end

	for _ = 1, ORIENT_ITERS do
		computePorts()
		for _, c in cells do
			chooseOrientation(c)
			computePorts()
		end
	end
	computePorts()

	-- The tip always points along its own wire, so the principal port keeps its
	-- normal. Auxiliary ports have no such constraint: let their wires leave
	-- towards their partner, avoiding a hairpin around the base of the triangle.
	const function computeTangents()
		tan = {}
		for _, c in cells do
			for slot = 1, arity(net.Tag[c]) + 1 do
				const p = portOf(c, slot)
				tan[p] = out[p]
			end
		end
		for _, c in cells do
			if arity(net.Tag[c]) == 2 then
				for slot = 2, 3 do
					const p = portOf(c, slot)
					const q = net.Link[p] or 0
					if q ~= 0 and owner(q) ~= c then
						tan[p] = leaveTangent(out[p], point[p], point[q])
					end
				end
			end
		end
	end
	computeTangents()

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
				local c1, c2
				if owner(q) == c then
					c1 = {
						x = P.x + out[p].x * LOOP_LEN,
						y = P.y + out[p].y * LOOP_LEN,
					}
					c2 = {
						x = Q.x + out[q].x * LOOP_LEN,
						y = Q.y + out[q].y * LOOP_LEN,
					}
				else
					const d = math.max(
						0.01,
						math.sqrt((Q.x - P.x) ^ 2 + (Q.y - P.y) ^ 2)
					)
					const k = math.min(d * WIRE_TENSION, WIRE_TENSION_MAX)
					c1 = { x = P.x + tan[p].x * k, y = P.y + tan[p].y * k }
					c2 = { x = Q.x + tan[q].x * k, y = Q.y + tan[q].y * k }
				end
				include(c1)
				include(c2)
				wires[#wires + 1] = `<path d="M {fmt(P.x)} {fmt(P.y)} C {fmt(
					c1.x
				)} {fmt(c1.y)} {fmt(c2.x)} {fmt(c2.y)} {fmt(Q.x)} {fmt(Q.y)}" {wireStyle}/>`
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
