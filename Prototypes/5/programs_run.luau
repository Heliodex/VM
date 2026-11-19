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

-- Malformed files, each with a fragment of the reason it should be refused.
const MALFORMED: { { name: string, text: string, reason: string } } = {
	{
		name = "a file with one separator",
		text = "header\n---\n(lam x x)\n1 => 1 fuel 10\n",
		reason = "three sections",
	},
	{
		name = "a test with no =>",
		text = "h\n---\n(lam x x)\n---\n1 1 fuel 10\n",
		reason = "needs => between",
	},
	{
		name = "a test with no fuel",
		text = "h\n---\n(lam x x)\n---\n1 => 1\n",
		reason = "needs fuel",
	},
	{
		name = "a test with zero fuel",
		text = "h\n---\n(lam x x)\n---\n1 => 1 fuel 0\n",
		reason = "above zero",
	},
	{
		name = "an input that is not canonical data",
		text = "h\n---\n(lam x x)\n---\n007 => 7 fuel 10\n",
		reason = "not in canonical form",
	},
	{
		name = "a program with an unbound name",
		text = "h\n---\n(lam x y)\n---\n1 => 1 fuel 10\n",
		reason = "line 3: y is not bound",
	},
	{
		name = "a file with no tests",
		text = "h\n---\n(lam x x)\n---\n\n",
		reason = "at least one test",
	},
}

for _, case in MALFORMED do
	const ok, err = pcall(ProgramFile.parse, case.text)
	check(
		`refuses {case.name}`,
		not ok and string.find(tostring(err), case.reason, 1, true) ~= nil,
		if ok then "it parsed, but it should not" else tostring(err)
	)
end

-- Every .prog file in programs/.
local files: { string } = {}

for _, entry in fs.listdir("programs") do
	if entry.type == "file" and string.sub(entry.name, -5) == ".prog" then
		table.insert(files, entry.name)
	end
end

table.sort(files)

local tests = 0

for _, name in files do
	const path = `programs/{name}`
	const ok, parsed = pcall(function()
		return ProgramFile.parse(readFile(path))
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
