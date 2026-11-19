--!strict
-- CHECKS THE DATA FORMAT
--
-- Checks interpreter/data.luau: the texts it writes for given values, the texts it rejects, and a round trip for every example that gives a value. A value that is a function or a pin must be refused by the writer.
--
--   luau data_run.luau      (from Prototypes/5)

const Data = require "./interpreter/data"
const Examples = require "./examples/examples"
const Programs = require "./L1/examples/programs"
const Reader = require "./L1/reader"
const Text = require "./L1/examples/text"
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

-- The value a program gives, for the cases below. Their programs are simple, so they are run directly.
const function valueOf(
	source: string
): VM.Value
	const result = VM.run(Reader.parse(source), 1e6)
	assert(result.status == "value", `{source} did not give a value`)
	return result.value :: VM.Value
end

-- A value and the text it should be written as.
const WRITES: { { source: string, text: string } } = {
	{ source = "0", text = "0" },
	{ source = "-3", text = "-3" },
	{ source = "9007199254740991", text = "9007199254740991" },
	{ source = "-9007199254740991", text = "-9007199254740991" },
	{ source = "~", text = "nil" },
	{ source = "[1 ~]", text = "cons 1 nil" },
	{ source = "[1 -3]", text = "cons 1 -3" },
	{ source = "[[1 ~] ~]", text = "cons cons 1 nil nil" },
	{ source = "[~ [~ ~]]", text = "cons nil cons nil nil" },
	{ source = "(list 1 2 3)", text = "cons 1 cons 2 cons 3 nil" },
}

for _, case in WRITES do
	const v = valueOf(case.source)
	local text = ""
	local ok, err = pcall(function()
		text = Data.write(v)
	end)

	check(`writes {case.source}`, ok and text == case.text, if ok then text else tostring(err))
end

-- A text that should be read as a value, and the text it should be written back as. These are the canonical forms, so the second is the first.
const READS: { string } = {
	"0",
	"-3",
	"nil",
	"cons 1 nil",
	"cons cons 1 nil nil",
	"cons 1 cons 2 cons 3 nil",
	"9007199254740991",
	"-9007199254740991",
}

for _, text in READS do
	local ok, back = pcall(Data.read, text)
	local again = if ok then Data.write(back) else ""
	check(`reads {text}`, ok and again == text, if ok then `back as {again}` else tostring(back))
end

-- Texts that are not canonical, or not a value. Each should be refused, so the format has one text per value.
const REJECTS: { string } = {
	"",
	" nil",
	"nil ",
	"nil  nil",
	"nil\n",
	"nil\tnil",
	"nil nil",
	"cons 1",
	"cons",
	"cons nil",
	"cons 1 nil nil",
	"007",
	"01",
	"-01",
	"-0",
	"+1",
	"1.5",
	"NIL",
	"[1 ~]",
	"(1 2)",
	"9007199254740992",
	"-9007199254740992",
	"cons 9007199254740992 nil",
}

for _, text in REJECTS do
	local ok, err = pcall(Data.read, text)
	const shown = string.gsub(string.format("%q", text), "\n", "\\n")
	check(`rejects {shown}`, not ok, if ok then "it read, but it should not" else tostring(err))
end

-- Writing a function or a pin is an error, and so is writing a cell that holds one.
const NO_FORM: { { source: string, what: string } } = {
	{ source = "(fn x x)", what = "a function" },
	{ source = "(pin 1)", what = "a pin" },
	{ source = "[1 (fn x x)]", what = "a function" },
	{ source = "[(pin 1) ~]", what = "a pin" },
}

for _, case in NO_FORM do
	local ok, err = pcall(Data.write, valueOf(case.source))
	check(
		`refuses {case.source}`,
		not ok and string.find(tostring(err), case.what .. " has no written form", 1, true) ~= nil,
		tostring(err)
	)
end

-- Every example that gives a value: a function or a pin is refused, and any other value must come back the same. Examples that do not give a value have nothing to write.
local roundTrips = 0
const function roundTrip(
	name: string,
	program: VM.Expr,
	fuel: number,
	outcome: string
)
	const result = VM.run(program, fuel)

	if result.status ~= "value" or outcome ~= "value" then
		return
	end

	local ok, text = pcall(Data.write, result.value)

	if not ok then
		check(`writer refuses {name}`, string.find(tostring(text), "has no written form", 1, true) ~= nil, tostring(text))
		return
	end

	roundTrips += 1
	local readOk, readValue = pcall(Data.read, text)
	local rewritten = if readOk then Data.write(readValue :: VM.Value) else ""

	check(`round trip {name}`, readOk and rewritten == text, if readOk then text else tostring(readValue))
end

for _, ex in Examples do
	roundTrip(ex.name, ex.program, ex.fuel, ex.outcome)
end

for _, ex in Text.examples do
	roundTrip(ex.name, ex.program, ex.fuel, ex.outcome)
end

for _, ex in Programs.examples do
	roundTrip(ex.name, ex.program, ex.fuel, ex.outcome)
end

-- A long list, so the iterative paths are exercised far past any nesting limit.
do
	local list: VM.Value = VM.NIL
	for i = 1, 100000 do
		list = { kind = "cell", head = i, tail = list } :: VM.Cell
	end

	const ok, text = pcall(Data.write, list)
	local readOk, back = false, nil
	if ok then
		readOk, back = pcall(Data.read, text)
	end

	check(
		"round trip a list of 100000",
		ok and readOk and Data.write(back :: VM.Value) == text,
		if ok then `{#text} characters` else tostring(text)
	)
end

print(string.format("%d of %d checks passed (%d example values round-tripped)", total - failures, total, roundTrips))

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
