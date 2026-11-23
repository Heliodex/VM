--!strict
-- CHECKS THE PROTOTYPE 7 BINARY FORMAT (SPEC.md section 12)
--
-- Checks reference/format.luau and reference/int.luau against the examples of the spec: the bytes of given values and programs, round trips for values and programs (including integers past 2^53, a long list, and a program nested 20,000 deep), and the bytes that are refused, each with its reason. The bytes in this file are written by hand from the spec, and the LEB128 numbers are checked against a separate hand-written encoder, so the test does not check the writer against itself.
--
--   lute run format_run.luau     (from Prototypes/7/reference)

const Int = require "./int"
const Format = require "./format"

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

-- The bytes of a string, as a hex list, for showing what was written.
const function hex(s: string): string
	local out: { string } = {}

	for i = 1, #s do
		table.insert(out, string.format("%02x", string.byte(s, i)))
	end

	return table.concat(out, " ")
end

-- Unsigned LEB128, written here independently of format.luau, for the numbers in the tests.
const function leb(n: number): string
	local out: { string } = {}
	local m = n

	while true do
		local b = m % 128
		m = (m - b) / 128

		if m > 0 then
			b += 128
		end

		table.insert(out, string.char(b))

		if m == 0 then
			break
		end
	end

	return table.concat(out)
end

-- Whether two values are the same, following every table, so a round trip is checked deeply.
local function isInt(v: any): boolean
	return type(v) == "number" or Int.isBig(v)
end

-- Iterative, so a deep program does not overflow the call stack of the test.
local function same(a: any, b: any): boolean
	local pending: { { any } } = { { a, b } }

	while #pending > 0 do
		const pair = table.remove(pending) :: { any }
		const x = pair[1]
		const y = pair[2]

		if isInt(x) or isInt(y) then
			if not (isInt(x) and isInt(y) and Int.equal(x, y)) then
				return false
			end
		elseif type(x) ~= "table" or type(y) ~= "table" then
			if x ~= y then
				return false
			end
		else
			for k in y do
				if x[k] == nil then
					return false
				end
			end

			for k, v in x do
				if y[k] == nil then
					return false
				end

				table.insert(pending, { v, y[k] })
			end
		end
	end

	return true
end

-- Builders, so the tests read like the spec.
const function lit(v: any): any
	return { op = "lit", value = v }
end

const function arg(i: number): any
	return { op = "arg", index = i }
end

const function call(f: any, ...: any): any
	return { op = "call", f = f, args = { ... } }
end

const function prim(tag: number, ...: any): any
	return { op = "prim", tag = tag, args = { ... } }
end

const function law(arity: number, body: any): any
	return { kind = "law", arity = arity, body = body }
end

const function cell(a: any, b: any): any
	return { kind = "cell", head = a, tail = b }
end

const function list(...: any): any
	local items = { ... }
	local v: any = Format.NIL

	for i = #items, 1, -1 do
		v = cell(items[i], v)
	end

	return v
end

-- The integer 2^53, which is past the number range, as a big integer.
const TWO_53 = Int.fromMagnitude(false, { 0, 0, 0, 0, 0, 0, 32 })

-- 1. The bytes of the examples in the spec (section 12.5).
do
	const cases: { { name: string, value: any, want: string } } = {
		{ name = "the value 0", value = 0, want = "\1\2\0" },
		{ name = "the value -1", value = -1, want = "\1\3\1" },
		{ name = "the value nil", value = Format.NIL, want = "\1\0" },
		{ name = "the list (1 2)", value = list(1, 2), want = "\1\1\2\1\1\2\2\0" },
		{ name = "the integer 2^53", value = TWO_53, want = "\1\2\128\128\128\128\128\128\128\16" },
		{ name = "the integer 128", value = 128, want = "\1\2\128\1" },
		{ name = "the integer 300", value = 300, want = "\1\2\172\2" },
	}

	for _, c in cases do
		const got = Format.encodeValue(c.value)
		check(c.name .. " is written as the spec says", got == c.want, `{hex(got)}`)
	end

	-- The groups of 2^53 agree with the separate encoder: seven groups of zero, then the group 16, which is eight bytes in all.
	const groups = Int.lebGroups(Int.magnitudeBytes(TWO_53))
	const separate = leb(9007199254740992)
	check("2^53's groups match the separate encoder's bytes", #separate == #groups and string.byte(separate, #separate) == groups[#groups] and #groups == 8, `{#groups} groups, separate encoder {#separate} bytes`)
end

-- 2. Round trips for values.
do
	const values: { { name: string, value: any } } = {
		{ name = "0", value = 0 },
		{ name = "-1", value = -1 },
		{ name = "2^53 - 1 (the largest number)", value = Int.MAX_SAFE },
		{ name = "-(2^53 - 1)", value = -Int.MAX_SAFE },
		{ name = "2^53 (a big integer)", value = TWO_53 },
		{ name = "-(2^53) (a big integer)", value = Int.fromMagnitude(true, { 0, 0, 0, 0, 0, 0, 32 }) },
		{ name = "2^100", value = Int.fromMagnitude(false, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16 }) },
		{ name = "-(2^100 + 7)", value = Int.fromMagnitude(true, { 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16 }) },
		{ name = "nil", value = Format.NIL },
		{ name = "a list of 5000 integers", value = (function()
			local items: { any } = {}

			for i = 1, 5000 do
				items[i] = i * 1000000007
			end

			return list(table.unpack(items))
		end)() },
		{ name = "a constructor", value = { kind = "con", tag = 3, payload = cell(-5, Format.NIL) } },
		{ name = "a law", value = law(2, prim(0, arg(1), arg(2))) },
		{ name = "a partial application", value = { kind = "app", law = law(3, arg(3)), args = { 1, cell(2, 3) } } },
		{ name = "a pin of a list", value = { kind = "pin", value = list(1, 2, 3) } },
	}

	for _, v in values do
		local ok, out = pcall(function()
			return Format.decodeValue(Format.encodeValue(v.value))
		end)

		check(`round trip: {v.name}`, ok and same(out, v.value), if ok then "same" else tostring(out))
	end
end

-- 3. Programs: the spec's examples, a deep one, and the bytes of inc.
do
	const inc = law(1, prim(0, arg(1), lit(1)))
	const incBytes = Format.encodeProgram(inc)
	check("the program inc is written as the spec says", incBytes == "\2\1\26\0\17\1\16\2\1", hex(incBytes))

	const length = law(1, {
		op = "if",
		c = prim(6, prim(7, arg(1)), lit(1)),
		t = lit(0),
		e = prim(0, lit(1), call(arg(0), prim(9, arg(1)))),
	})

	const safediv = law(1, {
		op = "if",
		c = prim(6, prim(9, arg(1)), lit(0)),
		t = { op = "con", tag = 1, e = lit(Format.NIL) },
		e = { op = "con", tag = 0, e = prim(3, prim(8, arg(1)), prim(9, arg(1))) },
	})

	const unwrap = law(1, {
		op = "case",
		e = arg(1),
		alts = { { tag = 0, body = arg(2) }, { tag = 1, body = lit(0) } },
		elseBody = lit(0),
	})

	const laziness = law(1, {
		op = "let",
		e = { op = "delay", call = { op = "call", f = lit(inc), args = { lit(1) } } },
		body = prim(0, { op = "force", e = arg(2) }, { op = "force", e = arg(2) }),
	})

	const loop = law(1, call(arg(0), arg(1)))

	const programs: { { name: string, p: any } } = {
		{ name = "inc", p = inc },
		{ name = "length", p = length },
		{ name = "safediv", p = safediv },
		{ name = "unwrap", p = unwrap },
		{ name = "laziness", p = laziness },
		{ name = "loop", p = loop },
		{ name = "tagof and payload", p = law(1, prim(13, prim(12, arg(1)))) },
	}

	for _, pr in programs do
		local ok, out = pcall(function()
			return Format.decodeProgram(Format.encodeProgram(pr.p))
		end)

		check(`round trip program: {pr.name}`, ok and same(out, pr.p), if ok then "same" else tostring(out))
	end

	-- A program nested 20,000 deep: a chain of lets, each binding a literal.
	local deep: any = arg(1)

	for i = 1, 20000 do
		deep = { op = "let", e = lit(i), body = deep }
	end

	const deepLaw = law(1, deep)
	local ok, out = pcall(function()
		return Format.decodeProgram(Format.encodeProgram(deepLaw))
	end)

	check("round trip: a program 20,000 forms deep", ok and same(out, deepLaw), if ok then "same" else tostring(out))
end

-- 4. The bytes that are refused, each with its reason.
do
	const refused: { { name: string, bytes: string, want: string, decodeAs: string } } = {
		{ name = "an empty string", bytes = "", want = "not a value", decodeAs = "value" },
		{ name = "a program read as a value", bytes = "\2\1\26\0\17\1\16\2\1", want = "not a value", decodeAs = "value" },
		{ name = "a value read as a program", bytes = "\1\2\0", want = "not a program", decodeAs = "program" },
		{ name = "an unknown value tag", bytes = "\1\9", want = "tag 9 is not a value", decodeAs = "value" },
		{ name = "negative zero", bytes = "\1\3\0", want = "negative zero", decodeAs = "value" },
		{ name = "a magnitude with a zero last group", bytes = "\1\2\128\0", want = "shortest form", decodeAs = "value" },
		{ name = "a magnitude cut short", bytes = "\1\2\128", want = "end", decodeAs = "value" },
		{ name = "bytes after a value", bytes = "\1\2\1\2", want = "after", decodeAs = "value" },
		{ name = "a law whose body is not a form", bytes = "\1\5\1\0", want = "tag 0 is not a form", decodeAs = "value" },
		{ name = "a program of arity 2", bytes = "\2\2\16\0", want = "arity 1", decodeAs = "program" },
		{ name = "an unknown form tag", bytes = "\2\1\27", want = "tag 27 is not a form", decodeAs = "program" },
		{ name = "a primitive of tag 14", bytes = "\2\1\26\14\16\0\16\0", want = "does not exist", decodeAs = "program" },
		{ name = "a case with the tag 0 twice", bytes = "\2\1\21\17\1\2\0\16\2\0\0\16\2\0\0", want = "twice", decodeAs = "program" },
		{ name = "a partial application with no fewer arguments than its arity", bytes = "\1\6\5\1\16\0\1\0", want = "fewer arguments", decodeAs = "value" },
		{ name = "a program with bytes after it", bytes = "\2\1\16\0\0", want = "after", decodeAs = "program" },
		{ name = "an index past 2^53 - 1 (a position, not an integer value)", bytes = "\2\1\17\128\128\128\128\128\128\128\16", want = "past 2^53 - 1", decodeAs = "program" },
	}

	for _, c in refused do
		local ok, err = pcall(function()
			if c.decodeAs == "value" then
				return Format.decodeValue(c.bytes)
			end

			return Format.decodeProgram(c.bytes)
		end)

		check(`refused: {c.name}`, not ok and string.find(tostring(err), c.want, 1, true) ~= nil, tostring(err))
	end
end

-- 5. The writer refuses what has no binary form.
do
	local ok, err = pcall(Format.encodeValue, { kind = "thunk" })
	check("a thunk has no binary form", not ok and string.find(tostring(err), "thunk", 1, true) ~= nil, tostring(err))

	ok, err = pcall(Format.encodeValue, { kind = "pin", value = { kind = "thunk" } })
	check("a pin of a thunk has no binary form", not ok and string.find(tostring(err), "pin of a thunk", 1, true) ~= nil, tostring(err))

	ok, err = pcall(Format.encodeProgram, law(2, lit(0)))
	check("a program must be a law of arity 1", not ok and string.find(tostring(err), "arity 1", 1, true) ~= nil, tostring(err))

	ok, err = pcall(Format.encodeProgram, law(1, prim(0, lit(1))))
	check("a prim with the wrong number of arguments is refused", not ok and string.find(tostring(err), "takes 2 arguments", 1, true) ~= nil, tostring(err))
end

print(`{total - failures} of {total} checks pass`)

if failures > 0 then
	print(`{failures} failures`)
end
