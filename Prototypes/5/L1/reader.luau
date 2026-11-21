--!strict
-- THE READER
--
-- Turns the text of a program into an Expr, which vm.luau then runs. The syntax is s-expressions, with ; starting a comment that runs to the end of the line.
--
--   42                 an integer, negative ones too
--   ~                  nil
--   x                  a variable, which must be bound by a fn around it
--   (fn x body)       a function of x; (fn (x y) body) is the same as (fn x (fn y body)).
--                      A fn has one parameter part, a name or a list of names, so (fn x y body) is refused
--   (f a b)            application, curried: (f a b) is ((f a) b)
--   [a b]              a pair
--   [a b c]            the same as [a [b c]]: the last item is the tail, so a list ends in ~, as [1 2 ~]
--   "abc"              a string: a list of its bytes, so "" is nil. Escapes are \" \\ \n \t and \0
--   (list a b c)       a proper list of a, b and c
--   (head e), (tail e)
--   (if c t e)         evaluates t if c is nonzero, otherwise e
--   (let x e body)     binds x to e in body. It is sugar for ((fn x body) e), so x is not in scope in e
--   (letrec f (fn ...) body)
--                      binds f to a recursive function, whose definition can call f. It is sugar for let, with fix
--   (mutual ((f (fn ...)) (g (fn ...))) body)
--                      binds f and g to functions that can call each other, and each other's names. It is sugar for one fixed point that takes a member and an argument
--   (pin e), (force e)
--   (fix f)            the fixed point of f, where f is (fn rec (fn ...)) and rec is the function itself
--   (+ a b), (- a b), (* a b), (< a b), (= a b)
--                      add, subtract, multiply, less-than, equal
--   (/ a b), (% a b)
--                      floored division and remainder: a = b * q + r, with r taking the sign of b
--   (@ a)           the kind of a: 0 integer, 1 nil, 2 cell, 3 function, 4 pin
--   (? a)              shorthand for (= (@ a) 1), whether a is nil
--
-- The words and operators above are reserved and cannot be used as variables. Errors are raised as strings that begin with the line number.
--
-- Reader.parse(source) reads exactly one expression and raises an error if there is anything after it.
--
-- The reader turns each variable into its index, so the machine never sees a name. A name that is not bound is an error here.

const Primitives = require "../interpreter/primitives"
const M = require "../interpreter/vm"

type Token = {
	text: string,
	line: number,
	-- set for a string literal, to its bytes
	codes: { number }?,
}
-- An expression as written, before it is compiled. Groups keep their line for error messages.
type Node =
	| { kind: "int"; value: number; line: number }
	| { kind: "str"; codes: { number }; line: number }
	| { kind: "sym"; name: string; line: number }
	| { kind: "list"; items: { Node }; line: number }
	| { kind: "pair"; items: { Node }; line: number }
-- The primitives, by the symbol that writes them, from the table in interpreter/primitives.luau.
const PRIMITIVES = Primitives.BY_SYMBOL
-- Forms that are primitives: @ (kind) is one, and ? is a shorthand built from it.
const KIND_FORMS: { [string]: number } = {
	["?"] = 1,
}
const UNARY_FORMS: { [string]: number } = {
	head = 1,
	tail = 1,
	pin = 1,
	force = 1,
	fix = 1,
}

const function reserved(name: string): boolean
	return false
		or name == "fn"
		or name == "if"
		or name == "let"
		or name == "letrec"
		or name == "mutual"
		or name == "list"
		or name == "~"
		or PRIMITIVES[name] ~= nil
		or KIND_FORMS[name] ~= nil
		or UNARY_FORMS[name] ~= nil
end

const function fail(line: number, message: string): never
	return error(string.format("line %d: %s", line, message), 0)
end

-- The escapes a string literal may use, by the character after the backslash, and the byte each one is.
const ESCAPES: { [string]: number } = {
	['"'] = 34,
	["\\"] = 92,
	n = 10,
	t = 9,
	["0"] = 0,
}

-- Reads the string literal whose opening quote is at position start. Returns its bytes and the position after the closing quote. A string is a list of bytes, so a character above 255 cannot be written in one.
local function scanString(source: string, start: number, line: number): ({ number }, number)
	local codes: { number } = {}
	local j = start + 1

	while true do
		if j > #source then
			fail(line, "a string is never closed")
		end

		const ch = string.sub(source, j, j)

		if ch == '"' then
			return codes, j + 1
		elseif ch == "\n" then
			fail(line, "a string cannot run over a line")
		elseif ch == "\\" then
			const escape = string.sub(source, j + 1, j + 1)
			const code = ESCAPES[escape]

			if code == nil then
				fail(line, "unknown escape \\" .. escape)
			end

			table.insert(codes, code)
			j += 2
		else
			table.insert(codes, string.byte(ch) :: number)
			j += 1
		end
	end
end

const function tokenize(source: string): { Token }
	local tokens: { Token } = {}
	local line = 1
	local i = 1

	while i <= #source do
		const c = string.sub(source, i, i)

		if c == "\n" then
			line += 1
			i += 1
		elseif string.match(c, "%s") then
			i += 1
		elseif c == ";" then
			-- A comment runs to the end of the line, and the newline is left for the loop above.
			i = string.find(source, "\n", i, true) or #source + 1
		elseif c == "(" or c == ")" or c == "[" or c == "]" then
			table.insert(tokens, { text = c; line = line })
			i += 1
		elseif c == '"' then
			const codes, after = scanString(source, i, line)
			table.insert(tokens, { text = string.sub(source, i, after - 1); line = line; codes = codes })
			i = after
		else
			const text: string = string.match(source, "^[^%s()%[%];]+", i) :: string
			table.insert(tokens, { text = text; line = line })
			i += #text
		end
	end

	return tokens
end

-- Reads the items of a group up to its closing token, and returns them with the position after the closing token.
local readNode: (tokens: { Token }, pos: number) -> (Node, number)

local function readItems(tokens: { Token }, pos: number, opener: Token, closer: string): ({ Node }, number)
	local items: { Node } = {}
	local p = pos

	while true do
		if p > #tokens then
			fail(opener.line, `{opener.text} is never closed`)
		end

		if tokens[p].text == closer then
			return items, p + 1
		end

		local node: Node
		node, p = readNode(tokens, p)
		table.insert(items, node)
	end
end

-- Reads one node starting at position pos, and returns it with the position after it.
readNode = function(tokens: { Token }, pos: number): (Node, number)
	if pos > #tokens then
		fail(tokens[#tokens].line, "the program ends before an expression is complete")
	end

	const token = tokens[pos]

	if token.text == ")" or token.text == "]" then
		fail(token.line, `unexpected {token.text}`)
	end

	if token.codes then
		return { kind = "str"; codes = token.codes; line = token.line }, pos + 1
	end

	if token.text == "(" then
		const items, after = readItems(tokens, pos + 1, token, ")")

		return { kind = "list"; items = items; line = token.line }, after
	end

	if token.text == "[" then
		const items, after = readItems(tokens, pos + 1, token, "]")

		return { kind = "pair"; items = items; line = token.line }, after
	end

	const digits = string.match(token.text, "^%-?%d+$")

	if digits then
		const value = tonumber(digits) :: number

		if value > M.MAX_INTEGER or value < -M.MAX_INTEGER then
			fail(token.line, `integer {digits} is out of range`)
		end

		return { kind = "int"; value = value; line = token.line }, pos + 1
	end

	return { kind = "sym"; name = token.text; line = token.line }, pos + 1
end

-- The index of a name in the scope: 0 for the innermost binder, counting outwards. The scope lists the names innermost first.
const function resolve(name: string, scope: { string }, line: number): number
	for i = 1, #scope do
		if scope[i] == name then
			return i - 1
		end
	end

	return fail(line, `{name} is not bound`)
end

-- Compiles a node to an expression, given the names of the binders around it, innermost first. Forms are recognised by their first word.
local compile: (Node, { string }) -> M.Expr
type SymNode = { kind: "sym"; name: string; line: number }
type ListNode = { kind: "list"; items: { Node }; line: number }

const function symNode(name: string, line: number): Node
	return { kind = "sym"; name = name; line = line }
end

const function intNode(value: number, line: number): Node
	return { kind = "int"; value = value; line = line }
end

const function listNode(items: { Node }, line: number): Node
	return { kind = "list"; items = items; line = line }
end

-- The function that calls member index of the group g with one argument: (fn " y" ((g index) " y")). The names begin with a space, which no source name can contain, so they cannot clash with the program's names.
const function member(g: string, index: number, line: number): Node
	const call = listNode({ listNode({ symNode(g, line); intNode(index, line) }, line); symNode(" y", line) }, line)

	return listNode({ symNode("fn", line); symNode(" y", line); call }, line)
end

-- The nodes for a mutual group. Every member shares one fixed point, dispatch, which takes a tag and then an argument. Member i has tag i - 1, and its body is run inside lets that bind each group name to a call through dispatch. The body is run with the names bound to calls through the fixed point. The result is the same as writing each function out with its names in scope, but no name is bound to a function that is not in the group.
const function mutualNode(names: { string }, defs: { Node }, body: Node, line: number): Node
	const n = #names
	local branches: { Node } = {}

	for i = 1, n do
		local inner: Node = listNode({ defs[i]; symNode(" x", line) }, line)

		for k = n, 1, -1 do
			inner = listNode({ symNode("let", line); symNode(names[k], line); member(" self", k - 1, line); inner }, line)
		end

		branches[i] = inner
	end

	local chain: Node = branches[n]

	for i = n - 1, 1, -1 do
		const test = listNode({ symNode("=", line); symNode(" tag", line); intNode(i - 1, line) }, line)
		chain = listNode({ symNode("if", line); test; branches[i]; chain }, line)
	end

	const dispatch = listNode(
		{
			symNode("fn", line),
			symNode(" self", line),
			listNode(
				{
					symNode("fn", line),
					symNode(" tag", line),
					listNode({ symNode("fn", line); symNode(" x", line); chain }, line),
				},
				line
			),
		},
		line
	)
	local inner: Node = body

	for k = n, 1, -1 do
		inner = listNode({ symNode("let", line); symNode(names[k], line); member(" group", k - 1, line); inner }, line)
	end

	return listNode(
		{
			symNode("let", line),
			symNode(" group", line),
			listNode({ symNode("fix", line); dispatch }, line),
			inner,
		},
		line
	)
end

local function compileForm(name: string, node: { kind: "list"; items: { Node }; line: number }, scope: { string }): M.Expr
	const items = node.items
	const args = #items - 1

	local function arity(expected: number)
		if args ~= expected then
			fail(
				node.line,
				string.format(
					"%s takes %d argument%s, but was given %d",
					name,
					expected,
					if expected == 1 then
						""
					else
						"s",
					args
				)
			)
		end
	end

	if name == "fn" then
		if args < 2 then
			fail(node.line, "fn needs a parameter and a body")
		end

		-- A fn has one parameter part and one body: (fn (x y) body) for a list of names, or (fn x body) for one name.
		if args > 2 then
			fail(node.line, "fn takes a list of parameters, (fn (x y) body), or one name, (fn x body)")
		end

		local names: { string } = {}
		const param = items[2]

		if param.kind == "sym" then
			table.insert(names, param.name)
		elseif param.kind == "list" then
			for _, inner in param.items do
				if inner.kind == "sym" then
					table.insert(names, inner.name)
				else
					fail(inner.line, "a fn parameter must be a name")
				end
			end
		else
			fail(param.line, "a fn parameter must be a name")
		end

		if #names == 0 then
			fail(node.line, "fn needs at least one parameter")
		end

		for _, name in names do
			if reserved(name) then
				fail(node.line, `{name} is a reserved word and cannot be used as a variable`)
			end
		end

		-- The last parameter is the innermost binder, so it goes at the front of the scope last.
		local inner = table.clone(scope)

		for i = 1, #names do
			table.insert(inner, 1, names[i])
		end

		local body = compile(items[#items], inner)

		for _ = 1, #names do
			body = M.lam(body)
		end

		return body
	end

	if name == "if" then
		arity(3)

		return M.ite(compile(items[2], scope), compile(items[3], scope), compile(items[4], scope))
	end

	if name == "let" then
		arity(3)
		const binder = items[2]

		if binder.kind ~= "sym" then
			fail(binder.line, "let binds a name")
		end

		-- The value is compiled in the current scope, and the body with the name added.
		const value = compile(items[3], scope)
		const inner = table.clone(scope)
		table.insert(inner, 1, (binder :: { kind: "sym"; name: string; line: number }).name)

		return M.app(M.lam(compile(items[4], inner)), value)
	end

	if name == "letrec" then
		arity(3)
		const binder = items[2]
		const definition = items[3]

		if binder.kind ~= "sym" then
			fail(binder.line, "letrec binds a name")
		end

		if false
			or definition.kind ~= "list"
			or #definition.items == 0
			or definition.items[1].kind ~= "sym"
			or (definition.items[1] :: { kind: "sym"; name: string; line: number }).name ~= "fn" then
			fail(definition.line, "letrec binds a fn, so the function can call itself")
		end

		-- The name is in scope in the definition and in the body. The definition is wrapped in fix, whose outer lambda binds the name to the function itself.
		const name_ = (binder :: { kind: "sym"; name: string; line: number }).name
		const inner = table.clone(scope)
		table.insert(inner, 1, name_)
		const recursive = M.app(M.fix, M.lam(compile(definition, inner)))

		return M.app(M.lam(compile(items[4], inner)), recursive)
	end

	if name == "mutual" then
		arity(2)
		const bindings = items[2]

		if bindings.kind ~= "list" then
			fail(bindings.line, "mutual binds a list of (name fn) pairs")
		end

		const bindingList = (bindings :: ListNode).items

		if #bindingList == 0 then
			fail(bindings.line, "mutual binds a list of (name fn) pairs")
		end

		local names: { string } = {}
		local defs: { Node } = {}

		for _, binding in bindingList do
			if binding.kind ~= "list" then
				fail(binding.line, "each mutual binding is (name fn)")
			end

			const parts = (binding :: ListNode).items

			if #parts ~= 2 or parts[1].kind ~= "sym" then
				fail(binding.line, "each mutual binding is (name fn)")
			end

			const def = parts[2]

			if def.kind ~= "list" or #def.items < 2 or def.items[1].kind ~= "sym" or (def.items[1] :: SymNode).name ~= "fn" then
				fail(def.line, "mutual binds fns, so the functions can call each other")
			end

			table.insert(names, (parts[1] :: SymNode).name)
			table.insert(defs, def)
		end

		return compile(mutualNode(names, defs, items[3], node.line), scope)
	end

	if name == "list" then
		local elements: { M.Expr } = {}

		for i = 2, #items do
			table.insert(elements, compile(items[i], scope))
		end

		return M.list(elements)
	end

	if name == "@" then
		arity(1)

		return M.prim(Primitives.TAG.kind, compile(items[2], scope))
	end

	if name == "?" then
		arity(1)

		return M.prim(Primitives.TAG.eq, M.prim(Primitives.TAG.kind, compile(items[2], scope)), M.int(1))
	end

	if PRIMITIVES[name] ~= nil then
		const primitive = PRIMITIVES[name]
		arity(primitive.arity)

		if primitive.arity == 1 then
			return M.prim(primitive.tag, compile(items[2], scope))
		end

		return M.prim(primitive.tag, compile(items[2], scope), compile(items[3], scope))
	end

	if UNARY_FORMS[name] ~= nil then
		arity(1)
		const inner = compile(items[2], scope)

		if name == "head" then
			return M.head(inner)
		elseif name == "tail" then
			return M.tail(inner)
		elseif name == "pin" then
			return M.pin(inner)
		elseif name == "force" then
			return M.force(inner)
		else
			return M.app(M.fix, inner)
		end
	end

	-- Not a form, so it is an application of the first item to the rest, one at a time.
	if args == 0 then
		fail(node.line, "a call needs at least one argument")
	end

	local e = compile(items[1], scope)

	for i = 2, #items do
		e = M.app(e, compile(items[i], scope))
	end

	return e
end

compile = function(node: Node, scope: { string }): M.Expr
	if node.kind == "int" then
		return M.int(node.value)
	end

	if node.kind == "str" then
		-- A string is the list of its bytes, so the empty string is nil.
		local elements: { M.Expr } = {}

		for _, code in node.codes do
			table.insert(elements, M.int(code))
		end

		return M.list(elements)
	end

	if node.kind == "sym" then
		if node.name == "~" then
			return M.nilv()
		end

		if reserved(node.name) then
			fail(node.line, `{node.name} is a reserved word and cannot be used as a variable`)
		end

		return M.var(resolve(node.name, scope, node.line))
	end

	const items = node.items

	if node.kind == "pair" then
		if #items < 2 then
			fail(node.line, `a pair takes at least two items, but was given {#items}`)
		end

		-- The last item is the tail, and the others are heads, so [a b c] is [a [b c]].
		local e = compile(items[#items], scope)

		for i = #items - 1, 1, -1 do
			e = M.cell(compile(items[i], scope), e)
		end

		return e
	end

	if #items == 0 then
		fail(node.line, "() is not an expression, and nil is written ~")
	end

	const head = items[1]

	if head.kind == "sym" and reserved(head.name) then
		return compileForm(head.name, node, scope)
	end

	return compileForm("", node, scope)
end

const function parse(source: string): M.Expr
	const tokens = tokenize(source)

	if #tokens == 0 then
		error("line 1: the program is empty", 0)
	end

	const node, after = readNode(tokens, 1)

	if after <= #tokens then
		fail(tokens[after].line, "there is more text after the expression")
	end

	return compile(node, {})
end

-- Reads a program in which each names[i] is bound to values[i], an expression that is closed, so it does not refer to any of the names. The first name is the outermost binding. This is how a program file's imports are bound.
const function parseWith(source: string, names: { string }, values: { M.Expr }): M.Expr
	const tokens = tokenize(source)

	if #tokens == 0 then
		error("line 1: the program is empty", 0)
	end

	const node, after = readNode(tokens, 1)

	if after <= #tokens then
		fail(tokens[after].line, "there is more text after the expression")
	end

	-- The scope lists the names innermost first, so the last name is the innermost.
	local scope: { string } = {}

	for i = 1, #names do
		table.insert(scope, 1, names[i])
	end

	local body = compile(node, scope)

	for i = #names, 1, -1 do
		body = M.app(M.lam(body), values[i])
	end

	return body
end

return {
	parse = parse,
	parseWith = parseWith,
	scanString = scanString,
	isReserved = reserved,
}
