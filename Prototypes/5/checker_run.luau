--!strict
-- CHECKS THE CHECKER ON THE CASES THAT THE PROGRAM FILES DO NOT REACH
--
-- The untyped import: a value from untyped code has type Dyn. It is used at a type only through an explicit check, which gives Ok or Err. Each run is through the desugarer and the machine, as a program is.
--
--   lute run checker_run.luau      (from Prototypes/5)

const Parser = require "./L2/parser"
const Checker = require "./L2/checker"
const Desugar = require "./L2/desugar"
const Lifecycle = require "./interpreter/lifecycle"
const VM = require "./interpreter/vm"
const Data = require "./interpreter/data"

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

-- Checks src with one untyped import named raw, runs it on input with raw bound to value, and gives the outcome. A failed run gives its status and its message. The input is an expression that gives the value the program is run on.
const function runDyn(
	src: string,
	value: VM.Expr,
	inputExpr: VM.Expr
): string
	const given = VM.run(inputExpr, 1000)

	if given.status ~= "value" then
		error("the input does not give a value", 0)
	end

	const input = given.value :: VM.Value
	const parsed = Parser.parse(src)
	const result = Checker.check(parsed, { { name = "raw", scheme = Checker.untyped() } }, "dyn.prog")
	const expr = Desugar.wrapImports(Desugar.desugarProgram(result.expr, { "raw" }, Desugar.buildCtors({})), { value })
	const outcome = Lifecycle.run(Desugar.boundary(expr, result.input, result.inputExpect), input, 100000)

	if outcome.status == "value" then
		return "value " .. Data.write(outcome.value)
	end

	if outcome.status == "error" then
		return "error " .. outcome.message
	end

	return outcome.status
end

-- The types of programs, as the checker writes them. Each is concrete, so it has no variable numbers to compare.
const SHOWN: { { name: string, src: string, want: string } } = {
	{ name = "a function of an integer", src = "fn x\n\t(+ x 1)", want = "(Int -> Int)" },
	{ name = "head of a list gives its item", src = "fn l\n\tmatch (head l) {\n\t\tOk h -> (+ h 1)\n\t\tErr e -> 0\n\t}", want = "([Int] -> Int)" },
	{ name = "head gives a Result", src = "fn x\n\t(head [x 1])", want = "(Int -> Result Int ([Int]))" },
	{ name = "fst and snd take a pair apart", src = "fn p\n\t(+ (fst p) (snd p))", want = "((Int . Int) -> Int)" },
	{ name = "cons makes a list", src = "fn x\n\t(cons x [1])", want = "(Int -> [Int])" },
	{ name = "division gives a Result", src = "fn x\n\t(/ 10 x)", want = "(Int -> Result Int ([Int]))" },
	{ name = "a sum takes its own type", src = "type Option a = None | Some a\nfn o\n\tmatch o {\n\tNone -> 0\n\tSome v -> v\n}", want = "(Option Int -> Int)" },
	{ name = "a match result is a Result", src = "fn x\n\t(if x (Ok 1) (Err 2))", want = "(Int -> Result Int Int)" },
}

for _, case in SHOWN do
	const ok, res = pcall(function()
		return Checker.showScheme(Checker.check(Parser.parse(case.src), {}, "t.prog").scheme)
	end)
	const shown = if ok then res :: string else tostring(res)
	check(case.name, shown == case.want, shown)
end

-- The text of an error value, as the L2 program writes it: Err with the bytes of the message.
const function bytesOf(
	s: string
): VM.Expr
	local v: VM.Expr = VM.nilv()

	for i = #s, 1, -1 do
		v = VM.cell(VM.int(string.byte(s, i) :: number), v)
	end

	return v
end

-- The value an expression gives, written as Data writes it.
const function writtenOf(
	e: VM.Expr
): string
	const r = VM.run(e, 1000)

	if r.status ~= "value" then
		error("the expected value does not give a value", 0)
	end

	return Data.write(r.value :: VM.Value)
end

-- Checks src, with an untyped import raw, and gives the type error, or "accepted" when it has none.
const function typeOf(
	src: string
): string
	const ok, res = pcall(Checker.check, Parser.parse(src), { { name = "raw", scheme = Checker.untyped() } }, "dyn.prog")
	return if ok then "accepted" else tostring(res)
end

-- A value from untyped code used at Int without a check is a type error, and the message says it is untyped.
const refusal = typeOf("fn x\n\t(+ raw x)")
check("an untyped value is refused at Int without a check", string.find(refusal, "expected Int, but this is Dyn", 1, true) ~= nil, refusal)

-- An explicit check gives Ok when the value has the type, and Err with the expected type when it does not.
const CHECKED = "fn x\n\tmatch (check raw) {\n\t\tOk v -> (Ok (+ v x))\n\t\tErr e -> (Err e)\n\t}"
check("an explicit check gives Ok for an integer", runDyn(CHECKED, VM.int(5), VM.int(1)) == "value " .. writtenOf(VM.construct(0, VM.int(6))), runDyn(CHECKED, VM.int(5), VM.int(1)))
check("an explicit check gives Err for a constructor", runDyn(CHECKED, VM.construct(0, VM.int(5)), VM.int(1)) == "value " .. writtenOf(VM.construct(1, bytesOf("expected Int"))), runDyn(CHECKED, VM.construct(0, VM.int(5)), VM.int(1)))
check("an explicit check gives Err for a list", runDyn(CHECKED, VM.cell(VM.int(1), VM.nilv()), VM.int(1)) == "value " .. writtenOf(VM.construct(1, bytesOf("expected Int"))), runDyn(CHECKED, VM.cell(VM.int(1), VM.nilv()), VM.int(1)))

-- The input is checked on entry, and a wrong input gives Err as the run's value.
check("an input of the wrong shape gives Err on entry", runDyn("fn x\n\t(+ x 1)", VM.int(0), VM.construct(0, VM.int(1))) == "value " .. writtenOf(VM.construct(1, bytesOf("expected Int"))), runDyn("fn x\n\t(+ x 1)", VM.int(0), VM.construct(0, VM.int(1))))
check("a list input gives Err on entry where an Int is needed", runDyn("fn x\n\t(+ x 1)", VM.int(0), VM.cell(VM.int(1), VM.nilv())) == "value " .. writtenOf(VM.construct(1, bytesOf("expected Int"))), runDyn("fn x\n\t(+ x 1)", VM.int(0), VM.cell(VM.int(1), VM.nilv())))

-- The untyped form: a value made Dyn with untyped is used at a type only through check, so an Int passes and anything else gives Err.
const UNTYPED = "fn x\n\tmatch (check (untyped x)) {\n\t\tOk v -> (+ v 1)\n\t\tErr e -> 0\n\t}"
check("untyped makes a value Dyn, and check gives Ok for an integer", runDyn(UNTYPED, VM.int(0), VM.int(5)) == "value 6", runDyn(UNTYPED, VM.int(0), VM.int(5)))
check("untyped makes a value Dyn, and check gives Err for a list", runDyn(UNTYPED, VM.int(0), VM.cell(VM.int(1), VM.nilv())) == "value 0", runDyn(UNTYPED, VM.int(0), VM.cell(VM.int(1), VM.nilv())))
check("untyped gives Dyn, which is a type error without check", string.find(typeOf("fn x\n\t(+ (untyped x) 1)"), "but this is Dyn", 1, true) ~= nil, typeOf("fn x\n\t(+ (untyped x) 1)"))

-- Every type error in a program is reported, one per line, not only the first.
const twoErrors = typeOf("let a = (+ 1 [2])\nlet b = (+ 1 ~)\nfn x\n\t(+ x 0)")
local errorLines = 0

for _ in string.gmatch(twoErrors, "[^\n]+") do
	errorLines += 1
end

check("two type errors are both reported", errorLines == 2 and string.find(twoErrors, "line 1", 1, true) ~= nil and string.find(twoErrors, "line 2", 1, true) ~= nil, twoErrors)

-- A pair is not a list: head of a pair is a type error, and so is fst of a list.
check("head of a pair is a type error", string.find(typeOf("fn x\n\t(head (1 . 2))"), "but this is (Int . Int)", 1, true) ~= nil, typeOf("fn x\n\t(head (1 . 2))"))
check("fst of a list is a type error", string.find(typeOf("fn x\n\t(fst [1 2])"), "but this is [Int]", 1, true) ~= nil, typeOf("fn x\n\t(fst [1 2])"))

print(string.format("%d of %d checks passed", total - failures, total))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
