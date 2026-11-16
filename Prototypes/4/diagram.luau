--!strict
-- SVG rendering of an interaction-combinator net, in the style of Lafont's paper: gamma/delta cells are triangles whose tip is the principal port; epsilon cells are circles; wires join ports; free ports are short dangling stubs.
--
-- The drawing is deliberately regular. Cells sit on a square grid at a fixed pitch, so neighbours are evenly spaced and never crowded. Each cell is turned in quarter turns only, so its ports always point along the grid axes. Branches that the wiring cannot tell apart are placed as mirror images, so a symmetric net is drawn symmetrically rather than lurching to one side. A wire leaves a port along the port's outward normal and curves to its partner; a curve that would cut through a cell body is routed around it, so a wire touches a cell only where it is attached, at its port. Cells joined at their principal ports (an active pair) face each other, so that wire is a straight step between the two tips. Parts of a net that share no wires are laid out on their own grids and packed a fixed distance apart.
--
-- The work is split between the modules in drawing/: geometry for shapes, layout for placing parts, orient for turning cells and fixing ports, and route for curves that go round cells.
--
--   const toSvg = require("./diagram")
--   print(toSvg(net))
--
-- `toSvg` only reads Net.Tag / Net.Link / Net.Free.

local G = require "./drawing/geometry"
local Layout = require "./drawing/layout"
local Orient = require "./drawing/orient"
local Route = require "./drawing/route"
local Net = require "./net"
local Types = require "./types"

type Symbol = Types.Symbol
type Net = Types.Net

const function colorOf(
	symbol: Symbol
): (string, string, string)
	if symbol == "Gamma" then
		return "#c8e6c9", "#2e7d32", "#1b5e20"
	elseif symbol == "Delta" then
		return "#bbdefb", "#1565c0", "#0d47a1"
	else
		return "#f8bbd0", "#c2185b", "#880e4f"
end end

const function labelOf(
	symbol: Symbol
): string
	if symbol == "Gamma" then
		return "γ"
	elseif symbol == "Delta" then
		return "δ"
	else
		return "ε"
end end

const function toSvg(
	net: Net
): string
	const cells = Net.liveCells(net)
	const pos = Layout.layout(net, cells)
	const scene = Orient.orient(net, cells, pos)
	const point, out, tip, e1, e2, hub = scene.point, scene.out, scene.tip, scene.e1, scene.e2, scene.hub
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge

	const function include(
		v: G.Vec
	)
		minX = math.min(minX, v.x)
		minY = math.min(minY, v.y)
		maxX = math.max(maxX, v.x)
		maxY = math.max(maxY, v.y)
	end

	for _, c in cells do
		if net.Tag[c] == "Epsilon" then
			const center = hub[c]
			include {
				x = center.x - G.CIRCLE_RADIUS - 2,
				y = center.y - G.CIRCLE_RADIUS - 2,
			}
			include {
				x = center.x + G.CIRCLE_RADIUS + 2,
				y = center.y + G.CIRCLE_RADIUS + 2,
			}
		else
			include(tip[c])
			include(e1[c])
			include(e2[c])
	end end

	const wireStyle = 'fill="none" stroke="#78909c" stroke-width="1.6" stroke-linecap="round"'
	const stubStyle = 'fill="none" stroke="#90a4ae" stroke-width="1.4" stroke-linecap="round"'
	const dotStyle = 'fill="#ffffff" stroke="#90a4ae" stroke-width="1.4"'
	const wires: { string } = {}
	const stubs: { string } = {}

	for _, c in cells do
		for slot = 1, Net.portCount(net.Tag[c]) do
			const p = Net.port(c, slot)
			const q = net.Link[p] or 0

			if q == 0 then
				const P, o = point[p], out[p]
				const E = {
					x = P.x + o.x * G.FREE_LEN,
					y = P.y + o.y * G.FREE_LEN,
				}
				include(E)
				stubs[#stubs + 1] = `<line x1="{G.fmt(P.x)}" y1="{G.fmt(P.y)}" x2="{G.fmt(E.x)}" y2="{G.fmt(E.y)}" {stubStyle}/>`
				stubs[#stubs + 1] = `<circle cx="{G.fmt(E.x)}" cy="{G.fmt(E.y)}" r="{G.STUB_RADIUS}" {dotStyle}/>`
			elseif p < q then
				const P, Q = point[p], point[q]

				if Net.owner(q) == c then
					const c1 = {
						x = P.x + out[p].x * G.LOOP_LEN,
						y = P.y + out[p].y * G.LOOP_LEN,
					}
					const c2 = {
						x = Q.x + out[q].x * G.LOOP_LEN,
						y = Q.y + out[q].y * G.LOOP_LEN,
					}
					include(c1)
					include(c2)
					wires[#wires + 1] = `<path d="M {G.fmt(P.x)} {G.fmt(P.y)} C {G.fmt(c1.x)} {G.fmt(c1.y)} {G.fmt(c2.x)} {G.fmt(c2.y)} {G.fmt(Q.x)} {G.fmt(Q.y)}" {wireStyle}/>`
				else
					-- The wire leaves each port along its normal and bends to the partner over one smooth curve. If that bend would cut through another cell it is routed around instead.
					const gap = math.max(0.01, math.sqrt((Q.x - P.x) ^ 2 + (Q.y - P.y) ^ 2))
					const k = math.min(gap * G.WIRE_BULGE, G.WIRE_BULGE_MAX)
					const c1 = {
						x = P.x + out[p].x * k,
						y = P.y + out[p].y * k,
					}
					const c2 = {
						x = Q.x + out[q].x * k,
						y = Q.y + out[q].y * k,
					}
					const detour =
						if Route.cubicHits(scene, P, c1, c2, Q, Net.owner(p), Net.owner(q)) then
							Route.route(scene, P, out[p], Q, out[q])
						else
							nil

					if detour then
						for _, v in detour do
							include(v)
						end

						wires[#wires + 1] = `<path d="{Route.roundedPath(detour)}" {wireStyle}/>`
					else
						include(c1)
						include(c2)
						wires[#wires + 1] = `<path d="M {G.fmt(P.x)} {G.fmt(P.y)} C {G.fmt(c1.x)} {G.fmt(c1.y)} {G.fmt(c2.x)} {G.fmt(c2.y)} {G.fmt(Q.x)} {G.fmt(Q.y)}" {wireStyle}/>`
	end end end end end

	const bodies: { string } = {}

	for _, c in cells do
		const fill, stroke, text = colorOf(net.Tag[c])

		if net.Tag[c] == "Epsilon" then
			const center = hub[c]
			bodies[#bodies + 1] = `<circle cx="{G.fmt(center.x)}" cy="{G.fmt(center.y)}" r="{G.CIRCLE_RADIUS}" fill="{fill}" stroke="{stroke}" stroke-width="1.6"/>`
		else
			bodies[#bodies + 1] = `<polygon points="{G.fmt(tip[c].x)},{G.fmt(tip[c].y)} {G.fmt(e1[c].x)},{G.fmt(e1[c].y)} {G.fmt(e2[c].x)},{G.fmt(e2[c].y)}" fill="{fill}" stroke="{stroke}" stroke-width="1.6" stroke-linejoin="round"/>`
		end

		bodies[#bodies + 1] = `<text x="{G.fmt(pos[c].x)}" y="{G.fmt(pos[c].y)}" font-size="13" font-weight="600" fill="{text}" text-anchor="middle" dominant-baseline="central">{labelOf(net.Tag[c])}</text>`
	end

	local x, y = minX - G.MARGIN, minY - G.MARGIN
	local w, h = maxX - minX + 2 * G.MARGIN, maxY - minY + 2 * G.MARGIN

	if #cells == 0 then
		x, y, w, h = 0, 0, 160, 80
	end

	const pieces = {
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="{G.fmt(x)} {G.fmt(y)} {G.fmt(w)} {G.fmt(h)}" width="{G.fmt(w)}" height="{G.fmt(h)}" font-family="system-ui, sans-serif">`,
		`<rect x="{G.fmt(x)}" y="{G.fmt(y)}" width="{G.fmt(w)}" height="{G.fmt(h)}" />`,
	}

	for _, group in {
		wires,
		stubs,
		bodies,
	} do
		const joined = table.concat(group, "\n")

		if joined ~= "" then
			pieces[#pieces + 1] = joined
	end end

	pieces[#pieces + 1] = "</svg>"

	return table.concat(pieces, "\n")
end

return toSvg
