--!strict
-- OBSERVING A REDUCTION
--
-- net.luau says how a net changes one step at a time; this says what happened when you let one run.
-- The failure this file exists for is a net that never reaches a normal form, which is the ordinary failure here rather than an exotic one: the calculus is confluent but not strongly normalising, so a bad encoding loops quietly instead of erroring.
-- Without something like this, that loop spends a budget and reports nothing, which is indistinguishable from a slow computation.
--
--   local H = require "./harness"
--
--   local report = H.reduce(net, 1000)
--   if report.outcome ~= "reduced" then
--       error(H.describe(report))
--   end
--
-- Reduction is bounded by a step budget rather than by a timeout, so a run is reproducible.
-- Cycle detection costs one structural fingerprint per step and keeps a copy of the net for each distinct state it has seen, so it suits the small nets a gadget is tested with, not a long computation.
-- A cycle is only reported when `isomorphic` confirms the earlier net, so a repeat is never taken on the fingerprint alone.
-- That comparison covers the cells and the wiring but not the order of the active pairs still pending, so a reported cycle is evidence rather than proof; the state space is finite, which is what makes the evidence good.

local Net = require "./net"
local Types = require "./types"

type Net = Types.Net
type Cell = Types.Cell
type Symbol = Types.Symbol
-- How a reduction ended.
-- `reduced` reached a normal form, `exhausted` used its whole budget, and `cycled` was caught returning to a state it had already been in.
export type Outcome =
	| "reduced"
	| "exhausted"
	| "cycled"
export type Report = {
	read outcome: Outcome,
	read steps: number,
	read cells: number,
	read peakCells: number,
	read period: number?,
	read firstSeen: number?,
}
-- set only when the outcome is "cycled"
const DEFAULT_BUDGET = 1000
const MAX_TRACKED = 0x1000

-- The number of ports a symbol actually has, principal included.
const function slots(
	symbol: Symbol
): number
	return
		if symbol == Net.EPSILON then
			1
		else
			3
end

-- Which port of a cell a port id refers to, as it is written in a dump.
const function portName(
	p: Types.Port
): string
	return
		if (p - 1) % 3 == 0 then
			"P"
		elseif (p - 1) % 3 == 1 then
			"a1"
		else
			"a2"
end

-- A summary of a net that does not depend on how its cells happen to be numbered.
-- Colours start as symbols and are refined against the colours of whatever each port is wired to, so two nets that differ only by a renaming settle on the same summary.
-- This is not a canonical form: two different nets can share a summary, which is why a repeat is only believed once `isomorphic` agrees.
const function fingerprint(
	net: Net
): string
	const cells = Net.liveCells(net)
	local colour: {
		[Cell]: string,
	} = {}

	for _, c in cells do
		colour[c] = net.Tag[c]
	end

	for _ = 1, #cells do
		const next: {
			[Cell]: string,
		} = {}
		local changed = false

		for _, c in cells do
			const parts: { string } = {}

			for slot = 1, slots(net.Tag[c]) do
				const q = net.Link[Net.principal(c) + slot - 1] or 0

				if q == 0 then
					table.insert(parts, `{slot}f`)
				else
					table.insert(parts, `{slot}{portName(q)}{colour[Net.owner(q)]}`)
			end end

			table.sort(parts)
			next[c] = `{net.Tag[c]}[{table.concat(parts, ",")}]`

			if next[c] ~= colour[c] then
				changed = true
		end end

		colour = next

		if not changed then
			break
	end end

	const list: { string } = {}

	for _, c in cells do
		table.insert(list, colour[c])
	end

	table.sort(list)

	return `{#cells}|{table.concat(list, ";")}`
end

-- A net holds arrays, and no cell or port, so a shallow clone of each is a snapshot.
const function snapshot(
	net: Net
): Net
	return {
		Tag = table.clone(net.Tag),
		Link = table.clone(net.Link),
		Active = table.clone(net.Active),
		Free = table.clone(net.Free),
	}
end

-- Rendered as one line, for messages that have to fit in a sentence.
const function describe(
	report: Report
): string
	const steps =
		if report.steps == 1 then
			"1 step"
		else
			`{report.steps} steps`

	if report.outcome == "cycled" then
		const period =
			if report.period == 1 then
				"1 step"
			else
				`{report.period} steps`

		return `cycles every {period}, from step {report.firstSeen} ({report.cells} cells, {report.peakCells} peak)`
	elseif report.outcome == "exhausted" then
		return `did not finish in {steps} ({report.cells} cells, {report.peakCells} peak)`
	end

	return `reduced in {steps} ({report.cells} cells, {report.peakCells} peak)`
end

-- Reduce to a normal form, or to whatever the budget allows.
-- The net is mutated in place, so pass a net you do not need again.
const function reduce(
	net: Net,
	budget: number?
): Report
	const limit = budget or DEFAULT_BUDGET
	const seen: {
		[string]: {
			step: number,
			net: Net,
		},
	} = {}
	local tracked = 0
	local steps = 0
	local cells = #Net.liveCells(net)
	local peak = cells

	while true do
		const mark = fingerprint(net)
		const previous = seen[mark]

		if previous then
			if Net.isomorphic(net, previous.net) then
				return {
					outcome = "cycled",
					steps = steps,
					cells = cells,
					peakCells = peak,
					period = steps - previous.step,
					firstSeen = previous.step,
				}
			end
		elseif tracked < MAX_TRACKED then
			-- Only the first sighting of a state is kept, so a cycle is measured from where it began.
			seen[mark] = {
				step = steps,
				net = snapshot(net),
			}
			tracked += 1
		end

		if steps >= limit then
			return {
				outcome = "exhausted",
				steps = steps,
				cells = cells,
				peakCells = peak,
			}
		end

		if not Net.step(net) then
			return {
				outcome = "reduced",
				steps = steps,
				cells = cells,
				peakCells = peak,
			}
		end

		steps += 1
		cells = #Net.liveCells(net)
		peak = math.max(peak, cells)
end end

-- A net as text, one cell per line, with every port either free or naming the cell and port it is wired to.
-- Cells keep their ids so that two dumps can be compared by eye.
const function dump(
	net: Net
): string
	const lines: { string } = {}

	for _, c in Net.liveCells(net) do
		const parts: { string } = {}

		for slot = 1, slots(net.Tag[c]) do
			const q = net.Link[Net.principal(c) + slot - 1] or 0
			const name = portName(Net.principal(c) + slot - 1)

			if q == 0 then
				table.insert(parts, `{name}=free`)
			else
				table.insert(parts, `{name}={Net.owner(q)}.{portName(q)}`)
		end end

		table.insert(lines, `  {c} {net.Tag[c]}  {table.concat(parts, "  ")}`)
	end

	if #lines == 0 then
		return "  (no cells)"
	end

	return table.concat(lines, "\n")
end

-- Reduce `start` and insist that what is left is `expect`, up to a renaming of cells.
-- The message carries both dumps and the report, because a bare "FAIL" is no help when a gadget is wrong.
const function assertReducesTo(
	start: Net,
	expect: Net,
	budget: number?
)
	const report = reduce(start, budget)

	if report.outcome ~= "reduced" then
		error(`expected a normal form, but the net {describe(report)}\n{dump(start)}`)
	end

	if not Net.wellFormed(start) then
		error(`the net reduced to something that is not well formed\n{dump(start)}`)
	end

	if not Net.isomorphic(start, expect) then
		error(`the net reduced to something other than expected\n  reduced:\n{dump(start)}\n  expected:\n{dump(expect)}`)
end end

return {
	DEFAULT_BUDGET = DEFAULT_BUDGET,
	fingerprint = fingerprint,
	describe = describe,
	reduce = reduce,
	dump = dump,
	assertReducesTo = assertReducesTo,
}
