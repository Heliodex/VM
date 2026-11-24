--!strict
-- GENERATES THE LAYOUT FIXTURE OF THE GO PIPELINE (Prototype 8, step 1)
--
-- The layout parity run's inputs (Prototypes/6/layout_parity_run.luau): the program section of every L2 program file, and a copy of each with one line deleted, dedented or indented, and four snippets. For each input, the Luau layout's output, or "error " and its message, as the parity run compares them. The Go test (fast/layout_test.go) must give the same for the bootstrapped layout stage.
--
-- Run from Prototypes/7/measure:
--   cd Prototypes/7/measure && lute run ../fast/gen/layout.luau > ../fast/testdata/layout.txt

const Layout = require "../../../6/L2/layout"
const fs = require "@lute/fs"

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

-- The lines of a file's program section: between its second and third lines of ---.
const function programLines(text: string): { string }
	local lines: { string } = {}

	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(lines, line)
	end

	local seps: { number } = {}

	for i, l in lines do
		if l == "---" then
			table.insert(seps, i)
		end
	end

	local out: { string } = {}

	if #seps ~= 3 then
		return out
	end

	for i = seps[2] + 1, seps[3] - 1 do
		table.insert(out, lines[i])
	end

	return out
end

const function copyWith(lines: { string }, i: number, replacement: string?): string
	local out: { string } = {}

	for j, l in lines do
		if j == i then
			if replacement ~= nil then
				table.insert(out, replacement :: string)
			end
		else
			table.insert(out, l)
		end
	end

	return table.concat(out, "\n")
end

local function listPrograms(folder: string, prefix: string, files: { { name: string; path: string } })
	for _, entry in fs.listdir(folder) do
		if entry.type == "dir" then
			listPrograms(`{folder}/{entry.name}`, `{prefix}{entry.name}/`, files)
		elseif entry.type == "file" and string.sub(entry.name, -3) == ".l2" then
			table.insert(files, { name = `{prefix}{entry.name}`; path = `{folder}/{entry.name}` })
		end
	end
end

local files: { { name: string; path: string } } = {}
listPrograms("../../6/L2/programs", "", files)
table.sort(
	files,
	function(a: { name: string; path: string }, b: { name: string; path: string })
		return a.name < b.name
	end
)
local MAX_LINES = 40
local inputs: { { name: string; src: string } } = {}

for _, f in files do
	const lines = programLines(readFile(f.path))

	if #lines == 0 then
		print(`!!! {f.name}: its program section is not found`)
	else
		table.insert(inputs, { name = `{f.name} as written`; src = table.concat(lines, "\n") })
		-- A long file is sampled: at most MAX_LINES lines are mutated, spread evenly through it, so every file is checked.
		const stride = math.max(1, math.ceil(#lines / MAX_LINES))

		for i = 1, #lines, stride do
			const l = lines[i]
			table.insert(inputs, { name = `{f.name} line {i} deleted`; src = copyWith(lines, i, nil) })

			if string.sub(l, 1, 1) == "\t" then
				table.insert(inputs, { name = `{f.name} line {i} dedented`; src = copyWith(lines, i, string.sub(l, 2)) })
			end

			table.insert(inputs, { name = `{f.name} line {i} indented`; src = copyWith(lines, i, "\t" .. l) })
		end
	end
end

-- Snippets that the generated inputs did not cover: a capitalised line with an argument and nothing below it, which is an application, not a record.
const SNIPPETS = {
	"let lineErr = fn (ln msg)\n\tErr msg\nlet isLowerB = fn c\n\tc\nfn x\n\tx",
	"let f = fn x\n\tErr (g x)\nb",
	"fn x\n\tOk 1",
	"let f = fn x\n\tOk x\nf 1",
}

for i, src in SNIPPETS do
	table.insert(inputs, { name = `snippet {i}`; src = src })
end


-- One line per input: its name (which the Go test rebuilds the input from), whether the layout gives text or an error, and the text's hex or the error's message in hex. A text is written as its hex here, and layout_digest.py replaces it with its SHA-256.
local function emit(name: string, src: string)
	const okA, outA = pcall(Layout.layout, src)

	if okA then
		print(`layout {hex(name)} text {hex(outA :: string)}`)
	else
		print(`layout {hex(name)} error {hex(tostring(outA))}`)
	end
end

for _, input in inputs do
	emit(input.name, input.src)
end
