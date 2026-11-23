--!strict
-- CHECKS THE IMPORTS OF THE BOOTSTRAPPED CHECKER (boot/types.l2, Req InferI) AGAINST THE LUAU CHECKER
--
-- For each corpus file that imports library code (lex.l2 and parse.l2 import reverse and append), the file is laid out, lexed and parsed on the VM, and so is each library it imports. The VM's checker then gets the imports as InferI (name . parsed library) and the parsed file, and gives its type and errors. The Luau checker checks the same file with the same libraries, given as import schemes. The two must agree: no errors on either side, and the same type text, up to the names of type variables.
--
-- A file that imports nothing is checked by the same request, with no imports, so the old path is covered too.
--
--   lute run imports_run.luau     (from this folder)

const Checker = require "../../6/L2/checker"
const Layout = require "../../6/L2/layout"
const Parser = require "../../6/L2/parser"
const ProgramFile = require "../../6/L2/programfile"
const Lifecycle = require "../../6/interpreter/lifecycle"
const VM = require "../../6/interpreter/vm"
const Compile = require "./compile"
const O = require "./outcomes"
const V = require "./vm_values"
const fs = require "@lute/fs"

const bytesValue = V.bytesValue
const textOf = V.textOf
const itemsOf = V.itemsOf
const P6 = "../../6/L2/programs/"
const P6BOOT = P6 .. "boot/"

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

-- The items of a VM list, in order.
-- Renames type variables by where they first appear, so that two checkers which number them differently agree.
const function canon(s: string): string
	local names: { [string]: string } = {}
	local count = 0

	return (
		string.gsub(
			s,
			"%?(%d+)",
			function(id: string): string
				if names[id] == nil then
					count += 1
					names[id] = `?v{count}`
				end

				return names[id]
			end
		)
	)
end

const layoutC = Compile.compile(readFile "boot/layout.l2", "boot/layout.l2")
const lexer = Compile.compile(readFile(P6BOOT .. "lex.l2"), "boot/lex.l2")
const parser = Compile.compile(readFile(P6BOOT .. "parse.l2"), "boot/parse.l2")
const checker = Compile.compile(readFile "boot/types.l2", "boot/types.l2")

-- The VM's front end on a raw program section: layout, lex, parse. Gives the parsed program, or the message of the stage that refuses.
const function vmParse(raw: string): (VM.Value?, string?)
	const laid = Lifecycle.run(layoutC.expr, bytesValue(raw), 1e10)

	if laid.status ~= "value" or O.tagOf(O.valueOf(laid)) ~= 0 then
		return nil, "layout " .. laid.status
	end

	const lexed = Lifecycle.run(lexer.expr, O.payloadOf(O.valueOf(laid)), 1e8)

	if lexed.status ~= "value" then
		return nil, "lex " .. lexed.status
	end

	const parsed = Lifecycle.run(parser.expr, O.payloadOf(O.valueOf(lexed)), 5e8)

	if parsed.status ~= "value" or O.tagOf(O.valueOf(parsed)) ~= 0 then
		return nil, "parse " .. parsed.status
	end

	return O.payloadOf(O.valueOf(parsed)), nil
end

local failures = 0

const function checkFile(name: string)
	const text = readFile(P6BOOT .. name)
	const file = ProgramFile.parse(text, nil)
	const raw = file.program :: string
	-- The VM: each import's parsed program, then the request.
	local importCells: VM.Value = VM.NIL
	local libraries: { { name: string; laid: string } } = {}

	for _, imp in file.imports do
		const libFile = ProgramFile.parse(readFile(P6 .. imp.file), nil)
		const libProgram, err = vmParse(libFile.program :: string)

		if libProgram == nil then
			print(`  {name}: the library {imp.file} refuses on the VM: {err}`)
			failures += 1

			return
		end

		const pairCell: VM.Cell = { kind = "cell"; head = bytesValue(imp.name); tail = libProgram }
		const listCell: VM.Cell = { kind = "cell"; head = pairCell; tail = importCells }
		importCells = listCell
		table.insert(libraries, { name = imp.name; laid = Layout.layout(libFile.program :: string) })
	end

	-- Reversed by construction; put them back in order so the order matches the Luau side.
	local ordered: VM.Value = VM.NIL

	for _, item in itemsOf(importCells) do
		const orderedCell: VM.Cell = { kind = "cell"; head = item; tail = ordered }
		ordered = orderedCell
	end

	const targetProgram, targetErr = vmParse(raw)

	if targetProgram == nil then
		print(`  {name}: the file refuses on the VM: {targetErr}`)
		failures += 1

		return
	end

	const requestCell: VM.Cell = { kind = "cell"; head = ordered; tail = targetProgram }
	const request: VM.Con = { kind = "con"; tag = 4; payload = requestCell }
	const result = Lifecycle.run(checker.expr, request, 1e10)

	if result.status ~= "value" then
		print(`  {name}: the VM checker {result.status}`)
		failures += 1

		return
	end

	const vmText = textOf(O.headOf(O.valueOf(result)))
	local vmErrors: { string } = {}

	for _, e in itemsOf(O.tailOf(O.valueOf(result))) do
		table.insert(vmErrors, textOf(e))
	end

	-- The Luau side, with the same libraries as import schemes.
	local importSchemes: { { name: string; scheme: Checker.Scheme } } = {}

	for _, lib in libraries do
		const libProgram = Parser.parse(lib.laid)
		const libChecked = Checker.check(libProgram, {}, lib.name)
		table.insert(importSchemes, { name = lib.name; scheme = libChecked.scheme })
	end

	local luauText = ""
	local luauOk = true
	const parsedLuau = Parser.parse(Layout.layout(raw))
	const okCheck, res = pcall(Checker.check, parsedLuau, importSchemes, name)

	if okCheck then
		luauText = Checker.showScheme(res.scheme)
	else
		luauOk = false
		luauText = tostring(res)
	end

	-- The Luau checker prints the program's scheme; the VM gives the type. Drop the quantifier of the scheme before comparing.
	const luauType = (string.gsub(luauText, "forall [^.]*%. ", ""))
	local agree = false

	if luauOk then
		agree = #vmErrors == 0 and canon(vmText) == canon(luauType)
	else
		agree = #vmErrors > 0
	end

	print(`{name}: {#libraries} imports`)
	print(
		`  VM:   {
			if #vmErrors == 0 then
				"no errors"
			else
				table.concat(vmErrors, "; ")
		}`
	)
	print(`        type {vmText}`)
	print(
		`  Luau: {
			if luauOk then
				"no errors"
			else
				luauText
		}`
	)
	print(
		`        type {
			if luauOk then
				luauType
			else
				"(none)"
		}`
	)
	print(
		`  {
			if agree then
				"AGREE"
			else
				"DISAGREE"
		}`
	)

	if not agree then
		failures += 1
	end
end

checkFile "lex.l2"
checkFile "parse.l2"
checkFile "layout.l2"
checkFile "types.l2"
print(`{failures} failures`)
