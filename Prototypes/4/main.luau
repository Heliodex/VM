--!strict
-- PROTOTYPE BASED ON INTERACTION COMBINATORS
--
-- Drives the engine in net.luau over the nets below and prints the whole reduction of each one as a page of SVG diagrams.
-- The nets themselves are built with builder.luau, which is also how anything above the calculus would build one.

const B = require "./builder"
const toSvg = require "./diagram"
const H = require "./harness"
const Net = require "./net"
const Types = require "./types"

type Net = Types.Net
type Builder = B.Builder
const step = Net.step
const wellFormed = Net.wellFormed
const isomorphic = Net.isomorphic
-- tests -----------------------------------------------------------------------
-- A net is described by a function that builds one into a builder it is handed.
-- The harness owns the builder and finishes it, so a test never has to say where its net begins or ends and can simply end at its last wire.
-- Free ports are whatever was left unwired, and are where the answer of a reduction is expected to show up.
type Build = (Builder) -> ()

const function build(
	f: Build
): Net
	local b = B.new()
	f(b)

	return b:finish()
end

type Test = {
	read name: string,
	read start: Build,
	read expect: Build?,
	read budget: number?,
}
-- nil means the reduction is expected not to finish
const tests: { Test } = {
	{
		name = "epsilon-epsilon annihilates to nothing",
		start = function(b)
			local e1, e2 = b:epsilon(), b:epsilon()
			b:meet(e1, e2)
		end,
		expect = function() end,
	},
	{
		name = "gamma-gamma exchanges its wires",
		start = function(b)
			local g1, g2 = b:gamma(), b:gamma()
			local d1, d2, d3, d4 = b:delta(), b:delta(), b:delta(), b:delta()
			b:meet(g1, g2)
			b:wire(g1.aux1, d1.aux1)
			b:wire(g1.aux2, d2.aux1)
			b:wire(g2.aux1, d3.aux1)
			b:wire(g2.aux2, d4.aux1)
		end,
		-- the crossed pairs become the deltas' own auxiliaries
		expect = function(b)
			local d1, d2, d3, d4 = b:delta(), b:delta(), b:delta(), b:delta()
			b:wire(d1.aux1, d4.aux1)
			b:wire(d2.aux1, d3.aux1)
		end,
	},
	{
		name = "delta-delta is straight",
		start = function(b)
			local d1, d2 = b:delta(), b:delta()
			local g1, g2, g3, g4 = b:gamma(), b:gamma(), b:gamma(), b:gamma()
			b:meet(d1, d2)
			b:wire(d1.aux1, g1.aux1)
			b:wire(d1.aux2, g2.aux1)
			b:wire(d2.aux1, g3.aux1)
			b:wire(d2.aux2, g4.aux1)
		end,
		expect = function(b)
			local g1, g2, g3, g4 = b:gamma(), b:gamma(), b:gamma(), b:gamma()
			b:wire(g1.aux1, g3.aux1)
			b:wire(g2.aux1, g4.aux1)
		end,
	},
	{
		name = "gamma-erase spawns one eraser per auxiliary",
		start = function(b)
			local g = b:gamma()
			local d1, d2 = b:delta(), b:delta()
			local e = b:epsilon()
			b:meet(g, e)
			b:wire(g.aux1, d1.aux1)
			b:wire(g.aux2, d2.aux1)
		end,
		expect = function(b)
			local d1, d2 = b:delta(), b:delta()
			local e1, e2 = b:epsilon(), b:epsilon()
			b:wire(d1.aux1, e1.principal)
			b:wire(d2.aux1, e2.principal)
		end,
	},
	{
		name = "gamma meets delta in the commutation square",
		start = function(b)
			local g, d = b:gamma(), b:delta()
			b:meet(g, d)
		end,
		expect = function(b)
			local d1, d2 = b:delta(), b:delta()
			local g1, g2 = b:gamma(), b:gamma()
			b:wire(d1.aux2, g1.aux1)
			b:wire(d1.aux1, g2.aux1)
			b:wire(d2.aux2, g1.aux2)
			b:wire(d2.aux1, g2.aux2)
		end,
	},
	{
		name = "a gamma erased on every port vanishes completely",
		start = function(b)
			local g = b:gamma()
			local e1, e2, e3 = b:epsilon(), b:epsilon(), b:epsilon()
			b:meet(g, e1)
			b:wire(g.aux1, e2.principal)
			b:wire(g.aux2, e3.principal)
		end,
		expect = function() end,
	},
	{
		name = "delta(epsilon, x) = gamma(x, epsilon)",
		start = function(b)
			local d, g = b:delta(), b:gamma()
			local e1, e2 = b:epsilon(), b:epsilon()
			b:meet(d, g)
			b:wire(d.aux1, e1.principal)
			b:wire(d.aux2, g.aux1)
			b:wire(g.aux2, e2.principal)
		end,
		expect = nil, -- does not terminate
		budget = 200,
	},
}
-- runner ----------------------------------------------------------------------
print '<!doctype html>\n<html lang="en-GB">\n<head>\n<meta charset="utf-8">\n<title>Interaction Combinator reductions</title>\n<style>\n  body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 1100px; background: black; color: white; }\n  h1 { font-size: 1.4rem; }\n  h2 { font-size: 1.05rem; margin: 0 0 0.75rem; }\n  section { border-top: 1px solid #ddd; padding: 1.5rem 0; }\n  figure { margin: 0 0 1rem; }\n  figcaption { font-size: 0.75rem; color: #ccc; margin-top: 0.2rem; }\n  svg { max-width: 100%; height: auto; border: 1px solid #eee; background: #111; }\n  .pass { color: #2e7d32; font-weight: 600; }\n  .fail { color: #c62828; font-weight: 600; }\n  .note { color: #ccc; font-style: italic; }\n</style>\n</head>\n<body>\n<h1>Interaction Combinator reductions</h1>'
const MAX_STEPS_SHOWN = 60

for _, test in tests do
	const limit = test.budget or H.DEFAULT_BUDGET
	-- Reduce first (no SVG): find out how many steps it takes and how the reduction ended. Only then decide which diagrams to draw, so the (expensive) layout is never paid for steps that will be omitted.
	const net = build(test.start)
	const report = H.reduce(net, limit)
	const steps = report.steps
	const finished = report.outcome == "reduced"

	print "<section>"
	print(`<h2>{test.name}</h2>`)
	print(`<figure>{toSvg(build(test.start))}<figcaption>start</figcaption></figure>`)

	if finished and steps <= MAX_STEPS_SHOWN then
		-- replay the reduction, drawing each step
		local walk = build(test.start)

		for i = 1, steps do
			step(walk)
			print(
				`<figure>{toSvg(walk)}<figcaption>after {i} step{
					if i == 1 then
						""
					else
						"s"
				}</figcaption></figure>`
			)
		end
	elseif finished then
		print(`<p class="note">{steps} steps omitted: more than the {MAX_STEPS_SHOWN}-step display limit.</p>`)
	else
		print(`<p class="note">Reduction {H.describe(report)}; steps omitted.</p>`)
	end

	const ok =
		if test.expect then
			finished and wellFormed(net) and isomorphic(net, build(test.expect))
		else
			not finished and wellFormed(net)
	print(
		if ok then
			'<p class="pass">PASS</p>'
		else
			'<p class="fail">FAIL</p>'
	)
	print "</section>"

	if not ok then
		error "fail"
end end

print "</body></html>"
