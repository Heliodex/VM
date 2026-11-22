--!strict
-- CHECKS THE PURE CHECKER, WRITTEN IN L2, AGAINST THE LUAU CHECKER
--
-- L2/programs/boot/types.l2 infers the type of a program from its syntax tree. Each input here is run through the L2 tokenizer and parser, then through the L2 checker, and through the Luau checker. The two must agree on the type of the program, or on its errors. Type variables are numbered by where they first appear, so the numbering of the two checkers does not matter.
--
-- An input that the parser refuses is skipped, since parse_run.luau checks the parser. So is an input that has a form the pure checker does not handle yet.
--
--   lute run infer_run.luau      (from Prototypes/5)

const Checker = require "./L2/checker"
const L2 = require "./L2/l2"
const Parser = require "./L2/parser"
const ProgramFile = require "./L2/programfile"
const VM = require "./interpreter/vm"
const fs = require "@lute/fs"

local failures = 0
local total = 0
local types = 0
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

const tokenizer = L2.compile(readFile "L2/programs/boot/lex.prog", resolve, "boot/lex.prog")
const parser = L2.compile(readFile "L2/programs/boot/parse.prog", resolve, "boot/parse.prog")
const checkerProgram = L2.compile(readFile "L2/programs/boot/types.l2", resolve, "boot/types.l2")

-- The bytes of a string, and a string of the bytes of a list of values.
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

-- A list of values, in order, as Lua values.
const function itemsOf(v: VM.Value): { VM.Value }
	local out: { VM.Value } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, (cur :: VM.Cell).head)
		cur = (cur :: VM.Cell).tail
	end

	return out
end

-- Renames the type variables of a message by where they first appear: ?12 and ?7 become ?a and ?b, so two checkers that number them differently agree.
const function canon(s: string): string
	local names: { [string]: string } = {}
	local count = 0

	return (
		string.gsub(
			s,
			"%?(%d+)",
			function(id: string): string
				if names[id] == nil then
					count += 1
					names[id] = `?v{count}`
				end

				return names[id]
			end
		)
	)
end

-- The outcome of the Luau checker: its type, or its errors.
const function luauOutcome(src: string): string?
	const parsedOk, parsed = pcall(Parser.parse, src)

	if not parsedOk then
		return nil
	end

	const ok, res = pcall(Checker.check, parsed, {}, "t.prog")

	if ok then
		return "type " .. canon(Checker.showScheme((res :: Checker.Result).scheme))
	end

	const message =
		if type(res) == "table" then
			(res :: { typeError: string }).typeError
		else
			tostring(res)

	return "error " .. canon(message)
end

-- The outcome of the L2 checker, run on the expression of an L2 parse.
local function l2Outcome(src: string): string?
	const tokenized = L2.run(tokenizer, bytesValue(src), 1e8)

	if tokenized.status ~= "value" then
		return nil
	end

	const parsed = L2.run(parser, (tokenized.value :: VM.Con).payload, 5e8)

	if parsed.status ~= "value" or (parsed.value :: VM.Con).tag ~= 0 then
		return nil
	end

	const program = (parsed.value :: VM.Con).payload :: VM.Cell
	-- The request Infer (tag 3 of Req) with the program: its declarations, then its body.
	const request: VM.Value = { kind = "con"; tag = 3; payload = program }
	-- The checker's own source takes more than 1e9 steps (about 11 minutes for this suite), so the limit is 1e10.
	const result = L2.run(checkerProgram, request, 1e10)

	if result.status ~= "value" then
		return "the checker " .. result.status
	end

	const out = result.value :: VM.Cell
	const text = textOf(out.head)
	const errs: { string } = {}

	for _, e in itemsOf(out.tail) do
		table.insert(errs, textOf(e))
	end

	if string.find(text, "this form is not checked yet", 1, true) ~= nil then
		return nil
	end

	for _, e in errs do
		if string.find(e, "this form is not checked yet", 1, true) ~= nil then
			return nil
		end
	end

	if #errs == 0 then
		return "type " .. canon(text)
	end

	return "error " .. canon(table.concat(errs, "\n"))
end

local function check(name: string, src: string)
	const want = luauOutcome(src)
	const got = l2Outcome(src)

	if want == nil or got == nil then
		skipped += 1

		return
	end

	total += 1

	if string.sub(want, 1, 5) == "type " then
		types += 1
	else
		errors += 1
	end

	if want == got then
		return
	end

	failures += 1
	print(string.format("FAIL  %s\n      luau: %s\n      l2:   %s", name, want:sub(1, 1200), got:sub(1, 1200)))
end

-- The program section of each L2 program file.
local function listPrograms(folder: string, prefix: string, out: { { name: string; text: string } })
	for _, entry in fs.listdir(folder) do
		if entry.type == "dir" then
			listPrograms(`{folder}/{entry.name}`, `{prefix}{entry.name}/`, out)
		elseif entry.type == "file" and (string.sub(entry.name, -5) == ".prog" or string.sub(entry.name, -3) == ".l2") then
			table.insert(out, { name = `{prefix}{entry.name}`; text = readFile(`{folder}/{entry.name}`) })
		end
	end
end

local files: { { name: string; text: string } } = {}
listPrograms("L2/programs", "L2/", files)

for _, f in files do
	check(f.name, ProgramFile.parse(f.text, f.name).program)
end

-- Cases for each form the checker handles, and for each error it reports.
const CASES = {
	"fn x\n\t(+ x 1)",
	"fn x\n\tx",
	"fn (x y)\n\t(+ x y)",
	"fn x\n\t(cons x ~)",
	"fn x\n\t[x 1]",
	"fn x\n\t(x 1)",
	"(fn x\n\t(+ x 1)) 2",
	"fn x\n\t(+ x [1])",
	"fn x\n\t(if x 1 2)",
	"fn x\n\t(if 1 x [2])",
	"fn x\n\t(if x 1 [2])",
	"fn x\n\t(+ (head x) 1)",
	"fn x\n\t(fst x)",
	"fn x\n\t(snd (x . 1))",
	"let f = (fn x\n\tx)\nf 1",
	"let f = (fn x\n\tx)\n(f 1) . (f [1])",
	"letrec f = (fn n\n\t(if (= n 0) 1 (* n (f (- n 1)))))\nf",
	"letrec f = (fn n\n\t(f n))\nf",
	"let f = (fn x\n\t(+ x 1))\nf [1]",
	"unbound 1",
	"fn x\n\tunbound",
	"5",
	"~",
	'"ab"',
	"[1 2 3]",
	"(1 . [2])",
	"[(1 . 2) (3 . 4)]",
	"[1 ~]",
	"fn x\n\t(@ x)",
	"fn x\n\t(pin x)",
	"fn x\n\t(force x)",
	"fn f\n\t(fix f)",
	"fn x\n\t(/ x 2)",
	"fn x\n\t(% 7 x)",
	"fn x\n\t(tail x)",
	"fn x\n\t(cons 1 x)",
	"fn x\n\tif (< x 0) (- 0 x) x",
	"fn x\n\t(let y = x\n(+ y 1))",
	"fn (x y)\n\tif x y [y]",
	"fn x\n\tletrec go = (fn (l n)\n\t\t(if (= (@ l) 1) n (go (tail l) (+ n 1))))\n\tgo x 0",
	"fn f\n\tlet g = (fn x\n\t\t(f x))\n\tg 1",
	"fn x\n\t(x x)",
	"fn x\n\t(x x x)",
	"fn x\n\t[x x]",
	"1 2",
	"fn x\n\tfn y\n\t\t(+ x y)",
	"fn r\n\tmatch r {\n\t\tOk v -> v\n\t\tErr e -> 0\n\t}",
	"fn r\n\tmatch r {\n\t\tOk v -> v\n\t}",
	"fn r\n\tmatch r {\n\t\tOk v -> v\n\t\tOk w -> w\n\t\tErr e -> 0\n\t}",
	"fn r\n\tmatch r {\n\t\tFoo v -> v\n\t}",
	"fn r\n\tmatch r {\n\t\t_ -> 1\n\t\tOk v -> v\n\t}",
	"fn r\n\tmatch r {\n\t\tv -> 1\n\t\tOk v -> v\n\t}",
	"fn r\n\tmatch r {\n\t\tOk _ -> 1\n\t\tErr _ -> 2\n\t}",
	"fn r\n\tmatch r {\n\t\tOk v -> [v]\n\t\tErr e -> 0\n\t}",
	"fn r\n\tmatch r {\n\t\tOk v -> v\n\t\tErr e -> e\n\t}",
	"fn x\n\tmatch (+ x 1) {\n\t\tOk v -> v\n\t\tErr e -> 0\n\t}",
	"fn r\n\tmatch r {\n\t\tOk v -> (Ok v)\n\t\tErr e -> (Err e)\n\t}",
	"fn x\n\t(Ok x)",
	"fn x\n\t(Err x)",
	"fn x\n\tmatch x {\n\t\tErr e -> e\n\t\tOk v -> 1\n\t}",
	"fn x\n\tmatch x {\n\t\tv -> v\n\t}",
	"fn x\n\tmatch x {\n\t\tOk v -> v\n\t\tErr e -> (+ e 1)\n\t}",
	"fn x\n\tmatch x {\n\t\tOk v -> (+ v 1)\n\t\tErr e -> 0\n\t}",
	"fn x\n\tmatch x {\n\t\tOk v -> v\n\t\tErr e -> (+ e 1)\n\t}",
	"type Option a = None | Some a\n\nfn x\n\tSome x",
	"type Option a = None | Some a\n\nfn x\n\tmatch x {\n\t\tNone -> 0\n\t\tSome v -> v\n\t}",
	"type Option a = None | Some a\n\nfn x\n\tmatch x {\n\t\tNone -> 0\n\t}",
	"type Option a = None | Some a\n\nfn x\n\tmatch x {\n\t\tSome v -> v\n\t\tNone -> 0\n\t\tSome w -> w\n\t}",
	"type Tree = Leaf | Node (Tree . Tree)\n\nfn x\n\tNode (x . Leaf)",
	"type Tree = Leaf | Node (Tree . Tree)\n\nfn x\n\tNode (Leaf . Leaf)",
	"type Tree = Leaf | Node (Tree . Tree)\n\nfn x\n\tmatch x {\n\t\tLeaf -> 0\n\t\tNode (l . r) -> 1\n\t}",
	"type Tree = Leaf | Node (Tree . Tree)\n\nfn x\n\tmatch x {\n\t\tLeaf -> 0\n\t\tNode p -> 1\n\t}",
	"type A = X\ntype B = X\n\nfn x\n\tx",
	"type A = X\ntype A = Y\n\nfn x\n\tx",
	"type A = X Foo\n\nfn x\n\tx",
	"type Box a = Box a\n\nfn x\n\tBox x",
	"type Box a = Box a\ntype U = U Box\n\nfn x\n\tx",
	"type A = P Int\n\nfn x\n\t(P x)",
	"type A = X\n\nfn x\n\tY x",
	"type A = X | Y Int\n\nfn x\n\tmatch x {\n\t\tX -> 1\n\t\tY n -> (+ n 1)\n\t}",
	"type A = X | Y Int\ntype B = Z | W\n\nfn x\n\tmatch x {\n\t\tX -> 1\n\t\tZ -> 2\n\t}",
	"type A = X | Y Int\n\nfn x\n\tmatch x {\n\t\tX -> 1\n\t\tY -> 2\n\t}",
	"fn r\n\tr?",
	"fn r\n\tlet v = r?\n\tOk v",
	"fn r\n\tlet v = r?\n\tlet w = (Err 1)?\n\tOk (+ v w)",
	"fn r\n\tlet v = r?\n\tv",
	"fn r\n\t(Ok (+ (r?) 1))",
	"fn (r s)\n\tlet a = (r s)?\n\tOk a",
	"fn x\n\tcheck x",
	"fn x\n\tuntyped x",
	"fn x\n\tcheck (+ x 1)",
	"fn x\n\tuntyped (+ x 1)",
	"fn x\n\t(+ (untyped x) 1)",
	"fn x\n\t(+ (check x) 1)",
	"fn x\n\tlet y = (check x)\n\ty",
	"type Option a = None | Some a\n\nfn x\n\tlet v = (match x {\n\t\tNone -> 0\n\t\tSome n -> n\n\t})\n\tv",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn m\n\tfixed m",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn m\n\twith m {\n\t\tfixed = 1\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn x\n\tMS {\n\t\tst = 1\n\t\tfixed = 2\n\t\tcatch = 3\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn x\n\tMS {\n\t\tst = 1\n\t\tfixed = 2\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn m\n\tmatch m {\n\t\tMS {\n\t\t\tst = s\n\t\t\tfixed = f\n\t\t\tcatch = c\n\t\t} -> (+ s (+ f c))\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn x\n\tMS {\n\t\tst = 1\n\t\tfixed = (+ 1 1)\n\t\tcatch = (cons 1 ~)\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn x\n\tMS x",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn x\n\tfixed (+ x 1)",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn m\n\tmatch m {\n\t\tMS {\n\t\t\tst = _\n\t\t\tfixed = f\n\t\t\tcatch = _\n\t\t} -> f\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn m\n\tmatch m {\n\t\tMS {\n\t\t\tst = s\n\t\t\tfixed = f\n\t\t} -> f\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn m\n\twith m {\n\t\tcolor = 1\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn m\n\twith m {\n\t\tfixed = 1\n\t\tfixed = 2\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn m\n\tcatch (with m {\n\t\tfixed = 1\n\t})",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn m\n\tfixed (with m {\n\t\tfixed = (cons 1 ~)\n\t})",
	"type Tr = TEmpty | TNode {\n\tvalue: Int\n\tleft: Int\n}\n\nfn x\n\tmatch x {\n\t\tTEmpty -> 0\n\t\tTNode {\n\t\t\tvalue = v\n\t\t\tleft = l\n\t\t} -> (+ v l)\n\t}",
	"type Tr = TEmpty | TNode {\n\tvalue: Int\n\tleft: Int\n}\n\nfn x\n\tTNode {\n\t\tvalue = 1\n\t\tleft = 2\n\t}",
	"type One = One {\n\tv: Int\n}\n\nfn x\n\tv (One {\n\t\tv = x\n\t})",
	"type One = One {\n\tv: Int\n}\n\nfn x\n\tOne {\n\t\tv = x\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn x\n\tPair {\n\t\tleft = 1\n\t}",
	"type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\nfn x\n\tmatch x {\n\t\tMS {\n\t\t\tst = 1\n\t\t\tfixed = f\n\t\t\tcatch = c\n\t\t} -> f\n\t}",
}

for i, src in CASES do
	check(`case {i}`, src)
end

print(string.format("%d of %d programs give the same type or errors as the Luau checker (%d types, %d errors, %d skipped: the parser refuses them or a form is not handled yet)", total - failures, total, types, errors, skipped))

if failures > 0 then
	error(string.format("%d program(s) differ", failures))
end
