--!strict
-- GENERATES THE CHECKER FIXTURE OF THE GO PIPELINE (Prototype 8, step 1)
--
-- For each source of the checker's parity run (measure/infer_run_variant.luau): the program files of the L2 programs folder (their laid program sections), and the sources of gen/checker_sources.luau: the outcome the Luau checker gives, as the parity run writes it, or "skip" when the parser refuses the source (or a form is not handled). The Go test (fast/checker_test.go) checks the bootstrapped checker gives the same outcome.
--
-- The outcome is "type <t>" or "error <messages>", with the type variables renamed by where they first appear. The sources are hex. Run from Prototypes/7/measure:
--   cd Prototypes/7/measure && lute run ../fast/gen/checker.luau > ../fast/testdata/checker.txt

const Checker = require "../../../6/L2/checker"
const Parser = require "../../../6/L2/parser"
const ProgramFile = require "../../../6/L2/programfile"
const CASES = require "./checker_sources"
const fs = require "@lute/fs"

const PROGRAMS = "../../6/L2/programs"

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text :: string
end

const function hex(s: string): string
	return (
		string.gsub(
			s,
			".",
			function(c: string): string
				return string.format("%02x", string.byte(c))
			end
		)
	)
end

-- Renames the type variables of a message by where they first appear, as the parity run does.
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

-- The outcome of the Luau checker on a source, or nil when the parser refuses it.
const function luauOutcome(src: string): string?
	const parsedOk, parsed = pcall(Parser.parse, src)

	if not parsedOk then
		return nil
	end

	const ok, res = pcall(Checker.check, parsed, {}, "t.prog")

	if ok then
		return "type " .. canon(Checker.showScheme((res :: Checker.Result).scheme))
	end

	const message =
		if type(res) == "table" then
			(res :: { typeError: string }).typeError
		else
			tostring(res)

	return "error " .. canon(message)
end

-- The program files of the folder, recursively, as the parity run lists them.
local function listPrograms(folder: string, prefix: string, out: { { name: string; text: string } })
	for _, entry in fs.listdir(folder) do
		if entry.type == "dir" then
			listPrograms(`{folder}/{entry.name}`, `{prefix}{entry.name}/`, out)
		elseif entry.type == "file" and (string.sub(entry.name, -5) == ".prog" or string.sub(entry.name, -3) == ".l2") then
			table.insert(out, { name = `{prefix}{entry.name}`; text = readFile(`{folder}/{entry.name}`) })
		end
	end
end

local files: { { name: string; text: string } } = {}
listPrograms(PROGRAMS, "L2/", files)

local function emit(name: string, src: string)
	const outcome = luauOutcome(src) or "skip"
	print(`check {hex(name)} {hex(src)} {hex(outcome)}`)
end

for _, f in files do
	emit(f.name, ProgramFile.parse(f.text, f.name).program)
end

for i, src in CASES do
	emit(`case {i}`, src)
end
