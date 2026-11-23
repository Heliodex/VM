--!strict
-- THE NEGATIVE IMPORT TEST: A PROGRAM THAT USES A LIBRARY NAME IT DOES NOT IMPORT
--
-- The program calls reverse. Without an import the bootstrapped checker must report reverse as unbound, and the Luau checker must too. With reverse imported (InferI), both must check it cleanly.
--
--   lute run negative_import_run.luau

const fs = require "@lute/fs"
const VM = require "../../6/interpreter/vm"
const Lifecycle = require "../../6/interpreter/lifecycle"
const Compile = require "./compile"
const ProgramFile = require "../../6/L2/programfile"
const Layout = require "../../6/L2/layout"
const Parser = require "../../6/L2/parser"
const Checker = require "../../6/L2/checker"

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

const function bytesValue(s: string): any
	local v: any = VM.NIL

	for i = #s, 1, -1 do
		v = { kind = "cell", head = string.byte(s, i), tail = v }
	end

	return v
end

const function textOf(v: any): string
	local out: { string } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, string.char(cur.head))
		cur = cur.tail
	end

	return table.concat(out)
end

local function itemsOf(v: any): { any }
	local out: { any } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, cur.head)
		cur = cur.tail
	end

	return out
end

const layoutC = Compile.compile(readFile "boot/layout.l2", "boot/layout.l2")
const lexer = Compile.compile(readFile "../../6/L2/programs/boot/lex.l2", "boot/lex.l2")
const parser = Compile.compile(readFile "../../6/L2/programs/boot/parse.l2", "boot/parse.l2")
const checker = Compile.compile(readFile "boot/types.l2", "boot/types.l2")

-- The program: a function of xs that calls reverse on it.
const raw = "fn xs\n\treverse xs\n"

local laid = Lifecycle.run(layoutC.expr, bytesValue(raw), 1e10)
const lexed = Lifecycle.run(lexer.expr, laid.value.payload, 1e8)
const parsed = Lifecycle.run(parser.expr, lexed.value.payload, 5e8)
const program = parsed.value.payload

-- The library, as the bootstrapped front end gives it.
const libRaw = ProgramFile.parse(readFile "../../6/L2/programs/lib/reverse.l2", nil).program :: string
const libLaid = Lifecycle.run(layoutC.expr, bytesValue(libRaw), 1e10)
const libLexed = Lifecycle.run(lexer.expr, libLaid.value.payload, 1e8)
const libParsed = Lifecycle.run(parser.expr, libLexed.value.payload, 5e8)
const libProgram = libParsed.value.payload

const withoutImport = Lifecycle.run(checker.expr, { kind = "con", tag = 3, payload = program }, 1e10)
const withImport = Lifecycle.run(checker.expr, { kind = "con", tag = 4, payload = { kind = "cell", head = { kind = "cell", head = bytesValue("reverse"), tail = libProgram }, tail = program } }, 1e10)

local function vmErrors(r: any): string
	local msgs: { string } = {}

	for _, e in itemsOf(r.value.tail) do
		table.insert(msgs, textOf(e))
	end

	return table.concat(msgs, "; ")
end

print("VM, without the import: " .. (if vmErrors(withoutImport) == "" then "no errors" else vmErrors(withoutImport)))
print("VM, with the import:    " .. (if vmErrors(withImport) == "" then "no errors" else vmErrors(withImport)))

-- The Luau checker on the same two cases.
const parsedLuau = Parser.parse(Layout.layout(raw))
local okNo, errNo = pcall(Checker.check, parsedLuau, {}, "neg")
print("Luau, without the import: " .. (if okNo then "no errors" else tostring(type(errNo) == "table" and (errNo :: any).typeError or errNo)))

const libLuau = Checker.check(Parser.parse(Layout.layout(libRaw)), {}, "reverse")
local okYes, errYes = pcall(Checker.check, parsedLuau, { { name = "reverse", scheme = libLuau.scheme } }, "neg")
print("Luau, with the import:    " .. (if okYes then "no errors" else tostring(type(errYes) == "table" and (errYes :: any).typeError or errYes)))
