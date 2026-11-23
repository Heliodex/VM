--!strict
-- PHASE 0 OF PROTOTYPE 7: MEASURES THE BOOTSTRAPPED FRONT END
--
-- Phase 0 measured Prototype 6 (runs 4 and 5). This driver now runs the Phase 1 variants in boot/ (layout, and the checker with imports), and keeps Prototype 6's own types.l2 as the input of the validation, so the checker's numbers stay comparable with run 4.
--
-- Five measurements:
--   1. Validation. The checker on Prototype 6's types.l2 takes 299,622,490 steps on the hybrid machine and on the counted reference machine, as vm_bench reports. The variant checker must give the same answer.
--   2. The build of the corpus. Each file goes through the VM stages: its imports (each library through layout, lex and parse, then the checker, with the libraries as InferI requests), then layout, lex, parse and check. The steps of the imports are reported as a stage of their own. The VM's layout output must equal the host's.
--   3. The profile. The checker on types.l2 under the counted machine: steps by form, by frame, and by owning function.
--   4. Growth by owner. The checker on 100 and 400 generated functions, profiled.
--   5. Scaling. The VM stages on generated programs, to see how the costs grow with size.
--
-- Run from this folder:
--   lute run phase0.luau

const ProgramFile = require "../../6/L2/programfile"
const Lifecycle = require "../../6/interpreter/lifecycle"
const VM = require "../../6/interpreter/vm"
const Compile = require "./compile"
const O = require "./outcomes"
const Counted = require "./vm_counted"
const V = require "./vm_values"
const fs = require "@lute/fs"

const bytesValue = V.bytesValue
const textOf = V.textOf
const BOOT = "../../6/L2/programs/boot/"
const P6 = "../../6/L2/programs/"
const CHECKER_STEPS = 299622490

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

-- Which machine runs the L2 programs. Lifecycle.run calls VM.run, so swapping that field swaps the machine, as vm_bench does.
-- The signature of a machine's run. Each machine has it: Prototype 6's run, runHybrid, and the counted copy's runReference.
type Runner = (program: VM.Expr, fuel: number, initialEnv: VM.Binding?) -> VM.Outcome
const machines: { [string]: Runner } = {
	fast = VM.run,
	hybrid = VM.runHybrid,
	counted = function(program: VM.Expr, fuel: number, env: VM.Binding?): VM.Outcome
		return Counted.runReference(program, fuel, env)
	end,
}

const function useMachine(name: string)
	VM.run = machines[name]
end

-- The text of a list of bytes.
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
const function timedRun(compiled: Compile.Compiled, input: VM.Value, fuel: number): (Lifecycle.Result, number)
	const t0 = os.clock()
	const result = Lifecycle.run(compiled.expr, input, fuel)

	return result, os.clock() - t0
end

type Stage = { steps: number; seconds: number; status: string }
type Import = { name: string; file: string }
type VmBuild = {
	imports: Stage,
	layout: Stage,
	lex: Stage,
	parse: Stage,
	check: Stage,
	-- The laid-out text the VM's layout stage gives, when it succeeds. The driver compares it with the host's.
	laidOut: string?,
	refused: string?,
	result: string?,
}

const function stage(result: Lifecycle.Result, seconds: number): Stage
	return { steps = result.steps; seconds = seconds; status = result.status }
end

const function skipped(): Stage
	return { steps = 0; seconds = 0; status = "skipped" }
end

-- The imports of a file, from its header.
const function importsOf(text: string): { Import }
	const file = ProgramFile.parse(text, nil)
	local out: { Import } = {}

	for _, imp in file.imports do
		table.insert(out, { name = imp.name; file = imp.file })
	end

	return out
end

-- The VM build of one source: its imports, then layout, lex, parse and check. The source is the raw program section (indented), which is what a VM build starts from. Each library is laid out, lexed and parsed on the VM, and the checker gets the libraries as InferI (name . program) with the program. A stage that fails ends the build, and the later stages are skipped.
-- The compiled stages of the compiler, each as Compile.Compiled.
type Compiler = { layout: Compile.Compiled; lexer: Compile.Compiled; parser: Compile.Compiled; checker: Compile.Compiled }

const function vmBuild(compiled: Compiler, raw: string, imports: { Import }): VmBuild
	local importSteps = 0
	local importSeconds = 0
	local libraries: { VM.Value } = {}
	local importRefusal: string? = nil

	for _, imp in imports do
		const libRaw = ProgramFile.parse(readFile(P6 .. imp.file), nil).program :: string
		const laid, t1 = timedRun(compiled.layout, bytesValue(libRaw), 1e10)
		importSteps += laid.steps
		importSeconds += t1

		if laid.status ~= "value" or O.tagOf(O.valueOf(laid)) ~= 0 then
			importRefusal = `{imp.file} layout {laid.status}`
			break
		end

		const lexed, t2 = timedRun(compiled.lexer, O.payloadOf(O.valueOf(laid)), 1e8)
		importSteps += lexed.steps
		importSeconds += t2

		if lexed.status ~= "value" then
			importRefusal = `{imp.file} lex {lexed.status}`
			break
		end

		const parsed, t3 = timedRun(compiled.parser, O.payloadOf(O.valueOf(lexed)), 5e8)
		importSteps += parsed.steps
		importSeconds += t3

		if parsed.status ~= "value" or O.tagOf(O.valueOf(parsed)) ~= 0 then
			importRefusal = `{imp.file} parse {parsed.status}`
			break
		end

		const library: VM.Cell = { kind = "cell"; head = bytesValue(imp.name); tail = O.payloadOf(O.valueOf(parsed)) }
		table.insert(libraries, library)
	end

	const importStage: Stage = {
		steps = importSteps,
		seconds = importSeconds,
		status = if importRefusal then
			"refused"
		else
			"value",
	}

	if importRefusal ~= nil then
		return { imports = importStage; layout = skipped(); lex = skipped(); parse = skipped(); check = skipped(); refused = "imports: " .. importRefusal }
	end

	const laid, layoutTime = timedRun(compiled.layout, bytesValue(raw), 1e10)
	const layout = stage(laid, layoutTime)

	if laid.status ~= "value" or O.tagOf(O.valueOf(laid)) ~= 0 then
		return { imports = importStage; layout = layout; lex = skipped(); parse = skipped(); check = skipped(); refused = "layout " .. laid.status }
	end

	const bracketed = O.payloadOf(O.valueOf(laid))
	const lexed, lexTime = timedRun(compiled.lexer, bracketed, 1e8)
	const lex = stage(lexed, lexTime)

	if lexed.status ~= "value" then
		return { imports = importStage; layout = layout; lex = lex; parse = skipped(); check = skipped(); laidOut = textOf(bracketed); refused = "lex " .. lexed.status }
	end

	const parsed, parseTime = timedRun(compiled.parser, O.payloadOf(O.valueOf(lexed)), 5e8)
	const parse = stage(parsed, parseTime)

	if parsed.status ~= "value" or O.tagOf(O.valueOf(parsed)) ~= 0 then
		return { imports = importStage; layout = layout; lex = lex; parse = parse; check = skipped(); laidOut = textOf(bracketed); refused = "parse " .. parsed.status }
	end

	-- Without imports the request is Infer (tag 3); with them it is InferI (tag 4), with the libraries in the order of the header.
	local request: VM.Value = { kind = "con"; tag = 3; payload = O.payloadOf(O.valueOf(parsed)) }

	if #libraries > 0 then
		local cells: VM.Value = VM.NIL

		for i = #libraries, 1, -1 do
			const cell: VM.Cell = { kind = "cell"; head = libraries[i]; tail = cells }
			cells = cell
		end

		const pair: VM.Cell = { kind = "cell"; head = cells; tail = O.payloadOf(O.valueOf(parsed)) }
		const withLibraries: VM.Con = { kind = "con"; tag = 4; payload = pair }
		request = withLibraries
	end

	const checked, checkTime = timedRun(compiled.checker, request, 1e10)

	return {
		imports = importStage,
		layout = layout,
		lex = lex,
		parse = parse,
		check = stage(checked, checkTime),
		laidOut = textOf(bracketed),
		result = if checked.status == "value" then
			VM.show(checked.value)
		else
			checked.status,
	}
end

const function vmSteps(build: VmBuild): number
	return build.imports.steps + build.layout.steps + build.lex.steps + build.parse.steps + build.check.steps
end

const function vmSeconds(build: VmBuild): number
	return build.imports.seconds + build.layout.seconds + build.lex.seconds + build.parse.seconds + build.check.seconds
end

-- The steps and seconds of each stage of a VM build, as text.
const function describe(name: string, build: VmBuild): string
	return string.format(
		"%s: imports %s steps %.3fs, layout %s steps %.3fs, lex %s steps %.3fs, parse %s steps %.3fs, check %s steps %.3fs (total %s steps)%s",
		name,
		commas(build.imports.steps),
		build.imports.seconds,
		commas(build.layout.steps),
		build.layout.seconds,
		commas(build.lex.steps),
		build.lex.seconds,
		commas(build.parse.steps),
		build.parse.seconds,
		commas(build.check.steps),
		build.check.seconds,
		commas(vmSteps(build)),
		if build.refused then
			"  refused: " .. build.refused
		else
			""
	)
end

-- The compiler's own stages, compiled once. Their compile time is not part of any build here, since the compiler is built once and used many times.
const compilerTimes: { string } = {}

const function compileCompiler(file: string, dir: string): Compile.Compiled
	const c = Compile.compile(readFile(dir .. file), "boot/" .. file)
	table.insert(compilerTimes, string.format("  %s (%s): layout %.3fs, parse %.3fs, check %.3fs, desugar %.3fs", file, dir, c.timings.layout, c.timings.parse, c.timings.check, c.timings.desugar))

	return c
end

print "== The compiler's own stages (host, once; not part of any build below)"
const layoutC = compileCompiler("layout.l2", "boot/")
const lexer = compileCompiler("lex.l2", BOOT)
const parser = compileCompiler("parse.l2", BOOT)
const checker = compileCompiler("types.l2", "boot/")
-- Prototype 6's types.l2 is the input of the validation and the profile, as in run 4.
const typesP6 = compileCompiler("types.l2", BOOT)
const compiled = { layout = layoutC; lexer = lexer; parser = parser; checker = checker }

for _, line in compilerTimes do
	print(line)
end

-- 1. Validation.
print ""
print "== 1. Validation: the checker on Prototype 6's types.l2"
useMachine "hybrid"
const hybridRun = vmBuild(compiled, typesP6.raw, {})
print(describe("hybrid", hybridRun))
print("  result: " .. tostring(hybridRun.result))
print(
	if hybridRun.check.steps == CHECKER_STEPS then
		"  matches vm_bench: " .. commas(CHECKER_STEPS) .. " steps"
	else
		`  differs from vm_bench's Prototype 6 count ({commas(CHECKER_STEPS)} steps) by {hybridRun.check.steps - CHECKER_STEPS} steps, as expected: this run checks with the variant checker in boot/, not Prototype 6's (the result is compared below)`
)
print(
	if hybridRun.laidOut == typesP6.source then
		"  VM layout agrees with host layout"
	else
		"  VM layout DISAGREES with host layout"
)
useMachine "counted"
const countedRun = vmBuild(compiled, typesP6.raw, {})
useMachine "hybrid"
print(
	if countedRun.check.steps == hybridRun.check.steps then
		"  counted machine agrees: " .. commas(countedRun.check.steps) .. " steps"
	else
		"  counted machine DISAGREES: " .. commas(countedRun.check.steps)
)
-- 2. The build of the corpus.
print ""
print "== 2. The build of the corpus (each file, host and VM)"
const corpus = { "lex.l2"; "parse.l2"; "layout.l2"; "types.l2" }
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
	const vm = vmBuild(compiled, host.raw, importsOf(text))
	const agreed = vm.laidOut == host.source

	if agreed then
		layoutAgreed += 1
	end

	totalBytes += #text
	totalLines += linesOf(text)
	totalHostSeconds += hostSeconds
	totalVmSteps += vmSteps(vm)
	totalVmSeconds += vmSeconds(vm)
	print(string.format("%s: %s bytes, %d lines, %d imports", file, commas(#text), linesOf(text), #importsOf(text)))
	print(string.format("  host: layout %.3fs, parse %.3fs, check %.3fs, desugar %.3fs, imports %.3fs", host.timings.layout, host.timings.parse, host.timings.check, host.timings.desugar, host.timings.imports))
	print("  " .. describe("VM", vm))
	print(
		"  VM layout " .. (
			if agreed then
				"agrees with host"
			else
				"DISAGREES with host"
		)
	)
	print("  check result: " .. tostring(vm.result))
end

print(string.format("corpus total: %s bytes, %d lines; host %.3fs; VM %s steps in %.3fs (hybrid); layout agreed on %d of %d files", commas(totalBytes), totalLines, totalHostSeconds, commas(totalVmSteps), totalVmSeconds, layoutAgreed, #corpus))
-- 3. The profile.
print ""
print "== 3. Profile: the checker on Prototype 6's types.l2, counted machine"

const function newProfile(): { op: { [string]: number }; frame: { [string]: number }; owner: { [string]: number }; steps: number }
	return {
		op = {},
		frame = {},
		owner = {},
		steps = 0,
	}
end

local profile = newProfile()

const function bump(t: { [string]: number }, key: string)
	t[key] = (t[key] or 0) + 1
end

-- Every step is charged to the owner of the node the machine holds in expr. On an evaluation step that is the node being evaluated. On a step that hands a value to a frame, it is the node that produced the value, which is the last node evaluated. Frames do not carry that node themselves (a tagof or index frame carries nothing), so this is the only owner that is always there.
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

-- The request for the profile comes from the VM's own layout, lex and parse, on the hybrid machine, so only the checker's own steps are counted.
const profileLaid = Lifecycle.run(layoutC.expr, bytesValue(typesP6.raw), 1e10)
const profileLexed = Lifecycle.run(lexer.expr, O.payloadOf(O.valueOf(profileLaid)), 1e8)
const profileParsed = Lifecycle.run(parser.expr, O.payloadOf(O.valueOf(profileLexed)), 5e8)
const profileRequest = { kind = "con"; tag = 3; payload = O.payloadOf(O.valueOf(profileParsed)) }
useMachine "counted";
Counted.probe.profile = hook
const profiled = Lifecycle.run(checker.expr, profileRequest, 1e10);
Counted.probe.profile = nil
useMachine "hybrid"
print(string.format("checker steps under the profile: %s (outcome %s)", commas(profiled.steps), profiled.status))
print(
	if profile.steps == profiled.steps then
		"  every step is in the profile"
	else
		"  PROFILE DOES NOT COVER ALL STEPS"
)

const function printTop(title: string, t: { [string]: number }, total: number, limit: number)
	local rows: { { string | number } } = {}

	for key, value in t do
		table.insert(rows, { key; value })
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

printTop("by form (steps that evaluate a node):", profile.op, profile.steps, 20)
printTop("by frame (steps that hand a value to a waiting frame):", profile.frame, profile.steps, 20)
printTop("by owning function (every step, top 40):", profile.owner, profile.steps, 40)

-- A program file: a header, no imports, the program, and one test. The program is a function of x, which calls the chain at x; f_n(x) = x + 1 + 2 + ... + n, so the test is the sum. Each function calls the one before it, so the program is a chain of nested lets.
const function synthetic(n: number): string
	local lines = { string.format("%d chained functions", n); "---"; "---"; "fn x" }
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
print ""
print "== 4. Growth by owner: the checker on 100 and 400 generated functions, counted"
local grown: { { [string]: number } } = {}

for _, n in { 100; 400 } do
	const host = Compile.compile(synthetic(n), `synthetic {n}`)
	const laidFor = Lifecycle.run(layoutC.expr, bytesValue(host.raw), 1e10)
	const lexedFor = Lifecycle.run(lexer.expr, O.payloadOf(O.valueOf(laidFor)), 1e8)
	const parsedFor = Lifecycle.run(parser.expr, O.payloadOf(O.valueOf(lexedFor)), 5e8)
	const requestFor = { kind = "con"; tag = 3; payload = O.payloadOf(O.valueOf(parsedFor)) }
	profile = newProfile()
	useMachine "counted";
	Counted.probe.profile = hook
	const runFor = Lifecycle.run(checker.expr, requestFor, 1e10);
	Counted.probe.profile = nil
	useMachine "hybrid"
	grown[n] = profile.owner
	print(string.format("%d functions: checker %s steps (outcome %s)", n, commas(runFor.steps), runFor.status))
end

local growthRows: { { string | number } } = {}

for key, small in grown[100] do
	const large = grown[400][key] or 0
	table.insert(growthRows, { key; small; large })
end

table.sort(
	growthRows,
	function(a, b)
		return a[3] :: number > b[3] :: number
	end
)
print(string.format("  %-44s %14s %14s %8s", "owner", "100 fns", "400 fns", "growth"))

for i = 1, math.min(15, #growthRows) do
	const row = growthRows[i]
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

-- 5. Scaling, on generated programs. Each function calls the one before it, so the program is a chain of nested lets.
print ""
print "== 5. Scaling: generated programs, chained functions"
useMachine "hybrid"

for _, n in { 25; 50; 100; 200; 400; 800; 1600 } do
	const text = synthetic(n)
	const host = Compile.compile(text, `synthetic {n}`)
	const vm = vmBuild(compiled, host.raw, {})
	const lines = linesOf(text)
	print(string.format("%d functions: %d lines, %s bytes; host check %.3fs, desugar %.3fs", n, lines, commas(#text), host.timings.check, host.timings.desugar))
	print("  " .. describe("VM", vm))
	print(string.format("  check steps per function: %s, per line: %s; check result: %s", commas(math.floor(vm.check.steps / n)), commas(math.floor(vm.check.steps / lines)), tostring(vm.result)))
end
