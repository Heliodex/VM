--!strict
-- CHECKS THE L2 LAYOUT LAYER, CONSTRUCT BY CONSTRUCT
--
-- Each case is an indented source (.l2) and the bracketed text (.prog) it should lay out to. The laid-out text must parse to the same tree as the bracketed text, with positions left out of the comparison.
--
--   lute run layout_cases_run.luau      (from Prototypes/5)

const L2 = require "./L2/l2"
const Layout = require "./L2/layout"
const Parser = require "./L2/parser"
const VM = require "./interpreter/vm"
const fs = require "@lute/fs"

const function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

-- The layer in L2, from boot/layout.l2, which is itself indented: the Luau layer lays it out when it is read.
const layerProgram = L2.compile(
	readFile "L2/programs/boot/layout.l2",
	function(_name: string): string?
		return nil
	end,
	"boot/layout.l2"
)

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

-- The L2 layer's outcome for a source: Ok of the text, or Err of the message, as the Luau layer raises it.
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

local ERRORS: { { name: string; l2: string } } = {
	{ name = "a sum with no constructors below"; l2 = "type T =\n\nfn x\n\tx" },
	{ name = "a sum constructor with no |"; l2 = "type T =\n\tA\n\tB\n\nfn x\n\tx" },
	{ name = "constructors below a type line with no ="; l2 = "type T = A\n\t| B\n\nfn x\n\tx" },
	{ name = "a field under a sum constructor with no colon"; l2 = "type Tr =\n\t| TNode\n\t\tvalue\n\nfn x\n\tx" },
	{ name = "an empty file"; l2 = "" },
	{ name = "a space at the start of a line"; l2 = " fn x" },
	{ name = "a let with no body"; l2 = "let a = 1" },
	{ name = "an arm with no ->"; l2 = "fn m\n\tmatch m\n\t\tOk v" },
}

-- Whether two trees are the same, ignoring the position of each node.
const function same(a: any, b: any, path: string): string?
	if type(a) ~= type(b) then
		return path .. ": " .. type(a) .. " against " .. type(b)
	end

	if type(a) ~= "table" then
		if a ~= b then
			return path .. ": " .. tostring(a) .. " against " .. tostring(b)
		end

		return nil
	end

	for k, v in a do
		if k ~= "at" and k ~= "line" and k ~= "col" then
			const diff = same(v, b[k], path .. "." .. tostring(k))

			if diff ~= nil then
				return diff
			end
		end
	end

	for k, _ in b do
		if k ~= "at" and k ~= "line" and k ~= "col" and a[k] == nil then
			return path .. "." .. tostring(k) .. ": missing on the left"
		end
	end

	return nil
end

local CASES: { { name: string; l2: string; prog: string } } = {
	{
		name = "let block",
		l2 = "let\n\ta = 1\n\tb = + a 2\n+ a b",
		prog = "let {\n\ta = 1\n\tb = (+ a 2)\n\t(+ a b)\n}",
	},
	{
		name = "letrec block with a mutual group",
		l2 = "letrec\n\tev = fn n\n\t\tif n\n\t\t\tod (- n 1)\n\t\telse\n\t\t\t1\n\tod = fn n\n\t\tif n\n\t\t\tev (- n 1)\n\t\telse\n\t\t\t0\nev 4",
		prog = "letrec {\n\tev = fn n\n\t(if n (od (- n 1)) 1)\n\tod = fn n\n\t(if n (ev (- n 1)) 0)\n\tev 4\n}",
	},
	{
		name = "let chain",
		l2 = "let a = 1\nlet b = 2\n(+ a b)",
		prog = "let a = 1\nlet b = 2\n(+ a b)",
	},
	{
		name = "application across lines",
		l2 = "let s = +\n\t1\n\t2\ns",
		prog = "let s = (+ 1 2)\ns",
	},
	{
		name = "fn with a body of lines",
		l2 = "fn x\n\tlet y = + x 1\n\ty",
		prog = "fn x\n\tlet y = (+ x 1)\n\ty",
	},
	{
		name = "fn as a let value",
		l2 = "let f = fn n\n\t+ n 1\nf 2",
		prog = "let f = (fn n\n\t(+ n 1))\nf 2",
	},
	{
		name = "if and else",
		l2 = "fn c\n\tif c\n\t\t1\n\telse\n\t\t2",
		prog = "fn c\n\t(if c\n\t(1)\n\t(2))",
	},
	{
		name = "match with arms",
		l2 = "fn m\n\tmatch m\n\t\tOk v -> v\n\t\tErr e -> 0",
		prog = "fn m\n\tmatch m {\n\t\tOk v -> v\n\t\tErr e -> 0\n\t}",
	},
	{
		name = "match arm with a body below it",
		l2 = "fn m\n\tmatch m\n\t\tOk v ->\n\t\t\tlet w = + v 1\n\t\t\tw\n\t\tErr e -> 0",
		prog = "fn m\n\tmatch m {\n\t\tOk v -> (let w = (+ v 1)\n\t\tw)\n\t\tErr e -> 0\n\t}",
	},
	{
		name = "match with a record pattern",
		l2 = "fn m\n\tmatch m\n\t\tMS\n\t\t\tfixed = f\n\t\t\tcatch = _\n\t\t-> f\n\t\t_ -> 0",
		prog = "fn m\n\tmatch m {\n\t\tMS {\n\t\t\tfixed = f\n\t\t\tcatch = _\n\t\t} -> f\n\t\t_ -> 0\n\t}",
	},
	{
		name = "if with elseif",
		l2 = "fn c\n\tif (< c 0)\n\t\t-1\n\telseif (= c 0)\n\t\t0\n\telse\n\t\t1",
		prog = "fn c\n\t(if (< c 0)\n\t(-1)\n\t(if (= c 0)\n\t(0)\n\t(1)))",
	},
	{
		name = "cond",
		l2 = "fn x\n\tcond\n\t\tx -> 1\n\t\t_ -> 2",
		prog = "fn x\n\tcond {\n\t\tx -> 1\n\t\t_ -> 2\n\t}",
	},
	{
		name = "with",
		l2 = "fn m\n\twith m\n\t\tfixed = 10",
		prog = "fn m\n\twith m {\n\t\tfixed = 10\n\t}",
	},
	{
		name = "with a field given by a block",
		l2 = "fn m\n\twith m\n\t\tfixed = +\n\t\t\t1\n\t\t\t2",
		prog = "fn m\n\twith m {\n\t\tfixed = (+ 1 2)\n\t}",
	},
	{
		name = "record literal",
		l2 = "fn x\n\tMS\n\t\tst = 1\n\t\tfixed = 2",
		prog = "fn x\n\tMS {\n\t\tst = 1\n\t\tfixed = 2\n\t}",
	},
	{
		name = "record declaration",
		l2 = "type MS = MS\n\tst: Int\n\tfixed: Int\n\nfn x\n\tfixed x",
		prog = "type MS = MS {\n\tst: Int\n\tfixed: Int\n}\n\nfn x\n\tfixed x",
	},
	{
		name = "record declaration in a sum",
		l2 = "type Tr = TEmpty | TNode\n\tvalue: Int\n\tleft: Int\n\nfn x\n\tx",
		prog = "type Tr = TEmpty | TNode {\n\tvalue: Int\n\tleft: Int\n}\n\nfn x\n\tx",
	},
	{
		name = "a sum with its constructors below",
		l2 = "type Opt =\n\t| None\n\t| Some Int\n\nfn x\n\tx",
		prog = "type Opt = None | Some Int\n\nfn x\n\tx",
	},
	{
		name = "a record constructor in a multiline sum",
		l2 = "type Tr =\n\t| TEmpty\n\t| TNode\n\t\tvalue: Int\n\t\tleft: Int\n\nfn x\n\tx",
		prog = "type Tr = TEmpty | TNode {\n\tvalue: Int\n\tleft: Int\n}\n\nfn x\n\tx",
	},
	{
		name = "a record constructor before another constructor",
		l2 = "type Tr =\n\t| TNode\n\t\tvalue: Int\n\t| TEmpty\n\nfn x\n\tx",
		prog = "type Tr = TNode {\n\tvalue: Int\n} | TEmpty\n\nfn x\n\tx",
	},
	{
		name = "a record literal in a let",
		l2 = "let s = MS\n\tfixed = 1\ns",
		prog = "let s = MS {\n\tfixed = 1\n}\ns",
	},
}
local failures = 0

for _, case in CASES do
	const okA, treeA = pcall(function()
		return Parser.parse(Layout.layout(case.l2))
	end)
	const okB, treeB = pcall(Parser.parse, case.prog)
	local result: string

	if not okA then
		result = `the layout failed: {tostring(treeA)}`
	elseif not okB then
		result = `the bracketed text does not parse: {tostring(treeB)}`
	else
		const diff = same(treeA, treeB, "program")
		result =
			if diff == nil then
				""
			else
				`the trees differ at {diff}`
	end

	if result == "" and okA then
		const text = Layout.layout(case.l2)
		const inL2 = layerInL2(case.l2)

		if inL2 ~= text then
			result = `the L2 layer gives a different text: {inL2} against {text}`
		end
	end

	if result == "" then
		print("PASS  " .. case.name)
	else
		failures += 1
		print("FAIL  " .. case.name .. ": " .. result)
	end
end

for _, case in ERRORS do
	const okA, msg = pcall(Layout.layout, case.l2)
	const want =
		if okA then
			"no error"
		else
			tostring(msg)
	const got = layerInL2(case.l2)
	local result: string

	if okA then
		result = "the Luau layer gave no error"
	elseif got ~= "error " .. want then
		result = "the L2 layer gives " .. got .. " against " .. want
	else
		result = ""
	end

	if result == "" then
		print("PASS  error: " .. case.name)
	else
		failures += 1
		print("FAIL  error: " .. case.name .. ": " .. result)
	end
end

print(string.format("%d of %d layout checks pass (the tree, the L2 text, and the errors)", #CASES + #ERRORS - failures, #CASES + #ERRORS))
