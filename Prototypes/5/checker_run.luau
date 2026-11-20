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

-- Checks src with one untyped import named raw, runs it on input with raw bound to value, and gives the outcome.
const function runDyn(
	src: string,
	value: VM.Expr,
	input: number
): string
	const parsed = Parser.parse(src)
	const result = Checker.check(parsed, { { name = "raw", scheme = Checker.untyped() } }, "dyn.prog")
	const expr = Desugar.wrapImports(Desugar.desugarProgram(result.expr, { "raw" }, {}), { value })
	const outcome = Lifecycle.run(Desugar.boundary(expr, result.input), input, 100000)

	if outcome.status == "value" then
		return "value " .. Data.write(outcome.value)
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
check("an untyped integer is used at Int", runDyn("fn x (+ raw x)", VM.int(5), 1) == "value 6", runDyn("fn x (+ raw x)", VM.int(5), 1))
check("an untyped constructor is refused at Int", runDyn("fn x (+ raw x)", VM.construct(0, VM.int(5)), 1) == "error", runDyn("fn x (+ raw x)", VM.construct(0, VM.int(5)), 1))

print(string.format("%d of %d checks passed", total - failures, total))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
