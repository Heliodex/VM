--!strict
-- PROFILES THE VARIANT CHECKER (boot/types.l2) ON PROTOTYPE 6'S types.l2, AS PHASE 0 PROFILED THE PROTOTYPE 6 CHECKER
--
-- The same counted machine and charging rule as phase0.luau's section 3, run on its own so that a Phase 1 change can be profiled in about two minutes. The request comes from the VM's layout, lex and parse, on the hybrid machine, so only the checker's steps are counted.
--
--   lute run checker_profile.luau     (from this folder)

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

local profile = { op = {} :: { [string]: number }; frame = {} :: { [string]: number }; owner = {} :: { [string]: number }; steps = 0 }

const function bump(t: { [string]: number }, key: string)
	t[key] = (t[key] or 0) + 1
end

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

const layoutC = Compile.compile(readFile "boot/layout.l2", "boot/layout.l2")
const lexer = Compile.compile(readFile(BOOT .. "lex.l2"), "boot/lex.l2")
const parser = Compile.compile(readFile(BOOT .. "parse.l2"), "boot/parse.l2")
const checker = Compile.compile(readFile "boot/types.l2", "boot/types.l2")
const typesP6 = Compile.compile(readFile(BOOT .. "types.l2"), "boot/types.l2")
const laid = Lifecycle.run(layoutC.expr, bytesValue(typesP6.raw), 1e10)
const lexed = Lifecycle.run(lexer.expr, O.payloadOf(O.valueOf(laid)), 1e8)
const parsed = Lifecycle.run(parser.expr, O.payloadOf(O.valueOf(lexed)), 5e8)
const request = { kind = "con"; tag = 3; payload = O.payloadOf(O.valueOf(parsed)) }
VM.run = function(p: VM.Expr, f: number, e: VM.Binding?): VM.Outcome
	return Counted.runReference(p, f, e)
end;
Counted.probe.profile = hook
const run = Lifecycle.run(checker.expr, request, 1e10);
Counted.probe.profile = nil
VM.run = VM.runHybrid
print(
	`checker steps: {commas(run.steps)} ({run.status}); profile covers {
		if profile.steps == run.steps then
			"all of them"
		else
			"NOT all: " .. profile.steps
	}`
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

printTop("by form:", profile.op, profile.steps, 12)
printTop("by frame:", profile.frame, profile.steps, 12)
printTop("by owning function:", profile.owner, profile.steps, 40)
