--!strict
-- CHECKS THE L2 TOKENIZER, WRITTEN IN L2, AGAINST THE LUAU LEXER
--
-- L2/programs/boot/lex.prog is the tokenizer in L2. For every input here, both lexers run on the same text, and the results must agree: the same tokens, with the same kinds, values, lines, columns and spacing, or the same error message. The inputs are every program file in L1 and L2, and a set of edge cases.
--
--   lute run lex_run.luau      (from Prototypes/5)

const L2 = require "./L2/l2"
const Lexer = require "./L2/lexer"
const ProgramFile = require "./L2/programfile"
const Data = require "./interpreter/data"
const VM = require "./interpreter/vm"
const fs = require "@lute/fs"

local failures = 0
local total = 0
local tokenLists = 0
local errors = 0

local function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

local function resolve(name: string): string?
	const ok, text = pcall(readFile, `L2/programs/{name}`)

	if ok then
		return text :: string
	end

	return nil
end

-- The L2 tokenizer, compiled from its program file.
const tokenizerText = readFile "L2/programs/boot/lex.prog"
const tokenizer = L2.compile(tokenizerText, resolve, "boot/lex.prog")
-- The tag of each kind, in the order the L2 type Kind declares its constructors.
const KIND_TAG: { [string]: number } = {
	["("] = 0,
	[")"] = 1,
	["["] = 2,
	["]"] = 3,
	["{"] = 4,
	["}"] = 5,
	["."] = 6,
	["->"] = 7,
	["?"] = 8,
	[":"] = 14,
	[","] = 15,
	NL = 9,
	eof = 10,
	int = 11,
	str = 12,
	sym = 13,
}

-- A list of bytes, as a value: the bytes of a string, or the items of a list of numbers.
const function bytesValue(bytes: { number }): VM.Value
	local v: VM.Value = VM.NIL

	for i = #bytes, 1, -1 do
		v = { kind = "cell", head = bytes[i], tail = v } :: VM.Cell
	end

	return v
end

const function stringBytes(s: string): { number }
	local out: { number } = {}

	for i = 1, #s do
		table.insert(out, string.byte(s, i) :: number)
	end

	return out
end

-- A Luau token as the L2 value (kind . (line . (col . spaced))).
const function tokenValue(t: Lexer.Token): VM.Value
	local payload: VM.Value = VM.NIL

	if t.kind == "int" then
		const n = t.value :: number
		payload =
			if n == 0 then
				0
			else
				n
	elseif t.kind == "str" then
		payload = bytesValue(t.value :: { number })
	elseif t.kind == "sym" then
		payload = bytesValue(stringBytes(t.value :: string))
	end

	const kind: VM.Value = { kind = "con", tag = KIND_TAG[t.kind], payload = payload }
	const spaced: VM.Value =
		if t.spaced then
			1
		else
			0

	return {
		kind = "cell",
		head = kind,
		tail = { kind = "cell", head = t.line, tail = { kind = "cell", head = t.col, tail = spaced } },
	}
end

-- The Luau lexer's outcome as an L2 Result value: Ok of the tokens, or Err of the message.
const function expectedValue(src: string): string
	const ok, res = pcall(Lexer.tokenize, src)

	if not ok then
		return Data.write({ kind = "con", tag = 1, payload = bytesValue(stringBytes(tostring(res))) } :: VM.Value)
	end

	local list: VM.Value = VM.NIL

	for i = #(res :: { Lexer.Token }), 1, -1 do
		list = { kind = "cell", head = tokenValue((res :: { Lexer.Token })[i]), tail = list }
	end

	return Data.write({ kind = "con", tag = 0, payload = list } :: VM.Value)
end

-- The L2 tokenizer's outcome for src, as the same text.
const function l2Value(src: string): string
	const result = L2.run(tokenizer, bytesValue(stringBytes(src)), 1e8)

	if result.status == "value" then
		return Data.write(result.value)
	end

	return "the tokenizer " .. result.status .. (
		if result.status == "error" then
			": " .. result.message
		else
			""
	)
end

const function check(name: string, src: string)
	total += 1
	const want = expectedValue(src)
	const got = l2Value(src)

	if string.sub(want, 1, 6) == "con 0 " then
		tokenLists += 1
	else
		errors += 1
	end

	if want == got then
		return
	end

	failures += 1
	print(string.format("FAIL  %s\n      luau: %s\n      l2:   %s", name, want:sub(1, 300), got:sub(1, 300)))
end

-- Every program file in L1 and L2, whole.
local function listPrograms(folder: string, prefix: string, out: { { name: string, text: string } })
	for _, entry in fs.listdir(folder) do
		if entry.type == "dir" then
			listPrograms(`{folder}/{entry.name}`, `{prefix}{entry.name}/`, out)
		elseif entry.type == "file" and (string.sub(entry.name, -5) == ".prog" or string.sub(entry.name, -3) == ".l2") then
			table.insert(out, { name = `{prefix}{entry.name}`, text = readFile(`{folder}/{entry.name}`) })
		end
	end
end

local sources: { { name: string, text: string } } = {}
listPrograms("L1/programs", "L1/", sources)
listPrograms("L2/programs", "L2/", sources)

for _, s in sources do
	check(s.name, s.text)
end

-- Edge cases: numbers at the limits, malformed words, dots, strings and comments.
const EDGE = {
	"",
	"a",
	"(a)",
	"1-2",
	"- 5",
	"-5",
	"-",
	"->",
	"x->y",
	"a.b",
	"a . b",
	"a.",
	".",
	"(a.b)",
	'"ab"',
	'"a',
	'"a\nb"',
	'"\\q"',
	'"\\0\\t\\n\\\\\\""',
	"\\",
	'"\\',
	"99999999999999999999",
	"9007199254740991",
	"9007199254740990",
	"9007199254740992",
	"-9007199254740991",
	"-9007199254740992",
	"007",
	"-0",
	"12ab",
	"a;b\nc",
	";only comment",
	"\t \r\n",
	"x\n\n\ny",
	"?",
	"st: St",
	"a,b",
	"x: [Int], y",
	"a:b",
	": ,",
	"MS {\n\tfixed = 1,\n}",
	"[1 . 2]",
	"1.2",
	"a ->",
	"0x1",
	"-x",
	"--",
	"-->",
	"a-b",
	"a-",
	"9007199254740991.",
	"(\n)",
	"a\n  b",
	'""',
	'"x\\"y"',
	"a . ",
}

for i, src in EDGE do
	check(`edge case {i}`, src)
end

print(string.format("%d of %d inputs give the same tokens or error as the Luau lexer (%d token lists, %d errors)", total - failures, total, tokenLists, errors))

if failures > 0 then
	error(string.format("%d input(s) differ", failures))
end
