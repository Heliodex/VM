--!strict
-- CHECKS THE PRINTER
--
-- Checks interpreter/printer.luau: the text for given programs, the refusal of an unbound variable, and a round trip for every example program. Reading the printed text must give the same expression, which is checked by comparing the binary encodings of the two.
--
--   luau printer_run.luau      (from Prototypes/5)

const Binary = require "./interpreter/binary"
const Examples = require "./examples/examples"
const Programs = require "./L1/examples/programs"
const Printer = require "./L1/printer"
const Reader = require "./L1/reader"
const Text = require "./L1/examples/text"
const VM = require "./interpreter/vm"

local failures = 0
local total = 0

const function check(
	name: string,
	ok: boolean,
	detail: string
)
	total += 1

	if ok then
		print(string.format("PASS  %s  -> %s", name, detail))
	else
		failures += 1
		print(string.format("FAIL  %s  -> %s", name, detail))
	end
end

-- Programs and the text they should print as.
const TEXTS: { { source: string, text: string } } = {
	{ source = "(fn x (+ x 1))", text = "(fn v0 (+ v0 1))" },
	{ source = "((fn x (fn y [y x])) 1 2)", text = "((fn v0 (fn v1 [v1 v0])) 1 2)" },
	{ source = "[1 ~]", text = "[1 ~]" },
	{ source = "(pin (force (head [1 ~])))", text = "(pin (force (head [1 ~])))" },
	{ source = "(fn x (if x (kind x) (- x 3)))", text = "(fn v0 (if v0 (kind v0) (- v0 3)))" },
	{ source = "(fn x (fn y (mod (div x y) x)))", text = "(fn v0 (fn v1 (mod (div v0 v1) v0)))" },
	{ source = "[1 [2 [3 ~]]]", text = "[1 2 3 ~]" },
	{ source = "[1 [2 3]]", text = "[1 2 3]" },
	{ source = "[[1 2] 3]", text = "[[1 2] 3]" },
	{ source = "-3", text = "-3" },
	{ source = "~", text = "~" },
}

for _, case in TEXTS do
	const printed = Printer.print(Reader.parse(case.source))
	check(`prints {case.source}`, printed == case.text, printed)
end

-- A variable with no binder around it cannot be printed. The reader would not accept the text either.
for _, e in { VM.var(0), VM.lam(VM.var(1)) } do
	const ok, err = pcall(Printer.print, e)
	check("refuses an unbound variable", not ok and string.find(tostring(err), "has no binder around it", 1, true) ~= nil, tostring(err))
end

-- A round trip for a program: printed, then read, the same expression, and printing it again gives the same text.
local roundTrips = 0
const function roundTrip(
	name: string,
	program: VM.Expr
)
	local printOk, printed = pcall(Printer.print, program)

	-- A program with a variable that has no binder cannot be printed, and the printer must say so, not print something else.
	if not printOk then
		check(`refuses {name}`, string.find(tostring(printed), "has no binder around it", 1, true) ~= nil, tostring(printed))
		return
	end

	local readOk, back = pcall(Reader.parse, printed :: string)

	if not readOk then
		check(`round trip {name}`, false, tostring(back))
		return
	end

	roundTrips += 1
	const same = Binary.encodeProgram(back :: VM.Expr) == Binary.encodeProgram(program)
	const again = Printer.print(back :: VM.Expr) == printed

	check(`round trip {name}`, same and again, printed)
end

for _, ex in Examples do
	roundTrip(ex.name, ex.program)
end

for _, ex in Text.examples do
	roundTrip(ex.name, ex.program)
end

for _, ex in Programs.examples do
	roundTrip(ex.name, ex.program)
end

print(string.format("%d of %d checks passed (%d example programs round-tripped)", total - failures, total, roundTrips))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
