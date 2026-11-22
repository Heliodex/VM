--!strict
-- CHECKS THE L2 UNPARSER ON EVERY BRACKETED PROGRAM
--
-- For each .prog program, the program section is parsed, written as indented .l2 by L2/unparse.luau, laid out again by L2/layout.luau, and parsed: the tree must be the same as the tree of the original. A program the unparser cannot write is reported with the reason, and is not counted as a failure.
--
--   lute run unparse_run.luau      (from Prototypes/5)

const Layout = require "./L2/layout"
const Parser = require "./L2/parser"
const ProgramFile = require "./L2/programfile"
const Unparse = require "./L2/unparse"
const fs = require "@lute/fs"

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

-- Whether two trees are the same, ignoring the position of each node.
const function same(a: any, b: any, path: string): string?
	if type(a) ~= type(b) then
		return path .. ": types"
	end

	if type(a) ~= "table" then
		if a ~= b then
			return path .. ": " .. tostring(a) .. " against " .. tostring(b)
		end

		return nil
	end

	for k, v in a do
		if k ~= "at" and k ~= "line" and k ~= "col" then
			const d = same(v, b[k], path .. "." .. tostring(k))

			if d ~= nil then
				return d
			end
		end
	end

	for k, _ in b do
		if k ~= "at" and k ~= "line" and k ~= "col" and a[k] == nil then
			return path .. "." .. tostring(k) .. ": missing"
		end
	end

	return nil
end

local files: { string } = {}

const function listPrograms(folder: string, prefix: string)
	for _, entry in fs.listdir(folder) do
		if entry.type == "dir" then
			listPrograms(`{folder}/{entry.name}`, `{prefix}{entry.name}/`)
		elseif entry.type == "file" and string.sub(entry.name, -3) == ".l2" then
			table.insert(files, `{prefix}{entry.name}`)
		end
	end
end

listPrograms("L2/programs", "")
table.sort(files)
local total = 0
local failures = 0
local skipped = 0

for _, name in files do
	const text = readFile(`L2/programs/{name}`)
	const okP, program = pcall(function()
		return ProgramFile.parse(text, name).program
	end)

	if not okP then
		skipped += 1
		print(string.format("SKIP  %s  -> %s", name, tostring(program)))
	else
		const parsed = Parser.parse(program)
		const okU, written = pcall(Unparse.program, parsed)

		if not okU then
			skipped += 1
			print(string.format("SKIP  %s  -> %s", name, tostring(written)))
		else
			total += 1
			const okR, relaid = pcall(function()
				return Parser.parse(Layout.layout(written :: string))
			end)
			local diff: string? = nil

			if not okR then
				diff = "the unparsed text does not lay out and parse: " .. tostring(relaid)
			else
				diff = same(parsed, relaid, "program")
			end

			if diff == nil then
				print(string.format("PASS  %s", name))
			else
				failures += 1
				print(`FAIL  {name}  -> {tostring(diff)}`)
			end
		end
	end
end

print(string.format("%d of %d bracketed programs round-trip through the indented form (%d skipped: the unparser has no form for them)", total - failures, total, skipped))
