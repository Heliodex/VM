--!strict
-- CHECKS THE PHASE 3 REFERENCE INTERPRETER (SPEC.md)
--
-- Checks reference/interp.luau: the examples of the spec (section 9), with the step count of inc worked out by hand; the primitives, with signed and big integers checked against identities on pseudo-random values; the errors, each by its message; deep programs, which must not overflow the host's stack; and the thunk memo.
--
--   lute run interp_run.luau     (from Prototypes/7/reference)

const Format = require "./format"
const Int = require "./int"
const Interp = require "./interp"
const Types = require "./types"

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

const NIL = Format.NIL
type Outcome = Types.Outcome

-- The value of an outcome, or nil when it is not a value. The checks compare it, so a failed run gives a value that matches nothing.
const function valueOf(o: Outcome): Types.Value
	if o.status == "value" then
		return o.value
	end

	return NIL
end

-- The message of an outcome, or the empty string when it is not an error.
const function messageOf(o: Outcome): string
	if o.status == "error" then
		return o.message
	end

	return ""
end

const function lit(v: Types.Value): Types.Form
	return { op = "lit"; value = v }
end

const function arg(i: number): Types.Form
	return { op = "arg"; index = i }
end

const function call(f: Types.Form, ...: Types.Form): Types.Form
	return { op = "call"; f = f; args = { ... } }
end

const function prim(tag: number, ...: Types.Form): Types.Form
	return { op = "prim"; tag = tag; args = { ... } }
end

const function law(arity: number, body: Types.Form): Types.Law
	return { kind = "law"; arity = arity; body = body }
end

const function cell(a: Types.Value, b: Types.Value): Types.Cell
	return { kind = "cell"; head = a; tail = b }
end

const function list(...: Types.Value): Types.Value
	local items = { ... }
	local v: Types.Value = NIL

	for i = #items, 1, -1 do
		v = cell(items[i], v)
	end

	return v
end

const function con(tag: number, payload: Types.Value): Types.Con
	return { kind = "con"; tag = tag; payload = payload }
end

const function show(v: Types.Value): string
	if type(v) == "number" or Int.isBig(v) then
		return Int.isBig(v) and "a big integer" or tostring(v)
	end

	if v == NIL then
		return "nil"
	end

	return tostring(v.kind)
end

-- Whether two outcomes' values agree: integers by value, nil, cells and constructors deeply.
const function sameValue(a: Types.Value, b: Types.Value): boolean
	const function isI(x: Types.Value): boolean
		return type(x) == "number" or Int.isBig(x)
	end

	if isI(a) or isI(b) then
		return isI(a) and isI(b) and Int.compare(a :: Int.Int, b :: Int.Int) == 0
	end

	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	if a.kind ~= b.kind then
		return false
	end

	if a.kind == "cell" then
		if b.kind ~= "cell" then
			return false
		end

		return sameValue(a.head, b.head) and sameValue(a.tail, b.tail)
	elseif a.kind == "con" then
		if b.kind ~= "con" then
			return false
		end

		return a.tag == b.tag and sameValue(a.payload, b.payload)
	end

	return a == b or a.kind == "nil"
end

-- 1. The examples of the spec, section 9.
do
	const inc = law(1, prim(0, arg(1), lit(1)))
	local o = Interp.runForm(call(lit(inc), lit(41)), NIL, 1000)
	check("the step count of call (lit inc) (lit 41) is 7, as worked out by hand", o.status == "value" and valueOf(o) == 42 and o.steps == 7, `{o.status} {tostring(valueOf(o))} in {o.steps} steps`)
	const length = law(
		1,
		{
			op = "if",
			c = prim(6, prim(7, arg(1)), lit(1)),
			t = lit(0),
			e = prim(0, lit(1), call(arg(0), prim(9, arg(1)))),
		}
	)
	o = Interp.run(length, list(1, 2, 3), 10000)
	check("length of (1 2 3) is 3", o.status == "value" and valueOf(o) == 3, `{o.status} {tostring(valueOf(o))} in {o.steps} steps`)
	local o2 = Interp.run(length, NIL, 10000)
	check("length of nil is 0", o2.status == "value" and valueOf(o2) == 0, `{o2.status} {tostring(valueOf(o2))} in {o2.steps} steps`)
	const safediv = law(
		1,
		{
			op = "if",
			c = prim(6, prim(9, arg(1)), lit(0)),
			t = { op = "con"; tag = 1; e = lit(NIL) },
			e = { op = "con"; tag = 0; e = prim(3, prim(8, arg(1)), prim(9, arg(1))) },
		}
	)
	o = Interp.run(safediv, cell(6, 3), 1000)
	check("safediv (6 . 3) is Ok 2", o.status == "value" and sameValue(valueOf(o), con(0, 2)), `{o.status} {show(valueOf(o))}`)
	o = Interp.run(safediv, cell(6, 0), 1000)
	check("safediv (6 . 0) is Err nil", o.status == "value" and sameValue(valueOf(o), con(1, NIL)), `{o.status} {show(valueOf(o))}`)
	const unwrap = law(
		1,
		{
			op = "case",
			e = arg(1),
			alts = { { tag = 0; body = arg(2) }; { tag = 1; body = lit(0) } },
			elseBody = lit(0),
		}
	)
	o = Interp.run(unwrap, con(0, 9), 1000)
	check("unwrap (Ok 9) is 9", o.status == "value" and valueOf(o) == 9, `{o.status} {tostring(valueOf(o))}`)
	const laziness = law(
		1,
		{
			op = "let",
			e = { op = "delay"; call = { op = "call"; f = lit(inc); args = { lit(1) } } },
			body = prim(0, { op = "force"; e = arg(2) }, { op = "force"; e = arg(2) }),
		}
	)
	o = Interp.run(laziness, NIL, 1000)
	check("laziness: a thunk forced twice is 4, and its call runs once", o.status == "value" and valueOf(o) == 4, `{o.status} {tostring(valueOf(o))} in {o.steps} steps`)
	-- The second force costs its own form and nothing else: compare with the same program forcing once.
	const onceForce = law(
		1,
		{
			op = "let",
			e = { op = "delay"; call = { op = "call"; f = lit(inc); args = { lit(1) } } },
			body = { op = "force"; e = arg(2) },
		}
	)
	local oOnce = Interp.run(onceForce, NIL, 1000)
	check("the second force costs its form and its argument (2 steps), and the add 1: no law entry", o.steps - oOnce.steps == 3, `two forces {o.steps} steps, one force {oOnce.steps} steps`)
	const loop = law(1, call(arg(0), arg(1)))
	o = Interp.run(loop, NIL, 500)
	check("loop runs out of fuel", o.status == "out_of_fuel" and o.steps <= 500, `{o.status} after {o.steps} steps`)
	o = Interp.runForm(prim(3, lit(1), lit(0)), NIL, 100)
	check("division by zero is an error", o.status == "error" and messageOf(o) == "division by zero", `{o.status} {tostring(messageOf(o))}`)
	const tagPayload = law(1, prim(13, prim(12, arg(1))))
	o = Interp.run(tagPayload, con(5, 7), 100)
	check("payload of a tag (a number, not a constructor) is an error", o.status == "error", `{o.status} {tostring(messageOf(o))}`)
	const tagOnly = law(1, prim(12, arg(1)))
	o = Interp.run(tagOnly, con(5, 7), 100)
	check("tagof a constructor is its tag", o.status == "value" and valueOf(o) == 5, `{o.status} {tostring(valueOf(o))}`)
	o = Interp.run(tagOnly, 3, 100)
	check("tagof any other value is -1", o.status == "value" and valueOf(o) == -1, `{o.status} {tostring(valueOf(o))}`)
end

-- 2. Integers of any size.
do
	local two53 = Int.fromMagnitude(false, { 0; 0; 0; 0; 0; 0; 32 })
	local two100 = Int.fromMagnitude(false, { 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 16 })
	local o = Interp.runForm(prim(0, lit(two100), lit(1)), NIL, 100)
	local back = Interp.runForm(prim(1, lit(valueOf(o)), lit(two100)), NIL, 100)
	check("2^100 + 1 is big, and minus 2^100 gives 1", o.status == "value" and Int.isBig(valueOf(o)) and valueOf(back) == 1, `{o.status} {tostring(valueOf(back))}`)
	o = Interp.runForm(prim(2, lit(two53), lit(two53)), NIL, 100)
	check("2^53 times 2^53 is 2^106 (big)", o.status == "value" and Int.isBig(valueOf(o)), `{o.status}`)
	o = Interp.runForm(prim(3, lit(two100), lit(two53)), NIL, 100)
	check("2^100 div 2^53 is 2^47", o.status == "value" and Int.equal(valueOf(o) :: Int.Int, Int.fromMagnitude(false, { 0; 0; 0; 0; 0; 128 })), `{o.status} {tostring(valueOf(o))}`)
	-- Floored division and modulus, with the sign of the divisor, on all sign combinations.
	const cases: { { a: number; b: number; q: number; r: number } } = {
		{ a = 7; b = 2; q = 3; r = 1 },
		{ a = -7; b = 2; q = -4; r = 1 },
		{ a = 7; b = -2; q = -4; r = -1 },
		{ a = -7; b = -2; q = 3; r = -1 },
		{ a = 6; b = 3; q = 2; r = 0 },
		{ a = 0; b = 5; q = 0; r = 0 },
	}

	for _, c in cases do
		const q, r = Int.divMod(c.a, c.b)
		check(`floored division {c.a} by {c.b}`, q == c.q and r == c.r, `{tostring(q)} remainder {tostring(r)}`)
	end

	-- Identities on pseudo-random big integers: a = b * q + r, the remainder has the sign of b and is smaller than b, and add and sub are inverse, and mul is commutative.
	local seed = 12345

	const function nextByte(): number
		seed = (seed * 1103515245 + 12345) % 0x80000000

		return seed % 256
	end

	const function randomInt(): Int.Int
		local len = 1 + nextByte() % 20
		local bytes: { number } = {}

		for i = 1, len do
			bytes[i] = nextByte()
		end

		return Int.fromMagnitude(nextByte() % 2 == 1, bytes)
	end

	local identityFailures = 0
	local rangeFailures = 0
	local addFailures = 0
	local mulFailures = 0

	for _ = 1, 300 do
		const a = randomInt()
		local b = randomInt()

		if Int.sign(b) == 0 then
			b = 1
		end

		const q, r = Int.divMod(a, b)

		if Int.compare(Int.add(Int.mul(b, q), r), a) ~= 0 then
			identityFailures += 1
		end

		if Int.sign(r) ~= 0 and Int.sign(r) ~= Int.sign(b) then
			rangeFailures += 1
		end

		if Int.compare(Int.mul(Int.sub(a, b), 1), Int.sub(a, b)) ~= 0 or Int.compare(Int.sub(Int.add(a, b), b), a) ~= 0 then
			addFailures += 1
		end

		if Int.compare(Int.mul(a, b), Int.mul(b, a)) ~= 0 then
			mulFailures += 1
		end
	end

	check("a = b * q + r for 300 pseudo-random pairs of big integers", identityFailures == 0, `{identityFailures} failures`)
	check("the remainder has the sign of the divisor, for 300 pairs", rangeFailures == 0, `{rangeFailures} failures`)
	check("add and sub are inverse, for 300 pairs", addFailures == 0, `{addFailures} failures`)
	check("mul is commutative, for 300 pairs", mulFailures == 0, `{mulFailures} failures`)
	-- A number and a big integer with the same value are the same integer: the normal form.
	const boundary = Int.fromMagnitude(false, { 255; 255; 255; 255; 255; 255; 31 })
	check("2^53 - 1 is a number, the largest one", type(boundary) == "number" and boundary == Int.MAX_SAFE, tostring(boundary))
end

-- 3. Pins are interned, and a pin of a thunk is an error.
do
	const pinOne = Interp.runForm(prim(10, lit(list(1, 2))), NIL, 100)
	const pinTwo = Interp.runForm(prim(10, lit(list(1, 2))), NIL, 100)
	check("equal pins are the same object", pinOne.status == "value" and valueOf(pinOne) == valueOf(pinTwo), `{pinOne.status}`)
	const unpinned = Interp.runForm(prim(11, lit(valueOf(pinOne))), NIL, 100)
	check("unpin gives back the value", unpinned.status == "value" and sameValue(valueOf(unpinned), list(1, 2)), `{unpinned.status}`)
	const thunk = Interp.runForm({ op = "delay"; call = { op = "call"; f = lit(law(1, arg(1))); args = { lit(1) } } }, NIL, 100)
	const bad = Interp.runForm(prim(10, { op = "lit"; value = valueOf(thunk) }), NIL, 100)
	check("a pin of a thunk is an error", bad.status == "error", `{bad.status} {tostring(messageOf(bad))}`)
end

-- 4. Errors, each with its message.
do
	local o = Interp.runForm(prim(8, lit(3)), NIL, 100)
	check("head of a value that is not a cell is an error", o.status == "error" and string.find(tostring(messageOf(o)), "not a cell") ~= nil, `{o.status} {tostring(messageOf(o))}`)
	o = Interp.runForm({ op = "case"; e = lit(con(2, 1)); alts = { { tag = 0; body = lit(0) } } }, NIL, 100)
	check("a case with no branch for the tag is an error", o.status == "error" and string.find(tostring(messageOf(o)), "no branch") ~= nil, `{o.status} {tostring(messageOf(o))}`)
	o = Interp.runForm(call(lit(3), lit(1)), NIL, 100)
	check("calling a value that is not a function is an error", o.status == "error", `{o.status} {tostring(messageOf(o))}`)
	o = Interp.runForm({ op = "force"; e = lit(3) }, NIL, 100)
	check("forcing a value that is not a thunk is an error", o.status == "error", `{o.status} {tostring(messageOf(o))}`)
	o = Interp.runForm({ op = "if"; c = lit(list(1)); t = lit(1); e = lit(2) }, NIL, 100)
	check("an if on a value that is not an integer is an error", o.status == "error", `{o.status} {tostring(messageOf(o))}`)
	o = Interp.runForm({ op = "arg"; index = 5 }, NIL, 100)
	check("an argument past the frame is an error", o.status == "error", `{o.status} {tostring(messageOf(o))}`)
end

-- 5. Deep programs: the explicit stack, not the host's, holds the depth.
do
	local deep: Types.Form = arg(1)

	for i = 1, 20000 do
		const outer: Types.Form = { op = "let"; e = lit(i); body = deep }
		deep = outer
	end

	local o = Interp.runForm(deep, 77, 1e7)
	check("a let chain 20,000 deep returns its input", o.status == "value" and valueOf(o) == 77, `{o.status} in {o.steps} steps`)
	-- length of a list of 5000, by self-reference, which recurses 5000 deep in the machine's own stack.
	const length = law(
		1,
		{
			op = "if",
			c = prim(6, prim(7, arg(1)), lit(1)),
			t = lit(0),
			e = prim(0, lit(1), call(arg(0), prim(9, arg(1)))),
		}
	)
	local items: { Types.Value } = {}

	for i = 1, 5000 do
		items[i] = i
	end

	o = Interp.run(length, list(table.unpack(items)), 1e8)
	check("length of 5000 elements is 5000, by self-reference", o.status == "value" and valueOf(o) == 5000, `{o.status} {tostring(valueOf(o))} in {o.steps} steps`)
end

-- 6. A program's steps are the same whether it is run as a program or as a form in the same frame.
do
	local program = law(1, prim(0, arg(1), lit(1)))
	local asProgram = Interp.run(program, 41, 100)
	local asForm = Interp.runForm(prim(0, arg(1), lit(1)), 41, 100)
	check("a program and its body give the same value", valueOf(asProgram) == 42 and valueOf(asForm) == 42, `{valueOf(asProgram)} and {valueOf(asForm)}`)
	check("a program costs one more step than its body, for its law entry", asProgram.steps == asForm.steps + 1, `{asProgram.steps} against {asForm.steps}`)
end

print(string.format("%d of %d checks pass", total - failures, total))

if failures > 0 then
	print(string.format("%d failures", failures))
end
