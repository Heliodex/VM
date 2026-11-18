--!strict
-- THE READER
--
-- Turns the text of a program into an Expr, which vm.luau then runs. The syntax is s-expressions, with ; starting a comment that runs to the end of the line.
--
--   42                 an integer, negative ones too
--   ~                  nil
--   x                  a variable, which must be bound by a lam around it
--   (lam x body)       a function of x; (lam (x y) body) is the same as (lam x (lam y body))
--   (f a b)            application, curried: (f a b) is ((f a) b)
--   [a b]              a pair
--   (list a b c)       a proper list of a, b and c
--   (head e), (tail e)
--   (if c t e)         evaluates t if c is nonzero, otherwise e
--   (let x e body)     binds x to e in body. It is sugar for ((lam x body) e), so x is not in scope in e
--   (letrec f (lam ...) body)
--                      binds f to a recursive function, whose definition can call f. It is sugar for let, with fix
--   (pin e), (force e)
--   (fix f)            the fixed point of f, where f is (lam rec (lam ...)) and rec is the function itself
--   (+ a b), (- a b), (* a b), (< a b), (= a b)
--                      add, subtract, multiply, less-than, equal
--   (kind a)           the kind of a: 0 integer, 1 nil, 2 cell, 3 function, 4 pin
--   (? a)              shorthand for (= (kind a) 1), whether a is nil
--
-- The words and operators above are reserved and cannot be used as variables. Errors are raised as strings that begin with the line number.
--
-- Reader.parse(source) reads exactly one expression and raises an error if there is anything after it.
--
-- The reader turns each variable into its index, so the machine never sees a name. A name that is not bound is an error here.

const M = require "./vm"

type Token = {
	text: string,
	line: number,
}

-- An expression as written, before it is compiled. Groups keep their line for error messages.
type Node =
	| { kind: "int", value: number, line: number }
	| { kind: "sym", name: string, line: number }
	| { kind: "list", items: { Node }, line: number }
	| { kind: "pair", items: { Node }, line: number }

-- The primitives, by the symbol that writes them, with the primitive each one builds and its arity.
const PRIMITIVES: { [string]: { op: string, arity: number } } = {
	["+"] = { op = "add", arity = 2 },
	["-"] = { op = "sub", arity = 2 },
	["*"] = { op = "mul", arity = 2 },
	["<"] = { op = "lt", arity = 2 },
	["="] = { op = "eq", arity = 2 },
}

-- Forms that are primitives: kind is one, and ? is a shorthand built from it.
const KIND_FORMS: { [string]: number } = {
	kind = 1,
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
	return name == "lam"
		or name == "if"
		or name == "let"
		or name == "letrec"
		or name == "list"
		or name == "~"
		or PRIMITIVES[name] ~= nil
		or KIND_FORMS[name] ~= nil
		or UNARY_FORMS[name] ~= nil
end

const function fail(
	line: number,
	message: string
): never
	return error(string.format("line %d: %s", line, message), 0)
end

const function tokenize(
	source: string
): { Token }
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
			i = string.find(source, "\n", i, true) or (#source + 1)
		elseif c == "(" or c == ")" or c == "[" or c == "]" then
			table.insert(tokens, { text = c, line = line })
			i += 1
		else
			const text: string = string.match(source, "^[^%s()%[%];]+", i) :: string
			table.insert(tokens, { text = text, line = line })
			i += #text
		end
	end

	return tokens
end

-- Reads the items of a group up to its closing token, and returns them with the position after the closing token.
local readNode: (tokens: { Token }, pos: number) -> (Node, number)

local function readItems(
	tokens: { Token },
	pos: number,
	opener: Token,
	closer: string
): ({ Node }, number)
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
readNode = function(
	tokens: { Token },
	pos: number
): (Node, number)
	if pos > #tokens then
		fail(tokens[#tokens].line, "the program ends before an expression is complete")
	end

	const token = tokens[pos]

	if token.text == ")" or token.text == "]" then
		fail(token.line, `unexpected {token.text}`)
	end

	if token.text == "(" then
		const items, after = readItems(tokens, pos + 1, token, ")")
		return { kind = "list", items = items, line = token.line }, after
	end

	if token.text == "[" then
		const items, after = readItems(tokens, pos + 1, token, "]")
		return { kind = "pair", items = items, line = token.line }, after
	end

	const digits = string.match(token.text, "^%-?%d+$")

	if digits then
		return { kind = "int", value = tonumber(digits) :: number, line = token.line }, pos + 1
	end

	return { kind = "sym", name = token.text, line = token.line }, pos + 1
end

-- The index of a name in the scope: 0 for the innermost binder, counting outwards. The scope lists the names innermost first.
const function resolve(
	name: string,
	scope: { string },
	line: number
): number
	for i = 1, #scope do
		if scope[i] == name then
			return i - 1
		end
	end

	return fail(line, `{name} is not bound`)
end

-- Compiles a node to an expression, given the names of the binders around it, innermost first. Forms are recognised by their first word.
local compile: (Node, { string }) -> M.Expr

local function compileForm(
	name: string,
	node: { kind: "list", items: { Node }, line: number },
	scope: { string }
): M.Expr
	const items = node.items
	const args = #items - 1

	local function arity(expected: number)
		if args ~= expected then
			fail(node.line, string.format("%s takes %d argument%s, but was given %d", name, expected, if expected == 1 then "" else "s", args))
		end
	end

	if name == "lam" then
		if args < 2 then
			fail(node.line, "lam needs a parameter and a body")
		end

		-- The body is the last item. The parameters are the items between, either names or lists of names.
		local names: { string } = {}
		for i = 2, #items - 1 do
			const param = items[i]

			if param.kind == "sym" then
				table.insert(names, param.name)
			elseif param.kind == "list" then
				for _, inner in param.items do
					if inner.kind == "sym" then
						table.insert(names, inner.name)
					else
						fail(inner.line, "a lam parameter must be a name")
					end
				end
			else
				fail(param.line, "a lam parameter must be a name")
			end
		end

		if #names == 0 then
			fail(node.line, "lam needs at least one parameter")
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
		table.insert(inner, 1, (binder :: { kind: "sym", name: string, line: number }).name)

		return M.app(M.lam(compile(items[4], inner)), value)
	end

	if name == "letrec" then
		arity(3)
		const binder = items[2]
		const definition = items[3]

		if binder.kind ~= "sym" then
			fail(binder.line, "letrec binds a name")
		end

		if definition.kind ~= "list" or #definition.items == 0 or definition.items[1].kind ~= "sym" or (definition.items[1] :: { kind: "sym", name: string, line: number, })
			.name ~= "lam" then
			fail(definition.line, "letrec binds a lam, so the function can call itself")
		end

		-- The name is in scope in the definition and in the body. The definition is wrapped in fix, whose outer lambda binds the name to the function itself.
		const name_ = (binder :: { kind: "sym", name: string, line: number }).name
		const inner = table.clone(scope)
		table.insert(inner, 1, name_)

		const recursive = M.app(M.fix, M.lam(compile(definition, inner)))
		return M.app(M.lam(compile(items[4], inner)), recursive)
	end

	if name == "list" then
		local elements: { M.Expr } = {}
		for i = 2, #items do
			table.insert(elements, compile(items[i], scope))
		end
		return M.list(elements)
	end

	if name == "kind" then
		arity(1)
		return M.prim("kind", compile(items[2], scope))
	end

	if name == "?" then
		arity(1)
		return M.prim("eq", M.prim("kind", compile(items[2], scope)), M.int(1))
	end

	if PRIMITIVES[name] ~= nil then
		const primitive = PRIMITIVES[name]
		arity(primitive.arity)

		if primitive.arity == 1 then
			return M.prim(primitive.op, compile(items[2], scope))
		end
		return M.prim(primitive.op, compile(items[2], scope), compile(items[3], scope))
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

compile = function(
	node: Node,
	scope: { string }
): M.Expr
	if node.kind == "int" then
		return M.int(node.value)
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
		if #items ~= 2 then
			fail(node.line, `a pair takes exactly two items, but was given {#items}`)
		end
		return M.cell(compile(items[1], scope), compile(items[2], scope))
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

const function parse(
	source: string
): M.Expr
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

return {
	parse = parse,
}
