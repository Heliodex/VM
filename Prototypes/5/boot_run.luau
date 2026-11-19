--!strict
-- CHECKS THE BOOTSTRAP READER
--
-- The bootstrap has two readers that should be the same. Stage 0 is the L1 reader in L1 (L1/programs/boot/read.prog), compiled by the Luau reader. Stage 1 is the L1 reader compiled by stage 0: stage 0 reads the reader's own source, and the quoted result is run as a reader. Then:
--
--   1. The fixed point: stage 1 reads the stage sources and the reader's source, and gives the same quoted programs as stage 0.
--   2. Stage 1 agrees with the Luau reader on every source the Luau reader is tested on, including the examples and rejects, and the program sections of every program file, the ones with imports included. Imports are bound by passing the imported programs in as values, as the Luau loader does.
--
--   lute run boot_run.luau      (from Prototypes/5)

const fs = require "@lute/fs"
const Code = require "./interpreter/code"
const Data = require "./interpreter/data"
const Lifecycle = require "./interpreter/lifecycle"
const ProgramFile = require "./L1/program_file"
const Programs = require "./L1/examples/programs"
const Reader = require "./L1/reader"
const Text = require "./L1/examples/text"
const VM = require "./interpreter/vm"

const FUEL = 1000000000

local agree = 0
local disagree = 0

const function readFile(
	path: string
): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)
	return text
end

const function resolve(
	name: string
): string?
	const ok, text = pcall(readFile, `L1/programs/{name}`)

	if ok then
		return text :: string
	end

	return nil
end

-- The bytes of a string as the list a reader takes, and a list of values.
const function bytesValue(
	s: string
): VM.Value
	local v: VM.Value = VM.NIL

	for i = #s, 1, -1 do
		v = ({ kind = "cell", head = string.byte(s, i), tail = v } :: VM.Cell)
	end

	return v
end

const function listValue(
	items: { VM.Value }
): VM.Value
	local v: VM.Value = VM.NIL

	for i = #items, 1, -1 do
		v = ({ kind = "cell", head = items[i], tail = v } :: VM.Cell)
	end

	return v
end

const function pairValue(
	a: VM.Value,
	b: VM.Value
): VM.Value
	return ({ kind = "cell", head = a, tail = b } :: VM.Cell)
end

-- The section of a program file between its second and third separators: the program.
local function sectionsOf(
	text: string
): ({ string }, string, string)
	local lines: { string } = {}

	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(lines, line)
	end

	local seps: { number } = {}

	for i, line in lines do
		if string.match(line, "^%s*(.-)%s*$") == "---" then
			table.insert(seps, i)
		end
	end

	local imports: { string } = {}

	for i = seps[1] + 1, seps[2] - 1 do
		if string.match(lines[i], "%S") then
			table.insert(imports, lines[i])
		end
	end

	return imports, table.concat(lines, "\n", seps[2] + 1, seps[3] - 1), table.concat(lines, "\n", seps[3] + 1)
end

-- Reads a source with a reader, given the names and values of its imports. A failed run is an error.
const function readWith(
	reader: VM.Expr,
	source: string,
	names: { string },
	values: { VM.Value }
): (string, VM.Value?)
	local nameValues: { VM.Value } = {}

	for _, n in names do
		table.insert(nameValues, bytesValue(n))
	end

	const input = pairValue(bytesValue(source), pairValue(listValue(nameValues), listValue(values)))
	const r = Lifecycle.run(reader, input, FUEL)

	if r.status == "value" then
		return "value", r.value
	end

	return r.status, nil
end

-- Stage 0: the reader, compiled by the Luau reader, with its imports linked the usual way.
const readerFile = ProgramFile.parse(readFile("L1/programs/boot/read.prog"), resolve, "boot/read.prog")
const stage0 = readerFile.program

const function valueOf(
	status: string,
	v: VM.Value?
): VM.Value
	if status ~= "value" or v == nil then
		error("a stage gave " .. status .. ", not a value", 0)
	end

	return v :: VM.Value
end

-- The quoted stage programs, from stage 0.
const _, tokSection = sectionsOf(readFile("L1/programs/boot/tokenize.prog"))
const _, parSection = sectionsOf(readFile("L1/programs/boot/parse.prog"))
const _, comSection = sectionsOf(readFile("L1/programs/boot/compile.prog"))
const _, readSection = sectionsOf(readFile("L1/programs/boot/read.prog"))

const QTOK = valueOf(readWith(stage0, tokSection, {}, {}))
const QPAR = valueOf(readWith(stage0, parSection, {}, {}))
const QCOM = valueOf(readWith(stage0, comSection, {}, {}))
const STAGE_NAMES = { "tok", "par", "com" }
const STAGE_VALUES = { QTOK, QPAR, QCOM }
const QREAD = valueOf(readWith(stage0, readSection, STAGE_NAMES, STAGE_VALUES))

-- Stage 1: the reader that stage 0 compiled from its own source.
const stage1 = Code.fromValue(QREAD)

local function same(
	label: string,
	a: VM.Value,
	b: VM.Value
)
	if Data.write(a) == Data.write(b) then
		agree += 1
	else
		disagree += 1
		print(`DISAGREE  {label}`)
	end
end

-- 1. The fixed point: stage 1 gives the same quoted programs as stage 0.
local _, tokSection1 = sectionsOf(readFile("L1/programs/boot/tokenize.prog"))
same("fixed point: tokenize", valueOf(readWith(stage1, tokSection1, {}, {})), QTOK)
same("fixed point: parse", valueOf(readWith(stage1, parSection, {}, {})), QPAR)
same("fixed point: compile", valueOf(readWith(stage1, comSection, {}, {})), QCOM)
same("fixed point: read", valueOf(readWith(stage1, readSection, STAGE_NAMES, STAGE_VALUES)), QREAD)

-- 2. Stage 1 agrees with the Luau reader on the sources. A source is read with no imports, unless it has some.
const function quotedOf(
	reader: VM.Expr,
	path: string
): VM.Value
	const text = readFile(`L1/programs/{path}`)
	const imports, section = sectionsOf(text)
	local names: { string } = {}
	local values: { VM.Value } = {}

	for _, line in imports do
		const name, file = string.match(line, "^%s*(%S+)%s*=%s*(%S+)%s*$")

		if name == nil then
			error(`a bad import line in {path}`, 0)
		end

		table.insert(names, name :: string)
		table.insert(values, quotedOf(reader, file :: string))
	end

	return valueOf(readWith(reader, section, names, values))
end

const function luauQuoted(
	path: string
): VM.Value
	const text = readFile(`L1/programs/{path}`)
	const program = ProgramFile.parse(text, resolve, path).program
	return Code.toValue(program)
end

local function check(
	label: string,
	source: string
)
	const refOk, ref = pcall(Reader.parse, source)
	const status, out = readWith(stage1, source, {}, {})

	if not refOk then
		if status == "error" then
			agree += 1
		else
			disagree += 1
			print(`DISAGREE  {label}: the Luau reader refuses it, the L1 reader gives {status}`)
		end
		return
	end

	const expected = Data.write(Code.toValue(ref :: VM.Expr))

	if status == "value" and out ~= nil and Data.write(out :: VM.Value) == expected then
		agree += 1
	else
		disagree += 1
		print(`DISAGREE  {label}: the L1 reader gives {status}`)
	end
end

for _, ex in Text.examples do
	check(`text example {ex.name}`, ex.source)
end

for _, ex in Programs.examples do
	check(`program example {ex.name}`, ex.source)
end

for _, source in Text.rejects do
	check(`reject {string.format("%q", source)}`, source)
end

-- Every program file, read by stage 1 with its imports, against the Luau loader.
local function walk(
	folder: string,
	prefix: string,
	out: { string }
)
	for _, entry in fs.listdir(folder) do
		if entry.type == "dir" then
			walk(`{folder}/{entry.name}`, `{prefix}{entry.name}/`, out)
		elseif entry.type == "file" and string.sub(entry.name, -5) == ".prog" then
			table.insert(out, `{prefix}{entry.name}`)
		end
	end
end

local files: { string } = {}
walk("L1/programs", "", files)
table.sort(files)

local withImports = 0

for _, name in files do
	const imports = sectionsOf(readFile(`L1/programs/{name}`))

	if #imports > 0 then
		withImports += 1
		same(`imports of {name}`, quotedOf(stage1, name), luauQuoted(name))
	else
		check(`program section of {name}`, select(2, sectionsOf(readFile(`L1/programs/{name}`))))
	end
end

print(string.format("%d agree, %d disagree (%d program files with imports checked through the linker)", agree, disagree, withImports))

if disagree > 0 then
	error(string.format("%d check(s) disagree", disagree))
end
