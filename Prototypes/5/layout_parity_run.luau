--!strict
-- THE LAYOUT PARITY CHECK, ON GENERATED INPUTS
--
-- For the program section of every L2/programs/**/*.l2 file, the section as written, and a copy of it with one line deleted, one line dedented by a tab, or one line indented by a tab. The Luau layer (L2/layout.luau) and the L2 layer (boot/layout.l2) must give the same text, or the same error message, for every input.
--
--   lute run layout_parity_run.luau      (from Prototypes/5)

const L2 = require "./L2/l2"
const Layout = require "./L2/layout"
const VM = require "./interpreter/vm"
const fs = require "@lute/fs"

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

const function bytesValue(s: string): VM.Value
	local v: VM.Value = VM.NIL

	for i = #s, 1, -1 do
		v = { kind = "cell"; head = string.byte(s, i) :: number; tail = v } :: VM.Cell
	end

	return v
end

const function textOf(v: VM.Value): string
	local out: { string } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, string.char((cur :: VM.Cell).head :: number))
		cur = (cur :: VM.Cell).tail
	end

	return table.concat(out)
end

-- The layer in L2, from boot/layout.l2, which is itself indented: the Luau layer lays it out when it is read.
const layerProgram = L2.compile(
	readFile "L2/programs/boot/layout.l2",
	function(_name: string): string?
		return nil
	end,
	"boot/layout.l2"
)

-- The L2 layer's outcome for a source: Ok of the text, or "error " and the message, as the Luau layer raises it.
const function layerInL2(src: string): string
	const outcome = L2.run(layerProgram, bytesValue(src), 1e9)

	if outcome.status ~= "value" then
		return "the L2 layer " .. outcome.status
	end

	const con = outcome.value :: VM.Con

	if con.tag == 0 then
		return textOf(con.payload)
	end

	return "error " .. textOf(con.payload)
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
listPrograms("L2/programs", "", files)
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
	print(`{f.name}: {#lines} lines`)

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

local agree = 0
local texts = 0
local errors = 0
local mismatches = 0

for _, input in inputs do
	const okA, outA = pcall(Layout.layout, input.src)
	const want =
		if okA then
			outA :: string
		else
			"error " .. tostring(outA)
	const got = layerInL2(input.src)

	if got == want then
		agree += 1

		if okA then
			texts += 1
		else
			errors += 1
		end
	else
		mismatches += 1

		if mismatches <= 20 then
			print(`MISMATCH {input.name}`)
			print(`  luau: {string.sub(want, 1, 200)}`)
			print(`  L2:   {string.sub(got, 1, 200)}`)
		end
	end
end

print(string.format("%d of %d layout inputs give the same text or error in both layers (%d texts, %d errors; %d files)", agree, #inputs, texts, errors, #files))
