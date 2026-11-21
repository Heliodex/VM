--!strict
-- READING PROGRAMS
--
-- Turns source text into expressions, which compile.luau then turns into a net.
-- The syntax is S-expressions: a natural number, a symbol, or a parenthesised list of expressions. A `'` before an expression quotes it, so 'x is (quote x). A `;` starts a comment that runs to the end of its line.
--
--   const Reader = require "./reader"
--
--   const forms = Reader.read("(+ 1 2) ; a comment\n(succ 3)")
--   print(Reader.show(forms[1])) -- (+ 1 2)
--
-- Errors are raised for unbalanced brackets and for an empty source where one form was expected; they carry the byte position where the problem was found.

export type Expr = {
	read kind: "num" | "sym" | "list",
	read value: number?,
	read name: string?,
	read items: { Expr }?,
	-- the byte offset where the expression starts in the source, if it came from source
	read at: number?,
}
type Token = {
	text: string,
	at: number,
}

const function num(n: number, at: number?): Expr
	return {
		kind = "num",
		value = n,
		at = at,
	}
end

const function sym(name: string, at: number?): Expr
	return {
		kind = "sym",
		name = name,
		at = at,
	}
end

const function list(items: { Expr }, at: number?): Expr
	return {
		kind = "list",
		items = items,
		at = at,
	}
end

-- Splits the source into brackets, atoms and nothing else.
const function tokenize(src: string): { Token }
	const tokens: { Token } = {}
	local pos = 1

	while true do
		-- skip whitespace, which may be empty
		const _, stop = string.find(src, "^%s*", pos)
		pos = stop :: number + 1

		if pos > #src then
			break
		end

		const c = string.sub(src, pos, pos)

		if c == ";" then
			const newline = string.find(src, "\n", pos, true)
			pos =
				if newline then
					newline :: number + 1
				else
					#src + 1
		elseif c == "(" or c == ")" or c == "'" then
			table.insert(
				tokens,
				{
					text = c,
					at = pos,
				}
			)
			pos += 1
		else
			const first, last = string.find(src, "^[^%s();']+", pos)
			table.insert(
				tokens,
				{
					text = string.sub(src, first :: number, last :: number),
					at = pos,
				}
			)
			pos = last :: number + 1
		end
	end

	return tokens
end

-- The expression starting at token `i`, and the index of the token after it.
local function parseAt(tokens: { Token }, i: number): (Expr, number)
	const t = tokens[i]

	if not t then
		error "unexpected end of input"
	end

	if t.text == ")" then
		error(`unexpected ) at byte {t.at}`)
	end

	-- 'x is (quote x), and the quoted form may itself be a list
	if t.text == "'" then
		const quoted, after = parseAt(tokens, i + 1)

		return list(
			{
				sym("quote", t.at),
				quoted,
			},
			t.at
		), after
	end

	if t.text == "(" then
		const items: { Expr } = {}
		local j = i + 1

		while true do
			const u = tokens[j]

			if not u then
				error(`( at byte {t.at} is never closed`)
			end

			if u.text == ")" then
				return list(items, t.at), j + 1
			end

			local item: Expr
			item, j = parseAt(tokens, j)
			table.insert(items, item)
		end
	end

	if string.match(t.text, "^%d+$") then
		return num(tonumber(t.text) :: number, t.at), i + 1
	end

	return sym(t.text, t.at), i + 1
end

-- Every expression in the source, in order. An empty source has none.
const function read(src: string): { Expr }
	const tokens = tokenize(src)
	const forms: { Expr } = {}
	local i = 1

	while i <= #tokens do
		local form: Expr
		form, i = parseAt(tokens, i)
		table.insert(forms, form)
	end

	return forms
end

-- An expression written back as source, with single spaces, so that a test can compare the shape of what was read.
const function show(e: Expr): string
	if e.kind == "num" then
		return tostring(e.value)
	elseif e.kind == "sym" then
		return e.name :: string
	end

	const parts: { string } = {}

	for _, item in e.items :: { Expr } do
		table.insert(parts, show(item))
	end

	return `({table.concat(parts, " ")})`
end

return {
	num = num,
	sym = sym,
	list = list,
	read = read,
	show = show,
}
