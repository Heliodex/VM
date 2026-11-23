--!strict
-- PROFILES THE VM'S LAYOUT STAGE (boot/layout.l2), AS PHASE 0 PROFILED THE CHECKER
--
-- Runs the layout on the VM on the raw program section of types.l2 and on generated programs of 100 and 400 functions, under the counted machine, and charges each step to its owning function, as phase0.luau does for the checker. The layout is a whole-file pass, so the owner is the function of layout.l2 whose body holds the step.
--
--   lute run layout_profile.luau     (from this folder; about a minute)

const Lifecycle = require "../../6/interpreter/lifecycle"
const VM = require "../../6/interpreter/vm"
const Compile = require "./compile"
const O = require "./outcomes"
const Counted = require "./vm_counted"
const V = require "./vm_values"
const fs = require "@lute/fs"

const bytesValue = V.bytesValue
const BOOT = "../../6/L2/programs/boot/"

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

const function commas(n: number): string
	local s = string.format("%d", n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()

	return (out:gsub("^,", ""))
end

-- The same generator as phase0.luau's section 5.
const function synthetic(n: number): string
	local lines = { string.format("%d chained functions", n), "---", "---", "fn x" }
	table.insert(lines, "\tlet f0 = fn y")
	table.insert(lines, "\t\ty")

	for i = 1, n do
		table.insert(lines, string.format("\tlet f%d = fn y", i))
		table.insert(lines, string.format("\t\t(+ (f%d y) %d)", i - 1, i))
	end

	table.insert(lines, "\t(f" .. n .. " x)")
	table.insert(lines, "---")
	table.insert(lines, string.format("0 => %d fuel 1000000000", n * (n + 1) // 2))
	table.insert(lines, "")

	return table.concat(lines, "\n")
end

const function newProfile(): { op: { [string]: number }, frame: { [string]: number }, owner: { [string]: number }, steps: number }
	return { op = {}, frame = {}, owner = {}, steps = 0 }
end

local profile = newProfile()

const function bump(t: { [string]: number }, key: string)
	t[key] = (t[key] or 0) + 1
end

-- The same charging rule as phase0.luau: the owner of the node the machine holds in expr, which for a frame step is the node that produced the value.
const function hook(expr: VM.Expr, returning: boolean, frame: { k: string }?)
	profile.steps += 1

	if returning then
		bump(
			profile.frame,
			if frame == nil then
				"final"
			else
				frame.k
		)
	else
		bump(profile.op, expr.op)
	end

	bump(profile.owner, V.ownerOf(expr))
end

-- The Phase 1 variant in boot/ (difference lists). Set this to BOOT .. "layout.l2" to profile Prototype 6's layout, the baseline in results/layout_profile.txt.
const layoutC = Compile.compile(readFile "boot/layout.l2", "boot/layout.l2")

-- Runs the layout on a raw program section under the counted machine, with the profile on.
const function profiled(raw: string): (number, string, typeof(profile))
	profile = newProfile()
	VM.run = function(p: VM.Expr, f: number, e: VM.Binding?): VM.Outcome
		return Counted.runReference(p, f, e)
	end;
	Counted.probe.profile = hook
	const result = Lifecycle.run(layoutC.expr, bytesValue(raw), 1e10);
	Counted.probe.profile = nil
	VM.run = VM.runHybrid

	return result.steps, result.status, profile
end

const function printTop(title: string, t: { [string]: number }, total: number, limit: number)
	local rows: { { string | number } } = {}

	for key, value in t do
		table.insert(rows, { key, value })
	end

	table.sort(
		rows,
		function(a, b)
			return a[2] :: number > b[2] :: number
		end
	)
	print(title)

	for i = 1, math.min(limit, #rows) do
		const row = rows[i]
		print(string.format("  %-44s %16s  %6.2f%%", tostring(row[1]), commas(row[2] :: number), 100 * row[2] :: number / total))
	end
end

-- 1. The corpus file the checker profile uses: types.l2, the largest.
const typesRaw = Compile.compile(readFile(BOOT .. "types.l2"), "boot/types.l2").raw
const typesSteps, typesStatus, typesProfile = profiled(typesRaw)
print(string.format("== types.l2 (%s bytes): layout %s steps (%s)", commas(#typesRaw), commas(typesSteps), typesStatus))
print(
	if typesProfile.steps == typesSteps then
		"  every step is in the profile"
	else
		"  PROFILE DOES NOT COVER ALL STEPS"
)
printTop("by form:", typesProfile.op, typesProfile.steps, 12)
printTop("by owning function:", typesProfile.owner, typesProfile.steps, 30)
-- 2. Growth by owner, on generated programs.
print ""
print "== Growth by owner: layout on 100 and 400 generated functions"
local grown: { { [string]: number } } = {}
local totals: { number } = {}

for _, n in { 100, 400 } do
	const raw = Compile.compile(synthetic(n), `synthetic {n}`).raw
	const steps, status, p = profiled(raw)
	grown[n] = p.owner
	totals[n] = steps
	print(string.format("%d functions (%d bytes): layout %s steps (%s)", n, #raw, commas(steps), status))
end

local rows: { { string | number } } = {}

for key, small in grown[100] do
	table.insert(rows, { key, small, grown[400][key] or 0 })
end

table.sort(
	rows,
	function(a, b)
		return a[3] :: number > b[3] :: number
	end
)
print(string.format("  %-44s %14s %14s %8s", "owner", "100 fns", "400 fns", "growth"))

for i = 1, math.min(20, #rows) do
	const row = rows[i]
	const small = row[2] :: number
	const large = row[3] :: number
	print(
		string.format(
			"  %-44s %14s %14s %7.1fx",
			tostring(row[1]),
			commas(small),
			commas(large),
			if small > 0 then
				large / small
			else
				0
		)
	)
end

print(string.format("  total growth: %.1fx (quadratic would be 16x, linear 4x)", totals[400] / totals[100]))
