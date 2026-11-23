--!strict
-- THE CHECKER'S STEPS AGAINST SIZE, ON THE VARIANT CHECKER (boot/types.l2), FOR THE PHASE 1 EXIT TEST
--
-- Runs the front end on Prototype 6's types.l2 (the validation input) and on generated programs of 25 to 1,600 functions, and reports the checker's steps, its steps per function, and the ratio at each doubling. Linear means the ratio stays near 2.0; quadratic means it climbs toward 4.0.
--
-- Only the checker's steps are reported, so the layout, lex and parse are run but not counted here.
--
--   lute run checker_scaling.luau     (from this folder; about a minute and a half)

const Lifecycle = require "../../6/interpreter/lifecycle"
const VM = require "../../6/interpreter/vm"
const Compile = require "./compile"
const O = require "./outcomes"
const V = require "./vm_values"
const fs = require "@lute/fs"

const bytesValue = V.bytesValue

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

-- The same generator as phase0.luau.
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

const layoutC = Compile.compile(readFile "boot/layout.l2", "boot/layout.l2")
const lexer = Compile.compile(readFile "../../6/L2/programs/boot/lex.l2", "boot/lex.l2")
const parser = Compile.compile(readFile "../../6/L2/programs/boot/parse.l2", "boot/parse.l2")
const checker = Compile.compile(readFile "boot/types.l2", "boot/types.l2")

-- The checker's steps for one program file text: its raw program section goes through the VM's layout, lex and parse, then the checker.
const function checkerSteps(text: string): (number, string)
	const raw = Compile.compile(text, "probe").raw
	const laid = Lifecycle.run(layoutC.expr, bytesValue(raw), 1e10)
	const lexed = Lifecycle.run(lexer.expr, O.payloadOf(O.valueOf(laid)), 1e8)
	const parsed = Lifecycle.run(parser.expr, O.payloadOf(O.valueOf(lexed)), 5e8)
	const result = Lifecycle.run(checker.expr, { kind = "con", tag = 3, payload = O.payloadOf(O.valueOf(parsed)) }, 1e10)

	return result.steps, result.status
end

local typesSteps, typesStatus = checkerSteps(readFile "../../6/L2/programs/boot/types.l2")
print(`types.l2 (Prototype 6's): checker {commas(typesSteps)} steps ({typesStatus})`)
print ""
print "functions  checker steps  steps per function  ratio to the previous size"
local previous: number? = nil
local previousN: number? = nil

for _, n in { 25, 50, 100, 200, 400, 800, 1600 } do
	const steps, status = checkerSteps(synthetic(n))
	local ratio = "-"

	if previous ~= nil then
		ratio = string.format("%.2f", steps / previous)
	end

	print(string.format("%9d  %14s  %18s  %s  (%s)", n, commas(steps), commas(math.floor(steps / n)), ratio, status))
	previous = steps
	previousN = n
end

local _ = previousN
