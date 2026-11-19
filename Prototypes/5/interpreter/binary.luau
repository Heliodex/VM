--!strict
-- THE BINARY FORMAT
--
-- Stores and sends data values, and programs, as bytes. It is for machines, so it has no readable form. The text forms are in data.luau and reader.luau.
--
-- Every string starts with one byte that says what it holds:
--
--   1   a data value
--   2   a program, as the quoted form in code.luau
--
-- After the header, a value is a prefix sequence of parts. Each part starts with a tag byte:
--
--   0   nil
--   1   a cell: its head, then its tail
--   2   an integer that is not negative, then its magnitude
--   3   a negative integer, then its magnitude, which is at least 1
--
-- A magnitude is an unsigned LEB128 number: 7 bits per byte, least significant group first, with the top bit set on every byte but the last. The last byte is not zero unless it is the only byte, so each number has one encoding.
--
-- The reader is strict, as the text form is. It refuses a header it does not expect, a tag it does not know, a magnitude that is not in its shortest form, a negative zero, an integer past the limit, a value cut short, and any bytes after the value. A program is read as a value and then checked by fromValue in code.luau.
--
-- The bytes are held in a buffer. The writer grows its buffer by doubling, since the length is not known until the end. The reader takes the string as a buffer, and reads it with positions counted from zero.
--
--   Binary.encodeValue(v): string        raises an error for a function or a pin
--   Binary.decodeValue(s): value         raises an error, with the reason, if the bytes are not a value
--   Binary.encodeProgram(e): string      the program as bytes, with header 2
--   Binary.decodeProgram(s): expr        the expression, checked

const M = require "./vm"
const Code = require "./code"

const VALUE_HEADER = 1
const PROGRAM_HEADER = 2

-- A growing buffer of bytes. The capacity is at least the length, and grows by doubling when a write would pass it.
type Writer = {
	buf: buffer,
	cap: number,
	len: number,
}

const function newWriter(): Writer
	return {
		buf = buffer.create(64),
		cap = 64,
		len = 0,
	}
end

const function reserve(
	w: Writer,
	extra: number
)
	if w.len + extra <= w.cap then
		return
	end

	local cap = w.cap

	while cap < w.len + extra do
		cap *= 2
	end

	const nb = buffer.create(cap)
	buffer.copy(nb, 0, w.buf, 0, w.len)
	w.buf = nb
	w.cap = cap
end

const function putByte(
	w: Writer,
	b: number
)
	reserve(w, 1)
	buffer.writeu8(w.buf, w.len, b)
	w.len += 1
end

-- Writes the unsigned LEB128 of n, a whole number that is not negative.
const function putLeb(
	w: Writer,
	n: number
)
	local m = n

	while true do
		local b = m % 128
		m = (m - b) / 128

		if m > 0 then
			b += 128
		end

		putByte(w, b)

		if m == 0 then
			break
		end
	end
end

-- Writes the body of a value, with no header. The cells are walked with an explicit stack, so a long list does not nest the Luau call stack.
const function writeBody(
	w: Writer,
	v: M.Value
)
	local pending: { M.Value } = { v }
	local count = 1

	while count > 0 do
		const cur = pending[count]
		pending[count] = nil
		count -= 1

		if type(cur) == "number" then
			if cur < 0 then
				putByte(w, 3)
				putLeb(w, -cur)
			else
				putByte(w, 2)
				putLeb(w, cur)
			end
		elseif cur == M.NIL then
			putByte(w, 0)
		elseif cur.kind == "cell" then
			putByte(w, 1)

			-- The head is written before the tail, so the tail goes on the stack first.
			count += 1
			pending[count] = cur.tail
			count += 1
			pending[count] = cur.head
		elseif cur.kind == "closure" then
			error("a function has no binary form", 0)
		else
			error("a pin has no binary form", 0)
		end
	end
end

-- The bytes written to w, as a string.
const function finish(
	w: Writer
): string
	return buffer.readstring(w.buf, 0, w.len)
end

-- Reads one magnitude from b at position p, and returns it with the position after it. Positions count from zero.
const function readMagnitude(
	b: buffer,
	p: number
): (number, number)
	local n = 0
	local scale = 1
	local pos = p
	local groups = 0

	while true do
		if pos >= buffer.len(b) then
			error("binary: the bytes end inside a number", 0)
		end

		const byte = buffer.readu8(b, pos)
		pos += 1
		groups += 1

		if groups > 8 then
			error("binary: a number is too long to be in range", 0)
		end

		n += (byte % 128) * scale
		scale *= 128

		if n > M.MAX_INTEGER then
			error("binary: integer is out of range", 0)
		end

		if byte < 128 then
			-- A last group of zero, after more than one group, would be a longer way to write the number.
			if byte == 0 and groups > 1 then
				error("binary: a number is not in its shortest form", 0)
			end

			return n, pos
		end
	end
end

-- Reads one leaf, which is nil or an integer, from b at position p. Returns the value and the position after it. Cells are not leaves.
const function readLeaf(
	b: buffer,
	p: number
): (M.Value, number)
	const tag = buffer.readu8(b, p)

	if tag == 0 then
		return M.NIL, p + 1
	elseif tag == 2 or tag == 3 then
		const n, after = readMagnitude(b, p + 1)

		if tag == 3 then
			if n == 0 then
				error("binary: negative zero is not a value", 0)
			end

			return -n, after
		end

		return n, after
	end

	error(`binary: tag {tag} is not a value`, 0)
end

-- Reads the body of a value from b at position p, and returns it with the position after it. A cell waits on the stack for its head and then its tail, as in data.luau.
const function readBody(
	b: buffer,
	p: number
): (M.Value, number)
	local stack: { { head: M.Value? } } = {}
	local pos = p

	while true do
		if pos >= buffer.len(b) then
			error("binary: the bytes end before the value is complete", 0)
		end

		if buffer.readu8(b, pos) == 1 then
			table.insert(stack, { head = nil })
			pos += 1
		else
			local v: M.Value
			v, pos = readLeaf(b, pos)

			-- Complete the cells this value finishes, then stop, so the value goes to the head or the tail of the cell around it, or is the whole result.
			while true do
				if #stack == 0 then
					return v, pos
				end

				const top = stack[#stack]

				if top.head == nil then
					top.head = v
					break
				end

				table.remove(stack)
				v = {
					kind = "cell",
					head = top.head :: M.Value,
					tail = v,
				}
			end
		end
	end
end

-- Reads bytes that hold one value, after a header that has been checked. The bytes must end with the value.
const function decodeBody(
	s: string,
	what: string
): M.Value
	if #s < 2 then
		error(`binary: the bytes end before the {what} is complete`, 0)
	end

	const b = buffer.fromstring(s)
	const v, after = readBody(b, 1)

	if after < buffer.len(b) then
		error(`binary: there are bytes after the {what}`, 0)
	end

	return v
end

-- Encodes a data value, with the value header.
const function encodeValue(
	v: M.Value
): string
	local w = newWriter()
	putByte(w, VALUE_HEADER)
	writeBody(w, v)
	return finish(w)
end

-- Decodes bytes that must be exactly one data value.
const function decodeValue(
	s: string
): M.Value
	if #s < 1 or string.byte(s, 1) ~= VALUE_HEADER then
		error("binary: the bytes are not a data value", 0)
	end

	return decodeBody(s, "value")
end

-- Encodes a program as the quoted value of its expression, with the program header.
const function encodeProgram(
	e: M.Expr
): string
	local w = newWriter()
	putByte(w, PROGRAM_HEADER)
	writeBody(w, Code.toValue(e))
	return finish(w)
end

-- Decodes bytes that must be exactly one program, and checks its shape.
const function decodeProgram(
	s: string
): M.Expr
	if #s < 1 or string.byte(s, 1) ~= PROGRAM_HEADER then
		error("binary: the bytes are not a program", 0)
	end

	return Code.fromValue(decodeBody(s, "program"))
end

return {
	encodeValue = encodeValue,
	decodeValue = decodeValue,
	encodeProgram = encodeProgram,
	decodeProgram = decodeProgram,
}
