--!strict
-- THE PROGRAM LIFECYCLE
--
-- A program is a function. The host applies it to an input value, and the result is the output: a data value, fully evaluated. Nothing else crosses the boundary, so a run is determined by the program, the input and the fuel.
--
-- The output is checked in the language, so the forcing of pins costs fuel like any other step. The check walks the value. A pin is forced, and its result is walked in turn. A cell has its head and tail walked. An integer or nil is data. A function is not data, and the check stops there. The check returns a pair: [0 v] for data, with v the value, or [1 ~] for a function.
--
-- A pin that never finishes therefore uses up the fuel, and the run ends out_of_fuel.
--
--   Lifecycle.run(program, input, fuel): Result        the program as an expression, the input as a value
--   Lifecycle.runBytes(program, input, fuel): ByteResult  the program and the input as binary, the output as binary
--
-- The outcomes are value, error, out_of_fuel, and not_data, which is a run whose output holds a function.

const Binary = require "./binary"
const Reader = require "../L1/reader"
const VM = require "./vm"

export type Result =
	| { status: "value", value: VM.Value, steps: number }
	| { status: "error", message: string, steps: number }
	| { status: "out_of_fuel", steps: number }
	| { status: "not_data", steps: number }

export type ByteResult =
	| { status: "value", bytes: string, steps: number }
	| { status: "error", message: string, steps: number }
	| { status: "out_of_fuel", steps: number }
	| { status: "not_data", steps: number }

-- The output check, as a program. Its tags are 0 for data and 1 for a function.
const CHECK = Reader.parse(
	"(fix (lam rec (lam v (if (= (kind v) 4) (rec (force v)) (if (= (kind v) 2) (let h (rec (head v)) (if (= (head h) 1) h (let t (rec (tail v)) (if (= (head t) 1) t [0 [(tail h) (tail t)]])))) (if (= (kind v) 3) [1 ~] [0 v]))))))"
)

-- Runs the program on the input, and checks the output. The outcome is a Result.
const function run(
	program: VM.Expr,
	input: VM.Value,
	fuel: number
): Result
	-- The input is the variable 0, in an environment that holds it. So an input does not need an expression form, and a function can be an input.
	const checked = VM.app(CHECK, VM.app(program, VM.var(0)))
	const outcome = VM.run(checked, fuel, { value = input, rest = nil })

	if outcome.status == "out_of_fuel" then
		return {
			status = "out_of_fuel",
			steps = outcome.steps,
		}
	elseif outcome.status == "error" then
		return {
			status = "error",
			message = outcome.message,
			steps = outcome.steps,
		}
	end

	-- The check always gives a pair, with a tag and a payload.
	const pair = outcome.value :: VM.Cell
	const tag = pair.head :: number

	if tag == 1 then
		return {
			status = "not_data",
			steps = outcome.steps,
		}
	end

	return {
		status = "value",
		value = pair.tail,
		steps = outcome.steps,
	}
end

-- The same run with the program and input as binary, and the output as binary. A program or input that does not decode is an error, and the program is not run.
const function runBytes(
	programBytes: string,
	inputBytes: string,
	fuel: number
): ByteResult
	local program: VM.Expr
	local input: VM.Value

	local ok, err = pcall(function()
		program = Binary.decodeProgram(programBytes)
		input = Binary.decodeValue(inputBytes)
	end)

	if not ok then
		return {
			status = "error",
			message = tostring(err),
			steps = 0,
		}
	end

	const result = run(program, input, fuel)

	if result.status == "value" then
		return {
			status = "value",
			bytes = Binary.encodeValue(result.value),
			steps = result.steps,
		}
	elseif result.status == "error" then
		return {
			status = "error",
			message = result.message,
			steps = result.steps,
		}
	elseif result.status == "out_of_fuel" then
		return {
			status = "out_of_fuel",
			steps = result.steps,
		}
	end

	return {
		status = "not_data",
		steps = result.steps,
	}
end

return {
	run = run,
	runBytes = runBytes,
}
