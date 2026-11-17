--!strict
-- SCREEN GEOMETRY FOR DIAGRAMS
--
-- The fixed sizes of a drawing and the plane geometry the layout and the router are built from: unit vectors, distances, crossings, quarter turns, and where a port sits on its cell.
-- Cells sit on a square grid of PITCH pixels and turn in quarter turns only, so every direction a cell can face is one of the four DIRS.

local Types = require "../../engine/types"

type Symbol = Types.Symbol
export type Vec = {
	x: number,
	y: number,
}
-- A position on the integer grid of cell slots, before it is scaled to pixels.
export type Grid = {
	x: number,
	y: number,
}
-- sizes --------------------------------------------------------------------
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
	{
		x = 1,
		y = 0,
	},
	{
		x = 0,
		y = 1,
	},
	{
		x = -1,
		y = 0,
	},
	{
		x = 0,
		y = -1,
	},
}

const function fmt(
	v: number
): string
	return string.format("%.1f", v)
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

-- Point a fraction t of the way from a to b.
const function lerp(
	a: Vec,
	b: Vec,
	t: number
): Vec
	return {
		x = a.x + (b.x - a.x) * t,
		y = a.y + (b.y - a.y) * t,
	}
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

	return (d1 > 0 and d2 < 0 or d1 < 0 and d2 > 0) and (d3 > 0 and d4 < 0 or d3 < 0 and d4 > 0)
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
const function dirToward(
	a: Vec,
	b: Vec
): number
	local best, bestDot = 0, -math.huge

	for i, d in DIRS do
		const dot = (b.x - a.x) * d.x + (b.y - a.y) * d.y

		if dot > bestDot then
			bestDot = dot
			best = i - 1
	end end

	return best
end

-- The quarter-turn index of a vector: 0 = +x, 1 = -x, 2 = +y, 3 = -y.
const function dirIndexOf(
	vx: number,
	vy: number
): number
	if math.abs(vx) >= math.abs(vy) then
		return
			if vx >= 0 then
				0
			else
				1
	end

	return
		if vy >= 0 then
			2
		else
			3
end

-- The position of a port, for a cell centred at `center` and turned to face `d`.
const function anchorOf(
	center: Vec,
	d: Vec,
	symbol: Symbol,
	slot: number
): Vec
	if symbol == "Epsilon" then
		return {
			x = center.x + d.x * CIRCLE_RADIUS,
			y = center.y + d.y * CIRCLE_RADIUS,
		}
	end

	if slot == 1 then
		return {
			x = center.x + d.x * TIP_LEN,
			y = center.y + d.y * TIP_LEN,
		}
	end

	const n = {
		x = -d.y,
		y = d.x,
	}
	const a = {
		x = center.x - d.x * BASE_LEN + n.x * HALF_WIDTH,
		y = center.y - d.y * BASE_LEN + n.y * HALF_WIDTH,
	}
	const b = {
		x = center.x - d.x * BASE_LEN - n.x * HALF_WIDTH,
		y = center.y - d.y * BASE_LEN - n.y * HALF_WIDTH,
	}

	return lerp(
		a, b, if slot == 2 then
			1 / 3
		else
			2 / 3
	)
end

-- The outward normal of a port: principal points along the tip, auxiliary ports point back out of the base.
const function normalOf(
	d: Vec,
	slot: number
): Vec
	if slot == 1 then
		return d
	end

	return {
		x = -d.x,
		y = -d.y,
	}
end

const function key(
	g: Grid
): string
	return `{g.x},{g.y}`
end

return {
	PITCH = PITCH,
	TIP_LEN = TIP_LEN,
	BASE_LEN = BASE_LEN,
	HALF_WIDTH = HALF_WIDTH,
	CIRCLE_RADIUS = CIRCLE_RADIUS,
	FREE_LEN = FREE_LEN,
	STUB_RADIUS = STUB_RADIUS,
	LOOP_LEN = LOOP_LEN,
	MARGIN = MARGIN,
	ORIENT_ITERS = ORIENT_ITERS,
	WIRE_BULGE = WIRE_BULGE,
	WIRE_BULGE_MAX = WIRE_BULGE_MAX,
	DIRS = DIRS,
	fmt = fmt,
	unit = unit,
	lerp = lerp,
	segDist = segDist,
	segmentsCross = segmentsCross,
	pointInTri = pointInTri,
	dirToward = dirToward,
	dirIndexOf = dirIndexOf,
	anchorOf = anchorOf,
	normalOf = normalOf,
	key = key,
}
