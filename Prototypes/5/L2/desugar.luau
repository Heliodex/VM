--!strict
-- THE L2 DESUGARER
--
-- Turns a surface tree (parser.luau) into the machine's expressions (interpreter/vm.luau). There is no type checking here: the checker is a later stage, and it will run before this one.
--
--   fn (x y) body         a function of x, then of y: lam, lam
--   let x = e, then b     a non-recursive binding: (lam b) applied to e
--   letrec f = fn ..., then b  a recursive function: fix, as in L1
--   letrec { ... } b      a group of functions that call each other, as in L1: one fix, dispatched by a tag
--   if c t e              ite; only the branch taken runs
--   match e { ... }       the scrutinee is bound, and each arm tests its constructor's tag: tagof, then payload
--   e?                    early return, rewritten as a match on the result, in the function it appears in
--
-- Early return. A `?` returns from the function it is in, so the rewrite must not run it when it would not run otherwise. A `?` is allowed where the expression runs whenever the function does: in the function's body, in let values, in arguments, and so on. Inside an if branch or a match arm it is allowed only when that if or match is itself the function's result, and then the branch is a function of its own. Anywhere else it is an error. The rewrite is done on the surface tree before desugaring, so the names it introduces are plain names.
--
--   Desugar.desugarProgram(expr, importNames, ctors): VM.Expr    expr is the checked tree (checker.luau)
--   Desugar.desugarExpr(expr, importNames, ctors): VM.Expr      an expression that is not checked, such as a test's
--   Desugar.buildCtors(decls): { [string]: Ctor }
--   Desugar.wrapImports(expr, importExprs): VM.Expr
--   Desugar.boundary(expr, test, expect): VM.Expr               the program, with its input checked when it is run

const Primitives = require "../interpreter/primitives"
const M = require "../interpreter/vm"
const Parser = require "./parser"

type Expr = Parser.Expr
type Arm = Parser.Arm
type Pattern = Parser.Pattern
type Pos = Parser.Pos
type Binding = Parser.Binding
type Test = Parser.Test
export type Ctor = { tag: number; payload: boolean; sum: string }
-- A ? expression pulled out of a function body, to be bound before the body runs.
type Hoist = { name: string; expr: Expr; at: Pos }
local counter = 0

-- A string as a list of its bytes, as the surface writes it.
local function textValue(s: string): M.Expr
	local e = M.nilv()

	for i = #s, 1, -1 do
		e = M.cell(M.int(string.byte(s, i) :: number), e)
	end

	return e
end

-- The checked forms of the operations that can fail. Each gives Ok with the result, or Err with the reason. Each operand is bound once, so it is evaluated once.
-- x / y or x % y: Err with the reason when y is zero, and Ok of the operation otherwise. tag is div or mod.
local function checkedDivision(tag: number, x: M.Expr, y: M.Expr, reason: string): M.Expr
	const body = M.ite(M.prim(Primitives.TAG.eq, M.var(0), M.int(0)), M.construct(1, textValue(reason)), M.construct(0, M.prim(tag, M.var(1), M.var(0))))

	return M.app(M.app(M.lam(M.lam(body)), x), y)
end

-- head x: Ok of the head when x is a pair, and Err when it is nil. A list is a pair or nil, so the test is the kind of x: 2 for a pair.
local function checkedHead(x: M.Expr): M.Expr
	const body = M.ite(M.prim(Primitives.TAG.eq, M.prim(Primitives.TAG.kind, M.var(0)), M.int(2)), M.construct(0, M.head(M.var(0))), M.construct(1, textValue "head of an empty list"))

	return M.app(M.lam(body), x)
end

-- tail x: Ok of the tail when x is a pair, and Err when it is nil.
local function checkedTail(x: M.Expr): M.Expr
	const body = M.ite(M.prim(Primitives.TAG.eq, M.prim(Primitives.TAG.kind, M.var(0)), M.int(2)), M.construct(0, M.tail(M.var(0))), M.construct(1, textValue "tail of an empty list"))

	return M.app(M.lam(body), x)
end

-- The reason each division gives Err, by the name of its primitive.
local DIVISION: { [string]: string } = {
	div = "division by zero",
	mod = "remainder by zero",
}
-- The built-in unary forms of section 7 and section 6. head and tail give a Result, so they are checked (checkedHead, checkedTail).
local UNARY: { [string]: (M.Expr) -> M.Expr } = {
	head = checkedHead,
	tail = checkedTail,
	-- A pair is never nil, so fst and snd take its parts without a check.
	fst = M.head,
	snd = M.tail,
	pin = M.pin,
	force = M.force,
	fix = function(e: M.Expr): M.Expr
		return M.app(M.fix, e)
	end,
}

local function fresh(): string
	counter += 1

	return string.format(" t%d", counter)
end

local function fail(at: Pos?, msg: string): never
	if at ~= nil then
		error(string.format("line %d, column %d: %s", at.line, at.col, msg), 0)
	end

	error(msg, 0)
end

local function isCapital(name: string): boolean
	return string.match(name, "^%u") ~= nil
end

-- Checks a name that is about to be bound.
local function checkBinder(name: string, at: Pos)
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
local function buildCtors(decls: { Parser.TypeDecl }): { [string]: Ctor }
	local ctors: { [string]: Ctor } = {
		Ok = { tag = 0; payload = true; sum = "Result" },
		Err = { tag = 1; payload = true; sum = "Result" },
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
local function indexOf(scope: { string }, name: string): number?
	for i, n in scope do
		if n == name then
			return i - 1
		end
	end

	return nil
end

local function withNames(scope: { string }, names: { string }): { string }
	local out = table.clone(scope)

	for _, name in names do
		table.insert(out, 1, name)
	end

	return out
end

-- Constructors for the surface nodes the desugarer makes itself. Each has its return type, so every literal is checked against its node kind.
local function nameE(name: string, at: Pos): Expr
	return { k = "name"; name = name; at = at }
end

local function intE(n: number, at: Pos): Expr
	return { k = "int"; n = n; at = at }
end

local function appE(f: Expr, args: { Expr }, at: Pos): Expr
	return { k = "app"; f = f; args = args; at = at }
end

local function fnE(names: { string }, body: Expr, at: Pos): Expr
	return { k = "fn"; names = names; body = body; at = at }
end

local function letE(name: string, value: Expr, body: Expr, at: Pos): Expr
	return { k = "let"; name = name; value = value; body = body; rec = false; at = at }
end

local function ifE(c: Expr, t: Expr, e: Expr, at: Pos): Expr
	return { k = "if"; c = c; t = t; e = e; at = at }
end

local function conPat(name: string, bind: string?, at: Pos): Pattern
	return { k = "con"; name = name; bind = bind; at = at }
end

-- EARLY RETURN
-- Collects the ? expressions of a body in evaluation order, and returns the body with each one replaced by a name. mode is "fn" where the value is the function's result, "eager" where the expression runs whenever the function does but is not the result, and "none" where it runs only sometimes.
local collect: (node: Expr, hoists: { Hoist }, mode: string) -> Expr

local function childMode(mode: string): string
	return
		if mode == "none" then
			"none"
		else
			"eager"
end

local function wrapHoists(body: Expr, hoists: { Hoist }): Expr
	for i = #hoists, 1, -1 do
		const h = hoists[i]
		const errName = fresh()
		const errBody = appE(nameE("Err", h.at), { nameE(errName, h.at) }, h.at)
		const okArm: Arm = { pat = conPat("Ok", h.name, h.at); body = body; at = h.at }
		const errArm: Arm = { pat = conPat("Err", errName, h.at); body = errBody; at = h.at }
		body = { k = "match"; scrut = h.expr; arms = { okArm; errArm }; at = h.at }
	end

	return body
end

-- A branch of an if or a match. In a tail position it is a function of its own, so its ? expressions return from it. Elsewhere it may not contain one.
local collectBranch: (node: Expr, mode: string) -> Expr
-- The body of a let or mutual, which sees the names it binds. In tail position its ? expressions wrap the body, inside the binding, so they can use the names. Elsewhere it may not contain one, since its early return would have to leave the let before the names exist.
local collectUnderBinding: (body: Expr, mode: string) -> Expr
collectBranch = function(node: Expr, mode: string): Expr
	if mode == "fn" then
		local own: { Hoist } = {}
		const out = collect(node, own, "fn")

		return wrapHoists(out, own)
	end

	local none: { Hoist } = {}

	return collect(node, none, "none")
end
collectUnderBinding = function(body: Expr, mode: string): Expr
	if mode == "fn" then
		local own: { Hoist } = {}
		const out = collect(body, own, "fn")

		return wrapHoists(out, own)
	end

	local none: { Hoist } = {}

	return collect(body, none, "none")
end
collect = function(node: Expr, hoists: { Hoist }, mode: string): Expr
	if node.k == "try" then
		if mode == "none" then
			fail(node.at, "? can only be used where it runs whenever its function does, or in the tail of an if or match")
		end

		const inner = collect(node.e, hoists, childMode(mode))
		const name = fresh()
		table.insert(hoists, { name = name; expr = inner; at = node.at })

		return { k = "name"; name = name; at = node.at }
	elseif node.k == "app" then
		const cm = childMode(mode)
		local args: { Expr } = {}

		for _, a in node.args do
			table.insert(args, collect(a, hoists, cm))
		end

		return { k = "app"; f = collect(node.f, hoists, cm); args = args; at = node.at }
	elseif node.k == "list" then
		local items: { Expr } = {}

		for _, a in node.items do
			table.insert(items, collect(a, hoists, childMode(mode)))
		end

		return { k = "list"; items = items; at = node.at }
	elseif node.k == "pair" then
		return {
			k = "pair",
			a = collect(node.a, hoists, childMode(mode)),
			b = collect(node.b, hoists, childMode(mode)),
			at = node.at,
		}
	elseif node.k == "let" then
		return {
			k = "let",
			name = node.name,
			value = collect(node.value, hoists, childMode(mode)),
			body = collectUnderBinding(node.body, mode),
			rec = node.rec,
			at = node.at,
		}
	elseif node.k == "untyped" then
		return { k = "untyped"; e = collect(node.e, hoists, childMode(mode)); at = node.at }
	elseif node.k == "check" then
		return { k = "check"; e = collect(node.e, hoists, childMode(mode)); test = node.test; expect = node.expect; at = node.at }
	elseif node.k == "mutual" then
		return { k = "mutual"; bindings = node.bindings; body = collectUnderBinding(node.body, mode); at = node.at }
	elseif node.k == "if" then
		return {
			k = "if",
			c = collect(node.c, hoists, childMode(mode)),
			t = collectBranch(node.t, mode),
			e = collectBranch(node.e, mode),
			at = node.at,
		}
	elseif node.k == "match" then
		local arms: { Arm } = {}

		for _, arm in node.arms do
			table.insert(arms, { pat = arm.pat; body = collectBranch(arm.body, mode); at = arm.at })
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

-- The body of a function, or of the program: its own ? expressions, with the early returns around it.
local function contextify(body: Expr): Expr
	local own: { Hoist } = {}
	const out = collect(body, own, "fn")

	return wrapHoists(out, own)
end

-- MUTUAL
-- A mutual group, as a surface tree, in the way the L1 reader builds it: one fix over a dispatch on a tag, and each name a call through the group.
local function mutualSurface(bindings: { Binding }, body: Expr, at: Pos): Expr
	local n = #bindings
	local names: { string } = {}

	for _, b in bindings do
		if b.value.k ~= "fn" then
			fail(b.at, "mutual binds functions, so that they can call each other")
		end

		checkBinder(b.name, b.at)
		table.insert(names, b.name)
	end

	-- member(g, j) is the j-th function of the group g, as a function of y: g j y.
	local function member(g: string, j: number): Expr
		return fnE({ " y" }, appE(appE(nameE(g, at), { intE(j, at) }, at), { nameE(" y", at) }, at), at)
	end

	-- branch(j) runs the j-th function, with every name of the group bound to its member.
	local function branch(j: number): Expr
		local bodyE: Expr = appE(bindings[j].value, { nameE(" x", at) }, at)

		for k = n, 1, -1 do
			bodyE = letE(names[k], member(" self", k - 1), bodyE, at)
		end

		return bodyE
	end

	local chain = branch(n)

	for j = n - 1, 1, -1 do
		chain = ifE(appE(nameE("=", at), { nameE(" tag", at); intE(j - 1, at) }, at), branch(j), chain, at)
	end

	const dispatch = fnE({ " self" }, fnE({ " tag" }, fnE({ " x" }, chain, at), at), at)
	local groupBody = body

	for k = n, 1, -1 do
		groupBody = letE(names[k], member(" group", k - 1), groupBody, at)
	end

	const fixed: Expr = { k = "rawfix"; value = dispatch; at = at }

	return letE(" group", fixed, groupBody, at)
end

-- The position of a name in scope, which the caller knows is there.
local function slot(scope: { string }, name: string): number
	const found = indexOf(scope, name)

	if found == nil then
		error(string.format("internal: %s is not in scope", name), 0)
	end

	return found
end

-- RUN-TIME CHECKS
-- A check compiles to a predicate over the value: a machine expression that gives 1 when the value has the shape of its test and 0 when it does not. The value is reached by a path from a name in scope: h takes the head, t the tail and p the payload.
local KIND_TAG = Primitives.BY_SYMBOL["@"].tag

local function extend(path: { string }, op: string): { string }
	local out = table.clone(path)
	table.insert(out, op)

	return out
end

local function valueOf(base: string, path: { string }, scope: { string }): M.Expr
	local e = M.var(slot(scope, base))

	for _, op in path do
		if op == "h" then
			e = M.head(e)
		elseif op == "t" then
			e = M.tail(e)
		else
			e = M.payload(e)
		end
	end

	return e
end

local function kindIs(base: string, path: { string }, scope: { string }, k: number): M.Expr
	return M.prim(Primitives.TAG.eq, M.prim(KIND_TAG, valueOf(base, path, scope)), M.int(k))
end

-- The predicate of a test, on the value at base and path. A rec or fixdef refers to a predicate by its key, which is a name in scope.
local compilePred: (Test, string, { string }, { string }) -> M.Expr
compilePred = function(test: Test, base: string, path: { string }, scope: { string }): M.Expr
	if test.kind == "any" then
		return M.int(1)
	elseif test.kind == "int" then
		return kindIs(base, path, scope, 0)
	elseif test.kind == "nil" then
		return kindIs(base, path, scope, 1)
	elseif test.kind == "fn" then
		return kindIs(base, path, scope, 3)
	elseif test.kind == "pin" then
		return kindIs(base, path, scope, 4)
	elseif test.kind == "pair" then
		return M.ite(kindIs(base, path, scope, 2), M.ite(compilePred(test.a, base, extend(path, "h"), scope), compilePred(test.b, base, extend(path, "t"), scope), M.int(0)), M.int(0))
	elseif test.kind == "list" then
		local cell = M.ite(compilePred(test.item, base, extend(path, "h"), scope), compilePred(test.tail, base, extend(path, "t"), scope), M.int(0))

		return M.ite(kindIs(base, path, scope, 1), M.int(1), M.ite(kindIs(base, path, scope, 2), cell, M.int(0)))
	elseif test.kind == "sum" then
		local chain: M.Expr = M.int(0)

		for i = #test.ctors, 1, -1 do
			const c = test.ctors[i]
			const tagIs = M.prim(Primitives.TAG.eq, M.tagof(valueOf(base, path, scope)), M.int(c.tag))
			chain = M.ite(tagIs, compilePred(c.payload, base, extend(path, "p"), scope), chain)
		end

		return M.ite(kindIs(base, path, scope, 5), chain, M.int(0))
	elseif test.kind == "rec" then
		return M.app(M.var(slot(scope, "self:" .. test.key)), valueOf(base, path, scope))
	end

	-- A fixdef: the predicate of its body, as a fixed point that knows itself by its key. Its body is on its own value, x.
	const inner = { "x"; "self:" .. test.key; table.unpack(scope) }
	const body = compilePred(test.body, "x", {}, inner)

	return M.app(M.app(M.fix, M.lam(M.lam(body))), valueOf(base, path, scope))
end

-- The value e, checked: Ok e when it has the test's shape, and Err with "expected" and the type when it does not.
local function checkValue(test: Test, expect: string, e: M.Expr): M.Expr
	const body = M.ite(compilePred(test, "v", {}, { "v" }), M.construct(0, M.var(0)), M.construct(1, textValue("expected " .. expect)))

	return M.app(M.lam(body), e)
end

-- DESUGARING
local desugar: (node: Expr, scope: { string }, ctors: { [string]: Ctor }) -> M.Expr

-- A string is a list of its bytes, as numbers.
local function stringValue(bytes: { number }): M.Expr
	local e = M.nilv()

	for i = #bytes, 1, -1 do
		e = M.cell(M.int(bytes[i]), e)
	end

	return e
end

local function resolveName(name: string, at: Pos, scope: { string }, ctors: { [string]: Ctor }): M.Expr
	const found = indexOf(scope, name)

	if found ~= nil then
		return M.var(found)
	end

	const p = Primitives.BY_SYMBOL[name]

	if p ~= nil then
		if p.arity == 1 then
			return M.lam(M.prim(p.tag, M.var(0)))
		end

		if DIVISION[p.name] ~= nil then
			return M.lam(M.lam(checkedDivision(p.tag, M.var(1), M.var(0), DIVISION[p.name])))
		end

		return M.lam(M.lam(M.prim(p.tag, M.var(1), M.var(0))))
	end

	if name == "cons" then
		return M.lam(M.lam(M.cell(M.var(1), M.var(0))))
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

	return fail(at, string.format("%s is not bound", name))
end

local function desugarApp(head: Expr, args: { Expr }, scope: { string }, ctors: { [string]: Ctor }): M.Expr
	-- cons x xs is the cell with x as its head and xs as its tail.
	if head.k == "name" and head.name == "cons" and indexOf(scope, "cons") == nil and #args >= 2 then
		local e = M.cell(desugar(args[1], scope, ctors), desugar(args[2], scope, ctors))

		for i = 3, #args do
			e = M.app(e, desugar(args[i], scope, ctors))
		end

		return e
	end

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
			elseif DIVISION[p.name] ~= nil then
				e = checkedDivision(p.tag, desugar(args[1], scope, ctors), desugar(args[2], scope, ctors), DIVISION[p.name])
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

local function buildArms(arms: { Arm }, i: number, scope: { string }, ctors: { [string]: Ctor }): M.Expr
	if i > #arms then
		-- A match with no arm that fits. The checker reports this before a program runs; until then it fails at run time.
		return M.head(M.int(0))
	end

	const arm = arms[i]
	const pat = arm.pat

	if pat.k == "wild" then
		if i < #arms then
			fail(arms[i + 1].at, "an arm after a catch-all arm is unreachable")
		end

		return desugar(arm.body, scope, ctors)
	elseif pat.k == "bind" then
		if i < #arms then
			fail(arms[i + 1].at, "an arm after a catch-all arm is unreachable")
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

	return M.ite(M.prim(Primitives.TAG.eq, M.tagof(M.var(0)), M.int(c.tag)), body, buildArms(arms, i + 1, scope, ctors))
end

local function desugarMatch(scrut: Expr, arms: { Arm }, scope: { string }, ctors: { [string]: Ctor }): M.Expr
	const s = desugar(scrut, scope, ctors)
	const inner = withNames(scope, { " scrut" })

	return M.app(M.lam(buildArms(arms, 1, inner, ctors)), s)
end

desugar = function(node: Expr, scope: { string }, ctors: { [string]: Ctor }): M.Expr
	if node.k == "int" then
		return M.int(node.n)
	elseif node.k == "str" then
		return stringValue(node.bytes)
	elseif node.k == "nil" then
		return M.nilv()
	elseif node.k == "name" then
		return resolveName(node.name, node.at, scope, ctors)
	elseif node.k == "list" then
		local e = M.nilv()
		local items: { M.Expr } = {}

		for _, a in node.items do
			table.insert(items, desugar(a, scope, ctors))
		end

		for i = #items, 1, -1 do
			e = M.cell(items[i], e)
		end

		return e
	elseif node.k == "pair" then
		return M.cell(desugar(node.a, scope, ctors), desugar(node.b, scope, ctors))
	elseif node.k == "app" then
		return desugarApp(node.f, node.args, scope, ctors)
	elseif node.k == "fn" then
		local names: { string } = {}

		for _, name in node.names do
			checkBinder(name, node.at)

			if table.find(names, name) ~= nil then
				fail(node.at, string.format("%s is named twice in the parameters", name))
			end

			table.insert(names, name)
		end

		local e = desugar(contextify(node.body), withNames(scope, names), ctors)

		for _ = 1, #names do
			e = M.lam(e)
		end

		return e
	elseif node.k == "let" then
		checkBinder(node.name, node.at)
		const inner = withNames(scope, { node.name })

		if node.rec then
			if node.value.k ~= "fn" then
				fail(node.value.at, "letrec binds a fn, so the function can call itself")
			end

			return M.app(M.lam(desugar(node.body, inner, ctors)), M.app(M.fix, M.lam(desugar(node.value, inner, ctors))))
		end

		return M.app(M.lam(desugar(node.body, inner, ctors)), desugar(node.value, scope, ctors))
	elseif node.k == "mutual" then
		return desugar(mutualSurface(node.bindings, node.body, node.at), scope, ctors)
	elseif node.k == "untyped" then
		return desugar(node.e, scope, ctors)
	elseif node.k == "check" then
		return checkValue(node.test :: Test, node.expect, desugar(node.e, scope, ctors))
	elseif node.k == "rawfix" then
		return M.app(M.fix, desugar(node.value, scope, ctors))
	elseif node.k == "if" then
		return M.ite(desugar(node.c, scope, ctors), desugar(node.t, scope, ctors), desugar(node.e, scope, ctors))
	elseif node.k == "match" then
		return desugarMatch(node.scrut, node.arms, scope, ctors)
	end

	-- A try was rewritten by collect, so one that reaches here sits where the early-return rule does not reach.
	return fail(node.at, "? was not rewritten: it is in a place the early-return rule does not reach")
end

-- The program, as an expression with the names of its imports free in it. importNames is in the order the file lists them.
local function desugarProgram(expr: Expr, importNames: { string }, ctors: { [string]: Ctor }): M.Expr
	local scope: { string } = {}

	for _, name in importNames do
		table.insert(scope, 1, name)
	end

	return desugar(contextify(expr), scope, ctors)
end

-- An expression of a file, with the same imports in scope, as desugarProgram does for the program.
local function desugarExpr(ast: Expr, importNames: { string }, ctors: { [string]: Ctor }): M.Expr
	local scope: { string } = {}

	for _, name in importNames do
		table.insert(scope, 1, name)
	end

	return desugar(contextify(ast), scope, ctors)
end

-- The whole program as the run applies it: a function that runs the program on its input when the input has the test's shape, and gives Err with "expected" and the type when it does not. The program is closed by then, since its imports are bound.
local function boundary(expr: M.Expr, test: Test, expect: string): M.Expr
	return M.lam(M.ite(compilePred(test, "v", {}, { "v" }), M.app(expr, M.var(0)), M.construct(1, textValue("expected " .. expect))))
end

-- Binds each import around the program. The imported programs are closed, so their expressions can be placed at the top.
local function wrapImports(expr: M.Expr, importExprs: { M.Expr }): M.Expr
	local e = expr

	for i = #importExprs, 1, -1 do
		e = M.app(M.lam(e), importExprs[i])
	end

	return e
end

return {
	desugarProgram = desugarProgram,
	desugarExpr = desugarExpr,
	buildCtors = buildCtors,
	wrapImports = wrapImports,
	boundary = boundary,
}
