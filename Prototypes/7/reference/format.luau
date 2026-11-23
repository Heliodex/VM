--!strict
-- THE BINARY FORMAT OF PROTOTYPE 7 (SPEC.md section 12)
--
-- Stores values and programs as bytes, for machines. The reader is strict: it refuses anything the spec does not allow, and says why. The writer refuses a value that has no binary form.
--
-- Values, in the reference's representation:
--   an integer:  a number or a big integer (int.luau)
--   nil:         the one nil, NIL
--   a cell:      { kind = "cell", head, tail }
--   a con:       { kind = "con", tag, payload }      tag is a number from 0 up
--   a law:       { kind = "law", arity, body }       body is a form
--   a partial application: { kind = "app", law, args }
--   a pin:       { kind = "pin", value }
-- A thunk has no binary form.
--
-- Forms, in the reference's representation (one table each):
--   { op = "lit", value }   { op = "arg", index }   { op = "call", f, args }
--   { op = "cell", a, b }   { op = "con", tag, e }  { op = "case", e, alts = { { tag, body } }, elseBody }
--   { op = "if", c, t, e }  { op = "let", e, body } { op = "delay", call = { op = "call", f, args } }
--   { op = "force", e }     { op = "prim", tag, args }
--
-- Positions (tags, indices, counts, arities) are numbers. The reader refuses one above Int.MAX_SAFE, which is a limit of this host's numbers on positions, not of integers (SPEC.md section 12.2).
--
-- Neither the writer nor the reader recurses. Each keeps its own stack of pending work, as the machine does, so the depth of a program is not limited by the host's call stack. The tests check a program 20,000 forms deep.

const Int = require "./int"

export type Value = any
export type Form = any

const NIL = { kind = "nil" }

-- The argument count of each primitive, by tag (SPEC.md section 4).
const PRIM_ARITY = { 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1 }

local VALUE_HEADER = 1
local PROGRAM_HEADER = 2

-- The tags of values and forms (SPEC.md section 12.3 and 12.4).
const V_NIL = 0
const V_CELL = 1
const V_POS = 2
const V_NEG = 3
const V_CON = 4
const V_LAW = 5
const V_APP = 6
const V_PIN = 7

const F_LIT = 0x10
const F_ARG = 0x11
const F_CALL = 0x12
const F_CELL = 0x13
const F_CON = 0x14
const F_CASE = 0x15
const F_IF = 0x16
const F_LET = 0x17
const F_DELAY = 0x18
const F_FORCE = 0x19
const F_PRIM = 0x1a

-- Writing

-- The bytes of a magnitude, as LEB128 from a list of 7-bit groups, least significant first.
local function groupsBytes(groups: { number }): string
	local out: { string } = {}

	for i, g in groups do
		local b = g

		if i < #groups then
			b += 128
		end

		table.insert(out, string.char(b))
	end

	return table.concat(out)
end

-- A position, as its bytes.
local function posBytes(n: number): string
	if n < 0 or n ~= math.floor(n) then
		error("binary: a position must be a whole number from 0 up", 0)
	end

	return groupsBytes(Int.lebGroups(Int.magnitudeBytes(n)))
end

-- An integer: its sign tag, then its magnitude.
local function intBytes(v: Int.Int): string
	const tag = if Int.sign(v) < 0 then V_NEG else V_POS

	return string.char(tag) .. groupsBytes(Int.lebGroups(Int.magnitudeBytes(v)))
end

-- The pieces a value is written as, in order. A piece is a string of bytes, or a value or form still to be written. The writer pushes the pieces on its stack in reverse, so the first piece is written first.
type Piece = string | { value: Value } | { form: Form }

local function valuePieces(v: Value): { Piece }
	if type(v) == "number" or Int.isBig(v) then
		return { intBytes(v) }
	end

	if v.kind == "nil" then
		return { string.char(V_NIL) }
	elseif v.kind == "cell" then
		return { string.char(V_CELL), { value = v.head }, { value = v.tail } }
	elseif v.kind == "con" then
		return { string.char(V_CON), posBytes(v.tag), { value = v.payload } }
	elseif v.kind == "law" then
		return { string.char(V_LAW), posBytes(v.arity), { form = v.body } }
	elseif v.kind == "app" then
		local pieces: { Piece } = { string.char(V_APP), { value = v.law }, posBytes(#v.args) }

		for _, a in v.args do
			table.insert(pieces, { value = a })
		end

		return pieces
	elseif v.kind == "pin" then
		if type(v.value) == "table" and v.value.kind == "thunk" then
			error("binary: a pin of a thunk has no binary form", 0)
		end

		return { string.char(V_PIN), { value = v.value } }
	elseif v.kind == "thunk" then
		error("binary: a thunk has no binary form", 0)
	end

	error(`binary: a value of kind {tostring(v.kind)} has no binary form`, 0)
end

local function formPieces(f: Form): { Piece }
	const op = f.op

	if op == "lit" then
		return { string.char(F_LIT), { value = f.value } }
	elseif op == "arg" then
		return { string.char(F_ARG), posBytes(f.index) }
	elseif op == "call" then
		local pieces: { Piece } = { string.char(F_CALL), posBytes(#f.args), { form = f.f } }

		for _, a in f.args do
			table.insert(pieces, { form = a })
		end

		return pieces
	elseif op == "cell" then
		return { string.char(F_CELL), { form = f.a }, { form = f.b } }
	elseif op == "con" then
		return { string.char(F_CON), posBytes(f.tag), { form = f.e } }
	elseif op == "case" then
		local pieces: { Piece } = { string.char(F_CASE), { form = f.e }, posBytes(#f.alts) }

		for _, alt in f.alts do
			table.insert(pieces, posBytes(alt.tag))
			table.insert(pieces, { form = alt.body })
		end

		if f.elseBody == nil then
			table.insert(pieces, string.char(0))
		else
			table.insert(pieces, string.char(1))
			table.insert(pieces, { form = f.elseBody })
		end

		return pieces
	elseif op == "if" then
		return { string.char(F_IF), { form = f.c }, { form = f.t }, { form = f.e } }
	elseif op == "let" then
		return { string.char(F_LET), { form = f.e }, { form = f.body } }
	elseif op == "delay" then
		local pieces: { Piece } = { string.char(F_DELAY), posBytes(#f.call.args), { form = f.call.f } }

		for _, a in f.call.args do
			table.insert(pieces, { form = a })
		end

		return pieces
	elseif op == "force" then
		return { string.char(F_FORCE), { form = f.e } }
	elseif op == "prim" then
		local arity = PRIM_ARITY[f.tag + 1]

		if arity == nil then
			error(`binary: primitive {tostring(f.tag)} does not exist`, 0)
		end

		if #f.args ~= arity then
			error(`binary: primitive {tostring(f.tag)} takes {arity} arguments, but is given {#f.args}`, 0)
		end

		local pieces: { Piece } = { string.char(F_PRIM), posBytes(f.tag) }

		for _, a in f.args do
			table.insert(pieces, { form = a })
		end

		return pieces
	end

	error(`binary: a form {tostring(op)} has no binary form`, 0)
end

-- Writes a root piece, and everything under it, with an explicit stack.
local function writeAll(root: Piece): string
	local out: { string } = {}
	local stack: { Piece } = { root }

	while #stack > 0 do
		const piece = table.remove(stack) :: Piece

		if type(piece) == "string" then
			table.insert(out, piece)
		else
			local pieces: { Piece }

			if (piece :: any).form ~= nil then
				pieces = formPieces((piece :: any).form)
			else
				pieces = valuePieces((piece :: any).value)
			end

			for i = #pieces, 1, -1 do
				table.insert(stack, pieces[i])
			end
		end
	end

	return table.concat(out)
end

-- Reading

type Reader = { s: string, p: number }

local function readByte(r: Reader, what: string): number
	if r.p > #r.s then
		error(`binary: the bytes end before {what} is complete`, 0)
	end

	const b = string.byte(r.s, r.p)
	r.p += 1

	return b
end

-- The 7-bit groups of one LEB128 magnitude, least significant first. The reader refuses a magnitude that is not in its shortest form: a last group of zero after more than one group.
local function readGroups(r: Reader, what: string): { number }
	local groups: { number } = {}

	while true do
		const b = readByte(r, what)
		table.insert(groups, b % 128)

		if b < 128 then
			if b == 0 and #groups > 1 then
				error("binary: a number is not in its shortest form", 0)
			end

			return groups
		end
	end
end

-- A position: a magnitude that must be at most Int.MAX_SAFE.
local function readPos(r: Reader, what: string): number
	const groups = readGroups(r, what)
	const v = Int.fromMagnitude(false, Int.bytesFromGroups(groups))

	if type(v) ~= "number" then
		error(`binary: {what} is past 2^53 - 1, the largest position`, 0)
	end

	return v
end

-- An integer, after its sign tag. Negative zero is refused.
local function readInt(r: Reader, neg: boolean): Int.Int
	const groups = readGroups(r, "an integer")
	const v = Int.fromMagnitude(neg, Int.bytesFromGroups(groups))

	if neg and Int.sign(v) == 0 then
		error("binary: negative zero is not a value", 0)
	end

	return v
end

-- A reading frame: a node with some parts still to read. init is what it asks for first ("pos", "flag", "form" or "value"); feed takes what it was given, and returns what it asks for next, or the finished node as { done = node }.
type Ask = { req: string } | { done: any }
type Frame = { init: string, feed: (datum: any, dtype: string) -> Ask }

local readNode: (r: Reader, want: string) -> any

-- A frame that reads a fixed list of parts, each a form or a value, then builds the node from them.
local function fixedFrame(init: string, count: number, build: (parts: { any }) -> any): Frame
	local parts: { any } = {}

	return {
		init = init,
		feed = function(datum: any, _dtype: string): Ask
			table.insert(parts, datum)

			if #parts == count then
				return { done = build(parts) }
			end

			return { req = init }
		end,
	}
end

-- Opens the frame of a node with the tag t, read as a form or a value. A node with no parts is returned as it is, with no frame.
local function open(want: string, t: number, r: Reader): (any?, Frame?)
	if want == "value" then
		if t == V_NIL then
			return NIL, nil
		elseif t == V_POS then
			return readInt(r, false), nil
		elseif t == V_NEG then
			return readInt(r, true), nil
		elseif t == V_CELL then
			return nil, fixedFrame("value", 2, function(p: { any }): any
				return { kind = "cell", head = p[1], tail = p[2] }
			end)
		elseif t == V_CON then
			local tag: number? = nil

			return nil, {
				init = "pos",
				feed = function(datum: any, dtype: string): Ask
					if dtype == "pos" then
						tag = datum

						return { req = "value" }
					end

					return { done = { kind = "con", tag = tag, payload = datum } }
				end,
			}
		elseif t == V_LAW then
			local arity: number? = nil

			return nil, {
				init = "pos",
				feed = function(datum: any, dtype: string): Ask
					if dtype == "pos" then
						if datum < 1 then
							error("binary: an arity is at least 1", 0)
						end

						arity = datum

						return { req = "form" }
					end

					return { done = { kind = "law", arity = arity, body = datum } }
				end,
			}
		elseif t == V_APP then
			local law: any = nil
			local n: number? = nil
			local args: { any } = {}

			return nil, {
				init = "value",
				feed = function(datum: any, dtype: string): Ask
					if dtype == "node" and law == nil then
						if type(datum) ~= "table" or datum.kind ~= "law" then
							error("binary: a partial application needs a law", 0)
						end

						law = datum

						return { req = "pos" }
					end

					if dtype == "pos" and n == nil then
						if datum < 1 or datum >= law.arity then
							error("binary: a partial application has fewer arguments than its law's arity, and at least one", 0)
						end

						n = datum

						return { req = "value" }
					end

					table.insert(args, datum)

					if #args == n then
						return { done = { kind = "app", law = law, args = args } }
					end

					return { req = "value" }
				end,
			}
		elseif t == V_PIN then
			return nil, fixedFrame("value", 1, function(p: { any }): any
				if type(p[1]) == "table" and p[1].kind == "thunk" then
					error("binary: a pin of a thunk has no binary form", 0)
				end

				return { kind = "pin", value = p[1] }
			end)
		end

		error(`binary: tag {t} is not a value`, 0)
	end

	-- A form.
	if t == F_LIT then
		return nil, fixedFrame("value", 1, function(p: { any }): any
			return { op = "lit", value = p[1] }
		end)
	elseif t == F_ARG then
		return nil, {
			init = "pos",
			feed = function(datum: any): Ask
				return { done = { op = "arg", index = datum } }
			end,
		}
	elseif t == F_CALL or t == F_DELAY then
		-- A call, and the call of a delay, are the same parts: a count, the function, then the arguments.
		local n: number? = nil
		local f: any = nil
		local args: { any } = {}

		local function finish(): any
			if t == F_DELAY then
				return { op = "delay", call = { op = "call", f = f, args = args } }
			end

			return { op = "call", f = f, args = args }
		end

		return nil, {
			init = "pos",
			feed = function(datum: any, dtype: string): Ask
				if dtype == "pos" then
					n = datum

					return { req = "form" }
				end

				if f == nil then
					f = datum

					if n == 0 then
						return { done = finish() }
					end

					return { req = "form" }
				end

				table.insert(args, datum)

				if #args == n then
					return { done = finish() }
				end

				return { req = "form" }
			end,
		}
	elseif t == F_CELL then
		return nil, fixedFrame("form", 2, function(p: { any }): any
			return { op = "cell", a = p[1], b = p[2] }
		end)
	elseif t == F_CON then
		local tag: number? = nil

		return nil, {
			init = "pos",
			feed = function(datum: any, dtype: string): Ask
				if dtype == "pos" then
					tag = datum

					return { req = "form" }
				end

				return { done = { op = "con", tag = tag, e = datum } }
			end,
		}
	elseif t == F_CASE then
		local e: any = nil
		local k: number? = nil
		local alts: { { tag: number, body: any } } = {}
		local seen: { [number]: boolean } = {}
		local tag: number? = nil
		local st = 0

		return nil, {
			init = "form",
			feed = function(datum: any, dtype: string): Ask
				if st == 0 then
					e = datum
					st = 1

					return { req = "pos" }
				elseif st == 1 then
					k = datum
					st = 2

					if k == 0 then
						st = 4

						return { req = "flag" }
					end

					return { req = "pos" }
				elseif st == 2 then
					tag = datum

					if seen[tag :: number] then
						error(`binary: the case has tag {tag} twice`, 0)
					end

					seen[tag :: number] = true
					st = 3

					return { req = "form" }
				elseif st == 3 then
					table.insert(alts, { tag = tag :: number, body = datum })

					if #alts < (k :: number) then
						st = 2

						return { req = "pos" }
					end

					st = 4

					return { req = "flag" }
				elseif st == 4 then
					if datum == 1 then
						st = 5

						return { req = "form" }
					elseif datum ~= 0 then
						error("binary: the else flag is 0 or 1", 0)
					end

					return { done = { op = "case", e = e, alts = alts, elseBody = nil } }
				end

				return { done = { op = "case", e = e, alts = alts, elseBody = datum } }
			end,
		}
	elseif t == F_IF then
		return nil, fixedFrame("form", 3, function(p: { any }): any
			return { op = "if", c = p[1], t = p[2], e = p[3] }
		end)
	elseif t == F_LET then
		return nil, fixedFrame("form", 2, function(p: { any }): any
			return { op = "let", e = p[1], body = p[2] }
		end)
	elseif t == F_FORCE then
		return nil, fixedFrame("form", 1, function(p: { any }): any
			return { op = "force", e = p[1] }
		end)
	elseif t == F_PRIM then
		local args: { any } = {}
		local tag: number? = nil
		local arity: number? = nil

		return nil, {
			init = "pos",
			feed = function(datum: any, dtype: string): Ask
				if dtype == "pos" then
					tag = datum
					arity = PRIM_ARITY[datum + 1]

					if arity == nil then
						error(`binary: primitive {datum} does not exist`, 0)
					end

					return { req = "form" }
				end

				table.insert(args, datum)

				if #args == arity then
					return { done = { op = "prim", tag = tag, args = args } }
				end

				return { req = "form" }
			end,
		}
	end

	error(`binary: tag {t} is not a form`, 0)
end

-- Reads one node of the kind want ("form" or "value") from r, with an explicit stack of the frames still open.
readNode = function(r: Reader, want: string): any
	local stack: { Frame } = {}
	local req = want

	while true do
		local datum: any = nil
		local dtype = "node"

		if req == "pos" then
			datum = readPos(r, "a position")
			dtype = "pos"
		elseif req == "flag" then
			datum = readByte(r, "the else flag")
			dtype = "flag"
		else
			const t = readByte(r, if req == "form" then "a form" else "a value")
			local leaf, frame = open(req, t, r)

			if frame ~= nil then
				table.insert(stack, frame)
				req = frame.init

				continue
			end

			datum = leaf
		end

		-- Hand the datum up. A frame that completes gives a node, which goes up in turn.
		while true do
			if #stack == 0 then
				return datum
			end

			const top = stack[#stack]
			const ask = top.feed(datum, dtype)

			if (ask :: any).done ~= nil then
				table.remove(stack)
				datum = (ask :: any).done
				dtype = "node"
			else
				req = (ask :: any).req
				break
			end
		end
	end
end

-- The header, and the rest of the bytes, checked.
local function start(s: string, header: number, what: string): Reader
	if #s < 1 or string.byte(s, 1) ~= header then
		error(`binary: the bytes are not {what}`, 0)
	end

	return { s = s, p = 2 }
end

local function finishRead(r: Reader, what: string)
	if r.p <= #r.s then
		error(`binary: there are bytes after the {what}`, 0)
	end
end

-- Encodes a value, with the value header.
local function encodeValue(v: Value): string
	return string.char(VALUE_HEADER) .. writeAll({ value = v })
end

-- Decodes bytes that must be exactly one value.
local function decodeValue(s: string): Value
	const r = start(s, VALUE_HEADER, "a value")
	const v = readNode(r, "value")
	finishRead(r, "value")

	return v
end

-- Encodes a program: a law of arity 1, with the program header.
local function encodeProgram(law: Value): string
	if type(law) ~= "table" or law.kind ~= "law" or law.arity ~= 1 then
		error("binary: a program is a law of arity 1", 0)
	end

	return string.char(PROGRAM_HEADER) .. posBytes(1) .. writeAll({ form = law.body })
end

-- Decodes bytes that must be exactly one program.
local function decodeProgram(s: string): Value
	const r = start(s, PROGRAM_HEADER, "a program")
	const arity = readPos(r, "an arity")

	if arity ~= 1 then
		error("binary: a program is a law of arity 1", 0)
	end

	const body = readNode(r, "form")
	finishRead(r, "program")

	return { kind = "law", arity = 1, body = body }
end

return {
	NIL = NIL,
	PRIM_ARITY = PRIM_ARITY,
	encodeValue = encodeValue,
	decodeValue = decodeValue,
	encodeProgram = encodeProgram,
	decodeProgram = decodeProgram,
}
