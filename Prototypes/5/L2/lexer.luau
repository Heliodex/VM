--!strict
-- THE L2 LEXER
--
-- Turns source text into tokens (SPEC section 2). Each token has a kind, a value, and the line and column where it starts. Newlines are tokens, because a match arm ends at a newline; the parser decides when they matter.
--
-- Kinds:
--
--   "(" ")" "[" "]" "{" "}"   delimiters
--   "."                       the dot of a pair, standing alone
--   "->"                      the arrow of a match arm
--   "?"                       early return
--   "NL"                      a newline
--   "int"                     an integer; the value is the number
--   "str"                     a string; the value is its bytes, as a list of numbers
--   "sym"                     a name or operator; the value is its text
--   "eof"                     the end of the text
--
-- A symbol is a run of characters that are not whitespace or a delimiter. The delimiters are ( ) [ ] { } " ; . ? and the space characters. A symbol cannot start with a digit. A word that starts with a digit, or with - and a digit, is an integer, and it must be a whole integer, so 1-2 is an error. A - directly before digits is part of the integer, so -5 is a literal and - 5 is the symbol - and 5. The arrow -> ends a symbol, so x->y is x, ->, y.
--
--   Lexer.tokenize(text): { Token }      raises an error, with the line and column, if the text does not lex

const M = require "../interpreter/vm"

export type TokenValue = string | number | { number } | nil

export type Token = {
	kind: string,
	value: TokenValue,
	line: number,
	col: number,
	spaced: boolean,
}

const function isSpace(
	c: string
): boolean
	return c == " " or c == "\t" or c == "\r" or c == "\n"
end

const function isDelimiter(
	c: string
): boolean
	return isSpace(c)
		or c == "("
		or c == ")"
		or c == "["
		or c == "]"
		or c == "{"
		or c == "}"
		or c == "\""
		or c == ";"
		or c == "."
		or c == "?"
		or c == ""
end

const function tokenize(
	src: string
): { Token }
	local tokens: { Token } = {}
	local i = 1
	local line = 1
	local lineStart = 1
	local spaced = true
	local n = #src

	local function at(
		pos: number
	): number
		return pos - lineStart + 1
	end

	local function fail(
		pos: number,
		msg: string
	)
		error(string.format("line %d, column %d: %s", line, at(pos), msg), 0)
	end

	local function push(
		kind: string,
		value: TokenValue,
		pos: number
	)
		table.insert(tokens, {
			kind = kind,
			value = value,
			line = line,
			col = at(pos),
			spaced = spaced,
		})
		spaced = false
	end

	while i <= n do
		const c = string.sub(src, i, i)

		if c == " " or c == "\t" or c == "\r" then
			i += 1
			spaced = true
		elseif c == "\n" then
			push("NL", nil, i)
			i += 1
			line += 1
			lineStart = i
			spaced = true
		elseif c == ";" then
			while i <= n and string.sub(src, i, i) ~= "\n" do
				i += 1
			end
		elseif c == "(" or c == ")" or c == "[" or c == "]" or c == "{" or c == "}" or c == "?" then
			push(c, nil, i)
			i += 1
		elseif c == "." then
			if i > 1 and not spaced and not isDelimiter(string.sub(src, i - 1, i - 1)) then
				fail(i, "a dot stands alone: put a space before it")
			end

			if not isDelimiter(string.sub(src, i + 1, i + 1)) then
				fail(i, "a dot stands alone: put a space after it")
			end

			push(".", nil, i)
			i += 1
		elseif c == "\"" then
			local bytes: { number } = {}
			local j = i + 1

			while true do
				if j > n then
					fail(i, "a string is never closed")
				end

				const ch = string.sub(src, j, j)

				if ch == "\"" then
					break
				end

				if ch == "\n" then
					fail(j, "a string cannot run over a line")
				end

				if ch == "\\" then
					const escape = string.sub(src, j + 1, j + 1)

					if escape == "\"" then
						table.insert(bytes, 34)
					elseif escape == "\\" then
						table.insert(bytes, 92)
					elseif escape == "n" then
						table.insert(bytes, 10)
					elseif escape == "t" then
						table.insert(bytes, 9)
					elseif escape == "0" then
						table.insert(bytes, 0)
					else
						fail(j, "unknown escape \\" .. escape)
					end

					j += 2
				else
					table.insert(bytes, string.byte(ch) :: number)
					j += 1
				end
			end

			push("str", bytes, i)
			i = j + 1
		elseif c == "-" and string.sub(src, i + 1, i + 1) == ">" then
			push("->", nil, i)
			i += 2
		else
			local start = i
			local j = i

			while j <= n do
				const ch = string.sub(src, j, j)

				if isDelimiter(ch) then
					break
				end

				-- The arrow ends a symbol, but only after its first character.
				if ch == "-" and string.sub(src, j + 1, j + 1) == ">" and j > start then
					break
				end

				j += 1
			end

			const word = string.sub(src, start, j - 1)
			i = j

			const second = string.sub(word, 2, 2)
			const startsNumber = string.match(word, "^%d") ~= nil or (string.sub(word, 1, 1) == "-" and string.match(second, "^%d") ~= nil)

			if startsNumber then
				if not string.match(word, "^%-?%d+$") then
					fail(start, string.format("%s is not a whole integer", word))
				end

				const value = tonumber(word) :: number

				if value > M.MAX_INTEGER or value < -M.MAX_INTEGER then
					fail(start, string.format("integer %s is out of range", word))
				end

				push("int", value, start)
			else
				push("sym", word, start)
			end
		end
	end

	push("eof", nil, i)
	return tokens
end

return {
	tokenize = tokenize,
}
