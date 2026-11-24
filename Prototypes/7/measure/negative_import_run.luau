--!strict
-- THE NEGATIVE IMPORT TEST: A PROGRAM THAT USES A LIBRARY NAME IT DOES NOT IMPORT
--
-- The program calls reverse. Without an import the bootstrapped checker must report reverse as unbound, and the Luau checker must too. With reverse imported (InferI), both must check it cleanly.
--
--   lute run negative_import_run.luau

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

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

const layoutC = Compile.compile(readFile "boot/layout.l2", "boot/layout.l2")
const lexer = Compile.compile(readFile "../../6/L2/programs/boot/lex.l2", "boot/lex.l2")
const parser = Compile.compile(readFile "../../6/L2/programs/boot/parse.l2", "boot/parse.l2")
const checker = Compile.compile(readFile "boot/types.l2", "boot/types.l2")
-- The program: a function of xs that calls reverse on it.
const raw = "fn xs\n\treverse xs\n"
local laid = Lifecycle.run(layoutC.expr, bytesValue(raw), 1e10)
const lexed = Lifecycle.run(lexer.expr, O.payloadOf(O.valueOf(laid)), 1e8)
const parsed = Lifecycle.run(parser.expr, O.payloadOf(O.valueOf(lexed)), 5e8)
const program = O.payloadOf(O.valueOf(parsed))
-- The library, as the bootstrapped front end gives it.
const libRaw = ProgramFile.parse(readFile "../../6/L2/programs/lib/reverse.l2", nil).program :: string
const libLaid = Lifecycle.run(layoutC.expr, bytesValue(libRaw), 1e10)
const libLexed = Lifecycle.run(lexer.expr, O.payloadOf(O.valueOf(libLaid)), 1e8)
const libParsed = Lifecycle.run(parser.expr, O.payloadOf(O.valueOf(libLexed)), 5e8)
const libProgram = O.payloadOf(O.valueOf(libParsed))
const withoutImport = Lifecycle.run(checker.expr, { kind = "con"; tag = 3; payload = program }, 1e10)
-- The import list is a list of (name . program) pairs: one pair here, then nil.
const importPair: VM.Value = { kind = "cell"; head = bytesValue "reverse"; tail = libProgram }
const importList: VM.Value = { kind = "cell"; head = importPair; tail = VM.NIL }
const withImport = Lifecycle.run(checker.expr, { kind = "con"; tag = 4; payload = { kind = "cell"; head = importList; tail = program } }, 1e10)

const function vmErrors(r: Lifecycle.Result): string
	local msgs: { string } = {}

	for _, e in itemsOf(O.headOf(O.tailOf(O.valueOf(r)))) do
		table.insert(msgs, textOf(e))
	end

	return table.concat(msgs, "; ")
end

print(
	"VM, without the import: " .. (
		if vmErrors(withoutImport) == "" then
			"no errors"
		else
			vmErrors(withoutImport)
	)
)
print(
	"VM, with the import:    " .. (
		if vmErrors(withImport) == "" then
			"no errors"
		else
			vmErrors(withImport)
	)
)
-- The Luau checker on the same two cases.
const parsedLuau = Parser.parse(Layout.layout(raw))
local okNo, errNo = pcall(Checker.check, parsedLuau, {}, "neg")
print(
	"Luau, without the import: " .. (
		if okNo then
			"no errors"
		else
			tostring(type(errNo) == "table" and (errNo :: { typeError: unknown }).typeError or errNo)
	)
)
const libLuau = Checker.check(Parser.parse(Layout.layout(libRaw)), {}, "reverse")
local okYes, errYes = pcall(Checker.check, parsedLuau, { { name = "reverse"; scheme = libLuau.scheme } }, "neg")
print(
	"Luau, with the import:    " .. (
		if okYes then
			"no errors"
		else
			tostring(type(errYes) == "table" and (errYes :: { typeError: unknown }).typeError or errYes)
	)
)
