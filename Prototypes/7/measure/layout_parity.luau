--!strict
-- CHECKS THE PHASE 1 LAYOUT ON THE VM AGAINST THE HOST LAYOUT, ON EVERY L2 PROGRAM FILE
--
-- For each file of Prototype 6's L2 programs (the list in results/layout_files.txt), the raw program section is laid out by the host (L2/layout.luau) and by the VM (boot/layout.l2, the Phase 1 variant). The two must agree: the same text when both succeed, and the same error message when both refuse. A file that is not indented (a .prog file) is not in the list.
--
--   lute run layout_parity.luau

const Layout = require "../../6/L2/layout"
const ProgramFile = require "../../6/L2/programfile"
const Lifecycle = require "../../6/interpreter/lifecycle"
const VM = require "../../6/interpreter/vm"
const Compile = require "./compile"
const O = require "./outcomes"
const V = require "./vm_values"
const fs = require "@lute/fs"

const bytesValue = V.bytesValue
const textOf = V.textOf
const PROGRAMS = "../../6/L2/programs/"

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

const layoutC = Compile.compile(readFile "boot/layout.l2", "boot/layout.l2")
const names = readFile "results/layout_files.txt"
local total = 0
local agreed = 0
local bothErrors = 0
local mismatches: { string } = {}
local boundaryFailures: { string } = {}

for name in string.gmatch(names, "[^\n]+") do
	local raw: string? = nil
	local ok, file = pcall(ProgramFile.parse, readFile(PROGRAMS .. name), nil)

	if ok then
		raw = file.program :: string
	end

	if raw ~= nil then
		total += 1
		local hostOk, hostResult = pcall(Layout.layout, raw)
		const vm = Lifecycle.run(layoutC.expr, bytesValue(raw), 1e10)

		if vm.status ~= "value" then
			table.insert(boundaryFailures, `{name}: the VM gave {vm.status} after {vm.steps} steps`)
		elseif hostOk then
			if O.tagOf(O.valueOf(vm)) == 0 and textOf(O.payloadOf(O.valueOf(vm))) == hostResult then
				agreed += 1
			else
				table.insert(mismatches, `{name}: the VM and the host give different text`)
			end
		else
			if O.tagOf(O.valueOf(vm)) == 1 and textOf(O.payloadOf(O.valueOf(vm))) == tostring(hostResult) then
				agreed += 1
				bothErrors += 1
			else
				table.insert(mismatches, `{name}: the host refuses ({tostring(hostResult)}) and the VM does not agree`)
			end
		end
	end
end

-- Inputs that the host refuses, one for each kind of error the layout gives, and the generated programs of the scaling runs.
const extra: { { string } } = {
	{ "tab-indent"; "fn x\n\t\tx\n" },
	{ "space-indent"; "fn x\n  x\n" },
	{ "empty"; "" },
	{ "let without body"; "fn x\n\tlet y = 1\n" },
	{ "if without else"; "fn x\n\tif x\n\t\t1\n" },
	{ "match without arms"; "fn x\n\tmatch x\n" },
	{ "record bad field"; "type T = A\n\tfoo\n\nfn x\n\t1\n" },
	{ "no expression after declarations"; "type T = A\n" },
	{ "bad arm"; "fn x\n\tmatch x\n\t\tfoo\n\t\t\t1\n" },
}

for _, case in extra do
	const raw = case[2]
	local hostOk, hostResult = pcall(Layout.layout, raw)
	const vm = Lifecycle.run(layoutC.expr, bytesValue(raw), 1e10)
	total += 1

	if vm.status ~= "value" then
		table.insert(boundaryFailures, `{case[1]}: the VM gave {vm.status}`)
	elseif hostOk then
		if O.tagOf(O.valueOf(vm)) == 0 and textOf(O.payloadOf(O.valueOf(vm))) == hostResult then
			agreed += 1
		else
			table.insert(mismatches, `{case[1]}: the VM and the host give different text`)
		end
	elseif O.tagOf(O.valueOf(vm)) == 1 and textOf(O.payloadOf(O.valueOf(vm))) == tostring(hostResult) then
		agreed += 1
		bothErrors += 1
	else
		table.insert(mismatches, `{case[1]}: the host refuses ({tostring(hostResult)}) and the VM does not agree ({textOf(O.payloadOf(O.valueOf(vm)))})`)
	end
end

for _, n in { 25; 100; 400; 800 } do
	const text = "fn x\n"
	local body = {}
	table.insert(body, "\tlet f0 = fn y")
	table.insert(body, "\t\ty")

	for i = 1, n do
		table.insert(body, string.format("\tlet f%d = fn y", i))
		table.insert(body, string.format("\t\t(+ (f%d y) %d)", i - 1, i))
	end

	table.insert(body, "\t(f" .. n .. " x)")
	const raw = text .. table.concat(body, "\n") .. "\n"
	const hostResult = Layout.layout(raw)
	const vm = Lifecycle.run(layoutC.expr, bytesValue(raw), 1e10)
	total += 1

	if vm.status == "value" and O.tagOf(O.valueOf(vm)) == 0 and textOf(O.payloadOf(O.valueOf(vm))) == hostResult then
		agreed += 1
	else
		table.insert(mismatches, `synthetic {n}: {vm.status}`)
	end
end

print(string.format("%d inputs; the VM agrees with the host on %d (%d of them refuse on both sides)", total, agreed, bothErrors))

for _, m in mismatches do
	print("  MISMATCH " .. m)
end

for _, b in boundaryFailures do
	print("  NO ANSWER " .. b)
end
