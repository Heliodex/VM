--!strict
-- CROSS-CHECKS THE REFERENCE AGAINST PROTOTYPES 5 AND 6 (Phase 3's exit test)
--
-- Every Prototype 5 example, and every test of every L2 program file in Prototype 6, is run twice: on its own machine (Prototype 5's, or Prototype 6's, through the L2 lifecycle), and on the reference, after its expressions are lowered to the core (lower.luau). The two must agree on the outcome: the same value when it is data, an error when it is an error, out of fuel when it is out of fuel, and a non-data result (a function or pin) where Prototype 6's lifecycle says not_data.
--
-- Fuel is not compared. The reference counts steps by the spec's rule, and Prototypes 5 and 6 count theirs differently, so the reference is given a budget of 20 times the other machine's fuel, and the steps of both are reported.
--
--   lute run cross_run.luau     (from Prototypes/7/reference)

const fs = require "@lute/fs"
const Int = require "./int"
const Interp = require "./interp"
const Lower = require "./lower"
const Format = require "./format"
const P5VM = require "../../5/interpreter/vm"
const P5Examples = require "../../5/examples/examples"
const L2 = require "../../6/L2/l2"
const ProgramFile = require "../../6/L2/programfile"

const NIL = Format.NIL
const P6_PROGRAMS = "../../6/L2/programs/"

local agreed = 0
local disagreed = 0
local explainedCount = 0
local skipped = 0
local details: { string } = {}

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

-- A machine value, as the reference's: integers, nil, cells and constructors deeply. A function is a marker, and so is a pin.
local function convert(v: any): any
	if type(v) == "number" then
		return v
	end

	if v.kind == "nil" then
		return NIL
	elseif v.kind == "cell" then
		return { kind = "cell", head = convert(v.head), tail = convert(v.tail) }
	elseif v.kind == "con" then
		return { kind = "con", tag = v.tag, payload = convert(v.payload) }
	elseif v.kind == "closure" then
		return { kind = "function-marker" }
	elseif v.kind == "pin" then
		return { kind = "pin-marker" }
	end

	error("cross: a machine value of kind " .. tostring(v.kind) .. " cannot be converted", 0)
end

-- A test's input, as the reference's value. Unlike a result, a function in an input is a real law: a closed closure lowered (lower.luau). An input closure with an environment is not closed, so it is refused.
local function convertInput(v: any): any
	if type(v) == "number" then
		return v
	end

	if v.kind == "closure" then
		if v.env ~= nil then
			error("cross: an input closure with an environment cannot be lowered", 0)
		end

		return Lower.closedClosure(v.body)
	elseif v.kind == "nil" then
		return NIL
	elseif v.kind == "cell" then
		return { kind = "cell", head = convertInput(v.head), tail = convertInput(v.tail) }
	elseif v.kind == "con" then
		return { kind = "con", tag = v.tag, payload = convertInput(v.payload) }
	end

	error("cross: an input value of kind " .. tostring(v.kind) .. " cannot be converted", 0)
end

-- Whether a machine value (converted) and a reference value agree. A function agrees with a law or a partial application, a pin with a pin or a thunk.
local function agree(p: any, r: any): boolean
	if type(p) == "number" then
		return (type(r) == "number" or Int.isBig(r)) and Int.compare(p, r) == 0
	end

	if p.kind == "function-marker" then
		return type(r) == "table" and (r.kind == "law" or r.kind == "app")
	end

	if p.kind == "pin-marker" then
		return type(r) == "table" and (r.kind == "pin" or r.kind == "thunk")
	end

	if p == NIL then
		return r == NIL
	end

	if type(r) ~= "table" or r.kind ~= p.kind then
		return false
	end

	if p.kind == "cell" then
		return agree(p.head, r.head) and agree(p.tail, r.tail)
	elseif p.kind == "con" then
		return p.tag == r.tag and agree(p.payload, r.payload)
	end

	return false
end

-- A disagreement is either a failure, or one of the differences the spec makes on purpose, which is named where it is recorded: the integer range (SPEC.md section 1 and decision 8), and a Prototype 5 pin, which the core models as a thunk (decision 4 and the open question in README.md).
local function record(name: string, ok: boolean, detail: string, explained: string?)
	if ok then
		agreed += 1
	elseif explained ~= nil then
		explainedCount += 1
		table.insert(details, `EXPLAINED {name}: {detail} ({explained})`)
	else
		disagreed += 1
		table.insert(details, `DISAGREE {name}: {detail}`)
	end
end

-- 1. The Prototype 5 examples: each program is an expression, run with no input.
do
	local steps5 = 0
	local steps6 = 0

	for _, ex in P5Examples do
		const p5 = P5VM.run(ex.program, ex.fuel)
		local ok = true
		local detail = ""
		local explained: string? = nil

		if p5.status == "out_of_fuel" then
			-- Both run out of fuel; the reference is given a budget of 20 times the other machine's, and must also run out.
			const r = Interp.runForm(Lower.expr(ex.program), NIL, 20 * ex.fuel)
			ok = r.status == "out_of_fuel"
			detail = `machine out of fuel, reference {r.status} after {r.steps}`
		elseif p5.status == "error" then
			const r = Interp.runForm(Lower.expr(ex.program), NIL, 20 * ex.fuel)
			ok = r.status == "error"
			detail = `machine error {tostring(p5.message)}, reference {r.status} {tostring(r.message)}`

			if not ok and r.status == "value" and string.find(tostring(p5.message), "out of range", 1, true) ~= nil then
				explained = "the integer range: the reference has no size limit, so the result is exact"
			end
		else
			const r = Interp.runForm(Lower.expr(ex.program), NIL, 20 * ex.fuel)
			ok = r.status == "value" and agree(convert(p5.value), r.value)
			detail = `machine value, reference {r.status} {if r.status == "value" and type(r.value) == "table" then "(" .. tostring(r.value.kind) .. ")" else ""}`
			steps5 += p5.steps
			steps6 += r.steps

			if not ok and ex.name == "kind of a pin" and r.status == "value" and r.value == 6 then
				explained = "a Prototype 5 pin is a suspended expression, which the core models as a thunk: kind 6, not 4"
			end
		end

		record("P5 example " .. ex.name, ok, detail, explained)
	end

	print(`Prototype 5 examples: {#P5Examples} run; steps by the machine {steps5}, by the reference {steps6}`)
end

-- 2. Every test of every L2 program file in Prototype 6.
do
	local files: { string } = {}

	const function listDir(folder: string, prefix: string)
		for _, entry in fs.listdir(folder) do
			if entry.type == "dir" then
				listDir(`{folder}/{entry.name}`, `{prefix}{entry.name}/`)
			elseif entry.type == "file" and string.sub(entry.name, -3) == ".l2" then
				table.insert(files, `{prefix}{entry.name}`)
			end
		end
	end

	listDir(P6_PROGRAMS, "")

	local tests = 0
	local steps6 = 0
	local steps7 = 0

	const function resolve(name: string): string?
		const ok, text = pcall(readFile, P6_PROGRAMS .. name)

		if ok then
			return text :: string
		end

		return nil
	end

	for _, name in files do
		const compiled = L2.compile(readFile(P6_PROGRAMS .. name), resolve, name)
		const file = ProgramFile.parse(readFile(P6_PROGRAMS .. name), name)
		const program = Lower.expr(compiled.expr)

		for _, test in file.tests do
			local ran, input = pcall(L2.evalText, compiled, test.input, L2.VALUE_FUEL)

			if not ran then
				skipped += 1
			else
				tests += 1
				const p6 = L2.run(compiled, input, test.fuel)
				const budget = 20 * test.fuel + 10000
				const r = Interp.runForm({ op = "call", f = program, args = { { op = "arg", index = 1 } } }, convertInput(input), budget)
				local ok: boolean
				local detail: string

				if p6.status == "value" then
					ok = r.status == "value" and agree(convert(p6.value), r.value)
					detail = `machine value, reference {r.status}`
					steps6 += p6.steps
					steps7 += r.steps
				elseif p6.status == "not_data" then
					ok = r.status == "value" and type(r.value) == "table" and (r.value.kind == "law" or r.value.kind == "app" or r.value.kind == "pin" or r.value.kind == "thunk")
					detail = `machine not_data, reference {r.status}`
				elseif p6.status == "error" then
					ok = r.status == "error"
					detail = `machine error {tostring(p6.message)}, reference {r.status} {tostring(r.message)}`
				else
					ok = r.status == "out_of_fuel"
					detail = `machine {p6.status}, reference {r.status} after {r.steps}`
				end

				record(`{name} test on line {test.line}`, ok, detail)
			end
		end
	end

	print(`L2 programs: {#files} files, {tests} tests run, {skipped} inputs skipped (they do not parse as values); steps by the machine {steps6}, by the reference {steps7} on the values`)
end

for _, d in details do
	print(d)
end

print(`{agreed} agree, {explainedCount} differ on purpose (named above), {disagreed} disagree`)
