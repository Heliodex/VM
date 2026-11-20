--!strict
-- CHECKS THE L2 PROGRAM FILES
--
-- Compiles every .prog file in L2/programs/, runs each test through the lifecycle, and checks the outcome. An expected output is an L2 expression, evaluated on the machine, so it is compared as data and not as text. Then checks that malformed programs are refused, each with the reason it should give.
--
--   lute run l2_run.luau      (from Prototypes/5)

const fs = require "@lute/fs"
const Data = require "./interpreter/data"
const L2 = require "./L2/l2"
const ProgramFile = require "./L2/programfile"

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

-- The text of a program file in L2/programs/, or nil if there is none.
const function resolve(
	name: string
): string?
	const ok, text = pcall(readFile, `L2/programs/{name}`)

	if ok then
		return text :: string
	end

	return nil
end

-- Malformed programs, each with a fragment of the reason it should be refused.
const MALFORMED: { { name: string, text: string, reason: string } } = {
	{
		name = "a list with a dot inside it",
		text = "h\n---\n---\n[1 . 2]\n---\n1 => 1 fuel 10\n",
		reason = "expected a value here",
	},
	{
		name = "a whole integer that is not whole",
		text = "h\n---\n---\nfn x (+ 1-2 x)\n---\n1 => 1 fuel 10\n",
		reason = "is not a whole integer",
	},
	{
		name = "a ? in a non-tail if branch",
		text = "h\n---\n---\nfn s (let v = (if s (Err 1)? (Ok 2))\nv)\n---\n1 => 1 fuel 10\n",
		reason = "expected a value here",
	},
	{
		name = "a ? in a let value that is not the function's result",
		text = "h\n---\n---\nfn s (g (let v = s\nv?))\n---\n1 => 1 fuel 10\n",
		reason = "? can only be used where it runs whenever its function does",
	},
	{
		name = "a match with an arm after a catch-all",
		text = "h\n---\n---\nfn r match r {\n  x -> 1\n  Ok v -> 2\n}\n---\n1 => 1 fuel 10\n",
		reason = "unreachable",
	},
	{
		name = "a match arm body that runs past its line",
		text = "h\n---\n---\nfn r match r {\n  Ok v -> v? 2\n}\n---\n1 => 1 fuel 10\n",
		reason = "an arm ends at the end of its line",
	},
	{
		name = "a constructor bound as a name",
		text = "h\n---\n---\nlet Ok = 1\nOk\n---\n1 => 1 fuel 10\n",
		reason = "Ok cannot be bound by let",
	},
	{
		name = "a primitive bound as a name",
		text = "h\n---\n---\nlet + = 1\n+\n---\n1 => 1 fuel 10\n",
		reason = "is a primitive, and cannot be bound",
	},
	{
		name = "a let that still has in",
		text = "h\n---\n---\nlet x = 1 in x\n---\n1 => 1 fuel 10\n",
		reason = "a let value ends at the end of its line",
	},
	{
		name = "a let inside a match arm",
		text = "h\n---\n---\nfn r match r {\n\tOk v -> let y = v\n\ty\n}\n---\n1 => 1 fuel 10\n",
		reason = "needs parentheses around it",
	},
	{
		name = "a letrec that does not bind a fn",
		text = "h\n---\n---\nletrec x = 1\nx\n---\n1 => 1 fuel 10\n",
		reason = "letrec binds a fn",
	},
	{
		name = "a type declared twice with one constructor",
		text = "h\n---\n---\ntype A = Ok\ntype B = Ok\nOk\n---\n1 => 1 fuel 10\n",
		reason = "Ok is already declared",
	},
	{
		name = "an unbound name",
		text = "h\n---\n---\nfn x y\n---\n1 => 1 fuel 10\n",
		reason = "y is not bound",
	},
	{
		name = "an import of a file that is not there",
		text = "h\n---\nhelper = missing.prog\n---\nfn x x\n---\n1 => 1 fuel 10\n",
		reason = "cannot find missing.prog",
	},
	{
		name = "a file with no tests",
		text = "h\n---\n---\nfn x x\n---\n\n",
		reason = "at least one test",
	},
}

for _, case in MALFORMED do
	const ok, err = pcall(L2.compile, case.text, resolve, "malformed.prog")
	check(
		`refuses {case.name}`,
		not ok and string.find(tostring(err), case.reason, 1, true) ~= nil,
		if ok then "it compiled, but it should not" else tostring(err)
	)
end

-- Every .prog file in L2/programs/, each run with its tests, including the ones that are only imported elsewhere.
local files: { string } = {}

for _, entry in fs.listdir("L2/programs") do
	if entry.type == "file" and string.sub(entry.name, -5) == ".prog" then
		table.insert(files, entry.name)
	end
end

table.sort(files)

local tests = 0

for _, name in files do
	const ok, res = pcall(function()
		const text = readFile(`L2/programs/{name}`)
		return { file = ProgramFile.parse(text), compiled = L2.compile(text, resolve, name) }
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
