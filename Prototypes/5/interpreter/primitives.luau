--!strict
-- THE PRIMITIVES
--
-- The primitives are the operations on integers, and kind, which works on any value. Each one is written here once, in a row that gives its tag, its name, the symbol that writes it in the reader's language, its arity and, for a binary one, its operation. The machine, the reader, the printer and the quoted form in code.luau all read this table, so a primitive is added or reordered in one place.
--
-- A binary operation takes two integers and gives an integer, or nil and a message for a failure, such as dividing by zero. kind is unary, and the machine computes it, since it works on any value.
--
--   Primitives.TAG.add == 11                  the tag of a primitive, by its name
--   Primitives.BY_TAG[11].symbol == "+"       the row for a tag
--   Primitives.BY_SYMBOL["+"].tag == 11       the row for a symbol

export type Operation = (number, number) -> (number?, string?)

export type Primitive = {
	tag: number,
	name: string,
	symbol: string,
	arity: number,
	operation: Operation?,
}

-- The remainder of a divided by b, taking the sign of b, so that a = b * div + mod. Only for integers in range.
const function floored_mod(
	a: number,
	b: number
): number
	-- math.fmod is exact on doubles, and its result takes the sign of a. It is shifted by b when the signs differ.
	local r = math.fmod(a, b)

	if r ~= 0 and (r < 0) ~= (b < 0) then
		r += b
	end

	return r
end

const ROWS: { Primitive } = {
	{
		tag = 11,
		name = "add",
		symbol = "+",
		arity = 2,
		operation = function(
			a: number,
			b: number
		): (number?, string?)
			return a + b, nil
		end,
	},
	{
		tag = 12,
		name = "sub",
		symbol = "-",
		arity = 2,
		operation = function(
			a: number,
			b: number
		): (number?, string?)
			return a - b, nil
		end,
	},
	{
		tag = 13,
		name = "mul",
		symbol = "*",
		arity = 2,
		operation = function(
			a: number,
			b: number
		): (number?, string?)
			return a * b, nil
		end,
	},
	{
		tag = 14,
		name = "div",
		symbol = "/",
		arity = 2,
		operation = function(
			a: number,
			b: number
		): (number?, string?)
			if b == 0 then
				return nil, "div by zero"
			end

			-- Floored, and exact. math.fmod leaves a - fmod(a, b) as the truncated quotient times b, which has magnitude at most |a|, so it is exact on doubles. Adding b to the remainder could push a - r past 2^53 and round, so the floor is taken as a correction to the truncated quotient instead.
			local r = math.fmod(a, b)
			local q = (a - r) / b

			if r ~= 0 and (r < 0) ~= (b < 0) then
				q -= 1
			end

			return q, nil
		end,
	},
	{
		tag = 15,
		name = "mod",
		symbol = "%",
		arity = 2,
		operation = function(
			a: number,
			b: number
		): (number?, string?)
			if b == 0 then
				return nil, "mod by zero"
			end

			return floored_mod(a, b), nil
		end,
	},
	{
		tag = 16,
		name = "lt",
		symbol = "<",
		arity = 2,
		operation = function(
			a: number,
			b: number
		): (number?, string?)
			if a < b then
				return 1, nil
			end

			return 0, nil
		end,
	},
	{
		tag = 17,
		name = "eq",
		symbol = "=",
		arity = 2,
		operation = function(
			a: number,
			b: number
		): (number?, string?)
			if a == b then
				return 1, nil
			end

			return 0, nil
		end,
	},
	{
		tag = 18,
		name = "kind",
		symbol = "@",
		arity = 1,
		operation = nil,
	},
}

const TAG: { [string]: number } = {}
const BY_TAG: { [number]: Primitive } = {}
const BY_SYMBOL: { [string]: Primitive } = {}

for _, row in ROWS do
	TAG[row.name] = row.tag
	BY_TAG[row.tag] = row
	BY_SYMBOL[row.symbol] = row
end

return {
	TAG = TAG,
	BY_TAG = BY_TAG,
	BY_SYMBOL = BY_SYMBOL,
}
