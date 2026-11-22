--!strict
-- CHECKS THE BINARY FORMAT
--
-- Checks interpreter/binary.luau: the bytes for given values, a round trip for every example value and every example program, the bytes that are refused, and one deep program.
--
--   luau binary_run.luau      (from Prototypes/5)

const Programs = require "./L1/examples/programs"
const Text = require "./L1/examples/text"
const Examples = require "./examples/examples"
const Binary = require "./interpreter/binary"
const Data = require "./interpreter/data"
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

-- Unsigned LEB128, written independently of binary.luau, so the test does not check the encoder against itself.
const function leb(n: number): string
	local out = ""
	local m = n

	repeat
		local b = m % 128
		m = (m - b) / 128

		if m > 0 then
			b += 128
		end

		out ..= string.char(b)
	until m == 0

	return out
end

-- The bytes that should be written for given values. These fix the layout, not just the round trip.
const VECTORS: { { name: string; value: VM.Value; bytes: string } } = {
	{ name = "nil"; value = VM.NIL; bytes = "\1\0" },
	{ name = "0"; value = 0; bytes = "\1\2\0" },
	{ name = "-3"; value = -3; bytes = "\1\3\3" },
	{ name = "127, one byte"; value = 127; bytes = "\1\2\127" },
	{ name = "128, two bytes"; value = 128; bytes = "\1\2\128\1" },
	{ name = "cell 1 nil"; value = { kind = "cell"; head = 1; tail = VM.NIL } :: VM.Cell; bytes = "\1\1\2\1\0" },
}

for _, case in VECTORS do
	local ok, bytes = pcall(Binary.encodeValue, case.value)
	check(
		`bytes of {case.name}`,
		ok and bytes == case.bytes,
		if ok then
			`{#bytes} bytes`
		else
			tostring(bytes)
	)
end

-- Each vector read back to the same value.
for _, case in VECTORS do
	local ok, back = pcall(Binary.decodeValue, case.bytes)
	check(
		`reads {case.name}`,
		ok and Data.write(back :: VM.Value) == Data.write(case.value),
		if ok then
			Data.write(back :: VM.Value)
		else
			tostring(back)
	)
end

-- Every example that gives a value: a function or a pin is refused, and any other value comes back with the same bytes and the same text.
local valueRoundTrips = 0

const function valueRoundTrip(name: string, program: VM.Expr, fuel: number, outcome: string)
	const result = VM.run(program, fuel)

	if result.status ~= "value" or outcome ~= "value" then
		return
	end

	local ok, bytes = pcall(Binary.encodeValue, result.value)

	if not ok then
		check(`refuses {name}`, string.find(tostring(bytes), "has no binary form", 1, true) ~= nil, tostring(bytes))

		return
	end

	valueRoundTrips += 1
	local readOk, back = pcall(Binary.decodeValue, bytes)
	const again =
		if readOk then
			Binary.encodeValue(back :: VM.Value)
		else
			""
	check(
		`round trip {name}`,
		readOk and again == bytes and Data.write(back :: VM.Value) == Data.write(result.value),
		if readOk then
			`{#bytes} bytes`
		else
			tostring(back)
	)
end

for _, ex in Examples do
	valueRoundTrip(ex.name, ex.program, ex.fuel, ex.outcome)
end

for _, ex in Text.examples do
	valueRoundTrip(ex.name, ex.program, ex.fuel, ex.outcome)
end

for _, ex in Programs.examples do
	valueRoundTrip(ex.name, ex.program, ex.fuel, ex.outcome)
end

-- Two outcomes agree when they have the same status, the same step count, and the same value or message.
const function sameOutcome(a: VM.Outcome, b: VM.Outcome): boolean
	if a.status ~= b.status or a.steps ~= b.steps then
		return false
	end

	if a.status == "value" and b.status == "value" then
		return VM.show(a.value) == VM.show(b.value)
	end

	if a.status == "error" and b.status == "error" then
		return a.message == b.message
	end

	return true
end

-- Every example program: encoded, decoded, encoded again to the same bytes, and run to the same outcome and step count as the original.
local programRoundTrips = 0

const function programRoundTrip(name: string, program: VM.Expr, fuel: number)
	local ok, bytes = pcall(Binary.encodeProgram, program)

	if not ok then
		check(`encodes {name}`, false, tostring(bytes))

		return
	end

	local readOk, decoded = pcall(Binary.decodeProgram, bytes)

	if not readOk then
		check(`decodes {name}`, false, tostring(decoded))

		return
	end

	programRoundTrips += 1
	const again = Binary.encodeProgram(decoded :: VM.Expr)
	const direct = VM.run(program, fuel)
	const rebuilt = VM.run(decoded :: VM.Expr, fuel)
	const same = again == bytes and sameOutcome(direct, rebuilt)
	check(`program round trip {name}`, same, `{#bytes} bytes, {direct.steps} steps`)
end

for _, ex in Examples do
	programRoundTrip(ex.name, ex.program, ex.fuel)
end

for _, ex in Text.examples do
	programRoundTrip(ex.name, ex.program, ex.fuel)
end

for _, ex in Programs.examples do
	programRoundTrip(ex.name, ex.program, ex.fuel)
end

-- Bytes that must be refused. Each is a text in the form the decoder accepts, so each failure comes from the check named.
const REFUSED: { { name: string; bytes: string } } = {
	{ name = "empty"; bytes = "" },
	{ name = "only the header"; bytes = "\1" },
	{ name = "a program header on a value"; bytes = "\2\2\0" },
	{ name = "an unknown tag"; bytes = "\1\4" },
	{ name = "a tag inside a cell"; bytes = "\1\1\t\0" },
	{ name = "a cell cut short"; bytes = "\1\1\0" },
	{ name = "bytes after the value"; bytes = "\1\0\0" },
	{ name = "a negative zero"; bytes = "\1\3\0" },
	{ name = "a number with a zero last byte"; bytes = "\1\2\128\0" },
	{ name = "a number cut short"; bytes = "\1\2\255" },
	{ name = "an integer one past the limit"; bytes = "\1\2" .. leb(0x20000000000000) },
	{ name = "a number with too many bytes"; bytes = "\1\2\128\128\128\128\128\128\128\128\1" },
}

for _, case in REFUSED do
	local ok, err = pcall(Binary.decodeValue, case.bytes)
	check(
		`refuses {case.name}`,
		not ok,
		if ok then
			"it decoded, but it should not"
		else
			tostring(err)
	)
end

-- Program bytes that are well formed as values, but not as programs. Each is refused by the check on the shape of the program, not by the reader of the bytes.
const BAD_PROGRAMS: { { name: string; value: VM.Value } } = {
	{ name = "a value that is not a pair"; value = 0 },
	{ name = "an unknown tag"; value = { kind = "cell"; head = 99; tail = VM.NIL } :: VM.Cell },
	{ name = "a variable with a negative index"; value = { kind = "cell"; head = 2; tail = { kind = "cell"; head = -1; tail = VM.NIL } :: VM.Cell } :: VM.Cell },
	{ name = "nil with an argument"; value = { kind = "cell"; head = 1; tail = { kind = "cell"; head = 5; tail = VM.NIL } :: VM.Cell } :: VM.Cell },
	{ name = "a cell with one argument"; value = { kind = "cell"; head = 5; tail = { kind = "cell"; head = 0; tail = VM.NIL } :: VM.Cell } :: VM.Cell },
}

for _, case in BAD_PROGRAMS do
	local ok, err = pcall(Binary.decodeProgram, "\2" .. string.sub(Binary.encodeValue(case.value), 2))
	check(
		`refuses program {case.name}`,
		not ok,
		if ok then
			"it decoded, but it should not"
		else
			tostring(err)
	)
end

-- A program cannot be decoded from value bytes, and a value cannot be decoded from program bytes.
do
	local ok, err = pcall(Binary.decodeProgram, Binary.encodeValue(VM.NIL))
	check("refuses a value header on a program", not ok, tostring(err))
end

-- A deep program, past what a short example reaches. The encoder and decoder walk cells with a stack, so only the depth of the expression itself matters.
do
	local e: VM.Expr = VM.nilv()

	for i = 1, 2000 do
		e = VM.cell(VM.int(i), e)
	end

	local ok, bytes = pcall(Binary.encodeProgram, e)
	local readOk, decoded = false, nil

	if ok then
		readOk, decoded = pcall(Binary.decodeProgram, bytes)
	end

	check(
		"round trip a list of 2000 in a program",
		ok and readOk and Binary.encodeProgram(decoded :: VM.Expr) == bytes,
		if ok then
			`{#bytes} bytes`
		else
			tostring(bytes)
	)
end

-- Constructors: tag byte 4, then the tag and the payload, and read back to the same value.
do
	const c: VM.Value = { kind = "con"; tag = 2; payload = { kind = "cell"; head = 1; tail = VM.NIL } } :: VM.Con
	const bytes = Binary.encodeValue(c)
	check("a constructor is tag byte 4, its tag, then its payload", bytes == "\1\4\2\2\1\2\1\0", "")
	check("a constructor reads back", Data.write(Binary.decodeValue(bytes)) == "con 2 cons 1 nil", "")
	local rejected, _ = pcall(Binary.decodeValue, "\1\4\3\1")
	check("a negative constructor tag is refused", not rejected, "")
end

print(string.format("%d of %d checks passed (%d example values and %d example programs round-tripped)", total - failures, total, valueRoundTrips, programRoundTrips))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
