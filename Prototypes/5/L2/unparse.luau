--!strict
-- THE L2 UNPARSER
--
-- Writes a parsed program as indented .l2 text, the inverse of L2/layout.luau for the forms the layer covers. It is used once, to convert a bracketed program to .l2, and the conversion is checked: the layout of the text must give the same tree as the parse of the original.
--
-- A form that is not written on one line is written as a block: a let, a fn, an if, a match, a letrec group and an application with arguments below it. A form that the layer cannot take as an argument (a let, or an if) is an error, and it is reported with its position, so the source can be rewritten by hand.
--
--   Unparse.program(program: Parser.Program, header: string): string

const Parser = require "./parser"

type Expr = Parser.Expr
type Pos = Parser.Pos
local M = {}

const function fail(at: Pos?, msg: string)
	if at ~= nil then
		error(string.format("line %d, column %d: %s", at.line, at.col, msg), 0)
	end

	error(msg, 0)
end

-- A string as the source writes it: the bytes, with the escapes the lexer reads.
const function quoted(bytes: { number }): string
	local out: { string } = {}

	for _, b in bytes do
		if b == 34 then
			table.insert(out, '\\"')
		elseif b == 92 then
			table.insert(out, "\\\\")
		elseif b == 10 then
			table.insert(out, "\\n")
		elseif b == 9 then
			table.insert(out, "\\t")
		elseif b == 0 then
			table.insert(out, "\\0")
		else
			table.insert(out, string.char(b))
		end
	end

	return `"{table.concat(out)}"`
end

-- A type, as a payload or in a declaration: atoms as they are, anything else in brackets.
const function typeText(t: Parser.Type): string
	if t.k == "tname" then
		return t.name
	elseif t.k == "tapp" then
		local args: { string } = {}

		for _, a in t.args do
			table.insert(args, typeText(a))
		end

		return `({t.name} {table.concat(args, " ")})`
	elseif t.k == "tpair" then
		return `({typeText(t.a)} . {typeText(t.b)})`
	elseif t.k == "tlist" then
		return `[{typeText(t.item)}]`
	end

	return `({typeText(t.a)} -> {typeText(t.b)})`
end

-- A pattern on one line: the constructor, its bound name or _, a name, or _.
const function patText(p: Parser.Pattern): string
	if p.k == "con" then
		if p.bind ~= nil then
			return `{p.name} {p.bind :: string}`
		end

		return p.name
	elseif p.k == "bind" then
		return p.name
	end

	return "_"
end

-- An expression on one line, or nil when it has to be a block.
local flat: (Expr) -> string?
flat = function(e: Expr): string?
	if e.k == "int" then
		return tostring(e.n)
	elseif e.k == "str" then
		return quoted(e.bytes)
	elseif e.k == "nil" then
		return "~"
	elseif e.k == "name" then
		return e.name
	elseif e.k == "list" then
		local items: { string } = {}

		for _, i in e.items do
			const t = flat(i)

			if t == nil then
				return nil
			end

			table.insert(items, t)
		end

		return `[{table.concat(items, " ")}]`
	elseif e.k == "pair" then
		const a = flat(e.a)
		const b = flat(e.b)

		if a == nil or b == nil then
			return nil
		end

		return `({a} . {b})`
	elseif e.k == "app" then
		local parts: { string } = {}
		const head = flat(e.f)

		if head == nil then
			return nil
		end

		table.insert(parts, head)

		for _, a in e.args do
			const t = flat(a)

			if t == nil then
				return nil
			end

			table.insert(parts, t)
		end

		return `({table.concat(parts, " ")})`
	elseif e.k == "if" then
		const c = flat(e.c)
		const t = flat(e.t)
		const f = flat(e.e)

		if c == nil or t == nil or f == nil then
			return nil
		end

		return `(if {c} {t} {f})`
	elseif e.k == "try" then
		const t = flat(e.e)

		if t == nil then
			return nil
		end

		return `({t}?)`
	elseif e.k == "check" then
		const t = flat(e.e)

		if t == nil or e.test ~= nil then
			return nil
		end

		return `(check {t})`
	elseif e.k == "untyped" then
		const t = flat(e.e)

		if t == nil then
			return nil
		end

		return `(untyped {t})`
	end

	return nil
end
-- The lines of a block, indented by ind tabs. Each line is a string with its tabs in front.
local emit: (Expr, number, { string }) -> ()

const function line(out: { string }, ind: number, text: string)
	table.insert(out, `{string.rep("\t", ind)}{text}`)
end

-- A flat expression, or a block that is the value of a let or an argument.
const function headerOf(e: Expr): string?
	if e.k == "record" then
		return e.name
	elseif e.k == "with" then
		const b = flat(e.base)

		if b == nil then
			return nil
		end

		return `with {b}`
	elseif e.k == "fn" then
		if #e.names == 1 then
			return `fn {e.names[1]}`
		end

		return `fn ({table.concat(e.names, " ")})`
	elseif e.k == "match" then
		const s = flat(e.scrut)

		if s == nil then
			return nil
		end

		return `match {s}`
	elseif e.k == "app" then
		return flat(e.f)
	end

	return nil
end

-- The lines below the header of a block value: a fn's body, a match's arms, or an application's arguments.
-- A field line, name = value: the value on the line, or a header with its block below.
local emitBelow: (Expr, number, { string }) -> ()

const function emitField(name: string, value: Expr, ind: number, out: { string })
	const t = flat(value)

	if t ~= nil then
		line(out, ind, `{name} = {t}`)
		return
	end

	const h = headerOf(value)

	if h == nil then
		fail(value.at, "a field value of this form is not written as a block")
	end

	line(out, ind, `{name} = {h :: string}`)
	emitBelow(value, ind + 1, out)
end

emitBelow = function(e: Expr, ind: number, out: { string })
	if e.k == "record" or e.k == "with" then
		for _, f in e.fields do
			emitField(f.name, f.value, ind, out)
		end
	elseif e.k == "fn" then
		emit(e.body, ind, out)
	elseif e.k == "match" then
		for _, arm in e.arms do
			const pat = patText(arm.pat)
			const body = flat(arm.body)

			if body ~= nil then
				line(out, ind, `{pat} -> {body}`)
			else
				line(out, ind, `{pat} ->`)
				emit(arm.body, ind + 1, out)
			end
		end
	elseif e.k == "app" then
		for _, a in e.args do
			emit(a, ind, out)
		end
	end
end

-- A value on the line of a let: flat, or a header with its block below it.
const function emitValue(value: Expr, name: string, kw: string, ind: number, out: { string })
	const t = flat(value)

	if t ~= nil then
		line(out, ind, `{kw}{name} = {t}`)

		return
	end

	const h = headerOf(value)

	if h == nil then
		fail(value.at, "a let value of this form is not written as a block")
	end

	line(out, ind, `{kw}{name} = {h :: string}`)
	emitBelow(value, ind + 1, out)
end

emit = function(e: Expr, ind: number, out: { string })
	const t = flat(e)

	if t ~= nil then
		line(out, ind, t :: string)

		return
	end

	if e.k == "record" or e.k == "with" then
		const h = headerOf(e)

		if h == nil then
			fail(e.at, "a record or with is written with its base on one line")
		end

		line(out, ind, h :: string)
		emitBelow(e, ind + 1, out)
	elseif e.k == "let" then
		emitValue(
			e.value,
			e.name,
			if e.rec then
				"letrec "
			else
				"let ",
			ind,
			out
		)
		emit(e.body, ind, out)
	elseif e.k == "fn" then
		line(out, ind, headerOf(e) :: string)
		emit(e.body, ind + 1, out)
	elseif e.k == "if" then
		const c = flat(e.c)

		if c == nil then
			fail(e.c.at, "an if condition is written on one line")
		end

		line(out, ind, `if {c :: string}`)
		emit(e.t, ind + 1, out)

		-- An else branch that is itself an if is written as an elseif, at the same level.
		local rest = e.e

		while rest.k == "if" do
			const rc = flat(rest.c)

			if rc == nil then
				fail(rest.c.at, "an if condition is written on one line")
			end

			line(out, ind, `elseif {rc :: string}`)
			emit(rest.t, ind + 1, out)
			rest = rest.e
		end

		line(out, ind, "else")
		emit(rest, ind + 1, out)
	elseif e.k == "match" then
		const s = flat(e.scrut)

		if s == nil then
			fail(e.scrut.at, "a match scrutinee is written on one line")
		end

		line(out, ind, `match {s :: string}`)
		emitBelow(e, ind + 1, out)
	elseif e.k == "mutual" then
		line(out, ind, "letrec")

		for _, b in e.bindings do
			emitValue(b.value, b.name, "", ind + 1, out)
		end

		emit(e.body, ind, out)
	elseif e.k == "app" then
		const h = flat(e.f)

		if h == nil then
			fail(e.at, "an application's head is written on one line")
		end

		line(out, ind, h :: string)
		emitBelow(e, ind + 1, out)
	else
		fail(e.at, "this form has no indented form in the converter")
	end
end
-- The program: its type declarations, then its expression. The header is the file's first lines, kept as they are.
M.program = function(program: Parser.Program): string
	local out: { string } = {}

	for _, d in program.decls do
		-- Each constructor's text, and the fields of a record constructor, which is the last one.
		local items: { { text: string; fields: { Parser.FieldDecl }? } } = {}

		for _, c in d.cons do
			if c.fields ~= nil then
				table.insert(items, { text = c.name; fields = c.fields })
			elseif c.payload ~= nil then
				table.insert(items, { text = `{c.name} {typeText(c.payload :: Parser.Type)}`; fields = nil })
			else
				table.insert(items, { text = c.name; fields = nil })
			end
		end

		local params =
			if #d.params > 0 then
				` {table.concat(d.params, " ")}`
			else
				""
		local texts: { string } = {}

		for _, it in items do
			table.insert(texts, it.text)
		end

		local header = `type {d.name}{params}`
		local oneLine = `{header} = {table.concat(texts, " | ")}`

		-- A record constructor that is not the last one can only be written with its fields below its | line.
		local middleRecord = false

		for k, it in items do
			if it.fields ~= nil and k ~= #items then
				middleRecord = true
			end
		end

		-- A long sum is written with each constructor on a | line below the type line, and a record constructor's fields below its | line.
		if #oneLine > 80 or middleRecord then
			line(out, 0, `{header} =`)

			for _, it in items do
				line(out, 1, `| {it.text}`)

				if it.fields ~= nil then
					for _, f in it.fields :: { Parser.FieldDecl } do
						line(out, 2, `{f.name}: {typeText(f.type)}`)
					end
				end
			end
		else
			line(out, 0, oneLine)

			-- A short sum keeps a record constructor's fields below the type line.
			for _, it in items do
				if it.fields ~= nil then
					for _, f in it.fields :: { Parser.FieldDecl } do
						line(out, 1, `{f.name}: {typeText(f.type)}`)
					end
				end
			end
		end
	end

	emit(program.expr, 0, out)

	return table.concat(out, "\n")
end

return M
