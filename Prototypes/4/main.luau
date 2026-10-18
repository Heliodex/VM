--!strict
-- PROTOTYPE BASED ON INTERACTION COMBINATORS
--
-- Drives the engine in net.luau over the nets below and prints the whole reduction of each one as a page of SVG diagrams.

const toSvg = require "./diagram"
const Net = require "./net"
const Types = require "./types"

type Gamma = Types.Gamma
type Delta = Types.Delta
type Epsilon = Types.Epsilon
type Symbol = Types.Symbol
type Cell = Types.Cell
type Port = Types.Port
type Net = Types.Net
const GAMMA = Net.GAMMA
const DELTA = Net.DELTA
const EPSILON = Net.EPSILON
const principal = Net.principal
const aux1 = Net.aux1
const aux2 = Net.aux2
const newNet = Net.newNet
const alloc = Net.alloc
const link = Net.link
const step = Net.step
const wellFormed = Net.wellFormed
const isomorphic = Net.isomorphic
-- test layer -----------------------------------------------------------------
-- A net for a test is written as a list of cells, each of the form
--   { symbol, label, label, ... }   -- principal port first, then auxiliaries
-- Ports that share a label are wired together; a label used on a single port is a free port. So { {GAMMA, "p", "a", "b"}, {GAMMA, "p", "c", "d"} } is two gammas joined at their principal ports with all four auxiliaries free.
type Spec = { { string } }

const function compile(
	spec: Spec
): Net
	const net = newNet()
	const endpoints: {
		[string]: { Port },
	} = {}

	for _, cell in spec do
		const c = alloc(net, cell[1] :: Symbol)
		const ports = {
			principal(c),
			aux1(c),
			aux2(c),
		}

		for i = 2, #cell do
			const label = cell[i]
			const group = endpoints[label]

			if group then
				table.insert(group, ports[i - 1])
			else
				endpoints[label] = {
					ports[i - 1],
				}
	end end end

	for label, group in endpoints do
		if #group == 2 then
			link(net, group[1], group[2])
		elseif #group > 2 then
			error(`label "{label}" is used {#group} times`)
	end end

	return net
end

-- tests -----------------------------------------------------------------------
type Test = {
	read name: string,
	read start: Spec,
	read expect: Spec?,
	read budget: number?,
}
-- nil means the reduction is expected not to finish
const tests: { Test } = {
	{
		name = "epsilon-epsilon annihilates to nothing",
		start = {
			{
				EPSILON,
				"p",
			},
			{
				EPSILON,
				"p",
			},
		},
		expect = {},
	},
	{
		name = "gamma-gamma exchanges its wires",
		start = {
			{
				GAMMA,
				"p",
				"a",
				"b",
			},
			{
				GAMMA,
				"p",
				"c",
				"d",
			},
			{
				DELTA,
				"e",
				"a",
				"f",
			},
			{
				DELTA,
				"g",
				"b",
				"h",
			},
			{
				DELTA,
				"i",
				"c",
				"j",
			},
			{
				DELTA,
				"k",
				"d",
				"l",
			},
		},
		expect = {
			{
				DELTA,
				"e",
				"ad",
				"f",
			},
			{
				DELTA,
				"g",
				"bc",
				"h",
			},
			{
				DELTA,
				"i",
				"bc",
				"j",
			},
			{
				DELTA,
				"k",
				"ad",
				"l",
			},
		},
	},
	{
		name = "delta-delta is straight",
		start = {
			{
				DELTA,
				"p",
				"a",
				"b",
			},
			{
				DELTA,
				"p",
				"c",
				"d",
			},
			{
				GAMMA,
				"e",
				"a",
				"f",
			},
			{
				GAMMA,
				"g",
				"b",
				"h",
			},
			{
				GAMMA,
				"i",
				"c",
				"j",
			},
			{
				GAMMA,
				"k",
				"d",
				"l",
			},
		},
		expect = {
			{
				GAMMA,
				"e",
				"ac",
				"f",
			},
			{
				GAMMA,
				"g",
				"bd",
				"h",
			},
			{
				GAMMA,
				"i",
				"ac",
				"j",
			},
			{
				GAMMA,
				"k",
				"bd",
				"l",
			},
		},
	},
	{
		name = "gamma-erase spawns one eraser per auxiliary",
		start = {
			{
				GAMMA,
				"p",
				"A",
				"B",
			},
			{
				DELTA,
				"u",
				"A",
				"v",
			},
			{
				DELTA,
				"w",
				"B",
				"x",
			},
			{
				EPSILON,
				"p",
			},
		},
		expect = {
			{
				DELTA,
				"u",
				"m",
				"v",
			},
			{
				DELTA,
				"w",
				"n",
				"x",
			},
			{
				EPSILON,
				"m",
			},
			{
				EPSILON,
				"n",
			},
		},
	},
	{
		name = "gamma meets delta in the commutation square",
		start = {
			{
				GAMMA,
				"p",
				"a",
				"b",
			},
			{
				DELTA,
				"p",
				"c",
				"d",
			},
		},
		expect = {
			{
				DELTA,
				"p1",
				"m2",
				"m1",
			},
			{
				DELTA,
				"p2",
				"m4",
				"m3",
			},
			{
				GAMMA,
				"p3",
				"m1",
				"m3",
			},
			{
				GAMMA,
				"p4",
				"m2",
				"m4",
			},
		},
	},
	{
		name = "a gamma erased on every port vanishes completely",
		start = {
			{
				GAMMA,
				"p",
				"A",
				"B",
			},
			{
				EPSILON,
				"p",
			},
			{
				EPSILON,
				"A",
			},
			{
				EPSILON,
				"B",
			},
		},
		expect = {},
	},
	{
		name = "delta(epsilon, x) = gamma(x, epsilon)",
		start = {
			{
				DELTA,
				"p",
				"e",
				"x",
			},
			{
				GAMMA,
				"p",
				"x",
				"f",
			},
			{
				EPSILON,
				"e",
			},
			{
				EPSILON,
				"f",
			},
		},
		expect = nil, -- does not terminate
		budget = 200,
	},
}
-- runner ----------------------------------------------------------------------
print '<!doctype html>\n<html lang="en-GB">\n<head>\n<meta charset="utf-8">\n<title>Interaction Combinator reductions</title>\n<style>\n  body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 1100px; background: black; color: white; }\n  h1 { font-size: 1.4rem; }\n  h2 { font-size: 1.05rem; margin: 0 0 0.75rem; }\n  section { border-top: 1px solid #ddd; padding: 1.5rem 0; }\n  figure { margin: 0 0 1rem; }\n  figcaption { font-size: 0.75rem; color: #ccc; margin-top: 0.2rem; }\n  svg { max-width: 100%; height: auto; border: 1px solid #eee; background: #111; }\n  .pass { color: #2e7d32; font-weight: 600; }\n  .fail { color: #c62828; font-weight: 600; }\n  .note { color: #ccc; font-style: italic; }\n</style>\n</head>\n<body>\n<h1>Interaction Combinator reductions</h1>'
const MAX_STEPS_SHOWN = 60

for _, test in tests do
	const limit = test.budget or 1000
	-- Reduce first (no SVG): find out how many steps it takes and whether it reaches a normal form. Only then decide which diagrams to draw, so the (expensive) layout is never paid for steps that will be omitted.
	const net = compile(test.start)
	local steps = 0
	local finished = false

	while steps < limit do
		if not step(net) then
			finished = true
			break
		end

		steps += 1
	end

	print "<section>"
	print(`<h2>{test.name}</h2>`)
	print(`<figure>{toSvg(compile(test.start))}<figcaption>start</figcaption></figure>`)

	if finished and steps <= MAX_STEPS_SHOWN then
		-- replay the reduction, drawing each step
		const walk = compile(test.start)

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
		print(`<p class="note">Reduction did not finish within the {limit}-step budget; steps omitted.</p>`)
	end

	const ok =
		if test.expect then
			finished and wellFormed(net) and isomorphic(net, compile(test.expect))
		else
			not finished and wellFormed(net)
	print(
		if ok then
			'<p class="pass">PASS</p>'
		else
			'<p class="fail">FAIL</p>'
	)
	print "</section>"
end

print "</body></html>"
