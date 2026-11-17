--!strict
-- PROTOTYPE BASED ON INTERACTION COMBINATORS
--
-- Drives the engine over the tests in cases.luau and prints the whole reduction of each one as a page of SVG diagrams.
-- The page is printed as it goes, and the run stops at the first test that does not behave as expected.

const Cases = require "./cases"
const toSvg = require "./diagram"
const H = require "./harness"
const Rules = require "./rules"

print '<!doctype html>\n<html lang="en-GB">\n<head>\n<meta charset="utf-8">\n<title>Interaction Combinator reductions</title>\n<style>\n  body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 1100px; background: black; color: white; }\n  h1 { font-size: 1.4rem; }\n  h2 { font-size: 1.05rem; margin: 0 0 0.75rem; }\n  section { border-top: 1px solid #ddd; padding: 1.5rem 0; }\n  figure { margin: 0 0 1rem; }\n  figcaption { font-size: 0.75rem; color: #ccc; margin-top: 0.2rem; }\n  svg { max-width: 100%; height: auto; border: 1px solid #eee; background: #111; }\n  .pass { color: #2e7d32; font-weight: 600; }\n  .fail { color: #c62828; font-weight: 600; }\n  .note { color: #ccc; font-style: italic; }\n</style>\n</head>\n<body>\n<h1>Interaction Combinator reductions</h1>'
const MAX_STEPS_SHOWN = 60

for _, test in Cases.tests do
	const limit = test.budget or H.DEFAULT_BUDGET
	-- Reduce first (no SVG): find out how many steps it takes and how the reduction ended. Only then decide which diagrams to draw, so the (expensive) layout is never paid for steps that will be omitted.
	const net = Cases.build(test.start)
	const report = H.reduce(net, limit)
	const steps = report.steps
	const finished = report.outcome == "reduced"
	print "<section>"
	print(`<h2>{test.name}</h2>`)
	print(`<figure>{toSvg(Cases.build(test.start))}<figcaption>start</figcaption></figure>`)

	if finished and steps <= MAX_STEPS_SHOWN then
		-- replay the reduction, drawing each step
		local walk = Cases.build(test.start)

		for i = 1, steps do
			Rules.step(walk)
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

	const ok = Cases.verdict(test, net, report)
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
