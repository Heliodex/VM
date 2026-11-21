--!strict
-- CHECKS THE L2 PARSER, WRITTEN IN L2, AGAINST THE LUAU PARSER
--
-- L2/programs/boot/parse.prog is the parser in L2, and it reads the token list that L2/programs/boot/lex.prog gives. For every program here, both parsers run on the same text, and the results must agree: the same tree, with the same positions, or the same error message. The tree is written as values in the layout given at the top of parse.prog, so both results can be compared as data.
--
-- The inputs are the program sections of every L2 program file, and a set of cases that reach each error the parser gives. An input the tokenizer refuses is skipped here, since lex_run.luau checks the tokenizer.
--
--   lute run parse_run.luau      (from Prototypes/5)

const L2 = require "./L2/l2"
const ProgramFile = require "./L2/programfile"
const Parser = require "./L2/parser"
const Lexer = require "./L2/lexer"
const VM = require "./interpreter/vm"
const Data = require "./interpreter/data"
const fs = require "@lute/fs"

local failures = 0
local total = 0
local trees = 0
local errors = 0
local skipped = 0

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

const tokenizer = L2.compile(readFile("L2/programs/boot/lex.prog"), resolve, "boot/lex.prog")
const parser = L2.compile(readFile("L2/programs/boot/parse.prog"), resolve, "boot/parse.prog")

-- VALUES

const function bytesOf(s: string): VM.Value
	local v: VM.Value = VM.NIL

	for i = #s, 1, -1 do
		v = { kind = "cell", head = string.byte(s, i) :: number, tail = v } :: VM.Cell
	end

	return v
end

-- A list of values, in order.
const function listOf(items: { VM.Value }): VM.Value
	local v: VM.Value = VM.NIL

	for i = #items, 1, -1 do
		v = { kind = "cell", head = items[i], tail = v } :: VM.Cell
	end

	return v
end

const function cellOf(h: VM.Value, t: VM.Value): VM.Value
	return { kind = "cell", head = h, tail = t } :: VM.Cell
end

const function conOf(tag: number, payload: VM.Value): VM.Value
	return { kind = "con", tag = tag, payload = payload } :: VM.Con
end

const function posOf(at: { line: number, col: number }): VM.Value
	return cellOf(at.line, at.col)
end

const function intOf(n: number): VM.Value
	return if n == 0 then 0 else n
end

-- THE LUAU TREE, AS VALUES

local convertExpr: (Parser.Expr) -> VM.Value

local function convertPattern(p: Parser.Pattern): VM.Value
	if p.k == "con" then
		const bind: VM.Value = if p.bind ~= nil then bytesOf(p.bind :: string) else VM.NIL
		return conOf(0, cellOf(bytesOf(p.name), cellOf(bind, posOf(p.at))))
	elseif p.k == "bind" then
		return conOf(1, cellOf(bytesOf(p.name), posOf(p.at)))
	end

	return conOf(2, posOf(p.at))
end

local function convertType(t: Parser.Type): VM.Value
	if t.k == "tname" then
		return conOf(0, cellOf(bytesOf(t.name), posOf(t.at)))
	elseif t.k == "tapp" then
		local args: { VM.Value } = {}

		for _, a in t.args do
			table.insert(args, convertType(a))
		end

		return conOf(1, cellOf(bytesOf(t.name), cellOf(listOf(args), posOf(t.at))))
	elseif t.k == "tpair" then
		return conOf(2, cellOf(convertType(t.a), cellOf(convertType(t.b), posOf(t.at))))
	elseif t.k == "tlist" then
		return conOf(3, cellOf(convertType(t.item), posOf(t.at)))
	end

	const f = t :: { k: string, a: Parser.Type, b: Parser.Type, at: { line: number, col: number } }
	return conOf(4, cellOf(convertType(f.a), cellOf(convertType(f.b), posOf(f.at))))
end

const function convertExprs(items: { Parser.Expr }): VM.Value
	local out: { VM.Value } = {}

	for _, e in items do
		table.insert(out, convertExpr(e))
	end

	return listOf(out)
end

convertExpr = function(e: Parser.Expr): VM.Value
	if e.k == "int" then
		return conOf(0, cellOf(intOf(e.n), posOf(e.at)))
	elseif e.k == "str" then
		return conOf(1, cellOf(listOf(table.clone(e.bytes) :: any), posOf(e.at)))
	elseif e.k == "nil" then
		return conOf(2, posOf(e.at))
	elseif e.k == "name" then
		return conOf(3, cellOf(bytesOf(e.name), posOf(e.at)))
	elseif e.k == "list" then
		return conOf(4, cellOf(convertExprs(e.items), posOf(e.at)))
	elseif e.k == "pair" then
		return conOf(5, cellOf(convertExpr(e.a), cellOf(convertExpr(e.b), posOf(e.at))))
	elseif e.k == "app" then
		return conOf(6, cellOf(convertExpr(e.f), cellOf(convertExprs(e.args), posOf(e.at))))
	elseif e.k == "fn" then
		local names: { VM.Value } = {}

		for _, n in e.names do
			table.insert(names, bytesOf(n))
		end

		return conOf(7, cellOf(listOf(names), cellOf(convertExpr(e.body), posOf(e.at))))
	elseif e.k == "let" then
		const rec = if e.rec then 1 else 0
		return conOf(8, cellOf(bytesOf(e.name), cellOf(convertExpr(e.value), cellOf(convertExpr(e.body), cellOf(rec, posOf(e.at))))))
	elseif e.k == "mutual" then
		local bindings: { VM.Value } = {}

		for _, b in e.bindings do
			table.insert(bindings, cellOf(bytesOf(b.name), cellOf(convertExpr(b.value), posOf(b.at))))
		end

		return conOf(9, cellOf(listOf(bindings), cellOf(convertExpr(e.body), posOf(e.at))))
	elseif e.k == "if" then
		return conOf(10, cellOf(convertExpr(e.c), cellOf(convertExpr(e.t), cellOf(convertExpr(e.e), posOf(e.at)))))
	elseif e.k == "match" then
		local arms: { VM.Value } = {}

		for _, a in e.arms do
			table.insert(arms, cellOf(convertPattern(a.pat), cellOf(convertExpr(a.body), posOf(a.at))))
		end

		return conOf(11, cellOf(convertExpr(e.scrut), cellOf(listOf(arms), posOf(e.at))))
	elseif e.k == "try" then
		return conOf(12, cellOf(convertExpr(e.e), posOf(e.at)))
	elseif e.k == "check" then
		return conOf(13, cellOf(convertExpr(e.e), posOf(e.at)))
	end

	const u = e :: { k: string, e: Parser.Expr, at: { line: number, col: number } }
	return conOf(14, cellOf(convertExpr(u.e), posOf(u.at)))
end

-- The whole program: (decls . expr), where a declaration is (name . (params . (cons . at))).
const function convertProgram(p: Parser.Program): VM.Value
	local decls: { VM.Value } = {}

	for _, d in p.decls do
		local params: { VM.Value } = {}

		for _, n in d.params do
			table.insert(params, bytesOf(n))
		end

		local cons: { VM.Value } = {}

		for _, c in d.cons do
			const payload: VM.Value = if c.payload ~= nil then convertType(c.payload :: Parser.Type) else conOf(5, VM.NIL)
			table.insert(cons, cellOf(bytesOf(c.name), cellOf(payload, posOf(c.at))))
		end

		table.insert(decls, cellOf(bytesOf(d.name), cellOf(listOf(params), cellOf(listOf(cons), posOf(d.at)))))
	end

	return cellOf(listOf(decls), convertExpr(p.expr))
end

-- THE TWO PARSERS

-- The Luau parser's outcome as an L2 Result value: Ok of the program, or Err of the message.
const function expectedValue(src: string): string
	const ok, res = pcall(Parser.parse, src)

	if not ok then
		return Data.write(conOf(1, bytesOf(tostring(res))))
	end

	return Data.write(conOf(0, convertProgram(res :: Parser.Program)))
end

-- The L2 tokenizer, then the L2 parser on its tokens. nil when the tokenizer refuses the text.
const function l2Value(src: string): string?
	const tokenized = L2.run(tokenizer, bytesOf(src), 100000000)

	if tokenized.status ~= "value" then
		return nil
	end

	const result = L2.run(parser, (tokenized.value :: VM.Con).payload, 500000000)

	if result.status == "value" then
		return Data.write(result.value)
	end

	return "the parser " .. result.status .. (if result.status == "error" then ": " .. result.message else "")
end

const function check(
	name: string,
	src: string
)
	const got = l2Value(src)

	if got == nil then
		skipped += 1
		return
	end

	total += 1
	const want = expectedValue(src)

	if string.sub(want, 1, 6) == "con 0 " then
		trees += 1
	else
		errors += 1
	end

	if want == got then
		return
	end

	failures += 1
	print(string.format("FAIL  %s\n      luau: %s\n      l2:   %s", name, want:sub(1, 300), got:sub(1, 300)))
end

-- The program section of each L2 program file.
local function listPrograms(folder: string, prefix: string, out: { { name: string, text: string } })
	for _, entry in fs.listdir(folder) do
		if entry.type == "dir" then
			listPrograms(`{folder}/{entry.name}`, `{prefix}{entry.name}/`, out)
		elseif entry.type == "file" and string.sub(entry.name, -5) == ".prog" then
			table.insert(out, { name = `{prefix}{entry.name}`, text = readFile(`{folder}/{entry.name}`) })
		end
	end
end

local files: { { name: string, text: string } } = {}
listPrograms("L2/programs", "L2/", files)

for _, f in files do
	check(f.name, ProgramFile.parse(f.text).program)
end

-- Cases that reach each error the parser gives, and the shapes it accepts.
const CASES = {
	"1",
	"~",
	"_",
	"fn",
	"if",
	"match",
	"1 2 3",
	"-5",
	"x->y",
	"(1 . 2)",
	"(1 . 2 . 3)",
	"(1 2",
	"[1 2",
	"[1 2 3)",
	"1)",
	"[1 (2 . 3)]",
	"[1 . 2]",
	"f x?",
	"(f x)?",
	"f (x)?",
	"a\nb",
	"f\n\tx",
	"fn x\n\tx",
	"fn x x",
	"fn ()\n1",
	"fn (x y)\n\tx",
	"fn (x (y))\n1",
	"fn x\n1",
	"(fn x\n\tx)",
	"let = 1\n2",
	"let fn = 1\n2",
	"let X = 1\n2",
	"let x 1\n2",
	"let x = 1 2\n3",
	"let x = 1\n2",
	"let x = 1\n\n\n2",
	"(let x = 1\n2)",
	"letrec f = fn x\n\tf x\nf 1",
	"match x 1",
	"match x {}",
	"match x {\n}",
	"match x {\n\t_ -> 1\n}",
	"match x {\n\tOk v -> 1 2\n}",
	"match x {\n\tok -> 1\n}",
	"match x {\n\tOk _ -> 1\n\tErr e -> 2\n}",
	"match x {\n\t1 -> 1\n}",
	"match x {\n\tNone -> 1\n\tSome v -> 2\n}\n",
	"match x {Ok v -> 1}",
	"match x {\n\tOk v -> let y = 1\n\ty\n}",
	"match x {\n\tOk v -> (let y = 1\n\ty)\n}",
	"if 1 2 3",
	"if 1 2",
	"mutual (a (fn x a)) a",
	"mutual ((a (fn x a))) a",
	"mutual ((a (fn x (b x))) (b (fn x (a x)))) a",
	"mutual ((a (fn x a)) (b (fn x b)))\n1",
	"check x",
	"untyped x",
	"check (x) 1",
	"(check x)?",
	"type T = A\nA",
	"type T = A | B\nA",
	"type T a b = P a | Q b\nP 1",
	"type a = X",
	"type T = x",
	"type T = A (Int . Int)\nA",
	"type T = A [Int]\nA",
	"type T = A Int -> Int\nA",
	"type T = A | B Int\nB 1",
	"type T a\nA",
	"type T = A | \nA",
	"type T = A B C\nA",
	"type T = A\ntype U = B\nB",
	"type T = A 1\nA",
	"type T = A\n\nA",
	"type T = A (Int . Int) [Int] -> Int\nA",
	"type T = A\n  B",
	"type T =\nA",
	"type T = A ; comment\nA",
	"(fn x (x))",
	"f (fn x\n\tx) 1",
	"[(fn x\n\tx) 1]",
	"f ~ _",
	"f \"ab\" 1",
	"f ;comment\n1",
	"(a . b) . c",
	"-\n5",
	"fn\nx",
	"cond {\n\t(< x 0) -> 1\n\t_ -> 2\n}",
	"cond {\n\t_ -> 1\n}",
	"cond {}",
	"cond {\n\t(= 1 1) -> 2\n}",
	"cond {\n\t_ -> 2\n\t(= 1 1) -> 3\n}",
	"cond {\n\t(= 1 1) 2\n\t_ -> 1\n}",
	"cond {\n\t(= 1 1) -> 2 3\n\t_ -> 1\n}",
	"cond (= 1 1) -> 2",
	"cond {_ -> 1}",
	"let {\n\tx = 1\n\ty = (+ x 1)\n\t(+ x y)\n}",
	"let {\n\tx = 1\n}",
	"let {\n\tx\n\ty = 1\n}",
	"let {x = 1\nx}",
	"let {\n\tfn = 1\n\tfn\n}",
	"let {\n\tX = 1\n\tX\n}",
	"let {\n\tx = 1 2\n\tx\n}",
	"letrec {\n\tf = (fn x\n\t\t(f x))\n\tf\n}",
	"letrec {\n\tx = 1\n\tx\n}",
	"letrec {\n\tf = (fn x\n\t\tx)\n\tg = (fn y\n\t\t(f y))\n\t(g 1)\n}",
	"let { ; a comment\n\tx = 1\n\tx\n}",
	"let {\n}",
}

for i, src in CASES do
	check(`case {i}`, src)
end

print(string.format(
	"%d of %d programs give the same tree or error as the Luau parser (%d trees, %d errors, %d skipped: the tokenizer refuses them)",
	total - failures,
	total,
	trees,
	errors,
	skipped
))

if failures > 0 then
	error(string.format("%d program(s) differ", failures))
end
