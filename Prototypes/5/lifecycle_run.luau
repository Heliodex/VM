--!strict
-- CHECKS THE PROGRAM LIFECYCLE
--
-- Checks interpreter/lifecycle.luau: a program applied to an input gives its output, pins in the output are forced, a function in the output is not_data, and a pin that never finishes uses up the fuel. Then the same runs through the binary format, from bytes in to bytes out.
--
--   luau lifecycle_run.luau      (from Prototypes/5)

const Reader = require "./L1/reader"
const Binary = require "./interpreter/binary"
const Data = require "./interpreter/data"
const Lifecycle = require "./interpreter/lifecycle"
const VM = require "./interpreter/vm"

local failures = 0
local total = 0

const function check(name: string, ok: boolean, detail: string)
	total += 1

	if ok then
		print(string.format("PASS  %s  -> %s", name, detail))
	else
		failures += 1
		print(string.format("FAIL  %s  -> %s", name, detail))
	end
end

const function describe(r: Lifecycle.Result): string
	if r.status == "value" then
		return `value {Data.write(r.value)}`
	elseif r.status == "error" then
		return `error: {r.message}`
	end

	return r.status
end

-- A program, an input as a program, the outcome it should give, and the output text it should give for a value.
type Case = {
	name: string,
	program: string,
	input: string,
	status: string,
	output: string?,
}

-- The value of an input written as a program, which must give a value.
const function valueOf(source: string): VM.Value
	const r = VM.run(Reader.parse(source), 1000)

	if r.status ~= "value" then
		error(`the input {source} does not give a value`, 0)
	end

	return r.value
end

const CASES: { Case } = {
	{ name = "identity"; program = "(fn x x)"; input = "[1 [2 ~]]"; status = "value"; output = "cons 1 cons 2 nil" },
	{ name = "add one"; program = "(fn x (+ x 1))"; input = "41"; status = "value"; output = "42" },
	{
		name = "sum a list",
		program = "(fn xs (letrec sum (fn l (if (? l) 0 (+ (head l) (sum (tail l))))) (sum xs)))",
		input = "(list 1 2 3 4 5 6 7 8 9 10)",
		status = "value",
		output = "55",
	},
	{ name = "a pin in a cell is forced"; program = "(fn x [1 (pin (+ x 1))])"; input = "5"; status = "value"; output = "cons 1 6" },
	{ name = "a pin of a pin is forced"; program = "(fn x (pin (pin 7)))"; input = "0"; status = "value"; output = "7" },
	{ name = "a function is not data"; program = "(fn x (fn y y))"; input = "1"; status = "not_data"; output = nil },
	{ name = "a function inside a cell is not data"; program = "(fn x [1 (fn y y)])"; input = "0"; status = "not_data"; output = nil },
	{ name = "a pin that errors is an error"; program = "(fn x [1 (pin (head 5))])"; input = "0"; status = "error"; output = nil },
	{
		name = "a pin that diverges runs out of fuel",
		program = "(fn x [1 (pin ((fix (fn f (fn n (f n)))) 0))])",
		input = "0",
		status = "out_of_fuel",
		output = nil,
	},
	{ name = "a program that loops runs out of fuel"; program = "(fn x ((fix (fn f (fn n (f n)))) x))"; input = "0"; status = "out_of_fuel"; output = nil },
	{ name = "a program that is not a function is an error"; program = "7"; input = "0"; status = "error"; output = nil },
}
const FUEL = 100000

for _, case in CASES do
	const result = Lifecycle.run(Reader.parse(case.program), valueOf(case.input), FUEL)
	const shown = describe(result)

	if case.status == "value" then
		check(case.name, result.status == "value" and Data.write(result.value) == case.output, shown)
	else
		check(case.name, result.status == case.status, shown)
	end
end

-- The same cases through the binary format: the program and input go in as bytes, and the value comes out as bytes.
const function runBytes(program: string, input: string): Lifecycle.ByteResult
	return Lifecycle.runBytes(Binary.encodeProgram(Reader.parse(program)), Binary.encodeValue(valueOf(input)), FUEL)
end

for _, case in CASES do
	const result = runBytes(case.program, case.input)

	if case.status == "value" then
		local ok, back = pcall(
			Binary.decodeValue,
			if result.status == "value" then
				result.bytes
			else
				""
		)
		check(
			`bytes: {case.name}`,
			result.status == "value" and ok and Data.write(back :: VM.Value) == case.output,
			if result.status == "value" then
				`{#result.bytes} bytes`
			else
				result.status
		)
	else
		check(`bytes: {case.name}`, result.status == case.status, result.status)
	end
end

-- A long output, so the output check and the writer walk a long list, and the bytes decode back to it.
do
	const program = "(fn n (letrec up (fn i (if (= i 0) ~ [i (up (- i 1))])) (up n)))"
	const result = Lifecycle.runBytes(Binary.encodeProgram(Reader.parse(program)), Binary.encodeValue(valueOf "1000"), 1e7)

	if result.status == "value" then
		local ok, back = pcall(Binary.decodeValue, result.bytes)
		const text =
			if ok then
				Data.write(back :: VM.Value)
			else
				""
		const _, cells = string.gsub(text, "cons", "")
		check("a list of 1000 comes out as bytes", ok and cells == 1000 and string.sub(text, 1, 27) == "cons 1000 cons 999 cons 998" and string.sub(text, -10) == "cons 1 nil", `{#result.bytes} bytes, {cells} cells, steps {result.steps}`)
	else
		check("a list of 1000 comes out as bytes", false, result.status)
	end
end

-- Bytes that do not decode are an error, and the program is not run.
do
	const result = Lifecycle.runBytes("", "", FUEL)
	check("bad program bytes are an error", result.status == "error" and result.steps == 0, result.status)
end

do
	const result = Lifecycle.runBytes(Binary.encodeProgram(Reader.parse "(fn x x)"), "\1\4", FUEL)
	check("bad input bytes are an error", result.status == "error" and result.steps == 0, result.status)
end

-- A constructor is built directly, since the L1 text has no constructors. Its payload decides whether it is data: a plain payload is data, and a pin or a function under it is not_data.
do
	const plain = Lifecycle.run(VM.lam(VM.construct(0, VM.int(1))), VM.NIL, 1000)
	check("a constructor with a plain payload is data", plain.status == "value" and Data.write(plain.value) == "con 0 1", plain.status)
	const withPin = Lifecycle.run(VM.lam(VM.construct(0, VM.pin(VM.int(1)))), VM.NIL, 1000)
	check("a pin under a constructor is not data", withPin.status == "not_data", withPin.status)
	const withFunction = Lifecycle.run(VM.lam(VM.construct(0, VM.lam(VM.var(0)))), VM.NIL, 1000)
	check("a function under a constructor is not data", withFunction.status == "not_data", withFunction.status)
end

print(string.format("%d of %d checks passed", total - failures, total))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
