--!strict
-- CHECKS THE BOOTSTRAP READER
--
-- Runs the L1 reader, written in L1 (L1/programs/boot/read.prog), on every source that the Luau reader is tested on, and checks that it gives the same expression, or refuses the source where the Luau reader refuses it. The expression is compared by its quoted form, written as data.
--
-- The sources are the examples, the rejects, the program sections of the program files that import nothing, and the sources of the bootstrap's own stages, so the L1 reader reads the code that is the L1 reader.
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
local skipped = 0

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

-- The bytes of a source, as the list the boot reader takes as its input.
const function bytesValue(
	s: string
): VM.Value
	local v: VM.Value = VM.NIL

	for i = #s, 1, -1 do
		v = ({ kind = "cell", head = string.byte(s, i), tail = v } :: VM.Cell)
	end

	return v
end

-- The boot reader, loaded from its program file.
const bootFile = ProgramFile.parse(readFile("L1/programs/boot/read.prog"), resolve, "boot/read.prog")
const boot = bootFile.program

-- Checks one source. The Luau reader decides what the answer should be.
local function check(
	label: string,
	source: string
)
	const refOk, ref = pcall(Reader.parse, source)
	const bootResult = Lifecycle.run(boot, bytesValue(source), FUEL)

	if not refOk then
		if bootResult.status == "error" then
			agree += 1
		else
			disagree += 1
			print(`DISAGREE  {label}: the Luau reader refuses it, the L1 reader gives {bootResult.status}`)
		end
		return
	end

	const expected = Data.write(Code.toValue(ref :: VM.Expr))

	if bootResult.status == "value" and Data.write(bootResult.value) == expected then
		agree += 1
	else
		disagree += 1
		print(`DISAGREE  {label}: the L1 reader gives {bootResult.status}`)
	end
end

-- The examples, and the sources that must not read.
for _, ex in Text.examples do
	check(`text example {ex.name}`, ex.source)
end

for _, ex in Programs.examples do
	check(`program example {ex.name}`, ex.source)
end

for _, source in Text.rejects do
	check(`reject {string.format("%q", source)}`, source)
end

-- The program sections of the program files. A file with imports is skipped, since its names are not in scope for the reader alone.
local function sectionOf(
	text: string
): string
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

	return table.concat(lines, "\n", seps[#seps - 1] + 1, seps[#seps] - 1)
end

local function importsOf(
	text: string
): boolean
	local lines: { string } = {}

	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(lines, line)
	end

	local first: number? = nil

	for i, line in lines do
		if string.match(line, "^%s*(.-)%s*$") == "---" then
			first = i
			break
		end
	end

	local second: number? = nil

	for i = (first :: number) + 1, #lines do
		if string.match(lines[i], "^%s*(.-)%s*$") == "---" then
			second = i
			break
		end
	end

	for i = (first :: number) + 1, (second :: number) - 1 do
		if string.match(lines[i], "%S") then
			return true
		end
	end

	return false
end

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

for _, name in files do
	const text = readFile(`L1/programs/{name}`)

	if importsOf(text) then
		skipped += 1
	else
		check(`program section of {name}`, sectionOf(text))
	end
end

print(string.format("%d agree, %d disagree, %d files with imports skipped", agree, disagree, skipped))

if disagree > 0 then
	error(string.format("%d source(s) disagree", disagree))
end
