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
--   Binary.encodeValue(v): string        raises an error for a function or a pin
--   Binary.decodeValue(s): value         raises an error, with the reason, if the bytes are not a value
--   Binary.encodeProgram(e): string      the program as bytes, with header 2
--   Binary.decodeProgram(s): expr        the expression, checked

const M = require "./vm"
const Code = require "./code"

const VALUE_HEADER = string.char(1)
const PROGRAM_HEADER = string.char(2)

-- Appends the unsigned LEB128 of n, a whole number that is not negative.
const function leb(
	n: number,
	out: { string }
)
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
end

-- Writes the body of a value, with no header. The cells are walked with an explicit stack, so a long list does not nest the Luau call stack.
const function body(
	v: M.Value
): string
	local out: { string } = {}
	local pending: { M.Value } = { v }
	local count = 1

	while count > 0 do
		const cur = pending[count]
		pending[count] = nil
		count -= 1

		if type(cur) == "number" then
			if cur < 0 then
				table.insert(out, string.char(3))
				leb(-cur, out)
			else
				table.insert(out, string.char(2))
				leb(cur, out)
			end
		elseif cur == M.NIL then
			table.insert(out, string.char(0))
		elseif cur.kind == "cell" then
			table.insert(out, string.char(1))

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

	return table.concat(out)
end

-- Reads one magnitude from s at pos, and returns it with the position after it.
const function readMagnitude(
	s: string,
	pos: number
): (number, number)
	local n = 0
	local scale = 1
	local p = pos
	local groups = 0

	while true do
		if p > #s then
			error("binary: the bytes end inside a number", 0)
		end

		const b = string.byte(s, p)
		p += 1
		groups += 1

		if groups > 8 then
			error("binary: a number is too long to be in range", 0)
		end

		n += (b % 128) * scale
		scale *= 128

		if n > M.MAX_INTEGER then
			error("binary: integer is out of range", 0)
		end

		if b < 128 then
			-- A last group of zero, after more than one group, would be a longer way to write the number.
			if b == 0 and groups > 1 then
				error("binary: a number is not in its shortest form", 0)
			end

			return n, p
		end
	end
end

-- Reads one leaf, which is nil or an integer, from s at pos. Returns the value and the position after it. Cells are not leaves.
const function readLeaf(
	s: string,
	pos: number
): (M.Value, number)
	const tag = string.byte(s, pos)

	if tag == 0 then
		return M.NIL, pos + 1
	elseif tag == 2 or tag == 3 then
		const n, after = readMagnitude(s, pos + 1)

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

-- Reads the body of a value from s at pos, and returns it with the position after it. A cell waits on the stack for its head and then its tail, as in data.luau.
const function readBody(
	s: string,
	pos: number
): (M.Value, number)
	local stack: { { head: M.Value? } } = {}
	local p = pos

	while true do
		if p > #s then
			error("binary: the bytes end before the value is complete", 0)
		end

		const tag = string.byte(s, p)
		local v: M.Value

		if tag == 1 then
			table.insert(stack, { head = nil })
			p += 1
		else
			v, p = readLeaf(s, p)

			-- Complete the cells this value finishes, then stop, so the value goes to the head or the tail of the cell around it, or is the whole result.
			while true do
				if #stack == 0 then
					return v, p
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

-- Encodes a data value, with the value header.
const function encodeValue(
	v: M.Value
): string
	return VALUE_HEADER .. body(v)
end

-- Decodes bytes that must be exactly one data value.
const function decodeValue(
	s: string
): M.Value
	if string.sub(s, 1, 1) ~= VALUE_HEADER then
		error("binary: the bytes are not a data value", 0)
	end

	if #s < 2 then
		error("binary: the bytes end before the value is complete", 0)
	end

	const v, after = readBody(s, 2)

	if after <= #s then
		error("binary: there are bytes after the value", 0)
	end

	return v
end

-- Encodes a program as the quoted value of its expression, with the program header.
const function encodeProgram(
	e: M.Expr
): string
	return PROGRAM_HEADER .. body(Code.toValue(e))
end

-- Decodes bytes that must be exactly one program, and checks its shape.
const function decodeProgram(
	s: string
): M.Expr
	if string.sub(s, 1, 1) ~= PROGRAM_HEADER then
		error("binary: the bytes are not a program", 0)
	end

	if #s < 2 then
		error("binary: the bytes end before the program is complete", 0)
	end

	const v, after = readBody(s, 2)

	if after <= #s then
		error("binary: there are bytes after the program", 0)
	end

	return Code.fromValue(v)
end

return {
	encodeValue = encodeValue,
	decodeValue = decodeValue,
	encodeProgram = encodeProgram,
	decodeProgram = decodeProgram,
}
