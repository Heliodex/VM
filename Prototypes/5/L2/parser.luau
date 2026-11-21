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
-- A let or letrec has no keyword between its value and its body. The value ends at the end of its line, and the body starts on the next line. A mutual group ends at the close of its bindings, so its body needs no keyword either.
--
-- The surface tree is the types below. The rawfix form is never written in source: the desugarer makes it for a mutual group.
--
--   Parser.parse(text): Program    raises an error, with the line and column, if the text is not a program

const Lexer = require "./lexer"

export type Pos = { line: number; col: number }
export type Type =
	| { k: "tname"; name: string; at: Pos }
	| { k: "tapp"; name: string; args: { Type }; at: Pos }
	| { k: "tpair"; a: Type; b: Type; at: Pos }
	| { k: "tlist"; item: Type; at: Pos }
	| { k: "tfun"; a: Type; b: Type; at: Pos }
export type Con = { name: string; payload: Type?; at: Pos }
export type TypeDecl = { name: string; params: { string }; cons: { Con }; at: Pos }
export type Pattern =
	| { k: "con"; name: string; bind: string?; at: Pos }
	| { k: "bind"; name: string; at: Pos }
	| { k: "wild"; at: Pos }
export type Expr =
	| { k: "int"; n: number; at: Pos }
	| { k: "str"; bytes: { number }; at: Pos }
	| { k: "nil"; at: Pos }
	| { k: "name"; name: string; at: Pos }
	| { k: "list"; items: { Expr }; at: Pos }
	| { k: "pair"; a: Expr; b: Expr; at: Pos }
	| { k: "app"; f: Expr; args: { Expr }; at: Pos }
	| { k: "fn"; names: { string }; body: Expr; at: Pos }
	| { k: "let"; name: string; value: Expr; body: Expr; rec: boolean; at: Pos }
	| { k: "mutual"; bindings: { Binding }; body: Expr; at: Pos }
	| { k: "if"; c: Expr; t: Expr; e: Expr; at: Pos }
	| { k: "match"; scrut: Expr; arms: { Arm }; at: Pos }
	| { k: "try"; e: Expr; at: Pos }
	| { k: "rawfix"; value: Expr; at: Pos }
	| { k: "check"; e: Expr; test: Test?; expect: string; at: Pos }
	| { k: "untyped"; e: Expr; at: Pos }
export type Arm = { pat: Pattern; body: Expr; at: Pos }
-- What a run-time check looks for, made by the checker from a type. Each test is a shape of value: any accepts every value, and a list or sum that refers to itself uses rec, with its fixdef around the whole test.
export type Test =
	| { kind: "any" }
	| { kind: "nil" }
	| { kind: "int" }
	| { kind: "fn" }
	| { kind: "pin" }
	| { kind: "pair"; a: Test; b: Test }
	| { kind: "list"; item: Test; tail: Test }
	| { kind: "sum"; ctors: { SumTest } }
	| { kind: "rec"; key: string }
	| { kind: "fixdef"; key: string; body: Test }
export type SumTest = { tag: number; payload: Test }
export type Binding = { name: string; value: Expr; at: Pos }
export type Program = { decls: { TypeDecl }; expr: Expr }
const KEYWORDS: { [string]: boolean } = {
	fn = true,
	let = true,
	letrec = true,
	["if"] = true,
	match = true,
	check = true,
	untyped = true,
	type = true,
	cond = true,
}

local function isCapital(name: string): boolean
	return string.match(name, "^%u") ~= nil
end

local function parse(text: string): Program
	const toks = Lexer.tokenize(text)
	local pos = 1
	local sig = false

	local function raw(): Lexer.Token
		return toks[pos]
	end

	-- The next token. Outside a match block, newlines are skipped.
	local function cur(): Lexer.Token
		if not sig then
			while toks[pos].kind == "NL" do
				pos += 1
			end
		end

		return toks[pos]
	end

	local function advance(): Lexer.Token
		const t = cur()
		pos += 1

		return t
	end

	local function fail(t: Lexer.Token, msg: string): never
		error(string.format("line %d, column %d: %s", t.line, t.col, msg), 0)
	end

	local function expectKind(kind: string): Lexer.Token
		const t = cur()

		if t.kind ~= kind then
			fail(t, string.format("expected %s here", kind))
		end

		return advance()
	end

	local function expectSym(value: string): Lexer.Token
		const t = cur()

		if t.kind ~= "sym" or t.value ~= value then
			fail(t, string.format("expected %s here", value))
		end

		return advance()
	end

	-- The text of a symbol or a string token. Only called where the kind has been checked.
	local function word(t: Lexer.Token): string
		return t.value :: string
	end

	local function at(t: Lexer.Token): Pos
		return { line = t.line; col = t.col }
	end

	-- TYPES
	local parseType: () -> Type

	local function typeAtomStart(t: Lexer.Token): boolean
		return t.kind == "sym" and t.value ~= "|" or t.kind == "(" or t.kind == "["
	end

	local function parseTypeAtom(): Type
		const t = cur()

		if t.kind == "sym" then
			advance()

			return { k = "tname"; name = word(t); at = at(t) }
		elseif t.kind == "(" then
			advance()
			const saved = sig
			sig = false
			const first = parseType()
			local result: Type = first

			if cur().kind == "." then
				advance()
				result = { k = "tpair"; a = first; b = parseType(); at = at(t) } :: Type
			end

			expectKind ")"
			sig = saved

			return result
		elseif t.kind == "[" then
			advance()
			const saved = sig
			sig = false
			const item = parseType()
			expectKind "]"
			sig = saved

			return { k = "tlist"; item = item; at = at(t) }
		end

		return fail(t, "expected a type")
	end

	local function parseBaseType(): Type
		const first = parseTypeAtom()

		if first.k == "tname" and isCapital(first.name) then
			local args: { Type } = {}

			while typeAtomStart(cur()) and cur().kind ~= "->" do
				table.insert(args, parseTypeAtom())
			end

			if #args > 0 then
				return { k = "tapp"; name = first.name; args = args; at = first.at }
			end
		end

		return first
	end

	parseType = function(): Type
		const base = parseBaseType()

		if cur().kind == "->" then
			const arrow = advance()

			return { k = "tfun"; a = base; b = parseType(); at = at(arrow) }
		end

		return base
	end

	-- A declaration: type Name params = Con payload | Con payload. The payload is one type atom, if there is one.
	local function parseTypeDecl(): TypeDecl
		const start = advance()
		const nameTok = expectKind "sym"

		if not isCapital(word(nameTok)) then
			fail(nameTok, "a type's name starts with a capital letter")
		end

		local params: { string } = {}

		while cur().kind == "sym" and not isCapital(word(cur())) and word(cur()) ~= "=" do
			table.insert(params, word(advance()))
		end

		expectSym "="
		local cons: { Con } = {}

		while true do
			const conTok = expectKind "sym"

			if not isCapital(word(conTok)) then
				fail(conTok, "a constructor's name starts with a capital letter")
			end

			local payload: Type? = nil

			if typeAtomStart(cur()) then
				payload = parseTypeAtom()
			end

			table.insert(cons, { name = word(conTok); payload = payload; at = at(conTok) })

			if cur().kind == "sym" and word(cur()) == "|" then
				advance()
			else
				break
			end
		end

		return { name = word(nameTok); params = params; cons = cons; at = at(start) }
	end

	-- EXPRESSIONS
	local parseExpr: () -> Expr

	local function atomStart(t: Lexer.Token): boolean
		if t.kind == "int" or t.kind == "str" or t.kind == "(" or t.kind == "[" then
			return true
		end

		return t.kind == "sym" and not KEYWORDS[word(t)] and word(t) ~= "_"
	end

	local function parseAtom(): Expr
		const t = cur()

		if t.kind == "int" then
			advance()

			return { k = "int"; n = t.value :: number; at = at(t) }
		elseif t.kind == "str" then
			advance()

			return { k = "str"; bytes = t.value :: { number }; at = at(t) }
		elseif t.kind == "(" then
			advance()
			const saved = sig
			sig = false
			const first = parseExpr()
			local result: Expr = first

			if cur().kind == "." then
				advance()
				result = { k = "pair"; a = first; b = parseExpr(); at = at(t) } :: Expr
			end

			expectKind ")"
			sig = saved

			return result
		elseif t.kind == "[" then
			advance()
			const saved = sig
			sig = false
			local items: { Expr } = {}

			while cur().kind ~= "]" do
				if cur().kind == "eof" then
					fail(cur(), "a list is never closed")
				end

				table.insert(items, parseAtom())
			end

			advance()
			sig = saved

			return { k = "list"; items = items; at = at(t) }
		elseif t.kind == "sym" then
			if word(t) == "~" then
				advance()

				return { k = "nil"; at = at(t) }
			end

			if KEYWORDS[word(t)] then
				fail(t, string.format("%s cannot be used as a value here", word(t)))
			end

			if word(t) == "_" then
				fail(t, "_ is only a pattern, and cannot be used as a value")
			end

			advance()

			return { k = "name"; name = word(t); at = at(t) }
		end

		return fail(t, "expected a value here")
	end

	local function parseApp(): Expr
		const head = parseAtom()
		local args: { Expr } = {}

		while atomStart(cur()) do
			table.insert(args, parseAtom())
		end

		if #args == 0 then
			return head
		end

		return { k = "app"; f = head; args = args; at = head.at }
	end

	local function parseFn(): Expr
		const start = advance()
		local names: { string } = {}

		if cur().kind == "(" then
			advance()
			const saved = sig
			sig = false

			while cur().kind ~= ")" do
				table.insert(names, word(expectKind "sym"))
			end

			advance()
			sig = saved
		else
			table.insert(names, word(expectKind "sym"))
		end

		if #names == 0 then
			fail(start, "fn needs at least one parameter")
		end

		-- The body starts on the line after the parameters, so a function's parameters and body are always on different lines.
		if raw().kind ~= "NL" then
			fail(raw(), "a function's body starts on the line after its parameters")
		end

		while raw().kind == "NL" do
			pos += 1
		end

		return { k = "fn"; names = names; body = parseExpr(); at = at(start) }
	end

	-- let { ... } and letrec { ... }: a block of bindings, then a body. Each binding is name = value, and the items are separated by newlines, as the arms of a match are. The block is sugar: let { is a chain of lets, and letrec { is a mutual group, so the parser builds those.
	local function parseBlock(start: Lexer.Token): Expr
		expectKind "{"

		if toks[pos].kind ~= "NL" then
			fail(toks[pos], "a block needs a newline after {, before its first item")
		end

		const rec = word(start) == "letrec"
		const saved = sig
		sig = true
		local bindings: { Binding } = {}
		local body: Expr? = nil

		while true do
			while toks[pos].kind == "NL" do
				pos += 1
			end

			if toks[pos].kind == "}" then
				break
			end

			if body ~= nil then
				fail(toks[pos], "a block's body is its last item")
			end

			if toks[pos].kind == "sym" and toks[pos + 1].kind == "sym" and toks[pos + 1].value == "=" then
				const nameTok = expectKind "sym"

				if KEYWORDS[word(nameTok)] or word(nameTok) == "_" or isCapital(word(nameTok)) then
					fail(nameTok, string.format("%s cannot be bound by let", word(nameTok)))
				end

				expectSym "="
				const value = parseExpr()

				if toks[pos].kind ~= "NL" then
					fail(toks[pos], "a block binding ends at the end of its line; wrap a longer value in parentheses")
				end

				if rec and value.k ~= "fn" then
					fail(nameTok, "a letrec block binds fns, so the functions can call each other")
				end

				table.insert(bindings, { name = word(nameTok); value = value; at = at(nameTok) })
			else
				body = parseExpr()

				if toks[pos].kind ~= "NL" and toks[pos].kind ~= "}" then
					fail(toks[pos], "a block's body ends at the end of its line; wrap a longer body in parentheses")
				end
			end
		end

		if body == nil then
			fail(toks[pos], "a block needs a body after its bindings")
		end

		const bodyExpr = body :: Expr
		pos += 1
		sig = saved

		if rec then
			return { k = "mutual"; bindings = bindings; body = bodyExpr; at = at(start) }
		end

		local result = bodyExpr

		for i = #bindings, 1, -1 do
			const b = bindings[i]
			result = { k = "let"; name = b.name; value = b.value; body = result; rec = false; at = b.at }
		end

		return result
	end

	-- cond { test -> body ... _ -> body }: clauses tried in order, the first whose test is nonzero gives its body. The last clause is _, the catch-all. It is written as nested ifs.
	local function parseCond(): Expr
		const start = advance()
		expectKind "{"

		if toks[pos].kind ~= "NL" then
			fail(toks[pos], "a cond needs a newline after {, before its first clause")
		end

		const saved = sig
		sig = true
		local tests: { Expr? } = {}
		local bodies: { Expr } = {}
		local ats: { Pos } = {}
		local sawCatchAll = false

		while true do
			while toks[pos].kind == "NL" do
				pos += 1
			end

			if toks[pos].kind == "}" then
				break
			end

			if sawCatchAll then
				fail(toks[pos], "the _ clause of a cond is its last clause")
			end

			const clauseStart = toks[pos]
			local test: Expr? = nil

			if toks[pos].kind == "sym" and word(toks[pos]) == "_" then
				advance()
				expectKind "->"
				sawCatchAll = true
			else
				test = parseExpr()
				expectKind "->"
			end

			const body = parseExpr()
			table.insert(tests, test)
			table.insert(bodies, body)
			table.insert(ats, at(clauseStart))

			if toks[pos].kind ~= "NL" and toks[pos].kind ~= "}" then
				fail(toks[pos], "a cond clause ends at the end of its line; wrap a longer body in parentheses")
			end
		end

		if not sawCatchAll then
			fail(start, "a cond needs a _ clause as its last clause")
		end

		pos += 1
		sig = saved
		local result: Expr = bodies[#bodies]

		for i = #bodies - 1, 1, -1 do
			result = { k = "if"; c = tests[i] :: Expr; t = bodies[i]; e = result; at = ats[i] }
		end

		return result
	end

	local function parseLet(): Expr
		const start = advance()

		if cur().kind == "{" then
			return parseBlock(start)
		end

		const nameTok = expectKind "sym"

		if KEYWORDS[word(nameTok)] or word(nameTok) == "_" or isCapital(word(nameTok)) then
			fail(nameTok, string.format("%s cannot be bound by let", word(nameTok)))
		end

		expectSym "="

		-- Inside a match arm a newline ends the arm, so a let there would have no body to read. It needs parentheses.
		if sig then
			fail(start, "a let in a match arm needs parentheses around it")
		end

		-- The value ends at the end of its line, so a longer value is wrapped in parentheses. The body is on the next line.
		sig = true
		const value = parseExpr()
		sig = false

		if toks[pos].kind ~= "NL" then
			fail(toks[pos], "a let value ends at the end of its line; wrap a longer value in parentheses")
		end

		while toks[pos].kind == "NL" do
			pos += 1
		end

		return {
			k = "let",
			name = word(nameTok),
			value = value,
			body = parseExpr(),
			rec = word(start) == "letrec",
			at = at(start),
		}
	end

	local function parseIf(): Expr
		const start = advance()
		const c = parseAtom()
		const t = parseAtom()
		const e = parseAtom()

		return { k = "if"; c = c; t = t; e = e; at = at(start) }
	end

	local function parsePattern(): Pattern
		const t = cur()

		if t.kind ~= "sym" then
			fail(t, "expected a pattern here")
		end

		if word(t) == "_" then
			advance()

			return { k = "wild"; at = at(t) }
		end

		if isCapital(word(t)) then
			advance()
			local bind: string? = nil
			const nxt = cur()

			if nxt.kind == "sym" and word(nxt) == "_" then
				advance()
			elseif nxt.kind == "sym" and not isCapital(word(nxt)) and not KEYWORDS[word(nxt)] then
				advance()
				bind = word(nxt)
			end

			return { k = "con"; name = word(t); bind = bind; at = at(t) }
		end

		advance()

		return { k = "bind"; name = word(t); at = at(t) }
	end

	local function parseMatch(): Expr
		const start = advance()
		const scrut = parseExpr()
		expectKind "{"

		if toks[pos].kind ~= "NL" then
			fail(toks[pos], "a match needs a newline after {, before its first arm")
		end

		const saved = sig
		sig = true
		local arms: { Arm } = {}

		while true do
			while toks[pos].kind == "NL" do
				pos += 1
			end

			if toks[pos].kind == "}" then
				break
			end

			const armStart = toks[pos]
			const pat = parsePattern()
			expectKind "->"
			const body = parseExpr()
			table.insert(arms, { pat = pat; body = body; at = at(armStart) })

			if toks[pos].kind ~= "NL" and toks[pos].kind ~= "}" then
				fail(toks[pos], "an arm ends at the end of its line; wrap a longer body in parentheses")
			end
		end

		if #arms == 0 then
			fail(start, "a match needs at least one arm")
		end

		pos += 1
		sig = saved

		return { k = "match"; scrut = scrut; arms = arms; at = at(start) }
	end

	-- check e: the value of e, tested when it is used at a type. The operand is an atom, so an application needs parentheses.
	local function parseCheck(): Expr
		const start = advance()
		const e = parseAtom()

		return { k = "check"; e = e; test = nil; expect = ""; at = at(start) }
	end

	-- untyped e: the value of e, given the type Dyn. A Dyn value is used at a type only through check.
	local function parseUntyped(): Expr
		const start = advance()
		const e = parseAtom()

		return { k = "untyped"; e = e; at = at(start) }
	end

	parseExpr = function(): Expr
		const t = cur()

		if t.kind == "sym" then
			if word(t) == "fn" then
				return parseFn()
			elseif word(t) == "let" or word(t) == "letrec" then
				return parseLet()
			elseif word(t) == "if" then
				return parseIf()
			elseif word(t) == "match" then
				return parseMatch()
			elseif word(t) == "check" then
				return parseCheck()
			elseif word(t) == "untyped" then
				return parseUntyped()
			elseif word(t) == "cond" then
				return parseCond()
			end
		end

		const e = parseApp()

		if cur().kind == "?" then
			const q = advance()

			return { k = "try"; e = e; at = at(q) }
		end

		return e
	end
	-- PROGRAM
	local decls: { TypeDecl } = {}
	sig = true

	while true do
		while raw().kind == "NL" do
			pos += 1
		end

		if raw().kind == "sym" and word(raw()) == "type" then
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

	return { decls = decls; expr = expr }
end

return {
	parse = parse,
}
