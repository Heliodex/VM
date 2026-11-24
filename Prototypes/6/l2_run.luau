--!strict
-- CHECKS THE L2 PROGRAM FILES
--
-- Compiles every .prog file in L2/programs/, runs each test through the lifecycle, and checks the outcome. An expected output is an L2 expression, evaluated on the machine, so it is compared as data and not as text. Then checks that malformed programs are refused, each with the reason it should give.
--
--   lute run l2_run.luau      (from Prototypes/5)

const L2 = require "./L2/l2"
const ProgramFile = require "./L2/programfile"
const Data = require "./interpreter/data"
const fs = require "@lute/fs"

local failures = 0
local total = 0

const function check(name: string, ok: boolean, detail: string)
	total += 1

	if ok then
		print(string.format("PASS  %s  -> %s", name, detail))
	else
		failures += 1
		print(string.format("FAIL  %s  -> %s", name, detail))
	end
end

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

-- The text of a program file in L2/programs/, or nil if there is none.
const function resolve(name: string): string?
	const ok, text = pcall(readFile, `L2/programs/{name}`)

	if ok then
		return text :: string
	end

	return nil
end

-- Malformed programs, each with a fragment of the reason it should be refused (shared with the bootstrapped compiler's runner).
const MALFORMED = require "./L2/malformed"

for _, case in MALFORMED do
	const ok, err = pcall(L2.compile, case.text, resolve, "malformed.prog")
	check(
		`refuses {case.name}`,
		not ok and string.find(tostring(err), case.reason, 1, true) ~= nil,
		if ok then
			"it compiled, but it should not"
		else
			tostring(err)
	)
end

-- Every .prog file in L2/programs/, each run with its tests, including the ones that are only imported elsewhere.
local files: { string } = {}

-- Lists the program files in a folder, and in its subfolders, with their paths from the top of L2/programs.
local function listPrograms(folder: string, prefix: string, out: { string })
	for _, entry in fs.listdir(folder) do
		if entry.type == "dir" then
			listPrograms(`{folder}/{entry.name}`, `{prefix}{entry.name}/`, out)
		elseif entry.type == "file" and (string.sub(entry.name, -5) == ".prog" or string.sub(entry.name, -3) == ".l2") then
			table.insert(out, `{prefix}{entry.name}`)
		end
	end
end

listPrograms("L2/programs", "", files)
table.sort(files)
local tests = 0

for _, name in files do
	const ok, res = pcall(function()
		const text = readFile(`L2/programs/{name}`)

		return {
			file = ProgramFile.parse(text, name),
			compiled = L2.compile(text, resolve, name),
		}
	end)

	if not ok then
		total += 1
		failures += 1
		print(`FAIL  {name}  -> {tostring(res)}`)
	else
		const file = res.file
		const compiled = res.compiled

		for _, test in file.tests do
			tests += 1
			const ran, input = pcall(L2.evalText, compiled, test.input, L2.VALUE_FUEL)

			if not ran then
				check(`{name}:{test.line}`, false, `the input {test.input}: {tostring(input)}`)
			else
				const result = L2.run(compiled, input, test.fuel)
				local got: string
				local pass: boolean

				if result.status == "value" then
					got = Data.write(result.value)

					if test.outcome == "value" then
						const expected = L2.evalText(compiled, test.output :: string, L2.VALUE_FUEL)
						pass = got == Data.write(expected)
					else
						pass = false
					end
				else
					got = result.status
					pass = test.outcome == result.status
				end

				-- The step count is shown so a test that is close to its fuel can be seen.
				check(`{name}:{test.line}`, pass, `{got} in {result.steps} steps (fuel {test.fuel})`)
			end
		end
	end
end

print(string.format("%d of %d checks passed (%d program files, %d tests)", total - failures, total, #files, tests))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
