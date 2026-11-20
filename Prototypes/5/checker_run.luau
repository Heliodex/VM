--!strict
-- CHECKS THE CHECKER ON THE CASES THAT THE PROGRAM FILES DO NOT REACH
--
-- The untyped import: a value from untyped code has type Dyn, so a use of it at Int gets a check, and the run fails when the value is not an integer. Each run is through the desugarer and the machine, as a program is.
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
	const expr = Desugar.wrapImports(Desugar.desugarProgram(result.expr, { "raw" }, {}), { value })
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
	{ name = "a function of an integer", src = "fn x (+ x 1)", want = "(Int -> Int)" },
	{ name = "head of a list gives its item", src = "fn l (+ (head l) 1)", want = "([Int] -> Int)" },
	{ name = "a sum takes its own type", src = "type Option a = None | Some a\nfn o match o {\n\tNone -> 0\n\tSome v -> v\n}", want = "(Option Int -> Int)" },
	{ name = "a match result is a Result", src = "fn x (if x (Ok 1) (Err 2))", want = "(Int -> Result Int Int)" },
}

for _, case in SHOWN do
	const ok, res = pcall(function()
		return Checker.showScheme(Checker.check(Parser.parse(case.src), {}, "t.prog").scheme)
	end)
	const shown = if ok then res :: string else tostring(res)
	check(case.name, shown == case.want, shown)
end

-- An untyped value used as an Int: fine when it is one, refused when it is not.
check("an untyped integer is used at Int", runDyn("fn x (+ raw x)", VM.int(5), VM.int(1)) == "value 6", runDyn("fn x (+ raw x)", VM.int(5), VM.int(1)))
check("an untyped constructor is refused at Int", runDyn("fn x (+ raw x)", VM.construct(0, VM.int(5)), VM.int(1)) == "error expected Int", runDyn("fn x (+ raw x)", VM.construct(0, VM.int(5)), VM.int(1)))
check("an input of the wrong shape is refused on entry", runDyn("fn x (+ x 1)", VM.int(0), VM.construct(0, VM.int(1))) == "error expected Int", runDyn("fn x (+ x 1)", VM.int(0), VM.construct(0, VM.int(1))))
check("a list input is refused where an Int is needed", runDyn("fn x (+ x 1)", VM.int(0), VM.cell(VM.int(1), VM.nilv())) == "error expected Int", runDyn("fn x (+ x 1)", VM.int(0), VM.cell(VM.int(1), VM.nilv())))

print(string.format("%d of %d checks passed", total - failures, total))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
