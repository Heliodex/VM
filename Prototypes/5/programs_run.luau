--!strict
-- CHECKS THE PROGRAM FILES
--
-- Runs every test in every .prog file in programs/, through the lifecycle, and checks that each file's outcome matches its test. Then checks that malformed files are refused, each with the reason it should give.
--
--   lute run programs_run.luau      (from Prototypes/5)

const fs = require "@lute/fs"
const Data = require "./interpreter/data"
const Lifecycle = require "./interpreter/lifecycle"
const ProgramFile = require "./interpreter/program_file"

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

const function readFile(
	path: string
): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)
	return text
end

-- The text of a program file in programs/, or nil if there is none. Imports are looked up here.
const function resolve(
	name: string
): string?
	const ok, text = pcall(readFile, `programs/{name}`)

	if ok then
		return text :: string
	end

	return nil
end

-- Malformed files, each with a fragment of the reason it should be refused.
const MALFORMED: { { name: string, text: string, reason: string } } = {
	{
		name = "a file with one separator",
		text = "header\n---\n(lam x x)\n1 => 1 fuel 10\n",
		reason = "four sections",
	},
	{
		name = "a test with no =>",
		text = "h\n---\n---\n(lam x x)\n---\n1 1 fuel 10\n",
		reason = "needs => between",
	},
	{
		name = "a test with no fuel",
		text = "h\n---\n---\n(lam x x)\n---\n1 => 1\n",
		reason = "needs fuel",
	},
	{
		name = "a test with zero fuel",
		text = "h\n---\n---\n(lam x x)\n---\n1 => 1 fuel 0\n",
		reason = "above zero",
	},
	{
		name = "an input that is a function",
		text = "h\n---\n---\n(lam x x)\n---\n(lam y y) => 1 fuel 10\n",
		reason = "the input is not data",
	},
	{
		name = "an input that raises an error",
		text = "h\n---\n---\n(lam x x)\n---\n(head 5) => 1 fuel 10\n",
		reason = "the input raises an error: head of a non-cell",
	},
	{
		name = "an output that is a function",
		text = "h\n---\n---\n(lam x x)\n---\n1 => (lam y y) fuel 10\n",
		reason = "the output is not data",
	},
	{
		name = "an output that does not read",
		text = "h\n---\n---\n(lam x x)\n---\n1 => (lam y fuel 10\n",
		reason = "the output: ( is never closed",
	},
	{
		name = "a program with an unbound name",
		text = "h\n---\n---\n(lam x y)\n---\n1 => 1 fuel 10\n",
		reason = "line 4: y is not bound",
	},
	{
		name = "an import line with no =",
		text = "h\n---\nhelper.prog\n---\n(lam x x)\n---\n1 => 1 fuel 10\n",
		reason = "an import is name = file",
	},
	{
		name = "an import whose name is reserved",
		text = "h\n---\nlam = helper.prog\n---\n(lam x x)\n---\n1 => 1 fuel 10\n",
		reason = "lam is not a name that can be bound",
	},
	{
		name = "an import of a file that is not there",
		text = "h\n---\nhelper = missing.prog\n---\n(lam x x)\n---\n1 => 1 fuel 10\n",
		reason = "cannot find missing.prog",
	},
	{
		name = "an import above the programs folder",
		text = "h\n---\nx = ../outside.prog\n---\n(lam x x)\n---\n1 => 1 fuel 10\n",
		reason = "../outside.prog is outside the programs folder",
	},
	{
		name = "a file with no tests",
		text = "h\n---\n---\n(lam x x)\n---\n\n",
		reason = "at least one test",
	},
}

for _, case in MALFORMED do
	const ok, err = pcall(ProgramFile.parse, case.text, resolve, "malformed.prog")
	check(
		`refuses {case.name}`,
		not ok and string.find(tostring(err), case.reason, 1, true) ~= nil,
		if ok then "it parsed, but it should not" else tostring(err)
	)
end

-- A cycle: a file that imports itself through another file. The loop is found when loop.prog is loaded, so the whole load is refused.
do
	const files: { [string]: string } = {
		["loop.prog"] = "h\n---\nagain = loop.prog\n---\n(lam x x)\n---\n1 => 1 fuel 10\n",
	}
	const ok, err = pcall(
		ProgramFile.parse,
		"h\n---\nstart = loop.prog\n---\n(lam x x)\n---\n1 => 1 fuel 10\n",
		function(name: string): string?
			return files[name]
		end,
		"top.prog"
	)
	check(
		"refuses an import cycle",
		not ok and string.find(tostring(err), "form a cycle through loop.prog", 1, true) ~= nil,
		tostring(err)
	)
end

-- A cycle through folders: lib/a.prog and extras/b.prog import each other by paths from the top of the folder.
do
	const files: { [string]: string } = {
		["lib/a.prog"] = "h\n---\nb = extras/b.prog\n---\n(lam x x)\n---\n1 => 1 fuel 10\n",
		["extras/b.prog"] = "h\n---\na = lib/a.prog\n---\n(lam x x)\n---\n1 => 1 fuel 10\n",
	}
	const ok, err = pcall(
		ProgramFile.parse,
		"h\n---\na = lib/a.prog\n---\n(lam x x)\n---\n1 => 1 fuel 10\n",
		function(name: string): string?
			return files[name]
		end,
		"top.prog"
	)
	check(
		"refuses a cycle through folders",
		not ok and string.find(tostring(err), "form a cycle through lib/a.prog", 1, true) ~= nil,
		tostring(err)
	)
end

-- Every .prog file in programs/, and in its folders, by its path from programs/. Each has its tests run, including the ones that are only imported elsewhere.
local function listPrograms(
	folder: string,
	prefix: string,
	out: { string }
)
	for _, entry in fs.listdir(folder) do
		if entry.type == "dir" then
			listPrograms(`{folder}/{entry.name}`, `{prefix}{entry.name}/`, out)
		elseif entry.type == "file" and string.sub(entry.name, -5) == ".prog" then
			table.insert(out, `{prefix}{entry.name}`)
		end
	end
end

local files: { string } = {}
listPrograms("programs", "", files)

table.sort(files)

local tests = 0

for _, name in files do
	const path = `programs/{name}`
	const ok, parsed = pcall(function()
		return ProgramFile.parse(readFile(path), resolve, name)
	end)

	if not ok then
		total += 1
		failures += 1
		print(`FAIL  {name}  -> {tostring(parsed)}`)
	else
		for _, test in parsed.tests do
			tests += 1
			const result = Lifecycle.run(parsed.program, test.input, test.fuel)
			local got: string
			local pass: boolean

			if result.status == "value" then
				got = Data.write(result.value)
				pass = test.outcome == "value" and got == test.output
			else
				got = result.status
				pass = test.outcome == result.status
			end

			-- The step count is shown so a test that is close to its fuel can be seen.
			check(`{name}:{test.line}`, pass, `{got} in {result.steps} steps (fuel {test.fuel})`)
		end
	end
end

print(string.format("%d of %d checks passed (%d program files, %d tests)", total - failures, total, #files, tests))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
