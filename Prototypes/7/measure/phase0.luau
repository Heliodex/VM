--!strict
-- PHASE 0 OF PROTOTYPE 7: MEASURES PROTOTYPE 6, WITHOUT CHANGING IT
--
-- Five measurements:
--   1. Validation. The checker on types.l2 takes 299,622,490 steps on the hybrid machine and on the counted reference machine, as vm_bench reports. The counted machine must agree with Prototype 6 before its profile is trusted.
--   2. The build of the corpus. Each file goes through the VM stages (layout, lex, parse, check) and the host stages (layout, Luau parser, Luau checker, desugar). Steps are exact; seconds are CPU time on this host. The VM's layout output must equal the host's.
--   3. The profile. The checker on types.l2 under the counted machine: steps by form, by frame, and by owning function.
--   4. Growth by owner. The checker on 100 and 400 generated functions, profiled.
--   5. Scaling. The VM stages on generated programs, to see how the costs grow with size.
--
-- Run from this folder:
--   lute run phase0.luau

const fs = require "@lute/fs"
const Compile = require "./compile"
const VM = require "../../6/interpreter/vm"
const Lifecycle = require "../../6/interpreter/lifecycle"
const Counted = require "./vm_counted"

const BOOT = "../../6/L2/programs/boot/"
const CHECKER_STEPS = 299622490

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

-- Which machine runs the L2 programs. Lifecycle.run calls VM.run, so swapping that field swaps the machine, as vm_bench does.
const machines: { [string]: any } = {
	fast = VM.run,
	hybrid = VM.runHybrid,
	counted = function(program: any, fuel: number, env: any): any
		return Counted.runReference(program, fuel, env)
	end,
}

local function useMachine(name: string)
	(VM :: any).run = machines[name]
end

const function bytesValue(s: string): any
	local v: any = VM.NIL

	for i = #s, 1, -1 do
		v = { kind = "cell", head = string.byte(s, i), tail = v }
	end

	return v
end

-- The text of a list of bytes.
const function textOf(v: any): string
	local out: { string } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, string.char(cur.head))
		cur = cur.tail
	end

	return table.concat(out)
end

const function commas(n: number): string
	local s = string.format("%d", n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()

	return (out:gsub("^,", ""))
end

const function linesOf(text: string): number
	local _, count = string.gsub(text, "\n", "")

	return count
end

-- Runs one stage, and gives the result and its CPU seconds.
local function timedRun(compiled: any, input: any, fuel: number): (any, number)
	const t0 = os.clock()
	const result = Lifecycle.run(compiled.expr, input, fuel)

	return result, os.clock() - t0
end

type Stage = { steps: number, seconds: number, status: string }
type VmBuild = {
	layout: Stage,
	lex: Stage,
	parse: Stage,
	check: Stage,
	-- The laid-out text the VM's layout stage gives, when it succeeds. The driver compares it with the host's.
	laidOut: string?,
	refused: string?,
	result: string?,
}

local function stage(result: any, seconds: number): Stage
	return { steps = result.steps, seconds = seconds, status = result.status }
end

local function skipped(): Stage
	return { steps = 0, seconds = 0, status = "skipped" }
end

-- The VM build of one source: layout, then lex, parse and check. The source is the raw program section (indented), which is what a VM build starts from. Each stage that fails ends the build, and the later stages are skipped.
local function vmBuild(compiled: any, raw: string): VmBuild
	const laid, layoutTime = timedRun(compiled.layout, bytesValue(raw), 1e10)
	const layout = stage(laid, layoutTime)

	if laid.status ~= "value" or laid.value.tag ~= 0 then
		return { layout = layout, lex = skipped(), parse = skipped(), check = skipped(), refused = "layout " .. laid.status }
	end

	const bracketed = laid.value.payload
	const lexed, lexTime = timedRun(compiled.lexer, bracketed, 1e8)
	const lex = stage(lexed, lexTime)

	if lexed.status ~= "value" then
		return { layout = layout, lex = lex, parse = skipped(), check = skipped(), laidOut = textOf(bracketed), refused = "lex " .. lexed.status }
	end

	const parsed, parseTime = timedRun(compiled.parser, lexed.value.payload, 5e8)
	const parse = stage(parsed, parseTime)

	if parsed.status ~= "value" or parsed.value.tag ~= 0 then
		return { layout = layout, lex = lex, parse = parse, check = skipped(), laidOut = textOf(bracketed), refused = "parse " .. parsed.status }
	end

	const request = { kind = "con", tag = 3, payload = parsed.value.payload }
	const checked, checkTime = timedRun(compiled.checker, request, 1e10)

	return {
		layout = layout,
		lex = lex,
		parse = parse,
		check = stage(checked, checkTime),
		laidOut = textOf(bracketed),
		result = if checked.status == "value" then VM.show(checked.value) else checked.status,
	}
end

const function vmSteps(build: VmBuild): number
	return build.layout.steps + build.lex.steps + build.parse.steps + build.check.steps
end

const function vmSeconds(build: VmBuild): number
	return build.layout.seconds + build.lex.seconds + build.parse.seconds + build.check.seconds
end

-- The steps and seconds of each stage of a VM build, as text.
local function describe(name: string, build: VmBuild): string
	return string.format(
		"%s: layout %s steps %.3fs, lex %s steps %.3fs, parse %s steps %.3fs, check %s steps %.3fs (total %s steps)%s",
		name,
		commas(build.layout.steps),
		build.layout.seconds,
		commas(build.lex.steps),
		build.lex.seconds,
		commas(build.parse.steps),
		build.parse.seconds,
		commas(build.check.steps),
		build.check.seconds,
		commas(vmSteps(build)),
		if build.refused then "  refused: " .. build.refused else ""
	)
end

-- The compiler's own stages, compiled once. Their compile time is not part of any build here, since the compiler is built once and used many times.
const compilerTimes: { string } = {}
local function compileCompiler(file: string): any
	const c = Compile.compile(readFile(BOOT .. file), "boot/" .. file)
	table.insert(compilerTimes, string.format("  %s: layout %.3fs, parse %.3fs, check %.3fs, desugar %.3fs", file, c.timings.layout, c.timings.parse, c.timings.check, c.timings.desugar))

	return c
end

print("== The compiler's own stages (host, once; not part of any build below)")
const layoutC = compileCompiler "layout.l2"
const lexer = compileCompiler "lex.l2"
const parser = compileCompiler "parse.l2"
const checker = compileCompiler "types.l2"
const compiled = { layout = layoutC, lexer = lexer, parser = parser, checker = checker }

for _, line in compilerTimes do
	print(line)
end

-- 1. Validation.
print("")
print("== 1. Validation: the checker on types.l2")
useMachine "hybrid"
const hybridRun = vmBuild(compiled, checker.raw)
print(describe("hybrid", hybridRun))
print("  result: " .. tostring(hybridRun.result))
print(
	if hybridRun.check.steps == CHECKER_STEPS
		then "  matches vm_bench: " .. commas(CHECKER_STEPS) .. " steps"
		else "  DOES NOT MATCH vm_bench (" .. commas(CHECKER_STEPS) .. " steps)"
)
print(
	if hybridRun.laidOut == checker.source
		then "  VM layout agrees with host layout"
		else "  VM layout DISAGREES with host layout"
)

useMachine "counted"
const countedRun = vmBuild(compiled, checker.raw)
useMachine "hybrid"
print(
	if countedRun.check.steps == hybridRun.check.steps
		then "  counted machine agrees: " .. commas(countedRun.check.steps) .. " steps"
		else "  counted machine DISAGREES: " .. commas(countedRun.check.steps)
)

-- 2. The build of the corpus.
print("")
print("== 2. The build of the corpus (each file, host and VM)")
const corpus = { "lex.l2", "parse.l2", "layout.l2", "types.l2" }
local totalBytes = 0
local totalLines = 0
local totalHostSeconds = 0
local totalVmSteps = 0
local totalVmSeconds = 0
local layoutAgreed = 0

for _, file in corpus do
	const text = readFile(BOOT .. file)
	const host = Compile.compile(text, "boot/" .. file)
	const hostSeconds = host.timings.layout + host.timings.parse + host.timings.check + host.timings.desugar + host.timings.imports
	const vm = vmBuild(compiled, host.raw)
	const agreed = vm.laidOut == host.source

	if agreed then
		layoutAgreed += 1
	end

	totalBytes += #text
	totalLines += linesOf(text)
	totalHostSeconds += hostSeconds
	totalVmSteps += vmSteps(vm)
	totalVmSeconds += vmSeconds(vm)

	print(string.format("%s: %s bytes, %d lines", file, commas(#text), linesOf(text)))
	print(string.format("  host: layout %.3fs, parse %.3fs, check %.3fs, desugar %.3fs, imports %.3fs", host.timings.layout, host.timings.parse, host.timings.check, host.timings.desugar, host.timings.imports))
	print("  " .. describe("VM", vm))
	print("  VM layout " .. if agreed then "agrees with host" else "DISAGREES with host")
	print("  check result: " .. tostring(vm.result))
end

print(
	string.format(
		"corpus total: %s bytes, %d lines; host %.3fs; VM %s steps in %.3fs (hybrid); layout agreed on %d of %d files",
		commas(totalBytes),
		totalLines,
		totalHostSeconds,
		commas(totalVmSteps),
		totalVmSeconds,
		layoutAgreed,
		#corpus
	)
)

-- 3. The profile.
print("")
print("== 3. Profile: the checker on types.l2, counted machine")

local function newProfile(): { op: { [string]: number }, frame: { [string]: number }, owner: { [string]: number }, steps: number }
	return {
		op = {},
		frame = {},
		owner = {},
		steps = 0,
	}
end

local profile = newProfile()

local function bump(t: { [string]: number }, key: string)
	t[key] = (t[key] or 0) + 1
end

-- Every step is charged to the owner of the node the machine holds in expr. On an evaluation step that is the node being evaluated. On a step that hands a value to a frame, it is the node that produced the value, which is the last node evaluated. Frames do not carry that node themselves (a tagof or index frame carries nothing), so this is the only owner that is always there.
local function hook(expr: any, returning: boolean, frame: any)
	profile.steps += 1

	if returning then
		bump(profile.frame, if frame == nil then "final" else frame.k)
	else
		bump(profile.op, expr.op)
	end

	bump(profile.owner, expr.owner or "?")
end

-- The request for the profile comes from the VM's own layout, lex and parse, on the hybrid machine, so only the checker's own steps are counted.
const profileLaid = Lifecycle.run(layoutC.expr, bytesValue(checker.raw), 1e10)
const profileLexed = Lifecycle.run(lexer.expr, profileLaid.value.payload, 1e8)
const profileParsed = Lifecycle.run(parser.expr, profileLexed.value.payload, 5e8)
const profileRequest = { kind = "con", tag = 3, payload = profileParsed.value.payload }

useMachine "counted"
;(Counted :: any).probe.profile = hook
const profiled = Lifecycle.run(checker.expr, profileRequest, 1e10)
;(Counted :: any).probe.profile = nil
useMachine "hybrid"

print(string.format("checker steps under the profile: %s (outcome %s)", commas(profiled.steps), profiled.status))
print(
	if profile.steps == profiled.steps
		then "  every step is in the profile"
		else "  PROFILE DOES NOT COVER ALL STEPS"
)

local function printTop(title: string, t: { [string]: number }, total: number, limit: number)
	local rows: { { string | number } } = {}

	for key, value in t do
		table.insert(rows, { key, value })
	end

	table.sort(rows, function(a, b)
		return (a[2] :: number) > (b[2] :: number)
	end)

	print(title)

	for i = 1, math.min(limit, #rows) do
		const row = rows[i]
		print(string.format("  %-44s %16s  %6.2f%%", row[1], commas(row[2] :: number), 100 * (row[2] :: number) / total))
	end
end

printTop("by form (steps that evaluate a node):", profile.op, profile.steps, 20)
printTop("by frame (steps that hand a value to a waiting frame):", profile.frame, profile.steps, 20)
printTop("by owning function (every step, top 40):", profile.owner, profile.steps, 40)

-- A program file: a header, no imports, the program, and one test. The program is a function of x, which calls the chain at x; f_n(x) = x + 1 + 2 + ... + n, so the test is the sum. Each function calls the one before it, so the program is a chain of nested lets.
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

-- 4. Growth by owner: the checker's owner steps on two sizes of the generated program. A function whose steps grow 16× from 100 to 400 functions is quadratic, and one that grows 4× is linear.
print("")
print("== 4. Growth by owner: the checker on 100 and 400 generated functions, counted")
local grown: { [number]: { [string]: number } } = {}

for _, n in { 100, 400 } do
	const host = Compile.compile(synthetic(n), `synthetic {n}`)
	const laidFor = Lifecycle.run(layoutC.expr, bytesValue(host.raw), 1e10)
	const lexedFor = Lifecycle.run(lexer.expr, laidFor.value.payload, 1e8)
	const parsedFor = Lifecycle.run(parser.expr, lexedFor.value.payload, 5e8)
	const requestFor = { kind = "con", tag = 3, payload = parsedFor.value.payload }

	profile = newProfile()
	useMachine "counted"
	;(Counted :: any).probe.profile = hook
	const runFor = Lifecycle.run(checker.expr, requestFor, 1e10)
	;(Counted :: any).probe.profile = nil
	useMachine "hybrid"

	grown[n] = profile.owner
	print(string.format("%d functions: checker %s steps (outcome %s)", n, commas(runFor.steps), runFor.status))
end

local growthRows: { { string | number } } = {}

for key, small in grown[100] do
	const large = grown[400][key] or 0
	table.insert(growthRows, { key, small, large })
end

table.sort(growthRows, function(a, b)
	return (a[3] :: number) > (b[3] :: number)
end)

print(string.format("  %-44s %14s %14s %8s", "owner", "100 fns", "400 fns", "growth"))

for i = 1, math.min(15, #growthRows) do
	const row = growthRows[i]
	const small = row[2] :: number
	const large = row[3] :: number
	print(string.format("  %-44s %14s %14s %7.1fx", row[1], commas(small), commas(large), if small > 0 then large / small else 0))
end

-- 5. Scaling, on generated programs. Each function calls the one before it, so the program is a chain of nested lets.
print("")
print("== 5. Scaling: generated programs, chained functions")
useMachine "hybrid"

for _, n in { 25, 50, 100, 200, 400, 800, 1600 } do
	const text = synthetic(n)
	const host = Compile.compile(text, `synthetic {n}`)
	const vm = vmBuild(compiled, host.raw)
	const lines = linesOf(text)

	print(string.format("%d functions: %d lines, %s bytes; host check %.3fs, desugar %.3fs", n, lines, commas(#text), host.timings.check, host.timings.desugar))
	print("  " .. describe("VM", vm))
	print(string.format("  check steps per function: %s, per line: %s; check result: %s", commas(math.floor(vm.check.steps / n)), commas(math.floor(vm.check.steps / lines)), tostring(vm.result)))
end
