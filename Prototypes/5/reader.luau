--!strict
-- THE READER
--
-- Turns the text of a program into an Expr, which vm.luau then runs. The syntax is s-expressions, with ; starting a comment that runs to the end of the line.
--
--   42                 an integer, negative ones too
--   ()                 nil
--   x                  a variable
--   (lam x body)       a function of x; (lam (x y) body) is the same as (lam x (lam y body))
--   (f a b)            application, curried: (f a b) is ((f a) b)
--   (cell h t)         a pair
--   (list a b c)       a proper list of a, b and c
--   (head e), (tail e)
--   (if c t e)         evaluates t if c is nonzero, otherwise e
--   (pin e), (force e)
--   (fix f)            the fixed point of f, where f is (lam rec (lam ...)) and rec is the function itself
--   (add a b), (sub a b), (mul a b), (lt a b), (eq a b), (isnil a)
--
-- The words above are reserved and cannot be used as variables. Errors are raised as strings that begin with the line number.
--
-- Reader.parse(source) reads exactly one expression and raises an error if there is anything after it.

const M = require "./vm"

type Token = {
	text: string,
	line: number,
}

-- An expression as written, before it is compiled. Lists keep their line for error messages.
type Node =
	| { kind: "int", value: number, line: number }
	| { kind: "sym", name: string, line: number }
	| { kind: "list", items: { Node }, line: number }

-- The arity of each form. Forms with an arity of nil take any number of arguments, at least one for lam.
const PRIMITIVES: { [string]: number } = {
	add = 2,
	sub = 2,
	mul = 2,
	lt = 2,
	eq = 2,
	isnil = 1,
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
		or name == "cell"
		or name == "list"
		or PRIMITIVES[name] ~= nil
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
		elseif c == "(" or c == ")" then
			table.insert(tokens, { text = c, line = line })
			i += 1
		else
			const text: string = string.match(source, "^[^%s();]+", i) :: string
			table.insert(tokens, { text = text, line = line })
			i += #text
		end
	end

	return tokens
end

-- Reads one node starting at position pos, and returns it with the position after it.
local function readNode(
	tokens: { Token },
	pos: number
): (Node, number)
	if pos > #tokens then
		fail(tokens[#tokens].line, "the program ends before an expression is complete")
	end

	const token = tokens[pos]

	if token.text == ")" then
		fail(token.line, "unexpected )")
	end

	if token.text == "(" then
		local items: { Node } = {}
		local p = pos + 1

		while true do
			if p > #tokens then
				fail(token.line, "( is never closed")
			end

			if tokens[p].text == ")" then
				return { kind = "list", items = items, line = token.line }, p + 1
			end

			local node: Node
			node, p = readNode(tokens, p)
			table.insert(items, node)
		end
	end

	const digits = string.match(token.text, "^%-?%d+$")

	if digits then
		return { kind = "int", value = tonumber(digits) :: number, line = token.line }, pos + 1
	end

	return { kind = "sym", name = token.text, line = token.line }, pos + 1
end

-- Compiles a node to an expression. Forms are recognised by their first word.
local compile: (Node) -> M.Expr

local function compileForm(
	name: string,
	node: { kind: "list", items: { Node }, line: number }
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

		local body = compile(items[#items])
		for i = #names, 1, -1 do
			body = M.lam(names[i], body)
		end

		return body
	end

	if name == "if" then
		arity(3)
		return M.ite(compile(items[2]), compile(items[3]), compile(items[4]))
	end

	if name == "cell" then
		arity(2)
		return M.cell(compile(items[2]), compile(items[3]))
	end

	if name == "list" then
		local elements: { M.Expr } = {}
		for i = 2, #items do
			table.insert(elements, compile(items[i]))
		end
		return M.list(elements)
	end

	if PRIMITIVES[name] ~= nil then
		arity(PRIMITIVES[name])
		if name == "isnil" then
			return M.prim(name, compile(items[2]))
		end
		return M.prim(name, compile(items[2]), compile(items[3]))
	end

	if UNARY_FORMS[name] ~= nil then
		arity(1)
		const inner = compile(items[2])

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

	local e = compile(items[1])
	for i = 2, #items do
		e = M.app(e, compile(items[i]))
	end
	return e
end

compile = function(
	node: Node
): M.Expr
	if node.kind == "int" then
		return M.int(node.value)
	end

	if node.kind == "sym" then
		if reserved(node.name) then
			fail(node.line, node.name .. " is a reserved word and cannot be used as a variable")
		end
		return M.var(node.name)
	end

	const items = node.items

	if #items == 0 then
		return M.nilv()
	end

	const head = items[1]

	if head.kind == "sym" and reserved(head.name) then
		return compileForm(head.name, node)
	end

	return compileForm("", node)
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

	return compile(node)
end

return {
	parse = parse,
}
