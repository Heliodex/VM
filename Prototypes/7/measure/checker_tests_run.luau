--!strict
-- CHECKS THE TESTS OF THE CHECKER, WRITTEN IN L2 (measure/boot/types.l2, request InferT), AGAINST THE LUAU CHECKER (Prototypes/6/L2/checker.luau)
--
-- The Luau checker gives each check node its expected type's text and its test, and the program's input its test and its text. The L2 checker gives the same, through request InferT, on the same programs: the program files of Prototypes/6/L2/programs (with their imports) and a set of programs with checks. Each program is parsed by the L2 tokenizer and parser, and by the Luau parser. The two must agree on the position, the text and the test of every check, and on the input. Type variables are renamed by where they first appear, and the keys of recursive tests by where they first appear, so the numbering of the two checkers does not matter.
--
--   lute run checker_tests_run.luau      (from Prototypes/7/measure)

const Checker = require "../../6/L2/checker"
const L2 = require "../../6/L2/l2"
const Layout = require "../../6/L2/layout"
const Parser = require "../../6/L2/parser"
const ProgramFile = require "../../6/L2/programfile"
const VM = require "../../6/interpreter/vm"
const fs = require "@lute/fs"

local failures = 0
local total = 0
local skipped = 0

local function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

local function resolve(name: string): string?
	const ok, text = pcall(readFile, `../../6/L2/programs/{name}`)

	if ok then
		return text :: string
	end

	return nil
end

const tokenizer = L2.compile(readFile "../../6/L2/programs/boot/lex.l2", resolve, "boot/lex.l2")
const parser = L2.compile(readFile "../../6/L2/programs/boot/parse.l2", resolve, "boot/parse.l2")
const checker = L2.compile(readFile "boot/types.l2", resolve, "boot/types.l2")

local function bytesValue(s: string): VM.Value
	local v: VM.Value = VM.NIL

	for i = #s, 1, -1 do
		v = { kind = "cell"; head = string.byte(s, i) :: number; tail = v } :: VM.Cell
	end

	return v
end

local function listValue(items: { VM.Value }): VM.Value
	local v: VM.Value = VM.NIL

	for i = #items, 1, -1 do
		v = { kind = "cell"; head = items[i]; tail = v } :: VM.Cell
	end

	return v
end

local function cellValue(a: VM.Value, b: VM.Value): VM.Value
	return { kind = "cell"; head = a; tail = b } :: VM.Cell
end

local function conValue(tag: number, payload: VM.Value): VM.Value
	return { kind = "con"; tag = tag; payload = payload } :: VM.Con
end

local function textOf(v: VM.Value): string
	local out: { string } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, string.char((cur :: VM.Cell).head :: number))
		cur = (cur :: VM.Cell).tail
	end

	return table.concat(out)
end

local function itemsOf(v: VM.Value): { VM.Value }
	local out: { VM.Value } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, (cur :: VM.Cell).head)
		cur = (cur :: VM.Cell).tail
	end

	return out
end

-- The keys of recursive tests, renamed by where they first appear.
local function keyName(keys: { [string]: string }, key: string): string
	if keys[key] == nil then
		keys[key] = `K{tostring(#keys + 1)}`
	end

	return keys[key]
end

-- A test of the Luau checker, in one notation.
local function showLuauTest(t: any, keys: { [string]: string }): string
	const kind = t.kind

	if kind == "any" then
		return "A"
	elseif kind == "nil" then
		return "N"
	elseif kind == "int" then
		return "I"
	elseif kind == "fn" then
		return "F"
	elseif kind == "pin" then
		return "P"
	elseif kind == "pair" then
		return `(p {showLuauTest(t.a, keys)} {showLuauTest(t.b, keys)})`
	elseif kind == "list" then
		return `(l {showLuauTest(t.item, keys)} {showLuauTest(t.tail, keys)})`
	elseif kind == "sum" then
		local items: { string } = {}

		for _, c in t.ctors do
			table.insert(items, `{c.tag}:{showLuauTest(c.payload, keys)}`)
		end

		return `(s {table.concat(items, " ")})`
	elseif kind == "rec" then
		return `(r {keyName(keys, t.key)})`
	elseif kind == "fixdef" then
		return `(x {keyName(keys, t.key)} {showLuauTest(t.body, keys)})`
	end

	error(`unknown test {tostring(kind)}`, 0)
end

-- A test of the L2 checker, as the value gives it: the tags of Test, KAny 0 to KFixdef 9.
local function showVmTest(v: VM.Value, keys: { [string]: string }): string
	const con = v :: VM.Con
	const p = con.payload

	if con.tag == 0 then
		return "A"
	elseif con.tag == 1 then
		return "N"
	elseif con.tag == 2 then
		return "I"
	elseif con.tag == 3 then
		return "F"
	elseif con.tag == 4 then
		return "P"
	elseif con.tag == 5 then
		const pr = p :: VM.Cell

		return `(p {showVmTest(pr.head, keys)} {showVmTest(pr.tail, keys)})`
	elseif con.tag == 6 then
		const pr = p :: VM.Cell

		return `(l {showVmTest(pr.head, keys)} {showVmTest(pr.tail, keys)})`
	elseif con.tag == 7 then
		local items: { string } = {}

		for _, c in itemsOf(p) do
			const pr = c :: VM.Cell
			table.insert(items, `{tostring(pr.head)}:{showVmTest(pr.tail, keys)}`)
		end

		return `(s {table.concat(items, " ")})`
	elseif con.tag == 8 then
		return `(r {keyName(keys, textOf(p))})`
	elseif con.tag == 9 then
		const pr = p :: VM.Cell

		return `(x {keyName(keys, textOf(pr.head))} {showVmTest(pr.tail, keys)})`
	end

	error(`unknown L2 test {tostring(con.tag)}`, 0)
end

-- The laid-out program section, parsed by the L2 tokenizer and parser: the payload (declarations . expression), or nil.
local function bootParse(laid: string): VM.Cell?
	const tokenized = L2.run(tokenizer, bytesValue(laid), 1e10)

	if tokenized.status ~= "value" then
		return nil
	end

	const parsed = L2.run(parser, (tokenized.value :: VM.Con).payload, 5e10)

	if parsed.status ~= "value" or (parsed.value :: VM.Con).tag ~= 0 then
		return nil
	end

	return (parsed.value :: VM.Con).payload :: VM.Cell
end

-- The request InferT with the imports (name . program) and the program.
local function bootCheck(imports: { VM.Value }, program: VM.Cell): VM.Cell?
	const request = conValue(5, cellValue(listValue(imports), program))
	const result = L2.run(checker, request, 1e11)

	if result.status ~= "value" then
		return nil
	end

	return result.value :: VM.Cell
end

-- Compares one program: the Luau checker's checks and input with the L2 checker's.
local function check(name: string, laid: string, imports: { { name: string; file: string } })
	-- The imports, as the Luau checker and the L2 checker have them: each a checked library.
	local schemes: { { name: string; scheme: any } } = {}
	local bootImports: { VM.Value } = {}

	for _, imp in imports do
		const libLaid = Layout.layout(ProgramFile.parse(readFile(`../../6/L2/programs/{imp.file}`), nil).program :: string)
		const libHost = Parser.parse(libLaid)
		const libChecked = Checker.check(libHost, {}, imp.file)
		table.insert(schemes, { name = imp.name; scheme = libChecked.scheme })
		const libBoot = bootParse(libLaid)

		if libBoot == nil then
			skipped += 1
			print(`SKIP  {name}: the L2 parser refuses the import {imp.file}`)

			return
		end

		table.insert(bootImports, cellValue(bytesValue(imp.name), libBoot))
	end

	const hostOk, host = pcall(function()
		return Checker.check(Parser.parse(laid), schemes, "t.prog")
	end)

	if not hostOk then
		skipped += 1
		print(`SKIP  {name}: the Luau checker refuses it`)

		return
	end

	const bootProgram = bootParse(laid)

	if bootProgram == nil then
		skipped += 1
		print(`SKIP  {name}: the L2 parser refuses it`)

		return
	end

	const out = bootCheck(bootImports, bootProgram)

	if out == nil then
		skipped += 1
		print(`SKIP  {name}: the L2 checker does not finish`)

		return
	end

	total += 1
	local problems: { string } = {}
	const result = host :: any
	local outErrs = textOf((out :: VM.Cell).head)
	const restPair = (out :: VM.Cell).tail :: VM.Cell
	const errs = itemsOf(restPair.head)

	if #errs > 0 then
		table.insert(
			problems,
			`the L2 checker reports errors: {
				table.concat(
					(function(): { string }
						local t: { string } = {}

						for _, e in errs do
							table.insert(t, textOf(e))
						end

						return t
					end)(),
					"; "
				)
			}`
		)
	end

	-- The checks: each check node of the Luau checker, found by its position in the L2 checker's list.
	const keysL: { [string]: string } = {}
	const keysV: { [string]: string } = {}
	const checksV = itemsOf((restPair.tail :: VM.Cell).head)
	local checksByAt: { [string]: VM.Cell } = {}

	for _, c in checksV do
		const pr = c :: VM.Cell
		const at = pr.head :: VM.Cell
		checksByAt[`{tostring(at.head)}:{tostring(at.tail)}`] = pr.tail :: VM.Cell
	end

	local seen = 0

	const function walk(node: any)
		if type(node) ~= "table" then
			return
		end

		if node.k == "check" and node.test ~= nil then
			seen += 1
			const found = checksByAt[`{node.at.line}:{node.at.col}`]

			if found == nil then
				table.insert(problems, `no L2 check at {node.at.line}:{node.at.col}`)
			else
				const expectV = textOf(found.head)
				const expectL = node.expect

				if expectV ~= expectL then
					table.insert(problems, `check at {node.at.line}:{node.at.col}: expects "{expectV}", the Luau checker "{expectL}"`)
				end

				const testV = showVmTest(found.tail, keysV)
				const testL = showLuauTest(node.test, keysL)

				if testV ~= testL then
					table.insert(problems, `check at {node.at.line}:{node.at.col}: test {testV}, the Luau checker {testL}`)
				end
			end
		end

		for key, value in node do
			if key ~= "test" and type(value) == "table" then
				walk(value)
			end
		end
	end

	walk(result.expr)

	if #checksV ~= seen then
		table.insert(problems, `the L2 checker gives {#checksV} checks, the Luau checker {seen}`)
	end

	-- The input: its test and its text.
	const input = restPair.tail :: VM.Cell
	const inputCon = input.tail :: VM.Con

	if inputCon.tag == 1 then
		const pr = inputCon.payload :: VM.Cell
		const testV = showVmTest(pr.head, keysV)
		const testL = showLuauTest(result.input, keysL)

		if testV ~= testL then
			table.insert(problems, `input test {testV}, the Luau checker {testL}`)
		end

		const expectV = textOf(pr.tail)
		const expectL = result.inputExpect

		if expectV ~= expectL then
			table.insert(problems, `input text "{expectV}", the Luau checker "{expectL}"`)
		end
	else
		table.insert(problems, "the L2 checker gives no input check")
	end

	if #problems == 0 then
		print(`PASS  {name}: {seen} checks`)
	else
		failures += 1
		print(`FAIL  {name}`)

		for _, p in problems do
			print(`      {p}`)
		end
	end
end

-- The program files of the L2 programs folder, with their imports.
local CORPUS = { "add_one", "block_let", "boot/layout", "boot/lex", "boot/parse", "boot/types", "cons", "division", "double", "fact", "forms", "head", "imports", "let_block", "letrec_block", "lib/abs", "lib/append", "lib/contains", "lib/filter", "lib/fold", "lib/gcd", "lib/insert", "lib/length", "lib/map", "lib/max", "lib/min", "lib/ninefold", "lib/nth", "lib/range", "lib/reverse", "lib/sort", "lib/sum", "lib/take", "lib/triple", "lib/unwrap_or", "mutual", "option", "pairs", "record_middle", "records", "remainder", "result", "sum_list", "tree" }
-- Programs with checks, as the Luau checker needs them: a function of its input.
local CHECKS: { { name: string; src: string } } = {
	{ name = "a check of an integer"; src = "fn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (+ v 1)\n\t\tErr e -> 0\n}" },
	{ name = "a check of a pair"; src = "fn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (fst v)\n\t\tErr e -> 0\n}" },
	{ name = "a check of a list"; src = "fn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (@ v)\n\t\tErr e -> 0\n}" },
	{ name = "a check of a user sum"; src = "type Shape = Circle Int | Dot\nlet area = fn s\n\tmatch s {\n\t\tCircle r -> r\n\t\tDot -> 0\n}\nfn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (area v)\n\t\tErr e -> 0\n}" },
	{ name = "a check of a recursive list of integers"; src = "type L = Nil2 | Cons2 (Int . L)\nletrec len = fn t\n\tmatch t {\n\t\tNil2 -> 0\n\t\tCons2 p -> (+ 1 (len (snd p)))\n\t}\nfn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (len v)\n\t\tErr e -> 0\n}" },
	{ name = "a check of a recursive sum with a pair"; src = "type T = Leaf | Node (T . Int)\nletrec depth = fn t\n\tmatch t {\n\t\tLeaf -> 0\n\t\tNode p -> (+ 1 (depth (fst p)))\n\t}\nfn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (depth v)\n\t\tErr e -> 0\n}" },
	{ name = "a check of a list of user sums"; src = "type C = Red | Blue Int\nfn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (cons v ~)\n\t\tErr e -> ~\n}" },
	{ name = "a check in a let"; src = "fn x\n\tlet r = (check (untyped x))\n\tmatch r {\n\t\tOk v -> (+ v 1)\n\t\tErr e -> 0\n}" },
	{ name = "a check of a record"; src = "type P = P {\n\tx: Int\n\ty: Int\n}\nfn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (match v {\n\t\t\tP {\n\t\t\t\tx = a\n\t\t\t\ty = b\n\t\t\t} -> (+ a b)\n\t\t})\n\t\tErr e -> 0\n}" },
	{ name = "the input of a program"; src = "fn x\n\t(+ x 1)" },
	{ name = "the input of a program that is a pair"; src = "fn p\n\t(fst p)" },
	{ name = "a program that returns a constructor"; src = "fn x\n\tOk x" },
	{ name = "a check of a polymorphic pair"; src = "fn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (fst v)\n\t\tErr e -> 0\n}" },
	{ name = "the input of a polymorphic pair"; src = "fn p\n\t(fst p)" },
	{ name = "a check of a list"; src = "fn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (cons v ~)\n\t\tErr e -> ~\n}" },
}
print "checker_tests_run: the L2 checker's tests against the Luau checker's"

for _, c in CHECKS do
	check(c.name, c.src, {})
end

for _, path in CORPUS do
	const file = ProgramFile.parse(readFile(`../../6/L2/programs/{path}.l2`), path)
	local imports: { { name: string; file: string } } = {}

	for _, imp in file.imports do
		table.insert(imports, { name = imp.name; file = imp.file })
	end

	check(path, Layout.layout(file.program), imports)
end

print(`{total - failures} of {total} compared pass, {skipped} skipped, {failures} differ`)

if failures > 0 then
	error(`{failures} differ`, 0)
end
