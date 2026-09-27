--!strict
-- SVG rendering of an interaction-combinator net, in the style of Lafont's
-- paper: gamma/delta cells are triangles whose tip is the principal port, drawn
-- pointing along the wire attached to it; epsilon cells are circles; wires are
-- curves; free ports are short dangling stubs.
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

-- Fruchterman-Reingold: repulsion between every pair of cells, springs along
-- the wires. Deterministic (starts on a circle), so a given net always draws
-- the same way.
const function layout(net: Net, cells: { Cell }): { [Cell]: Vec }
	const n = #cells
	const pos: { [Cell]: Vec } = {}
	if n == 0 then
		return pos
	end
	if n == 1 then
		pos[cells[1]] = { x = 0, y = 0 }
		return pos
	end

	const W, H = 640, 640
	const k = 0.85 * math.sqrt((W * H) / n)
	local temp = W / 8
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

-- geometry --------------------------------------------------------------------

const TIP_LEN = 20 -- centre -> principal tip
const BASE_LEN = 14 -- centre -> base edge
const HALF_WIDTH = 16 -- half the base edge length
const CIRCLE_RADIUS = 14 -- epsilon radius
const FREE_LEN = 18 -- length of a free-port stub
const STUB_RADIUS = 3.5
const WIRE_TENSION = 0.32 -- how far a wire bulges along the port normal
const LOOP_LEN = 26
const MARGIN = 28
const ORIENT_ITERS = 8

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

	for _ = 1, ORIENT_ITERS do
		computePorts()
		for _, c in cells do
			const tx, ty = principalTarget(net, c, pos, centroid)
			ux[c], uy[c] = unit(tx - pos[c].x, ty - pos[c].y, ux[c], uy[c])
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
					const k = d * WIRE_TENSION
					c1 = { x = P.x + out[p].x * k, y = P.y + out[p].y * k }
					c2 = { x = Q.x + out[q].x * k, y = Q.y + out[q].y * k }
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
