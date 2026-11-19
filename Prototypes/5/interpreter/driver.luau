--!strict
-- THE DRIVER
--
-- Runs a program that keeps a state between inputs. The program is a step: a function of a pair [state input], which gives a pair [state' output]. The state is data, so the driver can keep it between steps, store it, or send it on.
--
-- Each step is a lifecycle run, so its output is checked as data, and each step has its own fuel. A step that errors, runs out of fuel, returns something that is not a pair, or returns a function, ends the session, and the session reports which input it failed on.
--
--   Driver.step(step, state, input, fuel): StepResult
--   Driver.session(step, initial, inputs, fuel): Session
--   Driver.stepBytes(step, state, input, fuel): ByteStep    the same, with the program and state as bytes

const Binary = require "./binary"
const Lifecycle = require "./lifecycle"
const VM = require "./vm"

export type StepResult =
	| { status: "value", state: VM.Value, output: VM.Value, steps: number }
	| { status: "error", message: string, steps: number }
	| { status: "out_of_fuel", steps: number }
	| { status: "not_data", steps: number }

-- A session runs the inputs in order, and stops at the first step that does not give a value. state is the state after the last step that did.
export type Session = {
	status: string,
	state: VM.Value,
	outputs: { VM.Value },
	steps: number,
	failedAt: number?,
	message: string?,
}

export type ByteStep = {
	status: string,
	state: string?,
	output: string?,
	message: string?,
	steps: number,
}

-- Runs one step on a state and an input.
const function step(
	stepProgram: VM.Expr,
	state: VM.Value,
	input: VM.Value,
	fuel: number
): StepResult
	const pair: VM.Value = { kind = "cell", head = state, tail = input } :: VM.Cell
	const r = Lifecycle.run(stepProgram, pair, fuel)

	if r.status == "out_of_fuel" then
		return { status = "out_of_fuel", steps = r.steps }
	elseif r.status == "error" then
		return { status = "error", message = r.message, steps = r.steps }
	elseif r.status == "not_data" then
		return { status = "not_data", steps = r.steps }
	end

	const result = r.value

	if type(result) ~= "table" or result.kind ~= "cell" then
		return {
			status = "error",
			message = "a step must give a pair [state output]",
			steps = r.steps,
		}
	end

	return {
		status = "value",
		state = result.head,
		output = result.tail,
		steps = r.steps,
	}
end

-- Runs the inputs in order, carrying the state from each step to the next.
const function session(
	stepProgram: VM.Expr,
	initial: VM.Value,
	inputs: { VM.Value },
	fuel: number
): Session
	local state = initial
	local outputs: { VM.Value } = {}
	local steps = 0

	for i, input in inputs do
		const r = step(stepProgram, state, input, fuel)
		steps += r.steps

		if r.status ~= "value" then
			local message: string? = nil

			if r.status == "error" then
				message = r.message
			end

			return {
				status = r.status,
				state = state,
				outputs = outputs,
				steps = steps,
				failedAt = i,
				message = message,
			}
		end

		table.insert(outputs, r.output)
		state = r.state
	end

	return {
		status = "value",
		state = state,
		outputs = outputs,
		steps = steps,
	}
end

-- The same step, with the program, state and input as bytes, and the state and output as bytes. A program, state or input that does not decode is an error, and the step does not run.
const function stepBytes(
	stepBytesProgram: string,
	stateBytes: string,
	inputBytes: string,
	fuel: number
): ByteStep
	local program: VM.Expr
	local state: VM.Value
	local input: VM.Value

	local ok, err = pcall(function()
		program = Binary.decodeProgram(stepBytesProgram)
		state = Binary.decodeValue(stateBytes)
		input = Binary.decodeValue(inputBytes)
	end)

	if not ok then
		return {
			status = "error",
			message = tostring(err),
			steps = 0,
		}
	end

	const r = step(program, state, input, fuel)

	if r.status == "value" then
		return {
			status = "value",
			state = Binary.encodeValue(r.state),
			output = Binary.encodeValue(r.output),
			steps = r.steps,
		}
	elseif r.status == "error" then
		return {
			status = "error",
			message = r.message,
			steps = r.steps,
		}
	end

	return {
		status = r.status,
		steps = r.steps,
	}
end

return {
	step = step,
	session = session,
	stepBytes = stepBytes,
}
