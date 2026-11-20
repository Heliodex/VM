--!strict
-- THE L2 PARSER
--
-- Reads a program's text into a surface tree (SPEC sections 3, 9 and 12). Every node has the line and column where it starts, so the desugarer can report errors at source. Types are parsed too, for the checker; the desugarer ignores them.
--
-- A program is zero or more type declarations, then one expression:
--
--   type Result a e = Ok a | Err e        one declaration to a line
--   <expression>
--
-- Newlines are whitespace, except inside a match block, where a newline ends an arm body. Inside parentheses and brackets newlines are whitespace again. Items of a list are atoms, so a call inside a list needs parentheses.
--
-- The surface tree:
--
--   int {n}, str {bytes}, nil, name {name}, list {items}, pair {a, b}
--   app {f, args}, fn {names, body}, let {name, value, body, rec}
--   mutual {bindings = {{name, value}}, body}, if {c, t, e}
--   match {scrut, arms = {{pat, body}}}, try {e}
--   pattern: con {name, bind} (bind nil when the payload is ignored or there is none), bind {name}, wild
--
--   Parser.parse(text): { decls, expr }    raises an error, with the line and column, if the text is not a program

const Lexer = require "./lexer"

const KEYWORDS: { [string]: boolean } = {
	fn = true,
	let = true,
	letrec = true,
	["in"] = true,
	["if"] = true,
	match = true,
	mutual = true,
	type = true,
}

local function isCapital(
	name: string
): boolean
	return string.match(name, "^%u") ~= nil
end

local function parse(
	text: string
): { decls: { any }, expr: any }
	local toks = Lexer.tokenize(text)
	local pos = 1
	local sig = false

	local function raw(): any
		return toks[pos]
	end

	-- The next token. Outside a match block, newlines are skipped.
	local function cur(): any
		if not sig then
			while toks[pos].kind == "NL" do
				pos += 1
			end
		end

		return toks[pos]
	end

	local function advance(): any
		const t = cur()
		pos += 1
		return t
	end

	local function fail(
		t: any,
		msg: string
	)
		error(string.format("line %d, column %d: %s", t.line, t.col, msg), 0)
	end

	local function expectKind(
		kind: string
	): any
		const t = cur()

		if t.kind ~= kind then
			fail(t, string.format("expected %s here", kind))
		end

		return advance()
	end

	local function expectSym(
		value: string
	): any
		const t = cur()

		if t.kind ~= "sym" or t.value ~= value then
			fail(t, string.format("expected %s here", value))
		end

		return advance()
	end

	local function at(
		t: any
	): { line: number, col: number }
		return { line = t.line, col = t.col }
	end

	-- TYPES

	local parseType: () -> any

	local function typeAtomStart(
		t: any
	): boolean
		return (t.kind == "sym" and t.value ~= "|") or t.kind == "(" or t.kind == "["
	end

	local function parseTypeAtom(): any
		const t = cur()

		if t.kind == "sym" then
			advance()
			return { k = "tname", name = t.value, at = at(t) }
		elseif t.kind == "(" then
			advance()
			const saved = sig
			sig = false
			const first = parseType()
			local result: any = first

			if cur().kind == "." then
				advance()
				result = { k = "tpair", a = first, b = parseType(), at = at(t) }
			end

			expectKind(")")
			sig = saved
			return result
		elseif t.kind == "[" then
			advance()
			const saved = sig
			sig = false
			const item = parseType()
			expectKind("]")
			sig = saved
			return { k = "tlist", item = item, at = at(t) }
		end

		fail(t, "expected a type")
		return nil
	end

	local function parseBaseType(): any
		const first = parseTypeAtom()

		if first.k == "tname" and isCapital(first.name) then
			local args: { any } = {}

			while typeAtomStart(cur()) and cur().kind ~= "->" do
				table.insert(args, parseTypeAtom())
			end

			if #args > 0 then
				return { k = "tapp", name = first.name, args = args, at = first.at }
			end
		end

		return first
	end

	parseType = function(): any
		const base = parseBaseType()

		if cur().kind == "->" then
			const arrow = advance()
			return { k = "tfun", a = base, b = parseType(), at = at(arrow) }
		end

		return base
	end

	-- A declaration: type Name params = Con payload | Con payload. The payload is one type atom, if there is one.
	local function parseTypeDecl(): any
		const start = advance()
		const nameTok = expectKind("sym")

		if not isCapital(nameTok.value) then
			fail(nameTok, "a type's name starts with a capital letter")
		end

		local params: { string } = {}

		while cur().kind == "sym" and not isCapital(cur().value) and cur().value ~= "=" do
			table.insert(params, advance().value)
		end

		expectSym("=")
		local cons: { any } = {}

		while true do
			const conTok = expectKind("sym")

			if not isCapital(conTok.value) then
				fail(conTok, "a constructor's name starts with a capital letter")
			end

			local payload: any = nil

			if typeAtomStart(cur()) then
				payload = parseTypeAtom()
			end

			table.insert(cons, { name = conTok.value, payload = payload, at = at(conTok) })

			if cur().kind == "sym" and cur().value == "|" then
				advance()
			else
				break
			end
		end

		return { name = nameTok.value, params = params, cons = cons, at = at(start) }
	end

	-- EXPRESSIONS

	local parseExpr: () -> any

	local function atomStart(
		t: any
	): boolean
		if t.kind == "int" or t.kind == "str" or t.kind == "(" or t.kind == "[" then
			return true
		end

		return t.kind == "sym" and not KEYWORDS[t.value] and t.value ~= "_"
	end

	local function parseAtom(): any
		const t = cur()

		if t.kind == "int" then
			advance()
			return { k = "int", n = t.value, at = at(t) }
		elseif t.kind == "str" then
			advance()
			return { k = "str", bytes = t.value, at = at(t) }
		elseif t.kind == "(" then
			advance()
			const saved = sig
			sig = false
			const first = parseExpr()
			local result: any = first

			if cur().kind == "." then
				advance()
				result = { k = "pair", a = first, b = parseExpr(), at = at(t) }
			end

			expectKind(")")
			sig = saved
			return result
		elseif t.kind == "[" then
			advance()
			const saved = sig
			sig = false
			local items: { any } = {}

			while cur().kind ~= "]" do
				if cur().kind == "eof" then
					fail(cur(), "a list is never closed")
				end

				table.insert(items, parseAtom())
			end

			advance()
			sig = saved
			return { k = "list", items = items, at = at(t) }
		elseif t.kind == "sym" then
			if t.value == "~" then
				advance()
				return { k = "nil", at = at(t) }
			end

			if KEYWORDS[t.value] then
				fail(t, string.format("%s cannot be used as a value here", t.value))
			end

			if t.value == "_" then
				fail(t, "_ is only a pattern, and cannot be used as a value")
			end

			advance()
			return { k = "name", name = t.value, at = at(t) }
		end

		fail(t, "expected a value here")
		return nil
	end

	local function parseApp(): any
		const head = parseAtom()
		local args: { any } = {}

		while atomStart(cur()) do
			table.insert(args, parseAtom())
		end

		if #args == 0 then
			return head
		end

		return { k = "app", f = head, args = args, at = head.at }
	end

	local function parseFn(): any
		const start = advance()
		local names: { string } = {}

		if cur().kind == "(" then
			advance()
			const saved = sig
			sig = false

			while cur().kind ~= ")" do
				table.insert(names, expectKind("sym").value)
			end

			advance()
			sig = saved
		else
			table.insert(names, expectKind("sym").value)
		end

		if #names == 0 then
			fail(start, "fn needs at least one parameter")
		end

		return { k = "fn", names = names, body = parseExpr(), at = at(start) }
	end

	local function parseLet(): any
		const start = advance()
		const nameTok = expectKind("sym")

		if KEYWORDS[nameTok.value] or nameTok.value == "_" or isCapital(nameTok.value) then
			fail(nameTok, string.format("%s cannot be bound by let", nameTok.value))
		end

		expectSym("=")
		const value = parseExpr()
		expectSym("in")
		return {
			k = "let",
			name = nameTok.value,
			value = value,
			body = parseExpr(),
			rec = start.value == "letrec",
			at = at(start),
		}
	end

	local function parseIf(): any
		const start = advance()
		const c = parseAtom()
		const t = parseAtom()
		const e = parseAtom()
		return { k = "if", c = c, t = t, e = e, at = at(start) }
	end

	local function parsePattern(): any
		const t = cur()

		if t.kind ~= "sym" then
			fail(t, "expected a pattern here")
		end

		if t.value == "_" then
			advance()
			return { k = "wild", at = at(t) }
		end

		if isCapital(t.value) then
			advance()
			local bind: string? = nil
			const nxt = cur()

			if nxt.kind == "sym" and nxt.value == "_" then
				advance()
			elseif nxt.kind == "sym" and not isCapital(nxt.value) and not KEYWORDS[nxt.value] then
				advance()
				bind = nxt.value
			end

			return { k = "con", name = t.value, bind = bind, at = at(t) }
		end

		advance()
		return { k = "bind", name = t.value, at = at(t) }
	end

	local function parseMatch(): any
		const start = advance()
		const scrut = parseExpr()
		expectKind("{")

		if toks[pos].kind ~= "NL" then
			fail(toks[pos], "a match needs a newline after {, before its first arm")
		end

		const saved = sig
		sig = true
		local arms: { any } = {}

		while true do
			while toks[pos].kind == "NL" do
				pos += 1
			end

			if toks[pos].kind == "}" then
				break
			end

			const armStart = toks[pos]
			const pat = parsePattern()
			expectKind("->")
			const body = parseExpr()
			table.insert(arms, { pat = pat, body = body, at = at(armStart) })

			if toks[pos].kind ~= "NL" and toks[pos].kind ~= "}" then
				fail(toks[pos], "an arm ends at the end of its line; wrap a longer body in parentheses")
			end
		end

		if #arms == 0 then
			fail(start, "a match needs at least one arm")
		end

		pos += 1
		sig = saved
		return { k = "match", scrut = scrut, arms = arms, at = at(start) }
	end

	local function parseMutual(): any
		const start = advance()
		const saved = sig
		sig = false
		expectKind("(")
		local bindings: { any } = {}

		while cur().kind == "(" do
			advance()
			const nameTok = expectKind("sym")
			const value = parseExpr()
			expectKind(")")
			table.insert(bindings, { name = nameTok.value, value = value, at = at(nameTok) })
		end

		expectKind(")")
		expectSym("in")
		const body = parseExpr()
		sig = saved
		return { k = "mutual", bindings = bindings, body = body, at = at(start) }
	end

	parseExpr = function(): any
		const t = cur()

		if t.kind == "sym" then
			if t.value == "fn" then
				return parseFn()
			elseif t.value == "let" or t.value == "letrec" then
				return parseLet()
			elseif t.value == "if" then
				return parseIf()
			elseif t.value == "match" then
				return parseMatch()
			elseif t.value == "mutual" then
				return parseMutual()
			end
		end

		local e = parseApp()

		if cur().kind == "?" then
			const q = advance()
			return { k = "try", e = e, at = at(q) }
		end

		return e
	end

	-- PROGRAM

	local decls: { any } = {}

	sig = true

	while true do
		while raw().kind == "NL" do
			pos += 1
		end

		if raw().kind == "sym" and raw().value == "type" then
			table.insert(decls, parseTypeDecl())

			if raw().kind ~= "NL" and raw().kind ~= "eof" then
				fail(raw(), "a type declaration ends at the end of its line")
			end
		else
			break
		end
	end

	sig = false
	const expr = parseExpr()

	if cur().kind ~= "eof" then
		fail(cur(), string.format("unexpected %s after the expression", tostring(cur().value or cur().kind)))
	end

	return { decls = decls, expr = expr }
end

return {
	parse = parse,
}
