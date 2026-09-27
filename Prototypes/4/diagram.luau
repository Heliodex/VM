--!strict
-- SVG rendering of an interaction-combinator net, in the style of Lafont's
-- paper: every cell is a triangle whose tip is its principal port, wires are
-- drawn as curves, and free ports are short dangling stubs.
--
--   local toSvg = require("./diagram")
--   print(toSvg(net))
--
-- `toSvg` only reads Net.Tag / Net.Link / Net.Free, so it accepts the Net built
-- by main.luau without needing to import it.

const Types = require("./types")

type Cell = Types.Cell
type Port = Types.Port
type Symbol = Types.Symbol
type Net = Types.Net
type Vec = { x: number, y: number }

local STRIDE = 3

local function owner(p: Port): Cell
	return (p - 1) // STRIDE + 1
end
local function portOf(c: Cell, slot: number): Port
	return (c - 1) * STRIDE + slot
end
local function arity(symbol: Symbol): number
	return if symbol == "Epsilon" then 0 else 2
end
local function liveCells(net: Net): { Cell }
	local freed: { [Cell]: boolean } = {}
	for _, c in net.Free do
		freed[c] = true
	end
	local live = {}
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
local function layout(net: Net, cells: { Cell }): { [Cell]: Vec }
	local n = #cells
	local pos: { [Cell]: Vec } = {}
	if n == 0 then
		return pos
	end
	if n == 1 then
		pos[cells[1]] = { x = 0, y = 0 }
		return pos
	end

	local W, H = 640, 640
	local k = 0.85 * math.sqrt((W * H) / n)
	local temp = W / 8
	local radius = 34 * math.sqrt(n)
	for i, c in cells do
		local angle = 2 * math.pi * (i - 1) / n
		pos[c] = { x = radius * math.cos(angle), y = radius * math.sin(angle) }
	end

	local disp: { [Cell]: Vec } = {}
	for _ = 1, 300 do
		for _, c in cells do
			disp[c] = { x = 0, y = 0 }
		end

		for i = 1, n do
			for j = i + 1, n do
				local a, b = cells[i], cells[j]
				local dx, dy = pos[a].x - pos[b].x, pos[a].y - pos[b].y
				local d = math.sqrt(dx * dx + dy * dy)
				if d < 0.01 then
					dx, dy, d = 0.01, 0, 0.01
				end
				local force = (k * k) / d
				local ux, uy = dx / d, dy / d
				disp[a].x += ux * force
				disp[a].y += uy * force
				disp[b].x -= ux * force
				disp[b].y -= uy * force
			end
		end

		for _, c in cells do
			for slot = 1, arity(net.Tag[c]) + 1 do
				local p = portOf(c, slot)
				local q = net.Link[p] or 0
				if q ~= 0 and p < q then
					local a, b = owner(p), owner(q)
					if a ~= b then
						local dx, dy = pos[a].x - pos[b].x, pos[a].y - pos[b].y
						local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
						local force = (d * d) / k
						local ux, uy = dx / d, dy / d
						disp[a].x -= ux * force
						disp[a].y -= uy * force
						disp[b].x += ux * force
						disp[b].y += uy * force
					end
				end
			end
		end

		for _, c in cells do
			local dx, dy = disp[c].x, disp[c].y
			local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
			local step = math.min(d, temp)
			pos[c].x += dx / d * step
			pos[c].y += dy / d * step
			local pad = 60
			pos[c].x = math.max(-W / 2 + pad, math.min(W / 2 - pad, pos[c].x))
			pos[c].y = math.max(-H / 2 + pad, math.min(H / 2 - pad, pos[c].y))
		end
		temp *= 0.95
	end
	return pos
end

-- geometry --------------------------------------------------------------------

local TIP_LEN = 20
local BASE_LEN = 14
local HALF_WIDTH = 16
local FREE_LEN = 18
local STUB_RADIUS = 3.5
local WIRE_BOW = 0.12
local LOOP_LEN = 30
local MARGIN = 28

local function fmt(v: number): string
	return string.format("%.1f", v)
end

local function colorOf(symbol: Symbol): (string, string, string)
	if symbol == "Gamma" then
		return "#c8e6c9", "#2e7d32", "#1b5e20"
	elseif symbol == "Delta" then
		return "#bbdefb", "#1565c0", "#0d47a1"
	else
		return "#f8bbd0", "#c2185b", "#880e4f"
	end
end

local function labelOf(symbol: Symbol): string
	if symbol == "Gamma" then
		return "γ"
	elseif symbol == "Delta" then
		return "δ"
	else
		return "ε"
	end
end

-- The triangle points its tip at the partner of the principal port, so the tip
-- always marks (and faces) the principal wire.
local function orient(net: Net, c: Cell, pos: { [Cell]: Vec }, centroid: Vec): (Vec, Vec, Vec)
	local q = net.Link[portOf(c, 1)] or 0
	local target: Vec
	if q ~= 0 and owner(q) ~= c then
		target = pos[owner(q)]
	else
		target = { x = pos[c].x - centroid.x, y = pos[c].y - centroid.y }
		if math.abs(target.x) < 0.01 and math.abs(target.y) < 0.01 then
			target = { x = 0, y = 1 }
		end
	end
	local dx, dy = target.x - pos[c].x, target.y - pos[c].y
	local d = math.sqrt(dx * dx + dy * dy)
	if d < 0.01 then
		dx, dy, d = 0, 1, 1
	end
	local ux, uy = dx / d, dy / d
	local nx, ny = -uy, ux
	return {
		x = pos[c].x + ux * TIP_LEN,
		y = pos[c].y + uy * TIP_LEN,
	}, {
		x = pos[c].x - ux * BASE_LEN + nx * HALF_WIDTH,
		y = pos[c].y - uy * BASE_LEN + ny * HALF_WIDTH,
	}, {
		x = pos[c].x - ux * BASE_LEN - nx * HALF_WIDTH,
		y = pos[c].y - uy * BASE_LEN - ny * HALF_WIDTH,
	}
end

-- render ----------------------------------------------------------------------

local function toSvg(net: Net): string
	local cells = liveCells(net)
	local pos = layout(net, cells)

	local centroid: Vec = { x = 0, y = 0 }
	for _, c in cells do
		centroid.x += pos[c].x
		centroid.y += pos[c].y
	end
	if #cells > 0 then
		centroid.x /= #cells
		centroid.y /= #cells
	end

	local tip: { [Cell]: Vec } = {}
	local base1: { [Cell]: Vec } = {}
	local base2: { [Cell]: Vec } = {}
	local point: { [Port]: Vec } = {}
	for _, c in cells do
		local t, u, v = orient(net, c, pos, centroid)
		tip[c], base1[c], base2[c] = t, u, v
		point[portOf(c, 1)] = t
		if arity(net.Tag[c]) >= 1 then
			point[portOf(c, 2)] = u
		end
		if arity(net.Tag[c]) >= 2 then
			point[portOf(c, 3)] = v
		end
	end

	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local function include(v: Vec)
		minX = math.min(minX, v.x)
		minY = math.min(minY, v.y)
		maxX = math.max(maxX, v.x)
		maxY = math.max(maxY, v.y)
	end
	for _, c in cells do
		include(tip[c])
		include(base1[c])
		include(base2[c])
	end

	local wireStyle = 'fill="none" stroke="#78909c" stroke-width="1.6" stroke-linecap="round"'
	local stubStyle = 'fill="none" stroke="#90a4ae" stroke-width="1.4" stroke-linecap="round"'
	local dotStyle = 'fill="#ffffff" stroke="#90a4ae" stroke-width="1.4"'

	local wires: { string } = {}
	local stubs: { string } = {}
	for _, c in cells do
		for slot = 1, arity(net.Tag[c]) + 1 do
			local p = portOf(c, slot)
			local q = net.Link[p] or 0
			if q == 0 then
				local P = point[p]
				local ox, oy = P.x - pos[c].x, P.y - pos[c].y
				local od = math.max(0.01, math.sqrt(ox * ox + oy * oy))
				local E = { x = P.x + ox / od * FREE_LEN, y = P.y + oy / od * FREE_LEN }
				include(E)
				stubs[#stubs + 1] =
					`<line x1="{fmt(P.x)}" y1="{fmt(P.y)}" x2="{fmt(E.x)}" y2="{fmt(E.y)}" {stubStyle}/>`
				stubs[#stubs + 1] =
					`<circle cx="{fmt(E.x)}" cy="{fmt(E.y)}" r="{STUB_RADIUS}" {dotStyle}/>`
			elseif p < q then
				local P, Q = point[p], point[q]
				if owner(q) == c then
					local mx, my = (P.x + Q.x) / 2, (P.y + Q.y) / 2
					local ox, oy = mx - pos[c].x, my - pos[c].y
					local od = math.max(0.01, math.sqrt(ox * ox + oy * oy))
					local c1 = { x = P.x + ox / od * LOOP_LEN, y = P.y + oy / od * LOOP_LEN }
					local c2 = { x = Q.x + ox / od * LOOP_LEN, y = Q.y + oy / od * LOOP_LEN }
					include(c1)
					include(c2)
					wires[#wires + 1] =
						`<path d="M {fmt(P.x)} {fmt(P.y)} C {fmt(c1.x)} {fmt(c1.y)} {fmt(c2.x)} {fmt(c2.y)} {fmt(Q.x)} {fmt(Q.y)}" {wireStyle}/>`
				else
					local dx, dy = Q.x - P.x, Q.y - P.y
					local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
					local px, py = -dy / d, dx / d
					local mx, my = (P.x + Q.x) / 2, (P.y + Q.y) / 2
					local side = if px * (mx - centroid.x) + py * (my - centroid.y) >= 0 then 1 else -1
					local cx, cy = mx + px * side * d * WIRE_BOW, my + py * side * d * WIRE_BOW
					include({ x = cx, y = cy })
					wires[#wires + 1] =
						`<path d="M {fmt(P.x)} {fmt(P.y)} Q {fmt(cx)} {fmt(cy)} {fmt(Q.x)} {fmt(Q.y)}" {wireStyle}/>`
				end
			end
		end
	end

	local bodies: { string } = {}
	for _, c in cells do
		local t, u, v = tip[c], base1[c], base2[c]
		local fill, stroke, text = colorOf(net.Tag[c])
		bodies[#bodies + 1] =
			`<polygon points="{fmt(t.x)},{fmt(t.y)} {fmt(u.x)},{fmt(u.y)} {fmt(v.x)},{fmt(v.y)}" fill="{fill}" stroke="{stroke}" stroke-width="1.6" stroke-linejoin="round"/>`
		bodies[#bodies + 1] =
			`<text x="{fmt(pos[c].x)}" y="{fmt(pos[c].y)}" font-size="13" font-weight="600" fill="{text}" text-anchor="middle" dominant-baseline="central">{labelOf(net.Tag[c])}</text>`
	end

	local x, y = minX - MARGIN, minY - MARGIN
	local w, h = (maxX - minX) + 2 * MARGIN, (maxY - minY) + 2 * MARGIN
	if #cells == 0 then
		x, y, w, h = 0, 0, 160, 80
	end

	local pieces = {
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="{fmt(x)} {fmt(y)} {fmt(w)} {fmt(h)}" width="{fmt(w)}" height="{fmt(h)}" font-family="system-ui, sans-serif">`,
		`<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" />`,
	}
	for _, group in { wires, stubs, bodies } do
		local joined = table.concat(group, "\n")
		if joined ~= "" then
			pieces[#pieces + 1] = joined
		end
	end
	pieces[#pieces + 1] = `</svg>`
	return table.concat(pieces, "\n")
end

return toSvg
