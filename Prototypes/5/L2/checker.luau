--!strict
-- THE L2 CHECKER
--
-- Infers the type of a surface program (SPEC section 13), and gives each `check e` the test for the type its use gives it. It runs on the parser's tree, before the desugarer, and returns the same tree with the check nodes in it. Each check node carries the test the desugarer compiles.
--
-- The types (section 13.1) are Int, pairs, lists, functions, Pin, sums and Dyn, as constructors over type variables. Unification is Algorithm W's, with levels for generalisation. Dyn is the type of a value from untyped code. Dyn unifies only with Dyn and with a variable, so a value from untyped code is used at a specific type only through `check e`, which gives a Result. Unifying Dyn with a variable binds the variable to Dyn.
--
-- A program is run on data, so its input is checked when it is entered: the input is untyped data, and the checker gives its test in the result.
--
--   Checker.check(program, imports, fileKey): Result
--     program: Parser.Program; imports: { { name, scheme } }; fileKey: the file's name, which keeps the sums of different files apart
--     Result = { expr, input (the test for the input), scheme (the program's type, for importers) }
--   Checker.untyped(): Scheme      the scheme of a value from untyped code, for an import
--   Checker.showScheme(scheme): string
--   raises an error, with the line and column, for a type error
--
-- Errors are reported at the source position of the node where they are found.

const Parser = require "./parser"

export type Ty =
	| { k: "var"; id: number; level: number; ref: Ty? }
	| { k: "con"; name: string; args: { Ty } }
export type Scheme = { vars: { Ty }; ty: Ty }
export type Result = { expr: Parser.Expr; input: Parser.Test; inputExpect: string; scheme: Scheme }
type Pos = Parser.Pos
type CheckNode = { k: "check"; e: Parser.Expr; test: Parser.Test?; expect: string; at: Pos }
type Pending = { node: CheckNode; ty: Ty }
type SumCtor = { name: string; tag: number; payload: Ty?; fields: { string }? }
-- An accessor: the field at index (from 1) of a record of count fields, whose constructor is info.
type FieldInfo = { info: CtorInfo; index: number; count: number }
type Sum = { key: string; name: string; params: { Ty }; ctors: { SumCtor } }
type CtorInfo = { sum: Sum; ctor: SumCtor }
type Cx = {
	sums: { [string]: Sum },
	sumNames: { [string]: string },
	ctors: { [string]: CtorInfo },
	fields: { [string]: FieldInfo },
	pending: { Pending },
	errors: { string },
}
local counter = 0

local function fresh(level: number): Ty
	counter += 1

	return { k = "var"; id = counter; level = level; ref = nil }
end

local function con(name: string, args: { Ty }): Ty
	return { k = "con"; name = name; args = args }
end

local function arrow(a: Ty, b: Ty): Ty
	return con("->", { a; b })
end

local function pairOf(a: Ty, b: Ty): Ty
	return con("pair", { a; b })
end

local function listOf(t: Ty): Ty
	return con("list", { t })
end

local function pinOf(t: Ty): Ty
	return con("Pin", { t })
end

local INT = con("Int", {})
local DYN = con("Dyn", {})

local function prune(t: Ty): Ty
	local r = t

	while r.k == "var" and r.ref ~= nil do
		r = r.ref :: Ty
	end

	return r
end

local function isCapital(name: string): boolean
	return string.match(name, "^%u") ~= nil
end

-- The message of a type, with the sums' full names if full is set. Variables are written ?n.
local function render(t: Ty, full: boolean): string
	local x = prune(t)

	if x.k == "var" then
		return "?" .. tostring(x.id)
	end

	local n = x.name
	local a = x.args

	if n == "->" then
		return "(" .. render(a[1], full) .. " -> " .. render(a[2], full) .. ")"
	elseif n == "pair" then
		return "(" .. render(a[1], full) .. " . " .. render(a[2], full) .. ")"
	elseif n == "list" then
		return "[" .. render(a[1], full) .. "]"
	end

	const base =
		if full then
			n
		else
			string.match(n, "^([^@]*)") :: string

	if #a == 0 then
		return base
	end

	local parts = { base }

	for _, arg in a do
		local shown = render(arg, full)
		const px = prune(arg)

		if px.k == "con" and #px.args > 0 then
			shown = "(" .. shown .. ")"
		end

		table.insert(parts, shown)
	end

	return table.concat(parts, " ")
end

local function failAt(at: Pos?, msg: string): never
	local text = msg

	if at ~= nil then
		text = string.format("line %d, column %d: %s", at.line, at.col, msg)
	end

	error({ typeError = text }, 0)
end

-- The position of the node whose unification is running, for the errors it raises.
local hereAt: Pos? = nil

local function mismatch(actual: Ty, expected: Ty): never
	return failAt(hereAt, string.format("expected %s, but this is %s", render(expected, false), render(actual, false)))
end

local function occurs(v: Ty, t: Ty): boolean
	local x = prune(t)

	if x == v then
		return true
	end

	if x.k == "con" then
		for _, a in x.args do
			if occurs(v, a) then
				return true
			end
		end
	end

	return false
end

-- Moves every variable in t to the level of v, so that generalising at v's level does not quantify them.
local function lowerLevels(t: Ty, level: number)
	local x = prune(t)

	if x.k == "var" then
		if x.level > level then
			x.level = level
		end
	elseif x.k == "con" then
		for _, a in x.args do
			lowerLevels(a, level)
		end
	end
end

local function bindVar(v: Ty, t: Ty)
	if v == t then
		return
	end

	if occurs(v, t) then
		failAt(hereAt, string.format("%s would be an infinite type", render(v, false)))
	end

	if v.k == "var" then
		lowerLevels(t, v.level)
		v.ref = t
	end
end

-- Unifies an actual type with an expected one. A Dyn value unifies only with Dyn and with a variable, so an untyped value is used at a specific type only through an explicit check. A list and a pair unify head to head and tail to tail, since a list is a pair or nil.
local unify: (Ty, Ty) -> ()
unify = function(actual: Ty, expected: Ty)
	local a = prune(actual)
	local b = prune(expected)

	if a == b then
		return
	end

	if a.k == "var" then
		bindVar(a, b)

		return
	end

	if b.k == "var" then
		bindVar(b, a)

		return
	end

	if a.name == "Dyn" and b.name == "Dyn" then
		return
	end

	if a.name == "Dyn" or b.name == "Dyn" then
		mismatch(a, b)
	end

	if a.name ~= b.name or #a.args ~= #b.args then
		mismatch(a, b)
	end

	for i, x in a.args do
		unify(x, b.args[i])
	end
end

local function unifyAt(at: Pos, actual: Ty, expected: Ty)
	hereAt = at
	unify(actual, expected)
end

local function substitute(t: Ty, map: { Ty }): Ty
	local x = prune(t)

	if x.k == "var" then
		return map[x.id] or x
	end

	local args: { Ty } = {}

	for i, a in x.args do
		args[i] = substitute(a, map)
	end

	return con(x.name, args)
end

local function instantiate(s: Scheme, level: number): Ty
	local map: { Ty } = {}

	for _, v in s.vars do
		if v.k == "var" then
			map[v.id] = fresh(level)
		end
	end

	return substitute(s.ty, map)
end

-- Quantifies the variables of t that are deeper than level.
local function generalize(t: Ty, level: number): Scheme
	local vars: { Ty } = {}
	local seen: { boolean } = {}

	local function walk(x: Ty)
		local y = prune(x)

		if y.k == "var" then
			if y.level > level and not seen[y.id] then
				seen[y.id] = true
				table.insert(vars, y)
			end
		elseif y.k == "con" then
			for _, a in y.args do
				walk(a)
			end
		end
	end

	walk(t)

	return { vars = vars; ty = t }
end

-- SUMS
-- The built-in sum Result, and the names it is known by.
local function newCx(): Cx
	const a = fresh(-1)
	const e = fresh(-1)
	const ok: SumCtor = { name = "Ok"; tag = 0; payload = a }
	const err: SumCtor = { name = "Err"; tag = 1; payload = e }
	const result: Sum = { key = "Result"; name = "Result"; params = { a; e }; ctors = { ok; err } }

	return {
		sums = { Result = result },
		sumNames = { Result = "Result" },
		ctors = {
			Ok = { sum = result; ctor = ok },
			Err = { sum = result; ctor = err },
		},
		fields = {},
		pending = {},
		errors = {},
	}
end

local function sumType(cx: Cx, name: string, args: { Ty }, at: Pos): Ty
	const key = cx.sumNames[name]

	if key == nil then
		failAt(at, string.format("%s is not a type", name))
	end

	const sum = cx.sums[key]

	if #sum.params ~= #args then
		failAt(at, string.format("%s takes %d types, but is given %d", name, #sum.params, #args))
	end

	return con(key, args)
end

local function convType(cx: Cx, t: Parser.Type, params: { [string]: Ty }): Ty
	if t.k == "tname" then
		if isCapital(t.name) then
			if t.name == "Int" then
				return INT
			end

			return sumType(cx, t.name, {}, t.at)
		end

		const v = params[t.name]

		if v == nil then
			failAt(t.at, string.format("%s is not a type variable of this declaration", t.name))
		end

		return v
	elseif t.k == "tapp" then
		local args: { Ty } = {}

		for i, a in t.args do
			args[i] = convType(cx, a, params)
		end

		return sumType(cx, t.name, args, t.at)
	elseif t.k == "tpair" then
		return pairOf(convType(cx, t.a, params), convType(cx, t.b, params))
	elseif t.k == "tlist" then
		return listOf(convType(cx, t.item, params))
	end

	return arrow(convType(cx, t.a, params), convType(cx, t.b, params))
end

-- Declares every sum of the program. Names are entered first, so a sum can refer to itself and to the others.
-- A record's payload is its fields as pairs, nested with the last field unwrapped, as the desugarer builds them.
local function payloadOf(tys: { Ty }): Ty
	local n = #tys
	local t = tys[n]

	for i = n - 1, 1, -1 do
		t = pairOf(tys[i], t)
	end

	return t
end

-- The type of field index (from 1) of a record of count fields, whose payload is payload: the tail is taken index - 1 times, then the head, unless it is the last field.
local function fieldAt(payload: Ty, index: number, count: number): Ty
	local t: any = payload

	for _ = 1, index - 1 do
		t = t.args[2]
	end

	if index < count then
		return t.args[1]
	end

	return t
end

local function declare(cx: Cx, decls: { Parser.TypeDecl }, fileKey: string)
	local paramMaps: { { [string]: Ty } } = {}

	for i, decl in decls do
		if decl.name == "Int" or cx.sumNames[decl.name] ~= nil then
			failAt(decl.at, string.format("%s is already declared", decl.name))
		end

		const key = decl.name .. "@" .. fileKey
		local params: { Ty } = {}
		local map: { [string]: Ty } = {}

		for _, p in decl.params do
			const v = fresh(-1)
			table.insert(params, v)
			map[p] = v
		end

		cx.sums[key] = { key = key; name = decl.name; params = params; ctors = {} }
		cx.sumNames[decl.name] = key
		paramMaps[i] = map
	end

	for i, decl in decls do
		const sum = cx.sums[cx.sumNames[decl.name]]

		for k, c in decl.cons do
			if cx.ctors[c.name] ~= nil then
				failAt(c.at, string.format("%s is already declared", c.name))
			end

			local payload: Ty? = nil
			local fields: { string }? = nil

			if c.fields ~= nil then
				local tys: { Ty } = {}
				fields = {}

				for _, f in c.fields :: { Parser.FieldDecl } do
					if cx.ctors[f.name] ~= nil or cx.fields[f.name] ~= nil then
						failAt(f.at, string.format("%s is already declared", f.name))
					end

					table.insert(tys, convType(cx, f.type, paramMaps[i]))
					table.insert(fields :: { string }, f.name)
				end

				payload = payloadOf(tys)
			elseif c.payload ~= nil then
				payload = convType(cx, c.payload :: Parser.Type, paramMaps[i])
			end

			const ctor: SumCtor = { name = c.name; tag = k - 1; payload = payload; fields = fields }
			table.insert(sum.ctors, ctor)
			cx.ctors[c.name] = { sum = sum; ctor = ctor }

			if fields ~= nil then
				for j, fname in fields do
					cx.fields[fname] = { info = cx.ctors[c.name]; index = j; count = #fields }
				end
			end
		end
	end
end

-- A fresh instance of a constructor: its payload type, if it has one, and its sum type.
local function ctorInstance(info: CtorInfo, level: number): (Ty?, Ty, { Ty })
	local map: { Ty } = {}
	local args: { Ty } = {}

	for _, p in info.sum.params do
		if p.k == "var" then
			const v = fresh(level)
			map[p.id] = v
			table.insert(args, v)
		end
	end

	local payload: Ty? = nil

	if info.ctor.payload ~= nil then
		payload = substitute(info.ctor.payload, map)
	end

	return payload, con(info.sum.key, args), args
end

-- The payload of a constructor, at the given arguments of its sum.
local function ctorWithArgs(info: CtorInfo, args: { Ty }): Ty?
	const payload = info.ctor.payload

	if payload == nil then
		return nil
	end

	local map: { Ty } = {}

	for i, p in info.sum.params do
		if p.k == "var" then
			map[p.id] = args[i]
		end
	end

	return substitute(payload, map)
end

-- The type of an operation that can fail: a Result of its value, with a message as the error.
local function resultOf(t: Ty): Ty
	return con("Result", { t; listOf(INT) })
end

-- BUILT-IN NAMES
-- The types of the primitives and the built-in forms (section 13.3). Their variables are never bound, so every use instantiates them.
local BUILTINS: { [string]: Scheme } = {}

do
	for _, sym in { "+"; "-"; "*"; "<"; "=" } do
		BUILTINS[sym] = { vars = {}; ty = arrow(INT, arrow(INT, INT)) }
	end

	-- Division and remainder give an Err for a zero divisor.
	for _, sym in { "/"; "%" } do
		BUILTINS[sym] = { vars = {}; ty = arrow(INT, arrow(INT, resultOf(INT))) }
	end

	const kindA = fresh(-1)
	BUILTINS["@"] = { vars = { kindA }; ty = arrow(kindA, INT) }
	const headA = fresh(-1)
	BUILTINS.head = { vars = { headA }; ty = arrow(listOf(headA), resultOf(headA)) }
	const tailA = fresh(-1)
	BUILTINS.tail = { vars = { tailA }; ty = arrow(listOf(tailA), resultOf(listOf(tailA))) }
	-- A pair is never nil, so its parts are taken apart without a Result. A pair and a list are different types.
	const fstA = fresh(-1)
	const fstB = fresh(-1)
	BUILTINS.fst = { vars = { fstA; fstB }; ty = arrow(pairOf(fstA, fstB), fstA) }
	const sndA = fresh(-1)
	const sndB = fresh(-1)
	BUILTINS.snd = { vars = { sndA; sndB }; ty = arrow(pairOf(sndA, sndB), sndB) }
	-- cons puts an item on the front of a list.
	const consA = fresh(-1)
	BUILTINS.cons = { vars = { consA }; ty = arrow(consA, arrow(listOf(consA), listOf(consA))) }
	const pinA = fresh(-1)
	BUILTINS.pin = { vars = { pinA }; ty = arrow(pinA, pinOf(pinA)) }
	const forceA = fresh(-1)
	BUILTINS.force = { vars = { forceA }; ty = arrow(pinOf(forceA), forceA) }
	const fixA = fresh(-1)
	BUILTINS.fix = { vars = { fixA }; ty = arrow(arrow(fixA, fixA), fixA) }
end

local function lookup(cx: Cx, env: { [string]: Scheme }, name: string, at: Pos, level: number): Ty
	const bound = env[name]

	if bound ~= nil then
		return instantiate(bound, level)
	end

	const builtin = BUILTINS[name]

	if builtin ~= nil then
		return instantiate(builtin, level)
	end

	const info = cx.ctors[name]

	if info ~= nil then
		if info.ctor.fields ~= nil then
			return failAt(at, string.format("%s is a record: write its fields in braces", name))
		end

		const payload, sumTy = ctorInstance(info, level)

		if payload ~= nil then
			return arrow(payload, sumTy)
		end

		return sumTy
	end

	const accessor = cx.fields[name]

	if accessor ~= nil then
		const payload, sumTy = ctorInstance(accessor.info, level)

		return arrow(sumTy, fieldAt(payload :: Ty, accessor.index, accessor.count))
	end

	return failAt(at, string.format("%s is not bound", name))
end

-- INFERENCE
-- Unifies the type of node with the type expected at its position, and gives node back.
local function use(cx: Cx, node: Parser.Expr, actual: Ty, expected: Ty, at: Pos): Parser.Expr
	unifyAt(at, actual, expected)

	return node
end

local inferNode: (Cx, { [string]: Scheme }, Parser.Expr, number, Ty) -> (Parser.Expr, Ty)
local inferRecord: (Cx, { [string]: Scheme }, { name: string; fields: { Parser.FieldInit }; at: Pos }, number, Ty) -> (Parser.Expr, Ty)
local inferWith: (Cx, { [string]: Scheme }, { base: Parser.Expr; fields: { Parser.FieldInit }; at: Pos }, number, Ty) -> (Parser.Expr, Ty)

-- Records a type error, and rethrows anything else, since that is a bug in the checker.
local function recordError(cx: Cx, err: unknown)
	if type(err) == "table" and (err :: { typeError: string? }).typeError ~= nil then
		table.insert(cx.errors, (err :: { typeError: string }).typeError)

		return
	end

	error(err, 0)
end

-- Runs a step of the check that may fail with a type error. The error is recorded, and the check goes on.
local function attempt(cx: Cx, run: () -> ())
	const ok, err = pcall(run)

	if not ok then
		recordError(cx, err)
	end
end

-- Infers a node. A type error in it is recorded, and the node gets a fresh type, so the other errors are found too.
local function infer(cx: Cx, env: { [string]: Scheme }, node: Parser.Expr, level: number, ret: Ty): (Parser.Expr, Ty)
	const ok, result, ty = pcall(inferNode, cx, env, node, level, ret)

	if ok then
		return result :: Parser.Expr, ty :: Ty
	end

	recordError(cx, result)

	return node, fresh(level)
end

inferNode = function(cx: Cx, env: { [string]: Scheme }, node: Parser.Expr, level: number, ret: Ty): (Parser.Expr, Ty)
	if node.k == "int" then
		return node, INT
	elseif node.k == "str" then
		return node, listOf(INT)
	elseif node.k == "nil" then
		return node, listOf(fresh(level))
	elseif node.k == "name" then
		return node, lookup(cx, env, node.name, node.at, level)
	elseif node.k == "list" then
		const item = fresh(level)
		local items: { Parser.Expr } = {}

		for i, x in node.items do
			const out, ty = infer(cx, env, x, level, ret)
			items[i] = use(cx, out, ty, item, x.at)
		end

		return { k = "list"; items = items; at = node.at }, listOf(item)
	elseif node.k == "pair" then
		const a, ta = infer(cx, env, node.a, level, ret)
		const b, tb = infer(cx, env, node.b, level, ret)

		return { k = "pair"; a = a; b = b; at = node.at }, pairOf(ta, tb)
	elseif node.k == "app" then
		local f, fty = infer(cx, env, node.f, level, ret)
		local args: { Parser.Expr } = {}
		local cur = fty

		for i, arg in node.args do
			const out, aty = infer(cx, env, arg, level, ret)
			const pt = fresh(level)
			const rt = fresh(level)

			if i == 1 then
				f = use(cx, f, cur, arrow(pt, rt), node.at)
			else
				unifyAt(node.at, cur, arrow(pt, rt))
			end

			args[i] = use(cx, out, aty, pt, arg.at)
			cur = rt
		end

		return { k = "app"; f = f; args = args; at = node.at }, cur
	elseif node.k == "fn" then
		local inner = table.clone(env)
		local params: { Ty } = {}

		for i, name in node.names do
			const v = fresh(level)
			params[i] = v
			inner[name] = { vars = {}; ty = v }
		end

		const r = fresh(level)
		const body, bt = infer(cx, inner, node.body, level, r)
		local ty = r

		for i = #params, 1, -1 do
			ty = arrow(params[i], ty)
		end

		return { k = "fn"; names = node.names; body = use(cx, body, bt, r, node.body.at); at = node.at }, ty
	elseif node.k == "let" then
		if node.rec then
			const f = fresh(level + 1)
			local recEnv = table.clone(env)
			recEnv[node.name] = { vars = {}; ty = f }
			const value, vt = infer(cx, recEnv, node.value, level + 1, ret)
			unifyAt(node.value.at, vt, f)
			local env2 = table.clone(env)
			env2[node.name] = generalize(f, level)
			const body, bt = infer(cx, env2, node.body, level, ret)

			return { k = "let"; name = node.name; value = value; body = body; rec = true; at = node.at }, bt
		end

		const value, vt = infer(cx, env, node.value, level + 1, ret)
		local env2 = table.clone(env)
		env2[node.name] = generalize(vt, level)
		const body, bt = infer(cx, env2, node.body, level, ret)

		return { k = "let"; name = node.name; value = value; body = body; rec = false; at = node.at }, bt
	elseif node.k == "mutual" then
		local inner = table.clone(env)
		local vars: { Ty } = {}

		for i, b in node.bindings do
			const v = fresh(level + 1)
			vars[i] = v
			inner[b.name] = { vars = {}; ty = v }
		end

		local bindings: { Parser.Binding } = {}

		for i, b in node.bindings do
			const value, vt = infer(cx, inner, b.value, level + 1, ret)
			unifyAt(b.at, vt, vars[i])
			bindings[i] = { name = b.name; value = value; at = b.at }
		end

		local env2 = table.clone(env)

		for i, b in node.bindings do
			env2[b.name] = generalize(vars[i], level)
		end

		const body, bt = infer(cx, env2, node.body, level, ret)

		return { k = "mutual"; bindings = bindings; body = body; at = node.at }, bt
	elseif node.k == "if" then
		const c, ct = infer(cx, env, node.c, level, ret)
		const t, tt = infer(cx, env, node.t, level, ret)
		const e, et = infer(cx, env, node.e, level, ret)

		return {
			k = "if",
			c = use(cx, c, ct, INT, node.c.at),
			t = t,
			e = use(cx, e, et, tt, node.e.at),
			at = node.at,
		}, tt
	elseif node.k == "match" then
		const s, st = infer(cx, env, node.scrut, level, ret)
		local scrut = s
		local sumTy: Ty? = nil
		local sumArgs: { Ty } = {}
		local sum: Sum? = nil
		const resTy = fresh(level)
		local covered: { boolean } = {}
		local catchAll = false
		local arms: { Parser.Arm } = {}

		for _, arm in node.arms do
			if catchAll then
				failAt(arm.at, "an arm after a catch-all arm is unreachable")
			end

			const pat = arm.pat
			local inner = table.clone(env)

			if pat.k == "con" or pat.k == "rec" then
				const info = cx.ctors[pat.name]

				if info == nil then
					failAt(pat.at, string.format("%s is not a constructor", pat.name))
				end

				if pat.k == "rec" and info.ctor.fields == nil then
					failAt(pat.at, string.format("%s is not a record", pat.name))
				end

				if pat.k == "con" and info.ctor.fields ~= nil then
					failAt(pat.at, string.format("%s is a record: match its fields in braces", pat.name))
				end

				if sumTy == nil then
					-- The first constructor fixes the sum, and the scrutinee is used at it.
					const _, first, firstArgs = ctorInstance(info, level)
					sumTy = first
					sumArgs = firstArgs
					sum = info.sum
					scrut = use(cx, s, st, first, node.scrut.at)
				end

				if info.sum.key ~= (sum :: Sum).key then
					failAt(pat.at, string.format("%s belongs to %s, but the match is on %s", pat.name, info.sum.name, (sum :: Sum).name))
				end

				const payload = ctorWithArgs(info, sumArgs)
				covered[info.ctor.tag] = true

				if pat.k == "rec" then
					const names = info.ctor.fields :: { string }
					local seen: { [string]: boolean } = {}

					for _, f in pat.fields do
						local index: number? = nil

						for j, n in names do
							if n == f.name then
								index = j
							end
						end

						if index == nil then
							failAt(f.at, string.format("%s has no field %s", pat.name, f.name))
						end

						if seen[f.name] then
							failAt(f.at, string.format("%s is given twice", f.name))
						end

						seen[f.name] = true

						if f.bind ~= nil then
							inner[f.bind :: string] = { vars = {}; ty = fieldAt(payload :: Ty, index :: number, #names) }
						end
					end

					for _, n in names do
						if not seen[n] then
							failAt(pat.at, string.format("%s needs the field %s", pat.name, n))
						end
					end
				elseif pat.bind ~= nil then
					if payload == nil then
						failAt(pat.at, string.format("%s has no payload to bind", pat.name))
					end

					inner[pat.bind :: string] = { vars = {}; ty = payload :: Ty }
				end
			elseif pat.k == "bind" then
				catchAll = true
				inner[pat.name] = { vars = {}; ty = st }
			else
				catchAll = true
			end

			const body, bt = infer(cx, inner, arm.body, level, ret)
			table.insert(arms, { pat = pat; body = use(cx, body, bt, resTy, arm.body.at); at = arm.at })
		end

		if not catchAll then
			local missing: { string } = {}

			for _, c in (sum :: Sum).ctors do
				if not covered[c.tag] then
					table.insert(missing, c.name)
				end
			end

			if #missing > 0 then
				failAt(node.at, "match does not cover " .. table.concat(missing, ", "))
			end
		end

		return { k = "match"; scrut = scrut; arms = arms; at = node.at }, resTy
	elseif node.k == "record" then
		return inferRecord(cx, env, node, level, ret)
	elseif node.k == "with" then
		return inferWith(cx, env, node, level, ret)
	elseif node.k == "untyped" then
		const e = infer(cx, env, node.e, level, ret)

		return { k = "untyped"; e = e; at = node.at }, DYN
	elseif node.k == "check" then
		const e = infer(cx, env, node.e, level, ret)
		-- The test depends on the type the use gives the value, which is only known once inference is done, so the type is not generalised.
		const t = fresh(-1)
		const c: CheckNode = { k = "check"; e = e; test = nil; expect = ""; at = node.at }
		table.insert(cx.pending, { node = c; ty = t })

		return c, con("Result", { t; listOf(INT) })
	elseif node.k == "try" then
		const e, et = infer(cx, env, node.e, level, ret)
		const okTy = fresh(level)
		const errTy = fresh(level)
		const out = use(cx, e, et, con("Result", { okTy; errTy }), node.e.at)
		-- The early return leaves the function with an Err, so the function's result is a Result with the same error type.
		unifyAt(node.at, con("Result", { fresh(level); errTy }), ret)

		return { k = "try"; e = out; at = node.at }, okTy
	end

	-- Only the parser's forms reach the checker. The desugarer's rawfix form and check nodes are never in its input.
	error({ typeError = string.format("line %d, column %d: this form cannot be checked", node.at.line, node.at.col) }, 0)
end

-- DESCRIBING TYPES AS TESTS
-- The test a check of type t runs. A list or sum that refers to itself is described once, and the references to it are rec.
-- The field values of a record literal, against the field types, in the order the declaration gives them.
inferRecord = function(cx: Cx, env: { [string]: Scheme }, node: { name: string; fields: { Parser.FieldInit }; at: Pos }, level: number, ret: Ty): (Parser.Expr, Ty)
	const info = cx.ctors[node.name]

	if info == nil or info.ctor.fields == nil then
		failAt(node.at, string.format("%s is not a record", node.name))
	end

	const names = info.ctor.fields :: { string }
	const payload, sumTy = ctorInstance(info, level)

	for k, init in node.fields do
		local known = false

		for _, n in names do
			if n == init.name then
				known = true
			end
		end

		if not known then
			failAt(init.at, string.format("%s has no field %s", node.name, init.name))
		end

		for j = 1, k - 1 do
			if node.fields[j].name == init.name then
				failAt(init.at, string.format("%s is given twice", init.name))
			end
		end
	end

	local values: { [string]: Parser.Expr } = {}

	for j, n in names do
		local init: Parser.FieldInit? = nil

		for _, f in node.fields do
			if f.name == n then
				init = f
			end
		end

		if init == nil then
			failAt(node.at, string.format("%s needs the field %s", node.name, n))
		end

		const out, ity = infer(cx, env, (init :: Parser.FieldInit).value, level, ret)
		values[n] = use(cx, out, ity, fieldAt(payload :: Ty, j, #names), (init :: Parser.FieldInit).value.at)
	end

	local fields: { Parser.FieldInit } = {}

	for _, init in node.fields do
		table.insert(fields, { name = init.name; value = values[init.name]; at = init.at })
	end

	return { k = "record"; name = node.name; fields = fields; at = node.at }, sumTy
end

-- A record with some of its fields changed: the base has the record's type, and each field named has that field's type.
inferWith = function(cx: Cx, env: { [string]: Scheme }, node: { base: Parser.Expr; fields: { Parser.FieldInit }; at: Pos }, level: number, ret: Ty): (Parser.Expr, Ty)
	const first = node.fields[1]
	const acc = cx.fields[first.name]

	if acc == nil then
		failAt(first.at, string.format("%s is not a field of a record", first.name))
	end

	const info = (acc :: FieldInfo).info
	const names = info.ctor.fields :: { string }
	const payload, sumTy = ctorInstance(info, level)
	const base, bt = infer(cx, env, node.base, level, ret)
	const baseOut = use(cx, base, bt, sumTy, node.base.at)

	for k, init in node.fields do
		local known = false

		for _, n in names do
			if n == init.name then
				known = true
			end
		end

		if not known then
			failAt(init.at, string.format("%s is not a field of %s", init.name, info.ctor.name))
		end

		for j = 1, k - 1 do
			if node.fields[j].name == init.name then
				failAt(init.at, string.format("%s is given twice", init.name))
			end
		end
	end

	local fields: { Parser.FieldInit } = {}

	for _, init in node.fields do
		local index = 1

		for j, n in names do
			if n == init.name then
				index = j
			end
		end

		const out, ity = infer(cx, env, init.value, level, ret)
		const checked = use(cx, out, ity, fieldAt(payload :: Ty, index, #names), init.value.at)
		table.insert(fields, { name = init.name; value = checked; at = init.at })
	end

	return { k = "with"; base = baseOut; fields = fields; at = node.at }, sumTy
end

local function describe(cx: Cx, t: Ty): Parser.Test
	local stack: { [string]: boolean } = {}
	local used: { [string]: boolean } = {}

	local function go(x: Ty): Parser.Test
		const y = prune(x)

		if y.k == "var" then
			return { kind = "any" }
		end

		const n = y.name

		if n == "Dyn" then
			return { kind = "any" }
		elseif n == "Int" then
			return { kind = "int" }
		elseif n == "->" then
			return { kind = "fn" }
		elseif n == "Pin" then
			return { kind = "pin" }
		elseif n == "pair" then
			return { kind = "pair"; a = go(y.args[1]); b = go(y.args[2]) }
		end

		const key = render(y, true)

		if stack[key] then
			used[key] = true

			return { kind = "rec"; key = key }
		end

		stack[key] = true
		local body: Parser.Test

		if n == "list" then
			body = { kind = "list"; item = go(y.args[1]); tail = go(y) }
		else
			const sum = cx.sums[n]
			local map: { Ty } = {}

			for i, p in sum.params do
				if p.k == "var" then
					map[p.id] = y.args[i]
				end
			end

			local ctors: { Parser.SumTest } = {}

			for _, c in sum.ctors do
				local payload: Parser.Test = { kind = "nil" }

				if c.payload ~= nil then
					payload = go(substitute(c.payload, map))
				end

				table.insert(ctors, { tag = c.tag; payload = payload })
			end

			body = { kind = "sum"; ctors = ctors }
		end

		stack[key] = nil

		if used[key] then
			return { kind = "fixdef"; key = key; body = body }
		end

		return body
	end

	return go(t)
end

-- ENTRY
local function untyped(): Scheme
	return { vars = {}; ty = DYN }
end

local function showScheme(s: Scheme): string
	return render(s.ty, false)
end

local function check(program: Parser.Program, imports: { { name: string; scheme: Scheme } }, fileKey: string): Result
	const cx = newCx()
	declare(cx, program.decls, fileKey)
	local env: { [string]: Scheme } = {}

	for _, imp in imports do
		env[imp.name] = imp.scheme
	end

	const expr, ty = infer(cx, env, program.expr, 0, fresh(0))
	const input = fresh(0)
	const out = fresh(0)
	attempt(
		cx,
		function()
			const p = prune(ty)

			if p.k == "con" and p.name ~= "->" then
				failAt(program.expr.at, "the program must be a function of its input, but it is " .. render(ty, false))
			end

			unifyAt(program.expr.at, ty, arrow(input, out))
		end
	)

	if #cx.errors > 0 then
		error(table.concat(cx.errors, "\n"), 0)
	end

	for _, pending in cx.pending do
		pending.node.test = describe(cx, pending.ty)
		pending.node.expect = render(pending.ty, false)
	end

	return {
		expr = expr,
		input = describe(cx, input),
		inputExpect = render(input, false),
		scheme = generalize(ty, -1),
	}
end

return {
	check = check,
	untyped = untyped,
	showScheme = showScheme,
}
