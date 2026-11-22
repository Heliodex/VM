--!strict
-- THE DATA FORMAT
--
-- Writes a data value as text, and reads it back. This is for interchange: a value passed in, or out, of a program. It is not the program syntax in reader.luau, and it is never evaluated, so it has no variables, forms or brackets to parse.
--
-- A value is a sequence of tokens, separated by single spaces:
--
--   nil                the nil value
--   0, -3, 42          an integer, written in decimal, within the exact range
--   cons h t           a cell, with head h and tail t, each a value in turn
--   con n p            a constructor with tag n, a whole number from 0 up, and payload p
--
-- It is a prefix form, so the tokens of a cell follow it in order and the whole text can be read in one pass with no nesting. A list 1, 2, 3 is "cons 1 cons 2 cons 3 nil".
--
-- The form is canonical. The writer produces exactly one text for each value, and the reader accepts only that text: no leading zeros, no -0, no plus signs, one space between tokens and none at the ends, and nothing after the value. So reading a text and writing the value back gives the same text, and two values are equal exactly when their texts are.
--
-- A constructor is written con followed by its tag and its payload, and its tag is a whole number from 0 up. The text uses the tag, which is not a name: names are for the surface language.
-- Functions and pins have no written form. Writing one is an error.
--
--   Data.write(value): string      raises an error for a function or a pin
--   Data.read(text): value         raises an error, with the reason, if the text is not a value

const M = require "./vm"

type Stack = { { head: M.Value?; con: boolean } }

-- Writes a value. The cells are walked with an explicit stack, so a long list does not nest the Luau call stack.
const function write(v: M.Value): string
	local out: { string } = {}
	local pending: { M.Value } = { v }
	local count = 1

	while count > 0 do
		const cur = pending[count]
		pending[count] = nil
		count -= 1

		if type(cur) == "number" then
			table.insert(out, tostring(cur))
		elseif cur == M.NIL then
			table.insert(out, "nil")
		elseif cur.kind == "con" then
			table.insert(out, "con")
			-- The tag is written before the payload, so the payload goes on the stack first.
			count += 1
			pending[count] = cur.payload
			count += 1
			pending[count] = cur.tag
		elseif cur.kind == "cell" then
			table.insert(out, "cons")
			-- The head is written before the tail, so the tail goes on the stack first.
			count += 1
			pending[count] = cur.tail
			count += 1
			pending[count] = cur.head
		elseif cur.kind == "closure" then
			error("a function has no written form", 0)
		else
			error("a pin has no written form", 0)
		end
	end

	return table.concat(out, " ")
end

-- Reads one token that is not cons: nil, or an integer in canonical form and range.
const function leaf(token: string): M.Value
	if token == "nil" then
		return M.NIL
	end

	if not string.match(token, "^%-?%d+$") then
		error(string.format("data: %q is not a value token", token), 0)
	end

	-- A zero is written as 0, and a digit is never written after a leading zero.
	if token == "-0" or string.match(token, "^%-?0%d") then
		error(string.format("data: %q is not in canonical form", token), 0)
	end

	const n = tonumber(token) :: number

	-- A value past the limit may already have rounded, but it still compares past the limit, so the check is exact.
	if n > M.MAX_INTEGER or n < -M.MAX_INTEGER then
		error(string.format("data: integer %s is out of range", token), 0)
	end

	return n
end

-- Reads a whole text as one value. Each token either is a value, which completes the innermost cell still waiting for its tail, or starts a cell, which waits for its head and then its tail. The stack holds the cells waiting for a part.
const function read(text: string): M.Value
	if text == "" then
		error("data: the text is empty", 0)
	end

	if string.sub(text, 1, 1) == " " or string.sub(text, -1) == " " or string.find(text, "  ", 1, true) then
		error("data: tokens are separated by one space, with none at either end", 0)
	end

	local stack: Stack = {}
	local done = false
	local result: M.Value = M.NIL

	for token in string.gmatch(text, "[^ ]+") do
		if done then
			error(string.format("data: %q comes after the value has ended", token), 0)
		end

		if token == "cons" then
			table.insert(stack, { head = nil; con = false })
		elseif token == "con" then
			table.insert(stack, { head = nil; con = true })
		else
			local v = leaf(token)

			while true do
				if #stack == 0 then
					result = v
					done = true
					break
				end

				const top = stack[#stack]

				if top.head == nil then
					-- This value is the head, so the tail is still to come. A constructor's head is its tag, which is a whole number from 0 up.
					if top.con and (type(v) ~= "number" or v < 0 or v ~= math.floor(v)) then
						error("data: a constructor tag is a whole number from 0 up", 0)
					end

					top.head = v
					break
				end

				-- This value is the tail, so the cell is complete. It may complete the cell around it as well.
				table.remove(stack)

				if top.con then
					v = {
						kind = "con",
						tag = top.head :: number,
						payload = v,
					}
				else
					v = {
						kind = "cell",
						head = top.head :: M.Value,
						tail = v,
					}
				end
			end
		end
	end

	if not done then
		error("data: the text ends before the value is complete", 0)
	end

	return result
end

return {
	write = write,
	read = read,
}
