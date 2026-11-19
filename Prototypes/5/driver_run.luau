--!strict
-- CHECKS THE DRIVER
--
-- Checks interpreter/driver.luau: a counter that keeps a number between inputs, a state that is a list, each way a step can end a session, and the same sessions through the binary format, with the state carried as bytes.
--
--   luau driver_run.luau      (from Prototypes/5)

const Binary = require "./interpreter/binary"
const Data = require "./interpreter/data"
const Driver = require "./interpreter/driver"
const Reader = require "./L1/reader"
const VM = require "./interpreter/vm"

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

const FUEL = 100000

-- The value of an input written as a program, which must give a value.
const function valueOf(
	source: string
): VM.Value
	const r = VM.run(Reader.parse(source), 1000)

	if r.status ~= "value" then
		error(`the input {source} does not give a value`, 0)
	end

	return r.value
end

-- A counter. The state is a number, and each step adds the input to it and outputs the state before.
const COUNTER = "(lam p (let s (head p) (let i (tail p) [(+ s i) s])))"

do
	const session = Driver.session(Reader.parse(COUNTER), valueOf("0"), { valueOf("1"), valueOf("2"), valueOf("3") }, FUEL)
	local outputs = {}
	for _, o in session.outputs do
		table.insert(outputs, Data.write(o))
	end

	check(
		"a counter keeps its state",
		session.status == "value" and table.concat(outputs, " ") == "0 1 3" and Data.write(session.state) == "6",
		`outputs {table.concat(outputs, " ")}, state {Data.write(session.state)}, steps {session.steps}`
	)
end

-- A state that is a list: each step puts the input on the front, and outputs the list as it was.
do
	const session = Driver.session(
		Reader.parse("(lam p [[(tail p) (head p)] (head p)])"),
		valueOf("~"),
		{ valueOf("1"), valueOf("2"), valueOf("3") },
		FUEL
	)
	local outputs = {}
	for _, o in session.outputs do
		table.insert(outputs, Data.write(o))
	end

	check(
		"a state that is a list grows by a step",
		session.status == "value" and table.concat(outputs, " | ") == "nil | cons 1 nil | cons 2 cons 1 nil" and Data.write(session.state) == "cons 3 cons 2 cons 1 nil",
		`outputs {table.concat(outputs, " | ")}`
	)
end

-- No inputs: the session has no outputs, and the state is the initial one.
do
	const session = Driver.session(Reader.parse(COUNTER), valueOf("7"), {}, FUEL)
	check("no inputs leaves the state alone", session.status == "value" and #session.outputs == 0 and Data.write(session.state) == "7", `state {Data.write(session.state)}`)
end

-- Each way a step can end a session. The session reports the status, and the input it failed on.
const FAILURES: { { name: string, step: string, status: string, failedAt: number, message: string? } } = {
	{ name = "a step that errors", step = "(lam p (head 5))", status = "error", failedAt = 1, message = "head of a non-cell" },
	{ name = "a step that gives a number, not a pair", step = "(lam p 7)", status = "error", failedAt = 1, message = "a step must give a pair [state output]" },
	{ name = "a step whose state is a function", step = "(lam p [(lam y y) ~])", status = "not_data", failedAt = 1, message = nil },
	{ name = "a step whose output is a function", step = "(lam p [~ (lam y y)])", status = "not_data", failedAt = 1, message = nil },
	{
		name = "a step that runs out of fuel",
		step = "(lam p [(tail p) ((fix (lam f (lam n (f n)))) 0)])",
		status = "out_of_fuel",
		failedAt = 1,
		message = nil,
	},
}

for _, case in FAILURES do
	const session = Driver.session(Reader.parse(case.step), valueOf("0"), { valueOf("1"), valueOf("2") }, 10000)
	const ok = session.status == case.status
		and session.failedAt == case.failedAt
		and session.message == case.message
		and #session.outputs == 0
	check(case.name, ok, `{session.status} at input {tostring(session.failedAt)}{if session.message then ": " .. session.message else ""}`)
end

-- The session keeps what it had before the failure: the state after the last step that gave a value.
do
	const session = Driver.session(
		Reader.parse("(lam p (if (= (tail p) 3) (head 5) (let s (head p) (let i (tail p) [(+ s i) s]))))"),
		valueOf("0"),
		{ valueOf("1"), valueOf("2"), valueOf("3") },
		FUEL
	)

	check(
		"a failure keeps the state from before it",
		session.status == "error" and session.failedAt == 3 and Data.write(session.state) == "3" and #session.outputs == 2,
		`state {Data.write(session.state)} after {#session.outputs} outputs`
	)
end

-- The counter through the binary format. The program is bytes, and the state is carried from one step to the next as bytes.
do
	const program = Binary.encodeProgram(Reader.parse(COUNTER))
	local stateBytes = Binary.encodeValue(valueOf("0"))
	local outputs = {}
	local allOk = true

	for _, input in { "1", "2", "3" } do
		const r = Driver.stepBytes(program, stateBytes, Binary.encodeValue(valueOf(input)), FUEL)

		if r.status ~= "value" then
			allOk = false
			break
		end

		stateBytes = r.state :: string
		table.insert(outputs, Data.write(Binary.decodeValue(r.output :: string)))
	end

	check(
		"a counter through bytes",
		allOk and table.concat(outputs, " ") == "0 1 3" and Data.write(Binary.decodeValue(stateBytes)) == "6",
		`outputs {table.concat(outputs, " ")}`
	)
end

-- Bytes that do not decode are an error, and the step does not run.
do
	const r = Driver.stepBytes(Binary.encodeProgram(Reader.parse(COUNTER)), "", Binary.encodeValue(valueOf("1")), FUEL)
	check("a bad state is an error, and the step does not run", r.status == "error" and r.steps == 0, r.status)
end

do
	const r = Driver.stepBytes("junk", Binary.encodeValue(valueOf("0")), Binary.encodeValue(valueOf("1")), FUEL)
	check("a bad program is an error, and the step does not run", r.status == "error" and r.steps == 0, r.status)
end

print(string.format("%d of %d checks passed", total - failures, total))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
