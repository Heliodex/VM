--!strict
-- THE L2 DESUGARER
--
-- Turns a surface tree (parser.luau) into the machine's expressions (interpreter/vm.luau). There are no types here: the checker is a later stage, and it will run before this one.
--
--   fn (x y) body         a function of x, then of y: lam, lam
--   let x = e in b        a non-recursive binding: (lam b) applied to e
--   letrec f = fn ... in b  a recursive function: fix, as in L1
--   mutual (...) in b     a group of functions that call each other, as in L1: one fix, dispatched by a tag
--   if c t e              ite; only the branch taken runs
--   match e { ... }       the scrutinee is bound, and each arm tests its constructor's tag: tagof, then payload
--   e?                    early return, rewritten as a match on the result, in the function it appears in
--
-- Early return. A `?` returns from the function it is in, so the rewrite must not run it when it would not run otherwise. A `?` is allowed where the expression runs whenever the function does: in the function's body, in let values, in arguments, and so on. Inside an if branch or a match arm it is allowed only when that if or match is itself the function's result, and then the branch is a function of its own. Anywhere else it is an error. The rewrite is done on the surface tree before desugaring, so the names it introduces are plain names.
--
--   Desugar.desugarProgram(ast, importNames, ctors): VM.Expr
--   Desugar.buildCtors(decls): { [string]: Ctor }
--   Desugar.wrapImports(expr, importNames, importExprs): VM.Expr

const M = require "../interpreter/vm"
const Primitives = require "../interpreter/primitives"

export type Ctor = { tag: number, payload: boolean, sum: string }

local counter = 0

-- The built-in unary forms of section 7 and section 6. head and tail are the index expression, so a chain of them is one step.
local UNARY: { [string]: (M.Expr) -> M.Expr } = {
	head = M.head,
	tail = M.tail,
	pin = M.pin,
	force = M.force,
	fix = function(
		e: M.Expr
	): M.Expr
		return M.app(M.fix, e)
	end,
}

local function fresh(): string
	counter += 1
	return string.format(" t%d", counter)
end

local function fail(
	at: { line: number, col: number }?,
	msg: string
)
	if at ~= nil then
		error(string.format("line %d, column %d: %s", at.line, at.col, msg), 0)
	end

	error(msg, 0)
end

local function isCapital(
	name: string
): boolean
	return string.match(name, "^%u") ~= nil
end

-- Checks a name that is about to be bound.
local function checkBinder(
	name: string,
	at: any
)
	if isCapital(name) then
		fail(at, string.format("%s is a constructor, and cannot be bound", name))
	end

	if name == "_" or name == "~" then
		fail(at, string.format("%s cannot be bound", name))
	end

	if Primitives.BY_SYMBOL[name] ~= nil or UNARY[name] ~= nil then
		fail(at, string.format("%s is a primitive, and cannot be bound", name))
	end
end

-- The constructors of the built-in sum Result, and of every type declared in the program.
local function buildCtors(
	decls: { any }
): { [string]: Ctor }
	local ctors: { [string]: Ctor } = {
		Ok = { tag = 0, payload = true, sum = "Result" },
		Err = { tag = 1, payload = true, sum = "Result" },
	}

	for _, decl in decls do
		for k, con in decl.cons do
			if ctors[con.name] ~= nil then
				fail(con.at, string.format("%s is already declared", con.name))
			end

			ctors[con.name] = {
				tag = k - 1,
				payload = con.payload ~= nil,
				sum = decl.name,
			}
		end
	end

	return ctors
end

-- Position in the scope of a name, counting from 0 for the innermost binder. nil if the name is not in scope.
local function indexOf(
	scope: { string },
	name: string
): number?
	for i, n in scope do
		if n == name then
			return i - 1
		end
	end

	return nil
end

local function withNames(
	scope: { string },
	names: { string }
): { string }
	local out = table.clone(scope)

	for _, name in names do
		table.insert(out, 1, name)
	end

	return out
end

-- EARLY RETURN

-- Collects the ? expressions of a body in evaluation order, and returns the body with each one replaced by a name. mode is "fn" where the value is the function's result, "eager" where the expression runs whenever the function does but is not the result, and "none" where it runs only sometimes.
local collect: (node: any, hoists: { any }, mode: string) -> any

local function childMode(
	mode: string
): string
	return if mode == "none" then "none" else "eager"
end

local function wrapHoists(
	body: any,
	hoists: { any }
): any
	for i = #hoists, 1, -1 do
		const h = hoists[i]
		const errName = fresh()

		body = {
			k = "match",
			scrut = h.expr,
			arms = {
				{
					pat = { k = "con", name = "Ok", bind = h.name, at = h.at },
					body = body,
					at = h.at,
				},
				{
					pat = { k = "con", name = "Err", bind = errName, at = h.at },
					body = {
						k = "app",
						f = { k = "name", name = "Err", at = h.at },
						args = { { k = "name", name = errName, at = h.at } },
						at = h.at,
					},
					at = h.at,
				},
			},
			at = h.at,
		}
	end

	return body
end

-- A branch of an if or a match. In a tail position it is a function of its own, so its ? expressions return from it. Elsewhere it may not contain one.
local collectBranch: (node: any, mode: string) -> any
local collectUnderBinding: (body: any, mode: string) -> any

collectBranch = function(
	node: any,
	mode: string
): any
	if mode == "fn" then
		local own: { any } = {}
		const out = collect(node, own, "fn")
		return wrapHoists(out, own)
	end

	local none: { any } = {}
	return collect(node, none, "none")
end

collect = function(
	node: any,
	hoists: { any },
	mode: string
): any
	const k = node.k

	if k == "try" then
		if mode == "none" then
			fail(node.at, "? can only be used where it runs whenever its function does, or in the tail of an if or match")
		end

		const inner = collect(node.e, hoists, childMode(mode))
		const name = fresh()
		table.insert(hoists, { name = name, expr = inner, at = node.at })
		return { k = "name", name = name, at = node.at }
	elseif k == "app" then
		const cm = childMode(mode)
		local args: { any } = {}

		for _, a in node.args do
			table.insert(args, collect(a, hoists, cm))
		end

		return { k = "app", f = collect(node.f, hoists, cm), args = args, at = node.at }
	elseif k == "list" then
		local items: { any } = {}

		for _, a in node.items do
			table.insert(items, collect(a, hoists, childMode(mode)))
		end

		return { k = "list", items = items, at = node.at }
	elseif k == "pair" then
		return {
			k = "pair",
			a = collect(node.a, hoists, childMode(mode)),
			b = collect(node.b, hoists, childMode(mode)),
			at = node.at,
		}
	elseif k == "let" then
		return {
			k = "let",
			name = node.name,
			value = collect(node.value, hoists, childMode(mode)),
			body = collectUnderBinding(node.body, mode),
			rec = node.rec,
			at = node.at,
		}
	elseif k == "mutual" then
		return { k = "mutual", bindings = node.bindings, body = collectUnderBinding(node.body, mode), at = node.at }
	elseif k == "if" then
		return {
			k = "if",
			c = collect(node.c, hoists, childMode(mode)),
			t = collectBranch(node.t, mode),
			e = collectBranch(node.e, mode),
			at = node.at,
		}
	elseif k == "match" then
		local arms: { any } = {}

		for _, arm in node.arms do
			table.insert(arms, { pat = arm.pat, body = collectBranch(arm.body, mode), at = arm.at })
		end

		return {
			k = "match",
			scrut = collect(node.scrut, hoists, childMode(mode)),
			arms = arms,
			at = node.at,
		}
	end

	-- A fn is a function of its own, and the names, numbers and nil have no parts to collect.
	return node
end

-- The body of a let or mutual, which sees the names it binds. In tail position its ? expressions wrap the body, inside the binding, so they can use the names. Elsewhere it may not contain one, since its early return would have to leave the let before the names exist.
collectUnderBinding = function(
	body: any,
	mode: string
): any
	if mode == "fn" then
		local own: { any } = {}
		const out = collect(body, own, "fn")
		return wrapHoists(out, own)
	end

	local none: { any } = {}
	return collect(body, none, "none")
end

-- The body of a function, or of the program: its own ? expressions, with the early returns around it.
local function contextify(
	body: any
): any
	local own: { any } = {}
	const out = collect(body, own, "fn")
	return wrapHoists(out, own)
end

-- MUTUAL

-- A mutual group, as a surface tree, in the way the L1 reader builds it: one fix over a dispatch on a tag, and each name a call through the group.
local function mutualSurface(
	node: any
): any
	local n = #node.bindings
	local names: { string } = {}

	for _, b in node.bindings do
		if b.value.k ~= "fn" then
			fail(b.at, "mutual binds functions, so that they can call each other")
		end

		checkBinder(b.name, b.at)
		table.insert(names, b.name)
	end

	local function nameNode(
		name: string
	): any
		return { k = "name", name = name, at = node.at }
	end

	local function member(
		g: string,
		j: number
	): any
		return {
			k = "fn",
			names = { " y" },
			body = {
				k = "app",
				f = { k = "app", f = nameNode(g), args = { { k = "int", n = j, at = node.at } }, at = node.at },
				args = { nameNode(" y") },
				at = node.at,
			},
			at = node.at,
		}
	end

	local function branch(
		j: number
	): any
		local body: any = {
			k = "app",
			f = node.bindings[j].value,
			args = { nameNode(" x") },
			at = node.at,
		}

		for k = n, 1, -1 do
			body = {
				k = "let",
				name = names[k],
				value = member(" self", k - 1),
				body = body,
				rec = false,
				at = node.at,
			}
		end

		return body
	end

	local chain = branch(n)

	for j = n - 1, 1, -1 do
		chain = {
			k = "if",
			c = {
				k = "app",
				f = nameNode("="),
				args = { nameNode(" tag"), { k = "int", n = j - 1, at = node.at } },
				at = node.at,
			},
			t = branch(j),
			e = chain,
			at = node.at,
		}
	end

	const dispatch = {
		k = "fn",
		names = { " self" },
		body = {
			k = "fn",
			names = { " tag" },
			body = { k = "fn", names = { " x" }, body = chain, at = node.at },
			at = node.at,
		},
		at = node.at,
	}

	local body = node.body

	for k = n, 1, -1 do
		body = {
			k = "let",
			name = names[k],
			value = member(" group", k - 1),
			body = body,
			rec = false,
			at = node.at,
		}
	end

	return {
		k = "let",
		name = " group",
		value = { k = "rawfix", value = dispatch, at = node.at },
		body = body,
		rec = false,
		at = node.at,
	}
end

-- DESUGARING

local desugar: (node: any, scope: { string }, ctors: { [string]: Ctor }) -> M.Expr

local function stringValue(
	bytes: { number }
): M.Expr
	local e = M.nilv()

	for i = #bytes, 1, -1 do
		e = M.cell(M.int(bytes[i]), e)
	end

	return e
end

local function resolveName(
	node: any,
	scope: { string },
	ctors: { [string]: Ctor }
): M.Expr
	const name = node.name
	const found = indexOf(scope, name)

	if found ~= nil then
		return M.var(found)
	end

	const p = Primitives.BY_SYMBOL[name]

	if p ~= nil then
		if p.arity == 1 then
			return M.lam(M.prim(p.tag, M.var(0)))
		end

		return M.lam(M.lam(M.prim(p.tag, M.var(1), M.var(0))))
	end

	const unary = UNARY[name]

	if unary ~= nil then
		return M.lam(unary(M.var(0)))
	end

	const c = ctors[name]

	if c ~= nil then
		if c.payload then
			return M.lam(M.construct(c.tag, M.var(0)))
		end

		return M.construct(c.tag, M.nilv())
	end

	fail(node.at, string.format("%s is not bound", name))
	return M.nilv()
end

local function desugarApp(
	node: any,
	scope: { string },
	ctors: { [string]: Ctor }
): M.Expr
	const head = node.f
	const args = node.args

	if head.k == "name" and indexOf(scope, head.name) == nil and UNARY[head.name] ~= nil and #args >= 1 then
		local e = UNARY[head.name](desugar(args[1], scope, ctors))

		for i = 2, #args do
			e = M.app(e, desugar(args[i], scope, ctors))
		end

		return e
	end

	if head.k == "name" and indexOf(scope, head.name) == nil then
		const p = Primitives.BY_SYMBOL[head.name]

		if p ~= nil and #args >= p.arity then
			local e: M.Expr

			if p.arity == 1 then
				e = M.prim(p.tag, desugar(args[1], scope, ctors))
			else
				e = M.prim(p.tag, desugar(args[1], scope, ctors), desugar(args[2], scope, ctors))
			end

			for i = p.arity + 1, #args do
				e = M.app(e, desugar(args[i], scope, ctors))
			end

			return e
		end

		const c = ctors[head.name]

		if c ~= nil and (not c.payload or #args >= 1) then
			local e: M.Expr
			local first = 1

			if c.payload then
				e = M.construct(c.tag, desugar(args[1], scope, ctors))
				first = 2
			else
				e = M.construct(c.tag, M.nilv())
			end

			for i = first, #args do
				e = M.app(e, desugar(args[i], scope, ctors))
			end

			return e
		end
	end

	local e = desugar(head, scope, ctors)

	for _, a in args do
		e = M.app(e, desugar(a, scope, ctors))
	end

	return e
end

local function buildArms(
	arms: { any },
	i: number,
	scope: { string },
	ctors: { [string]: Ctor }
): M.Expr
	if i > #arms then
		-- A match with no arm that fits. The checker reports this before a program runs; until then it fails at run time.
		return M.head(M.int(0))
	end

	const arm = arms[i]
	const pat = arm.pat

	if pat.k == "wild" or pat.k == "bind" then
		if i < #arms then
			fail(arms[i + 1].at, "an arm after a catch-all arm is unreachable")
		end

		if pat.k == "wild" then
			return desugar(arm.body, scope, ctors)
		end

		checkBinder(pat.name, pat.at)
		return M.app(M.lam(desugar(arm.body, withNames(scope, { pat.name }), ctors)), M.var(0))
	end

	const c = ctors[pat.name]

	if c == nil then
		fail(pat.at, string.format("%s is not a constructor", pat.name))
	end

	local body: M.Expr

	if pat.bind ~= nil then
		if not c.payload then
			fail(pat.at, string.format("%s has no payload to bind", pat.name))
		end

		checkBinder(pat.bind, pat.at)
		body = M.app(M.lam(desugar(arm.body, withNames(scope, { pat.bind }), ctors)), M.payload(M.var(0)))
	else
		body = desugar(arm.body, scope, ctors)
	end

	return M.ite(
		M.prim(Primitives.TAG.eq, M.tagof(M.var(0)), M.int(c.tag)),
		body,
		buildArms(arms, i + 1, scope, ctors)
	)
end

local function desugarMatch(
	node: any,
	scope: { string },
	ctors: { [string]: Ctor }
): M.Expr
	const s = desugar(node.scrut, scope, ctors)
	const inner = withNames(scope, { " scrut" })
	return M.app(M.lam(buildArms(node.arms, 1, inner, ctors)), s)
end

desugar = function(
	node: any,
	scope: { string },
	ctors: { [string]: Ctor }
): M.Expr
	const k = node.k

	if k == "int" then
		return M.int(node.n)
	elseif k == "str" then
		return stringValue(node.bytes)
	elseif k == "nil" then
		return M.nilv()
	elseif k == "name" then
		return resolveName(node, scope, ctors)
	elseif k == "list" then
		local e = M.nilv()
		local items: { M.Expr } = {}

		for _, a in node.items do
			table.insert(items, desugar(a, scope, ctors))
		end

		for i = #items, 1, -1 do
			e = M.cell(items[i], e)
		end

		return e
	elseif k == "pair" then
		return M.cell(desugar(node.a, scope, ctors), desugar(node.b, scope, ctors))
	elseif k == "app" then
		return desugarApp(node, scope, ctors)
	elseif k == "fn" then
		local names: { string } = {}

		for _, name in node.names do
			checkBinder(name, node.at)

			if table.find(names, name) ~= nil then
				fail(node.at, string.format("%s is named twice in the parameters", name))
			end

			table.insert(names, name)
		end

		const body = desugar(contextify(node.body), withNames(scope, names), ctors)
		local e = body

		for _ = 1, #names do
			e = M.lam(e)
		end

		return e
	elseif k == "let" then
		checkBinder(node.name, node.at)
		const inner = withNames(scope, { node.name })

		if node.rec then
			if node.value.k ~= "fn" then
				fail(node.value.at, "letrec binds a fn, so the function can call itself")
			end

			return M.app(
				M.lam(desugar(node.body, inner, ctors)),
				M.app(M.fix, M.lam(desugar(node.value, inner, ctors)))
			)
		end

		return M.app(M.lam(desugar(node.body, inner, ctors)), desugar(node.value, scope, ctors))
	elseif k == "mutual" then
		return desugar(mutualSurface(node), scope, ctors)
	elseif k == "rawfix" then
		return M.app(M.fix, desugar(node.value, scope, ctors))
	elseif k == "if" then
		return M.ite(desugar(node.c, scope, ctors), desugar(node.t, scope, ctors), desugar(node.e, scope, ctors))
	elseif k == "match" then
		return desugarMatch(node, scope, ctors)
	elseif k == "try" then
		fail(node.at, "? was not rewritten: it is in a place the early-return rule does not reach")
	end

	fail(node.at, "unknown form in the tree")
	return M.nilv()
end

-- The program, as an expression with the names of its imports free in it. importNames is in the order the file lists them.
local function desugarProgram(
	ast: any,
	importNames: { string },
	ctors: { [string]: Ctor }
): M.Expr
	local scope: { string } = {}

	for _, name in importNames do
		table.insert(scope, 1, name)
	end

	return desugar(contextify(ast.expr), scope, ctors)
end

-- Binds each import around the program. The imported programs are closed, so their expressions can be placed at the top.
local function wrapImports(
	expr: M.Expr,
	importExprs: { M.Expr }
): M.Expr
	local e = expr

	for i = #importExprs, 1, -1 do
		e = M.app(M.lam(e), importExprs[i])
	end

	return e
end

return {
	desugarProgram = desugarProgram,
	buildCtors = buildCtors,
	wrapImports = wrapImports,
	desugarExpr = function(
		ast: any,
		importNames: { string },
		ctors: { [string]: Ctor }
	): M.Expr
		local scope: { string } = {}

		for _, name in importNames do
			table.insert(scope, 1, name)
		end

		return desugar(contextify(ast), scope, ctors)
	end,
}
